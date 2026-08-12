import AppKit
import AVFoundation
import Combine
import Foundation
import Network

enum PlaybackState: Equatable {
    case idle
    case connecting
    case playing
    case paused
    case failed(String)

    var isBusy: Bool { self == .connecting }
    var isActive: Bool { self == .playing || self == .connecting }
}

/// Обёртка над AVPlayer для живого потока: подключение, авто-переподключение,
/// громкость и отслеживание состояния.
@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published var volume: Double = 0.8 {
        didSet { applyVolume() }
    }
    @Published var isMuted: Bool = false {
        didSet { applyVolume() }
    }

    /// Множитель поверх пользовательской громкости — им и делаются плавные переходы.
    /// Отдельно от `volume`, чтобы затухание не сбивало положение ползунка.
    private var fadeGain: Double = 0
    private var fadeTask: Task<Void, Never>?

    private enum Fade {
        static let out = Duration.milliseconds(180)
        static let `in` = Duration.milliseconds(280)
        static let step = Duration.milliseconds(10)
    }

    private let player = AVPlayer()
    private var currentURL: URL?
    private var playerObservation: NSKeyValueObservation?
    private var itemObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []   // живут ровно столько, сколько текущий AVPlayerItem
    private var lifetimeTokens: [NSObjectProtocol] = []       // живут всё время работы плеера
    private var stallWatchdog: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let pathMonitor = NWPathMonitor()
    private var networkWasSatisfied = true

    /// Вызывается, когда поток пришлось перезапустить (для UI-подсказки).
    var onReconnect: (() -> Void)?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none
        applyVolume()

        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.handleTimeControlChange(status) }
        }

        startNetworkMonitoring()
        observeSystemWake()
    }

    /// После пробуждения Mac сокет обычно мёртв, хотя сеть формально «есть».
    /// Поэтому эфир пересобираем принудительно.
    private func observeSystemWake() {
        lifetimeTokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let url = self.currentURL, self.state.isActive else { return }
                    self.reconnectAttempt = 0
                    self.startItem(url: url)
                }
            }
        )
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - Управление

    func play(url: URL) {
        currentURL = url
        reconnectAttempt = 0
        fadeTask?.cancel()

        // Если что-то уже звучит, сначала гасим. Резкая подмена источника рвёт
        // волну на полуслове — отсюда щелчок и треск при переключении станций.
        guard player.timeControlStatus == .playing else {
            startItem(url: url)
            return
        }
        state = .connecting          // интерфейс откликается сразу, не дожидаясь затухания
        fadeTask = Task { [weak self] in
            await self?.ramp(to: 0, over: Fade.out)
            guard let self, !Task.isCancelled, self.currentURL == url else { return }
            self.startItem(url: url)
        }
    }

    func pause() {
        stallWatchdog?.cancel()
        state = .paused              // тоже сразу, звук догаснет следом
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            await self?.ramp(to: 0, over: Fade.out)
            guard let self, !Task.isCancelled, self.state == .paused else { return }
            self.player.pause()
            // Освобождаем сокет — живой поток незачем держать на паузе.
            self.player.replaceCurrentItem(with: nil)
        }
    }

    func stop() {
        stallWatchdog?.cancel()
        fadeTask?.cancel()
        state = .idle
        currentURL = nil
        fadeTask = Task { [weak self] in
            await self?.ramp(to: 0, over: Fade.out)
            guard let self, !Task.isCancelled, self.state == .idle else { return }
            self.player.pause()
            self.player.replaceCurrentItem(with: nil)
        }
    }

    // MARK: - Плавные переходы

    private func applyVolume() {
        player.volume = Float(isMuted ? 0 : volume * fadeGain)
    }

    /// Ведёт множитель к цели за указанное время небольшими шагами.
    /// AVPlayer не умеет рампу для живого потока сам, поэтому шагаем вручную.
    private func ramp(to target: Double, over duration: Duration) async {
        let steps = max(1, Int(duration / Fade.step))
        let start = fadeGain
        guard abs(target - start) > 0.001 else {
            fadeGain = target
            applyVolume()
            return
        }
        for step in 1...steps {
            if Task.isCancelled { return }
            let t = Double(step) / Double(steps)
            // Сглаживание по краям: без него слышны уступы в начале и конце.
            let eased = t * t * (3 - 2 * t)
            fadeGain = start + (target - start) * eased
            applyVolume()
            try? await Task.sleep(for: Fade.step)
        }
        guard !Task.isCancelled else { return }
        fadeGain = target
        applyVolume()
    }

    /// Вызывается, когда звук реально пошёл — до этого момента плавно поднимать нечего.
    private func fadeIn() {
        guard fadeGain < 0.999 else { return }
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            await self?.ramp(to: 1, over: Fade.in)
        }
    }

    // MARK: - Внутреннее

    private func startItem(url: URL) {
        clearItemObservers()

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "RecordPlayer/1.0 (macOS)",
                "Icy-MetaData": "1"
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4

        observeItem(item)
        player.replaceCurrentItem(with: item)
        // Новый поток всегда начинается с тишины и поднимается сам, когда пойдёт звук.
        // Без этого первые кадры буфера врубались на полной громкости.
        fadeGain = 0
        applyVolume()
        player.play()

        state = .connecting
        armStallWatchdog()
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemObservations.append(
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                let message = item.error?.localizedDescription ?? "Не удалось открыть поток"
                Task { @MainActor in
                    guard let self, failed else { return }
                    self.handleFailure(message)
                }
            }
        )

        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item, queue: .main
            ) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                Task { @MainActor in
                    self?.handleFailure(error?.localizedDescription ?? "Поток прервался")
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item, queue: .main
            ) { [weak self] _ in
                // Живой эфир «закончиться» не должен — значит, соединение оборвалось.
                Task { @MainActor in self?.scheduleReconnect(reason: "Соединение закрылось") }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVPlayerItem.playbackStalledNotification,
                object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.armStallWatchdog() }
            }
        )
    }

    private func clearItemObservers() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
    }

    private func handleTimeControlChange(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            reconnectAttempt = 0
            stallWatchdog?.cancel()
            state = .playing
            fadeIn()
        case .waitingToPlayAtSpecifiedRate:
            if state != .paused { state = .connecting }
            armStallWatchdog()
        case .paused:
            if case .failed = state { return }
            if state != .idle && state != .paused { state = .paused }
        @unknown default:
            break
        }
    }

    /// Если поток «висит» дольше 15 секунд — переподключаемся.
    private func armStallWatchdog() {
        stallWatchdog?.cancel()
        stallWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            guard self.player.timeControlStatus != .playing, self.state.isActive else { return }
            self.scheduleReconnect(reason: "Поток не отвечает")
        }
    }

    private func handleFailure(_ message: String) {
        guard state != .paused, state != .idle else { return }
        scheduleReconnect(reason: message)
    }

    private func scheduleReconnect(reason: String) {
        guard let currentURL, state != .paused, state != .idle else { return }
        stallWatchdog?.cancel()

        reconnectAttempt += 1
        guard reconnectAttempt <= 8 else {
            state = .failed(reason)
            return
        }

        state = .connecting
        onReconnect?()

        let delay = min(pow(1.6, Double(reconnectAttempt - 1)), 20.0)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.state.isActive else { return }
            self.startItem(url: currentURL)
        }
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                defer { self.networkWasSatisfied = satisfied }
                // Сеть вернулась после обрыва — сразу пробуем восстановить эфир.
                if satisfied, !self.networkWasSatisfied, let url = self.currentURL, self.state.isActive {
                    self.reconnectAttempt = 0
                    self.startItem(url: url)
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "ru.local.recordplayer.network"))
    }
}

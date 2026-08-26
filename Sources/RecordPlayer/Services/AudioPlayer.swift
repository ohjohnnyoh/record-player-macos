import AppKit
import AVFoundation
import Combine
import Foundation
import Network

/// Что именно играет. Живой эфир и файл ведут себя по-разному в шести местах,
/// и различие лучше держать явным типом, чем булевым флагом в глубине класса.
enum PlaybackSource: Equatable {
    /// Бесконечный поток станции: конец элемента означает обрыв связи.
    case live(URL)
    /// Выпуск подкаста: конечный файл с длительностью и перемоткой.
    case file(URL, startAt: TimeInterval)

    var url: URL {
        switch self {
        case .live(let url): url
        case .file(let url, _): url
        }
    }

    var isFile: Bool {
        if case .file = self { return true }
        return false
    }
}

/// Позиция и длительность вынесены в отдельный объект намеренно.
///
/// `VolumeSlider` подписан на `AudioPlayer` целиком, поэтому publisher позиции
/// с частотой два раза в секунду перерисовывал бы регулятор громкости в трёх
/// поверхностях. Вложенный объект наверх ничего не пробрасывает.
@MainActor
final class PlaybackTimeline: ObservableObject {
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    /// Пока пользователь тянет ползунок, обновления от плеера игнорируются —
    /// иначе бегунок дёргается под пальцем.
    var isScrubbing = false

    func update(position: TimeInterval) {
        guard !isScrubbing else { return }
        self.position = max(0, position)
    }

    func update(duration: TimeInterval) {
        self.duration = duration.isFinite && duration > 0 ? duration : 0
    }

    func reset() {
        position = 0
        duration = 0
        isScrubbing = false
    }
}

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

    /// Позиция и длительность текущего файла. Для эфира всегда нули.
    let timeline = PlaybackTimeline()

    private var source: PlaybackSource?
    private var currentURL: URL? { source?.url }
    private var isFileMode: Bool { source?.isFile ?? false }
    private var timeObserver: Any?

    /// Вызывается, когда выпуск доигран до конца. Передаёт адрес именно того
    /// файла, который закончился: пока уведомление ждало главный поток,
    /// пользователь мог включить другой выпуск.
    var onFinished: ((URL) -> Void)?
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
                    guard let self, let source = self.source, self.state.isActive else { return }
                    self.reconnectAttempt = 0
                    self.startItem(self.resumable(source))
                }
            }
        )
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - Управление

    /// Прежний вход для радио — поведение эфира не меняется.
    func play(url: URL) {
        play(.live(url))
    }

    func play(_ newSource: PlaybackSource) {
        source = newSource
        reconnectAttempt = 0
        fadeTask?.cancel()
        timeline.reset()

        // Если что-то уже звучит, сначала гасим. Резкая подмена источника рвёт
        // волну на полуслове — отсюда щелчок и треск при переключении станций.
        guard player.timeControlStatus == .playing else {
            startItem(newSource)
            return
        }
        state = .connecting          // интерфейс откликается сразу, не дожидаясь затухания
        fadeTask = Task { [weak self] in
            await self?.ramp(to: 0, over: Fade.out)
            guard let self, !Task.isCancelled, self.source == newSource else { return }
            self.startItem(newSource)
        }
    }

    /// Продолжить с текущего места. Осмысленно только для файла: у эфира
    /// элемент на паузе уничтожается, и продолжать нечего.
    func resume() {
        guard let source, source.isFile else { return }
        // Доигранный до конца элемент возобновить нельзя: AVPlayer не поднимет
        // rate, timeControlStatus не сменится, и состояние застрянет в .playing.
        // Такой выпуск начинаем заново.
        let atEnd = timeline.duration > 0 && timeline.position >= timeline.duration - 0.5
        if player.currentItem == nil || atEnd {
            play(.file(source.url, startAt: atEnd ? 0 : timeline.position))
            return
        }
        state = .playing
        player.play()
        fadeIn()
    }

    func seek(to seconds: TimeInterval) {
        guard isFileMode else { return }
        let target = max(0, min(seconds, timeline.duration > 0 ? timeline.duration : seconds))
        timeline.update(position: target)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
    }

    func skip(by delta: TimeInterval) {
        guard isFileMode else { return }
        seek(to: timeline.position + delta)
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
            // Для файла элемент оставляем: иначе теряется позиция, и при
            // возобновлении пришлось бы качать выпуск заново с самого начала.
            if !self.isFileMode {
                self.player.replaceCurrentItem(with: nil)
            }
        }
    }

    func stop() {
        stallWatchdog?.cancel()
        fadeTask?.cancel()
        state = .idle
        source = nil
        timeline.reset()
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

    private func startItem(_ source: PlaybackSource) {
        clearItemObservers()

        // Icy-MetaData просит поток присылать метаданные трека. Файлу выпуска
        // такой заголовок не нужен, а лишние заголовки на CDN лучше не слать.
        var headers = ["User-Agent": "RecordPlayer/1.0 (macOS)"]
        if !source.isFile { headers["Icy-MetaData"] = "1" }

        let asset = AVURLAsset(url: source.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ])
        let item = AVPlayerItem(asset: asset)
        // Радиопотоки приходят как mono/stereo audio-only. Для таких материалов
        // AVFoundation по умолчанию разрешает пространственную обработку только
        // многоканального сигнала, поэтому переключатель AirPods фактически
        // перестраивал маршрут для формата, который item не объявлял допустимым.
        // Явно разрешаем штатную spatialization для реального формата эфира;
        // конкретный режим по-прежнему выбирает пользователь в Пункте управления.
        item.allowedAudioSpatializationFormats = .monoAndStereo
        // Четыре секунды подобраны под эфир: маленький буфер быстрее стартует
        // и меньше отстаёт. Файлу выгоднее буфер по умолчанию.
        if !source.isFile { item.preferredForwardBufferDuration = 4 }

        // Наблюдатели ставим до подмены элемента: иначе .status успел бы стать
        // readyToPlay между вызовами, и длительность с перемоткой на старте
        // потерялись бы до следующего изменения статуса.
        observeItem(item, source: source)
        if case .file(_, let startAt) = source {
            observePlaybackTime(of: item, startAt: startAt)
        }
        player.replaceCurrentItem(with: item)
        // Новый поток всегда начинается с тишины и поднимается сам, когда пойдёт звук.
        // Без этого первые кадры буфера врубались на полной громкости.
        fadeGain = 0
        applyVolume()
        player.play()

        state = .connecting
        armStallWatchdog()
    }

    /// Следит за позицией и длительностью выпуска.
    ///
    /// Наблюдатель ставится только для файла и снимается вместе с элементом —
    /// у эфира ни позиции, ни длительности нет, и тикать там нечему.
    private func observePlaybackTime(of item: AVPlayerItem, startAt: TimeInterval) {
        removeTimeObserver()

        itemObservations.append(
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                let seconds = item.duration.seconds
                Task { @MainActor in
                    guard let self else { return }
                    self.timeline.update(duration: seconds)
                    if startAt > 1 { self.seek(to: startAt) }
                }
            }
        )

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isFileMode else { return }
                self.timeline.update(position: time.seconds)
            }
        }
    }

    /// Источник для перезапуска: файл продолжается с текущей позиции.
    private func resumable(_ source: PlaybackSource) -> PlaybackSource {
        source.isFile ? .file(source.url, startAt: timeline.position) : source
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func observeItem(_ item: AVPlayerItem, source: PlaybackSource) {
        itemObservations.append(
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                let message = item.error?.localizedDescription ?? L10n.string("Не удалось открыть поток")
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
                    self?.handleFailure(error?.localizedDescription ?? L10n.string("Поток прервался"))
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    // Ветвимся по источнику именно этого элемента: пока задача
                    // ждала главный поток, пользователь мог переключиться,
                    // и обрыв эфира зачёлся бы как доигранный выпуск.
                    if source.isFile {
                        // Выпуск доиграл до конца — это норма, а не обрыв.
                        self.timeline.update(position: self.timeline.duration)
                        self.state = .paused
                        self.onFinished?(source.url)
                    } else {
                        // Живой эфир «закончиться» не должен — значит, соединение оборвалось.
                        self.scheduleReconnect(reason: L10n.string("Соединение закрылось"))
                    }
                }
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
        removeTimeObserver()
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
        // У файла сторож только мешает: буферизация и перемотка законно
        // останавливают воспроизведение и выглядели бы как зависший поток.
        // Проверка здесь, а не на трёх точках вызова — их легко забыть.
        guard !isFileMode else { return }
        stallWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            guard self.player.timeControlStatus != .playing, self.state.isActive else { return }
            self.scheduleReconnect(reason: L10n.string("Поток не отвечает"))
        }
    }

    private func handleFailure(_ message: String) {
        guard state != .paused, state != .idle else { return }
        scheduleReconnect(reason: message)
    }

    private func scheduleReconnect(reason: String) {
        guard let source, state != .paused, state != .idle else { return }
        // Файл возобновляем с того места, где оборвалось, а не с начала:
        // выпуск может идти сорок минут, и терять их нельзя.
        let target = source.isFile
            ? PlaybackSource.file(source.url, startAt: timeline.position)
            : source
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
            self.startItem(target)
        }
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                defer { self.networkWasSatisfied = satisfied }
                // Сеть вернулась после обрыва — сразу пробуем восстановить эфир.
                if satisfied, !self.networkWasSatisfied, let source = self.source, self.state.isActive {
                    self.reconnectAttempt = 0
                    self.startItem(self.resumable(source))
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "ru.local.recordplayer.network"))
    }
}

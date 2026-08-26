import AVFoundation
import Combine
import Foundation

/// Проигрыватель тридцатисекундных фрагментов из чартов.
///
/// Намеренно отдельный от `AudioPlayer`, а не режим внутри него. Основной плеер
/// построен вокруг допущения «поток бесконечен»: конец файла он трактует как
/// обрыв связи и запускает переподключение, а пауза уничтожает элемент, чтобы
/// освободить сокет. Для короткого фрагмента оба поведения вредны, а вносить
/// в них развилки ради превью — значит рисковать радио, ради которого
/// приложение и существует.
///
/// Здесь ничего этого нет: один короткий файл, естественный конец, стоп.
@MainActor
final class PreviewPlayer: ObservableObject {
    /// Идентификатор трека, который сейчас звучит. nil — тишина.
    @Published private(set) var playingID: Int?

    private let player = AVPlayer()
    private var tokens: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?

    init() {
        player.actionAtItemEnd = .none
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    func toggle(id: Int, url: URL, volume: Double) {
        if playingID == id {
            stop()
        } else {
            play(id: id, url: url, volume: volume)
        }
    }

    func play(id: Int, url: URL, volume: Double) {
        clearObserver()

        let item = AVPlayerItem(url: url)
        tokens.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            // Фрагмент закончился сам — это норма, а не обрыв.
            MainActor.assumeIsolated { self?.stop() }
        })
        // Ссылки на фрагменты живут в чужом CDN и иногда отдают ошибку.
        // Без этих двух наблюдателей строка так и осталась бы подсвеченной
        // с кнопкой «стоп», хотя звука нет.
        tokens.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.stop() }
        }

        player.replaceCurrentItem(with: item)
        player.volume = Float(volume)
        player.play()
        playingID = id
    }

    func stop() {
        clearObserver()
        player.pause()
        player.replaceCurrentItem(with: nil)
        playingID = nil
    }

    private func clearObserver() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        statusObservation?.invalidate()
        statusObservation = nil
    }
}

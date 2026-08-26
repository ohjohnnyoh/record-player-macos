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
    private var endObserver: NSObjectProtocol?

    init() {
        player.actionAtItemEnd = .none
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
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
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            // Фрагмент закончился сам — это норма, а не обрыв.
            MainActor.assumeIsolated { self?.stop() }
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
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

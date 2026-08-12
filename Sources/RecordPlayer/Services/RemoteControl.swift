import AppKit
import Foundation
import MediaPlayer

/// Интеграция с системным «Сейчас исполняется»: медиа-клавиши на клавиатуре,
/// Пункт управления и панель воспроизведения в macOS.
@MainActor
final class RemoteControl {
    static let shared = RemoteControl()

    private let center = MPRemoteCommandCenter.shared()
    private let info = MPNowPlayingInfoCenter.default()
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkURL: URL?

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onToggle: (() -> Void)?
    var onNextStation: (() -> Void)?
    var onPreviousStation: (() -> Void)?

    private init() {}

    func activate() {
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        // Для живого эфира перемотка не имеет смысла.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false

        center.playCommand.addTarget { [weak self] _ in
            self?.onPlay?(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?(); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onToggle?(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextStation?(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousStation?(); return .success
        }
    }

    func update(station: Station?, track: Track?, isPlaying: Bool) {
        guard let station else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }

        var payload: [String: Any] = [
            MPMediaItemPropertyTitle: (track?.displaySong).nilIfEmpty ?? station.title,
            MPMediaItemPropertyArtist: (track?.displayArtist).nilIfEmpty ?? "Radio Record",
            MPMediaItemPropertyAlbumTitle: station.title,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: 0.0
        ]

        // Обложку подставляем асинхронно, чтобы не блокировать обновление текста.
        if let existing = info.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
           lastArtworkURL == (track?.artworkURL ?? station.iconURL) {
            payload[MPMediaItemPropertyArtwork] = existing
        }

        info.nowPlayingInfo = payload
        info.playbackState = isPlaying ? .playing : .paused

        loadArtwork(url: track?.artworkURL ?? station.iconURL)
    }

    private func loadArtwork(url: URL?) {
        guard let url, url != lastArtworkURL else { return }
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let image = await ImageStore.shared.image(for: url) else { return }
            guard !Task.isCancelled, let self else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var payload = self.info.nowPlayingInfo ?? [:]
            payload[MPMediaItemPropertyArtwork] = artwork
            self.info.nowPlayingInfo = payload
            self.lastArtworkURL = url
        }
    }
}

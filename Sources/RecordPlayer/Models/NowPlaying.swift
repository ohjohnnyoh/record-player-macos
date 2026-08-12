import Foundation

// MARK: - Трек

struct Track: Codable, Hashable, Identifiable {
    let id: Int?
    let artist: String?
    let song: String?
    let image100: String?
    let image200: String?
    let image600: String?
    let itunesUrl: String?
    let shareUrl: String?

    var displayArtist: String { (artist?.trimmed).nilIfEmpty ?? "" }
    var displaySong: String { (song?.trimmed).nilIfEmpty ?? "" }

    var displayTitle: String {
        switch (displayArtist.isEmpty, displaySong.isEmpty) {
        case (true, true): L10n.string("Прямой эфир")
        case (false, true): displayArtist
        case (true, false): displaySong
        case (false, false): "\(displayArtist) — \(displaySong)"
        }
    }

    var artworkURL: URL? {
        (image600 ?? image200 ?? image100).flatMap(URL.init(string:))
    }

    var smallArtworkURL: URL? {
        (image200 ?? image100 ?? image600).flatMap(URL.init(string:))
    }

    /// Ключ для сравнения «сменился ли трек» — id не всегда стабилен.
    var identityKey: String { "\(displayArtist)|\(displaySong)" }
}

// MARK: - Ответ API «сейчас играет»

struct NowPlayingResponse: Codable {
    struct Entry: Codable {
        let id: Int          // id станции
        let track: Track?
    }
    let result: [Entry]
}

// MARK: - Запись в истории прослушивания

struct HistoryEntry: Codable, Hashable, Identifiable {
    var id: String { "\(stationID)-\(trackKey)-\(date.timeIntervalSince1970)" }
    let stationID: Int
    let stationTitle: String
    let artist: String
    let song: String
    let artwork: String?
    let itunesUrl: String?
    let date: Date

    var trackKey: String { "\(artist)|\(song)" }
    var displayTitle: String {
        artist.isEmpty ? song : (song.isEmpty ? artist : "\(artist) — \(song)")
    }
    var artworkURL: URL? { artwork.flatMap(URL.init(string:)) }
}

// MARK: - Мелкие хелперы

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

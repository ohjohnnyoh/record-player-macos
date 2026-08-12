import Foundation

/// Запись из плейлиста станции — что играло в эфире и когда.
struct PlaylistTrack: Codable, Identifiable, Hashable {
    let id: Int
    let artist: String?
    let song: String?
    let image100: String?
    let image200: String?
    let itunesUrl: String?
    let shareUrl: String?
    let time: Int?
    let timeFormatted: String?

    /// В плейлисте один и тот же трек встречается много раз, поэтому
    /// идентификатор строки — трек плюс момент выхода в эфир.
    var rowID: String { "\(id)-\(time ?? 0)" }

    var displayArtist: String { (artist?.trimmed).nilIfEmpty ?? "" }
    var displaySong: String { (song?.trimmed).nilIfEmpty ?? "" }

    var displayTitle: String {
        switch (displayArtist.isEmpty, displaySong.isEmpty) {
        case (true, true): "Без названия"
        case (false, true): displayArtist
        case (true, false): displaySong
        case (false, false): "\(displayArtist) — \(displaySong)"
        }
    }

    var artworkURL: URL? { (image200 ?? image100).flatMap(URL.init(string:)) }

    var date: Date? { time.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    /// Время выхода в эфир. Берём метку из ответа, а не готовую строку:
    /// та отформатирована в часовом поясе станции, а не в вашем.
    var timeText: String {
        guard let date else { return timeFormatted ?? "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct StationHistoryResponse: Codable {
    struct Result: Codable {
        let history: [PlaylistTrack]
    }
    let result: Result
}

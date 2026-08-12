import Foundation

// MARK: - Genre

struct Genre: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
}

// MARK: - Station

/// Одна радиостанция из /api/stations/.
/// Декодируется с `.convertFromSnakeCase`, поэтому `stream_320` -> `stream320`.
struct Station: Codable, Identifiable, Hashable {
    let id: Int
    let prefix: String
    let title: String
    let tooltip: String?
    let sort: Int?
    let shortTitle: String?

    let iconFillWhite: String?
    let iconFillColored: String?
    let iconGray: String?
    let bgImage: String?

    let streamHls: String?
    let stream320: String?
    let stream128: String?
    let stream64: String?

    let genre: [Genre]?
    let new: Bool?

    var genreNames: [String] { (genre ?? []).map(\.name) }

    /// Иконка для карточки: белая заливка на прозрачном фоне.
    var iconURL: URL? { iconFillWhite.flatMap(URL.init(string:)) ?? iconGray.flatMap(URL.init(string:)) }

    func streamURL(for quality: StreamQuality) -> URL? {
        let raw: String? = switch quality {
        case .auto: streamHls
        case .high: stream320
        case .medium: stream128
        case .low: stream64
        }
        // Если нужного потока нет — деградируем по цепочке.
        let fallback = raw ?? streamHls ?? stream320 ?? stream128 ?? stream64
        return fallback.flatMap(URL.init(string:))
    }

    /// Текст для поиска: название + подпись + жанры.
    var searchHaystack: String {
        ([title, shortTitle ?? "", tooltip ?? ""] + genreNames)
            .joined(separator: " ")
            .lowercased()
    }
}

// MARK: - Качество потока

enum StreamQuality: String, CaseIterable, Codable, Identifiable {
    case auto      // HLS, адаптивный — самый устойчивый
    case high      // ~96 kbps AAC+
    case medium    // ~64 kbps AAC+
    case low       // ~32 kbps AAC+

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Авто (HLS)"
        case .high: "Высокое"
        case .medium: "Среднее"
        case .low: "Экономное"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: "адаптивный поток, до 112 kbps"
        case .high: "96 kbps AAC+"
        case .medium: "64 kbps AAC+"
        case .low: "32 kbps AAC+"
        }
    }
}

// MARK: - Ответ API со списком станций

struct StationsResponse: Codable {
    struct Result: Codable {
        let genre: [Genre]?
        let stations: [Station]
    }
    let result: Result
}

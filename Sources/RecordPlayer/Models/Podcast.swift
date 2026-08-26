import Foundation

/// Целое, которое API отдаёт то числом, то строкой.
///
/// У `/api/podcasts/` идентификатор в разные дни приходил и `15726`, и `"15726"`.
/// Жёсткий тип уронил бы разбор всего каталога из-за одного поля, поэтому здесь
/// принимаются оба варианта.
struct FlexibleInt: Codable, Hashable {
    let value: Int?

    init(_ value: Int?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Int(text.trimmed)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Подкаст

/// Объявлены только используемые поля. Остальное (`rss`, `rss_prefix`,
/// `apple_categories`, `talk_show`, `cover_itunes`) намеренно опущено: то, чего
/// нет в модели, декодер игнорирует, и смена типа на стороне API его не сломает.
struct Podcast: Codable, Hashable, Identifiable {
    let id: FlexibleInt
    let name: String?
    let description: String?
    let sort: FlexibleInt?
    let isNew: FlexibleInt?
    let coverVertical: String?
    let coverHorizontal: String?
    let coverHorizontalThumb: String?
    let coverBg: String?
    let shareUrl: String?

    /// Идентификатор для запроса выпусков.
    var feedID: Int? { id.value }

    var title: String { (name?.trimmed).nilIfEmpty ?? L10n.string("Без названия") }
    var summary: String { (description?.trimmed) ?? "" }

    /// Метка «новое» на карточке — как на сайте.
    var isFresh: Bool { (isNew?.value ?? 0) != 0 }

    var sortOrder: Int { sort?.value ?? .max }

    /// Вертикальная обложка для сетки, широкая — для шапки подкаста.
    var coverURL: URL? {
        (coverVertical ?? coverHorizontal ?? coverBg).flatMap(URL.init(string:))
    }

    var wideCoverURL: URL? {
        (coverHorizontal ?? coverBg ?? coverVertical).flatMap(URL.init(string:))
    }

    var shareURL: URL? { shareUrl.flatMap(URL.init(string:)) }
}

struct PodcastsResponse: Codable {
    let result: [Podcast]
}

// MARK: - Выпуск

struct PodcastEpisode: Codable, Hashable, Identifiable {
    let id: Int
    let artist: String?
    let song: String?
    let duration: Int?
    let createdAt: Int?
    let image100: String?
    let image600: String?
    let playlist: String?
    let link: String?
    let shareUrl: String?

    /// Название выпуска: у Radio Record это «#3734 (26-08-2026)».
    var title: String { (song?.trimmed).nilIfEmpty ?? L10n.string("Без названия") }

    /// Имя подкаста с ведущими — приходит в поле исполнителя.
    var subtitle: String { (artist?.trimmed).nilIfEmpty ?? "" }

    var date: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// Прямая ссылка на MP3. Это файл с длительностью, а не поток.
    var audioURL: URL? { link.flatMap(URL.init(string:)) }

    var artworkURL: URL? { (image600 ?? image100).flatMap(URL.init(string:)) }
    var smallArtworkURL: URL? { (image100 ?? image600).flatMap(URL.init(string:)) }

    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        return L10n.duration(seconds: Double(duration))
    }

    /// Состав выпуска — многострочный текст с нумерованными темами.
    var playlistLines: [String] {
        (playlist ?? "")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }

    var shareURL: URL? { shareUrl.flatMap(URL.init(string:)) }
}

import Foundation

/// Какой из трёх чартов показываем.
enum ChartKind: String, CaseIterable, Identifiable, Codable {
    case superchart
    case club
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .superchart: L10n.string("Суперчарт")
        case .club: L10n.string("Клаб чарт")
        case .newest: L10n.string("Новинки")
        }
    }

    var subtitle: String {
        switch self {
        case .superchart: L10n.string("Недельный хит-парад")
        case .club: L10n.string("Клубные треки недели")
        case .newest: L10n.string("Свежие треки радио")
        }
    }
}

/// Одна позиция чарта.
///
/// Объявлены только два поля из четырёх, и это защита, а не лень. Место берётся
/// из порядка в массиве: в `sort` приходит внутренний счётчик, а не позиция.
/// `status` везде — заглушка «(не установлено)». А `like` в клаб чарте приходит
/// то строкой, то числом в одном и том же ответе: объявленное поле с жёстким
/// типом уронило бы декодирование всего массива из-за одной позиции, тогда как
/// неупомянутое поле просто игнорируется.
struct ChartEntry: Codable, Hashable, Identifiable {
    let name: String?
    let track: Track?

    /// В одном чарте трек может повторяться, а `track.id` бывает пустым,
    /// поэтому идентичность строки задаём вместе с позицией — см. `positioned(_:)`.
    var id: String { "\(track?.id ?? 0)-\(name ?? "")" }

    var displayTitle: String {
        if let track, !track.displayTitle.isEmpty { return track.displayTitle }
        return (name?.trimmed).nilIfEmpty ?? L10n.string("Без названия")
    }

    /// Тридцатисекундный фрагмент из Apple Music. Полного трека API не отдаёт.
    var previewURL: URL? { track?.listenURL }

    var appleMusicURL: URL? { track?.itunesUrl.flatMap(URL.init(string:)) }

    /// Страница трека на сайте. Нужна как запасной вариант: ссылка на Apple
    /// Music приходит не у всех позиций.
    var siteURL: URL? { track?.shareUrl.flatMap(URL.init(string:)) }
}

/// Позиция вместе с её местом в чарте — место задаётся порядком в ответе.
struct RankedChartEntry: Identifiable, Hashable {
    let rank: Int
    let entry: ChartEntry

    var id: String { "\(rank)-\(entry.id)" }
}

extension Array where Element == ChartEntry {
    var ranked: [RankedChartEntry] {
        enumerated().map { RankedChartEntry(rank: $0.offset + 1, entry: $0.element) }
    }
}

// MARK: - Ответ API

struct ChartResponse: Codable {
    let result: [ChartEntry]
}

/// Ответ фида `/api/podcast/?id=`: одна и та же форма и для выпусков подкаста,
/// и для треков новинок, поэтому обёртка обобщённая.
struct PodcastFeedResponse<Item: Decodable>: Decodable {
    struct Result: Decodable {
        let tracks: [Item]
    }
    let result: Result
}

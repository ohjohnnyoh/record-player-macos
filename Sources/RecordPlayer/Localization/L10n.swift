import Foundation

/// Доступ к строкам, которые резолвятся вне SwiftUI-механизма `LocalizedStringKey`:
/// значения моделей, ошибки и тексты для VoiceOver.
enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func trackCount(_ count: Int) -> String {
        plural("%lld треков", count)
    }

    static func stationCount(_ count: Int) -> String {
        plural("%lld станций", count)
    }

    static func playCount(_ count: Int) -> String {
        plural("%lld включений", count)
    }

    static func recentTrackCount(_ count: Int) -> String {
        plural("%lld треков за последние сутки", count)
    }

    static func episodeCount(_ count: Int) -> String {
        plural("%lld выпусков", count)
    }

    static func podcastCount(_ count: Int) -> String {
        plural("%lld подкастов", count)
    }

    static func listeningSummary(stations: Int, duration: String) -> String {
        format("%@ · всего %@", stationCount(stations), duration)
    }

    /// Длительность словами: «41 мин», «1 ч 5 мин».
    ///
    /// Живёт здесь, а не в модели статистики станций: тем же форматом
    /// пользуются выпуски подкастов, и им незачем зависеть от чужой сущности.
    static func duration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        switch (hours, minutes) {
        case (0, 0): return string("меньше минуты")
        case (0, _): return format("%@ мин", String(minutes))
        case (_, 0): return format("%@ ч", String(hours))
        default: return format("%@ ч %@ мин", String(hours), String(minutes))
        }
    }

    /// Формы множественного числа берутся из String Catalog, а не считаются в коде.
    ///
    /// Каталог хранит вариации по категориям CLDR (one/few/many/other), компилируется
    /// в `Localizable.stringsdict`, а `localizedStringWithFormat` выбирает нужную по
    /// правилам конкретного языка. Раньше правила для русского были прописаны в Swift
    /// вручную — работало, но третий язык потребовал бы правки кода вместо каталога.
    private static func plural(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(string(key), count)
    }
}

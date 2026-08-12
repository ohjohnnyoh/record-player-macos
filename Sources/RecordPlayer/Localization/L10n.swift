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

    static func listeningSummary(stations: Int, duration: String) -> String {
        format("%@ · всего %@", stationCount(stations), duration)
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

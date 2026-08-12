import Foundation

/// Centralized access to strings that are resolved outside SwiftUI's
/// `LocalizedStringKey` APIs (model values, errors and accessibility text).
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
        plural(
            count,
            one: "%@ трек",
            few: "%@ трека",
            many: "%@ треков"
        )
    }

    static func stationCount(_ count: Int) -> String {
        plural(
            count,
            one: "%@ станция",
            few: "%@ станции",
            many: "%@ станций"
        )
    }

    static func playCount(_ count: Int) -> String {
        plural(
            count,
            one: "%@ включение",
            few: "%@ включения",
            many: "%@ включений"
        )
    }

    static func recentTrackCount(_ count: Int) -> String {
        plural(
            count,
            one: "%@ трек за последние сутки",
            few: "%@ трека за последние сутки",
            many: "%@ треков за последние сутки"
        )
    }

    static func listeningSummary(stations: Int, duration: String) -> String {
        let stationText = stationCount(stations)
        return format("%@ · всего %@", stationText, duration)
    }

    private static func plural(
        _ count: Int,
        one: String,
        few: String,
        many: String
    ) -> String {
        let key: String
        if isRussian {
            let remainder100 = abs(count) % 100
            let remainder10 = remainder100 % 10
            if remainder10 == 1, remainder100 != 11 {
                key = one
            } else if (2...4).contains(remainder10), !(12...14).contains(remainder100) {
                key = few
            } else {
                key = many
            }
        } else {
            key = count == 1 ? one : many
        }
        return format(key, String(count))
    }

    private static var isRussian: Bool {
        let language = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "ru"
        return language.lowercased().hasPrefix("ru")
    }
}

import Foundation

/// Накопленная статистика по станции: сколько слушали, когда включали в последний раз.
struct StationStat: Codable, Identifiable, Hashable {
    let stationID: Int
    var title: String
    var totalSeconds: Double
    var lastPlayed: Date
    var plays: Int

    var id: Int { stationID }

    var durationText: String { Self.duration(totalSeconds) }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        switch (hours, minutes) {
        case (0, 0): return L10n.string("меньше минуты")
        case (0, _): return L10n.format("%@ мин", String(minutes))
        case (_, 0): return L10n.format("%@ ч", String(hours))
        default: return L10n.format("%@ ч %@ мин", String(hours), String(minutes))
        }
    }

    /// «8 включений» — с правильным окончанием.
    var playsText: String {
        L10n.playCount(plays)
    }
}

/// Хранилище статистики на диске — рядом с кэшем станций.
enum StatsStore {
    private static let fileName = "station-stats.json"

    static func load() -> [Int: StationStat] {
        guard let data = DiskCache.read(fileName),
              let list = try? JSONDecoder().decode([StationStat].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.stationID, $0) })
    }

    static func save(_ stats: [Int: StationStat]) {
        guard let data = try? JSONEncoder().encode(Array(stats.values)) else { return }
        DiskCache.write(data, to: fileName)
    }
}

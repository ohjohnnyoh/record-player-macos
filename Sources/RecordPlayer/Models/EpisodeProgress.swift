import Foundation

/// Где остановились в выпуске.
struct EpisodeProgress: Codable, Hashable {
    let episodeID: Int
    var position: TimeInterval
    var duration: TimeInterval
    var updated: Date

    /// Выпуск считается прослушанным у самого конца — последние секунды обычно
    /// не дослушивают, и предлагать «продолжить» за десять секунд до финала глупо.
    var isFinished: Bool {
        guard duration > 0 else { return false }
        return position >= duration * 0.97
    }

    /// Продолжать имеет смысл, только если успели уйти от начала и не дошли
    /// до конца. Иначе кнопка «Продолжить с 00:04» выглядит издевательством.
    var isResumable: Bool {
        guard duration > 0, !isFinished else { return false }
        return position > 30
    }

    var positionText: String {
        let total = Int(position.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Хранилище прогресса рядом с остальным кэшем.
///
/// Отдельный файл, а не `UserDefaults`: записей со временем набирается много,
/// а настройки — не место для растущего журнала.
enum ProgressStore {
    private static let fileName = "episode-progress.json"

    /// Держим только последние записи: без ограничения файл рос бы вечно.
    private static let limit = 500

    static func load() -> [Int: EpisodeProgress] {
        guard let data = DiskCache.read(fileName),
              let list = try? JSONDecoder().decode([EpisodeProgress].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.episodeID, $0) })
    }

    static func save(_ progress: [Int: EpisodeProgress]) {
        let trimmed = progress.values
            .sorted { $0.updated > $1.updated }
            .prefix(limit)
        guard let data = try? JSONEncoder().encode(Array(trimmed)) else { return }
        DiskCache.write(data, to: fileName)
    }
}

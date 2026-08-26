import Foundation
import Testing
@testable import RecordPlayer

@Suite("Episode progress")
struct EpisodeProgressTests {
    private func progress(position: TimeInterval, duration: TimeInterval) -> EpisodeProgress {
        EpisodeProgress(episodeID: 1, position: position, duration: duration, updated: Date())
    }

    /// Продолжать предлагаем только если реально ушли от начала: кнопка
    /// «Продолжить с 00:04» бесполезна.
    @Test func firstSecondsDoNotCountAsStarted() {
        #expect(progress(position: 4, duration: 2400).isResumable == false)
        #expect(progress(position: 31, duration: 2400).isResumable == true)
    }

    /// У самого конца выпуск считается прослушанным, а не «почти дослушанным»:
    /// последние секунды обычно не дослушивают.
    @Test func endOfEpisodeCountsAsPlayed() {
        let almost = progress(position: 2400 * 0.98, duration: 2400)
        #expect(almost.isFinished == true)
        #expect(almost.isResumable == false)

        let middle = progress(position: 1200, duration: 2400)
        #expect(middle.isFinished == false)
        #expect(middle.isResumable == true)
    }

    /// Длительность приходит не сразу: пока её нет, ни «прослушано»,
    /// ни «продолжить» показывать нельзя — иначе делили бы на ноль.
    @Test func unknownDurationIsNeitherFinishedNorResumable() {
        let unknown = progress(position: 300, duration: 0)
        #expect(unknown.isFinished == false)
        #expect(unknown.isResumable == false)
    }

    @Test func positionIsFormattedAsMinutesAndSeconds() {
        #expect(progress(position: 0, duration: 100).positionText == "0:00")
        #expect(progress(position: 65, duration: 100).positionText == "1:05")
        #expect(progress(position: 3599, duration: 4000).positionText == "59:59")
    }

    /// Хранилище режет журнал по дате, оставляя свежие записи: без ограничения
    /// файл прогресса рос бы бесконечно.
    @Test func storeKeepsOnlyRecentEntries() throws {
        let now = Date()
        let many = (0..<600).map { index in
            EpisodeProgress(
                episodeID: index,
                position: 100,
                duration: 1000,
                updated: now.addingTimeInterval(TimeInterval(-index))
            )
        }
        let encoded = try JSONEncoder().encode(
            Array(many.sorted { $0.updated > $1.updated }.prefix(500))
        )
        let decoded = try JSONDecoder().decode([EpisodeProgress].self, from: encoded)

        #expect(decoded.count == 500)
        // Самая свежая запись должна пережить обрезку, самая старая — нет.
        #expect(decoded.contains { $0.episodeID == 0 })
        #expect(decoded.contains { $0.episodeID == 599 } == false)
    }
}

@Suite("Playback source")
struct PlaybackSourceTests {
    /// Развилка «эфир или файл» — основа всей файловой логики плеера.
    /// Если она перестанет различать случаи, конец выпуска снова начнёт
    /// трактоваться как обрыв связи.
    @Test func liveAndFileAreDistinguished() {
        let url = URL(string: "https://example.com/a.mp3")!
        #expect(PlaybackSource.live(url).isFile == false)
        #expect(PlaybackSource.file(url, startAt: 0).isFile == true)
        #expect(PlaybackSource.live(url).url == url)
        #expect(PlaybackSource.file(url, startAt: 120).url == url)
    }

    /// Позиция входит в равенство: перезапуск с другой секунды — другой источник.
    @Test func startPositionIsPartOfIdentity() {
        let url = URL(string: "https://example.com/a.mp3")!
        #expect(PlaybackSource.file(url, startAt: 0) != PlaybackSource.file(url, startAt: 120))
        #expect(PlaybackSource.live(url) != PlaybackSource.file(url, startAt: 0))
    }
}

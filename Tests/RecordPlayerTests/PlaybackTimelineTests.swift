import Testing
@testable import RecordPlayer

/// Регрессии на позицию выпуска. Полоса перемотки и сохранение прогресса
/// читают один и тот же объект, поэтому его поведение стоит зафиксировать.
@Suite("Playback timeline")
@MainActor
struct PlaybackTimelineTests {

    @Test func scrubbingBlocksIncomingPositions() {
        let timeline = PlaybackTimeline()
        timeline.update(position: 42)
        timeline.isScrubbing = true
        timeline.update(position: 100)
        #expect(timeline.position == 42)

        timeline.isScrubbing = false
        timeline.update(position: 100)
        #expect(timeline.position == 100)
    }

    /// `PlaybackScrubber` снимает флаг в `onDisappear`, но если вью пропала
    /// иначе — сброс таймлайна обязан вернуть его в рабочее состояние.
    @Test func resetClearsScrubbingFlag() {
        let timeline = PlaybackTimeline()
        timeline.isScrubbing = true
        timeline.reset()
        #expect(timeline.isScrubbing == false)

        timeline.update(position: 7)
        #expect(timeline.position == 7)
    }

    /// У живого эфира длительность приходит как NaN или бесконечность —
    /// в таком виде она уехала бы в системную панель «Сейчас исполняется».
    @Test func nonFiniteDurationIsTreatedAsUnknown() {
        let timeline = PlaybackTimeline()
        timeline.update(duration: .nan)
        #expect(timeline.duration == 0)

        timeline.update(duration: .infinity)
        #expect(timeline.duration == 0)

        timeline.update(duration: -5)
        #expect(timeline.duration == 0)

        timeline.update(duration: 1800)
        #expect(timeline.duration == 1800)
    }

    @Test func negativePositionIsClamped() {
        let timeline = PlaybackTimeline()
        timeline.update(position: -3)
        #expect(timeline.position == 0)
    }
}

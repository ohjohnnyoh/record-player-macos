import SwiftUI

/// Полоса перемотки выпуска.
///
/// Подписана на `PlaybackTimeline`, а не на плеер целиком: позиция обновляется
/// дважды в секунду, и перерисовывать из-за неё регулятор громкости или пилюлю
/// плеера незачем.
struct PlaybackScrubber: View {
    @ObservedObject var timeline: PlaybackTimeline
    let accent: Color
    var compact: Bool = false
    let onSeek: (TimeInterval) -> Void

    /// Пока тянут ползунок, показываем его собственное значение: позиция от
    /// плеера продолжает приходить, и без этого бегунок дёргался бы под пальцем.
    @State private var draft: Double = 0
    @State private var isDragging = false

    private var duration: TimeInterval { timeline.duration }
    private var isReady: Bool { duration > 0 }
    private var shown: TimeInterval { isDragging ? draft : timeline.position }

    var body: some View {
        VStack(spacing: compact ? 1 : 3) {
            Slider(
                value: Binding(
                    get: { min(max(shown, 0), max(duration, 1)) },
                    set: { newValue in
                        draft = newValue
                        if !isDragging {
                            isDragging = true
                            timeline.isScrubbing = true
                        }
                    }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        // Значение ползунка приходит уже после начала жеста, а на
                        // одиночном нажатии без перетаскивания — не приходит вовсе.
                        // Без засева отпускание отправило бы выпуск в самое начало.
                        draft = min(max(timeline.position, 0), max(duration, 1))
                        isDragging = true
                        timeline.isScrubbing = true
                    } else {
                        isDragging = false
                        timeline.isScrubbing = false
                        onSeek(draft)
                    }
                }
            )
            .controlSize(compact ? .mini : .small)
            .tint(accent)
            .disabled(!isReady)

            HStack {
                Text(Self.time(shown))
                Spacer()
                Text(isReady ? "−" + Self.time(max(0, duration - shown)) : "--:--")
            }
            .font(.system(size: compact ? 9 : 10))
            .monospacedDigit()
            .foregroundStyle(Theme.tertiaryText)
        }
        .onDisappear {
            // Вью может исчезнуть прямо посреди жеста — например, если закрыть
            // страницу подкаста. Забытый флаг заморозил бы позицию во всём
            // приложении: `PlaybackTimeline` общий.
            guard isDragging else { return }
            isDragging = false
            timeline.isScrubbing = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("Позиция в выпуске"))
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard isReady else { return }
            let delta: TimeInterval = direction == .increment ? 15 : -15
            onSeek(min(max(timeline.position + delta, 0), duration))
        }
    }

    /// Для VoiceOver время читается словами, а не как «12:34».
    private var accessibilityValue: String {
        guard isReady else { return L10n.string("Длительность неизвестна") }
        return L10n.format(
            "%@ из %@",
            L10n.duration(seconds: shown),
            L10n.duration(seconds: duration)
        )
    }

    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

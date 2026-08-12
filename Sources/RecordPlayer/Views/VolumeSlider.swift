import SwiftUI

/// Регулятор громкости, подписанный прямо на плеер.
///
/// Вынесен в отдельную вьюху сознательно: если бы громкость шла через `AppState`,
/// каждое движение ползунка перерисовывало бы всю сетку станций. Здесь
/// перерисовывается только он сам.
struct VolumeSlider: View {
    @Environment(\.appAccent) private var accent
    @ObservedObject var player: AudioPlayer
    var sliderWidth: CGFloat? = nil
    var compact: Bool = false

    private var binding: Binding<Double> {
        Binding(
            get: { player.volume },
            set: { newValue in
                player.volume = newValue
                // Потянули ползунок при выключенном звуке — логично его вернуть.
                if newValue > 0, player.isMuted { player.isMuted = false }
            }
        )
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Button {
                player.isMuted.toggle()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: compact ? 8.5 : 12))
                    .foregroundStyle(iconTint)
                    .frame(width: compact ? 11 : 16)
            }
            .buttonStyle(.plain)
            .help(L10n.string(player.isMuted ? "Включить звук (⌘M)" : "Выключить звук (⌘M)"))

            Slider(value: binding, in: 0...1)
                .frame(width: sliderWidth)
                .controlSize(compact ? .mini : .small)
                .tint(accent)
        }
    }

    private var iconTint: Color {
        if compact { return .white.opacity(0.8) }
        return player.isMuted ? accent : Theme.secondaryText
    }

    private var icon: String {
        if player.isMuted || player.volume < 0.01 { return "speaker.slash.fill" }
        if compact { return "speaker.fill" }
        if player.volume < 0.34 { return "speaker.wave.1.fill" }
        if player.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

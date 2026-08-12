import AppKit
import SwiftUI

/// Что и сколько слушали: время по станциям, число включений, когда были в последний раз.
struct StationStatsView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState

    private var rows: [StationStat] {
        let query = state.searchText.trimmed.lowercased()
        let all = state.statsByTime
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(query) }
    }

    /// Самое большое время — по нему масштабируются полоски.
    private var peak: Double {
        max(rows.first?.totalSeconds ?? 1, 1)
    }

    private var totalListened: Double {
        state.statsByTime.reduce(0) { $0 + $1.totalSeconds }
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(L10n.string(
                        state.statsByTime.isEmpty ? "Пока нечего показать" : "Ничего не найдено"
                    ))
                        .font(.headline)
                    Text("Включите станцию — здесь появится, сколько вы её слушали.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { stat in
                            StatRow(stat: stat, peak: peak)
                        }
                    }
                    .padding(12)
                    .padding(.bottom, PlayerBar.reservedHeight)
                }
                .safeAreaInset(edge: .top) {
                    HStack {
                        Text(L10n.listeningSummary(
                            stations: rows.count,
                            duration: StationStat.duration(totalListened)
                        ))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiaryText)
                        Spacer()
                        Button("Очистить статистику") { state.clearStats() }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StatRow: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState

    let stat: StationStat
    let peak: Double

    @State private var hovered = false

    private var station: Station? {
        state.stations.first { $0.id == stat.stationID }
    }

    private var isCurrent: Bool { state.currentStation?.id == stat.stationID }
    private var share: Double { min(1, stat.totalSeconds / peak) }

    var body: some View {
        HStack(spacing: 11) {
            CachedImage(url: station?.iconURL, contentMode: .fit, maxPixel: 96) { Color.clear }
                .frame(width: 26, height: 26)
                .opacity(0.85)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(stat.title)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? accent : Color.primary)
                        .lineLimit(1)
                    if isCurrent, state.player.state == .playing {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundStyle(accent)
                    }
                    Spacer(minLength: 6)
                    Text(stat.durationText)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }

                // Полоска показывает долю относительно самой слушаемой станции.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule()
                            .fill(accent.opacity(isCurrent ? 0.95 : 0.55))
                            .frame(width: max(3, geo.size.width * share))
                    }
                }
                .frame(height: 4)

                HStack(spacing: 6) {
                    Text(stat.playsText)
                    Text("·")
                    Text(stat.lastPlayed.formatted(.relative(presentation: .named)))
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if hovered {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
        .focusable()
        .onKeyPress(.return) {
            if let station { state.play(station) }
            return .handled
        }
        .onHover { hovered = $0 }
        .onTapGesture {
            if let station { state.play(station) }
        }
        .accessibilityLabel(stat.title)
        .accessibilityValue("\(stat.durationText), \(stat.playsText)")
        .accessibilityHint("Включить станцию")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let station { state.play(station) }
        }
        .help(L10n.format("Включить %@", stat.title))
    }
}

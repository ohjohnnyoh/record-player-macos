import AppKit
import SwiftUI

/// История треков, которые реально звучали во время прослушивания.
struct HistoryView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState
    @State private var mode: Mode = .tracks

    enum Mode: String, CaseIterable, Identifiable {
        case tracks, stations
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tracks: L10n.string("Треки")
            case .stations: L10n.string("Станции")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if mode == .stations {
                StationStatsView()
            } else {
                tracksList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tracksList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(L10n.string(state.history.isEmpty ? "История пуста" : "Ничего не найдено"))
                        .font(.headline)
                    Text("Здесь копятся треки, которые играли, пока вы слушали.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry)
                        }
                    }
                    .padding(12)
                    .padding(.bottom, PlayerBar.reservedHeight)
                }
                .safeAreaInset(edge: .top) {
                    HStack {
                        Text(L10n.trackCount(filtered.count))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiaryText)
                        Spacer()
                        Button("Очистить историю") { state.clearHistory() }
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

    private var filtered: [HistoryEntry] {
        let query = state.searchText.trimmed.lowercased()
        guard !query.isEmpty else { return state.history }
        return state.history.filter {
            $0.displayTitle.lowercased().contains(query) || $0.stationTitle.lowercased().contains(query)
        }
    }
}

private struct HistoryRow: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let entry: HistoryEntry
    @EnvironmentObject private var state: AppState
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            CachedImage(url: entry.artworkURL, contentMode: .fill) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3))
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(entry.stationTitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(accent)
            }

            Spacer(minLength: 8)

            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)

            if hovered || voiceOverEnabled {
                if let url = entry.itunesUrl.flatMap(URL.init(string:)) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .help("Открыть в Apple Music")
                }
                Button {
                    if let station = state.stations.first(where: { $0.id == entry.stationID }) {
                        state.startPlayback(station)
                    }
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .help(L10n.format("Включить %@", entry.stationTitle))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.displayTitle)
        .accessibilityValue("\(entry.stationTitle), \(entry.date.formatted(date: .omitted, time: .shortened))")
        .contextMenu {
            Button("Скопировать название") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.displayTitle, forType: .string)
            }
        }
    }
}

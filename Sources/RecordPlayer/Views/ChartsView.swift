import AppKit
import SwiftUI

/// Три чарта Radio Record: суперчарт, клаб чарт и новинки.
///
/// Вкладки загружаются независимо друг от друга — у новинок неофициальный
/// источник, и его поломка не должна гасить остальные два чарта.
struct ChartsView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState

    @State private var kind: ChartKind = .superchart

    private var entries: [RankedChartEntry] { (state.charts[kind] ?? []).ranked }
    private var isLoading: Bool { state.loadingCharts.contains(kind) }
    private var error: String? { state.chartErrors[kind] }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $kind) {
                ForEach(ChartKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .padding(.top, 12)
            .padding(.bottom, 10)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: kind) { await state.loadChart(kind) }
    }

    @ViewBuilder
    private var content: some View {
        if let error, entries.isEmpty {
            message(icon: "wifi.exclamationmark", title: L10n.string("Не удалось загрузить чарт"), subtitle: error) {
                Button("Повторить") {
                    Task { await state.loadChart(kind, force: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        } else if entries.isEmpty && isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            message(icon: "music.note.list", title: L10n.string("Чарт пуст"),
                    subtitle: L10n.string("Сервер не вернул ни одной позиции.")) { EmptyView() }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(entries) { ranked in
                    ChartRow(ranked: ranked, accent: accent).equatable()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, PlayerBar.reservedHeight)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text(kind.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Обновить") {
                        Task { await state.loadChart(kind, force: true) }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func message<Action: View>(
        icon: String, title: String, subtitle: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            action().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Строка чарта

/// Не подписана на состояние: получает готовые значения и сравнивается по ним,
/// как `StationCard` в сетке станций.
private struct ChartRow: View, Equatable {
    let ranked: RankedChartEntry
    let accent: Color

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var hovered = false

    static func == (lhs: ChartRow, rhs: ChartRow) -> Bool {
        lhs.ranked.id == rhs.ranked.id && lhs.accent == rhs.accent
    }

    private var entry: ChartEntry { ranked.entry }

    var body: some View {
        HStack(spacing: 11) {
            Text("\(ranked.rank)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ranked.rank <= 3 ? accent : Theme.tertiaryText)
                .frame(width: 26, alignment: .trailing)

            CachedImage(url: entry.track?.smallArtworkURL, contentMode: .fill, maxPixel: 96) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3))
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text((entry.track?.displaySong).nilIfEmpty ?? entry.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if let artist = (entry.track?.displayArtist).nilIfEmpty {
                    Text(artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if hovered || voiceOverEnabled, let url = entry.appleMusicURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .help(L10n.string("Открыть в Apple Music"))
                .accessibilityLabel(L10n.string("Открыть в Apple Music"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if hovered {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.07))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Место %@", String(ranked.rank)))
        .accessibilityValue(entry.displayTitle)
        .contextMenu {
            Button("Скопировать название") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.displayTitle, forType: .string)
            }
            if let url = entry.appleMusicURL {
                Button("Открыть в Apple Music") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

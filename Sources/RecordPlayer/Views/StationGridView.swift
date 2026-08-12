import AppKit
import SwiftUI

struct StationGridView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.appAccent) private var accent

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 190), spacing: 12)]

    var body: some View {
        Group {
            if let error = state.loadError, state.stations.isEmpty {
                emptyState(
                    icon: "wifi.exclamationmark",
                    title: "Не удалось загрузить станции",
                    subtitle: error,
                    action: ("Повторить", { Task { await state.loadStations() } })
                )
            } else if state.stations.isEmpty && state.isLoadingStations {
                ProgressView("Загружаем станции…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.visibleStations.isEmpty {
                emptyState(
                    icon: state.section == .favorites ? "heart" : "magnifyingglass",
                    title: state.section == .favorites ? "Пока нет избранного" : "Ничего не найдено",
                    subtitle: state.section == .favorites
                        ? "Нажмите на сердечко на карточке станции, чтобы добавить её сюда."
                        : "Попробуйте изменить запрос или сбросить фильтр по жанру.",
                    action: state.selectedGenre != nil ? ("Сбросить жанр", { state.selectedGenre = nil }) : nil
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(state.visibleStations) { station in
                            card(for: station)
                        }
                    }
                    .padding(16)
                    // Место под плавающей пилюлей плеера.
                    .padding(.bottom, PlayerBar.reservedHeight)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Карточке передаём готовые значения, а не всё состояние: тогда SwiftUI
    /// сравнит их и пропустит перерисовку, если для этой станции ничего не поменялось.
    private func card(for station: Station) -> some View {
        let isCurrent = state.currentStation?.id == station.id
        return StationCard(
            station: station,
            track: state.nowPlaying[station.id],
            isCurrent: isCurrent,
            isPlaying: isCurrent && state.player.state == .playing,
            isConnecting: isCurrent && state.player.state == .connecting,
            isFavorite: state.favorites.contains(station.id),
            accent: accent,
            onPlay: { state.play(station) },
            onToggleFavorite: { state.toggleFavorite(station) }
        )
        .equatable()
    }

    private func emptyState(
        icon: String,
        title: String,
        subtitle: String,
        action: (String, () -> Void)?
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Карточка станции

/// Намеренно не подписана на `AppState`: получает только свои данные.
/// Благодаря `Equatable` перерисовка пропускается, когда меняется что-то чужое —
/// например, текст в поиске или трек на соседней станции.
struct StationCard: View, Equatable {
    let station: Station
    let track: Track?
    let isCurrent: Bool
    let isPlaying: Bool
    let isConnecting: Bool
    let isFavorite: Bool
    let accent: Color
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovered = false

    static func == (lhs: StationCard, rhs: StationCard) -> Bool {
        lhs.station.id == rhs.station.id
            && lhs.track?.identityKey == rhs.track?.identityKey
            && lhs.isCurrent == rhs.isCurrent
            && lhs.isPlaying == rhs.isPlaying
            && lhs.isConnecting == rhs.isConnecting
            && lhs.isFavorite == rhs.isFavorite
            && lhs.accent == rhs.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CachedImage(url: station.iconURL, contentMode: .fit, maxPixel: 160) {
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .frame(width: 72, height: 72)
                .opacity(isHovered || isCurrent ? 0.25 : 0.85)

                if isHovered || isCurrent {
                    playIndicator
                }
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text(station.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isCurrent ? accent : Color.primary)

                Text(track?.displayTitle ?? station.tooltip ?? "")
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 148)
        .glassCard(hovered: isHovered, selected: isCurrent, accent: accent)
        .overlay(alignment: .topTrailing) { favoriteButton }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .onHover { isHovered = $0 }
        .help(helpText)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button(isPlaying ? "Пауза" : "Слушать", action: onPlay)
            Button(isFavorite ? "Убрать из избранного" : "В избранное", action: onToggleFavorite)
            if let track, let url = track.itunesUrl.flatMap(URL.init(string:)) {
                Divider()
                Button("Открыть трек в Apple Music") { NSWorkspace.shared.open(url) }
            }
            if let track, !track.displayTitle.isEmpty {
                Button("Скопировать название трека") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(track.displayTitle, forType: .string)
                }
            }
        }
    }

    private var playIndicator: some View {
        Group {
            if isConnecting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isCurrent ? accent : .white)
                    .shadow(radius: 6)
            }
        }
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isFavorite ? accent : Color.white.opacity(0.5))
                .padding(6)
        }
        .buttonStyle(.plain)
        .opacity(isFavorite || isHovered ? 1 : 0)
        .help(isFavorite ? "Убрать из избранного" : "В избранное")
    }

    private var helpText: String {
        var parts = [station.title]
        if let tooltip = station.tooltip, !tooltip.isEmpty { parts.append(tooltip) }
        if let track, !track.displayTitle.isEmpty { parts.append("Сейчас: \(track.displayTitle)") }
        return parts.joined(separator: "\n")
    }
}

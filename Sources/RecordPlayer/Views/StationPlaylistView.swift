import AppKit
import SwiftUI

/// Полноразмерный режим станции в духе Apple Music: текущий эфир слева,
/// история станции справа. Открывается внутри главного окна и не меняет toolbar.
struct StationDetailView: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var state: AppState

    let station: Station

    @State private var query = ""

    private var currentTrack: Track? { state.nowPlaying[station.id] }
    private var isCurrent: Bool { state.currentStation?.id == station.id }
    private var isPlaying: Bool { isCurrent && state.player.state == .playing }
    private var currentSongTitle: String {
        guard let song = currentTrack?.displaySong, !song.isEmpty else {
            return L10n.string("Прямой эфир")
        }
        return song
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            GeometryReader { geometry in
                let sidebarIsCollapsed = geometry.size.width >= 980
                let artworkColumnWidth = sidebarIsCollapsed
                    ? min(470, geometry.size.width * 0.43)
                    : min(300, max(235, geometry.size.width * 0.38))

                HStack(alignment: .top, spacing: sidebarIsCollapsed ? 30 : 26) {
                    nowPlayingColumn
                        .frame(width: artworkColumnWidth)

                    Divider()
                        .overlay(Theme.separator.opacity(0.65))

                    historyColumn
                        .frame(minWidth: 300, maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { detailBackground }
        .id(station.id)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.992)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: station.id)
    }

    private var detailBackground: some View {
        ZStack {
            Color.black.opacity(0.05)
            RadialGradient(
                colors: [accent.opacity(0.13), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 620
            )
            LinearGradient(
                colors: [.white.opacity(0.025), .clear, .black.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            Button {
                state.closeStation()
            } label: {
                Label("К станциям", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .help("Вернуться к списку станций")

            Spacer()
        }
        .padding(.horizontal, 26)
        .frame(height: 44)
    }

    // MARK: - Now playing

    private var nowPlayingColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 12)

            currentArtwork

            VStack(alignment: .leading, spacing: 4) {
                Text(currentSongTitle)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let artist = currentTrack?.displayArtist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    CachedImage(url: station.iconURL, contentMode: .fit, maxPixel: 64) { Color.clear }
                        .frame(width: 18, height: 18)

                    Text(station.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                .padding(.top, 3)
            }
            .padding(.top, 17)

            if let description = station.tooltip?.trimmed, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(2)
                    .padding(.top, 10)
            }

            controls
                .padding(.top, 17)

            if !station.genreNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(station.genreNames.prefix(3), id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.055), in: Capsule())
                    }
                }
                .padding(.top, 14)
            }

            Spacer(minLength: 20)
        }
        .frame(maxHeight: .infinity)
    }

    private var currentArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.28))

            if let artworkURL = currentTrack?.artworkURL {
                CachedImage(url: artworkURL, contentMode: .fill, maxPixel: 800) {
                    artworkFallback
                }
            } else {
                artworkFallback
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
        .accessibilityHidden(true)
    }

    private var artworkFallback: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.26), .black.opacity(0.36)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            CachedImage(url: station.iconURL, contentMode: .fit, maxPixel: 360) { Color.clear }
                .padding(54)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button {
                state.step(by: -1)
                query = ""
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.84))
            .disabled(state.stations.isEmpty)
            .accessibilityLabel("Предыдущая станция")
            .help("Предыдущая станция")

            Button {
                if isCurrent {
                    state.togglePlayPause()
                } else {
                    state.startPlayback(station)
                }
            } label: {
                ZStack {
                    Circle().fill(accent)
                    if isCurrent && state.player.state == .connecting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 1.5)
                    }
                }
                .frame(width: 46, height: 46)
                .shadow(color: accent.opacity(0.32), radius: 12, y: 5)
            }
            .buttonStyle(StationPlayButtonStyle())
            .accessibilityLabel(L10n.string(isPlaying ? "Пауза" : "Играть"))

            Button {
                state.step(by: 1)
                query = ""
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.84))
            .disabled(state.stations.isEmpty)
            .accessibilityLabel("Следующая станция")
            .help("Следующая станция")

            Button {
                state.toggleFavorite(station)
            } label: {
                Image(systemName: state.isFavorite(station) ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state.isFavorite(station) ? accent : Color.primary)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.06), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string(state.isFavorite(station) ? "Убрать из избранного" : "В избранное"))
        }
    }

    // MARK: - History

    private var historyColumn: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("История эфира")
                    .font(.system(size: 18, weight: .bold))

                if !state.playlist.isEmpty {
                    Text(L10n.recentTrackCount(state.playlist.count))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                }

                Spacer(minLength: 8)

                Button {
                    Task { await state.loadPlaylist(for: station) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(state.isLoadingPlaylist)
                .accessibilityLabel("Обновить историю эфира")
                .help("Обновить")
            }

            if !state.playlist.isEmpty { searchField }

            ScrollView {
                historyContent
                    .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.top, 12)
        .frame(maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
            TextField("Поиск по истории эфира", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let error = state.playlistError, state.playlist.isEmpty {
            detailMessage(icon: "wifi.exclamationmark", title: "Не удалось загрузить", subtitle: error) {
                Task { await state.loadPlaylist(for: station) }
            }
        } else if state.playlist.isEmpty && state.isLoadingPlaylist {
            ProgressView("Загружаем историю эфира…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if filteredTracks.isEmpty {
            detailMessage(
                icon: query.isEmpty ? "music.note.list" : "magnifyingglass",
                title: query.isEmpty ? "История эфира пуста" : "Ничего не найдено",
                subtitle: query.isEmpty
                    ? "Станция пока не отдала список недавних треков."
                    : "Попробуйте изменить поисковый запрос."
            )
        } else {
            LazyVStack(spacing: 2) {
                ForEach(groupedTracks, id: \.day) { group in
                    Section {
                        ForEach(group.tracks, id: \.rowID) { track in
                            StationHistoryRow(track: track)
                        }
                    } header: {
                        HStack {
                            Text(group.day)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 3)
                    }
                }
            }
        }
    }

    private var filteredTracks: [PlaylistTrack] {
        let normalized = query.trimmed.lowercased()
        guard !normalized.isEmpty else { return state.playlist }
        return state.playlist.filter { $0.displayTitle.lowercased().contains(normalized) }
    }

    private var groupedTracks: [(day: String, tracks: [PlaylistTrack])] {
        var order: [String] = []
        var buckets: [String: [PlaylistTrack]] = [:]
        for track in filteredTracks {
            let day = Self.dayLabel(for: track.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(track)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private static func dayLabel(for date: Date?) -> String {
        guard let date else { return L10n.string("Без времени") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.string("Сегодня") }
        if calendar.isDateInYesterday(date) { return L10n.string("Вчера") }
        return date.formatted(.dateTime.day().month(.wide))
    }

    private func detailMessage(
        icon: String,
        title: LocalizedStringKey,
        subtitle: String,
        retry: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Повторить", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct StationPlayButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - History row

private struct StationHistoryRow: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let track: PlaylistTrack

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(track.timeText)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 42, alignment: .leading)

            CachedImage(url: track.artworkURL, contentMode: .fill, maxPixel: 96) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3))
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(track.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer(minLength: 6)

            if (hovered || voiceOverEnabled), let url = track.itunesUrl.flatMap(URL.init(string:)) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .help("Открыть в Apple Music")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if hovered {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.07))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(track.displayTitle)
        .accessibilityValue(track.timeText)
        .contextMenu {
            Button("Скопировать название") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(track.displayTitle, forType: .string)
            }
            if let url = track.itunesUrl.flatMap(URL.init(string:)) {
                Button("Открыть в Apple Music") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

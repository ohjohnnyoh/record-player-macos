import AppKit
import SwiftUI

/// Плейлист станции: что играло в эфире до текущего трека.
struct StationPlaylistView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState

    let station: Station

    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            content
        }
        .frame(width: 520, height: 620)
        .background(Theme.background)
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 12) {
            CachedImage(url: station.iconURL, contentMode: .fit, maxPixel: 128) { Color.clear }
                .frame(width: 34, height: 34)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 1) {
                Text(station.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 8)

            Button {
                Task { await state.loadPlaylist(for: station) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Обновить")
            .disabled(state.isLoadingPlaylist)

            Button("Закрыть") { state.playlistStation = nil }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        if state.isLoadingPlaylist && state.playlist.isEmpty { return "Загружаем плейлист…" }
        if state.playlist.isEmpty { return "Плейлист эфира" }
        return "\(state.playlist.count) треков за последние сутки"
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var content: some View {
        if let error = state.playlistError, state.playlist.isEmpty {
            message(icon: "wifi.exclamationmark", title: "Не удалось загрузить", subtitle: error) {
                Button("Повторить") { Task { await state.loadPlaylist(for: station) } }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
        } else if state.playlist.isEmpty && state.isLoadingPlaylist {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.playlist.isEmpty {
            message(icon: "music.note.list", title: "Плейлист пуст",
                    subtitle: "Станция не отдала историю эфира.") { EmptyView() }
        } else {
            VStack(spacing: 0) {
                searchField
                Divider().overlay(Theme.separator)
                list
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
            TextField("Поиск по плейлисту", text: $query)
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.tracks, id: \.rowID) { track in
                            PlaylistRow(track: track)
                        }
                    } header: {
                        HStack {
                            Text(group.day)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 3)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    /// Треки, сгруппированные по дню — за сутки с лишним день успевает смениться.
    private var grouped: [(day: String, tracks: [PlaylistTrack])] {
        let normalized = query.trimmed.lowercased()
        let filtered = normalized.isEmpty
            ? state.playlist
            : state.playlist.filter { $0.displayTitle.lowercased().contains(normalized) }

        var order: [String] = []
        var buckets: [String: [PlaylistTrack]] = [:]
        for track in filtered {
            let day = Self.dayLabel(for: track.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(track)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private static func dayLabel(for date: Date?) -> String {
        guard let date else { return "Без времени" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        return date.formatted(.dateTime.day().month(.wide))
    }

    private func message<Action: View>(
        icon: String, title: String, subtitle: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            action().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Строка плейлиста

private struct PlaylistRow: View {
    @Environment(\.appAccent) private var accent
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
                RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.3))
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(track.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer(minLength: 6)

            if hovered, let url = track.itunesUrl.flatMap(URL.init(string:)) {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if hovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.07))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
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

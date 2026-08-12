import AppKit
import SwiftUI

/// Компактный плеер в меню-баре: слушать можно, не открывая окно.
struct MenuBarView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    private var track: Track? { state.currentTrack }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            stationList
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 320)
        .background(Theme.background)
    }

    // MARK: - Шапка с текущим треком

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                if let track, track.artworkURL != nil {
                    CachedImage(url: track.smallArtworkURL, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else if let station = state.currentStation {
                    CachedImage(url: station.iconURL, contentMode: .fit) { Color.clear }
                        .padding(7)
                } else {
                    Image(systemName: "radio").foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track?.displayTitle ?? state.currentStation?.title ?? "Ничего не играет")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                if let station = state.currentStation {
                    Text(station.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button {
                state.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(accent).frame(width: 30, height: 30)
                    if state.player.state == .connecting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: state.player.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(state.currentStation == nil && state.stations.isEmpty)
        }
        .padding(12)
    }

    // MARK: - Избранное / недавние

    private var stationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            let list = quickList
            if list.isEmpty {
                Text("Добавьте станции в избранное — они появятся здесь")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(12)
            } else {
                Text(state.favoriteStations.isEmpty ? "Популярные" : "Избранное")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(list) { station in
                            MenuStationRow(station: station)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private var quickList: [Station] {
        let favorites = state.favoriteStations
        if !favorites.isEmpty { return favorites }
        return Array(state.stations.sorted { ($0.sort ?? .max) < ($1.sort ?? .max) }.prefix(8))
    }

    // MARK: - Низ

    private var footer: some View {
        VStack(spacing: 8) {
            VolumeSlider(player: state.player)

            HStack(spacing: 10) {
                Button("Открыть окно") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                Button {
                    state.playRandom()
                } label: {
                    Image(systemName: "shuffle")
                }
                .help("Случайная станция")

                Spacer()

                Button("Выйти") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct MenuStationRow: View {
    @Environment(\.appAccent) private var accent
    let station: Station
    @EnvironmentObject private var state: AppState
    @State private var hovered = false

    private var isCurrent: Bool { state.currentStation?.id == station.id }

    var body: some View {
        Button {
            state.play(station)
        } label: {
            HStack(spacing: 8) {
                CachedImage(url: station.iconURL, contentMode: .fit) { Color.clear }
                    .frame(width: 20, height: 20)
                    .opacity(0.85)

                VStack(alignment: .leading, spacing: 1) {
                    Text(station.title)
                        .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? accent : Color.primary)
                        .lineLimit(1)
                    if let track = state.nowPlaying[station.id], !track.displayTitle.isEmpty {
                        Text(track.displayTitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if isCurrent && state.player.state == .playing {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered ? Color.white.opacity(0.09) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

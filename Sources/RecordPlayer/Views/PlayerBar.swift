import AppKit
import SwiftUI

/// Плавающая «пилюля» плеера поверх сетки станций — как мини-плеер Apple Music.
/// Не участвует в раскладке окна: контент прокручивается под ней.
struct PlayerBar: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var artworkHovered = false

    /// Сколько места оставить снизу в прокручиваемом контенте, чтобы
    /// последний ряд карточек не прятался под пилюлей.
    static let reservedHeight: CGFloat = 84

    private var station: Station? { state.currentStation }
    private var track: Track? { state.currentTrack }

    var body: some View {
        HStack(spacing: 12) {
            transportControls

            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(track?.displayTitle ?? station?.title ?? "Выберите станцию")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let station {
                        Text(station.title)
                            .foregroundStyle(accent)
                    }
                    statusLabel
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer(minLength: 12)

            VolumeSlider(player: state.player, sliderWidth: 84)
            extrasMenu
        }
        .padding(.horizontal, 13)
        .frame(height: 58)
        .frame(maxWidth: 900)
        .background {
            // Здесь была `.ultraThinMaterial`. Проблема в том, что ширина пилюли
            // равна ширине колонки: пока сайдбар выезжает, она меняется каждый кадр,
            // и размытие пересчитывается заново на каждом. На широком окне ширина
            // упирается в лимит 900 и не меняется — потому там и было плавно,
            // а на узком дёргалось. Плотная заливка приглушает карточки не хуже
            // и не стоит ничего.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.125).opacity(0.94))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.26), .white.opacity(0.08), .white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.42), radius: 16, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Части

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.35))

            if let track, track.artworkURL != nil {
                // Размер обязателен до обрезки: при .fill картинка растягивается
                // больше предложенного, и без рамки clipShape режет уже по её
                // раздутым границам — неквадратные обложки наезжали на текст.
                CachedImage(url: track.smallArtworkURL, contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if let station {
                CachedImage(url: station.iconURL, contentMode: .fit) {
                    Image(systemName: "radio").foregroundStyle(Theme.tertiaryText)
                }
                .padding(6)
            } else {
                Image(systemName: "radio")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Theme.tertiaryText)
            }

            // По клику разворачиваем обложку в отдельный мини-плеер.
            if artworkHovered {
                ZStack {
                    Color.black.opacity(0.45)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .frame(width: 38, height: 38)
        .contentShape(Rectangle())
        .onHover { artworkHovered = $0 }
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "mini")
        }
        .help("Открыть мини-плеер (⌥⌘M)")
        .animation(.easeOut(duration: 0.14), value: artworkHovered)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch state.player.state {
        case .connecting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text("подключение…")
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(1)
        case .paused:
            Text("· пауза")
        case .playing:
            if let deadline = state.sleepDeadline {
                // Обновляем остаток раз в полминуты, а не только при смене состояния.
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text("· сон через \(Self.remaining(until: deadline))")
                }
            } else {
                EmptyView()
            }
        case .idle:
            EmptyView()
        }
    }

    private var transportControls: some View {
        HStack(spacing: 13) {
            Button { state.step(by: -1) } label: {
                Image(systemName: "backward.fill")
            }
            .help("Предыдущая станция (⌘←)")

            Button {
                state.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(accent).frame(width: 32, height: 32)
                    if state.player.state == .connecting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: state.player.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: state.player.state == .playing ? 0 : 1)
                    }
                }
            }
            .help(state.player.state.isActive ? "Пауза (пробел)" : "Играть (пробел)")

            Button { state.step(by: 1) } label: {
                Image(systemName: "forward.fill")
            }
            .help("Следующая станция (⌘→)")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(state.currentStation == nil ? Theme.tertiaryText : Color.primary)
        .disabled(state.stations.isEmpty)
    }

    private var extrasMenu: some View {
        Menu {
            Section("Качество") {
                ForEach(StreamQuality.allCases) { quality in
                    Button {
                        state.quality = quality
                    } label: {
                        HStack {
                            Text("\(quality.title) — \(quality.subtitle)")
                            if state.quality == quality { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Section("Таймер сна") {
                ForEach([15, 30, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) мин") { state.setSleepTimer(minutes: minutes) }
                }
                if state.sleepDeadline != nil {
                    Button("Отменить таймер") { state.setSleepTimer(minutes: nil) }
                }
            }

            Divider()

            if let station = state.currentStation {
                Button("Что играло раньше…") { state.showPlaylist(for: station) }
            }

            Button("Мини-плеер") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "mini")
            }

            if let station = state.currentStation {
                Button(state.isFavorite(station) ? "Убрать из избранного" : "В избранное") {
                    state.toggleFavorite(station)
                }
            }
            if let url = track?.itunesUrl.flatMap(URL.init(string:)) {
                Button("Открыть трек в Apple Music") { NSWorkspace.shared.open(url) }
            }
            if let title = track?.displayTitle, !title.isEmpty {
                Button("Скопировать название трека") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(title, forType: .string)
                }
            }

            Divider()
            Button("Обновить список станций") {
                Task { await state.loadStations() }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .help("Качество, таймер сна и прочее")
    }

    static func remaining(until date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        return "\(minutes) мин"
    }
}

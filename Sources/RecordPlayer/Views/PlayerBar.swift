import AppKit
import SwiftUI

/// Плавающая «пилюля» плеера поверх сетки станций — как мини-плеер Apple Music.
/// Не участвует в раскладке окна: контент прокручивается под ней.
struct PlayerBar: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @EnvironmentObject private var state: AppState
    @State private var artworkHovered = false
    @State private var barHovered = false
    @State private var extrasHovered = false

    /// Сколько места оставить снизу в прокручиваемом контенте, чтобы
    /// последний ряд карточек не прятался под пилюлей.
    static let reservedHeight: CGFloat = 84

    private var station: Station? { state.currentStation }
    private var track: Track? { state.currentTrack }

    /// Что показать первой строкой: выпуск, трек эфира или приглашение выбрать.
    private var primaryTitle: String {
        if let episode = state.currentEpisode { return episode.title }
        return track?.displayTitle ?? station?.title ?? L10n.string("Выберите станцию")
    }

    var body: some View {
        HStack(spacing: 12) {
            transportControls

            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                if let episode = state.currentEpisode {
                    // У выпуска вместо строки состояния — полоса перемотки:
                    // знать, сколько осталось, полезнее, чем слово «пауза».
                    PlaybackScrubber(
                        timeline: state.player.timeline,
                        accent: accent,
                        compact: true,
                        onSeek: { state.seekInEpisode(to: $0) }
                    )
                    .id(episode.id)
                } else {
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
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer(minLength: 12)

            VolumeSlider(player: state.player, sliderWidth: 84)
            extrasMenu
        }
        .padding(.horizontal, 13)
        .frame(height: 56)
        .frame(maxWidth: 900)
        .modifier(PlayerGlassSurface(
            accent: accent,
            hovered: barHovered,
            reduceTransparency: reduceTransparency,
            reduceMotion: reduceMotion,
            increasedContrast: contrast == .increased
        ))
        .scaleEffect(barHovered && !reduceMotion ? 1.002 : 1)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .onHover { barHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: barHovered)
    }

    // MARK: - Части

    private var artwork: some View {
        Button {
            if let podcast = state.currentEpisodePodcast, state.currentEpisode != nil {
                state.showPodcast(podcast)
            } else if let station {
                state.showStation(station)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.35))

                if let episode = state.currentEpisode {
                    CachedImage(url: episode.smallArtworkURL, contentMode: .fill, maxPixel: 96) {
                        Image(systemName: "mic").foregroundStyle(Theme.tertiaryText)
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else if let track, track.artworkURL != nil {
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

                if artworkHovered {
                    ZStack {
                        Color.black.opacity(0.45)
                        Image(systemName: "rectangle.inset.filled")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(station == nil && state.currentEpisode == nil)
        .onHover { artworkHovered = $0 }
        .accessibilityLabel(L10n.string(
            state.currentEpisode != nil ? "Открыть подкаст" : "Открыть станцию"
        ))
        .accessibilityValue(primaryTitle)
        .help(L10n.string(
            state.currentEpisode != nil ? "Открыть подкаст" : "Открыть станцию"
        ))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: artworkHovered)
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
                    Text(L10n.format("· сон через %@", Self.remaining(until: deadline)))
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
            if let episode = state.currentEpisode {
                PlayerTransportButton(
                    symbol: "gobackward.15",
                    help: L10n.string("Назад на 15 секунд")
                ) { state.skipInEpisode(by: -15) }
                    .accessibilityLabel(L10n.string("Назад на 15 секунд"))
                    .id("back-\(episode.id)")
            } else {
                PlayerTransportButton(
                    symbol: "backward.fill",
                    help: L10n.string("Предыдущая станция (⌘←)")
                ) { state.step(by: -1) }
            }

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
            .buttonStyle(PlayerMainButtonStyle())
            .accessibilityLabel(L10n.string(state.player.state.isActive ? "Пауза" : "Играть"))
            .accessibilityHint(L10n.string(
                state.currentEpisode != nil
                    ? "Управляет воспроизведением выпуска"
                    : "Управляет воспроизведением текущей станции"
            ))
            .help(L10n.string(state.player.state.isActive ? "Пауза (пробел)" : "Играть (пробел)"))

            if let episode = state.currentEpisode {
                PlayerTransportButton(
                    symbol: "goforward.15",
                    help: L10n.string("Вперёд на 15 секунд")
                ) { state.skipInEpisode(by: 15) }
                    .accessibilityLabel(L10n.string("Вперёд на 15 секунд"))
                    .id("fwd-\(episode.id)")
            } else {
                PlayerTransportButton(
                    symbol: "forward.fill",
                    help: L10n.string("Следующая станция (⌘→)")
                ) { state.step(by: 1) }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(
            state.currentStation == nil && state.currentEpisode == nil
                ? Theme.tertiaryText
                : Color.primary
        )
        .disabled(state.stations.isEmpty && state.currentEpisode == nil)
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
                    Button(L10n.format("%@ мин", String(minutes))) {
                        state.setSleepTimer(minutes: minutes)
                    }
                }
                if state.sleepDeadline != nil {
                    Button("Отменить таймер") { state.setSleepTimer(minutes: nil) }
                }
            }

            Divider()

            if let station = state.currentStation {
                Button("Что играло раньше…") { state.showPlaylist(for: station) }
            }

            if let station = state.currentStation {
                Button(L10n.string(state.isFavorite(station) ? "Убрать из избранного" : "В избранное")) {
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
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(.white.opacity(extrasHovered ? 0.10 : 0))
                }
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28)
        .onHover { extrasHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: extrasHovered)
        .accessibilityLabel("Дополнительные параметры")
        .help("Качество, таймер сна и прочее")
    }

    static func remaining(until date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        return L10n.format("%@ мин", String(minutes))
    }
}

// MARK: - Микровзаимодействия плеера

private struct PlayerTransportButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(.white.opacity(hovered ? 0.10 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered && !reduceMotion ? 1.04 : 1)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .accessibilityLabel(help)
        .help(help)
    }
}

private struct PlayerMainButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Функциональный слой плеера. На macOS 26 система сама рисует рефракцию,
/// адаптирует контраст и реагирует на указатель. Старые системы получают один
/// AppKit blur-слой, а Reduce Transparency — полностью непрозрачную поверхность.
private struct PlayerGlassSurface: ViewModifier {
    let accent: Color
    let hovered: Bool
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let increasedContrast: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.playerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { shape.fill(Theme.opaqueBackground) }
                .overlay {
                    shape.strokeBorder(
                        .white.opacity(increasedContrast ? 0.48 : 0.24),
                        lineWidth: increasedContrast ? 1.2 : 1
                    )
                }
                .clipShape(shape)
                .modifier(PlayerDepth(hovered: hovered, reduceMotion: reduceMotion))
        } else if #available(macOS 26.0, *) {
            // Стекло не умеет сэмплировать другое стекло, поэтому Apple требует
            // группировать такие поверхности в контейнер. Сейчас слой здесь один,
            // но без контейнера любая добавленная рядом стеклянная деталь
            // рассогласуется с пилюлей — в мини-плеере контейнер уже стоит.
            GlassEffectContainer(spacing: 12) {
                content
                    .glassEffect(
                        .regular
                            .tint(accent.opacity(hovered ? 0.12 : 0.075))
                            .interactive(!reduceMotion),
                        in: shape
                    )
                    .overlay {
                        shape
                            .inset(by: 0.8)
                            .strokeBorder(
                                .white.opacity(increasedContrast ? 0.34 : 0.10),
                                lineWidth: increasedContrast ? 1.1 : 0.6
                            )
                            .allowsHitTesting(false)
                    }
            }
            .modifier(PlayerDepth(hovered: hovered, reduceMotion: reduceMotion))
        } else {
            content
                .background { legacyGlass }
                .clipShape(shape)
                .modifier(PlayerDepth(hovered: hovered, reduceMotion: reduceMotion))
        }
    }

    private var legacyGlass: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blending: .withinWindow)
            Color(red: 0.055, green: 0.055, blue: 0.07)
                .opacity(hovered ? 0.30 : 0.36)
            LinearGradient(
                colors: [.white.opacity(hovered ? 0.17 : 0.13), .white.opacity(0.035), .black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(hovered ? 0.11 : 0.07), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 360
            )
        }
        .allowsHitTesting(false)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.34), .white.opacity(0.13), .white.opacity(0.05), .black.opacity(0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }
}

private struct PlayerDepth: ViewModifier {
    let hovered: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(hovered ? 0.48 : 0.40), radius: hovered ? 22 : 17, y: 7)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: hovered)
    }
}

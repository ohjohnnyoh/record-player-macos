import AppKit
import SwiftUI

/// Мини-плеер в духе Apple Music: квадратное окно поверх остальных,
/// обложка во всю площадь, управление проявляется при наведении.
struct MiniPlayerView: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var hovered = false
    @FocusState private var focusedControl: MiniControl?

    private enum MiniControl: Hashable {
        case mainWindow, favorite, previous, playPause, next
    }

    private var station: Station? { state.currentStation }
    private var track: Track? { state.currentTrack }
    private var controlsVisible: Bool {
        hovered || voiceOverEnabled || focusedControl != nil
    }

    var body: some View {
        // Раскладку строим от фактического размера контента, а не от размера окна:
        // у окна есть скрытая полоса заголовка, из-за неё низ раньше срезался.
        GeometryReader { geo in
            ZStack {
                artwork(size: geo.size)
                scrim
                content
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .frame(minWidth: 220, minHeight: 220)
        // Заголовок скрыт, но SwiftUI всё равно резервирует под него полосу сверху —
        // без этого над обложкой оставалась чёрная лента высотой с титульбар.
        .ignoresSafeArea()
        .background(windowConfigurator)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: controlsVisible)
        .contextMenu {
            Button("Открыть главное окно") { showMainWindow() }
            if let station {
                Button(L10n.string(state.isFavorite(station) ? "Убрать из избранного" : "В избранное")) {
                    state.toggleFavorite(station)
                }
            }
            if let url = track?.itunesUrl.flatMap(URL.init(string:)) {
                Button("Открыть трек в Apple Music") { NSWorkspace.shared.open(url) }
            }
        }
    }

    // MARK: - Слои

    private func artwork(size: CGSize) -> some View {
        ZStack {
            Theme.background

            if let url = track?.artworkURL {
                CachedImage(url: url, contentMode: .fill)
                    .frame(width: size.width, height: size.height)
            } else if let icon = station?.iconURL {
                CachedImage(url: icon, contentMode: .fit) { Color.clear }
                    .frame(width: size.width * 0.52, height: size.height * 0.52)
                    .opacity(0.9)
            } else {
                Image(systemName: "radio")
                    .font(.system(size: size.width * 0.18, weight: .ultraLight))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var scrim: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .black.opacity(0.30), .black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            Color.black.opacity(hovered ? 0.28 : 0)
        }
        .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            transport
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
            Spacer(minLength: 0)
            bottomBlock
        }
    }

    private var topBar: some View {
        HStack(spacing: 2) {
            Spacer()
            glassButton(
                "macwindow", help: L10n.string("Открыть главное окно"), size: 11,
                control: .mainWindow
            ) { showMainWindow() }
            if let station {
                glassButton(
                    state.isFavorite(station) ? "heart.fill" : "heart",
                    help: L10n.string(state.isFavorite(station) ? "Убрать из избранного" : "В избранное"),
                    size: 11,
                    tint: state.isFavorite(station) ? accent : .white,
                    control: .favorite
                ) { state.toggleFavorite(station) }
            }
        }
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
        .padding(.top, 8)
        .padding(.trailing, 10)
        .frame(height: 34)
    }

    @ViewBuilder
    private var transport: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { transportControls }
                .modifier(TransportPresentation(reduceMotion: reduceMotion))
        } else {
            transportControls
                .modifier(TransportPresentation(reduceMotion: reduceMotion))
        }
    }

    private var transportControls: some View {
        HStack(spacing: 20) {
            glassButton(
                "backward.fill", help: L10n.string("Предыдущая станция"), size: 15,
                circle: 34, control: .previous
            ) {
                state.step(by: -1)
            }

            Button {
                state.togglePlayPause()
            } label: {
                ZStack {
                    if state.player.state == .connecting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: state.player.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: state.player.state == .playing ? 0 : 2)
                    }
                }
                .frame(width: 54, height: 54)
                .modifier(MiniGlassSurface(
                    tint: accent.opacity(0.10),
                    reduceTransparency: reduceTransparency,
                    reduceMotion: reduceMotion
                ))
            }
            .buttonStyle(.plain)
            .focused($focusedControl, equals: .playPause)
            .accessibilityLabel(L10n.string(state.player.state.isActive ? "Пауза" : "Играть"))

            glassButton(
                "forward.fill", help: L10n.string("Следующая станция"), size: 15,
                circle: 34, control: .next
            ) {
                state.step(by: 1)
            }
        }
    }

    private var bottomBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track?.displayTitle ?? station?.title ?? L10n.string("Ничего не играет"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)

            HStack(spacing: 5) {
                if state.player.state == .connecting {
                    ProgressView().controlSize(.mini).scaleEffect(0.6).tint(.white)
                }
                Text(station?.title ?? "")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
            }

            if controlsVisible {
                VolumeSlider(player: state.player, compact: true)
                    .padding(.top, 3)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 13)
        .padding(.top, 8)
    }

    // MARK: - Мелочи

    private func glassButton(
        _ symbol: String,
        help: String,
        size: CGFloat,
        tint: Color = .white,
        circle: CGFloat? = nil,
        control: MiniControl,
        action: @escaping () -> Void
    ) -> some View {
        let diameter = circle ?? 26
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .modifier(MiniGlassSurface(
                    tint: tint == accent ? accent.opacity(0.22) : nil,
                    reduceTransparency: reduceTransparency,
                    reduceMotion: reduceMotion
                ))
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: control)
        .accessibilityLabel(help)
        .help(help)
    }

    private var windowConfigurator: some View {
        WindowConfigurator { window in
            // fullSizeContentView обязателен: иначе контент живёт ниже скрытого
            // заголовка, а квадратные пропорции считаются по внешней рамке — низ срезается.
            window.styleMask.insert(.fullSizeContentView)
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.aspectRatio = NSSize(width: 1, height: 1)
            window.minSize = NSSize(width: 220, height: 220)
            window.maxSize = NSSize(width: 560, height: 560)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.backgroundColor = .black
            window.isOpaque = true

            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = Theme.windowRadius
                contentView.layer?.cornerCurve = .continuous
                contentView.layer?.masksToBounds = true
            }
        }
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}

private struct TransportPresentation: ViewModifier {
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.5), radius: 10)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
    }
}

/// Clear Liquid Glass предназначен Apple именно для transient-контролов поверх
/// фото и видео. При Reduce Transparency поверхность становится плотной.
private struct MiniGlassSurface: ViewModifier {
    let tint: Color?
    let reduceTransparency: Bool
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { Circle().fill(.black.opacity(0.78)) }
                .overlay { Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1) }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(
                .clear.tint(tint).interactive(!reduceMotion),
                in: Circle()
            )
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().fill(.white.opacity(0.12)) }
                .overlay { Circle().strokeBorder(.white.opacity(0.30), lineWidth: 1) }
        }
    }
}

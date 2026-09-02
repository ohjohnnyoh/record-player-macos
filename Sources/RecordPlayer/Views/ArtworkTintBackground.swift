import SwiftUI

/// Фон полноразмерного экрана, окрашенный в цвета обложки — как развёрнутый
/// плеер Apple Music.
///
/// Живёт только здесь и не поднимается на всё приложение: каталог станций
/// должен оставаться обычным полупрозрачным окном macOS, сквозь которое видны
/// обои. Цветной фон уместен там, где обложка и есть главный объект экрана.
struct ArtworkTintBackground: View {
    /// Обложка, с которой снимаются цвета. При смене трека фон переливается.
    let artworkURL: URL?
    /// Чем красить, пока палитры нет: обложка ещё грузится или её вовсе нет.
    let fallbackAccent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var palette: ArtworkPalette?

    var body: some View {
        ZStack {
            if let palette {
                tint(palette)
            } else {
                fallback
            }
            // Низ притемняем всегда: под ним подпись трека и название станции,
            // а яркая обложка может дать там почти белый фон.
            LinearGradient(
                colors: [.clear, .black.opacity(0.30)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: palette)
        .task(id: artworkURL) {
            guard let artworkURL else {
                palette = nil
                return
            }
            let loaded = await ImageStore.shared.palette(for: artworkURL)
            guard !Task.isCancelled else { return }
            // Неудачу не превращаем в сброс на серый: пусть лучше подержится
            // прежний цвет, чем экран моргнёт в пустоту из-за одной осечки.
            guard let loaded else { return }
            palette = loaded
        }
    }

    private func tint(_ palette: ArtworkPalette) -> some View {
        ZStack {
            palette.base.color

            // Главное пятно — под обложкой, она в левой колонке.
            RadialGradient(
                colors: [palette.primary.color.opacity(tintOpacity), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 820
            )
            // Второе — по диагонали, иначе фон читается как плоская заливка.
            RadialGradient(
                colors: [palette.secondary.color.opacity(tintOpacity * 0.8), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 700
            )
        }
    }

    private var fallback: some View {
        ZStack {
            Color.black.opacity(0.05)
            RadialGradient(
                colors: [fallbackAccent.opacity(0.13), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 620
            )
        }
    }

    /// При повышенном контрасте цвет приглушается: системе важнее, чтобы текст
    /// уверенно читался, чем чтобы фон точно повторял обложку.
    private var tintOpacity: Double {
        contrast == .increased ? 0.45 : 0.9
    }
}

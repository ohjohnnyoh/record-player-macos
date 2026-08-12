import SwiftUI

enum Theme {
    /// Системные семантические цвета автоматически учитывают активность окна,
    /// повышенный контраст и будущие изменения внешнего вида macOS.
    static let background = Color(nsColor: .windowBackgroundColor)
    static let opaqueBackground = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let separator = Color(nsColor: .separatorColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    static let windowRadius: CGFloat = 18
    static let cardRadius: CGFloat = 12
    static let playerRadius: CGFloat = 18
}

// MARK: - Карточка

/// Полупрозрачная панель с тонким бортиком-бликом.
///
/// Намеренно без собственного размытия: прозрачность даёт окно
/// (см. `VisualEffectBackground`), а карточка — лишь лёгкая засветка поверх.
/// Сорок восемь отдельных blur-слоёв клали композитор на лопатки,
/// эта версия не стоит практически ничего.
struct GlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var hovered: Bool = false
    var selected: Bool = false
    var radius: CGFloat = Theme.cardRadius
    var accent: Color = AccentPalette.red.color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                // Градиентный бортик остаётся только у выбранной карточки — она одна.
                // На всех остальных он был главной статьёй расходов при анимации:
                // растеризация осевого градиента идёт на процессоре, и 48 таких
                // обводок пересчитывались каждый кадр, пока выезжал сайдбар.
                // Сплошная обводка даёт ту же грань стекла и почти ничего не стоит.
                if selected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(selectedBorder, lineWidth: 1.2)
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            .white.opacity(borderOpacity),
                            lineWidth: contrast == .increased ? 1.2 : 1
                        )
                }
            }
    }

    private var fill: Color {
        if reduceTransparency {
            if selected { return Color(red: 0.18, green: 0.18, blue: 0.20) }
            if hovered { return Color(red: 0.145, green: 0.145, blue: 0.16) }
            return Color(red: 0.105, green: 0.105, blue: 0.12)
        }
        if selected { return .white.opacity(0.13) }
        if hovered { return .white.opacity(0.10) }
        return .white.opacity(0.05)
    }

    private var borderOpacity: Double {
        if contrast == .increased { return hovered ? 0.52 : 0.34 }
        return hovered ? 0.30 : 0.16
    }

    /// Бортик светлеет сверху-слева и гаснет снизу-справа — как отблеск на грани стекла.
    private var selectedBorder: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.95), accent.opacity(0.35)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

extension View {
    func glassCard(hovered: Bool = false, selected: Bool = false,
                   radius: CGFloat = Theme.cardRadius,
                   accent: Color = AccentPalette.red.color) -> some View {
        modifier(GlassCard(hovered: hovered, selected: selected, radius: radius, accent: accent))
    }
}

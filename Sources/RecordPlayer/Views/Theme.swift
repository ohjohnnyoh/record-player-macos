import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.065)
    static let separator = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)

    static let cardRadius: CGFloat = 12
}

// MARK: - Карточка

/// Полупрозрачная панель с тонким бортиком-бликом.
///
/// Намеренно без собственного размытия: прозрачность даёт окно
/// (см. `VisualEffectBackground`), а карточка — лишь лёгкая засветка поверх.
/// Сорок восемь отдельных blur-слоёв клали композитор на лопатки,
/// эта версия не стоит практически ничего.
struct GlassCard: ViewModifier {
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
                        .strokeBorder(.white.opacity(hovered ? 0.30 : 0.16), lineWidth: 1)
                }
            }
    }

    private var fill: Color {
        if selected { .white.opacity(0.13) }
        else if hovered { .white.opacity(0.10) }
        else { .white.opacity(0.05) }
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

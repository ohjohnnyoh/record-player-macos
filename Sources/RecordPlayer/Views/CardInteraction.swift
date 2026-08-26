import SwiftUI

/// Поведение карточки при наведении, фокусе и нажатии.
///
/// Общее для сеток станций и подкастов: наведение, кольцо фокуса, ввод с
/// клавиатуры и подавление анимаций при включённом Reduce Motion. Держать это
/// в одном месте важнее, чем кажется — иначе две сетки со временем разъедутся
/// в мелочах, которые никто не заметит до жалобы.
struct CardInteraction: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    @Binding var hovered: Bool
    let reduceMotion: Bool
    let isCurrent: Bool
    let accent: Color
    let helpText: String
    var radius: CGFloat = Theme.cardRadius
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .onKeyPress(.return) {
                action()
                return .handled
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(accent.opacity(0.88), lineWidth: 2)
                        .padding(1)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovered = $0 }
            .scaleEffect(hovered && !reduceMotion ? 1.012 : 1)
            .offset(y: hovered && !reduceMotion ? -1 : 0)
            .shadow(color: .black.opacity(hovered ? 0.22 : 0), radius: 10, y: 4)
            .help(helpText)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isCurrent)
    }
}

/// Карточка как единый элемент для VoiceOver: одна подпись вместо россыпи
/// текстов, одно действие вместо угадывания, куда нажимать.
struct CardAccessibility: ViewModifier {
    let label: String
    let value: String
    let hint: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

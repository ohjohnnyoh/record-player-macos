import SwiftUI

/// Палитра акцентного цвета. Оттенки подобраны так, чтобы одинаково читаться
/// на тёмном полупрозрачном фоне и не спорить с обложками.
enum AccentPalette: String, CaseIterable, Identifiable, Codable {
    case red
    case gray
    case orange
    case green
    case cyan
    case pink
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: "Красный"
        case .gray: "Нейтральный"
        case .orange: "Оранжевый"
        case .green: "Зелёный"
        case .cyan: "Голубой"
        case .pink: "Розовый"
        case .purple: "Фиолетовый"
        }
    }

    var color: Color {
        switch self {
        case .red:    Color(red: 0.93, green: 0.16, blue: 0.20)
        case .gray:   Color(red: 0.62, green: 0.64, blue: 0.68)
        case .orange: Color(red: 0.98, green: 0.55, blue: 0.14)
        case .green:  Color(red: 0.24, green: 0.78, blue: 0.44)
        case .cyan:   Color(red: 0.25, green: 0.68, blue: 0.94)
        case .pink:   Color(red: 0.96, green: 0.35, blue: 0.62)
        case .purple: Color(red: 0.65, green: 0.42, blue: 0.96)
        }
    }
}

// MARK: - Проброс через окружение

private struct AccentColorKey: EnvironmentKey {
    static let defaultValue: Color = AccentPalette.red.color
}

extension EnvironmentValues {
    /// Акцент приложения. Через окружение, а не глобальной константой:
    /// SwiftUI сам перерисует только те вьюхи, которые его читают.
    var appAccent: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

/// Кнопка в тулбаре с выпадающим списком цветов.
///
/// Сделана поповером, а не `Menu`: пункты системного меню на macOS рисуются
/// шаблонными изображениями, и цветные кружки в них теряют цвет.
struct AccentMenuButton: View {
    @Binding var selection: AccentPalette
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(selection.color)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .help("Акцентный цвет")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(AccentPalette.allCases) { palette in
                    AccentRow(palette: palette, isSelected: selection == palette) {
                        selection = palette
                        isPresented = false
                    }
                }
            }
            .padding(6)
            .frame(width: 178)
        }
    }
}

private struct AccentRow: View {
    let palette: AccentPalette
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(palette.color)
                    .frame(width: 13, height: 13)
                    .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }

                Text(palette.title)
                    .font(.system(size: 12))

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.09) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

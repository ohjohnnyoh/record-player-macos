import AppKit
import SwiftUI

/// Нативная полупрозрачность macOS.
///
/// Ключевое — `blendingMode = .behindWindow`: система размывает то, что лежит
/// *позади окна* (обои, другие окна), один раз и на уровне композитора.
/// Именно так выглядят Пункт управления, боковые панели Finder и Почты.
///
/// Материалы SwiftUI (`.ultraThinMaterial`) по умолчанию работают иначе —
/// `.withinWindow`, то есть размывают содержимое самого приложения. Каждый такой
/// слой стоит отдельного прохода размытия, поэтому их нельзя ставить десятками.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var isEmphasized = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // Присваивание этих свойств помечает вьюху грязной и запускает перерасчёт
        // раскладки — даже когда значение то же самое. А перерасчёт вызывает
        // очередное обновление SwiftUI, которое снова присваивает: получается
        // бесконечная петля, съедавшая проценты процессора на ровном месте.
        if view.material != material { view.material = material }
        if view.blendingMode != blending { view.blendingMode = blending }
        if view.state != state { view.state = state }
        if view.isEmphasized != isEmphasized { view.isEmphasized = isEmphasized }
    }
}

extension View {
    /// Убирает собственную подложку окна, которую SwiftUI рисует под содержимым.
    /// Без этого она закрашивает наш слой прозрачности, и обои сквозь окно не видны.
    @ViewBuilder
    func windowContainerClearBackground() -> some View {
        if #available(macOS 15.0, *) {
            containerBackground(.clear, for: .window)
        } else {
            self
        }
    }
}

/// Позволяет донастроить окно средствами AppKit — прозрачность, уровень, пропорции.
///
/// Настройка выполняется ровно один раз. Раньше она повторялась на каждое
/// обновление SwiftUI, и переустановка `aspectRatio`/`minSize`/`maxSize` на лету
/// заставляла окно дёргаться при изменении размера.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        // Ждём момента, когда вьюха попадёт в окно, вместо угадывания через задержку.
        WindowAwareView(onAttach: configure)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowAwareView: NSView {
        private let onAttach: (NSWindow) -> Void
        private var configured = false

        init(onAttach: @escaping (NSWindow) -> Void) {
            self.onAttach = onAttach
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !configured, let window else { return }
            configured = true
            onAttach(window)
        }
    }
}

extension Notification.Name {
    static let focusStationSearch = Notification.Name("Record.focusStationSearch")
}

/// Поле поиска фиксированной ширины для правой группы toolbar.
///
/// SwiftUI `searchable` на macOS создаёт адаптивный `NSSearchToolbarItem`: при
/// анимации `NavigationSplitView` он схлопывался в кнопку и тут же раскрывался
/// обратно. Обычный `NSSearchField` держит заданную ширину во всех состояниях
/// боковой панели и при этом остаётся полностью системным — со своей лупой,
/// кнопкой очистки, фокусом и меню недавних запросов.
struct FixedToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = prompt
        field.stringValue = text
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        // Размер совпадает с остальными элементами toolbar. Раньше поле было
        // мелким, а разницу в высоте компенсировали вертикальным сжатием всей
        // группы — из-за него текст и рамка переставали выглядеть системными.
        field.controlSize = .regular
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        context.coordinator.attach(to: field)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != prompt { field.placeholderString = prompt }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        private weak var field: NSSearchField?
        private var focusObserver: NSObjectProtocol?

        init(text: Binding<String>) {
            self.text = text
            super.init()
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        func attach(to field: NSSearchField) {
            self.field = field
            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusStationSearch,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let field = self?.field else { return }
                field.window?.makeFirstResponder(field)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            if text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
        }
    }
}

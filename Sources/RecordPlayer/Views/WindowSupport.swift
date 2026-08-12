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

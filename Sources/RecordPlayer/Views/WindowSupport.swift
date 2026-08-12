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

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
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

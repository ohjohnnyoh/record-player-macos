import AppKit
import AVFoundation
import SwiftUI

@main
struct RecordPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var state = AppState()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        Window("Record", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(updateChecker)
                .environment(\.appAccent, state.accent.color)
                .frame(minWidth: 860, minHeight: 560)
                .preferredColorScheme(.dark)
                .task {
                    async let bootstrap: Void = state.bootstrap()
                    async let updates: Void = updateChecker.checkIfNeeded()
                    _ = await (bootstrap, updates)
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appInfo) {
                Button("О программе Record") {
                    presentAboutPanel()
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") {
                    checkForUpdates()
                }
                .disabled(updateChecker.isChecking)
            }

            CommandGroup(after: .textEditing) {
                Button("Поиск") {
                    NotificationCenter.default.post(name: .focusStationSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandGroup(after: .windowArrangement) {
                Button("Мини-плеер") {
                    NSApp.activate(ignoringOtherApps: true)
                    openMiniPlayer()
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
            }

            CommandMenu("Воспроизведение") {
                // Пробел вешаем не через меню, а локальным монитором событий:
                // иначе он перехватывался бы при вводе в поле поиска.
                Button(L10n.string(state.player.state.isActive ? "Пауза" : "Играть")) {
                    state.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Следующая станция") { state.step(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Предыдущая станция") { state.step(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Случайная станция") { state.playRandom() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button(L10n.string(state.player.isMuted ? "Включить звук" : "Выключить звук")) {
                    state.player.isMuted.toggle()
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("Громче") {
                    state.player.volume = min(1, state.player.volume + 0.05)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Тише") {
                    state.player.volume = max(0, state.player.volume - 0.05)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Divider()

                Picker("Качество", selection: $state.quality) {
                    ForEach(StreamQuality.allCases) { Text($0.title).tag($0) }
                }
            }
        }

        Window("Мини-плеер", id: "mini") {
            MiniPlayerView()
                .environmentObject(state)
                .environment(\.appAccent, state.accent.color)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 320, height: 320)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(updateChecker)
                .environment(\.appAccent, state.accent.color)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: state.player.state == .playing ? "dot.radiowaves.left.and.right" : "radio")
        }
        .menuBarExtraStyle(.window)
    }

    private func openMiniPlayer() {
        openWindow(id: "mini")
    }

    @MainActor
    private func presentAboutPanel() {
        let developer = "oh_johnny"
        let text = L10n.format(
            "Плеер для прослушивания радиостанций Radio Record, созданный независимым разработчиком %@",
            developer
        )
        let credits = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        if let range = text.range(of: developer),
           let url = URL(string: "https://x.com/oh_johnny_ai") {
            credits.addAttributes(
                [
                    .link: url,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: NSRange(range, in: text)
            )
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        credits.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: credits.length)
        )

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): ""
        ])
    }

    private func checkForUpdates() {
        Task { @MainActor in
            let result = await updateChecker.checkNow()
            presentUpdateResult(result)
        }
    }

    @MainActor
    private func presentUpdateResult(_ result: UpdateCheckOutcome) {
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch result {
        case let .updateAvailable(release):
            alert.messageText = L10n.format("Доступна версия %@", release.version)
            alert.informativeText = L10n.string(
                "Откройте страницу релиза, чтобы прочитать описание и скачать обновление."
            )
            alert.addButton(withTitle: L10n.string("Открыть страницу релиза"))
            alert.addButton(withTitle: L10n.string("Позже"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }

        case let .upToDate(version):
            alert.messageText = L10n.string("Установлена актуальная версия")
            alert.informativeText = L10n.format("У вас установлена версия %@.", version)
            alert.addButton(withTitle: L10n.string("OK"))
            alert.runModal()

        case .failed:
            alert.alertStyle = .warning
            alert.messageText = L10n.string("Не удалось проверить обновления")
            alert.informativeText = L10n.string(
                "Проверьте подключение к интернету и попробуйте ещё раз."
            )
            alert.addButton(withTitle: L10n.string("OK"))
            alert.runModal()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Окно можно закрыть — музыка продолжит играть, управление остаётся в меню-баре.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }
}

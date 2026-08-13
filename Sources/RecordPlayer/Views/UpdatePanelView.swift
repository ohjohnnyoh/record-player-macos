import AppKit
import SwiftUI

struct UpdatePanelView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var updater: RecordUpdaterController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            content
            Divider().opacity(0.45)
            actions
        }
        .frame(width: 520)
        .modifier(UpdatePanelSurface(accent: accent))
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(requiresExplicitResponse)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 54, height: 54)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 12)
        }
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        switch updater.phase {
        case .checking:
            progressSection(label: L10n.string("Ищем новую версию…"), progress: nil)
        case let .available(release):
            releaseNotes(release)
        case let .downloading(release, progress):
            progressSection(
                label: L10n.format("Загрузка Record %@", release.version),
                progress: progress
            )
        case let .extracting(release, progress):
            progressSection(
                label: L10n.format("Подготовка Record %@", release.version),
                progress: progress
            )
        case let .ready(release):
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("Обновление готово к установке"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(L10n.format("Record %@ будет установлен после перезапуска приложения.", release.version))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        case .installing:
            progressSection(label: L10n.string("Устанавливаем обновление…"), progress: nil)
        case .upToDate:
            statusSection(
                icon: "checkmark.seal.fill",
                title: L10n.string("У вас установлена последняя версия Record"),
                message: currentVersionText
            )
        case let .failed(message):
            statusSection(
                icon: "exclamationmark.triangle.fill",
                title: L10n.string("Не удалось проверить обновления"),
                message: message
            )
        case .hidden:
            EmptyView()
        }
    }

    private func releaseNotes(_ release: RecordUpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Что нового"))
                .font(.system(size: 13, weight: .semibold))

            if release.notes.isEmpty {
                Text(L10n.string("В этой версии улучшены стабильность и качество приложения."))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ScrollView {
                    Text(release.notes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxHeight: 190)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private func progressSection(label: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
            if let progress {
                ProgressView(value: progress)
                    .tint(accent)
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private func statusSection(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            switch updater.phase {
            case let .available(release):
                Button(L10n.string("Пропустить эту версию")) { updater.skipVersion() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button(L10n.string("Напомнить завтра")) { updater.remindTomorrow() }
                Button(release.informationOnly ? L10n.string("Подробнее") : L10n.string("Обновить")) {
                    updater.install()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            case .ready:
                Spacer()
                Button(L10n.string("Позже")) { updater.remindTomorrow() }
                Button(L10n.string("Установить и перезапустить")) { updater.install() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            case .checking, .downloading:
                Spacer()
                Button(L10n.string("Отменить")) { updater.cancelOperation() }
            case .upToDate, .failed:
                Spacer()
                Button(L10n.string("Готово")) { updater.dismissResult() }
                    .buttonStyle(.bordered)
            case .extracting, .installing, .hidden:
                Spacer()
            }
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var title: String {
        switch updater.phase {
        case let .available(release): return L10n.format("Доступен Record %@", release.version)
        case let .ready(release): return L10n.format("Record %@ готов", release.version)
        case .failed: return L10n.string("Обновление Record")
        case .upToDate: return L10n.string("Record обновлён")
        default: return L10n.string("Обновление Record")
        }
    }

    private var subtitle: String {
        switch updater.phase {
        case let .available(release), let .ready(release),
             let .downloading(release, _), let .extracting(release, _),
             let .installing(release):
            return L10n.format("Установлена версия %@", currentVersionNumber) + "  •  " + L10n.format("Новая версия %@", release.version)
        default:
            return currentVersionText
        }
    }

    private var currentVersionNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var currentVersionText: String {
        L10n.format("Версия %@", currentVersionNumber)
    }

    private var requiresExplicitResponse: Bool {
        switch updater.phase {
        case .available, .ready, .extracting, .installing: true
        default: false
        }
    }
}

private struct UpdatePanelSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let accent: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { shape.fill(Theme.opaqueBackground) }
                .overlay { shape.strokeBorder(.white.opacity(0.22), lineWidth: 1) }
        } else if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                content
                    .glassEffect(
                        .regular.tint(accent.opacity(0.06)),
                        in: shape
                    )
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        }
    }
}

struct UpdateSettingsView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var updater: RecordUpdaterController

    var body: some View {
        Form {
            Section(L10n.string("Обновления")) {
                Toggle(
                    L10n.string("Автоматически проверять наличие обновлений"),
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    )
                )
                Toggle(
                    L10n.string("Загружать обновления автоматически"),
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.automaticallyDownloadsUpdates = $0 }
                    )
                )
                .disabled(!updater.automaticallyChecksForUpdates)

                HStack {
                    Button(L10n.string("Проверить сейчас")) { updater.checkForUpdates() }
                    Spacer()
                    Text(lastCheckText)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 470, height: 230)
        .tint(accent)
        .preferredColorScheme(.dark)
    }

    private var lastCheckText: String {
        guard let date = updater.lastUpdateCheckDate else {
            return L10n.string("Проверка ещё не выполнялась")
        }
        return L10n.format(
            "Последняя проверка: %@",
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }
}

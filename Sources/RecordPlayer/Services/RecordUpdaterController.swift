import AppKit
import Combine
import Sparkle

struct RecordUpdateRelease: Equatable {
    let version: String
    let build: String
    let title: String
    let notes: String
    let informationOnly: Bool
    let infoURL: URL?
}

enum RecordUpdatePhase: Equatable {
    case hidden
    case checking
    case available(RecordUpdateRelease)
    case downloading(RecordUpdateRelease, progress: Double?)
    case extracting(RecordUpdateRelease, progress: Double?)
    case ready(RecordUpdateRelease)
    case installing(RecordUpdateRelease)
    case upToDate
    case failed(message: String)

    var isPresented: Bool {
        if case .hidden = self { return false }
        return true
    }
}

/// Единственный координатор обновлений приложения.
///
/// Sparkle отвечает за расписание, проверку EdDSA, загрузку, замену приложения
/// и перезапуск. Record показывает только собственную SwiftUI-панель и передаёт
/// выбор пользователя обратно во фреймворк.
@MainActor
final class RecordUpdaterController: ObservableObject {
    let userDriver: RecordUpdateUserDriver
    let updater: SPUUpdater

    @Published private(set) var startupError: String?
    private var driverObservation: AnyCancellable?

    init(startingUpdater: Bool = true) {
        let userDriver = RecordUpdateUserDriver()
        self.userDriver = userDriver
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
        driverObservation = userDriver.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }

        if startingUpdater {
            do {
                try updater.start()
            } catch {
                startupError = error.localizedDescription
                userDriver.presentConfigurationError(error.localizedDescription)
            }
        }
    }

    var phase: RecordUpdatePhase { userDriver.phase }
    var isPanelPresented: Bool { userDriver.phase.isPresented }
    var canCheckForUpdates: Bool { updater.canCheckForUpdates }
    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else {
            userDriver.showUpdateInFocus()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
        objectWillChange.send()
    }

    func install() { userDriver.install() }
    func remindTomorrow() { userDriver.remindTomorrow() }
    func skipVersion() { userDriver.skipVersion() }
    func dismissResult() { userDriver.dismissResult() }
    func cancelOperation() { userDriver.cancelOperation() }

    func dismissPanelFromSystem() {
        switch phase {
        case .checking, .downloading:
            cancelOperation()
        case .upToDate, .failed:
            dismissResult()
        case .hidden, .available, .extracting, .ready, .installing:
            break
        }
    }
}

/// Пользовательский драйвер Sparkle. Все callbacks одноразовые: после ответа
/// замыкание удаляется, поэтому двойной клик не может отправить два решения.
@MainActor
final class RecordUpdateUserDriver: NSObject, ObservableObject, SPUUserDriver {
    @Published private(set) var phase: RecordUpdatePhase = .hidden

    private var release: RecordUpdateRelease?
    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var acknowledgement: (() -> Void)?
    private var cancellation: (() -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    private static let reminderVersionKey = "updates.reminder.version"
    private static let reminderDateKey = "updates.reminder.date"

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        phase = .checking
        presentApplication()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let release = Self.release(from: appcastItem)

        if !state.userInitiated, shouldPostpone(version: release.version) {
            reply(.dismiss)
            return
        }

        self.release = release
        updateReply = reply
        cancellation = nil

        switch state.stage {
        case .notDownloaded:
            phase = .available(release)
        case .downloaded:
            phase = .ready(release)
        case .installing:
            phase = .installing(release)
        @unknown default:
            phase = .available(release)
        }
        presentApplication()
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard var release else { return }
        let encoding = downloadData.textEncodingName
            .flatMap(String.Encoding.init(ianaCharsetName:)) ?? .utf8
        guard let downloadedNotes = String(data: downloadData.data, encoding: encoding) else { return }
        release = RecordUpdateRelease(
            version: release.version,
            build: release.build,
            title: release.title,
            notes: Self.plainText(from: downloadedNotes),
            informationOnly: release.informationOnly,
            infoURL: release.infoURL
        )
        self.release = release
        replaceRelease(in: phase, with: release)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // Отсутствие заметок не мешает безопасно установить подписанное обновление.
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        self.acknowledgement = acknowledgement
        cancellation = nil
        let cocoaError = error as NSError
        let reason = (cocoaError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        let isCurrentVersion = reason == Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue)
            || reason == Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue)
        phase = isCurrentVersion
            ? .upToDate
            : .failed(message: cocoaError.localizedDescription)
        presentApplication()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        self.acknowledgement = acknowledgement
        cancellation = nil
        phase = .failed(message: error.localizedDescription)
        presentApplication()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        expectedBytes = 0
        receivedBytes = 0
        if let release { phase = .downloading(release, progress: nil) }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
        updateDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        updateDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        if let release { phase = .extracting(release, progress: nil) }
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        if let release { phase = .extracting(release, progress: min(max(progress, 0), 1)) }
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        if let release { phase = .ready(release) }
        presentApplication()
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        // Модальный SwiftUI sheet блокирует стандартное завершение NSApplication.
        // К моменту установки Sparkle уже показывает системный Updater helper,
        // поэтому нашу панель надо убрать и освободить quit event.
        phase = .hidden
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        self.acknowledgement = acknowledgement
        phase = .upToDate
    }

    func dismissUpdateInstallation() {
        clearCallbacks()
        phase = .hidden
    }

    func showUpdateInFocus() {
        presentApplication()
    }

    func install() {
        clearReminder()
        if let infoURL = release?.infoURL, release?.informationOnly == true {
            NSWorkspace.shared.open(infoURL)
            takeUpdateReply()?(.dismiss)
            phase = .hidden
            return
        }

        if let reply = takeReadyReply() {
            phase = .hidden
            // Даём AppKit завершить анимацию закрытия sheet до quit event Sparkle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                reply(.install)
            }
        } else if let reply = takeUpdateReply() {
            if let release { phase = .downloading(release, progress: nil) }
            reply(.install)
        }
    }

    func remindTomorrow() {
        if let release {
            let defaults = UserDefaults.standard
            defaults.set(release.version, forKey: Self.reminderVersionKey)
            defaults.set(Date().addingTimeInterval(24 * 60 * 60), forKey: Self.reminderDateKey)
        }
        if let reply = takeReadyReply() { reply(.dismiss) }
        if let reply = takeUpdateReply() { reply(.dismiss) }
        phase = .hidden
    }

    func skipVersion() {
        clearReminder()
        if let reply = takeReadyReply() { reply(.skip) }
        if let reply = takeUpdateReply() { reply(.skip) }
        phase = .hidden
    }

    func dismissResult() {
        takeAcknowledgement()?()
        phase = .hidden
    }

    func cancelOperation() {
        cancellation?()
        cancellation = nil
        phase = .hidden
    }

    func presentConfigurationError(_ message: String) {
        phase = .failed(message: message)
        presentApplication()
    }

    private func updateDownloadProgress() {
        guard let release else { return }
        let progress: Double? = expectedBytes > 0
            ? min(Double(receivedBytes) / Double(expectedBytes), 1)
            : nil
        phase = .downloading(release, progress: progress)
    }

    private func replaceRelease(in phase: RecordUpdatePhase, with release: RecordUpdateRelease) {
        switch phase {
        case .available: self.phase = .available(release)
        case let .downloading(_, progress): self.phase = .downloading(release, progress: progress)
        case let .extracting(_, progress): self.phase = .extracting(release, progress: progress)
        case .ready: self.phase = .ready(release)
        case .installing: self.phase = .installing(release)
        default: break
        }
    }

    private func shouldPostpone(version: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.reminderVersionKey) == version,
              let date = defaults.object(forKey: Self.reminderDateKey) as? Date else {
            return false
        }
        if date > Date() { return true }
        clearReminder()
        return false
    }

    private func clearReminder() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.reminderVersionKey)
        defaults.removeObject(forKey: Self.reminderDateKey)
    }

    private func takeUpdateReply() -> ((SPUUserUpdateChoice) -> Void)? {
        defer { updateReply = nil }
        return updateReply
    }

    private func takeReadyReply() -> ((SPUUserUpdateChoice) -> Void)? {
        defer { readyReply = nil }
        return readyReply
    }

    private func takeAcknowledgement() -> (() -> Void)? {
        defer { acknowledgement = nil }
        return acknowledgement
    }

    private func clearCallbacks() {
        updateReply = nil
        readyReply = nil
        acknowledgement = nil
        cancellation = nil
    }

    private func presentApplication() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    }

    private static func release(from item: SUAppcastItem) -> RecordUpdateRelease {
        RecordUpdateRelease(
            version: item.displayVersionString,
            build: item.versionString,
            title: item.title ?? "Record \(item.displayVersionString)",
            notes: plainText(from: item.itemDescription ?? ""),
            informationOnly: item.isInformationOnlyUpdate,
            infoURL: item.infoURL
        )
    }

    private static func plainText(from source: String) -> String {
        guard source.contains("<"),
              let data = source.data(using: .utf8),
              let value = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html],
                  documentAttributes: nil
              ).string else {
            return markdownAsPlainText(source)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownAsPlainText(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var line = String(line)
                if line.hasPrefix("#") {
                    line = line.drop(while: { $0 == "#" || $0 == " " }).description
                } else if line.hasPrefix("- ") {
                    line.replaceSubrange(line.startIndex...line.index(after: line.startIndex), with: "• ")
                }
                return line.replacingOccurrences(of: "**", with: "")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String.Encoding {
    init?(ianaCharsetName: String) {
        let encoding = CFStringConvertIANACharSetNameToEncoding(ianaCharsetName as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}

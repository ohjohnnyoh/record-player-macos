import Foundation

struct AppRelease: Codable, Equatable, Sendable {
    let version: String
    let name: String
    let pageURL: URL
}

enum ReleaseFetchResult: Equatable, Sendable {
    case modified(AppRelease, etag: String?)
    case notModified
}

protocol ReleaseFetching {
    func fetchLatestRelease(etag: String?) async throws -> ReleaseFetchResult
}

struct GitHubReleaseClient: ReleaseFetching {
    private static let endpoint = URL(
        string: "https://api.github.com/repos/ohjohnnyoh/record-player-macos/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestRelease(etag: String?) async throws -> ReleaseFetchResult {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Record-macOS", forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            let release = try Self.decodeRelease(from: data)
            return .modified(
                release,
                etag: http.value(forHTTPHeaderField: "ETag")
            )
        case 304:
            return .notModified
        default:
            throw UpdateCheckError.httpStatus(http.statusCode)
        }
    }

    static func decodeRelease(from data: Data) throws -> AppRelease {
        let payload = try JSONDecoder().decode(LatestReleasePayload.self, from: data)
        guard !payload.draft, !payload.prerelease,
              let pageURL = URL(string: payload.htmlURL),
              let version = AppVersion.normalized(payload.tagName)
        else {
            throw UpdateCheckError.invalidResponse
        }

        let name = payload.name?.trimmed.nilIfEmpty ?? "Record \(version)"
        return AppRelease(version: version, name: name, pageURL: pageURL)
    }
}

private struct LatestReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

enum UpdateCheckOutcome: Equatable {
    case updateAvailable(AppRelease)
    case upToDate(currentVersion: String)
    case failed
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let checkInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var availableRelease: AppRelease?
    @Published private(set) var isChecking = false

    private let client: any ReleaseFetching
    private let defaults: UserDefaults
    private let currentVersion: String
    private let now: () -> Date

    init(
        client: any ReleaseFetching = GitHubReleaseClient(),
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0",
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.now = now

        if let cached = Self.loadCachedRelease(from: defaults),
           AppVersion.isNewer(cached.version, than: currentVersion) {
            availableRelease = cached
        }
    }

    func checkIfNeeded() async {
        guard shouldRunBackgroundCheck else { return }
        _ = await checkNow()
    }

    func checkNow() async -> UpdateCheckOutcome {
        guard !isChecking else {
            if let availableRelease { return .updateAvailable(availableRelease) }
            return .upToDate(currentVersion: currentVersion)
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let response = try await client.fetchLatestRelease(etag: storedETag)
            let release: AppRelease

            switch response {
            case let .modified(fetched, etag):
                release = fetched
                save(release: fetched, etag: etag)
            case .notModified:
                guard let cached = Self.loadCachedRelease(from: defaults) else {
                    // Без закэшированного ответа один ETag бесполезен. Следующая
                    // проверка должна получить полный JSON, поэтому сбрасываем его.
                    defaults.removeObject(forKey: Keys.etag)
                    throw UpdateCheckError.missingCachedRelease
                }
                release = cached
            }

            defaults.set(now(), forKey: Keys.lastCheckDate)

            if AppVersion.isNewer(release.version, than: currentVersion) {
                availableRelease = release
                return .updateAvailable(release)
            }

            availableRelease = nil
            return .upToDate(currentVersion: currentVersion)
        } catch {
            // Фоновая проверка не должна мешать запуску и воспроизведению.
            // Ручная команда показывает пользователю локализованное сообщение.
            return .failed
        }
    }

    private var shouldRunBackgroundCheck: Bool {
        guard !isChecking else { return false }
        guard let lastCheck = defaults.object(forKey: Keys.lastCheckDate) as? Date else {
            return true
        }
        return now().timeIntervalSince(lastCheck) >= Self.checkInterval
    }

    private var storedETag: String? {
        defaults.string(forKey: Keys.etag)
    }

    private func save(release: AppRelease, etag: String?) {
        if let data = try? JSONEncoder().encode(release) {
            defaults.set(data, forKey: Keys.cachedRelease)
        }
        if let etag, !etag.isEmpty {
            defaults.set(etag, forKey: Keys.etag)
        } else {
            defaults.removeObject(forKey: Keys.etag)
        }
    }

    private static func loadCachedRelease(from defaults: UserDefaults) -> AppRelease? {
        guard let data = defaults.data(forKey: Keys.cachedRelease) else { return nil }
        return try? JSONDecoder().decode(AppRelease.self, from: data)
    }

    private enum Keys {
        static let lastCheckDate = "updates.lastCheckDate"
        static let etag = "updates.latestReleaseETag"
        static let cachedRelease = "updates.cachedLatestRelease"
    }
}

enum AppVersion {
    static func normalized(_ value: String) -> String? {
        var value = value.trimmed
        if value.first?.lowercased() == "v" { value.removeFirst() }
        value = String(value.split(separator: "-", maxSplits: 1)[0])

        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && Int($0) != nil })
        else { return nil }

        return components.map(String.init).joined(separator: ".")
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = components(candidate),
              let current = components(current)
        else { return false }

        let count = max(candidate.count, current.count)
        for index in 0..<count {
            let lhs = index < candidate.count ? candidate[index] : 0
            let rhs = index < current.count ? current[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func components(_ value: String) -> [Int]? {
        guard let normalized = normalized(value) else { return nil }
        return normalized.split(separator: ".").compactMap { Int($0) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case missingCachedRelease
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse, .missingCachedRelease:
            "GitHub returned an invalid update response."
        case let .httpStatus(code):
            "GitHub returned HTTP status \(code)."
        }
    }
}

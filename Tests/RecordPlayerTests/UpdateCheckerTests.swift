import Foundation
import Testing
@testable import RecordPlayer

@Suite("App version comparison")
struct AppVersionTests {
    @Test func recognizesNewerVersions() {
        #expect(AppVersion.isNewer("v1.5", than: "1.4"))
        #expect(AppVersion.isNewer("1.10", than: "1.9.9"))
        #expect(AppVersion.isNewer("2.0.0", than: "1.99.99"))
    }

    @Test func treatsTrailingZeroesAsEqual() {
        #expect(!AppVersion.isNewer("v1.5.0", than: "1.5"))
        #expect(!AppVersion.isNewer("1.5", than: "1.5.0"))
    }

    @Test func rejectsOlderAndInvalidVersions() {
        #expect(!AppVersion.isNewer("1.4", than: "1.5"))
        #expect(!AppVersion.isNewer("latest", than: "1.5"))
        #expect(AppVersion.normalized("v1.6.0-beta") == "1.6.0")
    }
}

@Suite("GitHub release decoding")
struct GitHubReleaseDecodingTests {
    @Test func decodesPublishedRelease() throws {
        let json = """
        {
          "tag_name": "v1.6",
          "name": "Record 1.6",
          "html_url": "https://github.com/ohjohnnyoh/record-player-macos/releases/tag/v1.6",
          "draft": false,
          "prerelease": false
        }
        """.data(using: .utf8)!

        let release = try GitHubReleaseClient.decodeRelease(from: json)
        #expect(release.version == "1.6")
        #expect(release.name == "Record 1.6")
        #expect(release.pageURL.absoluteString.hasSuffix("/v1.6"))
    }
}

@MainActor
@Suite("Update checker")
struct UpdateCheckerTests {
    @Test func manualCheckFindsNewVersion() async throws {
        let defaults = try makeDefaults()
        let release = sampleRelease(version: "1.6")
        let client = FakeReleaseClient(result: .success(.modified(release, etag: "test-etag")))
        let checker = UpdateChecker(
            client: client,
            defaults: defaults,
            currentVersion: "1.5",
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let outcome = await checker.checkNow()

        #expect(outcome == .updateAvailable(release))
        #expect(checker.availableRelease == release)
        #expect(client.callCount == 1)
    }

    @Test func backgroundCheckRespectsDailyInterval() async throws {
        let defaults = try makeDefaults()
        let now = Date(timeIntervalSince1970: 100_000)
        defaults.set(now.addingTimeInterval(-60), forKey: "updates.lastCheckDate")
        let client = FakeReleaseClient(
            result: .success(.modified(sampleRelease(version: "1.6"), etag: nil))
        )
        let checker = UpdateChecker(
            client: client,
            defaults: defaults,
            currentVersion: "1.5",
            now: { now }
        )

        await checker.checkIfNeeded()

        #expect(client.callCount == 0)
    }

    @Test func notModifiedResponseUsesPersistentCache() async throws {
        let defaults = try makeDefaults()
        let release = sampleRelease(version: "1.6")
        let firstClient = FakeReleaseClient(
            result: .success(.modified(release, etag: "cached-etag"))
        )
        let first = UpdateChecker(
            client: firstClient,
            defaults: defaults,
            currentVersion: "1.5"
        )
        _ = await first.checkNow()

        let secondClient = FakeReleaseClient(result: .success(.notModified))
        let second = UpdateChecker(
            client: secondClient,
            defaults: defaults,
            currentVersion: "1.5"
        )

        let outcome = await second.checkNow()

        #expect(outcome == .updateAvailable(release))
        #expect(secondClient.receivedETag == "cached-etag")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "RecordPlayerTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    private func sampleRelease(version: String) -> AppRelease {
        AppRelease(
            version: version,
            name: "Record \(version)",
            pageURL: URL(
                string: "https://github.com/ohjohnnyoh/record-player-macos/releases/tag/v\(version)"
            )!
        )
    }
}

private final class FakeReleaseClient: ReleaseFetching {
    let result: Result<ReleaseFetchResult, Error>
    private(set) var callCount = 0
    private(set) var receivedETag: String?

    init(result: Result<ReleaseFetchResult, Error>) {
        self.result = result
    }

    func fetchLatestRelease(etag: String?) async throws -> ReleaseFetchResult {
        callCount += 1
        receivedETag = etag
        return try result.get()
    }
}

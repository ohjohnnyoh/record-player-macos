import Foundation
import Testing
@testable import RecordPlayer

@Suite("Update presentation state")
struct UpdatePresentationTests {
    private let release = RecordUpdateRelease(
        version: "1.7",
        build: "8",
        title: "Record 1.7",
        notes: "Automatic updates",
        informationOnly: false,
        infoURL: nil
    )

    @Test func onlyHiddenStateDismissesTheSheet() {
        #expect(!RecordUpdatePhase.hidden.isPresented)
        #expect(RecordUpdatePhase.checking.isPresented)
        #expect(RecordUpdatePhase.available(release).isPresented)
        #expect(RecordUpdatePhase.downloading(release, progress: 0.5).isPresented)
        #expect(RecordUpdatePhase.extracting(release, progress: nil).isPresented)
        #expect(RecordUpdatePhase.ready(release).isPresented)
        #expect(RecordUpdatePhase.installing(release).isPresented)
        #expect(RecordUpdatePhase.upToDate.isPresented)
        #expect(RecordUpdatePhase.failed(message: "Network").isPresented)
    }

    @Test func releaseIdentityContainsDisplayAndBuildVersions() {
        #expect(release.version == "1.7")
        #expect(release.build == "8")
        #expect(!release.informationOnly)
    }
}

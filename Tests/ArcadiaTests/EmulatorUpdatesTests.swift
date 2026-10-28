import Foundation
import Testing
@testable import Arcadia

@Suite struct EmulatorUpdatesTests {
    private func installed(_ version: String, revision: String? = nil) -> Installation {
        Installation(version: version, payload: "App.app", installedAt: .now, revision: revision)
    }

    @Test func checksAtMostOnceADay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(EmulatorUpdates.isCheckDue(lastCheck: nil, now: now))
        #expect(!EmulatorUpdates.isCheckDue(lastCheck: now.addingTimeInterval(-60), now: now))
        #expect(!EmulatorUpdates.isCheckDue(lastCheck: now.addingTimeInterval(-23 * 60 * 60), now: now))
        #expect(EmulatorUpdates.isCheckDue(lastCheck: now.addingTimeInterval(-24 * 60 * 60), now: now))
        // A clock set back never blocks checks for good.
        #expect(EmulatorUpdates.isCheckDue(lastCheck: now.addingTimeInterval(60 * 60), now: now))
    }

    @Test func readsVersionNumbersFromTags() {
        #expect(EmulatorUpdates.numbers("v1.20.4") == [1, 20, 4])
        #expect(EmulatorUpdates.numbers("1.19.1") == [1, 19, 1])
        #expect(EmulatorUpdates.numbers("v0.1-12083") == [0, 1, 12083])
        #expect(EmulatorUpdates.numbers("v.0.20.0") == [0, 20])
        #expect(EmulatorUpdates.numbers("2609a") == [2609])
        #expect(EmulatorUpdates.numbers("build-ffeb16fe1ec7a6a62ac317270dab20197b060ef9") == nil)
        #expect(EmulatorUpdates.numbers("latest") == nil)
        #expect(EmulatorUpdates.numbers("Pre-release-shadPS4-2026-10-28-78dd81fc") == nil)
    }

    @Test func comparesVersionNumbers() {
        #expect(EmulatorUpdates.isNewer(AvailableVersion(version: "v1.20.4"), than: installed("v1.20.3")))
        #expect(EmulatorUpdates.isNewer(AvailableVersion(version: "v1.20.10"), than: installed("v1.20.9")))
        #expect(EmulatorUpdates.isNewer(AvailableVersion(version: "v2.6"), than: installed("v2.5.1")))
        #expect(EmulatorUpdates.isNewer(AvailableVersion(version: "2609a"), than: installed("2609")))
        #expect(EmulatorUpdates.isNewer(AvailableVersion(version: "v0.1-12083"), than: installed("v0.1-9226")))
        // Older or the same version never counts as an update.
        #expect(!EmulatorUpdates.isNewer(AvailableVersion(version: "v1.20.3"), than: installed("v1.20.4")))
        #expect(!EmulatorUpdates.isNewer(AvailableVersion(version: "v1.20"), than: installed("1.20.0")))
        #expect(!EmulatorUpdates.isNewer(AvailableVersion(version: "2609"), than: installed("2609a")))
        #expect(!EmulatorUpdates.isNewer(AvailableVersion(version: "1.19.1"), than: installed("1.19.1")))
    }

    @Test func treatsOtherTagsAsNewerWhenTheyChange() {
        #expect(EmulatorUpdates.isNewer(AvailableVersion(version: "build-ffeb16fe"), than: installed("build-ffc50905")))
        #expect(!EmulatorUpdates.isNewer(AvailableVersion(version: "build-ffeb16fe"), than: installed("build-ffeb16fe")))
    }

    @Test func rollingTagsCompareByRevision() {
        #expect(EmulatorUpdates.isNewer(AvailableVersion(version: "latest", revision: "2"), than: installed("latest", revision: "1")))
        #expect(!EmulatorUpdates.isNewer(AvailableVersion(version: "latest", revision: "1"), than: installed("latest", revision: "1")))
        // Installs from before revisions were recorded only compare versions.
        #expect(!EmulatorUpdates.isNewer(AvailableVersion(version: "latest", revision: "2"), than: installed("latest")))
    }

    @Test func oldInstallRecordsStillDecode() throws {
        let json = #"{"version":"v1.0","payload":"App.app","installedAt":0}"#
        let installation = try JSONDecoder().decode(Installation.self, from: Data(json.utf8))
        #expect(installation.version == "v1.0")
        #expect(installation.revision == nil)
    }
}

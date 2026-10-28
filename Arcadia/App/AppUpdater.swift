import SwiftUI
import Sparkle

/// Keeps Arcadia itself up to date with Sparkle: a daily background check against the appcast
/// published with each release, plus "Check for Updates…" in the app menu.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var updater: SPUUpdater { controller.updater }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// Development builds only check when asked, so they are never replaced by a release.
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        #if DEBUG
        if updateCheck == .updatesInBackground { throw CancellationError() }
        #endif
    }
}

/// "Check for Updates…", disabled while Sparkle is already checking.
struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    @State private var canCheck = true

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}

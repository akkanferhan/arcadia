import Foundation

/// The newest build of an emulator that its download source offers.
struct AvailableVersion: Codable, Equatable {
    let version: String
    /// Identifies the exact download (a GitHub asset id, a commit hash) when the version alone
    /// does not, such as rolling tags like DuckStation's `latest`.
    var revision: String?
}

/// When to look for emulator updates, and whether a found version is newer than the installed one.
enum EmulatorUpdates {
    /// Background checks run at most this often.
    static let interval: TimeInterval = 24 * 60 * 60

    static func isCheckDue(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        // A clock set back past the last check counts as due, so checks never stall.
        return now.timeIntervalSince(lastCheck) >= interval || now < lastCheck
    }

    /// Whether `available` should replace `installed`. Release tags are not always version
    /// numbers (`build-<hash>`, `latest`), so a different tag counts as newer unless both are
    /// version numbers and the installed one is higher.
    static func isNewer(_ available: AvailableVersion, than installed: Installation) -> Bool {
        if available.version != installed.version {
            if let new = numbers(available.version), let old = numbers(installed.version) {
                // Dolphin marks hotfixes with a letter: 2609a follows 2609.
                if new == old { return letter(available.version) > letter(installed.version) }
                return old.lexicographicallyPrecedes(new)
            }
            return true
        }
        guard let new = available.revision, let old = installed.revision else { return false }
        return new != old
    }

    /// The numeric parts of a version-like tag: `v1.20.4` → [1, 20, 4], `v0.1-12083` → [0, 1, 12083],
    /// `2609a` → [2609]. Nil for tags that are not versions, such as `build-ffeb16fe`.
    static func numbers(_ tag: String) -> [Int]? {
        guard let match = tag.firstMatch(of: #/^[vV]?\.?(\d+(?:[.\-]\d+)*)[a-z]?$/#) else { return nil }
        var parts = match.1.split(whereSeparator: { $0 == "." || $0 == "-" }).compactMap { Int($0) }
        // 1.20 and 1.20.0 are the same version.
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        return parts
    }

    private static func letter(_ tag: String) -> String {
        guard let last = tag.last, last.isLetter else { return "" }
        return String(last)
    }
}

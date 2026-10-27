import Foundation

/// A game found in the library folder.
struct Game: Identifiable, Hashable {
    /// The file or folder the game lives in.
    let url: URL
    let systemID: String

    var id: String { url.path }
    var system: GameSystem { GameSystem.with(id: systemID)! }

    /// The file name without its extension, as used by No-Intro/Redump sets and box art.
    var fileTitle: String { url.deletingPathExtension().lastPathComponent }

    /// A tidy title: region and revision tags such as "(USA) (Rev 1)" are removed.
    var title: String {
        let cleaned = fileTitle
            .replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fileTitle : cleaned
    }

    /// Region tag shown under the title, e.g. "USA" or "Europe".
    var region: String? {
        guard let match = fileTitle.range(of: #"\((USA|Europe|Japan|World|Turkey|Germany|France|Spain|Italy|Korea|Brazil)[^\)]*\)"#,
                                          options: .regularExpression) else { return nil }
        return String(fileTitle[match].dropFirst().dropLast())
    }
}

/// What Arcadia remembers about a game between launches.
struct GameRecord: Codable, Equatable {
    var favorite = false
    var lastPlayed: Date?
    var playTime: TimeInterval = 0
}

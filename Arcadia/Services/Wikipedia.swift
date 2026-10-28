import Foundation

/// The opening paragraph of a game's Wikipedia article.
struct WikiSummary: Codable, Equatable {
    let title: String
    let extract: String
    let url: URL
    /// Wikipedia language code, e.g. "en" or "tr".
    let language: String
}

/// Game descriptions from Wikipedia's keyless REST API, in the user's language when an article exists.
actor Wikipedia {
    static let shared = Wikipedia()

    private struct Entry: Codable {
        var summary: WikiSummary?
        var checked: Date
    }

    private let file: URL
    private var cache: [String: Entry]?
    private var inFlight: [String: Task<WikiSummary?, Never>] = [:]
    /// A miss is looked up again after this long, in case an article was written.
    private let missAge: TimeInterval = 14 * 24 * 3600

    init(file: URL = Paths.metadata.appendingPathComponent("wikipedia.json")) {
        self.file = file
    }

    func summary(for game: Game, languages: [String] = Wikipedia.preferredLanguages) async -> WikiSummary? {
        let title = Self.searchTitle(game.title)
        let key = "\(languages.joined(separator: ","))|\(game.systemID)|\(title)"
        if let entry = loadCache()[key], entry.summary != nil || Date.now.timeIntervalSince(entry.checked) < missAge {
            return entry.summary
        }
        if let task = inFlight[key] { return await task.value }

        let task = Task { () -> (WikiSummary?, Bool) in
            var reachable = false
            for language in languages {
                switch await Self.lookUp(title, language: language) {
                case .found(let summary): return (summary, true)
                case .notFound: reachable = true
                case .offline: continue
                }
            }
            return (nil, reachable)
        }
        let shared = Task { await task.value.0 }
        inFlight[key] = shared
        let (summary, answered) = await task.value
        inFlight[key] = nil
        // Only remember a miss when Wikipedia actually answered.
        if summary != nil || answered {
            cache?[key] = Entry(summary: summary, checked: .now)
            saveCache()
        }
        return summary
    }

    /// The user's language first, then English.
    nonisolated static var preferredLanguages: [String] {
        let code = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        return code.map { $0 == "en" ? ["en"] : [$0, "en"] } ?? ["en"]
    }

    // MARK: Lookup

    private enum Outcome {
        case found(WikiSummary)
        case notFound
        case offline
    }

    private static func lookUp(_ title: String, language: String) async -> Outcome {
        var queries = [title]
        if let suffix = videoGame[language] { queries.insert("\(title) \(suffix)", at: 0) }
        var seen: Set<String> = []
        for query in queries {
            guard let pages = await search(query, language: language) else { return .offline }
            for page in rank(pages, for: title) where !seen.contains(page.key) {
                seen.insert(page.key)
                guard let summary = await summary(page.key, language: language) else { return .offline }
                if let summary { return .found(summary) }
            }
        }
        return .notFound
    }

    struct SearchPage: Decodable, Equatable {
        let key: String
        let title: String
        var description: String?
    }

    private static func search(_ query: String, language: String) async -> [SearchPage]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(language).wikipedia.org"
        components.path = "/w/rest.php/v1/search/page"
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "6")]
        struct Response: Decodable { let pages: [SearchPage] }
        guard let url = components.url, let data = await fetch(url) else { return nil }
        return (try? JSONDecoder().decode(Response.self, from: data))?.pages ?? []
    }

    /// Nil when offline; `.some(nil)` when the page is not a usable article.
    private static func summary(_ key: String, language: String) async -> WikiSummary?? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(language).wikipedia.org"
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        components.percentEncodedPath = "/api/rest_v1/page/summary/"
            + (key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)
        struct Response: Decodable {
            struct Links: Decodable {
                struct Page: Decodable { let page: URL }
                let desktop: Page
            }
            let type: String
            let title: String
            let extract: String
            let content_urls: Links
        }
        guard let url = components.url, let data = await fetch(url) else { return nil }
        guard let page = try? JSONDecoder().decode(Response.self, from: data), page.type == "standard",
              !page.extract.isEmpty else { return .some(nil) }
        return WikiSummary(title: page.title, extract: page.extract, url: page.content_urls.desktop.page, language: language)
    }

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Wikipedia asks API clients to identify themselves.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.setValue("Arcadia/\(version) (macOS emulator frontend; https://www.ferhanakkan.dev)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // A missing page is an answer; server errors count as offline.
        if status == 404 { return Data("{}".utf8) }
        return status == 200 ? data : nil
    }

    // MARK: Matching

    /// "video game" in the languages Arcadia speaks, to steer the search toward games.
    static let videoGame: [String: String] = [
        "en": "video game", "tr": "video oyunu", "de": "Computerspiel", "fr": "jeu vidéo", "es": "videojuego",
        "it": "videogioco", "pt": "jogo eletrônico", "nl": "computerspel", "ja": "ゲーム", "ko": "게임",
        "zh": "电子游戏", "ru": "компьютерная игра", "pl": "gra komputerowa",
    ]

    /// Turns a No-Intro title into the way Wikipedia writes it:
    /// "Legend of Zelda, The - A Link to the Past" becomes "The Legend of Zelda: A Link to the Past".
    static func searchTitle(_ title: String) -> String {
        let parts = title.components(separatedBy: " - ").map { part -> String in
            for article in ["The", "A", "An"] where part.hasSuffix(", \(article)") {
                return "\(article) " + part.dropLast(article.count + 2)
            }
            return part
        }
        return parts.joined(separator: ": ")
    }

    /// Search results whose title names the game: exact titles first, game articles before others.
    /// A longer or shorter title only counts when the article is about a game.
    static func rank(_ pages: [SearchPage], for title: String) -> [SearchPage] {
        let wanted = normalized(title)
        guard !wanted.isEmpty else { return [] }
        let exact = pages.filter { normalized($0.title) == wanted }
        let partial = pages.filter { page in
            let found = normalized(page.title)
            return found != wanted && (found.hasPrefix(wanted + " ") || wanted.hasPrefix(found + " ")) && looksLikeGame(page)
        }
        // "Crash Bandicoot (video game)" before the franchise's "Crash Bandicoot", then other game articles.
        let noted = exact.filter { page in
            page.title.range(of: #"\(.*\)"#, options: .regularExpression).map { mentionsGame(String(page.title[$0])) } ?? false
        }
        let games = exact.filter { looksLikeGame($0) && !noted.contains($0) }
        let others = exact.filter { !looksLikeGame($0) }
        return noted + games + others + partial
    }

    private static func looksLikeGame(_ page: SearchPage) -> Bool {
        mentionsGame((page.description ?? "") + " " + page.title)
    }

    private static func mentionsGame(_ text: String) -> Bool {
        let text = text.lowercased()
        return ["game", "spiel", "jeu", "juego", "gioco", "oyun", "jogo", "ゲーム", "게임", "游戏", "игра"]
            .contains { text.contains($0) }
    }

    /// Lower-case words without punctuation or parenthesised notes such as "(1991 video game)".
    static func normalized(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s*\([^\)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&", with: " and ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: Cache

    private func loadCache() -> [String: Entry] {
        if let cache { return cache }
        let loaded = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        cache = loaded
        return loaded
    }

    private func saveCache() {
        guard let cache, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

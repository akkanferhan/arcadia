import Foundation

/// What the libretro database knows about a game.
struct GameInfo: Codable, Equatable {
    var genre: String?
    var developer: String?
    var publisher: String?
    var year: Int?
    /// The most players the game supports at once.
    var players: Int?

    var isEmpty: Bool { self == GameInfo() }

    /// Fills the fields this value is missing from another.
    func filling(from other: GameInfo) -> GameInfo {
        GameInfo(genre: genre ?? other.genre, developer: developer ?? other.developer,
                 publisher: publisher ?? other.publisher, year: year ?? other.year, players: players ?? other.players)
    }
}

/// The libretro-database `metadat` files of one system, merged and keyed by game name.
struct MetadataIndex: Codable, Equatable {
    /// One `metadat` folder and the key its entries use.
    struct Field {
        let folder: String
        let key: String
        let apply: (inout GameInfo, String) -> Void
    }

    static let fields: [Field] = [
        Field(folder: "genre", key: "genre") { $0.genre = $1 },
        Field(folder: "developer", key: "developer") { $0.developer = $1 },
        Field(folder: "publisher", key: "publisher") { $0.publisher = $1 },
        Field(folder: "releaseyear", key: "releaseyear") { info, value in
            info.year = Int(value.prefix(4)).flatMap { (1970...2100).contains($0) ? $0 : nil }
        },
        Field(folder: "maxusers", key: "users") { info, value in
            info.players = Int(value).flatMap { $0 > 0 ? $0 : nil }
        },
    ]

    /// Keyed by the lower-cased No-Intro/Redump name, e.g. "super mario world (usa)".
    private(set) var entries: [String: GameInfo] = [:]
    var fetched = Date.now
    /// Entries grouped by tidied title, so other releases of a game can fill gaps.
    private var titles: [String: [Sibling]] = [:]

    private struct Sibling: Equatable {
        let name: String
        let region: String?
        let info: GameInfo
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([String: GameInfo].self, forKey: .entries)
        fetched = try container.decode(Date.self, forKey: .fetched)
        groupTitles()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(fetched, forKey: .fetched)
    }

    private enum CodingKeys: String, CodingKey { case entries, fetched }

    static func == (lhs: MetadataIndex, rhs: MetadataIndex) -> Bool { lhs.entries == rhs.entries }

    /// Merges one `metadat` file into the index.
    mutating func add(_ dat: String, field: Field) {
        for entry in DatFile.parse(dat) {
            guard let value = entry.fields[field.key] else { continue }
            for name in entry.names {
                field.apply(&entries[name.lowercased(), default: GameInfo()], value)
            }
        }
        groupTitles()
    }

    /// Exact name first; then other releases of the same game fill the gaps, the same region first.
    func info(for game: Game) -> GameInfo? {
        let exact = entries[game.fileTitle.lowercased()] ?? GameInfo()
        let region = game.region?.lowercased()
        let siblings = titles[Self.titleKey(game.title), default: []]
            .sorted { lhs, rhs in
                let left = lhs.region == region, right = rhs.region == region
                return left != right ? left : lhs.name < rhs.name
            }
        let merged = siblings.reduce(exact) { $0.filling(from: $1.info) }
        return merged.isEmpty ? nil : merged
    }

    private mutating func groupTitles() {
        var titles: [String: [Sibling]] = [:]
        for (name, info) in entries {
            let region = name.range(of: #"\((usa|europe|japan|world|turkey|germany|france|spain|italy|korea|brazil)[^\)]*\)"#,
                                    options: [.regularExpression, .caseInsensitive])
                .map { String(name[$0].dropFirst().dropLast()).lowercased() }
            titles[Self.titleKey(Game.tidy(name)), default: []].append(Sibling(name: name, region: region, info: info))
        }
        self.titles = titles
    }

    /// Lower-cased letters and digits only, so "Sonic The Hedgehog" matches "Sonic the Hedgehog".
    static func titleKey(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}

/// Reads clrmamepro-style DAT files as used by libretro-database.
enum DatFile {
    struct Entry: Equatable {
        /// Plain values of the game block, such as `comment`, `genre` or `users`.
        var fields: [String: String] = [:]
        /// File names from the block's `rom ( name ... )` lines, without extensions.
        var romNames: [String] = []

        /// Every name the game can be found by: its comment, name and rom names.
        var names: [String] {
            var names: [String] = []
            for name in [fields["comment"], fields["name"]].compactMap({ $0 }) + romNames
            where !name.isEmpty && !names.contains(name) {
                names.append(name)
            }
            return names
        }
    }

    static func parse(_ text: String) -> [Entry] {
        let tokens = tokenize(text)
        var entries: [Entry] = []
        var index = 0
        while index < tokens.count {
            // Top level: `word ( ... )`; only `game` blocks matter.
            guard case .word(let word) = tokens[index], index + 1 < tokens.count, tokens[index + 1] == .open else {
                index += 1
                continue
            }
            index += 2
            var entry = Entry()
            var depth = 1
            var block = ""
            while index < tokens.count, depth > 0 {
                switch tokens[index] {
                case .open:
                    depth += 1
                case .close:
                    depth -= 1
                    if depth == 1 { block = "" }
                case .word(let key), .string(let key):
                    // A key followed by `(` opens a block such as `rom ( ... )`.
                    if index + 1 < tokens.count, tokens[index + 1] == .open {
                        if depth == 1 { block = key }
                    } else if index + 1 < tokens.count, case .word = tokens[index], let value = tokens[index + 1].text {
                        if depth == 1 {
                            if entry.fields[key] == nil { entry.fields[key] = value }
                        } else if block == "rom", key == "name" {
                            entry.romNames.append((value as NSString).deletingPathExtension)
                        }
                        index += 1
                    }
                }
                index += 1
            }
            if word == "game" { entries.append(entry) }
        }
        return entries
    }

    private enum Token: Equatable {
        case open, close
        case word(String)
        case string(String)

        var text: String? {
            switch self {
            case .word(let text), .string(let text): text
            default: nil
            }
        }
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var scalars = text.unicodeScalars.makeIterator()
        var word = ""
        func flush() {
            if !word.isEmpty { tokens.append(.word(word)); word = "" }
        }
        while let scalar = scalars.next() {
            switch scalar {
            case "(":
                flush(); tokens.append(.open)
            case ")":
                flush(); tokens.append(.close)
            case "\"":
                flush()
                var string = ""
                while let next = scalars.next(), next != "\"" { string.unicodeScalars.append(next) }
                tokens.append(.string(string))
            case " ", "\t", "\n", "\r":
                flush()
            default:
                word.unicodeScalars.append(scalar)
            }
        }
        flush()
        return tokens
    }
}

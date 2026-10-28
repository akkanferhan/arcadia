import Foundation

/// Works out which system a file or folder belongs to, from its extension and, for
/// ambiguous ones (.iso, .bin, .cue, .zip, …), from the bytes the console itself checks.
enum GameIdentifier {
    struct Match {
        let systemID: String
        /// Files that must sit next to the game, such as the tracks a .cue sheet lists.
        var companions: [URL] = []
        /// Decided from folder names only; shown for review.
        var guessed = false
    }

    enum Result {
        case game(Match)
        /// Looks like a game, but the system could not be told; the player picks it.
        case unknown
        /// Not a game, or part of another game (a .bin listed by a .cue).
        case ignore
    }

    private static let byExtension: [String: String] = [
        "sfc": "snes", "smc": "snes", "nes": "nes", "fds": "nes", "unf": "nes",
        "n64": "n64", "z64": "n64", "v64": "n64", "gb": "gb", "gbc": "gbc", "gba": "gba", "nds": "nds",
        "3ds": "3ds", "cci": "3ds", "cxi": "3ds", "3dsx": "3ds",
        "md": "megadrive", "gen": "megadrive", "smd": "megadrive", "sms": "mastersystem", "gg": "gamegear",
        "pce": "pcengine", "a26": "atari2600", "gdi": "dreamcast", "cdi": "dreamcast",
        "wbfs": "wii", "wad": "wii", "gcm": "gc", "wua": "wiiu", "wud": "wiiu", "wux": "wiiu",
        "xiso": "xbox", "cso": "psp",
    ]
    /// Extensions worth opening to look inside.
    private static let ambiguous: Set<String> = ["iso", "bin", "cue", "chd", "zip", "7z", "rvz", "gcz", "ciso", "pbp", "zso", "img"]

    static func isCandidate(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return byExtension[ext] != nil || ambiguous.contains(ext)
    }

    // MARK: Folders (PS3, PS4, PS5)

    /// Installed PlayStation games are folders; returns the system for one, if it is a game.
    static func identifyFolder(_ folder: URL) -> String? {
        func has(_ path: String) -> Bool {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path)
        }
        if has("PS3_GAME/PARAM.SFO") || (has("PARAM.SFO") && has("USRDIR")) { return "ps3" }
        if has("eboot.bin") || has("EBOOT.BIN") {
            if has("sce_sys/param.json") { return "ps5" }
            if has("sce_sys/param.sfo") { return "ps4" }
        }
        return nil
    }

    // MARK: Files

    static func identify(_ file: URL) -> Result {
        let ext = file.pathExtension.lowercased()
        if let system = byExtension[ext] { return .game(Match(systemID: system)) }

        switch ext {
        case "iso", "img":
            if let system = DiscImage(file, sectorSize: 2048, dataOffset: 0)?.system { return .game(Match(systemID: system)) }
            if let system = DiscImage(file, sectorSize: 2352, dataOffset: 16)?.system { return .game(Match(systemID: system)) }
            return guess(file)
        case "cue":
            return identifyCue(file)
        case "bin":
            // Tracks of a .cue sheet are added with their cue.
            if isListedByCue(file) { return .ignore }
            if let header = read(file, at: 0x100, count: 4), header == Data("SEGA".utf8) {
                return .game(Match(systemID: "megadrive"))
            }
            if let system = DiscImage(file, sectorSize: 2352, dataOffset: 16)?.system ?? DiscImage(file, sectorSize: 2352, dataOffset: 24)?.system {
                return .game(Match(systemID: system))
            }
            return guess(file)
        case "rvz", "gcz", "ciso":
            // RVZ/WIA keep the disc header uncompressed near the start of the file.
            if let head = read(file, at: 0, count: 4096) {
                if head.range(of: Data([0x5D, 0x1C, 0x9E, 0xA3])) != nil { return .game(Match(systemID: "wii")) }
                if head.range(of: Data([0xC2, 0x33, 0x9F, 0x3D])) != nil { return .game(Match(systemID: "gc")) }
            }
            return guess(file)
        case "pbp":
            // PS1 games converted for PSP keep a "PSISOIMG" image inside.
            if let head = read(file, at: 0, count: 1 << 20), head.range(of: Data("PSISOIMG".utf8)) != nil
                || head.range(of: Data("PSTITLEIMG".utf8)) != nil {
                return .game(Match(systemID: "ps1"))
            }
            return .game(Match(systemID: "psp"))
        case "zip", "7z":
            return identifyArchive(file)
        case "chd", "zso":
            return guess(file)
        default:
            return .ignore
        }
    }

    // MARK: Cue sheets

    private static func cueTracks(_ cue: URL) -> [URL] {
        guard let text = (try? String(contentsOf: cue, encoding: .utf8)) ?? (try? String(contentsOf: cue, encoding: .isoLatin1)) else {
            return []
        }
        return text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("FILE"), let first = trimmed.firstIndex(of: "\""),
                  let last = trimmed.lastIndex(of: "\""), first < last else { return nil }
            return cue.deletingLastPathComponent().appendingPathComponent(String(trimmed[trimmed.index(after: first)..<last]))
        }
    }

    private static func identifyCue(_ cue: URL) -> Result {
        let tracks = cueTracks(cue)
        guard let data = tracks.first, FileManager.default.fileExists(atPath: data.path) else { return .ignore }
        for offset: UInt64 in [16, 24] {
            if let system = DiscImage(data, sectorSize: 2352, dataOffset: offset)?.system {
                return .game(Match(systemID: system, companions: tracks))
            }
        }
        if case .game(var match) = guess(cue) {
            match.companions = tracks
            return .game(match)
        }
        return .unknown
    }

    private static func isListedByCue(_ bin: URL) -> Bool {
        let folder = bin.deletingLastPathComponent()
        let cues = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "cue" }
        return cues.contains { cueTracks($0).contains { $0.lastPathComponent == bin.lastPathComponent } }
    }

    // MARK: Archives

    /// A zip holding one cartridge ROM belongs to that console; other zips are arcade sets.
    private static func identifyArchive(_ archive: URL) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tf", archive.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return .unknown }
        let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let names = listing.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !names.isEmpty else { return .ignore }
        for name in names {
            if let system = byExtension[(name as NSString).pathExtension.lowercased()] {
                return .game(Match(systemID: system))
            }
        }
        // Arcade sets are zips of many ROM chips (.bin, .rom, .u1, …).
        if archive.pathExtension.lowercased() == "zip", names.count > 1 {
            var match = Match(systemID: "arcade")
            match.guessed = hint(archive) != "arcade"
            return .game(match)
        }
        return .unknown
    }

    // MARK: Folder-name hints

    /// Keywords in folder names, checked in order (PS2 before PS1, and so on).
    private static let hints: [(String, [String])] = [
        ("ps2", ["ps2", "playstation 2", "playstation2"]),
        ("ps3", ["ps3", "playstation 3"]),
        ("psp", ["psp", "playstation portable"]),
        ("ps1", ["ps1", "psx", "psone", "playstation"]),
        ("saturn", ["saturn"]),
        ("dreamcast", ["dreamcast"]),
        ("pcengine", ["pc engine", "pcengine", "turbografx", "pce"]),
        ("gc", ["gamecube", "game cube", "ngc"]),
        ("wii", ["wii"]),
        ("xbox", ["xbox"]),
        ("arcade", ["arcade", "mame", "fbneo", "neogeo", "neo geo"]),
    ]

    private static func hint(_ url: URL) -> String? {
        let path = url.deletingLastPathComponent().path.lowercased()
        let words = path.split(whereSeparator: { "/_-. ()[]".contains($0) }).joined(separator: " ")
        for (system, keywords) in hints where keywords.contains(where: { " \(words) ".contains(" \($0) ") }) {
            return system
        }
        return nil
    }

    private static func guess(_ url: URL) -> Result {
        guard let system = hint(url), let known = GameSystem.with(id: system),
              known.extensions.contains(url.pathExtension.lowercased()) || url.pathExtension.lowercased() == "cue" else {
            return .unknown
        }
        return .game(Match(systemID: system, guessed: true))
    }

    static func read(_ file: URL, at offset: UInt64, count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.read(upToCount: count),
              data.count == count else { return nil }
        return data
    }
}

/// Reads just enough of a CD/DVD image to tell the console.
private struct DiscImage {
    let file: URL
    let sectorSize: UInt64
    let dataOffset: UInt64

    init?(_ file: URL, sectorSize: UInt64, dataOffset: UInt64) {
        self.file = file
        self.sectorSize = sectorSize
        self.dataOffset = dataOffset
        if sectorSize == 2352 {
            // Raw CD sectors start with a 12-byte sync pattern.
            let sync = Data([0x00] + Array(repeating: 0xFF, count: 10) + [0x00])
            guard GameIdentifier.read(file, at: 0, count: 12) == sync else { return nil }
        }
    }

    private func sector(_ lba: UInt64, count: Int = 2048) -> Data? {
        GameIdentifier.read(file, at: lba * sectorSize + dataOffset, count: count)
    }

    var system: String? {
        if sectorSize == 2048, let header = GameIdentifier.read(file, at: 0, count: 0x20) {
            if header[0x18..<0x1C] == Data([0x5D, 0x1C, 0x9E, 0xA3]) { return "wii" }
            if header[0x1C..<0x20] == Data([0xC2, 0x33, 0x9F, 0x3D]) { return "gc" }
            // XDVDFS volume at sector 32, either at the start (XISO) or after the video partition.
            for base: UInt64 in [0, 0x1830_0000] {
                if GameIdentifier.read(file, at: base + 0x10000, count: 20) == Data("MICROSOFT*XBOX*MEDIA".utf8) { return "xbox" }
            }
        }
        if let first = sector(0, count: 16) {
            let text = String(decoding: first, as: UTF8.self)
            if text.hasPrefix("SEGA SEGASATURN") { return "saturn" }
            if text.hasPrefix("SEGA SEGAKATANA") { return "dreamcast" }
        }
        // ISO 9660 primary volume descriptor.
        guard let volume = sector(16), volume[1..<6] == Data("CD001".utf8) else { return nil }
        let systemName = String(decoding: volume[8..<40], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let root = volume[156..<190]
        let rootLBA = UInt64(root.le32(2)), rootSize = Int(root.le32(10))
        let entries = directory(lba: rootLBA, size: rootSize)

        if entries.keys.contains("PS3_GAME") { return "ps3" }
        if entries.keys.contains("PSP_GAME") || systemName.hasPrefix("PSP") { return "psp" }
        if let config = entries["SYSTEM.CNF"], let data = sector(UInt64(config.lba), count: min(config.size, 2048)) {
            return String(decoding: data, as: UTF8.self).uppercased().contains("BOOT2") ? "ps2" : "ps1"
        }
        if systemName.hasPrefix("PLAYSTATION") { return "ps1" }
        return nil
    }

    /// Names, start sectors and sizes in an ISO 9660 directory.
    private func directory(lba: UInt64, size: Int) -> [String: (lba: Int, size: Int)] {
        guard let data = sector(lba, count: min(max(size, 2048), 2048)) else { return [:] }
        var entries: [String: (lba: Int, size: Int)] = [:]
        var offset = 0
        while offset + 33 < data.count {
            let length = Int(data[data.startIndex + offset])
            guard length > 0 else { break }
            let record = data[(data.startIndex + offset)..<min(data.startIndex + offset + length, data.endIndex)]
            let nameLength = Int(record[record.startIndex + 32])
            if record.count >= 33 + nameLength {
                let raw = String(decoding: record[(record.startIndex + 33)..<(record.startIndex + 33 + nameLength)], as: UTF8.self)
                let name = raw.split(separator: ";").first.map(String.init) ?? raw
                entries[name.uppercased()] = (Int(record.le32(2)), Int(record.le32(10)))
            }
            offset += length
        }
        return entries
    }
}

private extension Data {
    func le32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}

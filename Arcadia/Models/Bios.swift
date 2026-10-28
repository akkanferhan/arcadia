import Foundation

/// BIOS or firmware a system's emulator needs, and what Arcadia does without it.
struct BiosRule {
    let systemID: String
    /// Folder inside the library's `bios` folder ("" for the folder itself).
    let folder: String
    /// Groups of files: every group needs at least one match.
    let groups: [FileMatch]
    /// libretro core with a built-in BIOS, used while the real one is missing.
    var builtInCore: String?
    /// Arcadia can fetch it from the console maker's official servers.
    var downloadable = false
    let hint: LocalizedStringResource

    struct FileMatch {
        var names: Set<String> = []
        var sizes: Set<Int> = []

        func matches(_ url: URL) -> Bool {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            return names.contains(url.lastPathComponent.lowercased()) || sizes.contains(size)
        }
    }

    static func rule(for systemID: String) -> BiosRule? { all.first { $0.systemID == systemID } }

    static let all: [BiosRule] = [
        BiosRule(systemID: "ps1", folder: "ps1",
                 groups: [FileMatch(sizes: [524_288])],
                 builtInCore: "pcsx_rearmed",
                 hint: "Any PS1 BIOS from your console, such as scph5501.bin. Without it Arcadia uses a built-in BIOS that runs most games."),
        BiosRule(systemID: "ps2", folder: "ps2",
                 groups: [FileMatch(sizes: [4_194_304])],
                 hint: "A PS2 BIOS dumped from your console (4 MB). There is no free replacement."),
        BiosRule(systemID: "ps3", folder: "ps3",
                 groups: [FileMatch(names: ["ps3updat.pup"])],
                 downloadable: true,
                 hint: "PS3 system software. Arcadia downloads it from Sony when you first play."),
        BiosRule(systemID: "saturn", folder: "",
                 groups: [FileMatch(names: ["sega_101.bin", "mpr-17933.bin"])],
                 builtInCore: "yabause",
                 hint: "sega_101.bin or mpr-17933.bin. Without it Arcadia uses a built-in BIOS; multi-disc games need the real one."),
        BiosRule(systemID: "xbox", folder: "xbox",
                 groups: [FileMatch(sizes: [512]), FileMatch(sizes: [262_144, 1_048_576])],
                 hint: "The MCPX boot ROM (512 bytes) and a flash BIOS from your Xbox. There is no free replacement."),
    ]
}

enum BiosStatus: Equatable {
    case notNeeded
    case ready
    /// Missing, but a built-in BIOS keeps games playable.
    case builtIn
    /// Missing; Arcadia will download it.
    case willDownload
    case missing
}

enum Bios {
    static func folder(_ rule: BiosRule, in bios: URL) -> URL {
        rule.folder.isEmpty ? bios : bios.appendingPathComponent(rule.folder, isDirectory: true)
    }

    static func status(of system: GameSystem, bios: URL) -> BiosStatus {
        guard let rule = BiosRule.rule(for: system.id) else { return .notNeeded }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder(rule, in: bios), includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        if rule.groups.allSatisfy({ group in files.contains(where: group.matches) }) { return .ready }
        if rule.builtInCore != nil { return .builtIn }
        return rule.downloadable ? .willDownload : .missing
    }

    /// The emulator (and core) that plays a system right now: the built-in-BIOS core while
    /// the real BIOS is missing, otherwise the system's preferred emulator.
    static func player(for system: GameSystem, bios: URL) -> (emulator: Emulator, core: String?) {
        if status(of: system, bios: bios) == .builtIn, let core = BiosRule.rule(for: system.id)?.builtInCore {
            return (Emulator.with(id: "retroarch")!, core)
        }
        return (Emulator.with(id: system.emulatorID)!, system.core)
    }

    /// Where a dropped BIOS file belongs, judged by its name and size.
    /// BIOS files RetroArch cores look for in the bios folder itself.
    private static let rootFiles: Set<String> = ["syscard3.pce", "neogeo.zip", "gba_bios.bin", "dc_boot.bin"]

    static func destination(for file: URL, bios: URL) -> URL? {
        let name = file.lastPathComponent.lowercased()
        // Names win over sizes: syscard3.pce is as large as an Xbox flash BIOS.
        if rootFiles.contains(name) { return bios.appendingPathComponent(file.lastPathComponent) }
        if let rule = BiosRule.all.first(where: { $0.groups.contains { $0.names.contains(name) } }) {
            return folder(rule, in: bios).appendingPathComponent(file.lastPathComponent)
        }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        if let rule = BiosRule.all.first(where: { $0.groups.contains { $0.sizes.contains(size) } }) {
            return folder(rule, in: bios).appendingPathComponent(file.lastPathComponent)
        }
        return nil
    }
}

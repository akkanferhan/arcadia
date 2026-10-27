import SwiftUI

/// The company that made a system. Used to group systems in the sidebar.
enum Maker: String, CaseIterable, Identifiable {
    case sony = "PlayStation"
    case nintendo = "Nintendo"
    case sega = "Sega"
    case microsoft = "Xbox"
    case classic = "Classics & Arcade"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .sony: "PlayStation"
        case .nintendo: "Nintendo"
        case .sega: "Sega"
        case .microsoft: "Xbox"
        case .classic: "Classics & Arcade"
        }
    }
}

/// A game console or handheld that Arcadia can play.
struct GameSystem: Identifiable, Hashable {
    /// Also the name of the system's folder inside the game library.
    let id: String
    let name: String
    let shortName: String
    let maker: Maker
    let year: Int
    /// Lower-case file extensions without the dot.
    let extensions: [String]
    /// PS3/PS4/PS5 games are installed folders, not single files.
    var gameIsFolder = false
    let emulatorID: String
    /// libretro core name, for systems played through RetroArch.
    var core: String?
    /// Folder name on thumbnails.libretro.com, used for box art.
    var thumbnails: String?
    let symbol: String
    let colors: [Color]
    /// BIOS files the emulator needs, shown as a hint.
    var biosHint: LocalizedStringResource?

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func == (lhs: GameSystem, rhs: GameSystem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension GameSystem {
    static func with(id: String) -> GameSystem? { all.first { $0.id == id } }

    static let all: [GameSystem] = [
        // PlayStation
        GameSystem(id: "ps1", name: "PlayStation", shortName: "PS1", maker: .sony, year: 1994,
                   extensions: ["cue", "chd", "pbp", "m3u", "iso", "ecm", "mds"],
                   emulatorID: "duckstation", thumbnails: "Sony - PlayStation",
                   symbol: "playstation.logo", colors: [Color(hex: 0x8E9AAF), Color(hex: 0x4A5568)],
                   biosHint: "Put a PS1 BIOS (e.g. scph5501.bin) in bios/ps1."),
        GameSystem(id: "ps2", name: "PlayStation 2", shortName: "PS2", maker: .sony, year: 2000,
                   extensions: ["iso", "chd", "cso", "zso", "gz", "elf"],
                   emulatorID: "pcsx2", thumbnails: "Sony - PlayStation 2",
                   symbol: "playstation.logo", colors: [Color(hex: 0x1E3A8A), Color(hex: 0x0B1026)],
                   biosHint: "Put your PS2 BIOS in bios/ps2 and select it in PCSX2's first-run setup."),
        GameSystem(id: "psp", name: "PlayStation Portable", shortName: "PSP", maker: .sony, year: 2004,
                   extensions: ["iso", "cso", "chd", "pbp", "elf"],
                   emulatorID: "ppsspp", thumbnails: "Sony - PlayStation Portable",
                   symbol: "playstation.logo", colors: [Color(hex: 0x374151), Color(hex: 0x111827)]),
        GameSystem(id: "ps3", name: "PlayStation 3", shortName: "PS3", maker: .sony, year: 2006,
                   extensions: ["iso"], gameIsFolder: true,
                   emulatorID: "rpcs3", thumbnails: "Sony - PlayStation 3",
                   symbol: "playstation.logo", colors: [Color(hex: 0x111111), Color(hex: 0x3B3B3B)],
                   biosHint: "Install the PS3 firmware (PS3UPDAT.PUP) from RPCS3's File menu."),
        GameSystem(id: "ps4", name: "PlayStation 4", shortName: "PS4", maker: .sony, year: 2013,
                   extensions: [], gameIsFolder: true,
                   emulatorID: "shadps4",
                   symbol: "playstation.logo", colors: [Color(hex: 0x0070D1), Color(hex: 0x002A5C)],
                   biosHint: "Each game is a folder containing eboot.bin."),
        GameSystem(id: "ps5", name: "PlayStation 5", shortName: "PS5", maker: .sony, year: 2020,
                   extensions: [], gameIsFolder: true,
                   emulatorID: "sharpemu",
                   symbol: "playstation.logo", colors: [Color(hex: 0xE5E7EB), Color(hex: 0x2563EB)],
                   biosHint: "Experimental. Each game is a folder containing eboot.bin."),

        // Nintendo
        GameSystem(id: "nes", name: "Nintendo Entertainment System", shortName: "NES", maker: .nintendo, year: 1983,
                   extensions: ["nes", "fds", "unf", "zip"],
                   emulatorID: "retroarch", core: "mesen", thumbnails: "Nintendo - Nintendo Entertainment System",
                   symbol: "gamecontroller", colors: [Color(hex: 0xC53030), Color(hex: 0x4A0E0E)]),
        GameSystem(id: "snes", name: "Super Nintendo", shortName: "SNES", maker: .nintendo, year: 1990,
                   extensions: ["sfc", "smc", "zip"],
                   emulatorID: "retroarch", core: "snes9x", thumbnails: "Nintendo - Super Nintendo Entertainment System",
                   symbol: "gamecontroller", colors: [Color(hex: 0x7C3AED), Color(hex: 0x312E81)]),
        GameSystem(id: "n64", name: "Nintendo 64", shortName: "N64", maker: .nintendo, year: 1996,
                   extensions: ["n64", "z64", "v64", "zip"],
                   emulatorID: "retroarch", core: "mupen64plus_next", thumbnails: "Nintendo - Nintendo 64",
                   symbol: "gamecontroller", colors: [Color(hex: 0x16A34A), Color(hex: 0x1D4ED8)]),
        GameSystem(id: "gc", name: "GameCube", shortName: "GC", maker: .nintendo, year: 2001,
                   extensions: ["iso", "rvz", "gcm", "gcz", "ciso", "wbfs"],
                   emulatorID: "dolphin", thumbnails: "Nintendo - GameCube",
                   symbol: "cube", colors: [Color(hex: 0x6D28D9), Color(hex: 0x1E1B4B)]),
        GameSystem(id: "wii", name: "Wii", shortName: "Wii", maker: .nintendo, year: 2006,
                   extensions: ["iso", "rvz", "wbfs", "wad", "ciso"],
                   emulatorID: "dolphin", thumbnails: "Nintendo - Wii",
                   symbol: "wand.and.rays", colors: [Color(hex: 0x38BDF8), Color(hex: 0x0E7490)]),
        GameSystem(id: "wiiu", name: "Wii U", shortName: "Wii U", maker: .nintendo, year: 2012,
                   extensions: ["wua", "wud", "wux", "rpx"],
                   emulatorID: "cemu", thumbnails: "Nintendo - Wii U",
                   symbol: "ipad.landscape", colors: [Color(hex: 0x0EA5E9), Color(hex: 0x1E293B)],
                   biosHint: "Some games need keys.txt in Cemu's data folder."),
        GameSystem(id: "gb", name: "Game Boy", shortName: "GB", maker: .nintendo, year: 1989,
                   extensions: ["gb", "zip"],
                   emulatorID: "retroarch", core: "gambatte", thumbnails: "Nintendo - Game Boy",
                   symbol: "rectangle.portrait", colors: [Color(hex: 0x84CC16), Color(hex: 0x365314)]),
        GameSystem(id: "gbc", name: "Game Boy Color", shortName: "GBC", maker: .nintendo, year: 1998,
                   extensions: ["gbc", "zip"],
                   emulatorID: "retroarch", core: "gambatte", thumbnails: "Nintendo - Game Boy Color",
                   symbol: "rectangle.portrait", colors: [Color(hex: 0xEAB308), Color(hex: 0xDB2777)]),
        GameSystem(id: "gba", name: "Game Boy Advance", shortName: "GBA", maker: .nintendo, year: 2001,
                   extensions: ["gba", "zip"],
                   emulatorID: "retroarch", core: "mgba", thumbnails: "Nintendo - Game Boy Advance",
                   symbol: "rectangle", colors: [Color(hex: 0x6366F1), Color(hex: 0x1E1B4B)]),
        GameSystem(id: "nds", name: "Nintendo DS", shortName: "DS", maker: .nintendo, year: 2004,
                   extensions: ["nds", "zip"],
                   emulatorID: "melonds", thumbnails: "Nintendo - Nintendo DS",
                   symbol: "rectangle.split.1x2", colors: [Color(hex: 0x9CA3AF), Color(hex: 0x374151)]),
        GameSystem(id: "3ds", name: "Nintendo 3DS", shortName: "3DS", maker: .nintendo, year: 2011,
                   extensions: ["3ds", "cci", "cxi", "3dsx", "app"],
                   emulatorID: "azahar", thumbnails: "Nintendo - Nintendo 3DS",
                   symbol: "rectangle.split.1x2.fill", colors: [Color(hex: 0xDC2626), Color(hex: 0x111827)]),

        // Sega
        GameSystem(id: "mastersystem", name: "Master System", shortName: "SMS", maker: .sega, year: 1985,
                   extensions: ["sms", "zip"],
                   emulatorID: "retroarch", core: "genesis_plus_gx", thumbnails: "Sega - Master System - Mark III",
                   symbol: "gamecontroller", colors: [Color(hex: 0xEF4444), Color(hex: 0x111827)]),
        GameSystem(id: "megadrive", name: "Mega Drive / Genesis", shortName: "MD", maker: .sega, year: 1988,
                   extensions: ["md", "gen", "smd", "bin", "zip"],
                   emulatorID: "retroarch", core: "genesis_plus_gx", thumbnails: "Sega - Mega Drive - Genesis",
                   symbol: "gamecontroller.fill", colors: [Color(hex: 0x1F2937), Color(hex: 0xB91C1C)]),
        GameSystem(id: "gamegear", name: "Game Gear", shortName: "GG", maker: .sega, year: 1990,
                   extensions: ["gg", "zip"],
                   emulatorID: "retroarch", core: "genesis_plus_gx", thumbnails: "Sega - Game Gear",
                   symbol: "rectangle", colors: [Color(hex: 0x0F172A), Color(hex: 0x2563EB)]),
        GameSystem(id: "saturn", name: "Saturn", shortName: "Saturn", maker: .sega, year: 1994,
                   extensions: ["cue", "chd", "m3u", "ccd", "mds"],
                   emulatorID: "retroarch", core: "mednafen_saturn", thumbnails: "Sega - Saturn",
                   symbol: "circle.circle", colors: [Color(hex: 0x4B5563), Color(hex: 0x1E3A8A)],
                   biosHint: "Put sega_101.bin and mpr-17933.bin in bios/."),
        GameSystem(id: "dreamcast", name: "Dreamcast", shortName: "DC", maker: .sega, year: 1998,
                   extensions: ["gdi", "chd", "cdi", "cue"],
                   emulatorID: "flycast", thumbnails: "Sega - Dreamcast",
                   symbol: "hurricane", colors: [Color(hex: 0xF97316), Color(hex: 0x7C2D12)]),

        // Microsoft
        GameSystem(id: "xbox", name: "Xbox", shortName: "Xbox", maker: .microsoft, year: 2001,
                   extensions: ["iso", "xiso"],
                   emulatorID: "xemu", thumbnails: "Microsoft - Xbox",
                   symbol: "xbox.logo", colors: [Color(hex: 0x22C55E), Color(hex: 0x14532D)],
                   biosHint: "xemu needs the MCPX boot ROM, a flash BIOS and an HDD image (set in its settings)."),

        // Classics & Arcade
        GameSystem(id: "atari2600", name: "Atari 2600", shortName: "2600", maker: .classic, year: 1977,
                   extensions: ["a26", "bin", "zip"],
                   emulatorID: "retroarch", core: "stella", thumbnails: "Atari - 2600",
                   symbol: "arcade.stick", colors: [Color(hex: 0xB45309), Color(hex: 0x292524)]),
        GameSystem(id: "pcengine", name: "PC Engine / TurboGrafx-16", shortName: "PCE", maker: .classic, year: 1987,
                   extensions: ["pce", "cue", "chd", "zip"],
                   emulatorID: "retroarch", core: "mednafen_pce_fast", thumbnails: "NEC - PC Engine - TurboGrafx 16",
                   symbol: "gamecontroller", colors: [Color(hex: 0xF59E0B), Color(hex: 0x7F1D1D)]),
        GameSystem(id: "arcade", name: "Arcade", shortName: "Arcade", maker: .classic, year: 1978,
                   extensions: ["zip", "7z"],
                   emulatorID: "retroarch", core: "fbneo", thumbnails: "FBNeo - Arcade Games",
                   symbol: "arcade.stick.console", colors: [Color(hex: 0xEC4899), Color(hex: 0x581C87)]),
    ]
}

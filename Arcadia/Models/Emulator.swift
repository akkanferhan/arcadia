import Foundation

/// Where an emulator's macOS build is downloaded from.
enum DownloadSource {
    /// A GitHub release asset whose name matches `asset` (a regular expression).
    case github(repo: String, asset: String, includePrereleases: Bool = false)
    /// The newest stable RetroArch build from the libretro buildbot.
    case retroarch
    /// The newest Dolphin release from dolphin-emu.org's update service.
    case dolphin
}

/// Everything Arcadia needs to start a game.
struct LaunchRequest {
    let game: URL
    let fullscreen: Bool
    /// The libretro core, for RetroArch.
    var core: URL?
}

/// An emulator Arcadia can install and launch. Arcadia never ships emulators itself;
/// it downloads them from their official release pages.
struct Emulator: Identifiable {
    let id: String
    let name: String
    let website: URL
    let license: String
    /// Tried in order until one yields a download.
    let sources: [DownloadSource]
    /// Command-line arguments for a launch.
    let arguments: (LaunchRequest) -> [String]
    /// Intel-only build that runs through Rosetta 2 on Apple silicon.
    var needsRosetta = false
    var experimental = false

    var systems: [GameSystem] { GameSystem.all.filter { $0.emulatorID == id } }

    static func with(id: String) -> Emulator? { all.first { $0.id == id } }
}

private var isAppleSilicon: Bool {
    #if arch(arm64)
    true
    #else
    false
    #endif
}

extension Emulator {
    static let all: [Emulator] = [
        Emulator(id: "retroarch", name: "RetroArch", website: URL(string: "https://www.retroarch.com")!,
                 license: "GPL-3.0", sources: [.retroarch]) { r in
            (r.fullscreen ? ["-f"] : []) + ["-L", r.core?.path ?? "", r.game.path]
        },
        Emulator(id: "duckstation", name: "DuckStation", website: URL(string: "https://www.duckstation.org")!,
                 license: "CC BY-NC-ND 4.0",
                 sources: [.github(repo: "stenzek/duckstation", asset: #"^duckstation-mac-release\.zip$"#)]) { r in
            ["-batch"] + (r.fullscreen ? ["-fullscreen"] : []) + ["--", r.game.path]
        },
        Emulator(id: "pcsx2", name: "PCSX2", website: URL(string: "https://pcsx2.net")!, license: "GPL-3.0",
                 sources: [.github(repo: "PCSX2/pcsx2", asset: #"macos-Qt\.tar\.xz$"#)]) { r in
            ["-batch"] + (r.fullscreen ? ["-fullscreen"] : []) + ["--", r.game.path]
        },
        Emulator(id: "ppsspp", name: "PPSSPP", website: URL(string: "https://www.ppsspp.org")!, license: "GPL-2.0",
                 sources: [.github(repo: "hrydgard/ppsspp", asset: #"^PPSSPPSDL-macOS-.*\.zip$"#)]) { r in
            (r.fullscreen ? ["--fullscreen"] : []) + [r.game.path]
        },
        Emulator(id: "rpcs3", name: "RPCS3", website: URL(string: "https://rpcs3.net")!, license: "GPL-2.0",
                 sources: [isAppleSilicon
                           ? .github(repo: "RPCS3/rpcs3-binaries-mac-arm64", asset: #"macos_aarch64\.7z$"#, includePrereleases: true)
                           : .github(repo: "RPCS3/rpcs3-binaries-mac", asset: #"macos\.7z$"#, includePrereleases: true)]) { r in
            ["--no-gui"] + (r.fullscreen ? ["--fullscreen"] : []) + [r.game.path]
        },
        Emulator(id: "shadps4", name: "shadPS4", website: URL(string: "https://shadps4.net")!, license: "GPL-2.0",
                 sources: [.github(repo: "shadps4-emu/shadPS4", asset: #"macos-sdl.*\.zip$"#)],
                 arguments: { r in
            ["-g", r.game.path] + (r.fullscreen ? ["-f", "true"] : [])
        }, experimental: true),
        Emulator(id: "sharpemu", name: "SharpEmu", website: URL(string: "https://sharpemu.app")!, license: "GPL-2.0",
                 sources: [
                    .github(repo: "sharpemu/sharpemu-mac", asset: #"osx-x64-app\.zip$"#, includePrereleases: true),
                    .github(repo: "sharpemu/sharpemu", asset: #"osx-x64\.tar\.gz$"#, includePrereleases: true),
                 ],
                 arguments: { r in [r.game.path] }, needsRosetta: true, experimental: true),
        Emulator(id: "dolphin", name: "Dolphin", website: URL(string: "https://dolphin-emu.org")!, license: "GPL-2.0",
                 sources: [.dolphin]) { r in
            ["-b"] + (r.fullscreen ? ["-C", "Dolphin.Display.Fullscreen=True"] : []) + ["-e", r.game.path]
        },
        Emulator(id: "cemu", name: "Cemu", website: URL(string: "https://cemu.info")!, license: "MPL-2.0",
                 sources: [.github(repo: "cemu-project/Cemu", asset: #"macos.*\.dmg$"#)],
                 arguments: { r in
            (r.fullscreen ? ["-f"] : []) + ["-g", r.game.path]
        }, needsRosetta: true),
        Emulator(id: "melonds", name: "melonDS", website: URL(string: "https://melonds.kuribo64.net")!, license: "GPL-3.0",
                 sources: [.github(repo: "melonDS-emu/melonDS", asset: #"macOS-universal\.zip$"#)]) { r in
            (r.fullscreen ? ["-f"] : []) + [r.game.path]
        },
        Emulator(id: "azahar", name: "Azahar", website: URL(string: "https://azahar-emu.org")!, license: "GPL-2.0",
                 sources: [.github(repo: "azahar-emu/azahar", asset: #"^azahar-macos-universal-.*\.zip$"#)]) { r in
            (r.fullscreen ? ["-f"] : []) + [r.game.path]
        },
        Emulator(id: "flycast", name: "Flycast", website: URL(string: "https://github.com/flyinghead/flycast")!,
                 license: "GPL-2.0",
                 sources: [.github(repo: "flyinghead/flycast", asset: #"macOS.*\.zip$"#)]) { r in
            [r.game.path]
        },
        Emulator(id: "xemu", name: "xemu", website: URL(string: "https://xemu.app")!, license: "GPL-2.0",
                 sources: [.github(repo: "xemu-project/xemu", asset: #"^xemu-[0-9.]+-macos-universal\.zip$"#)]) { r in
            ["-dvd_path", r.game.path] + (r.fullscreen ? ["-full-screen"] : [])
        },
    ]
}

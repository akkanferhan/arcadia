import Foundation

/// What a preset needs to know about the launch.
struct PresetContext {
    let emulator: Emulator
    let system: GameSystem
    /// The file the emulator boots.
    let game: URL
    /// libretro core, for RetroArch.
    let core: URL?
    /// The installed `.app` bundle or executable.
    let install: URL
    let bios: URL
    /// Internal resolution multiplier from Arcadia's graphics quality setting.
    let scale: Int
    let fullscreen: Bool

    /// Settings, saves and memory cards for this emulator, owned by Arcadia.
    var data: URL { Paths.data(emulator.id) }

    /// Executable inside the app bundle, or the install itself for bare executables.
    var executableFolder: URL {
        install.pathExtension == "app"
            ? install.appendingPathComponent("Contents/MacOS", isDirectory: true)
            : install.deletingLastPathComponent()
    }
}

/// Extra launch details a preset asks for.
struct PresetLaunch {
    /// Placed before the emulator's own arguments.
    var arguments: [String] = []
    var environment: [String: String] = [:]
    /// For bare executables; app bundles always start in their own folder.
    var workingDirectory: URL?
}

/// Writes Arcadia's tuned settings for each emulator before a launch, so players never
/// need an emulator's own settings. Every preset maps Select + Start to "quit to Arcadia".
enum Presets {
    static func apply(_ context: PresetContext) async throws -> PresetLaunch {
        switch context.emulator.id {
        case "retroarch": try retroArch(context)
        case "duckstation": try duckStation(context)
        case "pcsx2": try pcsx2(context)
        case "ppsspp": try ppsspp(context)
        case "dolphin": try dolphin(context)
        case "cemu": try cemu(context)
        case "melonds": try melonDS(context)
        case "azahar": try azahar(context)
        case "flycast": try flycast(context)
        case "xemu": try await xemu(context)
        case "rpcs3": try await rpcs3(context)
        case "shadps4": try shadPS4(context)
        case "sharpemu": try sharpEmu(context)
        default: PresetLaunch()
        }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let applicationSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
}

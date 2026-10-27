import Foundation

/// RPCS3 (PS3), shadPS4 (PS4) and SharpEmu (PS5).
extension Presets {
    // MARK: RPCS3

    /// RPCS3 follows `$HOME`, so it gets a home inside Arcadia's data folder; firmware and
    /// game data then survive emulator updates.
    static func rpcs3(_ context: PresetContext) async throws -> PresetLaunch {
        let home = context.data.appendingPathComponent("home", isDirectory: true)
        let root = home.appendingPathComponent("Library/Application Support/rpcs3", isDirectory: true)

        try YAMLFile.update(root.appendingPathComponent("config.yml")) { yaml in
            yaml.set(["Core", "PPU Decoder"], "Recompiler (LLVM)")
            yaml.set(["Core", "SPU Decoder"], "Recompiler (LLVM)")
            yaml.set(["Video", "Renderer"], "Vulkan") // MoltenVK; RPCS3 has no Metal renderer
            yaml.set(["Video", "Resolution Scale"], String(pick(context.scale, [100, 150, 200, 250])))
            yaml.set(["Video", "Shader Mode"], "Async Recompiler with Shader Interpreter")
            yaml.set(["Video", "VSync Mode"], "Disabled")
            yaml.set(["Audio", "Renderer"], "Cubeb")
            yaml.set(["Miscellaneous", "Exit RPCS3 when process finishes"], "true")
            yaml.set(["Miscellaneous", "Start games in fullscreen mode"], context.fullscreen ? "true" : "false")
            yaml.set(["Miscellaneous", "Automatically start games after boot"], "true")
            yaml.set(["Miscellaneous", "Show shader compilation hint"], "false")
            yaml.set(["Miscellaneous", "Show PPU compilation hint"], "false")
            yaml.set(["Miscellaneous", "Prevent display sleep while running games"], "true")
        }
        try INIFile.update(root.appendingPathComponent("GuiConfigs/CurrentSettings.ini"), separator: "=") { ini in
            ini.set([
                "infoBoxEnabledWelcome": "false",
                "confirmationBoxExitGame": "false",
                "confirmationBoxBootGame": "false",
                "confirmationObsoleteCfg": "false",
                "infoBoxEnabledInstallPUP": "false",
            ], section: "main_window")
            ini.set(["checkUpdateStart": "false", "useRichPresence": "false"], section: "Meta")
            ini.set(["hideMouseOnIdle": "true", "hideMouseOnIdleTime": "2000"], section: "GSFrame")
            ini.set("game_window_stop", "Ctrl+Q", section: "Shortcuts")
        }

        // Install the PS3 firmware the player put in bios/ps3, once, without any window.
        let firmware = context.bios.appendingPathComponent("ps3/PS3UPDAT.PUP")
        let installed = root.appendingPathComponent("dev_flash/vsh/etc/version.txt")
        if FileManager.default.fileExists(atPath: firmware.path), !FileManager.default.fileExists(atPath: installed.path) {
            let executable = context.executableFolder.appendingPathComponent("rpcs3")
            try await Task.detached {
                let process = Process()
                process.executableURL = executable
                process.arguments = ["--headless", "--installfw", firmware.path]
                process.environment = ProcessInfo.processInfo.environment.merging(["HOME": home.path]) { $1 }
                try process.run()
                process.waitUntilExit()
            }.value
        }
        return PresetLaunch(environment: ["HOME": home.path])
    }

    // MARK: shadPS4

    /// shadPS4 uses `./user` when it exists, so it runs from Arcadia's data folder.
    static func shadPS4(_ context: PresetContext) throws -> PresetLaunch {
        let user = context.data.appendingPathComponent("user", isDirectory: true)
        let resolution = pick(context.scale, [(1280, 720), (1920, 1080), (1920, 1080), (2560, 1440)])
        try JSONSettings.update(user.appendingPathComponent("config.json"), [
            (["General", "show_splash"], false),
            (["General", "neo_mode"], false),
            (["General", "discord_rpc_enabled"], false),
            (["General", "trophy_popup_disabled"], true),
            (["GPU", "full_screen"], context.fullscreen),
            (["GPU", "full_screen_mode"], "Fullscreen (Borderless)"),
            (["GPU", "internal_screen_width"], resolution.0),
            (["GPU", "internal_screen_height"], resolution.1),
            (["GPU", "present_mode"], "Mailbox"),
            (["Vulkan", "pipeline_cache_enabled"], true),
            (["Log", "enable"], false),
        ])
        return PresetLaunch(workingDirectory: context.data)
    }

    // MARK: SharpEmu

    static func sharpEmu(_ context: PresetContext) throws -> PresetLaunch {
        try JSONSettings.update(context.executableFolder.appendingPathComponent("gui-settings.json"), [
            (["CheckForUpdatesOnStartup"], false),
            (["DiscordRichPresence"], false),
            (["OverlayEnabled"], false),
        ])
        return PresetLaunch(arguments: [
            "--window-mode=\(context.fullscreen ? "borderless" : "windowed")",
            "--vsync=on",
            "--overlay=off",
        ])
    }
}

/// Merges values into a JSON settings file, keeping keys Arcadia does not manage.
enum JSONSettings {
    static func update(_ url: URL, _ values: [(path: [String], value: Any)]) throws {
        var root = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        for (path, value) in values { set(&root, path[...], value) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    private static func set(_ object: inout [String: Any], _ path: ArraySlice<String>, _ value: Any) {
        guard let key = path.first else { return }
        if path.count == 1 {
            object[key] = value
        } else {
            var child = object[key] as? [String: Any] ?? [:]
            set(&child, path.dropFirst(), value)
            object[key] = child
        }
    }
}

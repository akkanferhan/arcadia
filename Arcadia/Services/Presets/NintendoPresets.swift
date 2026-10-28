import Foundation

extension Presets {
    // MARK: Dolphin (GameCube, Wii)

    /// Dolphin runs from its own user folder (`-u`), so a separately installed Dolphin is untouched.
    static func dolphin(_ context: PresetContext) throws -> PresetLaunch {
        let config = context.data.appendingPathComponent("Config", isDirectory: true)
        try INIFile.update(config.appendingPathComponent("Dolphin.ini")) { ini in
            ini.set(["PermissionAsked": "True", "Enabled": "False"], section: "Analytics")
            ini.set("UpdateTrack", "", section: "AutoUpdate")
            ini.set([
                "ConfirmStop": "False",
                "CursorVisibility": "0",
                "UsePanicHandlers": "False",
                "SkipNKitWarning": "True",
            ], section: "Interface")
            ini.set(["GFXBackend": "Metal", "CPUThread": "True", "SkipIPL": "True"], section: "Core")
            ini.set(["Fullscreen": context.fullscreen ? "True" : "False", "RenderToMain": "False"], section: "Display")
        }
        try INIFile.update(config.appendingPathComponent("GFX.ini")) { ini in
            ini.set([
                // 1 = native 528p, 3 ≈ 1080p, 4 ≈ 1440p.
                "InternalResolution": String(pick(context.scale, [2, 3, 4, 5])),
                // Asynchronous ubershaders: no stutter while shaders compile.
                "ShaderCompilationMode": "2",
                "WaitForShadersBeforeStarting": "True",
                "AspectRatio": "0",
            ], section: "Settings")
            ini.set("VSync", "True", section: "Hardware")
        }
        try dolphinControllers(context, config: config)
        return PresetLaunch(arguments: ["-u", context.data.path])
    }

    // MARK: Cemu (Wii U)

    static func cemu(_ context: PresetContext) throws -> PresetLaunch {
        let mlc = context.data.appendingPathComponent("mlc01", isDirectory: true)
        try FileManager.default.createDirectory(at: mlc, withIntermediateDirectories: true)
        // A missing settings.xml opens Cemu's getting-started wizard, so it is always written.
        try XMLSettings.update(applicationSupport.appendingPathComponent("Cemu/settings.xml"), root: "content", [
            ("check_update", "false"),
            ("macos_disclaimer", "true"),
            ("use_discord_presence", "false"),
            ("fullscreen", context.fullscreen ? "true" : "false"),
            ("mlc_path", mlc.path),
            ("Graphic/api", "1"), // Vulkan through MoltenVK; Cemu 2.6 has no Metal backend
            ("Graphic/VSync", "1"),
            ("Graphic/AsyncCompile", "true"),
            ("Graphic/UpscaleFilter", "1"),
            ("Graphic/FullscreenScaling", "0"),
        ])
        try cemuControllers(context)
        return PresetLaunch(arguments: ["-m", mlc.path])
    }

    // MARK: melonDS (Nintendo DS)

    /// melonDS rewrites its whole config on exit, so Arcadia writes a complete file each launch.
    /// It reads `portable/melonDS.toml` next to the app.
    static func melonDS(_ context: PresetContext) throws -> PresetLaunch {
        let file = context.install.deletingLastPathComponent().appendingPathComponent("portable/melonDS.toml")
        let toml = """
        LimitFPS = true
        AudioSync = false

        [3D]
        Renderer = 1

        [3D.GL]
        ScaleFactor = \(pick(context.scale, [2, 4, 5, 6]))
        BetterPolygons = true

        [Screen]
        UseGL = true
        VSync = true

        [JIT]
        Enable = true

        [Emu]
        ExternalBIOSEnable = false
        DirectBoot = true

        [Audio]
        Interpolation = 3

        [Mouse]
        Hide = true

        [Instance0]
        JoystickID = 0

        [Instance0.Window0]
        ScreenLayout = 0
        ScreenSizing = 0
        IntegerScaling = false
        ShowOSD = false

        [Instance0.Keyboard]
        A = 88
        B = 90
        X = 83
        Y = 65
        L = 81
        R = 87
        Start = 16777220
        Select = 16777219
        Up = 16777235
        Down = 16777237
        Left = 16777234
        Right = 16777236
        HK_FullscreenToggle = 16777274

        [Instance0.Joystick]
        \(melonDSJoystick(context.gamepads.first).map { "\($0.0) = \($0.1)" }.joined(separator: "\n"))

        """
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try toml.write(to: file, atomically: true, encoding: .utf8)
        return PresetLaunch()
    }

    // MARK: Azahar (Nintendo 3DS)

    /// Qt settings need `<key>\default=false` beside each value, or the built-in default wins.
    static func azahar(_ context: PresetContext) throws -> PresetLaunch {
        let file = applicationSupport.appendingPathComponent("Azahar/config/qt-config.ini")
        try INIFile.update(file, separator: "=") { ini in
            func set(_ values: [String: String], _ section: String) {
                for (key, value) in values {
                    ini.set(key, value, section: section)
                    ini.set("\(key)\\default", "false", section: section)
                }
            }
            set([
                "confirmClose": "false",
                "firstStart": "false",
                "saveStateWarning": "false",
                "enable_discord_presence": "false",
                "hideInactiveMouse": "true",
                "fullscreen": context.fullscreen ? "true" : "false",
            ], "UI")
            set(["check_for_update_on_start": "false"], "Miscellaneous")
            set([
                "graphics_api": "2", // Vulkan through MoltenVK
                "resolution_factor": String(pick(context.scale, [2, 3, 4, 5])),
                "async_shader_compilation": "true",
                "use_disk_shader_cache": "true",
                "use_hw_shader": "true",
                "use_vsync": "true",
            ], "Renderer")
            set(["use_cpu_jit": "true", "cpu_clock_percentage": "100"], "Core")

            // A gamepad binding replaces the keyboard one, so only bind the pad when one is connected.
            if !context.gamepads.isEmpty {
                func button(_ index: Int) -> String { "\"engine:sdl,api:controller,maptype:all,button:\(index)\"" }
                func trigger(_ axis: Int) -> String {
                    "\"engine:sdl,api:controller,maptype:all,axis:\(axis),direction:+,threshold:0.5\""
                }
                let profile = "profiles\\1\\"
                var controls: [String: String] = [
                    "profile": "0", "profiles\\size": "1", "\(profile)name": "Default",
                    "\(profile)button_zl": trigger(4), "\(profile)button_zr": trigger(5),
                    "\(profile)circle_pad": "\"engine:sdl,api:controller,maptype:all,axis_x:0,axis_y:1,deadzone:0.1\"",
                    "\(profile)c_stick": "\"engine:sdl,api:controller,maptype:all,axis_x:2,axis_y:3,deadzone:0.1\"",
                ]
                let buttons = ["a": 1, "b": 0, "x": 3, "y": 2, "up": 11, "down": 12, "left": 13, "right": 14,
                               "l": 9, "r": 10, "start": 6, "select": 4, "home": 5]
                for (name, index) in buttons { controls["\(profile)button_\(name)"] = button(index) }
                set(controls, "Controls")
            }
        }
        return PresetLaunch()
    }
}

extension Presets {
    // MARK: Flycast (Dreamcast)

    static func flycast(_ context: PresetContext) throws -> PresetLaunch {
        // Without dc_boot.bin Flycast falls back to its built-in BIOS.
        try INIFile.update(applicationSupport.appendingPathComponent("Flycast/emu.cfg")) { ini in
            ini.set([
                "pvr.rend": "4", // Vulkan through MoltenVK
                "rend.Resolution": String(480 * pick(context.scale, [2, 2, 3, 4])),
                "rend.WideScreen": "no",
                "rend.ThreadedRendering": "yes",
                "rend.vsync": "yes",
                "Dynarec.Enabled": "yes",
                "Dreamcast.AutoSaveState": "yes",
                "Dreamcast.AutoLoadState": "yes",
            ], section: "config")
            ini.set("fullscreen", context.fullscreen ? "yes" : "no", section: "window")
        }
        return PresetLaunch()
    }

    // MARK: xemu (Xbox)

    static func xemu(_ context: PresetContext) async throws -> PresetLaunch {
        let data = context.data
        let config = data.appendingPathComponent("xemu.toml")
        let hdd = data.appendingPathComponent("xbox_hdd.qcow2")
        if !FileManager.default.fileExists(atPath: hdd.path) {
            // xemu cannot create a hard disk itself; the project publishes a blank, legal image.
            context.report("Preparing the Xbox hard disk…")
            let zip = Paths.downloads.appendingPathComponent("xbox_hdd.qcow2.zip")
            defer { try? FileManager.default.removeItem(at: zip) }
            let url = URL(string: "https://github.com/xemu-project/xemu-hdd-image/releases/download/1.0/xbox_hdd.qcow2.zip")!
            _ = try await Downloader.download(url, to: zip, progress: context.progress)
            try await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, data.path])
        }

        // The user's own MCPX boot ROM is exactly 512 bytes; the flash BIOS is 256 KB or 1 MB.
        let biosFolder = context.bios.appendingPathComponent("xbox", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: biosFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        func file(sizes: Set<Int>) -> URL? {
            files.sorted { $0.lastPathComponent < $1.lastPathComponent }.first {
                sizes.contains((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        func quoted(_ value: String) -> String { "'\(value.replacingOccurrences(of: "'", with: "\\'"))'" }

        try INIFile.update(config) { toml in
            toml.set(["show_welcome": "false", "skip_boot_anim": "true"], section: "general")
            toml.set("renderer", "'OPENGL'", section: "display") // Vulkan is not built for macOS
            toml.set("surface_scale", String(pick(context.scale, [1, 2, 2, 3])), section: "display.quality")
            toml.set(["fullscreen_on_startup": context.fullscreen ? "true" : "false", "vsync": "true"],
                     section: "display.window")
            toml.set(["show_menubar": "false", "hide_cursor": "true"], section: "display.ui")
            toml.set("auto_bind", "true", section: "input")
            var system = ["hdd_path": quoted(hdd.path),
                          "eeprom_path": quoted(data.appendingPathComponent("eeprom.bin").path)]
            if let mcpx = file(sizes: [512]) { system["bootrom_path"] = quoted(mcpx.path) }
            if let flash = file(sizes: [262_144, 1_048_576]) { system["flashrom_path"] = quoted(flash.path) }
            toml.set(system, section: "sys.files")
        }
        return PresetLaunch(arguments: ["-config_path", config.path])
    }
}

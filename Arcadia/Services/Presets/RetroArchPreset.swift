import Foundation

extension Presets {
    /// Cores light enough to run one frame ahead, which removes a frame of input lag.
    private static let runAheadCores: Set<String> = ["snes9x", "genesis_plus_gx", "mesen", "gambatte", "stella"]

    /// RetroArch runs from Arcadia's own config file; per-core tweaks are appended per launch.
    static func retroArch(_ context: PresetContext) throws -> PresetLaunch {
        let data = context.data
        let config = data.appendingPathComponent("retroarch.cfg")
        let system = context.system.id
        func folder(_ path: String) -> String {
            let url = data.appendingPathComponent(path, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return "\"\(url.path)\""
        }

        try INIFile.update(config) { cfg in
            cfg.set([
                // Arcadia owns these settings; RetroArch must not save its own on exit.
                "config_save_on_exit": "\"false\"",
                "video_driver": "\"vulkan\"",
                "driver_switch_enable": "\"true\"",
                "video_fullscreen": context.fullscreen ? "\"true\"" : "\"false\"",
                "video_windowed_fullscreen": "\"true\"",
                "video_vsync": "\"true\"",
                "video_threaded": "\"false\"",
                "video_smooth": "\"false\"",
                "video_shader_enable": "\"false\"",
                "audio_driver": "\"coreaudio3\"",
                "audio_latency": "\"64\"",
                "pause_nonactive": "\"false\"",
                "quit_press_twice": "\"false\"",
                "menu_enable_widgets": "\"true\"",
                "notification_show_autoconfig": "\"false\"",
                "notification_show_remap_load": "\"false\"",
                "notification_show_config_override_load": "\"false\"",
                "notification_show_set_initial_disk": "\"false\"",
                "menu_show_load_content_animation": "\"false\"",
                "menu_show_core_updater": "\"false\"",
                "menu_show_online_updater": "\"false\"",
                "fps_show": "\"false\"",
                "savestate_auto_save": "\"true\"",
                "savestate_auto_load": "\"true\"",
                "check_firmware_before_loading": "\"false\"",
                "system_directory": "\"\(context.bios.path)\"",
                "savefile_directory": folder("saves/\(system)"),
                "savestate_directory": folder("states/\(system)"),
                "rgui_config_directory": folder("config"),
                "auto_overrides_enable": "\"false\"",
                "auto_remaps_enable": "\"false\"",
                "game_specific_options": "\"false\"",
                "global_core_options": "\"true\"",
                "core_options_path": "\"\(data.appendingPathComponent("retroarch-core-options.cfg").path)\"",
                // Any controller macOS knows (Xbox, PlayStation, MFi) works without setup.
                "input_joypad_driver": "\"mfi\"",
                "input_autodetect_enable": "\"true\"",
                // Select + Start quits back to Arcadia.
                "input_quit_gamepad_combo": "\"4\"",
            ])
            cfg.set(retroArchAchievements(context.achievements))
            // The mfi driver numbers controllers in connection order; player N takes controller N.
            for player in 1...maxPlayers {
                cfg.set("input_player\(player)_joypad_index", "\"\(player - 1)\"")
            }
        }

        let core = context.core?.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_libretro", with: "") ?? ""
        let coreConfig = data.appendingPathComponent("cores/\(core).cfg")
        try INIFile.update(coreConfig) { cfg in
            let runAhead = runAheadCores.contains(core)
            cfg.set([
                "run_ahead_enabled": runAhead ? "\"true\"" : "\"false\"",
                "run_ahead_frames": "\"1\"",
                "run_ahead_secondary_instance": "\"true\"",
                "run_ahead_hide_warnings": "\"true\"",
            ])
        }

        try INIFile.update(data.appendingPathComponent("retroarch-core-options.cfg")) { options in
            // ParaLLEl-RDP renders N64 games accurately on Vulkan (MoltenVK) and upscales cleanly.
            options.set("mupen64plus-rdp-plugin", "\"parallel\"")
            options.set("mupen64plus-parallel-rdp-upscaling", "\"\(context.scale >= 4 ? 4 : context.scale >= 2 ? 2 : 1)x\"")
            // The PCSX2 core runs natively on Apple silicon with its own arm64 recompiler.
            options.set("pcsx2_renderer", "\"Vulkan\"")
            options.set("pcsx2_upscale_multiplier", "\"\(pick(context.scale, ["1x (Native)", "2x", "2x", "4x"]))\"")
            options.set("pcsx2_fastboot", "\"enabled\"")
        }

        // The PCSX2 core looks for BIOS files in <system>/pcsx2/bios; point that at bios/ps2.
        if core == "pcsx2" {
            let expected = context.bios.appendingPathComponent("pcsx2/bios")
            if (try? expected.checkResourceIsReachable()) != true {
                try? FileManager.default.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.createSymbolicLink(at: expected, withDestinationURL: context.bios.appendingPathComponent("ps2"))
            }
        }

        return PresetLaunch(arguments: ["--config", config.path, "--appendconfig", coreConfig.path])
    }
}

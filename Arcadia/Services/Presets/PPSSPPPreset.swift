import Foundation

extension Presets {
    /// PPSSPP keeps its memory stick in `$HOME/.config/ppsspp`; Arcadia gives it its own home.
    static func ppsspp(_ context: PresetContext) throws -> PresetLaunch {
        let home = context.data.appendingPathComponent("home", isDirectory: true)
        let system = home.appendingPathComponent(".config/ppsspp/PSP/SYSTEM", isDirectory: true)

        try INIFile.update(system.appendingPathComponent("ppsspp.ini")) { ini in
            ini.set([
                "FirstRun": "False",
                "CheckForNewVersion": "False",
                "PauseOnLostFocus": "False",
                "DiscordRichPresence": "False",
                // Resume where the player left off.
                "AutoLoadSaveState": "2",
            ], section: "General")
            ini.set([
                "GraphicsBackend": "3 (VULKAN)",
                "FullScreen": context.fullscreen ? "True" : "False",
                "VerticalSync": "True",
                // PSP games are light; never go below 2× on Apple silicon.
                "InternalResolution": String(max(2, context.scale)),
                "TextureFiltering": "1",
                "AnisotropyLevel": "4",
                "FrameSkip": "0",
                "iShowStatusFlags": "0",
            ], section: "Graphics")
            ini.set("AudioBufferSize", "256", section: "Sound")
            ini.set(ppssppAchievements(context.achievements), section: "Achievements")
        }
        try writePPSSPPToken(context.achievements, system: system)

        // Once controls.ini has a mapping section, every action loses its defaults, so keyboard
        // (device 1) and gamepad (device 10) are written together. SDL also reports shoulder buttons
        // differently from PPSSPP's pad defaults.
        try INIFile.update(system.appendingPathComponent("controls.ini")) { ini in
            ini.set([
                "Up": "1-19,10-19", "Down": "1-20,10-20", "Left": "1-21,10-21", "Right": "1-22,10-22",
                "Cross": "1-54,10-189", "Circle": "1-52,10-190", "Square": "1-29,10-191", "Triangle": "1-47,10-188",
                "Start": "1-62,10-197", "Select": "1-66,10-196", "L": "1-45,10-193", "R": "1-51,10-192",
                "An.Up": "1-37,10-4003", "An.Down": "1-39,10-4002", "An.Left": "1-38,10-4001", "An.Right": "1-40,10-4000",
                "Pause": "1-111,10-4",
                "Fast-forward": "1-61",
                // Select + Start quits back to Arcadia.
                "Exit App": "10-196:10-197",
            ], section: "ControlMapping")
        }

        return PresetLaunch(environment: ["HOME": home.path])
    }
}

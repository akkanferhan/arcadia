import Foundation

/// DuckStation (PS1) and PCSX2 (PS2) share a settings format and input naming.
extension Presets {
    /// Keyboard defaults both emulators write into a fresh file, followed by an SDL gamepad.
    /// Repeated keys bind several inputs to one button.
    private static func dualShockBindings(keyboard: [String: String], pad: [String: String]) -> [(String, String)] {
        let order = ["Up", "Right", "Down", "Left", "Triangle", "Circle", "Cross", "Square", "Select", "Start",
                     "L1", "R1", "L2", "R2", "L3", "R3", "LUp", "LRight", "LDown", "LLeft", "RUp", "RRight", "RDown", "RLeft",
                     "Analog", "LargeMotor", "SmallMotor"]
        return order.flatMap { button -> [(String, String)] in
            [keyboard[button], pad[button]].compactMap { $0 }.map { (button, $0) }
        }
    }

    private static let keyboardPad: [String: String] = [
        "Triangle": "Keyboard/I", "Circle": "Keyboard/L", "Cross": "Keyboard/K", "Square": "Keyboard/J",
        "Select": "Keyboard/Backspace", "L1": "Keyboard/Q", "R1": "Keyboard/E", "L2": "Keyboard/1", "R2": "Keyboard/3",
        "L3": "Keyboard/2", "R3": "Keyboard/4", "LUp": "Keyboard/W", "LRight": "Keyboard/D", "LDown": "Keyboard/S",
        "LLeft": "Keyboard/A", "RUp": "Keyboard/T", "RRight": "Keyboard/H", "RDown": "Keyboard/G", "RLeft": "Keyboard/F",
    ]

    private static func sdlPad(face: (south: String, east: String, west: String, north: String)) -> [String: String] {
        [
            "Up": "SDL-0/DPadUp", "Right": "SDL-0/DPadRight", "Down": "SDL-0/DPadDown", "Left": "SDL-0/DPadLeft",
            "Cross": "SDL-0/\(face.south)", "Circle": "SDL-0/\(face.east)", "Square": "SDL-0/\(face.west)",
            "Triangle": "SDL-0/\(face.north)", "Select": "SDL-0/Back", "Start": "SDL-0/Start", "Analog": "SDL-0/Guide",
            "L1": "SDL-0/LeftShoulder", "R1": "SDL-0/RightShoulder", "L2": "SDL-0/+LeftTrigger", "R2": "SDL-0/+RightTrigger",
            "L3": "SDL-0/LeftStick", "R3": "SDL-0/RightStick",
            "LUp": "SDL-0/-LeftY", "LRight": "SDL-0/+LeftX", "LDown": "SDL-0/+LeftY", "LLeft": "SDL-0/-LeftX",
            "RUp": "SDL-0/-RightY", "RRight": "SDL-0/+RightX", "RDown": "SDL-0/+RightY", "RLeft": "SDL-0/-RightX",
            "LargeMotor": "SDL-0/LargeMotor", "SmallMotor": "SDL-0/SmallMotor",
        ]
    }

    /// Select + Start on a gamepad quits back to Arcadia.
    private static let quitCombo = "SDL-0/Back & SDL-0/Start"

    // MARK: DuckStation

    static func duckStation(_ context: PresetContext) throws -> PresetLaunch {
        let settings = applicationSupport.appendingPathComponent("DuckStation/settings.ini")
        let memoryCards = context.data.appendingPathComponent("memcards", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryCards, withIntermediateDirectories: true)

        try INIFile.update(settings) { ini in
            ini.set([
                "SetupWizardIncomplete": "false",
                "ConfirmPowerOff": "false",
                "RenderToSeparateWindow": "false",
                "PauseOnFocusLoss": "false",
                "SaveStateOnExit": "true",
            ], section: "Main")
            ini.set("CheckAtStartup", "false", section: "AutoUpdater")
            ini.set([
                "Renderer": "Metal",
                // 1 = native 240p; Apple GPUs handle 3–5× easily.
                "ResolutionScale": String(pick(context.scale, [2, 3, 4, 5])),
                "PGXPEnable": "true",
                "PGXPCulling": "true",
                "PGXPTextureCorrection": "true",
                "WidescreenHack": "false",
            ], section: "GPU")
            ini.set([
                "AspectRatio": "Auto (Game Native)",
                "ShowOSDMessages": "false",
                "ShowFPS": "false",
            ], section: "Display")
            ini.set([
                "SearchDirectory": context.bios.appendingPathComponent("ps1").path,
                "PatchFastBoot": "true",
            ], section: "BIOS")
            ini.set("Enabled", "false", section: "Cheevos")
            ini.set([
                "Directory": memoryCards.path,
                "Card1Type": "PerGameTitle",
                "Card2Type": "None",
            ], section: "MemoryCards")
            ini.set("SDL", "true", section: "InputSources")

            var keyboard = keyboardPad
            keyboard.merge(["Up": "Keyboard/UpArrow", "Right": "Keyboard/RightArrow", "Down": "Keyboard/DownArrow",
                            "Left": "Keyboard/LeftArrow", "Start": "Keyboard/Enter"]) { $1 }
            ini.replaceSection("Pad1", with: [("Type", "AnalogController")]
                + dualShockBindings(keyboard: keyboard, pad: sdlPad(face: ("A", "B", "X", "Y"))))
            ini.replaceSection("Hotkeys", with: [
                ("FastForward", "Keyboard/Tab"), ("TogglePause", "Keyboard/Space"), ("Screenshot", "Keyboard/F10"),
                ("ToggleFullscreen", "Keyboard/F11"), ("OpenPauseMenu", "Keyboard/Escape"),
                ("LoadSelectedSaveState", "Keyboard/F1"), ("SaveSelectedSaveState", "Keyboard/F2"),
                ("SelectPreviousSaveStateSlot", "Keyboard/F3"), ("SelectNextSaveStateSlot", "Keyboard/F4"),
                ("PowerOff", quitCombo),
            ])
        }
        return PresetLaunch()
    }

    // MARK: PCSX2

    static func pcsx2(_ context: PresetContext) throws -> PresetLaunch {
        // With -datapath, PCSX2 keeps everything in <data>/PCSX2.
        let settings = context.data.appendingPathComponent("PCSX2/inis/PCSX2.ini")

        try INIFile.update(settings) { ini in
            ini.set([
                // Without SettingsVersion PCSX2 resets everything and asks for confirmation.
                "SettingsVersion": "1",
                "SetupWizardIncomplete": "false",
                "ConfirmShutdown": "false",
                "PauseOnFocusLoss": "false",
                "RenderToSeparateWindow": "false",
                "HideMainWindowWhenRunning": "false",
                "StartFullscreen": "false",
            ], section: "UI")
            ini.set("CheckAtStartup", "false", section: "AutoUpdater")
            ini.set([
                "EnableFastBoot": "true",
                "SaveStateOnShutdown": "true",
                "EnableWideScreenPatches": "false",
            ], section: "EmuCore")
            ini.set("vuThread", "true", section: "EmuCore/Speedhacks")
            ini.set([
                "Renderer": "17", // Metal
                // 1 = native 480p, 3 ≈ 1080p, 4 ≈ 1440p.
                "upscale_multiplier": String(pick(context.scale, [2, 3, 3, 4])),
                "OsdMessagesPos": "0",
            ], section: "EmuCore/GS")
            ini.set("Enabled", "false", section: "Achievements")
            // PCSX2 picks the first valid BIOS in the folder when none is named.
            ini.set("Bios", context.bios.appendingPathComponent("ps2").path, section: "Folders")
            ini.set("SDL", "true", section: "InputSources")

            var keyboard = keyboardPad
            keyboard.merge(["Up": "Keyboard/Up", "Right": "Keyboard/Right", "Down": "Keyboard/Down",
                            "Left": "Keyboard/Left", "Start": "Keyboard/Return"]) { $1 }
            ini.replaceSection("Pad1", with: [("Type", "DualShock2")]
                + dualShockBindings(keyboard: keyboard,
                                    pad: sdlPad(face: ("FaceSouth", "FaceEast", "FaceWest", "FaceNorth"))))
            ini.replaceSection("Hotkeys", with: [
                ("ToggleFullscreen", "Keyboard/Alt & Keyboard/Return"), ("CycleAspectRatio", "Keyboard/F6"),
                ("Screenshot", "Keyboard/F8"), ("LoadStateFromSlot", "Keyboard/F3"), ("SaveStateToSlot", "Keyboard/F1"),
                ("NextSaveStateSlot", "Keyboard/F2"), ("PreviousSaveStateSlot", "Keyboard/Shift & Keyboard/F2"),
                ("OpenPauseMenu", "Keyboard/Escape"), ("ToggleFrameLimit", "Keyboard/F4"),
                ("TogglePause", "Keyboard/Space"), ("ToggleTurbo", "Keyboard/Tab"), ("HoldTurbo", "Keyboard/Period"),
                ("ShutdownVM", quitCombo),
            ])
        }
        return PresetLaunch(arguments: ["-datapath", context.data.path])
    }
}

extension Presets {
    /// Picks a value for the current graphics scale (1–4) from a four-entry table.
    static func pick<T>(_ scale: Int, _ table: [T]) -> T {
        table[min(max(scale, 1), table.count) - 1]
    }
}

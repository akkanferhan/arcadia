import Foundation

/// DuckStation (PS1) settings and gamepad bindings.
extension Presets {
    /// Keyboard defaults DuckStation writes into a fresh file, followed by an SDL gamepad.
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

    /// Bindings for DuckStation's SDL device `device`, which is SDL's player index: controllers
    /// are numbered in connection order.
    private static func sdlPad(face: (south: String, east: String, west: String, north: String),
                               device: Int) -> [String: String] {
        let pad = [
            "Up": "DPadUp", "Right": "DPadRight", "Down": "DPadDown", "Left": "DPadLeft",
            "Cross": face.south, "Circle": face.east, "Square": face.west,
            "Triangle": face.north, "Select": "Back", "Start": "Start", "Analog": "Guide",
            "L1": "LeftShoulder", "R1": "RightShoulder", "L2": "+LeftTrigger", "R2": "+RightTrigger",
            "L3": "LeftStick", "R3": "RightStick",
            "LUp": "-LeftY", "LRight": "+LeftX", "LDown": "+LeftY", "LLeft": "-LeftX",
            "RUp": "-RightY", "RRight": "+RightX", "RDown": "+RightY", "RLeft": "-RightX",
            "LargeMotor": "LargeMotor", "SmallMotor": "SmallMotor",
        ]
        return pad.mapValues { "SDL-\(device)/\($0)" }
    }

    /// Select + Start on a gamepad quits back to Arcadia.
    private static let quitCombo = "SDL-0/Back & SDL-0/Start"

    /// DuckStation's `[PadN]` sections: Pad1 and Pad2 are ports 1 and 2, and with a multitap in
    /// port 1 its slots 1B–1D are Pad3–Pad5. More than two players therefore share a multitap
    /// in port 1 (slots 1A–1D), the way four-player PS1 games expect it.
    static func duckStationPads(_ gamepads: [Gamepad], keyboard: [String: String] = [:])
        -> (multitap: String, pads: [(section: String, entries: [(String, String)])]) {
        let players = players(gamepads).count
        let slots = players > 2 ? [1, 3, 4, 5] : [1, 2]
        let pads = (1...8).map { number -> (section: String, entries: [(String, String)]) in
            // Player 1 always has a controller: the keyboard plus the first gamepad once one is connected.
            guard let player = slots.firstIndex(of: number), player == 0 || player < players else {
                return ("Pad\(number)", [("Type", "None")])
            }
            let bindings = dualShockBindings(keyboard: player == 0 ? keyboard : [:],
                                             pad: sdlPad(face: ("A", "B", "X", "Y"), device: player))
            return ("Pad\(number)", [("Type", "AnalogController")] + bindings)
        }
        return (players > 2 ? "Port1Only" : "Disabled", pads)
    }

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
            ini.set(duckStationAchievements(context.achievements), section: "Cheevos")
            ini.set([
                "Directory": memoryCards.path,
                "Card1Type": "PerGameTitle",
                "Card2Type": "None",
            ], section: "MemoryCards")
            ini.set("SDL", "true", section: "InputSources")

            var keyboard = keyboardPad
            keyboard.merge(["Up": "Keyboard/UpArrow", "Right": "Keyboard/RightArrow", "Down": "Keyboard/DownArrow",
                            "Left": "Keyboard/LeftArrow", "Start": "Keyboard/Enter"]) { $1 }
            let ports = duckStationPads(context.gamepads, keyboard: keyboard)
            ini.set("MultitapMode", ports.multitap, section: "ControllerPorts")
            for pad in ports.pads { ini.replaceSection(pad.section, with: pad.entries) }
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
}

extension Presets {
    /// Picks a value for the current graphics scale (1–4) from a four-entry table.
    static func pick<T>(_ scale: Int, _ table: [T]) -> T {
        table[min(max(scale, 1), table.count) - 1]
    }
}

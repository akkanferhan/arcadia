import Foundation

/// Controller mappings for emulators that bind one specific device by name or GUID
/// (Dolphin, Cemu, RPCS3) or by raw joystick numbers (melonDS). Up to four connected
/// controllers become players 1–4 in connection order; without one, each emulator keeps its
/// keyboard defaults.
extension Presets {
    /// Players Arcadia maps; every multiplayer console it runs has four ports.
    static let maxPlayers = 4

    /// The controllers that become players 1–4.
    static func players(_ gamepads: [Gamepad]) -> [Gamepad] { Array(gamepads.prefix(maxPlayers)) }

    /// The number of a controller among the connected ones that share `key` with it, from 0.
    /// Emulators tell identical controllers apart this way.
    static func ordinal(of index: Int, in gamepads: [Gamepad], by key: (Gamepad) -> String) -> Int {
        gamepads[..<index].filter { key($0) == key(gamepads[index]) }.count
    }

    // MARK: Dolphin

    /// Dolphin's own "SDL Gamepad" profile, used if the installed Dolphin lacks it.
    private static let dolphinGameCubeProfile: [(String, String)] = [
        ("Buttons/A", "`Button A`"), ("Buttons/B", "`Button B`"), ("Buttons/X", "`Button X`"),
        ("Buttons/Y", "`Button Y`"), ("Buttons/Z", "`Shoulder R`"), ("Buttons/Start", "`Start`"),
        ("Main Stick/Up", "`Left Y+`"), ("Main Stick/Down", "`Left Y-`"),
        ("Main Stick/Left", "`Left X-`"), ("Main Stick/Right", "`Left X+`"), ("Main Stick/Calibration", "100.00"),
        ("C-Stick/Up", "`Right Y+`"), ("C-Stick/Down", "`Right Y-`"),
        ("C-Stick/Left", "`Right X-`"), ("C-Stick/Right", "`Right X+`"), ("C-Stick/Calibration", "100.00"),
        ("Triggers/L", "`Trigger L`"), ("Triggers/R", "`Trigger R`"),
        ("Triggers/L-Analog", "`Trigger L`"), ("Triggers/R-Analog", "`Trigger R`"),
        ("D-Pad/Up", "`Pad N`"), ("D-Pad/Down", "`Pad S`"), ("D-Pad/Left", "`Pad W`"), ("D-Pad/Right", "`Pad E`"),
        ("Rumble/Motor", "`Motor L` | `Motor R`"),
    ]

    /// A Wii Remote with Nunchuk on a gamepad: right stick points, left stick is the Nunchuk.
    private static let dolphinWiimote: [(String, String)] = [
        ("Source", "1"), ("Extension", "Nunchuk"),
        ("Buttons/A", "`Button A`"), ("Buttons/B", "`Trigger R`"), ("Buttons/1", "`Button X`"),
        ("Buttons/2", "`Button Y`"), ("Buttons/-", "`Back`"), ("Buttons/+", "`Start`"), ("Buttons/Home", "`Guide`"),
        ("D-Pad/Up", "`Pad N`"), ("D-Pad/Down", "`Pad S`"), ("D-Pad/Left", "`Pad W`"), ("D-Pad/Right", "`Pad E`"),
        ("IR/Up", "`Right Y+`"), ("IR/Down", "`Right Y-`"), ("IR/Left", "`Right X-`"), ("IR/Right", "`Right X+`"),
        ("Shake/X", "`Button B`"), ("Shake/Y", "`Button B`"), ("Shake/Z", "`Button B`"),
        ("Nunchuk/Buttons/C", "`Shoulder L`"), ("Nunchuk/Buttons/Z", "`Trigger L`"),
        ("Nunchuk/Stick/Up", "`Left Y+`"), ("Nunchuk/Stick/Down", "`Left Y-`"),
        ("Nunchuk/Stick/Left", "`Left X-`"), ("Nunchuk/Stick/Right", "`Left X+`"),
        ("Rumble/Motor", "`Motor L` | `Motor R`"),
    ]

    /// Dolphin names SDL devices "SDL/<index among same-named devices>/<SDL gamepad name>".
    static func dolphinDevice(player: Int, of gamepads: [Gamepad]) -> String {
        "SDL/\(ordinal(of: player, in: gamepads, by: \.name))/\(gamepads[player].name)"
    }

    static func dolphinControllers(_ gamepads: [Gamepad], install: URL, config: URL) throws {
        let players = players(gamepads)
        // GameCube ports 2–4 hold a standard controller (SI device 6) only while a player has one.
        try INIFile.update(config.appendingPathComponent("Dolphin.ini")) { ini in
            for port in 1..<maxPlayers {
                ini.set("SIDevice\(port)", port < players.count ? "6" : "0", section: "Core")
            }
        }

        // Arcadia writes these files whole; missing ones make Dolphin fall back to its keyboard defaults.
        let files = ["GCPadNew.ini", "WiimoteNew.ini", "Hotkeys.ini"].map { config.appendingPathComponent($0) }
        for file in files { try? FileManager.default.removeItem(at: file) }
        guard !players.isEmpty else { return }

        let bundled = install.appendingPathComponent("Contents/Resources/Sys/Profiles/GCPad/SDL Gamepad.ini")
        var gameCube = dolphinGameCubeProfile
        if let text = try? String(contentsOf: bundled, encoding: .utf8) {
            let lines = text.components(separatedBy: .newlines).compactMap { line -> (String, String)? in
                guard let equals = line.firstIndex(of: "="), !line.hasPrefix("[") else { return nil }
                return (line[..<equals].trimmingCharacters(in: .whitespaces),
                        line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces))
            }
            if !lines.isEmpty { gameCube = lines }
        }

        let devices = players.indices.map { ("Device", dolphinDevice(player: $0, of: players)) }
        try INIFile.update(files[0]) { ini in
            for (player, device) in devices.enumerated() {
                ini.replaceSection("GCPad\(player + 1)", with: [device] + gameCube)
            }
        }
        // Wii Remotes without a player stay disconnected, Dolphin's default.
        try INIFile.update(files[1]) { ini in
            for (player, device) in devices.enumerated() {
                ini.replaceSection("Wiimote\(player + 1)", with: [device] + dolphinWiimote)
            }
        }
        // Select + Start on player 1's controller stops the game, which quits Dolphin in batch mode.
        try INIFile.update(files[2]) { $0.replaceSection("Hotkeys", with: [devices[0], ("General/Stop", "`Back` & `Start`")]) }
    }

    // MARK: Cemu

    /// Wii U GamePad buttons (Cemu mapping IDs) to SDL gamepad button IDs as Cemu reads them.
    private static let cemuGamePadMappings: [(Int, Int)] = [
        (1, 1), (2, 0), (3, 3), (4, 2), (5, 9), (6, 10), (7, 42), (8, 43), (9, 6), (10, 4),
        (11, 11), (12, 12), (13, 13), (14, 14), (15, 7), (16, 8),
        (17, 45), (18, 39), (19, 44), (20, 38), (21, 47), (22, 41), (23, 46), (24, 40), (27, 5),
    ]

    /// The same layout on a Wii U Pro Controller, whose mapping IDs put Home before the D-pad.
    private static let cemuProMappings: [(Int, Int)] = [
        (1, 1), (2, 0), (3, 3), (4, 2), (5, 9), (6, 10), (7, 42), (8, 43), (9, 6), (10, 4), (11, 5),
        (12, 11), (13, 12), (14, 13), (15, 14), (16, 7), (17, 8),
        (18, 45), (19, 39), (20, 44), (21, 38), (22, 47), (23, 41), (24, 46), (25, 40),
    ]

    /// One `controllerN.xml` per player: player 1 holds the Wii U GamePad, the others Pro Controllers.
    static func cemuProfiles(_ gamepads: [Gamepad]) -> [String] {
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let range = "<deadzone>0.25</deadzone><range>1</range>"
        let players = players(gamepads)
        return players.indices.map { player in
            let pad = players[player]
            let gamePad = player == 0
            let mappings = (gamePad ? cemuGamePadMappings : cemuProMappings)
                .map { "<entry><mapping>\($0.0)</mapping><button>\($0.1)</button></entry>" }.joined()
            let type = gamePad ? "<type>Wii U GamePad</type>\n<toggle_display>0</toggle_display>"
                : "<type>Wii U Pro Controller</type>"
            // Cemu identifies SDL controllers as "<index among same-GUID devices>_<GUID>".
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <emulated_controller>
            \(type)
            <controller>
            <api>SDLController</api>
            <uuid>\(ordinal(of: player, in: players, by: \.guid))_\(pad.guid)</uuid>
            <display_name>\(escaped(pad.name))</display_name>
            <rumble>0</rumble>
            <axis>\(range)</axis>
            <rotation>\(range)</rotation>
            <trigger>\(range)</trigger>
            <mappings>\(mappings)</mappings>
            </controller>
            </emulated_controller>

            """
        }
    }

    static func cemuControllers(_ gamepads: [Gamepad],
                                folder: URL = applicationSupport.appendingPathComponent("Cemu/controllerProfiles")) throws {
        let profiles = cemuProfiles(gamepads)
        guard !profiles.isEmpty else { return } // Cemu keeps its own setup
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (player, xml) in profiles.enumerated() {
            try xml.write(to: folder.appendingPathComponent("controller\(player).xml"), atomically: true, encoding: .utf8)
        }
        // Players without a controller this time are unplugged.
        for player in profiles.count..<maxPlayers {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("controller\(player).xml"))
        }
    }

    // MARK: RPCS3

    /// RPCS3 names SDL devices "<SDL gamepad name> <number among same-named devices, from 1>"
    /// and fills in the button layout itself once it knows the device.
    static func rpcs3Input(_ gamepads: [Gamepad]) -> String? {
        let players = players(gamepads)
        guard !players.isEmpty else { return nil }
        return players.indices.map { player in
            let name = players[player].name.replacingOccurrences(of: "\"", with: "\\\"")
            return """
            Player \(player + 1) Input:
              Handler: SDL
              Device: "\(name) \(ordinal(of: player, in: players, by: \.name) + 1)"

            """
        }.joined()
    }

    static func rpcs3Controllers(_ gamepads: [Gamepad], root: URL) throws {
        let file = root.appendingPathComponent("input_configs/global/Default.yml")
        guard let yaml = rpcs3Input(gamepads) else {
            try? FileManager.default.removeItem(at: file) // RPCS3 then uses the keyboard
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: Flycast

    /// Flycast gives SDL controller N maple port N, but by default only port A has a controller
    /// plugged in. Device type 0 is a controller, 1 a VMU and 10 an empty slot.
    static func flycastPorts(players: Int) -> [String: String] {
        var values: [String: String] = [:]
        for port in 2...maxPlayers {
            let used = port <= players
            values["device\(port)"] = used ? "0" : "10"
            values["device\(port).1"] = used ? "1" : "10"
            values["device\(port).2"] = "10"
        }
        return values
    }

    // MARK: melonDS

    /// melonDS binds raw SDL joystick inputs: a button or hat in the low 16 bits (0xFFFF for
    /// none) and optionally an axis as 0x10000 | axis << 24 | direction << 20.
    static func melonDSJoystick(_ pad: Gamepad?) -> [(String, Int)] {
        let names = ["A", "B", "X", "Y", "L", "R", "Select", "Start", "Up", "Down", "Left", "Right"]
        guard let pad else { return names.map { ($0, -1) } }

        func button(_ button: SDL_GamepadButton) -> Int {
            switch pad.buttons[button] {
            case .button(let index): index
            case .hat(let hat, let mask): 0x100 | (hat << 4) | mask
            default: 0xFFFF
            }
        }
        func stick(_ axis: SDL_GamepadAxis, negative: Bool) -> Int {
            guard case .axis(let index) = pad.axes[axis] else { return 0 }
            return 0x10000 | (index << 24) | ((negative ? 1 : 0) << 20)
        }
        func combined(_ code: Int, _ axis: Int) -> Int {
            code == 0xFFFF && axis == 0 ? -1 : code | axis
        }
        // Nintendo layout: A is the right face button, B the bottom one.
        let codes: [String: Int] = [
            "A": button(SDL_GAMEPAD_BUTTON_EAST), "B": button(SDL_GAMEPAD_BUTTON_SOUTH),
            "X": button(SDL_GAMEPAD_BUTTON_NORTH), "Y": button(SDL_GAMEPAD_BUTTON_WEST),
            "L": button(SDL_GAMEPAD_BUTTON_LEFT_SHOULDER), "R": button(SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER),
            "Select": button(SDL_GAMEPAD_BUTTON_BACK), "Start": button(SDL_GAMEPAD_BUTTON_START),
            "Up": combined(button(SDL_GAMEPAD_BUTTON_DPAD_UP), stick(SDL_GAMEPAD_AXIS_LEFTY, negative: true)),
            "Down": combined(button(SDL_GAMEPAD_BUTTON_DPAD_DOWN), stick(SDL_GAMEPAD_AXIS_LEFTY, negative: false)),
            "Left": combined(button(SDL_GAMEPAD_BUTTON_DPAD_LEFT), stick(SDL_GAMEPAD_AXIS_LEFTX, negative: true)),
            "Right": combined(button(SDL_GAMEPAD_BUTTON_DPAD_RIGHT), stick(SDL_GAMEPAD_AXIS_LEFTX, negative: false)),
        ]
        return names.map { ($0, codes[$0] == 0xFFFF ? -1 : codes[$0]!) }
    }
}

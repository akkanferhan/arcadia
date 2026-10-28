import Foundation
import Testing
@testable import Arcadia

@Suite struct MultiplayerMappingTests {
    private func pad(_ name: String, _ guid: String) -> Gamepad {
        Gamepad(name: name, guid: guid, buttons: [:], axes: [:])
    }

    private let dualSense = "PS5 Controller"
    private let xbox = "Xbox Wireless Controller"
    private var twoIdentical: [Gamepad] { [pad(dualSense, "aaaa"), pad(dualSense, "aaaa")] }
    private var five: [Gamepad] {
        [pad(dualSense, "aaaa"), pad(xbox, "bbbb"), pad(dualSense, "aaaa"), pad(xbox, "bbbb"), pad(xbox, "bbbb")]
    }

    @Test func identicalControllersAreNumberedApart() {
        #expect(Presets.ordinal(of: 0, in: five, by: \.name) == 0)
        #expect(Presets.ordinal(of: 2, in: five, by: \.name) == 1)
        #expect(Presets.ordinal(of: 4, in: five, by: \.guid) == 2)
        #expect(Presets.players(five).count == 4)
    }

    // MARK: DuckStation

    @Test func duckStationUsesBothPortsForTwoPlayers() {
        let ports = Presets.duckStationPads(twoIdentical, keyboard: ["Cross": "Keyboard/K"])
        #expect(ports.multitap == "Disabled")
        let pads = Dictionary(uniqueKeysWithValues: ports.pads.map { ($0.section, $0.entries) })
        #expect(pads.count == 8)
        #expect(pads["Pad1"]!.contains { $0 == ("Cross", "Keyboard/K") })
        #expect(pads["Pad1"]!.contains { $0 == ("Cross", "SDL-0/A") })
        #expect(pads["Pad2"]!.first! == ("Type", "AnalogController"))
        #expect(pads["Pad2"]!.contains { $0 == ("Cross", "SDL-1/A") })
        #expect(!pads["Pad2"]!.contains { $0.1.hasPrefix("Keyboard/") })
        #expect(pads["Pad3"]!.map(\.1) == ["None"])
    }

    @Test func duckStationPutsFourPlayersOnAMultitap() {
        let ports = Presets.duckStationPads(five)
        #expect(ports.multitap == "Port1Only")
        let pads = Dictionary(uniqueKeysWithValues: ports.pads.map { ($0.section, $0.entries) })
        // Slots 1A, 1B, 1C and 1D.
        #expect(pads["Pad1"]!.contains { $0 == ("Start", "SDL-0/Start") })
        #expect(pads["Pad3"]!.contains { $0 == ("Start", "SDL-1/Start") })
        #expect(pads["Pad4"]!.contains { $0 == ("Start", "SDL-2/Start") })
        #expect(pads["Pad5"]!.contains { $0 == ("Start", "SDL-3/Start") })
        for empty in ["Pad2", "Pad6", "Pad7", "Pad8"] { #expect(pads[empty]!.map(\.1) == ["None"]) }
    }

    @Test func duckStationKeepsPlayerOneWithoutControllers() {
        let ports = Presets.duckStationPads([], keyboard: ["Cross": "Keyboard/K"])
        #expect(ports.multitap == "Disabled")
        #expect(ports.pads[0].entries.first! == ("Type", "AnalogController"))
        #expect(ports.pads[0].entries.contains { $0 == ("Cross", "Keyboard/K") })
        #expect(ports.pads.dropFirst().allSatisfy { $0.entries.map(\.1) == ["None"] })
    }

    // MARK: Dolphin

    @Test func dolphinBindsEveryPlayerToItsOwnDevice() throws {
        let folder = TemporaryFolder()
        let config = folder.folder("Config")
        let pads = [pad(dualSense, "aaaa"), pad(xbox, "bbbb"), pad(dualSense, "aaaa")]
        try Presets.dolphinControllers(pads, install: folder.url, config: config)

        let gameCube = folder.read("Config/GCPadNew.ini")
        #expect(gameCube.contains("[GCPad1]\nDevice = SDL/0/PS5 Controller\n"))
        #expect(gameCube.contains("[GCPad2]\nDevice = SDL/0/Xbox Wireless Controller\n"))
        #expect(gameCube.contains("[GCPad3]\nDevice = SDL/1/PS5 Controller\n"))
        #expect(!gameCube.contains("[GCPad4]"))
        let wii = folder.read("Config/WiimoteNew.ini")
        #expect(wii.contains("[Wiimote3]\nDevice = SDL/1/PS5 Controller\nSource = 1\n"))
        #expect(!wii.contains("[Wiimote4]"))
        #expect(folder.read("Config/Hotkeys.ini").contains("Device = SDL/0/PS5 Controller"))
        let core = folder.read("Config/Dolphin.ini")
        #expect(core.contains("SIDevice1 = 6\nSIDevice2 = 6\nSIDevice3 = 0"))

        // Unplugging everything brings back the keyboard defaults and empty GameCube ports.
        try Presets.dolphinControllers([], install: folder.url, config: config)
        #expect(!FileManager.default.fileExists(atPath: config.appendingPathComponent("GCPadNew.ini").path))
        #expect(folder.read("Config/Dolphin.ini").contains("SIDevice1 = 0\nSIDevice2 = 0\nSIDevice3 = 0"))
    }

    // MARK: Cemu

    @Test func cemuGivesExtraPlayersProControllers() throws {
        let profiles = Presets.cemuProfiles(twoIdentical + [pad(xbox, "bbbb")])
        #expect(profiles.count == 3)
        #expect(profiles[0].contains("<type>Wii U GamePad</type>"))
        #expect(profiles[0].contains("<uuid>0_aaaa</uuid>"))
        #expect(profiles[1].contains("<type>Wii U Pro Controller</type>"))
        #expect(!profiles[1].contains("toggle_display"))
        #expect(profiles[1].contains("<uuid>1_aaaa</uuid>"))
        #expect(profiles[2].contains("<uuid>0_bbbb</uuid>"))
        // Pro Controller: Home is mapping 11 (Guide), the D-pad starts at 12.
        #expect(profiles[1].contains("<entry><mapping>11</mapping><button>5</button></entry>"))
        #expect(profiles[1].contains("<entry><mapping>12</mapping><button>11</button></entry>"))
        // GamePad: Home is mapping 27.
        #expect(profiles[0].contains("<entry><mapping>27</mapping><button>5</button></entry>"))
        for profile in profiles { _ = try XMLDocument(xmlString: profile) }
    }

    @Test func cemuRemovesPlayersThatLeft() throws {
        let folder = TemporaryFolder()
        try Presets.cemuControllers(five, folder: folder.url)
        for player in 0..<4 { #expect(!folder.read("controller\(player).xml").isEmpty) }
        #expect(folder.read("controller4.xml").isEmpty)

        try Presets.cemuControllers([pad(xbox, "bbbb")], folder: folder.url)
        #expect(folder.read("controller0.xml").contains("<uuid>0_bbbb</uuid>"))
        for player in 1..<4 { #expect(folder.read("controller\(player).xml").isEmpty) }

        // Without controllers Cemu keeps whatever it has.
        try Presets.cemuControllers([], folder: folder.url)
        #expect(folder.read("controller0.xml").contains("<uuid>0_bbbb</uuid>"))
    }

    // MARK: RPCS3

    @Test func rpcs3CountsSameNamedControllersFromOne() {
        let yaml = Presets.rpcs3Input(twoIdentical + [pad(xbox, "bbbb")])
        #expect(yaml == """
        Player 1 Input:
          Handler: SDL
          Device: "PS5 Controller 1"
        Player 2 Input:
          Handler: SDL
          Device: "PS5 Controller 2"
        Player 3 Input:
          Handler: SDL
          Device: "Xbox Wireless Controller 1"

        """)
        #expect(Presets.rpcs3Input([]) == nil)
    }

    // MARK: Flycast

    @Test func flycastPlugsControllersIntoUsedPorts() {
        let two = Presets.flycastPorts(players: 2)
        #expect(two["device2"] == "0")
        #expect(two["device2.1"] == "1")
        #expect(two["device3"] == "10")
        #expect(two["device4.1"] == "10")
        #expect(Presets.flycastPorts(players: 0).filter { $0.value != "10" }.isEmpty)
    }
}

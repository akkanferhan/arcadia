import Foundation
import Testing
@testable import Arcadia

@Suite struct GameTests {
    @Test func tidiesNoIntroNames() {
        let game = Game(url: URL(fileURLWithPath: "/g/Legend of Zelda, The - Ocarina of Time (USA) (Rev 1).z64"), systemID: "n64")
        #expect(game.title == "Legend of Zelda, The - Ocarina of Time")
        #expect(game.region == "USA")
        #expect(Game.tidy("Super_Metroid [!]") == "Super Metroid")
    }

    @Test func readsTitlesFromParamSFO() {
        // Minimal PARAM.SFO: header, one index entry, key table, data table.
        var sfo = Data([0x00, 0x50, 0x53, 0x46, 0x01, 0x01, 0x00, 0x00])
        let keyTable = 20 + 16, dataTable = keyTable + 8
        for value in [keyTable, dataTable, 1] { sfo.append(contentsOf: withUnsafeBytes(of: UInt32(value).littleEndian, Array.init)) }
        let title = Data("Demon's Souls\0".utf8)
        sfo.append(contentsOf: [0x00, 0x00, 0x04, 0x02])
        for value in [title.count, title.count, 0] { sfo.append(contentsOf: withUnsafeBytes(of: UInt32(value).littleEndian, Array.init)) }
        sfo.append(Data("TITLE\0\0\0".utf8))
        sfo.append(title)
        #expect(PlayStationFolder.sfoValue("TITLE", in: sfo) == "Demon's Souls")
        #expect(PlayStationFolder.sfoValue("CATEGORY", in: sfo) == nil)
    }
}

@Suite struct LibraryScanTests {
    @Test func findsGamesBySystemFolder() {
        let folder = TemporaryFolder()
        folder.write("snes/Super Mario World (USA).sfc", Data(count: 16))
        folder.write("snes/Sub Folder/Chrono Trigger (USA).sfc", Data(count: 16))
        folder.write("snes/readme.txt", text: "not a game")
        folder.write("gba/Metroid Fusion (USA).gba", Data(count: 16))
        let games = Library.scan(folder.url)
        #expect(games.map(\.title) == ["Chrono Trigger", "Metroid Fusion", "Super Mario World"])
        #expect(Set(games.map(\.systemID)) == ["snes", "gba"])
    }

    @Test func playlistsHideTheirDiscs() {
        let folder = TemporaryFolder()
        folder.write("ps1/Metal Gear Solid (USA).m3u", text: "Metal Gear Solid (USA) (Disc 1).cue\n")
        folder.write("ps1/Metal Gear Solid (USA) (Disc 1).cue", text: "FILE")
        folder.write("ps1/Metal Gear Solid (USA) (Disc 2).cue", text: "FILE")
        let games = Library.scan(folder.url)
        #expect(games.count == 1)
        #expect(games.first?.url.pathExtension == "m3u")
    }

    @Test func linkedGameFoldersCountAsGames() throws {
        let folder = TemporaryFolder()
        let installed = folder.folder("elsewhere/CUSA00001")
        folder.write("elsewhere/CUSA00001/eboot.bin", Data(count: 16))
        folder.folder("library/ps4")
        try FileManager.default.createSymbolicLink(at: folder.url.appendingPathComponent("library/ps4/CUSA00001"),
                                                   withDestinationURL: installed)
        let games = Library.scan(folder.url.appendingPathComponent("library"))
        #expect(games.map(\.systemID) == ["ps4"])
    }
}

@Suite struct BiosTests {
    @Test func builtInBiosIsUsedUntilARealOneIsAdded() throws {
        let folder = TemporaryFolder()
        let bios = folder.folder("bios")
        let ps1 = try #require(GameSystem.with(id: "ps1"))
        #expect(Bios.status(of: ps1, bios: bios) == .builtIn)
        #expect(Bios.player(for: ps1, bios: bios).core == "pcsx_rearmed")

        folder.write("bios/ps1/scph5501.bin", Data(count: 524_288))
        #expect(Bios.status(of: ps1, bios: bios) == .ready)
        #expect(Bios.player(for: ps1, bios: bios).emulator.id == "duckstation")
    }

    @Test func statusForOtherSystems() throws {
        let folder = TemporaryFolder()
        let bios = folder.folder("bios")
        #expect(Bios.status(of: try #require(GameSystem.with(id: "ps2")), bios: bios) == .missing)
        #expect(Bios.status(of: try #require(GameSystem.with(id: "ps3")), bios: bios) == .willDownload)
        #expect(Bios.status(of: try #require(GameSystem.with(id: "snes")), bios: bios) == .notNeeded)

        // Xbox needs both the boot ROM and the flash BIOS.
        let xbox = try #require(GameSystem.with(id: "xbox"))
        folder.write("bios/xbox/mcpx.bin", Data(count: 512))
        #expect(Bios.status(of: xbox, bios: bios) == .missing)
        folder.write("bios/xbox/flash.bin", Data(count: 1_048_576))
        #expect(Bios.status(of: xbox, bios: bios) == .ready)
    }

    @Test func droppedFilesAreSortedByNameAndSize() {
        let folder = TemporaryFolder()
        let bios = folder.url.appendingPathComponent("bios")
        func destination(_ name: String, size: Int) -> String? {
            let file = folder.write("drop/\(name)", Data(count: size))
            return Bios.destination(for: file, bios: bios).map { String($0.path.dropFirst(bios.path.count)) }
        }
        #expect(destination("scph5501.bin", size: 524_288) == "/ps1/scph5501.bin")
        #expect(destination("sega_101.bin", size: 524_288) == "/sega_101.bin")
        #expect(destination("ps2-0230a.bin", size: 4_194_304) == "/ps2/ps2-0230a.bin")
        #expect(destination("mcpx_1.0.bin", size: 512) == "/xbox/mcpx_1.0.bin")
        #expect(destination("PS3UPDAT.PUP", size: 2048) == "/ps3/PS3UPDAT.PUP")
        #expect(destination("syscard3.pce", size: 262_144) == "/syscard3.pce")
        #expect(destination("notes.txt", size: 10) == nil)
    }
}

@Suite struct GamepadMappingTests {
    @Test func melonDSCodesCombineDPadWithLeftStick() throws {
        let pad = Gamepad(
            name: "PS5 Controller", guid: "0",
            buttons: [SDL_GAMEPAD_BUTTON_SOUTH: .button(0), SDL_GAMEPAD_BUTTON_EAST: .button(1),
                      SDL_GAMEPAD_BUTTON_DPAD_UP: .button(11), SDL_GAMEPAD_BUTTON_DPAD_RIGHT: .hat(0, mask: 2)],
            axes: [SDL_GAMEPAD_AXIS_LEFTX: .axis(0), SDL_GAMEPAD_AXIS_LEFTY: .axis(1)])
        let codes = Dictionary(uniqueKeysWithValues: Presets.melonDSJoystick(pad))
        #expect(codes["A"] == 1)     // Nintendo A is the right face button
        #expect(codes["B"] == 0)
        #expect(codes["Up"] == 0x10000 | (1 << 24) | (1 << 20) | 11)
        #expect(codes["Right"] == 0x10000 | 0x100 | 2)
        #expect(codes["Select"] == -1)

        #expect(Presets.melonDSJoystick(nil).allSatisfy { $0.1 == -1 })
    }

    @Test func graphicsScaleTablePicksByScale() {
        #expect(Presets.pick(1, [2, 3, 4, 5]) == 2)
        #expect(Presets.pick(4, [2, 3, 4, 5]) == 5)
        #expect(Presets.pick(9, [2, 3, 4, 5]) == 5)
    }
}

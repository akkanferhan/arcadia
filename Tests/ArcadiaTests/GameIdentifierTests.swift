import Foundation
import Testing
@testable import Arcadia

@Suite struct GameIdentifierTests {
    private func system(of file: URL) -> String? {
        if case .game(let match) = GameIdentifier.identify(file) { return match.systemID }
        return nil
    }

    @Test func recognisesNintendoDiscsByTheirMagicNumbers() {
        let folder = TemporaryFolder()
        let gameCube = folder.write("Metroid Prime.iso", DiscFixture.bytes(65536, setting: [(0x1C, [0xC2, 0x33, 0x9F, 0x3D])]))
        let wii = folder.write("Wii Sports.iso", DiscFixture.bytes(65536, setting: [(0x18, [0x5D, 0x1C, 0x9E, 0xA3])]))
        #expect(system(of: gameCube) == "gc")
        #expect(system(of: wii) == "wii")
    }

    @Test func tellsPS1FromPS2BySystemConfig() {
        let folder = TemporaryFolder()
        let ps2 = folder.write("SotC.iso", DiscFixture.iso([("SYSTEM.CNF", false, Data("BOOT2 = cdrom0:\\SCUS_974.72;1\r\n".utf8))]))
        let ps1 = folder.write("Crash.iso", DiscFixture.iso([("SYSTEM.CNF", false, Data("BOOT = cdrom:\\SCUS_949.00;1\r\n".utf8))]))
        #expect(system(of: ps2) == "ps2")
        #expect(system(of: ps1) == "ps1")
    }

    @Test func recognisesOtherDiscs() {
        let folder = TemporaryFolder()
        let psp = folder.write("Patapon.iso", DiscFixture.iso([("PSP_GAME", true, Data())], system: "PSP GAME"))
        let saturn = folder.write("Nights.iso", DiscFixture.bytes(4096, setting: [(0, Array("SEGA SEGASATURN ".utf8))]))
        let xbox = folder.write("Halo.iso", DiscFixture.bytes(0x10800, setting: [(0x10000, Array("MICROSOFT*XBOX*MEDIA".utf8))]))
        #expect(system(of: psp) == "psp")
        #expect(system(of: saturn) == "saturn")
        #expect(system(of: xbox) == "xbox")
    }

    @Test func cueSheetsBringTheirTracks() throws {
        let folder = TemporaryFolder()
        let image = DiscFixture.iso([("SYSTEM.CNF", false, Data("BOOT = cdrom:\\SCUS_949.00;1\r\n".utf8))], raw: true)
        let bin = folder.write("PS1/Crash (USA).bin", image)
        let cue = folder.write("PS1/Crash (USA).cue", text: "FILE \"Crash (USA).bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n")
        guard case .game(let match) = GameIdentifier.identify(cue) else { Issue.record("cue not recognised"); return }
        #expect(match.systemID == "ps1")
        #expect(match.companions.map(\.lastPathComponent) == ["Crash (USA).bin"])
        // The track itself is added through its cue sheet.
        guard case .ignore = GameIdentifier.identify(bin) else { Issue.record("listed track not ignored"); return }
    }

    @Test func recognisesCartridgesAndArchives() throws {
        let folder = TemporaryFolder()
        let megaDrive = folder.write("Sonic.bin", DiscFixture.bytes(131_072, setting: [(0x100, Array("SEGA".utf8))]))
        #expect(system(of: megaDrive) == "megadrive")
        #expect(system(of: folder.write("Zelda.sfc", Data(count: 2048))) == "snes")

        let rom = folder.write("zip/Super Mario World.sfc", Data(count: 2048))
        let zip = folder.url.appendingPathComponent("Super Mario World.zip")
        let process = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-c", "-k", rom.path, zip.path])
        process.waitUntilExit()
        #expect(system(of: zip) == "snes")
    }

    @Test func guessesFromFolderNamesAndMarksForReview() {
        let folder = TemporaryFolder()
        let hinted = folder.write("PS2 Games/Mystery.iso", Data(count: 65536))
        let unknown = folder.write("misc/Mystery.iso", Data(count: 65536))
        guard case .game(let match) = GameIdentifier.identify(hinted) else { Issue.record("hint not used"); return }
        #expect(match.systemID == "ps2")
        #expect(match.guessed)
        guard case .unknown = GameIdentifier.identify(unknown) else { Issue.record("expected unknown"); return }
    }

    @Test func recognisesInstalledPlayStationFolders() {
        let folder = TemporaryFolder()
        folder.write("BLUS30001/PS3_GAME/PARAM.SFO", Data("\0PSF".utf8))
        folder.write("CUSA00001/sce_sys/param.sfo", Data("\0PSF".utf8))
        folder.write("CUSA00001/eboot.bin", Data(count: 16))
        folder.write("PPSA00001/sce_sys/param.json", Data("{}".utf8))
        folder.write("PPSA00001/eboot.bin", Data(count: 16))
        #expect(GameIdentifier.identifyFolder(folder.url.appendingPathComponent("BLUS30001")) == "ps3")
        #expect(GameIdentifier.identifyFolder(folder.url.appendingPathComponent("CUSA00001")) == "ps4")
        #expect(GameIdentifier.identifyFolder(folder.url.appendingPathComponent("PPSA00001")) == "ps5")
        #expect(GameIdentifier.identifyFolder(folder.folder("Photos")) == nil)
    }
}

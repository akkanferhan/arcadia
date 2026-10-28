import Foundation
import Testing
@testable import Arcadia

/// Builds PARAM.SFO files with UTF-8 strings and 32-bit integers, laid out like Sony's.
enum SFOFixture {
    enum Value { case text(String), number(UInt32) }

    static func make(_ entries: [(String, Value)]) -> Data {
        func le16(_ value: Int) -> [UInt8] { withUnsafeBytes(of: UInt16(value).littleEndian, Array.init) }
        func le32(_ value: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(value).littleEndian, Array.init) }
        var keys = Data(), values = Data(), index = Data()
        for (key, value) in entries {
            let bytes: Data, format: Int
            switch value {
            case .text(let text): bytes = Data((text + "\0").utf8); format = 0x0204
            case .number(let number): bytes = Data(le32(Int(number))); format = 0x0404
            }
            index.append(contentsOf: le16(keys.count) + le16(format) + le32(bytes.count) + le32(bytes.count) + le32(values.count))
            keys.append(Data((key + "\0").utf8))
            values.append(bytes)
        }
        while keys.count % 4 != 0 { keys.append(0) }
        let keyTable = 20 + index.count, dataTable = keyTable + keys.count
        var sfo = Data([0x00, 0x50, 0x53, 0x46, 0x01, 0x01, 0x00, 0x00])
        sfo.append(contentsOf: le32(keyTable) + le32(dataTable) + le32(entries.count))
        return sfo + index + keys + values
    }

    static func vita(_ id: String = "PCSE00001", title: String = "Gravity Rush", category: String = "gd",
                     version: String = "01.00") -> Data {
        make([("APP_VER", .text(version)), ("CATEGORY", .text(category)), ("PSP2_DISP_VER", .text("03.600")),
              ("PSP2_SYSTEM_VER", .number(0x0360_0000)), ("STITLE", .text(title)), ("TITLE", .text(title)),
              ("TITLE_ID", .text(id))])
    }

    static func ps4(_ id: String = "CUSA00001", title: String = "Bloodborne") -> Data {
        make([("APP_TYPE", .number(1)), ("APP_VER", .text("01.00")), ("CATEGORY", .text("gd")),
              ("SYSTEM_VER", .number(0x0450_0000)), ("TITLE", .text(title)), ("TITLE_ID", .text(id))])
    }
}

/// Zips a folder with the zip tool that ships with macOS, like the tools that make `.vpk` files.
private func zip(_ folder: URL, to archive: URL, stored: Bool = false) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-q", "-r", "-X"] + (stored ? ["-0"] : []) + [archive.path, "."]
    process.currentDirectoryURL = folder
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 2000)

@Suite struct VitaDetectionTests {
    @Test func tellsVitaFromPS4ByTheSFO() {
        #expect(VitaGame.isVitaSFO(SFOFixture.vita()))
        #expect(!VitaGame.isVitaSFO(SFOFixture.ps4()))
        #expect(!VitaGame.isVitaSFO(Data("\0PSF".utf8)))
        #expect(PlayStationFolder.sfoKeys(in: SFOFixture.vita()).contains("PSP2_SYSTEM_VER"))
        #expect(PlayStationFolder.sfoValue("TITLE_ID", in: SFOFixture.vita()) == "PCSE00001")
        #expect(PlayStationFolder.sfoValue("TITLE", in: SFOFixture.ps4()) == "Bloodborne")
    }

    @Test func recognisesVitaAndPS4Folders() {
        let folder = TemporaryFolder()
        folder.write("PCSE00001/eboot.bin", Data(count: 16))
        folder.write("PCSE00001/sce_sys/param.sfo", SFOFixture.vita())
        folder.write("CUSA00001/eboot.bin", Data(count: 16))
        folder.write("CUSA00001/sce_sys/param.sfo", SFOFixture.ps4())
        folder.write("PCSE00002/eboot.bin", Data(count: 16))
        folder.write("PCSE00002/sce_sys/param.sfo", SFOFixture.vita("PCSE00002", category: "gp"))
        folder.write("PCSE00003/sce_sys/param.sfo", SFOFixture.vita("PCSE00003", category: "ac"))
        #expect(GameIdentifier.identifyFolder(folder.url.appendingPathComponent("PCSE00001")) == "psvita")
        #expect(GameIdentifier.identifyFolder(folder.url.appendingPathComponent("CUSA00001")) == "ps4")
        // Updates and add-ons are not games of their own, and never PS4 games.
        #expect(GameIdentifier.identifyFolder(folder.url.appendingPathComponent("PCSE00002")) == nil)
        #expect(GameIdentifier.identifyFolder(folder.url.appendingPathComponent("PCSE00003")) == nil)
    }

    @Test func readsPackagesWithTheirTitleAndIcon() throws {
        let folder = TemporaryFolder()
        folder.write("src/sce_sys/param.sfo", SFOFixture.vita(title: "Gravity\nRush"))
        folder.write("src/sce_sys/icon0.png", png)
        folder.write("src/eboot.bin", Data(count: 4096))
        for stored in [false, true] {
            let vpk = folder.url.appendingPathComponent("library/psvita/game-\(stored).vpk")
            try FileManager.default.createDirectory(at: vpk.deletingLastPathComponent(), withIntermediateDirectories: true)
            try zip(folder.url.appendingPathComponent("src"), to: vpk, stored: stored)

            guard case .game(let match) = GameIdentifier.identify(vpk) else { Issue.record("vpk not recognised"); return }
            #expect(match.systemID == "psvita")
            #expect(PlayStationFolder.title(in: vpk) == "Gravity Rush")
            #expect(VitaGame.packageIcon(vpk) == png)
            #expect(GameIdentifier.isCandidate(vpk))
        }
        let games = Library.scan(folder.url.appendingPathComponent("library"))
        #expect(games.map(\.title) == ["Gravity Rush", "Gravity Rush"])
        #expect(Set(games.map(\.systemID)) == ["psvita"])
    }

    @Test func packagesMayWrapTheGameInAFolder() throws {
        let folder = TemporaryFolder()
        folder.write("src/PCSE00001/sce_sys/param.sfo", SFOFixture.vita())
        folder.write("src/PCSE00001/sce_sys/package/work.bin", Data(count: 512))
        folder.write("src/PCSE00001/sce_sys/package/head.bin", Data(count: 512))
        // An update bundled next to the game does not hide it.
        folder.write("src/patch/sce_sys/param.sfo", SFOFixture.vita(category: "gp", version: "01.05"))
        let vpk = folder.url.appendingPathComponent("game.vpk")
        try zip(folder.url.appendingPathComponent("src"), to: vpk)

        let content = try #require(VitaGame.Content(vpk))
        #expect(content.titleID == "PCSE00001")
        #expect(content.version == "01.00")
        #expect(content.isGame && content.isEncrypted && content.hasLicense && !content.isVitamin)
    }

    @Test func otherZipsAreNotVitaGames() throws {
        let folder = TemporaryFolder()
        folder.write("src/readme.txt", text: "hello")
        let vpk = folder.url.appendingPathComponent("other.vpk")
        try zip(folder.url.appendingPathComponent("src"), to: vpk)
        guard case .ignore = GameIdentifier.identify(vpk) else { Issue.record("expected ignore"); return }
        #expect(ZipReader(folder.write("broken.vpk", Data(count: 100))) == nil)
    }
}

@Suite struct VitaFirmwareTests {
    /// Sony's list as served on 2026-10-28.
    static let list = """
    <?xml version="1.0" encoding="UTF-8"?>
    <update_data_list>
    <region id="us">
    <np level0_system_version="01.600.000" level1_system_version="03.740.000" level2_system_version="03.740.000" map="03.740.000" />
    <version system_version="03.740.000" label="3.74">
    <update_data update_type="full">
    <image size="133834240">http://dus01.psp2.update.playstation.net/update/psp2/image/2022_0209/rel_f2c7b12fe85496ec88a0391b514d6e3b/PSP2UPDAT.PUP?dest=us</image>
    </update_data>
    </version>
    <recovery spkg_type="systemdata">
    <image spkg_version="01.000.010" size="56778752">http://dus01.psp2.update.playstation.net/update/psp2/image/2022_0209/sd_59dcf059d3328fb67be7e51f8aa33418/PSP2UPDAT.PUP?dest=us</image>
    </recovery>
    <recovery spkg_type="preinst">
    <image spkg_version="01.000.000" size="128798720">http://dus01.psp2.update.playstation.net/update/psp2/image/2022_0209/pre_efd1ef6c1cc2fe92e72e9e783e421237/PSP2UPDAT.PUP?dest=us</image>
    </recovery>
    </region>
    </update_data_list>
    """

    @Test func findsSystemSoftwareAndFontsInSonysList() throws {
        let images = try #require(VitaFirmware.parse(Data(Self.list.utf8)))
        #expect(images.system.url.absoluteString.contains("/rel_f2c7b12fe85496ec88a0391b514d6e3b/PSP2UPDAT.PUP"))
        #expect(images.system.size == 133_834_240)
        #expect(images.fonts.url.absoluteString.contains("/sd_59dcf059d3328fb67be7e51f8aa33418/PSP2UPDAT.PUP"))
        #expect(images.fonts.size == 56_778_752)
        #expect(images[.fonts] == images.fonts)
    }

    @Test func acceptsOnlySonysServers() {
        let elsewhere = Self.list.replacingOccurrences(of: "dus01.psp2.update.playstation.net", with: "example.com")
        #expect(VitaFirmware.parse(Data(elsewhere.utf8)) == nil)
        #expect(VitaFirmware.parse(Data("<update_data_list/>".utf8)) == nil)
        #expect(VitaFirmware.parse(Data("not xml".utf8)) == nil)
    }

    @Test func readsInstallProgressFromVita3KsLog() {
        let log = "[info] Firmware installation progress: 20%\n[info] Firmware installation progress: 70%\n"
        #expect(VitaFirmware.installProgress(in: log) == 0.7)
        #expect(VitaFirmware.installProgress(in: "nothing") == nil)
    }

    @Test func installedPartsFollowVita3KsFolders() {
        let folder = TemporaryFolder()
        let fs = folder.folder("fs")
        folder.folder("fs/sa0")
        #expect(!VitaFirmware.isInstalled(.system, fs: fs))
        #expect(!VitaFirmware.isInstalled(.fonts, fs: fs))
        folder.write("fs/vs0/vsh/index.dat", Data(count: 4))
        folder.write("fs/sa0/data/font/pvf/ltn0.pvf", Data(count: 4))
        #expect(VitaFirmware.isInstalled(.system, fs: fs))
        #expect(VitaFirmware.isInstalled(.fonts, fs: fs))
    }

    @Test func biosCardShowsTheDownload() throws {
        let folder = TemporaryFolder()
        let bios = folder.folder("bios")
        let vita = try #require(GameSystem.with(id: "psvita"))
        #expect(Bios.status(of: vita, bios: bios) == .willDownload)
        folder.write("bios/psvita/PSVUPDAT.PUP", Data(count: 64))
        #expect(Bios.status(of: vita, bios: bios) == .willDownload)
        folder.write("bios/psvita/PSP2UPDAT.PUP", Data(count: 64))
        #expect(Bios.status(of: vita, bios: bios) == .ready)
        let dropped = folder.write("Downloads/PSVUPDAT.PUP", Data(count: 64))
        #expect(Bios.destination(for: dropped, bios: bios)?.path == bios.path + "/psvita/PSVUPDAT.PUP")
    }
}

@Suite struct Vita3KPresetTests {
    private final class Fixture {
        let folder = TemporaryFolder()
        var data: URL { folder.url.appendingPathComponent("Data/vita3k") }
        var fs: URL { data.appendingPathComponent("fs") }
        var install: URL { folder.url.appendingPathComponent("Emulators/vita3k/Vita3K.app") }

        init(firmware: Bool = true) {
            folder.folder("Emulators/vita3k/Vita3K.app/Contents/MacOS")
            if firmware {
                folder.write("Data/vita3k/fs/vs0/vsh/index.dat", Data(count: 4))
                folder.write("Data/vita3k/fs/sa0/data/font/pvf/ltn0.pvf", Data(count: 4))
            }
        }

        func context(game: URL, scale: Int = 2, fullscreen: Bool = true) -> PresetContext {
            PresetContext(emulator: Emulator.with(id: "vita3k")!, system: GameSystem.with(id: "psvita")!, game: game,
                          core: nil, install: install, bios: folder.folder("bios"), scale: scale, fullscreen: fullscreen)
        }

        func game(_ id: String = "PCSE00001", version: String = "01.00") -> URL {
            folder.write("library/psvita/\(id)/eboot.bin", Data(count: 16))
            folder.write("library/psvita/\(id)/sce_sys/param.sfo", SFOFixture.vita(id, version: version))
            return folder.url.appendingPathComponent("library/psvita/\(id)")
        }
    }

    @Test func writesTunedSettingsIntoVita3KsOwnConfig() async throws {
        let fixture = Fixture()
        // As yaml-cpp writes it: a document with start and end markers.
        fixture.folder.write("Data/vita3k/config.yml",
                             text: "---\nbackend-renderer: OpenGL\nresolution-multiplier: 1\nshow-welcome: true\nlle-modules:\n  []\naudio-volume: 80\n...\n")
        let launch = try await Presets.vita3k(fixture.context(game: fixture.game(), scale: 4, fullscreen: false), data: fixture.data)
        #expect(launch.arguments.isEmpty && launch.environment.isEmpty)

        let config = fixture.folder.read("Data/vita3k/config.yml")
        let lines = config.components(separatedBy: "\n")
        #expect(lines.first == "---")
        #expect(lines.filter { !$0.isEmpty }.last == "...")
        for line in ["backend-renderer: Vulkan", "resolution-multiplier: 3", "anisotropic-filtering: 16",
                     "show-welcome: false", "initial-setup: true", "check-for-updates-mode: 0",
                     "warn-missing-firmware: false", "discord-rich-presence: false", "boot-apps-full-screen: false",
                     "log-level: 2", "audio-volume: 80", "lle-modules:", "pref-path: \"\(fixture.fs.path)/\""] {
            #expect(lines.contains(line), "missing \(line)")
        }
        #expect(lines.filter { $0.hasPrefix("backend-renderer:") }.count == 1)

        // Portable mode: Vita3K finds Arcadia's data folder next to its app.
        let link = fixture.folder.url.appendingPathComponent("Emulators/vita3k/portable")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == fixture.data.path)
    }

    @Test func qualityScaleSetsTheResolution() {
        let fs = URL(fileURLWithPath: "/data/fs")
        func value(_ key: String, scale: Int) -> String? {
            Presets.vita3kSettings(scale: scale, fullscreen: true, fs: fs).first { $0.0 == key }?.1
        }
        #expect((1...4).map { value("resolution-multiplier", scale: $0) } == ["1", "1.5", "2", "3"])
        #expect(value("boot-apps-full-screen", scale: 1) == "true")
        #expect(value("pref-path", scale: 1) == "\"/data/fs/\"")
    }

    @Test func relinksAMovedDataFolder() throws {
        let fixture = Fixture()
        let link = fixture.folder.url.appendingPathComponent("Emulators/vita3k/portable")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.folder.folder("old"))
        try Presets.linkVita3KData(install: fixture.install, to: fixture.data)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == fixture.data.path)
        try Presets.linkVita3KData(install: fixture.install, to: fixture.data)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == fixture.data.path)
    }

    @Test func refusesGamesVita3KCannotInstall() async throws {
        let fixture = Fixture(firmware: false)
        let encrypted = fixture.game("PCSE00002")
        fixture.folder.write("library/psvita/PCSE00002/sce_sys/package/head.bin", Data(count: 16))
        await #expect(throws: Presets.Vita3KFailure.needsLicense) {
            try await Presets.vita3k(fixture.context(game: encrypted), data: fixture.data)
        }
        // Nothing was set up or downloaded for a game that cannot play.
        #expect(!FileManager.default.fileExists(atPath: fixture.data.appendingPathComponent("config.yml").path))

        fixture.folder.write("library/psvita/PCSE00002/sce_sys/package/work.bin", Data(count: 512))
        #expect(try Presets.vita3kContent(encrypted).hasLicense)

        let vitamin = fixture.game("PCSE00003")
        fixture.folder.write("library/psvita/PCSE00003/sce_module/steroid.suprx", Data(count: 16))
        #expect(throws: Presets.Vita3KFailure.vitamin) { try Presets.vita3kContent(vitamin) }

        fixture.folder.write("library/psvita/PCSE00004/sce_sys/param.sfo", SFOFixture.vita("PCSE00004", category: "gp"))
        #expect(throws: Presets.Vita3KFailure.notAGame) {
            try Presets.vita3kContent(fixture.folder.url.appendingPathComponent("library/psvita/PCSE00004"))
        }
        #expect(throws: Presets.Vita3KFailure.unreadable) { try Presets.vita3kContent(fixture.folder.folder("empty")) }
    }

    @Test func installsOnFirstPlayThenBootsByTitleID() {
        let fixture = Fixture()
        let game = fixture.game(version: "01.00")
        #expect(Presets.vita3kBootArguments(for: game, fs: fixture.fs) == [game.path])

        fixture.folder.write("Data/vita3k/fs/ux0/app/PCSE00001/sce_sys/param.sfo", SFOFixture.vita(version: "01.00"))
        #expect(Presets.vita3kBootArguments(for: game, fs: fixture.fs) == ["-r", "PCSE00001"])

        // An update installed in Vita3K stays; a newer copy in the library is installed over the old one.
        fixture.folder.write("Data/vita3k/fs/ux0/app/PCSE00001/sce_sys/param.sfo", SFOFixture.vita(version: "01.05"))
        #expect(Presets.vita3kBootArguments(for: game, fs: fixture.fs) == ["-r", "PCSE00001"])
        let newer = fixture.game(version: "02.00")
        #expect(Presets.vita3kBootArguments(for: newer, fs: fixture.fs) == [newer.path])
    }

    @Test func folderGamesBootTheFolder() {
        #expect(PlayStationFolder.bootFile(in: URL(fileURLWithPath: "/g/PCSE00001"), systemID: "psvita").path == "/g/PCSE00001")
    }
}

@Suite struct YAMLDocumentEndTests {
    @Test func newKeysGoBeforeTheDocumentEnd() throws {
        let folder = TemporaryFolder()
        let file = folder.write("config.yml", text: "---\na: 1\n...\n")
        try YAMLFile.update(file) { $0.set(["b"], "2"); $0.set(["a"], "3") }
        #expect(folder.read("config.yml") == "---\na: 3\nb: 2\n...\n")
    }
}

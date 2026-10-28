import Foundation

/// PS Vita games in the library: installed game folders (`<TITLEID>/sce_sys/param.sfo`, as copied
/// from a console's `ux0:app`) and `.vpk` packages, which are zips of such a folder.
enum VitaGame {
    static func isPackage(_ url: URL) -> Bool { url.pathExtension.lowercased() == "vpk" }

    /// Vita and PS4 game folders both keep `sce_sys/param.sfo`. Only the Vita's system software
    /// reads the `PSP2_SYSTEM_VER` / `PSP2_DISP_VER` keys (PSP2 is the Vita's code name); every
    /// Vita app has them, including homebrew made with the VitaSDK.
    static func isVitaSFO(_ data: Data) -> Bool {
        PlayStationFolder.sfoKeys(in: data).contains { $0.hasPrefix("PSP2_") }
    }

    /// What Arcadia needs to know before Vita3K installs and boots a game.
    struct Content: Equatable {
        let titleID: String?
        let title: String?
        /// `gd` for games and apps, `gp` for updates, `ac` for add-ons.
        let category: String?
        let version: String?
        /// `sce_sys/package` holds the encrypted parts of a retail game...
        let isEncrypted: Bool
        /// ...and `work.bin` there is its license, which Vita3K needs to decrypt it (NoNpDrm dumps).
        let hasLicense: Bool
        /// Vitamin dumps, which Vita3K refuses to install.
        let isVitamin: Bool

        var isGame: Bool { category.map { !$0.hasPrefix("gp") && $0 != "ac" } ?? true }

        init(sfo: Data, files: (String) -> Bool) {
            func value(_ key: String) -> String? { PlayStationFolder.sfoValue(key, in: sfo) }
            titleID = value("TITLE_ID")
            title = (value("TITLE") ?? value("STITLE"))?.replacingOccurrences(of: "\n", with: " ")
            category = value("CATEGORY")
            version = value("APP_VER")
            isEncrypted = files("sce_sys/package/")
            hasLicense = files("sce_sys/package/work.bin")
            isVitamin = files("sce_module/steroid.suprx")
        }

        /// Reads a game folder or `.vpk` package; nil when it holds no Vita `param.sfo`.
        init?(_ url: URL) {
            if VitaGame.isPackage(url) {
                guard let zip = ZipReader(url), let root = VitaGame.root(in: zip),
                      let sfo = zip.data(named: root + "sce_sys/param.sfo"), VitaGame.isVitaSFO(sfo) else { return nil }
                let names = zip.entries.map(\.name)
                self.init(sfo: sfo) { path in
                    path.hasSuffix("/")
                        ? names.contains { $0.hasPrefix(root + path) }
                        : names.contains(root + path)
                }
            } else {
                guard let sfo = try? Data(contentsOf: url.appendingPathComponent("sce_sys/param.sfo")),
                      VitaGame.isVitaSFO(sfo) else { return nil }
                self.init(sfo: sfo) { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
            }
        }
    }

    /// The folder inside a package that holds the game; packages may wrap it in a folder of its own
    /// or bundle an update next to it, so the game's own `param.sfo` wins.
    static func root(in zip: ZipReader) -> String? {
        let roots = zip.entries.map(\.name)
            .filter { $0.hasSuffix("sce_sys/param.sfo") }
            .map { String($0.dropLast("sce_sys/param.sfo".count)) }
            .filter { $0.isEmpty || $0.hasSuffix("/") }
            .sorted { $0.count < $1.count }
        return roots.first { root in
            guard let sfo = zip.data(named: root + "sce_sys/param.sfo"),
                  let category = PlayStationFolder.sfoValue("CATEGORY", in: sfo) else { return false }
            return category.hasPrefix("gd")
        } ?? roots.first
    }

    /// The game's icon (`sce_sys/icon0.png`) from a package.
    static func packageIcon(_ url: URL) -> Data? {
        guard let zip = ZipReader(url), let root = root(in: zip) else { return nil }
        return zip.data(named: root + "sce_sys/icon0.png")
    }

    /// Whether a folder is an installed Vita game (and not a PS4 one, an update or an add-on).
    static func isGameFolder(_ folder: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("eboot.bin").path),
              let content = Content(folder) else { return false }
        return content.isGame
    }
}

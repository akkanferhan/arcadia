import Foundation

/// Vita3K (PS Vita).
extension Presets {
    /// Vita3K runs in portable mode when a `portable` folder sits next to Vita3K.app: its config,
    /// emulated memory card (`fs/ux0`), firmware (`fs/vs0`, `fs/sa0`), caches and logs all live
    /// there. Arcadia makes that folder a link to its own data folder, so everything survives
    /// emulator updates and stays out of `~/Library/Application Support/Vita3K`.
    static func vita3k(_ context: PresetContext) async throws -> PresetLaunch {
        try await vita3k(context, data: context.data)
    }

    static func vita3k(_ context: PresetContext, data: URL) async throws -> PresetLaunch {
        // Refuse games Vita3K cannot install before downloading anything.
        _ = try vita3kContent(context.game)

        try linkVita3KData(install: context.install, to: data)
        let fs = vita3kFS(data)
        try FileManager.default.createDirectory(at: fs, withIntermediateDirectories: true)
        try YAMLFile.update(data.appendingPathComponent("config.yml")) { yaml in
            for (key, value) in vita3kSettings(scale: context.scale, fullscreen: context.fullscreen, fs: fs) {
                yaml.set([key], value)
            }
        }
        try await vita3kFirmware(context, fs: fs)
        // Vita3K maps every connected SDL controller itself (players 1–4 on a PS TV), so there is
        // nothing to write; its SDL window has no Select + Start hotkey, so Arcadia's Stop quits it.
        return PresetLaunch()
    }

    /// The emulated PS Vita file system: `ux0` (memory card), `vs0`/`sa0` (firmware) and so on.
    static func vita3kFS(_ data: URL = Paths.data("vita3k")) -> URL {
        data.appendingPathComponent("fs", isDirectory: true)
    }

    /// Top-level keys of Vita3K's config.yml.
    static func vita3kSettings(scale: Int, fullscreen: Bool, fs: URL) -> [(String, String)] {
        let escaped = fs.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return [
            // `--firmware` reads the memory card location from here before portable mode applies.
            ("pref-path", "\"\(escaped)/\""),
            ("initial-setup", "true"),
            ("show-welcome", "false"),
            ("warn-missing-firmware", "false"),
            ("check-for-updates-mode", "0"), // UPDATE_STARTUP_OFF; Arcadia updates Vita3K
            ("discord-rich-presence", "false"),
            ("user-auto-connect", "true"),
            ("backend-renderer", "Vulkan"), // MoltenVK; Vita3K needs OpenGL 4.4, which macOS lacks
            ("resolution-multiplier", pick(scale, ["1", "1.5", "2", "3"])), // of 960×544
            ("anisotropic-filtering", pick(scale, ["2", "4", "8", "16"])),
            ("v-sync", "true"),
            ("async-pipeline-compilation", "true"),
            ("shader-cache", "true"),
            ("show-compile-shaders", "false"),
            ("performance-overlay", "false"),
            ("boot-apps-full-screen", fullscreen ? "true" : "false"),
            ("modules-mode", "0"), // automatic
            ("log-level", "2"), // info; the default traces every call
        ]
    }

    /// Links `portable` next to Vita3K.app to Arcadia's data folder. Arcadia owns the emulator
    /// folder, so whatever else is there is replaced.
    static func linkVita3KData(install: URL, to data: URL) throws {
        let manager = FileManager.default
        let link = install.deletingLastPathComponent().appendingPathComponent("portable")
        if let target = try? manager.destinationOfSymbolicLink(atPath: link.path), target == data.path { return }
        try? manager.removeItem(at: link)
        try manager.createDirectory(at: data, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: link, withDestinationURL: data)
    }

    // MARK: Games

    enum Vita3KFailure: LocalizedError, Equatable {
        case unreadable, notAGame, needsLicense, vitamin

        var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "This doesn't look like a PS Vita game: its param.sfo is missing or has no title ID.")
            case .notAGame:
                String(localized: "This is an update or add-on for a PS Vita game, not the game itself.")
            case .needsLicense:
                String(localized: "This PS Vita game is encrypted and can't be installed without its license (sce_sys/package/work.bin). Dump it again with NoNpDrm or FAGDec.")
            case .vitamin:
                String(localized: "Vitamin dumps can't be played. Dump the game again with NoNpDrm or FAGDec.")
            }
        }
    }

    /// The game's details, or the reason Vita3K would refuse to install it (the same checks as
    /// Vita3K's `install_archive_content` and `install_content`).
    static func vita3kContent(_ game: URL) throws -> VitaGame.Content {
        guard let content = VitaGame.Content(game), content.titleID != nil else { throw Vita3KFailure.unreadable }
        guard content.isGame else { throw Vita3KFailure.notAGame }
        if content.isVitamin { throw Vita3KFailure.vitamin }
        if content.isEncrypted, !content.hasLicense { throw Vita3KFailure.needsLicense }
        return content
    }

    /// Vita3K plays games installed in `ux0/app/<TITLEID>`. The first time, the game's folder or
    /// package is handed to Vita3K, which installs it (decrypting NoNpDrm dumps) and boots it;
    /// afterwards it boots straight from `ux0/app` by title ID.
    static func vita3kBootArguments(for game: URL, fs: URL = vita3kFS()) -> [String] {
        guard let content = VitaGame.Content(game), let id = content.titleID,
              vita3kIsInstalled(content, fs: fs) else { return [game.path] }
        return ["-r", id]
    }

    /// Whether `ux0/app` holds this game, at least at its version. Updates installed in Vita3K
    /// raise the installed version, so they are never replaced by the older library copy.
    static func vita3kIsInstalled(_ content: VitaGame.Content, fs: URL) -> Bool {
        guard let id = content.titleID,
              let sfo = try? Data(contentsOf: fs.appendingPathComponent("ux0/app/\(id)/sce_sys/param.sfo")) else { return false }
        guard let wanted = content.version, let installed = PlayStationFolder.sfoValue("APP_VER", in: sfo) else { return true }
        return installed.compare(wanted, options: .numeric) != .orderedAscending
    }

    // MARK: Firmware

    /// Installs the PS Vita system software and fonts once, without any window. They come from
    /// bios/psvita or, when the player has none, straight from Sony's update servers.
    static func vita3kFirmware(_ context: PresetContext, fs: URL) async throws {
        let missing = VitaFirmware.Part.allCases.filter { !VitaFirmware.isInstalled($0, fs: fs) }
        guard !missing.isEmpty else { return }
        let executable = context.executableFolder.appendingPathComponent("Vita3K")
        var images: VitaFirmware.Images?
        for part in missing {
            let file = context.bios.appendingPathComponent("psvita/\(part.fileName)")
            if !FileManager.default.fileExists(atPath: file.path) {
                context.report(part.downloadStatus)
                if images == nil { images = try await VitaFirmware.images() }
                try await VitaFirmware.download(images![part], to: file, progress: context.progress)
            }
            context.report("Installing PS Vita system software…")
            try await VitaFirmware.install(file, executable: executable, progress: context.progress)
            guard VitaFirmware.isInstalled(part, fs: fs) else {
                try? FileManager.default.removeItem(at: file)
                throw VitaFirmware.Failure.corrupted
            }
        }
    }
}

/// The PS Vita system software and font package Sony publishes for console owners.
enum VitaFirmware {
    enum Failure: LocalizedError {
        case unavailable, corrupted
        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "Sony's PS Vita update server could not be reached.")
            case .corrupted: String(localized: "The PS Vita system software download was damaged. Try again.")
            }
        }
    }

    enum Part: CaseIterable {
        /// The system software (3.74), installed into `vs0` and `os0`.
        case system
        /// System fonts, installed into `sa0`. Many games show no text without them.
        case fonts

        /// The system software keeps the name playstation.com gives it.
        var fileName: String { self == .system ? "PSVUPDAT.PUP" : "PSP2UPDAT.PUP" }

        /// The folder Vita3K checks to decide whether the part is installed (`get_firmware_state`).
        var folder: String { self == .system ? "vs0" : "sa0" }

        var downloadStatus: LocalizedStringResource {
            self == .system ? "Downloading PS Vita system software from Sony…" : "Downloading PS Vita system fonts from Sony…"
        }
    }

    struct Image: Equatable {
        let url: URL
        let size: Int?
    }

    struct Images: Equatable {
        let system: Image
        let fonts: Image
        subscript(part: Part) -> Image { part == .system ? system : fonts }
    }

    /// Sony's update list for US consoles; the same one a PS Vita reads. It serves the newest
    /// full system update and, as recovery data, the font package.
    static let list = URL(string: "http://fus01.psp2.update.playstation.net/update/psp2/list/us/psp2-updatelist.xml")!

    static func isInstalled(_ part: Part, fs: URL) -> Bool {
        let folder = fs.appendingPathComponent(part.folder)
        return !((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty
    }

    /// Reads the update list. Only links to Sony's own servers are accepted.
    static func parse(_ data: Data) -> Images? {
        guard let xml = try? XMLDocument(data: data) else { return nil }
        func image(_ path: String) -> Image? {
            guard let element = (try? xml.nodes(forXPath: path))?.first as? XMLElement,
                  let text = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: text), url.host?.hasSuffix(".playstation.net") == true else { return nil }
            return Image(url: url, size: element.attribute(forName: "size")?.stringValue.flatMap { Int($0) })
        }
        guard let system = image("//version/update_data[@update_type='full']/image"),
              let fonts = image("//recovery[@spkg_type='systemdata']/image") else { return nil }
        return Images(system: system, fonts: fonts)
    }

    static func images() async throws -> Images {
        guard let (data, response) = try? await URLSession.shared.data(from: list),
              (response as? HTTPURLResponse)?.statusCode == 200, let images = parse(data) else {
            throw Failure.unavailable
        }
        return images
    }

    /// Sony serves the files over plain HTTP; the size from the list catches broken downloads.
    static func download(_ image: Image, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let temporary = Paths.downloads.appendingPathComponent("\(UUID().uuidString).PUP")
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try await Downloader.download(image.url, to: temporary, progress: progress)
        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        if let expected = image.size, size != expected { throw Failure.corrupted }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    /// `Vita3K --firmware <file>` installs a PUP and quits before any window opens
    /// (vita3k/config/src/config.cpp, vita3k/main.cpp).
    static func install(_ pup: URL, executable: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--firmware", pup.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                if let value = installProgress(in: String(decoding: data, as: UTF8.self)) { progress(value) }
            }
            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
        }.value
    }

    /// Vita3K logs "Firmware installation progress: 70%" while it installs.
    static func installProgress(in output: String) -> Double? {
        guard let match = output.matches(of: #/Firmware installation progress: (\d+)%/#).last,
              let percent = Int(match.1) else { return nil }
        return Double(min(percent, 100)) / 100
    }
}

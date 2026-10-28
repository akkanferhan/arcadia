import Foundation

/// Reads installed PS3, PS4, PS5 and PS Vita game folders (and Vita `.vpk` packages):
/// the boot file, the title and the icon.
enum PlayStationFolder {
    /// The file the emulator should boot.
    static func bootFile(in folder: URL, systemID: String) -> URL {
        // Vita3K installs the whole folder or package, then boots it by title ID.
        if systemID == "psvita" { return folder }
        let candidates = systemID == "ps3"
            ? ["PS3_GAME/USRDIR/EBOOT.BIN", "USRDIR/EBOOT.BIN", "EBOOT.BIN"]
            : ["eboot.bin", "EBOOT.BIN"]
        return candidates.lazy.map { folder.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? folder
    }

    static func title(in folder: URL) -> String? {
        if VitaGame.isPackage(folder) { return VitaGame.Content(folder)?.title }
        let paths = ["sce_sys/param.sfo", "PS3_GAME/PARAM.SFO", "PARAM.SFO"]
        for path in paths {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(path)),
               let title = sfoValue("TITLE", in: data) {
                // Vita titles may break onto two lines.
                return title.replacingOccurrences(of: "\n", with: " ")
            }
        }
        if let data = try? Data(contentsOf: folder.appendingPathComponent("sce_sys/param.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let localized = json["localizedParameters"] as? [String: Any],
           let language = localized["defaultLanguage"] as? String,
           let entry = localized[language] as? [String: Any],
           let title = entry["titleName"] as? String {
            return title
        }
        return nil
    }

    static func icon(in folder: URL) -> URL? {
        ["sce_sys/icon0.png", "PS3_GAME/ICON0.PNG", "ICON0.PNG"].lazy
            .map { folder.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reads a UTF-8 string from a PARAM.SFO file.
    static func sfoValue(_ key: String, in data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let entries = sfoEntries(bytes) else { return nil }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        let dataTable = u32(12)
        for (name, entry) in entries {
            guard name == key else { continue }
            let start = dataTable + u32(entry + 12)
            let end = min(start + u32(entry + 4), bytes.count)
            guard start < end else { return nil }
            let value = String(decoding: bytes[start..<end], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Every key in a PARAM.SFO file, whatever its value type.
    static func sfoKeys(in data: Data) -> [String] {
        sfoEntries([UInt8](data))?.map(\.key) ?? []
    }

    /// Key names and index-entry offsets, or nil when the data is not a PARAM.SFO file.
    private static func sfoEntries(_ bytes: [UInt8]) -> [(key: String, entry: Int)]? {
        guard bytes.count > 20, bytes[0...3] == [0x00, 0x50, 0x53, 0x46] else { return nil }
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        let keyTable = u32(8), count = u32(16)
        var entries: [(key: String, entry: Int)] = []
        for index in 0..<count {
            let entry = 20 + index * 16
            guard entry + 16 <= bytes.count else { break }
            let keyStart = keyTable + u16(entry)
            guard keyStart < bytes.count, let keyEnd = bytes[keyStart...].firstIndex(of: 0) else { break }
            entries.append((String(decoding: bytes[keyStart..<keyEnd], as: UTF8.self), entry))
        }
        return entries
    }
}

import Foundation

/// Reads installed PS3, PS4 and PS5 game folders: the boot file, the title and the icon.
enum PlayStationFolder {
    /// The file the emulator should boot.
    static func bootFile(in folder: URL, systemID: String) -> URL {
        let candidates = systemID == "ps3"
            ? ["PS3_GAME/USRDIR/EBOOT.BIN", "USRDIR/EBOOT.BIN", "EBOOT.BIN"]
            : ["eboot.bin", "EBOOT.BIN"]
        return candidates.lazy.map { folder.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? folder
    }

    static func title(in folder: URL) -> String? {
        let paths = ["sce_sys/param.sfo", "PS3_GAME/PARAM.SFO", "PARAM.SFO"]
        for path in paths {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(path)),
               let title = sfoValue("TITLE", in: data) {
                return title
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
        guard bytes.count > 20, bytes[0...3] == [0x00, 0x50, 0x53, 0x46] else { return nil }
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        let keyTable = u32(8), dataTable = u32(12), count = u32(16)
        for index in 0..<count {
            let entry = 20 + index * 16
            guard entry + 16 <= bytes.count else { return nil }
            let keyStart = keyTable + u16(entry)
            guard let keyEnd = bytes[keyStart...].firstIndex(of: 0) else { return nil }
            guard String(decoding: bytes[keyStart..<keyEnd], as: UTF8.self) == key else { continue }
            let start = dataTable + u32(entry + 12)
            let end = min(start + u32(entry + 4), bytes.count)
            guard start < end else { return nil }
            let value = String(decoding: bytes[start..<end], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

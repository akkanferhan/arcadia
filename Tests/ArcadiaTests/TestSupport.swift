import Foundation

/// A temporary folder removed when the value goes away.
final class TemporaryFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ArcadiaTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ path: String, _ data: Data) -> URL {
        let file = url.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
        return file
    }

    @discardableResult
    func write(_ path: String, text: String) -> URL { write(path, Data(text.utf8)) }

    @discardableResult
    func folder(_ path: String) -> URL {
        let folder = url.appendingPathComponent(path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func read(_ path: String) -> String {
        (try? String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }
}

/// Builds tiny disc images that carry the same markers real console discs do.
enum DiscFixture {
    static func bytes(_ count: Int, setting patches: [(Int, [UInt8])] = []) -> Data {
        var data = Data(count: count)
        for (offset, bytes) in patches { data.replaceSubrange(offset..<offset + bytes.count, with: bytes) }
        return data
    }

    /// An ISO 9660 image whose root directory holds the given entries.
    static func iso(_ entries: [(name: String, directory: Bool, content: Data)], system: String = "PLAYSTATION",
                    raw: Bool = false) -> Data {
        var sectors = Array(repeating: Data(count: 2048), count: 40)
        var volume = Data(count: 2048)
        volume[0] = 1
        volume.replaceSubrange(1..<6, with: Data("CD001".utf8))
        volume.replaceSubrange(8..<40, with: Data(system.padding(toLength: 32, withPad: " ", startingAt: 0).utf8))
        var root = Data()
        var lba: UInt32 = 20
        for entry in entries {
            let name = Data((entry.name + (entry.directory ? "" : ";1")).utf8)
            var record = Data(count: 33 + name.count)
            record[0] = UInt8(record.count)
            record.replaceSubrange(2..<6, with: withUnsafeBytes(of: lba.littleEndian, Array.init))
            let size = UInt32(max(entry.content.count, 2048))
            record.replaceSubrange(10..<14, with: withUnsafeBytes(of: size.littleEndian, Array.init))
            record[25] = entry.directory ? 2 : 0
            record[32] = UInt8(name.count)
            record.replaceSubrange(33..<33 + name.count, with: name)
            root.append(record)
            var sector = Data(count: 2048)
            sector.replaceSubrange(0..<entry.content.count, with: entry.content)
            sectors[Int(lba)] = sector
            lba += 1
        }
        var rootSector = Data(count: 2048)
        rootSector.replaceSubrange(0..<root.count, with: root)
        sectors[18] = rootSector
        var rootRecord = Data(count: 34)
        rootRecord[0] = 34
        rootRecord.replaceSubrange(2..<6, with: withUnsafeBytes(of: UInt32(18).littleEndian, Array.init))
        rootRecord.replaceSubrange(10..<14, with: withUnsafeBytes(of: UInt32(2048).littleEndian, Array.init))
        volume.replaceSubrange(156..<190, with: rootRecord)
        sectors[16] = volume

        guard raw else { return sectors.reduce(Data(), +) }
        // Raw CD (2352-byte Mode 2 sectors): sync pattern, header, subheader, then user data.
        return sectors.reduce(into: Data()) { image, user in
            var sector = Data(count: 2352)
            sector.replaceSubrange(0..<12, with: [0x00] + Array(repeating: 0xFF, count: 10) + [0x00])
            sector.replaceSubrange(24..<24 + 2048, with: user)
            image.append(sector)
        }
    }
}

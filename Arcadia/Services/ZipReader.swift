import Foundation
import zlib

/// Reads the file list of a zip archive and small files inside it, without unpacking the rest.
/// PS Vita `.vpk` packages are zips; Arcadia reads their `param.sfo` and icon this way.
/// Supports Zip64 (packages over 4 GB) and stored or deflated entries.
struct ZipReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: UInt64
        let size: UInt64
        let localHeaderOffset: UInt64
    }

    let url: URL
    let entries: [Entry]

    /// Files larger than this are never read into memory.
    static let maximumEntrySize: UInt64 = 32 << 20

    init?(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize >= 22 else { return nil }

        // The end-of-central-directory record sits in the last 64 KB (after an optional comment).
        let tailSize = min(fileSize, 65_557 + 20)
        guard let tail = Self.read(handle, at: fileSize - tailSize, count: Int(tailSize)),
              let eocd = Self.lastSignature(0x0605_4B50, in: tail, recordSize: 22) else { return nil }

        var count = UInt64(tail.le16(eocd + 10))
        var directorySize = UInt64(tail.le32(eocd + 12))
        var directoryOffset = UInt64(tail.le32(eocd + 16))

        // Zip64: a locator right before the record points at the 64-bit record.
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            guard eocd >= 20, tail.le32(eocd - 20) == 0x0706_4B50 else { return nil }
            let recordOffset = tail.le64(eocd - 20 + 8)
            guard let record = Self.read(handle, at: recordOffset, count: 56), record.le32(0) == 0x0606_4B50 else { return nil }
            count = record.le64(32)
            directorySize = record.le64(40)
            directoryOffset = record.le64(48)
        }
        guard directorySize <= 64 << 20, directoryOffset + directorySize <= fileSize,
              let directory = Self.read(handle, at: directoryOffset, count: Int(directorySize)) else { return nil }

        var entries: [Entry] = []
        var offset = 0
        for _ in 0..<count {
            guard offset + 46 <= directory.count, directory.le32(offset) == 0x0201_4B50 else { return nil }
            let method = directory.le16(offset + 10)
            var compressedSize = UInt64(directory.le32(offset + 20))
            var size = UInt64(directory.le32(offset + 24))
            let nameLength = Int(directory.le16(offset + 28))
            let extraLength = Int(directory.le16(offset + 30))
            let commentLength = Int(directory.le16(offset + 32))
            var localOffset = UInt64(directory.le32(offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength + extraLength <= directory.count else { return nil }
            let nameData = directory[(directory.startIndex + nameStart)..<(directory.startIndex + nameStart + nameLength)]
            let name = String(decoding: nameData, as: UTF8.self)

            // Zip64 extra field: the 64-bit values, in this order, for each 32-bit field that is full.
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = directory.le16(extra), length = Int(directory.le16(extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    if size == 0xFFFF_FFFF, field + 8 <= extraEnd { size = directory.le64(field); field += 8 }
                    if compressedSize == 0xFFFF_FFFF, field + 8 <= extraEnd { compressedSize = directory.le64(field); field += 8 }
                    if localOffset == 0xFFFF_FFFF, field + 8 <= extraEnd { localOffset = directory.le64(field) }
                }
                extra += 4 + length
            }
            entries.append(Entry(name: name, method: method, compressedSize: compressedSize, size: size,
                                 localHeaderOffset: localOffset))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        self.url = url
        self.entries = entries
    }

    func entry(named name: String) -> Entry? { entries.first { $0.name == name } }

    /// The contents of a small stored or deflated file.
    func data(_ entry: Entry) -> Data? {
        guard entry.size <= Self.maximumEntrySize, entry.compressedSize <= Self.maximumEntrySize,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = Self.read(handle, at: entry.localHeaderOffset, count: 30), header.le32(0) == 0x0403_4B50 else {
            return nil
        }
        let start = entry.localHeaderOffset + 30 + UInt64(header.le16(26)) + UInt64(header.le16(28))
        guard let stored = Self.read(handle, at: start, count: Int(entry.compressedSize)) else { return nil }
        switch entry.method {
        case 0: return stored
        case 8: return Self.inflate(stored, size: Int(entry.size))
        default: return nil
        }
    }

    func data(named name: String) -> Data? { entry(named: name).flatMap(data) }

    // MARK: Helpers

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        if count == 0 { return Data() }
        guard let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return data
    }

    private static func lastSignature(_ signature: UInt32, in data: Data, recordSize: Int) -> Int? {
        var offset = data.count - recordSize
        while offset >= 0 {
            if data.le32(offset) == signature { return offset }
            offset -= 1
        }
        return nil
    }

    /// Raw deflate, as zip stores it.
    private static func inflate(_ input: Data, size: Int) -> Data? {
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var output = Data(count: size)
        if size == 0 { return output }
        let result: Int32 = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(size)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END, stream.avail_out == 0 else { return nil }
        return output
    }
}

private extension Data {
    func le16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func le32(_ offset: Int) -> UInt32 {
        UInt32(le16(offset)) | UInt32(le16(offset + 2)) << 16
    }

    func le64(_ offset: Int) -> UInt64 {
        UInt64(le32(offset)) | UInt64(le32(offset + 4)) << 32
    }
}

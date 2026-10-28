import CryptoKit
import Foundation
import zlib

/// A lossless, block-compressed disc image format that emulators read directly.
///
/// Both formats store each block deflated on its own (or as-is when it would not shrink), so an
/// emulator can seek anywhere in the disc. Arcadia writes them itself with the zlib that ships
/// with macOS; no extra tools are downloaded.
enum DiscImageFormat: String, CaseIterable, Sendable {
    /// Compressed ISO (CISO version 1), read by PPSSPP and PCSX2.
    case cso
    /// Dolphin's GCZ format for GameCube discs.
    case gcz

    var fileExtension: String { rawValue }

    var name: String {
        switch self {
        case .cso: "CSO"
        case .gcz: "GCZ"
        }
    }

    /// Uncompressed bytes per block. CSO uses one DVD sector; GCZ uses Dolphin's default.
    var blockSize: Int {
        switch self {
        case .cso: 2048
        case .gcz: 32 * 1024
        }
    }

    /// CSO stores raw deflate streams; GCZ stores zlib streams.
    var rawDeflate: Bool { self == .cso }
}

enum DiscImageError: LocalizedError {
    case unreadable
    case damaged
    case mismatch

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "The game file could not be read.")
        case .damaged: String(localized: "The compressed file is damaged.")
        case .mismatch: String(localized: "The compressed file does not match the original, so the original was kept.")
        }
    }
}

/// Writes and reads CSO and GCZ images.
enum DiscImageCodec {
    /// Uncompressed bytes handled per batch; blocks in a batch are compressed in parallel.
    private static let batchBytes = 8 * 1024 * 1024

    // MARK: Compressing

    /// Compresses `source` into `destination` and returns the SHA-256 of the original bytes.
    /// Checks for task cancellation between batches.
    static func compress(_ source: URL, to destination: URL, format: DiscImageFormat,
                         progress: (Double) -> Void) throws -> SHA256Digest {
        guard let input = try? FileHandle(forReadingFrom: source) else { throw DiscImageError.unreadable }
        defer { try? input.close() }
        let size = try fileSize(source)
        let blockSize = format.blockSize
        let blockCount = Int((size + UInt64(blockSize) - 1) / UInt64(blockSize))

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        let layout = Layout(format: format, size: size, blockCount: blockCount)
        // Reserve room for the header and index, written once every block's place is known.
        try output.write(contentsOf: Data(count: layout.dataStart))
        var position = UInt64(layout.dataStart)
        var entries: [(offset: UInt64, stored: Int, plain: Bool, hash: UInt32)] = []
        entries.reserveCapacity(blockCount)
        var hasher = SHA256()
        let perBatch = batchBytes / blockSize
        var block = 0

        while block < blockCount {
            try Task.checkCancellation()
            let count = min(perBatch, blockCount - block)
            guard var chunk = try input.read(upToCount: count * blockSize), !chunk.isEmpty else {
                throw DiscImageError.unreadable
            }
            hasher.update(data: chunk)
            // The last block is padded with zeros: readers always expect whole blocks.
            if chunk.count < count * blockSize { chunk.append(Data(count: count * blockSize - chunk.count)) }

            let packed = compressBlocks(chunk, blockSize: blockSize, rawDeflate: format.rawDeflate)
            var batch = Data()
            for (index, compressed) in packed.enumerated() {
                let padding = layout.padding(before: position)
                if padding > 0 { batch.append(Data(count: padding)); position += UInt64(padding) }
                let stored = compressed ?? chunk.subdata(in: index * blockSize..<(index + 1) * blockSize)
                let hash = format == .gcz ? adler(stored) : 0
                entries.append((position, stored.count, compressed == nil, hash))
                batch.append(stored)
                position += UInt64(stored.count)
            }
            try output.write(contentsOf: batch)
            block += count
            progress(Double(block) / Double(max(blockCount, 1)))
        }
        let tail = layout.padding(before: position)
        if tail > 0 { try output.write(contentsOf: Data(count: tail)); position += UInt64(tail) }

        try output.seek(toOffset: 0)
        try output.write(contentsOf: layout.header(entries: entries, end: position))
        try output.synchronize()
        return hasher.finalize()
    }

    /// Estimates the compressed size by compressing evenly spread samples of the file.
    static func estimatedSize(of source: URL, format: DiscImageFormat, samples: Int = 24) throws -> UInt64 {
        guard let input = try? FileHandle(forReadingFrom: source) else { throw DiscImageError.unreadable }
        defer { try? input.close() }
        let size = try fileSize(source)
        let blockSize = format.blockSize
        let sampleBytes = max(blockSize, 512 * 1024 / blockSize * blockSize)
        guard size > UInt64(sampleBytes * samples) else {
            let data = try input.readToEnd() ?? Data()
            return UInt64(compressedBytes(data, format: format)) + UInt64(Layout.overhead(format, size: size))
        }
        var original = 0, compressed = 0
        let blocks = size / UInt64(blockSize)
        for sample in 0..<samples {
            try Task.checkCancellation()
            let start = blocks * UInt64(sample) / UInt64(samples) * UInt64(blockSize)
            try input.seek(toOffset: start)
            guard let data = try input.read(upToCount: sampleBytes), data.count == sampleBytes else { continue }
            original += data.count
            compressed += compressedBytes(data, format: format)
        }
        guard original > 0 else { throw DiscImageError.unreadable }
        let ratio = Double(compressed) / Double(original)
        return UInt64(Double(size) * ratio) + UInt64(Layout.overhead(format, size: size))
    }

    private static func compressedBytes(_ data: Data, format: DiscImageFormat) -> Int {
        var data = data
        let blockSize = format.blockSize
        if data.count % blockSize != 0 { data.append(Data(count: blockSize - data.count % blockSize)) }
        return compressBlocks(data, blockSize: blockSize, rawDeflate: format.rawDeflate)
            .reduce(0) { $0 + ($1?.count ?? blockSize) }
    }

    /// Deflates every block of `chunk` in parallel; `nil` marks a block that does not shrink.
    private static func compressBlocks(_ chunk: Data, blockSize: Int, rawDeflate: Bool) -> [Data?] {
        let count = chunk.count / blockSize
        var results = [Data?](repeating: nil, count: count)
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, count))
        chunk.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            results.withUnsafeMutableBufferPointer { results in
                let out = results.baseAddress!
                DispatchQueue.concurrentPerform(iterations: workers) { worker in
                    let deflater = Deflater(raw: rawDeflate)
                    for index in stride(from: worker, to: count, by: workers) {
                        let block = UnsafeRawBufferPointer(rebasing: bytes[index * blockSize..<(index + 1) * blockSize])
                        out[index] = deflater.compress(block)
                    }
                }
            }
        }
        return results
    }

    // MARK: Reading back

    /// Decompresses a whole image and returns the SHA-256 of the disc it holds, checking
    /// every block on the way. Used to prove a compressed copy matches its original.
    static func contentDigest(of image: URL, progress: (Double) -> Void) throws -> SHA256Digest {
        guard let input = try? FileHandle(forReadingFrom: image) else { throw DiscImageError.unreadable }
        defer { try? input.close() }
        let index = try Index.read(input, fileSize: fileSize(image))
        let blockSize = index.blockSize
        let perBatch = max(1, batchBytes / blockSize)
        var hasher = SHA256()
        var remaining = index.size
        var block = 0

        while block < index.blockCount {
            try Task.checkCancellation()
            let count = min(perBatch, index.blockCount - block)
            let start = index.blocks[block].offset
            let last = index.blocks[block + count - 1]
            try input.seek(toOffset: start)
            let length = Int(last.offset - start) + last.length
            guard let stored = try input.read(upToCount: length), stored.count == length else {
                throw DiscImageError.damaged
            }
            let blocks = Array(index.blocks[block..<block + count])
            let decoded = try decompress(blocks, from: stored, base: start, blockSize: blockSize,
                                         rawDeflate: index.format.rawDeflate, checksHashes: index.format == .gcz)
            let keep = Int(min(UInt64(decoded.count), remaining))
            hasher.update(data: decoded.prefix(keep))
            remaining -= UInt64(keep)
            block += count
            progress(Double(block) / Double(max(index.blockCount, 1)))
        }
        guard remaining == 0 else { throw DiscImageError.damaged }
        return hasher.finalize()
    }

    /// Reads the format and uncompressed size from an image's header.
    static func info(of image: URL) throws -> (format: DiscImageFormat, size: UInt64) {
        guard let input = try? FileHandle(forReadingFrom: image) else { throw DiscImageError.unreadable }
        defer { try? input.close() }
        let index = try Index.read(input, fileSize: fileSize(image))
        return (index.format, index.size)
    }

    private static func decompress(_ blocks: [Index.Block], from stored: Data, base: UInt64, blockSize: Int,
                                   rawDeflate: Bool, checksHashes: Bool) throws -> Data {
        var output = Data(count: blocks.count * blockSize)
        var failed = false
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, blocks.count))
        stored.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
                let lock = NSLock()
                DispatchQueue.concurrentPerform(iterations: workers) { worker in
                    let inflater = Inflater(raw: rawDeflate)
                    for index in stride(from: worker, to: blocks.count, by: workers) {
                        let block = blocks[index]
                        let start = Int(block.offset - base)
                        let source = UnsafeRawBufferPointer(rebasing: input[start..<start + block.length])
                        let target = UnsafeMutableRawBufferPointer(
                            rebasing: out[index * blockSize..<(index + 1) * blockSize])
                        var ok = !checksHashes || adler(source) == block.hash
                        if ok {
                            if block.plain {
                                ok = block.length == blockSize
                                if ok { target.copyMemory(from: source) }
                            } else {
                                ok = inflater.decompress(source, into: target)
                            }
                        }
                        if !ok { lock.lock(); failed = true; lock.unlock() }
                    }
                }
            }
        }
        if failed { throw DiscImageError.damaged }
        return output
    }

    // MARK: Helpers

    static func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    static func adler(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { adler($0) }
    }

    static func adler(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        let start = adler32(0, nil, 0)
        guard let base = bytes.baseAddress, bytes.count > 0 else { return UInt32(start) }
        return UInt32(adler32(start, base.assumingMemoryBound(to: Bytef.self), uInt(bytes.count)))
    }
}

// MARK: - File layout

/// Header and index of an image being written.
private struct Layout {
    let format: DiscImageFormat
    let size: UInt64
    let blockCount: Int
    /// CSO stores offsets shifted right by this many bits, so blocks start on multiples of `1 << align`.
    let align: Int

    init(format: DiscImageFormat, size: UInt64, blockCount: Int) {
        self.format = format
        self.size = size
        self.blockCount = blockCount
        var align = 0
        if format == .cso {
            // CSO offsets are 31 bits; larger discs (dual-layer PS2 games) need alignment.
            while align < 8 {
                let worst = UInt64(Layout.overhead(format, size: size)) + UInt64(blockCount) * UInt64(format.blockSize + (1 << align))
                if worst >> UInt64(align) < 0x8000_0000 { break }
                align += 1
            }
        }
        self.align = align
    }

    static func overhead(_ format: DiscImageFormat, size: UInt64) -> Int {
        let blocks = Int((size + UInt64(format.blockSize) - 1) / UInt64(format.blockSize))
        switch format {
        case .cso: return 24 + (blocks + 1) * 4
        case .gcz: return 32 + blocks * 12
        }
    }

    var dataStart: Int {
        let start = Layout.overhead(format, size: size)
        return start + padding(before: UInt64(start))
    }

    func padding(before position: UInt64) -> Int {
        let unit = UInt64(1) << UInt64(align)
        return Int((unit - position % unit) % unit)
    }

    func header(entries: [(offset: UInt64, stored: Int, plain: Bool, hash: UInt32)], end: UInt64) -> Data {
        var data = Data()
        switch format {
        case .cso:
            data.append(contentsOf: Array("CISO".utf8))
            data.appendLittleEndian(UInt32(24))
            data.appendLittleEndian(size)
            data.appendLittleEndian(UInt32(format.blockSize))
            data.append(contentsOf: [1, UInt8(align), 0, 0])
            for entry in entries {
                data.appendLittleEndian(UInt32(entry.offset >> UInt64(align)) | (entry.plain ? 0x8000_0000 : 0))
            }
            data.appendLittleEndian(UInt32(end >> UInt64(align)))
        case .gcz:
            let dataStart = UInt64(Layout.overhead(format, size: size))
            data.appendLittleEndian(UInt32(0xB10B_C001))
            data.appendLittleEndian(UInt32(0))
            data.appendLittleEndian(end - dataStart)
            data.appendLittleEndian(size)
            data.appendLittleEndian(UInt32(format.blockSize))
            data.appendLittleEndian(UInt32(blockCount))
            for entry in entries {
                data.appendLittleEndian((entry.offset - dataStart) | (entry.plain ? 1 << 63 : 0))
            }
            for entry in entries { data.appendLittleEndian(entry.hash) }
        }
        return data
    }
}

/// The block table of an existing image, validated against the file's size.
private struct Index {
    struct Block {
        let offset: UInt64
        let length: Int
        let plain: Bool
        let hash: UInt32
    }

    let format: DiscImageFormat
    let size: UInt64
    let blockSize: Int
    let blocks: [Block]
    var blockCount: Int { blocks.count }

    static func read(_ input: FileHandle, fileSize: UInt64) throws -> Index {
        try input.seek(toOffset: 0)
        guard let head = try input.read(upToCount: 32), head.count >= 24 else { throw DiscImageError.damaged }
        if head.prefix(4) == Data("CISO".utf8) {
            let size = head.littleEndian(UInt64.self, at: 8)
            let blockSize = Int(head.littleEndian(UInt32.self, at: 16))
            let version = head[20], align = UInt64(head[21])
            guard version <= 1, blockSize >= 2048, blockSize & (blockSize - 1) == 0 else { throw DiscImageError.damaged }
            let count = Int((size + UInt64(blockSize) - 1) / UInt64(blockSize))
            try input.seek(toOffset: 24)
            guard let table = try input.read(upToCount: (count + 1) * 4), table.count == (count + 1) * 4 else {
                throw DiscImageError.damaged
            }
            var blocks: [Block] = []
            blocks.reserveCapacity(count)
            for index in 0..<count {
                let entry = table.littleEndian(UInt32.self, at: index * 4)
                let next = table.littleEndian(UInt32.self, at: index * 4 + 4)
                let start = UInt64(entry & 0x7FFF_FFFF) << align
                let end = UInt64(next & 0x7FFF_FFFF) << align
                guard end >= start, end <= fileSize else { throw DiscImageError.damaged }
                let plain = entry & 0x8000_0000 != 0
                // Alignment padding follows a block; a plain block is exactly one block long.
                let length = plain ? min(Int(end - start), blockSize) : Int(end - start)
                blocks.append(Block(offset: start, length: length, plain: plain, hash: 0))
            }
            return Index(format: .cso, size: size, blockSize: blockSize, blocks: blocks)
        }
        guard head.count == 32, head.littleEndian(UInt32.self, at: 0) == 0xB10B_C001 else { throw DiscImageError.damaged }
        let compressedSize = head.littleEndian(UInt64.self, at: 8)
        let size = head.littleEndian(UInt64.self, at: 16)
        let blockSize = Int(head.littleEndian(UInt32.self, at: 24))
        let count = Int(head.littleEndian(UInt32.self, at: 28))
        guard blockSize > 0, UInt64(count) == (size + UInt64(blockSize) - 1) / UInt64(blockSize) else {
            throw DiscImageError.damaged
        }
        guard let table = try input.read(upToCount: count * 12), table.count == count * 12 else {
            throw DiscImageError.damaged
        }
        let dataStart = UInt64(32 + count * 12)
        guard dataStart + compressedSize <= fileSize else { throw DiscImageError.damaged }
        var blocks: [Block] = []
        blocks.reserveCapacity(count)
        for index in 0..<count {
            let pointer = table.littleEndian(UInt64.self, at: index * 8)
            let start = pointer & ~(1 << 63)
            let end = index + 1 < count ? table.littleEndian(UInt64.self, at: index * 8 + 8) & ~(1 << 63) : compressedSize
            guard end >= start, end <= compressedSize else { throw DiscImageError.damaged }
            blocks.append(Block(offset: dataStart + start, length: Int(end - start), plain: pointer & (1 << 63) != 0,
                                hash: table.littleEndian(UInt32.self, at: count * 8 + index * 4)))
        }
        return Index(format: .gcz, size: size, blockSize: blockSize, blocks: blocks)
    }
}

// MARK: - zlib

/// One reusable deflate stream at the strongest level. Not thread-safe.
private final class Deflater {
    private var stream = z_stream()
    private let ready: Bool

    init(raw: Bool) {
        ready = deflateInit2_(&stream, 9, Z_DEFLATED, raw ? -15 : 15, 9, Z_DEFAULT_STRATEGY,
                              zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK
    }

    deinit { if ready { deflateEnd(&stream) } }

    /// The compressed block, or `nil` when it would not be smaller than the block itself.
    func compress(_ block: UnsafeRawBufferPointer) -> Data? {
        guard ready, block.count > 1 else { return nil }
        deflateReset(&stream)
        let limit = block.count - 1
        var output = Data(count: limit)
        let result: Int32 = output.withUnsafeMutableBytes { out in
            stream.next_in = UnsafeMutablePointer(mutating: block.baseAddress!.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(block.count)
            stream.next_out = out.baseAddress!.assumingMemoryBound(to: Bytef.self)
            stream.avail_out = uInt(limit)
            return deflate(&stream, Z_FINISH)
        }
        guard result == Z_STREAM_END else { return nil }
        output.count = limit - Int(stream.avail_out)
        return output
    }
}

/// One reusable inflate stream. Not thread-safe.
private final class Inflater {
    private var stream = z_stream()
    private let ready: Bool

    init(raw: Bool) {
        ready = inflateInit2_(&stream, raw ? -15 : 15, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK
    }

    deinit { if ready { inflateEnd(&stream) } }

    /// Inflates one block; succeeds only when it fills `output` exactly.
    func decompress(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer) -> Bool {
        guard ready, let source = input.baseAddress, let target = output.baseAddress else { return false }
        inflateReset(&stream)
        stream.next_in = UnsafeMutablePointer(mutating: source.assumingMemoryBound(to: Bytef.self))
        stream.avail_in = uInt(input.count)
        stream.next_out = target.assumingMemoryBound(to: Bytef.self)
        stream.avail_out = uInt(output.count)
        return inflate(&stream, Z_FINISH) == Z_STREAM_END && stream.avail_out == 0
    }
}

// MARK: - Little-endian helpers

fileprivate extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func littleEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var value: T = 0
        Swift.withUnsafeMutableBytes(of: &value) { target in
            let start = startIndex + offset
            target.copyBytes(from: self[start..<start + MemoryLayout<T>.size])
        }
        return T(littleEndian: value)
    }
}

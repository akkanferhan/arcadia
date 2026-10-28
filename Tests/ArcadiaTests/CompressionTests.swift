import Compression
import CryptoKit
import Foundation
import Testing
import zlib
@testable import Arcadia

/// A small disc-like image: zero padding, repeated file data and incompressible noise.
private func sampleDisc(blocks: Int, extra: Int = 0) -> Data {
    var generator = SystemRandomNumberGenerator()
    var data = Data()
    for index in 0..<blocks {
        switch index % 4 {
        case 0: data.append(Data(count: 2048))
        case 1: data.append(Data(String(repeating: "ARCADIA SECTOR \(index) ", count: 120).utf8.prefix(2048)))
        case 2: data.append(Data((0..<2048).map { _ in UInt8.random(in: 0...255, using: &generator) }))
        default: data.append(Data((0..<2048).map { UInt8($0 % 7) }))
        }
    }
    data.append(Data(repeating: 0xAB, count: extra))
    return data
}

private func u32(_ data: Data, _ offset: Int) -> UInt32 {
    data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
}

private func u64(_ data: Data, _ offset: Int) -> UInt64 {
    data.subdata(in: offset..<offset + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
}

@Suite struct DiscImageCodecTests {
    @Test(arguments: DiscImageFormat.allCases)
    func roundTripsLosslessly(format: DiscImageFormat) throws {
        let folder = TemporaryFolder()
        // 2 000 sectors plus a partial block, so the padded last block is exercised too.
        let original = sampleDisc(blocks: 2000, extra: 100)
        let source = folder.write("game.iso", original)
        let target = folder.url.appendingPathComponent("game.\(format.fileExtension)")

        let digest = try DiscImageCodec.compress(source, to: target, format: format) { _ in }
        #expect(digest == SHA256.hash(data: original))
        #expect(try DiscImageCodec.contentDigest(of: target) { _ in } == digest)
        let info = try DiscImageCodec.info(of: target)
        #expect(info.format == format)
        #expect(info.size == UInt64(original.count))
        #expect(try DiscImageCodec.fileSize(target) < UInt64(original.count) * 7 / 10)
    }

    @Test func writesStandardCSOHeaderAndRawDeflateBlocks() throws {
        let folder = TemporaryFolder()
        let original = sampleDisc(blocks: 8)
        let source = folder.write("game.iso", original)
        let target = folder.url.appendingPathComponent("game.cso")
        _ = try DiscImageCodec.compress(source, to: target, format: .cso) { _ in }
        let cso = try Data(contentsOf: target)

        #expect(cso.prefix(4) == Data("CISO".utf8))
        #expect(u32(cso, 4) == 24)
        #expect(u64(cso, 8) == UInt64(original.count))
        #expect(u32(cso, 16) == 2048)
        #expect(cso[20] == 1 && cso[21] == 0)
        // Block 2 is noise, so it is stored as-is and flagged plain.
        #expect(u32(cso, 24 + 2 * 4) & 0x8000_0000 != 0)
        #expect(u32(cso, 24 + 0 * 4) & 0x8000_0000 == 0)
        #expect(Int(u32(cso, 24 + 8 * 4)) == cso.count)

        // Decode block 1 with Apple's own raw-deflate decoder, independent of Arcadia's zlib code.
        let start = Int(u32(cso, 28) & 0x7FFF_FFFF), end = Int(u32(cso, 32) & 0x7FFF_FFFF)
        let compressed = cso.subdata(in: start..<end)
        var output = Data(count: 2048)
        let written = output.withUnsafeMutableBytes { out in
            compressed.withUnsafeBytes { input in
                compression_decode_buffer(out.baseAddress!.assumingMemoryBound(to: UInt8.self), 2048,
                                          input.baseAddress!.assumingMemoryBound(to: UInt8.self), compressed.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        #expect(written == 2048)
        #expect(output == original.subdata(in: 2048..<4096))
    }

    @Test func writesStandardGCZHeaderZlibBlocksAndHashes() throws {
        let folder = TemporaryFolder()
        let original = sampleDisc(blocks: 64)  // 128 KiB: four 32 KiB blocks.
        let source = folder.write("game.iso", original)
        let target = folder.url.appendingPathComponent("game.gcz")
        _ = try DiscImageCodec.compress(source, to: target, format: .gcz) { _ in }
        let gcz = try Data(contentsOf: target)

        #expect(u32(gcz, 0) == 0xB10B_C001)
        #expect(u64(gcz, 16) == UInt64(original.count))
        #expect(u32(gcz, 24) == 32768)
        #expect(u32(gcz, 28) == 4)
        let dataStart = 32 + 4 * 12
        #expect(u64(gcz, 8) == UInt64(gcz.count - dataStart))
        #expect(u64(gcz, 32) == 0)

        let end = Int(u64(gcz, 40) & ~(1 << 63))
        let block = gcz.subdata(in: dataStart..<dataStart + end)
        #expect(u32(gcz, 32 + 4 * 8) == DiscImageCodec.adler(block))
        // A zlib stream, as Dolphin's inflateInit() expects.
        var output = Data(count: 32768)
        var length = uLongf(32768)
        let status = output.withUnsafeMutableBytes { out in
            block.withUnsafeBytes { input in
                uncompress(out.baseAddress!.assumingMemoryBound(to: Bytef.self), &length,
                           input.baseAddress!.assumingMemoryBound(to: Bytef.self), uLong(block.count))
            }
        }
        #expect(status == Z_OK)
        #expect(output == original.prefix(32768))
    }

    @Test(arguments: DiscImageFormat.allCases)
    func noticesDamage(format: DiscImageFormat) throws {
        let folder = TemporaryFolder()
        let original = sampleDisc(blocks: 400)
        let source = folder.write("game.iso", original)
        let target = folder.url.appendingPathComponent("game.\(format.fileExtension)")
        let digest = try DiscImageCodec.compress(source, to: target, format: format) { _ in }

        var damaged = try Data(contentsOf: target)
        damaged[damaged.count - 700] ^= 0x5A
        try damaged.write(to: target)
        let result = try? DiscImageCodec.contentDigest(of: target) { _ in }
        #expect(result != digest)
    }

    @Test func estimatesCloseToTheRealSize() throws {
        let folder = TemporaryFolder()
        let source = folder.write("game.iso", sampleDisc(blocks: 12_000))
        let target = folder.url.appendingPathComponent("game.cso")
        let estimate = try DiscImageCodec.estimatedSize(of: source, format: .cso)
        _ = try DiscImageCodec.compress(source, to: target, format: .cso) { _ in }
        let actual = try DiscImageCodec.fileSize(target)
        #expect(Double(estimate) > Double(actual) * 0.8 && Double(estimate) < Double(actual) * 1.2)
    }
}

@Suite struct CompressionPlanTests {
    private func plan(_ name: String, _ system: String) -> DiscImageFormat? {
        CompressionPlan.plan(for: Game(url: URL(fileURLWithPath: "/g/\(system)/\(name)"), systemID: system))?.format
    }

    @Test func offersOnlyFormatsTheEmulatorPlays() {
        #expect(plan("Game.iso", "psp") == .cso)
        #expect(plan("Game.ISO", "ps2") == .cso)
        #expect(plan("Game.iso", "gc") == .gcz)
        #expect(plan("Game.gcm", "gc") == .gcz)
        #expect(plan("Game.cso", "psp") == nil)
        #expect(plan("Game.rvz", "gc") == nil)
        // Dolphin plays GCZ for Wii too, but Arcadia's Wii folder does not list .gcz.
        #expect(plan("Game.iso", "wii") == nil)
        #expect(plan("Game.cue", "ps1") == nil)
        #expect(plan("Game.iso", "xbox") == nil)
        #expect(plan("Game.iso", "ps3") == nil)
        for system in CompressionPlan.supportedSystems {
            #expect(system.extensions.contains(plan("Game.iso", system.id)!.fileExtension))
        }
    }
}

@Suite struct ReplacementTests {
    @Test func replacesALibraryFileAndTrashesTheOriginal() throws {
        let folder = TemporaryFolder()
        let original = sampleDisc(blocks: 600)
        let game = folder.write("Library/psp/Game (USA).iso", original)
        let trash = folder.folder("Trash")

        let outcome = try Replacement.perform(game, format: .cso, expectedSize: nil, trash: { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }, report: { _ in })

        let cso = folder.url.appendingPathComponent("Library/psp/Game (USA).cso")
        #expect(outcome.newGameURL.standardizedFileURL.path == cso.standardizedFileURL.path)
        #expect(!outcome.originalKept)
        #expect(outcome.saved > 0)
        #expect(!FileManager.default.fileExists(atPath: game.path))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Game (USA).iso").path))
        #expect(try DiscImageCodec.contentDigest(of: cso) { _ in } == SHA256.hash(data: original))
        // Nothing half-written is left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.url.appendingPathComponent("Library/psp").path)
        #expect(leftovers == ["Game (USA).cso"])
        let games = Library.scan(folder.url.appendingPathComponent("Library"))
        #expect(games.map(\.url.lastPathComponent) == ["Game (USA).cso"])
    }

    @Test func compressesBesideTheRealFileOfALinkedGame() throws {
        let folder = TemporaryFolder()
        let real = folder.write("Elsewhere/Game.iso", sampleDisc(blocks: 600))
        let library = folder.folder("Library/gc")
        let link = library.appendingPathComponent("Game.iso")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        var trashed: [URL] = []

        let outcome = try Replacement.perform(link, format: .gcz, expectedSize: nil,
                                              trash: { trashed.append($0); try FileManager.default.removeItem(at: $0) },
                                              report: { _ in })

        let compressed = folder.url.appendingPathComponent("Elsewhere/Game.gcz")
        let newLink = library.appendingPathComponent("Game.gcz")
        #expect(FileManager.default.fileExists(atPath: compressed.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: newLink.path)
                == compressed.resolvingSymlinksInPath().path)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(trashed.map { $0.resolvingSymlinksInPath().path } == [real.resolvingSymlinksInPath().path])
        #expect(outcome.newGameURL.path == newLink.path)
    }

    @Test func keepsTheOriginalWhenTheTrashFails() throws {
        let folder = TemporaryFolder()
        let game = folder.write("psp/Game.iso", sampleDisc(blocks: 200))
        struct NoTrash: Error {}
        let outcome = try Replacement.perform(game, format: .cso, expectedSize: nil,
                                              trash: { _ in throw NoTrash() }, report: { _ in })
        #expect(outcome.originalKept)
        #expect(FileManager.default.fileExists(atPath: game.path))
    }

    @Test func refusesToOverwriteAnExistingCopy() {
        let folder = TemporaryFolder()
        let game = folder.write("psp/Game.iso", sampleDisc(blocks: 50))
        folder.write("psp/Game.cso", Data(count: 10))
        #expect(throws: CompressionError.self) {
            try Replacement.perform(game, format: .cso, expectedSize: nil, trash: { _ in }, report: { _ in })
        }
        #expect(FileManager.default.fileExists(atPath: game.path))
    }
}

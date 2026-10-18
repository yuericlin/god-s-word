// SwordModule.swift
// Reader for SWORD zText Bible modules (BlockType=BOOK, CompressType=ZIP).
// File layout mirrors zVerse: per testament, ot.bzv (10-byte verse index),
// ot.bzs (12-byte block index), ot.bzz (concatenated zlib blocks).
// All integers are little-endian (sysdata.h: no swap when !WORDS_BIGENDIAN).

import Foundation

public enum SwordModuleError: Error, Equatable {
    case missingFile(String)
    case corruptIndex(String)
    case decompressionFailed
}

/// One verse-index entry: which compressed block holds the verse, and the
/// byte range of the verse within the decompressed block.
private struct VerseIndexEntry {
    let block: UInt32
    let start: UInt32
    let size: UInt16
}

private struct BlockIndexEntry {
    let compOffset: UInt32
    let compSize: UInt32
}

private func readU16LE(_ d: [UInt8], _ o: Int) -> UInt16 {
    UInt16(d[o]) | (UInt16(d[o + 1]) << 8)
}

private func readU32LE(_ d: [UInt8], _ o: Int) -> UInt32 {
    UInt32(d[o]) | (UInt32(d[o + 1]) << 8) | (UInt32(d[o + 2]) << 16) | (UInt32(d[o + 3]) << 24)
}

/// An installed zText Bible module.
///
/// Conforms to `Sendable` via `@unchecked`: every stored property is immutable
/// after init except `blockCache`, whose access is serialized by `cacheLock`.
public final class SwordModule: @unchecked Sendable {
    public let versification: Versification
    private let otVerseIndex: [VerseIndexEntry]
    private let ntVerseIndex: [VerseIndexEntry]
    private let otBlockIndex: [BlockIndexEntry]
    private let ntBlockIndex: [BlockIndexEntry]
    private let otData: [UInt8]
    private let ntData: [UInt8]
    /// Cache of decompressed blocks, keyed by testament * 1_000_000 + block.
    /// Guarded by cacheLock: readers may hop across actors (ModuleLoader is an
    /// actor; call sites are main-actor), so unsynchronized mutation is a data race.
    private var blockCache = [Int: [UInt8]]()
    private let cacheLock = NSLock()
    private let maxCachedBlocks = 4

    /// - Parameter moduleDir: directory containing ot.bzv/.bzs/.bzz and nt.*.
    public init(moduleDir: URL, versification: Versification) throws {
        self.versification = versification
        func read(_ name: String) throws -> [UInt8] {
            let url = moduleDir.appendingPathComponent(name)
            guard let d = try? Data(contentsOf: url) else {
                throw SwordModuleError.missingFile(name)
            }
            return [UInt8](d)
        }
        func parseVerseIndex(_ bytes: [UInt8], _ name: String) throws -> [VerseIndexEntry] {
            guard bytes.count % 10 == 0 else { throw SwordModuleError.corruptIndex(name) }
            var out = [VerseIndexEntry]()
            out.reserveCapacity(bytes.count / 10)
            var o = 0
            while o < bytes.count {
                out.append(VerseIndexEntry(block: readU32LE(bytes, o),
                                          start: readU32LE(bytes, o + 4),
                                          size: readU16LE(bytes, o + 8)))
                o += 10
            }
            return out
        }
        func parseBlockIndex(_ bytes: [UInt8], _ name: String) throws -> [BlockIndexEntry] {
            guard bytes.count % 12 == 0 else { throw SwordModuleError.corruptIndex(name) }
            var out = [BlockIndexEntry]()
            out.reserveCapacity(bytes.count / 12)
            var o = 0
            while o < bytes.count {
                out.append(BlockIndexEntry(compOffset: readU32LE(bytes, o),
                                           compSize: readU32LE(bytes, o + 4)))
                o += 12
            }
            return out
        }
        otVerseIndex = try parseVerseIndex(read("ot.bzv"), "ot.bzv")
        ntVerseIndex = try parseVerseIndex(read("nt.bzv"), "nt.bzv")
        otBlockIndex = try parseBlockIndex(read("ot.bzs"), "ot.bzs")
        ntBlockIndex = try parseBlockIndex(read("nt.bzs"), "nt.bzs")
        otData = try read("ot.bzz")
        ntData = try read("nt.bzz")
    }

    private func decompressedBlock(testament: Int, block: UInt32) throws -> [UInt8] {
        let key = testament * 1_000_000 + Int(block)
        if let hit = cacheLock.withLock({ blockCache[key] }) { return hit }
        let (index, data): ([BlockIndexEntry], [UInt8]) =
            testament == 1 ? (otBlockIndex, otData) : (ntBlockIndex, ntData)
        guard Int(block) < index.count else { throw SwordModuleError.corruptIndex("block") }
        let entry = index[Int(block)]
        let start = Int(entry.compOffset), end = start + Int(entry.compSize)
        guard start >= 0 && end <= data.count else { throw SwordModuleError.corruptIndex("block range") }
        let decompressed: [UInt8]
        do {
            decompressed = try Inflate.decompressZlib(Array(data[start ..< end]))
        } catch {
            throw SwordModuleError.decompressionFailed
        }
        cacheLock.withLock {
            if blockCache.count >= maxCachedBlocks {
                blockCache.removeValue(forKey: blockCache.keys.first!)
            }
            blockCache[key] = decompressed
        }
        return decompressed
    }

    /// Raw (still OSIS-marked-up) verse text, or nil when the module has no
    /// entry for the verse (mirrors zText::hasEntry).
    public func rawVerse(testament: Int, book: Int, chapter: Int, verse: Int) -> String? {
        guard let ti = versification.testamentIndex(testament: testament, book: book,
                                                    chapter: chapter, verse: verse) else { return nil }
        let index = testament == 1 ? otVerseIndex : ntVerseIndex
        guard ti >= 0 && ti < index.count else { return nil }
        let entry = index[ti]
        guard entry.size > 0 else { return nil }
        guard let block = try? decompressedBlock(testament: testament, block: entry.block) else { return nil }
        let start = Int(entry.start), end = start + Int(entry.size)
        guard start >= 0 && end <= block.count else { return nil }
        return String(bytes: block[start ..< end], encoding: .utf8)
    }

    /// Plain-text verse for display.
    public func verse(testament: Int, book: Int, chapter: Int, verse: Int) -> String? {
        rawVerse(testament: testament, book: book, chapter: chapter, verse: verse)
            .map { OsisPlain.plainText(from: $0) }
    }

    /// All verses of a chapter as (verseNumber, plainText), skipping empty entries.
    public func chapter(testament: Int, book: Int, chapter: Int) -> [(verse: Int, text: String)] {
        guard let count = versification.verseCount(testament: testament, book: book, chapter: chapter)
        else { return [] }
        var out = [(verse: Int, text: String)]()
        out.reserveCapacity(count)
        for v in 1 ... count {
            if let t = verse(testament: testament, book: book, chapter: chapter, verse: v) {
                out.append((verse: v, text: t))
            }
        }
        return out
    }
}

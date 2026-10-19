// StrongsLexicon.swift
// Reader for Strong's lexicon modules: StrongsHebrew (RawLD driver) and
// StrongsGreek (zLD driver). Both are keyed positionally: H/G number N
// lives at index record N (record 0 is preamble).
//
// RawLD: <base>.idx holds 6-byte records (dataOffset u32 LE, dataSize u16 LE);
//        <base>.dat holds the entry text.
// zLD:   <base>.idx holds 8-byte records (datOffset u32 LE, datSize u32 LE);
//        <base>.dat holds per-entry "NNNNN\r\n" + (block u32 LE, index u32 LE);
//        <base>.zdx holds 12-byte block records (compOffset u32, compSize u32);
//        <base>.zdt holds zlib blocks; each decompressed block starts with
//        [entryCount u32][(dataOffset u32, dataSize u32) x count], then data.

import Foundation

public enum StrongsLexiconError: Error, Equatable {
    case missingFile(String)
    case corruptIndex(String)
}

/// Strong's Hebrew/Greek lexicon.
///
/// Conforms to `Sendable` via `@unchecked`: the backing bytes are immutable
/// after init; the zLD block cache is serialized by `cacheLock`.
public final class StrongsLexicon: @unchecked Sendable {
    private enum Backing: Sendable {
        case rawLD(idx: [UInt8], dat: [UInt8])
        case zLD(idx: [UInt8], dat: [UInt8], zdx: [UInt8], zdt: [UInt8])
    }

    private let backing: Backing
    private var blockCache = [Int: [UInt8]]()
    private let cacheLock = NSLock()
    private let maxCachedBlocks = 8

    private init(backing: Backing) {
        self.backing = backing
    }

    /// Loads a lexicon from its module directory (the DataPath directory,
    /// containing <base>.idx/.dat and, for zLD, <base>.zdx/.zdt).
    public static func load(moduleDir: URL) throws -> StrongsLexicon {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: moduleDir, includingPropertiesForKeys: nil,
                                                 options: .skipsHiddenFiles)) ?? []
        guard let idxURL = files.first(where: { $0.pathExtension.lowercased() == "idx" }) else {
            throw StrongsLexiconError.missingFile("*.idx")
        }
        let base = idxURL.deletingPathExtension()
        func read(_ ext: String) throws -> [UInt8] {
            let url = base.appendingPathExtension(ext)
            guard let d = try? Data(contentsOf: url) else {
                throw StrongsLexiconError.missingFile(url.lastPathComponent)
            }
            return [UInt8](d)
        }
        let idx = try read("idx")
        let dat = try read("dat")
        if fm.fileExists(atPath: base.appendingPathExtension("zdx").path) {
            let zdx = try read("zdx")
            let zdt = try read("zdt")
            return StrongsLexicon(backing: .zLD(idx: idx, dat: dat, zdx: zdx, zdt: zdt))
        } else {
            return StrongsLexicon(backing: .rawLD(idx: idx, dat: dat))
        }
    }

    /// Display-ready definition for "H7225" / "G26" (tags stripped),
    /// or nil when the key is malformed or absent.
    public func definition(for key: String) -> String? {
        guard let n = Self.strongsNumber(from: key), n >= 1 else { return nil }
        let raw: String?
        switch backing {
        case .rawLD(let idx, let dat):
            raw = Self.rawLDEntry(n: n, idx: idx, dat: dat)
        case .zLD(let idx, let dat, let zdx, let zdt):
            raw = zLDEntry(n: n, idx: idx, dat: dat, zdx: zdx, zdt: zdt)
        }
        return raw.map { Self.cleanDefinition($0) }
    }

    /// "H07225" -> 7225, "G26" -> 26, nil for anything else.
    static func strongsNumber(from key: String) -> Int? {
        let k = key.uppercased()
        guard (k.hasPrefix("H") || k.hasPrefix("G")), k.count > 1 else { return nil }
        let digits = k.dropFirst().drop(while: { $0 == "0" })
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        return n
    }

    private static func rawLDEntry(n: Int, idx: [UInt8], dat: [UInt8]) -> String? {
        let recSize = 6
        guard (n + 1) * recSize <= idx.count else { return nil }
        let o = n * recSize
        let dataOffset = Int(readU32LE(idx, o))
        let dataSize = Int(readU16LE(idx, o + 4))
        guard dataSize > 0, dataOffset >= 0, dataOffset + dataSize <= dat.count else { return nil }
        return String(bytes: dat[dataOffset ..< dataOffset + dataSize], encoding: .utf8)
    }

    private func zLDEntry(n: Int, idx: [UInt8], dat: [UInt8], zdx: [UInt8], zdt: [UInt8]) -> String? {
        let recSize = 8
        guard (n + 1) * recSize <= idx.count else { return nil }
        let o = n * recSize
        let datOffset = Int(readU32LE(idx, o))
        let datSize = Int(readU32LE(idx, o + 4))
        let recEnd = datOffset + datSize
        guard datSize > 0, datOffset >= 0, recEnd <= dat.count else { return nil }
        // dat record: "NNNNN\r\n" header, then block u32 + entry-index u32.
        var hs: Int? = nil
        var p = datOffset
        while p + 1 < recEnd {
            if dat[p] == 0x0D && dat[p + 1] == 0x0A { hs = p + 2; break }
            p += 1
        }
        guard let headerEnd = hs, headerEnd + 8 <= recEnd else { return nil }
        let blockNum = Int(readU32LE(dat, headerEnd))
        let entryIdx = Int(readU32LE(dat, headerEnd + 4))
        guard let block = decompressedZLDBlock(blockNum, zdx: zdx, zdt: zdt),
              block.count >= 4
        else { return nil }
        let count = Int(readU32LE(block, 0))
        guard entryIdx >= 0, entryIdx < count else { return nil }
        let eo = 4 + entryIdx * 8
        guard eo + 8 <= block.count else { return nil }
        let dataOffset = Int(readU32LE(block, eo))
        let dataSize = Int(readU32LE(block, eo + 4))
        guard dataSize > 0, dataOffset >= 0, dataOffset + dataSize <= block.count else { return nil }
        return String(bytes: block[dataOffset ..< dataOffset + dataSize], encoding: .utf8)
    }

    private func decompressedZLDBlock(_ block: Int, zdx: [UInt8], zdt: [UInt8]) -> [UInt8]? {
        if let hit = cacheLock.withLock({ blockCache[block] }) { return hit }
        guard block >= 0, (block + 1) * 12 <= zdx.count else { return nil }
        let o = block * 12
        let compOffset = Int(readU32LE(zdx, o))
        let compSize = Int(readU32LE(zdx, o + 4))
        guard compSize > 0, compOffset >= 0, compOffset + compSize <= zdt.count else { return nil }
        guard let dec = try? Inflate.decompressZlib(Array(zdt[compOffset ..< compOffset + compSize]))
        else { return nil }
        cacheLock.withLock {
            if blockCache.count >= maxCachedBlocks { blockCache.removeAll() }
            blockCache[block] = dec
        }
        return dec
    }

    /// Drops the RawLD "00001\" header line, then strips tags/entities.
    static func cleanDefinition(_ raw: String) -> String {
        var s = raw
        if let nl = s.firstIndex(of: "\n") {
            let first = s[..<nl].trimmingCharacters(in: .whitespacesAndNewlines)
            let isHeader = !first.isEmpty && first.dropLast().allSatisfy({ $0.isNumber })
                && first.hasSuffix("\\")
            if isHeader { s = String(s[s.index(after: nl)...]) }
        }
        return OsisPlain.plainText(from: s)
    }
}

private func readU16LE(_ d: [UInt8], _ o: Int) -> UInt16 {
    UInt16(d[o]) | (UInt16(d[o + 1]) << 8)
}

private func readU32LE(_ d: [UInt8], _ o: Int) -> UInt32 {
    UInt32(d[o]) | (UInt32(d[o + 1]) << 8) | (UInt32(d[o + 2]) << 16) | (UInt32(d[o + 3]) << 24)
}

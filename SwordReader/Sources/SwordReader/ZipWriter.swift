// ZipWriter.swift
// Minimal ZIP archive writer (stored entries, UTF-8 names). Used to back up
// installed SWORD modules as one package zip each, in the same layout the
// CrossWire repository uses, so ZipReader / ModuleStore.install read them
// back like any downloaded package (REQ-BK-6).
//
// Entries are stored uncompressed: module data files are already compressed
// (zText/zCom/zLD), so deflating them again gains little.

import Foundation

public enum ZipWriteError: Error, Equatable {
    case tooManyEntries
    case tooLarge
    case emptyName
}

public struct ZipWriter {
    private var body: [UInt8] = []
    private var central: [UInt8] = []
    private var count = 0

    public init() {}

    /// CRC-32 (IEEE), as ZIP requires.
    public static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data {
            crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        return ~crc
    }

    private static let table: [UInt32] = (0 ..< 256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0 ..< 8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }

    /// Adds a file. `name` uses "/" separators and is relative (no leading "/").
    public mutating func add(name: String, data: [UInt8]) throws {
        guard !name.isEmpty else { throw ZipWriteError.emptyName }
        guard count < Int(UInt16.max) else { throw ZipWriteError.tooManyEntries }
        guard data.count < Int(UInt32.max), body.count < Int(UInt32.max) - data.count - 1024
        else { throw ZipWriteError.tooLarge }
        let nameBytes = Array(name.utf8)
        guard nameBytes.count <= Int(UInt16.max) else { throw ZipWriteError.tooLarge }
        let crc = ZipWriter.crc32(data)
        let size = UInt32(data.count)
        let offset = UInt32(body.count)
        let flags: UInt16 = 0x0800            // UTF-8 names
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = 0x0021          // 1980-01-01

        body += ZipWriter.le32(0x0403_4B50)
        body += ZipWriter.le16(20)            // version needed
        body += ZipWriter.le16(flags)
        body += ZipWriter.le16(0)             // method: stored
        body += ZipWriter.le16(dosTime)
        body += ZipWriter.le16(dosDate)
        body += ZipWriter.le32(crc)
        body += ZipWriter.le32(size)          // compressed
        body += ZipWriter.le32(size)          // uncompressed
        body += ZipWriter.le16(UInt16(nameBytes.count))
        body += ZipWriter.le16(0)             // extra length
        body += nameBytes
        body += data

        central += ZipWriter.le32(0x0201_4B50)
        central += ZipWriter.le16(20)         // version made by
        central += ZipWriter.le16(20)         // version needed
        central += ZipWriter.le16(flags)
        central += ZipWriter.le16(0)
        central += ZipWriter.le16(dosTime)
        central += ZipWriter.le16(dosDate)
        central += ZipWriter.le32(crc)
        central += ZipWriter.le32(size)
        central += ZipWriter.le32(size)
        central += ZipWriter.le16(UInt16(nameBytes.count))
        central += ZipWriter.le16(0)          // extra
        central += ZipWriter.le16(0)          // comment
        central += ZipWriter.le16(0)          // disk number
        central += ZipWriter.le16(0)          // internal attributes
        central += ZipWriter.le32(0)          // external attributes
        central += ZipWriter.le32(offset)
        central += nameBytes
        count += 1
    }

    /// The finished archive.
    public func finish() throws -> [UInt8] {
        guard body.count + central.count < Int(UInt32.max) - 64 else {
            throw ZipWriteError.tooLarge
        }
        var out = body
        let cdOffset = UInt32(out.count)
        out += central
        out += ZipWriter.le32(0x0605_4B50)
        out += ZipWriter.le16(0)              // this disk
        out += ZipWriter.le16(0)              // disk with central directory
        out += ZipWriter.le16(UInt16(count))
        out += ZipWriter.le16(UInt16(count))
        out += ZipWriter.le32(UInt32(central.count))
        out += ZipWriter.le32(cdOffset)
        out += ZipWriter.le16(0)              // comment length
        return out
    }

    /// Zips every file under `directory`, with paths relative to it
    /// (e.g. "mods.d/kjv.conf", "modules/texts/ztext/kjv/ot.bzs"), sorted so
    /// the archive is the same each time. Hidden files are skipped.
    public static func archive(directory: URL) throws -> [UInt8] {
        let fm = FileManager.default
        let base = directory.resolvingSymlinksInPath().path
        guard let walker = fm.enumerator(at: directory,
                                         includingPropertiesForKeys: [.isRegularFileKey],
                                         options: .skipsHiddenFiles) else { return try ZipWriter().finish() }
        var files: [(path: String, url: URL)] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(base + "/") else { continue }
            files.append((String(full.dropFirst(base.count + 1)), url))
        }
        files.sort { $0.path < $1.path }
        var writer = ZipWriter()
        for f in files {
            try writer.add(name: f.path, data: [UInt8](try Data(contentsOf: f.url)))
        }
        return try writer.finish()
    }
}

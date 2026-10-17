// SwordReaderTests.swift
// Self-contained unit tests (no network, no fixtures).

import XCTest
@testable import SwordReader

final class InflateTests: XCTestCase {
    // "The quick brown fox jumps over the lazy dog. " * 8, zlib level 9.
    let foxZlib: [UInt8] = [
        120, 218, 11, 201, 72, 85, 40, 44, 205, 76, 206, 86, 72, 42, 202, 47, 207, 83, 72, 203, 175,
        80, 200, 42, 205, 45, 40, 86, 200, 47, 75, 45, 82, 40, 1, 74, 231, 36, 86, 85, 42, 164, 228,
        167, 235, 41, 132, 140, 42, 38, 87, 49, 0, 101, 49, 129, 57,
    ]
    let foxPlain = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 8)

    func testZlibRoundTrip() throws {
        let out = try Inflate.decompressZlib(foxZlib)
        XCTAssertEqual(String(bytes: out, encoding: .utf8), foxPlain)
    }

    func testRawDeflateRoundTrip() throws {
        let raw = Array(foxZlib[2 ..< foxZlib.count - 4])
        let out = try Inflate.decompressRawDeflate(raw)
        XCTAssertEqual(String(bytes: out, encoding: .utf8), foxPlain)
    }

    func testStoredBlock() throws {
        // BFINAL=1, BTYPE=00 (stored), LEN=2, NLEN=0xFFFD, "Hi".
        let stored: [UInt8] = [0x01, 0x02, 0x00, 0xFD, 0xFF, 0x48, 0x69]
        let out = try Inflate.decompressRawDeflate(stored)
        XCTAssertEqual(out, [0x48, 0x69])
    }

    func testBadZlibHeader() {
        XCTAssertThrowsError(try Inflate.decompressZlib([0x00, 0x00, 0x01, 0x02, 0x00, 0x00])) { e in
            XCTAssertEqual(e as? InflateError, .invalidZlibHeader)
        }
    }

    func testAdlerMismatch() {
        var bad = foxZlib
        bad[bad.count - 1] ^= 0xFF
        XCTAssertThrowsError(try Inflate.decompressZlib(bad)) { e in
            XCTAssertEqual(e as? InflateError, .adlerMismatch)
        }
    }

    func testAdler32() {
        XCTAssertEqual(Inflate.adler32([UInt8]("Wikipedia".utf8)), 0x11E60398)
    }

    func testGzip() throws {
        // gzip -9 of the fox string above (mtime=0).
        let gz: [UInt8] = [
            31, 139, 8, 0, 0, 0, 0, 0, 2, 3, 11, 201, 72, 85, 40, 44, 205, 76, 206, 86,
            72, 42, 202, 47, 207, 83, 72, 203, 175, 80, 200, 42, 205, 45, 40, 86, 200, 47, 75, 45,
            82, 40, 1, 74, 231, 36, 86, 85, 42, 164, 228, 167, 235, 41, 132, 140, 42, 38, 87, 49,
            0, 187, 22, 15, 227, 104, 1, 0, 0,
        ]
        let out = try Inflate.decompressGzip(gz)
        XCTAssertEqual(String(bytes: out, encoding: .utf8), foxPlain)
    }

    func testZlibWithPadding() throws {
        // SWORD .bzz blocks are zero-padded after the zlib stream; the
        // decoder must stop at the real stream end like zlib does.
        var padded = foxZlib
        padded.append(contentsOf: [UInt8](repeating: 0, count: 1024))
        let out = try Inflate.decompressZlib(padded)
        XCTAssertEqual(String(bytes: out, encoding: .utf8), foxPlain)
    }

    func testTruncated() {
        XCTAssertThrowsError(try Inflate.decompressRawDeflate([0x01, 0x02])) { e in
            XCTAssertEqual(e as? InflateError, .truncated)
        }
    }
}

final class OsisPlainTests: XCTestCase {
    func testStripsTagsKeepsText() {
        let osis = #"<verse osisID="Gen.1.1">In the <w lemma="strong:H0430">beginning</w> God created<note>fn</note>.</verse>"#
        XCTAssertEqual(OsisPlain.plainText(from: osis), "In the beginning God created.")
    }

    func testEntities() {
        XCTAssertEqual(OsisPlain.plainText(from: "a &lt; b &amp; c &#65; &#x42;"), "a < b & c A B")
    }

    func testLineBreaks() {
        let osis = "first<lb/>second"
        XCTAssertEqual(OsisPlain.plainText(from: osis), "first second")
    }
}

final class SwordConfTests: XCTestCase {
    let sample = """
        ## comment
        [KJV]

        Description=King James Version
        DataPath=./modules/texts/ztext/kjv/
        ModDrv=zText
        BlockType=BOOK
        Versification=KJV
        Lang=en
        Empty=
        """

    func testParse() {
        let conf = SwordConf(text: sample)
        XCTAssertEqual(conf.moduleID, "KJV")
        XCTAssertEqual(conf.displayName, "King James Version")
        XCTAssertEqual(conf.dataPath, "./modules/texts/ztext/kjv/")
        XCTAssertEqual(conf.driver, "zText")
        XCTAssertEqual(conf.blockType, "BOOK")
        XCTAssertEqual(conf.versification, "KJV")
        XCTAssertEqual(conf.language, "en")
        XCTAssertEqual(conf["Empty"], "")
        XCTAssertNil(conf["Missing"])
    }

    func testBOMAndCRLF() {
        let conf = SwordConf(text: "\u{FEFF}[ChiUns]\r\nDescription=和合本\r\nLang=zh-Hans\r\n")
        XCTAssertEqual(conf.moduleID, "ChiUns")
        XCTAssertEqual(conf.displayName, "和合本")
        XCTAssertEqual(conf.language, "zh-Hans")
    }
}

final class VersificationTests: XCTestCase {
    func testKJVBasics() {
        let v = Versification.kjv
        XCTAssertEqual(v.books.count, 66)
        XCTAssertEqual(v.verseCount(testament: 1, book: 1, chapter: 1), 31)
        XCTAssertEqual(v.verseCount(testament: 1, book: 19, chapter: 119), 176)
        XCTAssertEqual(v.verseCount(testament: 2, book: 27, chapter: 22), 21)
        // Mirrors SWORD: module heading=0, OT heading=1, Gen heading=2, Gen 1 heading=3.
        XCTAssertEqual(v.testamentIndex(testament: 1, book: 1, chapter: 1, verse: 1), 4)
        XCTAssertEqual(v.testamentIndex(testament: 2, book: 1, chapter: 1, verse: 1), 4)
        XCTAssertNil(v.testamentIndex(testament: 1, book: 1, chapter: 1, verse: 32))
        XCTAssertNil(v.testamentIndex(testament: 3, book: 1, chapter: 1, verse: 1))
    }

    func testNRSVExists() {
        XCTAssertEqual(Versification.nrsv.books.count, 66)
        XCTAssertNotNil(Versification.named("nrsv"))
        XCTAssertNil(Versification.named("vulg"))
    }

    func testChineseBookNames() {
        XCTAssertEqual(BibleBookNamesZhHans.count, 66)
        XCTAssertEqual(BibleBookNamesZhHans[0], "创世纪")
        XCTAssertEqual(BibleBookNamesZhHans[65], "启示录")
    }
}

final class TarReaderTests: XCTestCase {
    /// Builds a minimal tar in-memory: one file "mods.d/kjv.conf" with 12 bytes.
    func testReadTar() throws {
        var tar = [UInt8]()
        var header = [UInt8](repeating: 0, count: 512)
        let name = Array("mods.d/kjv.conf".utf8)
        header.replaceSubrange(0 ..< name.count, with: name)
        let sizeStr = Array("00000000014".utf8) // 12 in octal
        header.replaceSubrange(124 ..< 124 + sizeStr.count, with: sizeStr)
        header[156] = 48 // '0'
        // checksum (not validated by reader, but fill for realism)
        var csum = 256
        for b in header { csum += Int(b) }
        let csumStr = Array(String(format: "%06o", csum).utf8)
        header.replaceSubrange(148 ..< 148 + csumStr.count, with: csumStr)
        tar.append(contentsOf: header)
        tar.append(contentsOf: Array("hello world!".utf8))
        tar.append(contentsOf: [UInt8](repeating: 0, count: 512 - 12))
        tar.append(contentsOf: [UInt8](repeating: 0, count: 1024))
        let entries = try TarReader.read(tar)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "mods.d/kjv.conf")
        XCTAssertEqual(entries[0].bytes, Array("hello world!".utf8))
    }
}

final class ZipReaderTests: XCTestCase {
    /// Minimal stored-entry zip built in-memory: one file "a.txt" = "hi".
    func testStoredZip() throws {
        var zip = [UInt8]()
        func u16(_ v: Int) { zip.append(UInt8(v & 0xFF)); zip.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ v: Int) { for s in [0, 8, 16, 24] { zip.append(UInt8((v >> s) & 0xFF)) } }
        func str(_ s: String) { zip.append(contentsOf: s.utf8) }
        let name = "a.txt"
        let content: [UInt8] = [0x68, 0x69]
        let localOff = 0
        u32(0x04034B50); u16(20); u16(0x0800); u16(0); u16(0); u16(0); u32(0)
        u32(content.count); u32(content.count); u16(name.count); u16(0); str(name)
        zip.append(contentsOf: content)
        let cdOff = zip.count
        u32(0x02014B50); u16(20); u16(20); u16(0x0800); u16(0); u16(0); u16(0); u32(0)
        u32(content.count); u32(content.count); u16(name.count)
        u16(0); u16(0); u16(0); u16(0); u32(0); u32(localOff); str(name)
        let cdSize = zip.count - cdOff
        let cdCount = 1
        u32(0x06054B50); u16(0); u16(0); u16(cdCount); u16(cdCount)
        u32(cdSize); u32(cdOff); u16(0)
        let reader = try ZipReader(data: zip)
        XCTAssertEqual(reader.entries.count, 1)
        XCTAssertEqual(reader.entries[0].name, "a.txt")
        XCTAssertEqual(try reader.data(for: reader.entries[0]), content)
    }
}

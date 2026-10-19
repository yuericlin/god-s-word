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

final class StrongsTests: XCTestCase {
    func testConfCollectsRepeatedKeys() {
        let conf = SwordConf(text: "[KJV]\nGlobalOptionFilter=OSISFootnotes\nGlobalOptionFilter=OSISStrongs\n")
        XCTAssertEqual(conf["GlobalOptionFilter"], "OSISFootnotes") // first wins, unchanged
        XCTAssertEqual(conf.allValues["GlobalOptionFilter"], ["OSISFootnotes", "OSISStrongs"])
    }

    func testSupportsStrongs() {
        let withStrongs = ModuleInfo(conf: SwordConf(text: "[KJV]\nGlobalOptionFilter=OSISStrongs\n"))
        XCTAssertTrue(withStrongs.supportsStrongs)
        let without = ModuleInfo(conf: SwordConf(text: "[ABC]\nGlobalOptionFilter=OSISFootnotes\n"))
        XCTAssertFalse(without.supportsStrongs)
    }

    func testNormalizeStrongs() {
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H07225"), "H7225")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:G26"), "G26")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H00001"), "H1")
        XCTAssertNil(OsisTokens.normalizeStrongs("x-lemma:H1"))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:H0"))
    }

    func testTokensFromKJVGen1v1() {
        // Real KJV Genesis 1:1 raw markup (verified against CrossWire).
        let raw = #"<w lemma="strong:H07225">In the beginning</w> <w lemma="strong:H0430">God</w> <w lemma="strong:H0853 strong:H01254" morph="strongMorph:TH8804">created</w> <w lemma="strong:H08064">the heaven</w> <w lemma="strong:H0853">and</w> <w lemma="strong:H0776">the earth</w>."#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        let texts = tokens.map { $0.text }
        XCTAssertEqual(texts, ["In", "the", "beginning", "God", "created",
                               "the", "heaven", "and", "the", "earth."])
        XCTAssertEqual(tokens[0].strongs, ["H7225"])
        XCTAssertEqual(tokens[1].strongs, ["H7225"])
        XCTAssertEqual(tokens[4].strongs, ["H853", "H1254"])
        XCTAssertEqual(tokens[9].strongs, ["H776"])
        // Rejoining reproduces the plain text.
        XCTAssertEqual(texts.joined(separator: " "), OsisPlain.plainText(from: raw))
    }

    func testStrongsNumberParsing() {
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "H07225"), 7225)
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "G26"), 26)
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "h1"), 1)
        XCTAssertNil(StrongsLexicon.strongsNumber(from: "7225"))
        XCTAssertNil(StrongsLexicon.strongsNumber(from: "X12"))
    }

    func testCleanDefinition() {
        let raw = "00001\\\n 1  'ab  awb\r\n\r\n a primitive word; father."
        XCTAssertEqual(StrongsLexicon.cleanDefinition(raw), "1 'ab awb a primitive word; father.")
        let xml = "<entryFree><orth>x</orth> <def>hello <b>world</b></def>"
        XCTAssertEqual(StrongsLexicon.cleanDefinition(xml), "x hello world")
    }

    // MARK: - Lexicon fixtures

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Tiny RawLD lexicon: records 0..2 -> preamble, H1, H2.
    func testRawLDLookup() throws {
        let dir = try tempDir()
        let parts = ["preamble", "00001\\\n 1 'ab -- father.", "00002\\\n 2 'ab -- aramaic father."]
        var dat = Data()
        var idx = Data()
        for p in parts {
            let bytes = [UInt8](p.utf8)
            var off = UInt32(dat.count).littleEndian
            var size = UInt16(bytes.count).littleEndian
            idx.append(Data(bytes: &off, count: 4))
            idx.append(Data(bytes: &size, count: 2))
            dat.append(contentsOf: bytes)
        }
        try idx.write(to: dir.appendingPathComponent("test.idx"))
        try dat.write(to: dir.appendingPathComponent("test.dat"))
        let lex = try StrongsLexicon.load(moduleDir: dir)
        XCTAssertEqual(lex.definition(for: "H1"), "1 'ab -- father.")
        XCTAssertEqual(lex.definition(for: "H00002"), "2 'ab -- aramaic father.")
        XCTAssertNil(lex.definition(for: "H3"))
        XCTAssertNil(lex.definition(for: "G1"))
    }

    /// Tiny zLD lexicon (base64 fixture): records 0..2 -> preamble, G1, G2.
    func testZLDLookup() throws {
        let dir = try tempDir()
        let files = [
            ("g.idx", "AAAAAA8AAAAPAAAADwAAAB4AAAAPAAAA"),
            ("g.dat", "MDAwMDANCgAAAAAAAAAAMDAwMDENCgAAAAABAAAAMDAwMDINCgAAAAACAAAA"),
            ("g.zdx", "AAAAAGgAAAA="),
            ("g.zdt", "eJxjZmBgkAFiDiBWAWJrII6H0gVFqYm5STmpNql5JUWVbkWpqQp5tkqGSnY2+UUlGXaJOQUZiTb6YLaCTUpqml1aZlFxiUJOaklJapGNPkgEVasRTGtSagmqzuLU5Py8FBStAKuhLWg="),
        ]
        for (name, b64) in files {
            try Data(base64Encoded: b64)!.write(to: dir.appendingPathComponent(name))
        }
        let lex = try StrongsLexicon.load(moduleDir: dir)
        XCTAssertEqual(lex.definition(for: "G1"), "alpha first letter")
        XCTAssertEqual(lex.definition(for: "G2"), "beta second letter")
        XCTAssertNil(lex.definition(for: "G3"))
        XCTAssertNil(lex.definition(for: "H1"))
    }

    func testLexiconMissingIdx() throws {
        let dir = try tempDir()
        XCTAssertThrowsError(try StrongsLexicon.load(moduleDir: dir))
    }

    // MARK: - Crash regressions (Oct 19, 2026)

    /// plainText must survive empty / whitespace-only input instead of
    /// fatal-erroring in removeLast(). Triggered by the tokenizer's
    /// flushTextRun on verses starting with <w>.
    func testPlainTextEmptyAndBlank() {
        XCTAssertEqual(OsisPlain.plainText(from: ""), "")
        XCTAssertEqual(OsisPlain.plainText(from: "   "), "")
        XCTAssertEqual(OsisPlain.plainText(from: "  a  "), "a")
        XCTAssertEqual(OsisPlain.plainText(from: "<w>x</w>"), "x")
    }

    /// Verse starting with a <w> tag: flushTextRun sees an empty run.
    func testTokensVerseStartingWithW() {
        let tokens = OsisTokens.tokensWithStrongs(
            from: "<w lemma=\"strong:H07225\">In</w> <w lemma=\"strong:H0430\">God</w>")
        XCTAssertEqual(tokens.map(\.text), ["In", "God"])
        XCTAssertEqual(tokens[0].strongs, ["H7225"])
        XCTAssertEqual(tokens[1].strongs, ["H430"])
    }

    /// Leading whitespace and empty <w></w> pairs must not crash either.
    func testTokensBlankRuns() {
        let tokens = OsisTokens.tokensWithStrongs(
            from: " <w lemma=\"strong:H07225\"></w><w lemma=\"strong:H0430\">God</w>")
        XCTAssertEqual(tokens.map(\.text), ["God"])
        XCTAssertEqual(tokens[0].strongs, ["H430"])
    }

    /// Self-closing <w/> carries no word: skipped, and must not swallow
    /// the following <w>...</w> into its (empty) range.
    func testTokensSelfClosingW() {
        let raw = #"<w lemma="strong:G3588" src="18"/><w lemma="strong:G1161">de</w> <w lemma="strong:G2424">Jesus</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        XCTAssertEqual(tokens.map(\.text), ["de", "Jesus"])
        XCTAssertEqual(tokens[0].strongs, ["G1161"])
        XCTAssertEqual(tokens[1].strongs, ["G2424"])
    }

    /// Punctuation glued to words in the plain text stays glued, with the
    /// number staying on the word it belongs to.
    func testTokensPunctuationGlue() {
        let raw = #"<w lemma="strong:H06625">And Pathrusim</w>, (<w lemma="strong:H03695">and Casluhim</w>)"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        let texts = tokens.map { $0.text }
        XCTAssertEqual(texts, ["And", "Pathrusim,", "(and", "Casluhim)"])
        XCTAssertEqual(tokens[2].strongs, ["H3695"])
        XCTAssertEqual(texts.joined(separator: " "), OsisPlain.plainText(from: raw))
    }
}

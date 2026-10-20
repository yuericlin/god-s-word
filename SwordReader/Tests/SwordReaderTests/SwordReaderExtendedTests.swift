// SwordReaderExtendedTests.swift
// Additional unit and integration tests for SwordReader.
// Unit: tokenizer edge cases, Strong's normalization, ChiUns extensions,
//       conf parsing, versification. Integration: full OSIS -> tokens ->
//       Strong's lookup pipelines for KJV and ChiUns.

import XCTest
@testable import SwordReader

// MARK: - Strong's normalization (unit)

final class NormalizeStrongsTests: XCTestCase {
    func testChiUnsExtensionsPassThrough() {
        // H9001-H9004 are ChiUns-specific preposition markers; must survive.
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H9001"), "H9001")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H9002"), "H9002")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H9003"), "H9003")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H9004"), "H9004")
    }

    func testMorphologyCodesFiltered() {
        // Hebrew morphology (8675+) and Greek morphology (5625+) are dropped.
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:H8675"))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:H9000"))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:G5625"))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:G6000"))
        // Boundary: max valid numbers survive.
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H8674"), "H8674")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:G5624"), "G5624")
    }

    func testValidNumbersPassThrough() {
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H07225"), "H7225")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:H1"), "H1")
        XCTAssertEqual(OsisTokens.normalizeStrongs("strong:G26"), "G26")
        XCTAssertEqual(OsisTokens.normalizeStrongs("H430"), "H430")
    }

    func testInvalidFormatsReturnNil() {
        XCTAssertNil(OsisTokens.normalizeStrongs(""))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:"))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:H"))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:X123"))
        XCTAssertNil(OsisTokens.normalizeStrongs("strong:H12A"))
    }
}

// MARK: - ChiUns extension definitions (unit)

final class ChiUnsExtensionTests: XCTestCase {
    func testH9001Definition() {
        let def = StrongsLexicon.chiUnsExtensionDefinition(for: "H9001")
        XCTAssertNotNil(def)
        XCTAssertTrue(def!.contains("לְ"))
        XCTAssertTrue(def!.contains("lamed"))
    }

    func testH9002Definition() {
        let def = StrongsLexicon.chiUnsExtensionDefinition(for: "H9002")
        XCTAssertNotNil(def)
        XCTAssertTrue(def!.contains("בְּ"))
        XCTAssertTrue(def!.contains("bet"))
    }

    func testH9003AndH9004ShareDefinition() {
        let d3 = StrongsLexicon.chiUnsExtensionDefinition(for: "H9003")
        let d4 = StrongsLexicon.chiUnsExtensionDefinition(for: "H9004")
        XCTAssertNotNil(d3)
        XCTAssertNotNil(d4)
        XCTAssertEqual(d3, d4)
        XCTAssertTrue(d3!.contains("כְּ"))
        XCTAssertTrue(d3!.contains("kaf"))
    }

    func testNonExtensionsReturnNil() {
        XCTAssertNil(StrongsLexicon.chiUnsExtensionDefinition(for: "H9000"))
        XCTAssertNil(StrongsLexicon.chiUnsExtensionDefinition(for: "H9005"))
        XCTAssertNil(StrongsLexicon.chiUnsExtensionDefinition(for: "H1234"))
        XCTAssertNil(StrongsLexicon.chiUnsExtensionDefinition(for: "G1234"))
        XCTAssertNil(StrongsLexicon.chiUnsExtensionDefinition(for: ""))
    }
}

// MARK: - Strong's number parsing (unit)

final class StrongsNumberTests: XCTestCase {
    func testParsesWithLeadingZeros() {
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "H00776"), 776)
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "G00026"), 26)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "h7225"), 7225)
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "g5624"), 5624)
    }

    func testRejectsInvalid() {
        XCTAssertNil(StrongsLexicon.strongsNumber(from: ""))
        XCTAssertNil(StrongsLexicon.strongsNumber(from: "H"))
        XCTAssertNil(StrongsLexicon.strongsNumber(from: "7225"))
        XCTAssertNil(StrongsLexicon.strongsNumber(from: "Hebrew123"))
    }
}

// MARK: - Tokenizer edge cases (unit)

final class TokenizerEdgeCaseTests: XCTestCase {
    func testSelfClosingWIsSkipped() {
        let raw = #"Hello <w lemma="strong:H0430"/> world"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        // Self-closing <w/> contributes no text and no Strong's.
        let texts = tokens.map { $0.text }.joined()
        XCTAssertEqual(texts, "Hello  world")
        XCTAssertTrue(tokens.allSatisfy { $0.strongs.isEmpty })
    }

    func testMultipleLemmasOnOneWord() {
        let raw = #"<w lemma="strong:H0853 strong:H01254">created</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].text, "created")
        XCTAssertEqual(tokens[0].strongs, ["H853", "H1254"])
    }

    func testEmptyWTag() {
        let raw = #"<w lemma="strong:H0430"></w>after"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        let texts = tokens.map { $0.text }.joined()
        XCTAssertEqual(texts, "after")
    }

    func testWWithoutLemma() {
        let raw = #"<w>plain</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        XCTAssertEqual(tokens.map { $0.text }.joined(), "plain")
        XCTAssertTrue(tokens.allSatisfy { $0.strongs.isEmpty })
    }

    func testChiUnsCJKTokenization() {
        // ChiUns Genesis 1:1: no spaces; segments split at <w> boundaries.
        let raw = #"<w lemma="strong:H9002 strong:H7225">起初</w><w lemma="strong:H0430">神</w><w lemma="strong:H1254 strong:H0853">创造</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        let texts = tokens.map { $0.text }
        XCTAssertEqual(texts, ["起初", "神", "创造"])
        XCTAssertEqual(tokens[0].strongs, ["H9002", "H7225"])
        XCTAssertEqual(tokens[1].strongs, ["H430"])
        XCTAssertEqual(tokens[2].strongs, ["H1254", "H853"])
        // Concatenation reproduces plain text exactly.
        XCTAssertEqual(texts.joined(), OsisPlain.plainText(from: raw))
    }

    func testMorphologyFilteredInTokens() {
        // H8675 (morphology) must not appear in token Strong's.
        let raw = #"<w lemma="strong:H8675 strong:H0430">word</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        XCTAssertEqual(tokens[0].strongs, ["H430"])
    }
}

// MARK: - SwordConf (unit)

final class SwordConfTests: XCTestCase {
    func testSupportsStrongsDetection() {
        let conf = SwordConf(text: """
            [KJV]
            GlobalOptionFilter=OSISStrongs
            GlobalOptionFilter=OSISFootnotes
            """)
        let info = ModuleInfo(conf: conf)
        XCTAssertTrue(info.supportsStrongs)

        let conf2 = SwordConf(text: """
            [WEB]
            GlobalOptionFilter=OSISFootnotes
            """)
        let info2 = ModuleInfo(conf: conf2)
        XCTAssertFalse(info2.supportsStrongs)
    }

    func testDataDirForBibleVsLexicon() {
        // Bibles: DataPath is a directory.
        let bibleConf = SwordConf(text: """
            [KJV]
            DataPath=./modules/texts/ztext/kjv
            """)
        let bible = ModuleInfo(conf: bibleConf)
        XCTAssertTrue(bible.dataDir.hasSuffix("kjv"))

        // Lexicons: DataPath names the file base, not a directory.
        let lexConf = SwordConf(text: """
            [StrongsHebrew]
            DataPath=./modules/lexdict/rawld/strongshebrew/strongshebrew
            """)
        let lex = ModuleInfo(conf: lexConf)
        // dataDir resolves the containing directory.
        XCTAssertTrue(lex.dataDir.hasSuffix("strongshebrew"))
        XCTAssertFalse(lex.dataDir.hasSuffix("strongshebrew/strongshebrew"))
    }

    func testAllValuesCollectsRepeatedKeys() {
        let conf = SwordConf(text: """
            [KJV]
            GlobalOptionFilter=OSISStrongs
            GlobalOptionFilter=OSISFootnotes
            GlobalOptionFilter=OSISMorph
            """)
        XCTAssertEqual(conf.allValues["GlobalOptionFilter"],
                       ["OSISStrongs", "OSISFootnotes", "OSISMorph"])
    }
}

// MARK: - Integration: full pipelines

final class PipelineIntegrationTests: XCTestCase {
    /// KJV Gen 1:1: OSIS -> tokens -> Strong's numbers -> plain text.
    /// Verifies the whole reader pipeline on real markup.
    func testKJVGen1v1Pipeline() {
        let raw = #"<w lemma="strong:H07225">In the beginning</w> <w lemma="strong:H0430">God</w> <w lemma="strong:H0853 strong:H01254">created</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        let plain = OsisPlain.plainText(from: raw)

        // 1. Tokenization preserves all text.
        XCTAssertEqual(tokens.map { $0.text }.joined(), plain)
        XCTAssertEqual(plain, "In the beginning God created")

        // 2. Strong's numbers extracted and normalized.
        let allStrongs = tokens.flatMap { $0.strongs }
        XCTAssertEqual(allStrongs, ["H7225", "H430", "H853", "H1254"])

        // 3. Numbers parse to integers for lexicon lookup.
        XCTAssertEqual(allStrongs.compactMap { StrongsLexicon.strongsNumber(from: $0) },
                       [7225, 430, 853, 1254])
    }

    /// ChiUns Gen 1:1: verifies H9002 extension flows through the pipeline
    /// and resolves to a built-in definition (no lexicon download needed).
    func testChiUnsGen1v1PipelineWithExtensions() {
        let raw = #"<w lemma="strong:H9002 strong:H7225">起初</w><w lemma="strong:H0430">神</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)

        XCTAssertEqual(tokens[0].strongs, ["H9002", "H7225"])
        // H9002 resolves via the built-in ChiUns extension.
        let def = StrongsLexicon.chiUnsExtensionDefinition(for: "H9002")
        XCTAssertNotNil(def)
        // H7225 is a real Strong's number (would need lexicon download).
        XCTAssertEqual(StrongsLexicon.strongsNumber(from: "H7225"), 7225)
        XCTAssertNil(StrongsLexicon.chiUnsExtensionDefinition(for: "H7225"))
    }

    /// Morphology codes are filtered before reaching the UI layer.
    func testMorphologyFilteringPipeline() {
        let raw = #"<w lemma="strong:H08064">the heaven</w> <w lemma="strong:H8675">morph</w>"#
        let tokens = OsisTokens.tokensWithStrongs(from: raw)
        let allStrongs = tokens.flatMap { $0.strongs }
        // H8675 (morphology) must not leak through.
        XCTAssertEqual(allStrongs, ["H8064"])
        XCTAssertFalse(allStrongs.contains("H8675"))
    }

    /// Verse text with entities and tags cleans to readable plain text.
    func testPlainTextCleaningPipeline() {
        let raw = #"And God <note>footnote</note> said &quot;Let there be light&quot;."#
        let plain = OsisPlain.plainText(from: raw)
        XCTAssertEqual(plain, #"And God  said "Let there be light"."#)
    }
}

// MARK: - Versification (unit)

final class VersificationTests: XCTestCase {
    func testKJVBookCount() {
        XCTAssertEqual(Versification.kjv.books.count, 66)
    }

    func testGenesisChapterCount() {
        let gen = Versification.kjv.books[0]
        XCTAssertEqual(gen.name, "Genesis")
        XCTAssertEqual(gen.chapters, 50)
        // Gen 1 has 31 verses.
        XCTAssertEqual(Versification.kjv.versesPerChapter[0][0], 31)
    }

    func testRevelationLastBook() {
        let rev = Versification.kjv.books[65]
        XCTAssertEqual(rev.name, "Revelation")
        XCTAssertEqual(rev.chapters, 22)
    }

    func testChineseBookNamesCount() {
        XCTAssertEqual(BibleBookNamesZhHans.count, 66)
        XCTAssertEqual(BibleBookNamesZhHans[0], "创世纪")
        XCTAssertEqual(BibleBookNamesZhHans[65], "启示录")
    }
}

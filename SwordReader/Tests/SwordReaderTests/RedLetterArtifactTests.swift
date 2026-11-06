// RedLetterArtifactTests.swift
// REQ-RL-4: the bundled span artifact covers the versions whose
// own data carries no speaker markup (the ChiUns module), in the
// coordinates of the text exactly as rendered.

import XCTest
@testable import SwordReader

final class RedLetterArtifactTests: XCTestCase {

    /// Spans come from the real extraction (NASB1995 primary,
    /// KJV backup, quotation-delimiter audit — Nov 4–5, 2026).
    /// The Father's voice in Matt 3:17 is not Jesus and carries
    /// no span.
    func testFatherVoiceNotPainted() {
        XCTAssertTrue(RedLetterArtifact.spans(versionID: "ChiUns", book: "Matthew",
                                              chapter: 3, verse: 17).isEmpty)
    }

    /// ChiUns John 3:16: the speech opens the verse (「) and runs
    /// to its end — the closing 」 falls in the next verse, as
    /// both ground truths carry the speech through John 3:21.
    /// Matt 4:4's span starts at the 「 (character 7).
    func testChiUnsSpans() {
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "John",
                                    chapter: 3, verse: 16).map { [$0.start, $0.end] },
            [[0, 37]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Matthew",
                                    chapter: 4, verse: 4).map { [$0.start, $0.end] },
            [[7, 40]])
    }

    /// The version id matches case-insensitively (module ids keep
    /// their conf case, e.g. "ChiUns"); versions with their own
    /// markup, and unknown versions, get nothing — their rendering
    /// never consults inflated data.
    func testCoverageBoundaries() {
        XCTAssertFalse(RedLetterArtifact.spans(versionID: "CHIUNS", book: "John",
                                               chapter: 3, verse: 16).isEmpty)
        XCTAssertTrue(RedLetterArtifact.spans(versionID: "KJV", book: "John",
                                              chapter: 3, verse: 16).isEmpty)
        XCTAssertTrue(RedLetterArtifact.spans(versionID: "NASB1995", book: "John",
                                              chapter: 3, verse: 16).isEmpty)
        XCTAssertTrue(RedLetterArtifact.spans(versionID: "NoSuchVersion", book: "John",
                                              chapter: 3, verse: 16).isEmpty)
    }

    /// Chapter queries return exactly that chapter's verses
    /// (a chapter-1 query must not bleed into chapter 11+).
    func testChapterSpans() {
        let ch3 = RedLetterArtifact.chapterSpans(versionID: "ChiUns",
                                                 book: "Matthew", chapter: 3)
        XCTAssertEqual(ch3[15]?.map { [$0.start, $0.end] }, [[6, 34]])
        XCTAssertNil(ch3[17])
        let ch1 = RedLetterArtifact.chapterSpans(versionID: "ChiUns",
                                                 book: "John", chapter: 1)
        XCTAssertTrue(ch1.values.allSatisfy { !$0.isEmpty })
        XCTAssertFalse(ch1.isEmpty)
    }

    /// Regression (Nov 6, 2026): Revelation spans must be
    /// computed on Revelation's own texts. An earlier artifact
    /// build read ChiUns's Jude + Revelation entries shifted by
    /// one to two verses — the module stream carries extra
    /// entries the offline reader's fixed heading model
    /// undercounted — so Rev 22:12 carried 22:10's span
    /// ([6, 25], mid-quote on the true text) and 22:16 carried
    /// 22:14's ([0, 32]). Rebuilt with the reader anchored to
    /// the module's own chapter markers: each span now runs
    /// quote to quote on the verse's own text.
    func testRevelationSpansAreQuoteAligned() {
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Revelation of John",
                                    chapter: 22, verse: 12).map { [$0.start, $0.end] },
            [[0, 25]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Revelation of John",
                                    chapter: 22, verse: 13).map { [$0.start, $0.end] },
            [[0, 33]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Revelation of John",
                                    chapter: 22, verse: 16).map { [$0.start, $0.end] },
            [[0, 48]])
    }
}

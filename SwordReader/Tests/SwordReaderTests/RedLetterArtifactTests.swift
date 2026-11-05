// RedLetterArtifactTests.swift
// REQ-RL-4: the bundled span artifact covers the versions whose
// own data carries no speaker markup (ChiUns, NKJV+), in the
// coordinates of the text exactly as rendered.

import XCTest
@testable import SwordReader

final class RedLetterArtifactTests: XCTestCase {

    /// Spans come from the real extraction (NASB1995 primary,
    /// KJV backup, quotation-delimiter audit — Nov 4–5, 2026):
    /// Jesus's answer to John in Matt 3:15 is exactly the quoted
    /// sentence; the Father's voice in the next-but-one verse is
    /// not Jesus and carries no span in either version.
    func testKnownVerses() {
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "nkjv-plus", book: "Matthew",
                                    chapter: 3, verse: 15).map { [$0.start, $0.end] },
            [[36, 121]])
        XCTAssertTrue(RedLetterArtifact.spans(versionID: "nkjv-plus", book: "Matthew",
                                              chapter: 3, verse: 17).isEmpty)
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
        XCTAssertEqual(ch3[15].map { [$0.start, $0.end] }, [[6, 34]])
        XCTAssertNil(ch3[17])
        let ch1 = RedLetterArtifact.chapterSpans(versionID: "ChiUns",
                                                 book: "John", chapter: 1)
        XCTAssertTrue(ch1.values.allSatisfy { !$0.isEmpty })
        XCTAssertFalse(ch1.isEmpty)
    }
}

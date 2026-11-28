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

    /// REQ-RL-6 (Nov 16, 2026): a saying of Jesus quoted inside
    /// another speaker's speech paints only between its 『…』
    /// marks — Acts 11:16 (Peter quoting the Lord; the table
    /// formerly painted the whole verse) — and sayings the
    /// audit had left unpainted inside a frame are covered:
    /// Acts 20:35 (Paul), Acts 22:8 (the voice from heaven,
    /// recounted by Paul; Paul's own question in the same verse
    /// stays unpainted).
    func testNestedQuotationSpans() {
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Acts",
                                    chapter: 11, verse: 16).map { [$0.start, $0.end] },
            [[9, 29]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Acts",
                                    chapter: 20, verse: 35).map { [$0.start, $0.end] },
            [[41, 51]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Acts",
                                    chapter: 22, verse: 8).map { [$0.start, $0.end] },
            [[17, 34]])
    }

    /// Regenerated Nov 27, 2026 from the amended derivation
    /// rules — the artifact is the derivation's pre-generated
    /// output for ChiUns, never hand-edited (see the policy in
    /// RedLetterArtifact.swift). John 16:17 and 16:18 (sayings
    /// inside the disciples' speech), John 5:12 and 7:36
    /// (frames narrowed to the saying quoted inside them),
    /// John 8:22 (a saying added), Acts 22:10 (a narrator's
    /// carry-over frame removed).
    func testRegeneratedSpans() {
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "John",
                                    chapter: 16, verse: 17).map { [$0.start, $0.end] },
            [[17, 44], [48, 58]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "John",
                                    chapter: 16, verse: 18).map { [$0.start, $0.end] },
            [[9, 15]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "John",
                                    chapter: 5, verse: 12).map { [$0.start, $0.end] },
            [[10, 16]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "John",
                                    chapter: 7, verse: 36).map { [$0.start, $0.end] },
            [[3, 28]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "John",
                                    chapter: 8, verse: 22).map { [$0.start, $0.end] },
            [[8, 22]])
        XCTAssertEqual(
            RedLetterArtifact.spans(versionID: "ChiUns", book: "Acts",
                                    chapter: 22, verse: 10).map { [$0.start, $0.end] },
            [[17, 47]])
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

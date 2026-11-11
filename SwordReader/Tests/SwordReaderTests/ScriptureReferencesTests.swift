// ScriptureReferencesTests.swift
// Tests for the commentary scripture-reference scanner
// (REQ-AP-19). Fixtures are real TSK (Treasury of Scripture
// Knowledge) entry fragments, decoded from the CrossWire module:
// Genesis 1:2, 1:3, and 1:4 entries, the Genesis 1 chapter
// outline entry, and the Genesis 10 and 12 entries below.

import XCTest
@testable import SwordReader

final class ScriptureReferencesTests: XCTestCase {

    private func references(in segments: [ScriptureReferences.Segment])
        -> [(display: String, target: ScriptureReferenceTarget)]
    {
        segments.compactMap { segment in
            if case .reference(let display, let target) = segment {
                return (display, target)
            }
            return nil
        }
    }

    private func target(_ testament: Int, _ book: Int, _ chapter: Int,
                        _ verses: [Int]) -> ScriptureReferenceTarget
    {
        ScriptureReferenceTarget(testament: testament, book: book,
                                 chapter: chapter, verses: verses)
    }

    // TSK on Genesis 1:2: a plain list of book chapter:verse items.
    func testBookChapterVerseList() {
        let segments = ScriptureReferences.segments(
            plain: "Job 26:7; Isa 45:18; Jer 4:23; Na 2:10",
            raw: "<scripRef>Job 26:7; Isa 45:18; Jer 4:23; Na 2:10</scripRef>",
            testament: 1, book: 1, chapter: 1)
        let refs = references(in: segments)
        XCTAssertEqual(refs.map(\.display),
                       ["Job 26:7", "Isa 45:18", "Jer 4:23", "Na 2:10"])
        XCTAssertEqual(refs.map(\.target), [
            target(1, 18, 26, [7]),
            target(1, 23, 45, [18]),
            target(1, 24, 4, [23]),
            target(1, 34, 2, [10]),
        ])
        // The rendered text is unchanged: segments rejoin to plain.
        let rejoined = segments.map { segment -> String in
            switch segment {
            case .text(let s): return s
            case .reference(let display, _): return display
            }
        }.joined()
        XCTAssertEqual(rejoined, "Job 26:7; Isa 45:18; Jer 4:23; Na 2:10")
    }

    // TSK on Genesis 1:3: verse lists ("33:6,9"), a chapter
    // continuation ("148:5" stays in Psalms), and NT books.
    func testVerseListsAndContinuations() {
        let segments = ScriptureReferences.segments(
            plain: "Ps 33:6,9; 148:5; Mt 8:3; Joh 11:43",
            raw: "<scripRef>Ps 33:6,9; 148:5; Mt 8:3; Joh 11:43</scripRef>",
            testament: 1, book: 1, chapter: 1)
        XCTAssertEqual(references(in: segments).map(\.target), [
            target(1, 19, 33, [6, 9]),
            target(1, 19, 148, [5]),
            target(2, 1, 8, [3]),
            target(2, 3, 11, [43]),
        ])
    }

    // TSK on Genesis 1:4: a bare verse list takes the entry's own
    // book and chapter; later items move book, then continue in it.
    func testBareVerseListUsesEntryContext() {
        let segments = ScriptureReferences.segments(
            plain: "10,12,18,25,31; Ec 2:13; 11:7",
            raw: "<scripRef>10,12,18,25,31; Ec 2:13; 11:7</scripRef>",
            testament: 1, book: 1, chapter: 1)
        XCTAssertEqual(references(in: segments).map(\.target), [
            target(1, 1, 1, [10, 12, 18, 25, 31]),
            target(1, 21, 2, [13]),
            target(1, 21, 11, [7]),
        ])
    }

    // TSK's chapter outline entries carry the reference in the
    // passage attribute; the visible text is just the verse number.
    func testPassageAttribute() {
        let segments = ScriptureReferences.segments(
            plain: "3 the light;",
            raw: "<scripRef passage=\"Ge 1:3\">3</scripRef> the light;",
            testament: 1, book: 1, chapter: 1)
        let refs = references(in: segments)
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs.first?.display, "3")
        XCTAssertEqual(refs.first?.target, target(1, 1, 1, [3]))
    }

    // TSK on Genesis 10: chapter continuations in the entry's book,
    // and a range crossing chapters ("14:1-21:45" in Joshua covers
    // Joshua 14 to its end — the target is the starting chapter).
    func testCrossChapterRangeTargetsStartChapter() {
        let segments = ScriptureReferences.segments(
            plain: "13:12-17; 15:18-21; Nu 34:2-15; De 32:8; Jos 12:7,8; 14:1-21:45",
            raw: "<scripRef>13:12-17; 15:18-21; Nu 34:2-15; De 32:8; Jos 12:7,8; 14:1-21:45</scripRef>",
            testament: 1, book: 1, chapter: 10)
        XCTAssertEqual(references(in: segments).map(\.target), [
            target(1, 1, 13, [12, 13, 14, 15, 16, 17]),
            target(1, 1, 15, [18, 19, 20, 21]),
            target(1, 4, 34, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
            target(1, 5, 32, [8]),
            target(1, 6, 12, [7, 8]),
            target(1, 6, 14, Array(1 ... 15)),
        ])
    }

    // TSK on Genesis 1:28 ("be fruitful and multiply"): a run of
    // continuations — a bare verse of the entry's own chapter,
    // then chapter:verse items — all in the entry's book.
    func testContinuationRun() {
        let segments = ScriptureReferences.segments(
            plain: "22; 8:17; 9:1,7; 17:16,20; 22:17,18",
            raw: "<scripRef>22; 8:17; 9:1,7; 17:16,20; 22:17,18</scripRef>",
            testament: 1, book: 1, chapter: 1)
        XCTAssertEqual(references(in: segments).map(\.target), [
            target(1, 1, 1, [22]),
            target(1, 1, 8, [17]),
            target(1, 1, 9, [1, 7]),
            target(1, 1, 17, [16, 20]),
            target(1, 1, 22, [17, 18]),
        ])
    }

    // Lowercase short forms and ranges (the user's "ge 3:1-2").
    func testLowercaseRange() {
        let segments = ScriptureReferences.segments(
            plain: "ge 3:1-2",
            raw: "<scripRef>ge 3:1-2</scripRef>",
            testament: 1, book: 1, chapter: 1)
        XCTAssertEqual(references(in: segments).map(\.target),
                       [target(1, 1, 3, [1, 2])])
    }

    // Margin markers and malformed data are not references.
    func testNonReferencesStayText() {
        let marg = ScriptureReferences.segments(
            plain: "*marg:",
            raw: "<scripRef>*marg:</scripRef>",
            testament: 1, book: 1, chapter: 1)
        XCTAssertEqual(marg, [.text("*marg:")])

        let malformed = ScriptureReferences.segments(
            plain: "28:17:19",
            raw: "<scripRef>28:17:19</scripRef>",
            testament: 1, book: 19, chapter: 33)
        XCTAssertTrue(references(in: malformed).isEmpty)

        let noMarkup = ScriptureReferences.segments(
            plain: "A plain entry.",
            raw: "A plain entry.",
            testament: 1, book: 1, chapter: 1)
        XCTAssertEqual(noMarkup, [.text("A plain entry.")])
    }

    // Text around a scripRef is preserved verbatim and in order.
    func testSurroundingTextPreserved() {
        let segments = ScriptureReferences.segments(
            plain: "without. Job 26:7 Spirit.",
            raw: "without.<br /><scripRef>Job 26:7</scripRef><br />Spirit.",
            testament: 1, book: 1, chapter: 1)
        XCTAssertEqual(segments, [
            .text("without. "),
            .reference(display: "Job 26:7", target: target(1, 18, 26, [7])),
            .text(" Spirit."),
        ])
    }
}

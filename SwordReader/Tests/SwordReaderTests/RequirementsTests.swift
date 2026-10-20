// RequirementsTests.swift
// Tests verifying the user requirements in docs/requirements.md.
// Each test is tagged with its REQ- ID.

import XCTest
@testable import SwordReader

// MARK: - REQ-CP: Copy format

final class CopyFormatRequirementsTests: XCTestCase {
    let texts = [
        1: "In the beginning God created the heaven and the earth.",
        2: "And the earth was without form, and void.",
        3: "And God said, Let there be light.",
        5: "And God called the light Day.",
    ]

    // REQ-CP-1, CP-2, CP-3: single verse, quoted, no number in text.
    func testSingleVerseCopyFormat() {
        let out = VerseFormatting.copyString(
            selectedVerses: [1], verseTexts: texts,
            bookTitle: "Genesis", chapter: 1, version: "KJV")
        XCTAssertEqual(out,
            "\"In the beginning God created the heaven and the earth.\" Genesis 1:1 KJV")
    }

    // REQ-CP-1, CP-2, CP-4: multiple verses, numbers in text.
    func testMultipleVerseCopyFormat() {
        let out = VerseFormatting.copyString(
            selectedVerses: [1, 2], verseTexts: texts,
            bookTitle: "Genesis", chapter: 1, version: "KJV")
        XCTAssertEqual(out,
            "\"1 In the beginning God created the heaven and the earth. " +
            "2 And the earth was without form, and void.\" Genesis 1:1-2 KJV")
    }

    // REQ-CP-5: ranges compressed.
    func testVerseListStringCompression() {
        XCTAssertEqual(VerseFormatting.verseListString([1, 2, 3, 5]), "1-3, 5")
        XCTAssertEqual(VerseFormatting.verseListString([1]), "1")
        XCTAssertEqual(VerseFormatting.verseListString([1, 3, 5]), "1, 3, 5")
        XCTAssertEqual(VerseFormatting.verseListString([]), "")
    }

    func testCopyWithRangeCompression() {
        let out = VerseFormatting.copyString(
            selectedVerses: [1, 2, 3, 5], verseTexts: texts,
            bookTitle: "Genesis", chapter: 1, version: "KJV")
        XCTAssertTrue(out!.contains("Genesis 1:1-3, 5 KJV"))
        XCTAssertTrue(out!.hasPrefix("\"1 "))
    }

    func testCopyEmptySelectionReturnsNil() {
        XCTAssertNil(VerseFormatting.copyString(
            selectedVerses: [], verseTexts: texts,
            bookTitle: "Genesis", chapter: 1, version: "KJV"))
    }

    func testCopySortsUnorderedSelection() {
        let out = VerseFormatting.copyString(
            selectedVerses: [3, 1], verseTexts: texts,
            bookTitle: "Genesis", chapter: 1, version: "KJV")
        XCTAssertTrue(out!.contains("1:1, 3"))
        XCTAssertTrue(out!.hasPrefix("\"1 In the beginning"))
    }
}

// MARK: - REQ-NT: Notes

final class NoteRequirementsTests: XCTestCase {
    // REQ-NT-11: key format.
    func testNoteKeyFormat() {
        let key = NoteKey.make(moduleID: "KJV", testament: 1, book: 1,
                               chapter: 1, verse: 1)
        XCTAssertEqual(key, "KJV:1:1:1:1")
    }

    func testNoteKeyParseRoundTrip() {
        let key = "ChiUns:1:1:1:2"
        let parsed = NoteKey.parse(key)
        XCTAssertEqual(parsed?.moduleID, "ChiUns")
        XCTAssertEqual(parsed?.testament, 1)
        XCTAssertEqual(parsed?.book, 1)
        XCTAssertEqual(parsed?.chapter, 1)
        XCTAssertEqual(parsed?.verse, 2)
    }

    func testNoteKeyParseInvalid() {
        XCTAssertNil(NoteKey.parse(""))
        XCTAssertNil(NoteKey.parse("KJV:1:1:1"))
        XCTAssertNil(NoteKey.parse("KJV:1:1:1:x"))
        XCTAssertNil(NoteKey.parse("KJV:1:1:1:1:extra"))
    }

    // REQ-NT-1, NT-2: anchor at first selected verse.
    func testAnchorAtFirstSelectedVerse() {
        XCTAssertEqual(NoteAnchoring.anchorVerse(selectedVerses: [3, 1, 2]), 1)
        XCTAssertEqual(NoteAnchoring.anchorVerse(selectedVerses: [5]), 5)
    }

    // REQ-NT-1, NT-3: no selection -> chapter note at verse 1.
    func testAnchorDefaultsToVerseOne() {
        XCTAssertEqual(NoteAnchoring.anchorVerse(selectedVerses: []), 1)
    }
}

// MARK: - REQ-BP: Bookmarks panel notes sorting

final class BookmarksPanelRequirementsTests: XCTestCase {
    // REQ-BP-3: notes sorted by (module, testament, book, chapter, verse).
    func testNoteSortOrder() {
        let keys = [
            "KJV:1:2:1:1",   // Exodus
            "KJV:1:1:2:1",   // Genesis ch 2
            "KJV:1:1:1:3",   // Genesis ch 1 v 3
            "KJV:1:1:1:1",   // Genesis ch 1 v 1
            "ChiUns:1:1:1:1",
        ]
        let sorted = keys.compactMap { NoteKey.parse($0) }.sorted {
            ($0.moduleID, $0.testament, $0.book, $0.chapter, $0.verse) <
            ($1.moduleID, $1.testament, $1.book, $1.chapter, $1.verse)
        }
        let result = sorted.map {
            NoteKey.make(moduleID: $0.moduleID, testament: $0.testament,
                         book: $0.book, chapter: $0.chapter, verse: $0.verse)
        }
        XCTAssertEqual(result, [
            "ChiUns:1:1:1:1",
            "KJV:1:1:1:1",
            "KJV:1:1:1:3",
            "KJV:1:1:2:1",
            "KJV:1:2:1:1",
        ])
    }
}

// MARK: - REQ-VP: Verse picker selection rules

final class VersePickerRequirementsTests: XCTestCase {
    /// Models REQ-VP-4/5: selection clears on testament/book/chapter change,
    /// kept on version change.
    struct SelectionModel {
        var selected: Set<Int> = []
        mutating func navigate(testamentChanged: Bool, bookChanged: Bool,
                               chapterChanged: Bool, versionChanged: Bool) {
            if testamentChanged || bookChanged || chapterChanged {
                selected = []
            }
            // versionChanged alone: keep selection (REQ-VP-5)
        }
    }

    func testClearsOnChapterChange() {
        var m = SelectionModel(selected: [1, 2])
        m.navigate(testamentChanged: false, bookChanged: false,
                   chapterChanged: true, versionChanged: false)
        XCTAssertTrue(m.selected.isEmpty)
    }

    func testClearsOnBookChange() {
        var m = SelectionModel(selected: [1])
        m.navigate(testamentChanged: false, bookChanged: true,
                   chapterChanged: false, versionChanged: false)
        XCTAssertTrue(m.selected.isEmpty)
    }

    func testKeepsOnVersionChange() {
        var m = SelectionModel(selected: [1, 2])
        m.navigate(testamentChanged: false, bookChanged: false,
                   chapterChanged: false, versionChanged: true)
        XCTAssertEqual(m.selected, [1, 2])
    }
}

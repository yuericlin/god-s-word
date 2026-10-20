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

// MARK: - REQ-BM: Bookmark palette

final class BookmarkRequirementsTests: XCTestCase {
    // REQ-BM-1: fresh installs start with zero bookmarks (palette empty state).
    // (Enforced by PersonalData default; palette logic tested below.)

    // REQ-BM-2: colors assigned in order, cycling after five.
    func testPaletteOrder() {
        XCTAssertEqual(BookmarkPalette.color(forCount: 0).red, 0.53, accuracy: 0.001)
        XCTAssertEqual(BookmarkPalette.color(forCount: 1).red, 1.00, accuracy: 0.001)
        XCTAssertEqual(BookmarkPalette.color(forCount: 2).red, 0.79, accuracy: 0.001)
        XCTAssertEqual(BookmarkPalette.color(forCount: 3).red, 0.83, accuracy: 0.001)
        XCTAssertEqual(BookmarkPalette.color(forCount: 4).red, 0.56, accuracy: 0.001)
    }

    func testPaletteCyclesAfterFive() {
        let c5 = BookmarkPalette.color(forCount: 5)
        let c0 = BookmarkPalette.color(forCount: 0)
        XCTAssertEqual(c5.red, c0.red)
        XCTAssertEqual(c5.green, c0.green)
        XCTAssertEqual(c5.blue, c0.blue)
    }

    func testPaletteExactValues() {
        // Light sky blue, gold, purple, silver, green (REQ-BM-2).
        let expected: [(Double, Double, Double)] = [
            (0.53, 0.81, 0.98), (1.00, 0.84, 0.40), (0.79, 0.66, 0.91),
            (0.83, 0.83, 0.83), (0.56, 0.93, 0.56),
        ]
        XCTAssertEqual(BookmarkPalette.colors.count, 5)
        for (i, e) in expected.enumerated() {
            let c = BookmarkPalette.colors[i]
            XCTAssertEqual(c.red, e.0, accuracy: 0.001, "bookmark \(i) red")
            XCTAssertEqual(c.green, e.1, accuracy: 0.001, "bookmark \(i) green")
            XCTAssertEqual(c.blue, e.2, accuracy: 0.001, "bookmark \(i) blue")
        }
    }
}

// MARK: - REQ-HI: Reading history log

final class HistoryRequirementsTests: XCTestCase {
    // REQ-HI-3: revisiting dedupes to the front.
    func testDedupeToFront() {
        let log = HistoryLogLogic.insert("Gen1", into: ["Ex1", "Gen1", "Lev1"])
        XCTAssertEqual(log, ["Gen1", "Ex1", "Lev1"])
    }

    // REQ-HI-2: cap at 100 entries.
    func testCapAt100() {
        var log: [Int] = []
        for i in 1...105 { log = HistoryLogLogic.insert(i, into: log) }
        XCTAssertEqual(log.count, 100)
        XCTAssertEqual(log.first, 105)
        XCTAssertEqual(log.last, 6) // 105 - 99
    }

    func testNewEntryAtFront() {
        let log = HistoryLogLogic.insert("New", into: ["A", "B"])
        XCTAssertEqual(log.first, "New")
        XCTAssertEqual(log.count, 3)
    }
}


// MARK: - REQ-CM: Compare versions

final class CompareRequirementsTests: XCTestCase {
    let available = ["KJV", "ChiUns", "ASV", "NKJV+"]

    // REQ-CM-3: nil or empty setting -> only the current version.
    func testNilOrEmptySettingShowsOnlyCurrent() {
        XCTAssertEqual(CompareVersions.ids(current: "KJV", configured: nil,
                                           available: available), ["KJV"])
        XCTAssertEqual(CompareVersions.ids(current: "KJV", configured: [],
                                           available: available), ["KJV"])
    }

    // REQ-CM-4: configured versions union the current one, current first.
    func testConfiguredUnionCurrent() {
        XCTAssertEqual(CompareVersions.ids(current: "KJV",
                                           configured: ["ChiUns", "ASV"],
                                           available: available),
                       ["KJV", "ChiUns", "ASV"])
    }

    // REQ-CM-4: after the current version, the order follows the library
    // (available) order, not the order the versions were chosen in.
    func testOrderFollowsAvailableNotSetting() {
        XCTAssertEqual(CompareVersions.ids(current: "KJV",
                                           configured: ["ASV", "ChiUns"],
                                           available: available),
                       ["KJV", "ChiUns", "ASV"])
    }

    // REQ-CM-4: the current version is never duplicated, wherever it sits
    // in the setting, and a current version outside the setting is added.
    func testCurrentNotDuplicated() {
        XCTAssertEqual(CompareVersions.ids(current: "ASV",
                                           configured: ["KJV", "ASV", "ChiUns"],
                                           available: available),
                       ["ASV", "KJV", "ChiUns"])
        XCTAssertEqual(CompareVersions.ids(current: "KJV",
                                           configured: ["KJV"],
                                           available: available), ["KJV"])
    }

    // REQ-CM-5: versions that are no longer installed are skipped, and
    // duplicate ids in the setting collapse.
    func testUnavailableAndDuplicateIdsSkipped() {
        XCTAssertEqual(CompareVersions.ids(current: "KJV",
                                           configured: ["Gone", "ASV", "ASV"],
                                           available: available),
                       ["KJV", "ASV"])
    }

    // REQ-CM-3: a setting that only names uninstalled versions behaves as
    // empty.
    func testOnlyUnavailableSettingShowsOnlyCurrent() {
        XCTAssertEqual(CompareVersions.ids(current: "KJV", configured: ["Gone"],
                                           available: available), ["KJV"])
    }

    // The current version is always shown, even if (oddly) it isn't in the
    // available list.
    func testCurrentAlwaysIncluded() {
        XCTAssertEqual(CompareVersions.ids(current: "Odd", configured: ["ASV"],
                                           available: available), ["Odd", "ASV"])
    }
}

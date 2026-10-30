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
    // REQ-NT-11: key format (version-less since REQ-NT-19).
    func testNoteKeyFormat() {
        let key = NoteKey.make(testament: 1, book: 1,
                               chapter: 1, verse: 1)
        XCTAssertEqual(key, "1:1:1:1")
    }

    func testNoteKeyParseRoundTrip() {
        let key = "1:1:1:2"
        let parsed = NoteKey.parse(key)
        XCTAssertEqual(parsed?.testament, 1)
        XCTAssertEqual(parsed?.book, 1)
        XCTAssertEqual(parsed?.chapter, 1)
        XCTAssertEqual(parsed?.verse, 2)
    }

    func testNoteKeyParseInvalid() {
        XCTAssertNil(NoteKey.parse(""))
        XCTAssertNil(NoteKey.parse("1:1:1"))
        XCTAssertNil(NoteKey.parse("1:1:1:x"))
        XCTAssertNil(NoteKey.parse("1:1:1:1:extra"))
        // Legacy per-version keys no longer parse as note keys.
        XCTAssertNil(NoteKey.parse("KJV:1:1:1:1"))
    }

    // REQ-NT-19: legacy per-version keys split into module id + the
    // version-less key; current keys and malformed keys do not split.
    func testNoteKeyMigrationSplitLegacy() {
        let verse = NoteKeyMigration.splitLegacy("NASB:1:40:3:5",
                                                 newPartCount: 4)
        XCTAssertEqual(verse?.moduleID, "NASB")
        XCTAssertEqual(verse?.key, "1:40:3:5")
        let book = NoteKeyMigration.splitLegacy("ChiUns:2:1",
                                                newPartCount: 2)
        XCTAssertEqual(book?.moduleID, "ChiUns")
        XCTAssertEqual(book?.key, "2:1")
        XCTAssertNil(NoteKeyMigration.splitLegacy("1:40:3:5",
                                                  newPartCount: 4))
        XCTAssertNil(NoteKeyMigration.splitLegacy("NASB:1:40:3",
                                                  newPartCount: 4))
        XCTAssertNil(NoteKeyMigration.splitLegacy("NASB:1:40:x:5",
                                                  newPartCount: 4))
        XCTAssertNil(NoteKeyMigration.splitLegacy(":1:40:3:5",
                                                  newPartCount: 4))
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
    // REQ-BP-3: notes sorted by (testament, book, chapter, verse).
    func testNoteSortOrder() {
        let keys = [
            "1:2:1:1",   // Exodus
            "1:1:2:1",   // Genesis ch 2
            "1:1:1:3",   // Genesis ch 1 v 3
            "1:1:1:1",   // Genesis ch 1 v 1
        ]
        let sorted = keys.compactMap { NoteKey.parse($0) }.sorted {
            ($0.testament, $0.book, $0.chapter, $0.verse) <
            ($1.testament, $1.book, $1.chapter, $1.verse)
        }
        let result = sorted.map {
            NoteKey.make(testament: $0.testament,
                         book: $0.book, chapter: $0.chapter, verse: $0.verse)
        }
        XCTAssertEqual(result, [
            "1:1:1:1",
            "1:1:1:3",
            "1:1:2:1",
            "1:2:1:1",
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

// MARK: - REQ-BM-8: book location math (assign bookmark)

final class BookLocationRequirementsTests: XCTestCase {
    func testOverallIndexBoundaries() {
        XCTAssertEqual(BookLocation.overallIndex(testament: 1, book: 1), 0)
        XCTAssertEqual(BookLocation.overallIndex(testament: 1, book: 39), 38)
        XCTAssertEqual(BookLocation.overallIndex(testament: 2, book: 1), 39)
        XCTAssertEqual(BookLocation.overallIndex(testament: 2, book: 27), 65)
    }

    func testOverallIndexRejectsOutsideTheBible() {
        XCTAssertNil(BookLocation.overallIndex(testament: 1, book: 0))
        XCTAssertNil(BookLocation.overallIndex(testament: 1, book: 40))
        XCTAssertNil(BookLocation.overallIndex(testament: 2, book: 0))
        XCTAssertNil(BookLocation.overallIndex(testament: 2, book: 28))
        XCTAssertNil(BookLocation.overallIndex(testament: 0, book: 1))
        XCTAssertNil(BookLocation.overallIndex(testament: 3, book: 1))
    }

    func testTestamentAndBookBoundaries() {
        let first = BookLocation.testamentAndBook(overall: 0)
        XCTAssertEqual(first?.testament, 1)
        XCTAssertEqual(first?.book, 1)
        let lastOT = BookLocation.testamentAndBook(overall: 38)
        XCTAssertEqual(lastOT?.testament, 1)
        XCTAssertEqual(lastOT?.book, 39)
        let firstNT = BookLocation.testamentAndBook(overall: 39)
        XCTAssertEqual(firstNT?.testament, 2)
        XCTAssertEqual(firstNT?.book, 1)
        let last = BookLocation.testamentAndBook(overall: 65)
        XCTAssertEqual(last?.testament, 2)
        XCTAssertEqual(last?.book, 27)
        XCTAssertNil(BookLocation.testamentAndBook(overall: -1))
        XCTAssertNil(BookLocation.testamentAndBook(overall: 66))
    }

    func testRoundTripAllSixtySixBooks() {
        for overall in 0..<BookLocation.bookCount {
            let loc = BookLocation.testamentAndBook(overall: overall)
            XCTAssertNotNil(loc, "overall \(overall)")
            if let loc {
                XCTAssertEqual(
                    BookLocation.overallIndex(testament: loc.testament, book: loc.book),
                    overall)
            }
        }
    }
}

// MARK: - REQ-PK-5: version pick keeps the position

final class VersionPickPositionRequirementsTests: XCTestCase {
    // Within range: unchanged, so picking a version doesn't move the reader.
    func testChapterWithinRangeIsKept() {
        XCTAssertEqual(BookLocation.clampedChapter(1, chapterCount: 50), 1)
        XCTAssertEqual(BookLocation.clampedChapter(23, chapterCount: 50), 23)
        XCTAssertEqual(BookLocation.clampedChapter(50, chapterCount: 50), 50)
    }

    // A version with fewer chapters clamps to its last chapter.
    func testChapterPastTheEndIsClamped() {
        XCTAssertEqual(BookLocation.clampedChapter(150, chapterCount: 66), 66)
    }

    func testChapterBelowOneIsClampedToOne() {
        XCTAssertEqual(BookLocation.clampedChapter(0, chapterCount: 10), 1)
        XCTAssertEqual(BookLocation.clampedChapter(-3, chapterCount: 10), 1)
    }

    // A version that lacks the book has no chapters: the caller falls back.
    func testNoChaptersReturnsNil() {
        XCTAssertNil(BookLocation.clampedChapter(1, chapterCount: 0))
        XCTAssertNil(BookLocation.clampedChapter(5, chapterCount: -1))
    }
}

// MARK: - REQ-AP: Auxiliary panel

final class AuxiliaryPanelRequirementsTests: XCTestCase {
    private func conf(_ text: String) -> ModuleInfo {
        ModuleInfo(conf: SwordConf(text: text))
    }

    // REQ-AP-4: an OSIS zCom commentary (MHCC's conf shape) is a
    // commentary and is renderable by the panel.
    func testOSISCommentaryIsRenderable() {
        let info = conf("""
            [MHCC]
            Description=Matthew Henry's Concise Commentary on the Whole Bible
            DataPath=./modules/comments/zcom/mhcc/
            ModDrv=zCom
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=KJV
            Category=Commentaries
            Lang=en
            """)
        XCTAssertTrue(info.isCommentary)
        XCTAssertTrue(info.isCommentaryRenderable)
        XCTAssertFalse(info.isRenderable)
    }

    // REQ-AP-4 originally excluded ThML commentaries; REQ-AP-14
    // supersedes that: a ThML commentary (TSK's conf shape) IS
    // renderable — see LegacyConfRequirementsTests for the details.
    func testThMLCommentaryIsRenderable() {
        let info = conf("""
            [TSK]
            DataPath=./modules/comments/zcom/tsk/
            ModDrv=zCom
            BlockType=BOOK
            CompressType=ZIP
            SourceType=ThML
            Lang=en
            """)
        XCTAssertTrue(info.isCommentary)
        XCTAssertTrue(info.isCommentaryRenderable)
    }

    // REQ-AP-4: a Bible is not a commentary.
    func testBibleIsNotCommentary() {
        let info = conf("""
            [KJV]
            DataPath=./modules/texts/ztext/kjv/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=KJV
            Category=Biblical Texts
            Lang=en
            """)
        XCTAssertFalse(info.isCommentary)
        XCTAssertTrue(info.isRenderable)
    }

    // REQ-SRC-6 (regression, Oct 29, 2026): the "Add Bible" download
    // list showed commentaries — its filter admitted every
    // panel-renderable commentary alongside the Bibles. A Bible is
    // admitted to the list...
    func testAddBibleListAdmitsBible() {
        let info = conf("""
            [KJV]
            DataPath=./modules/texts/ztext/kjv/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=KJV
            Category=Biblical Texts
            Lang=en
            """)
        XCTAssertTrue(info.isDownloadableBible)
    }

    // ...a commentary the panel can read (MHCC's conf shape) is
    // not, even though it is downloadable elsewhere...
    func testAddBibleListExcludesPanelCommentary() {
        let info = conf("""
            [MHCC]
            Description=Matthew Henry's Concise Commentary on the Whole Bible
            DataPath=./modules/comments/zcom/mhcc/
            ModDrv=zCom
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=KJV
            Category=Commentaries
            Lang=en
            """)
        XCTAssertTrue(info.isCommentaryRenderable)
        XCTAssertFalse(info.isDownloadableBible)
    }

    // ...and neither is a commentary riding a zText driver: it
    // satisfies isRenderable, but its Category gives it away, so
    // the Bible checks alone are not enough.
    func testAddBibleListExcludesZTextCommentary() {
        let info = conf("""
            [ZTextCom]
            DataPath=./modules/comments/ztext/ztextcom/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=KJV
            Category=Commentaries
            Lang=en
            """)
        XCTAssertTrue(info.isRenderable)
        XCTAssertTrue(info.isCommentary)
        XCTAssertFalse(info.isDownloadableBible)
    }

    // ...and a dictionary (StrongsGreek's conf shape) is excluded
    // too; it has its own download list.
    func testAddBibleListExcludesDictionary() {
        let info = conf("""
            [StrongsGreek]
            DataPath=./modules/lexdict/zld/strongsgreek/strongsgreek
            ModDrv=zLD
            SourceType=TEI
            Encoding=UTF-8
            CompressType=ZIP
            Lang=en
            """)
        XCTAssertTrue(info.isDictionary)
        XCTAssertFalse(info.isDownloadableBible)
    }

    // REQ-AP-5: consecutive verses sharing one entry collapse into a
    // range; a repeated text later starts a new entry; empties skip.
    func testCommentaryGrouping() {
        let grouped = CommentaryGrouping.group([
            (verse: 1, text: "intro and verses 1-2"),
            (verse: 2, text: "intro and verses 1-2"),
            (verse: 3, text: "verses 3-5"),
            (verse: 4, text: ""),
            (verse: 5, text: "verses 3-5"),
            (verse: 6, text: "intro and verses 1-2"),
        ])
        XCTAssertEqual(grouped, [
            CommentaryGrouping.Entry(startVerse: 1, endVerse: 2,
                                     text: "intro and verses 1-2"),
            CommentaryGrouping.Entry(startVerse: 3, endVerse: 3,
                                     text: "verses 3-5"),
            CommentaryGrouping.Entry(startVerse: 5, endVerse: 5,
                                     text: "verses 3-5"),
            CommentaryGrouping.Entry(startVerse: 6, endVerse: 6,
                                     text: "intro and verses 1-2"),
        ])
        XCTAssertEqual(CommentaryGrouping.entry(in: grouped, covering: 2)?.text,
                       "intro and verses 1-2")
        XCTAssertNil(CommentaryGrouping.entry(in: grouped, covering: 4))
    }

    // REQ-NT-14: book/chapter note keys round-trip and reject bad shapes
    // (version-less since REQ-NT-19).
    func testScopedNoteKeys() {
        let bookKey = BookNoteKey.make(testament: 1, book: 1)
        XCTAssertEqual(bookKey, "1:1")
        XCTAssertEqual(BookNoteKey.parse(bookKey),
                       BookNoteKey.Parsed(testament: 1, book: 1))
        XCTAssertNil(BookNoteKey.parse("1"))
        XCTAssertNil(BookNoteKey.parse("1:1:1"))
        XCTAssertNil(BookNoteKey.parse("KJV:1:1"))

        let chapterKey = ChapterNoteKey.make(testament: 2,
                                             book: 1, chapter: 3)
        XCTAssertEqual(chapterKey, "2:1:3")
        XCTAssertEqual(ChapterNoteKey.parse(chapterKey),
                       ChapterNoteKey.Parsed(testament: 2,
                                              book: 1, chapter: 3))
        XCTAssertNil(ChapterNoteKey.parse("2:1"))
        XCTAssertNil(ChapterNoteKey.parse("2:x:3"))
        XCTAssertNil(ChapterNoteKey.parse("KJV:2:1:3"))
    }

    // REQ-AP-8: the module's DistributionLicense is exposed for the
    // panel's commentary info (commentaries are often copyrighted).
    func testModuleDistributionLicense() {
        let licensed = conf("""
            [Licensed]
            DataPath=./modules/comments/zcom/licensed/
            ModDrv=zCom
            DistributionLicense=Copyrighted; Free for non-commercial use
            Lang=en
            """)
        XCTAssertEqual(licensed.distributionLicense,
                       "Copyrighted; Free for non-commercial use")

        let silent = conf("""
            [Silent]
            DataPath=./modules/comments/zcom/silent/
            ModDrv=zCom
            Lang=en
            """)
        XCTAssertEqual(silent.distributionLicense, "")
    }

    // REQ-AP-7: the Strong's verse source resolution order.
    func testStrongsVerseSourceResolution() {
        // Current version carries Strong's: it wins over any fallback.
        XCTAssertEqual(StrongsVerseSource.resolve(
            currentID: "KJV", currentSupportsStrongs: true,
            fallbackID: "ChiUns", strongsVersionIDs: ["KJV", "ChiUns"]), "KJV")
        // Otherwise the configured fallback, when installed.
        XCTAssertEqual(StrongsVerseSource.resolve(
            currentID: "ASV", currentSupportsStrongs: false,
            fallbackID: "ChiUns", strongsVersionIDs: ["KJV", "ChiUns"]), "ChiUns")
        // Fallback not installed (or unset): first Strong's version.
        XCTAssertEqual(StrongsVerseSource.resolve(
            currentID: "ASV", currentSupportsStrongs: false,
            fallbackID: "Gone", strongsVersionIDs: ["KJV", "ChiUns"]), "KJV")
        XCTAssertEqual(StrongsVerseSource.resolve(
            currentID: "ASV", currentSupportsStrongs: false,
            fallbackID: nil, strongsVersionIDs: ["KJV"]), "KJV")
        // No Strong's version at all.
        XCTAssertNil(StrongsVerseSource.resolve(
            currentID: "ASV", currentSupportsStrongs: false,
            fallbackID: nil, strongsVersionIDs: []))
    }
}

// MARK: - REQ-SRC: Module sources

final class ModuleSourceRequirementsTests: XCTestCase {
    private func conf(_ text: String) -> ModuleInfo {
        ModuleInfo(conf: SwordConf(text: text))
    }

    // REQ-SRC-4: a Bible with no Versification line (NASB1995's conf
    // shape) uses the SWORD default, KJV: renderable, and resolves to
    // the KJV versification so the reader can open it.
    func testBibleWithoutVersificationIsRenderableAsKJV() {
        let info = conf("""
            [NASB1995]
            Description=New American Standard Bible - NASB 1995
            DataPath=./modules/texts/ztext/nasb1995/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Lang=en
            """)
        XCTAssertTrue(info.isRenderable)
        XCTAssertEqual(info.versification?.name, "KJV")
    }

    // REQ-SRC-4: the same default applies to commentaries.
    func testCommentaryWithoutVersificationIsRenderable() {
        let info = conf("""
            [SomeCommentary]
            DataPath=./modules/comments/zcom/somecommentary/
            ModDrv=zCom
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Category=Commentaries
            Lang=en
            """)
        XCTAssertTrue(info.isCommentaryRenderable)
    }

    // REQ-SRC-4: an empty CipherKey= line (the NET Bible's and
    // NA28's conf shape) means not enciphered, so the module is
    // renderable; a real key still locks it out.
    func testEmptyCipherKeyIsNotLocked() {
        let unlocked = conf("""
            [NET]
            DataPath=./modules/texts/ztext/net/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            CipherKey=
            Lang=en
            """)
        XCTAssertTrue(unlocked.isRenderable)

        let locked = conf("""
            [Locked]
            DataPath=./modules/texts/ztext/locked/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            CipherKey=somekey
            Lang=en
            """)
        XCTAssertFalse(locked.isRenderable)
    }

    // REQ-SRC-4: conf values match case-insensitively, as in SWORD —
    // the NET Bible writes BlockType=Book and would otherwise be
    // hidden despite meeting every other condition.
    func testConfValuesMatchCaseInsensitively() {
        let info = conf("""
            [NET]
            DataPath=./modules/texts/ztext/net/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=Book
            CipherKey=
            Lang=en
            """)
        XCTAssertTrue(info.isRenderable)
    }

    // REQ-SRC-4: an explicitly unsupported versification stays
    // unrenderable and unresolved (only the absent line defaults).
    func testOtherVersificationIsNotRenderable() {
        let info = conf("""
            [LXX]
            DataPath=./modules/texts/ztext/lxx/
            ModDrv=zText
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=LXX
            Lang=grc
            """)
        XCTAssertFalse(info.isRenderable)
        XCTAssertNil(info.versification)
    }
}

// MARK: - REQ-NT-18: Notes sub-tabs

final class NotesSubTabRequirementsTests: XCTestCase {
    private func availability(_ recents: Bool, _ book: Bool,
                              _ chapter: Bool, _ verse: Bool)
        -> NotesTabLogic.Availability
    {
        NotesTabLogic.Availability(recents: recents, book: book,
                                   chapter: chapter, verse: verse)
    }

    // Only sub-tabs with notes are visible, in bar order.
    func testVisibleTabsFilterAndOrder() {
        XCTAssertEqual(NotesTabLogic.visibleTabs(availability(true, true, true, true)),
                       [.recents, .book, .chapter, .verse])
        XCTAssertEqual(NotesTabLogic.visibleTabs(availability(true, false, true, false)),
                       [.recents, .chapter])
        XCTAssertEqual(NotesTabLogic.visibleTabs(availability(false, false, false, true)),
                       [.verse])
        XCTAssertEqual(NotesTabLogic.visibleTabs(availability(false, false, false, false)),
                       [])
    }

    // A visible selection resolves to itself.
    func testResolvedKeepsVisibleSelection() {
        let a = availability(true, false, true, false)
        XCTAssertEqual(NotesTabLogic.resolved(selected: .recents, availability: a), .recents)
        XCTAssertEqual(NotesTabLogic.resolved(selected: .chapter, availability: a), .chapter)
    }

    // A hidden selection falls back to the nearest visible sub-tab.
    func testResolvedFallsBackToNearest() {
        // Verse selected, only the chapter has notes besides recents:
        // chapter (distance 1) beats book (2) and recents (3).
        XCTAssertEqual(NotesTabLogic.resolved(
            selected: .verse, availability: availability(true, true, true, false)), .chapter)
        // Verse selected, verse and chapter empty: book wins over recents.
        XCTAssertEqual(NotesTabLogic.resolved(
            selected: .verse, availability: availability(true, true, false, false)), .book)
        // Book selected, the whole book is empty: recents remains.
        XCTAssertEqual(NotesTabLogic.resolved(
            selected: .book, availability: availability(true, false, false, false)), .recents)
        // Chapter selected, chapter and verse empty: book (distance 1).
        XCTAssertEqual(NotesTabLogic.resolved(
            selected: .chapter, availability: availability(true, true, false, false)), .book)
    }

    // Equidistant fallbacks go to the earlier sub-tab in the bar.
    func testResolvedTieGoesToEarlierTab() {
        // Chapter selected; book and verse visible (both distance 1).
        XCTAssertEqual(NotesTabLogic.resolved(
            selected: .chapter, availability: availability(false, true, false, true)), .book)
    }

    // No notes at all: nothing is visible and nothing resolves.
    func testResolvedNilWhenNoNotes() {
        let a = availability(false, false, false, false)
        for tab in NotesSubTab.allCases {
            XCTAssertNil(NotesTabLogic.resolved(selected: tab, availability: a))
        }
    }
}

// REQ-LG-1 / REQ-DC-1: dictionary detection + renderability from real
// catalog conf shapes, and the download-list language filter.
final class DictionaryAndLanguageRequirementsTests: XCTestCase {
    private func conf(_ text: String) -> ModuleInfo {
        ModuleInfo(conf: SwordConf(text: text))
    }

    private var strongsGreek: ModuleInfo {
        conf("""
            [StrongsGreek]
            DataPath=./modules/lexdict/zld/strongsgreek/strongsgreek
            ModDrv=zLD
            SourceType=TEI
            Encoding=UTF-8
            CompressType=ZIP
            Lang=en
            """)
    }

    // REQ-DC-1: the canonical Strong's pair is dictionary-renderable —
    // StrongsGreek (zLD/ZIP) and StrongsHebrew (RawLD, which declares
    // no SourceType, Encoding, or CompressType at all).
    func testStrongsPairIsDictionaryRenderable() {
        XCTAssertTrue(strongsGreek.isDictionary)
        XCTAssertTrue(strongsGreek.isDictionaryRenderable)
        let hebrew = conf("""
            [StrongsHebrew]
            DataPath=./modules/lexdict/rawld/strongshebrew/strongshebrew
            ModDrv=RawLD
            Lang=en
            """)
        XCTAssertTrue(hebrew.isDictionary)
        XCTAssertTrue(hebrew.isDictionaryRenderable)
    }

    // REQ-DC-1: glossaries and daily devotionals use the LD drivers
    // too but are not dictionaries; Bibles are not either.
    func testNonDictionariesExcluded() {
        let devotional = conf("""
            [DBD]
            DataPath=./modules/lexdict/zld/dbd/dbd
            ModDrv=zLD
            Category=Daily Devotional
            CompressType=ZIP
            Lang=en
            """)
        XCTAssertFalse(devotional.isDictionary)
        let glossary = conf("""
            [BR_EN]
            DataPath=./modules/lexdict/rawld/br_en/br_en
            ModDrv=RawLD
            Category=Glossaries
            Lang=br
            """)
        XCTAssertFalse(glossary.isDictionary)
        let bible = conf("""
            [KJV]
            DataPath=./modules/texts/ztext/kjv/
            ModDrv=zText
            CompressType=ZIP
            BlockType=BOOK
            SourceType=OSIS
            Encoding=UTF-8
            Lang=en
            """)
        XCTAssertFalse(bible.isDictionary)
    }

    // REQ-DC-1: a zLD with no ZIP compression (or a cipher key) can't
    // be read, so it isn't renderable even though it is a dictionary.
    func testUncompressedOrLockedLDNotRenderable() {
        let noComp = conf("""
            [RusCarsaDict]
            DataPath=./modules/lexdict/zld/ruscarsadict/ruscarsadict
            ModDrv=zLD
            SourceType=TEI
            Encoding=UTF-8
            Lang=ru
            """)
        XCTAssertTrue(noComp.isDictionary)
        XCTAssertFalse(noComp.isDictionaryRenderable)
        let locked = conf("""
            [LockedDict]
            DataPath=./modules/lexdict/zld/lockeddict/lockeddict
            ModDrv=zLD
            CompressType=ZIP
            Encoding=UTF-8
            CipherKey=secret
            Lang=en
            """)
        XCTAssertFalse(locked.isDictionaryRenderable)
    }

    // REQ-LG-1: an empty selection passes everything.
    func testEmptyLanguageSelectionPassesAll() {
        XCTAssertTrue(strongsGreek.isInLanguages([]))
    }

    // REQ-LG-1: matching is by primary subtag, case-insensitive:
    // "zh" covers zh-Hans and zh-Hant modules; a zh-Hans selection
    // covers a plain "zh" module.
    func testLanguageMatchByPrimarySubtag() {
        let hans = conf("""
            [ChiSstrongsGreek]
            DataPath=./modules/lexdict/zld/chisstrongsgreek/chisstrongsgreek
            ModDrv=zLD
            CompressType=ZIP
            Encoding=UTF-8
            Lang=zh-Hans
            """)
        XCTAssertTrue(hans.isInLanguages(["zh"]))
        XCTAssertTrue(hans.isInLanguages(["ZH", "en"]))
        XCTAssertFalse(hans.isInLanguages(["en", "fr"]))
        XCTAssertFalse(strongsGreek.isInLanguages(["zh"]))
        XCTAssertTrue(strongsGreek.isInLanguages(["en"]))
    }

    // REQ-LG-1: a module with no declared language passes only an
    // empty filter.
    func testLanguagelessModuleFilteredOut() {
        let noLang = conf("""
            [NoLang]
            DataPath=./modules/lexdict/rawld/nolang/nolang
            ModDrv=RawLD
            """)
        XCTAssertFalse(noLang.isInLanguages(["en"]))
        XCTAssertTrue(noLang.isInLanguages([]))
    }
}

// REQ-AP-14: legacy-encoded confs decode tolerantly, and ThML
// commentaries are renderable.
final class LegacyConfRequirementsTests: XCTestCase {
    private func conf(_ text: String) -> ModuleInfo {
        ModuleInfo(conf: SwordConf(text: text))
    }

    // A conf carrying Windows-1252 bytes (0xAE = ®, 0x93/0x94 =
    // smart quotes — NETnotes' actual conf bytes) decodes with the
    // right characters and parses normally, instead of being
    // rejected as invalid UTF-8.
    func testWindows1252ConfDecodes() {
        var bytes = [UInt8]("[NETnotes]\nDescription=NET Bible Footnotes\nAbout=The NET Bible".utf8)
        bytes.append(0xAE)
        bytes.append(contentsOf: [UInt8](", ".utf8))
        bytes.append(0x93)
        bytes.append(contentsOf: [UInt8]("quoted".utf8))
        bytes.append(0x94)
        let parsed = SwordConf(text: SwordConf.decodeText(bytes))
        XCTAssertEqual(parsed.moduleID, "NETnotes")
        XCTAssertEqual(parsed["About"], "The NET Bible®, \u{201C}quoted\u{201D}")
    }

    // Valid UTF-8 still decodes as UTF-8 (the 2-byte ® must not
    // come back as the cp1252 mojibake "Â®").
    func testUTF8ConfDecodesAsUTF8() {
        let text = SwordConf.decodeText([UInt8]("[X]\nAbout=Bible®".utf8))
        XCTAssertEqual(SwordConf(text: text)["About"], "Bible®")
    }

    // REQ-AP-14: a ThML commentary with the zCom storage the reader
    // handles (ZIP, whole-book blocks) is renderable — TSK's actual
    // conf shape, which also declares no Encoding line at all.
    func testThMLCommentaryRenderable() {
        let tsk = conf("""
            [TSK]
            DataPath=./modules/comments/zcom/tsk/
            ModDrv=zCom
            SourceType=ThML
            CompressType=ZIP
            BlockType=BOOK
            Category=Commentaries
            Lang=en
            """)
        XCTAssertTrue(tsk.isCommentaryRenderable)
    }

    // REQ-AP-15: a module with only NT files opens; the OT reads
    // as empty. (Zero-size verse entries need no compressed
    // blocks, so the fixture is just the index files.)
    func testNTOnlyModuleOpens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nt-only-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // One zero-size verse entry; no blocks at all.
        try Data([UInt8](repeating: 0, count: 10)).write(to: dir.appendingPathComponent("nt.bzv"))
        try Data().write(to: dir.appendingPathComponent("nt.bzs"))
        try Data().write(to: dir.appendingPathComponent("nt.bzz"))
        let module = try SwordModule(moduleDir: dir, versification: .kjv)
        XCTAssertEqual(module.chapter(testament: 1, book: 1, chapter: 1).count, 0)
        XCTAssertEqual(module.chapter(testament: 2, book: 1, chapter: 1).count, 0)
        XCTAssertNil(module.verse(testament: 2, book: 1, chapter: 1, verse: 1))
    }

    // REQ-AP-15: a directory with no testament data at all still
    // fails, and a partial file set (index without its data
    // files) still fails as corrupt/missing.
    func testEmptyAndPartialModulesStillFail() throws {
        let fm = FileManager.default
        let empty = fm.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: empty) }
        XCTAssertThrowsError(try SwordModule(moduleDir: empty, versification: .kjv))

        let partial = fm.temporaryDirectory
            .appendingPathComponent("partial-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: partial) }
        try Data([UInt8](repeating: 0, count: 10)).write(to: partial.appendingPathComponent("nt.bzv"))
        XCTAssertThrowsError(try SwordModule(moduleDir: partial, versification: .kjv))
    }

    // REQ-AP-14: ThML alone isn't enough — a CHAPTER-block module
    // (NETnotes' shape, .cz* storage) stays excluded.
    func testChapterBlockThMLStillExcluded() {
        let netnotes = conf("""
            [NETnotes]
            DataPath=./modules/comments/zcom/netnotes/
            ModDrv=zCom
            SourceType=ThML
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=CHAPTER
            Category=Commentaries
            Lang=en
            """)
        XCTAssertFalse(netnotes.isCommentaryRenderable)
    }
}

// MARK: - REQ-AP-16: "4"-driver storage (zText4 / zCom4)

final class V4StorageRequirementsTests: XCTestCase {
    private func conf(_ text: String) -> ModuleInfo {
        ModuleInfo(conf: SwordConf(text: text))
    }

    // REQ-AP-16: TDavid's real conf shape — zCom4, no Category line —
    // is a renderable commentary in the v4 storage format.
    func testTDavidShapeIsRenderableCommentary() {
        let tdavid = conf("""
            [TDavid]
            DataPath=./modules/comments/zcom/tdavid/
            ModDrv=zCom4
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=KJV
            Lang=en
            """)
        XCTAssertTrue(tdavid.isCommentary)
        XCTAssertTrue(tdavid.isCommentaryRenderable)
        XCTAssertTrue(tdavid.usesV4Storage)
    }

    // REQ-AP-16: a zText4 Bible is renderable; a classic zCom
    // commentary is not v4 storage.
    func testZText4BibleRenderableAndV1IsNotV4() {
        let bible = conf("""
            [KTuvB]
            DataPath=./modules/texts/ztext4/ktuvb/
            ModDrv=zText4
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Versification=KJV
            Category=Biblical Texts
            Lang=sw
            """)
        XCTAssertTrue(bible.isRenderable)
        XCTAssertTrue(bible.usesV4Storage)

        let mhcc = conf("""
            [MHCC]
            DataPath=./modules/comments/zcom/mhcc/
            ModDrv=zCom
            SourceType=OSIS
            Encoding=UTF-8
            CompressType=ZIP
            BlockType=BOOK
            Category=Commentaries
            Lang=en
            """)
        XCTAssertTrue(mhcc.isCommentaryRenderable)
        XCTAssertFalse(mhcc.usesV4Storage)
    }

    /// A zlib stream holding `data` in one stored (uncompressed)
    /// block — enough for Inflate to decompress in fixtures.
    private func storedZlib(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01, 0x01]
        let len = UInt16(data.count)
        out += [UInt8(len & 0xff), UInt8(len >> 8)]
        let nlen = ~len
        out += [UInt8(nlen & 0xff), UInt8(nlen >> 8)]
        out += data
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = (b << 16) | a
        out += [UInt8(adler >> 24), UInt8((adler >> 16) & 0xff),
                UInt8((adler >> 8) & 0xff), UInt8(adler & 0xff)]
        return out
    }

    private func u32le(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff),
         UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    // REQ-AP-16: a zVerse4 module (12-byte index entries, 32-bit
    // sizes, same heading-slot numbering as zVerse) opens and its
    // verses read back. OT-only fixture: 24,115 KJV OT slots.
    func testV4ModuleReadsVerses() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let v1 = "In the beginning God created the heaven and the earth."
        let v2 = "And the earth was without form, and void."
        let block = [UInt8]((v1 + v2).utf8)
        let stream = storedZlib(block)

        var bzv = [UInt8](repeating: 0, count: 24_115 * 12)
        // Genesis 1:1 is testament index 4 (slots 0-3 are the
        // module, testament, book and chapter headings); 1:2 is 5.
        for (slot, start, size) in [(4, 0, v1.count), (5, v1.count, v2.count)] {
            let o = slot * 12
            bzv.replaceSubrange(o ..< o + 4, with: u32le(0))
            bzv.replaceSubrange(o + 4 ..< o + 8, with: u32le(UInt32(start)))
            bzv.replaceSubrange(o + 8 ..< o + 12, with: u32le(UInt32(size)))
        }
        try Data(bzv).write(to: dir.appendingPathComponent("ot.bzv"))
        try Data(u32le(0) + u32le(UInt32(stream.count)) + u32le(UInt32(block.count)))
            .write(to: dir.appendingPathComponent("ot.bzs"))
        try Data(stream).write(to: dir.appendingPathComponent("ot.bzz"))

        let module = try SwordModule(moduleDir: dir, versification: .kjv,
                                     format: .zVerse4)
        XCTAssertEqual(module.verse(testament: 1, book: 1, chapter: 1, verse: 1), v1)
        XCTAssertEqual(module.verse(testament: 1, book: 1, chapter: 1, verse: 2), v2)
        XCTAssertEqual(module.chapter(testament: 1, book: 1, chapter: 1).count, 2)
        XCTAssertEqual(module.chapter(testament: 2, book: 1, chapter: 1).count, 0)
    }

    // REQ-AP-16: a classic-width index opened as v4 is corrupt
    // (its byte count isn't a multiple of the 12-byte stride).
    func testV1WidthIndexRejectedAsV4() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v4-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([UInt8](repeating: 0, count: 241_150))
            .write(to: dir.appendingPathComponent("ot.bzv"))
        XCTAssertThrowsError(try SwordModule(moduleDir: dir, versification: .kjv,
                                             format: .zVerse4))
    }
}

// MARK: - REQ-RS-5: section headings ("subtitles")

final class SectionHeadingRequirementsTests: XCTestCase {
    // NASB's Luke 10:1 entry shape: a preverse section title, then
    // the verse text.
    private let luke10_1 = """
        <div type="x-milestone" subType="x-preverse" sID="pv1806"/><title subType="x-preverse" type="section">The Seventy Sent Out</title> <div type="x-milestone" subType="x-preverse" eID="pv1806"/>Now after this the Lord appointed seventy others
        """

    func testSectionTitleExtracted() {
        XCTAssertEqual(OsisPlain.sectionTitle(from: luke10_1), "The Seventy Sent Out")
    }

    func testSectionTitleRemovedFromVerseText() {
        let cleaned = OsisPlain.plainText(from: OsisPlain.removingSectionTitles(luke10_1))
        XCTAssertEqual(cleaned, "Now after this the Lord appointed seventy others")
    }

    // NASB Psalm 3:1 carries TWO preverse titles: the section
    // heading and the canonical psalm title. Only the section
    // heading is a subtitle; the psalm title is scripture text
    // and stays in the verse.
    func testCanonicalPsalmTitleStaysInText() {
        let ps3_1 = """
            <title subType="x-preverse" type="section">Morning Prayer of Trust in God.</title> <title canonical="true" subType="x-preverse" type="psalm">A Psalm of David, when he fled from Absalom his son.</title> O Lord, how many are my foes!
            """
        XCTAssertEqual(OsisPlain.sectionTitle(from: ps3_1), "Morning Prayer of Trust in God.")
        let cleaned = OsisPlain.plainText(from: OsisPlain.removingSectionTitles(ps3_1))
        XCTAssertEqual(cleaned, "A Psalm of David, when he fled from Absalom his son. O Lord, how many are my foes!")
    }

    // A title that isn't a preverse section title (TDavid's
    // "Psalm 1 OVERVIEW" shape) is not a heading and is untouched.
    func testNonSectionTitleUntouched() {
        let raw = "<title type=\"x-s\">Psalm 1 OVERVIEW</title> Blessed is the man"
        XCTAssertNil(OsisPlain.sectionTitle(from: raw))
        XCTAssertEqual(OsisPlain.removingSectionTitles(raw), raw)
    }

    /// A zlib stream holding `data` in one stored block.
    private func storedZlib(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01, 0x01]
        let len = UInt16(data.count)
        out += [UInt8(len & 0xff), UInt8(len >> 8)]
        let nlen = ~len
        out += [UInt8(nlen & 0xff), UInt8(nlen >> 8)]
        out += data
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = (b << 16) | a
        out += [UInt8(adler >> 24), UInt8((adler >> 16) & 0xff),
                UInt8((adler >> 8) & 0xff), UInt8(adler & 0xff)]
        return out
    }

    private func u32le(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff),
         UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    private func u16le(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xff), UInt8(v >> 8)]
    }

    // End to end through SwordModule: Genesis 1:1 with a "The
    // Creation" heading reads as clean verse text plus a heading.
    func testModuleSeparatesHeadingFromVerse() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let raw = "<title subType=\"x-preverse\" type=\"section\">The Creation</title> In the beginning God created the heaven and the earth."
        let block = [UInt8](raw.utf8)
        let stream = storedZlib(block)
        var bzv = [UInt8](repeating: 0, count: 24_115 * 10)
        // Genesis 1:1 is testament index 4 in the classic format.
        let o = 4 * 10
        bzv.replaceSubrange(o ..< o + 4, with: u32le(0))
        bzv.replaceSubrange(o + 4 ..< o + 8, with: u32le(0))
        bzv.replaceSubrange(o + 8 ..< o + 10, with: u16le(UInt16(block.count)))
        try Data(bzv).write(to: dir.appendingPathComponent("ot.bzv"))
        try Data(u32le(0) + u32le(UInt32(stream.count)) + u32le(UInt32(block.count)))
            .write(to: dir.appendingPathComponent("ot.bzs"))
        try Data(stream).write(to: dir.appendingPathComponent("ot.bzz"))

        let module = try SwordModule(moduleDir: dir, versification: .kjv)
        XCTAssertEqual(module.verse(testament: 1, book: 1, chapter: 1, verse: 1),
                       "In the beginning God created the heaven and the earth.")
        XCTAssertEqual(module.heading(testament: 1, book: 1, chapter: 1, verse: 1),
                       "The Creation")
        XCTAssertEqual(module.chapterHeadings(testament: 1, book: 1, chapter: 1),
                       [1: "The Creation"])
    }
}

// MARK: - REQ-AP-17: raw drivers (RawCom)

final class RawComRequirementsTests: XCTestCase {
    private func conf(_ text: String) -> ModuleInfo {
        ModuleInfo(conf: SwordConf(text: text))
    }

    // REQ-AP-17: DTN's real conf shape — RawCom, GBF source, no
    // Category / Encoding / Versification / compression lines —
    // is a renderable commentary in the raw storage format.
    func testDTNShapeIsRenderableCommentary() {
        let dtn = conf("""
            [DTN]
            DataPath=./modules/comments/rawcom/dtn/
            ModDrv=RawCom
            SourceType=GBF
            Lang=en
            Description=Darby Translation Notes
            """)
        XCTAssertTrue(dtn.isCommentary)
        XCTAssertTrue(dtn.isCommentaryRenderable)
        XCTAssertTrue(dtn.usesRawStorage)
        XCTAssertFalse(dtn.usesV4Storage)
        XCTAssertFalse(dtn.isRenderable)
    }

    // REQ-AP-17: the raw path's guards — GBF is admitted only for
    // RawCom (a zCom GBF module stays excluded), an enciphered
    // RawCom stays excluded, and a RawText Bible is raw storage
    // but not yet a listed Bible.
    func testRawComGuards() {
        let zcomGbf = conf("""
            [X]
            ModDrv=zCom
            SourceType=GBF
            CompressType=ZIP
            BlockType=BOOK
            Category=Commentaries
            Lang=en
            """)
        XCTAssertFalse(zcomGbf.isCommentaryRenderable)

        let locked = conf("""
            [Y]
            ModDrv=RawCom
            SourceType=OSIS
            CipherKey=secret
            Lang=en
            """)
        XCTAssertTrue(locked.isCommentary)
        XCTAssertFalse(locked.isCommentaryRenderable)

        let rawBible = conf("""
            [Z]
            ModDrv=RawText
            SourceType=OSIS
            Encoding=UTF-8
            Category=Biblical Texts
            Lang=en
            """)
        XCTAssertTrue(rawBible.usesRawStorage)
        XCTAssertFalse(rawBible.isRenderable)
    }

    private func u32le(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff),
         UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    private func u16le(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xff), UInt8(v >> 8)]
    }

    /// A .vss index with `records` 6-byte entries; `filled` maps
    /// slot -> (offset, size).
    private func vss(records: Int, filled: [Int: (Int, Int)]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: records * 6)
        for (slot, range) in filled {
            out.replaceSubrange(slot * 6 ..< slot * 6 + 4, with: u32le(UInt32(range.0)))
            out.replaceSubrange(slot * 6 + 4 ..< slot * 6 + 6, with: u16le(UInt16(range.1)))
        }
        return out
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("raw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // REQ-AP-17: a raw module opens and its entries read back —
    // rawVerse verbatim, verse() with GBF tags stripped; verses
    // without an entry (and slots past the index) read as absent.
    func testRawModuleReadsEntries() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let e1 = "1:1\n  God (a-4)\n  Heb. <FI>Elohim<Fi>, the plural."
        let e2 = "1:2\n  waste (b-5)\n  See Isa. 34.11; 45.18."
        let data = [UInt8]((e1 + e2).utf8)
        // Slots 0-3 are the heading slots; Genesis 1:1 is slot 4.
        try Data(vss(records: 6, filled: [4: (0, e1.count), 5: (e1.count, e2.count)]))
            .write(to: dir.appendingPathComponent("ot.vss"))
        try Data(data).write(to: dir.appendingPathComponent("ot"))

        let module = try SwordModule(moduleDir: dir, versification: .kjv, format: .raw)
        XCTAssertEqual(module.rawVerse(testament: 1, book: 1, chapter: 1, verse: 1), e1)
        XCTAssertEqual(module.rawVerse(testament: 1, book: 1, chapter: 1, verse: 2), e2)
        let plain = module.verse(testament: 1, book: 1, chapter: 1, verse: 1)
        XCTAssertTrue(plain?.contains("Elohim") ?? false)
        XCTAssertFalse(plain?.contains("<FI>") ?? true)
        XCTAssertNil(module.verse(testament: 1, book: 1, chapter: 1, verse: 3))
        XCTAssertEqual(module.chapter(testament: 1, book: 1, chapter: 1).count, 2)
        XCTAssertEqual(module.chapter(testament: 2, book: 1, chapter: 1).count, 0)
    }

    // REQ-AP-17 + REQ-AP-15: an NT-only raw module opens with
    // the OT reading as empty.
    func testRawNTOnlyModuleOpens() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let e = "1:11\n  away (a-14) In those days conquerors transported conquered nations."
        // Matthew 1:11 is NT slot 14.
        try Data(vss(records: 15, filled: [14: (0, e.count)]))
            .write(to: dir.appendingPathComponent("nt.vss"))
        try Data([UInt8](e.utf8)).write(to: dir.appendingPathComponent("nt"))

        let module = try SwordModule(moduleDir: dir, versification: .kjv, format: .raw)
        XCTAssertEqual(module.rawVerse(testament: 2, book: 1, chapter: 1, verse: 11), e)
        XCTAssertNil(module.rawVerse(testament: 1, book: 1, chapter: 1, verse: 1))
    }

    // REQ-AP-17: a half-present testament (index without data)
    // is corruption, and a .vss whose size isn't a multiple of
    // the 6-byte stride is a corrupt index.
    func testRawCorruptShapesThrow() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(vss(records: 6, filled: [:])).write(to: dir.appendingPathComponent("ot.vss"))
        XCTAssertThrowsError(try SwordModule(moduleDir: dir, versification: .kjv, format: .raw))

        let dir2 = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir2) }
        try Data([UInt8](repeating: 0, count: 7)).write(to: dir2.appendingPathComponent("ot.vss"))
        try Data().write(to: dir2.appendingPathComponent("ot"))
        XCTAssertThrowsError(try SwordModule(moduleDir: dir2, versification: .kjv, format: .raw))
    }
}

// MARK: - REQ-BK-6: module packages for manual backup

final class ModulePackageBackupRequirementsTests: XCTestCase {
    // The standard CRC-32 check value.
    func testCRC32CheckValue() {
        XCTAssertEqual(ZipWriter.crc32(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(ZipWriter.crc32([]), 0)
    }

    // What the writer produces, the reader (used by ModuleStore.install)
    // reads back, byte for byte.
    func testWriterOutputIsReadByZipReader() throws {
        var w = ZipWriter()
        let conf = Array("[KJV]\nDataPath=./modules/texts/ztext/kjv/\n".utf8)
        let blob = (0 ..< 5000).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        try w.add(name: "mods.d/kjv.conf", data: conf)
        try w.add(name: "modules/texts/ztext/kjv/ot.bzs", data: blob)
        try w.add(name: "modules/texts/ztext/kjv/empty", data: [])
        let zip = try w.finish()
        let reader = try ZipReader(data: zip)
        XCTAssertEqual(reader.entries.map { $0.name },
                       ["mods.d/kjv.conf", "modules/texts/ztext/kjv/ot.bzs",
                        "modules/texts/ztext/kjv/empty"])
        XCTAssertEqual(try reader.data(for: reader.entry(named: "mods.d/kjv.conf")!), conf)
        XCTAssertEqual(try reader.data(for: reader.entry(named: "modules/texts/ztext/kjv/ot.bzs")!), blob)
        XCTAssertEqual(try reader.data(for: reader.entry(named: "modules/texts/ztext/kjv/empty")!), [])
    }

    func testNonASCIINamesSurvive() throws {
        var w = ZipWriter()
        try w.add(name: "mods.d/和合本.conf", data: [1, 2, 3])
        let reader = try ZipReader(data: try w.finish())
        XCTAssertEqual(reader.entries.first?.name, "mods.d/和合本.conf")
    }

    func testEmptyArchiveIsValid() throws {
        let reader = try ZipReader(data: try ZipWriter().finish())
        XCTAssertTrue(reader.entries.isEmpty)
    }

    func testEmptyNameIsRejected() {
        var w = ZipWriter()
        XCTAssertThrowsError(try w.add(name: "", data: [1])) {
            XCTAssertEqual($0 as? ZipWriteError, .emptyName)
        }
    }

    // A module folder packs with paths relative to it (the layout of a
    // CrossWire package), sorted, and unpacks to the same files.
    func testArchiveOfAModuleFolderUsesRelativePaths() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("zipw-\(UUID().uuidString)", isDirectory: true)
        let mod = root.appendingPathComponent("KJV", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let files: [String: [UInt8]] = [
            "mods.d/kjv.conf": Array("[KJV]\n".utf8),
            "modules/texts/ztext/kjv/ot.bzv": [9, 8, 7],
            "modules/texts/ztext/kjv/nt.bzs": [6, 5],
        ]
        for (path, bytes) in files {
            let url = mod.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try Data(bytes).write(to: url)
        }
        let zip = try ZipWriter.archive(directory: mod)
        let reader = try ZipReader(data: zip)
        XCTAssertEqual(reader.entries.map { $0.name },
                       files.keys.sorted())
        for entry in reader.entries {
            XCTAssertEqual(try reader.data(for: entry), files[entry.name])
        }
    }

    func testArchiveOfAMissingFolderIsEmpty() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-\(UUID().uuidString)")
        let reader = try ZipReader(data: try ZipWriter.archive(directory: missing))
        XCTAssertTrue(reader.entries.isEmpty)
    }
}

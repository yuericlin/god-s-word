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

    // REQ-AP-4: a ThML commentary (TSK's conf shape) is a commentary but
    // not renderable yet.
    func testThMLCommentaryIsNotRenderable() {
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
        XCTAssertFalse(info.isCommentaryRenderable)
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

    // REQ-NT-14: book/chapter note keys round-trip and reject bad shapes.
    func testScopedNoteKeys() {
        let bookKey = BookNoteKey.make(moduleID: "KJV", testament: 1, book: 1)
        XCTAssertEqual(bookKey, "KJV:1:1")
        XCTAssertEqual(BookNoteKey.parse(bookKey),
                       BookNoteKey.Parsed(moduleID: "KJV", testament: 1, book: 1))
        XCTAssertNil(BookNoteKey.parse("KJV:1"))
        XCTAssertNil(BookNoteKey.parse("KJV:1:1:1"))

        let chapterKey = ChapterNoteKey.make(moduleID: "KJV", testament: 2,
                                             book: 1, chapter: 3)
        XCTAssertEqual(chapterKey, "KJV:2:1:3")
        XCTAssertEqual(ChapterNoteKey.parse(chapterKey),
                       ChapterNoteKey.Parsed(moduleID: "KJV", testament: 2,
                                              book: 1, chapter: 3))
        XCTAssertNil(ChapterNoteKey.parse("KJV:2:1"))
        XCTAssertNil(ChapterNoteKey.parse("KJV:2:x:3"))
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

// MARK: - REQ-HI-3, REQ-HI-7..9: combined reading history

final class CombinedHistoryRequirementsTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func hours(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

    func record(_ log: [ReadingHistoryEntry], _ module: String, book: Int = 1,
                chapter: Int = 1, at: Date) -> [ReadingHistoryEntry] {
        ReadingHistoryLog.recording(moduleID: module, bookName: "Book\(book)",
                                    testament: 1, book: book, chapter: chapter,
                                    at: at, into: log)
    }

    // REQ-HI-7: a revisit within 24 hours joins the entry: one more
    // timestamp, and the version when it is new.
    func testRevisitWithin24HoursMergesTimestampAndVersion() {
        var log = record([], "KJV", at: t0)
        log = record(log, "ChiUns", at: hours(2))
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log[0].timestamps, [t0, hours(2)])
        XCTAssertEqual(log[0].moduleIDs, ["KJV", "ChiUns"])
        XCTAssertEqual(log[0].moduleID, "ChiUns")   // most recent version
        XCTAssertEqual(log[0].earliest, t0)
    }

    // The same version again adds a timestamp but no duplicate version.
    func testSameVersionAddsTimestampOnly() {
        var log = record([], "KJV", at: t0)
        log = record(log, "KJV", at: hours(3))
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log[0].moduleIDs, ["KJV"])
        XCTAssertEqual(log[0].timestamps.count, 2)
    }

    // Reading an earlier version again makes it the most recent one.
    func testReusedVersionBecomesMostRecent() {
        var log = record([], "KJV", at: t0)
        log = record(log, "ChiUns", at: hours(1))
        log = record(log, "KJV", at: hours(2))
        XCTAssertEqual(log[0].moduleIDs, ["ChiUns", "KJV"])
        XCTAssertEqual(log[0].moduleID, "KJV")
    }

    // REQ-HI-7: past 24 hours it starts a new entry; the newer one is first.
    func testRevisitAfter24HoursStartsNewEntry() {
        var log = record([], "KJV", at: t0)
        log = record(log, "KJV", at: hours(25))
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log[0].timestamps, [hours(25)])
        XCTAssertEqual(log[1].timestamps, [t0])
    }

    // The window runs from the entry's earliest visit, not its latest, so
    // an entry can't stretch forever by being revisited every day.
    func testWindowIsMeasuredFromTheEarliestVisit() {
        var log = record([], "KJV", at: t0)
        log = record(log, "KJV", at: hours(20))   // joins (20h from earliest)
        log = record(log, "KJV", at: hours(30))   // 30h from earliest: new entry
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log[1].timestamps, [t0, hours(20)])
        XCTAssertEqual(log[0].timestamps, [hours(30)])
    }

    // Different chapters never merge.
    func testDifferentChaptersStaySeparate() {
        var log = record([], "KJV", chapter: 1, at: t0)
        log = record(log, "KJV", chapter: 2, at: hours(1))
        XCTAssertEqual(log.count, 2)
    }

    // REQ-HI-3: a merged entry moves to the front.
    func testMergedEntryMovesToFront() {
        var log = record([], "KJV", chapter: 1, at: t0)
        log = record(log, "KJV", chapter: 2, at: hours(1))
        log = record(log, "KJV", chapter: 1, at: hours(2))
        XCTAssertEqual(log.map { $0.chapter }, [1, 2])
    }

    // A reload seconds later is not a new visit: no extra timestamp, but
    // the version still counts.
    func testQuickReloadAddsNoTimestamp() {
        var log = record([], "KJV", at: t0)
        log = record(log, "ChiUns", at: t0.addingTimeInterval(5))
        XCTAssertEqual(log[0].timestamps, [t0])
        XCTAssertEqual(log[0].moduleIDs, ["KJV", "ChiUns"])
    }

    // REQ-HI-2: the cap still applies to entries.
    func testCapKeepsNewestEntries() {
        var log: [ReadingHistoryEntry] = []
        for ch in 1...5 {
            log = ReadingHistoryLog.recording(
                moduleID: "KJV", bookName: "B", testament: 1, book: 1, chapter: ch,
                at: hours(Double(ch)), into: log, limit: 3)
        }
        XCTAssertEqual(log.map { $0.chapter }, [5, 4, 3])
    }

    // Entries written before combining existed (one moduleID + timestamp)
    // still decode.
    func testDecodesTheOlderOneVisitFormat() throws {
        let json = """
        {"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","moduleID":"KJV",
         "bookName":"Genesis","testament":1,"book":1,"chapter":1,
         "timestamp":782000000}
        """
        let entry = try JSONDecoder().decode(ReadingHistoryEntry.self,
                                             from: Data(json.utf8))
        XCTAssertEqual(entry.moduleIDs, ["KJV"])
        XCTAssertEqual(entry.timestamps,
                       [Date(timeIntervalSinceReferenceDate: 782_000_000)])
        XCTAssertEqual(entry.bookName, "Genesis")
    }

    func testEncodeDecodeRoundTripUsesTheNewFormat() throws {
        var log = record([], "KJV", at: t0)
        log = record(log, "ChiUns", at: hours(1))
        let data = try JSONEncoder().encode(log)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("moduleIDs"))
        XCTAssertFalse(text.contains("\"moduleID\""))
        XCTAssertFalse(text.contains("\"timestamp\""))
        XCTAssertEqual(try JSONDecoder().decode([ReadingHistoryEntry].self, from: data), log)
    }

    // REQ-HI-7: history recorded before combining existed is combined when
    // loaded: same chapter within 24 hours becomes one entry.
    func testCombinedMergesOlderSeparateEntries() {
        let a = ReadingHistoryEntry(bookName: "Genesis", testament: 1, book: 1, chapter: 1,
                                    moduleIDs: ["KJV"], timestamps: [t0])
        let b = ReadingHistoryEntry(bookName: "Genesis", testament: 1, book: 1, chapter: 1,
                                    moduleIDs: ["ChiUns"], timestamps: [hours(3)])
        let c = ReadingHistoryEntry(bookName: "Genesis", testament: 1, book: 1, chapter: 1,
                                    moduleIDs: ["KJV"], timestamps: [hours(40)])
        let other = ReadingHistoryEntry(bookName: "Exodus", testament: 1, book: 2, chapter: 1,
                                        moduleIDs: ["KJV"], timestamps: [hours(1)])
        // most recent first, as stored
        let combined = ReadingHistoryLog.combined([c, b, other, a])
        XCTAssertEqual(combined.count, 3)
        XCTAssertEqual(combined[0].timestamps, [hours(40)])
        let merged = combined.first { $0.chapter == 1 && $0.timestamps.count == 2 }
        XCTAssertEqual(merged?.timestamps, [t0, hours(3)])
        XCTAssertEqual(merged?.moduleIDs, ["KJV", "ChiUns"])
    }

    func testCombinedIsIdempotent() {
        var log = record([], "KJV", at: t0)
        log = record(log, "ChiUns", at: hours(2))
        log = record(log, "KJV", at: hours(30))
        log = record(log, "KJV", chapter: 2, at: hours(31))
        let once = ReadingHistoryLog.combined(log)
        XCTAssertEqual(once, log)
        XCTAssertEqual(ReadingHistoryLog.combined(once), once)
    }

    // REQ-HI-9: the list shows the last 20 entries, then "...".
    func testVisibleShowsTwentyAndSaysWhetherThereAreMore() {
        func entries(_ n: Int) -> [ReadingHistoryEntry] {
            (1...n).map {
                ReadingHistoryEntry(bookName: "B", testament: 1, book: 1, chapter: $0,
                                    moduleIDs: ["KJV"], timestamps: [hours(Double($0))])
            }
        }
        let many = ReadingHistoryLog.visible(entries(25))
        XCTAssertEqual(many.entries.count, 20)
        XCTAssertEqual(many.entries.first?.chapter, 1)   // log order is kept
        XCTAssertTrue(many.hasMore)
        let exactly = ReadingHistoryLog.visible(entries(20))
        XCTAssertEqual(exactly.entries.count, 20)
        XCTAssertFalse(exactly.hasMore)
        let few = ReadingHistoryLog.visible(entries(3))
        XCTAssertEqual(few.entries.count, 3)
        XCTAssertFalse(few.hasMore)
        XCTAssertFalse(ReadingHistoryLog.visible([]).hasMore)
    }
}

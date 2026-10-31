// VerseFormatting.swift
// Pure, testable logic for verse copy formatting and note key handling.
// Extracted from ReaderView/BookmarksPanel so requirements can be unit-tested.

import Foundation

/// Formats selected verses for the clipboard per REQ-CP-1..5.
/// - Single verse: `"text" Book C:V Version` (no number in text).
/// - Multiple: `"1 text 2 text" Book C:1-2 Version` (numbers in text).
public enum VerseFormatting {
    /// [1,2,3,5] -> "1-3, 5" (REQ-CP-5)
    public static func verseListString(_ verses: [Int]) -> String {
        guard !verses.isEmpty else { return "" }
        var parts: [String] = []
        var start = verses[0]
        var prev = verses[0]
        for v in verses.dropFirst() {
            if v == prev + 1 {
                prev = v
            } else {
                parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
                start = v
                prev = v
            }
        }
        parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
        return parts.joined(separator: ", ")
    }

    /// Builds the clipboard string. `verseTexts` maps verse number -> plain text.
    public static func copyString(
        selectedVerses: [Int],
        verseTexts: [Int: String],
        bookTitle: String,
        chapter: Int,
        version: String
    ) -> String? {
        let sorted = selectedVerses.sorted()
        guard !sorted.isEmpty else { return nil }
        let ref = "\(bookTitle) \(chapter):\(verseListString(sorted))"
        let single = sorted.count == 1
        let parts = sorted.compactMap { v -> String? in
            guard let text = verseTexts[v] else { return nil }
            return single ? text : "\(v) \(text)"
        }
        guard !parts.isEmpty else { return nil }
        let quoted = "\"\(parts.joined(separator: " "))\""
        return "\(quoted) \(ref) \(version)"
    }
}

/// Book location math shared by bookmarks and the reader (REQ-BM-8).
/// A book is addressed either as (testament 1|2, 1-based book within the
/// testament) or as a 0-based index across the whole 66-book Bible.
public enum BookLocation {
    public static let otBookCount = 39
    public static let ntBookCount = 27
    public static let bookCount = otBookCount + ntBookCount

    /// (1, 1) -> 0 ... (1, 39) -> 38, (2, 1) -> 39 ... (2, 27) -> 65.
    /// Nil when the location is outside the Bible.
    public static func overallIndex(testament: Int, book: Int) -> Int? {
        switch testament {
        case 1 where (1...otBookCount).contains(book): return book - 1
        case 2 where (1...ntBookCount).contains(book): return otBookCount + book - 1
        default: return nil
        }
    }

    /// Keeps `chapter` within 1...`chapterCount`. Nil when the book has no
    /// chapters (e.g. a partial private Bible that lacks the book), so the
    /// caller can fall back instead of opening a chapter that doesn't exist.
    public static func clampedChapter(_ chapter: Int, chapterCount: Int) -> Int? {
        guard chapterCount > 0 else { return nil }
        return min(max(chapter, 1), chapterCount)
    }

    /// The inverse of `overallIndex`; nil when `overall` isn't in 0...65.
    public static func testamentAndBook(overall: Int)
        -> (testament: Int, book: Int)?
    {
        guard (0..<bookCount).contains(overall) else { return nil }
        return overall < otBookCount
            ? (1, overall + 1)
            : (2, overall - otBookCount + 1)
    }
}

/// Which versions the Compare panel shows (REQ-CM-3..5).
public enum CompareVersions {
    /// The version ids to show, current version first. `configured` is the
    /// user's Compare setting: nil or empty -> only the current version;
    /// otherwise the configured versions union the current one. The rest
    /// follow `available`'s order (the library's), so the panel's order
    /// doesn't depend on the order versions were ticked. Configured ids
    /// that aren't in `available` (e.g. since deleted) are skipped and
    /// duplicates dropped.
    public static func ids(current: String, configured: [String]?,
                           available: [String]) -> [String] {
        let wanted = Set(configured ?? [])
        var out = [current]
        for id in available where wanted.contains(id) && !out.contains(id) {
            out.append(id)
        }
        return out
    }
}

/// Note storage key handling per REQ-NT-11.
/// Format: "{testament}:{book}:{chapter}:{verse}". Notes belong to the
/// verse, not to a version (REQ-NT-19): the key carries no module id,
/// so a note written in one version shows in every version.
public enum NoteKey {
    public static func make(testament: Int, book: Int,
                            chapter: Int, verse: Int) -> String {
        "\(testament):\(book):\(chapter):\(verse)"
    }

    public struct Parsed: Equatable {
        public let testament: Int
        public let book: Int
        public let chapter: Int
        public let verse: Int
    }

    public static func parse(_ key: String) -> Parsed? {
        let parts = key.split(separator: ":")
        guard parts.count == 4,
              let testament = Int(parts[0]),
              let book = Int(parts[1]),
              let chapter = Int(parts[2]),
              let verse = Int(parts[3]) else { return nil }
        return Parsed(testament: testament,
                      book: book, chapter: chapter, verse: verse)
    }
}

/// Book-level note storage keys (REQ-NT-14). Book notes live in their own
/// store, so the format only needs to be unique within it:
/// "{testament}:{book}". Like verse notes, book notes are shared across
/// versions (REQ-NT-19) and carry no module id.
public enum BookNoteKey {
    public static func make(testament: Int, book: Int) -> String {
        "\(testament):\(book)"
    }

    public struct Parsed: Equatable {
        public let testament: Int
        public let book: Int
    }

    public static func parse(_ key: String) -> Parsed? {
        let parts = key.split(separator: ":")
        guard parts.count == 2,
              let testament = Int(parts[0]),
              let book = Int(parts[1]) else { return nil }
        return Parsed(testament: testament, book: book)
    }
}

/// Chapter-level note storage keys (REQ-NT-14). Chapter notes live in
/// their own store: "{testament}:{book}:{chapter}". Shared across
/// versions like the other note scopes (REQ-NT-19).
public enum ChapterNoteKey {
    public static func make(testament: Int, book: Int,
                            chapter: Int) -> String {
        "\(testament):\(book):\(chapter)"
    }

    public struct Parsed: Equatable {
        public let testament: Int
        public let book: Int
        public let chapter: Int
    }

    public static func parse(_ key: String) -> Parsed? {
        let parts = key.split(separator: ":")
        guard parts.count == 3,
              let testament = Int(parts[0]),
              let book = Int(parts[1]),
              let chapter = Int(parts[2]) else { return nil }
        return Parsed(testament: testament,
                      book: book, chapter: chapter)
    }
}

/// Splitting legacy note keys (REQ-NT-19 migration). Before REQ-NT-19,
/// note keys were prefixed with the module id of the version the note
/// was written in: "{moduleID}:{testament}:...". A key is legacy when
/// its first component is not an integer (module ids are never purely
/// numeric; a version-less key starts with the testament, 1 or 2).
public enum NoteKeyMigration {
    /// Splits a legacy key into its module id and its version-less
    /// key. `newPartCount` is the component count of the version-less
    /// key in the caller's store (2 book, 3 chapter, 4 verse). Returns
    /// nil when the key is already version-less or malformed.
    public static func splitLegacy(_ key: String,
                                   newPartCount: Int)
        -> (moduleID: String, key: String)? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == newPartCount + 1,
              Int(parts[0]) == nil, !parts[0].isEmpty,
              parts.dropFirst().allSatisfy({ Int($0) != nil })
        else { return nil }
        return (String(parts[0]),
                parts.dropFirst().joined(separator: ":"))
    }
}

/// The auxiliary panel's swipe-down-to-collapse decision
/// (REQ-AP-18). The panel's tab contents scroll, so a plain
/// downward drag must not collapse it: the gesture has to be a
/// committed swipe — at least `minimumTranslation` points of
/// downward travel and a predicted end well past the actual
/// travel, which is what sets a flick apart from a scroll drag
/// that merely ends while moving downward.
public enum PanelCollapseGesture {
    /// Downward travel (points) a swipe needs before it can
    /// collapse the panel.
    public static let minimumTranslation: CGFloat = 50
    /// Predicted end translation (points) a swipe needs; a flick's
    /// predicted end runs far ahead of its actual travel.
    public static let minimumPredictedEnd: CGFloat = 110

    public static func shouldCollapse(translation: CGFloat,
                                      predictedEnd: CGFloat) -> Bool {
        translation >= minimumTranslation
            && predictedEnd >= minimumPredictedEnd
    }
}

/// Grouping of one chapter's commentary entries (REQ-AP-5). A commentary
/// stores a single entry covering a run of verses by repeating the same
/// text at every verse it covers (verified against MHCC: the entry for
/// Genesis 1:1-2 is stored identically at verses 1 and 2). Collapsing
/// consecutive verses with identical text recovers those ranges.
public enum CommentaryGrouping {
    public struct Entry: Equatable {
        public let startVerse: Int
        public let endVerse: Int
        public let text: String
        public init(startVerse: Int, endVerse: Int, text: String) {
            self.startVerse = startVerse
            self.endVerse = endVerse
            self.text = text
        }
    }

    /// Collapses (verse, text) pairs — in verse order — into ranges.
    /// Empty texts are skipped and break a run; the same text appearing
    /// again later (not consecutively) starts a new entry.
    public static func group(_ verses: [(verse: Int, text: String)]) -> [Entry] {
        var out = [Entry]()
        for v in verses where !v.text.isEmpty {
            if var last = out.last, last.text == v.text,
               last.endVerse == v.verse - 1 {
                last = Entry(startVerse: last.startVerse, endVerse: v.verse,
                             text: last.text)
                out[out.count - 1] = last
            } else {
                out.append(Entry(startVerse: v.verse, endVerse: v.verse,
                                 text: v.text))
            }
        }
        return out
    }

    /// The grouped entry covering `verse`, or nil when the commentary
    /// has no entry for it.
    public static func entry(in entries: [Entry], covering verse: Int) -> Entry? {
        entries.first { $0.startVerse <= verse && verse <= $0.endVerse }
    }
}

/// Which version supplies the Strong's rendering of the selected verse
/// in the auxiliary panel (REQ-AP-7). The version being read wins when it
/// carries Strong's numbers; otherwise the user's fallback setting;
/// otherwise the first installed Strong's version (in library order).
public enum StrongsVerseSource {
    public static func resolve(currentID: String, currentSupportsStrongs: Bool,
                               fallbackID: String?,
                               strongsVersionIDs: [String]) -> String? {
        if currentSupportsStrongs { return currentID }
        if let fallbackID, strongsVersionIDs.contains(fallbackID) {
            return fallbackID
        }
        return strongsVersionIDs.first
    }
}

/// Note anchoring per REQ-NT-1..3.
/// - Selected verses -> anchor at the lowest selected verse.
/// - No selection -> chapter note anchored at verse 1.
public enum NoteAnchoring {
    public static func anchorVerse(selectedVerses: Set<Int>) -> Int {
        selectedVerses.min() ?? 1
    }
}

/// Bookmark ribbon palette per REQ-BM-2.
/// Colors cycle in order: sky blue, gold, purple, silver, green.
public enum BookmarkPalette {
    public static let colors: [(red: Double, green: Double, blue: Double)] = [
        (0.53, 0.81, 0.98), // light sky blue
        (1.00, 0.84, 0.40), // light gold
        (0.79, 0.66, 0.91), // light purple
        (0.83, 0.83, 0.83), // light silver
        (0.56, 0.93, 0.56), // light green
    ]

    /// Color for the bookmark created at `count` existing bookmarks (0-based).
    public static func color(forCount count: Int) -> (red: Double, green: Double, blue: Double) {
        colors[count % colors.count]
    }
}

/// Reading history log behavior per REQ-HI-2/3: dedupe-to-front, cap at `limit`.
public enum HistoryLogLogic {
    public static let limit = 100

    /// Insert `entry` at the front, removing any existing duplicate,
    /// then truncate to the cap. Entries must be Equatable to dedupe.
    public static func insert<T: Equatable>(_ entry: T, into log: [T], limit: Int = limit) -> [T] {
        var out = log.filter { $0 != entry }
        out.insert(entry, at: 0)
        if out.count > limit { out = Array(out.prefix(limit)) }
        return out
    }
}


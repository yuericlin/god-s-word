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
/// Format: "{moduleID}:{testament}:{book}:{chapter}:{verse}"
public enum NoteKey {
    public static func make(moduleID: String, testament: Int, book: Int,
                            chapter: Int, verse: Int) -> String {
        "\(moduleID):\(testament):\(book):\(chapter):\(verse)"
    }

    public struct Parsed: Equatable {
        public let moduleID: String
        public let testament: Int
        public let book: Int
        public let chapter: Int
        public let verse: Int
    }

    public static func parse(_ key: String) -> Parsed? {
        let parts = key.split(separator: ":")
        guard parts.count == 5,
              let testament = Int(parts[1]),
              let book = Int(parts[2]),
              let chapter = Int(parts[3]),
              let verse = Int(parts[4]) else { return nil }
        return Parsed(moduleID: String(parts[0]), testament: testament,
                      book: book, chapter: chapter, verse: verse)
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


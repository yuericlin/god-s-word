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

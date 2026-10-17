// Versification.swift
// Verse-index math mirroring SWORD's VersificationMgr::System
// (loadFromSBook / getOffsetFromVerse / VerseKey::getTestamentIndex).

import Foundation

public struct BibleBook: Sendable {
    public let name: String      // English name, e.g. "Genesis"
    public let osis: String      // OSIS id, e.g. "Gen"
    public let chapters: Int
    public init(name: String, osis: String, chapters: Int) {
        self.name = name; self.osis = osis; self.chapters = chapters
    }
}

/// A versification system: ordered books plus per-chapter verse counts.
/// testament: 1 = Old Testament, 2 = New Testament.
/// book: 1-based within the testament. chapter/verse: 1-based.
public struct Versification: Sendable {
    public let name: String
    public let books: [BibleBook]          // 66, canonical order
    public let versesPerChapter: [[Int]]    // [book][chapter] -> verse count

    public static let otBookCount = 39

    /// Absolute offset of a chapter heading, mirroring loadFromSBook.
    private func chapterHeadingOffset(testament: Int, book: Int, chapter: Int) -> Int? {
        guard testament == 1 || testament == 2 else { return nil }
        let overall = testament == 1 ? book - 1 : Self.otBookCount + book - 1
        guard overall >= 0 && overall < books.count else { return nil }
        guard chapter >= 1 && chapter <= books[overall].chapters else { return nil }
        var offset = 0       // module heading
        offset += 1          // OT testament heading
        for b in 0 ..< Self.otBookCount {
            offset += 1      // book heading
            for c in 0 ..< books[b].chapters {
                offset += 1  // chapter heading
                if testament == 1 && b == overall && c == chapter - 1 { return offset }
                offset += versesPerChapter[b][c]
            }
        }
        let ntStart = offset
        offset += 1          // NT testament heading
        for b in Self.otBookCount ..< books.count {
            offset += 1
            for c in 0 ..< books[b].chapters {
                offset += 1
                if testament == 2 && b == overall && c == chapter - 1 { return offset - ntStart }
                offset += versesPerChapter[b][c]
            }
        }
        return nil
    }

    /// Index of a verse within its testament's .bzv file, mirroring
    /// VerseKey::getTestamentIndex() with intros disabled.
    public func testamentIndex(testament: Int, book: Int, chapter: Int, verse: Int) -> Int? {
        guard let heading = chapterHeadingOffset(testament: testament, book: book, chapter: chapter)
        else { return nil }
        let overall = testament == 1 ? book - 1 : Self.otBookCount + book - 1
        guard verse >= 1 && verse <= versesPerChapter[overall][chapter - 1] else { return nil }
        return heading + verse
    }

    public func verseCount(testament: Int, book: Int, chapter: Int) -> Int? {
        let overall = testament == 1 ? book - 1 : Self.otBookCount + book - 1
        guard overall >= 0 && overall < books.count else { return nil }
        guard chapter >= 1 && chapter <= books[overall].chapters else { return nil }
        return versesPerChapter[overall][chapter - 1]
    }

    public func book(testament: Int, book: Int) -> BibleBook? {
        let overall = testament == 1 ? book - 1 : Self.otBookCount + book - 1
        guard overall >= 0 && overall < books.count else { return nil }
        return books[overall]
    }
}

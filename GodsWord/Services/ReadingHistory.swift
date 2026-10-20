// ReadingHistory.swift — shared, observable record of the current reading
// selection (version/book/chapter). The version picker, book picker, chapter
// picker, and the reader all read from and write to this one object, so
// stepping back through the pickers always reflects the current selection.

import SwiftUI
import SwordReader

@Observable
final class ReadingHistory {
    var version: BibleVersion
    var testament: Int  // 1 = Old Testament, 2 = New Testament
    var book: Int       // 1-based within the testament
    var chapter: Int    // 1-based

    /// When true (set by a bookmark jump), the reader does not record a
    /// history entry on load. Instead it starts a 60-second dwell timer:
    /// the entry is recorded only if the user is still on the chapter when
    /// it fires — quick flips through chapters leave no trace. Cleared once
    /// a dwell completes.
    var dwellMode = false

    init(version: BibleVersion, testament: Int = 1, book: Int = 1, chapter: Int = 1) {
        self.version = version
        self.testament = testament
        self.book = book
        self.chapter = chapter
    }

    /// Convenience for callers that hold a downloaded SWORD module.
    convenience init(module: InstalledModule, testament: Int = 1, book: Int = 1, chapter: Int = 1) {
        self.init(version: .sword(module), testament: testament, book: book, chapter: chapter)
    }

    /// 0-based index across the whole Bible (0–65).
    var overallBookIndex: Int {
        testament == 1 ? book - 1 : 39 + book - 1
    }

    func bookName(overall: Int) -> String {
        version.bookName(overall: overall)
    }

    var bookTitle: String {
        bookName(overall: overallBookIndex)
    }

    var chapterCount: Int {
        chapterCount(testament: testament, book: book)
    }

    func chapterCount(testament: Int, book: Int) -> Int {
        version.chapterCount(testament: testament, book: book)
    }

    /// Select a book by its 0-based overall index; jumps to its chapter 1.
    func setBook(overall: Int) {
        if overall < 39 {
            testament = 1
            book = overall + 1
        } else {
            testament = 2
            book = overall - 39 + 1
        }
        chapter = 1
    }
}

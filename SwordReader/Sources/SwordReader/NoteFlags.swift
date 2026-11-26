// NoteFlags.swift
// Which notes cover a verse, for the flag hint after the verse
// number (REQ-NT-5): one flag per covering note.

import Foundation

/// A note covering a verse. The reader shows one blue flag per
/// covering note after the verse number, broadest scope first.
/// A verse flag carries its note's key: a verse can carry
/// several verse notes, one per scope (REQ-NT-22).
public enum NoteFlag: Equatable, Sendable {
    case book
    case chapter
    case verse(key: String)
}

public enum NoteFlagLogic {
    /// The flags for a verse, in display order (book, chapter,
    /// verse notes): the book note counts only at the book's
    /// first verse (chapter 1, verse 1), the chapter note only
    /// at its chapter's first verse, and each verse note at its
    /// anchor verse. Verse notes are ordered narrowest scope
    /// first.
    public static func flags(isBookStart: Bool, isChapterStart: Bool,
                             hasBookNote: Bool, hasChapterNote: Bool,
                             verseNoteKeys: [String]) -> [NoteFlag] {
        var out: [NoteFlag] = []
        if isBookStart, hasBookNote { out.append(.book) }
        if isChapterStart, hasChapterNote { out.append(.chapter) }
        let sorted = verseNoteKeys.sorted {
            let a = NoteKey.parse($0)?.scope ?? []
            let b = NoteKey.parse($1)?.scope ?? []
            return a.lexicographicallyPrecedes(b)
        }
        out += sorted.map { .verse(key: $0) }
        return out
    }
}

// NoteFlags.swift
// Which notes cover a verse, for the flag hint after the verse
// number (REQ-NT-5): one flag per covering note.

import Foundation

/// A note covering a verse. The reader shows one blue flag per
/// covering note after the verse number, broadest scope first.
public enum NoteFlag: Equatable, Sendable {
    case book
    case chapter
    case verse
}

public enum NoteFlagLogic {
    /// The flags for a verse, in display order (book, chapter,
    /// verse): the book note counts only at the book's first
    /// verse (chapter 1, verse 1), the chapter note only at its
    /// chapter's first verse, and the verse note at its own
    /// verse.
    public static func flags(isBookStart: Bool, isChapterStart: Bool,
                             hasBookNote: Bool, hasChapterNote: Bool,
                             hasVerseNote: Bool) -> [NoteFlag] {
        var out: [NoteFlag] = []
        if isBookStart, hasBookNote { out.append(.book) }
        if isChapterStart, hasChapterNote { out.append(.chapter) }
        if hasVerseNote { out.append(.verse) }
        return out
    }
}

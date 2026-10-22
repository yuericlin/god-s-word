// NotesTabs.swift
// Sub-tab model for the auxiliary panel's Notes tab (REQ-NT-18):
// which sub-tabs exist for the current state, and which one shows
// when the selected sub-tab has no notes. Pure logic, unit-tested
// here; the panel computes the availability from PersonalData.

import Foundation

/// The Notes tab's sub-tabs, in bar order. Raw values define the
/// bar positions used by the nearest-visible fallback.
public enum NotesSubTab: Int, CaseIterable, Sendable {
    case recents = 0
    case book
    case chapter
    case verse

    /// Segment label in the sub-tab bar.
    public var label: String {
        switch self {
        case .recents: return "Recents"
        case .book: return "Book"
        case .chapter: return "Chapter"
        case .verse: return "Verse"
        }
    }
}

public enum NotesTabLogic {
    /// Whether each sub-tab has at least one note to show.
    public struct Availability: Equatable, Sendable {
        public var recents: Bool
        public var book: Bool
        public var chapter: Bool
        public var verse: Bool

        public init(recents: Bool, book: Bool, chapter: Bool, verse: Bool) {
            self.recents = recents
            self.book = book
            self.chapter = chapter
            self.verse = verse
        }

        public func hasNotes(for tab: NotesSubTab) -> Bool {
            switch tab {
            case .recents: return recents
            case .book: return book
            case .chapter: return chapter
            case .verse: return verse
            }
        }
    }

    /// The sub-tabs to put in the bar, in bar order: exactly those
    /// with notes. Empty when there are no notes at all (the panel
    /// then hides the bar and shows its empty state).
    public static func visibleTabs(_ availability: Availability) -> [NotesSubTab] {
        NotesSubTab.allCases.filter { availability.hasNotes(for: $0) }
    }

    /// The sub-tab to display: the selection when it is visible,
    /// otherwise the nearest visible sub-tab by bar position (ties
    /// go to the earlier sub-tab). Nil when no sub-tab is visible.
    public static func resolved(selected: NotesSubTab,
                                availability: Availability) -> NotesSubTab? {
        let visible = visibleTabs(availability)
        if visible.contains(selected) { return selected }
        return visible.min { a, b in
            let da = abs(a.rawValue - selected.rawValue)
            let db = abs(b.rawValue - selected.rawValue)
            return da != db ? da < db : a.rawValue < b.rawValue
        }
    }
}

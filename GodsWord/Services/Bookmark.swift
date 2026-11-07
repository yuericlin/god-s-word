// Bookmark.swift — named, colored ribbon bookmarks.
// Each bookmark points at a testament/book/chapter (1-based) and
// optionally at a verse within the chapter (REQ-BM-12): no verse
// means the bookmark marks the chapter as a whole.
// Persisted in PersonalData (UserDefaults) and included in Drive backups.

import Foundation
import SwiftUI
import SwordReader

public struct Bookmark: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Ribbon color as 0...1 RGB components (Codable-friendly).
    public var red: Double
    public var green: Double
    public var blue: Double
    public var testament: Int  // 1 = OT, 2 = NT
    public var book: Int       // 1-based within testament
    public var chapter: Int
    /// The marked verse (1-based), or nil for a chapter-level
    /// bookmark (REQ-BM-12). Optional in the payload, so bookmarks
    /// stored before verse-level bookmarks existed decode as
    /// chapter-level.
    public var verse: Int?
    /// When the bookmark was created and last changed (REQ-BM-10),
    /// stamped by PersonalData on save/assign. Nil in bookmarks
    /// written before timestamps existed.
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID = UUID(), name: String,
                red: Double, green: Double, blue: Double,
                testament: Int = 1, book: Int = 1, chapter: Int = 1,
                verse: Int? = nil,
                createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.testament = testament
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The time shown as the bookmark's last update: the last change,
    /// falling back to creation; nil when it predates timestamps.
    public var lastUpdated: Date? { updatedAt ?? createdAt }

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// 0-based index across the whole Bible; nil for an invalid location.
    var overallBookIndex: Int? {
        BookLocation.overallIndex(testament: testament, book: book)
    }

    /// Whether the bookmark points at this chapter (any verse,
    /// or none).
    func isAt(testament: Int, book: Int, chapter: Int) -> Bool {
        self.testament == testament && self.book == book && self.chapter == chapter
    }

    /// Whether the bookmark points at exactly this target: the
    /// chapter, and exactly this verse — where a nil verse
    /// matches chapter-level bookmarks only (REQ-BM-12).
    func isAt(testament: Int, book: Int, chapter: Int, verse: Int?) -> Bool {
        isAt(testament: testament, book: book, chapter: chapter)
            && self.verse == verse
    }

    /// A copy pointing at another location (name, color, and id
    /// unchanged). Without a verse the copy is chapter-level:
    /// assigning a bookmark to a chapter clears its verse.
    func moved(testament: Int, book: Int, chapter: Int,
               verse: Int? = nil) -> Bookmark {
        var copy = self
        copy.testament = testament
        copy.book = book
        copy.chapter = chapter
        copy.verse = verse
        return copy
    }

    /// Default ribbon colors, in order, for newly created bookmarks:
    /// 1. light sky blue, 2. light gold, 3. light purple,
    /// 4. light silver, 5. light green. Cycles for the 6th and beyond.
    public static let defaultPalette: [(red: Double, green: Double, blue: Double)] = [
        (0.53, 0.81, 0.98),  // light sky blue (#87CEFA)
        (1.00, 0.84, 0.40),  // light gold
        (0.79, 0.66, 0.91),  // light purple
        (0.83, 0.83, 0.83),  // light silver
        (0.56, 0.93, 0.56),  // light green
    ]

    public static func paletteColor(at index: Int) -> (red: Double, green: Double, blue: Double) {
        defaultPalette[index % defaultPalette.count]
    }
}

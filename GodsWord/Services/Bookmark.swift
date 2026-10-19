// Bookmark.swift — named, colored ribbon bookmarks.
// Each bookmark points at a testament/book/chapter (1-based).
// Persisted in PersonalData (UserDefaults) and included in Drive backups.

import Foundation
import SwiftUI

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

    public init(id: UUID = UUID(), name: String,
                red: Double, green: Double, blue: Double,
                testament: Int = 1, book: Int = 1, chapter: Int = 1) {
        self.id = id
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.testament = testament
        self.book = book
        self.chapter = chapter
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// The bookmarks a fresh install starts with: all at Genesis 1,
    /// ready for the user to name and mark.
    public static var defaults: [Bookmark] {
        [
            Bookmark(name: "Bookmark 1", red: 0.90, green: 0.25, blue: 0.25),
            Bookmark(name: "Bookmark 2", red: 0.95, green: 0.75, blue: 0.15),
            Bookmark(name: "Bookmark 3", red: 0.25, green: 0.45, blue: 0.95),
        ]
    }
}

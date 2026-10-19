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

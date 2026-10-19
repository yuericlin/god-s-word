// BookmarksView.swift — ribbon bookmarks on the reader.
// Translucent ribbons hang from the top-right corner: one per bookmark.
// Single tap jumps to the bookmark; holding one for 3 seconds offers
// "Mark" (assign the current chapter to it) and "Edit" (name, color,
// book & chapter).

import SwiftUI
import UIKit
import SwordReader

/// A hanging ribbon: rectangle with a V notch cut out of the bottom.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notchDepth: CGFloat = 12
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notchDepth))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The row of ribbons pinned to the reader's top-right corner.
struct BookmarksRibbonsView: View {
    let history: ReadingHistory
    @EnvironmentObject private var personalData: PersonalData
    @State private var pendingBookmark: Bookmark?
    @State private var showingOptions = false
    @State private var editingBookmark: Bookmark?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(personalData.bookmarks) { bookmark in
                ribbon(for: bookmark)
            }
            // Add a bookmark at the current chapter. The ribbon color
            // follows the default palette in creation order.
            Button {
                let created = personalData.addBookmark(
                    name: "Bookmark \(personalData.bookmarks.count + 1)",
                    testament: history.testament,
                    book: history.book,
                    chapter: history.chapter)
                editingBookmark = created
            } label: {
                Image(systemName: "plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(.top, 2)
        }
        .padding(.trailing, 10)
        .confirmationDialog(
            pendingBookmark.map { "\($0.name) — \(reference(for: $0))" } ?? "Bookmark",
            isPresented: $showingOptions,
            titleVisibility: .visible
        ) {
            Button("Mark") {
                // Assign the current chapter to the held bookmark.
                if var b = pendingBookmark {
                    b.testament = history.testament
                    b.book = history.book
                    b.chapter = history.chapter
                    personalData.updateBookmark(b)
                }
            }
            Button("Edit") {
                editingBookmark = pendingBookmark
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark assigns the chapter you are reading to this bookmark. Edit changes its name, color, book and chapter.")
        }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditView(bookmark: bookmark, history: history)
        }
    }

    private func ribbon(for bookmark: Bookmark) -> some View {
        RibbonShape()
            .fill(bookmark.color.opacity(0.55))
            .frame(width: 40, height: 76)
            .contentShape(RibbonShape())
            .onTapGesture { jump(to: bookmark) }
            .onLongPressGesture(minimumDuration: 3.0) {
                pendingBookmark = bookmark
                showingOptions = true
            }
    }

    private func jump(to bookmark: Bookmark) {
        history.testament = bookmark.testament
        history.book = bookmark.book
        let count = max(history.chapterCount(testament: bookmark.testament,
                                             book: bookmark.book), 1)
        history.chapter = min(max(bookmark.chapter, 1), count)
    }

    private func reference(for bookmark: Bookmark) -> String {
        let overall = bookmark.testament == 1
            ? bookmark.book - 1 : 39 + bookmark.book - 1
        guard overall >= 0 && overall < 66 else { return "" }
        return "\(history.bookName(overall: overall)) \(bookmark.chapter)"
    }
}

/// Edits a bookmark's name, ribbon color, and book/chapter.
struct BookmarkEditView: View {
    let bookmark: Bookmark
    let history: ReadingHistory
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: Color
    @State private var overallBook: Int
    @State private var chapter: Int

    init(bookmark: Bookmark, history: ReadingHistory) {
        self.bookmark = bookmark
        self.history = history
        _name = State(initialValue: bookmark.name)
        _color = State(initialValue: bookmark.color)
        let overall = bookmark.testament == 1
            ? bookmark.book - 1 : 39 + bookmark.book - 1
        _overallBook = State(initialValue: min(max(overall, 0), 65))
        _chapter = State(initialValue: max(bookmark.chapter, 1))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bookmark") {
                    TextField("Name", text: $name)
                    ColorPicker("Ribbon color", selection: $color)
                }
                Section("Location") {
                    Picker("Book", selection: $overallBook) {
                        ForEach(0..<66, id: \.self) { i in
                            Text(history.bookName(overall: i)).tag(i)
                        }
                    }
                    Picker("Chapter", selection: $chapter) {
                        ForEach(1...chapterCount, id: \.self) { c in
                            Text("\(c)").tag(c)
                        }
                    }
                    .onChange(of: overallBook) {
                        chapter = min(chapter, chapterCount)
                    }
                }
            }
            .navigationTitle("Edit Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private var chapterCount: Int {
        let t = overallBook < 39 ? 1 : 2
        let b = overallBook < 39 ? overallBook + 1 : overallBook - 39 + 1
        return max(history.chapterCount(testament: t, book: b), 1)
    }

    private func save() {
        let t = overallBook < 39 ? 1 : 2
        let b = overallBook < 39 ? overallBook + 1 : overallBook - 39 + 1
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, &g, &bl, &a)
        var updated = bookmark
        updated.name = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? bookmark.name : name.trimmingCharacters(in: .whitespaces)
        updated.red = Double(r)
        updated.green = Double(g)
        updated.blue = Double(bl)
        updated.testament = t
        updated.book = b
        updated.chapter = min(max(chapter, 1), chapterCount)
        personalData.updateBookmark(updated)
    }
}

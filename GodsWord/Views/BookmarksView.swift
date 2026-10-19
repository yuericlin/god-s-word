// BookmarksView.swift — ribbon bookmarks panel on the reader.
// A right-edge swipe at the reader slides this panel in from the right.
// Small translucent ribbons sit at the panel's top-right corner, one per
// bookmark. Single tap jumps to the bookmark; holding one for 3 seconds
// offers "Mark" (assign the current chapter to it) and "Edit" (name,
// color, book & chapter). The reading view itself stays clean.

import SwiftUI
import UIKit
import SwordReader

/// A hanging ribbon: rectangle with a V notch cut out of the bottom.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notchDepth: CGFloat = 10
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

/// A row of bookmark ribbons: single tap jumps, holding 3 seconds offers
/// Mark (assign the current chapter) and Edit (name, color, book & chapter).
struct BookmarkRibbonsRow: View {
    let history: ReadingHistory
    let bookmarks: [Bookmark]
    var ribbonWidth: CGFloat = 30
    var ribbonHeight: CGFloat = 54
    var onJump: (Bookmark) -> Void

    @EnvironmentObject private var personalData: PersonalData
    @State private var pendingBookmark: Bookmark?
    @State private var showingOptions = false
    @State private var editingBookmark: Bookmark?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(bookmarks) { bookmark in
                RibbonShape()
                    .fill(bookmark.color.opacity(0.55))
                    .frame(width: ribbonWidth, height: ribbonHeight)
                    .contentShape(RibbonShape())
                    .onTapGesture { onJump(bookmark) }
                    .onLongPressGesture(minimumDuration: 1.0) {
                        pendingBookmark = bookmark
                        showingOptions = true
                    }
            }
        }
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
            Button("Delete", role: .destructive) {
                if let b = pendingBookmark {
                    personalData.deleteBookmark(b)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark assigns the chapter you are reading to this bookmark. Edit changes its name, color, book and chapter.")
        }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditView(bookmark: bookmark, history: history)
        }
    }

    private func reference(for bookmark: Bookmark) -> String {
        let overall = bookmark.testament == 1
            ? bookmark.book - 1 : 39 + bookmark.book - 1
        guard overall >= 0 && overall < 66 else { return "" }
        return "\(history.bookName(overall: overall)) \(bookmark.chapter)"
    }
}

/// Slide-in bookmarks panel, opened with a right-edge swipe on the reader.
struct BookmarksPanel: View {
    let history: ReadingHistory
    @Binding var showing: Bool
    @EnvironmentObject private var personalData: PersonalData
    @State private var editingBookmark: Bookmark?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bookmarks").font(.headline)
                Spacer()
                Button { showing = false } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            // Small ribbons at the top-right corner, one per bookmark.
            BookmarkRibbonsRow(
                history: history,
                bookmarks: personalData.bookmarks,
                onJump: { jump(to: $0) }
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)

            if personalData.bookmarks.isEmpty {
                Text("No bookmarks yet.")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Spacer()

            Button("Add Bookmark") { addBookmark() }
                .frame(maxWidth: .infinity)
                .padding()
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 40 { showing = false }
                }
        )
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditView(bookmark: bookmark, history: history)
        }
    }

    private func addBookmark() {
        let created = personalData.addBookmark(
            name: "Bookmark \(personalData.bookmarks.count + 1)",
            testament: history.testament,
            book: history.book,
            chapter: history.chapter)
        editingBookmark = created
    }

    private func jump(to bookmark: Bookmark) {
        history.testament = bookmark.testament
        history.book = bookmark.book
        let count = max(history.chapterCount(testament: bookmark.testament,
                                             book: bookmark.book), 1)
        history.chapter = min(max(bookmark.chapter, 1), count)
        showing = false
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
        uiColor.getRed(&r, green: &g, blue: &bl, alpha: &a)
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

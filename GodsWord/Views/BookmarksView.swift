// BookmarksView.swift — ribbon bookmarks panel on the reader.
// A right-edge swipe at the reader slides this panel in from the right.
// Small translucent ribbons sit at the panel's top-right corner, one per
// bookmark. Single tap jumps to the bookmark; holding one for 3 seconds
// offers "Assign" (point it at the current chapter) and "Edit" (name,
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

/// A ribbon laid horizontally: rectangle with a V notch cut out of the right end.
struct HorizontalRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notchDepth: CGFloat = 12
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - notchDepth, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A row of bookmark ribbons: single tap jumps, holding 1 second offers
/// Assign, Edit and Delete. Two styles: mini (small vertical ribbons, color
/// only, for the reading view) and labeled (horizontal ribbons showing
/// name plus book and chapter, for the bookmarks panel).
struct BookmarkRibbonsRow: View {
    enum Style { case mini, labeled }

    let history: ReadingHistory
    let bookmarks: [Bookmark]
    var style: Style = .mini
    var onJump: (Bookmark) -> Void

    @EnvironmentObject private var personalData: PersonalData
    @State private var pendingBookmark: Bookmark?
    @State private var showingOptions = false
    @State private var editingBookmark: Bookmark?

    var body: some View {
        Group {
            switch style {
            case .mini:
                HStack(alignment: .top, spacing: 6) {
                    ForEach(bookmarks) { bookmark in
                        miniRibbon(for: bookmark)
                    }
                }
            case .labeled:
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(bookmarks) { bookmark in
                        labeledRibbon(for: bookmark)
                    }
                }
            }
        }
        .confirmationDialog(
            pendingBookmark.map { "\($0.name) — \(reference(for: $0))" } ?? "Bookmark",
            isPresented: $showingOptions,
            titleVisibility: .visible
        ) {
            Button("Assign") {
                // Assign the current chapter to the held bookmark.
                if let b = pendingBookmark {
                    personalData.assignBookmark(b, testament: history.testament,
                                                book: history.book,
                                                chapter: history.chapter)
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
            Text("Assign points this bookmark at the chapter you are reading. Edit changes its name, color, book and chapter.")
        }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditView(bookmark: bookmark, history: history)
        }
    }

    /// Small vertical ribbon, color only — 80% of the original
    /// 24×44 (Nov 7, 2026).
    private func miniRibbon(for bookmark: Bookmark) -> some View {
        RibbonShape()
            .fill(bookmark.color.opacity(0.55))
            .frame(width: 19.2, height: 35.2)
            .contentShape(RibbonShape())
            .onTapGesture { onJump(bookmark) }
            .onLongPressGesture(minimumDuration: 1.0) {
                pendingBookmark = bookmark
                showingOptions = true
            }
    }

    /// Horizontal ribbon showing the bookmark's name plus book and chapter.
    private func labeledRibbon(for bookmark: Bookmark) -> some View {
        HorizontalRibbonShape()
            .fill(bookmark.color.opacity(0.55))
            .frame(height: 52)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(reference(for: bookmark))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // Book and chapter stay on one line, shrinking a
                        // little for long names ("Song of Solomon 8").
                        .minimumScaleFactor(0.75)
                }
                .padding(.leading, 16)
                .padding(.trailing, 20)
            }
            .contentShape(HorizontalRibbonShape())
            .onTapGesture { onJump(bookmark) }
            .onLongPressGesture(minimumDuration: 1.0) {
                pendingBookmark = bookmark
                showingOptions = true
            }
    }

    private func reference(for bookmark: Bookmark) -> String {
        guard let overall = bookmark.overallBookIndex,
              let name = history.version.bookNameIfPresent(overall: overall)
        else {
            return ""
        }
        var text = "\(name) \(bookmark.chapter)"
        if let verse = bookmark.verse { text += ":\(verse)" }
        // Last-change date on the same line, without an "Updated"
        // label (REQ-BM-10): "Genesis 12 - Oct 22, 2026". Bookmarks
        // written before timestamps show no date part.
        if let updated = bookmark.lastUpdated {
            text += " - \(updated.formatted(date: .abbreviated, time: .omitted))"
        }
        return text
    }
}

/// Slide-in bookmarks panel, opened with a right-edge swipe on the reader.
/// Bookmarks only — notes live in the auxiliary panel below the reader
/// (its Notes tab, including the Recents sub-tab, REQ-AP-11).
struct BookmarksPanel: View {
    let history: ReadingHistory
    @Binding var showing: Bool
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store

    /// Single sheet for the panel (SwiftUI doesn't reliably handle two .sheet modifiers).
    private enum PanelSheet: Identifiable {
        case bookmark(Bookmark)
        var id: String {
            switch self {
            case .bookmark(let b): return "bookmark-\(b.id.uuidString)"
            }
        }
    }
    @State private var activeSheet: PanelSheet?

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

            // Horizontal ribbons, one per bookmark, showing name plus book and chapter.
            BookmarkRibbonsRow(
                history: history,
                bookmarks: personalData.bookmarks,
                style: .labeled,
                onJump: { jump(to: $0) }
            )
            .padding(.horizontal)

            if personalData.bookmarks.isEmpty {
                Text("No bookmarks yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            Spacer()

            HStack {
                Button("Add Bookmark") { addBookmark() }
                Spacer()
            }
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .bookmark(let bookmark):
                BookmarkEditView(bookmark: bookmark, history: history)
            }
        }
    }

    /// Opens the editor on a new, unsaved bookmark at the current chapter.
    /// It is stored only when the user taps Save.
    private func addBookmark() {
        let draft = personalData.makeBookmarkDraft(
            name: "Bookmark \(personalData.bookmarks.count + 1)",
            testament: history.testament,
            book: history.book,
            chapter: history.chapter)
        activeSheet = .bookmark(draft)
    }

    private func jump(to bookmark: Bookmark) {
        history.dwellMode = true
        history.testament = bookmark.testament
        history.book = bookmark.book
        let count = max(history.chapterCount(testament: bookmark.testament,
                                             book: bookmark.book), 1)
        history.chapter = min(max(bookmark.chapter, 1), count)
        // A verse-level bookmark also lands on its verse — the
        // reader selects and scrolls to it like a note jump
        // (REQ-BM-5). A chapter-level jump clears any stale
        // pending verse.
        history.pendingVerse = bookmark.verse
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
    /// 0 = chapter-level (no verse); 1... = the marked verse
    /// (REQ-BM-12).
    @State private var verse: Int

    init(bookmark: Bookmark, history: ReadingHistory) {
        self.bookmark = bookmark
        self.history = history
        _name = State(initialValue: bookmark.name)
        _color = State(initialValue: bookmark.color)
        let overall = bookmark.testament == 1
            ? bookmark.book - 1 : 39 + bookmark.book - 1
        _overallBook = State(initialValue: min(max(overall, 0), 65))
        _chapter = State(initialValue: max(bookmark.chapter, 1))
        _verse = State(initialValue: bookmark.verse ?? 0)
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
                    Picker("Verse", selection: $verse) {
                        Text("Chapter only").tag(0)
                        ForEach(1...verseCount, id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    }
                    .onChange(of: chapter) {
                        verse = min(verse, verseCount)
                    }
                }
            }
            .navigationTitle(isNew ? "New Bookmark" : "Edit Bookmark")
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

    /// True while the bookmark is an unsaved draft (Cancel discards it).
    private var isNew: Bool {
        !personalData.bookmarks.contains { $0.id == bookmark.id }
    }

    private var chapterCount: Int {
        let t = overallBook < 39 ? 1 : 2
        let b = overallBook < 39 ? overallBook + 1 : overallBook - 39 + 1
        return max(history.chapterCount(testament: t, book: b), 1)
    }

    /// Verses in the chosen book/chapter (KJV versification,
    /// the app's canonical numbering).
    private var verseCount: Int {
        let counts = Versification.kjv.versesPerChapter
        guard counts.indices.contains(overallBook),
              counts[overallBook].indices.contains(chapter - 1)
        else { return 1 }
        return max(counts[overallBook][chapter - 1], 1)
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
        updated.verse = verse == 0 ? nil : min(verse, verseCount)
        personalData.saveBookmark(updated)
    }
}

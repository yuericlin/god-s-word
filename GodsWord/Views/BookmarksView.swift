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
/// Mark, Edit and Delete. Two styles: mini (small vertical ribbons, color
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

    /// Small vertical ribbon, color only.
    private func miniRibbon(for bookmark: Bookmark) -> some View {
        RibbonShape()
            .fill(bookmark.color.opacity(0.55))
            .frame(width: 24, height: 44)
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
                }
                .padding(.leading, 16)
                .padding(.trailing, 28)
            }
            .contentShape(HorizontalRibbonShape())
            .onTapGesture { onJump(bookmark) }
            .onLongPressGesture(minimumDuration: 1.0) {
                pendingBookmark = bookmark
                showingOptions = true
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
    @Environment(\.moduleStore) private var store
    @State private var editingBookmark: Bookmark?

    /// A verse note parsed from its storage key.
    private struct NoteEntry {
        let key: String
        let moduleID: String
        let testament: Int
        let book: Int
        let chapter: Int
        let verse: Int
        let text: String
    }

    private var noteEntries: [NoteEntry] {
        personalData.verseNotes.compactMap { key, text -> NoteEntry? in
            let parts = key.split(separator: ":")
            guard parts.count == 5,
                  let testament = Int(parts[1]),
                  let book = Int(parts[2]),
                  let chapter = Int(parts[3]),
                  let verse = Int(parts[4]) else { return nil }
            return NoteEntry(key: key, moduleID: String(parts[0]),
                             testament: testament, book: book,
                             chapter: chapter, verse: verse, text: text)
        }
        .sorted {
            ($0.moduleID, $0.testament, $0.book, $0.chapter, $0.verse) <
            ($1.moduleID, $1.testament, $1.book, $1.chapter, $1.verse)
        }
    }

    private func noteReference(_ entry: NoteEntry) -> String {
        let overall = entry.testament == 1 ? entry.book - 1 : 39 + entry.book - 1
        let bookName = history.bookName(overall: overall)
        let ref = "\(bookName) \(entry.chapter):\(entry.verse)"
        return entry.moduleID == history.module.id ? ref : "\(entry.moduleID) \(ref)"
    }

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

            // Notes section: every verse with a note, tap to jump there.
            Text("Notes").font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)
            if noteEntries.isEmpty {
                Text("No notes yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(noteEntries, id: \.key) { entry in
                            Button { jumpToNote(entry) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(noteReference(entry))
                                        .font(.subheadline)
                                    Text(entry.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
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
        history.dwellMode = true
        history.testament = bookmark.testament
        history.book = bookmark.book
        let count = max(history.chapterCount(testament: bookmark.testament,
                                             book: bookmark.book), 1)
        history.chapter = min(max(bookmark.chapter, 1), count)
        showing = false
    }

    private func jumpToNote(_ entry: NoteEntry) {
        // Switch version if the note belongs to another one.
        if entry.moduleID != history.module.id,
           let mod = store.installedModules().first(where: { $0.id == entry.moduleID }) {
            history.module = mod
        }
        history.dwellMode = true
        history.testament = entry.testament
        history.book = entry.book
        let count = max(history.chapterCount(testament: entry.testament,
                                             book: entry.book), 1)
        history.chapter = min(max(entry.chapter, 1), count)
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

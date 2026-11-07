// AssignBookmarkView.swift — sheet opened from the reader's long-press menu
// ("Assign Bookmark") and from the selection bar's Bookmark action
// (REQ-BM-13). Lists the existing bookmarks; tapping one moves it to the
// target being read (REQ-BM-8) — a chapter, or one verse of it when the
// sheet was opened for a single selected verse (REQ-BM-12). "New Bookmark"
// starts an unsaved draft at the target and hands it back so the presenter
// can open its editor; the draft is stored only if the user saves it
// there (REQ-BM-9).

import SwiftUI

struct AssignBookmarkView: View {
    let history: ReadingHistory
    /// The verse the sheet targets, or nil to target the chapter
    /// as a whole (REQ-BM-12/13).
    var verse: Int? = nil
    /// Called with a new, unsaved bookmark; the presenter opens its editor.
    var onCreate: (Bookmark) -> Void

    /// "John 3" for a chapter target, "John 3:16" for a verse target.
    private var targetReference: String {
        var text = "\(history.bookTitle) \(history.chapter)"
        if let verse { text += ":\(verse)" }
        return text
    }

    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        let draft = personalData.makeBookmarkDraft(
                            name: targetReference,
                            testament: history.testament,
                            book: history.book,
                            chapter: history.chapter,
                            verse: verse)
                        onCreate(draft)
                        dismiss()
                    } label: {
                        Label("New Bookmark", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Starts a bookmark at \(targetReference). It is saved when you tap Save.")
                }

                if !personalData.bookmarks.isEmpty {
                    Section {
                        ForEach(personalData.bookmarks) { bookmark in
                            Button { assign(bookmark) } label: { row(for: bookmark) }
                        }
                    } header: {
                        Text("Existing bookmarks")
                    } footer: {
                        Text("Choosing a bookmark moves it to \(targetReference).")
                    }
                }
            }
            .navigationTitle("Assign bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(for bookmark: Bookmark) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(bookmark.color)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.name)
                    .foregroundStyle(.primary)
                Text(reference(for: bookmark))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isHere(bookmark) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    private func isHere(_ bookmark: Bookmark) -> Bool {
        bookmark.isAt(testament: history.testament, book: history.book,
                      chapter: history.chapter, verse: verse)
    }

    private func assign(_ bookmark: Bookmark) {
        personalData.assignBookmark(bookmark, testament: history.testament,
                                    book: history.book, chapter: history.chapter,
                                    verse: verse)
        dismiss()
    }

    private func reference(for bookmark: Bookmark) -> String {
        guard let overall = bookmark.overallBookIndex,
              let name = history.version.bookNameIfPresent(overall: overall)
        else {
            // This version lacks the book (partial private Bible).
            return "Book \(bookmark.book), chapter \(bookmark.chapter)"
        }
        var text = "\(name) \(bookmark.chapter)"
        if let verse = bookmark.verse { text += ":\(verse)" }
        return text
    }
}

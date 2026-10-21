// AssignBookmarkView.swift — sheet opened from the reader's long-press menu
// ("Assign Bookmark"). Lists the existing bookmarks; tapping one moves it to
// the chapter being read (REQ-BM-8). "New Bookmark" starts an unsaved draft
// at this chapter and hands it back so the presenter can open its editor;
// the draft is stored only if the user saves it there (REQ-BM-9).

import SwiftUI

struct AssignBookmarkView: View {
    let history: ReadingHistory
    /// Called with a new, unsaved bookmark; the presenter opens its editor.
    var onCreate: (Bookmark) -> Void

    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        let draft = personalData.makeBookmarkDraft(
                            name: "\(history.bookTitle) \(history.chapter)",
                            testament: history.testament,
                            book: history.book,
                            chapter: history.chapter)
                        onCreate(draft)
                        dismiss()
                    } label: {
                        Label("New Bookmark", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Starts a bookmark at \(history.bookTitle) \(history.chapter). It is saved when you tap Save.")
                }

                if !personalData.bookmarks.isEmpty {
                    Section {
                        ForEach(personalData.bookmarks) { bookmark in
                            Button { assign(bookmark) } label: { row(for: bookmark) }
                        }
                    } header: {
                        Text("Existing bookmarks")
                    } footer: {
                        Text("Choosing a bookmark moves it to \(history.bookTitle) \(history.chapter).")
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
                      chapter: history.chapter)
    }

    private func assign(_ bookmark: Bookmark) {
        personalData.assignBookmark(bookmark, testament: history.testament,
                                    book: history.book, chapter: history.chapter)
        dismiss()
    }

    private func reference(for bookmark: Bookmark) -> String {
        guard let overall = bookmark.overallBookIndex,
              let name = history.version.bookNameIfPresent(overall: overall)
        else {
            // This version lacks the book (partial private Bible).
            return "Book \(bookmark.book), chapter \(bookmark.chapter)"
        }
        return "\(name) \(bookmark.chapter)"
    }
}

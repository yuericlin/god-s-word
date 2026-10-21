// AssignBookmarkView.swift — sheet opened from the reader's long-press menu
// ("Assign Bookmark"). Lists the existing bookmarks; tapping one moves it to
// the chapter being read (REQ-BM-8). "New Bookmark" creates one at this
// chapter and hands it back so the presenter can open its editor.

import SwiftUI

struct AssignBookmarkView: View {
    let history: ReadingHistory
    /// Called with a newly created bookmark; the presenter opens its editor.
    var onCreate: (Bookmark) -> Void

    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        let created = personalData.addBookmark(
                            name: "\(history.bookTitle) \(history.chapter)",
                            testament: history.testament,
                            book: history.book,
                            chapter: history.chapter)
                        onCreate(created)
                        dismiss()
                    } label: {
                        Label("New Bookmark", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Creates a bookmark at \(history.bookTitle) \(history.chapter).")
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
        bookmark.testament == history.testament
            && bookmark.book == history.book
            && bookmark.chapter == history.chapter
    }

    private func assign(_ bookmark: Bookmark) {
        var moved = bookmark
        moved.testament = history.testament
        moved.book = history.book
        moved.chapter = history.chapter
        personalData.updateBookmark(moved)
        dismiss()
    }

    private func reference(for bookmark: Bookmark) -> String {
        let overall = bookmark.testament == 1
            ? bookmark.book - 1 : 39 + bookmark.book - 1
        guard overall >= 0 && overall < 66 else { return "" }
        return "\(history.bookName(overall: overall)) \(bookmark.chapter)"
    }
}

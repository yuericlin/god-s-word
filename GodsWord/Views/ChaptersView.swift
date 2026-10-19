// ChaptersView.swift — combined book and chapter picker.
// The top bar picks both book and chapter; the grid below is for browsing.
// Selecting a book jumps to its last-read chapter (not always 1).

import SwiftUI
import SwordReader

struct ChaptersView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    /// Two-level book menu: tap a book to see its chapters, tap a chapter
    /// to open the reader. Selecting a book defaults to its last-read chapter.
    private var bookMenu: some View {
        Menu {
            ForEach(0..<66, id: \.self) { i in
                let t = i < 39 ? 1 : 2
                let b = i < 39 ? i + 1 : i - 39 + 1
                let count = max(history.chapterCount(testament: t, book: b), 1)
                Menu(history.bookName(overall: i)) {
                    ForEach(1...count, id: \.self) { c in
                        Button("\(c)") {
                            history.testament = t
                            history.book = b
                            history.chapter = c
                            path.append(Route.reader)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(history.bookTitle) \(history.chapter)")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: two-level book menu (book -> chapter).
            bookMenu
                .padding(.vertical, 12)

            Divider()

            // Chapter grid for browsing.
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(1...max(history.chapterCount, 1), id: \.self) { c in
                        Button {
                            history.chapter = c
                            path.append(Route.reader)
                        } label: {
                            Text("\(c)")
                                .font(.body)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(c == history.chapter
                                    ? Color.accentColor.opacity(0.25)
                                    : Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Select")
        .navigationBarTitleDisplayMode(.inline)
        .edgeNavigation(
            onForward: {
                // Right-edge swipe left: forward to the reader.
                path.append(Route.reader)
            },
            onBackward: {
                // Right-edge swipe right: back to the book picker.
                if !path.isEmpty { path.removeLast() }
            }
        )
    }
}

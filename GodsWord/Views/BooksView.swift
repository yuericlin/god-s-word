// BooksView.swift — the 66 books, grouped Old / New Testament.
// Reads the shared ReadingHistory so the current book stays highlighted.

import SwiftUI
import SwordReader

struct BooksView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath

    var body: some View {
        List {
            Section("Old Testament") {
                ForEach(0 ..< 39, id: \.self) { i in
                    bookButton(overall: i, testament: 1, book: i + 1)
                }
            }
            Section("New Testament") {
                ForEach(0 ..< 27, id: \.self) { i in
                    bookButton(overall: 39 + i, testament: 2, book: i + 1)
                }
            }
        }
        .navigationTitle(history.version.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .edgeNavigation(
            onForward: {
                // Right-edge swipe left: forward to the chapter picker.
                path.append(Route.chapters)
            },
            onBackward: {
                // Right-edge swipe right: back to the version picker.
                if !path.isEmpty { path.removeLast() }
            }
        )
    }

    private func bookButton(overall: Int, testament: Int, book: Int) -> some View {
        Button {
            history.testament = testament
            history.book = book
            history.chapter = 1
            path.append(Route.chapters)
        } label: {
            HStack {
                Text(history.bookName(overall: overall))
                if history.overallBookIndex == overall {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

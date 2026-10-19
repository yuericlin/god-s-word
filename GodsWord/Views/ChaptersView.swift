// ChaptersView.swift — chapter picker grid for the current book.
// Reads the shared ReadingHistory so the current chapter stays highlighted.

import SwiftUI
import SwordReader

struct ChaptersView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1 ... max(history.chapterCount, 1), id: \.self) { c in
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
        .navigationTitle(history.bookTitle)
        .navigationBarTitleDisplayMode(.inline)
        .stepBackOnRightEdge(path: $path)
    }
}

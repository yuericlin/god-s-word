// ChaptersView.swift — combined book and chapter picker.
// The top bar picks both book and chapter; the grid below is for browsing.
// Selecting a book jumps to its last-read chapter (not always 1).

import SwiftUI
import SwordReader

struct ChaptersView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath
    @EnvironmentObject private var personalData: PersonalData

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    /// Book picker: selecting a book jumps to its last-read chapter.
    private var bookSelection: Binding<Int> {
        Binding(
            get: { history.overallBookIndex },
            set: { overall in
                let newTestament = overall < 39 ? 1 : 2
                let newBook = overall < 39 ? overall + 1 : overall - 39 + 1
                history.testament = newTestament
                history.book = newBook
                // Jump to the last-read chapter for this book, not chapter 1.
                if let last = personalData.historyLog.first(where: {
                    $0.moduleID == history.module.id &&
                    $0.testament == newTestament && $0.book == newBook
                }) {
                    history.chapter = min(last.chapter, max(history.chapterCount, 1))
                } else {
                    history.chapter = 1
                }
            }
        )
    }

    /// Chapter picker: selecting a chapter opens the reader.
    private var chapterSelection: Binding<Int> {
        Binding(
            get: { history.chapter },
            set: { c in
                history.chapter = c
                path.append(Route.reader)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: pick both book and chapter.
            HStack(spacing: 16) {
                Menu {
                    Picker("Book", selection: bookSelection) {
                        ForEach(0..<66, id: \.self) { i in
                            Text(history.bookName(overall: i)).tag(i)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(history.bookTitle)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Menu {
                    Picker("Chapter", selection: chapterSelection) {
                        ForEach(1...max(history.chapterCount, 1), id: \.self) { c in
                            Text("\(c)").tag(c)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Ch \(history.chapter)")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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

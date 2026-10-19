// ChaptersView.swift — combined book and chapter picker.
// A book strip on top lets the user switch books without going back;
// the chapter grid below updates. Tapping a chapter opens the reader.

import SwiftUI
import SwordReader

struct ChaptersView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            // Book strip: switch books without leaving the picker.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<66, id: \.self) { i in
                            Button {
                                history.setBook(overall: i)
                            } label: {
                                Text(shortBookName(overall: i))
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(i == history.overallBookIndex
                                        ? Color.accentColor
                                        : Color(.secondarySystemBackground))
                                    .foregroundStyle(i == history.overallBookIndex ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .id(i)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    proxy.scrollTo(history.overallBookIndex, anchor: .center)
                }
                .onChange(of: history.overallBookIndex) { _, newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            Divider()

            // Chapter grid for the selected book.
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
        .navigationTitle(history.bookTitle)
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

    /// Short book name for the strip (full name is in the title).
    private func shortBookName(overall: Int) -> String {
        history.bookName(overall: overall)
    }
}

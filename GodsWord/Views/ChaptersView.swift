// ChaptersView.swift — book and chapter picker.
// Top button opens a two-level picker (books -> chapters) in a sheet.
// The grid below browses chapters for the current book.

import SwiftUI
import SwordReader

struct ChaptersView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath
    @State private var showingPicker = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            // Top: two-level picker button.
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text("\(history.bookTitle) \(history.chapter)")
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)

            Divider()

            // Chapter grid for the current book.
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
                path.append(Route.reader)
            },
            onBackward: {
                if !path.isEmpty { path.removeLast() }
            }
        )
        .sheet(isPresented: $showingPicker) {
            BookChapterPickerSheet(history: history) { t, b, c in
                history.testament = t
                history.book = b
                history.chapter = c
                showingPicker = false
                path.append(Route.reader)
            }
        }
    }
}

/// Two-level picker sheet: books list drills into chapter grids.
struct BookChapterPickerSheet: View {
    let history: ReadingHistory
    var onSelect: (Int, Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var bookPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $bookPath) {
            List {
                Section("Old Testament") {
                    ForEach(0..<39, id: \.self) { i in
                        NavigationLink(value: i) {
                            Text(history.bookName(overall: i))
                        }
                    }
                }
                Section("New Testament") {
                    ForEach(39..<66, id: \.self) { i in
                        NavigationLink(value: i) {
                            Text(history.bookName(overall: i))
                        }
                    }
                }
            }
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Int.self) { overall in
                let t = overall < 39 ? 1 : 2
                let b = overall < 39 ? overall + 1 : overall - 39 + 1
                let count = max(history.chapterCount(testament: t, book: b), 1)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(1...count, id: \.self) { c in
                            Button {
                                onSelect(t, b, c)
                            } label: {
                                Text("\(c)")
                                    .font(.body)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .navigationTitle(history.bookName(overall: overall))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

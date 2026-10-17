// ChaptersView.swift — chapter picker grid for one book.

import SwiftUI
import SwordReader

struct ChaptersView: View {
    let module: InstalledModule
    let testament: Int
    let book: Int
    @Binding var path: NavigationPath

    private var bookTitle: String {
        let overall = testament == 1 ? book - 1 : 39 + book - 1
        return module.info.isChinese ? BibleBookNamesZhHans[overall] : Versification.kjv.books[overall].name
    }

    private var chapterCount: Int {
        module.info.versification?.book(testament: testament, book: book)?.chapters ?? 0
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1 ... max(chapterCount, 1), id: \.self) { c in
                    NavigationLink(value: Route.reader(moduleID: module.id, testament: testament,
                                                      book: book, chapter: c)) {
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
        .navigationTitle(bookTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

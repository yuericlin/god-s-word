// BooksView.swift — the 66 books, grouped Old / New Testament.

import SwiftUI
import SwordReader

struct BooksView: View {
    let module: InstalledModule
    @Binding var path: NavigationPath

    private var useChinese: Bool { module.info.isChinese }

    private func bookName(overallIndex: Int) -> String {
        if useChinese { return BibleBookNamesZhHans[overallIndex] }
        return Versification.kjv.books[overallIndex].name
    }

    var body: some View {
        List {
            Section("Old Testament") {
                ForEach(0 ..< 39, id: \.self) { i in
                    NavigationLink(value: Route.chapters(moduleID: module.id, testament: 1, book: i + 1)) {
                        Text(bookName(overallIndex: i))
                    }
                }
            }
            Section("New Testament") {
                ForEach(0 ..< 27, id: \.self) { i in
                    NavigationLink(value: Route.chapters(moduleID: module.id, testament: 2, book: i + 1)) {
                        Text(bookName(overallIndex: 39 + i))
                    }
                }
            }
        }
        .navigationTitle(module.info.description)
        .navigationBarTitleDisplayMode(.inline)
    }
}

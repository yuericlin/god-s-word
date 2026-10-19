// ReaderView.swift — renders one chapter at a time.

import SwiftUI
import SwordReader

struct ReaderView: View {
    let module: InstalledModule
    @State var testament: Int
    @State var book: Int
    @State var chapter: Int
    @Binding var path: NavigationPath

    @EnvironmentObject private var personalData: PersonalData
    @State private var verses: [(verse: Int, text: String)] = []
    @State private var loadError: String?

    private var bookTitle: String {
        let overall = testament == 1 ? book - 1 : 39 + book - 1
        return module.info.isChinese ? BibleBookNamesZhHans[overall] : Versification.kjv.books[overall].name
    }

    private var v11n: Versification? { module.info.versification }

    private var chapterCount: Int {
        v11n?.book(testament: testament, book: book)?.chapters ?? 0
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("Couldn't open chapter", systemImage: "exclamationmark.triangle",
                                        description: Text(loadError))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Color.clear.frame(height: 0).id("top")
                            if personalData.verseByVerse {
                                ForEach(verses, id: \.verse) { v in
                                    Text(attributedVerse(number: v.verse, text: v.text))
                                        .font(.system(size: personalData.fontSize, design: .serif))
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                // Paragraph mode: no paragraph info in the modules,
                                // so the whole chapter flows as one paragraph.
                                Text(attributedParagraph())
                                    .font(.system(size: personalData.fontSize, design: .serif))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chapter) { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .navigationTitle("\(bookTitle) \(chapter)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button { go(toChapter: chapter - 1) } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(!canGo(toChapter: chapter - 1))
                    Spacer()
                    Text("\(chapter) / \(chapterCount)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { go(toChapter: chapter + 1) } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(!canGo(toChapter: chapter + 1))
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -60 { go(toChapter: chapter + 1) }
                    else if value.translation.width > 60 { go(toChapter: chapter - 1) }
                }
        )
        .task(id: chapterKey) { await load() }
    }

    private var chapterKey: String { "\(testament)-\(book)-\(chapter)" }

    private func canGo(toChapter c: Int) -> Bool {
        // Same-book navigation only; cross-book comes via the chapter picker.
        c >= 1 && c <= chapterCount
    }

    private func go(toChapter c: Int) {
        guard canGo(toChapter: c) else { return }
        chapter = c
    }

    private func attributedVerse(number: Int, text: String) -> AttributedString {
        var num = AttributedString("\(number) ")
        num.font = .system(size: personalData.fontSize * 0.65, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.25
        let body = AttributedString(text)
        return num + AttributedString(" ") + body
    }

    /// Whole chapter as one flowing paragraph (paragraph mode). Verse numbers
    /// stay inline; verses are joined with spaces.
    private func attributedParagraph() -> AttributedString {
        var out = AttributedString("")
        for (i, v) in verses.enumerated() {
            if i > 0 { out += AttributedString(" ") }
            out += attributedVerse(number: v.verse, text: v.text)
        }
        return out
    }

    private func load() async {
        loadError = nil
        do {
            let mod = try await ModuleLoader.shared.module(for: module)
            let rendered = mod.chapter(testament: testament, book: book, chapter: chapter)
            guard !rendered.isEmpty else {
                loadError = "This chapter has no text in this version."
                return
            }
            verses = rendered
            personalData.savePosition(ReadingPosition(testament: testament, book: book, chapter: chapter),
                                      for: module.id)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// ReaderView.swift — renders one chapter at a time.
// Reads and writes the shared ReadingHistory, so the pickers and the
// version menu always reflect the current selection.

import SwiftUI
import SwordReader

struct ReaderView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath

    @Environment(\.moduleStore) private var store
    @EnvironmentObject private var personalData: PersonalData
    @State private var verses: [(verse: Int, text: String)] = []
    @State private var verseTokens: [(verse: Int, tokens: [WordToken])] = []
    @State private var loadError: String?
    @State private var showingSettings = false
    @State private var showingFullSettings = false
    @State private var showingHistory = false
    @State private var showingBookChapterPicker = false
    @State private var showingBookmarks = false
    @State private var strongsKey: String?
    @State private var dwellTask: Task<Void, Never>?
    @State private var availableModules: [InstalledModule] = []
    @State private var viewSize: CGSize = .zero

    /// Whether to render tappable Strong's numbers: the toggle is on and
    /// the current version carries Strong's data.
    private var useStrongs: Bool {
        personalData.showStrongs && history.module.info.supportsStrongs
    }

    private var chapterPickerSelection: Binding<Int> {
        Binding(get: { history.chapter }, set: { go(toChapter: $0) })
    }

    /// Binding for the version picker next to the book title. Keeps the same
    /// reference, clamped to the new version's chapter count.
    private var versionSelection: Binding<String> {
        Binding(
            get: { history.module.id },
            set: { newID in
                guard newID != history.module.id,
                      let mod = availableModules.first(where: { $0.id == newID }) else { return }
                history.module = mod
                let count = history.chapterCount
                if history.chapter > count {
                    history.chapter = max(count, 1)
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
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
                                    if useStrongs {
                                        ForEach(verseTokens, id: \.verse) { v in
                                            Text(attributedVerseTokens(number: v.verse, tokens: v.tokens))
                                                .font(.system(size: personalData.fontSize, design: .serif))
                                                .lineSpacing(6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    } else {
                                        ForEach(verses, id: \.verse) { v in
                                            Text(attributedVerse(number: v.verse, text: v.text))
                                                .font(.system(size: personalData.fontSize, design: .serif))
                                                .lineSpacing(6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                } else {
                                    // Paragraph mode: no paragraph info in the modules,
                                    // so the whole chapter flows as one paragraph.
                                    Text(useStrongs ? attributedParagraphTokens() : attributedParagraph())
                                        .font(.system(size: personalData.fontSize, design: .serif))
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: history.chapter) { proxy.scrollTo("top", anchor: .top) }
                        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
                    }
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "strongs",
                              let key = url.host, !key.isEmpty
                        else { return .systemAction }
                        strongsKey = key
                        return .handled
                    })
                }
            }
            // Ribbons for bookmarks pointing at the chapter being read.
            // Nothing shows when the current chapter isn't bookmarked.
            let currentMarks = personalData.bookmarks.filter {
                $0.testament == history.testament &&
                $0.book == history.book &&
                $0.chapter == history.chapter
            }
            if !currentMarks.isEmpty {
                BookmarkRibbonsRow(history: history,
                                   bookmarks: currentMarks,
                                   style: .mini,
                                   onJump: { _ in })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 10)
            }
            // Slide-in bookmarks panel, opened with a right-edge swipe.
            if showingBookmarks {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { showingBookmarks = false }
                BookmarksPanel(history: history, showing: $showingBookmarks)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing))
            }
            // Slide-in settings drawer, opened with a left-edge swipe.
            if showingSettings {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { showingSettings = false }
                settingsDrawer
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingSettings)
        .animation(.easeInOut(duration: 0.25), value: showingBookmarks)
        .background(DrawerEdgeGesture { showingSettings = true }.frame(width: 0, height: 0))
        .navigationBarTitleDisplayMode(.inline)
        .edgeNavigation(
            onForward: {
                // Right-edge swipe left: open the bookmarks panel.
                showingBookmarks = true
            },
            onBackward: {
                // Right-edge swipe right: back to the chapter picker.
                if !path.isEmpty { path.removeLast() }
            }
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Version", selection: versionSelection) {
                            ForEach(availableModules, id: \.id) { mod in
                                Text(mod.id).tag(mod.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(history.module.id)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showingBookChapterPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(history.bookTitle)
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button { go(toChapter: history.chapter - 1) } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(!canGo(toChapter: history.chapter - 1))
                    Spacer()
                    if history.chapterCount > 0 {
                        Menu {
                            Picker("Chapter", selection: chapterPickerSelection) {
                                ForEach(1...history.chapterCount, id: \.self) { c in
                                    Text("\(c)").tag(c)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(history.chapter) / \(history.chapterCount)")
                                Image(systemName: "chevron.down")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(history.chapter) / \(history.chapterCount)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { go(toChapter: history.chapter + 1) } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(!canGo(toChapter: history.chapter + 1))
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    guard !showingSettings && !showingBookmarks else { return }
                    // Middle swipes turn chapters. Edge swipes are handled by
                    // the drawer (left) and the navigation overlay (right).
                    let inRightEdge = viewSize.width > 0 && value.startLocation.x > viewSize.width - 20
                    guard !inRightEdge else { return }
                    if value.translation.width < -60 {
                        go(toChapter: history.chapter + 1)
                    } else if value.translation.width > 60 {
                        go(toChapter: history.chapter - 1)
                    }
                }
        )
        .task(id: chapterKey) { await load() }
        .onAppear { availableModules = store.installedModules() }
        .onDisappear { dwellTask?.cancel() }
        .sheet(isPresented: $showingFullSettings) {
            SettingsView(onSelectHistoryEntry: { entry in
                if let mod = availableModules.first(where: { $0.id == entry.moduleID }) {
                    history.module = mod
                    history.testament = entry.testament
                    history.book = entry.book
                    history.chapter = entry.chapter
                }
                showingFullSettings = false
            })
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                HistoryView(onSelect: { entry in
                    if let mod = availableModules.first(where: { $0.id == entry.moduleID }) {
                        history.module = mod
                        history.testament = entry.testament
                        history.book = entry.book
                        history.chapter = entry.chapter
                    }
                    showingHistory = false
                })
            }
            .environmentObject(personalData)
        }
        .sheet(isPresented: $showingBookChapterPicker) {
            BookChapterPickerSheet(history: history) { t, b, c in
                history.testament = t
                history.book = b
                history.chapter = c
                showingBookChapterPicker = false
            }
        }
        .sheet(isPresented: Binding(
            get: { strongsKey != nil },
            set: { if !$0 { strongsKey = nil } }
        )) {
            if let key = strongsKey {
                StrongsDefinitionView(key: key)
            }
        }
    }

    /// Slide-in settings panel with reading options and a link to full settings.
    /// Closes with the X button, a tap outside, or a left-drag on the edge handle.
    /// (The close drag lives only on the handle so it never fights the toggle.)
    private var settingsDrawer: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Settings").font(.headline)
                    Spacer()
                    Button { showingSettings = false } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                }
                ReadingSettingsView(showStrongsOption: history.module.info.supportsStrongs)
                Spacer()
                Button("History") {
                    showingSettings = false
                    showingHistory = true
                }
                Button("More Settings…") {
                    showingSettings = false
                    showingFullSettings = true
                }
            }
            .padding()
            .frame(width: 288)
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 5, height: 48)
                Spacer()
            }
            .frame(width: 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -30 { showingSettings = false }
                    }
            )
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var chapterKey: String {
        "\(history.module.id)-\(history.testament)-\(history.book)-\(history.chapter)"
    }

    private func canGo(toChapter c: Int) -> Bool {
        // Same-book navigation only; cross-book comes via the chapter picker.
        c >= 1 && c <= history.chapterCount
    }

    private func go(toChapter c: Int) {
        guard canGo(toChapter: c) else { return }
        history.chapter = c
    }

    private func attributedVerse(number: Int, text: String) -> AttributedString {
        attributedVerseNumber(number) + AttributedString(" ") + AttributedString(text)
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

    /// One Strong's number as small raised linked text, e.g. " H7225".
    /// Tapping opens the dictionary entry (handled via the openURL environment).
    private func attributedStrongsNumber(_ key: String) -> AttributedString {
        var num = AttributedString(" \(key)")
        num.font = .system(size: personalData.fontSize * 0.55, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.22
        num.underlineStyle = []
        num.link = URL(string: "strongs://\(key)")
        return num
    }

    /// Verse text from word tokens, with tappable Strong's numbers inline.
    private func attributedVerseTokens(number: Int, tokens: [WordToken]) -> AttributedString {
        var out = attributedVerseNumber(number)
        for (i, token) in tokens.enumerated() {
            if i > 0 { out += AttributedString(" ") }
            out += AttributedString(token.text)
            for key in token.strongs {
                out += attributedStrongsNumber(key)
            }
        }
        return out
    }

    /// Whole chapter as one flowing paragraph from word tokens.
    private func attributedParagraphTokens() -> AttributedString {
        var out = AttributedString("")
        for (i, v) in verseTokens.enumerated() {
            if i > 0 { out += AttributedString(" ") }
            out += attributedVerseTokens(number: v.verse, tokens: v.tokens)
        }
        return out
    }

    /// The raised verse number prefix shared by both verse renderers.
    private func attributedVerseNumber(_ number: Int) -> AttributedString {
        var num = AttributedString("\(number) ")
        num.font = .system(size: personalData.fontSize * 0.65, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.25
        return num
    }

    private func load() async {
        loadError = nil
        dwellTask?.cancel()
        do {
            let mod = try await ModuleLoader.shared.module(for: history.module)
            let rendered = mod.chapter(testament: history.testament, book: history.book,
                                       chapter: history.chapter)
            guard !rendered.isEmpty else {
                loadError = "This chapter has no text in this version."
                return
            }
            verses = rendered
            if history.module.info.supportsStrongs {
                verseTokens = mod.chapterTokens(testament: history.testament,
                                                book: history.book,
                                                chapter: history.chapter)
            } else {
                verseTokens = []
            }
            personalData.savePosition(ReadingPosition(testament: history.testament,
                                                      book: history.book,
                                                      chapter: history.chapter),
                                      for: history.module.id)
            personalData.saveLastReading(moduleID: history.module.id,
                                          testament: history.testament,
                                          book: history.book,
                                          chapter: history.chapter)
            if history.dwellMode {
                // Bookmark jump: record only after a 60-second dwell.
                // Turning chapters restarts the timer; quick flips are skipped.
                startDwellTimer(for: chapterKey)
            } else {
                personalData.recordHistory(moduleID: history.module.id,
                                            bookName: history.bookTitle,
                                            testament: history.testament,
                                            book: history.book,
                                            chapter: history.chapter)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Records a history entry only if the user is still on the same
    /// chapter after 60 seconds, then leaves dwell mode.
    private func startDwellTimer(for key: String) {
        dwellTask?.cancel()
        dwellTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            if key == chapterKey {
                personalData.recordHistory(moduleID: history.module.id,
                                            bookName: history.bookTitle,
                                            testament: history.testament,
                                            book: history.book,
                                            chapter: history.chapter)
                history.dwellMode = false
            }
        }
    }
}

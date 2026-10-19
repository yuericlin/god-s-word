// ReaderView.swift — renders one chapter at a time.
// Reads and writes the shared ReadingHistory, so the pickers and the
// version menu always reflect the current selection.

import SwiftUI
import UIKit
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
    /// Verse picker: verses the user has tapped. Light sky blue highlight;
    /// tap again to unselect; long-press a selected verse for Copy/Notes.
    @State private var selectedVerses: Set<Int> = []
    @State private var noteVerse: Int?
    @State private var noteDraft: String = ""
    @State private var showingNoteEditor = false

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
                                    // One flow per verse: each verse stays on
                                    // its own line but words wrap within it.
                                    ForEach(verses, id: \.verse) { v in
                                        FlowLayout {
                                            ForEach(flowTokens(for: v.verse)) { token in
                                                flowTokenView(token)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else {
                                    // Paragraph mode: no paragraph info in the
                                    // modules, so the whole chapter flows as
                                    // one paragraph of tappable words.
                                    FlowLayout {
                                        ForEach(allFlowTokens) { token in
                                            flowTokenView(token)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .font(.system(size: personalData.fontSize, design: .serif))
                            .padding()
                            // Long-press on empty reading area (margins, gaps)
                            // offers a chapter note. Words swallow the
                            // long-press so it doesn't fire on text.
                            .contextMenu {
                                Button("Take Notes") { openChapterNoteEditor() }
                            }
                        }
                        .onChange(of: history.chapter) { proxy.scrollTo("top", anchor: .top) }
                        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
                    }
                }
            }
            // Copy/Notes bar while verses are selected. Tapping a word
            // toggles its verse; the bar acts on the whole selection.
            if !selectedVerses.isEmpty {
                HStack(spacing: 24) {
                    Button("Copy") { copySelectedVerses() }
                    Button("Notes") { openNoteEditorForSelection() }
                    Button {
                        selectedVerses = []
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 90)
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
        // Selection lives within a chapter: clear it when the location
        // changes, but keep it when only the version (module) changes.
        .onChange(of: history.testament) { selectedVerses = [] }
        .onChange(of: history.book) { selectedVerses = [] }
        .onChange(of: history.chapter) { selectedVerses = [] }
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
        .sheet(isPresented: $showingNoteEditor) {
            if let verse = noteVerse {
                VerseNoteEditor(reference: noteReference(verse), text: $noteDraft) { text in
                    personalData.setVerseNote(text, forKey: noteKey(verse))
                }
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

    // MARK: - Verse picker (flow tokens)

    /// One tappable unit in the reading flow: a word (or verse number)
    /// belonging to a verse, a Strong's number anchored after its word,
    /// or the tiny note icon marking a verse that has a note.
    private struct FlowToken: Identifiable {
        enum Kind {
            case word(AttributedString)
            case strongs(key: String, text: AttributedString)
            case noteIcon(verse: Int)
        }
        let id: Int
        let verse: Int
        let kind: Kind
    }

    /// Light sky blue highlight for selected verses.
    private var selectionColor: Color {
        Color(red: 0.53, green: 0.81, blue: 0.98).opacity(0.55)
    }

    private var allFlowTokens: [FlowToken] {
        useStrongs ? strongsFlowTokens() : plainFlowTokens()
    }

    private func flowTokens(for verse: Int) -> [FlowToken] {
        allFlowTokens.filter { $0.verse == verse }
    }

    /// Plain mode: verse number, optional note icon, then words.
    private func plainFlowTokens() -> [FlowToken] {
        var tokens: [FlowToken] = []
        var id = 0
        for v in verses {
            id = appendVerseHead(v.verse, to: &tokens, id: id)
            for word in v.text.split(separator: " ", omittingEmptySubsequences: true) {
                tokens.append(FlowToken(id: id, verse: v.verse,
                                        kind: .word(AttributedString(String(word)))))
                id += 1
            }
        }
        return tokens
    }

    /// Strong's mode: words from the token segments, each Strong's number a
    /// separate tappable token right after its word.
    private func strongsFlowTokens() -> [FlowToken] {
        var tokens: [FlowToken] = []
        var id = 0
        for v in verseTokens {
            id = appendVerseHead(v.verse, to: &tokens, id: id)
            for seg in v.tokens {
                let words = seg.text.split(separator: " ", omittingEmptySubsequences: true)
                for (wi, word) in words.enumerated() {
                    tokens.append(FlowToken(id: id, verse: v.verse,
                                            kind: .word(AttributedString(String(word)))))
                    id += 1
                    if wi == words.count - 1 {
                        for key in seg.strongs {
                            var sattr = AttributedString(key)
                            sattr.font = .system(size: personalData.fontSize * 0.55,
                                                design: .serif)
                            sattr.foregroundColor = .secondary
                            tokens.append(FlowToken(id: id, verse: v.verse,
                                                    kind: .strongs(key: key, text: sattr)))
                            id += 1
                        }
                    }
                }
            }
        }
        return tokens
    }

    /// Verse number token plus the tiny note icon when the verse has a note.
    /// Returns the next id.
    private func appendVerseHead(_ verse: Int, to tokens: inout [FlowToken], id: Int) -> Int {
        var id = id
        tokens.append(FlowToken(id: id, verse: verse,
                                kind: .word(verseNumberAttr(verse))))
        id += 1
        if hasNote(verse: verse) {
            tokens.append(FlowToken(id: id, verse: verse, kind: .noteIcon(verse: verse)))
            id += 1
        }
        return id
    }

    /// Raised verse number.
    private func verseNumberAttr(_ verse: Int) -> AttributedString {
        var num = AttributedString("\(verse)")
        num.font = .system(size: personalData.fontSize * 0.65, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.25
        return num
    }

    @ViewBuilder
    private func flowTokenView(_ token: FlowToken) -> some View {
        switch token.kind {
        case .word(let attr):
            // Tapping a word toggles the verse's selection; the Copy/Notes
            // bar appears while any verse is selected.
            let selected = selectedVerses.contains(token.verse)
            Text(attr)
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(selected ? selectionColor : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onTapGesture { toggleSelection(token.verse) }
                // Swallow long-press so the empty-area menu doesn't fire on words.
                .onLongPressGesture { }
        case .strongs(let key, let attr):
            // Tapping a Strong's number opens its dictionary entry.
            Text(attr)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { strongsKey = key }
                .onLongPressGesture { }
        case .noteIcon(let verse):
            // Tiny sticky-note marker; tapping opens the verse's note.
            Image(systemName: "note")
                .font(.system(size: personalData.fontSize * 0.45))
                .foregroundStyle(.orange)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { openNoteEditor(for: verse) }
                .onLongPressGesture { }
        }
    }

    private func toggleSelection(_ verse: Int) {
        if selectedVerses.contains(verse) {
            selectedVerses.remove(verse)
        } else {
            selectedVerses.insert(verse)
        }
    }

    /// Copies the selected verses as "Book Chapter:1, 3" + "1 text" lines.
    private func copySelectedVerses() {
        let sorted = selectedVerses.sorted()
        guard !sorted.isEmpty else { return }
        let ref = "\(history.bookTitle) \(history.chapter):\(verseListString(sorted))"
        let lines = sorted.compactMap { v -> String? in
            guard let text = verses.first(where: { $0.verse == v })?.text else { return nil }
            return "\(v) \(text)"
        }
        UIPasteboard.general.string = ([ref] + lines).joined(separator: "\n")
    }

    /// [1,2,3,5] -> "1-3, 5"
    private func verseListString(_ verses: [Int]) -> String {
        var parts: [String] = []
        var start = verses[0]
        var prev = verses[0]
        for v in verses.dropFirst() {
            if v == prev + 1 {
                prev = v
            } else {
                parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
                start = v
                prev = v
            }
        }
        parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
        return parts.joined(separator: ", ")
    }

    // MARK: - Verse notes

    private func noteKey(_ verse: Int) -> String {
        personalData.verseNoteKey(moduleID: history.module.id,
                                  testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter,
                                  verse: verse)
    }

    private func hasNote(verse: Int) -> Bool {
        personalData.verseNote(forKey: noteKey(verse)) != nil
    }

    private func openNoteEditor(for verse: Int) {
        noteVerse = verse
        noteDraft = personalData.verseNotes[noteKey(verse)] ?? ""
        showingNoteEditor = true
    }

    /// Notes from the selection bar anchor to the first selected verse,
    /// so a multi-verse note shows its icon only there.
    private func openNoteEditorForSelection() {
        guard let first = selectedVerses.min() else { return }
        openNoteEditor(for: first)
    }

    private func noteReference(_ verse: Int) -> String {
        "\(history.bookTitle) \(history.chapter):\(verse)"
    }

    /// A chapter note is a note from the first verse to the last;
    /// anchor it at the first verse like any multi-verse note.
    private func openChapterNoteEditor() {
        if let first = verses.first?.verse {
            openNoteEditor(for: first)
        }
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

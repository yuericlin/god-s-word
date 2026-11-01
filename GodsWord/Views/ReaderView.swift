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
    /// Section headings ("subtitles") by verse number (REQ-RS-5).
    @State private var headings: [Int: String] = [:]
    @State private var loadError: String?
    @State private var showingSettings = false
    @State private var showingFullSettings = false

    @State private var showingBookChapterPicker = false
    @State private var showingBookmarks = false
    /// The auxiliary panel starts collapsed (REQ-AP-1); its toggle is
    /// the arrow button in the bottom bar.
    @State private var panelCollapsed = true
    @State private var strongsKey: String?
    @State private var dwellTask: Task<Void, Never>?
    @State private var availableVersions: [BibleVersion] = []
    @State private var viewSize: CGSize = .zero
    /// Verse picker: tap a verse to select it (light sky blue highlight).
    /// Selection is by verse number, so it survives version changes.
    @State private var selectedVerses: Set<Int> = []
    @State private var noteEditorItem: NoteEditorItem?
    @State private var showingChapterNoteEditor = false
    @State private var showingCompare = false
    @State private var showingAssignBookmark = false
    /// A new, unsaved bookmark started in the Assign sheet; its editor opens
    /// once that sheet has closed (presenting two sheets at once is unreliable).
    @State private var pendingNewBookmark: Bookmark?
    @State private var bookmarkToEdit: Bookmark?

    /// Identifiable wrapper so the note sheet always opens with fresh data.
    private struct NoteEditorItem: Identifiable {
        let id: String   // the note key
        let verse: Int
        let reference: String
        let initialText: String
        /// Pre-fill for a note that doesn't exist yet (ignored otherwise).
        let seedText: String
    }

    /// Whether to render tappable Strong's numbers: the toggle is on and
    /// the current version carries Strong's data (SWORD versions only).
    private var useStrongs: Bool {
        personalData.showStrongs && history.version.supportsStrongs
    }

    private var chapterPickerSelection: Binding<Int> {
        Binding(get: { history.chapter }, set: { go(toChapter: $0) })
    }

    /// Binding for the version picker next to the book title. Keeps the same
    /// reference, clamped to the new version's chapter count.
    private var versionSelection: Binding<String> {
        Binding(
            get: { history.version.id },
            set: { newID in
                guard newID != history.version.id,
                      let v = availableVersions.first(where: { $0.id == newID }) else { return }
                history.version = v
                let count = history.chapterCount
                if history.chapter > count {
                    history.chapter = max(count, 1)
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            readerContent
            // Auxiliary panel below the reading panel: Notes / Commentary /
            // Strong's / Recents tabs (REQ-AP-1). It reads the same history
            // and the verse selection; the reading text above is untouched.
            // Collapsed (the default) it renders nothing — the toggle is
            // the arrow button in the bottom bar, next to the chapter
            // controls.
            AuxiliaryPanelView(history: history,
                               selectedVerses: selectedVerses,
                               availableVersions: availableVersions,
                               collapsed: $panelCollapsed)
        }
    }

    private var readerContent: some View {
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
                                            Group {
                                                if let heading = headings[v.verse] {
                                                    headingRow(heading)
                                                }
                                                Text(attributedVerseTokens(number: v.verse, tokens: v.tokens))
                                                    .font(.system(size: personalData.fontSize, design: .serif))
                                                    .lineSpacing(6)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    // Swallow long-press so the empty-area
                                                    // menu doesn't fire on text.
                                                    .onLongPressGesture { }
                                            }
                                        }
                                    } else {
                                        ForEach(verses, id: \.verse) { v in
                                            Group {
                                                if let heading = headings[v.verse] {
                                                    headingRow(heading)
                                                }
                                                Text(attributedVerse(number: v.verse, text: v.text))
                                                    .font(.system(size: personalData.fontSize, design: .serif))
                                                    .lineSpacing(6)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .onLongPressGesture { }
                                            }
                                        }
                                    }
                                } else {
                                    // Paragraph mode: no paragraph info in the modules,
                                    // so the whole chapter flows as one paragraph.
                                    Text(useStrongs ? attributedParagraphTokens() : attributedParagraph())
                                        .font(.system(size: personalData.fontSize, design: .serif))
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .onLongPressGesture { }
                                }
                            }
                            .padding()
                            // Long-press on empty reading area (margins, gaps)
                            // offers to take a chapter-level note.
                            .contextMenu {
                                Button("Take Notes") { openChapterNoteEditor() }
                                Button("Assign Bookmark") { showingAssignBookmark = true }
                            }
                        }
                        .onChange(of: history.chapter) { proxy.scrollTo("top", anchor: .top) }
                        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
                    }
                    .environment(\.openURL, OpenURLAction { url in
                        switch url.scheme {
                        case "strongs":
                            // Tapping a Strong's number opens its dictionary entry.
                            if let key = url.host, !key.isEmpty {
                                strongsKey = key
                                return .handled
                            }
                        case "verse":
                            // Tapping a verse's words toggles its selection.
                            if let host = url.host, let n = Int(host) {
                                toggleSelection(n)
                                return .handled
                            }
                        case "note":
                            // Tapping the note icon opens the verse's note.
                            if let host = url.host, let n = Int(host) {
                                openNoteEditor(for: n)
                                return .handled
                            }
                        default:
                            break
                        }
                        return .systemAction
                    })
                }
            }
            // Copy/Notes/Compare bar while verses are selected.
            if !selectedVerses.isEmpty {
                HStack(spacing: 24) {
                    Button("Copy") { copySelectedVerses() }
                    Button("Notes") { openNoteEditorForSelection() }
                    Button("Compare") { showingCompare = true }
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
                $0.isAt(testament: history.testament, book: history.book,
                        chapter: history.chapter)
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
                            ForEach(availableVersions, id: \.id) { v in
                                Text(v.shortLabel).tag(v.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(history.version.shortLabel)
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
                            Text("\(history.bookTitle) \(history.chapter)")
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button { turnChapter(by: -1) } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
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
                    Button { turnChapter(by: 1) } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    // Auxiliary panel toggle, next to the chapter
                    // controls (REQ-AP-1): an up arrow when the panel
                    // is collapsed, a down arrow when it is open.
                    Button { panelCollapsed.toggle() } label: {
                        Label(panelCollapsed ? "Show Panel" : "Hide Panel",
                              systemImage: panelCollapsed ? "chevron.up" : "chevron.down")
                    }
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
                        turnChapter(by: 1)
                    } else if value.translation.width > 60 {
                        turnChapter(by: -1)
                    }
                }
        )
        .task(id: chapterKey) { await load() }
        // Selection lives within a chapter: clear it when the location
        // changes, but keep it when only the version (module) changes.
        .onChange(of: history.testament) { selectedVerses = [] }
        .onChange(of: history.book) { selectedVerses = [] }
        .onChange(of: history.chapter) { selectedVerses = [] }
        .onAppear {
            availableVersions = allLibraryVersions()
            adoptReimportedVersion()
        }
        .onDisappear { dwellTask?.cancel() }
        .sheet(isPresented: $showingFullSettings) {
            SettingsView(history: history)
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
        .sheet(isPresented: $showingAssignBookmark, onDismiss: {
            if let created = pendingNewBookmark {
                bookmarkToEdit = created
                pendingNewBookmark = nil
            }
        }) {
            AssignBookmarkView(history: history,
                               onCreate: { pendingNewBookmark = $0 })
                .environmentObject(personalData)
        }
        .sheet(item: $bookmarkToEdit) { bookmark in
            BookmarkEditView(bookmark: bookmark, history: history)
                .environmentObject(personalData)
        }
        .sheet(isPresented: $showingCompare) {
            CompareView(current: history.version,
                        available: availableVersions,
                        testament: history.testament,
                        book: history.book,
                        chapter: history.chapter,
                        bookTitle: history.bookTitle,
                        selectedVerses: selectedVerses.sorted())
                .environmentObject(personalData)
        }
        .sheet(item: $noteEditorItem) { item in
            VerseNoteEditor(reference: item.reference,
                            noteKey: item.id,
                            initialText: item.initialText,
                            seedText: item.seedText,
                            sourceModuleID: history.version.id)
                .environmentObject(personalData)
        }
        .sheet(isPresented: $showingChapterNoteEditor) {
            ScopedNoteEditor(
                reference: "\(history.bookTitle) \(history.chapter)",
                initialText: personalData.chapterNote(forKey: currentChapterNoteKey) ?? ""
            ) { text in
                personalData.setChapterNote(text, forKey: currentChapterNoteKey,
                                            source: history.version.id)
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
                ReadingSettingsView(showStrongsOption: history.version.supportsStrongs)
                Spacer()
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
        "\(history.version.id)-\(history.testament)-\(history.book)-\(history.chapter)"
    }

    /// All versions known to the library (downloaded + private imports).
    private func allLibraryVersions() -> [BibleVersion] {
        BibleVersion.allInstalled(in: store)
    }

    /// A re-import replaces a private Bible's file on disk, but this reader
    /// renders the instance captured in `history` — without rebinding, the
    /// old text would stay on screen indefinitely (the chapter key does not
    /// change when only the file's contents do). On appear, adopt the
    /// freshly loaded instance for the current version id; if the displayed
    /// chapter's text changed, reload it. SWORD modules are immutable
    /// installs, so only private versions need this.
    private func adoptReimportedVersion() {
        guard let fresh = availableVersions.first(where: { $0.id == history.version.id }),
              fresh.isPrivate else { return }
        history.version = fresh
        // On first appear `verses` is still empty and the chapter task below
        // loads from the rebound instance; only an already-rendered chapter
        // needs the explicit comparison (and reload when it changed).
        guard !verses.isEmpty else { return }
        Task {
            let newVerses = (try? await fresh.loadChapter(
                testament: history.testament, book: history.book,
                chapter: history.chapter)) ?? []
            if newVerses.map({ $0.text }) != verses.map({ $0.text }) {
                await load()
            }
        }
    }

    private func canGo(toChapter c: Int) -> Bool {
        // Same-book check: the chapter menu's range, and the
        // in-book fast path of turnChapter (REQ-GS-1).
        c >= 1 && c <= history.chapterCount
    }

    private func go(toChapter c: Int) {
        guard canGo(toChapter: c) else { return }
        history.chapter = c
    }

    /// Chapter turn (REQ-GS-1), shared by the middle swipes and
    /// the bottom-bar arrows: inside the book it is
    /// go(toChapter:); at the book's edge it crosses into the
    /// adjacent book — forward from the last chapter to the next
    /// book's first chapter, backward from the first chapter to
    /// the previous book's last chapter — wrapping around the
    /// Bible (Revelation 22 -> Genesis 1, Genesis 1 -> Revelation
    /// 22). With the wrap, every chapter has a turn both ways,
    /// so the arrows are never disabled.
    private func turnChapter(by step: Int) {
        if canGo(toChapter: history.chapter + step) {
            go(toChapter: history.chapter + step)
            return
        }
        guard let adjacent = BookLocation.adjacentBook(
            testament: history.testament, book: history.book, step: step)
        else { return }
        if step > 0 {
            jumpTo(testament: adjacent.testament, book: adjacent.book, chapter: 1)
        } else {
            // Land on the previous book's last chapter; a probe
            // history reads that book's chapter count for the
            // current version (the pattern LibraryView uses when
            // it builds a reading in another book).
            let probe = ReadingHistory(version: history.version,
                                       testament: adjacent.testament,
                                       book: adjacent.book, chapter: 1)
            jumpTo(testament: adjacent.testament, book: adjacent.book,
                   chapter: max(probe.chapterCount, 1))
        }
    }

    /// Moves the reading to another book/chapter in place (the
    /// chapter picker's assignment order).
    private func jumpTo(testament t: Int, book b: Int, chapter c: Int) {
        history.testament = t
        history.book = b
        history.chapter = c
    }

    private func attributedVerse(number: Int, text: String) -> AttributedString {
        var out = attributedVerseNumber(number)
        if hasNote(verse: number) {
            // Yellow background highlights the verse number; tapping it opens the note.
            // (backgroundColor isn't overridden by link styling, unlike foregroundColor.)
            let numRange = out.startIndex..<out.endIndex
            out[numRange].backgroundColor = UIColor(red: 1.0, green: 0.9, blue: 0.45, alpha: 0.55)
            out[numRange].link = URL(string: "note://\(number)")
            out[numRange].underlineStyle = []
        }
        out += AttributedString(" ")
        out += AttributedString(text)
        // Invisible verse:// link makes the verse tappable for selection
        // without changing how it renders. Runs that already have a link
        // (verse number with a note) keep theirs.
        applyVerseLink(to: &out, verse: number)
        applySelectionHighlight(to: &out, verse: number)
        return out
    }

    /// A section heading ("subtitle", REQ-RS-5) as its own row in
    /// verse-by-verse mode: the reading serif, semibold.
    private func headingRow(_ heading: String) -> some View {
        Text(heading)
            .font(.system(size: personalData.fontSize, design: .serif).weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A section heading as a semibold run in paragraph mode.
    private func attributedHeading(_ heading: String) -> AttributedString {
        var run = AttributedString(heading)
        run.font = .system(size: personalData.fontSize, design: .serif).weight(.semibold)
        return run
    }

    /// Whole chapter as one flowing paragraph (paragraph mode). Verse numbers
    /// stay inline; verses are joined with spaces. A verse with a section
    /// heading starts a new line block: heading on its own line, then
    /// the verse (REQ-RS-5).
    private func attributedParagraph() -> AttributedString {
        var out = AttributedString("")
        for (i, v) in verses.enumerated() {
            if let heading = headings[v.verse] {
                if i > 0 { out += AttributedString("\n\n") }
                out += attributedHeading(heading)
                out += AttributedString("\n")
            } else if i > 0 { out += AttributedString(" ") }
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

    /// Verse text from segments, with Strong's numbers after the segment
    /// they belong to. Segments concatenate directly (they already carry
    /// their spacing); numbers render small and raised.
    private func attributedVerseTokens(number: Int, tokens: [WordToken]) -> AttributedString {
        var out = attributedVerseNumber(number)
        if hasNote(verse: number) {
            // Yellow background highlights the verse number; tapping it opens the note.
            let numRange = out.startIndex..<out.endIndex
            out[numRange].backgroundColor = UIColor(red: 1.0, green: 0.9, blue: 0.45, alpha: 0.55)
            out[numRange].link = URL(string: "note://\(number)")
            out[numRange].underlineStyle = []
        }
        out += AttributedString(" ")
        for token in tokens {
            out += AttributedString(token.text)
            for key in token.strongs {
                out += attributedStrongsNumber(key)
            }
        }
        // Verse link skips the Strong's numbers and the verse number (already linked).
        applyVerseLink(to: &out, verse: number)
        applySelectionHighlight(to: &out, verse: number)
        return out
    }

    /// Whole chapter as one flowing paragraph from word tokens.
    /// Section headings break the flow exactly as in
    /// `attributedParagraph()` (REQ-RS-5).
    private func attributedParagraphTokens() -> AttributedString {
        var out = AttributedString("")
        for (i, v) in verseTokens.enumerated() {
            if let heading = headings[v.verse] {
                if i > 0 { out += AttributedString("\n\n") }
                out += attributedHeading(heading)
                out += AttributedString("\n")
            } else if i > 0 { out += AttributedString(" ") }
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

    // MARK: - Verse picker (invisible links; rendering unchanged)

    /// Sets an invisible verse://N link on every run without one, so the
    /// verse is tappable for selection. Link styling is neutralized
    /// (no underline, normal colors) so rendering is pixel-identical.
    private func applyVerseLink(to attr: inout AttributedString, verse: Int) {
        let url = URL(string: "verse://\(verse)")
        struct Item { let range: Range<AttributedString.Index>; let hasColor: Bool }
        let items = attr.runs.compactMap { run -> Item? in
            guard run.link == nil else { return nil }
            return Item(range: run.range, hasColor: run.foregroundColor != nil)
        }
        for item in items {
            attr[item.range].link = url
            attr[item.range].underlineStyle = []
            if !item.hasColor {
                attr[item.range].foregroundColor = .primary
            }
        }
    }

    /// Light sky blue background on a selected verse.
    private func applySelectionHighlight(to attr: inout AttributedString, verse: Int) {
        guard selectedVerses.contains(verse) else { return }
        attr.backgroundColor = UIColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 0.55)
    }

    private func toggleSelection(_ verse: Int) {
        if selectedVerses.contains(verse) {
            selectedVerses.remove(verse)
        } else {
            selectedVerses.insert(verse)
        }
    }

    /// Copies the selected verses as "Book Chapter:1, 3" + "1 text" lines.
    /// The selected verses' text: a single verse plain, multiple verses
    /// numbered ("1 text 2 text").
    private func selectionVerseText() -> String {
        let sorted = selectedVerses.sorted()
        let single = sorted.count == 1
        let parts = sorted.compactMap { v -> String? in
            guard let text = verses.first(where: { $0.verse == v })?.text else { return nil }
            return single ? text : "\(v) \(text)"
        }
        return parts.joined(separator: " ")
    }

    /// The clipboard format for the current selection:
    /// "\"verse text\" Book Chapter:Verses Version". Copy uses it
    /// verbatim; a new note is seeded with it (plus a newline).
    private func selectionClipboardString() -> String {
        let sorted = selectedVerses.sorted()
        let ref = "\(history.bookTitle) \(history.chapter):\(verseListString(sorted))"
        return "\"\(selectionVerseText())\" \(ref) \(history.version.id)"
    }

    private func copySelectedVerses() {
        guard !selectedVerses.isEmpty else { return }
        UIPasteboard.general.string = selectionClipboardString()
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
        personalData.verseNoteKey(testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter,
                                  verse: verse)
    }

    private func hasNote(verse: Int) -> Bool {
        personalData.verseNote(forKey: noteKey(verse)) != nil
    }

    private func openNoteEditor(for verse: Int) {
        let key = noteKey(verse)
        noteEditorItem = NoteEditorItem(
            id: key,
            verse: verse,
            reference: noteReference(verse),
            initialText: personalData.verseNote(forKey: key) ?? "",
            seedText: "\(history.bookTitle) \(history.chapter)\n")
    }

    /// Notes from the selection bar anchor to the first selected verse,
    /// so a multi-verse note shows its icon only there. A new note is
    /// seeded with the selection in the clipboard format.
    private func openNoteEditorForSelection() {
        guard let first = selectedVerses.min() else { return }
        let key = noteKey(first)
        noteEditorItem = NoteEditorItem(
            id: key,
            verse: first,
            reference: noteReference(first),
            initialText: personalData.verseNote(forKey: key) ?? "",
            seedText: selectionClipboardString() + "\n")
    }

    private func noteReference(_ verse: Int) -> String {
        "\(history.bookTitle) \(history.chapter):\(verse)"
    }

    /// The storage key of the current chapter's chapter-level note
    /// (REQ-NT-14).
    private var currentChapterNoteKey: String {
        personalData.chapterNoteKey(testament: history.testament,
                                    book: history.book,
                                    chapter: history.chapter)
    }

    /// A chapter note is scoped to the whole chapter (REQ-NT-14): it
    /// lives in the chapter-notes store, not on any verse.
    private func openChapterNoteEditor() {
        showingChapterNoteEditor = true
    }

    private func load() async {
        loadError = nil
        dwellTask?.cancel()
        do {
            let rendered = try await history.version.loadChapter(
                testament: history.testament, book: history.book,
                chapter: history.chapter)
            guard !rendered.isEmpty else {
                loadError = "This chapter has no text in this version."
                return
            }
            verses = rendered
            verseTokens = await history.version.loadTokens(
                testament: history.testament, book: history.book,
                chapter: history.chapter)
            headings = await history.version.loadHeadings(
                testament: history.testament, book: history.book,
                chapter: history.chapter)
            personalData.savePosition(ReadingPosition(testament: history.testament,
                                                      book: history.book,
                                                      chapter: history.chapter),
                                      for: history.version.id)
            personalData.saveLastReading(moduleID: history.version.id,
                                          testament: history.testament,
                                          book: history.book,
                                          chapter: history.chapter)
            if history.dwellMode {
                // Bookmark jump: record only after a 60-second dwell.
                // Turning chapters restarts the timer; quick flips are skipped.
                startDwellTimer(for: chapterKey)
            } else {
                personalData.recordHistory(moduleID: history.version.id,
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
                personalData.recordHistory(moduleID: history.version.id,
                                            bookName: history.bookTitle,
                                            testament: history.testament,
                                            book: history.book,
                                            chapter: history.chapter)
                history.dwellMode = false
            }
        }
    }
}

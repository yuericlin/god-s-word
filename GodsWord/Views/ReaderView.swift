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
    /// Jesus-speech character spans by verse number (REQ-RL-1);
    /// empty for versions whose module carries no speech tags.
    @State private var jesusSpans: [Int: [(start: Int, end: Int)]] = [:]
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
    /// The reader's frame in window coordinates. The swipe observer
    /// reports window coordinates; this is what converts them into
    /// the reader's own start zones (REQ-GS-2).
    @State private var readerFrame: CGRect = .zero
    /// This view's total height, measured on the root VStack and passed
    /// to the auxiliary panel: the expanded panel is 30% of it.
    @State private var rootHeight: CGFloat = 0
    @State private var bottomRowWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var bottomIconSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var bottomRowHeight: CGFloat = 28
    /// Verse picker: tap a verse to select it (light sky blue highlight).
    /// Selection is by verse number, so it survives version changes.
    @State private var selectedVerses: Set<Int> = []
    /// Verse a note jump wants scrolled into view (REQ-NT-21).
    @State private var scrollTargetVerse: Int? = nil
    /// chapterKey of the chapter actually on screen (set when a
    /// load completes), so a same-chapter verse jump lands at
    /// once while a chapter-changing one waits for its load.
    @State private var loadedChapterKey = ""
    @State private var noteEditorItem: NoteEditorItem?
    @State private var showingChapterNoteEditor = false
    @State private var showingCompare = false
    @State private var showingAssignBookmark = false
    /// The verse the Assign sheet targets: nil for a chapter
    /// target (the long-press menu), the single selected verse
    /// for the selection bar's Bookmark action (REQ-BM-13).
    @State private var assignVerse: Int?
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
            // Strong's / Recents / Highlights tabs (REQ-AP-1). It reads the same history
            // and the verse selection; the reading text above is untouched.
            // Collapsed (the default) it renders nothing — the toggle is
            // the arrow button in the bottom bar, next to the chapter
            // controls.
            AuxiliaryPanelView(history: history,
                               selectedVerses: selectedVerses,
                               availableVersions: availableVersions,
                               collapsed: $panelCollapsed,
                               totalHeight: rootHeight)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { rootHeight = $0 }
        // The swipe guard (EdgeNavigation) is permanent; the
        // reader arms its handler while it is on screen and
        // clears it when it leaves, so reports never reach a
        // reader that is not there. (On the body, not on
        // readerContent: that expression is at the type
        // checker's limit already.)
        .onAppear { SwipeBackGuard.shared.onSwipe = handleReaderSwipe }
        .onDisappear { SwipeBackGuard.shared.onSwipe = nil }
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
                                                    .id("v\(v.verse)")
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
                                                    .id("v\(v.verse)")
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
                                        // Invisible ladder of 20 equal slices
                                        // spanning the chapter text's height:
                                        // the approximate scroll targets for
                                        // verse jumps in paragraph mode.
                                        .background {
                                            GeometryReader { geo in
                                                VStack(spacing: 0) {
                                                    ForEach(0..<20, id: \.self) { i in
                                                        Color.clear
                                                            .id("frac-\(i)")
                                                    }
                                                }
                                                .frame(height: geo.size.height)
                                                .allowsHitTesting(false)
                                            }
                                        }
                                }
                            }
                            .padding()
                            // Long-press on empty reading area (margins, gaps)
                            // offers to take a chapter-level note.
                            .contextMenu {
                                Button { openChapterNoteEditor() } label: {
                                    Label("Add Note", systemImage: "square.and.pencil")
                                }
                                Button {
                                    assignVerse = nil
                                    showingAssignBookmark = true
                                } label: {
                                    Label("Assign Bookmark", systemImage: "bookmark")
                                }
                            }
                        }
                        .onChange(of: history.chapter) { proxy.scrollTo("top", anchor: .top) }
                        .onChange(of: scrollTargetVerse) {
                            guard let target = scrollTargetVerse else { return }
                            scrollTargetVerse = nil
                            if personalData.verseByVerse {
                                proxy.scrollTo("v\(target)", anchor: .center)
                            } else if let i = paragraphAnchorIndex(for: target) {
                                // Paragraph mode has no per-verse anchors:
                                // scroll to the ladder slice at the verse's
                                // share of the chapter's text (REQ-NT-21).
                                proxy.scrollTo("frac-\(i)", anchor: .center)
                            }
                        }
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
            // Ribbons for the bookmarks pointing at the chapter
            // being read (REQ-BM-3) — chapter-level and verse-level
            // alike; every bookmark shows at the top-right corner.
            // Nothing shows when the current chapter has none.
            let currentMarks = personalData.bookmarks.filter {
                $0.isAt(testament: history.testament,
                        book: history.book,
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
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { readerFrame = $0 }
        .background(ReaderSwipeGesture(onSwipe: handleReaderSwipe).frame(width: 0, height: 0))
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
        }
        .safeAreaInset(edge: .bottom) {
            bottomControl
        }
        // Reader swipes are decided by handleReaderSwipe from the
        // swipe observer in the background above (REQ-GS-2) — not by
        // a SwiftUI drag gesture, whose reported start location
        // proved unreliable on device.
        .task(id: chapterKey) {
            await load()
            applyPendingVerse()
        }
        // Selection lives within a chapter: clear it when the location
        // changes, but keep it when only the version (module) changes.
        .onChange(of: history.testament) { selectedVerses = [] }
        .onChange(of: history.book) { selectedVerses = [] }
        .onChange(of: history.chapter) { selectedVerses = [] }
        // A verse-note jump to the chapter already on screen lands
        // at once; a chapter-changing jump is applied by the load
        // task above instead (REQ-NT-21).
        .onChange(of: history.pendingVerse) {
            if history.pendingVerse != nil,
               loadedChapterKey == chapterKey {
                applyPendingVerse()
            }
        }
        .onAppear {
            availableVersions = allLibraryVersions()
            adoptReimportedVersion()
        }
        .onDisappear { dwellTask?.cancel() }
        .sheet(isPresented: $showingFullSettings, onDismiss: {
            // Downloads and deletions inside Settings change the
            // library; the version picker reads the snapshot taken
            // when the reader appeared, so take a fresh one.
            availableVersions = allLibraryVersions()
            adoptReimportedVersion()
        }) {
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
            AssignBookmarkView(history: history, verse: assignVerse,
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
                            sourceModuleID: history.version.id,
                            onJump: {
                                if let p = NoteKey.parse(item.id) {
                                    history.testament = p.testament
                                    history.book = p.book
                                    history.chapter = p.chapter
                                    history.pendingVerse = p.verse
                                }
                            })
                .environmentObject(personalData)
        }
        .sheet(isPresented: $showingChapterNoteEditor) {
            ScopedNoteEditor(
                reference: "\(history.bookTitle) \(history.chapter)",
                initialText: personalData.chapterNote(forKey: currentChapterNoteKey) ?? "",
                onJump: {}
            ) { text in
                personalData.setChapterNote(text, forKey: currentChapterNoteKey,
                                            source: history.version.id)
            }
        }
    }

    /// One decision for every reader swipe (REQ-GS-2), fed by the
    /// UIKit swipe observer: `start` is the touch's start point in
    /// window coordinates — where the finger actually landed — and
    /// converting it into the reader's frame is what keeps a middle
    /// swipe out of the drawer's 20pt zone. Swipes starting on the
    /// bottom control (the reader's bottom 80pt) scroll its row;
    /// they never turn chapters, and swipes starting outside the
    /// reader (the auxiliary panel, the navigation bar) are not
    /// reader swipes at all.
    private func handleReaderSwipe(start: CGPoint, translation: CGSize) {
        guard !showingSettings && !showingBookmarks else { return }
        guard readerFrame.width > 0 else { return }
        let localX = start.x - readerFrame.minX
        let localY = start.y - readerFrame.minY
        guard localX >= 0, localX <= readerFrame.width,
              localY >= 0, localY < readerFrame.height - 80
        else { return }
        switch ReaderSwipeZones.action(
            startX: localX,
            viewWidth: readerFrame.width,
            translationWidth: translation.width,
            translationHeight: translation.height)
        {
        case .openDrawer:
            showingSettings = true
        case .turnChapter(let forward):
            turnChapter(by: forward ? 1 : -1)
        case .none:
            break
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
        applyRedLetters(to: &out, verse: number)
        applyHighlight(to: &out, verse: number)
        applyRedLetterHighlight(to: &out, verse: number)
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
        num.foregroundColor = .blue
        num.baselineOffset = personalData.fontSize * 0.22
        num.underlineStyle = .single
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
        // Character ranges of the Jesus-speech tokens, for the
        // blue-gray highlight background (REQ-HL-2): the Strong's
        // numbers interspersed below shift the plain-text span
        // coordinates, so the ranges are tracked as the string is
        // built instead of read from jesusSpans.
        var jesusRanges: [(start: Int, end: Int)] = []
        var cursor = out.characters.count
        for token in tokens {
            var seg = AttributedString(token.text)
            if personalData.showRedLetters, token.isJesusSpeech {
                seg.foregroundColor = Self.redLetterColor
                seg.font = .system(size: personalData.fontSize, design: .serif).weight(.bold)
                jesusRanges.append((start: cursor,
                                    end: cursor + token.text.count))
            }
            out += seg
            cursor += token.text.count
            for key in token.strongs {
                out += attributedStrongsNumber(key)
                cursor += " \(key)".count
            }
        }
        // Verse link skips the Strong's numbers and the verse number (already linked).
        applyVerseLink(to: &out, verse: number)
        applyHighlight(to: &out, verse: number)
        if highlightedInChapter.contains(number) {
            for range in jesusRanges {
                guard range.start < range.end,
                      range.end <= out.characters.count else { continue }
                let r = out.index(out.startIndex, offsetByCharacters: range.start)
                    ..< out.index(out.startIndex, offsetByCharacters: range.end)
                out[r].backgroundColor = Self.redLetterHighlightColor
            }
        }
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

    /// The verses of the chapter being read that carry a
    /// highlight — made in any version (REQ-HL-2).
    private var highlightedInChapter: Set<Int> {
        personalData.highlightedVerses(testament: history.testament,
                                       book: history.book,
                                       chapter: history.chapter)
    }

    /// Red-letter color (REQ-RL-3): the classic deep red on light
    /// backgrounds, brighter on dark so it stays readable.
    private static let redLetterColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.42, blue: 0.36, alpha: 1)
            : UIColor(red: 0.76, green: 0.09, blue: 0.07, alpha: 1)
    })

    /// Background for Jesus's words inside a highlighted verse
    /// (REQ-HL-2): a blue-gray instead of the verse's bright
    /// yellow — red on that yellow is low-contrast. Light on
    /// light backgrounds, deeper on dark, in the same dynamic
    /// pattern as redLetterColor.
    private static let redLetterHighlightColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.23, blue: 0.38, alpha: 0.95)
            : UIColor(red: 0.78, green: 0.86, blue: 0.99, alpha: 0.9)
    }

    /// Paints the verse's Jesus-speech spans red and bold
    /// (REQ-RL-3). Spans are character offsets into the verse text;
    /// the number prefix is skipped exactly as in applyHighlight.
    /// No-op when the setting is off or the version's module
    /// carries no speech tags for the verse (REQ-RL-1).
    private func applyRedLetters(to attr: inout AttributedString, verse: Int) {
        guard personalData.showRedLetters, let spans = jesusSpans[verse] else { return }
        let prefix = "\(verse) ".count + 1
        for span in spans {
            let start = prefix + span.start
            let end = prefix + span.end
            guard start < end, end <= attr.characters.count else { continue }
            let r = attr.index(attr.startIndex, offsetByCharacters: start)
                ..< attr.index(attr.startIndex, offsetByCharacters: end)
            attr[r].foregroundColor = Self.redLetterColor
            attr[r].font = .system(size: personalData.fontSize, design: .serif).weight(.bold)
        }
    }

    /// Bright yellow background on a highlighted verse's text
    /// (REQ-HL-2). The verse number keeps its own styling, so a
    /// note's pale-yellow number stays visible; the selection's
    /// sky blue, applied after this, covers the yellow while the
    /// verse is selected.
    private func applyHighlight(to attr: inout AttributedString, verse: Int) {
        guard highlightedInChapter.contains(verse) else { return }
        // Skip the number run ("\(verse) ") and the space after it:
        // the highlight belongs to the verse's text.
        let prefix = "\(verse) ".count + 1
        guard attr.characters.count > prefix else { return }
        let start = attr.index(attr.startIndex, offsetByCharacters: prefix)
        attr[start ..< attr.endIndex].backgroundColor =
            UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 0.65)
    }

    /// Repaints the background of a highlighted verse's
    /// Jesus-speech spans with redLetterHighlightColor (REQ-HL-2),
    /// over the yellow applyHighlight laid down. Same span
    /// coordinates applyRedLetters uses. No-op when the verse is
    /// not highlighted, red letters are off, or the verse carries
    /// no speech spans.
    private func applyRedLetterHighlight(to attr: inout AttributedString, verse: Int) {
        guard highlightedInChapter.contains(verse),
              personalData.showRedLetters,
              let spans = jesusSpans[verse] else { return }
        let prefix = "\(verse) ".count + 1
        for span in spans {
            let start = prefix + span.start
            let end = prefix + span.end
            guard start < end, end <= attr.characters.count else { continue }
            let r = attr.index(attr.startIndex, offsetByCharacters: start)
                ..< attr.index(attr.startIndex, offsetByCharacters: end)
            attr[r].backgroundColor = Self.redLetterHighlightColor
        }
    }

    /// The selection bar's Marker action (REQ-HL-1): records
    /// the selected verses as highlights made in the version
    /// being read, then clears the selection so the yellow shows.
    private func highlightSelection() {
        personalData.addHighlight(testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter,
                                  verses: selectedVerses,
                                  version: history.version.id)
        selectedVerses = []
    }

    /// Whether every selected verse already carries a highlight:
    /// the bar's Marker then removes instead of adding (the
    /// label stays "Marker" in both states, REQ-HL-1).
    private var selectionFullyHighlighted: Bool {
        !selectedVerses.isEmpty
            && selectedVerses.isSubset(of: highlightedInChapter)
    }

    /// The selection bar's Marker action on a fully highlighted
    /// selection (REQ-HL-1): removes
    /// the selected verses from the chapter's highlights — spans
    /// shrink or split as needed — then clears the selection.
    private func unhighlightSelection() {
        personalData.removeHighlight(testament: history.testament,
                                     book: history.book,
                                     chapter: history.chapter,
                                     verses: selectedVerses)
        selectedVerses = []
    }

    /// The target of the selection bar's Bookmark action
    /// (REQ-BM-13): the single selected verse, or nil — the
    /// chapter as a whole — for a multi-verse selection.
    private var selectionTargetVerse: Int? {
        selectedVerses.count == 1 ? selectedVerses.first : nil
    }

    /// Whether a bookmark already sits exactly at the selection's
    /// target: tapping the bar's Bookmark then removes it (the
    /// label stays "Bookmark" in both states).
    private var selectionBookmarked: Bool {
        personalData.bookmarks.contains {
            $0.isAt(testament: history.testament, book: history.book,
                    chapter: history.chapter, verse: selectionTargetVerse)
        }
    }

    /// The selection bar's Bookmark action on an already
    /// bookmarked target (REQ-BM-13): deletes the bookmark(s)
    /// there, then clears the selection (mirrors Marker's
    /// removal tap).
    private func unmarkSelection() {
        for mark in personalData.bookmarks where
            mark.isAt(testament: history.testament, book: history.book,
                      chapter: history.chapter,
                      verse: selectionTargetVerse) {
            personalData.deleteBookmark(mark)
        }
        selectedVerses = []
    }

    /// The bottom control: the chapter navigation and — while
    /// verses are selected — the selection actions, all in ONE
    /// horizontally scrollable row inside a capsule (Nov 9,
    /// 2026). It replaces the system bottom toolbar, whose
    /// height and scrolling iOS owns (a second row spilled out
    /// of it, and it cannot scroll): as a custom safe-area inset
    /// the row holds every control at once and scrolls the
    /// overflow. When a selection appears, the row scrolls the
    /// actions into view. The capsule hugs the row's width —
    /// measured as the row lays out and capped at the screen
    /// width — so an unselected chapter shows a small centered
    /// pill instead of a full-width bar with empty space. Its
    /// ultra-thin-material background is drawn at 75% opacity,
    /// because the material alone still reads as a solid bar
    /// over the page, while full transparency left the controls
    /// with too little contrast against the text showing
    /// through. The capsule does not change height when the
    /// selection actions appear — the row height is constant
    /// for a given Text Size — and the icons and row height
    /// scale with the phone's Text Size via ScaledMetric
    /// (19pt icons in a 28pt row at the default size), not
    /// hard-coded constants (Nov 9, 2026).
    private var bottomControl: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    Button { turnChapter(by: -1) } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .labelStyle(.iconOnly)
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
                            // The buttons' accent blue, a little
                            // dimmer (Nov 9, 2026) — the secondary
                            // gray washed out against the text
                            // showing through the capsule. The
                            // chapter numbers use the callout
                            // style — 16pt at the default Text
                            // Size, up from caption — and, like
                            // caption, it scales with the phone's
                            // Text Size rather than a hard-coded
                            // number.
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.accentColor.opacity(0.75))
                        }
                    } else {
                        Text("\(history.chapter) / \(history.chapterCount)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.accentColor.opacity(0.75))
                    }
                    Button { turnChapter(by: 1) } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .labelStyle(.iconOnly)
                    // Auxiliary panel toggle, next to the chapter
                    // controls (REQ-AP-1): an up arrow when the panel
                    // is collapsed, a down arrow when it is open.
                    Button { panelCollapsed.toggle() } label: {
                        Label(panelCollapsed ? "Show Panel" : "Hide Panel",
                              systemImage: panelCollapsed ? "chevron.up" : "chevron.down")
                    }
                    .labelStyle(.iconOnly)
                    if !selectedVerses.isEmpty {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 1, height: bottomRowHeight * 22 / 28)
                        selectionActionButtons
                            .id("selectionActions")
                    }
                }
                .font(.system(size: bottomIconSize))
                .frame(height: bottomRowHeight)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) {
                    bottomRowWidth = $0
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .frame(width: bottomCapsuleWidth)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
            .padding(.top, 6)
            .padding(.bottom, 6)
            .onChange(of: selectedVerses.isEmpty) {
                if !selectedVerses.isEmpty {
                    withAnimation {
                        proxy.scrollTo("selectionActions", anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: selectedVerses.isEmpty)
    }

    /// The capsule's width: the row's measured width plus its
    /// horizontal padding (18 + 18), capped at the screen width
    /// minus margins — the capsule hugs its content and only
    /// stops growing at the point where the row must scroll.
    /// Nil until the row has been measured (no constraint).
    private var bottomCapsuleWidth: CGFloat? {
        guard bottomRowWidth > 0, viewSize.width > 0 else { return nil }
        return min(bottomRowWidth + 36, viewSize.width - 24)
    }

    /// The selection action buttons (Copy / Bookmark / Marker /
    /// Note / Compare / Close) as a fragment of the bottom
    /// control's row. Icon-only — state is carried by the
    /// glyphs: a filled bookmark when a bookmark already sits at
    /// the selection's target, a yellow highlighter when every
    /// selected verse already carries a highlight. Tapping
    /// toggles, exactly as the old text bar did; VoiceOver keeps
    /// the actions' names.
    @ViewBuilder
    private var selectionActionButtons: some View {

        Button { copySelectedVerses() } label: {
            Image(systemName: "square.on.square")
        }
        .accessibilityLabel("Copy")
        if selectionBookmarked {
            Button { unmarkSelection() } label: {
                Image(systemName: "bookmark.fill")
            }
            .accessibilityLabel("Bookmark")
        } else {
            Button {
                assignVerse = selectionTargetVerse
                showingAssignBookmark = true
            } label: {
                Image(systemName: "bookmark")
            }
            .accessibilityLabel("Bookmark")
        }
        if selectionFullyHighlighted {
            Button { unhighlightSelection() } label: {
                Image(systemName: "highlighter")
                    .foregroundStyle(Color.yellow)
            }
            .accessibilityLabel("Marker")
        } else {
            Button { highlightSelection() } label: {
                Image(systemName: "highlighter")
            }
            .accessibilityLabel("Marker")
        }
        Button { openNoteEditorForSelection() } label: {
            Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel("Note")
        Button { showingCompare = true } label: {
            Image(systemName: "rectangle.split.2x1")
        }
        .accessibilityLabel("Compare")
        Button { selectedVerses = [] } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
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
            jesusSpans = await history.version.loadJesusSpans(
                testament: history.testament, book: history.book,
                chapter: history.chapter)
            headings = await history.version.loadHeadings(
                testament: history.testament, book: history.book,
                chapter: history.chapter)
            loadedChapterKey = chapterKey
            personalData.savePosition(ReadingPosition(testament: history.testament,
                                                      book: history.book,
                                                      chapter: history.chapter),
                                      for: history.version.id)
            personalData.saveLastReading(moduleID: history.version.id,
                                          testament: history.testament,
                                          book: history.book,
                                          chapter: history.chapter)
            // Recents records a chapter only after it has been
            // read for 60 seconds (REQ-HI-1): the dwell timer
            // records the visit if the user is still on this
            // chapter when it fires, and turning chapters restarts
            // it, so chapters flipped through quickly are never
            // recorded. Bookmark jumps follow the same rule
            // (REQ-HI-6).
            startDwellTimer(for: chapterKey)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// The ladder slice (of 20) at a verse's share of the
    /// chapter's text length — the approximate scroll target for
    /// a verse jump in paragraph mode (REQ-NT-21). Nil when the
    /// verse isn't in the loaded chapter.
    private func paragraphAnchorIndex(for verse: Int) -> Int? {
        guard verses.contains(where: { $0.verse == verse }) else { return nil }
        var total = 0
        var before = 0
        for v in verses {
            if v.verse < verse { before += v.text.count }
            total += v.text.count
        }
        guard total > 0 else { return nil }
        return min(19, Int(Double(before) / Double(total) * 20))
    }

    /// Lands a verse-note jump (REQ-NT-21) once its chapter is on
    /// screen: select the verse and arm the scroll to it.
    private func applyPendingVerse() {
        guard let verse = history.pendingVerse else { return }
        history.pendingVerse = nil
        selectedVerses = [verse]
        scrollTargetVerse = verse
    }

    /// Records a history entry only if the user is still on the
    /// same chapter after 60 seconds (REQ-HI-1's reading-time
    /// rule), then leaves dwell mode.
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

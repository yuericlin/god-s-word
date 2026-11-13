// AuxiliaryPanelView.swift — the panel below the reading panel.
// Six tabs: Notes, Commentary, the selected verse rendered with
// Strong's numbers, Recents (the reading history), Highlights,
// and Parallel — a second chapter view, synced to the reading
// or independent of it (REQ-PA).
// The Notes tab
// has Recents / Book / Chapter / Verse sub-tabs (REQ-NT-18) over the
// scoped notes (REQ-NT-14); Commentary has Book / Chapter / Verse
// sub-tabs (REQ-AP-1..11) showing the entries at those scopes.
//
// The panel never alters the main reading text; it only reads the
// shared ReadingHistory, the verse selection, and PersonalData.

import SwiftUI
import UIKit
import SwordReader

/// The channel between the main reading view and the panel's
/// parallel view while sync mode is live (REQ-PA-2): the verse
/// both views keep at their top, and which side moved last — a
/// side scrolls programmatically only when the OTHER side set
/// the anchor, so the two never chase each other around.
/// Owned by ReaderView and passed to the panel; the panel
/// turns `active` on only while its Parallel tab is showing
/// in sync mode.
@Observable
final class ParallelSyncState {
    var anchorVerse: Int = 1
    var lastMovedByMain: Bool = true
    var active: Bool = false
}

/// A book/chapter location for the parallel view.
struct ParallelTarget: Equatable {
    var testament: Int
    var book: Int
    var chapter: Int

    /// 0-based index across the whole Bible (0–65).
    var overall: Int {
        testament == 1 ? book - 1 : 39 + book - 1
    }

    init(testament: Int, book: Int, chapter: Int) {
        self.testament = testament
        self.book = book
        self.chapter = chapter
    }

    init(overall: Int, chapter: Int) {
        if overall < 39 {
            testament = 1
            book = overall + 1
        } else {
            testament = 2
            book = overall - 39 + 1
        }
        self.chapter = chapter
    }
}

/// What the parallel settings sheet is doing (REQ-PA-4).
enum ParallelSettingsKind: Identifiable {
    /// Gear in sync mode: the sync version only.
    case syncVersion
    /// Gear in separate mode: version, book, and chapter.
    case separate
    /// Chain in sync mode: separate's settings; Done switches
    /// to separate mode with them applied.
    case toSeparate
    /// Chain in separate mode: the sync version; book and
    /// chapter are the main view's and cannot be changed.
    case toSync

    var id: String { "\(self)" }
}

/// Verse number -> the verse row's top edge in the reporting
/// scroll view's coordinate space. Both the reader and the
/// parallel view report through it while sync is live, to find
/// the topmost visible verse (REQ-PA-2).
struct VerseTopFramesKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat],
                       nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The reading text's scroll fraction (0...1), reported in
/// paragraph mode, where there are no per-verse rows (REQ-PA-2).
struct ScrollFractionKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: Double? = nil
    static func reduce(value: inout Double?, nextValue: () -> Double?) {
        if let next = nextValue() { value = next }
    }
}

/// The topmost visible verse from reported row tops: the last
/// verse whose top has reached `threshold` (just past the
/// scroll view's top padding), or the first verse when none has.
func topVisibleVerse(frames: [Int: CGFloat], threshold: CGFloat) -> Int? {
    let sorted = frames.sorted { $0.value < $1.value }
    var top: Int? = nil
    for (verse, minY) in sorted {
        if minY <= threshold {
            top = verse
        } else {
            break
        }
    }
    return top ?? sorted.first?.key
}

/// A reading text's scroll fraction from its frame in the
/// scroll view's coordinate space (the text is padded by
/// `inset` within the scroll content).
func scrollFraction(frame: CGRect, viewportHeight: CGFloat,
                    inset: CGFloat = 16) -> Double {
    let scrollable = frame.height + inset * 2 - viewportHeight
    guard scrollable > 0 else { return 0 }
    let offset = max(0, inset - frame.minY)
    return min(1, Double(offset / scrollable))
}

/// Reports a verse row's top edge in the named scroll space
/// while sync is live (REQ-PA-2); inert otherwise, so a view
/// that isn't syncing pays nothing for it.
struct VerseTopReporter: ViewModifier {
    let verse: Int
    let space: String
    let enabled: Bool

    func body(content: Content) -> some View {
        content.background {
            if enabled {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: VerseTopFramesKey.self,
                        value: [verse: geo.frame(in: .named(space)).minY])
                }
            }
        }
    }
}

extension View {
    /// See VerseTopReporter.
    func reportVerseTop(_ verse: Int, space: String, enabled: Bool) -> some View {
        modifier(VerseTopReporter(verse: verse, space: space, enabled: enabled))
    }
}

struct AuxiliaryPanelView: View {
    let history: ReadingHistory
    /// Verses selected in the reader; the Verse scopes anchor at the
    /// lowest selected verse (verse 1 when nothing is selected).
    let selectedVerses: Set<Int>
    /// All installed Bible versions (for the Strong's source resolution).
    let availableVersions: [BibleVersion]
    /// The sync channel to the reader's main view (REQ-PA-2),
    /// owned by ReaderView.
    let parallelSync: ParallelSyncState
    /// Owned by ReaderView: the toggle button lives in the reader's
    /// bottom bar, next to the chapter controls (REQ-AP-1). When
    /// collapsed, the panel renders nothing at all.
    @Binding var collapsed: Bool
    /// The reader view's total height, passed by ReaderView: the
    /// expanded panel — tab bar plus content — is 30% of it.
    /// Zero until ReaderView's first measurement lands (and in
    /// previews), where the content keeps its old fixed height.
    var totalHeight: CGFloat = 0

    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store
    @State private var tab: PanelTab = .notes
    @State private var notesSubTab: NotesSubTab = .recents
    @State private var commentaryScope: PanelScope = .verse
    @State private var editorItem: EditorItem?
    @State private var commentaries: [CommentaryModule] = []
    @State private var showingCommentaryDownload = false
    @State private var showingCommentaryInfo = false
    @State private var commentaryChapter: [CommentaryGrouping.Entry] = []
    @State private var commentaryBook: [BookSection] = []
    /// Reference segments (REQ-AP-19) for the chapter scope's
    /// grouped entries, keyed by the entry's start verse.
    @State private var commentarySegments: [Int: [ScriptureReferences.Segment]] = [:]
    /// Book scope: chapter -> start verse -> reference segments.
    @State private var commentaryBookSegments: [Int: [Int: [ScriptureReferences.Segment]]] = [:]
    /// A chapter to show in the reference chapter sheet
    /// (REQ-AP-20): a tapped commentary reference, Recents
    /// entry, or highlight.
    @State private var referenceLink: ReferenceLink?
    /// Parallel tab: the settings sheet being shown (REQ-PA-4).
    @State private var parallelSettings: ParallelSettingsKind?
    /// Parallel tab, separate mode: the session's target —
    /// frozen from the chapter being read when separate mode
    /// is first shown, then owned by its settings (REQ-PA-3).
    /// Deliberately not persisted (REQ-PA-5).
    @State private var parallelSepTarget: ParallelTarget?

    /// Identifiable wrapper around a chapter to show in the
    /// reference chapter sheet (REQ-AP-20): the target, the
    /// version to show it in, and what the sheet's Read More
    /// button does — each opener decides. A commentary
    /// reference reads in the version being read; a Recents
    /// entry in its own version, its Read More performing the
    /// version-switching jump a tap used to do directly; a
    /// highlight in the version being read, its verses
    /// selected.
    private struct ReferenceLink: Identifiable {
        let version: BibleVersion
        let target: ScriptureReferenceTarget
        let onReadChapter: () -> Void
        var id: String {
            "\(version.id)-\(target.testament)-\(target.book)-\(target.chapter)-"
                + target.verses.map(String.init).joined(separator: ",")
        }
    }

    /// One chapter's grouped commentary entries, for the Book scope.
    private struct BookSection: Identifiable {
        let chapter: Int
        let entries: [CommentaryGrouping.Entry]
        var id: Int { chapter }
    }
    @State private var commentaryLoading = false
    @State private var commentaryError: String?
    @State private var expandedBookChapters: Set<Int> = []
    @State private var strongsTokens: [WordToken] = []
    @State private var strongsLoadedKey = ""
    @State private var strongsDefKey: String?
    @State private var highlightsSubTab: HighlightsSubTab = .recents
    /// Measured height of the tab bar, so the content can take the
    /// rest of the panel's 30% of the total height.
    @State private var tabBarHeight: CGFloat = 49

    enum PanelTab: String, CaseIterable {
        case notes = "Notes"
        case commentary = "Commentary"
        case strongs = "Strong's"
        case recents = "Recents"
        case highlights = "Highlights"
        case parallel = "Parallel"
    }

    enum PanelScope: String, CaseIterable {
        case book = "Book"
        case chapter = "Chapter"
        case verse = "Verse"
    }

    /// One editor presentation for the panel (a single .sheet, as in the
    /// bookmarks panel: SwiftUI doesn't reliably handle two).
    private enum EditorItem: Identifiable {
        case verse(key: String, reference: String)
        case book(key: String, reference: String)
        case chapter(key: String, reference: String)
        var id: String {
            switch self {
            case .verse(let key, _): return "verse-\(key)"
            case .book(let key, _): return "book-\(key)"
            case .chapter(let key, _): return "chapter-\(key)"
            }
        }
    }

    /// The verse the Verse scopes anchor at.
    private var anchorVerse: Int { selectedVerses.min() ?? 1 }

    private var locationKey: String {
        "\(history.version.id)-\(history.testament)-\(history.book)-\(history.chapter)"
    }

    var body: some View {
        // Collapsed, the panel renders nothing: the only trace is the
        // up-arrow button in the reader's bottom bar (REQ-AP-1).
        if !collapsed {
            expandedBody
        }
    }

    /// Swipe down from the panel's header to collapse it (REQ-AP-18).
    /// Simultaneous, so the tabs' own scrolling and taps keep
    /// working; whether a finished drag counts as a collapse swipe
    /// is PanelCollapseGesture's call (unit-tested). The drag's
    /// start location is in this panel's own coordinates, so the
    /// header is everything from its top edge down through the
    /// tab bar (the divider plus the measured tab-bar height); a
    /// drag starting below that is the content's scroll.
    private var collapseGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                if PanelCollapseGesture.shouldCollapse(
                    translation: value.translation.height,
                    predictedEnd: value.predictedEndTranslation.height,
                    startY: value.startLocation.y,
                    headerBottom: tabBarHeight + 1) {
                    collapsed = true
                }
            }
    }

    /// The panel's tab bar: a horizontally scrollable row of pills, one
    /// per tab, each at its label's natural width — a segmented control
    /// squeezed all five labels into the panel width and truncated them
    /// ("Comment..."). The selected tab scrolls into view whenever the
    /// selection changes and when the panel opens.
    private var panelTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PanelTab.allCases, id: \.self) { t in
                        Button {
                            tab = t
                        } label: {
                            Text(t.rawValue)
                                .font(.callout)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(Color.primary.opacity(tab == t ? 0.24 : 0.07))
                                )
                                .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == t ? [.isSelected] : [])
                        .id(t)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .onAppear {
                proxy.scrollTo(tab, anchor: .center)
            }
            .onChange(of: tab) { _, newTab in
                withAnimation {
                    proxy.scrollTo(newTab, anchor: .center)
                }
            }
        }
    }

    /// Height of the tab content: the whole expanded panel — divider,
    /// tab bar, and content — is 30% of the total height. Before
    /// ReaderView's first measurement lands (totalHeight still zero),
    /// the content keeps the old fixed 264.
    private var contentHeight: CGFloat {
        guard totalHeight > 0 else { return 264 }
        return max(totalHeight * 0.30 - tabBarHeight - 1, 80)
    }

    /// The expanded panel: the tab bar plus the selected tab's content.
    private var expandedBody: some View {
        VStack(spacing: 0) {
            Divider()
            panelTabBar
                .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                    tabBarHeight = $0
                }

            Group {
                switch tab {
                case .notes: notesTab
                case .commentary: commentaryTab
                case .strongs: strongsTab
                case .recents: recentsTab
                case .highlights: highlightsTab
                case .parallel: parallelTab
                }
            }
            .frame(height: contentHeight)
        }
        .background(.regularMaterial)
        .simultaneousGesture(collapseGesture)
        .onChange(of: tab) { updateSyncActive() }
        .onChange(of: personalData.parallelSyncMode) { updateSyncActive() }
        .onDisappear { parallelSync.active = false }
        .onAppear {
            commentaries = CommentaryModule.allInstalled(in: store)
            expandedBookChapters = [history.chapter]
        }
        .sheet(item: $editorItem) { item in
            switch item {
            case .verse(let key, let reference):
                NoteEditor(reference: reference,
                           initialText: personalData.verseNote(forKey: key) ?? "",
                           seedText: "\(history.bookTitle) \(history.chapter)\n",
                           onReadChapter: {
                               if let p = NoteKey.parse(key) {
                                   jumpTo(testament: p.testament,
                                          book: p.book,
                                          chapter: p.chapter)
                                   history.pendingVerse = p.verse
                               }
                           }) { text in
                    personalData.setVerseNote(text, forKey: key,
                                              source: history.version.id)
                }
            case .book(let key, let reference):
                NoteEditor(reference: reference,
                                 initialText: personalData.bookNote(forKey: key) ?? "",
                                 onReadChapter: {
                                     if let p = BookNoteKey.parse(key) {
                                         jumpTo(testament: p.testament,
                                                book: p.book, chapter: 1)
                                     }
                                 }) { text in
                    personalData.setBookNote(text, forKey: key,
                                             source: history.version.id)
                }
            case .chapter(let key, let reference):
                NoteEditor(reference: reference,
                                 initialText: personalData.chapterNote(forKey: key) ?? "",
                                 onReadChapter: {
                                     if let p = ChapterNoteKey.parse(key) {
                                         jumpTo(testament: p.testament,
                                                book: p.book,
                                                chapter: p.chapter)
                                     }
                                 }) { text in
                    personalData.setChapterNote(text, forKey: key,
                                                source: history.version.id)
                }
            }
        }
        .sheet(item: $referenceLink) { link in
            ReferenceChapterView(version: link.version,
                                 target: link.target) {
                link.onReadChapter()
            }
            .environmentObject(personalData)
        }
        .sheet(isPresented: $showingCommentaryDownload, onDismiss: {
            commentaries = CommentaryModule.allInstalled(in: store)
        }) {
            CommentaryRepositoryView()
        }
        .sheet(isPresented: Binding(
            get: { strongsDefKey != nil },
            set: { if !$0 { strongsDefKey = nil } }
        )) {
            if let key = strongsDefKey {
                StrongsDefinitionView(key: key)
            }
        }
    }

    // MARK: - Notes tab

    /// Whether each Notes sub-tab has notes (REQ-NT-18): Recents =
    /// any note at all — notes are shared across versions, so no
    /// sub-tab is scoped to the version being read (REQ-NT-19);
    /// Book = any note in the active book; Chapter = any note in
    /// the active chapter; Verse = a note on the anchor verse (the
    /// first selected verse when several are selected).
    private var notesAvailability: NotesTabLogic.Availability {
        let bookPrefix = "\(history.testament):\(history.book):"
        let chapterPrefix = "\(bookPrefix)\(history.chapter):"
        return NotesTabLogic.Availability(
            recents: !personalData.bookNotes.isEmpty
                || !personalData.chapterNotes.isEmpty
                || !personalData.verseNotes.isEmpty,
            book: personalData.bookNote(forKey: bookNoteKey) != nil
                || personalData.chapterNotes.keys.contains { $0.hasPrefix(bookPrefix) }
                || personalData.verseNotes.keys.contains { $0.hasPrefix(bookPrefix) },
            chapter: personalData.chapterNote(forKey: chapterNoteKey) != nil
                || personalData.verseNotes.keys.contains { $0.hasPrefix(chapterPrefix) },
            verse: personalData.verseNote(forKey: verseNoteKey) != nil)
    }

    private var visibleNotesTabs: [NotesSubTab] {
        NotesTabLogic.visibleTabs(notesAvailability)
    }

    /// The sub-tab actually shown: the user's selection when it is
    /// visible, otherwise the nearest visible one (REQ-NT-18). Nil
    /// when there are no notes at all — the bar hides and the empty
    /// state shows instead.
    private var effectiveNotesTab: NotesSubTab? {
        NotesTabLogic.resolved(selected: notesSubTab,
                               availability: notesAvailability)
    }

    private var notesTabSelection: Binding<NotesSubTab> {
        Binding(get: { effectiveNotesTab ?? .recents },
                set: { notesSubTab = $0 })
    }

    /// One note in a sub-tab list: everything its row shows, and the
    /// editor it opens on tap.
    private struct NoteRow: Identifiable {
        enum Kind { case book, chapter, verse }
        let kind: Kind
        let key: String
        let testament: Int
        let book: Int
        /// Chapter the title-line jump lands on (1 for a book note).
        let chapter: Int
        /// The note's verse (verse notes only); the jump lands on it.
        let verse: Int?
        let reference: String
        let text: String
        /// Version the note was first written in (REQ-NT-19).
        let source: String?
        let updated: Date?
        var id: String { key }
    }

    private func bookName(testament: Int, book: Int) -> String {
        let overall = testament == 1 ? book - 1 : 39 + book - 1
        return history.version.bookNameIfPresent(overall: overall) ?? "Book \(book)"
    }

    private func bookNoteRow(key: String, parsed: BookNoteKey.Parsed) -> NoteRow {
        NoteRow(kind: .book, key: key, testament: parsed.testament, book: parsed.book, chapter: 1, verse: nil,
                reference: "\(bookName(testament: parsed.testament, book: parsed.book)) — Book note",
                text: personalData.bookNotes[key] ?? "",
                source: personalData.noteSources[key],
                updated: personalData.bookNoteTimes[key]?.updatedAt)
    }

    private func chapterNoteRow(key: String, parsed: ChapterNoteKey.Parsed) -> NoteRow {
        NoteRow(kind: .chapter, key: key, testament: parsed.testament, book: parsed.book, chapter: parsed.chapter, verse: nil,
                reference: "\(bookName(testament: parsed.testament, book: parsed.book)) \(parsed.chapter) — Chapter note",
                text: personalData.chapterNotes[key] ?? "",
                source: personalData.noteSources[key],
                updated: personalData.chapterNoteTimes[key]?.updatedAt)
    }

    private func verseNoteRow(key: String, parsed: NoteKey.Parsed) -> NoteRow {
        NoteRow(kind: .verse, key: key, testament: parsed.testament, book: parsed.book, chapter: parsed.chapter, verse: parsed.verse,
                reference: "\(bookName(testament: parsed.testament, book: parsed.book)) \(parsed.chapter):\(parsed.verse)",
                text: personalData.verseNotes[key] ?? "",
                source: personalData.noteSources[key],
                updated: personalData.verseNoteTimes[key]?.updatedAt)
    }

    /// Every note in the active book, in reading order: the book
    /// note first, then each chapter's chapter note (as verse 0) and
    /// verse notes.
    private var bookNoteRows: [NoteRow] {
        var rows: [NoteRow] = []
        if personalData.bookNote(forKey: bookNoteKey) != nil,
           let parsed = BookNoteKey.parse(bookNoteKey) {
            rows.append(bookNoteRow(key: bookNoteKey, parsed: parsed))
        }
        var located: [(chapter: Int, verse: Int, row: NoteRow)] = []
        for key in personalData.chapterNotes.keys {
            guard let p = ChapterNoteKey.parse(key),
                  p.testament == history.testament, p.book == history.book
            else { continue }
            located.append((p.chapter, 0, chapterNoteRow(key: key, parsed: p)))
        }
        for key in personalData.verseNotes.keys {
            guard let p = NoteKey.parse(key),
                  p.testament == history.testament, p.book == history.book
            else { continue }
            located.append((p.chapter, p.verse, verseNoteRow(key: key, parsed: p)))
        }
        rows += located
            .sorted { ($0.chapter, $0.verse) < ($1.chapter, $1.verse) }
            .map(\.row)
        return rows
    }

    /// Every note in the active chapter, in reading order: the
    /// chapter note, then verse notes by verse. While the legacy
    /// verse-1 note is presented as the chapter note (REQ-NT-16) it
    /// is not repeated as a verse row.
    private var chapterNoteRows: [NoteRow] {
        var rows: [NoteRow] = []
        if personalData.chapterNote(forKey: chapterNoteKey) != nil,
           let parsed = ChapterNoteKey.parse(chapterNoteKey) {
            rows.append(chapterNoteRow(key: chapterNoteKey, parsed: parsed))
        }
        let legacyShown = personalData.chapterNote(forKey: chapterNoteKey) == nil
            && personalData.verseNote(forKey: verse1NoteKey) != nil
        let verseRows = personalData.verseNotes.keys
            .compactMap { key -> (Int, NoteRow)? in
                guard let p = NoteKey.parse(key),
                      p.testament == history.testament, p.book == history.book,
                      p.chapter == history.chapter,
                      !(legacyShown && key == verse1NoteKey)
                else { return nil }
                return (p.verse, verseNoteRow(key: key, parsed: p))
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        return rows + verseRows
    }

    /// Every note, from every version (REQ-NT-19), most recently
    /// updated first (REQ-NT-17 times; notes without times fall
    /// back to the verse-note order, then key order so the sort is
    /// stable).
    private var recentNoteRows: [NoteRow] {
        var rows: [NoteRow] = []
        for key in personalData.bookNotes.keys {
            guard let p = BookNoteKey.parse(key) else { continue }
            rows.append(bookNoteRow(key: key, parsed: p))
        }
        for key in personalData.chapterNotes.keys {
            guard let p = ChapterNoteKey.parse(key) else { continue }
            rows.append(chapterNoteRow(key: key, parsed: p))
        }
        for key in personalData.verseNotes.keys {
            guard let p = NoteKey.parse(key) else { continue }
            rows.append(verseNoteRow(key: key, parsed: p))
        }
        let rank = Dictionary(uniqueKeysWithValues:
            personalData.verseNoteOrder.enumerated().map { ($0.element, $0.offset) })
        return rows.sorted { a, b in
            let ta = a.updated ?? .distantPast
            let tb = b.updated ?? .distantPast
            if ta != tb { return ta > tb }
            let ra = rank[a.key] ?? .max
            let rb = rank[b.key] ?? .max
            if ra != rb { return ra < rb }
            return a.key < b.key
        }
    }

    /// " - Oct 22, 2026" for a note's last-edit date, "" when the
    /// note has no timestamp (REQ-NT-17): the date rides the
    /// note's title line — no "Updated" label and no separate
    /// line under the note; date only, no time of day.
    private func noteDateSuffix(_ updated: Date?) -> String {
        guard let updated else { return "" }
        return " - \(updated.formatted(date: .abbreviated, time: .omitted))"
    }

    /// " · NASB" — the version a note was first written in
    /// (REQ-NT-19); "" when the source isn't known (e.g. a note
    /// that predates source tracking and never carried a key).
    private func sourceSuffix(_ source: String?) -> String {
        guard let source, !source.isEmpty else { return "" }
        return " · \(source)"
    }

    /// A note row in any Notes sub-tab: the title line (reference,
    /// source, date) is a jump button — tapping it takes the reader
    /// to the note's passage (REQ-NT-21) — while the note's text is
    /// the editor button. Swipe offers Delete (REQ-NT-20).
    /// Tapping a note row — title line or note text alike —
    /// opens its editor (REQ-NT-21): rows only edit, they
    /// never navigate. Reading the note's chapter is the
    /// editor's Read button's job.
    private func openNoteEditor(_ row: NoteRow) {
        switch row.kind {
        case .book: editorItem = .book(key: row.key, reference: row.reference)
        case .chapter: editorItem = .chapter(key: row.key, reference: row.reference)
        case .verse: editorItem = .verse(key: row.key, reference: row.reference)
        }
    }

    private func noteRowView(_ row: NoteRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                openNoteEditor(row)
            } label: {
                Text(row.reference + sourceSuffix(row.source)
                     + noteDateSuffix(row.updated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                openNoteEditor(row)
            } label: {
                Text(row.text)
                    .font(.system(size: personalData.fontSize, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }
            rowHairline
        }
        .listRowInsets(EdgeInsets(top: 11, leading: 16,
                                  bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions {
            Button(role: .destructive) {
                deleteNote(row)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Swipe-to-delete for a note row (REQ-NT-20): removes the
    /// note at the row's scope (its times and source go with it,
    /// as when the editor deletes it).
    private func deleteNote(_ row: NoteRow) {
        switch row.kind {
        case .book: personalData.setBookNote(nil, forKey: row.key)
        case .chapter: personalData.setChapterNote(nil, forKey: row.key)
        case .verse: personalData.setVerseNote(nil, forKey: row.key)
        }
    }

    /// A note list (REQ-NT-20): a List, like the Recents tab's
    /// history list, so its rows carry the swipe-to-delete
    /// action.
    /// The bottom hairline the Notes lists' rows draw themselves
    /// (their automatic separator is hidden): one straight
    /// rectangle. The List's separator steps where it meets the
    /// row background's edge — the kink the Highlights rows had
    /// (PR #48) — so these rows clear their background too and
    /// sit on the panel's gray.
    private var rowHairline: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 0.5)
    }

    private func noteList(_ rows: [NoteRow]) -> some View {
        List {
            ForEach(rows) { row in
                noteRowView(row)
            }
        }
        .listStyle(.plain)
    }

    /// The Book sub-tab: every note in the book. (Adding the
    /// book note is the header Add Note button's job — it
    /// follows the active sub-tab.)
    private var bookNotesContent: some View {
        List {
            ForEach(bookNoteRows) { row in
                noteRowView(row)
            }
        }
        .listStyle(.plain)
    }

    /// The header's one Add Note button follows the current
    /// context (Nov 12, 2026): the Book sub-tab edits the book
    /// note, the Chapter sub-tab the chapter note; anywhere
    /// else it edits the selected verses' note (anchored at
    /// the first selected verse), or the chapter note when no
    /// verses are selected. The Book and Chapter sub-tabs' own
    /// add entries are gone — this button is the only one.
    private func openAddNote() {
        switch effectiveNotesTab {
        case .book:
            editorItem = .book(key: bookNoteKey, reference: history.bookTitle)
        case .chapter:
            editorItem = .chapter(
                key: chapterNoteKey,
                reference: "\(history.bookTitle) \(history.chapter)")
        default:
            if selectedVerses.isEmpty {
                editorItem = .chapter(
                    key: chapterNoteKey,
                    reference: "\(history.bookTitle) \(history.chapter)")
            } else {
                editorItem = .verse(key: verseNoteKey, reference: verseReference)
            }
        }
    }

    /// The Notes tab's header row: the sub-tab picker plus the
    /// one Add Note button. Factored out of notesTab — the
    /// combined expression strained the type checker.
    private var notesHeader: some View {
        HStack(spacing: 8) {
            if !visibleNotesTabs.isEmpty {
                Picker("Notes", selection: notesTabSelection) {
                    ForEach(visibleNotesTabs, id: \.self) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }
            Spacer()
            // The one add-note entry point: always available,
            // even when there are no notes at all (REQ-NT-18).
            // It follows the current context (see openAddNote).
            // Always "Add Note" — editing an existing note is
            // what tapping the note itself does (REQ-NT-21).
            Button {
                openAddNote()
            } label: {
                Label("Add Note", systemImage: "square.and.pencil")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var notesTab: some View {
        VStack(spacing: 0) {
            notesHeader

            if let effectiveNotesTab {
                switch effectiveNotesTab {
                case .recents:
                    noteList(recentNoteRows)
                case .book:
                    bookNotesContent
                case .chapter:
                    chapterNotesContent
                case .verse:
                    scopedNote(reference: verseReference,
                               text: personalData.verseNote(forKey: verseNoteKey),
                               emptyText: "No note for this verse yet.",
                               updated: personalData.verseNoteTimes[verseNoteKey]?.updatedAt) {
                        editorItem = .verse(key: verseNoteKey, reference: verseReference)
                    }
                }
            } else {
                VStack {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
    }

    /// One scoped note (the Verse sub-tab): its reference line
    /// and its text (scrollable). No Add/Edit button — tapping
    /// the text, or the empty state, opens the editor
    /// (REQ-NT-21).
    private func scopedNote(reference: String, text: String?,
                            emptyText: String,
                            updated: Date? = nil,
                            edit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reference + noteDateSuffix(updated)).font(.subheadline).foregroundStyle(.secondary)
            if let text {
                ScrollView {
                    Text(text)
                        .font(.system(size: personalData.fontSize, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .onTapGesture { edit() }
            } else {
                Text(emptyText).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { edit() }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var verseReference: String {
        "\(history.bookTitle) \(history.chapter):\(anchorVerse)"
    }

    private var bookNoteKey: String {
        personalData.bookNoteKey(testament: history.testament,
                                 book: history.book)
    }

    private var chapterNoteKey: String {
        personalData.chapterNoteKey(testament: history.testament,
                                    book: history.book,
                                    chapter: history.chapter)
    }

    private var verseNoteKey: String {
        personalData.verseNoteKey(testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter,
                                  verse: anchorVerse)
    }

    /// The verse-1 note key for this chapter — where chapter notes
    /// were stored before scoped chapter notes (REQ-NT-16).
    private var verse1NoteKey: String {
        personalData.verseNoteKey(testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter,
                                  verse: 1)
    }

    /// The Chapter sub-tab: the legacy verse-1 presentation when it
    /// applies (REQ-NT-16), and the chapter's notes in reading
    /// order. (Adding the chapter note is the header Add Note
    /// button's job — it follows the active sub-tab.)
    private var chapterNotesContent: some View {
        List {
            if personalData.chapterNote(forKey: chapterNoteKey) == nil,
               let legacy = personalData.verseNote(forKey: verse1NoteKey) {
                legacyChapterNote(legacy)
            }
            ForEach(chapterNoteRows) { row in
                noteRowView(row)
            }
        }
        .listStyle(.plain)
    }

    /// The legacy verse-1 note shown in the Chapter sub-tab
    /// (REQ-NT-16): before scoped notes, the reader's "Take Notes"
    /// stored chapter notes as verse-1 notes, and the two are
    /// indistinguishable, so nothing migrates automatically — the
    /// user moves it with one tap instead.
    private func legacyChapterNote(_ legacy: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This note is saved on verse 1 — before chapter notes existed, that is where chapter notes were stored"
                 + noteDateSuffix(personalData.verseNoteTimes[verse1NoteKey]?.updatedAt) + ".")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(legacy)
                .font(.system(size: personalData.fontSize, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack {
                Button("Move to Chapter Note") {
                    personalData.setChapterNote(
                        legacy, forKey: chapterNoteKey,
                        source: personalData.noteSources[verse1NoteKey])
                    personalData.setVerseNote(nil, forKey: verse1NoteKey)
                }
                Spacer()
                Button("Edit") {
                    editorItem = .chapter(
                        key: chapterNoteKey,
                        reference: "\(history.bookTitle) \(history.chapter)")
                }
            }
            .font(.subheadline)
            rowHairline
                .padding(.top, 3)
        }
        .listRowInsets(EdgeInsets(top: 11, leading: 16,
                                  bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Commentary tab

    private var resolvedCommentary: CommentaryModule? {
        CommentaryModule.resolve(settingID: personalData.commentaryModuleID,
                                 installed: commentaries)
    }

    private var commentaryLoadKey: String {
        "\(resolvedCommentary?.id ?? "none")-\(locationKey)-\(commentaryScope.rawValue)"
    }

    /// Whether the Commentary tab has any entry at the current
    /// location — in the current chapter for the Verse/Chapter
    /// scopes, or anywhere in the book for the Book scope. The scope
    /// sub-tabs only appear when there is at least one entry
    /// (REQ-AP-9).
    private var commentaryHasEntries: Bool {
        commentaryScope == .book
            ? commentaryBook.contains { !$0.entries.isEmpty }
            : !commentaryChapter.isEmpty
    }

    private var commentaryTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if commentaryHasEntries || commentaryLoading {
                    scopePicker(selection: $commentaryScope)
                } else {
                    Spacer()
                }
                Menu {
                    ForEach(commentaries) { mod in
                        Button {
                            personalData.commentaryModuleID = mod.id
                        } label: {
                            if mod.id == resolvedCommentary?.id {
                                Label(mod.shortLabel, systemImage: "checkmark")
                            } else {
                                Text(mod.shortLabel)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(resolvedCommentary?.shortLabel ?? "None")
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if let mod = resolvedCommentary {
                    Button { showingCommentaryInfo = true } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingCommentaryInfo) {
                        CommentaryInfoView(module: mod)
                    }
                }
            }
            if let mod = resolvedCommentary {
                if let commentaryError {
                    // A module that failed to open is an error
                    // state, never an empty chapter (REQ-AP-13).
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Commentary couldn't be loaded",
                              systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(commentaryError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                } else if commentaryHasEntries || commentaryLoading {
                    commentaryContent(for: mod)
                } else {
                    emptyCommentary("No commentary entries for this chapter in \(mod.shortLabel).")
                }
            } else {
                VStack(spacing: 8) {
                    Text("No commentary installed yet.")
                        .foregroundStyle(.secondary)
                    Button("Download a Commentary…") { showingCommentaryDownload = true }
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
        .task(id: commentaryLoadKey) { await loadCommentary() }
        // Reference links in commentary entries (REQ-AP-19) open
        // the reference chapter sheet instead of a browser.
        .environment(\.openURL, OpenURLAction { url in
            if let target = refTarget(from: url) {
                referenceLink = ReferenceLink(
                    version: history.version, target: target) {
                        jumpTo(testament: target.testament,
                               book: target.book,
                               chapter: target.chapter)
                        history.pendingVerse = target.verses.first
                    }
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private func commentaryContent(for mod: CommentaryModule) -> some View {
        if commentaryLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch commentaryScope {
            case .verse:
                if let entry = CommentaryGrouping.entry(in: commentaryChapter,
                                                          covering: anchorVerse) {
                    ScrollView {
                        commentaryEntry(entry, reference: "\(history.bookTitle) \(history.chapter)",
                                        segments: commentarySegments[entry.startVerse])
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                } else {
                    emptyCommentary("No commentary entry for \(verseReference) in \(mod.shortLabel).")
                }
            case .chapter:
                if commentaryChapter.isEmpty {
                    emptyCommentary("No commentary entries for this chapter in \(mod.shortLabel).")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(commentaryChapter, id: \.startVerse) { entry in
                                commentaryEntry(entry, reference: "\(history.bookTitle) \(history.chapter)",
                                                segments: commentarySegments[entry.startVerse])
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
            case .book:
                if commentaryBook.allSatisfy({ $0.entries.isEmpty }) {
                    emptyCommentary("No commentary entries for this book in \(mod.shortLabel).")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(commentaryBook) { section in
                                if !section.entries.isEmpty {
                                    Button {
                                        toggleBookChapter(section.chapter)
                                    } label: {
                                        HStack {
                                            Text("\(history.bookTitle) \(section.chapter)")
                                                .font(.subheadline.bold())
                                            Spacer()
                                            Image(systemName: expandedBookChapters.contains(section.chapter)
                                                  ? "chevron.down" : "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 6)
                                    if expandedBookChapters.contains(section.chapter) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ForEach(section.entries, id: \.startVerse) { entry in
                                                commentaryEntry(entry, reference: "\(history.bookTitle) \(section.chapter)",
                                                                segments: commentaryBookSegments[section.chapter]?[entry.startVerse])
                                            }
                                        }
                                        .padding(.bottom, 8)
                                    }
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    /// One commentary entry with its verse-range reference. When
    /// the entry's segments carry scripture references (REQ-AP-19),
    /// they render blue and underlined and open the reference
    /// chapter sheet; the wording is the entry's plain text either
    /// way.
    private func commentaryEntry(_ entry: CommentaryGrouping.Entry,
                                 reference: String,
                                 segments: [ScriptureReferences.Segment]? = nil)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.startVerse == entry.endVerse
                 ? "\(reference):\(entry.startVerse)"
                 : "\(reference):\(entry.startVerse)-\(entry.endVerse)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let segments, segments.contains(where: hasReference) {
                Text(attributedCommentary(segments))
                    .font(.system(size: personalData.fontSize, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(entry.text)
                    .font(.system(size: personalData.fontSize, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func hasReference(_ segment: ScriptureReferences.Segment) -> Bool {
        if case .reference = segment { return true }
        return false
    }

    /// A commentary entry's segments as an attributed string:
    /// references are blue, underlined links (REQ-AP-19); the rest
    /// is the entry's plain text unchanged.
    private func attributedCommentary(_ segments: [ScriptureReferences.Segment])
        -> AttributedString
    {
        var out = AttributedString("")
        for segment in segments {
            switch segment {
            case .text(let s):
                out += AttributedString(s)
            case .reference(let display, let target):
                var run = AttributedString(display)
                run.foregroundColor = .blue
                run.underlineStyle = .single
                if let url = refURL(for: target) {
                    run.link = url
                }
                out += run
            }
        }
        return out
    }

    /// The link a reference segment carries; the panel's openURL
    /// interception turns it back into a target.
    private func refURL(for target: ScriptureReferenceTarget) -> URL? {
        URL(string: "ref://target?t=\(target.testament)&b=\(target.book)"
            + "&c=\(target.chapter)"
            + "&v=\(target.verses.map(String.init).joined(separator: ","))")
    }

    /// Inverse of `refURL(for:)`; nil for any other URL.
    private func refTarget(from url: URL) -> ScriptureReferenceTarget? {
        guard url.scheme == "ref",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems
        else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let t = value("t").flatMap({ Int($0) }),
              let b = value("b").flatMap({ Int($0) }),
              let c = value("c").flatMap({ Int($0) }),
              let v = value("v")
        else { return nil }
        let verses = v.split(separator: ",").compactMap { Int($0) }
        guard !verses.isEmpty else { return nil }
        return ScriptureReferenceTarget(testament: t, book: b,
                                        chapter: c, verses: verses)
    }

    private func emptyCommentary(_ message: String) -> some View {
        VStack {
            Text(message).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
    }

    private func toggleBookChapter(_ chapter: Int) {
        if expandedBookChapters.contains(chapter) {
            expandedBookChapters.remove(chapter)
        } else {
            expandedBookChapters.insert(chapter)
        }
    }

    private func loadCommentary() async {
        guard tab == .commentary, let mod = resolvedCommentary else { return }
        commentaryLoading = true
        defer { commentaryLoading = false }
        do {
            switch commentaryScope {
            case .verse, .chapter:
                let rows = try await mod.loadChapterSegments(
                    testament: history.testament,
                    book: history.book,
                    chapter: history.chapter)
                commentaryChapter = CommentaryGrouping.group(
                    rows.map { (verse: $0.verse, text: $0.text) })
                commentarySegments = segmentsByEntry(rows: rows,
                                                     entries: commentaryChapter)
            case .book:
                let count = mod.chapterCount(testament: history.testament,
                                              book: history.book)
                let chapters = count > 0 ? count : history.chapterCount
                var sections: [BookSection] = []
                var bookSegments: [Int: [Int: [ScriptureReferences.Segment]]] = [:]
                if chapters > 0 {
                    for c in 1 ... chapters {
                        let rows = try await mod.loadChapterSegments(
                            testament: history.testament,
                            book: history.book,
                            chapter: c)
                        let grouped = CommentaryGrouping.group(
                            rows.map { (verse: $0.verse, text: $0.text) })
                        sections.append(BookSection(chapter: c, entries: grouped))
                        bookSegments[c] = segmentsByEntry(rows: rows,
                                                          entries: grouped)
                    }
                }
                commentaryBook = sections
                commentaryBookSegments = bookSegments
            }
            commentaryError = nil
        } catch {
            // A module that can't be opened (damaged, missing,
            // unsupported) is an error state, not an empty chapter
            // (REQ-AP-13).
            commentaryChapter = []
            commentaryBook = []
            commentarySegments = [:]
            commentaryBookSegments = [:]
            commentaryError = "The \(mod.shortLabel) module couldn't be opened. "
                + "It may be damaged or missing — re-downloading it from the "
                + "repository usually fixes this. (\(error.localizedDescription))"
        }
    }

    /// Reference segments for each grouped entry, keyed by the
    /// entry's start verse. Grouped entries repeat one module entry
    /// across their verses, so the first row's segments serve the
    /// whole group.
    private func segmentsByEntry(
        rows: [(verse: Int, text: String,
                segments: [ScriptureReferences.Segment])],
        entries: [CommentaryGrouping.Entry]
    ) -> [Int: [ScriptureReferences.Segment]] {
        var out: [Int: [ScriptureReferences.Segment]] = [:]
        for entry in entries {
            if let row = rows.first(where: { $0.verse == entry.startVerse }) {
                out[entry.startVerse] = row.segments
            }
        }
        return out
    }

    // MARK: - Strong's tab

    private var strongsVersions: [BibleVersion] {
        availableVersions.filter { $0.supportsStrongs }
    }

    private var strongsSourceID: String? {
        StrongsVerseSource.resolve(
            currentID: history.version.id,
            currentSupportsStrongs: history.version.supportsStrongs,
            fallbackID: personalData.strongsFallbackVersionID.isEmpty
                ? nil : personalData.strongsFallbackVersionID,
            strongsVersionIDs: strongsVersions.map(\.id))
    }

    private var strongsSource: BibleVersion? {
        guard let id = strongsSourceID else { return nil }
        return availableVersions.first { $0.id == id }
    }

    private var strongsLoadKey: String {
        "\(strongsSourceID ?? "none")-\(history.testament)-\(history.book)-\(history.chapter)-\(anchorVerse)"
    }

    private var strongsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verseReference)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let source = strongsSource {
                    if source.id == history.version.id {
                        Text(source.shortLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(strongsVersions) { version in
                                Button {
                                    personalData.strongsFallbackVersionID = version.id
                                } label: {
                                    if version.id == source.id {
                                        Label(version.shortLabel, systemImage: "checkmark")
                                    } else {
                                        Text(version.shortLabel)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(source.shortLabel)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if strongsSource == nil {
                Text("No installed version has Strong's numbers. Download one (e.g. KJV) from the repository, or pick a fallback in Settings.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if strongsLoadedKey != strongsLoadKey {
                ProgressView()
                Spacer()
            } else if strongsTokens.isEmpty {
                Text("This version has no Strong's data for this verse.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    Text(attributedStrongsVerse())
                        .font(.system(size: personalData.fontSize, design: .serif))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .task(id: strongsLoadKey) { await loadStrongs() }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "strongs", let key = url.host, !key.isEmpty {
                strongsDefKey = key
                return .handled
            }
            return .systemAction
        })
    }

    /// The selected verse with tappable Strong's numbers, rendered like
    /// the main reader's Strong's mode.
    private func attributedStrongsVerse() -> AttributedString {
        var num = AttributedString("\(anchorVerse) ")
        num.font = .system(size: personalData.fontSize * 0.65, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.25
        var out = num
        for token in strongsTokens {
            out += AttributedString(token.text)
            for key in token.strongs {
                var n = AttributedString(" \(key)")
                n.font = .system(size: personalData.fontSize * 0.55, design: .serif)
                n.foregroundColor = .blue
                n.baselineOffset = personalData.fontSize * 0.22
                n.underlineStyle = .single
                n.link = URL(string: "strongs://\(key)")
                out += n
            }
        }
        return out
    }

    private func loadStrongs() async {
        guard tab == .strongs, let source = strongsSource else { return }
        let rows = await source.loadTokens(testament: history.testament,
                                           book: history.book,
                                           chapter: history.chapter)
        strongsTokens = rows.first { $0.verse == anchorVerse }?.tokens ?? []
        strongsLoadedKey = strongsLoadKey
    }

    // MARK: - Recents tab

    /// The reading history (REQ-AP-11), moved here from the reader's
    /// left drawer: the same HistoryView list — tap an entry to view
    /// its chapter in the reference chapter sheet, the sheet's Read
    /// More jumping back to it (switching version when that version
    /// is installed); swipe to delete. HistoryView's own Clear
    /// toolbar button needs a navigation bar, so the tab header
    /// carries Clear instead.
    private var recentsTab: some View {
        VStack(spacing: 0) {
            if !personalData.historyLog.isEmpty {
                HStack {
                    Text("Reading history")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        personalData.clearHistory()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            HistoryView(onSelect: openHistoryEntry)
        }
        .background(Color.black)
    }

    /// Tapping a history entry views its chapter in the
    /// reference chapter sheet (REQ-AP-20), in the entry's own
    /// version when it is still installed (the version being
    /// read when it is not), with no verses selected — an
    /// entry names a chapter, not verses. The sheet's Read
    /// More performs the jump a tap used to do directly.
    private func openHistoryEntry(_ entry: HistoryEntry) {
        let version = availableVersions.first(where: { $0.id == entry.moduleID })
            ?? history.version
        referenceLink = ReferenceLink(
            version: version,
            target: ScriptureReferenceTarget(testament: entry.testament,
                                             book: entry.book,
                                             chapter: entry.chapter,
                                             verses: [])) {
                jumpToHistoryEntry(entry)
            }
    }

    /// Jumps the reader to a history entry, switching to the entry's
    /// version first when it is still installed (the same behavior
    /// the drawer's History button had).
    private func jumpToHistoryEntry(_ entry: HistoryEntry) {
        if let v = availableVersions.first(where: { $0.id == entry.moduleID }) {
            history.version = v
            history.testament = entry.testament
            history.book = entry.book
            history.chapter = entry.chapter
        }
    }

    // MARK: - Highlights tab

    /// Whether each Highlights sub-tab has highlights (REQ-HL-4),
    /// in the Notes tab's pattern (REQ-NT-18): Recents = any
    /// highlight at all; Book = any in the active book; Chapter =
    /// any in the active chapter. Highlights are shared across
    /// versions (REQ-HL-2), so none of the scopes is per-version.
    private var highlightsAvailability: HighlightsTabLogic.Availability {
        HighlightsTabLogic.Availability(
            recents: !personalData.highlights.isEmpty,
            book: personalData.highlights.contains {
                $0.testament == history.testament && $0.book == history.book
            },
            chapter: personalData.highlights.contains {
                $0.isAt(testament: history.testament, book: history.book,
                        chapter: history.chapter)
            })
    }

    private var visibleHighlightsTabs: [HighlightsSubTab] {
        HighlightsTabLogic.visibleTabs(highlightsAvailability)
    }

    /// The sub-tab actually shown: the user's selection when it
    /// is visible, otherwise the nearest visible one (REQ-HL-4).
    /// Nil when there are no highlights at all — the bar hides
    /// and the empty state shows instead.
    private var effectiveHighlightsTab: HighlightsSubTab? {
        HighlightsTabLogic.resolved(selected: highlightsSubTab,
                                    availability: highlightsAvailability)
    }

    private var highlightsTabSelection: Binding<HighlightsSubTab> {
        Binding(get: { effectiveHighlightsTab ?? .recents },
                set: { highlightsSubTab = $0 })
    }

    private var highlightsTab: some View {
        VStack(spacing: 0) {
            if !visibleHighlightsTabs.isEmpty {
                Picker("Highlights", selection: highlightsTabSelection) {
                    ForEach(visibleHighlightsTabs, id: \.self) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if let effectiveHighlightsTab {
                switch effectiveHighlightsTab {
                case .recents:
                    // Reverse creation order: newest first.
                    highlightList(sortedHighlights)
                case .book:
                    bookHighlightList
                case .chapter:
                    highlightList(HighlightLogic.chapterHighlights(
                        in: personalData.highlights,
                        testament: history.testament, book: history.book,
                        chapter: history.chapter))
                }
            } else {
                VStack {
                    Text("No highlights yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
        .background(Color.black)
    }

    /// Every highlight, newest first (the Recents sub-tab).
    private var sortedHighlights: [Highlight] {
        personalData.highlights.sorted { $0.createdAt > $1.createdAt }
    }

    /// The Book sub-tab (REQ-HL-4): the active book's highlights
    /// grouped by chapter, ordered by verse within a chapter.
    private var bookHighlightList: some View {
        let groups = HighlightLogic.bookGroups(
            in: personalData.highlights,
            testament: history.testament, book: history.book)
        return List {
            ForEach(groups.indices, id: \.self) { i in
                Section {
                    ForEach(groups[i].highlights) { h in
                        highlightRow(h)
                    }
                } header: {
                    Text("\(history.bookTitle) \(groups[i].chapter)")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
    }

    private func highlightList(_ highlights: [Highlight]) -> some View {
        List {
            ForEach(highlights) { h in
                highlightRow(h)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
    }

    private func highlightReference(_ h: Highlight) -> String {
        let book = bookName(testament: h.testament, book: h.book)
        return h.startVerse == h.endVerse
            ? "\(book) \(h.chapter):\(h.startVerse)"
            : "\(book) \(h.chapter):\(h.startVerse)-\(h.endVerse)"
    }

    /// One highlight row in any sub-tab: a yellow swatch and the
    /// reference with the version it was made in and its date
    /// (the note-row format), blue on black — the same rendering
    /// as the Recents tab's history entries (REQ-AP-11). Tap views the passage in the
    /// reference chapter sheet; swipe deletes. Built
    /// exactly like a HistoryView row — default button style, no
    /// content-shape override — so the List makes the whole row
    /// the tap target, like the Recents tab's history items; the
    /// plain style confined the tap to the label's own frame and
    /// the rows felt dead.
    private func highlightRow(_ h: Highlight) -> some View {
        Button {
            openHighlight(h)
        } label: {
            // The row draws its own bottom hairline and hides the
            // List's separator: the automatic separator rendered in
            // two segments at slightly different heights — a kink
            // where the text begins — both when the row led with
            // the swatch shape and as a single padded text. One
            // rectangle cannot kink. The swatch is overlaid in the
            // text's leading padding.
            VStack(alignment: .leading, spacing: 0) {
                Text(highlightReference(h)
                     + sourceSuffix(h.version)
                     + noteDateSuffix(h.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 1.0, green: 0.9, blue: 0.0)
                                .opacity(0.65))
                            .frame(width: 4, height: 22)
                    }
                    .padding(.bottom, 11)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 0.5)
            }
        }
        .listRowInsets(EdgeInsets(top: 11, leading: 16,
                                  bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.black)
        .swipeActions {
            Button(role: .destructive) {
                personalData.removeHighlight(id: h.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Jumps the reader to a highlight's passage in the version
    /// being read — highlights show in every version (REQ-HL-2),
    /// so unlike a history jump this never switches version.
    /// Moves the reader to a passage, in the version being read.
    private func jumpTo(testament: Int, book: Int, chapter: Int) {
        history.testament = testament
        history.book = book
        history.chapter = chapter
    }

    /// Tapping a highlight views its passage in the reference
    /// chapter sheet (REQ-AP-20), in the version being read —
    /// highlights show in every version (REQ-HL-2), so unlike
    /// a history entry this never switches version — with the
    /// highlight's verses selected. The sheet's Read More
    /// moves the reader to the passage, landing on its first
    /// verse.
    private func openHighlight(_ h: Highlight) {
        let target = ScriptureReferenceTarget(
            testament: h.testament, book: h.book, chapter: h.chapter,
            verses: Array(h.startVerse...h.endVerse))
        referenceLink = ReferenceLink(version: history.version,
                                      target: target) {
            jumpTo(testament: h.testament, book: h.book,
                   chapter: h.chapter)
            history.pendingVerse = h.startVerse
        }
    }

    // MARK: - Shared

    private func scopePicker(selection: Binding<PanelScope>) -> some View {
        Picker("Scope", selection: selection) {
            ForEach(PanelScope.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Parallel tab (REQ-PA)

    /// Sync is live only while this tab is the one showing, the
    /// panel is expanded, and the remembered mode is sync.
    private func updateSyncActive() {
        parallelSync.active = tab == .parallel && !collapsed
            && personalData.parallelSyncMode
    }

    /// The sync mode's version: the remembered choice, else the
    /// first installed version that isn't the one being read.
    private var parallelSyncVersion: BibleVersion {
        availableVersions.first { $0.id == personalData.parallelSyncVersionID }
            ?? availableVersions.first { $0.id != history.version.id }
            ?? history.version
    }

    /// The separate mode's version, resolved the same way.
    private var parallelSeparateVersion: BibleVersion {
        availableVersions.first { $0.id == personalData.parallelSeparateVersionID }
            ?? availableVersions.first { $0.id != history.version.id }
            ?? history.version
    }

    /// Separate mode's target: the session's frozen target, or
    /// — before it freezes — the chapter being read.
    private var effectiveSepTarget: ParallelTarget {
        parallelSepTarget
            ?? ParallelTarget(testament: history.testament,
                              book: history.book,
                              chapter: history.chapter)
    }

    /// The location the parallel view shows: the main view's
    /// own chapter in sync mode, the session target otherwise.
    private var parallelTarget: ParallelTarget {
        personalData.parallelSyncMode
            ? ParallelTarget(testament: history.testament,
                             book: history.book,
                             chapter: history.chapter)
            : effectiveSepTarget
    }

    private var parallelTab: some View {
        VStack(spacing: 0) {
            parallelHeader
            Divider()
            ParallelChapterView(
                version: personalData.parallelSyncMode
                    ? parallelSyncVersion : parallelSeparateVersion,
                testament: parallelTarget.testament,
                book: parallelTarget.book,
                chapter: parallelTarget.chapter,
                sync: personalData.parallelSyncMode ? parallelSync : nil)
        }
        .sheet(item: $parallelSettings) { kind in
            ParallelSettingsSheet(
                kind: kind,
                versions: availableVersions,
                mainTarget: ParallelTarget(testament: history.testament,
                                           book: history.book,
                                           chapter: history.chapter),
                mainBookTitle: history.bookTitle,
                initialVersionID: initialParallelVersionID(for: kind),
                initialTarget: initialParallelTarget(for: kind),
                onApply: { versionID, target in
                    applyParallelSettings(kind: kind,
                                          versionID: versionID,
                                          target: target)
                })
        }
        .onAppear {
            // Separate mode freezes its starting target from the
            // chapter being read (REQ-PA-5); after that only its
            // settings move it.
            if !personalData.parallelSyncMode, parallelSepTarget == nil {
                parallelSepTarget = ParallelTarget(
                    testament: history.testament,
                    book: history.book,
                    chapter: history.chapter)
            }
            updateSyncActive()
        }
    }

    /// The header over the parallel chapter: the gear on the
    /// left, the version and passage, and the mode chain on
    /// the right (REQ-PA-1, REQ-PA-4).
    private var parallelHeader: some View {
        HStack(spacing: 10) {
            Button {
                parallelSettings = personalData.parallelSyncMode
                    ? .syncVersion : .separate
            } label: {
                Image(systemName: "gearshape")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Parallel view settings")

            Text(parallelTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                parallelSettings = personalData.parallelSyncMode
                    ? .toSeparate : .toSync
            } label: {
                if personalData.parallelSyncMode {
                    Image(systemName: "link")
                        .font(.callout)
                        .foregroundStyle(.yellow)
                } else {
                    brokenChainIcon
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(personalData.parallelSyncMode
                                ? "Switch to separate mode"
                                : "Switch to sync mode")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    /// The broken chain of separate mode (REQ-PA-4): a gray
    /// link struck through — SF Symbols has no broken-link
    /// glyph, so the slash is drawn over it.
    private var brokenChainIcon: some View {
        Image(systemName: "link")
            .font(.callout)
            .foregroundStyle(.gray)
            .overlay {
                Rectangle()
                    .fill(.gray)
                    .frame(width: 2, height: 20)
                    .rotationEffect(.degrees(-45))
            }
    }

    private var parallelTitle: String {
        if personalData.parallelSyncMode {
            return "\(parallelSyncVersion.displayName) — \(history.bookTitle) \(history.chapter)"
        }
        let target = effectiveSepTarget
        return "\(parallelSeparateVersion.displayName) — \(parallelSeparateVersion.bookName(overall: target.overall)) \(target.chapter)"
    }

    /// The version a settings sheet starts from.
    private func initialParallelVersionID(for kind: ParallelSettingsKind) -> String {
        switch kind {
        case .syncVersion, .toSync: return parallelSyncVersion.id
        case .separate, .toSeparate: return parallelSeparateVersion.id
        }
    }

    /// The passage a settings sheet starts from.
    private func initialParallelTarget(for kind: ParallelSettingsKind) -> ParallelTarget {
        switch kind {
        case .syncVersion, .toSync:
            return ParallelTarget(testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter)
        case .separate, .toSeparate:
            return effectiveSepTarget
        }
    }

    /// Applies a settings sheet's Done (REQ-PA-4): the gear
    /// sheets set their own mode's version (the full form also
    /// sets separate's target); the chain sheets do the same
    /// and switch the mode.
    private func applyParallelSettings(kind: ParallelSettingsKind,
                                       versionID: String,
                                       target: ParallelTarget) {
        switch kind {
        case .syncVersion:
            personalData.parallelSyncVersionID = versionID
        case .toSync:
            personalData.parallelSyncVersionID = versionID
            personalData.parallelSyncMode = true
        case .separate:
            personalData.parallelSeparateVersionID = versionID
            parallelSepTarget = target
        case .toSeparate:
            personalData.parallelSeparateVersionID = versionID
            parallelSepTarget = target
            personalData.parallelSyncMode = false
        }
    }
}

/// Chooses the commentary module the auxiliary panel shows. Used from
/// Settings > Commentary. The panel's own header menu offers the same
/// choice; an installed commentary can be deleted here.
struct CommentaryModulePicker: View {
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store
    @State private var commentaries: [CommentaryModule] = []
    @State private var showingDownload = false

    var body: some View {
        List {
            Section {
                Button {
                    personalData.commentaryModuleID = ""
                } label: {
                    HStack {
                        Text("Automatic (first installed)")
                            .foregroundStyle(.primary)
                        Spacer()
                        if personalData.commentaryModuleID.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                ForEach(commentaries) { mod in
                    Button {
                        personalData.commentaryModuleID = mod.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mod.shortLabel)
                                    .foregroundStyle(.primary)
                                if mod.displayName != mod.shortLabel {
                                    Text(mod.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !mod.license.isEmpty {
                                    Text(mod.license)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if personalData.commentaryModuleID == mod.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            delete(mod)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("The Commentary tab of the panel below the reader shows this commentary's entries for the book, chapter, or verse being read.")
            }
            Section {
                Button("Download a Commentary…") { showingDownload = true }
            } footer: {
                Text("OSIS commentaries such as MHCC are supported; each commentary's license is shown before you download it.")
            }
        }
        .navigationTitle("Commentary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { commentaries = CommentaryModule.allInstalled(in: store) }
        .sheet(isPresented: $showingDownload, onDismiss: {
            commentaries = CommentaryModule.allInstalled(in: store)
        }) {
            CommentaryRepositoryView()
        }
    }

    private func delete(_ mod: CommentaryModule) {
        try? store.delete(mod.id)
        Task { await ModuleLoader.shared.evict(mod.id) }
        if personalData.commentaryModuleID == mod.id {
            personalData.commentaryModuleID = ""
        }
        commentaries = CommentaryModule.allInstalled(in: store)
    }
}

/// Info about the commentary shown in the panel (REQ-AP-8): its
/// title, its declared distribution license, and the About text from
/// its .conf, which carries the copyright notice. Commentaries are
/// often copyrighted — the license is the field the copyright holder
/// declares, and this is where the reader can see it.
struct CommentaryInfoView: View {
    let module: CommentaryModule
    @Environment(\.dismiss) private var dismiss

    /// The About text with SWORD's \par / \t markup turned into
    /// line breaks and spaces.
    private var formattedAbout: String {
        module.about
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: "\\par", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Module") {
                    LabeledContent("Name", value: module.displayName)
                    LabeledContent("Module ID", value: module.id)
                }
                if !module.license.isEmpty {
                    Section("License") {
                        Text(module.license)
                    }
                }
                if !formattedAbout.isEmpty {
                    Section("About") {
                        Text(formattedAbout)
                    }
                }
                if module.license.isEmpty && formattedAbout.isEmpty {
                    Text("This module's configuration declares no license or About text.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Commentary info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Chooses the fallback Strong's version for the auxiliary panel
/// (REQ-AP-7). Used from Settings > Strong's.
struct StrongsFallbackPicker: View {
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store
    @State private var versions: [BibleVersion] = []

    var body: some View {
        List {
            Section {
                Button {
                    personalData.strongsFallbackVersionID = ""
                } label: {
                    HStack {
                        Text("Automatic (first available)")
                            .foregroundStyle(.primary)
                        Spacer()
                        if personalData.strongsFallbackVersionID.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                ForEach(versions) { version in
                    Button {
                        personalData.strongsFallbackVersionID = version.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.shortLabel)
                                    .foregroundStyle(.primary)
                                if version.displayName != version.shortLabel {
                                    Text(version.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if personalData.strongsFallbackVersionID == version.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            } footer: {
                Text("When the version you are reading has no Strong's numbers, the panel's Strong's tab renders the selected verse from this version instead.")
            }
        }
        .navigationTitle("Strong's fallback version")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            versions = BibleVersion.allInstalled(in: store)
                .filter { $0.supportsStrongs }
        }
    }
}

/// Chooses the dictionaries Strong's definitions come from
/// (REQ-DC-2): one lexicon for Hebrew ("H") keys, one for Greek
/// ("G") keys. Used from Settings > Dictionary. With no choice, the
/// app uses (and downloads) StrongsHebrew / StrongsGreek. An
/// installed dictionary can be deleted here.
struct DictionarySettingsView: View {
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store
    @State private var dictionaries: [InstalledModule] = []
    @State private var showingDownload = false

    var body: some View {
        List {
            choiceSection(
                header: "Hebrew dictionary",
                automaticLabel: "Automatic (StrongsHebrew)",
                selectedID: personalData.dictionaryHebrewID,
                footer: "Definitions for Hebrew Strong's numbers (H…) come from this dictionary."
            ) { personalData.dictionaryHebrewID = $0 }
            choiceSection(
                header: "Greek dictionary",
                automaticLabel: "Automatic (StrongsGreek)",
                selectedID: personalData.dictionaryGreekID,
                footer: "Definitions for Greek Strong's numbers (G…) come from this dictionary."
            ) { personalData.dictionaryGreekID = $0 }
            Section {
                Button("Download a Dictionary…") { showingDownload = true }
            } footer: {
                Text("Only Strong's-keyed lexicons have entries for Strong's numbers: the Strongs lexicons in any language (StrongsHebrew, ChiSstrongsGreek, FreStrongsGreek…), BDBGlosses_Strongs, AbbottSmithStrongs, MLStrong. Other dictionaries (Easton, ISBE, Webster…) download and install the same way but have no Strong's entries to show.")
            }
        }
        .navigationTitle("Dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(isPresented: $showingDownload, onDismiss: reload) {
            DictionaryRepositoryView()
        }
    }

    private func choiceSection(header: String, automaticLabel: String,
                               selectedID: String, footer: String,
                               select: @escaping (String) -> Void) -> some View {
        Section {
            Button {
                select("")
            } label: {
                HStack {
                    Text(automaticLabel).foregroundStyle(.primary)
                    Spacer()
                    if selectedID.isEmpty {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            ForEach(dictionaries) { mod in
                Button {
                    select(mod.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mod.info.description)
                                .foregroundStyle(.primary)
                            Text("\(mod.id) · \(mod.info.language)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedID == mod.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .swipeActions {
                    Button(role: .destructive) {
                        delete(mod)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    private func reload() {
        dictionaries = store.installedModules()
            .filter { $0.info.isDictionaryRenderable }
    }

    private func delete(_ mod: InstalledModule) {
        try? store.delete(mod.id)
        if personalData.dictionaryHebrewID == mod.id {
            personalData.dictionaryHebrewID = ""
        }
        if personalData.dictionaryGreekID == mod.id {
            personalData.dictionaryGreekID = ""
        }
        reload()
    }
}

/// The chapter a commentary reference points to (REQ-AP-20):
/// the whole chapter in the version being read, rendered the
/// way the main reader renders it — the reader's mode
/// (paragraph or verse by verse, following its setting), font,
/// and line spacing, with section headings, red letters, and
/// Strong's numbers where the reader would show them — and
/// the referenced verses highlighted like a selection in the
/// reader, scrolled into view. None of the reader's own marks
/// are drawn: no bookmarks, highlights, or notes. "Done" sits
/// where the Strong's dictionary view puts it (top-left, the
/// cancellation action) and returns to the commentary; the
/// bottom "Read More" button — a text button in the bottom
/// bar, alongside that view's back / forward arrow buttons —
/// moves the main reader to the chapter (at the first
/// referenced verse) and dismisses.
///
/// The rendering builders below mirror ReaderView's, minus
/// the marks: keeping them local is simpler than extracting a
/// shared renderer for one sheet.
private struct ReferenceChapterView: View {
    let version: BibleVersion
    let target: ScriptureReferenceTarget
    let onReadChapter: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var personalData: PersonalData
    @State private var verses: [(verse: Int, text: String)] = []
    @State private var verseTokens: [(verse: Int, tokens: [WordToken])] = []
    @State private var jesusSpans: [Int: [(start: Int, end: Int)]] = [:]
    @State private var headings: [Int: String] = [:]
    @State private var strongsKey: String?

    /// Strong's numbers show exactly when the reader would
    /// show them for this version (the reader's own rule).
    private var useStrongs: Bool {
        personalData.showStrongs && version.supportsStrongs
    }

    private var title: String {
        "\(version.bookName(overall: target.overallBook)) \(target.chapter)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if personalData.verseByVerse {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if useStrongs {
                                    ForEach(verseTokens, id: \.verse) { v in
                                        Group {
                                            if let heading = headings[v.verse] {
                                                headingRow(heading)
                                            }
                                            Text(attributedVerseTokens(number: v.verse, tokens: v.tokens))
                                                .id(v.verse)
                                                .font(.system(size: personalData.fontSize, design: .serif))
                                                .lineSpacing(6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                } else {
                                    ForEach(verses, id: \.verse) { v in
                                        Group {
                                            if let heading = headings[v.verse] {
                                                headingRow(heading)
                                            }
                                            Text(attributedVerse(number: v.verse, text: v.text))
                                                .id(v.verse)
                                                .font(.system(size: personalData.fontSize, design: .serif))
                                                .lineSpacing(6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .onChange(of: verses.count) {
                            if let first = target.verses.first {
                                proxy.scrollTo(first, anchor: .center)
                            }
                        }
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(useStrongs ? attributedParagraphTokens() : attributedParagraph())
                                .font(.system(size: personalData.fontSize, design: .serif))
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Invisible ladder of 20 equal slices
                                // spanning the text's height: paragraph
                                // mode has no per-verse anchors, so the
                                // first referenced verse is reached by
                                // its share of the chapter's text — the
                                // reader's own approximation.
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
                                .padding()
                        }
                        .onChange(of: verses.count) {
                            if let first = target.verses.first,
                               let i = paragraphAnchorIndex(for: first) {
                                proxy.scrollTo("frac-\(i)", anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                // The bottom button sits in the bottom bar
                // with the Strong's dictionary view's back /
                // forward arrow buttons — but as a text button,
                // not a Label: a toolbar Label renders as an
                // icon alone, and this button's words must show.
                ToolbarItem(placement: .bottomBar) {
                    Button("Read More") {
                        onReadChapter()
                        dismiss()
                    }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                // Tapping a Strong's number opens its dictionary
                // entry, as in the reader.
                if url.scheme == "strongs", let key = url.host, !key.isEmpty {
                    strongsKey = key
                    return .handled
                }
                return .systemAction
            })
            .sheet(isPresented: Binding(
                get: { strongsKey != nil },
                set: { if !$0 { strongsKey = nil } }
            )) {
                if let key = strongsKey {
                    StrongsDefinitionView(key: key)
                }
            }
            .task {
                // Verses load last: both modes scroll on their
                // arrival, and everything they render must
                // already be in place by then.
                verseTokens = await version.loadTokens(
                    testament: target.testament,
                    book: target.book,
                    chapter: target.chapter)
                jesusSpans = await version.loadJesusSpans(
                    testament: target.testament,
                    book: target.book,
                    chapter: target.chapter)
                headings = await version.loadHeadings(
                    testament: target.testament,
                    book: target.book,
                    chapter: target.chapter)
                verses = (try? await version.loadChapter(
                    testament: target.testament,
                    book: target.book,
                    chapter: target.chapter)) ?? []
            }
        }
    }

    // MARK: - Rendering (mirrors the reader's, minus its marks)

    /// A section heading as its own row in verse-by-verse
    /// mode: the reading serif, semibold.
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

    private func attributedVerse(number: Int, text: String) -> AttributedString {
        var out = attributedVerseNumber(number)
        out += AttributedString(" ")
        out += AttributedString(text)
        applyRedLetters(to: &out, verse: number)
        applyReferencedHighlight(to: &out, verse: number)
        return out
    }

    /// Whole chapter as one flowing paragraph (paragraph
    /// mode), headings breaking the flow as in the reader.
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

    /// One Strong's number as small raised blue underlined
    /// linked text, exactly as the reader renders it.
    private func attributedStrongsNumber(_ key: String) -> AttributedString {
        var num = AttributedString(" \(key)")
        num.font = .system(size: personalData.fontSize * 0.55, design: .serif)
        num.foregroundColor = .blue
        num.baselineOffset = personalData.fontSize * 0.22
        num.underlineStyle = .single
        num.link = URL(string: "strongs://\(key)")
        return num
    }

    /// Verse text from word tokens, with Strong's numbers
    /// after the segment they belong to and Jesus's speech
    /// red and bold, as in the reader.
    private func attributedVerseTokens(number: Int, tokens: [WordToken]) -> AttributedString {
        var out = attributedVerseNumber(number)
        out += AttributedString(" ")
        for token in tokens {
            var seg = AttributedString(token.text)
            if personalData.showRedLetters, token.isJesusSpeech {
                seg.foregroundColor = Self.redLetterColor
                seg.font = .system(size: personalData.fontSize, design: .serif).weight(.bold)
            }
            out += seg
            for key in token.strongs {
                out += attributedStrongsNumber(key)
            }
        }
        applyReferencedHighlight(to: &out, verse: number)
        return out
    }

    /// Whole chapter as one flowing paragraph from word
    /// tokens, headings breaking the flow as in the reader.
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

    /// The raised verse number prefix, as in the reader.
    private func attributedVerseNumber(_ number: Int) -> AttributedString {
        var num = AttributedString("\(number) ")
        num.font = .system(size: personalData.fontSize * 0.65, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.25
        return num
    }

    /// The ladder slice a verse falls in, by its share of
    /// the chapter's characters — the reader's own math
    /// (REQ-NT-21's paragraph approximation).
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

    /// A referenced verse wears the reader's selection blue
    /// over its text — the treatment a selected verse gets in
    /// the reader — except the verse number itself: the number
    /// is smaller and raised, so its background box is smaller
    /// and shifted up, and painting it leaves a step (a kink)
    /// at the bottom where its box meets the text's box. The
    /// background therefore starts right after the number run.
    private func applyReferencedHighlight(to attr: inout AttributedString, verse: Int) {
        guard target.verses.contains(verse) else { return }
        let numberLength = "\(verse) ".count
        guard attr.characters.count > numberLength else { return }
        let start = attr.index(attr.startIndex, offsetByCharacters: numberLength)
        attr[start..<attr.endIndex].backgroundColor =
            UIColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 0.55)
    }

    /// Red-letter color (REQ-RL-3): deep red on light
    /// backgrounds, brighter on dark — the reader's own.
    private static let redLetterColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.42, blue: 0.36, alpha: 1)
            : UIColor(red: 0.76, green: 0.09, blue: 0.07, alpha: 1)
    })

    /// Paints the verse's Jesus-speech spans red and bold
    /// (REQ-RL-3), in the reader's span coordinates.
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
}
// MARK: - Parallel chapter view

/// The Parallel tab's chapter: one chapter in one version,
/// rendered the way the reference chapter renders it
/// (REQ-PA-6) but embedded in the panel and read-only — no
/// selection, no marks; Strong's numbers still open the
/// dictionary. In sync mode (`sync` non-nil) it reports its
/// top verse to the shared anchor and follows the anchor when
/// the main view moved it (REQ-PA-2); in separate mode it
/// simply scrolls on its own (REQ-PA-3).
private struct ParallelChapterView: View {
    let version: BibleVersion
    let testament: Int
    let book: Int
    let chapter: Int
    /// The shared anchor channel in sync mode; nil in
    /// separate mode.
    let sync: ParallelSyncState?

    @EnvironmentObject private var personalData: PersonalData
    @State private var verses: [(verse: Int, text: String)] = []
    @State private var verseTokens: [(verse: Int, tokens: [WordToken])] = []
    @State private var jesusSpans: [Int: [(start: Int, end: Int)]] = [:]
    @State private var headings: [Int: String] = [:]
    @State private var strongsKey: String?
    /// True while a sync-driven scroll is settling: its own
    /// position reports must not be mistaken for the user
    /// moving the anchor (mirrors ReaderView's flag).
    @State private var applying = false
    @State private var applyGeneration = 0
    /// The verse currently at this view's top.
    @State private var topVerse = 1
    @State private var viewSize: CGSize = .zero

    /// Strong's numbers show exactly when the reader would
    /// show them for this version (the reader's own rule).
    private var useStrongs: Bool {
        personalData.showStrongs && version.supportsStrongs
    }

    private var loadKey: String {
        "\(version.id)|\(testament)|\(book)|\(chapter)"
    }

    private var anchorFromSync: Int { sync?.anchorVerse ?? -1 }
    private var syncIsActive: Bool { sync?.active ?? false }

    var body: some View {
        Group {
            if personalData.verseByVerse {
                verseMode
            } else {
                paragraphMode
            }
        }
        .task(id: loadKey) {
            // Verses load last: everything the renderers read
            // must already be in place when they arrive.
            verseTokens = await version.loadTokens(
                testament: testament, book: book, chapter: chapter)
            jesusSpans = await version.loadJesusSpans(
                testament: testament, book: book, chapter: chapter)
            headings = await version.loadHeadings(
                testament: testament, book: book, chapter: chapter)
            verses = (try? await version.loadChapter(
                testament: testament, book: book, chapter: chapter)) ?? []
        }
        .environment(\.openURL, OpenURLAction { url in
            // Tapping a Strong's number opens its dictionary
            // entry, as in the reader.
            if url.scheme == "strongs", let key = url.host, !key.isEmpty {
                strongsKey = key
                return .handled
            }
            return .systemAction
        })
        .sheet(isPresented: Binding(
            get: { strongsKey != nil },
            set: { if !$0 { strongsKey = nil } }
        )) {
            if let key = strongsKey {
                StrongsDefinitionView(key: key)
            }
        }
    }

    private var verseMode: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if useStrongs {
                        ForEach(verseTokens, id: \.verse) { v in
                            Group {
                                if let heading = headings[v.verse] {
                                    headingRow(heading)
                                }
                                Text(attributedVerseTokens(number: v.verse, tokens: v.tokens))
                                    .id(v.verse)
                                    .reportVerseTop(v.verse, space: "parallelReading",
                                                    enabled: sync != nil)
                                    .font(.system(size: personalData.fontSize, design: .serif))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        ForEach(verses, id: \.verse) { v in
                            Group {
                                if let heading = headings[v.verse] {
                                    headingRow(heading)
                                }
                                Text(attributedVerse(number: v.verse, text: v.text))
                                    .id(v.verse)
                                    .reportVerseTop(v.verse, space: "parallelReading",
                                                    enabled: sync != nil)
                                    .font(.system(size: personalData.fontSize, design: .serif))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding()
            }
            .coordinateSpace(name: "parallelReading")
            .onPreferenceChange(VerseTopFramesKey.self) { frames in
                reportTop(topVisibleVerse(frames: frames, threshold: 20))
            }
            .onChange(of: verses.count) { alignAfterLoad(proxy: proxy) }
            .onChange(of: loadKey) { alignAfterLoad(proxy: proxy) }
            .onChange(of: anchorFromSync) { applyAnchor(proxy: proxy) }
            .onChange(of: syncIsActive) {
                if syncIsActive { applyAnchor(proxy: proxy) }
            }
        }
    }

    private var paragraphMode: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(useStrongs ? attributedParagraphTokens() : attributedParagraph())
                    .font(.system(size: personalData.fontSize, design: .serif))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The same invisible 20-slice ladder the
                    // reference chapter uses for verse jumps.
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
                    // Sync reporting in paragraph mode: the
                    // text's scroll fraction in this view.
                    .background {
                        if sync != nil {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollFractionKey.self,
                                    value: scrollFraction(
                                        frame: geo.frame(in: .named("parallelReading")),
                                        viewportHeight: viewSize.height))
                            }
                        }
                    }
                    .padding()
            }
            .coordinateSpace(name: "parallelReading")
            .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
            .onPreferenceChange(ScrollFractionKey.self) { fraction in
                if let fraction {
                    reportTop(verseAtScrollFraction(fraction))
                }
            }
            .onChange(of: verses.count) { alignAfterLoad(proxy: proxy) }
            .onChange(of: loadKey) { alignAfterLoad(proxy: proxy) }
            .onChange(of: anchorFromSync) { applyAnchor(proxy: proxy) }
            .onChange(of: syncIsActive) {
                if syncIsActive { applyAnchor(proxy: proxy) }
            }
        }
    }

    /// After a (re)load — a new chapter, or the same chapter in
    /// a newly picked version — realign to the shared anchor,
    /// whichever side set it last: the reloaded content starts
    /// wherever the scroll view left it, and sync means the
    /// anchor's verse is at the top.
    private func alignAfterLoad(proxy: ScrollViewProxy) {
        guard let sync, sync.active else { return }
        let anchor = sync.anchorVerse
        guard anchor != topVerse else { return }
        applying = true
        applyGeneration += 1
        let generation = applyGeneration
        if personalData.verseByVerse {
            proxy.scrollTo(anchor, anchor: .top)
        } else if let i = paragraphAnchorIndex(for: anchor) {
            proxy.scrollTo("frac-\(i)", anchor: .top)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if applyGeneration == generation { applying = false }
        }
    }

    /// Follows the shared anchor when the main view moved it.
    private func applyAnchor(proxy: ScrollViewProxy) {
        guard let sync, sync.active, sync.lastMovedByMain else { return }
        let anchor = sync.anchorVerse
        guard anchor != topVerse else { return }
        applying = true
        applyGeneration += 1
        let generation = applyGeneration
        if personalData.verseByVerse {
            proxy.scrollTo(anchor, anchor: .top)
        } else if let i = paragraphAnchorIndex(for: anchor) {
            proxy.scrollTo("frac-\(i)", anchor: .top)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if applyGeneration == generation { applying = false }
        }
    }

    /// Publishes this view's top verse to the shared anchor.
    private func reportTop(_ top: Int?) {
        guard let sync, let top else { return }
        topVerse = top
        guard sync.active, !applying, top != sync.anchorVerse else { return }
        sync.anchorVerse = top
        sync.lastMovedByMain = false
    }

    /// The verse at a scroll fraction of the chapter text, by
    /// character share — the inverse of paragraphAnchorIndex.
    private func verseAtScrollFraction(_ fraction: Double) -> Int {
        guard !verses.isEmpty else { return 1 }
        let total = verses.reduce(0) { $0 + $1.text.count }
        guard total > 0 else { return verses[0].verse }
        var acc = 0.0
        for v in verses {
            acc += Double(v.text.count) / Double(total)
            if fraction < acc { return v.verse }
        }
        return verses[verses.count - 1].verse
    }

    // MARK: - Rendering (mirrors the reference chapter's,
    // minus its referenced-verse highlight)

    private func headingRow(_ heading: String) -> some View {
        Text(heading)
            .font(.system(size: personalData.fontSize, design: .serif).weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributedHeading(_ heading: String) -> AttributedString {
        var run = AttributedString(heading)
        run.font = .system(size: personalData.fontSize, design: .serif).weight(.semibold)
        return run
    }

    private func attributedVerse(number: Int, text: String) -> AttributedString {
        var out = attributedVerseNumber(number)
        out += AttributedString(" ")
        out += AttributedString(text)
        applyRedLetters(to: &out, verse: number)
        return out
    }

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

    private func attributedStrongsNumber(_ key: String) -> AttributedString {
        var num = AttributedString(" \(key)")
        num.font = .system(size: personalData.fontSize * 0.55, design: .serif)
        num.foregroundColor = .blue
        num.baselineOffset = personalData.fontSize * 0.22
        num.underlineStyle = .single
        num.link = URL(string: "strongs://\(key)")
        return num
    }

    private func attributedVerseTokens(number: Int, tokens: [WordToken]) -> AttributedString {
        var out = attributedVerseNumber(number)
        out += AttributedString(" ")
        for token in tokens {
            var seg = AttributedString(token.text)
            if personalData.showRedLetters, token.isJesusSpeech {
                seg.foregroundColor = Self.redLetterColor
                seg.font = .system(size: personalData.fontSize, design: .serif).weight(.bold)
            }
            out += seg
            for key in token.strongs {
                out += attributedStrongsNumber(key)
            }
        }
        return out
    }

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

    private func attributedVerseNumber(_ number: Int) -> AttributedString {
        var num = AttributedString("\(number) ")
        num.font = .system(size: personalData.fontSize * 0.65, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.25
        return num
    }

    /// The ladder slice a verse falls in, by its share of the
    /// chapter's characters — the reader's own math.
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

    /// Red-letter color (REQ-RL-3): deep red on light
    /// backgrounds, brighter on dark — the reader's own.
    private static let redLetterColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.42, blue: 0.36, alpha: 1)
            : UIColor(red: 0.76, green: 0.09, blue: 0.07, alpha: 1)
    })

    /// Paints the verse's Jesus-speech spans red and bold
    /// (REQ-RL-3), in the reader's span coordinates.
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
}

// MARK: - Parallel settings sheet

/// The Parallel tab's settings (REQ-PA-4). One sheet, three
/// forms: the version only (sync mode's gear); version, book,
/// and chapter (separate's gear, and sync's chain on its way
/// to separate); and the version with the main view's book
/// and chapter shown fixed (separate's chain, on its way to
/// sync). Done applies through `onApply`; Cancel dismisses
/// and applies nothing.
private struct ParallelSettingsSheet: View {
    let kind: ParallelSettingsKind
    let versions: [BibleVersion]
    /// The main view's current location: shown fixed by the
    /// to-sync form.
    let mainTarget: ParallelTarget
    let mainBookTitle: String
    /// What Done reports: the chosen version id, and the
    /// chosen target (the full forms only).
    let onApply: (String, ParallelTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftVersionID: String
    @State private var draftOverall: Int
    @State private var draftChapter: Int

    init(kind: ParallelSettingsKind,
         versions: [BibleVersion],
         mainTarget: ParallelTarget,
         mainBookTitle: String,
         initialVersionID: String,
         initialTarget: ParallelTarget,
         onApply: @escaping (String, ParallelTarget) -> Void) {
        self.kind = kind
        self.versions = versions
        self.mainTarget = mainTarget
        self.mainBookTitle = mainBookTitle
        self.onApply = onApply
        _draftVersionID = State(initialValue: initialVersionID)
        _draftOverall = State(initialValue: initialTarget.overall)
        _draftChapter = State(initialValue: initialTarget.chapter)
    }

    private var showsTargetFields: Bool {
        kind == .separate || kind == .toSeparate
    }

    private var title: String {
        switch kind {
        case .syncVersion: return "Sync Version"
        case .toSync: return "Sync View"
        case .separate, .toSeparate: return "Separate View"
        }
    }

    private var draftVersion: BibleVersion? {
        versions.first { $0.id == draftVersionID } ?? versions.first
    }

    private var draftChapterCount: Int {
        guard let v = draftVersion else { return 1 }
        let t = ParallelTarget(overall: draftOverall, chapter: 1)
        return max(1, v.chapterCount(testament: t.testament, book: t.book))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Version") {
                    ForEach(versions, id: \.id) { v in
                        Button {
                            draftVersionID = v.id
                        } label: {
                            HStack {
                                Text(v.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if v.id == draftVersionID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                if showsTargetFields, let dv = draftVersion {
                    Section("Passage") {
                        Picker("Book", selection: $draftOverall) {
                            Section("Old Testament") {
                                ForEach(0..<39, id: \.self) { i in
                                    Text(dv.bookName(overall: i)).tag(i)
                                }
                            }
                            Section("New Testament") {
                                ForEach(39..<66, id: \.self) { i in
                                    Text(dv.bookName(overall: i)).tag(i)
                                }
                            }
                        }
                        Picker("Chapter", selection: $draftChapter) {
                            ForEach(1...draftChapterCount, id: \.self) { c in
                                Text("\(c)").tag(c)
                            }
                        }
                    }
                }
                if kind == .toSync {
                    Section("Passage") {
                        LabeledContent("Book", value: mainBookTitle)
                            .foregroundStyle(.secondary)
                        LabeledContent("Chapter", value: "\(mainTarget.chapter)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onApply(draftVersionID,
                                ParallelTarget(overall: draftOverall,
                                               chapter: draftChapter))
                        dismiss()
                    }
                }
            }
            .onChange(of: draftOverall) {
                if draftChapter > draftChapterCount {
                    draftChapter = draftChapterCount
                }
            }
        }
    }
}

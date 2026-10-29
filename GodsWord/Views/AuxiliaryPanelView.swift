// AuxiliaryPanelView.swift — the panel below the reading panel.
// Four tabs: Notes, Commentary, the selected verse rendered with
// Strong's numbers, and Recents (the reading history). The Notes tab
// has Recents / Book / Chapter / Verse sub-tabs (REQ-NT-18) over the
// scoped notes (REQ-NT-14); Commentary has Book / Chapter / Verse
// sub-tabs (REQ-AP-1..11) showing the entries at those scopes.
//
// The panel never alters the main reading text; it only reads the
// shared ReadingHistory, the verse selection, and PersonalData.

import SwiftUI
import UIKit
import SwordReader

struct AuxiliaryPanelView: View {
    let history: ReadingHistory
    /// Verses selected in the reader; the Verse scopes anchor at the
    /// lowest selected verse (verse 1 when nothing is selected).
    let selectedVerses: Set<Int>
    /// All installed Bible versions (for the Strong's source resolution).
    let availableVersions: [BibleVersion]
    /// Owned by ReaderView: the toggle button lives in the reader's
    /// bottom bar, next to the chapter controls (REQ-AP-1). When
    /// collapsed, the panel renders nothing at all.
    @Binding var collapsed: Bool

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

    enum PanelTab: String, CaseIterable {
        case notes = "Notes"
        case commentary = "Commentary"
        case strongs = "Strong's"
        case recents = "Recents"
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

    /// The expanded panel: the tab bar plus the selected tab's content.
    private var expandedBody: some View {
        VStack(spacing: 0) {
            Divider()
            Picker("Panel", selection: $tab) {
                ForEach(PanelTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                switch tab {
                case .notes: notesTab
                case .commentary: commentaryTab
                case .strongs: strongsTab
                case .recents: recentsTab
                }
            }
            .frame(height: 264)
        }
        .background(.regularMaterial)
        .onAppear {
            commentaries = CommentaryModule.allInstalled(in: store)
            expandedBookChapters = [history.chapter]
        }
        .sheet(item: $editorItem) { item in
            switch item {
            case .verse(let key, let reference):
                VerseNoteEditor(reference: reference, noteKey: key,
                                initialText: personalData.verseNote(forKey: key) ?? "",
                                seedText: "\(history.bookTitle) \(history.chapter)\n",
                                sourceModuleID: history.version.id)
                    .environmentObject(personalData)
            case .book(let key, let reference):
                ScopedNoteEditor(reference: reference,
                                 initialText: personalData.bookNote(forKey: key) ?? "") { text in
                    personalData.setBookNote(text, forKey: key,
                                             source: history.version.id)
                }
            case .chapter(let key, let reference):
                ScopedNoteEditor(reference: reference,
                                 initialText: personalData.chapterNote(forKey: key) ?? "") { text in
                    personalData.setChapterNote(text, forKey: key,
                                                source: history.version.id)
                }
            }
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
        NoteRow(kind: .book, key: key,
                reference: "\(bookName(testament: parsed.testament, book: parsed.book)) — Book note",
                text: personalData.bookNotes[key] ?? "",
                source: personalData.noteSources[key],
                updated: personalData.bookNoteTimes[key]?.updatedAt)
    }

    private func chapterNoteRow(key: String, parsed: ChapterNoteKey.Parsed) -> NoteRow {
        NoteRow(kind: .chapter, key: key,
                reference: "\(bookName(testament: parsed.testament, book: parsed.book)) \(parsed.chapter) — Chapter note",
                text: personalData.chapterNotes[key] ?? "",
                source: personalData.noteSources[key],
                updated: personalData.chapterNoteTimes[key]?.updatedAt)
    }

    private func verseNoteRow(key: String, parsed: NoteKey.Parsed) -> NoteRow {
        NoteRow(kind: .verse, key: key,
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

    private func noteRowView(_ row: NoteRow) -> some View {
        Button {
            switch row.kind {
            case .book: editorItem = .book(key: row.key, reference: row.reference)
            case .chapter: editorItem = .chapter(key: row.key, reference: row.reference)
            case .verse: editorItem = .verse(key: row.key, reference: row.reference)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.reference + sourceSuffix(row.source)
                     + noteDateSuffix(row.updated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(row.text)
                    .font(.system(size: personalData.fontSize, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func noteList(_ rows: [NoteRow]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    noteRowView(row)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// The Book sub-tab: an add-book-note entry when the book has no
    /// book note yet, then every note in the book.
    private var bookNotesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if personalData.bookNote(forKey: bookNoteKey) == nil {
                    Button {
                        editorItem = .book(key: bookNoteKey, reference: history.bookTitle)
                    } label: {
                        Label("Add Book Note", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                }
                ForEach(bookNoteRows) { row in
                    noteRowView(row)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var notesTab: some View {
        VStack(spacing: 0) {
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
                // The add-note entry point: always available, even
                // when the Verse sub-tab is hidden or there are no
                // notes at all (REQ-NT-18). It edits the anchor
                // verse's note — adding one when there is none.
                Button {
                    editorItem = .verse(key: verseNoteKey, reference: verseReference)
                } label: {
                    Label(personalData.verseNote(forKey: verseNoteKey) == nil
                          ? "Add Note" : "Edit Note",
                          systemImage: "square.and.pencil")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

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

    /// One scoped note: its text (scrollable) and an Edit/Add button.
    private func scopedNote(reference: String, text: String?,
                            emptyText: String,
                            updated: Date? = nil,
                            edit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reference + noteDateSuffix(updated)).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(text == nil ? "Add" : "Edit") { edit() }
                    .font(.subheadline)
            }
            if let text {
                ScrollView {
                    Text(text)
                        .font(.system(size: personalData.fontSize, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                Text(emptyText).foregroundStyle(.secondary)
                Spacer()
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
    /// applies (REQ-NT-16), an add-chapter-note entry when the
    /// chapter has no chapter note, and the chapter's notes in
    /// reading order.
    private var chapterNotesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if personalData.chapterNote(forKey: chapterNoteKey) == nil,
                   let legacy = personalData.verseNote(forKey: verse1NoteKey) {
                    legacyChapterNote(legacy)
                } else if personalData.chapterNote(forKey: chapterNoteKey) == nil {
                    Button {
                        editorItem = .chapter(
                            key: chapterNoteKey,
                            reference: "\(history.bookTitle) \(history.chapter)")
                    } label: {
                        Label("Add Chapter Note", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                }
                ForEach(chapterNoteRows) { row in
                    noteRowView(row)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
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
        }
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
                        commentaryEntry(entry, reference: "\(history.bookTitle) \(history.chapter)")
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
                                commentaryEntry(entry, reference: "\(history.bookTitle) \(history.chapter)")
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
                                                commentaryEntry(entry, reference: "\(history.bookTitle) \(section.chapter)")
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

    /// One commentary entry with its verse-range reference.
    private func commentaryEntry(_ entry: CommentaryGrouping.Entry,
                                 reference: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.startVerse == entry.endVerse
                 ? "\(reference):\(entry.startVerse)"
                 : "\(reference):\(entry.startVerse)-\(entry.endVerse)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.text)
                .font(.system(size: personalData.fontSize, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
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
                let rows = try await mod.loadChapter(testament: history.testament,
                                                     book: history.book,
                                                     chapter: history.chapter)
                commentaryChapter = CommentaryGrouping.group(rows)
            case .book:
                let count = mod.chapterCount(testament: history.testament,
                                              book: history.book)
                let chapters = count > 0 ? count : history.chapterCount
                var sections: [BookSection] = []
                if chapters > 0 {
                    for c in 1 ... chapters {
                        let rows = try await mod.loadChapter(testament: history.testament,
                                                             book: history.book,
                                                             chapter: c)
                        sections.append(BookSection(
                            chapter: c,
                            entries: CommentaryGrouping.group(rows)))
                    }
                }
                commentaryBook = sections
            }
            commentaryError = nil
        } catch {
            // A module that can't be opened (damaged, missing,
            // unsupported) is an error state, not an empty chapter
            // (REQ-AP-13).
            commentaryChapter = []
            commentaryBook = []
            commentaryError = "The \(mod.shortLabel) module couldn't be opened. "
                + "It may be damaged or missing — re-downloading it from the "
                + "repository usually fixes this. (\(error.localizedDescription))"
        }
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
                n.foregroundColor = .secondary
                n.baselineOffset = personalData.fontSize * 0.22
                n.underlineStyle = []
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
    /// left drawer: the same HistoryView list — tap an entry to jump
    /// back to it (switching version when that version is installed),
    /// swipe to delete. HistoryView's own Clear toolbar button needs
    /// a navigation bar, so the tab header carries Clear instead.
    private var recentsTab: some View {
        VStack(spacing: 0) {
            if !personalData.historyLog.isEmpty {
                HStack {
                    Text("Reading history")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", role: .destructive) {
                        personalData.clearHistory()
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            HistoryView(onSelect: jumpToHistoryEntry)
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
}

/// Editor for a book- or chapter-level note (REQ-NT-14). Mirrors
/// VerseNoteEditor's behavior — self-contained text, Save/Delete via
/// the `onSave` closure (nil = delete) — without a storage key, so the
/// caller decides which scoped store the note belongs to.
struct ScopedNoteEditor: View {
    let reference: String
    private let originalText: String
    private let onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text: String
    @State private var showingDeleteConfirm = false

    init(reference: String, initialText: String,
         onSave: @escaping (String?) -> Void) {
        self.reference = reference
        self.originalText = initialText
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .padding()
                .navigationTitle(reference)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        if !originalText.isEmpty {
                            Button("Delete", role: .destructive) {
                                showingDeleteConfirm = true
                            }
                        }
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                        .disabled(text == originalText)
                    }
                }
                .confirmationDialog("Delete this note?",
                                    isPresented: $showingDeleteConfirm,
                                    titleVisibility: .visible) {
                    Button("Delete Note", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isFocused = true
                    }
                }
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

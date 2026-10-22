// AuxiliaryPanelView.swift — the panel below the reading panel.
// Four tabs: Notes, Commentary, the selected verse rendered with
// Strong's numbers, and Recents (the reading history). Notes and
// Commentary both have Book / Chapter / Verse sub-tabs (REQ-AP-1..11):
// notes are scoped notes at those three levels (REQ-NT-14); commentary
// shows the entries at those scopes.
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
    @State private var notesScope: PanelScope = .verse
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
                                seedText: "\(history.bookTitle) \(history.chapter)\n")
                    .environmentObject(personalData)
            case .book(let key, let reference):
                ScopedNoteEditor(reference: reference,
                                 initialText: personalData.bookNote(forKey: key) ?? "") { text in
                    personalData.setBookNote(text, forKey: key)
                }
            case .chapter(let key, let reference):
                ScopedNoteEditor(reference: reference,
                                 initialText: personalData.chapterNote(forKey: key) ?? "") { text in
                    personalData.setChapterNote(text, forKey: key)
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

    /// Whether the Notes tab has any note for the current location —
    /// a book or chapter note, a legacy verse-1 note, or any verse note
    /// in this chapter. The scope sub-tabs only appear when there is
    /// at least one entry (REQ-AP-9); with none, the tab falls back to
    /// the Verse scope so the first note can still be added.
    private var notesHasEntries: Bool {
        if personalData.bookNote(forKey: bookNoteKey) != nil { return true }
        if personalData.chapterNote(forKey: chapterNoteKey) != nil { return true }
        if personalData.verseNote(forKey: verse1NoteKey) != nil { return true }
        let prefix = "\(history.version.id):\(history.testament):\(history.book):\(history.chapter):"
        return personalData.verseNotes.keys.contains { $0.hasPrefix(prefix) }
    }

    private var notesTab: some View {
        VStack(spacing: 0) {
            if notesHasEntries {
                scopePicker(selection: $notesScope)
            }
            switch notesHasEntries ? notesScope : .verse {
            case .book:
                scopedNote(reference: history.bookTitle,
                           text: personalData.bookNote(forKey: bookNoteKey),
                           emptyText: "No note for this book yet.") {
                    editorItem = .book(key: bookNoteKey, reference: history.bookTitle)
                }
            case .chapter:
                chapterNoteView
            case .verse:
                scopedNote(reference: verseReference,
                           text: personalData.verseNote(forKey: verseNoteKey),
                           emptyText: "No note for this verse yet.") {
                    editorItem = .verse(key: verseNoteKey, reference: verseReference)
                }
            }
        }
    }

    /// One scoped note: its text (scrollable) and an Edit/Add button.
    private func scopedNote(reference: String, text: String?,
                            emptyText: String,
                            edit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reference).font(.subheadline).foregroundStyle(.secondary)
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
        personalData.bookNoteKey(moduleID: history.version.id,
                                 testament: history.testament,
                                 book: history.book)
    }

    private var chapterNoteKey: String {
        personalData.chapterNoteKey(moduleID: history.version.id,
                                    testament: history.testament,
                                    book: history.book,
                                    chapter: history.chapter)
    }

    private var verseNoteKey: String {
        personalData.verseNoteKey(moduleID: history.version.id,
                                  testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter,
                                  verse: anchorVerse)
    }

    /// The verse-1 note key for this chapter — where chapter notes
    /// were stored before scoped chapter notes (REQ-NT-16).
    private var verse1NoteKey: String {
        personalData.verseNoteKey(moduleID: history.version.id,
                                  testament: history.testament,
                                  book: history.book,
                                  chapter: history.chapter,
                                  verse: 1)
    }

    /// The Chapter scope of the Notes tab. When no chapter note exists
    /// yet but the chapter has a note on verse 1, that note is shown
    /// as a legacy note (REQ-NT-16): before scoped notes, the reader's
    /// "Take Notes" stored chapter notes as verse-1 notes, and the two
    /// are indistinguishable, so nothing migrates automatically — the
    /// user moves it with one tap instead.
    @ViewBuilder
    private var chapterNoteView: some View {
        let reference = "\(history.bookTitle) \(history.chapter)"
        if let text = personalData.chapterNote(forKey: chapterNoteKey) {
            scopedNote(reference: reference, text: text, emptyText: "") {
                editorItem = .chapter(key: chapterNoteKey, reference: reference)
            }
        } else if let legacy = personalData.verseNote(forKey: verse1NoteKey) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(reference).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") {
                        editorItem = .chapter(key: chapterNoteKey, reference: reference)
                    }
                    .font(.subheadline)
                }
                Text("This note is saved on verse 1 — before chapter notes existed, that is where chapter notes were stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(legacy)
                        .font(.system(size: personalData.fontSize, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                Button("Move to Chapter Note") {
                    personalData.setChapterNote(legacy, forKey: chapterNoteKey)
                    personalData.setVerseNote(nil, forKey: verse1NoteKey)
                }
                .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else {
            scopedNote(reference: reference, text: nil,
                       emptyText: "No note for this chapter yet.") {
                editorItem = .chapter(key: chapterNoteKey, reference: reference)
            }
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
                if commentaryHasEntries || commentaryLoading {
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
        switch commentaryScope {
        case .verse, .chapter:
            let rows = await mod.loadChapter(testament: history.testament,
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
                    let rows = await mod.loadChapter(testament: history.testament,
                                                     book: history.book,
                                                     chapter: c)
                    sections.append(BookSection(
                        chapter: c,
                        entries: CommentaryGrouping.group(rows)))
                }
            }
            commentaryBook = sections
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

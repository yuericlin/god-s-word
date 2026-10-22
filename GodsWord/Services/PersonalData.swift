// PersonalData.swift
// All personal data lives in iPhone local storage by default:
// - Settings and reading positions: UserDefaults (suite-local)
// - Downloaded modules: Application Support/Modules (see ModuleStore)
// The BackupPayload below is what gets synced to Google Drive
// when the user consents and signs in.

import Foundation
import SwordReader

/// Where the user left off in a module: testament/book/chapter (1-based).
public struct ReadingPosition: Codable, Sendable {
    public var testament: Int
    public var book: Int
    public var chapter: Int
    public init(testament: Int, book: Int, chapter: Int) {
        self.testament = testament; self.book = book; self.chapter = chapter
    }
}

/// One entry in the reading history: a chapter with every visit (within
/// 24 hours of the first) and every version read. See ReadingHistoryLog.
public typealias HistoryEntry = ReadingHistoryEntry

/// Creation / last-edit times for one note (REQ-NT-17). `createdAt`
/// is nil for notes written before timestamps existed; their first
/// later edit stamps `updatedAt` only.
public struct NoteTimes: Codable, Sendable {
    public var createdAt: Date?
    public var updatedAt: Date
    public init(createdAt: Date?, updatedAt: Date) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Everything synced to Google Drive. Module *contents* are not included;
/// the backup records which module IDs were installed so they can be
/// re-downloaded from the repository on restore.
public struct BackupPayload: Codable, Sendable {
    public var version: Int = 9
    public var fontSize: Double
    public var verseByVerse: Bool
    public var showStrongs: Bool
    public var positions: [String: ReadingPosition]  // moduleID -> position
    public var installedModuleIDs: [String]
    public var bookmarks: [Bookmark]
    public var verseNotes: [String: String]
    /// Note keys, most recently saved first (the panel's list order).
    public var verseNoteOrder: [String]
    /// Versions the Compare panel shows besides the current one.
    public var compareVersionIDs: [String]
    /// Book-level notes (REQ-NT-14), keyed like BookNoteKey.
    public var bookNotes: [String: String]
    /// Chapter-level notes (REQ-NT-14), keyed like ChapterNoteKey.
    public var chapterNotes: [String: String]
    /// Note creation/edit times (REQ-NT-17), keyed like the notes.
    public var verseNoteTimes: [String: NoteTimes]
    public var bookNoteTimes: [String: NoteTimes]
    public var chapterNoteTimes: [String: NoteTimes]
    /// Commentary module the auxiliary panel shows (REQ-AP-4); "" = none.
    public var commentaryModuleID: String
    /// Fallback Strong's version for the panel (REQ-AP-7); "" = automatic.
    public var strongsFallbackVersionID: String
    /// Primary language codes the download lists are filtered to
    /// (REQ-LG-1); empty = no filtering.
    public var interestedLanguages: [String]
    /// Dictionaries for Strong's lookups (REQ-DC-2); "" = automatic
    /// (StrongsHebrew / StrongsGreek).
    public var dictionaryHebrewID: String
    public var dictionaryGreekID: String
    public var backedUpAt: Date

    public init(fontSize: Double, verseByVerse: Bool = false, showStrongs: Bool = false,
                positions: [String: ReadingPosition], installedModuleIDs: [String],
                bookmarks: [Bookmark] = [], verseNotes: [String: String] = [:],
                verseNoteOrder: [String] = [],
                compareVersionIDs: [String] = [],
                bookNotes: [String: String] = [:],
                chapterNotes: [String: String] = [:],
                verseNoteTimes: [String: NoteTimes] = [:],
                bookNoteTimes: [String: NoteTimes] = [:],
                chapterNoteTimes: [String: NoteTimes] = [:],
                commentaryModuleID: String = "",
                strongsFallbackVersionID: String = "",
                interestedLanguages: [String] = [],
                dictionaryHebrewID: String = "",
                dictionaryGreekID: String = "",
                backedUpAt: Date) {
        self.fontSize = fontSize
        self.verseByVerse = verseByVerse
        self.showStrongs = showStrongs
        self.positions = positions
        self.installedModuleIDs = installedModuleIDs
        self.bookmarks = bookmarks
        self.verseNotes = verseNotes
        self.verseNoteOrder = verseNoteOrder
        self.compareVersionIDs = compareVersionIDs
        self.bookNotes = bookNotes
        self.chapterNotes = chapterNotes
        self.verseNoteTimes = verseNoteTimes
        self.bookNoteTimes = bookNoteTimes
        self.chapterNoteTimes = chapterNoteTimes
        self.commentaryModuleID = commentaryModuleID
        self.strongsFallbackVersionID = strongsFallbackVersionID
        self.interestedLanguages = interestedLanguages
        self.dictionaryHebrewID = dictionaryHebrewID
        self.dictionaryGreekID = dictionaryGreekID
        self.backedUpAt = backedUpAt
    }

    // Custom decoding so backups written before verseByVerse / showStrongs /
    // bookmarks / verseNotes / compareVersionIDs existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        verseByVerse = try c.decodeIfPresent(Bool.self, forKey: .verseByVerse) ?? false
        showStrongs = try c.decodeIfPresent(Bool.self, forKey: .showStrongs) ?? false
        positions = try c.decode([String: ReadingPosition].self, forKey: .positions)
        installedModuleIDs = try c.decode([String].self, forKey: .installedModuleIDs)
        bookmarks = try c.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        verseNotes = try c.decodeIfPresent([String: String].self, forKey: .verseNotes) ?? [:]
        verseNoteOrder = try c.decodeIfPresent([String].self, forKey: .verseNoteOrder) ?? []
        compareVersionIDs = try c.decodeIfPresent([String].self, forKey: .compareVersionIDs) ?? []
        bookNotes = try c.decodeIfPresent([String: String].self, forKey: .bookNotes) ?? [:]
        chapterNotes = try c.decodeIfPresent([String: String].self, forKey: .chapterNotes) ?? [:]
        verseNoteTimes = try c.decodeIfPresent([String: NoteTimes].self, forKey: .verseNoteTimes) ?? [:]
        bookNoteTimes = try c.decodeIfPresent([String: NoteTimes].self, forKey: .bookNoteTimes) ?? [:]
        chapterNoteTimes = try c.decodeIfPresent([String: NoteTimes].self, forKey: .chapterNoteTimes) ?? [:]
        commentaryModuleID = try c.decodeIfPresent(String.self, forKey: .commentaryModuleID) ?? ""
        strongsFallbackVersionID = try c.decodeIfPresent(String.self, forKey: .strongsFallbackVersionID) ?? ""
        interestedLanguages = try c.decodeIfPresent([String].self, forKey: .interestedLanguages) ?? []
        dictionaryHebrewID = try c.decodeIfPresent(String.self, forKey: .dictionaryHebrewID) ?? ""
        dictionaryGreekID = try c.decodeIfPresent(String.self, forKey: .dictionaryGreekID) ?? ""
        backedUpAt = try c.decode(Date.self, forKey: .backedUpAt)
    }
}

@MainActor
public final class PersonalData: ObservableObject {
    private let defaults: UserDefaults
    private let positionsKey = "gw.readingPositions.v1"
    private let fontSizeKey = "gw.fontSize.v1"
    private let verseByVerseKey = "gw.verseByVerse.v1"
    private let showStrongsKey = "gw.showStrongs.v1"
    private let historyLogKey = "gw.historyLog.v1"
    private let lastReadingKey = "gw.lastReading.v1"
    private let bookmarksKey = "gw.bookmarks.v1"
    private let verseNotesKey = "gw.verseNotes.v1"
    private let verseNoteOrderKey = "gw.verseNoteOrder.v1"
    private let compareVersionsKey = "gw.compareVersions.v1"
    private let bookNotesKey = "gw.bookNotes.v1"
    private let chapterNotesKey = "gw.chapterNotes.v1"
    private let verseNoteTimesKey = "gw.verseNoteTimes.v1"
    private let bookNoteTimesKey = "gw.bookNoteTimes.v1"
    private let chapterNoteTimesKey = "gw.chapterNoteTimes.v1"
    private let commentaryModuleKey = "gw.commentaryModule.v1"
    private let strongsFallbackKey = "gw.strongsFallbackVersion.v1"
    private let interestedLanguagesKey = "gw.interestedLanguages.v1"
    private let dictionaryHebrewKey = "gw.dictionaryHebrew.v1"
    private let dictionaryGreekKey = "gw.dictionaryGreek.v1"
    private let maxHistoryEntries = 100

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: fontSizeKey)
        self.fontSize = saved > 0 ? saved : 19
        self.verseByVerse = defaults.bool(forKey: verseByVerseKey)
        self.showStrongs = defaults.bool(forKey: showStrongsKey)
        let log: [HistoryEntry]
        if let data = defaults.data(forKey: "gw.historyLog.v1"),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            log = ReadingHistoryLog.combined(decoded)
        } else {
            log = []
        }
        self.historyLog = log
        let marks: [Bookmark]
        if let data = defaults.data(forKey: "gw.bookmarks.v1"),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            marks = decoded
        } else {
            // Fresh install: start with zero bookmarks.
            marks = []
            defaults.set(try? JSONEncoder().encode(marks), forKey: "gw.bookmarks.v1")
        }
        self.bookmarks = marks
        self.verseNotes = defaults.dictionary(forKey: verseNotesKey) as? [String: String] ?? [:]
        self.verseNoteOrder = defaults.stringArray(forKey: verseNoteOrderKey) ?? []
        self.compareVersionIDs = defaults.stringArray(forKey: compareVersionsKey) ?? []
        self.bookNotes = defaults.dictionary(forKey: bookNotesKey) as? [String: String] ?? [:]
        self.chapterNotes = defaults.dictionary(forKey: chapterNotesKey) as? [String: String] ?? [:]
        self.verseNoteTimes = Self.decodeNoteTimes(defaults, verseNoteTimesKey)
        self.bookNoteTimes = Self.decodeNoteTimes(defaults, bookNoteTimesKey)
        self.chapterNoteTimes = Self.decodeNoteTimes(defaults, chapterNoteTimesKey)
        self.commentaryModuleID = defaults.string(forKey: commentaryModuleKey) ?? ""
        self.strongsFallbackVersionID = defaults.string(forKey: strongsFallbackKey) ?? ""
        self.interestedLanguages = defaults.stringArray(forKey: interestedLanguagesKey) ?? []
        self.dictionaryHebrewID = defaults.string(forKey: dictionaryHebrewKey) ?? ""
        self.dictionaryGreekID = defaults.string(forKey: dictionaryGreekKey) ?? ""
    }

    @Published public var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: fontSizeKey) }
    }

    /// When true, each verse renders on its own line; when false (default),
    /// the chapter flows as paragraphs (currently one paragraph per chapter,
    /// since modules carry no paragraph info).
    @Published public var verseByVerse: Bool {
        didSet { defaults.set(verseByVerse, forKey: verseByVerseKey) }
    }

    /// When true (default false), Strong's numbers show after words in
    /// modules that support them, and tapping a number opens its dictionary
    /// entry.
    @Published public var showStrongs: Bool {
        didSet { defaults.set(showStrongs, forKey: showStrongsKey) }
    }

    /// Full reading history, most recent first. Persisted in UserDefaults.
    @Published public var historyLog: [HistoryEntry] {
        didSet {
            defaults.set(try? JSONEncoder().encode(historyLog), forKey: historyLogKey)
            syncHistoryToiCloud()
        }
    }

    /// Named ribbon bookmarks. Persisted in UserDefaults.
    @Published public var bookmarks: [Bookmark] {
        didSet {
            defaults.set(try? JSONEncoder().encode(bookmarks), forKey: bookmarksKey)
            syncBookmarksToiCloud()
        }
    }

    /// Per-verse text notes, keyed by
    /// "<moduleID>:<testament>:<book>:<chapter>:<verse>".
    /// Persisted in UserDefaults.
    @Published public var verseNotes: [String: String] {
        didSet {
            defaults.set(verseNotes, forKey: verseNotesKey)
            syncNotesToiCloud()
        }
    }

    /// Verse-note keys ordered most-recently-saved first (notes
    /// missing from the list sort last, in canonical order).
    /// Maintained by `setVerseNote`.
    @Published public var verseNoteOrder: [String] {
        didSet { defaults.set(verseNoteOrder, forKey: verseNoteOrderKey) }
    }

    /// Ids of the versions the Compare panel shows besides the one being
    /// read. Empty (the default) means Compare shows only the current
    /// version. Persisted in UserDefaults.
    @Published public var compareVersionIDs: [String] {
        didSet { defaults.set(compareVersionIDs, forKey: compareVersionsKey) }
    }

    /// Adds or removes a version from the Compare setting.
    public func toggleCompareVersion(_ id: String) {
        if let i = compareVersionIDs.firstIndex(of: id) {
            compareVersionIDs.remove(at: i)
        } else {
            compareVersionIDs.append(id)
        }
    }

    /// Book-level notes (REQ-NT-14), keyed by
    /// "<moduleID>:<testament>:<book>" (see BookNoteKey). One note per
    /// book per version, alongside the chapter- and verse-level notes.
    /// Persisted in UserDefaults.
    @Published public var bookNotes: [String: String] {
        didSet {
            defaults.set(bookNotes, forKey: bookNotesKey)
            syncBookNotesToiCloud()
        }
    }

    /// Chapter-level notes (REQ-NT-14), keyed by
    /// "<moduleID>:<testament>:<book>:<chapter>" (see ChapterNoteKey).
    /// Persisted in UserDefaults.
    @Published public var chapterNotes: [String: String] {
        didSet {
            defaults.set(chapterNotes, forKey: chapterNotesKey)
            syncChapterNotesToiCloud()
        }
    }

    /// Creation / last-edit times for verse notes (REQ-NT-17), keyed
    /// like `verseNotes`. Maintained by `setVerseNote`.
    /// Persisted in UserDefaults.
    @Published public var verseNoteTimes: [String: NoteTimes] {
        didSet {
            defaults.set(try? JSONEncoder().encode(verseNoteTimes), forKey: verseNoteTimesKey)
            syncVerseNoteTimesToiCloud()
        }
    }

    /// Creation / last-edit times for book notes (REQ-NT-17).
    @Published public var bookNoteTimes: [String: NoteTimes] {
        didSet {
            defaults.set(try? JSONEncoder().encode(bookNoteTimes), forKey: bookNoteTimesKey)
            syncBookNoteTimesToiCloud()
        }
    }

    /// Creation / last-edit times for chapter notes (REQ-NT-17).
    @Published public var chapterNoteTimes: [String: NoteTimes] {
        didSet {
            defaults.set(try? JSONEncoder().encode(chapterNoteTimes), forKey: chapterNoteTimesKey)
            syncChapterNoteTimesToiCloud()
        }
    }

    private static func decodeNoteTimes(_ defaults: UserDefaults,
                                        _ key: String) -> [String: NoteTimes] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: NoteTimes].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Applies the REQ-NT-17 stamping rules for one note key: a first
    /// save sets both times, saving changed text moves only
    /// `updatedAt`, saving identical text changes nothing. A note
    /// that predates timestamps has no times entry; its first later
    /// edit stamps `updatedAt` with `createdAt` left nil.
    private func stampedTimes(_ times: [String: NoteTimes], key: String,
                              isNew: Bool, changed: Bool) -> [String: NoteTimes] {
        guard isNew || changed else { return times }
        var t = times
        let now = Date()
        if isNew {
            t[key] = NoteTimes(createdAt: now, updatedAt: now)
        } else if var existing = t[key] {
            existing.updatedAt = now
            t[key] = existing
        } else {
            t[key] = NoteTimes(createdAt: nil, updatedAt: now)
        }
        return t
    }

    /// The commentary module the auxiliary panel shows (REQ-AP-4).
    /// "" means none chosen: the panel uses the first installed
    /// renderable commentary. Persisted in UserDefaults.
    @Published public var commentaryModuleID: String {
        didSet { defaults.set(commentaryModuleID, forKey: commentaryModuleKey) }
    }

    /// Version whose Strong's numbers render the selected verse in the
    /// auxiliary panel when the version being read has none (REQ-AP-7).
    /// "" means automatic: the first installed Strong's version.
    /// Persisted in UserDefaults.
    @Published public var strongsFallbackVersionID: String {
        didSet { defaults.set(strongsFallbackVersionID, forKey: strongsFallbackKey) }
    }

    /// Primary language codes the download lists are filtered to
    /// (REQ-LG-1), e.g. ["en", "zh"]. Empty means no filtering.
    /// Persisted in UserDefaults.
    @Published public var interestedLanguages: [String] {
        didSet { defaults.set(interestedLanguages, forKey: interestedLanguagesKey) }
    }

    /// Dictionaries used for Strong's lookups (REQ-DC-2): the module
    /// IDs serving Hebrew ("H") and Greek ("G") keys. "" means
    /// automatic — StrongsHebrew / StrongsGreek. Persisted in
    /// UserDefaults.
    @Published public var dictionaryHebrewID: String {
        didSet { defaults.set(dictionaryHebrewID, forKey: dictionaryHebrewKey) }
    }

    @Published public var dictionaryGreekID: String {
        didSet { defaults.set(dictionaryGreekID, forKey: dictionaryGreekKey) }
    }

    /// Builds the storage key for a book-level note.
    public func bookNoteKey(moduleID: String, testament: Int, book: Int) -> String {
        BookNoteKey.make(moduleID: moduleID, testament: testament, book: book)
    }

    /// Returns the book-level note for a key, or nil when there is none.
    public func bookNote(forKey key: String) -> String? {
        let note = bookNotes[key]
        return (note?.isEmpty ?? true) ? nil : note
    }

    /// Stores a book-level note; an empty/nil text removes it (and
    /// its times). Saves stamp the note's times (REQ-NT-17).
    public func setBookNote(_ text: String?, forKey key: String) {
        if let text, !text.isEmpty {
            let old = bookNotes[key]
            bookNotes[key] = text
            bookNoteTimes = stampedTimes(bookNoteTimes, key: key,
                                         isNew: old == nil, changed: old != text)
        } else {
            bookNotes.removeValue(forKey: key)
            bookNoteTimes.removeValue(forKey: key)
        }
    }

    /// Builds the storage key for a chapter-level note.
    public func chapterNoteKey(moduleID: String, testament: Int, book: Int,
                               chapter: Int) -> String {
        ChapterNoteKey.make(moduleID: moduleID, testament: testament,
                            book: book, chapter: chapter)
    }

    /// Returns the chapter-level note for a key, or nil when there is none.
    public func chapterNote(forKey key: String) -> String? {
        let note = chapterNotes[key]
        return (note?.isEmpty ?? true) ? nil : note
    }

    /// Stores a chapter-level note; an empty/nil text removes it (and
    /// its times). Saves stamp the note's times (REQ-NT-17).
    public func setChapterNote(_ text: String?, forKey key: String) {
        if let text, !text.isEmpty {
            let old = chapterNotes[key]
            chapterNotes[key] = text
            chapterNoteTimes = stampedTimes(chapterNoteTimes, key: key,
                                            isNew: old == nil, changed: old != text)
        } else {
            chapterNotes.removeValue(forKey: key)
            chapterNoteTimes.removeValue(forKey: key)
        }
    }

    /// Builds the storage key for a verse note.
    public func verseNoteKey(moduleID: String, testament: Int, book: Int,
                             chapter: Int, verse: Int) -> String {
        "\(moduleID):\(testament):\(book):\(chapter):\(verse)"
    }

    /// Returns the note for a verse, or nil when there is none.
    public func verseNote(forKey key: String) -> String? {
        let note = verseNotes[key]
        return (note?.isEmpty ?? true) ? nil : note
    }

    /// Stores a verse note; an empty/nil text removes it (and its
    /// times). Saving moves the note to the front of `verseNoteOrder`
    /// (latest on top) and stamps its times (REQ-NT-17).
    public func setVerseNote(_ text: String?, forKey key: String) {
        if let text, !text.isEmpty {
            let old = verseNotes[key]
            verseNotes[key] = text
            verseNoteOrder.removeAll { $0 == key }
            verseNoteOrder.insert(key, at: 0)
            verseNoteTimes = stampedTimes(verseNoteTimes, key: key,
                                           isNew: old == nil, changed: old != text)
        } else {
            verseNotes.removeValue(forKey: key)
            verseNoteOrder.removeAll { $0 == key }
            verseNoteTimes.removeValue(forKey: key)
        }
    }

    /// Replaces the bookmark with the same id, stamping its
    /// `updatedAt` (REQ-BM-10); `createdAt` is carried over from the
    /// stored copy (or the passed one, or now, in that order).
    public func updateBookmark(_ bookmark: Bookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            var b = bookmark
            b.createdAt = bookmarks[i].createdAt ?? b.createdAt ?? Date()
            b.updatedAt = Date()
            bookmarks[i] = b
        }
    }

    /// Points an existing bookmark at another chapter. Used by the bookmarks
    /// panel's Assign and the reader's Assign Bookmark so both behave alike.
    public func assignBookmark(_ bookmark: Bookmark,
                               testament: Int, book: Int, chapter: Int) {
        updateBookmark(bookmark.moved(testament: testament, book: book,
                                      chapter: chapter))
    }

    /// Removes the bookmark with the same id.
    public func deleteBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    /// A new bookmark at the given location that is NOT stored yet. The
    /// ribbon color comes from the default palette in creation order. The
    /// editor stores it with `saveBookmark` when the user taps Save; cancelling
    /// the editor just drops the draft.
    public func makeBookmarkDraft(name: String, testament: Int, book: Int,
                                  chapter: Int) -> Bookmark {
        let c = Bookmark.paletteColor(at: bookmarks.count)
        return Bookmark(name: name, red: c.red, green: c.green, blue: c.blue,
                        testament: testament, book: book, chapter: chapter)
    }

    /// Stores a bookmark: replaces the one with the same id, or appends a
    /// new one (a draft from `makeBookmarkDraft`). Stamps its times
    /// (REQ-BM-10): a new bookmark gets both, a replacement only
    /// `updatedAt`.
    public func saveBookmark(_ bookmark: Bookmark) {
        if bookmarks.contains(where: { $0.id == bookmark.id }) {
            updateBookmark(bookmark)
        } else {
            var b = bookmark
            let now = Date()
            if b.createdAt == nil { b.createdAt = now }
            b.updatedAt = now
            bookmarks.append(b)
        }
    }

    /// Records a visited chapter. A revisit within 24 hours of an entry's
    /// first visit joins that entry (another timestamp, and the version if
    /// new) and moves it to the front; otherwise a new entry is added.
    public func recordHistory(moduleID: String, bookName: String,
                              testament: Int, book: Int, chapter: Int) {
        historyLog = ReadingHistoryLog.recording(
            moduleID: moduleID, bookName: bookName, testament: testament,
            book: book, chapter: chapter, into: historyLog,
            limit: maxHistoryEntries)
    }

    public func deleteHistory(at offsets: IndexSet) {
        historyLog.remove(atOffsets: offsets)
    }

    public func clearHistory() {
        historyLog = []
    }

    /// Remembers the last selected reading location across app launches.
    public func saveLastReading(moduleID: String, testament: Int, book: Int, chapter: Int) {
        defaults.set([
            "moduleID": moduleID,
            "testament": testament,
            "book": book,
            "chapter": chapter
        ], forKey: lastReadingKey)
    }

    public func loadLastReading() -> (moduleID: String, testament: Int, book: Int, chapter: Int)? {
        guard let dict = defaults.dictionary(forKey: lastReadingKey),
              let moduleID = dict["moduleID"] as? String,
              let testament = dict["testament"] as? Int,
              let book = dict["book"] as? Int,
              let chapter = dict["chapter"] as? Int
        else { return nil }
        return (moduleID, testament, book, chapter)
    }

    public func position(for moduleID: String) -> ReadingPosition? {
        positions[moduleID]
    }

    public func savePosition(_ position: ReadingPosition, for moduleID: String) {
        var p = positions
        p[moduleID] = position
        positions = p
    }

    private var positions: [String: ReadingPosition] {
        get {
            guard let data = defaults.data(forKey: positionsKey),
                  let decoded = try? JSONDecoder().decode([String: ReadingPosition].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: positionsKey)
        }
    }

    public func makeBackup(installedModuleIDs: [String]) -> BackupPayload {
        BackupPayload(fontSize: fontSize,
                      verseByVerse: verseByVerse,
                      showStrongs: showStrongs,
                      positions: positions,
                      installedModuleIDs: installedModuleIDs,
                      bookmarks: bookmarks,
                      verseNotes: verseNotes,
                      verseNoteOrder: verseNoteOrder,
                      compareVersionIDs: compareVersionIDs,
                      bookNotes: bookNotes,
                      chapterNotes: chapterNotes,
                      verseNoteTimes: verseNoteTimes,
                      bookNoteTimes: bookNoteTimes,
                      chapterNoteTimes: chapterNoteTimes,
                      commentaryModuleID: commentaryModuleID,
                      strongsFallbackVersionID: strongsFallbackVersionID,
                      interestedLanguages: interestedLanguages,
                      dictionaryHebrewID: dictionaryHebrewID,
                      dictionaryGreekID: dictionaryGreekID,
                      backedUpAt: Date())
    }

    public func applyBackup(_ payload: BackupPayload) {
        fontSize = payload.fontSize
        verseByVerse = payload.verseByVerse
        showStrongs = payload.showStrongs
        positions = payload.positions
        // Old backups predate bookmarks (decode yields []); don't let
        // those wipe the current ribbons.
        if !payload.bookmarks.isEmpty {
            bookmarks = payload.bookmarks
        }
        // Same guard for notes.
        if !payload.verseNotes.isEmpty {
            verseNotes = payload.verseNotes
        }
        if !payload.verseNoteOrder.isEmpty {
            verseNoteOrder = payload.verseNoteOrder
        }
        // Same guard: backups made before Compare existed decode to [].
        if !payload.compareVersionIDs.isEmpty {
            compareVersionIDs = payload.compareVersionIDs
        }
        // Same guard for the scoped notes (payloads before v7 decode to [:]).
        if !payload.bookNotes.isEmpty {
            bookNotes = payload.bookNotes
        }
        if !payload.chapterNotes.isEmpty {
            chapterNotes = payload.chapterNotes
        }
        // Note times (payload v8+; older payloads decode to [:] and
        // leave current times alone). Times for notes that don't
        // exist are dropped.
        if !payload.verseNoteTimes.isEmpty {
            verseNoteTimes = payload.verseNoteTimes.filter { verseNotes[$0.key] != nil }
        }
        if !payload.bookNoteTimes.isEmpty {
            bookNoteTimes = payload.bookNoteTimes.filter { bookNotes[$0.key] != nil }
        }
        if !payload.chapterNoteTimes.isEmpty {
            chapterNoteTimes = payload.chapterNoteTimes.filter { chapterNotes[$0.key] != nil }
        }
        if !payload.commentaryModuleID.isEmpty {
            commentaryModuleID = payload.commentaryModuleID
        }
        if !payload.strongsFallbackVersionID.isEmpty {
            strongsFallbackVersionID = payload.strongsFallbackVersionID
        }
        // Download languages + dictionaries (payload v9+; older
        // payloads decode to empty and leave current values alone).
        if !payload.interestedLanguages.isEmpty {
            interestedLanguages = payload.interestedLanguages
        }
        if !payload.dictionaryHebrewID.isEmpty {
            dictionaryHebrewID = payload.dictionaryHebrewID
        }
        if !payload.dictionaryGreekID.isEmpty {
            dictionaryGreekID = payload.dictionaryGreekID
        }
    }

    // MARK: - iCloud sync

    /// Settings snapshot for iCloud (JSON). Includes repository URL and
    /// installed module IDs so a new device can restore its library.
    public struct iCloudSettings: Codable {
        public var fontSize: Double
        public var verseByVerse: Bool
        public var showStrongs: Bool
        public var repositoryURL: String
        public var installedModuleIDs: [String]
        /// Optional so settings.json files written before Compare existed
        /// still decode (nil = leave the current setting alone).
        public var compareVersionIDs: [String]?
        /// Optional so older settings.json files still decode
        /// (nil = leave the current setting alone).
        public var commentaryModuleID: String?
        public var strongsFallbackVersionID: String?
        /// Download-list languages + Strong's dictionaries (REQ-LG-1,
        /// REQ-DC-2); optional for the same reason.
        public var interestedLanguages: [String]?
        public var dictionaryHebrewID: String?
        public var dictionaryGreekID: String?
    }

    private func syncBookmarksToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(bookmarks, as: .bookmarks)
    }

    private func syncNotesToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(verseNotes, as: .notes)
    }

    private func syncBookNotesToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(bookNotes, as: .bookNotes)
    }

    private func syncChapterNotesToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(chapterNotes, as: .chapterNotes)
    }

    private func syncVerseNoteTimesToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(verseNoteTimes, as: .verseNoteTimes)
    }

    private func syncBookNoteTimesToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(bookNoteTimes, as: .bookNoteTimes)
    }

    private func syncChapterNoteTimesToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(chapterNoteTimes, as: .chapterNoteTimes)
    }

    private func syncHistoryToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(historyLog, as: .history)
    }

    /// Syncs all data to iCloud immediately (called when the toggle is enabled).
    /// Ensures the JSON files exist so the folder becomes visible in Files.
    public func syncAllToiCloud(repositoryURL: String,
                                installedModuleIDs: [String]) {
        guard iCloudSync.shared.isEnabled else { return }
        iCloudSync.shared.ensureFolders()
        // Save even empty collections so the files (and folder) appear.
        try? iCloudSync.shared.save(bookmarks, as: .bookmarks)
        try? iCloudSync.shared.save(verseNotes, as: .notes)
        try? iCloudSync.shared.save(bookNotes, as: .bookNotes)
        try? iCloudSync.shared.save(chapterNotes, as: .chapterNotes)
        try? iCloudSync.shared.save(verseNoteTimes, as: .verseNoteTimes)
        try? iCloudSync.shared.save(bookNoteTimes, as: .bookNoteTimes)
        try? iCloudSync.shared.save(chapterNoteTimes, as: .chapterNoteTimes)
        try? iCloudSync.shared.save(historyLog, as: .history)
        syncSettingsToiCloud(repositoryURL: repositoryURL,
                              installedModuleIDs: installedModuleIDs)
    }

    /// Call when settings change (font size, toggles, installed modules).
    public func syncSettingsToiCloud(repositoryURL: String,
                                     installedModuleIDs: [String]) {
        guard iCloudSync.shared.isEnabled else { return }
        let settings = iCloudSettings(
            fontSize: fontSize, verseByVerse: verseByVerse,
            showStrongs: showStrongs, repositoryURL: repositoryURL,
            installedModuleIDs: installedModuleIDs,
            compareVersionIDs: compareVersionIDs,
            commentaryModuleID: commentaryModuleID,
            strongsFallbackVersionID: strongsFallbackVersionID,
            interestedLanguages: interestedLanguages,
            dictionaryHebrewID: dictionaryHebrewID,
            dictionaryGreekID: dictionaryGreekID)
        try? iCloudSync.shared.save(settings, as: .settings)
    }

    /// Loads all data from iCloud Drive (when enabled). Called on launch.
    public func loadFromiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        if let b: [Bookmark] = try? iCloudSync.shared.load([Bookmark].self,
                                                            as: .bookmarks),
           !b.isEmpty {
            bookmarks = b
        }
        if let n: [String: String] = try? iCloudSync.shared.load(
            [String: String].self, as: .notes), !n.isEmpty {
            verseNotes = n
        }
        if let bn: [String: String] = try? iCloudSync.shared.load(
            [String: String].self, as: .bookNotes), !bn.isEmpty {
            bookNotes = bn
        }
        if let cn: [String: String] = try? iCloudSync.shared.load(
            [String: String].self, as: .chapterNotes), !cn.isEmpty {
            chapterNotes = cn
        }
        if let vt: [String: NoteTimes] = try? iCloudSync.shared.load(
            [String: NoteTimes].self, as: .verseNoteTimes), !vt.isEmpty {
            verseNoteTimes = vt
        }
        if let bt: [String: NoteTimes] = try? iCloudSync.shared.load(
            [String: NoteTimes].self, as: .bookNoteTimes), !bt.isEmpty {
            bookNoteTimes = bt
        }
        if let ct: [String: NoteTimes] = try? iCloudSync.shared.load(
            [String: NoteTimes].self, as: .chapterNoteTimes), !ct.isEmpty {
            chapterNoteTimes = ct
        }
        if let h: [HistoryEntry] = try? iCloudSync.shared.load(
            [HistoryEntry].self, as: .history), !h.isEmpty {
            historyLog = ReadingHistoryLog.combined(h)
        }
    }

    // MARK: - Manual export/import (Files app)

    /// Exports all data as JSON files to Documents/god-s-word-export/.
    /// Returns the folder URL for sharing via the Files app or AirDrop.
    public func exportToDocuments() throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("god-s-word-export",
                                                 isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(bookmarks)
            .write(to: folder.appendingPathComponent("bookmarks.json"))
        try encoder.encode(verseNotes)
            .write(to: folder.appendingPathComponent("notes.json"))
        try encoder.encode(verseNoteOrder)
            .write(to: folder.appendingPathComponent("noteOrder.json"))
        try encoder.encode(bookNotes)
            .write(to: folder.appendingPathComponent("bookNotes.json"))
        try encoder.encode(chapterNotes)
            .write(to: folder.appendingPathComponent("chapterNotes.json"))
        try encoder.encode(verseNoteTimes)
            .write(to: folder.appendingPathComponent("verseNoteTimes.json"))
        try encoder.encode(bookNoteTimes)
            .write(to: folder.appendingPathComponent("bookNoteTimes.json"))
        try encoder.encode(chapterNoteTimes)
            .write(to: folder.appendingPathComponent("chapterNoteTimes.json"))
        try encoder.encode(historyLog)
            .write(to: folder.appendingPathComponent("history.json"))
        let settings = iCloudSettings(
            fontSize: fontSize, verseByVerse: verseByVerse,
            showStrongs: showStrongs,
            repositoryURL: "https://crosswire.org/ftpmirror/pub/sword/raw",
            installedModuleIDs: [],
            compareVersionIDs: compareVersionIDs,
            commentaryModuleID: commentaryModuleID,
            strongsFallbackVersionID: strongsFallbackVersionID,
            interestedLanguages: interestedLanguages,
            dictionaryHebrewID: dictionaryHebrewID,
            dictionaryGreekID: dictionaryGreekID)
        try encoder.encode(settings)
            .write(to: folder.appendingPathComponent("settings.json"))
        return folder
    }

    /// Imports data from JSON files (selected via document picker).
    /// Only non-empty values are applied (never wipes with empty files).
    public func importFrom(urls: [URL]) throws {
        for url in urls {
            // Handle both "bookmarks.json" and "bookmarks.json.gz".
            var name = url.deletingPathExtension().lastPathComponent
            if url.pathExtension == "gz" {
                name = URL(fileURLWithPath: name).deletingPathExtension()
                    .lastPathComponent
            }
            let data = try Data(contentsOf: url)
            let json: Data
            if url.pathExtension == "gz" {
                guard let d = try? (data as NSData)
                    .decompressed(using: .zlib) as Data else { continue }
                json = d
            } else {
                json = data
            }
            switch name {
            case "bookmarks":
                let b = try JSONDecoder().decode([Bookmark].self, from: json)
                if !b.isEmpty { bookmarks = b }
            case "notes":
                let n = try JSONDecoder().decode([String: String].self,
                                                 from: json)
                if !n.isEmpty { verseNotes = n }
            case "noteOrder":
                let o = try JSONDecoder().decode([String].self, from: json)
                if !o.isEmpty { verseNoteOrder = o }
            case "bookNotes":
                let bn = try JSONDecoder().decode([String: String].self,
                                                  from: json)
                if !bn.isEmpty { bookNotes = bn }
            case "chapterNotes":
                let cn = try JSONDecoder().decode([String: String].self,
                                                  from: json)
                if !cn.isEmpty { chapterNotes = cn }
            case "verseNoteTimes":
                let vt = try JSONDecoder().decode([String: NoteTimes].self,
                                                  from: json)
                if !vt.isEmpty { verseNoteTimes = vt }
            case "bookNoteTimes":
                let bt = try JSONDecoder().decode([String: NoteTimes].self,
                                                  from: json)
                if !bt.isEmpty { bookNoteTimes = bt }
            case "chapterNoteTimes":
                let ct = try JSONDecoder().decode([String: NoteTimes].self,
                                                  from: json)
                if !ct.isEmpty { chapterNoteTimes = ct }
            case "history":
                let h = try JSONDecoder().decode([HistoryEntry].self,
                                                 from: json)
                if !h.isEmpty { historyLog = ReadingHistoryLog.combined(h) }
            case "settings":
                let s = try JSONDecoder().decode(iCloudSettings.self,
                                                 from: json)
                fontSize = s.fontSize
                verseByVerse = s.verseByVerse
                showStrongs = s.showStrongs
                if let ids = s.compareVersionIDs { compareVersionIDs = ids }
                if let cid = s.commentaryModuleID, !cid.isEmpty {
                    commentaryModuleID = cid
                }
                if let fid = s.strongsFallbackVersionID, !fid.isEmpty {
                    strongsFallbackVersionID = fid
                }
                if let langs = s.interestedLanguages, !langs.isEmpty {
                    interestedLanguages = langs
                }
                if let hid = s.dictionaryHebrewID, !hid.isEmpty {
                    dictionaryHebrewID = hid
                }
                if let gid = s.dictionaryGreekID, !gid.isEmpty {
                    dictionaryGreekID = gid
                }
            default:
                continue
            }
        }
    }
}

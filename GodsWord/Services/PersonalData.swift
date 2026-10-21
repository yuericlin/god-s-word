// PersonalData.swift
// All personal data lives in iPhone local storage by default:
// - Settings and reading positions: UserDefaults (suite-local)
// - Downloaded modules: Application Support/Modules (see ModuleStore)
// The BackupPayload below is what gets synced to Google Drive
// when the user consents and signs in.

import Foundation

/// Where the user left off in a module: testament/book/chapter (1-based).
public struct ReadingPosition: Codable, Sendable {
    public var testament: Int
    public var book: Int
    public var chapter: Int
    public init(testament: Int, book: Int, chapter: Int) {
        self.testament = testament; self.book = book; self.chapter = chapter
    }
}

/// One entry in the full reading history log.
public struct HistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let moduleID: String
    public let bookName: String
    public let testament: Int
    public let book: Int
    public let chapter: Int
    public let timestamp: Date

    public init(id: UUID = UUID(), moduleID: String, bookName: String,
                testament: Int, book: Int, chapter: Int, timestamp: Date = Date()) {
        self.id = id
        self.moduleID = moduleID
        self.bookName = bookName
        self.testament = testament
        self.book = book
        self.chapter = chapter
        self.timestamp = timestamp
    }
}

/// Everything synced to Google Drive. Module *contents* are not included;
/// the backup records which module IDs were installed so they can be
/// re-downloaded from the repository on restore.
public struct BackupPayload: Codable, Sendable {
    public var version: Int = 6
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
    public var backedUpAt: Date

    public init(fontSize: Double, verseByVerse: Bool = false, showStrongs: Bool = false,
                positions: [String: ReadingPosition], installedModuleIDs: [String],
                bookmarks: [Bookmark] = [], verseNotes: [String: String] = [:],
                verseNoteOrder: [String] = [],
                compareVersionIDs: [String] = [],
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
            log = decoded
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

    /// Note keys ordered most-recently-saved first; the bookmarks panel
    /// lists notes in this order (notes missing from the list sort last,
    /// in canonical order). Maintained by `setVerseNote`.
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

    /// Stores a verse note; an empty/nil text removes it. Saving moves
    /// the note to the front of `verseNoteOrder` (latest on top).
    public func setVerseNote(_ text: String?, forKey key: String) {
        if let text, !text.isEmpty {
            verseNotes[key] = text
            verseNoteOrder.removeAll { $0 == key }
            verseNoteOrder.insert(key, at: 0)
        } else {
            verseNotes.removeValue(forKey: key)
            verseNoteOrder.removeAll { $0 == key }
        }
    }

    /// Replaces the bookmark with the same id.
    public func updateBookmark(_ bookmark: Bookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[i] = bookmark
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
    /// new one (a draft from `makeBookmarkDraft`).
    public func saveBookmark(_ bookmark: Bookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[i] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
    }

    /// Records a visited chapter. Moves an existing entry for the same
    /// location to the front instead of duplicating it.
    public func recordHistory(moduleID: String, bookName: String,
                              testament: Int, book: Int, chapter: Int) {
        var log = historyLog.filter {
            !($0.moduleID == moduleID && $0.testament == testament &&
              $0.book == book && $0.chapter == chapter)
        }
        log.insert(HistoryEntry(moduleID: moduleID, bookName: bookName,
                                testament: testament, book: book, chapter: chapter),
                   at: 0)
        if log.count > maxHistoryEntries {
            log = Array(log.prefix(maxHistoryEntries))
        }
        historyLog = log
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
    }

    private func syncBookmarksToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(bookmarks, as: .bookmarks)
    }

    private func syncNotesToiCloud() {
        guard iCloudSync.shared.isEnabled else { return }
        try? iCloudSync.shared.save(verseNotes, as: .notes)
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
            compareVersionIDs: compareVersionIDs)
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
        if let h: [HistoryEntry] = try? iCloudSync.shared.load(
            [HistoryEntry].self, as: .history), !h.isEmpty {
            historyLog = h
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
        try encoder.encode(historyLog)
            .write(to: folder.appendingPathComponent("history.json"))
        let settings = iCloudSettings(
            fontSize: fontSize, verseByVerse: verseByVerse,
            showStrongs: showStrongs,
            repositoryURL: "https://crosswire.org/ftpmirror/pub/sword/raw",
            installedModuleIDs: [],
            compareVersionIDs: compareVersionIDs)
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
            case "history":
                let h = try JSONDecoder().decode([HistoryEntry].self,
                                                 from: json)
                if !h.isEmpty { historyLog = h }
            case "settings":
                let s = try JSONDecoder().decode(iCloudSettings.self,
                                                 from: json)
                fontSize = s.fontSize
                verseByVerse = s.verseByVerse
                showStrongs = s.showStrongs
                if let ids = s.compareVersionIDs { compareVersionIDs = ids }
            default:
                continue
            }
        }
    }
}

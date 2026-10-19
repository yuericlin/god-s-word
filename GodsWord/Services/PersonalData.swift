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

/// Everything synced to Google Drive. Module *contents* are not included;
/// the backup records which module IDs were installed so they can be
/// re-downloaded from the repository on restore.
public struct BackupPayload: Codable, Sendable {
    public var version: Int = 2
    public var fontSize: Double
    public var verseByVerse: Bool
    public var positions: [String: ReadingPosition]  // moduleID -> position
    public var installedModuleIDs: [String]
    public var backedUpAt: Date

    public init(fontSize: Double, verseByVerse: Bool = false,
                positions: [String: ReadingPosition], installedModuleIDs: [String],
                backedUpAt: Date) {
        self.fontSize = fontSize
        self.verseByVerse = verseByVerse
        self.positions = positions
        self.installedModuleIDs = installedModuleIDs
        self.backedUpAt = backedUpAt
    }

    // Custom decoding so backups written before verseByVerse existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        verseByVerse = try c.decodeIfPresent(Bool.self, forKey: .verseByVerse) ?? false
        positions = try c.decode([String: ReadingPosition].self, forKey: .positions)
        installedModuleIDs = try c.decode([String].self, forKey: .installedModuleIDs)
        backedUpAt = try c.decode(Date.self, forKey: .backedUpAt)
    }
}

public final class PersonalData: ObservableObject {
    private let defaults: UserDefaults
    private let positionsKey = "gw.readingPositions.v1"
    private let fontSizeKey = "gw.fontSize.v1"
    private let verseByVerseKey = "gw.verseByVerse.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: fontSizeKey)
        self.fontSize = saved > 0 ? saved : 19
        self.verseByVerse = defaults.bool(forKey: verseByVerseKey)
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
                      positions: positions,
                      installedModuleIDs: installedModuleIDs,
                      backedUpAt: Date())
    }

    public func applyBackup(_ payload: BackupPayload) {
        fontSize = payload.fontSize
        verseByVerse = payload.verseByVerse
        positions = payload.positions
    }
}

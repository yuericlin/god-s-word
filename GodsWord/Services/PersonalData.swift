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
    public var version: Int = 1
    public var fontSize: Double
    public var positions: [String: ReadingPosition]  // moduleID -> position
    public var installedModuleIDs: [String]
    public var backedUpAt: Date
}

public final class PersonalData: ObservableObject {
    private let defaults: UserDefaults
    private let positionsKey = "gw.readingPositions.v1"
    private let fontSizeKey = "gw.fontSize.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: fontSizeKey)
        self.fontSize = saved > 0 ? saved : 19
    }

    @Published public var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: fontSizeKey) }
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
                      positions: positions,
                      installedModuleIDs: installedModuleIDs,
                      backedUpAt: Date())
    }

    public func applyBackup(_ payload: BackupPayload) {
        fontSize = payload.fontSize
        positions = payload.positions
    }
}

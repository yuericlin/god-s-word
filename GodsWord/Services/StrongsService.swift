// StrongsService.swift — downloads (once) and queries the Strong's
// Hebrew/Greek lexicon modules from CrossWire. Lexicons live in
// Application Support/Lexicons/, separate from Bible modules.

import Foundation
import SwordReader

public enum StrongsServiceError: Error {
    case downloadFailed
    case notInstalled
}

/// Downloads (on first use) and queries Strong's lexicons.
/// Sendable: mutable state is guarded by `lock`.
public final class StrongsService: Sendable {
    public static let shared = StrongsService()

    private let store: ModuleStore
    private let lock = NSLock()
    private var loaded = [String: StrongsLexicon]() // "H"/"G" -> lexicon
    private var downloadTasks = [String: Task<Void, Error>]()

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        store = ModuleStore(baseDir: appSupport.appendingPathComponent("Lexicons",
                                                                       isDirectory: true))
    }

    /// Display-ready dictionary entry for "H7225" / "G26", or nil when the
    /// key is malformed or has no entry. Downloads the lexicon on first use.
    public func definition(for key: String) async throws -> String? {
        let prefix = key.uppercased().hasPrefix("H") ? "H" : "G"
        let lexicon = try await lexicon(prefix: prefix)
        return lexicon.definition(for: key)
    }

    private func lexicon(prefix: String) async throws -> StrongsLexicon {
        if let hit = lock.withLock({ loaded[prefix] }) { return hit }
        let moduleID = prefix == "H" ? "StrongsHebrew" : "StrongsGreek"
        let task: Task<Void, Error> = lock.withLock {
            if let existing = downloadTasks[moduleID] { return existing }
            let created = Task { try await ensureInstalled(moduleID: moduleID) }
            downloadTasks[moduleID] = created
            return created
        }
        try await task.value
        lock.withLock { downloadTasks[moduleID] = nil }
        guard let mod = store.installedModules().first(where: { $0.id == moduleID }) else {
            throw StrongsServiceError.notInstalled
        }
        let lexicon = try StrongsLexicon.load(moduleDir: mod.moduleDir)
        lock.withLock { loaded[prefix] = lexicon }
        return lexicon
    }

    private func ensureInstalled(moduleID: String) async throws {
        if store.isInstalled(moduleID) { return }
        let url = URL(string: "https://crosswire.org/ftpmirror/pub/sword/raw/packages/\(moduleID).zip")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw StrongsServiceError.downloadFailed
        }
        try store.install(packageData: [UInt8](data), moduleID: moduleID)
    }
}

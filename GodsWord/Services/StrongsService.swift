// StrongsService.swift — queries the Strong's Hebrew/Greek lexicon
// modules. The dictionaries used are a setting (REQ-DC-2): the
// chosen modules (Settings > Dictionary) are looked up in the main
// module store first; with no choice, StrongsHebrew / StrongsGreek
// are downloaded once from CrossWire into Application
// Support/Lexicons/, separate from Bible modules.

import Foundation
import SwordReader

public enum StrongsServiceError: Error {
    case downloadFailed
    case notInstalled
}

/// Downloads (on first use) and queries Strong's lexicons.
/// @unchecked Sendable: mutable state is guarded by `lock`.
public final class StrongsService: @unchecked Sendable {
    public static let shared = StrongsService()

    private let store: ModuleStore        // the auto-downloaded pair
    private let mainStore: ModuleStore    // user-downloaded dictionaries
    private let lock = NSLock()
    private var loaded = [String: StrongsLexicon]() // moduleID -> lexicon
    private var downloadTasks = [String: Task<Void, Error>]()

    // The Settings > Dictionary choices, persisted by PersonalData
    // under these keys (PersonalData.dictionaryHebrewKey / ...GreekKey).
    private let hebrewKey = "gw.dictionaryHebrew.v1"
    private let greekKey = "gw.dictionaryGreek.v1"

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        store = ModuleStore(baseDir: appSupport.appendingPathComponent("Lexicons",
                                                                       isDirectory: true))
        mainStore = ModuleStore()
    }

    /// Display-ready dictionary entry for "H7225" / "G26", or nil when the
    /// key is malformed or has no entry. Downloads the lexicon on first use.
    public func definition(for key: String) async throws -> String? {
        let prefix = key.uppercased().hasPrefix("H") ? "H" : "G"
        let lexicon = try await lexicon(prefix: prefix)
        return lexicon.definition(for: key)
    }

    /// The module serving a prefix: the user's dictionary choice for
    /// it, or the automatic StrongsHebrew / StrongsGreek.
    /// `userChosen` is false when the choice is empty or names the
    /// automatic module itself.
    private func resolvedModule(prefix: String) -> (id: String, userChosen: Bool) {
        let defaultID = prefix == "H" ? "StrongsHebrew" : "StrongsGreek"
        let chosen = UserDefaults.standard.string(
            forKey: prefix == "H" ? hebrewKey : greekKey) ?? ""
        if chosen.isEmpty || chosen == defaultID { return (defaultID, false) }
        return (chosen, true)
    }

    private func lexicon(prefix: String) async throws -> StrongsLexicon {
        let (moduleID, userChosen) = resolvedModule(prefix: prefix)
        if let hit = lock.withLock({ loaded[moduleID] }) { return hit }
        // Only the automatic pair downloads itself; a chosen
        // dictionary must already be installed (Add Dictionary).
        if moduleID == "StrongsHebrew" || moduleID == "StrongsGreek" {
            let task: Task<Void, Error> = lock.withLock {
                if let existing = downloadTasks[moduleID] { return existing }
                let created = Task { try await ensureInstalled(moduleID: moduleID) }
                downloadTasks[moduleID] = created
                return created
            }
            try await task.value
            lock.withLock { downloadTasks[moduleID] = nil }
        }
        // A chosen dictionary lives in the main store; the automatic
        // pair lives in the lexicons store. Check the home store of
        // each kind first, then the other.
        let stores = userChosen ? [mainStore, store] : [store, mainStore]
        guard let mod = stores
            .compactMap({ $0.installedModules().first(where: { $0.id == moduleID }) })
            .first
        else { throw StrongsServiceError.notInstalled }
        let lexicon = try StrongsLexicon.load(moduleDir: mod.moduleDir)
        lock.withLock { loaded[moduleID] = lexicon }
        return lexicon
    }

    private func ensureInstalled(moduleID: String) async throws {
        if store.isInstalled(moduleID) || mainStore.isInstalled(moduleID) { return }
        let url = URL(string: "https://crosswire.org/ftpmirror/pub/sword/raw/packages/\(moduleID).zip")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw StrongsServiceError.downloadFailed
        }
        try store.install(packageData: [UInt8](data), moduleID: moduleID)
    }
}

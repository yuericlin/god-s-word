// BibleSource.swift — named origins for Bible versions. A source is either
// a remote SWORD repository (a URL you can download from) or a local folder
// holding private JSON Bibles. The public repositories (CrossWire,
// CrossWire Beta, CrossWire Attic, eBible.org) and Private are built in;
// the user can add more sources of either kind, edit any source, and
// delete the custom ones (deleting a source keeps its version files).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SourceKind: Codable, Equatable {
    /// A remote SWORD repository (downloadable modules).
    case repository(URL)
    /// The app's own PrivateModules folder (the built-in Private source).
    case appFolder
    /// A user-picked folder, kept as a security-scoped bookmark.
    case folder(bookmark: Data)
}

struct BibleSource: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var kind: SourceKind
    var isBuiltIn: Bool

    /// The two built-in sources.
    static let crossWire = BibleSource(
        id: "crosswire", name: "CrossWire",
        kind: .repository(URL(string: "https://crosswire.org/ftpmirror/pub/sword/raw")!),
        isBuiltIn: true)
    static let `private` = BibleSource(
        id: "private", name: "Private", kind: .appFolder, isBuiltIn: true)

    /// The other built-in public repositories (REQ-SRC-1), each verified
    /// live in the app's repository format (mods.d.tar.gz catalog plus
    /// packages/<id>.zip downloads).
    static let crossWireBeta = BibleSource(
        id: "crosswire-beta", name: "CrossWire Beta",
        kind: .repository(URL(string: "https://www.crosswire.org/ftpmirror/pub/sword/betaraw")!),
        isBuiltIn: true)
    static let bibleOrg = BibleSource(
        id: "bible-org", name: "Bible.org",
        kind: .repository(URL(string: "https://crosswire.org/ftpmirror/pub/bible.org/sword")!),
        isBuiltIn: true)
    static let crossWireAttic = BibleSource(
        id: "crosswire-attic", name: "CrossWire Attic",
        kind: .repository(URL(string: "https://www.crosswire.org/ftpmirror/pub/sword/atticraw")!),
        isBuiltIn: true)
    static let crossWireWycliffe = BibleSource(
        id: "crosswire-wycliffe", name: "CrossWire Wycliffe",
        kind: .repository(URL(string: "https://crosswire.org/ftpmirror/pub/sword/wyclifferaw")!),
        isBuiltIn: true)
    static let eBible = BibleSource(
        id: "ebible", name: "eBible.org",
        kind: .repository(URL(string: "https://ebible.org/sword")!),
        isBuiltIn: true)
    static let dbg = BibleSource(
        id: "dbg", name: "Deutsche Bibelgesellschaft",
        kind: .repository(URL(string: "https://crosswire.org/ftpmirror/pub/sword/dbgraw")!),
        isBuiltIn: true)
    static let lockman = BibleSource(
        id: "lockman", name: "Lockman Foundation",
        kind: .repository(URL(string: "https://crosswire.org/ftpmirror/pub/sword/lockmanraw")!),
        isBuiltIn: true)

    /// The public repository sources bundled with the app, in the
    /// SWORD master list's order, CrossWire first. Together they are
    /// every repository on that list reachable over https (Xiphos is
    /// http-only). "Update Public Sources" (REQ-SRC-3) can replace this
    /// list with a newer one downloaded from the project repository.
    static let bundledPublicSources: [BibleSource] =
        [crossWire, crossWireBeta, bibleOrg, crossWireAttic,
         crossWireWycliffe, eBible, dbg, lockman]

    /// The repository URL for URL sources; nil for local sources.
    var repositoryURL: URL? {
        if case .repository(let url) = kind { return url }
        return nil
    }

    /// True for local sources (app folder or a user-picked folder).
    var isLocal: Bool {
        switch kind {
        case .repository: return false
        case .appFolder, .folder: return true
        }
    }
}

/// The registry of sources: the two built-ins plus the user's custom ones,
/// and which source each downloaded module came from.
@MainActor
final class BibleSourceStore {
    static let shared = BibleSourceStore()

    /// Where the maintained public-source list lives (public-sources.json
    /// in the project repository); "Update Public Sources" fetches it.
    static let publicListURL = URL(
        string: "https://raw.githubusercontent.com/yuericlin/god-s-word/main/public-sources.json")!

    private struct Persisted: Codable {
        var customSources: [BibleSource]
        var moduleSources: [String: String]  // moduleID -> sourceID
        var editedBuiltIns: [BibleSource]    // built-ins the user renamed/relocated
        // Added with REQ-SRC-2/3; optional so BibleSources.json files
        // written before them (which lack these keys) still decode.
        var publicSources: [BibleSource]? = nil   // last downloaded public list
        var publicSourcesUpdatedAt: Date? = nil
        var defaultSourceID: String? = nil
    }

    private var persisted: Persisted
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("BibleSources.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            persisted = decoded
        } else {
            persisted = Persisted(customSources: [], moduleSources: [:], editedBuiltIns: [])
        }
    }

    /// All sources: the public repositories (CrossWire first), Private,
    /// then custom sources by name.
    var allSources: [BibleSource] {
        let publics = publicSources.map { base in
            persisted.editedBuiltIns.first { $0.id == base.id } ?? base
        }
        let priv = persisted.editedBuiltIns.first { $0.id == BibleSource.`private`.id }
            ?? BibleSource.`private`
        return publics + [priv] + persisted.customSources.sorted { $0.name < $1.name }
    }

    /// The effective public repository list: the last downloaded one,
    /// or the bundled list when it was never updated.
    var publicSources: [BibleSource] {
        persisted.publicSources ?? BibleSource.bundledPublicSources
    }

    /// When the public list was last downloaded; nil means the app is
    /// using the bundled list.
    var publicSourcesUpdatedAt: Date? { persisted.publicSourcesUpdatedAt }

    /// The repository source the download pages open with (REQ-SRC-2).
    /// Falls back to CrossWire when unset or no longer available.
    var defaultSourceID: String {
        get {
            if let id = persisted.defaultSourceID,
               allSources.contains(where: { $0.id == id && $0.repositoryURL != nil }) {
                return id
            }
            return BibleSource.crossWire.id
        }
        set {
            persisted.defaultSourceID = newValue
            write()
        }
    }

    func source(withID id: String) -> BibleSource? {
        allSources.first { $0.id == id }
    }

    /// Add or update a source. Built-in edits keep the id and just change
    /// name/URL; custom sources are stored as given.
    func save(_ source: BibleSource) {
        if source.isBuiltIn {
            persisted.editedBuiltIns.removeAll { $0.id == source.id }
            persisted.editedBuiltIns.append(source)
        } else if let i = persisted.customSources.firstIndex(where: { $0.id == source.id }) {
            persisted.customSources[i] = source
        } else {
            persisted.customSources.append(source)
        }
        write()
    }

    /// Remove a custom source (its version files are kept). Downloaded
    /// modules that belonged to it fall back to CrossWire.
    func delete(_ source: BibleSource) {
        guard !source.isBuiltIn else { return }
        persisted.customSources.removeAll { $0.id == source.id }
        for (mod, src) in persisted.moduleSources where src == source.id {
            persisted.moduleSources[mod] = BibleSource.crossWire.id
        }
        write()
    }

    /// Downloads the latest public-source list and replaces the current
    /// one with it (REQ-SRC-3). Custom sources are never touched;
    /// modules tagged to a source the new list drops fall back to
    /// CrossWire (as does the default, via `defaultSourceID`). Returns
    /// the number of public sources in the new list. On any failure the
    /// current list is kept and the error is thrown.
    func refreshPublicSources() async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: Self.publicListURL)
        let list = try JSONDecoder().decode(PublicSourceList.self, from: data)
        var seen = Set<String>()
        let sources = list.sources.compactMap { entry -> BibleSource? in
            guard seen.insert(entry.id).inserted,
                  let url = URL(string: entry.url), url.scheme == "https"
            else { return nil }
            return BibleSource(id: entry.id, name: entry.name,
                               kind: .repository(url), isBuiltIn: true)
        }
        guard sources.contains(where: { $0.id == BibleSource.crossWire.id }) else {
            throw PublicSourceError.invalidList
        }
        persisted.publicSources = sources
        persisted.publicSourcesUpdatedAt = Date()
        let valid = Set(allSources.map(\.id))
        for (mod, src) in persisted.moduleSources where !valid.contains(src) {
            persisted.moduleSources[mod] = BibleSource.crossWire.id
        }
        write()
        return sources.count
    }

    // MARK: - Downloaded-module source tagging

    func sourceID(forModule moduleID: String) -> String {
        persisted.moduleSources[moduleID] ?? BibleSource.crossWire.id
    }

    func setSourceID(_ sourceID: String, forModule moduleID: String) {
        persisted.moduleSources[moduleID] = sourceID
        write()
    }

    private func write() {
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension BibleSource {
    /// Resolves the on-disk folder for a local source, if any. For a
    /// security-scoped folder the returned URL must be accessed between
    /// `startAccessingSecurityScopedResource()` and the matching stop.
    var resolvedFolder: URL? {
        switch kind {
        case .repository:
            return nil
        case .appFolder:
            return PrivateBibleStore.baseDir
        case .folder(let bookmark):
            var stale = false
            return try? URL(resolvingBookmarkData: bookmark,
                            options: [],
                            relativeTo: nil, bookmarkDataIsStale: &stale)
        }
    }

    var needsSecurityScope: Bool {
        if case .folder = kind { return true }
        return false
    }
}

/// The downloaded public-source list format (public-sources.json in the
/// project repository).
struct PublicSourceList: Decodable {
    struct Entry: Decodable {
        var id: String
        var name: String
        var url: String
    }
    var version: Int
    var sources: [Entry]
}

enum PublicSourceError: Error, LocalizedError {
    /// The downloaded list was unusable (e.g. CrossWire missing).
    case invalidList

    var errorDescription: String? {
        switch self {
        case .invalidList:
            return "The downloaded source list was empty or missing CrossWire."
        }
    }
}

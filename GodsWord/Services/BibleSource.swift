// BibleSource.swift — named origins for Bible versions. A source is either
// a remote SWORD repository (a URL you can download from) or a local folder
// holding private JSON Bibles. CrossWire and Private are built in; the user
// can add more sources of either kind, edit any source, and delete the
// custom ones (deleting a source keeps its version files).

import Foundation

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

    private struct Persisted: Codable {
        var customSources: [BibleSource]
        var moduleSources: [String: String]  // moduleID -> sourceID
        var editedBuiltIns: [BibleSource]    // built-ins the user renamed/relocated
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

    /// All sources: CrossWire, Private, then custom sources by name.
    var allSources: [BibleSource] {
        let builtIns = [BibleSource.crossWire, BibleSource.`private`].map { base in
            persisted.editedBuiltIns.first { $0.id == base.id } ?? base
        }
        return builtIns + persisted.customSources.sorted { $0.name < $1.name }
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

// iCloudSync.swift
// iCloud Drive sync for God's Word personal data.
// When enabled, bookmarks, notes, settings, and history are stored as JSON
// in the iCloud Drive folder "god-s-word/". A "private-repo/" subfolder holds
// private/custom Bible modules (JSON or gzipped JSON).
//
// The user enables iCloud in Settings; the app requires the iCloud Drive
// capability (see GodsWord.entitlements; enable in Xcode Signing & Capabilities).

import Foundation

/// iCloud Drive sync state and file operations.
@MainActor
public final class iCloudSync: ObservableObject {
    public static let shared = iCloudSync()

    /// User preference: iCloud sync enabled (persisted in UserDefaults).
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "gw.iCloudSync.enabled")
            if isEnabled {
                ensureFolders()
                // Download any private Bibles from iCloud to local.
                // File operations are quick (small JSON files); safe on main.
                let count = syncPrivateModulesToLocal()
                if count > 0 {
                    print("[iCloudSync] Downloaded \(count) private Bible(s) to local")
                }
            }
        }
    }

    /// True if the device has an iCloud account (ubiquity token available).
    public var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "gw.iCloudSync.enabled")
    }

    /// Call on app launch: ensures folders exist if iCloud was already enabled.
    public func ensureFoldersOnLaunchIfEnabled() {
        guard isEnabled else { return }
        // Delay slightly to let iCloud initialize.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.ensureFolders()
        }
    }

    // MARK: - Folder structure

    /// The iCloud Drive container URL, e.g. ~/Library/Mobile Documents/iCloud~.../
    public var containerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    /// god-s-word/ in iCloud Drive.
    public var rootFolder: URL? {
        containerURL?.appendingPathComponent("god-s-word", isDirectory: true)
    }

    /// god-s-word/private-repo/ for custom Bible modules.
    public var privateRepoFolder: URL? {
        rootFolder?.appendingPathComponent("private-repo", isDirectory: true)
    }

    /// Creates the folder structure if iCloud is available and enabled.
    public func ensureFolders() {
        guard isEnabled, isAvailable else { return }
        for folder in [rootFolder, privateRepoFolder].compactMap({ $0 }) {
            try? FileManager.default.createDirectory(at: folder,
                                                     withIntermediateDirectories: true)
        }
    }

    // MARK: - JSON file I/O

    public enum FileName: String {
        case bookmarks = "bookmarks.json"
        case notes = "notes.json"
        case bookNotes = "bookNotes.json"
        case chapterNotes = "chapterNotes.json"
        case verseNoteTimes = "verseNoteTimes.json"
        case bookNoteTimes = "bookNoteTimes.json"
        case chapterNoteTimes = "chapterNoteTimes.json"
        case settings = "settings.json"
        case history = "history.json"
    }

    /// Saves Encodable data as JSON to the god-s-word/ folder.
    /// If `compressed` is true, writes gzipped JSON with a .gz extension.
    public func save<T: Encodable>(_ value: T, as file: FileName,
                                   compressed: Bool = false) throws {
        guard let folder = rootFolder else {
            throw iCloudError.notAvailable
        }
        ensureFolders()
        let data = try JSONEncoder().encode(value)
        let url: URL
        let outData: Data
        if compressed {
            url = folder.appendingPathComponent(file.rawValue + ".gz")
            outData = try gzip(data)
        } else {
            url = folder.appendingPathComponent(file.rawValue)
            outData = data
        }
        // NSFileCoordinator for safe iCloud Drive writes.
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing,
                               error: nil) { newURL in
            do {
                try outData.write(to: newURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let e = writeError { throw e }
    }

    /// Loads Decodable data from the god-s-word/ folder.
    /// Tries `.json` first, then `.json.gz`.
    public func load<T: Decodable>(_ type: T.Type, as file: FileName) throws -> T {
        guard let folder = rootFolder else {
            throw iCloudError.notAvailable
        }
        let plain = folder.appendingPathComponent(file.rawValue)
        let gzipped = folder.appendingPathComponent(file.rawValue + ".gz")

        var readData: Data?
        var readError: Error?
        let coordinator = NSFileCoordinator()

        if FileManager.default.fileExists(atPath: gzipped.path) {
            coordinator.coordinate(readingItemAt: gzipped, options: [],
                                   error: nil) { url in
                do {
                    let compressed = try Data(contentsOf: url)
                    readData = try gunzip(compressed)
                } catch {
                    readError = error
                }
            }
        } else if FileManager.default.fileExists(atPath: plain.path) {
            coordinator.coordinate(readingItemAt: plain, options: [],
                                   error: nil) { url in
                do {
                    readData = try Data(contentsOf: url)
                } catch {
                    readError = error
                }
            }
        } else {
            throw iCloudError.fileNotFound(file.rawValue)
        }
        if let e = readError { throw e }
        guard let data = readData else {
            throw iCloudError.fileNotFound(file.rawValue)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Private repo

    /// Lists custom module files in private-repo/ (.json or .json.gz).
    public func listPrivateModules() -> [URL] {
        guard let folder = privateRepoFolder else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter {
            $0.pathExtension == "json" || $0.pathExtension == "gz"
        }
    }

    /// Downloads private Bible modules from iCloud private-repo/ to local
    /// Application Support/PrivateModules/. Call on launch and when iCloud
    /// is enabled. Returns the number of modules downloaded.
    @discardableResult
    public func syncPrivateModulesToLocal() -> Int {
        guard isEnabled, isAvailable else { return 0 }
        let remote = listPrivateModules()
        guard !remote.isEmpty else { return 0 }
        var count = 0
        let fm = FileManager.default
        try? fm.createDirectory(at: PrivateBibleStore.baseDir,
                                withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator()
        for url in remote {
            let dest = PrivateBibleStore.baseDir
                .appendingPathComponent(url.lastPathComponent)
            // Skip if already downloaded and same size (avoid redundant copies).
            if fm.fileExists(atPath: dest.path),
               let rAttr = try? fm.attributesOfItem(atPath: url.path),
               let dAttr = try? fm.attributesOfItem(atPath: dest.path),
               (rAttr[.size] as? Int) == (dAttr[.size] as? Int) {
                continue
            }
            var copyError: Error?
            coordinator.coordinate(readingItemAt: url, options: [],
                                   error: nil) { readURL in
                do {
                    // Start downloading if not yet local (iCloud Drive).
                    try fm.startDownloadingUbiquitousItem(at: readURL)
                    let data = try Data(contentsOf: readURL)
                    try data.write(to: dest, options: .atomic)
                    count += 1
                } catch {
                    copyError = error
                }
            }
            if copyError != nil { continue }
        }
        return count
    }

    // MARK: - Gzip helpers

    private func gzip(_ data: Data) throws -> Data {
        // Use NSData compression (iOS 13+).
        guard let compressed = try? (data as NSData)
            .compressed(using: .zlib) as Data else {
            throw iCloudError.compressionFailed
        }
        return compressed
    }

    private func gunzip(_ data: Data) throws -> Data {
        guard let decompressed = try? (data as NSData)
            .decompressed(using: .zlib) as Data else {
            throw iCloudError.compressionFailed
        }
        return decompressed
    }
}

public enum iCloudError: Error, Equatable {
    case notAvailable
    case fileNotFound(String)
    case compressionFailed
}

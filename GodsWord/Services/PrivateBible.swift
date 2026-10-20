// PrivateBible.swift
// Reader for private/custom Bible versions stored as JSON.
// Modules live in Application Support/PrivateModules/<ModuleID>.json
// (downloaded from iCloud Drive god-s-word/private-repo/).
//
// JSON schema:
// {
//   "id": "MyVersion",
//   "name": "My Custom Bible",
//   "language": "en",
//   "books": [
//     { "name": "Genesis",
//       "chapters": [ ["v1 text", "v2 text"], ["ch2 v1"] ] }
//   ]
// }

import Foundation

public struct PrivateBible: Codable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let books: [PrivateBook]

    public struct PrivateBook: Codable, Sendable {
        public let name: String
        /// chapters[chapterIndex][verseIndex] = verse text (0-based).
        public let chapters: [[String]]
    }

    /// Verse text for 1-based book/chapter/verse. Nil if out of range.
    public func verse(book: Int, chapter: Int, verse: Int) -> String? {
        guard book >= 1, book <= books.count else { return nil }
        let b = books[book - 1]
        guard chapter >= 1, chapter <= b.chapters.count else { return nil }
        let c = b.chapters[chapter - 1]
        guard verse >= 1, verse <= c.count else { return nil }
        return c[verse - 1]
    }

    /// All verse texts for a chapter (1-based). Nil if out of range.
    public func chapter(book: Int, chapter: Int) -> [String]? {
        guard book >= 1, book <= books.count else { return nil }
        let b = books[book - 1]
        guard chapter >= 1, chapter <= b.chapters.count else { return nil }
        return b.chapters[chapter - 1]
    }

    public var bookCount: Int { books.count }
    public func chapterCount(book: Int) -> Int {
        guard book >= 1, book <= books.count else { return 0 }
        return books[book - 1].chapters.count
    }
}

/// Loads private Bible modules from local storage.
public enum PrivateBibleStore: Sendable {
    public static var baseDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                  in: .userDomainMask).first!
            .appendingPathComponent("PrivateModules", isDirectory: true)
    }

    /// All locally available private Bibles (from .json or .json.gz).
    public static func loadAll() -> [PrivateBible] {
        loadAll(in: baseDir)
    }

    /// All private Bibles in an arbitrary folder.
    public static func loadAll(in dir: URL) -> [PrivateBible] {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles) else { return [] }
        var out: [PrivateBible] = []
        for url in files {
            if let bible = load(from: url) { out.append(bible) }
        }
        return out.sorted { $0.name < $1.name }
    }

    public static func load(from url: URL) -> PrivateBible? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let json: Data
        if url.pathExtension == "gz" {
            guard let d = try? (data as NSData).decompressed(using: .zlib) as Data
            else { return nil }
            json = d
        } else {
            json = data
        }
        return try? JSONDecoder().decode(PrivateBible.self, from: json)
    }

    /// Saves a private Bible locally (used after downloading from iCloud).
    public static func save(_ bible: PrivateBible, compressed: Bool = false) throws {
        try FileManager.default.createDirectory(at: baseDir,
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(bible)
        let url: URL
        let out: Data
        if compressed {
            url = baseDir.appendingPathComponent("\(bible.id).json.gz")
            guard let c = try? (data as NSData).compressed(using: .zlib) as Data
            else { throw PrivateBibleError.compressionFailed }
            out = c
        } else {
            url = baseDir.appendingPathComponent("\(bible.id).json")
            out = data
        }
        try out.write(to: url, options: .atomic)
    }

    /// Saves a private Bible into a specific folder (a source's location).
    public static func save(_ bible: PrivateBible, into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(bible)
        let url = dir.appendingPathComponent("\(bible.id).json")
        try data.write(to: url, options: .atomic)
    }
}

public enum PrivateBibleError: Error {
    case compressionFailed
}

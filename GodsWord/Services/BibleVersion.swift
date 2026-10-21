// BibleVersion.swift — a readable Bible version, from either the public
// CrossWire repository (a SWORD module) or the user's private imported
// JSON. The library groups versions by source, then language, then name.

import Foundation
import SwordReader

enum BibleVersion: Identifiable, Equatable {
    case sword(InstalledModule)
    case `private`(PrivateBible)

    static func == (lhs: BibleVersion, rhs: BibleVersion) -> Bool {
        lhs.id == rhs.id && lhs.isPrivate == rhs.isPrivate
    }

    /// All versions known to the library (downloaded + private imports).
    static func allInstalled(in store: ModuleStore) -> [BibleVersion] {
        store.installedModules().map(BibleVersion.sword)
            + PrivateBibleStore.loadAll().map(BibleVersion.private)
    }

    /// Stable key shared with PersonalData (notes, bookmarks, history,
    /// positions) so data stays attached to its version.
    var id: String {
        switch self {
        case .sword(let m): return m.id
        case .private(let b): return b.id
        }
    }

    /// Full title, e.g. "King James Version" / "NKJV+".
    var displayName: String {
        switch self {
        case .sword(let m): return m.info.description
        case .private(let b): return b.name
        }
    }

    /// Compact label for toolbars and pickers: the module id for SWORD
    /// versions (e.g. "KJV"), the title for private ones (e.g. "NKJV+").
    var shortLabel: String {
        switch self {
        case .sword(let m): return m.id
        case .private(let b): return b.name
        }
    }

    var language: String {
        switch self {
        case .sword(let m): return m.info.language
        case .private(let b): return b.language
        }
    }

    /// Source group name shown in the library.
    var sourceName: String {
        switch self {
        case .sword: return "CrossWire"
        case .private: return "Private"
        }
    }

    var isPrivate: Bool {
        if case .private = self { return true }
        return false
    }

    /// The public source's base URL (shown in the library). Private
    /// versions are local files and have no URL.
    var sourceURL: URL? {
        switch self {
        case .sword:
            return URL(string: "https://crosswire.org/ftpmirror/pub/sword/raw")
        case .private:
            return nil
        }
    }

    var supportsStrongs: Bool {
        switch self {
        case .sword(let m): return m.info.supportsStrongs
        case .private: return false
        }
    }

    var isChinese: Bool {
        language.lowercased().hasPrefix("zh")
    }

    /// Human-readable language group title.
    var languageTitle: String {
        let code = language.lowercased()
        if code.hasPrefix("zh") { return "中文" }
        if code.hasPrefix("en") { return "English" }
        return language.isEmpty ? "Other" : language
    }

    /// 1-based book index across the whole Bible (1–66) for a position.
    private func overallBook(testament: Int, book: Int) -> Int {
        testament == 1 ? book : 39 + book
    }

    func bookName(overall: Int) -> String {
        switch self {
        case .sword(let m):
            return m.info.isChinese
                ? BibleBookNamesZhHans[overall]
                : Versification.kjv.books[overall].name
        case .private(let b):
            return b.books[overall].name
        }
    }

    /// Like `bookName(overall:)`, but nil instead of an out-of-range crash
    /// when this version lacks the book (a private Bible can have fewer than
    /// 66 books while a bookmark points anywhere in the Bible).
    func bookNameIfPresent(overall: Int) -> String? {
        guard overall >= 0, overall < 66 else { return nil }
        if case .private(let b) = self, overall >= b.books.count { return nil }
        return bookName(overall: overall)
    }

    func chapterCount(testament: Int, book: Int) -> Int {
        switch self {
        case .sword(let m):
            return m.info.versification?
                .book(testament: testament, book: book)?.chapters ?? 0
        case .private(let b):
            return b.chapterCount(book: overallBook(testament: testament, book: book))
        }
    }

    /// Verse list for one chapter as (verse number, text).
    func loadChapter(testament: Int, book: Int, chapter: Int) async throws
        -> [(verse: Int, text: String)]
    {
        switch self {
        case .sword(let m):
            let mod = try await ModuleLoader.shared.module(for: m)
            return mod.chapter(testament: testament, book: book, chapter: chapter)
        case .private(let b):
            let ob = overallBook(testament: testament, book: book)
            guard let texts = b.chapter(book: ob, chapter: chapter) else { return [] }
            return texts.enumerated().map { (verse: $0.offset + 1, text: $0.element) }
        }
    }

    /// Strong's word tokens for one chapter (SWORD versions only).
    func loadTokens(testament: Int, book: Int, chapter: Int) async
        -> [(verse: Int, tokens: [WordToken])]
    {
        guard case .sword(let m) = self, m.info.supportsStrongs else { return [] }
        guard let mod = try? await ModuleLoader.shared.module(for: m) else { return [] }
        return mod.chapterTokens(testament: testament, book: book, chapter: chapter)
    }
}

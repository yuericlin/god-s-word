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
    /// Commentary and dictionary modules are not Bible versions and
    /// never appear here (REQ-DC-1); the auxiliary panel reaches
    /// commentaries via CommentaryModule, and dictionaries serve the
    /// Strong's tab via StrongsService. (The reader's version picker
    /// reads this list — a lexicon left in it, e.g. StrongsGreek,
    /// could be picked as a "version" and then fail to open, since a
    /// dictionary has no testament files.)
    static func allInstalled(in store: ModuleStore) -> [BibleVersion] {
        store.installedModules()
            .filter { !$0.info.isCommentary && !$0.info.isDictionary }
            .map(BibleVersion.sword)
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

    /// Full title, e.g. "King James Version".
    var displayName: String {
        switch self {
        case .sword(let m): return m.info.description
        case .private(let b): return b.name
        }
    }

    /// Compact label for toolbars and pickers: the module id for SWORD
    /// versions (e.g. "KJV"), the title for private ones.
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
            // A "¶…¶" prefix is the verse's section heading
            // (REQ-RS-5), not verse text. Whitespace is sanitized
            // for display like module text (REQ-RS-6).
            return texts.enumerated().map {
                (verse: $0.offset + 1,
                 text: OsisPlain.sanitized(PrivateBible.splitHeading($0.element).text))
            }
        }
    }

    /// Canonical English book name for the red-letter artifact key
    /// (the KJV versification's name, e.g. "Revelation of John").
    private func artifactBookName(testament: Int, book: Int) -> String {
        let overall = testament == 1 ? book - 1 : 39 + book - 1
        return Versification.kjv.books[overall].name
    }

    /// Strong's word tokens for one chapter (SWORD versions only).
    /// Tokens also carry Jesus-speech flags — from the module
    /// markup (REQ-RL-1), or, for a tagless Strong's module like
    /// ChiUns, from the bundled artifact (REQ-RL-4); the reader's
    /// red-letter setting decides whether they are painted.
    func loadTokens(testament: Int, book: Int, chapter: Int) async
        -> [(verse: Int, tokens: [WordToken])]
    {
        guard case .sword(let m) = self, m.info.supportsStrongs else { return [] }
        guard let mod = try? await ModuleLoader.shared.module(for: m) else { return [] }
        let tokenChapter = mod.chapterTokensWithJesus(testament: testament, book: book, chapter: chapter)
        guard tokenChapter.allSatisfy({ $0.tokens.allSatisfy { !$0.isJesusSpeech } })
        else { return tokenChapter }
        // No markup flags anywhere in the chapter: fall back to
        // the artifact. Tokens are plain-text segments, so
        // cumulative character offsets locate each one.
        let spans = RedLetterArtifact.chapterSpans(
            versionID: m.id,
            book: artifactBookName(testament: testament, book: book),
            chapter: chapter)
        guard !spans.isEmpty else { return tokenChapter }
        return tokenChapter.map { entry in
            let verseSpans = spans[entry.verse] ?? []
            guard !verseSpans.isEmpty else { return entry }
            var offset = 0
            let marked = entry.tokens.map { token -> WordToken in
                let range = (start: offset, end: offset + token.text.count)
                offset = range.end
                guard verseSpans.contains(where: { range.start < $0.end && $0.start < range.end })
                else { return token }
                return WordToken(text: token.text, strongs: token.strongs,
                                 isJesusSpeech: true)
            }
            return (verse: entry.verse, tokens: marked)
        }
    }

    /// Jesus-speech character spans per verse for one chapter:
    /// the module's own `<q who="Jesus">` markup where it speaks
    /// (REQ-RL-1), otherwise the bundled artifact for versions it
    /// covers — currently ChiUns (REQ-RL-4).
    func loadJesusSpans(testament: Int, book: Int, chapter: Int) async
        -> [Int: [(start: Int, end: Int)]]
    {
        switch self {
        case .sword(let m):
            if let mod = try? await ModuleLoader.shared.module(for: m) {
                let tagged = mod.chapterJesusSpans(testament: testament, book: book, chapter: chapter)
                if !tagged.isEmpty { return tagged }
            }
            return RedLetterArtifact.chapterSpans(
                versionID: m.id,
                book: artifactBookName(testament: testament, book: book),
                chapter: chapter)
        case .private:
            // The artifact is built purely from published
            // modules and never relies on a private version;
            // private imports carry no markup and return none.
            return [:]
        }
    }

    /// Section headings ("subtitles") for one chapter, keyed by
    /// verse number (REQ-RS-5). SWORD versions read the preverse
    /// section titles out of the module; private versions carry
    /// theirs as a "¶…¶" prefix on the verse string.
    func loadHeadings(testament: Int, book: Int, chapter: Int) async -> [Int: String] {
        switch self {
        case .sword(let m):
            guard let mod = try? await ModuleLoader.shared.module(for: m)
            else { return [:] }
            return mod.chapterHeadings(testament: testament, book: book, chapter: chapter)
        case .private(let b):
            let ob = overallBook(testament: testament, book: book)
            guard let texts = b.chapter(book: ob, chapter: chapter) else { return [:] }
            var out = [Int: String]()
            for (i, text) in texts.enumerated() {
                if let heading = PrivateBible.splitHeading(text).heading {
                    out[i + 1] = OsisPlain.sanitized(heading)
                }
            }
            return out
        }
    }
}

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
        // the chapter's span source (the bundled artifact, or
        // on-device derivation via loadJesusSpans). Tokens are
        // plain-text segments, so cumulative character offsets
        // locate each one.
        let spans = await loadJesusSpans(testament: testament, book: book, chapter: chapter)
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
    /// covers — currently ChiUns (REQ-RL-4) — otherwise spans
    /// derived on-device from the installed markup-carrying
    /// versions (REQ-RL-5).
    func loadJesusSpans(testament: Int, book: Int, chapter: Int) async
        -> [Int: [(start: Int, end: Int)]]
    {
        switch self {
        case .sword(let m):
            if let mod = try? await ModuleLoader.shared.module(for: m) {
                let tagged = mod.chapterJesusSpans(testament: testament, book: book, chapter: chapter)
                if !tagged.isEmpty { return tagged }
            }
            let artifact = RedLetterArtifact.chapterSpans(
                versionID: m.id,
                book: artifactBookName(testament: testament, book: book),
                chapter: chapter)
            if !artifact.isEmpty { return artifact }
            return await RedLetterDerivationService.shared.derivedSpans(
                version: self, testament: testament, book: book, chapter: chapter)
        case .private:
            return await RedLetterDerivationService.shared.derivedSpans(
                version: self, testament: testament, book: book, chapter: chapter)
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

/// On-device red-letter derivation (REQ-RL-5), derive-once: the
/// first read that needs a book's spans runs the transfer from
/// the bundled source truth (`RedLetterTruth` — extracted from
/// the published NASB1995 and KJV modules, so neither module
/// needs to be installed) and saves the resulting span table on
/// the device; every later read is a plain lookup. A saved table
/// is keyed to the truth it was derived from and, for private
/// imports, to a fingerprint of the book's text, so a truth
/// update or a re-import re-derives instead of serving stale
/// spans. Module versions are keyed by id, as the module cache
/// keys them. Tables live in Application Support/DerivedRedLetters.
private actor RedLetterDerivationService {
    static let shared = RedLetterDerivationService()

    /// One book's derived spans: "chapter.verse" → [start, end] pairs.
    private struct SpanTable: Codable {
        var sourceSignature: String
        var targetFingerprint: String
        var spans: [String: [[Int]]]
    }

    private var loadedTables: [String: SpanTable] = [:]

    func derivedSpans(version: BibleVersion, testament: Int, book: Int, chapter: Int) async
        -> [Int: [(start: Int, end: Int)]]
    {
        // Jesus's speech is a New Testament record; the bundled
        // truth covers nothing elsewhere.
        guard testament == 2 else { return [:] }
        let signature = "bundled:" + RedLetterTruth.sourceIDs.joined(separator: ",")
        let key = "\(version.id)|\(testament).\(book)"
        // Private imports are fingerprinted from their live text
        // (already in memory); module versions key by id.
        var liveBook: [(chapter: Int, verse: Int, text: String)]?
        var fingerprint = "module"
        if case .private = version {
            let texts = await bookTexts(version: version, testament: testament, book: book)
            liveBook = texts
            fingerprint = Self.fingerprint(of: texts)
        }
        if let table = table(for: key, versionID: version.id,
                             testament: testament, book: book),
           table.sourceSignature == signature,
           table.targetFingerprint == fingerprint {
            return Self.chapterSlice(table, chapter: chapter)
        }

        // Derive the whole book once, then save it.
        let content = liveBook ?? await bookTexts(version: version,
                                                  testament: testament, book: book)
        var spans: [String: [[Int]]] = [:]
        if !content.isEmpty,
           let mode = RedLetterDerivation.detectMode(texts: content.map { $0.text }) {
            let overall = 39 + book - 1  // testament == 2 here
            let bookName = Versification.kjv.books[overall].name
            let parity = RedLetterDerivation.parityStartsInside(
                texts: content.map { $0.text }, mode: mode)
            var derived: [Int: [Int: [(start: Int, end: Int)]]] = [:]
            for sourceID in RedLetterTruth.sourceIDs {
                for c in Set(content.map { $0.chapter }).sorted() {
                    let truthChapter = RedLetterTruth.truth(
                        sourceID: sourceID, book: bookName, chapter: c)
                    guard !truthChapter.isEmpty else { continue }
                    var startsInside: [Int: Bool] = [:]
                    var target: [(verse: Int, text: String)] = []
                    for (index, entry) in content.enumerated() where entry.chapter == c {
                        target.append((verse: entry.verse, text: entry.text))
                        startsInside[entry.verse] = parity[index]
                    }
                    let one = RedLetterDerivation.deriveChapter(
                        target: target, truth: truthChapter,
                        startsInside: startsInside, mode: mode)
                    guard !one.isEmpty else { continue }
                    // The earlier source is primary; later sources
                    // fill the verses it left unpainted.
                    derived[c] = derived[c].map {
                        RedLetterDerivation.merge(primary: $0, fallback: one)
                    } ?? one
                }
            }
            for (c, chapterSpans) in derived {
                for (v, verseSpans) in chapterSpans where !verseSpans.isEmpty {
                    spans["\(c).\(v)"] = verseSpans.map { [$0.start, $0.end] }
                }
            }
        }
        let table = SpanTable(sourceSignature: signature,
                              targetFingerprint: fingerprint, spans: spans)
        save(table, for: key, versionID: version.id, testament: testament, book: book)
        return Self.chapterSlice(table, chapter: chapter)
    }

    // MARK: - Tables on disk

    private func tableFile(versionID: String, testament: Int, book: Int) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let safeID = versionID.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let dir = appSupport.appendingPathComponent("DerivedRedLetters",
                                                    isDirectory: true)
            .appendingPathComponent(String(safeID), isDirectory: true)
        return dir.appendingPathComponent("\(testament)-\(book).json")
    }

    private func table(for key: String, versionID: String,
                       testament: Int, book: Int) -> SpanTable?
    {
        if let hit = loadedTables[key] { return hit }
        let url = tableFile(versionID: versionID, testament: testament, book: book)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SpanTable.self, from: data)
        else { return nil }
        loadedTables[key] = decoded
        return decoded
    }

    private func save(_ table: SpanTable, for key: String, versionID: String,
                      testament: Int, book: Int) {
        loadedTables[key] = table
        let url = tableFile(versionID: versionID, testament: testament, book: book)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(table) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func chapterSlice(_ table: SpanTable, chapter: Int)
        -> [Int: [(start: Int, end: Int)]]
    {
        var out: [Int: [(start: Int, end: Int)]] = [:]
        for (ref, pairs) in table.spans {
            let parts = ref.split(separator: ".")
            guard parts.count == 2, Int(parts[0]) == chapter,
                  let verse = Int(parts[1]) else { continue }
            out[verse] = pairs.compactMap { $0.count == 2 ? (start: $0[0], end: $0[1]) : nil }
        }
        return out
    }

    /// FNV-1a over a private book's rendered texts, in order.
    private static func fingerprint(
        of texts: [(chapter: Int, verse: Int, text: String)]) -> String
    {
        var hash: UInt64 = 0xcbf29ce484222325
        func feed(_ s: String) {
            for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
            hash = (hash ^ 0x1f) &* 0x100000001b3
        }
        for entry in texts {
            feed("\(entry.chapter).\(entry.verse)")
            feed(entry.text)
        }
        return String(hash, radix: 16)
    }

    // MARK: - Derivation inputs

    /// The target book's rendered texts in book order.
    private func bookTexts(version: BibleVersion, testament: Int, book: Int) async
        -> [(chapter: Int, verse: Int, text: String)]
    {
        var out: [(chapter: Int, verse: Int, text: String)] = []
        let chapters = version.chapterCount(testament: testament, book: book)
        guard chapters > 0 else { return [] }
        for c in 1 ... chapters {
            guard let rows = try? await version.loadChapter(
                testament: testament, book: book, chapter: c) else { continue }
            for row in rows { out.append((chapter: c, verse: row.verse, text: row.text)) }
        }
        return out
    }
}

// ScriptureReferences.swift
// Clickable scripture references inside commentary entries
// (REQ-AP-19). ThML commentaries such as TSK carry their cross
// references in <scripRef> elements; the plain-text conversion
// keeps the reference text but drops the tags, so this scanner
// works from the RAW entry: it parses each scripRef's reference
// list into targets, then anchors the parsed items in the entry's
// plain text (whose wording it never changes) to produce segments
// the UI can render with links.
//
// The list grammar, verified against the whole TSK module
// (85,508 scripRef elements, 316,273 list items):
//   list  := item (";" item)*
//   item  := [Book] chapter ":" verseList | chapter ":" verseList
//          | verseList                      (continuations)
//   verseList := part ("," part)*
//   part  := verse | verse "-" verse | verse "-" chapter ":" verse
// A continuation reuses the book / chapter of the item before it,
// starting from the entry's own book and chapter. An item starting
// with "*" ("*marg:", "*title") is a margin marker, not a
// reference. A range that crosses into a later chapter targets
// its starting chapter, with the verses it covers there. Anything
// that does not parse stays plain text — a reference is never
// guessed.

import Foundation

/// One parsed scripture reference: a chapter plus the verses in
/// it the reference covers.
public struct ScriptureReferenceTarget: Equatable, Sendable {
    /// 1 = Old Testament, 2 = New Testament.
    public let testament: Int
    /// 1-based book index within its testament.
    public let book: Int
    public let chapter: Int
    /// The referenced verses in `chapter`, ascending, de-duplicated.
    public let verses: [Int]

    public init(testament: Int, book: Int, chapter: Int, verses: [Int]) {
        self.testament = testament
        self.book = book
        self.chapter = chapter
        self.verses = verses
    }

    /// 0-based book index across the whole Bible (0–65).
    public var overallBook: Int {
        testament == 1 ? book - 1 : 39 + book - 1
    }
}

public enum ScriptureReferences {
    public enum Segment: Equatable, Sendable {
        case text(String)
        case reference(display: String, target: ScriptureReferenceTarget)
    }

    /// Resolution context carried across the items of one entry:
    /// continuations inherit the book and chapter last referenced.
    private struct Context {
        var overall: Int
        var chapter: Int
    }

    /// Split one commentary entry into text and reference segments.
    /// `plain` is the entry's rendered plain text (what the UI
    /// shows today); `raw` is the entry's raw markup, used only to
    /// find and parse its scripRef elements. When nothing parses,
    /// the result is a single text segment holding `plain`.
    public static func segments(plain: String, raw: String,
                                testament: Int, book: Int, chapter: Int)
        -> [Segment]
    {
        let refs = scripRefs(in: raw)
        guard !refs.isEmpty else { return plain.isEmpty ? [] : [.text(plain)] }
        var context = Context(overall: testament == 1 ? book - 1 : 39 + book - 1,
                              chapter: chapter)
        var out: [Segment] = []
        var cursor = plain.startIndex
        for ref in refs {
            // Parse first (this advances the context whether or not
            // the content can be anchored in the plain text).
            let items: [(display: String, target: ScriptureReferenceTarget?)]
            if let passage = ref.passage {
                let target = parseItem(passage, context: &context)
                items = [(display: ref.content, target: target)]
            } else {
                items = ref.content
                    .split(separator: ";", omittingEmptySubsequences: false)
                    .map { part in
                        let display = String(part)
                            .trimmingCharacters(in: .whitespaces)
                        return (display: display,
                                target: display.isEmpty
                                    ? nil : parseItem(display, context: &context))
                    }
            }
            guard !ref.content.isEmpty,
                  let span = plain.range(of: ref.content,
                                         range: cursor ..< plain.endIndex)
            else { continue }
            if span.lowerBound > cursor {
                out.append(.text(String(plain[cursor ..< span.lowerBound])))
            }
            // Emit the items inside the span, keeping the exact
            // separators and any unparsed item as plain text.
            var inner = span.lowerBound
            for item in items {
                guard !item.display.isEmpty,
                      let r = plain.range(of: item.display,
                                          range: inner ..< span.upperBound)
                else { continue }
                if r.lowerBound > inner {
                    out.append(.text(String(plain[inner ..< r.lowerBound])))
                }
                if let target = item.target {
                    out.append(.reference(display: item.display, target: target))
                } else {
                    out.append(.text(item.display))
                }
                inner = r.upperBound
            }
            if inner < span.upperBound {
                out.append(.text(String(plain[inner ..< span.upperBound])))
            }
            cursor = span.upperBound
        }
        if cursor < plain.endIndex {
            out.append(.text(String(plain[cursor ..< plain.endIndex])))
        }
        // Coalesce neighbouring text segments; drop empty ones.
        var merged: [Segment] = []
        for segment in out {
            switch segment {
            case .text(let s) where s.isEmpty:
                continue
            case .text(let s):
                if let last = merged.last, case .text(let prev) = last {
                    merged[merged.count - 1] = .text(prev + s)
                } else {
                    merged.append(segment)
                }
            case .reference:
                merged.append(segment)
            }
        }
        return merged
    }

    // MARK: - scripRef extraction

    private struct ScripRef {
        /// The `passage` attribute ("Ge 1:1"), when present.
        let passage: String?
        /// The element's inner text, trimmed.
        let content: String
    }

    private static func scripRefs(in raw: String) -> [ScripRef] {
        var out: [ScripRef] = []
        var search = raw.startIndex
        while let open = raw.range(of: "<scripRef", range: search ..< raw.endIndex),
              let tagEnd = raw.range(of: ">", range: open.upperBound ..< raw.endIndex),
              let close = raw.range(of: "</scripRef>",
                                     range: tagEnd.upperBound ..< raw.endIndex)
        {
            let attrs = String(raw[open.upperBound ..< tagEnd.lowerBound])
            var passage: String?
            if let p = attrs.range(of: "passage=\""),
               let q = attrs.range(of: "\"", range: p.upperBound ..< attrs.endIndex)
            {
                passage = String(attrs[p.upperBound ..< q.lowerBound])
            }
            let content = String(raw[tagEnd.upperBound ..< close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(ScripRef(passage: passage, content: content))
            search = close.upperBound
        }
        return out
    }

    // MARK: - Item parsing

    /// Parse one list item ("Ps 33:6,9", "104:30", "10,12",
    /// "Isa 13:1-14:32") against the running context, updating the
    /// context to the item's last referenced location. Returns nil
    /// when the item is not a reference (margin markers, prose,
    /// malformed data) — it then renders as plain text.
    private static func parseItem(_ item: String, context: inout Context)
        -> ScriptureReferenceTarget?
    {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("*") else { return nil }
        var tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        var overall = context.overall
        if tokens.count > 1, let book = bookIndex(forToken: tokens[0]) {
            overall = book
            tokens.removeFirst()
        }
        guard tokens.count == 1 else { return nil }
        let body = tokens[0]

        // Verse parts, comma-separated; the first may carry the
        // chapter as "chapter:rest".
        var parts = body.split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        guard !parts.isEmpty else { return nil }
        var chapter = context.chapter
        if let colon = parts[0].firstIndex(of: ":") {
            guard let ch = Int(parts[0][..<colon]) else { return nil }
            chapter = ch
            parts[0] = String(parts[0][parts[0].index(after: colon)...])
            guard !parts[0].isEmpty else { return nil }
        }
        guard chapter >= 1,
              chapter <= Versification.kjv.books[overall].chapters
        else { return nil }

        let targetChapter = chapter
        var currentChapter = chapter
        var verses = Set<Int>()
        for (index, part) in parts.enumerated() {
            guard let contributed = parsePart(part,
                                              chapter: &currentChapter,
                                              overall: overall,
                                              isFirst: index == 0)
            else { return nil }
            if currentChapter == targetChapter || index == 0 {
                verses.formUnion(contributed)
            }
        }
        // Only the target chapter's verses can be shown; parts that
        // moved on to a later chapter contribute nothing here, but
        // they still moved the context (below). A part can also
        // wander back — its verses count when it is in the target
        // chapter, which parsePart reports through `chapter`.
        guard !verses.isEmpty else { return nil }
        context.overall = overall
        context.chapter = currentChapter
        let testament = overall < 39 ? 1 : 2
        let book = overall < 39 ? overall + 1 : overall - 39 + 1
        return ScriptureReferenceTarget(testament: testament, book: book,
                                        chapter: targetChapter,
                                        verses: verses.sorted())
    }

    /// Parse one comma-separated verse part: "7", "6-9", "1-21:45",
    /// or (not as the first part) "104:30". `chapter` is the part's
    /// starting chapter and is updated to the chapter the part ends
    /// in. Returns the verses the part covers in the chapter it
    /// STARTS in (the caller keeps only its target chapter's), or
    /// nil when the part is malformed.
    private static func parsePart(_ part: String, chapter: inout Int,
                                  overall: Int, isFirst: Bool) -> Set<Int>?
    {
        guard chapter >= 1,
              chapter <= Versification.kjv.books[overall].chapters
        else { return nil }
        var startChapter = chapter
        var rest = part
        // A "chapter:verse" part (not the first part, whose chapter
        // prefix the item parser already consumed).
        if !isFirst, let colon = part.firstIndex(of: ":") {
            guard let ch = Int(part[..<colon]),
                  ch >= 1, ch <= Versification.kjv.books[overall].chapters
            else { return nil }
            startChapter = ch
            rest = String(part[part.index(after: colon)...])
            chapter = ch
        }
        let ends = rest.split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)
        guard ends.count == 1 || ends.count == 2,
              let startVerse = Int(ends[0]), startVerse >= 1
        else { return nil }
        let count = Versification.kjv.versesPerChapter[overall][startChapter - 1]
        guard startVerse <= count else { return nil }
        guard ends.count == 2 else {
            return [startVerse]
        }
        // Range end: "verse" in the same chapter, or "chapter:verse".
        var endChapter = startChapter
        var endVerseText = ends[1]
        if let colon = ends[1].firstIndex(of: ":") {
            guard let ch = Int(ends[1][..<colon]),
                  ch >= 1, ch <= Versification.kjv.books[overall].chapters
            else { return nil }
            endChapter = ch
            endVerseText = String(ends[1][ends[1].index(after: colon)...])
        }
        guard let endVerse = Int(endVerseText), endVerse >= 1 else { return nil }
        chapter = endChapter
        if endChapter == startChapter {
            guard endVerse >= startVerse else { return nil }
            return Set(startVerse ... min(endVerse, count))
        }
        guard endChapter > startChapter else { return nil }
        // Crossing into a later chapter: the part covers the rest
        // of its starting chapter.
        return Set(startVerse ... count)
    }

    // MARK: - Book tokens

    /// 0-based overall book index for a reference token, matched
    /// case-insensitively ("ge", "Ge", "Gen", "Josh", "1Sa", …).
    /// The table covers every token TSK uses (enumerated from the
    /// module itself) plus the OSIS book ids and common variants,
    /// so other ThML commentaries resolve too.
    private static func bookIndex(forToken token: String) -> Int? {
        bookTokens[token.lowercased()]
    }

    private static let bookTokens: [String: Int] = {
        let table: [(Int, [String])] = [
            (0, ["ge", "gen", "genesis"]),
            (1, ["ex", "exod", "exodus"]),
            (2, ["le", "lev", "leviticus"]),
            (3, ["nu", "num", "numbers"]),
            (4, ["de", "deut", "deuteronomy"]),
            (5, ["jos", "josh", "joshua"]),
            (6, ["jud", "judg", "judges"]),
            (7, ["ru", "ruth"]),
            (8, ["1sa", "1sam", "1samuel"]),
            (9, ["2sa", "2sam", "2samuel"]),
            (10, ["1ki", "1kings"]),
            (11, ["2ki", "2kings"]),
            (12, ["1ch", "1chr", "1chronicles"]),
            (13, ["2ch", "2chr", "2chronicles"]),
            (14, ["ezr", "ezra"]),
            (15, ["ne", "neh", "nehemiah"]),
            (16, ["es", "esth", "esther"]),
            (17, ["job"]),
            (18, ["ps", "psa", "psalm", "psalms"]),
            (19, ["pr", "prov", "proverbs"]),
            (20, ["ec", "eccl", "ecclesiastes"]),
            (21, ["so", "song", "cant"]),
            (22, ["isa", "isaiah"]),
            (23, ["jer", "jeremiah"]),
            (24, ["la", "lam", "lamentations"]),
            (25, ["eze", "ezek", "ezekiel"]),
            (26, ["da", "dan", "daniel"]),
            (27, ["ho", "hos", "hosea"]),
            (28, ["joe", "joel"]),
            (29, ["am", "amos"]),
            (30, ["ob", "obad", "obadiah"]),
            (31, ["jon", "jonah"]),
            (32, ["mic", "micah"]),
            (33, ["na", "nah", "nahum"]),
            (34, ["hab", "habakkuk"]),
            (35, ["zep", "zeph", "zephaniah"]),
            (36, ["hag", "haggai"]),
            (37, ["zec", "zech", "zechariah"]),
            (38, ["mal", "malachi"]),
            (39, ["mt", "matt", "matthew"]),
            (40, ["mr", "mark"]),
            (41, ["lu", "luke"]),
            (42, ["joh", "john"]),
            (43, ["ac", "acts"]),
            (44, ["ro", "rom", "romans"]),
            (45, ["1co", "1cor"]),
            (46, ["2co", "2cor"]),
            (47, ["ga", "gal", "galatians"]),
            (48, ["eph", "ephesians"]),
            (49, ["php", "phil", "philippians"]),
            (50, ["col", "colossians"]),
            (51, ["1th", "1thess"]),
            (52, ["2th", "2thess"]),
            (53, ["1ti", "1tim"]),
            (54, ["2ti", "2tim"]),
            (55, ["tit", "titus"]),
            (56, ["phm", "phlm", "philemon"]),
            (57, ["heb", "hebrews"]),
            (58, ["jas", "james"]),
            (59, ["1pe", "1pet", "1peter"]),
            (60, ["2pe", "2pet", "2peter"]),
            (61, ["1jo", "1jn", "1john"]),
            (62, ["2jo", "2jn", "2john"]),
            (63, ["3jo", "3jn", "3john"]),
            (64, ["jude"]),
            (65, ["re", "rev", "revelation"]),
        ]
        var out: [String: Int] = [:]
        for (index, tokens) in table {
            for token in tokens { out[token] = index }
        }
        return out
    }()
}

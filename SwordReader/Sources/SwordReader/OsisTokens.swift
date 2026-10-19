// OsisTokens.swift
// Splits SWORD OSIS verse markup into word tokens, capturing Strong's
// numbers from <w lemma="strong:H07225 ...">word</w> tags.
// Words are taken from the plain-text rendering (so rejoining them with
// spaces always reproduces the plain verse text); each <w>'s Strong's
// numbers attach to every plain word its content overlaps. A <w> whose
// inner text holds several words (e.g. "In the beginning") yields one
// token per word, each carrying the same Strong's numbers.

import Foundation

/// One word of verse text with its Strong's numbers (possibly empty).
public struct WordToken: Sendable {
    public let text: String
    /// Normalized Strong's numbers, e.g. ["H7225", "G26"].
    public let strongs: [String]

    public init(text: String, strongs: [String] = []) {
        self.text = text
        self.strongs = strongs
    }
}

public enum OsisTokens {
    /// Tokenizes OSIS verse markup, capturing Strong's numbers.
    ///
    /// Words come from the plain-text rendering itself, so rejoining the
    /// tokens with spaces always reproduces the plain verse text. Each
    /// `<w>...</w>` is located in that plain text (in document order) and
    /// its Strong's numbers attach to every plain word it overlaps —
    /// covering multi-word `<w>`s ("In the beginning"), punctuation glued
    /// to words ("(For", "David.Hear"), and self-closing `<w/>` tags,
    /// which carry no word and are skipped.
    public static func tokensWithStrongs(from osis: String) -> [WordToken] {
        let s = OsisPlain.removeNotes(osis)
        let plain = OsisPlain.plainText(from: s)

        // (plain range, Strong's) for each <w>, in document order.
        var ranges = [(range: Range<String.Index>, strongs: [String])]()
        var searchFrom = plain.startIndex
        var i = s.startIndex
        let end = s.endIndex
        while i < end {
            guard let lt = s[i...].firstIndex(of: "<") else { break }
            i = lt
            guard isWOpenTag(at: i, in: s),
                  let tagEnd = s[i...].firstIndex(of: ">")
            else {
                i = s.index(after: i)
                continue
            }
            let tag = s[i...tagEnd]
            let innerStart = s.index(after: tagEnd)
            // Self-closing <w .../> has no word; its numbers anchor nothing.
            guard !tag.hasSuffix("/>"),
                  let close = s.range(of: "</w>", options: .caseInsensitive,
                                      range: innerStart ..< end)
            else {
                i = innerStart
                continue
            }
            let strongs = strongsFromWTag(String(tag))
            let innerPlain = OsisPlain.plainText(from: String(s[innerStart ..< close.lowerBound]))
            if !innerPlain.isEmpty,
               let r = plain.range(of: innerPlain,
                                   range: searchFrom ..< plain.endIndex) {
                ranges.append((r, strongs))
                searchFrom = r.upperBound
            }
            i = close.upperBound
        }

        // Plain words (single spaces: plainText collapses whitespace).
        var tokens = [WordToken]()
        var wi = plain.startIndex
        while wi < plain.endIndex {
            let wEnd = plain[wi...].firstIndex(of: " ") ?? plain.endIndex
            var strongs = [String]()
            for r in ranges where r.range.lowerBound < wEnd && r.range.upperBound > wi {
                for st in r.strongs where !strongs.contains(st) { strongs.append(st) }
            }
            tokens.append(WordToken(text: String(plain[wi ..< wEnd]), strongs: strongs))
            wi = wEnd == plain.endIndex ? wEnd : plain.index(after: wEnd)
        }
        return tokens
    }

    /// True when s[i] starts a `<w ...>` opening tag (case-insensitive).
    private static func isWOpenTag(at i: String.Index, in s: String) -> Bool {
        var j = s.index(after: i)
        guard j < s.endIndex, s[j] == "w" || s[j] == "W" else { return false }
        j = s.index(after: j)
        return j >= s.endIndex || s[j] == " " || s[j] == "\t" || s[j] == ">" || s[j] == "/"
    }

    /// Extracts Strong's numbers from a `<w ...>` tag's lemma attribute.
    static func strongsFromWTag(_ tag: String) -> [String] {
        guard let lemmaRange = tag.range(of: "lemma", options: .caseInsensitive),
              let eq = tag[lemmaRange.upperBound...].firstIndex(of: "=")
        else { return [] }
        let afterEq = tag[tag.index(after: eq)...].drop(while: { $0 == " " || $0 == "\t" })
        guard let quote = afterEq.first, quote == "\"" || quote == "'" else { return [] }
        let rest = afterEq.dropFirst()
        guard let endQuote = rest.firstIndex(of: quote) else { return [] }
        return rest[..<endQuote].split(separator: " ").compactMap {
            normalizeStrongs(String($0))
        }
    }

    /// "strong:H07225" -> "H7225". Returns nil for non-Strong's lemmas.
    static func normalizeStrongs(_ s: String) -> String? {
        let parts = s.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "strong" else { return nil }
        let key = parts[1].uppercased()
        guard let first = key.first, first.isLetter else { return nil }
        let digits = key.dropFirst().drop(while: { $0 == "0" })
        guard !digits.isEmpty else { return nil }
        return String(first) + digits
    }
}

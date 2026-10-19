// OsisTokens.swift
// Splits SWORD OSIS verse markup into word tokens, capturing Strong's
// numbers from <w lemma="strong:H07225 ...">word</w> tags.
// A <w> whose inner text holds several words (e.g. "In the beginning")
// yields one token per word, each carrying the same Strong's numbers.
// Punctuation-only runs outside <w> merge into the preceding token so
// rejoining tokens with spaces reproduces the plain verse text.

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
    public static func tokensWithStrongs(from osis: String) -> [WordToken] {
        let s = OsisPlain.removeNotes(osis)
        var tokens = [WordToken]()
        var i = s.startIndex
        let end = s.endIndex
        var textRun = ""
        func flushTextRun() {
            let clean = OsisPlain.plainText(from: textRun)
            for part in clean.split(separator: " ") {
                appendWord(String(part), strongs: [], to: &tokens)
            }
            textRun = ""
        }
        while i < end {
            if s[i] == "<" {
                if isWOpenTag(at: i, in: s) {
                    flushTextRun()
                    guard let tagEnd = s[i...].firstIndex(of: ">") else { break }
                    let strongs = strongsFromWTag(String(s[i...tagEnd]))
                    let innerStart = s.index(after: tagEnd)
                    if let close = s.range(of: "</w>", options: .caseInsensitive,
                                           range: innerStart ..< end) {
                        let clean = OsisPlain.plainText(from: String(s[innerStart ..< close.lowerBound]))
                        for part in clean.split(separator: " ") {
                            appendWord(String(part), strongs: strongs, to: &tokens)
                        }
                        i = close.upperBound
                    } else {
                        i = s.index(after: tagEnd)
                    }
                } else {
                    // Skip any other tag.
                    flushTextRun()
                    if let tagEnd = s[i...].firstIndex(of: ">") {
                        i = s.index(after: tagEnd)
                    } else {
                        break
                    }
                }
            } else {
                textRun.append(s[i])
                i = s.index(after: i)
            }
        }
        flushTextRun()
        return tokens
    }

    /// Appends a word, merging punctuation-only runs (".", ",", ...) into
    /// the preceding token so the text rejoins cleanly.
    private static func appendWord(_ word: String, strongs: [String],
                                   to tokens: inout [WordToken]) {
        if strongs.isEmpty, isPunctuationOnly(word), let last = tokens.last {
            tokens[tokens.count - 1] = WordToken(text: last.text + word,
                                                 strongs: last.strongs)
        } else {
            tokens.append(WordToken(text: word, strongs: strongs))
        }
    }

    private static func isPunctuationOnly(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
        }
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

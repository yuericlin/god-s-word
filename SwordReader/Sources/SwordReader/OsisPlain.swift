// OsisPlain.swift
// Converts SWORD OSIS verse markup to plain display text:
// drops notes/cross-references, strips tags (keeping inner text),
// decodes entities, collapses whitespace.
// Implemented as a single-pass scanner (no regex) to keep chapter
// rendering fast on device.

import Foundation

public enum OsisPlain {
    public static func plainText(from osis: String) -> String {
        let withoutNotes = removeNotes(osis)
        // Strip tags, keeping inner text. <lb/> becomes a space.
        var stripped = ""
        stripped.reserveCapacity(withoutNotes.count)
        var i = withoutNotes.startIndex
        let end = withoutNotes.endIndex
        var pendingSpace = false
        while i < end {
            let c = withoutNotes[i]
            if c == "<" {
                guard let close = withoutNotes[i...].firstIndex(of: ">") else { break }
                if isLineBreakTag(withoutNotes[i...close]) { pendingSpace = true }
                i = withoutNotes.index(after: close)
            } else {
                if pendingSpace {
                    if let last = stripped.last, !last.isWhitespace { stripped.append(" ") }
                    pendingSpace = false
                }
                stripped.append(c)
                i = withoutNotes.index(after: i)
            }
        }
        // Decode entities + collapse whitespace + trim, in one pass.
        var out = ""
        out.reserveCapacity(stripped.count)
        i = stripped.startIndex
        let strippedEnd = stripped.endIndex
        var lastWasSpace = true // trims leading whitespace
        while i < strippedEnd {
            let c = stripped[i]
            if c == "&", let (decoded, next) = decodeEntity(at: i, in: stripped) {
                if decoded.isWhitespace {
                    if !lastWasSpace { out.append(" "); lastWasSpace = true }
                } else {
                    out.append(decoded)
                    lastWasSpace = false
                }
                i = next
                continue
            }
            if c.isWhitespace || c == "\u{00A0}" {
                if !lastWasSpace { out.append(" "); lastWasSpace = true }
            } else {
                out.append(c)
                lastWasSpace = false
            }
            i = stripped.index(after: i)
        }
        // Trim one trailing space. (Guard on content, not on lastWasSpace:
        // an empty or all-whitespace input leaves `out` empty, and
        // removeLast() on an empty string is a fatal error.)
        if out.last == " " { out.removeLast() }
        return sanitized(out)
    }

    /// Whitespace cleanup for display (REQ-RS-6): collapses runs to
    /// a single space and trims, then removes spaces that are never
    /// wanted in print — between CJK letters and around CJK
    /// punctuation (the Chinese modules segment text with spaces
    /// that render as gaps, e.g. "看见 神的灵" for "看见神的灵"),
    /// and before closing punctuation. Latin word spacing is
    /// otherwise untouched. Applied to every verse the reader
    /// shows: `plainText` ends here, and private versions are
    /// sanitized by the caller.
    public static func sanitized(_ text: String) -> String {
        var chars: [Character] = []
        chars.reserveCapacity(text.count)
        var lastWasSpace = true // trims leading whitespace
        for c in text {
            if c.isWhitespace || c == "\u{00A0}" {
                if !lastWasSpace { chars.append(" "); lastWasSpace = true }
            } else {
                chars.append(c)
                lastWasSpace = false
            }
        }
        if chars.last == " " { chars.removeLast() }
        var out = ""
        out.reserveCapacity(chars.count)
        for idx in chars.indices {
            let c = chars[idx]
            if c == " ", idx > 0, idx + 1 < chars.count,
               dropsSpace(prev: chars[idx - 1], next: chars[idx + 1],
                          afterNext: idx + 2 < chars.count ? chars[idx + 2] : nil) {
                continue
            }
            out.append(c)
        }
        return out
    }

    /// True when the single space between `prev` and `next` should
    /// not print. `afterNext` disambiguates quotes: a closing quote
    /// (at the end, or followed by space/punctuation) takes no
    /// space before it, while an opening quote keeps its space.
    private static func dropsSpace(prev: Character, next: Character, afterNext: Character?) -> Bool {
        if isCJKPunctuation(prev) || isCJKPunctuation(next) { return true }
        if isCJKLetter(prev), isCJKLetter(next) { return true }
        if next == "," || next == "." || next == ")" || next == "]" { return true }
        if next == "\"" || next == "'" {
            guard let a = afterNext else { return true }
            return a == " " || a == "," || a == "." || a == ";" || a == ":"
                || a == "!" || a == "?" || a == ")" || a == "]"
        }
        return false
    }

    private static func isCJKLetter(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3400 ... 0x4DBF).contains(v) || (0x4E00 ... 0x9FFF).contains(v)
            || (0xF900 ... 0xFAFF).contains(v) || (0x3040 ... 0x30FF).contains(v)
            || (0xAC00 ... 0xD7AF).contains(v)
    }

    private static func isCJKPunctuation(_ c: Character) -> Bool {
        // Only the CJK punctuation blocks: characters shared with
        // Latin typography (—, …, ·) are deliberately excluded, so
        // an English em dash keeps its spaces.
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3000 ... 0x303F).contains(v) || (0xFF01 ... 0xFF5E).contains(v)
    }

    /// A `<title>` element found in an entry: its full range, its
    /// attributes, and its inner markup.
    private struct TitleElement {
        let range: Range<String.Index>
        let attrs: String
        let inner: String
    }

    /// All <title>...</title> elements in the entry, in order.
    private static func titleElements(in s: String) -> [TitleElement] {
        var out: [TitleElement] = []
        var i = s.startIndex
        let end = s.endIndex
        while i < end, let found = s[i...].range(of: "<title", options: .caseInsensitive) {
            // The character after "<title" must end the tag name
            // (space, "/" or ">"), so "<titles>" can't false-match.
            let after = found.upperBound
            guard after < end, s[after] == " " || s[after] == "/" || s[after] == ">"
            else { i = after; continue }
            guard let tagEnd = s[found.lowerBound...].firstIndex(of: ">") else { break }
            let tag = s[found.lowerBound ... tagEnd]
            if tag.hasSuffix("/>") {
                i = s.index(after: tagEnd)
                continue
            }
            guard let close = s.range(of: "</title>", options: .caseInsensitive,
                                      range: s.index(after: tagEnd) ..< end) else { break }
            out.append(TitleElement(
                range: found.lowerBound ..< close.upperBound,
                attrs: String(tag),
                inner: String(s[s.index(after: tagEnd) ..< close.lowerBound])))
            i = close.upperBound
        }
        return out
    }

    /// True for a preverse section title — the "subtitle" a version
    /// prints before a verse (osis2mod marks it subType="x-preverse"
    /// with type section/subsection). Canonical titles (psalm
    /// superscriptions) are scripture text, never section titles.
    private static func isSectionTitle(_ attrs: String) -> Bool {
        let a = attrs.lowercased()
        guard a.contains("x-preverse"), !a.contains("canonical=\"true\"") else { return false }
        return a.contains("type=\"section\"") || a.contains("type=\"subsection\"")
    }

    /// The section heading ("subtitle") printed before a verse, if
    /// the entry carries one — e.g. NASB's "The Seventy Sent Out"
    /// at Luke 10:1 (REQ-RS-5).
    public static func sectionTitle(from osis: String) -> String? {
        for el in titleElements(in: osis) where isSectionTitle(el.attrs) {
            let text = plainText(from: el.inner)
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// The entry with its section titles removed, so a heading does
    /// not also appear inline in the verse text. Everything else —
    /// including canonical psalm titles — is untouched.
    public static func removingSectionTitles(_ osis: String) -> String {
        let sections = titleElements(in: osis).filter { isSectionTitle($0.attrs) }
        guard !sections.isEmpty else { return osis }
        var out = ""
        var cursor = osis.startIndex
        for el in sections {
            out += osis[cursor ..< el.range.lowerBound]
            cursor = el.range.upperBound
        }
        out += osis[cursor...]
        return out
    }

    /// Removes <note ...>...</note> blocks (footnotes, cross-references).
    static func removeNotes(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        let end = s.endIndex
        while i < end {
            if s[i] == "<",
                let tagEnd = s[i...].firstIndex(of: ">"),
                s[i...tagEnd].lowercased().hasPrefix("<note"),
                let closeRange = s.range(of: "</note>", options: .caseInsensitive,
                                         range: tagEnd ..< end)
            {
                i = closeRange.upperBound
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }

    private static func isLineBreakTag(_ tag: Substring) -> Bool {
        // tag starts with '<'; check for "<lb" case-insensitively.
        var it = tag.index(after: tag.startIndex)
        for expected in ["l", "b"] {
            guard it < tag.endIndex else { return false }
            if String(tag[it]).lowercased() != expected { return false }
            it = tag.index(after: it)
        }
        return true
    }

    /// Decodes one entity starting at `i` (which points at '&').
    /// Returns the decoded character and the index after ';', or nil.
    private static func decodeEntity(at i: String.Index, in s: String) -> (Character, String.Index)? {
        guard let semi = s[i...].firstIndex(of: ";"),
              s.distance(from: i, to: semi) <= 10
        else { return nil }
        let entity = s[s.index(after: i) ..< semi]
        let decoded: Character?
        switch entity.lowercased() {
        case "lt": decoded = "<"
        case "gt": decoded = ">"
        case "amp": decoded = "&"
        case "quot": decoded = "\""
        case "apos": decoded = "'"
        case "nbsp": decoded = " "
        default:
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                guard let v = UInt32(entity.dropFirst(2), radix: 16),
                      let scalar = UnicodeScalar(v) else { return nil }
                decoded = Character(scalar)
            } else if entity.hasPrefix("#") {
                guard let v = UInt32(entity.dropFirst()),
                      let scalar = UnicodeScalar(v) else { return nil }
                decoded = Character(scalar)
            } else {
                return nil
            }
        }
        return (decoded!, s.index(after: semi))
    }
}

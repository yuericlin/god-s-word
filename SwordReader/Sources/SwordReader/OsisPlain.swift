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
        if lastWasSpace { out.removeLast() }
        return out
    }

    /// Removes <note ...>...</note> blocks (footnotes, cross-references).
    private static func removeNotes(_ s: String) -> String {
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

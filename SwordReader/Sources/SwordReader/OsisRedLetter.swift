// OsisRedLetter.swift
// Locates the words of Jesus in a SWORD OSIS verse: the character
// ranges of <q who="Jesus">…</q> content within the verse's plain
// text (OsisPlain output). Red letters are a property of the
// module's own markup — a module whose text carries no such tags
// (e.g. ChiUns) yields no spans, and the reader invents none
// (REQ-RL-1).

import Foundation

public enum OsisRedLetter {
    /// Character-offset spans (start, end) of Jesus's speech in the
    /// plain text of `osis`, in document order, never overlapping.
    /// The caller prepares `osis` exactly as for display (section
    /// titles already removed), so the spans index into the same
    /// string `OsisPlain.plainText(from:)` returns for it.
    public static func jesusSpans(in osis: String) -> [(start: Int, end: Int)] {
        let s = OsisPlain.removeNotes(osis)
        let plain = OsisPlain.plainText(from: s)
        guard !plain.isEmpty else { return [] }

        // Split the markup into Jesus / non-Jesus chunks in document
        // order. A chunk is Jesus speech while at least one enclosing
        // <q> carries who="Jesus" — a quotation nested inside Jesus's
        // words (Scripture he cites, someone he quotes) stays part of
        // his speech, as red-letter editions print it.
        var chunks: [(osis: String, isJesus: Bool)] = []
        var stack: [Bool] = []
        var current = ""
        var currentIsJesus = false
        func flush() {
            if !current.isEmpty { chunks.append((current, currentIsJesus)) }
            current = ""
            currentIsJesus = stack.contains(true)
        }
        var i = s.startIndex
        let end = s.endIndex
        while i < end {
            if s[i] == "<", let gt = s[i...].firstIndex(of: ">") {
                let tag = s[i...gt]
                if tag.hasSuffix("/>"), isQTag(tag, closing: false) {
                    // Milestone form (<q sID="…" …/> … <q eID="…" …/>):
                    // an sID milestone opens, an eID milestone closes.
                    let low = tag.lowercased()
                    if low.contains("eid=") {
                        flush()
                        if !stack.isEmpty { stack.removeLast() }
                        currentIsJesus = stack.contains(true)
                    } else if low.contains("sid=") {
                        flush()
                        stack.append(isJesusQTag(tag))
                        currentIsJesus = stack.contains(true)
                    } else {
                        current += tag
                    }
                    i = s.index(after: gt)
                    continue
                }
                if isQTag(tag, closing: false) {
                    flush()
                    stack.append(isJesusQTag(tag))
                    currentIsJesus = stack.contains(true)
                    i = s.index(after: gt)
                    continue
                }
                if isQTag(tag, closing: true) {
                    flush()
                    if !stack.isEmpty { stack.removeLast() }
                    currentIsJesus = stack.contains(true)
                    i = s.index(after: gt)
                    continue
                }
                current += tag
                i = s.index(after: gt)
            } else {
                current.append(s[i])
                i = s.index(after: i)
            }
        }
        flush()

        // Locate each Jesus chunk's plain text in the verse's plain
        // text, sequentially (the same approach tokensWithStrongs
        // uses for <w> ranges): chunks are in document order, so each
        // search starts where the previous chunk ended.
        var spans: [(start: Int, end: Int)] = []
        var cursor = plain.startIndex
        for chunk in chunks where chunk.isJesus {
            let inner = OsisPlain.plainText(from: chunk.osis)
            guard !inner.isEmpty,
                  let r = plain.range(of: inner, range: cursor ..< plain.endIndex)
            else { continue }
            spans.append((plain.distance(from: plain.startIndex, to: r.lowerBound),
                          plain.distance(from: plain.startIndex, to: r.upperBound)))
            cursor = r.upperBound
        }
        // Coalesce spans separated only by whitespace (a nested
        // quotation inside Jesus's words splits his chunk at the
        // inner tags; the speech is still one run).
        var merged: [(start: Int, end: Int)] = []
        for span in spans {
            if let last = merged.last {
                let gap = plain[plain.index(plain.startIndex, offsetBy: last.end)
                    ..< plain.index(plain.startIndex, offsetBy: span.start)]
                if gap.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\n" }) {
                    merged[merged.count - 1].end = span.end
                    continue
                }
            }
            merged.append(span)
        }
        return merged
    }

    /// True when `tag` (angle brackets included) opens a `<q …>` —
    /// or, with `closing`, is a `</q>` — as opposed to some other
    /// element whose name merely starts with "q".
    private static func isQTag(_ tag: Substring, closing: Bool) -> Bool {
        var t = tag.dropFirst()  // "<"
        if closing {
            guard t.hasPrefix("/") else { return false }
            t = t.dropFirst()
        } else if t.hasPrefix("/") {
            return false
        }
        guard t.lowercased().hasPrefix("q") else { return false }
        let rest = t.dropFirst()
        guard let c = rest.first else { return false }
        return c == ">" || c == "/" || c == " " || c == "\t"
    }

    /// True when an opening `<q …>` tag carries who="Jesus".
    private static func isJesusQTag(_ tag: Substring) -> Bool {
        let low = tag.lowercased().replacingOccurrences(of: "'", with: "\"")
        return low.contains("who=\"jesus\"")
    }
}

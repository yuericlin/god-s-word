// RedLetterDerivation.swift
// On-device derivation of Jesus-speech spans for a version whose
// own data carries no speaker markup (REQ-RL-5). The transfer is
// the audited offline pipeline: a markup-carrying source version
// supplies each verse's speech as fractions of its text; the
// target version's own quotation delimiters — 「」 pairs or
// toggling " pairs, seeded by the book-wide delimiter parity —
// locate the corresponding segments; a segment is painted only
// when the source's fractions attribute at least half of it to
// the speech. The rule throughout is strict — an attribution
// that cannot be made with confidence is left unpainted: no
// proportional guessing where the target has no delimiters, and
// no rescue of a weakly attributed segment. Nothing is painted
// for a verse the source leaves untagged: derivation locates
// delimiters, it never guesses.

import Foundation

public enum RedLetterDerivation {

    /// One verse of a markup-carrying source version, digested for
    /// transfer by `SwordModule.bookJesusTruth`.
    public struct TruthVerse: Sendable {
        /// Jesus-speech spans in the source verse's plain text.
        public let spans: [(start: Int, end: Int)]
        /// Length of that plain text (the spans' coordinate basis).
        public let textLength: Int
        /// Jesus quotations carried into the verse from earlier
        /// verses of the book (> 0: the verse opens mid-speech).
        public let depthIn: Int
        public init(spans: [(start: Int, end: Int)], textLength: Int, depthIn: Int) {
            self.spans = spans; self.textLength = textLength; self.depthIn = depthIn
        }
    }

    /// How the target version delimits quotations.
    public enum Mode: Sendable {
        /// "…" pairs whose open/close role alternates (parity).
        case toggleQuotes
        /// 「…」 pairs with distinct open and close glyphs.
        case brackets
    }

    /// The delimiter mode a version uses, from a sample of its
    /// texts; nil when the sample holds no quotation delimiters.
    public static func detectMode(texts: [String]) -> Mode? {
        var brackets = false, quotes = false
        for t in texts {
            if t.contains("「") || t.contains("」") { brackets = true }
            if t.contains("\"") { quotes = true }
        }
        if brackets { return .brackets }
        if quotes { return .toggleQuotes }
        return nil
    }

    /// Whether each verse of a book opens inside a quotation, from
    /// the target's own delimiter parity walked in book order —
    /// the seed that lets a verse opening mid-speech be read as
    /// speech from its first character.
    public static func parityStartsInside(texts: [String], mode: Mode) -> [Bool] {
        var inside = false
        var out: [Bool] = []
        out.reserveCapacity(texts.count)
        for t in texts {
            out.append(inside)
            switch mode {
            case .brackets:
                let d = t.filter({ $0 == "「" }).count - t.filter({ $0 == "」" }).count
                if d > 0 { inside = true } else if d < 0 { inside = false }
            case .toggleQuotes:
                if t.filter({ $0 == "\"" }).count % 2 == 1 { inside.toggle() }
            }
        }
        return out
    }

    /// Derive one chapter's spans from ONE source's truth.
    /// - target: the chapter's verses as rendered, in order.
    /// - truth: the source's truth for the same chapter.
    /// - startsInside: the target parity flag for each verse.
    public static func deriveChapter(
        target: [(verse: Int, text: String)],
        truth: [Int: TruthVerse],
        startsInside: [Int: Bool],
        mode: Mode
    ) -> [Int: [(start: Int, end: Int)]] {
        var out: [Int: [(start: Int, end: Int)]] = [:]
        for entry in target {
            guard let g = truth[entry.verse], !entry.text.isEmpty else { continue }
            let chars = Array(entry.text)
            let length = max(chars.count, 1)
            let denom = Double(max(g.textLength, 1))
            let kfrac: [(start: Double, end: Double)] = g.spans.map {
                (Double($0.start) / denom, Double($0.end) / denom)
            }
            let kcov = kfrac.reduce(0.0) { $0 + $1.end - $1.start }
            let startsIn = (startsInside[entry.verse] ?? false) || g.depthIn > 0
            let segs = mode == .brackets
                ? segmentsBrackets(chars, startsInside: startsIn)
                : toggleSegments(chars, kfrac: kfrac, kcov: kcov)
            var painted: [(start: Int, end: Int)] = []
            if segs.isEmpty {
                // No delimiters to locate the speech by: paint
                // only when the source covers essentially the
                // whole verse, so the verse itself is the span.
                // Anything less is unsure, and unsure stays
                // unpainted.
                if kcov >= 0.9 {
                    painted = [(0, chars.count)]
                }
            } else {
                painted = selectPainted(segs, kfrac: kfrac, length: length)
            }
            // A painted range holding no letter or digit at all is
            // a delimiter artifact, not speech; drop it.
            let kept = painted.filter { span in
                span.end > span.start && span.start >= 0 && span.end <= chars.count
                    && chars[span.start ..< span.end].contains { $0.isLetter || $0.isNumber }
            }
            if !kept.isEmpty { out[entry.verse] = kept }
        }
        return out
    }

    /// Nesting-aware segment selection (REQ-RL-6). Segments are
    /// judged innermost first. A segment with no accepted segment
    /// nested in it is judged flat, on its whole range, exactly
    /// as before. A segment that contains an accepted quotation
    /// is judged on its exclusive part — its range minus every
    /// nested segment's range — but only when the source's
    /// speech begins well inside that quotation (its first
    /// fraction starts after the quotation starts, allowing a
    /// small drift): that is the signature of another speaker's
    /// speech carrying a saying of Jesus, where the frame must
    /// not paint for the saying's sake. When the source's speech
    /// begins at or before the quotation, the frame is the
    /// speaker's own (Jesus quoting Scripture inside his own
    /// speech) and the segment is judged flat. A segment paints
    /// when the source attributes at least half of the judged
    /// part to the speech. The painted set is every accepted
    /// segment's range minus the ranges of confidently rejected
    /// segments nested in it (the source attributes less than a
    /// quarter of such a segment — a quotation the speech makes
    /// but the source does not tag), coalesced where pieces
    /// touch. A nested segment the source attributes a quarter
    /// or more of is not carved out: its rejection came from
    /// proportional drift, not from the source's silence, and
    /// the accepted frame keeps it covered.
    static func selectPainted(
        _ segs: [(start: Int, end: Int)],
        kfrac: [(start: Double, end: Double)],
        length: Int
    ) -> [(start: Int, end: Int)] {
        func strictlyInside(_ j: Int, _ i: Int) -> Bool {
            segs[j].start >= segs[i].start && segs[j].end <= segs[i].end
                && (segs[j].start > segs[i].start || segs[j].end < segs[i].end)
        }
        func share(of pieces: [(start: Int, end: Int)]) -> Double {
            let total = pieces.reduce(0) { $0 + $1.end - $1.start }
            guard total > 0 else { return 0 }
            let covered = pieces.reduce(0.0) { acc, piece in
                acc + overlap(Double(piece.start) / Double(length),
                              Double(piece.end) / Double(length), kfrac)
                    * Double(length)
            }
            return covered / Double(total)
        }
        var accepted: [Int: Bool] = [:]
        // Innermost first: a segment's verdict may demote the
        // segments containing it, never the reverse.
        for i in segs.indices.sorted(by: { (segs[$0].end - segs[$0].start) < (segs[$1].end - segs[$1].start) }) {
            let inners = segs.indices.filter { $0 != i && strictlyInside($0, i) }
            let acceptedInners = inners.filter { accepted[$0] == true }
            var judged = [segs[i]]
            if !acceptedInners.isEmpty, let truthStart = kfrac.first?.start {
                let demote = acceptedInners.allSatisfy {
                    Double(segs[$0].start) / Double(length) + 0.05 < truthStart
                }
                if demote {
                    for j in inners { judged = judged.flatMap { subtract($0, segs[j]) } }
                }
            }
            accepted[i] = share(of: judged) >= 0.5
        }
        var painted: [(start: Int, end: Int)] = []
        for i in segs.indices where accepted[i] == true {
            var pieces = [segs[i]]
            for j in segs.indices where j != i && accepted[j] != true && strictlyInside(j, i)
                && share(of: [segs[j]]) < 0.25 {
                pieces = pieces.flatMap { subtract($0, segs[j]) }
            }
            painted += pieces
        }
        var merged: [(start: Int, end: Int)] = []
        for piece in painted.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, piece.start <= last.end {
                merged[merged.count - 1] = (last.start, max(last.end, piece.end))
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// [piece] minus the sub-range [inner] (0–2 pieces).
    static func subtract(
        _ piece: (start: Int, end: Int),
        _ inner: (start: Int, end: Int)
    ) -> [(start: Int, end: Int)] {
        guard inner.start < piece.end, inner.end > piece.start else {
            return [piece]
        }
        var out: [(start: Int, end: Int)] = []
        if inner.start > piece.start {
            out.append((piece.start, inner.start))
        }
        if inner.end < piece.end {
            out.append((inner.end, piece.end))
        }
        return out
    }

    /// Per-verse merge of two derivations: the primary source's
    /// entry wins wherever it paints; the fallback fills the rest.
    public static func merge(
        primary: [Int: [(start: Int, end: Int)]],
        fallback: [Int: [(start: Int, end: Int)]]
    ) -> [Int: [(start: Int, end: Int)]] {
        var out = fallback
        for (verse, spans) in primary where !spans.isEmpty { out[verse] = spans }
        return out
    }

    // MARK: - Segmentation

    /// 「…」 segments of a verse; a verse opening mid-speech (per
    /// parity or the source's depth) starts its first segment at 0,
    /// and an unclosed segment runs to the verse end. The nested
    /// 『…』 level — a quotation inside a quotation (REQ-RL-6) —
    /// is tracked alongside: its segments nest inside the outer
    /// ones and are judged separately by `selectPainted`. A 『
    /// quotation that opened in an earlier verse and closes in
    /// this one contributes its tail segment from 0; one still
    /// open at the verse end runs to the end.
    static func segmentsBrackets(_ chars: [Character], startsInside: Bool)
        -> [(start: Int, end: Int)]
    {
        var segs: [(start: Int, end: Int)] = []
        var start: Int? = startsInside ? 0 : nil
        var innerStart: Int? = nil
        var innerTailUsed = false
        for (i, ch) in chars.enumerated() {
            if ch == "「" {
                if start == nil { start = i }
            } else if ch == "」" {
                if let s = start {
                    segs.append((s, i + 1)); start = nil
                } else if startsInside, segs.isEmpty {
                    segs.append((0, i + 1))
                }
            } else if ch == "『" {
                if innerStart == nil { innerStart = i }
            } else if ch == "』" {
                if let s = innerStart {
                    segs.append((s, i + 1)); innerStart = nil
                } else if !innerTailUsed, start != nil {
                    segs.append((0, i + 1)); innerTailUsed = true
                }
            }
        }
        if let s = start { segs.append((s, chars.count)) }
        if let s = innerStart { segs.append((s, chars.count)) }
        return segs
    }

    /// Offset just past a leading ¶…¶ section heading, or 0.
    static func headingEnd(_ chars: [Character]) -> Int {
        guard chars.first == "¶" else { return 0 }
        if let j = chars.dropFirst().firstIndex(of: "¶") { return j + 1 }
        return 0
    }

    /// "…" segments of a verse, located with the source fractions:
    /// a verse the source covers almost wholly is one span, its
    /// bounds snapped to nearby quotation marks; otherwise the
    /// marks pair off in order, a leading mark closing a speech
    /// the verse opens inside of, and a trailing unclosed mark
    /// running to the verse end. Single-quoted segments ('…' or
    /// ‘…’) — a quotation inside a quotation (REQ-RL-6) — are
    /// collected alongside and judged separately by
    /// `selectPainted`.
    static func toggleSegments(
        _ chars: [Character],
        kfrac: [(start: Double, end: Double)],
        kcov: Double
    ) -> [(start: Int, end: Int)] {
        let pos = chars.indices.filter { chars[$0] == "\"" }
        let length = max(chars.count, 1)
        let he = headingEnd(chars)
        if kcov >= 0.9, let first = kfrac.first, let last = kfrac.last {
            var a = Int((first.start * Double(length)).rounded())
            var b = Int((last.end * Double(length)).rounded())
            if he > 0, pos.isEmpty || pos[0] >= he { a = max(a, he) }
            for q in pos where q >= a - 15 && q < a { a = q }
            for q in pos where q >= a && q - a <= max(15, length / 10) {
                let blank = q <= he || chars[he ..< q].allSatisfy { $0.isWhitespace }
                if blank { a = q }
            }
            for q in pos where q + 1 > b && q + 1 <= b + 15 { b = q + 1 }
            return [(a, b)]
        }
        var segs: [(start: Int, end: Int)] = []
        var rest = pos
        if let first = kfrac.first, first.start <= 0.01, rest.count % 2 == 1 {
            segs.append((he, rest[0] + 1))
            rest.removeFirst()
        }
        var k = 0
        while k + 1 < rest.count {
            segs.append((rest[k], rest[k + 1] + 1))
            k += 2
        }
        if rest.count % 2 == 1, let lastQ = rest.last {
            segs.append((lastQ, chars.count))
        }
        // Nested single-quoted segments (REQ-RL-6). An apostrophe
        // inside a word (don't, Lord's) never opens or closes: an
        // opening mark follows the verse start, whitespace, or
        // opening punctuation and precedes a letter; a closing
        // mark follows a letter or sentence punctuation and
        // precedes whitespace, punctuation, or the verse end.
        // Singles pair strictly within the verse; an unclosed one
        // runs to the verse end, like an unclosed double quote.
        var openSingle: Int? = nil
        for i in chars.indices {
            let ch = chars[i]
            guard ch == "'" || ch == "‘" || ch == "’" else { continue }
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if openSingle == nil {
                let opens = ch == "‘"
                    || (ch == "'"
                        && (prev.map { $0.isWhitespace || "\"([:;,".contains($0) } ?? true)
                        && (next?.isLetter ?? false))
                if opens { openSingle = i }
            } else {
                let closes = (prev?.isLetter ?? false)
                    || (prev.map { ".!?;:".contains($0) } ?? false)
                let followed = next.map {
                    $0.isWhitespace || ".,!?;:)]\"".contains($0)
                } ?? true
                if closes && followed {
                    segs.append((openSingle!, i + 1))
                    openSingle = nil
                }
            }
        }
        if let s = openSingle { segs.append((s, chars.count)) }
        return segs
    }

    /// Total overlap of [a0, a1] with the fraction spans.
    static func overlap(_ a0: Double, _ a1: Double,
                        _ spans: [(start: Double, end: Double)]) -> Double {
        spans.reduce(0.0) { $0 + max(0.0, min(a1, $1.end) - max(a0, $1.start)) }
    }
}

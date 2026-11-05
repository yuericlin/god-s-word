// RedLetterDerivationTests.swift
// REQ-RL-5: on-device derivation transfers a markup-carrying
// source's speech fractions through the target version's own
// quotation delimiters. Fixtures are synthetic and hand-computed;
// the same transfer, run offline over the real modules, is what
// produced the bundled artifact's audited coverage.

import XCTest
@testable import SwordReader

final class RedLetterDerivationTests: XCTestCase {

    private func truth(_ spans: [(Int, Int)], length: Int, depthIn: Int = 0)
        -> RedLetterDerivation.TruthVerse
    {
        RedLetterDerivation.TruthVerse(
            spans: spans.map { (start: $0.0, end: $0.1) },
            textLength: length, depthIn: depthIn)
    }

    // MARK: Mode detection and parity

    func testDetectMode() {
        XCTAssertEqual(RedLetterDerivation.detectMode(texts: ["他說：「來。」"]),
                       .brackets)
        XCTAssertEqual(RedLetterDerivation.detectMode(texts: ["He said, \"Come.\""]),
                       .toggleQuotes)
        XCTAssertNil(RedLetterDerivation.detectMode(texts: ["No quotations here."]))
    }

    func testParityStartsInside() {
        XCTAssertEqual(
            RedLetterDerivation.parityStartsInside(
                texts: ["「a", "b」c「d", "e」"], mode: .brackets),
            [false, true, true])
        XCTAssertEqual(
            RedLetterDerivation.parityStartsInside(
                texts: ["\"a", "b\" \"c", "d\""], mode: .toggleQuotes),
            [false, true, true])
    }

    // MARK: Bracket-mode derivation

    func testBracketSpeechPaintedNarrationQuoteSkipped() {
        // One narration quote (share 0) and one speech quote.
        let text = "「亞伯拉罕」說：「你要出去。」"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(5, 10)], length: 10)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[8, 15]])
    }

    func testBracketWholeSpeechSegment() {
        let text = "他說：「我是道路。」眾人聽了。"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(4, 16)], length: 20)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[3, 10]])
    }

    func testBracketContinuationFromSourceDepth() {
        // The verse opens mid-speech: no opening bracket, and the
        // parity map is silent — the source's carried depth opens
        // the segment at 0.
        let text = "繼續的話」後來"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(0, 9)], length: 10, depthIn: 1)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[0, 5]])
    }

    // MARK: Toggle-mode derivation

    func testTogglePairedSpeech() {
        let text = "He answered, \"Come to me.\""
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(13, 26)], length: 26)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[13, 26]])
    }

    func testToggleWholeVerseSpeechSnappedToQuotes() {
        let text = "\"I am the way.\""
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(0, 15)], length: 15)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[0, 15]])
    }

    func testToggleLeadingCloseIsSpeechTail() {
        // The verse opens inside the speech (source fraction starts
        // at 0) and holds only the closing mark.
        let text = "the labor.\" Then he left."
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(0, 11)], length: 25)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[0, 11]])
    }

    func testToggleNoDelimitersPartialCoveragePaintsNothing() {
        // No quotation marks to locate the speech by, and the
        // source covers only half its verse: unsure — unpainted.
        let text = "Come to me, all you."
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(2, 12)], length: 20)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertTrue(out.isEmpty)
    }

    func testToggleNoDelimitersWholeVerseCoveredPaintsAll() {
        let text = "Come to me, all you."
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(0, 20)], length: 20)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[0, 20]])
    }

    func testSoleSegmentWeakSharePaintsNothing() {
        // The verse's only segment is attributed just a third of
        // its length by the source's fractions: unsure — unpainted
        // (no sole-segment rescue).
        let text = "「一二三四五六七八」還有別的話語在這裡"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(0, 4)], length: 20)],
            startsInside: [:], mode: .brackets)
        XCTAssertTrue(out.isEmpty)
    }

    func testUntaggedVersePaintsNothing() {
        let text = "He answered, \"Come to me.\""
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text), (verse: 2, text: text)],
            truth: [1: truth([], length: 26)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertTrue(out.isEmpty)
    }

    func testDelimiterOnlySpanDropped() {
        // The attributed segment holds only a quote and a space —
        // a delimiter artifact, never speech.
        let text = "Say \" \" now"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(4, 7)], length: 11)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: Merge

    func testMergePrimaryWinsFallbackFills() {
        let merged = RedLetterDerivation.merge(
            primary: [1: [(start: 0, end: 5)]],
            fallback: [1: [(start: 2, end: 3)], 2: [(start: 0, end: 9)]])
        XCTAssertEqual(merged[1]?.map { [$0.start, $0.end] }, [[0, 5]])
        XCTAssertEqual(merged[2]?.map { [$0.start, $0.end] }, [[0, 9]])
    }
}

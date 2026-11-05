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

    // MARK: OsisRedLetter depth carry

    func testJesusSpansDepthCarryAcrossVerses() {
        let v1 = "He said <q who=\"Jesus\">come and see"
        let r1 = OsisRedLetter.jesusSpans(in: v1, jesusDepthIn: 0)
        XCTAssertEqual(r1.spans.map { [$0.start, $0.end] }, [[8, 20]])
        XCTAssertEqual(r1.jesusDepthOut, 1)

        let v2 = "and rest</q> today"
        let r2 = OsisRedLetter.jesusSpans(in: v2, jesusDepthIn: r1.jesusDepthOut)
        XCTAssertEqual(r2.spans.map { [$0.start, $0.end] }, [[0, 8]])
        XCTAssertEqual(r2.jesusDepthOut, 0)

        // The standalone entry point is unchanged: a verse holding
        // only a closing tag yields nothing on its own.
        XCTAssertTrue(OsisRedLetter.jesusSpans(in: v2).isEmpty)
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

    func testToggleNoDelimitersFallsBackToFractions() {
        let text = "Come to me, all you."
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(2, 12)], length: 20)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[2, 12]])
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

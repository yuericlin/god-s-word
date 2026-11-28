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

    // MARK: Nested quotations (REQ-RL-6)

    func testBracketNestedRequotationPaintsOnlyTheSaying() {
        // Acts 11:16 in ChiUns: Peter, inside his own speech
        // (the parity seed), quotes a saying of Jesus in 『…』.
        // The KJV truth tags only the saying ([58, 136) of its
        // verse), so the frame must not paint for its sake.
        let text = "我就想起主的话说：『约翰是用水施洗，但你们要受圣灵的洗。』"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(58, 136)], length: 136)],
            startsInside: [1: true], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[9, 29]])
    }

    func testBracketFrameSpeechKeptWhenSourceStartsBeforeQuote() {
        // Luke 4:4 in ChiUns: Jesus quotes Scripture in 『…』
        // inside his own 「…」 reply. The NASB truth's speech
        // begins before the quotation ("It is written"), so the
        // whole reply is his and paints whole.
        let text = "耶稣回答说：「经上记着说：『人活着不是单靠食物，乃是靠 神口里所出的一切话。』」"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(24, 77)], length: 77)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[6, 40]])
    }

    func testBracketUntaggedInnerQuotationCarvedOut() {
        // The source tags the outer speech around a quotation it
        // leaves untagged: the frame paints, the quotation does
        // not.
        let text = "「主說：『你要小心那假先知。』你們要謹慎儆醒。」"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(0, 4), (15, 24)], length: 24)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[0, 4], [15, 24]])
    }

    func testToggleSingleQuotedSayingPaints() {
        // A saying delimited only by single quotes — a quotation
        // inside the narration — is located and painted when the
        // source attributes it.
        let text = "Then I remembered the word of the Lord, how He said, 'John baptized with water, but you shall be baptized with the Holy Spirit.'"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(58, 136)], length: 137)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[53, 128]])
    }

    func testToggleApostrophesDoNotDelimit() {
        // Apostrophes inside words (Don't, Lord's) open and
        // close nothing; the double-quoted speech paints alone.
        let text = "He said, \"Don't be afraid; the Lord's promise stands.\""
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(10, 54)], length: 54)],
            startsInside: [:], mode: .toggleQuotes)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[9, 54]])
    }

    // MARK: Amended nested rules (REQ-RL-6, Nov 27, 2026)

    func testBracketTwoSayingsFrameRejected() {
        // ChiUns John 16:17: the disciples quote TWO sayings of
        // Jesus inside one 「…」 frame. The source's speech
        // begins well inside the earliest saying, so the frame
        // is theirs and does not paint, however many sayings it
        // carries. (The earlier demote test, keyed on every
        // accepted quotation, let this frame through.)
        let text = "有几个门徒就彼此说：「他对我们说：『等不多时，你们就不得见我；再等不多时，你们还要见我』；又说：『因我往父那里去。』这是甚么意思呢？」"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(86, 174), (181, 209)], length: 211)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[17, 44], [48, 58]])
    }

    func testBracketSoleQuotationReassignedFromFrame() {
        // ChiUns John 5:12: the Jews quote Jesus's command
        // 『拿褥子走』 inside their question. The source tags
        // only the command — fractionally at its own verse's
        // end, so the frame barely passes its flat test and the
        // quotation fails its own; but the frame's opening
        // words are wholly untagged, and the saying is the
        // quotation, not the frame.
        let text = "他们问他说：「对你说『拿褥子走』的是甚么人？」"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(49, 79)], length: 81)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[10, 16]])
    }

    func testBracketSoleQuotationCarriedWhenFractionsMiss() {
        // ChiUns John 16:18: the disciples quote 『等不多时』;
        // the source tags exactly that fragment, but at 45–60%
        // of its verse against the fragment's 25–42% here, so
        // the fractions never touch it. The frame carries no
        // other quotation and its opening words are untagged:
        // the fragment is the saying.
        let text = "门徒彼此说：「他说『等不多时』到底是甚么意思呢？我们不明白他所说的话。」"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(49, 65)], length: 108)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[9, 15]])
    }

    func testBracketSoleQuotationAddedJohnEight() {
        // ChiUns John 8:22: the same shape as 16:18 — the Jews
        // quote Jesus's saying, the source tags it, and the
        // fractions place it past the quotation's end.
        let text = "犹太人说：「他说『我所去的地方，你们不能到』，难道他要自尽吗？」"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(83, 118)], length: 120)],
            startsInside: [:], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[8, 22]])
    }

    func testBracketCarryOverFrameVetoed() {
        // ChiUns Acts 22:10: Paul's narration carries over from
        // the verses before (the parity seed), holding his own
        // question and the Lord's answer. The source attributes
        // none of the carry-over's own words — only the answer
        // paints.
        let text = "我说：『主啊，我当做甚么？』主说：『起来，进大马士革去，在那里，要将所派你做的一切事告诉你。』"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(62, 168)], length: 168)],
            startsInside: [1: true], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[17, 47]])
    }

    func testBracketCarryOverSpeechKept() {
        // ChiUns Mark 7:11: Jesus's own speech carries over,
        // quoting the Pharisees' Corban formula. The source
        // attributes over two-fifths of the carry-over's own
        // exclusive words, so it is his speech and paints whole.
        let text = "你们倒说：『人若对父母说：我所当奉给你的，已经作了各耳板』（各耳板就是供献的意思），"
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: text)],
            truth: [1: truth([(0, 102)], length: 135)],
            startsInside: [1: true], mode: .brackets)
        XCTAssertEqual(out[1]?.map { [$0.start, $0.end] }, [[0, 42]])
    }

    func testOneCharacterVersePaintsNothing() {
        // A one-character verse (ChiUns's Luke 21:30 is the
        // filler "a" in the module data) is a versification
        // artifact, not speech, however fully the source
        // covers its own verse.
        let out = RedLetterDerivation.deriveChapter(
            target: [(verse: 1, text: "a")],
            truth: [1: truth([(0, 10)], length: 10)],
            startsInside: [1: true], mode: .brackets)
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

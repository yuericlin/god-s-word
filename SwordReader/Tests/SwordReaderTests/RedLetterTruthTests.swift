// RedLetterTruthTests.swift
// REQ-RL-5: the bundled source truth extracted from the
// published NASB1995 and KJV modules (Nov 5, 2026). Pins check
// the extraction against the modules' own text: KJV John 3:16
// is one whole-verse span; the Father's voice at Matthew 3:17
// is tagged in neither source.

import XCTest
@testable import SwordReader

final class RedLetterTruthTests: XCTestCase {

    func testSourcePriorityOrder() {
        XCTAssertEqual(RedLetterTruth.sourceIDs, ["nasb1995", "kjv"])
    }

    func testKJVWholeVerseSpeech() {
        let ch = RedLetterTruth.truth(sourceID: "KJV", book: "John", chapter: 3)
        let v16 = ch[16]
        XCTAssertEqual(v16?.spans.map { [$0.start, $0.end] }, [[0, 141]])
        XCTAssertEqual(v16?.textLength, 141)
        XCTAssertEqual(v16?.depthIn, 0)
    }

    func testFatherVoiceTaggedInNeitherSource() {
        for source in RedLetterTruth.sourceIDs {
            let ch = RedLetterTruth.truth(sourceID: source,
                                          book: "Matthew", chapter: 3)
            XCTAssertNil(ch[17], "\(source) must not tag Matthew 3:17")
            XCTAssertEqual(ch[15].map { $0.spans.isEmpty }, false)
        }
        let nasb15 = RedLetterTruth.truth(sourceID: "NASB1995",
                                          book: "Matthew", chapter: 3)[15]
        XCTAssertEqual(nasb15?.spans.map { [$0.start, $0.end] }, [[33, 125]])
        XCTAssertEqual(nasb15?.textLength, 148)
    }

    func testUnknownSourceAndBookAreEmpty() {
        XCTAssertTrue(RedLetterTruth.truth(sourceID: "WEB",
                                           book: "John", chapter: 3).isEmpty)
        XCTAssertTrue(RedLetterTruth.truth(sourceID: "KJV",
                                           book: "Genesis", chapter: 1).isEmpty)
    }
}

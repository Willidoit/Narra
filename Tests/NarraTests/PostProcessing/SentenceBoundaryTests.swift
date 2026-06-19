import XCTest
@testable import Narra

final class SentenceBoundaryTests: XCTestCase {
    func testEmptyBufferReturnsNothing() {
        let (completed, remainder) = extractCompletedSentences(buffer: "")
        XCTAssertTrue(completed.isEmpty)
        XCTAssertEqual(remainder, "")
    }

    func testSingleSentenceWithoutTerminatorStaysInRemainder() {
        let (completed, remainder) = extractCompletedSentences(buffer: "hello there")
        XCTAssertTrue(completed.isEmpty)
        XCTAssertEqual(remainder, "hello there")
    }

    func testTerminatorSplitsOnWhitespace() {
        let (completed, remainder) = extractCompletedSentences(buffer: "Hello there. How are you")
        XCTAssertEqual(completed, ["Hello there."])
        XCTAssertEqual(remainder, "How are you")
    }

    func testMultipleSentencesInOneBuffer() {
        let (completed, remainder) = extractCompletedSentences(buffer: "One. Two! Three? Four")
        XCTAssertEqual(completed, ["One.", "Two!", "Three?"])
        XCTAssertEqual(remainder, "Four")
    }

    func testTerminatorAtEndStaysInBuffer() {
        // No whitespace after the terminator means we can't be sure the
        // sentence is complete yet (could be "Dr. Foo"); keep it in remainder.
        let (completed, remainder) = extractCompletedSentences(buffer: "Hello there.")
        XCTAssertTrue(completed.isEmpty)
        XCTAssertEqual(remainder, "Hello there.")
    }

    func testForceFlushReturnsEverythingAsOneSentence() {
        let (completed, remainder) = extractCompletedSentences(buffer: "Hello world", force: true)
        XCTAssertEqual(completed, ["Hello world"])
        XCTAssertEqual(remainder, "")
    }
}

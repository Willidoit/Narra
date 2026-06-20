import XCTest
@testable import Narra

private let t0 = Date(timeIntervalSince1970: 0)
private let t2 = Date(timeIntervalSince1970: 2)
private let t4 = Date(timeIntervalSince1970: 4)

final class LocalCorrectionFilterTests: XCTestCase {
    func testFillerWordsAreRemovedWhenUsedAsStandaloneFillers() {
        let filter = LocalCorrectionFilter()

        let result = filter.apply(
            PostProcessingRequest(
                rawText: "um, I need a timer",
                segment: TranscriptSegment(text: "um, I need a timer", startTime: t0, endTime: t2)
            )
        )

        XCTAssertEqual(result.refinedText, "I need a timer")
        XCTAssertEqual(result.segments.map(\.text), ["I need a timer"])
    }

    func testLikeIsPreservedWhenUsedSemantically() {
        let filter = LocalCorrectionFilter()

        let result = filter.apply(
            PostProcessingRequest(
                rawText: "I like this",
                segment: TranscriptSegment(text: "I like this", startTime: t0, endTime: t2, confidence: 0.98)
            )
        )

        XCTAssertEqual(result.refinedText, "I like this")
        XCTAssertEqual(result.segments.map(\.text), ["I like this"])
    }

    func testIMeanAndRatherTriggerCorrectionPrefixRemoval() {
        let filter = LocalCorrectionFilter()
        let previous = TranscriptSegment(text: "Book lunch for Tuesday", startTime: t0, endTime: t2)

        let iMeanResult = filter.apply(
            PostProcessingRequest(
                rawText: "I mean, book lunch for Wednesday",
                segment: TranscriptSegment(text: "I mean, book lunch for Wednesday", startTime: t2, endTime: t4),
                context: [previous]
            )
        )
        XCTAssertEqual(iMeanResult.refinedText, "book lunch for Wednesday")
        XCTAssertEqual(iMeanResult.segments.map(\.text), ["book lunch for Wednesday"])

        let ratherResult = filter.apply(
            PostProcessingRequest(
                rawText: "Rather, book lunch for Thursday",
                segment: TranscriptSegment(text: "Rather, book lunch for Thursday", startTime: t2, endTime: t4),
                context: [previous]
            )
        )
        XCTAssertEqual(ratherResult.refinedText, "book lunch for Thursday")
        XCTAssertEqual(ratherResult.segments.map(\.text), ["book lunch for Thursday"])
    }

    func testMidSentenceCorrectionMarkerDropsEarlierPhrasing() {
        let filter = LocalCorrectionFilter()

        let ohWait = filter.apply(
            PostProcessingRequest(
                rawText: "I'll head to the store, oh wait, the mall",
                segment: TranscriptSegment(
                    text: "I'll head to the store, oh wait, the mall",
                    startTime: t0,
                    endTime: t2
                )
            )
        )
        XCTAssertEqual(ohWait.refinedText, "the mall")

        let scratchThat = filter.apply(
            PostProcessingRequest(
                rawText: "Email Sarah at three, scratch that, four",
                segment: TranscriptSegment(
                    text: "Email Sarah at three, scratch that, four",
                    startTime: t0,
                    endTime: t2
                )
            )
        )
        XCTAssertEqual(scratchThat.refinedText, "four")
    }

    func testRestatementDedupesNearDuplicateContextToCleanerVersion() {
        let filter = LocalCorrectionFilter()
        let previous = TranscriptSegment(text: "um set a timer for ten minutes", startTime: t0, endTime: t2)
        let current = TranscriptSegment(text: "set a timer for ten minutes", startTime: t2, endTime: t4)

        let result = filter.apply(
            PostProcessingRequest(
                rawText: current.text,
                segment: current,
                context: [previous]
            )
        )

        XCTAssertEqual(result.refinedText, "set a timer for ten minutes")
        XCTAssertEqual(result.segments.map(\.text), ["set a timer for ten minutes"])
    }
}

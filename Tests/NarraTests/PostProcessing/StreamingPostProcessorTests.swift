import XCTest
@testable import Narra

final class StreamingPostProcessorTests: XCTestCase {

    /// A PostProcessingService that sleeps `delaySeconds` before returning
    /// `cannedText`. Used to verify the 800 ms timeout in `flush`.
    private struct StallingProcessor: PostProcessingService {
        let cannedText: String
        let delaySeconds: Double

        func process(segment: TranscriptSegment) async throws -> ProcessedTranscript {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            return ProcessedTranscript(
                text: cannedText,
                startTime: segment.startTime,
                endTime: segment.endTime,
                sourceSegmentIDs: [segment.id],
                confidence: 1.0,
                usedCloud: true
            )
        }

        func process(segments: [TranscriptSegment]) async throws -> ProcessedTranscript {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            let start = segments.first?.startTime ?? Date()
            let end = segments.last?.endTime ?? start
            return ProcessedTranscript(
                text: cannedText,
                startTime: start,
                endTime: end,
                sourceSegmentIDs: segments.map(\.id),
                confidence: 1.0,
                usedCloud: true
            )
        }
    }

    func testFlushRespectsTimeoutWhenLLMStalls() async {
        let stalling = StallingProcessor(cannedText: "from cloud", delaySeconds: 5)
        let processor = StreamingPostProcessor(
            configuration: .init(
                cloudProcessor: stalling,
                localProcessor: stalling,
                useCloud: true
            )
        )
        let now = Date()
        await processor.feed(segment: TranscriptSegment(
            text: "hello world.",
            startTime: now,
            endTime: now
        ))

        let start = Date()
        let result = await processor.flush(level: .medium)
        let elapsed = Date().timeIntervalSince(start)

        // Should give up around 800ms and return the filter-cleaned text.
        XCTAssertLessThan(elapsed, 2.0, "flush waited too long on stalled LLM")
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertFalse(result.usedCloud, "fallback path should not be cloud")
    }

    func testFlushUsesLLMResultWhenItBeatsTimeout() async {
        let fast = StallingProcessor(cannedText: "polished output", delaySeconds: 0.05)
        let processor = StreamingPostProcessor(
            configuration: .init(
                cloudProcessor: fast,
                localProcessor: fast,
                useCloud: true
            )
        )
        let now = Date()
        await processor.feed(segment: TranscriptSegment(
            text: "hello world.",
            startTime: now,
            endTime: now
        ))

        let result = await processor.flush(level: .medium)
        XCTAssertEqual(result.text, "polished output")
        XCTAssertTrue(result.usedCloud)
    }

    func testLevelNoneSkipsLLM() async {
        let neverReturns = StallingProcessor(cannedText: "should not appear", delaySeconds: 999)
        let processor = StreamingPostProcessor(
            configuration: .init(
                cloudProcessor: neverReturns,
                localProcessor: neverReturns,
                useCloud: true
            )
        )
        let now = Date()
        await processor.feed(segment: TranscriptSegment(
            text: "hello world.",
            startTime: now,
            endTime: now
        ))

        let start = Date()
        let result = await processor.flush(level: .none)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.5, "level=.none should not invoke the LLM at all")
        XCTAssertFalse(result.usedCloud)
        XCTAssertFalse(result.text.isEmpty)
    }
}

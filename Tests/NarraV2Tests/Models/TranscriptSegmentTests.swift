import XCTest
@testable import NarraV2

final class TranscriptSegmentTests: XCTestCase {

    func test_defaultInit_createsValidSegment() {
        let now = Date()
        let segment = TranscriptSegment(
            text: "Hello, world.",
            startTime: now,
            endTime: now.addingTimeInterval(1.5)
        )

        XCTAssertEqual(segment.text, "Hello, world.")
        XCTAssertEqual(segment.startTime, now)
        XCTAssertEqual(segment.endTime, now.addingTimeInterval(1.5))
        XCTAssertEqual(segment.confidence, 1.0, "Default confidence should be 1.0")
        XCTAssertNotNil(segment.id, "Default id should be auto-generated")
    }

    func test_initWithConfidence_storesValue() {
        let now = Date()
        let segment = TranscriptSegment(
            text: "maybe",
            startTime: now,
            endTime: now,
            confidence: 0.42
        )
        XCTAssertEqual(segment.confidence, 0.42, accuracy: 0.0001)
    }

    func test_idIsUniquePerInstance() {
        let now = Date()
        let a = TranscriptSegment(text: "a", startTime: now, endTime: now)
        let b = TranscriptSegment(text: "a", startTime: now, endTime: now)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_duration_computedFromTimestamps() {
        let now = Date()
        let segment = TranscriptSegment(
            text: "x",
            startTime: now,
            endTime: now.addingTimeInterval(2.5)
        )
        XCTAssertEqual(segment.duration, 2.5, accuracy: 0.0001)
    }

    func test_duration_zeroForSameStartAndEnd() {
        let now = Date()
        let segment = TranscriptSegment(text: "x", startTime: now, endTime: now)
        XCTAssertEqual(segment.duration, 0)
    }

    func test_equality_basedOnAllFields() {
        let id = UUID()
        let now = Date()
        let a = TranscriptSegment(id: id, text: "hi", startTime: now, endTime: now, confidence: 0.8)
        let b = TranscriptSegment(id: id, text: "hi", startTime: now, endTime: now, confidence: 0.8)
        XCTAssertEqual(a, b)

        let c = TranscriptSegment(id: id, text: "hi", startTime: now, endTime: now, confidence: 0.9)
        XCTAssertNotEqual(a, c, "Different confidence should produce inequality")
    }
}

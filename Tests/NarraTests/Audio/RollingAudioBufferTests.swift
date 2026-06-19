import XCTest
@testable import Narra

final class RollingAudioBufferTests: XCTestCase {

    // MARK: - Empty buffer

    func test_emptyBuffer_returnsZeroDuration() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        XCTAssertEqual(buffer.duration, 0)
        XCTAssertEqual(buffer.sampleCount, 0)
    }

    func test_emptyBuffer_windowReturnsEmpty() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        XCTAssertEqual(buffer.last(seconds: 5.0), [])
        XCTAssertEqual(buffer.last(seconds: 0.5), [])
    }

    // MARK: - Append

    func test_append_samplesAreRetrievableInOrder() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        let samples: [Int16] = [1, 2, 3, 4, 5]
        buffer.append(samples)

        XCTAssertEqual(buffer.sampleCount, 5)
        XCTAssertEqual(buffer.last(seconds: 1.0), samples)
    }

    func test_append_multipleBatchesAccumulate() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        buffer.append([1, 2, 3])
        buffer.append([4, 5, 6])

        XCTAssertEqual(buffer.sampleCount, 6)
        XCTAssertEqual(buffer.last(seconds: 1.0), [1, 2, 3, 4, 5, 6])
    }

    // MARK: - Duration

    func test_duration_usesSampleRate() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        buffer.append(Array(repeating: Int16(0), count: 16_000)) // 1 second

        XCTAssertEqual(buffer.duration, 1.0, accuracy: 0.0001)
    }

    // MARK: - Window query

    func test_lastSeconds_returnsOnlyRequestedWindow() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        // Append 2 seconds of distinct samples (value == sample index)
        let twoSeconds = (0..<32_000).map { Int16(truncatingIfNeeded: $0) }
        buffer.append(twoSeconds)

        // 1-second window of the most recent audio
        let last1s = buffer.last(seconds: 1.0)
        XCTAssertEqual(last1s.count, 16_000)
        // The first sample of the returned window should match sample 16000 of the input
        XCTAssertEqual(last1s.first, Int16(truncatingIfNeeded: 16_000))
    }

    func test_lastSeconds_clampsToAvailableData() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        buffer.append([10, 20, 30]) // 3 samples only

        // Requesting more than available returns whatever exists
        let window = buffer.last(seconds: 5.0)
        XCTAssertEqual(window, [10, 20, 30])
    }

    func test_lastSeconds_zeroReturnsEmpty() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        buffer.append([1, 2, 3, 4])

        XCTAssertEqual(buffer.last(seconds: 0.0), [])
    }

    // MARK: - Capacity / overflow

    func test_capacity_overflowDropsOldestSamples() {
        // 1 second of capacity at 16kHz = 16,000 samples
        let buffer = RollingAudioBuffer(capacitySeconds: 1.0, sampleRate: 16_000)
        let first = (0..<16_000).map { Int16(truncatingIfNeeded: $0) }
        buffer.append(first)

        // Append an additional 8,000 samples - the first 8,000 must be dropped
        let second = (16_000..<24_000).map { Int16(truncatingIfNeeded: $0) }
        buffer.append(second)

        XCTAssertEqual(buffer.sampleCount, 16_000, "Buffer should not exceed capacity")
        let window = buffer.last(seconds: 1.0)
        XCTAssertEqual(window.first, Int16(truncatingIfNeeded: 8_000),
                       "Oldest sample should be the first sample of the second batch")
        XCTAssertEqual(window.last, Int16(truncatingIfNeeded: 23_999),
                      "Newest sample should be the last sample of the second batch")
    }

    func test_capacity_singleLargeAppendIsClamped() {
        // Append way more than the buffer can hold in one call
        let buffer = RollingAudioBuffer(capacitySeconds: 1.0, sampleRate: 16_000)
        let big = (0..<40_000).map { Int16(truncatingIfNeeded: $0) }
        buffer.append(big)

        XCTAssertEqual(buffer.sampleCount, 16_000)
        let window = buffer.last(seconds: 1.0)
        XCTAssertEqual(window.first, Int16(truncatingIfNeeded: 24_000))
        XCTAssertEqual(window.last, Int16(truncatingIfNeeded: 39_999))
    }

    // MARK: - Clear

    func test_clear_resetsBuffer() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        buffer.append([1, 2, 3, 4, 5])
        buffer.clear()

        XCTAssertEqual(buffer.sampleCount, 0)
        XCTAssertEqual(buffer.duration, 0)
        XCTAssertEqual(buffer.last(seconds: 1.0), [])
    }

    // MARK: - Flush

    func test_flush_returnsAndClearsContents() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        let samples: [Int16] = [1, 2, 3, 4, 5]
        buffer.append(samples)

        let flushed = buffer.flush()
        XCTAssertEqual(flushed, samples)
        XCTAssertEqual(buffer.sampleCount, 0)
    }

    // MARK: - Edge cases

    func test_negativeWindow_returnsEmpty() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 16_000)
        buffer.append([1, 2, 3])
        XCTAssertEqual(buffer.last(seconds: -1.0), [])
    }

    func test_invalidSampleRate_treatedAsZeroCapacity() {
        // A zero or negative sample rate would produce nonsense; we guard against it.
        let buffer = RollingAudioBuffer(capacitySeconds: 5.0, sampleRate: 0)
        buffer.append([1, 2, 3])
        // The buffer cannot accept samples if capacity cannot be computed
        XCTAssertEqual(buffer.sampleCount, 0)
    }
}

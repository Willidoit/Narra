import XCTest
import AVFoundation
@testable import NarraV2

final class AudioCaptureManagerTests: XCTestCase {

    // MARK: - Errors

    func test_audioCaptureError_equality() {
        XCTAssertEqual(AudioCaptureError.permissionDenied, .permissionDenied)
        XCTAssertEqual(AudioCaptureError.noInputDevice, .noInputDevice)
        XCTAssertEqual(
            AudioCaptureError.engineFailedToStart("nope"),
            .engineFailedToStart("nope")
        )
        XCTAssertNotEqual(AudioCaptureError.permissionDenied, .noInputDevice)
    }

    // MARK: - Configuration

    func test_defaultTargetSampleRate_is16k() {
        XCTAssertEqual(AudioCaptureManager.targetSampleRate, 16_000)
    }

    func test_defaultBufferSeconds_isFive() {
        XCTAssertEqual(AudioCaptureManager.defaultBufferSeconds, 5.0)
    }

    // MARK: - Init

    func test_init_createsBufferWithRequestedCapacity() {
        let mgr = AudioCaptureManager(bufferCapacitySeconds: 3.0, targetSampleRate: 16_000)
        XCTAssertEqual(mgr.buffer.capacitySeconds, 3.0)
        XCTAssertEqual(mgr.buffer.sampleRate, 16_000)
        XCTAssertEqual(mgr.buffer.sampleCount, 0)
        XCTAssertEqual(mgr.isCapturing, false)
        XCTAssertEqual(mgr.lastLevel, 0)
    }

    func test_init_acceptsArbitrarySampleRate() {
        let mgr = AudioCaptureManager(bufferCapacitySeconds: 2.0, targetSampleRate: 48_000)
        XCTAssertEqual(mgr.buffer.sampleRate, 48_000)
        XCTAssertEqual(mgr.buffer.capacity, 96_000)
    }

    // MARK: - Idempotency

    func test_clearBuffer_resetsBufferContents() {
        let mgr = AudioCaptureManager(bufferCapacitySeconds: 1.0, targetSampleRate: 16_000)
        mgr.buffer.append([1, 2, 3])
        XCTAssertEqual(mgr.buffer.sampleCount, 3)
        mgr.clearBuffer()
        XCTAssertEqual(mgr.buffer.sampleCount, 0)
    }

    // MARK: - Stop without start

    func test_stop_withoutStart_returnsEmptyChunk() {
        let mgr = AudioCaptureManager()
        let chunk = mgr.stop()
        XCTAssertEqual(chunk.samples, [])
        XCTAssertEqual(chunk.sampleRate, AudioCaptureManager.targetSampleRate)
        XCTAssertNil(chunk.startTime)
    }

    func test_stop_clearsPreviouslyCapturedBuffer() {
        let mgr = AudioCaptureManager(bufferCapacitySeconds: 1.0, targetSampleRate: 16_000)
        mgr.buffer.append([1, 2, 3, 4])
        let chunk = mgr.stop()
        XCTAssertEqual(chunk.samples, [1, 2, 3, 4])
        XCTAssertEqual(mgr.buffer.sampleCount, 0)
    }
}

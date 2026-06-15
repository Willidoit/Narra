import XCTest
@testable import NarraV2

final class TranscriptionServiceTests: XCTestCase {

    // MARK: - Mock service used by these tests

    /// A simple test double that records calls and returns canned results.
    actor MockTranscriptionService: TranscriptionService {
        struct Call: Sendable, Equatable {
            let sampleCount: Int
            let sampleRate: Double
        }

        private(set) var callCount = 0
        private(set) var lastAudio: AudioChunk?
        private let response: TranscriptSegment?

        init(response: TranscriptSegment? = nil) {
            self.response = response
        }

        func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
            callCount += 1
            lastAudio = audio
            if let response {
                return response
            } else {
                throw TranscriptionError.notImplemented
            }
        }

        func transcribe(stream: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptSegment, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    for await chunk in stream {
                        do {
                            let segment = try await self.transcribe(audio: chunk)
                            continuation.yield(segment)
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Protocol conformance

    func test_mockConformsToProtocol() {
        let mock = MockTranscriptionService()
        let service: any TranscriptionService = mock
        XCTAssertNotNil(service)
    }

    // MARK: - transcribe(audio:)

    func test_transcribe_invokesImplementation() async throws {
        let expected = TranscriptSegment(
            text: "hello",
            startTime: Date(),
            endTime: Date().addingTimeInterval(0.5)
        )
        let mock = MockTranscriptionService(response: expected)
        let chunk = AudioChunk(samples: [0, 1, 2], sampleRate: 16_000)

        let result = try await mock.transcribe(audio: chunk)
        XCTAssertEqual(result, expected)
        let calls = await mock.callCount
        XCTAssertEqual(calls, 1)
    }

    func test_transcribe_propagatesError() async {
        let mock = MockTranscriptionService(response: nil) // throws notImplemented
        let chunk = AudioChunk(samples: [0], sampleRate: 16_000)

        do {
            _ = try await mock.transcribe(audio: chunk)
            XCTFail("Expected error to be thrown")
        } catch {
            // expected
        }
    }

    // MARK: - AudioChunk

    func test_audioChunk_durationComputedFromSamples() {
        let chunk = AudioChunk(samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)
        XCTAssertEqual(chunk.duration, 1.0, accuracy: 0.0001)
    }

    func test_audioChunk_defaultSampleRateIs16k() {
        let chunk = AudioChunk(samples: [0])
        XCTAssertEqual(chunk.sampleRate, 16_000, "Default sample rate should match STT engine default")
    }

    func test_audioChunk_emptyIsValid() {
        let chunk = AudioChunk(samples: [], sampleRate: 16_000)
        XCTAssertEqual(chunk.duration, 0)
    }
}

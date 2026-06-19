import XCTest
@testable import Narra

final class WhisperCppTranscriptionServiceTests: XCTestCase {

    /// Until whisper.cpp is vendored as a CWhisper SwiftPM C-target, the
    /// service throws on every call. This locks the contract so we notice
    /// if the stub gets accidentally re-enabled without an implementation.
    func testStubServiceThrowsClearError() async {
        let service = WhisperCppTranscriptionService()
        let samples = [Int16](repeating: 0, count: 16_000)
        let chunk = AudioChunk(samples: samples, sampleRate: 16_000)
        do {
            _ = try await service.transcribe(audio: chunk)
            XCTFail("Expected stub to throw")
        } catch TranscriptionError.serviceError(let message) {
            XCTAssertTrue(message.contains("whisper.cpp"), "Error should mention whisper.cpp")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}

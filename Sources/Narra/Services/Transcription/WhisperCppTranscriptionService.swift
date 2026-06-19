import Foundation

/// Placeholder for the offline whisper.cpp + base.en path.
///
/// Status: stubbed. ggerganov/whisper.cpp does not publish a usable root
/// `Package.swift`, so SwiftPM cannot consume it as a dependency. The
/// follow-up is to vendor the C sources (`whisper.cpp`, `ggml*.c`, headers)
/// under `Sources/CWhisper/` as a SwiftPM C target, then re-implement
/// `transcribe(audio:)` against the bundled `Models/whisper-cpp/ggml-base.en.bin`
/// (see `Scripts/fetch-whisper-model.sh`).
///
/// Until that lands the service throws `TranscriptionError.serviceError`
/// with a clear message. The orchestrator already routes around it via
/// `transcribeWithFallback` when an active provider errors out.
public final class WhisperCppTranscriptionService: TranscriptionService, @unchecked Sendable {

    public struct Configuration: Sendable {
        public var modelID: String
        public init(modelID: String = "base.en") {
            self.modelID = modelID
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        throw TranscriptionError.serviceError(
            "whisper.cpp transcription is not yet wired in this build. Use WhisperKit or a cloud provider until the C-target vendoring lands."
        )
    }

    public func transcribe(
        stream: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptSegment, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: TranscriptionError.serviceError(
                "whisper.cpp transcription is not yet wired in this build."
            ))
        }
    }
}

import Foundation

/// Local transcription service backed by whisper.cpp.
///
/// This file ships the service shell and the model-orchestration glue;
/// the actual whisper.cpp call is left as a clearly-marked
/// `// TODO(integration)` so the real engine can be wired in without
/// re-architecting the surrounding code. The protocol surface and
/// error model are complete and testable.
public final class LocalTranscriptionService: TranscriptionService, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var modelManager: LocalModelManager
        public var spec: LocalModelManager.ModelSpec

        public init(
            modelManager: LocalModelManager = LocalModelManager(),
            spec: LocalModelManager.ModelSpec = LocalModelManager.defaultWhisper
        ) {
            self.modelManager = modelManager
            self.spec = spec
        }
    }

    // MARK: - State

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - TranscriptionService

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        guard !audio.samples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }
        let modelURL = try await ensureModel()

        // TODO(integration): replace the next line with a call to
        // whisper.cpp. The expected integration is:
        //
        //   1. Wrap `audio.samples` in an `AVAudioPCMBuffer` (16 kHz
        //      mono Int16, as the audio layer already produces).
        //   2. Call into a Swift binding for whisper.cpp:
        //          let ctx = WhisperContext(modelURL: modelURL)
        //          let result = try ctx.fullTranscribe(samples: audio.samples)
        //   3. Map the result to a TranscriptSegment using the audio's
        //      startTime / duration and any segment-level confidence the
        //      engine reports.
        //
        // Until the binding is added, raise `.serviceError` so the
        // orchestrator falls back to the cloud service.
        _ = modelURL
        throw TranscriptionError.serviceError(
            "Local whisper.cpp transcription is not yet wired in this build. " +
            "See TODO(integration) in LocalTranscriptionService.swift."
        )
    }

    public func transcribe(
        stream: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptSegment, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
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
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private func ensureModel() async throws -> URL {
        if let url = configuration.modelManager.localURL(for: configuration.spec) {
            return url
        }
        do {
            return try await configuration.modelManager.download(configuration.spec)
        } catch {
            throw TranscriptionError.serviceError(
                "Failed to download local STT model: \(error)"
            )
        }
    }
}

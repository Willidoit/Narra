import Foundation
import FluidAudio

/// Local transcription via NVIDIA Parakeet TDT, exposed through FluidAudio's
/// `UnifiedAsrManager` (CoreML port).
///
/// FluidAudio owns the model lifecycle: `loadModels(to:progressHandler:)` is
/// what `ModelDownloadCoordinator` invokes when the user clicks Download.
/// Once the models are on disk, this service constructs a cached
/// `UnifiedAsrManager` and routes audio chunks through `transcribe(_:)`.
public final class ParakeetTranscriptionService: TranscriptionService, @unchecked Sendable {

    public struct Configuration: Sendable {
        /// Directory containing the Parakeet CoreML bundle. The directory
        /// passed here is the one FluidAudio populates via `loadModels(to:)`.
        public var modelDirectory: URL
        public init(modelDirectory: URL) {
            self.modelDirectory = modelDirectory
        }
    }

    private let configuration: Configuration
    private var manager: UnifiedAsrManager?

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        guard !audio.samples.isEmpty else { throw TranscriptionError.emptyAudio }
        let mgr = try await loadManager()
        let floatSamples = audio.samples.map { Float($0) / 32_768.0 }
        let text: String
        do {
            text = try await mgr.transcribe(floatSamples)
        } catch {
            throw TranscriptionError.serviceError(
                "Parakeet transcription failed: \(error)"
            )
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw TranscriptionError.serviceError("Empty transcription result")
        }
        let now = audio.startTime ?? Date()
        return TranscriptSegment(
            text: trimmed,
            startTime: now,
            endTime: now.addingTimeInterval(audio.duration),
            confidence: 1.0
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

    private func loadManager() async throws -> UnifiedAsrManager {
        if let manager { return manager }
        let mgr = UnifiedAsrManager()
        do {
            try await mgr.loadModels(from: configuration.modelDirectory)
        } catch {
            throw TranscriptionError.serviceError(
                "Parakeet models not loaded — \(error). Download via Settings → Models."
            )
        }
        manager = mgr
        return mgr
    }
}

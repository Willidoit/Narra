import Foundation
import WhisperKit

/// Local transcription service backed by WhisperKit (on-device Whisper via
/// Apple Neural Engine / Core ML).
///
/// WhisperKit manages its own model downloads and caches them in
/// `~/.cache/huggingface/hub/`. The first call to `transcribe(audio:)` will
/// trigger a one-time model download (≈145 MB for `openai_whisper-base`) and
/// then cache a `WhisperKit` instance for subsequent calls so the model is
/// only loaded once per app lifetime.
public final class LocalTranscriptionService: TranscriptionService, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// WhisperKit model identifier. Must match a model name available via
        /// the Hugging Face `argmaxinc/whisperkit-coreml` repo.
        public var modelName: String

        /// Where WhisperKit looks for previously-downloaded model bundles.
        /// We point this at our app-support folder so progress observed by
        /// `ModelDownloadCoordinator` lands in the same place this service
        /// later loads from.
        public var downloadBase: URL?

        /// Legacy model-manager plumbing kept for API compatibility with
        /// `LocalModelManager`. WhisperKit bypasses the manager's download
        /// logic and handles its own caching.
        public var modelManager: LocalModelManager
        public var spec: LocalModelManager.ModelSpec

        public init(
            modelName: String = "openai_whisper-base",
            downloadBase: URL? = nil,
            modelManager: LocalModelManager = LocalModelManager(),
            spec: LocalModelManager.ModelSpec = LocalModelManager.defaultWhisper
        ) {
            self.modelName = modelName
            self.downloadBase = downloadBase
            self.modelManager = modelManager
            self.spec = spec
        }
    }

    // MARK: - State

    private let configuration: Configuration

    /// Lazily initialized on the first transcription call. Protected by the
    /// actor isolation of `loadWhisperKit()`.
    private var whisperKit: WhisperKit?

    /// Surfaces load/ready state for the menu bar and home view. Optional so
    /// tests can construct the service without UI plumbing.
    weak var engineState: TranscriptionEngineState?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Preload

    /// Loads the WhisperKit model without performing any transcription.
    /// Safe to call at app launch to avoid the multi-second freeze on the
    /// first recording.
    public func preload() async throws {
        _ = try await loadWhisperKit()
    }

    // MARK: - TranscriptionService

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        guard !audio.samples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let wk = try await loadWhisperKit()

        // AudioChunk.samples are 16-bit PCM integers; WhisperKit expects
        // normalized Float32 in [-1.0, 1.0].
        let floatSamples = audio.samples.map { Float($0) / 32_768.0 }

        let results = try await wk.transcribe(audioArray: floatSamples)

        let text = results.first?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Derive a confidence value from the first segment's average
        // log-probability (exp maps log-prob → [0, 1]).
        let confidence: Double
        if let avgLogprob = results.first?.segments.first?.avgLogprob {
            confidence = Double(Foundation.exp(avgLogprob))
        } else {
            confidence = 1.0
        }

        let now = Date()
        return TranscriptSegment(
            text: text,
            startTime: now,
            endTime: now,
            confidence: confidence
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

    /// Returns the cached `WhisperKit` instance, creating and caching it on
    /// first call. Subsequent calls are fast (no model reload).
    private func loadWhisperKit() async throws -> WhisperKit {
        if let existing = whisperKit { return existing }
        let state = engineState
        await MainActor.run {
            state?.isLoading = true
            state?.lastError = nil
        }
        do {
            let wk = try await WhisperKit(
                model: configuration.modelName,
                downloadBase: configuration.downloadBase
            )
            whisperKit = wk
            await MainActor.run {
                state?.isReady = true
                state?.isLoading = false
            }
            return wk
        } catch {
            await MainActor.run {
                state?.lastError = String(describing: error)
                state?.isLoading = false
            }
            throw TranscriptionError.serviceError(
                "Failed to initialize WhisperKit (\(configuration.modelName)): \(error)"
            )
        }
    }
}

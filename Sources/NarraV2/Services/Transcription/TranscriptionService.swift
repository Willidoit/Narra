import Foundation

// MARK: - AudioChunk

/// A self-contained slice of audio handed to a `TranscriptionService`.
///
/// `AudioChunk` is intentionally engine-agnostic: it is a flat array of
/// mono `Int16` samples plus the sample rate. The capture layer is
/// responsible for resampling and downmixing to this format, so that
/// every concrete service (Grok, local Whisper, …) sees the same shape.
public struct AudioChunk: Sendable, Equatable {
    public let samples: [Int16]
    public let sampleRate: Double

    /// The wall-clock time at which this chunk's first sample was captured.
    /// May be `nil` for synthetic or replayed audio.
    public let startTime: Date?

    public init(
        samples: [Int16],
        sampleRate: Double = 16_000,
        startTime: Date? = nil
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.startTime = startTime
    }

    /// Duration of this chunk in seconds.
    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

// MARK: - Errors

/// Errors raised by a `TranscriptionService`.
public enum TranscriptionError: Error, Equatable, Sendable {
    /// The concrete service has not been implemented yet (test placeholder).
    case notImplemented
    /// Audio was empty or otherwise unprocessable.
    case emptyAudio
    /// The remote service returned an unrecoverable error.
    case serviceError(String)
    /// The user has not granted microphone access.
    case permissionDenied
}

// MARK: - Protocol

/// Abstracts audio chunking and speech-to-text calls.
///
/// A `TranscriptionService` is the seam between the audio capture layer
/// and the STT engine. The capture layer hands it `AudioChunk`s (typically
/// produced from a `RollingAudioBuffer` window); the service returns
/// `TranscriptSegment`s.
///
/// Two usage modes are supported:
///
/// 1. **Batch** via `transcribe(audio:)`: hand the engine an entire chunk
///    of audio and await a single result. Best for short captures and
///    "transcribe the last 5 seconds" UX.
/// 2. **Streaming** via `transcribe(stream:)`: feed chunks as they become
///    available and consume emitted segments as they are produced. Best
///    for continuous dictation and live captioning.
///
/// Implementations are expected to be `Sendable` and to never block the
/// real-time audio thread; any work that needs audio-thread results should
/// be hopped to an internal queue or async context first.
public protocol TranscriptionService: Sendable {
    /// Transcribe a single audio chunk in its entirety and return the
    /// resulting segment.
    func transcribe(audio: AudioChunk) async throws -> TranscriptSegment

    /// Consume a stream of audio chunks, yielding transcript segments as
    /// they become available. The returned stream finishes when the input
    /// stream finishes or an unrecoverable error occurs.
    func transcribe(stream: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptSegment, Error>
}

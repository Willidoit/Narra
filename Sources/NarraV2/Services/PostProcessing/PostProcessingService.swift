import Foundation

/// A single post-processed rewrite of one or more transcript segments.
///
/// `ProcessedTranscript` is the value type produced by a
/// `PostProcessingService` and consumed by the UI. It carries the
/// corrected text, the time range it covers, and the source segments it
/// was derived from so the UI can highlight the corrected span.
public struct ProcessedTranscript: Equatable, Sendable, Hashable, Codable {

    /// Stable identifier. Useful for SwiftUI diffing and for tracking
    /// corrections across re-runs of the post-processor.
    public let id: UUID

    /// The corrected text, ready to display.
    public let text: String

    /// Start of the time range that this rewrite covers.
    public let startTime: Date

    /// End of the time range that this rewrite covers.
    public let endTime: Date

    /// The source `TranscriptSegment` ids that this rewrite was derived
    /// from. May be empty for synthetic results (e.g. a manual edit).
    public let sourceSegmentIDs: [UUID]

    /// Confidence in the rewrite, in `[0, 1]`. Defaults to `1.0` when the
    /// service does not report a value.
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: Date,
        endTime: Date,
        sourceSegmentIDs: [UUID] = [],
        confidence: Double = 1.0
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.sourceSegmentIDs = sourceSegmentIDs
        self.confidence = confidence
    }

    /// Duration of the rewrite in seconds, derived from its timestamps.
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Errors

/// Errors raised by a `PostProcessingService`.
public enum PostProcessingError: Error, Equatable, Sendable {
    /// The remote service returned an unrecoverable error.
    case serviceError(String)
    /// The user has not provided an API key for the remote service.
    case missingAPIKey
    /// The remote service returned malformed output that could not be
    /// parsed into a `ProcessedTranscript`.
    case invalidResponse
    /// Network request exceeded the configured timeout.
    case timeout
    /// Rate limited by the remote service.
    case rateLimited(retryAfterSeconds: Double?)
}

// MARK: - Protocol

/// Cleans up raw transcript segments for display.
///
/// Implementations take one or more `TranscriptSegment`s and produce a
/// single `ProcessedTranscript` that has been intelligently rewritten to
/// handle:
/// - Self-corrections ("No, wait, I mean...")
/// - Restatements
/// - Filler words ("um", "uh", "like", "you know")
///
/// Implementations are expected to be `Sendable` and to keep the API
/// surface narrow: the UI hands it text, it returns text.
public protocol PostProcessingService: Sendable {
    /// Process a single segment in isolation. Useful for low-latency
    /// streaming use cases where the caller wants to rewrite each
    /// segment as it is produced.
    func process(segment: TranscriptSegment) async throws -> ProcessedTranscript

    /// Process a sequence of segments as one window. Implementations
    /// should use the window's context to detect self-corrections and
    /// restatements that span segment boundaries.
    func process(segments: [TranscriptSegment]) async throws -> ProcessedTranscript
}

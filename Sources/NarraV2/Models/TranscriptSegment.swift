import Foundation

/// A single unit of transcribed text with timing and confidence metadata.
///
/// `TranscriptSegment` is the value type produced by `TranscriptionService`
/// and consumed by post-processing and the UI. It carries enough information
/// for downstream stages to reason about timing (e.g. aligning corrections
/// with their target spans) and to display confidence to the user.
public struct TranscriptSegment: Identifiable, Equatable, Sendable, Hashable, Codable {

    /// Stable identifier for the segment. Useful for SwiftUI diffing and for
    /// referencing a segment from a post-processing correction.
    public let id: UUID

    /// The transcribed text for this segment.
    public let text: String

    /// The wall-clock time at which the spoken audio for this segment began.
    public let startTime: Date

    /// The wall-clock time at which the spoken audio for this segment ended.
    public let endTime: Date

    /// Engine-reported confidence in `[0, 1]`. Defaults to `1.0` when the
    /// engine does not report a value.
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: Date,
        endTime: Date,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }

    /// Duration of the segment in seconds, derived from its timestamps.
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

import Foundation

// MARK: - Protocol output type

/// A single post-processed rewrite of one or more transcript segments.
///
/// `ProcessedTranscript` is the value type produced by a
/// `PostProcessingService` and consumed by the UI. It carries the
/// corrected text, the time range it covers, and the source segments it
/// was derived from so the UI can highlight the corrected span.
public struct ProcessedTranscript: Equatable, Sendable, Hashable, Codable {

    public let id: UUID
    public let text: String
    public let startTime: Date
    public let endTime: Date
    public let sourceSegmentIDs: [UUID]
    public let confidence: Double
    public let usedCloud: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: Date,
        endTime: Date,
        sourceSegmentIDs: [UUID] = [],
        confidence: Double = 1.0,
        usedCloud: Bool = false
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.sourceSegmentIDs = sourceSegmentIDs
        self.confidence = confidence
        self.usedCloud = usedCloud
    }

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Errors

public enum PostProcessingError: Error, Equatable, Sendable {
    case serviceError(String)
    case missingAPIKey
    case invalidResponse
    case timeout
    case rateLimited(retryAfterSeconds: Double?)
}

// MARK: - Protocol

public protocol PostProcessingService: Sendable {
    func process(segment: TranscriptSegment) async throws -> ProcessedTranscript
    func process(segments: [TranscriptSegment]) async throws -> ProcessedTranscript
}

// MARK: - LocalCorrectionFilter I/O types

/// Input type for `LocalCorrectionFilter.apply(_:)`.
public struct PostProcessingRequest: Equatable, Sendable {
    public var rawText: String
    public var segment: TranscriptSegment?
    public var context: [TranscriptSegment]

    public init(
        rawText: String,
        segment: TranscriptSegment? = nil,
        context: [TranscriptSegment] = []
    ) {
        self.rawText = rawText
        self.segment = segment
        self.context = context
    }
}

/// Output type for `LocalCorrectionFilter.apply(_:)`.
public struct PostProcessingResult: Equatable, Sendable {
    public var refinedText: String
    public var segments: [TranscriptSegment]

    public init(refinedText: String, segments: [TranscriptSegment] = []) {
        self.refinedText = refinedText
        self.segments = segments
    }
}

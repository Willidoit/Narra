import Foundation

// MARK: - Sentence boundary

/// Pure sentence splitter used by `StreamingPostProcessor`. Splits on
/// `.`, `!`, `?` followed by whitespace. Anything past the last terminator
/// stays in `remainder` so we can re-attempt boundary detection once the
/// next segment lands.
///
/// `force = true` flushes the entire buffer (used by `flush()` on stop).
public func extractCompletedSentences(buffer: String, force: Bool = false) -> (completed: [String], remainder: String) {
    let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ([], "") }

    if force {
        return ([trimmed], "")
    }

    var completed: [String] = []
    var current = ""
    var i = trimmed.startIndex
    while i < trimmed.endIndex {
        let ch = trimmed[i]
        current.append(ch)
        if ch == "." || ch == "!" || ch == "?" {
            let next = trimmed.index(after: i)
            let isAtEnd = next == trimmed.endIndex
            let nextIsWhitespace = !isAtEnd && trimmed[next].isWhitespace
            if nextIsWhitespace {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { completed.append(sentence) }
                current = ""
            }
        }
        i = trimmed.index(after: i)
    }
    let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
    return (completed, remainder)
}

// MARK: - StreamingPostProcessor

/// Live, per-recording cleanup pipeline. Segments are fed in as the
/// transcriber emits them. The engine runs `LocalCorrectionFilter`
/// synchronously on each completed sentence so the paste-on-stop hot path
/// is fast even when the LLM is slow or offline.
///
/// Concurrency model: one actor instance per recording session. `feed` is
/// reentrant; `flush` is called exactly once on stop and races an 800 ms
/// timeout against the in-flight LLM batch.
public actor StreamingPostProcessor {

    // MARK: Config

    public struct Configuration: Sendable {
        public var cloudProcessor: any PostProcessingService
        public var localProcessor: any PostProcessingService
        public var useCloud: Bool
        public var startTime: Date
        public var smartFillerThreshold: Bool

        public init(
            cloudProcessor: any PostProcessingService,
            localProcessor: any PostProcessingService,
            useCloud: Bool,
            startTime: Date = Date(),
            smartFillerThreshold: Bool = true
        ) {
            self.cloudProcessor = cloudProcessor
            self.localProcessor = localProcessor
            self.useCloud = useCloud
            self.startTime = startTime
            self.smartFillerThreshold = smartFillerThreshold
        }
    }

    private let config: Configuration
    private let filter = LocalCorrectionFilter()
    private var rawSegments: [TranscriptSegment] = []
    private var rollingBuffer: String = ""
    private var cleanedSentences: [String] = []

    public init(configuration: Configuration) {
        self.config = configuration
    }

    // MARK: - Feed

    /// Called by ContentViewModel for every emitted TranscriptSegment.
    /// Runs the regex filter synchronously; never awaits the LLM here
    /// (LLM passes are deferred to `flush` so an LLM stall can't back up
    /// the segment stream).
    public func feed(segment: TranscriptSegment) {
        rawSegments.append(segment)
        rollingBuffer.append(segment.text)
        if !segment.text.hasSuffix(" ") { rollingBuffer.append(" ") }

        let (completed, remainder) = extractCompletedSentences(buffer: rollingBuffer)
        rollingBuffer = remainder

        for sentence in completed {
            let cleaned = filter.apply(PostProcessingRequest(rawText: sentence, segment: segment))
            let text = cleaned.refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { cleanedSentences.append(text) }
        }
    }

    // MARK: - Flush

    /// Called once on recording stop. Returns the final `ProcessedTranscript`.
    /// Strategy: drain the remainder buffer, then race the LLM cleanup against
    /// an 800 ms timeout. If the timeout wins, return the regex-cleaned text
    /// (still readable) and let the orchestrator decide whether to swap in
    /// the LLM result later (clipboard upgrade, no re-paste).
    public func flush(level: CleanupLevel) async -> ProcessedTranscript {
        let (tail, _) = extractCompletedSentences(buffer: rollingBuffer, force: true)
        for sentence in tail {
            let cleaned = filter.apply(PostProcessingRequest(rawText: sentence))
            let text = cleaned.refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { cleanedSentences.append(text) }
        }
        rollingBuffer = ""

        let filterOnlyText = cleanedSentences.joined(separator: " ")
        let now = Date()
        let fallback = ProcessedTranscript(
            text: filterOnlyText,
            startTime: rawSegments.first?.startTime ?? now,
            endTime: rawSegments.last?.endTime ?? now,
            sourceSegmentIDs: rawSegments.map(\.id),
            confidence: 1.0,
            usedCloud: false
        )

        // Cleanup level .none: skip the LLM entirely, paste raw filter output.
        guard level != .none, !rawSegments.isEmpty else {
            return fallback
        }

        let processor = config.useCloud ? config.cloudProcessor : config.localProcessor
        let segmentsForLLM = rawSegments
        let llmResult = await runWithTimeout(timeout: .milliseconds(800)) {
            try await processor.process(segments: segmentsForLLM)
        }
        return llmResult ?? fallback
    }

    // MARK: - Inspection (for tests / debug HUD)

    public var currentCleanedText: String {
        cleanedSentences.joined(separator: " ")
    }
}

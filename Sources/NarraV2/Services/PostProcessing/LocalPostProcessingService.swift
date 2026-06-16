import Foundation

/// Local post-processing service backed by an on-device LLM via MLX Swift.
///
/// Each call first runs the deterministic `LocalCorrectionFilter` to strip
/// obvious fillers and self-corrections, then attempts MLX inference. If
/// the model is unavailable or inference fails, the filter output is used
/// as the result.
public final class LocalPostProcessingService: PostProcessingService, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var modelManager: LocalModelManager
        public var spec: LocalModelManager.ModelSpec
        public var systemPrompt: String

        public init(
            modelManager: LocalModelManager = LocalModelManager(),
            spec: LocalModelManager.ModelSpec = LocalModelManager.defaultLLM,
            systemPrompt: String = LocalPostProcessingService.defaultSystemPrompt
        ) {
            self.modelManager = modelManager
            self.spec = spec
            self.systemPrompt = systemPrompt
        }
    }

    public static let defaultSystemPrompt: String = """
    You are a post-processor for a voice-to-text app running on-device.
    Apply these rules IN ORDER:

    1. Drop filler words ("um", "uh", "like", "you know").
    2. Resolve self-corrections. When the speaker says "no, wait" /
       "actually" / "I mean" and then restates, keep only the final
       corrected version.
    3. Merge restatements. Keep the more coherent version, drop the
       weaker one.
    4. Preserve the speaker's voice. Do not rephrase, summarize, or
       add new information.
    5. If the input is already clean, return it unchanged.

    Output: the cleaned text only, with no preamble or quotation marks.
    """

    // MARK: - State

    private let configuration: Configuration
    private let localFilter: LocalCorrectionFilter

    public init(
        configuration: Configuration = Configuration(),
        localFilter: LocalCorrectionFilter = LocalCorrectionFilter()
    ) {
        self.configuration = configuration
        self.localFilter = localFilter
    }

    // MARK: - PostProcessingService

    public func process(segment: TranscriptSegment) async throws -> ProcessedTranscript {
        try await process(segments: [segment])
    }

    public func process(segments: [TranscriptSegment]) async throws -> ProcessedTranscript {
        guard !segments.isEmpty else {
            throw PostProcessingError.serviceError("No segments to process")
        }

        let filtered = applyLocalFilter(to: segments)
        let start = segments.map(\.startTime).min() ?? Date()
        let end = segments.map(\.endTime).max() ?? Date()
        let avgConfidence = segments.map(\.confidence).reduce(0, +) / Double(segments.count)

        if let mlxText = try? await runMLX(on: filtered) {
            return ProcessedTranscript(
                text: mlxText,
                startTime: start,
                endTime: end,
                sourceSegmentIDs: segments.map(\.id),
                confidence: avgConfidence
            )
        }

        let text = filtered.map(\.text).joined(separator: " ")
        return ProcessedTranscript(
            text: text,
            startTime: start,
            endTime: end,
            sourceSegmentIDs: segments.map(\.id),
            confidence: avgConfidence
        )
    }

    // MARK: - Local pre-pass

    private func applyLocalFilter(to segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.map { segment in
            let request = PostProcessingRequest(rawText: segment.text, segment: segment)
            let result = localFilter.apply(request)
            return TranscriptSegment(
                id: segment.id,
                text: result.refinedText,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence
            )
        }
    }

    // MARK: - MLX inference

    private func runMLX(on segments: [TranscriptSegment]) async throws -> String {
        // ponytail: MLX inference is a TODO and ensureModel triggers an
        // 800MB Llama download that blocks the pill. Short-circuit until
        // wired up; caller falls through to regex output.
        guard configuration.modelManager.isDownloaded(configuration.spec) else {
            throw PostProcessingError.serviceError("Local LLM not downloaded; skipping MLX.")
        }
        throw PostProcessingError.serviceError(
            "Local MLX post-processing is not yet wired. See TODO(integration) in LocalPostProcessingService.swift."
        )
    }

    private func ensureModel() async throws -> URL {
        if let url = configuration.modelManager.localURL(for: configuration.spec) {
            return url
        }
        do {
            return try await configuration.modelManager.download(configuration.spec)
        } catch {
            throw PostProcessingError.serviceError("Failed to download local LLM model: \(error)")
        }
    }
}

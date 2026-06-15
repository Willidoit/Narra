import Foundation

/// Local post-processing service backed by an on-device LLM via MLX
/// Swift.
///
/// Like `LocalTranscriptionService`, this ships the orchestration
/// shell; the actual MLX inference call is left as a `// TODO(integration)`
/// marker so the integration can be dropped in without restructuring
/// the surrounding code.
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

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - PostProcessingService

    public func process(segment: TranscriptSegment) async throws -> ProcessedTranscript {
        try await process(segments: [segment])
    }

    public func process(segments: [TranscriptSegment]) async throws -> ProcessedTranscript {
        guard !segments.isEmpty else {
            throw PostProcessingError.serviceError("No segments to process")
        }
        let modelURL = try await ensureModel()

        // TODO(integration): replace the next line with a call into
        // MLX Swift. The expected integration is:
        //
        //   1. Concatenate `segments.map(\.text)` with a single newline
        //      between them.
        //   2. Build a chat-template prompt:
        //          "<system>\(configuration.systemPrompt)\n</system>\n" +
        //          "<user>\(joined)</user>\n<assistant>"
        //   3. Run inference at low temperature (0.1) with a small max
        //      token count (segments rarely need more than 1k tokens).
        //   4. Strip the assistant marker and any leading/trailing
        //      whitespace from the response.
        //
        // Until MLX is wired in, raise `.serviceError` so the
        // orchestrator falls back to the cloud service.
        _ = modelURL
        throw PostProcessingError.serviceError(
            "Local MLX post-processing is not yet wired in this build. " +
            "See TODO(integration) in LocalPostProcessingService.swift."
        )
    }

    // MARK: - Private

    private func ensureModel() async throws -> URL {
        if let url = configuration.modelManager.localURL(for: configuration.spec) {
            return url
        }
        do {
            return try await configuration.modelManager.download(configuration.spec)
        } catch {
            throw PostProcessingError.serviceError(
                "Failed to download local LLM model: \(error)"
            )
        }
    }
}

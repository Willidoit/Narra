import Foundation

/// PostProcessingService implementation backed by the xAI (Grok) chat
/// completions endpoint.
///
/// Each call first runs the deterministic `LocalCorrectionFilter` to strip
/// obvious fillers and self-corrections, then sends the filtered text to
/// Grok for LLM-quality refinement.
public final class GrokPostProcessingService: PostProcessingService, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var temperature: Double
        public var timeout: TimeInterval

        public init(
            baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!,
            model: String = "llama-3.1-8b-instant",
            temperature: Double = 0.1,
            timeout: TimeInterval = 20
        ) {
            self.baseURL = baseURL
            self.model = model
            self.temperature = temperature
            self.timeout = timeout
        }
    }

    // MARK: - Dependencies

    private let configuration: Configuration
    private let injectedKey: String?
    private let session: URLSession
    private let requestBuilder: GrokChatCompletionsRequestBuilder
    private let responseParser: GrokChatCompletionsResponseParser
    private let localFilter: LocalCorrectionFilter

    // MARK: - Init

    public init(
        configuration: Configuration = Configuration(),
        apiKey: String? = nil,
        localFilter: LocalCorrectionFilter = LocalCorrectionFilter(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.injectedKey = apiKey
        self.localFilter = localFilter
        self.session = session
        self.requestBuilder = GrokChatCompletionsRequestBuilder(configuration: configuration)
        self.responseParser = GrokChatCompletionsResponseParser()
    }

    // MARK: - PostProcessingService

    public func process(segment: TranscriptSegment) async throws -> ProcessedTranscript {
        try await process(segments: [segment])
    }

    public func process(segments: [TranscriptSegment]) async throws -> ProcessedTranscript {
        try await process(segments: segments, level: .medium)
    }

    public func process(segments: [TranscriptSegment], level: CleanupLevel) async throws -> ProcessedTranscript {
        let key = currentAPIKey()
        guard !key.isEmpty else {
            throw PostProcessingError.missingAPIKey
        }
        guard !segments.isEmpty else {
            throw PostProcessingError.serviceError("No segments to process")
        }

        let filtered = applyLocalFilter(to: segments)
        let prompt = PostProcessingPrompt(level: level)
        let request = try requestBuilder.makeRequest(
            apiKey: key,
            systemPrompt: prompt.systemPrompt,
            userPrompt: prompt.userPrompt(for: filtered)
        )
        let (data, response) = try await send(request)
        try responseParser.validate(response: response, body: data)
        let text = try responseParser.parseContent(data: data)

        let start = segments.map(\.startTime).min() ?? Date()
        let end = segments.map(\.endTime).max() ?? Date()
        let avgConfidence = segments.map(\.confidence).reduce(0, +) / Double(segments.count)
        return ProcessedTranscript(
            text: text,
            startTime: start,
            endTime: end,
            sourceSegmentIDs: segments.map(\.id),
            confidence: avgConfidence,
            usedCloud: true
        )
    }

    private func currentAPIKey() -> String {
        injectedKey ?? GrokAPIKeySource.resolve() ?? ""
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

    // MARK: - Networking

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    cont.resume(throwing: PostProcessingError.serviceError("No response"))
                    return
                }
                cont.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

// MARK: - Prompt

struct PostProcessingPrompt {

    let level: CleanupLevel

    init(level: CleanupLevel = .medium) {
        self.level = level
    }

    var systemPrompt: String {
        switch level {
        case .none:
            return "You are a post-processor for a voice-to-text app. Return the transcript exactly as provided, with no edits whatsoever.\n\nOutput: the text only, with no preamble, no explanation, and no quotation marks."
        case .light:
            return "You are a post-processor for a voice-to-text app. Strip filler words (\"um\", \"uh\", \"er\", \"like\", \"you know\") and fix obvious grammar errors only. Do not rephrase, restructure, or remove any content.\n\nOutput: the cleaned text only, with no preamble, no explanation, and no quotation marks. Preserve the original language of the input."
        case .medium:
            return """
    You are a post-processor for a voice-to-text app. Your job is to
    clean up raw speech-to-text output for display. Apply these rules
    IN ORDER:

    1. Remove filler words ("um", "uh", "er", "like", "you know", "I
       mean" when used as fillers, "kind of", "sort of") unless they
       are load-bearing for meaning.
    2. Resolve self-corrections. When the speaker says "no, wait" /
       "actually" / "I mean" / "sorry" and then restates, keep only
       the final corrected version. The discarded text must not
       appear.
    3. Merge restatements. If the same idea is stated twice in
       different words, keep the more coherent version. Drop the
       weaker one.
    4. Preserve the speaker's voice. Do not rephrase, summarize, or
       add new information. Punctuation may be cleaned up.
    5. If the input is already clean, return it unchanged.

    Output: the cleaned text only, with no preamble, no explanation,
    and no quotation marks. Preserve the original language of the
    input.
    """
        case .high:
            return "You are a post-processor for a voice-to-text app. Condense the transcript aggressively: drop all redundancy, filler, self-corrections, and restatements. Prioritize brevity. Keep only the core information.\n\nOutput: the condensed text only, with no preamble, no explanation, and no quotation marks. Preserve the original language of the input."
        }
    }

    func userPrompt(for segments: [TranscriptSegment]) -> String {
        let numbered = segments.enumerated()
            .map { i, s in "[\(i)] \(s.text)" }
            .joined(separator: "\n")
        return "Raw transcript segments (use [N] only as references):\n\(numbered)\n\nCleaned text:"
    }
}

// MARK: - Request builder

struct GrokChatCompletionsRequestBuilder {

    let configuration: GrokPostProcessingService.Configuration

    func makeRequest(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String
    ) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.timeout

        let body: [String: Any] = [
            "model": configuration.model,
            "temperature": configuration.temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Response parser

struct GrokChatCompletionsResponseParser {

    func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PostProcessingError.serviceError("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw PostProcessingError.serviceError("Unauthorized (\(http.statusCode))")
        case 408, 504:
            throw PostProcessingError.timeout
        case 429:
            let retry = parseRetryAfter(response: http)
            throw PostProcessingError.rateLimited(retryAfterSeconds: retry)
        default:
            let snippet = String(data: body.prefix(256), encoding: .utf8) ?? ""
            throw PostProcessingError.serviceError("HTTP \(http.statusCode): \(snippet)")
        }
    }

    func parseContent(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw PostProcessingError.invalidResponse
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw PostProcessingError.invalidResponse
        }
        return trimmed
    }

    private func parseRetryAfter(response: HTTPURLResponse) -> Double? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Double(header)
    }
}

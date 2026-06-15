import Foundation

/// PostProcessingService implementation backed by the xAI (Grok) chat
/// completions endpoint.
///
/// Uses a strict, low-temperature system prompt to rewrite raw STT text
/// into display-ready text. The prompt is engineered to:
///
/// - Drop filler words ("um", "uh", "like", "you know") when they are
///   not load-bearing.
/// - Detect self-corrections ("no, wait", "actually", "I mean") and
///   keep only the corrected version.
/// - Merge restatements into the most coherent version.
/// - Preserve the speaker's voice — never rephrase, only clean.
public final class GrokPostProcessingService: PostProcessingService, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var temperature: Double
        public var timeout: TimeInterval

        public init(
            baseURL: URL = URL(string: "https://api.x.ai/v1")!,
            model: String = "grok-2-latest",
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
    private let apiKey: String
    private let session: URLSession
    private let requestBuilder: GrokChatCompletionsRequestBuilder
    private let responseParser: GrokChatCompletionsResponseParser
    private let prompt: PostProcessingPrompt

    // MARK: - Init

    public init(
        configuration: Configuration = Configuration(),
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.apiKey = apiKey ?? GrokAPIKeySource.resolve() ?? ""
        self.session = session
        self.requestBuilder = GrokChatCompletionsRequestBuilder(configuration: configuration)
        self.responseParser = GrokChatCompletionsResponseParser()
        self.prompt = PostProcessingPrompt()
    }

    // MARK: - PostProcessingService

    public func process(segment: TranscriptSegment) async throws -> ProcessedTranscript {
        guard !apiKey.isEmpty else {
            throw PostProcessingError.missingAPIKey
        }
        let request = try requestBuilder.makeRequest(
            apiKey: apiKey,
            systemPrompt: prompt.systemPrompt,
            userPrompt: prompt.userPrompt(for: [segment])
        )
        let (data, response) = try await send(request)
        try responseParser.validate(response: response, body: data)
        let text = try responseParser.parseContent(data: data)
        return ProcessedTranscript(
            text: text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            sourceSegmentIDs: [segment.id],
            confidence: segment.confidence
        )
    }

    public func process(segments: [TranscriptSegment]) async throws -> ProcessedTranscript {
        guard !apiKey.isEmpty else {
            throw PostProcessingError.missingAPIKey
        }
        guard !segments.isEmpty else {
            throw PostProcessingError.serviceError("No segments to process")
        }
        let request = try requestBuilder.makeRequest(
            apiKey: apiKey,
            systemPrompt: prompt.systemPrompt,
            userPrompt: prompt.userPrompt(for: segments)
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
            confidence: avgConfidence
        )
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

/// The system + user prompts sent to Grok for post-processing.
///
/// The system prompt is the contract: it tells the model exactly what
/// "post-processing" means in this app and forbids the behaviors that
/// would degrade quality (rephrasing, summarizing, hallucinating).
struct PostProcessingPrompt {

    let systemPrompt: String = """
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

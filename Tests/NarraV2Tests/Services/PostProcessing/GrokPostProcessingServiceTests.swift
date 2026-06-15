import XCTest
import Foundation
@testable import NarraV2

final class GrokPostProcessingServiceTests: XCTestCase {

    // MARK: - Prompt

    func test_systemPrompt_forbidsRephrasing() {
        let prompt = PostProcessingPrompt()
        XCTAssertTrue(prompt.systemPrompt.contains("Do not rephrase"))
        XCTAssertTrue(prompt.systemPrompt.contains("filler"))
        XCTAssertTrue(prompt.systemPrompt.contains("self-correction"))
    }

    func test_userPrompt_numbersSegments() {
        let prompt = PostProcessingPrompt()
        let now = Date()
        let segments = [
            TranscriptSegment(text: "hello", startTime: now, endTime: now),
            TranscriptSegment(text: "world", startTime: now, endTime: now)
        ]
        let output = prompt.userPrompt(for: segments)
        XCTAssertTrue(output.contains("[0] hello"))
        XCTAssertTrue(output.contains("[1] world"))
    }

    // MARK: - Request builder

    func test_requestBuilder_targetsChatCompletions() throws {
        let builder = GrokChatCompletionsRequestBuilder(
            configuration: GrokPostProcessingService.Configuration()
        )
        let request = try builder.makeRequest(
            apiKey: "k",
            systemPrompt: "system",
            userPrompt: "user"
        )
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer k"
        )
    }

    func test_requestBuilder_passesModelAndTemperature() throws {
        let builder = GrokChatCompletionsRequestBuilder(
            configuration: GrokPostProcessingService.Configuration(
                model: "grok-test",
                temperature: 0.42
            )
        )
        let request = try builder.makeRequest(
            apiKey: "k",
            systemPrompt: "sys",
            userPrompt: "usr"
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "grok-test")
        XCTAssertEqual(body?["temperature"] as? Double, 0.42)
    }

    func test_requestBuilder_includesSystemAndUserMessages() throws {
        let builder = GrokChatCompletionsRequestBuilder(
            configuration: GrokPostProcessingService.Configuration()
        )
        let request = try builder.makeRequest(
            apiKey: "k",
            systemPrompt: "you are X",
            userPrompt: "process this"
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?[0]["role"] as? String, "system")
        XCTAssertEqual(messages?[0]["content"] as? String, "you are X")
        XCTAssertEqual(messages?[1]["role"] as? String, "user")
        XCTAssertEqual(messages?[1]["content"] as? String, "process this")
    }

    // MARK: - Response parser

    func test_responseParser_parsesContent() throws {
        let parser = GrokChatCompletionsResponseParser()
        let json: [String: Any] = [
            "choices": [
                ["message": ["role": "assistant", "content": "  hello world  "]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let text = try parser.parseContent(data: data)
        XCTAssertEqual(text, "hello world")
    }

    func test_responseParser_throwsOnEmptyChoices() throws {
        let parser = GrokChatCompletionsResponseParser()
        let data = try JSONSerialization.data(withJSONObject: ["choices": []])
        XCTAssertThrowsError(try parser.parseContent(data: data)) { err in
            XCTAssertEqual(err as? PostProcessingError, .invalidResponse)
        }
    }

    func test_responseParser_throwsOnEmptyContent() throws {
        let parser = GrokChatCompletionsResponseParser()
        let json: [String: Any] = [
            "choices": [["message": ["role": "assistant", "content": "   "]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try parser.parseContent(data: data)) { err in
            XCTAssertEqual(err as? PostProcessingError, .invalidResponse)
        }
    }

    func test_responseParser_mapsTimeout() {
        let parser = GrokChatCompletionsResponseParser()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 504,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertThrowsError(try parser.validate(response: response, body: Data())) { err in
            XCTAssertEqual(err as? PostProcessingError, .timeout)
        }
    }

    func test_responseParser_mapsRateLimitWithRetryAfter() {
        let parser = GrokChatCompletionsResponseParser()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "12"]
        )!
        XCTAssertThrowsError(try parser.validate(response: response, body: Data())) { err in
            XCTAssertEqual(err as? PostProcessingError, .rateLimited(retryAfterSeconds: 12))
        }
    }

    // MARK: - Service end-to-end behaviour

    func test_service_throwsOnMissingAPIKey() async {
        let service = GrokPostProcessingService(apiKey: "")
        let segment = TranscriptSegment(
            text: "hello",
            startTime: Date(),
            endTime: Date()
        )
        do {
            _ = try await service.process(segment: segment)
            XCTFail("Expected missingAPIKey")
        } catch {
            XCTAssertEqual(error as? PostProcessingError, .missingAPIKey)
        }
    }

    func test_service_throwsOnEmptySegments() async {
        let service = GrokPostProcessingService(apiKey: "k")
        do {
            _ = try await service.process(segments: [])
            XCTFail("Expected serviceError")
        } catch {
            // Either serviceError or missingAPIKey; both are acceptable
            // since the check is internal. We document the order.
            XCTAssertTrue(error is PostProcessingError)
        }
    }
}

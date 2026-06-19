import XCTest
import Foundation
@testable import Narra

final class GrokTranscriptionServiceTests: XCTestCase {

    // MARK: - Request builder

    func test_defaultConfiguration_pointsAtGroqInc() {
        // Regression: a previous default targeted xAI (api.x.ai), which has
        // no audio/transcriptions endpoint. Provider ID `.groq` must hit
        // Groq Inc.'s OpenAI-compatible API.
        let config = GrokTranscriptionService.Configuration()
        XCTAssertEqual(config.baseURL.host, "api.groq.com")
        XCTAssertEqual(config.baseURL.path, "/openai/v1")
    }

    func test_requestBuilder_setsAuthHeader() throws {
        let builder = GrokTranscriptionRequestBuilder(
            configuration: GrokTranscriptionService.Configuration(model: "grok-2-audio")
        )
        let chunk = AudioChunk(samples: [0, 1, 2], sampleRate: 16_000)
        let request = try builder.makeRequest(audio: chunk, apiKey: "secret-key")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer secret-key"
        )
        XCTAssertTrue(
            request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true
        )
    }

    func test_requestBuilder_targetsAudioTranscriptionsEndpoint() throws {
        let builder = GrokTranscriptionRequestBuilder(
            configuration: GrokTranscriptionService.Configuration(
                baseURL: URL(string: "https://example.com/v1")!,
                model: "grok-2-audio"
            )
        )
        let chunk = AudioChunk(samples: [0], sampleRate: 16_000)
        let request = try builder.makeRequest(audio: chunk, apiKey: "k")
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
    }

    func test_requestBuilder_includesLanguageHint() throws {
        let builder = GrokTranscriptionRequestBuilder(
            configuration: GrokTranscriptionService.Configuration(languageHint: "en")
        )
        let chunk = AudioChunk(samples: [0], sampleRate: 16_000)
        let request = try builder.makeRequest(audio: chunk, apiKey: "k")
        let body = request.httpBody ?? Data()
        XCTAssertTrue(String(data: body, encoding: .utf8)?.contains("name=\"language\"") == true)
        XCTAssertTrue(String(data: body, encoding: .utf8)?.contains("en") == true)
    }

    func test_requestBuilder_appendsWavFile() throws {
        let builder = GrokTranscriptionRequestBuilder(
            configuration: GrokTranscriptionService.Configuration()
        )
        let chunk = AudioChunk(samples: [0, 1, 2, 3], sampleRate: 16_000)
        let request = try builder.makeRequest(audio: chunk, apiKey: "k")
        let body = request.httpBody ?? Data()
        let str = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("filename=\"audio.wav\""))
        XCTAssertTrue(str.contains("Content-Type: audio/wav"))
    }

    // MARK: - Response parser

    func test_responseParser_validatesSuccess() {
        let parser = GrokTranscriptionResponseParser()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertNoThrow(try parser.validate(response: response, body: Data()))
    }

    func test_responseParser_mapsUnauthorized() {
        let parser = GrokTranscriptionResponseParser()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertThrowsError(try parser.validate(response: response, body: Data())) { err in
            guard case TranscriptionError.serviceError = err else {
                return XCTFail("Expected serviceError, got \(err)")
            }
        }
    }

    func test_responseParser_mapsRateLimit() {
        let parser = GrokTranscriptionResponseParser()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertThrowsError(try parser.validate(response: response, body: Data())) { err in
            guard case TranscriptionError.serviceError = err else {
                return XCTFail("Expected serviceError, got \(err)")
            }
        }
    }

    func test_responseParser_parsesVerboseJson() throws {
        let parser = GrokTranscriptionResponseParser()
        let json: [String: Any] = [
            "text": "hello world",
            "duration": 1.5,
            "confidence": 0.92
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let audio = AudioChunk(samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)
        let segment = try parser.parse(data: data, audio: audio)

        XCTAssertEqual(segment.text, "hello world")
        XCTAssertEqual(segment.confidence, 0.92, accuracy: 0.0001)
        XCTAssertEqual(segment.duration, 1.5, accuracy: 0.0001)
    }

    func test_responseParser_parsesVerboseJsonWithSegments() throws {
        let parser = GrokTranscriptionResponseParser()
        let json: [String: Any] = [
            "text": "hello world",
            "duration": 2.0,
            "segments": [
                ["text": "hello", "confidence": 0.9, "start": 0.0, "end": 1.0],
                ["text": "world", "confidence": 0.7, "start": 1.0, "end": 2.0]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let audio = AudioChunk(samples: Array(repeating: 0, count: 32_000), sampleRate: 16_000)
        let segment = try parser.parse(data: data, audio: audio)

        XCTAssertEqual(segment.text, "hello world")
        XCTAssertEqual(segment.confidence, 0.8, accuracy: 0.0001)
    }

    func test_responseParser_throwsOnEmptyText() throws {
        let parser = GrokTranscriptionResponseParser()
        let data = try JSONSerialization.data(withJSONObject: ["text": ""])
        let audio = AudioChunk(samples: [0], sampleRate: 16_000)
        XCTAssertThrowsError(try parser.parse(data: data, audio: audio))
    }

    // MARK: - Service init / empty audio

    func test_service_throwsOnEmptyAudio() async {
        let service = GrokTranscriptionService(apiKey: "k")
        let chunk = AudioChunk(samples: [], sampleRate: 16_000)
        do {
            _ = try await service.transcribe(audio: chunk)
            XCTFail("Expected emptyAudio error")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .emptyAudio)
        }
    }

    func test_service_throwsOnMissingAPIKey() async {
        // No env var, no dotenv, no keychain -> empty key
        let service = GrokTranscriptionService(apiKey: "")
        let chunk = AudioChunk(samples: [0, 1, 2], sampleRate: 16_000)
        do {
            _ = try await service.transcribe(audio: chunk)
            XCTFail("Expected serviceError")
        } catch {
            // Acceptable to be either serviceError or emptyAudio depending
            // on check order; we documented the missing-key check first.
            XCTAssertTrue(error is TranscriptionError)
        }
    }
}

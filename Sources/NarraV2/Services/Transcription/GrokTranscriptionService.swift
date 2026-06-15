import Foundation

/// TranscriptionService implementation backed by the xAI (Grok) audio
/// transcription endpoint.
///
/// As of early 2026, xAI exposes batch audio transcription at
/// `POST /v1/audio/transcriptions`, mirroring OpenAI Whisper's API. There
/// is no native streaming STT endpoint, so this service implements the
/// batch `transcribe(audio:)` method and provides a `transcribe(stream:)`
/// implementation that buffers chunks into a rolling window and emits
/// results as the window slides. When xAI ships a true streaming STT
/// endpoint, the streaming path can be swapped without changing the
/// protocol.
public final class GrokTranscriptionService: TranscriptionService, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var timeout: TimeInterval
        public var languageHint: String?

        public init(
            baseURL: URL = URL(string: "https://api.x.ai/v1")!,
            model: String = "grok-2-audio",
            timeout: TimeInterval = 30,
            languageHint: String? = nil
        ) {
            self.baseURL = baseURL
            self.model = model
            self.timeout = timeout
            self.languageHint = languageHint
        }
    }

    // MARK: - Dependencies

    private let configuration: Configuration
    private let apiKey: String
    private let session: URLSession
    private let requestBuilder: GrokTranscriptionRequestBuilder
    private let responseParser: GrokTranscriptionResponseParser

    // MARK: - Init

    public init(
        configuration: Configuration = Configuration(),
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.apiKey = apiKey ?? GrokAPIKeySource.resolve() ?? ""
        self.session = session
        self.requestBuilder = GrokTranscriptionRequestBuilder(configuration: configuration)
        self.responseParser = GrokTranscriptionResponseParser()
    }

    // MARK: - TranscriptionService

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.serviceError("Missing GROK_API_KEY")
        }
        guard !audio.samples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let request = try requestBuilder.makeRequest(audio: audio, apiKey: apiKey)
        let (data, response) = try await send(request)
        try responseParser.validate(response: response, body: data)
        return try responseParser.parse(data: data, audio: audio)
    }

    public func transcribe(
        stream: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptSegment, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var accumulator: [Int16] = []
                let minSamples = 16_000 * 2 // 2 seconds of 16 kHz audio
                let maxSamples = 16_000 * 30 // 30 seconds upper bound
                let startTime = Date()

                for await chunk in stream {
                    accumulator.append(contentsOf: chunk.samples)
                    while accumulator.count >= minSamples {
                        let windowSize = min(accumulator.count, maxSamples)
                        let windowSamples = Array(accumulator.suffix(windowSize))
                        let window = AudioChunk(
                            samples: windowSamples,
                            sampleRate: chunk.sampleRate,
                            startTime: chunk.startTime
                        )
                        do {
                            let segment = try await self.transcribe(audio: window)
                            continuation.yield(segment)
                        } catch {
                            // Surface the error but keep listening so a
                            // transient failure does not abort the stream.
                            continuation.finish(throwing: error)
                            return
                        }
                        // Drop everything we just emitted, plus the
                        // 0.5s of audio before it to give the model
                        // overlap context for the next window.
                        let dropCount = max(0, windowSamples.count - 8_000)
                        if dropCount >= accumulator.count {
                            accumulator.removeAll(keepingCapacity: true)
                        } else {
                            accumulator.removeFirst(dropCount)
                        }
                        if Task.isCancelled { break }
                    }
                }
                if !accumulator.isEmpty {
                    let window = AudioChunk(
                        samples: accumulator,
                        sampleRate: 16_000,
                        startTime: startTime
                    )
                    do {
                        let segment = try await self.transcribe(audio: window)
                        continuation.yield(segment)
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
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
                    cont.resume(throwing: TranscriptionError.serviceError("No response"))
                    return
                }
                cont.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

// MARK: - Request builder

/// Builds the multipart/form-data body for a Grok transcription request.
///
/// Exposed as an internal type so tests can exercise the body
/// construction without hitting the network.
struct GrokTranscriptionRequestBuilder {

    let configuration: GrokTranscriptionService.Configuration

    func makeRequest(audio: AudioChunk, apiKey: String) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.timeout

        let wavData = WAVEncoder.encode(
            samples: audio.samples,
            sampleRate: audio.sampleRate
        )
        let body = try MultipartFormDataBuilder.build(
            boundary: "narrav2-\(UUID().uuidString)",
            fields: [
                .file(
                    name: "file",
                    filename: "audio.wav",
                    contentType: "audio/wav",
                    data: wavData
                ),
                .text(name: "model", value: configuration.model),
                .text(name: "response_format", value: "verbose_json"),
            ] + (configuration.languageHint.map { hint in
                [.text(name: "language", value: hint)] as [MultipartFormDataBuilder.Field]
            } ?? [])
        )
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data
        return request
    }
}

// MARK: - Response parser

/// Parses the verbose_json response from the Grok STT endpoint into a
/// `TranscriptSegment`. Exposed for testability.
struct GrokTranscriptionResponseParser {

    func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.serviceError("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw TranscriptionError.serviceError("Unauthorized (\(http.statusCode))")
        case 429:
            throw TranscriptionError.serviceError("Rate limited")
        case 408, 504:
            throw TranscriptionError.serviceError("Timeout")
        default:
            let snippet = String(data: body.prefix(256), encoding: .utf8) ?? ""
            throw TranscriptionError.serviceError("HTTP \(http.statusCode): \(snippet)")
        }
    }

    func parse(data: Data, audio: AudioChunk) throws -> TranscriptSegment {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.serviceError("Invalid JSON response")
        }
        let text = (json["text"] as? String)
            ?? (json["transcript"] as? String)
            ?? ""
        if text.isEmpty {
            throw TranscriptionError.serviceError("Empty transcription result")
        }
        let duration = (json["duration"] as? Double) ?? audio.duration
        let startTime = audio.startTime ?? Date()
        let endTime = startTime.addingTimeInterval(duration)
        let segments = json["segments"] as? [[String: Any]]
        let confidence: Double = {
            if let avg = json["confidence"] as? Double { return avg }
            if let segs = segments, !segs.isEmpty {
                let confs = segs.compactMap { $0["confidence"] as? Double }
                if !confs.isEmpty { return confs.reduce(0, +) / Double(confs.count) }
            }
            return 1.0
        }()
        return TranscriptSegment(
            text: text,
            startTime: startTime,
            endTime: endTime,
            confidence: confidence
        )
    }
}

import Foundation

/// Deepgram `/v1/listen` raw-audio batch endpoint.
public final class DeepgramTranscriptionService: TranscriptionService, @unchecked Sendable {

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var timeout: TimeInterval
        public var languageHint: String?

        public init(
            baseURL: URL = URL(string: "https://api.deepgram.com/v1")!,
            model: String = "nova-3",
            timeout: TimeInterval = 30,
            languageHint: String? = nil
        ) {
            self.baseURL = baseURL
            self.model = model
            self.timeout = timeout
            self.languageHint = languageHint
        }
    }

    private let configuration: Configuration
    private let apiKey: String
    private let session: URLSession

    public init(
        configuration: Configuration = Configuration(),
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.apiKey = apiKey ?? KeychainService.load(for: .deepgram) ?? ""
        self.session = session
    }

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.serviceError("Missing Deepgram API key")
        }
        guard !audio.samples.isEmpty else { throw TranscriptionError.emptyAudio }

        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent("listen"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "model", value: configuration.model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]
        if let hint = configuration.languageHint {
            items.append(URLQueryItem(name: "language", value: hint))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = configuration.timeout
        request.httpBody = WAVEncoder.encode(samples: audio.samples, sampleRate: audio.sampleRate)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.serviceError("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(256), encoding: .utf8) ?? ""
            throw TranscriptionError.serviceError("Deepgram HTTP \(http.statusCode): \(snippet)")
        }

        // Response shape: results.channels[0].alternatives[0].transcript
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = json?["results"] as? [String: Any]
        let channels = results?["channels"] as? [[String: Any]]
        let alts = channels?.first?["alternatives"] as? [[String: Any]]
        let alt = alts?.first
        let text = (alt?["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            throw TranscriptionError.serviceError("Empty transcription result")
        }
        let confidence = (alt?["confidence"] as? Double) ?? 1.0
        let now = audio.startTime ?? Date()
        return TranscriptSegment(
            text: text,
            startTime: now,
            endTime: now.addingTimeInterval(audio.duration),
            confidence: confidence
        )
    }

    public func transcribe(stream: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptSegment, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for await chunk in stream {
                    do {
                        let segment = try await self.transcribe(audio: chunk)
                        continuation.yield(segment)
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

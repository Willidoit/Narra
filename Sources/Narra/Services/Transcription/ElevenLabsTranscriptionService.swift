import Foundation

/// ElevenLabs `/v1/speech-to-text` (Scribe) endpoint.
public final class ElevenLabsTranscriptionService: TranscriptionService, @unchecked Sendable {

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var timeout: TimeInterval
        public var languageHint: String?

        public init(
            baseURL: URL = URL(string: "https://api.elevenlabs.io/v1")!,
            model: String = "scribe_v1",
            timeout: TimeInterval = 60,
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
        self.apiKey = apiKey ?? KeychainService.load(for: .elevenLabs) ?? ""
        self.session = session
    }

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.serviceError("Missing ElevenLabs API key")
        }
        guard !audio.samples.isEmpty else { throw TranscriptionError.emptyAudio }

        let url = configuration.baseURL.appendingPathComponent("speech-to-text")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.timeout

        let wavData = WAVEncoder.encode(samples: audio.samples, sampleRate: audio.sampleRate)
        var fields: [MultipartFormDataBuilder.Field] = [
            .file(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wavData),
            .text(name: "model_id", value: configuration.model),
        ]
        if let hint = configuration.languageHint {
            fields.append(.text(name: "language_code", value: hint))
        }
        let body = try MultipartFormDataBuilder.build(
            boundary: "narrav2-\(UUID().uuidString)",
            fields: fields
        )
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.serviceError("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(256), encoding: .utf8) ?? ""
            throw TranscriptionError.serviceError("ElevenLabs HTTP \(http.statusCode): \(snippet)")
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = (json?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            throw TranscriptionError.serviceError("Empty transcription result")
        }
        let now = audio.startTime ?? Date()
        return TranscriptSegment(
            text: text,
            startTime: now,
            endTime: now.addingTimeInterval(audio.duration),
            confidence: 1.0
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

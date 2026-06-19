import Foundation
import Speech
import AVFoundation

/// On-device transcription via `SFSpeechRecognizer`. Free, ships with the OS.
/// Quality is the OS dictation engine — lower than Whisper but no key, no download.
public final class AppleSpeechTranscriptionService: TranscriptionService, @unchecked Sendable {

    public struct Configuration: Sendable {
        public var localeIdentifier: String

        public init(localeIdentifier: String = "en-US") {
            self.localeIdentifier = localeIdentifier
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func transcribe(audio: AudioChunk) async throws -> TranscriptSegment {
        guard !audio.samples.isEmpty else { throw TranscriptionError.emptyAudio }

        let authorized = await Self.requestAuthorization()
        guard authorized else { throw TranscriptionError.permissionDenied }

        let locale = Locale(identifier: configuration.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.serviceError(
                "Apple Speech recognizer unavailable for \(configuration.localeIdentifier)"
            )
        }
        // On-device required so audio never leaves the machine, matching the
        // user's expectation for a "local" provider.
        let supportsOnDevice = recognizer.supportsOnDeviceRecognition

        let wavData = WAVEncoder.encode(samples: audio.samples, sampleRate: audio.sampleRate)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("narra-apple-\(UUID().uuidString).wav")
        try wavData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let request = SFSpeechURLRecognitionRequest(url: tmpURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = supportsOnDevice

        let text: String = try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    cont.resume(throwing: TranscriptionError.serviceError(error.localizedDescription))
                    return
                }
                guard let result = result, result.isFinal else { return }
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw TranscriptionError.serviceError("Empty transcription result")
        }
        let now = audio.startTime ?? Date()
        return TranscriptSegment(
            text: trimmed,
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

    private static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }
}

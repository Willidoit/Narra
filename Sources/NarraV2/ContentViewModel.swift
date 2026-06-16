import Foundation
import AVFoundation

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var transcriptText = "Transcription will appear here..."
    @Published var statusText = "Ready"
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 40)
    @Published var errorMessage: String?

    private let orchestrator = ServiceOrchestrator()
    private let captureManager = AudioCaptureManager()
    private var captureTask: Task<Void, Never>?

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        isRecording = true
        statusText = "Recording"
        errorMessage = nil
        captureTask = Task {
            do {
                try await captureManager.start()
            } catch {
                errorMessage = error.localizedDescription
                isRecording = false
                statusText = "Ready"
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                let level = captureManager.lastLevel
                audioLevels.removeFirst()
                audioLevels.append(min(1.0, level * 3))  // boost for visibility
            }
        }
    }

    func stopRecording() {
        captureTask?.cancel()
        captureTask = nil
        isRecording = false
        statusText = "Transcribing..."
        audioLevels = Array(repeating: 0, count: 40)

        Task {
            let chunk = captureManager.stop()
            do {
                let segment = try await orchestrator.transcribeWithFallback(chunk)
                let processed = try await orchestrator.processWithFallback(segment)
                if transcriptText == "Transcription will appear here..." {
                    transcriptText = processed.text
                } else {
                    transcriptText += "\n" + processed.text
                }
                statusText = "Ready"
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Ready"
            }
        }
    }
}

import Foundation
import AVFoundation
import AppKit
import CoreGraphics

@MainActor
final class ContentViewModel: ObservableObject {

    enum UIMode: Equatable {
        case hidden, home, recording, processing, reviewing
    }

    private enum CaptureMode { case pushToTalk, toggle }

    @Published var uiMode: UIMode = .hidden
    @Published var transcriptText = ""
    @Published var lastTranscript = ""
    @Published var statusText = "Ready"
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 40)
    @Published var errorMessage: String?
    @Published var pipelineText: String = ""

    var isRecording: Bool { uiMode == .recording }

    private var currentMode: CaptureMode = .pushToTalk
    private let orchestrator = AppServices.shared.orchestrator
    private let captureManager = AudioCaptureManager()
    private var captureTask: Task<Void, Never>?

    // MARK: - Hotkey entry points

    func startPushToTalk() {
        currentMode = .pushToTalk
        startRecording()
    }

    func stopPushToTalk() {
        guard uiMode == .recording else { return }
        finishRecording(autoPaste: true)
    }

    func handleToggleHotkey() {
        switch uiMode {
        case .recording:
            finishRecording(autoPaste: false)
        case .hidden, .home:
            currentMode = .toggle
            startRecording()
        case .processing, .reviewing:
            // Ignore: user must finish reviewing first.
            break
        }
    }

    // MARK: - UI actions

    func showHome() {
        if uiMode == .recording || uiMode == .processing { return }
        uiMode = .home
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideHome() {
        if uiMode == .home { uiMode = .hidden }
    }

    func acceptReview() {
        guard uiMode == .reviewing else { return }
        let text = transcriptText
        uiMode = .hidden
        Task { await Self.pasteToFrontmostApp(text: text) }
    }

    func cancelReview() {
        guard uiMode == .reviewing else { return }
        transcriptText = ""
        uiMode = .hidden
    }

    func pasteLastTranscription() {
        guard !lastTranscript.isEmpty else { return }
        let text = lastTranscript
        Task { await Self.pasteToFrontmostApp(text: text) }
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        guard uiMode != .recording, uiMode != .processing else { return }
        uiMode = .recording
        statusText = "Recording"
        errorMessage = nil
        captureTask = Task {
            do {
                try await captureManager.start()
            } catch {
                errorMessage = error.localizedDescription
                uiMode = .hidden
                statusText = "Ready"
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                let level = captureManager.lastLevel
                audioLevels.removeFirst()
                audioLevels.append(min(1.0, level * 3))
            }
        }
    }

    private func finishRecording(autoPaste: Bool) {
        captureTask?.cancel()
        captureTask = nil
        uiMode = .processing
        statusText = "Transcribing..."
        audioLevels = Array(repeating: 0, count: 40)

        Task {
            let chunk = captureManager.stop()
            do {
                let level = AppSettings.shared.cleanupLevel
                let segment = try await orchestrator.transcribeWithFallback(chunk)
                let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    statusText = "Ready"
                    uiMode = .hidden
                    return
                }
                let processed = try await orchestrator.processWithFallback(segment, level: level)
                transcriptText = processed.text
                lastTranscript = processed.text
                pipelineText = "Whisper (local) · \(processed.usedCloud ? "Groq" : "Local cleanup")"
                statusText = "Ready"
                if autoPaste {
                    uiMode = .hidden
                    await Self.pasteToFrontmostApp(text: processed.text)
                } else {
                    uiMode = .reviewing
                }
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Ready"
                uiMode = .hidden
            }
        }
    }

    // MARK: - Paste helper

    /// Copies `text` to the system pasteboard and posts a synthetic Cmd+V to
    /// the frontmost app. Needs Accessibility permission for the keystroke;
    /// the clipboard half always succeeds so the user can paste manually.
    private static func pasteToFrontmostApp(text: String) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Give the OS time to retire our key window and restore the
        // previous frontmost app, so Cmd+V lands in the right process.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

import Foundation
import AVFoundation
import AppKit
import CoreGraphics

@MainActor
final class ContentViewModel: ObservableObject {

    // Single instance shared across the main window, HUD window, and menu bar
    // bridge so all three observe the same state.
    static let shared = ContentViewModel()

    enum UIMode: Equatable {
        case hidden, recording, processing, reviewing
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
    /// Drains the live `chunkStream` through Whisper while recording so
    /// transcription overlaps with speech. Result is the partial segments
    /// collected up to stop time.
    private var streamingTask: Task<[TranscriptSegment], Error>?
    /// Per-recording live cleanup engine. Created on start, flushed on stop.
    private var streamingProcessor: StreamingPostProcessor?
    /// Wall-clock time the recording began, for SmartContext length escalation.
    private var recordingStartTime: Date?
    /// Frontmost bundle ID at start time, captured before we steal focus, so
    /// SmartContext can detect code-editor recordings.
    private var recordingFrontmostBundleID: String?
    /// Set true as soon as the capture loop sees a level above the speech
    /// threshold. Used to drop empty takes on release.
    private var heardSpeech: Bool = false

    // MARK: - Hotkey entry points

    func startPushToTalk() {
        // Re-pressing the trigger key while a recording is in flight
        // cancels and discards it.
        if uiMode == .recording || uiMode == .processing {
            cancelRecording()
            return
        }
        currentMode = .pushToTalk
        startRecording()
    }

    func stopPushToTalk() {
        guard uiMode == .recording else { return }
        if !heardSpeech {
            cancelRecording()
            return
        }
        finishRecording(autoPaste: true)
    }

    func handleToggleHotkey() {
        switch uiMode {
        case .recording:
            // Second tap stops the take. Drop it if it was silent;
            // otherwise hand off to review.
            if !heardSpeech {
                cancelRecording()
            } else {
                finishRecording(autoPaste: false)
            }
        case .processing:
            cancelRecording()
        case .hidden:
            currentMode = .toggle
            startRecording()
        case .reviewing:
            break
        }
    }

    // MARK: - UI actions

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
        heardSpeech = false
        recordingStartTime = Date()
        recordingFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if AppSettings.shared.muteOutputWhenRecording {
            SystemOutput.muteForRecording()
        }
        // Stand up a live cleanup engine for this take. Filter passes run
        // synchronously per sentence, so paste-on-stop barely waits.
        let mode = AppSettings.shared.orchestratorMode
        let useCloud = (mode != .localOnly)
        let processor = StreamingPostProcessor(
            configuration: .init(
                cloudProcessor: orchestrator.cloudProcessor,
                localProcessor: orchestrator.localProcessor,
                useCloud: useCloud,
                startTime: recordingStartTime ?? Date(),
                smartFillerThreshold: AppSettings.shared.smartFillerThreshold
            )
        )
        streamingProcessor = processor

        // Wire the streaming consumer BEFORE start() so the tap's first
        // samples have somewhere to go.
        let chunkStream = captureManager.chunkStream()
        let segmentStream = orchestrator.transcribeStream(chunkStream)
        streamingTask = Task {
            var collected: [TranscriptSegment] = []
            for try await segment in segmentStream {
                collected.append(segment)
                await processor.feed(segment: segment)
            }
            return collected
        }
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.captureManager.start()
            } catch {
                self.errorMessage = error.localizedDescription
                self.uiMode = .hidden
                self.statusText = "Ready"
                return
            }
            // ponytail: 0.05 RMS clears typical room/fan noise (~0.01-0.03)
            // and trips on normal indoor speech (~0.08+). Flag is read on
            // release (`stopPushToTalk` / `handleToggleHotkey`) to drop
            // empty takes.
            let silenceThreshold: Float = 0.05
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                let level = self.captureManager.lastLevel
                if level > silenceThreshold { self.heardSpeech = true }
                self.audioLevels.removeFirst()
                self.audioLevels.append(min(1.0, level * 3))
            }
        }
    }

    /// Aborts the active recording (or in-flight processing) and returns to
    /// the idle state. Drops any captured audio and restores muted output.
    private func cancelRecording() {
        captureTask?.cancel()
        captureTask = nil
        _ = captureManager.stop()
        streamingTask?.cancel()
        streamingTask = nil
        streamingProcessor = nil
        recordingStartTime = nil
        recordingFrontmostBundleID = nil
        SystemOutput.restore()
        audioLevels = Array(repeating: 0, count: 40)
        statusText = "Ready"
        uiMode = .hidden
    }

    private func finishRecording(autoPaste: Bool) {
        captureTask?.cancel()
        captureTask = nil
        uiMode = .processing
        statusText = "Transcribing..."
        audioLevels = Array(repeating: 0, count: 40)
        SystemOutput.restore()

        let pendingStream = streamingTask
        streamingTask = nil
        let activeProcessor = streamingProcessor
        streamingProcessor = nil
        let startedAt = recordingStartTime
        let frontmost = recordingFrontmostBundleID
        recordingStartTime = nil
        recordingFrontmostBundleID = nil
        Task {
            // Stops the engine and finishes the chunk stream (tail emitted
            // through it). The returned chunk is unused while streaming —
            // the rolling buffer overlaps with already-emitted windows.
            _ = captureManager.stop()
            do {
                let userLevel = AppSettings.shared.cleanupLevel
                let segments = (try await pendingStream?.value) ?? []
                let combinedText = segments
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if combinedText.isEmpty {
                    statusText = "Ready"
                    uiMode = .hidden
                    return
                }
                let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
                let effectiveLevel: CleanupLevel
                if AppSettings.shared.postProcessingEnabled {
                    effectiveLevel = SmartContext.effectiveLevel(
                        userLevel: userLevel,
                        durationSeconds: duration,
                        settings: AppSettings.shared,
                        frontmost: frontmost
                    )
                } else {
                    effectiveLevel = .none
                }

                let processed: ProcessedTranscript
                if !AppSettings.shared.postProcessingEnabled || effectiveLevel == .none {
                    // Cleanup disabled or smart-skipped (e.g. code editor) —
                    // paste the raw combined transcript.
                    let start = segments.first?.startTime ?? Date()
                    let end = segments.last?.endTime ?? start
                    let conf = segments.map { $0.confidence }.min() ?? 1.0
                    processed = ProcessedTranscript(
                        text: combinedText,
                        startTime: start,
                        endTime: end,
                        sourceSegmentIDs: segments.map(\.id),
                        confidence: conf,
                        usedCloud: false
                    )
                } else if let processor = activeProcessor {
                    statusText = "Cleaning..."
                    processed = await processor.flush(level: effectiveLevel)
                } else {
                    // Fallback (no processor — shouldn't happen for normal
                    // recordings, but startRecording could be re-entered).
                    let start = segments.first?.startTime ?? Date()
                    let end = segments.last?.endTime ?? start
                    let conf = segments.map { $0.confidence }.min() ?? 1.0
                    let segment = TranscriptSegment(
                        text: combinedText,
                        startTime: start,
                        endTime: end,
                        confidence: conf
                    )
                    processed = try await orchestrator.processWithFallback(segment, level: effectiveLevel)
                }
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

    /// Pastes `text` into the frontmost app via synthetic Cmd+V, then restores
    /// whatever was on the clipboard before. Needs Accessibility permission
    /// for the keystroke; the clipboard half always succeeds so the user can
    /// paste manually if the keystroke is blocked.
    private static func pasteToFrontmostApp(text: String) async {
        let pb = NSPasteboard.general
        // Snapshot existing items so we can put them back.
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        pb.clearContents()
        pb.setString(text, forType: .string)

        // Give the OS time to retire our key window and restore the
        // previous frontmost app, so Cmd+V lands in the right process.
        // ponytail: 80ms covers normal cases on macOS 14+; bump back to
        // 200ms if users report mis-targeted pastes.
        try? await Task.sleep(nanoseconds: 80_000_000)
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Restore the user's prior clipboard. uiMode is already .hidden at
        // this point so this delay does not affect perceived speed.
        // ponytail: 300ms covers fast targets; raise if restore lands
        // before the destination app finishes reading the pasteboard.
        try? await Task.sleep(nanoseconds: 300_000_000)
        pb.clearContents()
        if !saved.isEmpty {
            pb.writeObjects(saved)
        }
    }
}

// MARK: - System output muting

/// Mutes the system default output via `osascript`. ponytail: Core Audio's
/// per-device volume property is unsupported on AirPods / many BT outputs;
/// `set volume output muted` is the one path that works on every device
/// because AppleScript's StandardAdditions routes through the same control
/// the menu-bar volume icon uses.
@MainActor
private enum SystemOutput {
    private static var didMute = false

    static func muteForRecording() {
        guard !didMute else { return }
        run("set volume output muted true")
        didMute = true
    }

    static func restore() {
        guard didMute else { return }
        run("set volume output muted false")
        didMute = false
    }

    private static func run(_ script: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }
}

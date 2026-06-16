import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var showInputMonitoringAlert = false

    var body: some View {
        Group {
            switch viewModel.uiMode {
            case .hidden:
                Color.clear.frame(width: 1, height: 1)
            case .home:
                homeBody
            case .recording:
                recordingPill
            case .processing:
                processingPill
            case .reviewing:
                reviewPill
            }
        }
        .background(WindowBehavior(mode: viewModel.uiMode))
        .task {
            MenuBarShared.viewModel = viewModel
            KeybindingManager.shared.onPushToTalkStart = { viewModel.startPushToTalk() }
            KeybindingManager.shared.onPushToTalkStop  = { viewModel.stopPushToTalk() }
            KeybindingManager.shared.onPushToToggle    = { viewModel.handleToggleHotkey() }
            KeybindingManager.shared.start()
            if !KeybindingManager.shared.hasInputMonitoringAccess {
                showInputMonitoringAlert = true
            }
        }
        .alert("Input Monitoring Required", isPresented: $showInputMonitoringAlert) {
            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                )
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Narra needs Input Monitoring to use fn key shortcuts. Enable it in System Settings → Privacy & Security → Input Monitoring.")
        }
    }

    // MARK: - Recording pill (active capture)

    private var recordingPill: some View {
        pillContainer {
            Image(systemName: "mic.fill").foregroundStyle(.red)
            WaveformView(levels: viewModel.audioLevels)
                .frame(width: 80, height: 28)
            Spacer()
            pillButton(title: "Stop", color: .red, action: viewModel.stopPushToTalk)
        }
    }

    // MARK: - Processing pill (transcribing)

    private var processingPill: some View {
        pillContainer {
            ProgressView().controlSize(.small)
            Text("Transcribing…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if !viewModel.pipelineText.isEmpty {
                Text(viewModel.pipelineText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Review pill (toggle mode: accept or discard)

    private var reviewPill: some View {
        pillContainer {
            Button(action: viewModel.cancelReview) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard transcription")

            Text(viewModel.transcriptText)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: viewModel.acceptReview) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.green))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paste transcription")
        }
    }

    // MARK: - Home (menu-bar Home button)

    private var homeBody: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Narra")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: viewModel.hideHome) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            LiquidGlassView(cornerRadius: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(viewModel.lastTranscript.isEmpty
                             ? "No transcription yet. Hold fn to record."
                             : viewModel.lastTranscript)
                            .font(.body)
                            .foregroundStyle(viewModel.lastTranscript.isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.pasteLastTranscription()
                } label: {
                    Label("Paste Last", systemImage: "doc.on.clipboard")
                }
                .disabled(viewModel.lastTranscript.isEmpty)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }

                Spacer()
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(width: 420, height: 320)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 18)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            } else {
                RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial)
            }
        }
        .padding(10)
    }

    // MARK: - Pill chrome

    @ViewBuilder
    private func pillContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(width: 296, height: 56)
            .background {
                if #available(macOS 26.0, *) {
                    Capsule().glassEffect(.regular, in: Capsule())
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
    }

    private func pillButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Behavior

/// Sizes / positions / hides the single shared window based on `uiMode`.
private struct WindowBehavior: NSViewRepresentable {
    let mode: ContentViewModel.UIMode

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let screen = NSScreen.main ?? NSScreen.screens[0]
            switch mode {
            case .hidden:
                window.orderOut(nil)
            case .home:
                let w: CGFloat = 440, h: CGFloat = 340
                let x = screen.visibleFrame.midX - w / 2
                let y = screen.visibleFrame.midY - h / 2
                window.level = .normal
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: true)
                window.makeKeyAndOrderFront(nil)
            case .recording, .processing, .reviewing:
                let w: CGFloat = 296, h: CGFloat = 56
                let x = screen.visibleFrame.midX - w / 2
                let y = screen.visibleFrame.minY + 40
                window.level = .floating
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: true)
                window.orderFront(nil)
            }
        }
    }
}

// MARK: - Menu bar bridge

/// Holds a weak reference to the active `ContentViewModel` so the
/// menu bar extra (which lives in the App scene, separate from
/// `ContentView`) can drive it. Populated in `ContentView.task`.
@MainActor
enum MenuBarShared {
    static weak var viewModel: ContentViewModel?
}

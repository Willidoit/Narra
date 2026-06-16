import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var isShowingSettings = false
    @State private var copied = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            VStack(spacing: 0) {
                // MARK: Header
                HStack {
                    StatusIndicator(status: viewModel.statusText)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Status: \(viewModel.statusText)")

                    Spacer()

                    Button(action: copyTranscript) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(copied ? "Copied!" : "Copy transcript")
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                    Button(action: viewModel.toggleRecording) {
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundStyle(viewModel.isRecording ? Color.red : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
                    .keyboardShortcut("r", modifiers: .command)

                    Button(action: { isShowingSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Settings")
                    .keyboardShortcut(",")
                }
                .padding(.horizontal)
                .padding(.top, 16)

                Divider()
                    .background(.white.opacity(0.2))
                    .padding(.horizontal)

                // MARK: Transcription Area
                ScrollView {
                    Text(viewModel.transcriptText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                        .padding()
                }
                .padding()
                .background {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 16)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.thinMaterial)
                    }
                }
                .padding(.horizontal)

                // MARK: Waveform
                if viewModel.isRecording {
                    WaveformView(levels: viewModel.audioLevels)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                // MARK: Error Banner
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                Spacer()
            }
            .padding(.bottom, 16)

            // MARK: Settings Panel (overlay)
            if isShowingSettings {
                SettingsPanel(isPresented: $isShowingSettings)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(WindowAccessor.configure())
        .frame(minWidth: 500, minHeight: 300)
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.transcriptText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status == "Ready" ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(status)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Settings Panel

struct SettingsPanel: View {
    @Binding var isPresented: Bool
    @State private var apiKeyDraft = ""
    @State private var keySaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Settings")
                .keyboardShortcut(.escape)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("xAI API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Paste your API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        try? KeychainService.save(key: apiKeyDraft)
                        keySaved = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            keySaved = false
                        }
                    }
                    .disabled(apiKeyDraft.isEmpty)
                    if keySaved {
                        Text("Key saved ✓")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Divider()

            Group {
                Text("Speech Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Whisper Base (local)")
                    .font(.body)

                Text("Language Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Llama 3.2 1B (local)")
                    .font(.body)

                Text("Shortcuts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⌘R – Start / Stop recording")
                    .font(.body)
                Text("⌘⇧C – Copy transcript")
                    .font(.body)
            }

            Spacer()
        }
        .padding()
        .frame(width: 280, height: 380)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 20)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(radius: 10)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            apiKeyDraft = GrokAPIKeySource.resolve() ?? ""
        }
    }
}

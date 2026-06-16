import SwiftUI
import AppKit

// MARK: - Settings Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            PostProcessingSettingsTab()
                .tabItem { Label("Post-Processing", systemImage: "wand.and.stars") }
            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiKeyDraft = ""
    @State private var keySaved = false

    var body: some View {
        Form {
            Section("API Key") {
                SecureField("Paste your Groq API key", text: $apiKeyDraft)
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
                        Text("Key saved ✓").foregroundStyle(.green)
                    }
                }
            }
            Section("Service Mode") {
                Picker("Mode", selection: $settings.orchestratorMode) {
                    Text("Automatic").tag(ServiceOrchestrator.Mode.automatic)
                    Text("Cloud only (Groq)").tag(ServiceOrchestrator.Mode.cloudOnly)
                    Text("Local only (Whisper)").tag(ServiceOrchestrator.Mode.localOnly)
                }
                .pickerStyle(.segmented)
                Text("Takes effect on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Models") {
                LabeledContent("Speech Model", value: "Whisper Base (local)")
                LabeledContent("Language Model", value: "Llama 3.2 1B (local)")
            }
        }
        .formStyle(.grouped)
        .onAppear { apiKeyDraft = GrokAPIKeySource.resolve() ?? "" }
    }
}

// MARK: - Post-Processing Tab

private struct PostProcessingSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Auto-cleanup applies to all dictations. The raw transcript is always preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(spacing: 12) {
                ForEach(CleanupLevel.allCases) { level in
                    CleanupLevelCard(level: level, isSelected: settings.cleanupLevel == level)
                        .onTapGesture { settings.cleanupLevel = level }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CleanupLevelCard: View {
    let level: CleanupLevel
    let isSelected: Bool

    var body: some View {
        LiquidGlassView(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(level.title)
                    .font(.headline)
                Text(level.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(level.example)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.purple.opacity(0.8))
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Shortcuts Tab

private struct ShortcutsSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            if !KeybindingManager.shared.hasInputMonitoringAccess {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Narra needs Input Monitoring access for global shortcuts.")
                        Spacer()
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                    }
                }
            }

            Section("Global Shortcuts") {
                LabeledContent("Push-to-Talk (hold)") {
                    KeyRecorderView(binding: $settings.pushToTalkBinding)
                        .frame(width: 140, height: 28)
                }
                LabeledContent("Push-to-Toggle (press)") {
                    KeyRecorderView(binding: $settings.pushToToggleBinding)
                        .frame(width: 140, height: 28)
                }
            }

            Section("Local Shortcuts") {
                LabeledContent("Copy transcript", value: "⌘⇧C")
            }
        }
        .formStyle(.grouped)
    }
}

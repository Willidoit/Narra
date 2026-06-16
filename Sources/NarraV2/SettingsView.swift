import SwiftUI

struct SettingsView: View {

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            CleanupTab()
                .tabItem { Label("Cleanup", systemImage: "sparkles") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiKeyDraft: String = ""
    @State private var keyStatus: Bool = AppSettings.shared.grokAPIKeyStatus

    var body: some View {
        Form {
            Section("Service Mode") {
                Picker("Selection", selection: $settings.orchestratorMode) {
                    Text("Automatic").tag(ServiceOrchestrator.Mode.automatic)
                    Text("Cloud only").tag(ServiceOrchestrator.Mode.cloudOnly)
                    Text("Local only").tag(ServiceOrchestrator.Mode.localOnly)
                }
                .pickerStyle(.segmented)
            }

            Section("Grok API Key") {
                SecureField("xai-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveKey)
                HStack {
                    Button("Save Key", action: saveKey)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    Text("API Key Status: \(keyStatus ? "Connected ✓" : "Not Set")")
                        .font(.caption)
                        .foregroundStyle(keyStatus ? .green : .secondary)
                }
            }
        }
        .padding(20)
    }

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? KeychainService.save(key: trimmed)
        apiKeyDraft = ""
        keyStatus = AppSettings.shared.grokAPIKeyStatus
    }
}

// MARK: - Cleanup

private struct CleanupTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cleanup Level")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(CleanupLevel.allCases, id: \.self) { level in
                    cleanupCard(for: level)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func cleanupCard(for level: CleanupLevel) -> some View {
        let isSelected = settings.cleanupLevel == level
        LiquidGlassView(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: level))
                    .font(.body.weight(.semibold))
                Text(description(for: level))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { settings.cleanupLevel = level }
    }

    private func title(for level: CleanupLevel) -> String {
        switch level {
        case .none: return "None"
        case .light: return "Light"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    private func description(for level: CleanupLevel) -> String {
        switch level {
        case .none: return "Pass through exactly as transcribed."
        case .light: return "Strip filler words and fix obvious grammar only."
        case .medium: return "Remove fillers, resolve self-corrections, merge restatements."
        case .high: return "Condense aggressively. Keep only the core information."
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Narra")
                .font(.title.weight(.semibold))
            Text("Voice-to-text for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

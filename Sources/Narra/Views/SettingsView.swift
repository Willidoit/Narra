import SwiftUI
import AppKit

// MARK: - Settings Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            PostProcessingSettingsTab()
                .tabItem { Label("Cleanup", systemImage: "wand.and.stars") }
            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 600, height: 500)
        .background(Palette.canvas.ignoresSafeArea())
    }
}

// MARK: - Shared chrome

private struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                content()
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.canvas)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EditorialSectionLabel(text: title)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
            }
            GlassCard(padding: Spacing.lg, radius: CornerRadius.xl) {
                content()
            }
        }
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiKeyDraft = ""
    @State private var storedKey: String? = KeychainService.load(for: .groq)
    @State private var keySaved = false
    @State private var isValidating = false
    @State private var validationOK: Bool? = nil
    @State private var validationError: String? = nil

    private var draftMatchesStored: Bool {
        guard let stored = storedKey, !apiKeyDraft.isEmpty else { return false }
        return stored == apiKeyDraft
    }

    var body: some View {
        SettingsScroll {
            SettingsSection(title: "API Key",
                            subtitle: "Stored in macOS Keychain. Used for cloud post-processing only.") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SecureField("Paste your Groq API key", text: $apiKeyDraft)
                        .textFieldStyle(.plain)
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .onChange(of: apiKeyDraft) { _, _ in
                            // Editing invalidates any previous validation result.
                            validationOK = nil
                            validationError = nil
                        }
                    HStack(spacing: Spacing.sm) {
                        if draftMatchesStored {
                            Button(action: validate) {
                                HStack(spacing: 6) {
                                    if isValidating {
                                        ProgressView()
                                            .progressViewStyle(.linear)
                                            .frame(width: 32)
                                    } else {
                                        Image(systemName: "checkmark.seal")
                                    }
                                    Text(isValidating ? "Validating…" : "Validate")
                                }
                                .font(Typography.sans(12, .medium))
                                .foregroundStyle(Palette.canvas)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                        .fill(Palette.ink)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isValidating)
                        } else {
                            Button(action: saveKey) {
                                Label("Save Key", systemImage: "key.fill")
                                    .font(Typography.sans(12, .medium))
                                    .foregroundStyle(Palette.canvas)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                            .fill(Palette.ink)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(apiKeyDraft.isEmpty)
                            .opacity(apiKeyDraft.isEmpty ? 0.4 : 1)
                        }

                        if keySaved {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Saved")
                            }
                            .font(Typography.sans(11, .semibold))
                            .foregroundStyle(Palette.greenInk)
                            .transition(.opacity)
                        }
                        if let ok = validationOK {
                            HStack(spacing: 4) {
                                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                Text(ok ? "Key works" : (validationError ?? "Key rejected"))
                            }
                            .font(Typography.sans(11, .semibold))
                            .foregroundStyle(ok ? Palette.greenInk : Palette.redInk)
                            .transition(.opacity)
                        }
                        Spacer()
                    }
                    .animation(.easeInOut(duration: 0.18), value: keySaved)
                    .animation(.easeInOut(duration: 0.18), value: validationOK)
                    .animation(.easeInOut(duration: 0.18), value: draftMatchesStored)
                }
            }

            SettingsSection(title: "Behavior",
                            subtitle: "App-wide preferences.") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    behaviorRow(
                        title: "Launch at Login",
                        subtitle: "Start Narra automatically when you sign in.",
                        isOn: $settings.launchAtLogin
                    )
                    Divider().background(Color.white.opacity(0.08))
                    behaviorRow(
                        title: "Mute Audio While Recording",
                        subtitle: "Silences system output so music or video doesn't bleed into the mic. Volume is restored when recording ends.",
                        isOn: $settings.muteOutputWhenRecording
                    )
                }
            }

            SettingsSection(title: "Service Mode",
                            subtitle: "Takes effect on next launch.") {
                Picker("Mode", selection: $settings.orchestratorMode) {
                    Text("Automatic").tag(ServiceOrchestrator.Mode.automatic)
                    Text("Cloud (Groq)").tag(ServiceOrchestrator.Mode.cloudOnly)
                    Text("Local").tag(ServiceOrchestrator.Mode.localOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsSection(title: "Models",
                            subtitle: "Local models run on-device when the cloud is unavailable.") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    settingsRow(label: "Speech", value: "Whisper Base (local)")
                    Divider().background(Color.white.opacity(0.08))
                    settingsRow(label: "Cleanup (cloud)", value: "Llama 3.1 8B Instant (Groq)")
                }
            }

            SettingsSection(title: "Local Model Downloads",
                            subtitle: "Downloaded to ~/Library/Application Support/Narra/Models.") {
                LocalModelsList()
            }
        }
        .onAppear {
            apiKeyDraft = GrokAPIKeySource.resolve() ?? ""
            storedKey = KeychainService.load(for: .groq)
        }
    }

    private func saveKey() {
        try? KeychainService.save(key: apiKeyDraft, for: .groq)
        storedKey = KeychainService.load(for: .groq)
        keySaved = true
        validationOK = nil
        validationError = nil
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            keySaved = false
        }
    }

    private func validate() {
        let key = apiKeyDraft
        guard !key.isEmpty else { return }
        isValidating = true
        validationOK = nil
        validationError = nil
        Task {
            let (ok, err) = await Self.pingGroqModels(key: key)
            await MainActor.run {
                isValidating = false
                validationOK = ok
                validationError = err
            }
        }
    }

    /// GET https://api.groq.com/openai/v1/models with Bearer auth.
    /// Returns (success, errorMessage?).
    private static func pingGroqModels(key: String) async -> (Bool, String?) {
        guard let url = URL(string: "https://api.groq.com/openai/v1/models") else {
            return (false, "Bad URL")
        }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return (false, "No response")
            }
            if (200..<300).contains(http.statusCode) {
                return (true, nil)
            }
            if http.statusCode == 401 { return (false, "Unauthorized") }
            return (false, "HTTP \(http.statusCode)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func behaviorRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.sans(12, .medium))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(value)
                .font(Typography.mono(11))
                .foregroundStyle(Palette.muted)
        }
    }
}

// MARK: - Local models list

private struct LocalModelsList: View {
    private let manager = LocalModelManager()
    private let specs: [LocalModelManager.ModelSpec] = [
        LocalModelManager.defaultWhisper,
        LocalModelManager.defaultLLM,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(specs, id: \.key) { spec in
                if spec.key != specs.first?.key {
                    Divider().background(Color.white.opacity(0.08))
                }
                LocalModelRow(spec: spec, manager: manager)
            }
        }
    }
}

private struct LocalModelRow: View {
    let spec: LocalModelManager.ModelSpec
    let manager: LocalModelManager

    @State private var installed: Bool = false
    @State private var downloading: Bool = false
    @State private var progress: Double = 0
    @State private var error: String? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.displayName)
                    .font(Typography.sans(12, .medium))
                    .foregroundStyle(Palette.ink)
                Text(sizeText)
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.muted)
                if let error {
                    Text(error)
                        .font(Typography.sans(11))
                        .foregroundStyle(Palette.redInk)
                }
            }
            Spacer()
            if installed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Installed")
                }
                .font(Typography.sans(11, .semibold))
                .foregroundStyle(Palette.greenInk)
            } else if downloading {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                    Text("\(Int(progress * 100))%")
                        .font(Typography.mono(10))
                        .foregroundStyle(Palette.muted)
                }
            } else {
                Button(action: download) {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(Typography.sans(11, .semibold))
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .fill(Palette.ink)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { installed = manager.isDownloaded(spec) }
    }

    private var sizeText: String {
        let mb = Double(spec.sizeBytes) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        }
        return String(format: "%.0f MB", mb)
    }

    private func download() {
        downloading = true
        progress = 0
        error = nil
        Task {
            do {
                _ = try await manager.download(spec) { p in
                    Task { @MainActor in self.progress = p }
                }
                await MainActor.run {
                    downloading = false
                    installed = manager.isDownloaded(spec)
                }
            } catch {
                await MainActor.run {
                    downloading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Post-Processing Tab

private struct PostProcessingSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsScroll {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                EditorialSectionLabel(text: "Cleanup level")
                Text("Auto-cleanup applies to every dictation. The raw transcript is always preserved.")
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md),
                                GridItem(.flexible(), spacing: Spacing.md)],
                      spacing: Spacing.md) {
                ForEach(CleanupLevel.allCases) { level in
                    CleanupLevelCard(level: level, isSelected: settings.cleanupLevel == level)
                        .onTapGesture {
                            withAnimation(Motion.snappy) {
                                settings.cleanupLevel = level
                            }
                        }
                }
            }
        }
    }
}

private struct CleanupLevelCard: View {
    let level: CleanupLevel
    let isSelected: Bool

    var body: some View {
        GlassCard(padding: Spacing.lg, radius: CornerRadius.lg, selected: isSelected) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(level.title)
                        .font(Typography.sans(14, .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(level.description)
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(level.example)
                    .font(Typography.mono(10))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .lineLimit(3)
            }
        }
        .contentShape(Rectangle())
        .pointerCursor()
    }

    private var symbolName: String {
        switch level {
        case .none: return "circle.dashed"
        case .light: return "sparkle"
        case .medium: return "wand.and.stars"
        case .high: return "scissors"
        }
    }
}

private extension View {
    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Shortcuts Tab

private struct ShortcutsSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsScroll {
            if !KeybindingManager.shared.hasInputMonitoringAccess {
                GlassCard(padding: Spacing.lg, radius: CornerRadius.lg) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.yellowInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Input Monitoring Required")
                                .font(Typography.sans(12, .semibold))
                                .foregroundStyle(Palette.ink)
                            Text("Narra needs Input Monitoring to capture global shortcuts.")
                                .font(Typography.sans(11))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                        .buttonStyle(.plain)
                        .font(Typography.sans(11, .semibold))
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .fill(Palette.ink)
                        )
                    }
                }
            }

            SettingsSection(title: "Global Shortcuts",
                            subtitle: "Hold for press-to-talk. Tap toggle to start/stop with review.") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    shortcutRow(label: "Push-to-Talk", binding: $settings.pushToTalkBinding)
                    Divider().background(Color.white.opacity(0.08))
                    shortcutRow(label: "Push-to-Toggle", binding: $settings.pushToToggleBinding)
                }
            }

            SettingsSection(title: "In-App") {
                HStack {
                    Text("Copy transcript")
                        .font(Typography.sans(12, .medium))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    KbdChip(text: "⌘⇧C")
                }
            }
        }
    }

    private func shortcutRow(label: String, binding: Binding<KeyBinding>) -> some View {
        HStack {
            Text(label)
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
            KeyRecorderView(binding: binding)
                .frame(width: 180, height: 30)
        }
    }
}

private struct KbdChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Typography.mono(11))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

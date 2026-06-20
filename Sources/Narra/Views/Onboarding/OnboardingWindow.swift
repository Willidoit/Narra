import SwiftUI
import AVFoundation

// MARK: - OnboardingWindow
//
// First-run wizard. Six steps; the final one flips
// `AppSettings.hasCompletedOnboarding` to true and dismisses the window.
//
// Design notes:
// - One GlassCard wraps the whole step. Inputs inside use flat fills
//   (Color.white.opacity(0.05) + border) to avoid glass-on-glass.
// - KeyRecorderView is reused for the hotkeys step.
// - The API key step auto-advances for providers that don't require one.

/// Plan-named alias. The plan referred to this as `OnboardingView`; the
/// internal name kept here for the Window scene/file association.
typealias OnboardingView = OnboardingWindow

struct OnboardingWindow: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismissWindow) private var dismissWindow

    enum Step: Int, CaseIterable {
        case welcome, provider, apiKey, localSetup, hotkeys, mic, done

        /// Steps shown in the "Step n of N" footer. `done` is the
        /// celebration screen — not counted.
        static let trackedTotal = Step.allCases.count - 1
    }

    @State private var step: Step = .welcome
    @State private var apiKeyDraft: String = ""
    @State private var keySaved: Bool = false
    @State private var keySkipped: Bool = false
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @ObservedObject private var downloads = ModelDownloadCoordinator.shared

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            GlassCard(padding: Spacing.xxl, radius: CornerRadius.xl) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    stepContent
                    Spacer(minLength: 0)
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.lg)
        }
        .frame(width: 520, height: 460)
    }

    /// Returns true if any wired provider is ready: either it doesn't need
    /// an API key, or one is stored in the keychain.
    private var anyProviderReady: Bool {
        TranscriptionProviderRegistry.all.contains { provider in
            guard provider.status == .wired else { return false }
            if !provider.requiresAPIKey { return true }
            return (KeychainService.load(for: provider.id) ?? "").isEmpty == false
        }
    }

    // MARK: - Step routing

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:    welcomeStep
        case .provider:   providerStep
        case .apiKey:     apiKeyStep
        case .localSetup: localSetupStep
        case .hotkeys:    hotkeysStep
        case .mic:        micStep
        case .done:       doneStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Welcome to Narra")
                .font(Typography.serif(32, .medium))
                .foregroundStyle(Palette.ink)
            Text("Voice dictation for macOS that streams as you speak.")
                .font(Typography.sans(14))
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: - Provider

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Choose a transcription provider")
                .font(Typography.serif(24, .medium))
                .foregroundStyle(Palette.ink)
            Text("Cloud is fast and high-quality. Local runs entirely on your Mac.")
                .font(Typography.sans(13))
                .foregroundStyle(Palette.muted)

            VStack(spacing: Spacing.xs) {
                ForEach(TranscriptionProviderRegistry.all) { provider in
                    providerRow(provider)
                }
            }
            .padding(.top, Spacing.sm)
        }
    }

    private func providerRow(_ provider: TranscriptionProvider) -> some View {
        let isSelected = provider.id == settings.selectedProviderID
        let isStubbed = provider.status == .stubbed
        return Button {
            guard !isStubbed else { return }
            settings.selectedProviderID = provider.id
            // ponytail: snap to provider's default model; cheaper than
            // tracking last-used per provider.
            settings.selectedModelID = provider.defaultModelID
            AppServices.shared.orchestrator.setProvider(
                provider.id,
                model: provider.defaultModelID
            )
            // Reset API-key gating when provider changes.
            keySaved = false
            keySkipped = false
            apiKeyDraft = KeychainService.load(for: provider.id) ?? ""
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.muted)
                Text(provider.displayName)
                    .font(Typography.sans(13, .medium))
                    .foregroundStyle(isStubbed ? Palette.muted : Palette.ink)
                if isStubbed {
                    Text("(coming soon)")
                        .font(Typography.sans(11))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Text(provider.kind == .cloud ? "Cloud" : "Local")
                    .font(Typography.mono(10))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(isStubbed ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isStubbed)
    }

    // MARK: - API Key

    private var apiKeyStep: some View {
        let provider = TranscriptionProviderRegistry.provider(settings.selectedProviderID)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Enter your \(provider.displayName) API key")
                .font(Typography.serif(24, .medium))
                .foregroundStyle(Palette.ink)
            Text(apiKeyHint(for: provider))
                .font(Typography.sans(13))
                .foregroundStyle(Palette.muted)

            SecureField("Paste API key", text: $apiKeyDraft)
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
                .onSubmit { saveKey(for: provider) }

            HStack(spacing: Spacing.sm) {
                PillButton(title: "Save Key",
                           systemImage: "key.fill",
                           style: .filled,
                           isDisabled: apiKeyDraft.isEmpty) {
                    saveKey(for: provider)
                }
                PillButton(title: "Skip for now",
                           systemImage: "forward.fill",
                           style: .outline) {
                    keySkipped = true
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
                Spacer(minLength: 0)
            }
            .animation(Motion.microFade, value: keySaved)
        }
        .onAppear {
            // ponytail: auto-advance for providers that don't need a key —
            // saves a step instead of branching the wizard graph.
            if !provider.requiresAPIKey {
                advance()
                return
            }
            apiKeyDraft = KeychainService.load(for: provider.id) ?? ""
            if !apiKeyDraft.isEmpty { keySaved = true }
        }
    }

    private func apiKeyHint(for provider: TranscriptionProvider) -> String {
        switch provider.id {
        case .groq:
            return "Generate one at console.groq.com under API Keys. Stored locally in macOS Keychain."
        case .openAI:
            return "Generate one at platform.openai.com under API Keys. Stored locally in macOS Keychain."
        default:
            return "Paste your provider API key. Stored locally in macOS Keychain."
        }
    }

    private func saveKey(for provider: TranscriptionProvider) {
        guard !apiKeyDraft.isEmpty else { return }
        try? KeychainService.save(key: apiKeyDraft, for: provider.id)
        keySaved = true
        keySkipped = false
    }

    // MARK: - Hotkeys

    private var hotkeysStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Set your hotkeys")
                .font(Typography.serif(24, .medium))
                .foregroundStyle(Palette.ink)
            Text("Push-to-talk records while held. Push-to-toggle records until you press it again.")
                .font(Typography.sans(13))
                .foregroundStyle(Palette.muted)

            hotkeyRow(title: "Push-to-talk", caption: "Hold to record, release to transcribe.",
                      binding: Binding(
                        get: { settings.pushToTalkBinding },
                        set: { settings.pushToTalkBinding = $0 }
                      ))
            hotkeyRow(title: "Push-to-toggle", caption: "Tap to start, tap again to review.",
                      binding: Binding(
                        get: { settings.pushToToggleBinding },
                        set: { settings.pushToToggleBinding = $0 }
                      ))
        }
    }

    private func hotkeyRow(title: String, caption: String, binding: Binding<KeyBinding>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.sans(12, .semibold))
                .foregroundStyle(Palette.ink)
            Text(caption)
                .font(Typography.sans(11))
                .foregroundStyle(Palette.muted)
            KeyRecorderView(binding: binding)
                .frame(width: 200, height: 28)
        }
    }

    // MARK: - Mic

    private var micStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Microphone access")
                .font(Typography.serif(24, .medium))
                .foregroundStyle(Palette.ink)
            Text("You can grant later in System Settings → Privacy & Security if needed.")
                .font(Typography.sans(13))
                .foregroundStyle(Palette.muted)

            HStack(spacing: Spacing.sm) {
                Image(systemName: micStatusSymbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(micStatusColor)
                Text(micStatusLabel)
                    .font(Typography.sans(12, .medium))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        }
    }

    private var micStatusSymbol: String {
        switch micStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        case .notDetermined: return "questionmark.circle"
        @unknown default: return "questionmark.circle"
        }
    }

    private var micStatusColor: Color {
        switch micStatus {
        case .authorized: return Palette.greenInk
        case .denied, .restricted: return Palette.redInk
        case .notDetermined: return Palette.muted
        @unknown default: return Palette.muted
        }
    }

    private var micStatusLabel: String {
        switch micStatus {
        case .authorized: return "Microphone access granted"
        case .denied: return "Microphone access denied"
        case .restricted: return "Microphone restricted by policy"
        case .notDetermined: return "Awaiting microphone permission"
        @unknown default: return "Unknown microphone state"
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("You're all set")
                .font(Typography.serif(32, .medium))
                .foregroundStyle(Palette.ink)
            Text("Press your push-to-talk hotkey from any app to start dictating.")
                .font(Typography.sans(14))
                .foregroundStyle(Palette.muted)

            if !anyProviderReady {
                Text("Add an API key or pick an on-device provider before finishing.")
                    .font(Typography.sans(12))
                    .foregroundStyle(Palette.redInk)
            }

            HStack {
                Spacer()
                PillButton(title: "Finish",
                           systemImage: "checkmark",
                           style: .filled,
                           isDisabled: !anyProviderReady) {
                    settings.hasCompletedOnboarding = true
                    dismissWindow(id: "onboarding")
                }
                Spacer()
            }
            .padding(.top, Spacing.lg)
        }
    }

    // MARK: - Footer (progress + back/continue)

    @ViewBuilder
    private var footer: some View {
        if step != .done {
            HStack(spacing: Spacing.md) {
                Text("Step \(step.rawValue + 1) of \(Step.trackedTotal)")
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.muted)

                Spacer()

                if step.rawValue > Step.welcome.rawValue {
                    PillButton(title: "Back", systemImage: "chevron.left", style: .outline) {
                        retreat()
                    }
                }
                PillButton(title: "Continue",
                           systemImage: "chevron.right",
                           style: .filled,
                           isDisabled: !canAdvance) {
                    advance()
                }
            }
        }
    }

    // MARK: - Advancement

    private var canAdvance: Bool {
        switch step {
        case .apiKey:
            let provider = TranscriptionProviderRegistry.provider(settings.selectedProviderID)
            if !provider.requiresAPIKey { return true }
            return keySaved || keySkipped
        case .localSetup:
            let provider = TranscriptionProviderRegistry.provider(settings.selectedProviderID)
            if provider.kind == .cloud { return true }
            if provider.id == .appleSpeech { return true }
            // Downloadable local providers gate on a finished download —
            // user can still hit Back to choose a different provider/model.
            return downloads.isDownloaded(
                providerID: provider.id,
                modelID: settings.selectedModelID
            )
        default:
            return true
        }
    }

    private func advance() {
        let next = step.rawValue + 1
        if let nextStep = Step(rawValue: next) {
            withAnimation(Motion.snappy) { step = nextStep }
        }
    }

    private func retreat() {
        let prev = step.rawValue - 1
        if let prevStep = Step(rawValue: prev) {
            withAnimation(Motion.snappy) { step = prevStep }
        }
    }

    // MARK: - Local setup step (download progress / language picker)

    private var localSetupStep: some View {
        let provider = TranscriptionProviderRegistry.provider(settings.selectedProviderID)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            if provider.id == .appleSpeech {
                appleSpeechLanguageStep
            } else {
                downloadStep(for: provider)
            }
        }
        .onAppear {
            if provider.kind == .cloud {
                // Cloud providers don't need a local setup — skip the step.
                advance()
            }
        }
    }

    // Apple Speech: pick the dictation locale.
    private var appleSpeechLanguageStep: some View {
        let provider = TranscriptionProviderRegistry.provider(.appleSpeech)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Choose your language")
                .font(Typography.serif(24, .medium))
                .foregroundStyle(Palette.ink)
            Text("Apple Speech runs on-device. Pick the language you'll dictate in most often — you can change it later in Settings.")
                .font(Typography.sans(13))
                .foregroundStyle(Palette.muted)

            VStack(spacing: Spacing.xs) {
                ForEach(provider.models) { model in
                    appleSpeechLanguageRow(model)
                }
            }
        }
    }

    private func appleSpeechLanguageRow(_ model: ProviderModel) -> some View {
        let isSelected = settings.selectedModelID == model.id
            && settings.selectedProviderID == .appleSpeech
        return Button {
            settings.selectedProviderID = .appleSpeech
            settings.selectedModelID = model.id
            AppServices.shared.orchestrator.setProvider(.appleSpeech, model: model.id)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 16)
                Text(model.displayName)
                    .font(Typography.sans(13, .medium))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isSelected ? Palette.greenInk : Palette.muted)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // WhisperKit / Parakeet: download the selected model with a
    // big progress bar and a byte counter.
    @ViewBuilder
    private func downloadStep(for provider: TranscriptionProvider) -> some View {
        // Registry guarantees every provider has at least one model, but
        // bail to an empty view rather than `.first!`-crash if that ever
        // breaks. Cheaper than a fatalError, no user-visible regression.
        if let model = provider.models.first(where: { $0.id == settings.selectedModelID })
            ?? provider.models.first {
            let state = downloads.state(for: provider.id, modelID: model.id)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Download \(model.displayName)")
                    .font(Typography.serif(24, .medium))
                    .foregroundStyle(Palette.ink)
                Text("\(provider.displayName) runs entirely on your Mac. The model is a one-time download — about \(approxSize(model)).")
                    .font(Typography.sans(13))
                    .foregroundStyle(Palette.muted)

                switch state {
                case .idle:
                    PillButton(title: "Start download",
                               systemImage: "arrow.down.circle",
                               style: .filled) {
                        downloads.download(providerID: provider.id, modelID: model.id)
                    }
                case .downloading(let frac):
                    ProgressView(value: frac)
                        .progressViewStyle(.linear)
                        .tint(Palette.greenInk)
                    Text("\(Int(frac * 100))% · \(byteCounter(model: model, fraction: frac))")
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.muted)
                    PillButton(title: "Cancel",
                               systemImage: "xmark",
                               style: .outline) {
                        downloads.cancel(providerID: provider.id, modelID: model.id)
                    }
                case .ready:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Downloaded — ready to use")
                    }
                    .font(Typography.sans(12, .semibold))
                    .foregroundStyle(Palette.greenInk)
                case .failed(let message):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Download failed: \(message)")
                    }
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.redInk)
                    PillButton(title: "Retry",
                               systemImage: "arrow.clockwise",
                               style: .filled) {
                        downloads.download(providerID: provider.id, modelID: model.id)
                    }
                }
            }
        }
    }

    private func approxSize(_ model: ProviderModel) -> String {
        guard let bytes = model.approxBytes, bytes > 0 else { return "unknown size" }
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useMB, .useGB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }

    private func byteCounter(model: ProviderModel, fraction: Double) -> String {
        guard let total = model.approxBytes, total > 0 else { return "" }
        let done = Int64(Double(total) * fraction)
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useMB, .useGB]
        fmt.countStyle = .file
        return "\(fmt.string(fromByteCount: done)) of \(fmt.string(fromByteCount: total))"
    }
}


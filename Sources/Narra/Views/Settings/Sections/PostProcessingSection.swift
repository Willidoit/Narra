import SwiftUI

// MARK: - PostProcessingSection
//
// Cleanup level + smart defaults. Provider routing is read-only here —
// the user picks cloud/local/auto from General → Network fallback.

struct PostProcessingSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            enableBlock
            Divider().background(Color.white.opacity(0.08))
            levelBlock
            Divider().background(Color.white.opacity(0.08))
            providerBlock
            Divider().background(Color.white.opacity(0.08))
            smartBlock
        }
    }

    // MARK: - Enable

    private var enableBlock: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clean up transcripts")
                    .font(Typography.sans(12, .medium))
                    .foregroundStyle(Palette.ink)
                Text("Polish punctuation, remove filler words, and tighten phrasing as you speak.")
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: $settings.postProcessingEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    // MARK: - Cleanup level

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Cleanup level")
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.ink)
            Picker("", selection: $settings.cleanupLevel) {
                ForEach(CleanupLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!settings.postProcessingEnabled)
            Text(settings.cleanupLevel.description)
                .font(Typography.sans(11))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(settings.cleanupLevel.example)
                .font(Typography.mono(11))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .opacity(settings.postProcessingEnabled ? 1 : 0.45)
    }

    // MARK: - Provider (read-only)

    private var providerBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Provider")
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.ink)
            Text(providerSummary)
                .font(Typography.sans(11))
                .foregroundStyle(Palette.muted)
            Text("Change cloud/local routing in General → Network fallback.")
                .font(Typography.sans(11))
                .foregroundStyle(Palette.muted)
                .padding(.top, 2)
        }
        .opacity(settings.postProcessingEnabled ? 1 : 0.45)
    }

    private var providerSummary: String {
        switch settings.orchestratorMode {
        case .automatic:
            return "Auto: Groq cloud LLM, falls back to on-device regex when offline."
        case .cloudOnly:
            return "Cloud only: Groq LLM."
        case .localOnly:
            return "On-device only: deterministic regex cleanup."
        }
    }

    // MARK: - Smart behaviors

    private var smartBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Smart behaviors")
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.ink)
            smartToggle(
                title: "Skip cleanup in code editors",
                detail: "Detects Xcode, VS Code, Cursor, iTerm, Warp — pastes verbatim.",
                isOn: $settings.smartCodeDetection
            )
            smartToggle(
                title: "Stronger cleanup on long recordings",
                detail: "Bumps the cleanup level one notch past 30 seconds.",
                isOn: $settings.smartLengthEscalation
            )
            smartToggle(
                title: "Preserve fillers in fragments",
                detail: "Only strip \u{201C}um\u{201D}/\u{201C}uh\u{201D} when the surrounding sentence is complete.",
                isOn: $settings.smartFillerThreshold
            )
        }
        .opacity(settings.postProcessingEnabled ? 1 : 0.45)
    }

    private func smartToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.sans(12))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!settings.postProcessingEnabled)
        }
    }
}

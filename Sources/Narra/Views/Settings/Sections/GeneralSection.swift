import SwiftUI

// MARK: - GeneralSection
//
// Launch behavior, network fallback policy, onboarding reset, and About.
// The onboarding reset only flips the flag — Task 3 owns wiring the
// actual first-run wizard re-display.

struct GeneralSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            launchBlock
            Divider().background(Color.white.opacity(0.08))
            modeBlock
            Divider().background(Color.white.opacity(0.08))
            onboardingBlock
            Divider().background(Color.white.opacity(0.08))
            aboutBlock
        }
    }

    // MARK: - Launch

    private var launchBlock: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at Login")
                    .font(Typography.sans(12, .medium))
                    .foregroundStyle(Palette.ink)
                Text("Start Narra automatically when you sign in.")
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    // MARK: - Network fallback mode

    private var modeBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Network fallback behavior")
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.ink)
            Text("Takes effect on next launch.")
                .font(Typography.sans(11))
                .foregroundStyle(Palette.muted)
            Picker("", selection: $settings.orchestratorMode) {
                Text("Automatic").tag(ServiceOrchestrator.Mode.automatic)
                Text("Cloud only").tag(ServiceOrchestrator.Mode.cloudOnly)
                Text("Local only").tag(ServiceOrchestrator.Mode.localOnly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Onboarding

    private var onboardingBlock: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Re-run onboarding")
                    .font(Typography.sans(12, .medium))
                    .foregroundStyle(Palette.ink)
                Text("Resets the first-run flag. Relaunch Narra to see the wizard again.")
                    .font(Typography.sans(11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: rerunOnboarding) {
                Text("Re-run onboarding…")
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
        }
    }

    private func rerunOnboarding() {
        settings.hasCompletedOnboarding = false
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }

    // MARK: - About

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Narra")
                    .font(Typography.serif(14, .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("v\(appVersion)")
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.muted)
            }
            Text("Voice dictation for macOS.")
                .font(Typography.sans(11))
                .foregroundStyle(Palette.muted)
        }
    }
}

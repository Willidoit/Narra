import SwiftUI
import AppKit

/// Primary app window. Hosts the same sidebar/sections used by the legacy
/// Settings scene — provider & model selection is one of those sections, so
/// there's no need for a separate "main" UI duplicating it. The .task block
/// wires up keybindings, the menu-bar bridge, and first-run onboarding.
struct MainWindowView: View {
    @ObservedObject private var viewModel = ContentViewModel.shared
    @State private var didTriggerOnboarding = false
    @State private var showInputMonitoringAlert = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsRoot()
            .task {
                MenuBarShared.viewModel = viewModel
                KeybindingManager.shared.onPushToTalkStart = { viewModel.startPushToTalk() }
                KeybindingManager.shared.onPushToTalkStop  = { viewModel.stopPushToTalk() }
                KeybindingManager.shared.onPushToToggle    = { viewModel.handleToggleHotkey() }
                KeybindingManager.shared.start()
                if !KeybindingManager.shared.hasInputMonitoringAccess {
                    showInputMonitoringAlert = true
                }
                // Bring up the HUD window — its own behavior view will hide it
                // until viewModel.uiMode leaves .hidden.
                openWindow(id: "hud")
                if !didTriggerOnboarding && !AppSettings.shared.hasCompletedOnboarding {
                    didTriggerOnboarding = true
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "onboarding")
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
}

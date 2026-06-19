import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
        // Activation policy is driven dynamically by WindowBehavior per uiMode:
        // .regular while Home is visible (Dock icon shown), .accessory otherwise.
        NSApp.setActivationPolicy(.accessory)
        KeychainService.migrateLegacyGrokKeyIfNeeded()
        let axOpts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(axOpts)
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        // Eagerly initialize shared services so the engine state object
        // is observable by the menu bar, and kick off the WhisperKit
        // download in the background so first-record isn't a 145 MB wait.
        Task { @MainActor in
            try? await AppServices.shared.orchestrator.localTranscriber.preload()
        }

        // Warm Groq's TLS connection so the first post-processing call
        // doesn't pay DNS + TCP + TLS latency on top of the LLM round-trip.
        // ponytail: HEAD request is enough; URLSession reuses the connection.
        if let url = URL(string: "https://api.groq.com/") {
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.httpMethod = "HEAD"
            URLSession.shared.dataTask(with: req).resume()
        }
    }
}

// MARK: - App Entry Point

@main
struct NarraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engineState = AppServices.shared.engineState

    static let menuBarIcon: NSImage = {
        let img: NSImage = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        // Size by height so wide artwork doesn't collapse vertically.
        // 15pt = ~15% smaller than the standard 18pt menu bar height.
        let h: CGFloat = 15
        let w = h * (img.size.width / max(img.size.height, 1))
        img.size = NSSize(width: w, height: h)
        img.isTemplate = false
        return img
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
        } label: {
            if engineState.isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 36)
            } else {
                Image(nsImage: Self.menuBarIcon)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRoot()
                .preferredColorScheme(.dark)
        }

        // ponytail: re-running onboarding via Settings flips the
        // hasCompletedOnboarding flag but does not auto-reopen this window —
        // user relaunches the app. A NotificationCenter trigger is plausible
        // but unnecessary for a one-button-in-Settings path.
        Window("Setup", id: "onboarding") {
            OnboardingWindow()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContent: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings

    private var currentProvider: TranscriptionProvider {
        TranscriptionProviderRegistry.provider(settings.selectedProviderID)
    }

    private var currentModelDisplayName: String {
        currentProvider.models.first(where: { $0.id == settings.selectedModelID })?.displayName
            ?? settings.selectedModelID
    }

    /// "<provider> · <model>" — the dot indicator is a separate SF Symbol so
    /// it never falls back to a font-emoji glyph on certain systems.
    private func currentStatusText() -> String {
        "Narra — \(currentProvider.displayName) · \(currentModelDisplayName)"
    }

    var body: some View {
        // Status row — disabled Label with a tinted SF Symbol dot.
        Button(action: {}) {
            Label {
                Text(currentStatusText())
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(Palette.greenInk)
            }
        }
        .disabled(true)

        Divider()

        Button("Open Narra") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Button("Paste Last Transcription") {
            MenuBarShared.viewModel?.pasteLastTranscription()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Divider()

        Menu("Provider") {
            ForEach(TranscriptionProviderRegistry.all, id: \.id) { provider in
                providerMenuItem(provider)
            }
        }

        Menu("Model") {
            ForEach(currentProvider.models, id: \.id) { model in
                modelMenuItem(model)
            }
        }

        Divider()

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Narra") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private func providerMenuItem(_ provider: TranscriptionProvider) -> some View {
        let isSelected = provider.id == settings.selectedProviderID
        let isStubbed = provider.status == .stubbed
        let title = isStubbed ? "\(provider.displayName) (soon)" : provider.displayName
        Button {
            guard !isStubbed else { return }
            settings.selectedProviderID = provider.id
            // ponytail: snap to provider's default model instead of tracking
            // last-used per provider.
            settings.selectedModelID = provider.defaultModelID
            AppServices.shared.orchestrator.setProvider(
                provider.id,
                model: provider.defaultModelID
            )
        } label: {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .disabled(isStubbed)
    }

    @ViewBuilder
    private func modelMenuItem(_ model: ProviderModel) -> some View {
        let isSelected = model.id == settings.selectedModelID
        Button {
            settings.selectedModelID = model.id
            AppServices.shared.orchestrator.setProvider(
                settings.selectedProviderID,
                model: model.id
            )
        } label: {
            if isSelected {
                Label(model.displayName, systemImage: "checkmark")
            } else {
                Text(model.displayName)
            }
        }
    }
}

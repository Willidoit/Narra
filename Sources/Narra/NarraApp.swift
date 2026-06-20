import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app: titled main window + Dock icon. Set activation
        // policy before the icon so the Dock tile exists when we assign.
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
            NSApp.dockTile.display()
        }
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
        // Primary app window — titled, resizable, real Mac chrome. Holds
        // provider/model status and wires up keybindings on appear.
        WindowGroup("Narra") {
            MainWindowView()
                .preferredColorScheme(.dark)
        }
        // ponytail: hidden title bar lets the canvas flow under the traffic
        // lights for the coherent dark look. SettingsRoot already insets the
        // sidebar's top padding by 28pt to clear them.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 600)

        // HUD bead — separate window so the main window can stay normal
        // while the bead docks to the notch with .statusBar level + clear
        // background.
        Window("Narra HUD", id: "hud") {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.plain)
        // ponytail: HUDWindowBehavior calls setFrame manually; letting
        // SwiftUI also size the window via .contentSize was throwing an
        // AutoLayout NSException on fn-key (constraint conflict between
        // SwiftUI's content-size policy and our manual frame).
        .commandsRemoved()

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

        // ponytail: settings live in the main window itself — no separate
        // Settings scene. ⌘, brings the main window forward (see MenuBarContent).

        // ponytail: re-running onboarding via Settings flips the
        // hasCompletedOnboarding flag but does not auto-reopen this window —
        // user relaunches the app. A NotificationCenter trigger is plausible
        // but unnecessary for a one-button-in-Settings path.
        Window("Setup", id: "onboarding") {
            OnboardingWindow()
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContent: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var mics = MicrophoneList()

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let main = NSApp.windows.first(where: { $0.title == "Narra" }) {
            main.makeKeyAndOrderFront(nil)
        }
    }

    private var currentProvider: TranscriptionProvider {
        TranscriptionProviderRegistry.provider(settings.selectedProviderID)
    }

    private var currentModelDisplayName: String {
        currentProvider.models.first(where: { $0.id == settings.selectedModelID })?.displayName
            ?? settings.selectedModelID
    }

    private func currentStatusText() -> String {
        "Narra — \(currentProvider.displayName) · \(currentModelDisplayName)"
    }

    var body: some View {
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

        Button("Paste Last Transcription") {
            MenuBarShared.viewModel?.pasteLastTranscription()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Divider()

        Menu("Select Microphone") {
            Button {
                UserDefaults.standard.removeObject(forKey: "preferredMicUniqueID")
                mics.refresh()
            } label: {
                if mics.selectedUID == nil {
                    Label("System Default", systemImage: "checkmark")
                } else {
                    Text("System Default")
                }
            }
            Divider()
            ForEach(mics.devices, id: \.uniqueID) { device in
                Button {
                    UserDefaults.standard.set(device.uniqueID, forKey: "preferredMicUniqueID")
                    mics.refresh()
                } label: {
                    if mics.selectedUID == device.uniqueID {
                        Label(device.localizedName, systemImage: "checkmark")
                    } else {
                        Text(device.localizedName)
                    }
                }
            }
        }

        // ponytail: hook Sparkle later; menu entry exists so users see it.
        Button("Check for Updates…") {}
            .disabled(true)

        Button("Send Feedback") {
            if let url = URL(string: "mailto:feedback@narra.app?subject=Narra%20Feedback") {
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Button("Settings…") { openMainWindow() }
            .keyboardShortcut(",", modifiers: .command)

        Button("Quit Narra") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

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
            SettingsView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContent: View {
    @StateObject private var mics = MicrophoneList()
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Native NSMenu-style rows — macOS handles styling, padding, key chips.
        Button("Open Narra") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Button("Paste Last Transcription") {
            MenuBarShared.viewModel?.pasteLastTranscription()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Menu("Microphone") {
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
}


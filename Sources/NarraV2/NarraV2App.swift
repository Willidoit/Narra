import SwiftUI
import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
struct NarraV2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engineState = AppServices.shared.engineState

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
        } label: {
            if engineState.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "waveform")
                    .symbolRenderingMode(.hierarchical)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContent: View {
    @StateObject private var mics = MicrophoneList()
    @ObservedObject private var engineState = AppServices.shared.engineState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(engineStatusText)
            .disabled(true)

        Divider()

        Button {
            MenuBarShared.viewModel?.showHome()
        } label: {
            Label("Home", systemImage: "house")
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Button {
            MenuBarShared.viewModel?.pasteLastTranscription()
        } label: {
            Label("Paste Last Transcription", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Divider()

        Menu {
            Button {
                UserDefaults.standard.removeObject(forKey: "preferredMicUniqueID")
                mics.refresh()
            } label: {
                HStack {
                    if mics.selectedUID == nil {
                        Image(systemName: "checkmark")
                    }
                    Text("System Default")
                }
            }
            Divider()
            ForEach(mics.devices, id: \.uniqueID) { device in
                Button {
                    UserDefaults.standard.set(device.uniqueID, forKey: "preferredMicUniqueID")
                    mics.refresh()
                } label: {
                    HStack {
                        if mics.selectedUID == device.uniqueID {
                            Image(systemName: "checkmark")
                        }
                        Text(device.localizedName)
                    }
                }
            }
        } label: {
            Label("Microphone", systemImage: "mic")
        }

        Divider()

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Narra", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private var engineStatusText: String {
        if engineState.isReady { return "Engine: Ready" }
        if engineState.isLoading { return "Engine: Loading…" }
        if let err = engineState.lastError, !err.isEmpty { return "Engine: Error" }
        return "Engine: Not loaded"
    }
}

// MARK: - Microphone enumeration

@MainActor
private final class MicrophoneList: ObservableObject {
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedUID: String? = nil

    init() {
        refresh()
    }

    func refresh() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        devices = session.devices
        selectedUID = UserDefaults.standard.string(forKey: "preferredMicUniqueID")
    }
}

import Foundation
import AppKit
import ServiceManagement

// MARK: - CleanupLevel

public enum CleanupLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, light, medium, high

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .none:   return "None"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var description: String {
        switch self {
        case .none:   return "Pass through the raw transcript unchanged."
        case .light:  return "Strip filler words and fix grammar only."
        case .medium: return "Remove fillers, resolve self-corrections, merge restatements."
        case .high:   return "Condense aggressively, drop redundancy, prioritize brevity."
        }
    }

    var example: String {
        switch self {
        case .none:   return "\"Um, I was going to, uh, say that the meeting is uh cancelled.\""
        case .light:  return "\"I was going to say that the meeting is cancelled.\""
        case .medium: return "\"The meeting is cancelled.\""
        case .high:   return "\"Meeting cancelled.\""
        }
    }
}

// MARK: - KeyBinding

struct KeyBinding: Codable, Equatable, Sendable {
    /// Single-character string, or nil for modifier-only (e.g. bare fn).
    var keyChar: String?
    /// NSEvent.ModifierFlags raw value; may include .function (1 << 23).
    var modifierFlags: UInt

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.function) { parts.append("fn") }
        if flags.contains(.control)  { parts.append("⌃") }
        if flags.contains(.option)   { parts.append("⌥") }
        if flags.contains(.shift)    { parts.append("⇧") }
        if flags.contains(.command)  { parts.append("⌘") }
        if let char = keyChar {
            parts.append(char == " " ? "Space" : char.uppercased())
        }
        return parts.joined(separator: " + ")
    }
}

// MARK: - AppSettings

final class AppSettings: ObservableObject, @unchecked Sendable {
    static let shared = AppSettings()

    @Published var cleanupLevel: CleanupLevel {
        didSet { UserDefaults.standard.set(cleanupLevel.rawValue, forKey: "cleanupLevel") }
    }

    @Published var orchestratorMode: ServiceOrchestrator.Mode {
        didSet { UserDefaults.standard.set(orchestratorMode.rawValue, forKey: "orchestratorMode") }
    }

    @Published var pushToTalkBinding: KeyBinding {
        didSet { save(binding: pushToTalkBinding, forKey: "pushToTalkBinding") }
    }

    @Published var pushToToggleBinding: KeyBinding {
        didSet { save(binding: pushToToggleBinding, forKey: "pushToToggleBinding") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin()
        }
    }

    @Published var muteOutputWhenRecording: Bool {
        didSet { UserDefaults.standard.set(muteOutputWhenRecording, forKey: "muteOutputWhenRecording") }
    }

    @Published var selectedProviderID: ProviderID {
        didSet { UserDefaults.standard.set(selectedProviderID.rawValue, forKey: "selectedProviderID") }
    }

    @Published var selectedModelID: String {
        didSet {
            UserDefaults.standard.set(
                selectedModelID,
                forKey: "selectedModelID:\(selectedProviderID.rawValue)"
            )
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Post-processing

    @Published var postProcessingEnabled: Bool {
        didSet { UserDefaults.standard.set(postProcessingEnabled, forKey: "postProcessingEnabled") }
    }

    @Published var smartCodeDetection: Bool {
        didSet { UserDefaults.standard.set(smartCodeDetection, forKey: "smartCodeDetection") }
    }

    @Published var smartLengthEscalation: Bool {
        didSet { UserDefaults.standard.set(smartLengthEscalation, forKey: "smartLengthEscalation") }
    }

    @Published var smartFillerThreshold: Bool {
        didSet { UserDefaults.standard.set(smartFillerThreshold, forKey: "smartFillerThreshold") }
    }

    private init() {
        // Defaults: fn for push-to-talk, fn+Space for push-to-toggle.
        let functionFlag = NSEvent.ModifierFlags.function.rawValue

        if let raw = UserDefaults.standard.string(forKey: "cleanupLevel"),
           let level = CleanupLevel(rawValue: raw) {
            cleanupLevel = level
        } else {
            cleanupLevel = .medium
        }

        if let raw = UserDefaults.standard.string(forKey: "orchestratorMode"),
           let mode = ServiceOrchestrator.Mode(rawValue: raw) {
            orchestratorMode = mode
        } else {
            orchestratorMode = .automatic
        }

        if let data = UserDefaults.standard.data(forKey: "pushToTalkBinding"),
           let binding = try? JSONDecoder().decode(KeyBinding.self, from: data) {
            pushToTalkBinding = binding
        } else {
            pushToTalkBinding = KeyBinding(keyChar: nil, modifierFlags: functionFlag)
        }

        if let data = UserDefaults.standard.data(forKey: "pushToToggleBinding"),
           let binding = try? JSONDecoder().decode(KeyBinding.self, from: data) {
            pushToToggleBinding = binding
        } else {
            pushToToggleBinding = KeyBinding(keyChar: " ", modifierFlags: functionFlag)
        }

        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        muteOutputWhenRecording = UserDefaults.standard.bool(forKey: "muteOutputWhenRecording")

        let resolvedProviderID: ProviderID
        if let raw = UserDefaults.standard.string(forKey: "selectedProviderID"),
           let id = ProviderID(rawValue: raw) {
            resolvedProviderID = id
        } else {
            resolvedProviderID = .groq
        }
        selectedProviderID = resolvedProviderID

        let modelKey = "selectedModelID:\(resolvedProviderID.rawValue)"
        if let stored = UserDefaults.standard.string(forKey: modelKey), !stored.isEmpty {
            selectedModelID = stored
        } else {
            selectedModelID = TranscriptionProviderRegistry.provider(resolvedProviderID).defaultModelID
        }

        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Post-processing defaults — all opt-out, default-on so the cleanup
        // pipeline runs automatically for first-time users.
        postProcessingEnabled = (UserDefaults.standard.object(forKey: "postProcessingEnabled") as? Bool) ?? true
        smartCodeDetection = (UserDefaults.standard.object(forKey: "smartCodeDetection") as? Bool) ?? true
        smartLengthEscalation = (UserDefaults.standard.object(forKey: "smartLengthEscalation") as? Bool) ?? true
        smartFillerThreshold = (UserDefaults.standard.object(forKey: "smartFillerThreshold") as? Bool) ?? true
    }

    private func save(binding: KeyBinding, forKey key: String) {
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Surface via console; the toggle reverts on next launch if the
            // OS rejected it (e.g. user hasn't approved the helper).
            NSLog("Narra: launch-at-login update failed: \(error)")
        }
    }
}

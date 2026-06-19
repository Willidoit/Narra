import Foundation
import AppKit

/// Inspects the frontmost app when a recording starts and returns hints the
/// cleanup pipeline should respect (skip cleanup in code editors, etc.).
///
/// Stateless. Safe to call on the main actor from `ContentViewModel`.
enum SmartContext {

    /// Bundle IDs (or prefixes) we treat as code-editing contexts. Cleanup
    /// is forced off so the verbatim transcript pastes unchanged.
    /// Prefix-matched so JetBrains products (`com.jetbrains.intellij`,
    /// `com.jetbrains.pycharm`, etc.) all match a single entry.
    static let codeEditorBundleIDs: [String] = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.github.atom",
        "com.sublimetext",
        "com.jetbrains",
        "com.googlecode.iterm2",
        "dev.warp.Warp",
        "com.apple.Terminal",
    ]

    /// Returns true when the frontmost app should bypass LLM cleanup.
    static func isFrontmostAppCodeEditor(
        frontmost: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    ) -> Bool {
        guard let id = frontmost else { return false }
        return codeEditorBundleIDs.contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    /// Bump the cleanup level one step when the recording is long enough that
    /// users typically want tighter output. Stops at `.high`.
    static func escalateForLength(_ level: CleanupLevel, durationSeconds: TimeInterval) -> CleanupLevel {
        guard durationSeconds > 30 else { return level }
        switch level {
        case .none:   return .none // user explicitly said no cleanup
        case .light:  return .medium
        case .medium: return .high
        case .high:   return .high
        }
    }

    /// Resolve the effective cleanup level for a recording given user
    /// settings and recording metadata. Single entry point so callers don't
    /// re-implement the toggle logic.
    static func effectiveLevel(
        userLevel: CleanupLevel,
        durationSeconds: TimeInterval,
        settings: AppSettings = .shared,
        frontmost: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    ) -> CleanupLevel {
        if settings.smartCodeDetection, isFrontmostAppCodeEditor(frontmost: frontmost) {
            return .none
        }
        if settings.smartLengthEscalation {
            return escalateForLength(userLevel, durationSeconds: durationSeconds)
        }
        return userLevel
    }
}

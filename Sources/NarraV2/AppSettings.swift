import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Keys {
        static let cleanupLevel = "narrav2.cleanupLevel"
        static let orchestratorMode = "narrav2.orchestratorMode"
    }

    @Published var cleanupLevel: CleanupLevel {
        didSet {
            UserDefaults.standard.set(cleanupLevel.rawValue, forKey: Keys.cleanupLevel)
        }
    }

    @Published var orchestratorMode: ServiceOrchestrator.Mode {
        didSet {
            UserDefaults.standard.set(orchestratorMode.rawValue, forKey: Keys.orchestratorMode)
        }
    }

    var grokAPIKeyStatus: Bool {
        GrokAPIKeySource.resolve() != nil
    }

    private init() {
        let defaults = UserDefaults.standard
        self.cleanupLevel = (defaults.string(forKey: Keys.cleanupLevel).flatMap(CleanupLevel.init(rawValue:))) ?? .medium
        self.orchestratorMode = (defaults.string(forKey: Keys.orchestratorMode).flatMap(ServiceOrchestrator.Mode.init(rawValue:))) ?? .automatic
    }
}

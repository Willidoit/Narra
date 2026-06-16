import Foundation

@MainActor
final class AppServices {

    static let shared = AppServices()

    let orchestrator: ServiceOrchestrator
    let engineState: TranscriptionEngineState

    private init() {
        let engineState = TranscriptionEngineState()
        // ponytail: mode read once at launch; ServiceOrchestrator.configuration is `let`,
        // so changing Service Mode in Settings takes effect on next launch.
        let mode = AppSettings.shared.orchestratorMode
        let orchestrator = ServiceOrchestrator(configuration: .init(mode: mode))
        orchestrator.localTranscriber.engineState = engineState
        self.engineState = engineState
        self.orchestrator = orchestrator
    }
}

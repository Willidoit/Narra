import Foundation

@MainActor
final class AppServices {

    static let shared = AppServices()

    let orchestrator: ServiceOrchestrator
    let engineState: TranscriptionEngineState

    private init() {
        let engineState = TranscriptionEngineState()
        let orchestrator = ServiceOrchestrator()
        orchestrator.localTranscriber.engineState = engineState
        self.engineState = engineState
        self.orchestrator = orchestrator
    }
}

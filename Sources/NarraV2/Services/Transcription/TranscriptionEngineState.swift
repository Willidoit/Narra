import Foundation

@MainActor
final class TranscriptionEngineState: ObservableObject {
    @Published var isReady: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastError: String?
}

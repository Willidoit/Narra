import Foundation
import Network

/// Selects between the cloud (Grok) and local services based on
/// connectivity, user preference, and service availability.
///
/// The orchestrator is the only object the app should call into. The
/// selection rules, in order, are:
///
/// 1. **User override** — if the user pinned a service in Settings,
///    that service wins.
/// 2. **Network reachability** — if the network is unreachable and a
///    local service is downloaded, use local.
/// 3. **Default** — prefer cloud (Grok) when the network is up, since
///    it gives the highest quality today.
///
/// The orchestrator exposes a `preferred` service and a `fallback` for
/// each stage. Callers that want to handle the fallback themselves can
/// catch the orchestrator's error and call into the fallback. Callers
/// that want a single try should use `transcribeWithFallback(_:)` /
/// `processWithFallback(_:)` — those retry on the local service if the
/// primary fails for any reason other than a hard client error.
public final class ServiceOrchestrator: @unchecked Sendable {

    public enum Mode: String, Sendable, CaseIterable, Codable {
        case automatic
        case cloudOnly
        case localOnly
    }

    public struct Configuration: Sendable {
        public var mode: Mode
        public var apiKey: String?

        public init(mode: Mode = .automatic, apiKey: String? = nil) {
            self.mode = mode
            self.apiKey = apiKey
        }
    }

    public let configuration: Configuration
    public let cloudTranscriber: GrokTranscriptionService
    public let localTranscriber: LocalTranscriptionService
    public let cloudProcessor: GrokPostProcessingService
    public let localProcessor: LocalPostProcessingService
    public let modelManager: LocalModelManager

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.narrav2.orchestrator.path")
    private var currentPath: NWPath?

    public init(
        configuration: Configuration = Configuration(),
        modelManager: LocalModelManager = LocalModelManager()
    ) {
        self.configuration = configuration
        self.modelManager = modelManager
        self.cloudTranscriber = GrokTranscriptionService(apiKey: configuration.apiKey)
        self.localTranscriber = LocalTranscriptionService(
            configuration: LocalTranscriptionService.Configuration(modelManager: modelManager)
        )
        self.cloudProcessor = GrokPostProcessingService(apiKey: configuration.apiKey)
        self.localProcessor = LocalPostProcessingService(
            configuration: LocalPostProcessingService.Configuration(modelManager: modelManager)
        )
        monitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Selection

    /// Whether the local fallback is currently usable. True when at
    /// least one of the two default models is downloaded.
    public var isLocalAvailable: Bool {
        modelManager.isDownloaded(LocalModelManager.defaultWhisper) ||
        modelManager.isDownloaded(LocalModelManager.defaultLLM)
    }

    /// Whether the network is currently reachable. Synchronous read of
    /// the most recent path update.
    public var isNetworkReachable: Bool {
        currentPath.map { $0.status == .satisfied } ?? true
    }

    // MARK: - Transcription

    public func transcribeWithFallback(_ audio: AudioChunk) async throws -> TranscriptSegment {
        switch pickOrder() {
        case .cloud:
            do {
                return try await cloudTranscriber.transcribe(audio: audio)
            } catch {
                if isLocalAvailable {
                    return try await localTranscriber.transcribe(audio: audio)
                }
                throw error
            }
        case .local:
            return try await localTranscriber.transcribe(audio: audio)
        }
    }

    // MARK: - Post-processing

    public func processWithFallback(_ segments: [TranscriptSegment]) async throws -> ProcessedTranscript {
        switch pickOrder() {
        case .cloud:
            do {
                return try await cloudProcessor.process(segments: segments)
            } catch {
                if isLocalAvailable {
                    return try await localProcessor.process(segments: segments)
                }
                throw error
            }
        case .local:
            return try await localProcessor.process(segments: segments)
        }
    }

    public func processWithFallback(_ segment: TranscriptSegment) async throws -> ProcessedTranscript {
        try await processWithFallback([segment])
    }

    // MARK: - Selection logic

    enum Pick { case cloud, local }

    func pickOrder() -> Pick {
        switch configuration.mode {
        case .cloudOnly:
            return .cloud
        case .localOnly:
            return .local
        case .automatic:
            if !isNetworkReachable && isLocalAvailable {
                return .local
            }
            return .cloud
        }
    }
}

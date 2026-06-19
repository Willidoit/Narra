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
    public let whisperCpp: WhisperCppTranscriptionService
    public let cloudProcessor: GrokPostProcessingService
    public let localProcessor: LocalPostProcessingService
    public let modelManager: LocalModelManager

    /// Currently-selected provider. Persisted in `AppSettings`; mirrored
    /// here so the routing methods can consult it without reaching back
    /// into the settings singleton.
    private(set) public var activeProviderID: ProviderID = .groq
    /// Currently-selected model for `activeProviderID`. See `setProvider`.
    private(set) public var activeModelID: String = TranscriptionProviderRegistry
        .provider(.groq).defaultModelID

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
        self.whisperCpp = WhisperCppTranscriptionService()
        self.cloudProcessor = GrokPostProcessingService()
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
        let service = makeService(for: activeProviderID, model: activeModelID)
        do {
            return try await service.transcribe(audio: audio)
        } catch {
            // Fall back to local WhisperKit when the active provider fails
            // for any reason other than empty audio — matches prior behavior.
            if case TranscriptionError.emptyAudio = error { throw error }
            if activeProviderID == .whisperKit { throw error }
            return try await localTranscriber.transcribe(audio: audio)
        }
    }

    public func transcribeStream(
        _ stream: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptSegment, Error> {
        makeService(for: activeProviderID, model: activeModelID).transcribe(stream: stream)
    }

    /// Construct a fresh service for the requested provider + model. Cheap
    /// for cloud (URLSession-backed); WhisperKit is the only expensive one
    /// and reuses its cached singleton via `localTranscriber`.
    public func makeService(for id: ProviderID, model: String) -> TranscriptionService {
        switch id {
        case .groq:
            return GrokTranscriptionService(
                configuration: .init(model: model)
            )
        case .openAI:
            return OpenAITranscriptionService(
                configuration: .init(model: model)
            )
        case .deepgram:
            return DeepgramTranscriptionService(
                configuration: .init(model: model)
            )
        case .elevenLabs:
            return ElevenLabsTranscriptionService(
                configuration: .init(model: model)
            )
        case .whisperKit:
            return localTranscriber
        case .appleSpeech:
            return AppleSpeechTranscriptionService(
                configuration: .init(localeIdentifier: model)
            )
        case .whisperCpp:
            return whisperCpp
        case .parakeet:
            // Still stubbed in the registry — fall through to WhisperKit so the
            // pipeline keeps working if a user selects it before it's wired.
            return localTranscriber
        }
    }

    // MARK: - Post-processing

    public func processWithFallback(_ segments: [TranscriptSegment], level: CleanupLevel) async throws -> ProcessedTranscript {
        switch pickOrder() {
        case .cloud:
            do {
                return try await cloudProcessor.process(segments: segments, level: level)
            } catch {
                // ponytail: local cleanup always degrades to regex, so unconditional
                // fallback is safe. The previous isLocalAvailable gate keyed on a
                // HuggingFace cache path WhisperKit doesn't actually populate.
                return try await localProcessor.process(segments: segments)
            }
        case .local:
            return try await localProcessor.process(segments: segments)
        }
    }

    public func processWithFallback(_ segment: TranscriptSegment, level: CleanupLevel) async throws -> ProcessedTranscript {
        try await processWithFallback([segment], level: level)
    }

    // MARK: - Provider selection

    /// Set the active transcription provider and model. Mode
    /// (`.automatic`/`.cloudOnly`/`.localOnly`) is orthogonal — it
    /// controls fallback policy, not provider identity.
    public func setProvider(_ id: ProviderID, model: String) {
        activeProviderID = id
        activeModelID = model
        NSLog("Narra: provider set to \(id.rawValue) (model=\(model))")
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

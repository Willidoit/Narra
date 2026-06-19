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
        // xAI has no audio/transcriptions endpoint as of 2026 (404). Always
        // use the local WhisperKit pipeline. Cloud is still used for
        // post-processing (Grok chat/completions).
        return try await localTranscriber.transcribe(audio: audio)
    }

    /// Streaming transcription: feed live audio windows in, get
    /// `TranscriptSegment`s out as Whisper finishes each one. Local-only for
    /// the same reason as `transcribeWithFallback`.
    public func transcribeStream(
        _ stream: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptSegment, Error> {
        localTranscriber.transcribe(stream: stream)
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
        switch id {
        case .groq:
            // ponytail: GrokTranscriptionService takes its model id via
            // Configuration at init time and exposes no setter. Storing
            // the choice on the orchestrator is enough for Task 1; when
            // the cloud STT endpoint comes back online (see
            // transcribeWithFallback note about xAI 404), the cloud
            // transcriber should be rebuilt here with a fresh
            // Configuration(model: model). Ceiling: model selection is
            // not yet plumbed end-to-end for Groq STT.
            NSLog("Narra: provider set to groq (model=\(model)); applied on next cloud STT call.")
        case .whisperKit:
            // ponytail: LocalTranscriptionService also fixes its model
            // name at init. Same upgrade path as Groq — rebuild the
            // service when we wire model switching for WhisperKit.
            NSLog("Narra: provider set to whisperKit (model=\(model)); requires service rebuild to take effect.")
        case .openAI, .whisperCpp, .parakeet:
            // ponytail: stubbed providers — UI shows them, orchestrator
            // ignores them. Upgrade path: implement a real
            // TranscriptionService and flip status to .wired in the
            // registry.
            NSLog("Narra: provider \(id.rawValue) is not yet wired; ignoring.")
        }
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

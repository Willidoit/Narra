import Foundation
import WhisperKit
import FluidAudio

// MARK: - ModelDownloadCoordinator
//
// Single source of truth for "is this local model present, downloading, or
// missing?" The Settings download row, the onboarding download step, and
// the engine all observe it.
//
// Two download paths sit behind one coordinator:
//
//   * WhisperKit models — CoreML bundles (multi-file folders). Fetched via
//     `WhisperKit.download(variant:from:progressCallback:)` so the artifacts
//     land in a Narra-owned folder. We get real fractionCompleted progress.
//
//   * Single-file models (Parakeet .safetensors bundle).
//     Fetched via `LocalModelManager.download(_:progress:)` which is already
//     wired with URLSession byte-progress.
//
// Cancellation is cooperative: each download runs in a `Task` stored by
// key, and `cancel(...)` cancels it. URLSession honors `Task.cancel()` via
// the implicit cancellation token on `session.download(from:delegate:)`.

@MainActor
final class ModelDownloadCoordinator: ObservableObject {

    static let shared = ModelDownloadCoordinator()

    struct Key: Hashable {
        let providerID: ProviderID
        let modelID: String
    }

    enum State: Equatable {
        case idle
        case downloading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var states: [Key: State] = [:]

    private var tasks: [Key: Task<Void, Never>] = [:]
    private let modelManager: LocalModelManager
    private let fileManager: FileManager
    /// Base for Narra-owned WhisperKit downloads, so we don't fight
    /// `~/.cache/huggingface/...` ownership. Also used as the folder we
    /// hand to `WhisperKit.init(modelFolder:)` at load time.
    private let whisperKitBase: URL
    /// Base for FluidAudio's Parakeet bundles. `UnifiedAsrManager` writes
    /// `<base>/parakeet-tdt-0.6b-v3-coreml/<files>` under this directory.
    private let parakeetBase: URL

    init(
        modelManager: LocalModelManager = LocalModelManager(),
        fileManager: FileManager = .default
    ) {
        self.modelManager = modelManager
        self.fileManager = fileManager
        let appSupport = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.whisperKitBase = appSupport
            .appendingPathComponent("Narra/Models/whisperkit", isDirectory: true)
        self.parakeetBase = appSupport
            .appendingPathComponent("Narra/Models/parakeet", isDirectory: true)
        try? fileManager.createDirectory(
            at: whisperKitBase,
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: parakeetBase,
            withIntermediateDirectories: true
        )
        // Seed states from disk so the UI shows "Downloaded" without a tap.
        refreshAll()
    }

    // MARK: - Lookup

    func state(for providerID: ProviderID, modelID: String) -> State {
        states[Key(providerID: providerID, modelID: modelID)] ?? .idle
    }

    func isDownloaded(providerID: ProviderID, modelID: String) -> Bool {
        if case .ready = state(for: providerID, modelID: modelID) { return true }
        return false
    }

    /// Local folder URL for a downloaded WhisperKit model — used by
    /// `LocalTranscriptionService` to point WhisperKit at our cache rather
    /// than the HuggingFace hub default. Returns nil if the variant hasn't
    /// been downloaded yet.
    ///
    /// WhisperKit.download writes to
    /// `<downloadBase>/models--argmaxinc--whisperkit-coreml/snapshots/<hash>/<variant>/`.
    /// The hash component varies per snapshot so we scan rather than guess.
    func whisperKitModelFolder(modelID: String) -> URL? {
        let snapshots = whisperKitBase
            .appendingPathComponent("models--argmaxinc--whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return nil }
        let variant = whisperKitVariant(for: modelID)
        for snapshot in contents {
            let candidate = snapshot.appendingPathComponent(variant, isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// The base passed to `WhisperKit.download(downloadBase:)`. Also used
    /// by `LocalTranscriptionService` when constructing a `WhisperKit`
    /// instance without a pre-resolved folder path.
    var whisperKitDownloadBase: URL { whisperKitBase }

    /// Folder containing the Parakeet CoreML bundle, if downloaded. Returns
    /// nil when no bundle is present. `ParakeetTranscriptionService` loads
    /// its models from this URL.
    func parakeetModelDirectory() -> URL? {
        Self.resolveParakeetDirectory(in: parakeetBase, fileManager: fileManager)
    }

    /// Nonisolated variant so the orchestrator (running off the main actor)
    /// can resolve the same directory without hopping back.
    nonisolated static func resolveParakeetDirectory(
        in base: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidate = base
            .appendingPathComponent("parakeet-tdt-0.6b-v3-coreml", isDirectory: true)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Static-friendly path to the Parakeet base directory. Mirrors the
    /// `parakeetBase` we compute in `init` so non-actor contexts can build
    /// it without holding a coordinator reference.
    nonisolated static func parakeetBaseDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Narra/Models/parakeet", isDirectory: true)
    }

    // MARK: - Public actions

    func download(providerID: ProviderID, modelID: String) {
        let key = Key(providerID: providerID, modelID: modelID)
        guard tasks[key] == nil else { return }
        states[key] = .downloading(0)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                switch providerID {
                case .whisperKit:
                    try await self.downloadWhisperKit(modelID: modelID, key: key)
                case .parakeet:
                    try await self.downloadParakeet(key: key)
                default:
                    self.states[key] = .failed("This provider does not require a download.")
                }
                if case .downloading = self.states[key] ?? .idle {
                    self.states[key] = .ready
                }
            } catch is CancellationError {
                self.states[key] = .idle
            } catch {
                self.states[key] = .failed(String(describing: error))
            }
            self.tasks[key] = nil
        }
        tasks[key] = task
    }

    func cancel(providerID: ProviderID, modelID: String) {
        let key = Key(providerID: providerID, modelID: modelID)
        tasks[key]?.cancel()
        tasks[key] = nil
        // Refresh from disk to land back on the right idle/ready state.
        states[key] = diskState(for: providerID, modelID: modelID)
    }

    func delete(providerID: ProviderID, modelID: String) {
        let key = Key(providerID: providerID, modelID: modelID)
        switch providerID {
        case .whisperKit:
            if let folder = whisperKitModelFolder(modelID: modelID) {
                try? fileManager.removeItem(at: folder)
            }
        case .parakeet:
            if let folder = parakeetModelDirectory() {
                try? fileManager.removeItem(at: folder)
            }
        default:
            break
        }
        states[key] = .idle
    }

    // MARK: - Disk → state seeding

    func refreshAll() {
        for provider in TranscriptionProviderRegistry.all where provider.kind == .local {
            for model in provider.models {
                let key = Key(providerID: provider.id, modelID: model.id)
                states[key] = diskState(for: provider.id, modelID: model.id)
            }
        }
    }

    private func diskState(for providerID: ProviderID, modelID: String) -> State {
        switch providerID {
        case .appleSpeech:
            return .ready
        case .whisperKit:
            return whisperKitModelFolder(modelID: modelID) != nil ? .ready : .idle
        case .parakeet:
            return parakeetModelDirectory() != nil ? .ready : .idle
        default:
            return .idle
        }
    }

    // MARK: - WhisperKit fetch

    private func downloadWhisperKit(modelID: String, key: Key) async throws {
        let variant = whisperKitVariant(for: modelID)
        let progressBox = ProgressBox { [weak self] frac in
            Task { @MainActor in
                self?.states[key] = .downloading(frac)
            }
        }
        let callback: @Sendable (Progress) -> Void = { progress in
            progressBox.update(progress.fractionCompleted)
        }
        _ = try await WhisperKit.download(
            variant: variant,
            downloadBase: whisperKitBase,
            useBackgroundSession: false,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: callback
        )
        try Task.checkCancellation()
    }

    // MARK: - Parakeet fetch (FluidAudio-managed multi-file bundle)

    private func downloadParakeet(key: Key) async throws {
        let progressBox = ProgressBox { [weak self] frac in
            Task { @MainActor in
                self?.states[key] = .downloading(frac)
            }
        }
        let handler: DownloadUtils.ProgressHandler = { progress in
            progressBox.update(progress.fractionCompleted)
        }
        let manager = UnifiedAsrManager()
        try await manager.loadModels(
            to: parakeetBase,
            configuration: nil,
            progressHandler: handler
        )
        try Task.checkCancellation()
    }

    // MARK: - Model URL catalog

    /// Map model UI id ("base", "small"…) → the variant string WhisperKit
    /// recognizes on HuggingFace.
    private func whisperKitVariant(for modelID: String) -> String {
        switch modelID {
        case "base":     return "openai_whisper-base"
        case "small":    return "openai_whisper-small"
        case "medium":   return "openai_whisper-medium"
        case "large-v3": return "openai_whisper-large-v3"
        default:         return "openai_whisper-\(modelID)"
        }
    }


}

// Small thread-safe box so the closure captured by WhisperKit (which may
// fire on any queue) can hop onto the main actor without a data race.
private final class ProgressBox: @unchecked Sendable {
    private let onChange: @Sendable (Double) -> Void
    init(onChange: @escaping @Sendable (Double) -> Void) {
        self.onChange = onChange
    }
    func update(_ value: Double) { onChange(value) }
}

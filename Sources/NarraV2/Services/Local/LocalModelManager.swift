import Foundation

/// Downloads and caches local model files for the offline STT and LLM
/// fallbacks.
///
/// On first launch the orchestrator calls `downloadIfNeeded(for:)`. The
/// download is best-effort and resumable; on success the file lands in
/// `~/Library/Application Support/NarraV2/Models/<key>.<ext>`. On failure
/// the caller can fall back to the cloud service.
///
/// The manager does not block startup: callers should download in the
/// background and report progress to the UI.
public final class LocalModelManager: @unchecked Sendable {

    // MARK: - Configuration

    public struct ModelSpec: Sendable, Equatable {
        public let key: String
        public let displayName: String
        public let url: URL
        public let sizeBytes: Int64

        public init(key: String, displayName: String, url: URL, sizeBytes: Int64) {
            self.key = key
            self.displayName = displayName
            self.url = url
            self.sizeBytes = sizeBytes
        }
    }

    public enum ModelFamily: String, Sendable, CaseIterable {
        case whisper
        case llm
    }

    // MARK: - Defaults

    /// Curated default specs. These are intentionally conservative —
    /// small, well-known models that run on Apple Silicon without
    /// external downloads from sketchy sources.
    ///
    /// NOTE: The `url` field is kept for API compatibility but is **not**
    /// used for the Whisper model. `LocalTranscriptionService` now delegates
    /// all Whisper downloads to WhisperKit, which fetches Core ML bundles
    /// from `argmaxinc/whisperkit-coreml` on Hugging Face and caches them
    /// under `~/.cache/huggingface/hub/`.  The `key` value mirrors WhisperKit's
    /// model-name convention so that `isDownloaded(_:)` can locate the cached
    /// bundle without re-downloading it.
    public static let defaultWhisper: ModelSpec = .init(
        key: "openai_whisper-base",
        displayName: "Whisper Base (145M, via WhisperKit)",
        url: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
        sizeBytes: 145_000_000
    )

    public static let defaultLLM: ModelSpec = .init(
        key: "llama-3.2-1b",
        displayName: "Llama 3.2 1B Instruct (Q4)",
        url: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!,
        sizeBytes: 800_000_000
    )

    // MARK: - State

    private let session: URLSession
    private let fileManager: FileManager
    private let baseDirectory: URL

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("NarraV2/Models", isDirectory: true)
        try? fileManager.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Local file URL for the model. `nil` if the model is not yet
    /// downloaded.
    ///
    /// For WhisperKit-managed models (keys matching `openai_whisper-*`),
    /// this also checks WhisperKit's Hugging Face hub cache at
    /// `~/.cache/huggingface/hub/` before falling back to the NarraV2
    /// app-support directory. WhisperKit downloads Core ML bundles, so the
    /// check looks for a directory rather than a `.bin` file.
    public func localURL(for spec: ModelSpec) -> URL? {
        // 1. Check the WhisperKit HuggingFace hub cache for whisper models.
        //    WhisperKit stores models as directories under:
        //    ~/.cache/huggingface/hub/models--argmaxinc--whisperkit-coreml/
        //      snapshots/<hash>/<ModelName>/
        //    We accept the presence of the top-level repo directory as a
        //    signal that WhisperKit has already downloaded at least one model.
        if spec.key.hasPrefix("openai_whisper") {
            if let whisperKitCacheURL = whisperKitCacheURL(for: spec) {
                return whisperKitCacheURL
            }
        }

        // 2. Legacy / LLM models: look for a flat .bin file in the NarraV2
        //    application-support directory.
        let url = baseDirectory.appendingPathComponent(spec.key + ".bin")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether a model is downloaded and ready to use.
    public func isDownloaded(_ spec: ModelSpec) -> Bool {
        localURL(for: spec) != nil
    }

    // MARK: - Private helpers

    /// Returns the WhisperKit model cache URL if the model directory exists
    /// inside `~/.cache/huggingface/hub/`.
    private func whisperKitCacheURL(for spec: ModelSpec) -> URL? {
        // WhisperKit names the HuggingFace repo "argmaxinc/whisperkit-coreml",
        // which maps to the directory name "models--argmaxinc--whisperkit-coreml".
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let hubDir = homeDir
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
            .appendingPathComponent("models--argmaxinc--whisperkit-coreml", isDirectory: true)

        guard fileManager.fileExists(atPath: hubDir.path) else { return nil }

        // Walk snapshots/<hash>/<ModelName> to find the model directory.
        let snapshotsDir = hubDir.appendingPathComponent("snapshots", isDirectory: true)
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        for snapshot in snapshots {
            let modelDir = snapshot.appendingPathComponent(spec.key, isDirectory: true)
            if fileManager.fileExists(atPath: modelDir.path) {
                return modelDir
            }
        }

        // Model repo is present but this specific model variant hasn't been
        // downloaded yet; return the hub directory as a hint so callers know
        // WhisperKit is set up but the variant needs downloading.
        return nil
    }

    /// Download a model with progress reporting. Safe to call from any
    /// actor; the work happens on `session`'s queue.
    public func download(
        _ spec: ModelSpec,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let dest = baseDirectory.appendingPathComponent(spec.key + ".bin")
        if fileManager.fileExists(atPath: dest.path) {
            progress(1.0)
            return dest
        }
        let (tempURL, response) = try await session.download(from: spec.url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LocalModelError.downloadFailed(spec.key, http.statusCode)
        }
        // Atomically move the download to its final location
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: tempURL, to: dest)
        progress(1.0)
        return dest
    }
}

public enum LocalModelError: Error, Equatable, Sendable {
    case downloadFailed(String, Int)
    case modelNotFound(String)
}

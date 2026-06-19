import Foundation

// MARK: - ProviderID

/// Stable identifier for every transcription provider Narra can route to.
///
/// New providers must be added here first; the registry, keychain, and
/// settings persistence all key off the `rawValue`.
public enum ProviderID: String, CaseIterable, Codable, Sendable {
    case groq
    case whisperKit
    case openAI
    case whisperCpp
    case parakeet
    case deepgram
    case elevenLabs
    case appleSpeech
}

// MARK: - ProviderKind

/// Whether the provider runs in the cloud or on-device. Used by the
/// orchestrator's automatic-fallback policy and by the Settings UI to
/// group providers visually.
public enum ProviderKind: Sendable {
    case cloud
    case local
}

// MARK: - ProviderStatus

/// Lifecycle state of a provider's integration. `wired` providers have a
/// real `TranscriptionService` implementation; `stubbed` providers exist
/// for the UI only — selecting them logs and no-ops at the orchestrator.
public enum ProviderStatus: Sendable {
    case wired
    case stubbed
}

// MARK: - ProviderModel

public struct ProviderModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let notes: String?

    public init(id: String, displayName: String, notes: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.notes = notes
    }
}

// MARK: - TranscriptionProvider

public struct TranscriptionProvider: Identifiable, Hashable, Sendable {
    public let id: ProviderID
    public let displayName: String
    public let kind: ProviderKind
    public let status: ProviderStatus
    public let requiresAPIKey: Bool
    public let models: [ProviderModel]
    public let defaultModelID: String

    public init(
        id: ProviderID,
        displayName: String,
        kind: ProviderKind,
        status: ProviderStatus,
        requiresAPIKey: Bool,
        models: [ProviderModel],
        defaultModelID: String
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.status = status
        self.requiresAPIKey = requiresAPIKey
        self.models = models
        self.defaultModelID = defaultModelID
    }

    public static func == (lhs: TranscriptionProvider, rhs: TranscriptionProvider) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Registry

/// Static catalog of every transcription provider Narra knows about.
///
/// The registry is the single source of truth for the UI (which providers
/// to list, which models to offer) and for the orchestrator (which IDs
/// are wired vs stubbed). It is intentionally a value-type table so it
/// can be referenced from any actor or thread without coordination.
public enum TranscriptionProviderRegistry {

    public static let all: [TranscriptionProvider] = [
        TranscriptionProvider(
            id: .groq,
            displayName: "Groq",
            kind: .cloud,
            status: .wired,
            requiresAPIKey: true,
            models: [
                ProviderModel(id: "whisper-large-v3-turbo", displayName: "Whisper Large v3 Turbo"),
                ProviderModel(id: "whisper-large-v3", displayName: "Whisper Large v3"),
                ProviderModel(id: "distil-whisper-large-v3-en", displayName: "Distil Whisper Large v3 (EN)"),
            ],
            defaultModelID: "whisper-large-v3-turbo"
        ),
        TranscriptionProvider(
            id: .whisperKit,
            displayName: "WhisperKit",
            kind: .local,
            status: .wired,
            requiresAPIKey: false,
            models: [
                ProviderModel(id: "base", displayName: "Base"),
                ProviderModel(id: "small", displayName: "Small"),
                ProviderModel(id: "medium", displayName: "Medium"),
                ProviderModel(id: "large-v3", displayName: "Large v3"),
            ],
            defaultModelID: "base"
        ),
        TranscriptionProvider(
            id: .openAI,
            displayName: "OpenAI",
            kind: .cloud,
            status: .wired,
            requiresAPIKey: true,
            models: [
                ProviderModel(id: "gpt-4o-transcribe", displayName: "GPT-4o Transcribe"),
                ProviderModel(id: "gpt-4o-mini-transcribe", displayName: "GPT-4o Mini Transcribe"),
                ProviderModel(id: "whisper-1", displayName: "Whisper 1"),
            ],
            defaultModelID: "gpt-4o-mini-transcribe"
        ),
        TranscriptionProvider(
            id: .deepgram,
            displayName: "Deepgram",
            kind: .cloud,
            status: .wired,
            requiresAPIKey: true,
            models: [
                ProviderModel(id: "nova-3", displayName: "Nova 3"),
                ProviderModel(id: "nova-2", displayName: "Nova 2"),
            ],
            defaultModelID: "nova-3"
        ),
        TranscriptionProvider(
            id: .elevenLabs,
            displayName: "ElevenLabs",
            kind: .cloud,
            status: .wired,
            requiresAPIKey: true,
            models: [
                ProviderModel(id: "scribe_v1", displayName: "Scribe v1"),
            ],
            defaultModelID: "scribe_v1"
        ),
        TranscriptionProvider(
            id: .appleSpeech,
            displayName: "Apple Speech",
            kind: .local,
            status: .wired,
            requiresAPIKey: false,
            models: [
                ProviderModel(id: "en-US", displayName: "English (US)"),
                ProviderModel(id: "en-GB", displayName: "English (UK)"),
                ProviderModel(id: "es-ES", displayName: "Spanish (Spain)"),
                ProviderModel(id: "fr-FR", displayName: "French (France)"),
                ProviderModel(id: "de-DE", displayName: "German"),
                ProviderModel(id: "ja-JP", displayName: "Japanese"),
            ],
            defaultModelID: "en-US"
        ),
        TranscriptionProvider(
            id: .whisperCpp,
            displayName: "whisper.cpp",
            kind: .local,
            // Stub until ggerganov/whisper.cpp is vendored as a CWhisper
            // SwiftPM C-target. Stays in the registry so the UI keeps the
            // "Coming soon" badge users can plan around.
            status: .stubbed,
            requiresAPIKey: false,
            models: [
                ProviderModel(id: "base.en", displayName: "Base (EN)"),
                ProviderModel(id: "small.en", displayName: "Small (EN)"),
                ProviderModel(id: "medium.en", displayName: "Medium (EN)"),
            ],
            defaultModelID: "base.en"
        ),
        TranscriptionProvider(
            id: .parakeet,
            displayName: "Parakeet",
            kind: .local,
            status: .stubbed,
            requiresAPIKey: false,
            models: [
                ProviderModel(id: "parakeet-tdt-0.6b", displayName: "Parakeet TDT 0.6B"),
            ],
            defaultModelID: "parakeet-tdt-0.6b"
        ),
    ]

    /// Look up a provider by ID. Force-unwraps because every `ProviderID`
    /// case has a matching entry in `all`; that invariant is checked by
    /// `CaseIterable` coverage.
    public static func provider(_ id: ProviderID) -> TranscriptionProvider {
        guard let match = all.first(where: { $0.id == id }) else {
            fatalError("TranscriptionProviderRegistry missing entry for \(id.rawValue)")
        }
        return match
    }
}

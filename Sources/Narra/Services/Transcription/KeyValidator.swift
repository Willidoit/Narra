import Foundation

/// One-shot authenticated GET against each cloud provider's models/account
/// endpoint. Returns true on 200-range, false on 401/403, throws on network
/// errors or unexpected non-2xx statuses (so the UI can show a real message).
public enum KeyValidator {

    public static func validate(
        provider id: ProviderID,
        key: String,
        session: URLSession = .shared
    ) async throws -> Bool {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let request = makeRequest(for: id, key: key) else {
            // Local providers never need a key — treat as already valid.
            return true
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.serviceError("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return true
        case 401, 403:
            return false
        default:
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw TranscriptionError.serviceError("HTTP \(http.statusCode): \(snippet)")
        }
    }

    private static func makeRequest(for id: ProviderID, key: String) -> URLRequest? {
        switch id {
        case .groq:
            return bearer(URL(string: "https://api.groq.com/openai/v1/models")!, key: key)
        case .openAI:
            return bearer(URL(string: "https://api.openai.com/v1/models")!, key: key)
        case .deepgram:
            var req = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
            req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
            return req
        case .elevenLabs:
            var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user")!)
            req.setValue(key, forHTTPHeaderField: "xi-api-key")
            return req
        case .whisperKit, .parakeet, .appleSpeech:
            return nil
        }
    }

    private static func bearer(_ url: URL, key: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return req
    }
}

// MARK: - Validation persistence

/// Persists "this key was last validated successfully" state per provider
/// in `UserDefaults`. Clearing the key wipes the bit.
public enum ValidationState {
    private static let prefix = "narra.validated."

    public static func isValidated(_ id: ProviderID) -> Bool {
        UserDefaults.standard.bool(forKey: prefix + id.rawValue)
    }

    public static func setValidated(_ id: ProviderID, _ value: Bool) {
        if value {
            UserDefaults.standard.set(true, forKey: prefix + id.rawValue)
            UserDefaults.standard.set(
                ISO8601DateFormatter().string(from: Date()),
                forKey: prefix + id.rawValue + ".at"
            )
        } else {
            UserDefaults.standard.removeObject(forKey: prefix + id.rawValue)
            UserDefaults.standard.removeObject(forKey: prefix + id.rawValue + ".at")
        }
    }
}

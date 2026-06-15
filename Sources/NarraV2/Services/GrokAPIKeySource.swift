import Foundation

/// Resolves a `xAI` (Grok) API key from the user's environment.
///
/// The key is read from the first non-empty source in the following
/// order, so secrets never need to be hardcoded in source:
///
/// 1. The `GROK_API_KEY` environment variable. This is the recommended
///    path during development — set it in your shell or in
///    `~/.narrav2/.env` (which is gitignored).
/// 2. The `~/.narrav2/.env` file (if present), parsed as `KEY=VALUE`
///    lines. Useful for keeping dev keys in one place without exporting
///    them globally.
/// 3. The macOS Keychain, under the service
///    `com.narrav2.apikey` and account `grok`. This is the recommended
///    path for production users.
///
/// If none of the above yield a key, the resolver returns `nil`. Callers
/// should treat `nil` as `PostProcessingError.missingAPIKey` /
/// `TranscriptionError.serviceError("Missing GROK_API_KEY")`.
public enum GrokAPIKeySource {

    /// Try every source in order and return the first non-empty key.
    public static func resolve() -> String? {
        if let env = ProcessInfo.processInfo.environment["GROK_API_KEY"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        if let dotenv = readDotenvValue(named: "GROK_API_KEY") {
            return dotenv
        }
        if let keychain = readKeychain() {
            return keychain
        }
        return nil
    }

    /// Read `~/.<name>` as a simple `KEY=VALUE` file and return the value
    /// for `name`. Returns `nil` if the file does not exist or the key
    /// is not present.
    static func readDotenvValue(named key: String, fileName: String = ".env") -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".narrav2").appendingPathComponent(fileName),
            home.appendingPathComponent(fileName),
        ]
        for url in candidates {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for raw in contents.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                let k = line[..<eq].trimmingCharacters(in: .whitespaces)
                guard k == key else { continue }
                var v = String(line[line.index(after: eq)...])
                    .trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
                    v = String(v.dropFirst().dropLast())
                }
                if !v.isEmpty { return v }
            }
        }
        return nil
    }

    /// Read the API key from the macOS Keychain. The shell helper
    /// `security find-generic-password` is used so this module does not
    /// have to link Security.framework directly.
    static func readKeychain(
        service: String = "com.narrav2.apikey",
        account: String = "grok"
    ) -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/security"
        process.arguments = [
            "find-generic-password",
            "-s", service,
            "-a", account,
            "-w"
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return nil
    }
}

import Security
import Foundation

/// Per-provider API key storage backed by the macOS Keychain.
///
/// Keys are stored under a single service name (`com.narrav2.apikey`) and
/// keyed by `ProviderID.rawValue` in the account slot. Adding a new
/// provider is a `ProviderID` case plus the corresponding UI affordance —
/// no schema change here.
public enum KeychainService {
    private static let service = "com.narrav2.apikey"

    // Legacy slot, only consulted by `migrateLegacyGrokKeyIfNeeded()`.
    private static let legacyService = "com.narrav2.grok-api-key"
    private static let legacyAccount = "grok-api-key"

    // MARK: - Per-provider API

    public static func save(key: String, for providerID: ProviderID) throws {
        let account = providerID.rawValue
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let data = key.data(using: .utf8) else { return }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError.saveFailed(status)
        }
    }

    public static func load(for providerID: ProviderID) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: providerID.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    public static func delete(for providerID: ProviderID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: providerID.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Legacy migration

    /// One-shot migration: if a key exists under the old single-tenant
    /// slot (`com.narrav2.grok-api-key` / `grok-api-key`), copy it into
    /// the new per-provider slot for `.groq` and delete the legacy entry.
    ///
    /// Idempotent: safe to call on every launch. After the first
    /// successful run the legacy entry is gone, so subsequent calls
    /// no-op.
    public static func migrateLegacyGrokKeyIfNeeded() {
        let legacyQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: legacyService,
            kSecAttrAccount: legacyAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return
        }

        // ponytail: best-effort migration. If save fails we leave the
        // legacy entry in place so a later launch can retry. Ceiling:
        // a permanent Keychain error would surface as a missing key in
        // GrokAPIKeySource; upgrade path is to add an explicit error
        // surface if real users hit this.
        do {
            try save(key: key, for: .groq)
            let deleteQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: legacyService,
                kSecAttrAccount: legacyAccount,
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        } catch {
            NSLog("Narra: legacy Grok key migration failed: \(error)")
        }
    }
}

public enum KeychainError: Error {
    case saveFailed(OSStatus)
}

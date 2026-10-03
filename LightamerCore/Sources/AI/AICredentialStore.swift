import Foundation
import Security

// ─────────────────────────────────────────────────────────────────────────────
// AICredentialStore (Plan M2-10-04 KD-1, D-M2-10-CONTEXT-5, M2AI-06) — the
// Keychain face for the remote AI provider key (kSecClassGenericPassword).
//
// SHAPE: a stateless enum of static faces — the store NEVER retains a copy
// of a secret. `read` hands the caller a fresh `Data` copy straight from the
// keychain; the CALLER owns it and zeroizes it (`resetBytes`) after use
// (the AIProviderClient is the production caller; its internal copy is
// scrubbed in a defer). There is deliberately no cache, no actor, no
// observed state — a credential read is one SecItem call.
//
// RED LINES (the E4 test family pins these):
//   • the key never enters UserDefaults / logs / error text (this file has
//     no logging face at all and its errors carry only OSStatus codes)
//   • service = the app bundle id (`com.kamasylvia.lightamer`), account =
//     the OQ-7-A single-connection key (`rating-provider`) — no multi-
//     profile key explosion
//   • delete of a missing item is idempotent success (the wipe path never
//     needs to distinguish "gone" from "was never there")
//
// The login-keychain tests run against the REAL host keychain
// (Scripts/test-direct.sh direct launch has access); a CI/lock-screen
// environment without keychain access surfaces as an XCTSkip (the
// `requireKeychain` probe in the test file).
// ─────────────────────────────────────────────────────────────────────────────

public enum AICredentialStore {

    public enum CredentialError: Error, Equatable {
        /// No password item exists for the account.
        case notFound
        /// The keychain is unavailable in this environment (the
        /// errSecMissingEntitlement family — tests XCTSkip on this).
        case unavailable(OSStatus)
        /// Any other unhandled SecItem status.
        case unhandledStatus(OSStatus)
    }

    /// The keychain service name — the app bundle id (D-5 literal; the ONLY
    /// spelling).
    public static let service = "com.kamasylvia.lightamer"

    /// The OQ-7-A single remote connection's account key. One connection
    /// configuration (protocol/baseURL/key/model) — no template library, no
    /// multi-profile accounts.
    public static let ratingProviderAccount = "rating-provider"

    // MARK: - Write

    /// Store (or overwrite) the secret for `account`. Overwrite rides
    /// SecItemUpdate so the item's creation date/ACL survive a re-key.
    public static func save(_ secret: Data, account: String) throws {
        var addQuery = baseQuery(account: account)
        let status = SecItemCopyMatching(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let update: [String: Any] = [kSecValueData as String: secret]
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw CredentialError.unhandledStatus(updateStatus)
            }
        case errSecItemNotFound:
            addQuery[kSecValueData as String] = secret
            addQuery[kSecClass as String] = kSecClassGenericPassword
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialError.unhandledStatus(addStatus)
            }
        case errSecMissingEntitlement:
            throw CredentialError.unavailable(status)
        default:
            throw CredentialError.unhandledStatus(status)
        }
    }

    // MARK: - Read

    /// Return a FRESH copy of the secret. The store keeps nothing: the
    /// caller owns the returned buffer and zeroizes it after use
    /// (`key.resetBytes()` — the E4 byte assertion's subject).
    public static func read(_ account: String) throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw CredentialError.unhandledStatus(status)
            }
            return data
        case errSecItemNotFound:
            throw CredentialError.notFound
        case errSecMissingEntitlement:
            throw CredentialError.unavailable(status)
        default:
            throw CredentialError.unhandledStatus(status)
        }
    }

    // MARK: - Delete

    /// Remove the secret. Idempotent: a missing item is success (the
    /// settings-page reset path never errors on an already-empty keychain).
    public static func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        case errSecMissingEntitlement:
            throw CredentialError.unavailable(status)
        default:
            throw CredentialError.unhandledStatus(status)
        }
    }

    // MARK: - Query plumbing

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

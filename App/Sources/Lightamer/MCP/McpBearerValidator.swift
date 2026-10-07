import Foundation
import MCP
import Security

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 T5 (research §RQ-14-13, R4): the static shared-token Bearer face.
//
// The SDK's built-in BearerTokenValidator targets OAuth 2.0 protected
// resources (JWT + audience) — a STATIC shared token has no ready-made
// valve, so this is the ~40-line HTTPRequestValidator the research called
// for, appended AFTER the SDK's default pipeline (Origin → Accept →
// Content-Type → Protocol-Version → Session → Bearer).
//
// Posture (D-14-CONTEXT-6①): the loopback default carries NO token at all
// (auth: "none" — the smallest attack surface); the token valve exists for
// the explicit non-loopback branch where Bearer is MANDATORY. The token's
// true body lives in the keychain (0600 file fallback) and NEVER in the
// discovery json — which only ever carries the "bearer" marker.
//
// Public-repo audit note: comparison is constant-time by hand (below) — do
// not "simplify" it to ==; timing side channels are the reason it exists.
// ─────────────────────────────────────────────────────────────────────────────

/// The Bearer valve: 401s every request whose `Authorization` header does
/// not carry the exact shared token. Missing header and malformed scheme are
/// indistinguishable at the timing level (both fail before any comparison).
struct McpBearerValidator: HTTPRequestValidator {

    let token: String

    init(token: String) {
        self.token = token
    }

    func validate(
        _ request: HTTPRequest, context: HTTPValidationContext
    ) -> HTTPResponse? {
        guard let authorization = request.header("Authorization") else {
            return .unauthorized("missing Authorization header")
        }
        guard authorization.hasPrefix("Bearer "), authorization.count > "Bearer ".count
        else {
            return .unauthorized("malformed Authorization scheme")
        }
        let presented = String(authorization.dropFirst("Bearer ".count))
        if Self.constantTimeCompare(presented, token) {
            return nil
        }
        return .unauthorized("token mismatch")
    }
}

private extension HTTPResponse {
    static func unauthorized(_ reason: String) -> HTTPResponse {
        .error(
            statusCode: 401,
            MCPError.internalError("Unauthorized: \(reason)"),
            extraHeaders: ["WWW-Authenticate": "Bearer"])
    }
}

extension McpBearerValidator {

    /// Constant-time equality over the LONGER input (length independent of
    /// secret content: a length mismatch never short-circuits the loop).
    static func constantTimeCompare(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        var diff = lhsBytes.count ^ rhsBytes.count
        let longest = max(lhsBytes.count, rhsBytes.count)
        for index in 0..<longest {
            let left = index < lhsBytes.count ? lhsBytes[index] : 0
            let right = index < rhsBytes.count ? rhsBytes[index] : 0
            diff |= Int(left ^ right)
        }
        return diff == 0
    }
}

/// The token lifecycle: SecRandom 32 bytes → base64url (~43 chars), keychain
/// as the truth, `~/.lightamer/mcp-token` 0600 as the non-sandboxed-last-
/// resort fallback. Consumers (launcher, 14-4 docs) read through `load`.
enum McpBearerToken {

    static let keychainService = "com.kamasylvia.lightamer.mcp"
    static let keychainAccount = "bearer-token"

    /// 32 random bytes, base64url, no padding — ~43 characters.
    static func generate() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }
        var data = Data(bytes)
        var encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while encoded.hasSuffix("=") {
            encoded.removeLast()
        }
        return encoded
    }

    /// Persists the token: keychain first; on keychain failure the 0600
    /// fallback file (created with restrictive permissions, never world-read).
    static func store(_ token: String) throws {
        if keychainStore(token) { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fileURL = home.appendingPathComponent(
            ".lightamer/mcp-token", isDirectory: false)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try Data(token.utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Reads the token back (keychain → fallback file). `nil` = no token
    /// stored yet; the caller generates one and stores it.
    static func load() -> String? {
        if let keychain = keychainLoad() { return keychain }
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lightamer/mcp-token", isDirectory: false)
        let data = try? Data(contentsOf: fileURL)
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Test/rotation support: removes BOTH faces (keychain + fallback file).
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lightamer/mcp-token", isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Keychain legs

    private static func keychainStore(_ token: String) -> Bool {
        deleteKeychainItem()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func keychainLoad() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

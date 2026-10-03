import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryConnectionStore (Plan M2-10-07 T1, KD-2, checker M11) — the SINGLE
// remote AI connection's persistence face for the ACA settings page.
//
// SPLIT (the safe shape, KD-2): UserDefaults carries the NON-SECRET face
// (protocol / baseURL / model / timeout + the rating strictness + the output
// language); the Keychain carries the key body through `AICredentialStore`
// (account = the OQ-7-A single-connection `rating-provider`). THE KEY BODY
// NEVER ENTERS DEFAULTS — the M2-10-04 red line, test-pinned here by a
// defaults-dump negative.
//
// SHAPES (the preferences twins): constant keys (the ONLY spellings) +
// injectable defaults suite + full-replacement store + reset — the
// ImportDefaults / LabelingPreferences lineage.
//
// ADMISSION (the front gate, KD-2): a baseURL must pass `AIEndpointPolicy`
// BEFORE it can be stored — the config face never persists an unauthorized
// endpoint, so the send-side transport gate (04) stays the SECOND check,
// never the first.
//
// CONNECTION TEST: one minimal completion round trip through
// `AIProviderClient` ("ping", no image) — the result surfaces inline on the
// ACA page. The transport seam is injected (URLSession in production, a
// URLProtocol-mocked session in tests — zero real network).
// ─────────────────────────────────────────────────────────────────────────────

/// The three-way output-language preference (KD-2: 中文 / English / 跟随
/// 系统). `system` resolves to `AIRatingLanguage` at the call site via the
/// preferred-localizations probe (no locale snapshot stored).
enum AIOutputLanguage: String, Sendable, CaseIterable {
    case system
    case chinese
    case english

    /// The rubric-facing language. `system` follows the device's FIRST
    /// preferred localization (zh family → Chinese, else English).
    func resolved(preferredLocalizations: [String]) -> AIRatingLanguage {
        switch self {
        case .chinese: return .chinese
        case .english: return .english
        case .system:
            let zh = preferredLocalizations.contains {
                $0.hasPrefix("zh")
            }
            return zh ? .chinese : .english
        }
    }
}

struct LibraryConnectionStore: Sendable {

    // MARK: - Keys (the ONLY spellings)

    nonisolated static let connectionKey = "library.ai.connection"
    nonisolated static let strictnessKey = "library.ai.strictness"
    nonisolated static let outputLanguageKey = "library.ai.outputLanguage"

    /// The rating-strictness default (the rubric midpoint).
    nonisolated static let defaultStrictness = 3

    /// The connection-config JSON envelope (Codable — `AIConnectionConfig`
    /// itself stays untouched in Core; this is the App-side storage shape).
    private struct StoredConnection: Codable {
        let protocolRaw: String
        let baseURL: String
        let model: String
        let timeout: TimeInterval
    }

    /// nil = `.standard` (the app face); tests pass an isolated suite name.
    let defaultsSuiteName: String?

    /// The keychain account face. Production = the OQ-7-A single-connection
    /// `rating-provider` (the ONLY production spelling); tests inject a
    /// UUID-suffixed account so reruns never collide with a real key in the
    /// shared login keychain (the AICredentialStoreTests discipline).
    let keychainAccount: String

    init(
        defaultsSuiteName: String? = nil,
        keychainAccount: String = AICredentialStore.ratingProviderAccount
    ) {
        self.defaultsSuiteName = defaultsSuiteName
        self.keychainAccount = keychainAccount
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // MARK: - Connection config (the non-secret face)

    /// The stored connection, or nil when never configured (or unreadable —
    /// a corrupt payload degrades to "unconfigured", never to a guess).
    func connection() -> AIConnectionConfig? {
        guard let data = defaults.data(forKey: Self.connectionKey),
            let stored = try? JSONDecoder().decode(StoredConnection.self, from: data),
            let provider = AIProviderProtocol(rawValue: stored.protocolRaw),
            let url = URL(string: stored.baseURL)
        else { return nil }
        return AIConnectionConfig(
            protocol: provider, baseURL: url, model: stored.model,
            timeout: stored.timeout)
    }

    /// Store the connection WHOLE (never a partial/union semantic). The
    /// caller runs the admission gate first — the store-side guard here is
    /// the backstop that refuses an unauthorized endpoint even if a future
    /// caller forgets (defense in depth, same predicate).
    func store(_ config: AIConnectionConfig) throws {
        guard AIEndpointPolicy.isAuthorized(config.baseURL) else {
            throw AIEndpointPolicy.PolicyError.insecureEndpoint(config.baseURL)
        }
        let stored = StoredConnection(
            protocolRaw: config.protocol.rawValue,
            baseURL: config.baseURL.absoluteString,
            model: config.model,
            timeout: config.timeout)
        defaults.set(try JSONEncoder().encode(stored), forKey: Self.connectionKey)
    }

    // MARK: - Strictness / output language

    /// The stored strictness clamped into 1...5 (a garbage value degrades to
    /// the default — the ImportDefaults fallback shape).
    func strictness() -> Int {
        let raw = defaults.integer(forKey: Self.strictnessKey)
        guard defaults.object(forKey: Self.strictnessKey) != nil else {
            return Self.defaultStrictness
        }
        return min(max(raw, 1), 5)
    }

    func storeStrictness(_ value: Int) {
        defaults.set(min(max(value, 1), 5), forKey: Self.strictnessKey)
    }

    func outputLanguage() -> AIOutputLanguage {
        guard let raw = defaults.string(forKey: Self.outputLanguageKey),
            let language = AIOutputLanguage(rawValue: raw)
        else { return .system }
        return language
    }

    func storeOutputLanguage(_ language: AIOutputLanguage) {
        defaults.set(language.rawValue, forKey: Self.outputLanguageKey)
    }

    // MARK: - The API key (the Keychain face)

    /// Whether a key exists (a probe, not a read — the secret never leaves
    /// the keychain for this face).
    var hasAPIKey: Bool {
        guard let key = try? AICredentialStore.read(keychainAccount)
        else { return false }
        var scratch = key
        scratch.resetBytes(in: 0..<scratch.count)
        return true
    }

    /// Store (or overwrite) the key body. Keychain-only — defaults untouched.
    func storeAPIKey(_ secret: String) throws {
        try AICredentialStore.save(Data(secret.utf8), account: keychainAccount)
    }

    /// Remove the key body (idempotent — the settings reset never errors on
    /// an already-empty keychain).
    func deleteAPIKey() throws {
        try AICredentialStore.delete(keychainAccount)
    }

    // MARK: - Connection test (the inline ping)

    enum ConnectionTestOutcome: Equatable {
        /// The provider answered a parseable completion.
        case ok
        /// No key configured — the test cannot even be attempted.
        case missingKey
        /// No connection configured.
        case missingConnection
        /// The endpoint failed admission (never any wire traffic).
        case refusedEndpoint
        /// The round trip failed — the provider/transport's typed message
        /// (key-free by the 04 red line).
        case failed(String)
    }

    /// One minimal completion round trip ("ping", no image). Single shot —
    /// the D-9 no-retry discipline.
    func testConnection(
        transport: AISession = URLSessionTransport()
    ) async -> ConnectionTestOutcome {
        guard let config = connection() else { return .missingConnection }
        guard AIEndpointPolicy.isAuthorized(config.baseURL) else {
            return .refusedEndpoint
        }
        guard let key = try? AICredentialStore.read(keychainAccount), !key.isEmpty
        else { return .missingKey }
        do {
            _ = try await AIProviderClient.complete(
                AICompletionRequest(
                    systemText: nil, userText: "ping", imageJPEG: nil),
                config: config, apiKey: key, transport: transport)
            var scratch = key
            scratch.resetBytes(in: 0..<scratch.count)
            return .ok
        } catch {
            var scratch = key
            scratch.resetBytes(in: 0..<scratch.count)
            return .failed("\(error)")
        }
    }
}

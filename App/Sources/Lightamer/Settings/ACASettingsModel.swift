import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// ACASettingsModel (Plan M2-10-07 T1, KD-2) — the Advanced Content Analysis
// settings page's pure-logic face (the LibraryInspectorModel shape: all
// dependencies injected, zero business logic in the view).
//
// OWNERSHIP:
//   • the connection form (protocol / baseURL / model) over
//     `LibraryConnectionStore` — the ADMISSION GATE runs on every baseURL
//     edit (KD-2: 拒绝 = 行内红字 typed 文案，禁到请求时才失败), and an
//     unauthorized endpoint is never stored (the store backstops too);
//   • the key face (SecureField → Keychain save / clear + the presence
//     line + the 「未配置」 banner state);
//   • the rating preferences (strictness 1-5 + output language — the
//     `AIRatingService.rubric` consumption face, straight through);
//   • the 不再询问 toggle over `RatingConfirmPreferences` (the OQ-11-A
//     preference; the 04 handoff's ACA-page assignment);
//   • the connection test (one minimal ping, the outcome inline).
//
// The label key bodies NEVER enter this model's state beyond the SecureField
// buffer the user is typing (cleared on save/clear) — the 04 red line.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class ACASettingsModel {

    // MARK: - Dependencies (injected; tests drive every seam)

    private let store: LibraryConnectionStore
    private let ratingConfirm: RatingConfirmPreferences
    private let transport: AISession
    /// The system-localizations probe seam (`system` language resolution;
    /// the production default reads Host's preferred localizations).
    private let preferredLocalizations: @Sendable () -> [String]

    // MARK: - Observable state

    private(set) var provider: AIProviderProtocol = .openAIChatCompletions
    var baseURLText: String = ""
    var modelText: String = ""
    private(set) var strictness: Int = LibraryConnectionStore.defaultStrictness
    private(set) var language: AIOutputLanguage = .system
    private(set) var keyPresent = false
    private(set) var testOutcome: LibraryConnectionStore.ConnectionTestOutcome?
    private(set) var testRunning = false
    /// The connection/key write feedback line (nil = nothing pending).
    private(set) var statusLine: String?

    init(
        store: LibraryConnectionStore = LibraryConnectionStore(),
        ratingConfirm: RatingConfirmPreferences = RatingConfirmPreferences(),
        transport: AISession = URLSessionTransport(),
        preferredLocalizations: @escaping @Sendable () -> [String] = {
            Locale.preferredLanguages
        }
    ) {
        self.store = store
        self.ratingConfirm = ratingConfirm
        self.transport = transport
        self.preferredLocalizations = preferredLocalizations
    }

    // MARK: - Load (the page's onAppear)

    func load() {
        if let config = store.connection() {
            provider = config.protocol
            baseURLText = config.baseURL.absoluteString
            modelText = config.model
        }
        strictness = store.strictness()
        language = store.outputLanguage()
        keyPresent = store.hasAPIKey
    }

    // MARK: - Form commits (the view routes changes through these)

    func setProvider(_ provider: AIProviderProtocol) {
        self.provider = provider
        commitConnection()
    }

    func setStrictness(_ value: Int) {
        strictness = min(max(value, 1), 5)
        store.storeStrictness(strictness)
    }

    func setLanguage(_ language: AIOutputLanguage) {
        self.language = language
        store.storeOutputLanguage(language)
    }

    /// The rubric-facing language (the runner's resolution of `system`).
    var resolvedLanguage: AIRatingLanguage {
        language.resolved(preferredLocalizations: preferredLocalizations())
    }

    /// The 不再询问 toggle (the OQ-11-A preference face).
    var skipRatingConfirmation: Bool {
        get { ratingConfirm.skipConfirmation }
        set { ratingConfirm.setSkipConfirmation(newValue) }
    }

    // MARK: - The admission gate (KD-2)

    /// The typed refusal copy for the CURRENT baseURL text, or nil when the
    /// text is admissible (or empty = unconfigured). Pure and deterministic —
    /// the test pins it per admission matrix leg.
    var endpointRejection: String? {
        Self.endpointRejection(for: baseURLText)
    }

    nonisolated static func endpointRejection(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil
        else {
            return String(
                localized: "settings_aca_endpoint_invalid",
                defaultValue: "Not a valid URL — enter the provider's base URL.")
        }
        guard case .failure(let failure) = AIEndpointPolicy.authorize(url) else {
            return nil
        }
        if case .insecureEndpoint = failure {
            return String(
                localized: "settings_aca_endpoint_insecure",
                defaultValue: "Refused: only https:// endpoints are allowed (http:// is limited to localhost/127.0.0.1/::1 dev hosts). The connection is not saved.")
        }
        return nil
    }

    /// Whether the form is complete enough to store (the save button's gate).
    var connectionStorable: Bool {
        endpointRejection == nil
            && !baseURLText.trimmingCharacters(in: .whitespaces).isEmpty
            && !modelText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Store the form's connection (whole-connection replacement). A change
    /// stores immediately — the form IS the stored truth on success.
    func commitConnection() {
        guard connectionStorable else { return }
        let trimmedURL = baseURLText.trimmingCharacters(in: .whitespaces)
        let trimmedModel = modelText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmedURL) else { return }
        do {
            try store.store(AIConnectionConfig(
                protocol: provider, baseURL: url, model: trimmedModel))
            statusLine = nil
        } catch {
            statusLine = Self.endpointRejection(for: trimmedURL)
        }
    }

    // MARK: - The key face

    /// The 「未配置」 banner state: a connection needs the key for anything
    /// to actually run (the rating/description commands' guidance root).
    var needsSetup: Bool { !keyPresent }

    func saveKey(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.storeAPIKey(trimmed)
            keyPresent = true
            statusLine = String(
                localized: "settings_aca_key_saved",
                defaultValue: "API key stored in the Keychain.")
        } catch {
            statusLine = String(
                localized: "settings_aca_key_save_failed \(String(describing: error))")
        }
    }

    func deleteKey() {
        do {
            try store.deleteAPIKey()
            keyPresent = false
            statusLine = String(
                localized: "settings_aca_key_cleared",
                defaultValue: "API key removed from the Keychain.")
        } catch {
            statusLine = String(
                localized: "settings_aca_key_clear_failed \(String(describing: error))")
        }
    }

    // MARK: - The connection test (the inline ping)

    func runConnectionTest() async {
        guard !testRunning else { return }
        testRunning = true
        defer { testRunning = false }
        testOutcome = await store.testConnection(transport: transport)
    }

    /// The test outcome's line copy (nil outcome = no line).
    var testOutcomeLine: String? {
        switch testOutcome {
        case .ok:
            String(localized: "settings_aca_test_ok",
                   defaultValue: "Connection OK — the provider answered.")
        case .missingKey:
            String(localized: "settings_aca_test_missing_key",
                   defaultValue: "No API key configured — save a key first.")
        case .missingConnection:
            String(localized: "settings_aca_test_missing_connection",
                   defaultValue: "No connection configured yet.")
        case .refusedEndpoint:
            String(localized: "settings_aca_test_refused",
                   defaultValue: "Endpoint refused by the local policy — nothing was sent.")
        case .failed(let message):
            String(localized: "settings_aca_test_failed \(message)")
        case nil:
            nil
        }
    }
}

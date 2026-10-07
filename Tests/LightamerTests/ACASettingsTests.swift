import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// ACASettingsTests (Plan M2-10-07 T1, AC#2) — the ACA settings page's model
// face over an ISOLATED defaults suite + a URLProtocol-mocked transport
// (zero real network) + a UUID-suffixed keychain account (the 04 discipline —
// the real `rating-provider` slot is never touched):
//
//   • connection round-trip (store → load, whole-replacement semantics)
//   • THE KEY NEVER ENTERS DEFAULTS (the E4 red line's storage half): the
//     defaults suite is dumped WHOLE after a key save — no value carries the
//     key substring
//   • the admission gate: insecure baseURL = typed inline refusal + NOTHING
//     stored; https + loopback pass (the 04 admission matrix, UI face)
//   • the connection test: mock 2xx → .ok; 500 → .failed; missing key →
//     .missingKey; no connection → .missingConnection; insecure →
//     .refusedEndpoint (zero wire traffic)
//   • strictness clamps into 1...5; language round-trips; the OQ-11-A
//     不再询问 toggle round-trips and resets
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// The URLProtocol mock (the AIProviderClientTests shape) — FILE-SCOPE so it
// does not inherit the @MainActor test-case isolation (URLProtocol subclass
// methods must stay nonisolated; session queues call them).
// ─────────────────────────────────────────────────────────────────────────────

final class ACAStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder:
        (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let (status, data) = Self.responder?(self.request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: self.request.url ?? URL(string: "about:blank")!,
            statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(
            self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class ACASettingsTests: XCTestCase {

    private var suiteName: String!
    private var account: String!
    private var probeAccount: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.aca.\(UUID().uuidString)"
        account = "rating-provider-acatest-\(UUID().uuidString)"
        probeAccount = "rating-provider-acaprobe-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? AICredentialStore.delete(account ?? "")
        try? AICredentialStore.delete(probeAccount ?? "")
        super.tearDown()
    }

    /// The resource gate: a real login keychain is required for the key-face
    /// legs. Absent (CI / lock screen) → XCTSkip (the auditable skip face).
    private func requireKeychain() throws {
        do {
            try AICredentialStore.save(Data([0x01]), account: probeAccount!)
        } catch let error as AICredentialStore.CredentialError {
            throw XCTSkip("keychain unavailable in this environment: \(error)")
        }
    }

    private func makeStore() -> LibraryConnectionStore {
        LibraryConnectionStore(
            defaultsSuiteName: suiteName, keychainAccount: account!)
    }

    private func makeModel(
        transport: AISession = FailingTransport()
    ) -> ACASettingsModel {
        ACASettingsModel(
            store: makeStore(), transport: transport,
            preferredLocalizations: { ["en"] })
    }

    /// The connection test's no-network guard: any call through this fails
    /// typed — a leg that MUST reach the wire turns red here.
    private struct FailingTransport: AISession {
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.unsupportedURL)
        }
    }

    private func mockTransport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ACAStubURLProtocol.self]
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    private let chatBody = Data("""
    {"choices":[{"message":{"content":"pong"},"finish_reason":"stop"}]}
    """.utf8)

    // MARK: - 1: connection round-trip

    func testConnectionRoundTripThroughIsolatedSuite() throws {
        let store = makeStore()
        XCTAssertNil(store.connection(), "an empty suite is unconfigured")
        let config = AIConnectionConfig(
            protocol: .anthropicMessages,
            baseURL: URL(string: "https://api.anthropic.com")!,
            model: "claude-test", timeout: 42)
        try store.store(config)
        let loaded = try XCTUnwrap(store.connection())
        XCTAssertEqual(loaded.protocol, .anthropicMessages)
        XCTAssertEqual(loaded.baseURL, config.baseURL)
        XCTAssertEqual(loaded.model, "claude-test")
        XCTAssertEqual(loaded.timeout, 42)
        // Whole replacement: a second store wins.
        try store.store(AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: "gpt-test"))
        XCTAssertEqual(try XCTUnwrap(store.connection()).model, "gpt-test")
    }

    func testStoreRefusesAnUnauthorizedEndpoint() {
        let store = makeStore()
        XCTAssertThrowsError(try store.store(AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "http://attacker.example/v1")!,
            model: "m")))
        XCTAssertNil(store.connection(), "the refused endpoint is never stored")
    }

    // MARK: - 2: the key never enters defaults (E4 storage half)

    func testKeyNeverEntersDefaultsDump() throws {
        try requireKeychain()
        let store = makeStore()
        let secret = "sk-lightamer-leak-hunter-\(UUID().uuidString)"
        try store.storeAPIKey(secret)
        defer { try? store.deleteAPIKey() }
        XCTAssertTrue(store.hasAPIKey)

        // The WHOLE suite dump — every defaults value in everyplist-relevant
        // form must be free of the key substring.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let dictionary = defaults.dictionaryRepresentation()
        for (key, value) in dictionary {
            let rendered = "\(key)=\(value)"
            XCTAssertFalse(
                rendered.contains(secret),
                "the key leaked into defaults under \(key)")
        }
        // And the connection payload (a different config face) too.
        try? store.store(AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "m"))
        for (key, value) in defaults.dictionaryRepresentation() {
            XCTAssertFalse(
                "\(key)=\(value)".contains(secret),
                "the key leaked into defaults under \(key)")
        }
        // Remove the key; the presence probe flips off (idempotent delete).
        try store.deleteAPIKey()
        XCTAssertFalse(store.hasAPIKey)
        try store.deleteAPIKey()  // idempotent — no error on the second call
        XCTAssertFalse(store.hasAPIKey)
    }

    // MARK: - 3: the admission gate (KD-2 inline refusal)

    func testAdmissionGateRefusesInsecureEndpointInline() {
        let model = makeModel()
        model.baseURLText = "http://attacker.example/v1"
        model.modelText = "m"
        XCTAssertNotNil(model.endpointRejection, "insecure endpoint = inline typed refusal")
        model.commitConnection()
        XCTAssertNil(
            makeStore().connection(),
            "a refused endpoint is never stored — the request-time gate must never be the first line")
        // The save gate matches (the button's disabled face).
        XCTAssertFalse(model.connectionStorable)
    }

    func testAdmissionGatePassesHTTPSAndLoopback() {
        let model = makeModel()
        model.baseURLText = "https://api.openai.com/v1"
        XCTAssertNil(model.endpointRejection)
        model.modelText = "gpt-test"
        model.commitConnection()
        XCTAssertEqual(makeStore().connection()?.model, "gpt-test")

        model.baseURLText = "http://localhost:11434/v1"
        XCTAssertNil(
            model.endpointRejection,
            "the loopback dev exception has no toggle (D-5)")
        model.baseURLText = "not a url"
        XCTAssertNotNil(model.endpointRejection, "unparseable text refuses")
    }

    // MARK: - 4: the connection test (mock round-trip)

    func testConnectionTestMockRoundTrip() async throws {
        try requireKeychain()
        let store = makeStore()
        try store.store(AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "gpt-test"))
        try store.storeAPIKey("sk-mock-roundtrip-\(UUID().uuidString)")
        defer { try? store.deleteAPIKey() }

        let body = chatBody
        ACAStubURLProtocol.responder = { _ in (200, body) }
        let okModel = makeModel(transport: mockTransport())
        await okModel.runConnectionTest()
        XCTAssertEqual(okModel.testOutcome, .ok)

        // A provider error maps to the typed failed outcome (key-free).
        ACAStubURLProtocol.responder = { _ in
            (500, Data(#"{"error":{"message":"overloaded"}}"#.utf8))
        }
        let failedModel = makeModel(transport: mockTransport())
        await failedModel.runConnectionTest()
        XCTAssertEqual(
            failedModel.testOutcome,
            .failed("providerError(status: 500, message: \"overloaded\")"))

        // No key → the test cannot even be attempted.
        try store.deleteAPIKey()
        let missingKeyModel = makeModel(transport: mockTransport())
        await missingKeyModel.runConnectionTest()
        XCTAssertEqual(missingKeyModel.testOutcome, .missingKey)
    }

    func testConnectionTestRefusalsNeverTouchTheWire() async throws {
        let model = makeModel()
        // No connection at all.
        await model.runConnectionTest()
        XCTAssertEqual(model.testOutcome, .missingConnection)

        // A forced-insecure stored payload (bypassing the store's own
        // admission backstop via the raw defaults face) → the local
        // refusal; the FailingTransport default proves zero wire traffic.
        let payload = try JSONEncoder().encode(InsecurePayload())
        UserDefaults(suiteName: suiteName)!
            .set(payload, forKey: LibraryConnectionStore.connectionKey)
        await model.runConnectionTest()
        XCTAssertEqual(model.testOutcome, .refusedEndpoint)
    }

    /// The raw-payload carrier for the forced-insecure leg (the same shape
    /// LibraryConnectionStore's envelope encodes).
    private struct InsecurePayload: Encodable {
        let protocolRaw = "openAIChatCompletions"
        let baseURL = "http://attacker.example/v1"
        let model = "m"
        let timeout = 10.0
    }

    // MARK: - 5: strictness / language / the 不再询问 toggle

    func testStrictnessClampsAndLanguagePersists() {
        let store = makeStore()
        XCTAssertEqual(
            store.strictness(),
            LibraryConnectionStore.defaultStrictness,
            "an absent key reads the default")
        store.storeStrictness(0)
        XCTAssertEqual(store.strictness(), 1, "clamped into range")
        store.storeStrictness(9)
        XCTAssertEqual(store.strictness(), 5, "clamped into range")
        store.storeStrictness(4)
        XCTAssertEqual(store.strictness(), 4)

        XCTAssertEqual(store.outputLanguage(), .system, "absent = system")
        store.storeOutputLanguage(.chinese)
        XCTAssertEqual(store.outputLanguage(), .chinese)

        // The `system` resolution seam: zh preferred → Chinese, else English.
        XCTAssertEqual(
            AIOutputLanguage.system.resolved(preferredLocalizations: ["zh-Hans"]),
            .chinese)
        XCTAssertEqual(
            AIOutputLanguage.system.resolved(preferredLocalizations: ["en"]),
            .english)
        XCTAssertEqual(AIOutputLanguage.chinese.resolved(preferredLocalizations: []), .chinese)

        // The model surface round-trips the same keys.
        let model = makeModel()
        model.setStrictness(2)
        model.setLanguage(.english)
        XCTAssertEqual(store.strictness(), 2)
        XCTAssertEqual(store.outputLanguage(), .english)
        XCTAssertEqual(model.resolvedLanguage, .english)
    }

    func testRatingConfirmToggleRoundTripsAndResets() {
        let preferences = RatingConfirmPreferences(defaultsSuiteName: suiteName)
        let model = ACASettingsModel(
            store: makeStore(), ratingConfirm: preferences)
        XCTAssertFalse(model.skipRatingConfirmation, "default = always confirm")
        model.skipRatingConfirmation = true
        XCTAssertTrue(preferences.skipConfirmation)
        model.skipRatingConfirmation = false
        XCTAssertFalse(preferences.skipConfirmation)
        // The reset face returns to confirm-always.
        preferences.setSkipConfirmation(true)
        preferences.reset()
        XCTAssertFalse(preferences.skipConfirmation)
    }

    // MARK: - 6: the page model load face

    func testLoadSeedsTheFormFromTheStore() throws {
        let store = makeStore()
        try store.store(AIConnectionConfig(
            protocol: .anthropicMessages,
            baseURL: URL(string: "https://api.anthropic.com")!,
            model: "claude-test"))
        store.storeStrictness(5)
        store.storeOutputLanguage(.english)
        try requireKeychain()
        try store.storeAPIKey("sk-load-seed")
        defer { try? store.deleteAPIKey() }

        let model = makeModel()
        model.load()
        XCTAssertEqual(model.provider, .anthropicMessages)
        XCTAssertEqual(model.baseURLText, "https://api.anthropic.com")
        XCTAssertEqual(model.modelText, "claude-test")
        XCTAssertEqual(model.strictness, 5)
        XCTAssertEqual(model.language, .english)
        XCTAssertTrue(model.keyPresent)
        XCTAssertFalse(model.needsSetup, "a stored key clears the banner")
    }
}

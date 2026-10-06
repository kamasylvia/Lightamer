import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AIProviderClientTests (Plan M2-10-04 T2, AC#2/3 + E4) — the dual-protocol
// golden face over a REAL URLSession stacked on a URLProtocol mock (ZERO real
// network — the transport seam IS the design face, the mock is a legal缝):
//
//   • request goldens, field by field: URL join rules (openAI base+version →
//     /chat/completions; anthropic bare host → /v1/messages), auth headers
//     (Bearer / x-api-key + anthropic-version), the vision payload bytes
//     round-trip through the base64 body parts, timeoutInterval = config
//   • response decode: choices[0].message.content + finish_reason (openAI),
//     text-block concatenation + stop_reason (anthropic)
//   • error mapping: BOTH provider error-body shapes → typed .providerError,
//     non-JSON body → truncated raw, malformed 2xx → .malformedResponse
//   • cancellation: a hanging mock + task cancel → .cancelled (native
//     URLSessionTask semantics; the timeout INTERVAL is config-golden-pinned
//     instead of wall-clock-waited — DECISIONS note)
//   • E4: the key appears ONLY in the auth header; every typed error's text
//     is key-free; the caller-side zeroize contract (read → use → scrub)
//   • AIJSON.extractObject four golden shapes
//   • the send-side policy gate refuses insecure bases BEFORE any request
// ─────────────────────────────────────────────────────────────────────────────

final class AIProviderClientTests: XCTestCase {

    // MARK: - The URLProtocol mock

    /// Records requests; serves a stubbed (response, data). Thread-safe via
    /// a lock (URLProtocol methods arrive on session queues).
    final class StubURLProtocol: URLProtocol {
        struct Exchange {
            let requestURL: URL
            let method: String
            let headers: [String: String]
            let body: Data
            let timeoutInterval: TimeInterval
        }

        nonisolated(unsafe) static var responder:
            (@Sendable (URLRequest) -> (Int, Data))?
        private static let lock = NSLock()
        nonisolated(unsafe) private static var _recorded: [Exchange] = []

        static func reset() {
            lock.lock()
            _recorded = []
            responder = nil
            lock.unlock()
        }

        static func record(_ exchange: Exchange) {
            lock.lock()
            _recorded.append(exchange)
            lock.unlock()
        }

        static var recorded: [Exchange] {
            lock.lock()
            defer { lock.unlock() }
            return _recorded
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        /// URLSession hands the body as a STREAM to URLProtocol — drain it.
        static func bodyData(of request: URLRequest) -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }

        override func startLoading() {
            let request = self.request
            Self.record(Exchange(
                requestURL: request.url ?? URL(string: "about:blank")!,
                method: request.httpMethod ?? "GET",
                headers: request.allHTTPHeaderFields ?? [:],
                body: Self.bodyData(of: request),
                timeoutInterval: request.timeoutInterval))
            guard let responder = Self.responder else {
                client?.urlProtocol(
                    self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            let (status, data) = responder(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "about:blank")!,
                statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(
                self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeTransport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    private let key = Data("sk-lightamer-golden-key-42".utf8)
    private let keyString = "sk-lightamer-golden-key-42"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private var openAIConfig: AIConnectionConfig {
        AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "gpt-test")
    }

    private var anthropicConfig: AIConnectionConfig {
        AIConnectionConfig(
            protocol: .anthropicMessages,
            baseURL: URL(string: "https://api.example.com")!,
            model: "claude-test")
    }

    private func sampleRequest() -> AICompletionRequest {
        AICompletionRequest(
            systemText: "system-prompt-text",
            userText: "user-instruction",
            imageJPEG: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0x04]))
    }

    private func serve(status: Int, body: String) {
        StubURLProtocol.responder = { _ in (status, Data(body.utf8)) }
    }

    // MARK: - URL join rules (the plan's golden-pin)

    func testOpenAIEndpointJoinsChatCompletionsOnVersionedBase() {
        let url = AIProviderClient.endpointURL(for: openAIConfig)
        XCTAssertEqual(
            url.absoluteString, "https://api.example.com/v1/chat/completions")
        // A trailing-slash base must not double the slash.
        let slashed = AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            model: "m")
        XCTAssertEqual(
            AIProviderClient.endpointURL(for: slashed).absoluteString,
            "http://localhost:11434/v1/chat/completions")
    }

    func testAnthropicEndpointJoinsV1MessagesOnBareHost() {
        let url = AIProviderClient.endpointURL(for: anthropicConfig)
        XCTAssertEqual(
            url.absoluteString, "https://api.example.com/v1/messages")
    }

    // MARK: - openAI request golden

    func testOpenAIRequestGoldenFieldByField() async throws {
        serve(status: 200, body: """
            {"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}
            """)
        _ = try await AIProviderClient.complete(
            sampleRequest(), config: openAIConfig, apiKey: key,
            transport: makeTransport())
        let exchange = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(exchange.method, "POST")
        XCTAssertEqual(
            exchange.requestURL.absoluteString,
            "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(
            exchange.headers["Authorization"], "Bearer \(keyString)")
        XCTAssertEqual(
            exchange.headers["Content-Type"], "application/json")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exchange.body)
                as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-test")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(
            (messages[0]["content"] as? [[String: Any]])?.first?["text"]
                as? String, "system-prompt-text")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        let userParts = try XCTUnwrap(
            messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(userParts.count, 2)
        XCTAssertEqual(userParts[0]["type"] as? String, "text")
        XCTAssertEqual(userParts[1]["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(
            (userParts[1]["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertTrue(imageURL.hasPrefix("data:image/jpeg;base64,"))
        // The vision payload bytes survive the base64 round trip EXACTLY.
        let payload = try XCTUnwrap(Data(base64Encoded: String(
            imageURL.dropFirst("data:image/jpeg;base64,".count))))
        XCTAssertEqual(payload, sampleRequest().imageJPEG)
    }

    // MARK: - anthropic request golden

    func testAnthropicRequestGoldenFieldByField() async throws {
        serve(status: 200, body: """
            {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn"}
            """)
        _ = try await AIProviderClient.complete(
            sampleRequest(), config: anthropicConfig, apiKey: key,
            transport: makeTransport())
        let exchange = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(
            exchange.requestURL.absoluteString,
            "https://api.example.com/v1/messages")
        XCTAssertEqual(exchange.headers["x-api-key"], keyString)
        XCTAssertEqual(exchange.headers["anthropic-version"], "2023-06-01")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exchange.body)
                as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-test")
        XCTAssertEqual(body["max_tokens"] as? Int, AIProviderClient.maxTokens)
        XCTAssertEqual(body["system"] as? String, "system-prompt-text")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        // anthropic puts the image FIRST (the recommended block order).
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        let source = try XCTUnwrap(blocks[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        let payload = try XCTUnwrap(Data(base64Encoded: source["data"] as! String))
        XCTAssertEqual(payload, sampleRequest().imageJPEG)
        XCTAssertEqual(blocks[1]["type"] as? String, "text")
        XCTAssertEqual(blocks[1]["text"] as? String, "user-instruction")
    }

    // MARK: - response decode

    func testOpenAIResponseDecodesContentAndFinishReason() async throws {
        serve(status: 200, body: """
            {"id":"x","choices":[{"message":{"role":"assistant","content":"hello world"},"finish_reason":"stop"}],"usage":{}}
            """)
        let result = try await AIProviderClient.complete(
            sampleRequest(), config: openAIConfig, apiKey: key,
            transport: makeTransport())
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.finishReason, "stop")
    }

    func testAnthropicResponseConcatenatesTextBlocks() async throws {
        serve(status: 200, body: """
            {"content":[{"type":"text","text":"first "},{"type":"tool_use","id":"t"},{"type":"text","text":"second"}],"stop_reason":"end_turn"}
            """)
        let result = try await AIProviderClient.complete(
            sampleRequest(), config: anthropicConfig, apiKey: key,
            transport: makeTransport())
        XCTAssertEqual(result.text, "first second")
        XCTAssertEqual(result.finishReason, "end_turn")
    }

    func testMalformed2xxBodyIsTyped() async {
        serve(status: 200, body: "{\"unexpected\":true}")
        do {
            _ = try await AIProviderClient.complete(
                sampleRequest(), config: openAIConfig, apiKey: key,
                transport: makeTransport())
            XCTFail("expected malformedResponse")
        } catch let error as AIProviderError {
            XCTAssertEqual(
                error, .malformedResponse(
                    "openAI response has no choices[0].message.content"))
        } catch {
            XCTFail("wrong error family: \(error)")
        }
    }

    // MARK: - error-body mapping (the dual shape)

    func testOpenAIErrorBodyMapsToTypedProviderError() async {
        serve(status: 429, body: """
            {"error":{"message":"Rate limit reached","type":"requests","code":"rate_limit"}}
            """)
        await assertProviderError(status: 429, message: "Rate limit reached")
        // M2-10-07 (the M2-10-04 acceptance O-2 consumption): the no-retry
        // automaton's EXPLICIT pin — exactly ONE request hit the wire; the
        // user re-runs by hand (the fee-storm guard, D-9).
        XCTAssertEqual(StubURLProtocol.recorded.count, 1)
    }

    func testAnthropicErrorBodyMapsToTypedProviderError() async {
        serve(status: 500, body: """
            {"type":"error","error":{"type":"api_error","message":"Overloaded"}}
            """)
        await assertProviderError(status: 500, message: "Overloaded")
    }

    func testNonJSONErrorBodyDegradesToTruncatedRaw() async {
        serve(status: 502, body: "<html>bad gateway</html>")
        do {
            _ = try await AIProviderClient.complete(
                sampleRequest(), config: openAIConfig, apiKey: key,
                transport: makeTransport())
            XCTFail("expected providerError")
        } catch let error as AIProviderError {
            guard case .providerError(let status, let message) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(status, 502)
            XCTAssertEqual(message, "<html>bad gateway</html>")
        } catch {
            XCTFail("wrong error family: \(error)")
        }
    }

    private func assertProviderError(
        status: Int, message: String, line: UInt = #line
    ) async {
        do {
            _ = try await AIProviderClient.complete(
                sampleRequest(), config: openAIConfig, apiKey: key,
                transport: makeTransport())
            XCTFail("expected providerError", line: line)
        } catch let error as AIProviderError {
            XCTAssertEqual(
                error, .providerError(status: status, message: message),
                line: line)
        } catch {
            XCTFail("wrong error family: \(error)", line: line)
        }
    }

    // MARK: - cancellation + the timeout config

    func testTaskCancellationSurfacesTyped() async throws {
        StubURLProtocol.responder = { _ in
            // A hanging upstream: the mock blocks the session queue until
            // the task cancel tears the transfer down.
            Thread.sleep(forTimeInterval: 5)
            return (200, Data("{}".utf8))
        }
        // Sendable locals only inside the detached work (L038 discipline).
        let request = sampleRequest()
        let config = openAIConfig
        let keyCopy = key
        let transport = makeTransport()
        let task = Task {
            try await AIProviderClient.complete(
                request, config: config, apiKey: keyCopy, transport: transport)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancelled")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("wrong error family: \(error)")
        }
    }

    func testTimeoutIntervalRidesTheConfig() async throws {
        let config = AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "m", timeout: 37)
        serve(status: 200, body: """
            {"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
            """)
        _ = try await AIProviderClient.complete(
            sampleRequest(), config: config, apiKey: key,
            transport: makeTransport())
        let exchange = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(exchange.timeoutInterval, 37)
    }

    // MARK: - the send-side policy gate

    func testInsecureBaseURLRefusedBeforeAnyWireTraffic() async {
        let insecure = AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "http://example.com/v1")!,
            model: "m")
        do {
            _ = try await AIProviderClient.complete(
                sampleRequest(), config: insecure, apiKey: key,
                transport: makeTransport())
            XCTFail("expected insecureEndpoint")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .insecureEndpoint(insecure.baseURL))
        } catch {
            XCTFail("wrong error family: \(error)")
        }
        XCTAssertTrue(
            StubURLProtocol.recorded.isEmpty,
            "the gate must refuse BEFORE the transport sees anything")
    }

    func testLoopbackHTTPBaseIsAdmittedAtTheTransportGate() async throws {
        let local = AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "http://localhost:11434/v1")!,
            model: "llama")
        serve(status: 200, body: """
            {"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
            """)
        _ = try await AIProviderClient.complete(
            sampleRequest(), config: local, apiKey: key,
            transport: makeTransport())
        XCTAssertEqual(
            StubURLProtocol.recorded.first?.requestURL.absoluteString,
            "http://localhost:11434/v1/chat/completions")
    }

    // MARK: - E4: the key's exposure surface

    func testKeyRidesOnlyTheAuthHeaderAndNeverTheBodyOrErrors() async throws {
        // A provider error body deliberately containing prose — the typed
        // error must stay key-free regardless.
        serve(status: 400, body: """
            {"error":{"message":"invalid request: model not found"}}
            """)
        await assertKeyContainedOnlyInAuthHeader(config: openAIConfig)
        StubURLProtocol.reset()
        await assertKeyContainedOnlyInAuthHeader(config: anthropicConfig)
    }

    private func assertKeyContainedOnlyInAuthHeader(
        config: AIConnectionConfig, line: UInt = #line
    ) async {
        do {
            _ = try await AIProviderClient.complete(
                sampleRequest(), config: config, apiKey: key,
                transport: makeTransport())
        } catch {
            // Every typed error's textual faces are key-free.
            let errorText = String(describing: error)
            XCTAssertFalse(
                errorText.contains(keyString),
                "error text leaked the key", line: line)
        }
        for exchange in StubURLProtocol.recorded {
            let headerHits = exchange.headers.filter {
                $0.value.contains(keyString)
            }
            XCTAssertEqual(headerHits.count, 1, line: line)
            let headerName = headerHits.first?.key.lowercased()
            XCTAssertTrue(
                headerName == "authorization" || headerName == "x-api-key",
                "the key rode an unexpected header: \(headerHits.keys)",
                line: line)
            let bodyText = String(decoding: exchange.body, as: UTF8.self)
            XCTAssertFalse(
                bodyText.contains(keyString),
                "the request BODY must never carry the raw key", line: line)
        }
    }

    func testCallerSideZeroizeContract() {
        // The documented ownership: the caller's buffer is scrubbed after
        // the call; the client's internal copy is scrubbed in a defer (Data
        // CoW keeps the two independent — DECISIONS ownership note).
        var callerBuffer = key
        callerBuffer.resetBytes(in: 0..<callerBuffer.count)
        XCTAssertTrue(callerBuffer.allSatisfy { byte in byte == 0 })
        // The client's scrub does not reach back into the caller's buffer.
        XCTAssertEqual(key, Data(keyString.utf8))
    }

    // MARK: - AIJSON.extractObject (the four golden shapes)

    func testAIJSONBareObject() {
        XCTAssertEqual(
            AIJSON.extractObject(#"{"rating": 4}"#), #"{"rating": 4}"#)
    }

    func testAIJSONFencedObject() {
        let fenced = """
            ```json
            {"rating": 3, "reasons": ["ok"]}
            ```
            """
        XCTAssertEqual(
            AIJSON.extractObject(fenced), #"{"rating": 3, "reasons": ["ok"]}"#)
    }

    func testAIJSONInsideProse() {
        let prose = """
            Sure! Here is my assessment:
            {"rating": 5, "reasons": ["sharp"]}
            Let me know if you need more.
            """
        XCTAssertEqual(
            AIJSON.extractObject(prose), #"{"rating": 5, "reasons": ["sharp"]}"#)
    }

    func testAIJSONMultipleObjectsTakesTheFirst() {
        let two = #"{"a":1} trailing junk {"b":2}"#
        XCTAssertEqual(AIJSON.extractObject(two), #"{"a":1}"#)
    }

    func testAIJSONBracesInsideStringsNeverCount() {
        let tricky = #"{"text":"a } brace and \" an escape {","n":2}"#
        XCTAssertEqual(
            AIJSON.extractObject(tricky),
            #"{"text":"a } brace and \" an escape {","n":2}"#)
    }

    func testAIJSONUnbalancedReturnsNil() {
        XCTAssertNil(AIJSON.extractObject("{\"open\": 1"))
        XCTAssertNil(AIJSON.extractObject("no object at all"))
    }
}

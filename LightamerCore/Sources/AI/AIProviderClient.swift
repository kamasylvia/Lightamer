import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIProviderClient (Plan M2-10-04 KD-2, D-M2-10-CONTEXT-9, OQ-7-A) — the dual
// protocol remote face: OpenAI-compatible `POST {base}/chat/completions` and
// Anthropic `POST {base}/v1/messages`, hand-written Codable, zero SDK, zero
// streaming (the Phase 14「同步 req/resp」precedent).
//
// RED LINES (each one test-pinned in AIProviderClientTests):
//   • the send-side policy gate runs BEFORE the request is built — an
//     insecure baseURL is a typed refusal with zero requests on the wire
//   • the API key rides ONLY the auth header; it never enters the request
//     body, any log line (this file has none), or any error value
//   • the key buffer's internal copy is scrubbed in a `defer` when the call
//     exits; the CALLER owns its buffer and zeroizes it after the call
//     (Data is a CoW value — see DECISIONS for the ownership note)
//   • NO retry automaton (D-9: 重试走 URLSession 原生 = none here) — one
//     shot per call; 429/5xx surface as typed `.providerError` and the USER
//     re-runs (the fee-storm guard: a runaway retry loop bills real money)
//
// VISION PAYLOAD: both flows (cull rating / description) need the model to
// SEE the photograph — the image rides as base64 JPEG in the message parts
// (openAI `image_url` data URL / anthropic base64 source block).
//
// ROBUST PARSE (KD-2): models wrap JSON in ``` fences or prose —
// `AIJSON.extractObject` peels the FIRST balanced JSON object (brace counting
// with string/escape awareness); its four golden shapes are pinned.
// ─────────────────────────────────────────────────────────────────────────────

/// The wire protocol of the single remote connection (OQ-7-A: no template
/// library — one config covers the OpenAI-compatible ecosystem AND Anthropic
/// direct).
public enum AIProviderProtocol: String, Sendable {
    case openAIChatCompletions
    case anthropicMessages
}

/// The single remote connection configuration (OQ-7-A). `baseURL` MUST have
/// passed `AIEndpointPolicy` before a config is stored (the configuration
/// gate); the client re-checks at send time (the transport gate).
public struct AIConnectionConfig: Sendable, Equatable {
    public let `protocol`: AIProviderProtocol
    public let baseURL: URL
    public let model: String
    public var timeout: TimeInterval

    public init(
        protocol: AIProviderProtocol, baseURL: URL, model: String,
        timeout: TimeInterval = 120
    ) {
        self.protocol = `protocol`
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
    }
}

/// The protocol-normalized completion (the ONE result face both protocols
/// fold into: text content parts concatenated + the finish/stop reason).
public struct AICompletionResult: Sendable, Equatable {
    public let text: String
    public let finishReason: String?

    public init(text: String, finishReason: String?) {
        self.text = text
        self.finishReason = finishReason
    }
}

/// The message contract the client sends (rubric/role prompt in `systemText`,
/// the JSON output instruction + any prose in `userText`, the photograph as
/// base64 JPEG in `imageJPEG`).
public struct AICompletionRequest: Sendable {
    public let systemText: String?
    public let userText: String
    public let imageJPEG: Data?

    public init(systemText: String?, userText: String, imageJPEG: Data?) {
        self.systemText = systemText
        self.userText = userText
        self.imageJPEG = imageJPEG
    }
}

public enum AIProviderError: Error, Equatable {
    /// The send-side policy gate refused the endpoint (zero wire traffic).
    case insecureEndpoint(URL)
    /// A non-2xx response — the provider's `error.message` when parseable,
    /// else a truncated raw body. The KEY never appears here.
    case providerError(status: Int, message: String)
    /// A 2xx body that does not decode into the protocol's response shape.
    case malformedResponse(String)
    /// URLError-family transport failures (timeout / offline / …).
    case transportFailed(String)
    /// The task was cancelled (URLSessionTask.cancel semantics, native).
    case cancelled
}

/// The transport seam (KD-2): URLSession in production, a URLProtocol-mocked
/// session in tests (zero real network). The protocol shape mirrors
/// URLSession.data(for:) so the conformer is a thin wrapper.
public protocol AISession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The production conformer.
public struct URLSessionTransport: AISession {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.transportFailed("non-HTTP response")
        }
        return (data, http)
    }
}

public enum AIProviderClient {

    /// The anthropic `max_tokens` floor (a required field; one client
    /// constant — DECISIONS sign: not a config surface in this plan).
    static let maxTokens = 4096

    // MARK: - The one entry point

    /// One completion request. Single shot — no retry automaton (D-9).
    public static func complete(
        _ request: AICompletionRequest,
        config: AIConnectionConfig,
        apiKey: Data,
        transport: AISession
    ) async throws -> AICompletionResult {
        // TRANSPORT GATE (the second of the two policy checks): refuse
        // BEFORE anything touches the wire.
        guard AIEndpointPolicy.isAuthorized(config.baseURL) else {
            throw AIProviderError.insecureEndpoint(config.baseURL)
        }

        let url = endpointURL(for: config)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = config.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // The key's INTERNAL copy — scrubbed on exit. The header string is
        // the only derived form that necessarily exists (HTTP requires it).
        var keyBytes = apiKey
        defer { keyBytes.resetBytes(in: 0..<keyBytes.count) }
        let keyValue = String(decoding: keyBytes, as: UTF8.self)
        switch config.protocol {
        case .openAIChatCompletions:
            urlRequest.setValue(
                "Bearer \(keyValue)", forHTTPHeaderField: "Authorization")
        case .anthropicMessages:
            urlRequest.setValue(keyValue, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue(
                "2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let bodyData: Data
        switch config.protocol {
        case .openAIChatCompletions:
            bodyData = try JSONEncoder().encode(
                openAIBody(request, model: config.model))
        case .anthropicMessages:
            bodyData = try JSONEncoder().encode(
                anthropicBody(request, model: config.model))
        }
        urlRequest.httpBody = bodyData

        let (data, response) = try await send(urlRequest, transport: transport)
        guard (200..<300).contains(response.statusCode) else {
            throw AIProviderError.providerError(
                status: response.statusCode,
                message: Self.errorMessage(from: data))
        }
        return try decodeResponse(data, protocol: config.protocol)
    }

    // MARK: - Endpoint URL join (the golden-pinned rules)

    /// openAI: the user supplies the base INCLUDING the version segment
    /// (`https://api.openai.com/v1`, or `http://localhost:11434/v1` for
    /// ollama) — the client appends `chat/completions`.
    /// anthropic: the bare host — the client appends `v1/messages`.
    public static func endpointURL(for config: AIConnectionConfig) -> URL {
        switch config.protocol {
        case .openAIChatCompletions:
            return appending("chat/completions", to: config.baseURL)
        case .anthropicMessages:
            return appending("v1/messages", to: config.baseURL)
        }
    }

    private static func appending(_ suffix: String, to base: URL) -> URL {
        let separator = base.absoluteString.hasSuffix("/") ? "" : "/"
        return URL(string: base.absoluteString + separator + suffix) ?? base
    }

    // MARK: - Request bodies

    private static func openAIBody(
        _ request: AICompletionRequest, model: String
    ) -> OpenAIRequestBody {
        var messages: [OpenAIMessage] = []
        if let system = request.systemText {
            messages.append(OpenAIMessage(role: "system", content: [.text(system)]))
        }
        var parts: [OpenAIContentPart] = [.text(request.userText)]
        if let jpeg = request.imageJPEG {
            parts.append(.imageDataURL(
                "data:image/jpeg;base64,\(jpeg.base64EncodedString())"))
        }
        messages.append(OpenAIMessage(role: "user", content: parts))
        return OpenAIRequestBody(model: model, messages: messages)
    }

    private static func anthropicBody(
        _ request: AICompletionRequest, model: String
    ) -> AnthropicRequestBody {
        var blocks: [AnthropicContentBlock] = []
        if let jpeg = request.imageJPEG {
            blocks.append(.image(
                source: .init(
                    type: "base64", mediaType: "image/jpeg",
                    data: jpeg.base64EncodedString())))
        }
        blocks.append(.text(request.userText))
        return AnthropicRequestBody(
            model: model,
            maxTokens: maxTokens,
            system: request.systemText,
            messages: [AnthropicMessage(role: "user", content: blocks)])
    }

    // MARK: - Send + error mapping

    private static func send(
        _ request: URLRequest, transport: AISession
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw AIProviderError.cancelled
        } catch is CancellationError {
            throw AIProviderError.cancelled
        } catch let error as URLError {
            throw AIProviderError.transportFailed(error.localizedDescription)
        }
    }

    /// The dual error-body shape: BOTH providers nest `error.message` (the
    /// plan's 双形 note — one decoder serves both); an unparseable body
    /// degrades to a truncated raw text (honest, still key-free).
    static func errorMessage(from data: Data) -> String {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
           let message = body.error?.message, !message.isEmpty {
            return message
        }
        let raw = String(decoding: data.prefix(300), as: UTF8.self)
        return raw.isEmpty ? "(empty error body)" : raw
    }

    // MARK: - Response decode

    private static func decodeResponse(
        _ data: Data, protocol: AIProviderProtocol
    ) throws -> AICompletionResult {
        switch `protocol` {
        case .openAIChatCompletions:
            struct Body: Decodable {
                struct Message: Decodable { let content: String? }
                struct Choice: Decodable {
                    let message: Message?
                    let finishReason: String?
                    enum CodingKeys: String, CodingKey {
                        case message, finishReason = "finish_reason"
                    }
                }
                let choices: [Choice]?
            }
            guard
                let body = try? JSONDecoder().decode(Body.self, from: data),
                let content = body.choices?.first?.message?.content,
                !content.isEmpty
            else {
                throw AIProviderError.malformedResponse(
                    "openAI response has no choices[0].message.content")
            }
            return AICompletionResult(
                text: content, finishReason: body.choices?.first?.finishReason)
        case .anthropicMessages:
            struct Body: Decodable {
                struct Block: Decodable {
                    let type: String?
                    let text: String?
                }
                let content: [Block]?
                let stopReason: String?
                enum CodingKeys: String, CodingKey {
                    case content, stopReason = "stop_reason"
                }
            }
            guard
                let body = try? JSONDecoder().decode(Body.self, from: data),
                let text = body.content?
                    .filter({ $0.type == "text" })
                    .compactMap({ $0.text })
                    .joined(separator: ""),
                !text.isEmpty
            else {
                throw AIProviderError.malformedResponse(
                    "anthropic response has no text content blocks")
            }
            return AICompletionResult(text: text, finishReason: body.stopReason)
        }
    }
}

// MARK: - Wire structs (file-private; the shapes ARE the golden assertions)

private struct OpenAIRequestBody: Encodable {
    let model: String
    let messages: [OpenAIMessage]
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: [OpenAIContentPart]
}

private enum OpenAIContentPart: Encodable {
    case text(String)
    case imageDataURL(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, imageURL = "image_url"
    }

    /// The nested `{"url": …}` object has its OWN key set (reusing the part
    /// keys here would emit `"image_url"` where the spec wants `"url"`).
    private enum ImageURLKeys: String, CodingKey {
        case url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageDataURL(let url):
            try container.encode("image_url", forKey: .type)
            var nested = container.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .imageURL)
            try nested.encode(url, forKey: .url)
        }
    }
}

private struct AnthropicRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicContentBlock]
}

private enum AnthropicContentBlock: Encodable {
    case text(String)
    case image(source: ImageSource)

    struct ImageSource: Encodable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, source
    }
}

// MARK: - AIJSON (the robust output peel, KD-2)

public enum AIJSON {

    /// Return the FIRST balanced JSON object in `raw`, or nil. Handles the
    /// four golden shapes: bare JSON, ```-fenced JSON, JSON inside prose,
    /// and multiple objects (first wins). Brace counting is string-aware
    /// (braces inside string literals and escaped quotes never count).
    public static func extractObject(_ raw: String) -> String? {
        let scalars = Array(raw.unicodeScalars)
        var depth = 0
        var start = -1
        var inString = false
        var escaped = false
        for index in 0..<scalars.count {
            let scalar = scalars[index]
            if escaped {
                escaped = false
                continue
            }
            if inString {
                switch scalar {
                case "\\": escaped = true
                case "\"": inString = false
                default: break
                }
                continue
            }
            switch scalar {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, start >= 0 {
                    let slice = scalars[start...index]
                    return String(String.UnicodeScalarView(slice))
                }
            default:
                break
            }
        }
        return nil
    }
}

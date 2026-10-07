import Foundation
import LightamerCore
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOHTTP1

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 T4: the NIO Streamable HTTP adapter leg.
//
// The SDK's StatefulHTTPServerTransport is a framework-agnostic
// `handleRequest -> HTTPResponse` pure-function face with NO listener (D1) —
// binding 127.0.0.1 needs this ~250-line NIO leg, ported from the SDK's own
// conformance server (Sources/MCPConformance/Server/HTTPApp.swift, the
// shape正本 named by the research). The load-bearing detail the probe
// flattened: each JSON-RPC response rides a REQUEST-SCOPED SSE STREAM —
// `handleJSONRPCRequest` returns `.stream` and the writeResponse stream
// branch MUST pump `AsyncThrowingStream<Data, Error>` into the chunked body
// (first probe version skipped the pump → clients hung forever).
//
// Deltas vs the conformance正本:
//   - start() returns after bind (a HOSTED leg, not a standalone daemon —
//     the GUI host and the headless daemon park on their own).
//   - the per-session transport dictionary has a HARD CAP of 4 (§RQ-14-14);
//     excess initialize requests get 503.
//   - stop() is the graceful-shutdown face: stop accepting → bounded
//     in-flight drain → close all sessions (the controller deletes the
//     discovery json and releases the writer lock around it).
// ─────────────────────────────────────────────────────────────────────────────

/// The Streamable HTTP host leg: one NIO listener, one transport per client
/// session (single transport = single session — §RQ-14-1③), every session's
/// Server built by the caller's factory over the SAME registry kernel.
actor McpHTTPHost {

    // MARK: Configuration

    struct Configuration: Sendable {
        /// D-14-CONTEXT-6①: the loopback binding is a HARDCODED CONSTANT —
        /// not a default, a floor (no settings item may move it; non-loopback
        /// exposure is a separate explicit branch that also demands Bearer).
        var host: String
        /// 0 = ask the kernel for an ephemeral port; the ACTUAL port is read
        /// back after bind (the discovery file carries the real number).
        var port: Int
        var endpoint: String
        var sessionTimeout: TimeInterval
        var maxSessions: Int

        init(
            host: String = McpHTTPHost.loopbackHost,
            port: Int = 0,
            endpoint: String = "/mcp",
            sessionTimeout: TimeInterval = 3600,
            maxSessions: Int = 4
        ) {
            self.host = host
            self.port = port
            self.endpoint = endpoint
            self.sessionTimeout = sessionTimeout
            self.maxSessions = maxSessions
        }
    }

    static let loopbackHost = "127.0.0.1"
    static let defaultMaxSessions = 4

    typealias ServerFactory =
        @Sendable (_ transport: StatefulHTTPServerTransport) async throws -> Server

    private struct SessionContext {
        let server: Server
        let transport: StatefulHTTPServerTransport
        let createdAt: Date
        var lastAccessedAt: Date
    }

    private let configuration: Configuration
    private let serverFactory: ServerFactory
    private let validationPipeline: (any HTTPRequestValidationPipeline)?
    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?
    private var sessions: [String: SessionContext] = [:]
    private var cleanupTask: Task<Void, Never>?
    private var inFlightRequests = 0
    private var stopping = false

    // MARK: Init

    init(
        configuration: Configuration = Configuration(),
        validationPipeline: (any HTTPRequestValidationPipeline)? = nil,
        serverFactory: @escaping ServerFactory
    ) {
        self.configuration = configuration
        self.serverFactory = serverFactory
        self.validationPipeline = validationPipeline
    }

    // MARK: Lifecycle

    /// Binds the listener and starts accepting. Returns after bind — the
    /// actual (possibly ephemeral) port is readable through `boundPort`.
    func start() async throws {
        guard channel == nil else { return }
        stopping = false
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(host: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let boundHost = configuration.host
        let boundPortWanted = configuration.port
        let boundEndpoint = configuration.endpoint
        AppError.logger.info(
            "mcp: HTTP leg binding \(boundHost):\(boundPortWanted) \(boundEndpoint)")
        let channel = try await bootstrap.bind(
            host: configuration.host, port: configuration.port).get()
        self.channel = channel
        self.group = group
        cleanupTask = Task { await sessionCleanupLoop() }
    }

    /// The port actually bound (the discovery file's `port` source).
    var boundPort: Int? {
        channel?.localAddress?.port
    }

    /// Graceful stop (§RQ-14-14 停机处置): stop accepting → bounded drain of
    /// in-flight requests (render-class work "finishes into the void", the
    /// QL boundedWait posture) → close all session transports. The CALLER
    /// owns the discovery-file deletion and the flock release around this.
    func stop(drainTimeout: Duration = McpTimeouts.shutdownDrain) async {
        stopping = true
        cleanupTask?.cancel()
        cleanupTask = nil
        try? await channel?.close()
        channel = nil
        // Bounded drain: in-flight requests may hold render work; give them
        // up to `drainTimeout` to land, never block termination forever.
        let deadline = ContinuousClock.now + drainTimeout
        while inFlightRequests > 0 && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        await closeAllSessions()
        if let group {
            await Self.shutdownGroup(group)
        }
        group = nil
        AppError.logger.info("mcp: HTTP leg stopped")
    }

    /// The async-safe group shutdown (syncShutdownGracefully is unavailable
    /// in async contexts — this is its continuation-shaped twin).
    private static func shutdownGroup(_ group: MultiThreadedEventLoopGroup) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.shutdownGracefully { _ in continuation.resume() }
        }
    }

    // MARK: - Request routing (the conformance shape)

    var endpoint: String { configuration.endpoint }

    /// Routes an incoming HTTP request: existing session → its transport;
    /// initialize → new session (capacity-gated); anything else → error.
    func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
        inFlightRequests += 1
        defer { inFlightRequests -= 1 }

        let sessionID = request.header(HTTPHeaderName.sessionID)

        // Route to an existing session.
        if let sessionID, var session = sessions[sessionID] {
            session.lastAccessedAt = Date()
            sessions[sessionID] = session

            let response = await session.transport.handleRequest(request)

            // Clean up on successful DELETE (the client's disconnect).
            if request.method.uppercased() == "DELETE" && response.statusCode == 200 {
                sessions.removeValue(forKey: sessionID)
            }
            return response
        }

        // No session: an initialize POST creates one (capacity-gated).
        if request.method.uppercased() == "POST",
            let body = request.body,
            Self.isInitializeRequest(body)
        {
            if sessions.count >= configuration.maxSessions {
                return .error(
                    statusCode: 503,
                    MCPError.internalError(
                        "Session capacity reached (\(configuration.maxSessions)); "
                            + "retry after an existing client disconnects"))
            }
            return await createSessionAndHandle(request)
        }

        // No session and not initialize.
        if sessionID != nil {
            return .error(
                statusCode: 404,
                MCPError.internalError("Not Found: Session not found or expired"))
        }
        return .error(
            statusCode: 400,
            MCPError.internalError(
                "Bad Request: Missing \(HTTPHeaderName.sessionID) header"))
    }

    // MARK: - Session management

    /// The initialize-request probe (mirrors the SDK's package-internal
    /// JSONRPCMessageKind semantics: a REQUEST carries both method and id;
    /// `initialize` is the session-creating method).
    private static func isInitializeRequest(_ body: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: body)
                as? [String: Any],
            let method = object["method"] as? String,
            object["id"] != nil
        else { return false }
        return method == "initialize"
    }

    private struct FixedSessionIDGenerator: SessionIDGenerator {
        let sessionID: String
        func generateSessionID() -> String { sessionID }
    }

    private func createSessionAndHandle(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = UUID().uuidString
        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
            validationPipeline: validationPipeline)

        do {
            // The per-session Server: a fresh actor, the SAME kernel — the
            // factory closes over the shared registry.
            let server = try await serverFactory(transport)
            try await server.start(transport: transport)

            sessions[sessionID] = SessionContext(
                server: server,
                transport: transport,
                createdAt: Date(),
                lastAccessedAt: Date())

            let response = await transport.handleRequest(request)

            if case .error = response {
                sessions.removeValue(forKey: sessionID)
                await transport.disconnect()
            }
            return response
        } catch {
            await transport.disconnect()
            return .error(
                statusCode: 500,
                MCPError.internalError(
                    "Failed to create session: \(error.localizedDescription)"))
        }
    }

    private func closeSession(_ sessionID: String) async {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        await session.transport.disconnect()
        AppError.logger.info("mcp: closed session \(sessionID)")
    }

    private func closeAllSessions() async {
        for sessionID in sessions.keys {
            await closeSession(sessionID)
        }
    }

    private func sessionCleanupLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { break }
            let now = Date()
            let expired = sessions.filter { _, context in
                now.timeIntervalSince(context.lastAccessedAt)
                    > configuration.sessionTimeout
            }
            for sessionID in expired.keys {
                AppError.logger.info("mcp: session expired \(sessionID)")
                await closeSession(sessionID)
            }
        }
    }
}

// MARK: - NIO HTTP handler (the conformance adapter, verbatim shape)

/// Thin NIO adapter converting NIO HTTP parts into the framework-agnostic
/// `HTTPRequest`/`HTTPResponse` and delegating everything to the host actor.
private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let host: McpHTTPHost

    private struct RequestState {
        var head: HTTPRequestHead
        var bodyBuffer: ByteBuffer
    }

    private var requestState: RequestState?

    init(host: McpHTTPHost) {
        self.host = host
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestState = RequestState(
                head: head,
                bodyBuffer: context.channel.allocator.buffer(capacity: 0))
        case .body(var buffer):
            requestState?.bodyBuffer.writeBuffer(&buffer)
        case .end:
            guard let state = requestState else { return }
            requestState = nil

            nonisolated(unsafe) let ctx = context
            Task {
                await self.handleRequest(state: state, context: ctx)
            }
        }
    }

    private func handleRequest(state: RequestState, context: ChannelHandlerContext) async {
        let head = state.head
        let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
        let endpoint = await host.endpoint

        guard path == endpoint else {
            await writeResponse(
                .error(statusCode: 404, MCPError.internalError("Not Found")),
                version: head.version,
                context: context)
            return
        }

        let httpRequest = makeHTTPRequest(from: state)
        let response = await host.handleHTTPRequest(httpRequest)
        await writeResponse(response, version: head.version, context: context)
    }

    private func makeHTTPRequest(from state: RequestState) -> HTTPRequest {
        // Combine multiple header values per RFC 7230.
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let body: Data?
        if state.bodyBuffer.readableBytes > 0,
            let bytes = state.bodyBuffer.getBytes(
                at: 0, length: state.bodyBuffer.readableBytes)
        {
            body = Data(bytes)
        } else {
            body = nil
        }

        let path = String(
            state.head.uri.split(separator: "?").first ?? Substring(state.head.uri))

        return HTTPRequest(
            method: state.head.method.rawValue,
            headers: headers,
            body: body,
            path: path)
    }

    /// THE SSE PUMP (the probe's hard-won branch): a `.stream` response is a
    /// request-scoped SSE body — head first, then every chunk flushed as it
    /// arrives, then `.end`. Writing head+end without pumping the stream is
    /// exactly the first-probe bug that hung clients forever.
    private func writeResponse(
        _ response: HTTPResponse,
        version: HTTPVersion,
        context: ChannelHandlerContext
    ) async {
        nonisolated(unsafe) let ctx = context
        let eventLoop = ctx.eventLoop
        let statusCode = response.statusCode
        let headers = response.headers

        switch response {
        case .stream(let stream, _):
            eventLoop.execute {
                var head = HTTPResponseHead(
                    version: version,
                    status: HTTPResponseStatus(statusCode: statusCode))
                for (name, value) in headers {
                    head.headers.add(name: name, value: value)
                }
                ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)
                ctx.flush()
            }

            do {
                for try await chunk in stream {
                    eventLoop.execute {
                        var buffer = ctx.channel.allocator.buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        ctx.writeAndFlush(
                            self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    }
                }
            } catch {
                // Stream ended with error — close the connection.
            }

            eventLoop.execute {
                ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }

        default:
            let bodyData = response.bodyData
            eventLoop.execute {
                var head = HTTPResponseHead(
                    version: version,
                    status: HTTPResponseStatus(statusCode: statusCode))
                for (name, value) in headers {
                    head.headers.add(name: name, value: value)
                }

                ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)

                if let body = bodyData {
                    var buffer = ctx.channel.allocator.buffer(capacity: body.count)
                    buffer.writeBytes(body)
                    ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }

                ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}

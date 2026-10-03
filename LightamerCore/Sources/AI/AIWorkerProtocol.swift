import CoreML
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIWorkerProtocol (Plan M2-10-05 KD-1) — the length-prefixed JSON frame
// protocol between the editor process and the `--ai-worker` child process.
//
// A frame = 4-byte BIG-ENDIAN UInt32 payload length + the payload bytes
// (JSON UTF-8). Two envelope shapes:
//
//   request  {"id":N,"op":"open|run|ping|stop","profile":"…","units":"all|cpuAndGPU|cpuOnly",
//             "payload":{…}}
//   response {"id":N,"ok":true,"result":{…}} |
//            {"id":N,"ok":false,"error":"…","culpritUnits":"all"}
//
// DELIBERATELY NOT MCP (D-M2-10-CONTEXT plan ruling): the Phase 14 MCP stdio
// transport is JSON-RPC semantics (capabilities/tools/notifications) — the
// worker needs a one-way request→response pipe and nothing else, so this is
// the minimal self-built shape. No capabilities, no tool surface.
//
// OQ-10-C HYBRID CHANNEL (the 8MB boundary): the BYTE channel (payload in
// the frame, e.g. `jpegBase64`) is reserved for SMALL images (the CLIP
// 256² JPEG ≈ 20-50KB); LARGE images (the super-resolution intermediate
// frames) MUST travel the PATH channel (`inPath`/`outPath` tmp files —
// zero IPC copy, crash-interruptible work naturally on disk). The boundary
// is enforced at CONSTRUCTION: an oversized payload is a typed rejection
// on the send side, never a mid-flight truncation. The spike numbers
// (M2-10-05 SUMMARY) justify the constant; the SEMANTICS (bytes = small
// only) are fixed regardless of the measured values.
//
// BAD-FRAME TOLERANCE (KD-1): a frame whose JSON/UTF-8 decode fails, or
// whose length prefix exceeds the bound, is survivable — the reader skips
// exactly the declared byte count (the length prefix keeps the stream
// aligned) and the worker answers with an error frame; the connection
// stays alive. Only EOF / a physically broken pipe folds into a
// process-level crash.
//
// Core-level pure functions: unit-testable with plain Pipe objects, no
// process required (the worker process body lives in the App target).
// ─────────────────────────────────────────────────────────────────────────────

/// The compute-units axis of the device fallback chain (KD-3 attempt order
/// `.all → .cpuAndGPU → .cpuOnly`; the raw values are the wire spellings).
public enum AIComputeUnits: String, CaseIterable, Codable, Sendable {
    case all
    case cpuAndGPU
    case cpuOnly

    /// The CoreML configuration value the worker session opens with.
    public var mlComputeUnits: MLComputeUnits {
        switch self {
        case .all: return .all
        case .cpuAndGPU: return .cpuAndGPU
        case .cpuOnly: return .cpuOnly
        }
    }
}

/// The ops the worker understands (the envelope carries the raw string;
/// unknown ops produce an error frame and the loop continues).
public enum AIWorkerOp: String, Sendable {
    case open
    case run
    case ping
    case stop
}

/// One worker request envelope (KD-1). Unknown JSON fields are tolerated
/// (forward compatibility within a same-binary pair is a non-goal, but
/// strictness here would only add fragile failure modes).
public struct AIWorkerRequest: Codable, Equatable, Sendable {
    public var id: UInt64
    public var op: String
    public var profile: String?
    public var units: String?
    public var payload: AIWorkerPayload?

    public init(
        id: UInt64, op: String, profile: String? = nil,
        units: String? = nil, payload: AIWorkerPayload? = nil
    ) {
        self.id = id
        self.op = op
        self.profile = profile
        self.units = units
        self.payload = payload
    }

    public var opKind: AIWorkerOp? { AIWorkerOp(rawValue: op) }
    public var unitsKind: AIComputeUnits? { units.flatMap(AIComputeUnits.init(rawValue:)) }
}

/// The request payload variants (KD-1): the text-embedding rows, the CLIP
/// small-image BYTE channel, or the super-resolution PATH channel. Exactly
/// one variant is populated per request; the worker validates presence.
public struct AIWorkerPayload: Codable, Equatable, Sendable {
    /// Text tower: the tokenizer's static-shape rows (52) + the 1-D padding
    /// mask (the worker expands per the model contract, exactly as the
    /// in-process runner does).
    public var tokens: [Int64]?
    public var mask: [Int64]?
    /// CLIP image tower: pre-scaled JPEG bytes, base64 (the BYTE channel —
    /// small images only, see the 8MB boundary above).
    public var jpegBase64: String?
    /// Enhancement family: tmp file paths (the PATH channel). The worker
    /// self-decodes `inPath` and writes the result to `outPath`; large
    /// frames never cross the pipe.
    public var inPath: String?
    public var outPath: String?
    /// Tiling parameters for the enhancement family. Shape placeholder —
    /// M2-10-06 owns the fields; the envelope round-trips the container so
    /// the frame shape is already proven.
    public var tile: AITileParameters?

    public init(
        tokens: [Int64]? = nil, mask: [Int64]? = nil, jpegBase64: String? = nil,
        inPath: String? = nil, outPath: String? = nil, tile: AITileParameters? = nil
    ) {
        self.tokens = tokens
        self.mask = mask
        self.jpegBase64 = jpegBase64
        self.inPath = inPath
        self.outPath = outPath
        self.tile = tile
    }
}

/// Tiling parameters container (M2-10-06 fills the fields; today it is the
/// proven-empty shape so the path-channel envelope is stable).
public struct AITileParameters: Codable, Equatable, Sendable {
    public init() {}
}

/// One worker response envelope. `ok:false` carries the human-readable
/// `error` plus the OPTIONAL `culpritUnits` — the units the failure is
/// attributed to, which is the client's degradation-bookkeeping input
/// (KD-2: model-load failures answer WITH the culprit; profile-level
/// failures like absent assets answer WITHOUT one).
public struct AIWorkerResponse: Codable, Equatable, Sendable {
    public var id: UInt64
    public var ok: Bool
    public var result: AIWorkerResult?
    public var error: String?
    public var culpritUnits: String?

    public init(
        id: UInt64, ok: Bool, result: AIWorkerResult? = nil,
        error: String? = nil, culpritUnits: String? = nil
    ) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
        self.culpritUnits = culpritUnits
    }

    public var culpritUnitsKind: AIComputeUnits? {
        culpritUnits.flatMap(AIComputeUnits.init(rawValue:))
    }
}

/// The success-result variants (KD-1): the ping pid, the open echo, the
/// embedding vector, the enhancement output path, and the spike byte count
/// (the DEBUG-only IPC microbenchmark op).
public struct AIWorkerResult: Codable, Equatable, Sendable {
    public var pid: Int?
    public var profile: String?
    public var units: String?
    public var embedding: [Float]?
    public var outPath: String?
    public var bytes: Int?

    public init(
        pid: Int? = nil, profile: String? = nil, units: String? = nil,
        embedding: [Float]? = nil, outPath: String? = nil, bytes: Int? = nil
    ) {
        self.pid = pid
        self.profile = profile
        self.units = units
        self.embedding = embedding
        self.outPath = outPath
        self.bytes = bytes
    }
}

// MARK: - Frame codec

public enum AIWorkerFrameError: Error, Equatable, Sendable {
    /// The send-side typed rejection (OQ-10-C: an oversized payload must
    /// travel the PATH channel — construction refuses the byte channel).
    case payloadTooLarge(bytes: Int, limit: Int)
    /// The received frame's payload is not decodable (JSON/UTF-8). The
    /// stream stays aligned (the reader consumed exactly the declared
    /// bytes); the peer answers with an error frame and the connection
    /// survives.
    case badFrame(String)
    /// The pipe closed mid-frame (a physical break — the one fatal shape).
    case connectionClosed
}

public enum AIWorkerFrameCodec {

    /// The OQ-10-C channel boundary: request frames larger than this are
    /// rejected at construction (the spike numbers live in the M2-10-05
    /// SUMMARY; the small-images-only semantics do not move with them).
    public static let maxFrameBytes: UInt32 = 8 * 1024 * 1024

    /// Encodes one envelope into a frame (prefix + JSON bytes), enforcing
    /// the size boundary at construction.
    public static func encode(
        _ value: some Encodable, maxBytes: UInt32 = AIWorkerFrameCodec.maxFrameBytes
    ) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        guard payload.count <= Int(maxBytes) else {
            throw AIWorkerFrameError.payloadTooLarge(
                bytes: payload.count, limit: Int(maxBytes))
        }
        var frame = Data(count: 4)
        frame.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let bigEndian = UInt32(payload.count).bigEndian
            raw.storeBytes(of: bigEndian, toByteOffset: 0, as: UInt32.self)
        }
        frame.append(payload)
        return frame
    }

    public static func encode(request: AIWorkerRequest) throws -> Data {
        try encode(request)
    }

    public static func encode(response: AIWorkerResponse) throws -> Data {
        try encode(response)
    }

    /// Decodes one frame payload (the bytes AFTER the prefix).
    public static func decodeRequest(_ payload: Data) throws -> AIWorkerRequest {
        do {
            return try JSONDecoder().decode(AIWorkerRequest.self, from: payload)
        } catch {
            throw AIWorkerFrameError.badFrame(
                "request decode failed: \(error.localizedDescription)")
        }
    }

    public static func decodeResponse(_ payload: Data) throws -> AIWorkerResponse {
        do {
            return try JSONDecoder().decode(AIWorkerResponse.self, from: payload)
        } catch {
            throw AIWorkerFrameError.badFrame(
                "response decode failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Frame reader

/// The outcome of one blocking frame read.
public enum AIWorkerFrameRead: Equatable, Sendable {
    case frame(Data)
    /// The declared length exceeded the bound — the payload bytes were
    /// skipped (the prefix keeps the stream aligned) and the caller decides
    /// the survivable answer (worker: an error frame; client: a typed
    /// protocol violation).
    case oversize(declaredBytes: UInt32)
}

/// A buffered blocking frame reader over a pipe `FileHandle`. Shared by the
/// worker main loop (stdin) and the client's response pump (stdout).
public final class AIWorkerFrameReader {

    private let handle: FileHandle
    private var buffer = Data()

    public init(handle: FileHandle) {
        self.handle = handle
    }

    /// Blocks until one frame is available.
    /// - Returns: nil on a CLEAN EOF (the peer closed between frames);
    ///   throws `connectionClosed` when the pipe closes mid-frame.
    public func readFrame(
        maxBytes: UInt32 = AIWorkerFrameCodec.maxFrameBytes
    ) throws -> AIWorkerFrameRead? {
        guard let prefix = try readExactly(4) else { return nil }
        // WIDEN BEFORE SHIFTING: `UInt8 << 24` stays UInt8 (silent
        // truncation) — each byte must widen to UInt32 first (probed: a
        // 5359-byte frame read as 239 = 0x14EF & 0xFF without this).
        let declared = prefix.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            UInt32(raw.load(fromByteOffset: 0, as: UInt8.self)) << 24
                | UInt32(raw.load(fromByteOffset: 1, as: UInt8.self)) << 16
                | UInt32(raw.load(fromByteOffset: 2, as: UInt8.self)) << 8
                | UInt32(raw.load(fromByteOffset: 3, as: UInt8.self))
        }
        guard declared <= maxBytes else {
            // Survivable corruption: skip exactly the declared byte count so
            // the stream stays aligned, then keep reading.
            _ = skip(Int(declared))
            return .oversize(declaredBytes: declared)
        }
        guard let payload = try readExactly(Int(declared)) else {
            throw AIWorkerFrameError.connectionClosed
        }
        return .frame(payload)
    }

    /// Reads exactly `count` bytes (buffered across `availableData` chunks).
    /// nil = clean EOF at a chunk boundary; throws on EOF mid-read.
    private func readExactly(_ count: Int) throws -> Data? {
        while buffer.count < count {
            let chunk = handle.availableData
            if chunk.isEmpty {
                if buffer.isEmpty { return nil }
                throw AIWorkerFrameError.connectionClosed
            }
            buffer.append(chunk)
        }
        let payload = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(payload)
    }

    /// Best-effort skip of `count` bytes (the oversize tolerance path).
    private func skip(_ count: Int) -> Bool {
        var remaining = count
        while remaining > 0 {
            if !buffer.isEmpty {
                let take = min(remaining, buffer.count)
                buffer.removeFirst(take)
                remaining -= take
                continue
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return false }
            if chunk.count > remaining {
                buffer.append(chunk.dropFirst(remaining))
                remaining = 0
            } else {
                remaining -= chunk.count
            }
        }
        return true
    }
}

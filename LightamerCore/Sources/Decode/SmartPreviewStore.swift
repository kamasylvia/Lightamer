import Compression
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SmartPreviewStore (Plan LUMEN-B T1, X6) — the decoded-preview pack format
// behind the smart-preview cache (LU4). The store is a DECODE-EXIT wrapper
// layer over `RAWDecoder.decode` (the wrapper consumes decode through an
// injected closure — RAWDecoder itself keeps a ZERO-diff signature).
//
// ATTRIBUTION (MIT): the FORMAT SHAPE — the LPV1 magic + header-length +
// JSON-header + float16 plane + byte-plane split + zlib envelope — is
// derived from LUMEN RAW's `preview_cache.py` (Copyright (c) LUMEN RAW
// contributors, MIT license; the root NOTICE carries the entry). This is an
// independent Swift reimplementation for our own container (no code copied);
// the format is not algorithm surface, so the note rides this file header
// (the plan T1 note-level attribution; T3 re-checks the NOTICE coverage).
//
// FORMAT (T1, the plan's "LPV1 形我方拼写"):
//   magic "LAPV1" | UInt32 LE header length | JSON header | zlib(deflate) planes
//   header JSON = { width, height, version, meta: [String: String] }
//   planes      = the float16-quantized RGBA samples split into TWO byte
//                 planes (all low bytes, then all high bytes) — the
//                 rearrangement lifts zlib's ratio on smooth image data
//                 (the Lumen transliteration motive; the smoke test pins it).
//
// QUANTIZATION CONSISTENCY (H-LU3 arm 1, the T1 red line): `quantize` is a
// PUBLIC function and every FRESH decode passes through the same float16
// round-trip before it is cached or served — so a cache hit and a fresh
// decode produce BIT-IDENTICAL planes ("缓存不改变观感" made structural).
// The round-trip golden test pins bit-identity + the <0.05% relative error.
//
// COMPRESSION: zlib level 1 is the Lumen calibration (speed-first; the
// plan red line bans higher levels). Apple's Compression framework exposes
// no level knob — its COMPRESSION_ZLIB is a speed-oriented deflate, which
// is the structural equivalent of the "level 1" intent (declared in
// LUMEN-B DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

/// The decoded working plane the cache stores: working-space LINEAR float32
/// RGBA, row-major, premultiplied-alpha (the pipeline's plane discipline —
/// the readback composes straight into the RGBA face).
public struct SmartPreviewPlane: Sendable, Equatable {

    public let width: Int
    public let height: Int
    /// Row-major RGBA, `count == width * height * 4`.
    public let rgba: [Float]

    public init(width: Int, height: Int, rgba: [Float]) {
        precondition(width > 0 && height > 0, "plane dimensions must be positive")
        precondition(
            rgba.count == width * height * 4,
            "rgba count \(rgba.count) != \(width)*\(height)*4")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public var sampleCount: Int { width * height * 4 }
}

/// The typed pack/unpack failures (malformed input NEVER crashes — the
/// plan's typed-failure face; the store treats every error as a cache miss).
public enum SmartPreviewFormatError: Error, Equatable, Sendable {
    case badMagic
    case truncatedEnvelope
    case headerTooLarge
    case badHeader
    case truncatedPlanes
}

/// The LPV1-shaped pack format ("LAPV1" spelling). Pure value semantics —
/// no I/O, no clock, fully deterministic (the golden tests ride this).
public enum SmartPreviewFormat {

    /// The container magic (our spelling of the Lumen LPV1 shape).
    public static let magic = "LAPV1"

    /// The cache-key format dimension (bumping it invalidates every entry —
    /// the T2 key folds this).
    public static let formatVersion = 1

    /// The header JSON's meta values are strings (the JSON-safe projection
    /// of the key/carrier facts T3 records: source path, process version…).
    public typealias Meta = [String: String]

    struct Header: Codable, Equatable {
        let width: Int
        let height: Int
        let version: Int
        let meta: Meta
    }

    // MARK: - Quantization (the consistency rule)

    /// The float16 round-trip every fresh decode passes through (H-LU3 arm
    /// 1): relative precision ≈ 2^-11 ≈ 0.049% < 0.05% (the Lumen measured
    /// bound the golden test asserts). Bit-identity: quantize(quantize(p))
    /// == quantize(p) — the idempotence the hit/miss equality rides.
    public static func quantize(_ plane: SmartPreviewPlane) -> SmartPreviewPlane {
        var out = plane.rgba
        out.reserveCapacity(out.count)
        for index in out.indices {
            out[index] = Float(Float16(out[index]))
        }
        return SmartPreviewPlane(width: plane.width, height: plane.height, rgba: out)
    }

    /// The float16 halves of a plane (the pack intermediate; internal so the
    /// rearrangement smoke test can compose both byte orders).
    static func halves(_ plane: SmartPreviewPlane) -> [Float16] {
        var out = [Float16](repeating: 0, count: plane.sampleCount)
        for index in 0..<plane.sampleCount {
            out[index] = Float16(plane.rgba[index])
        }
        return out
    }

    /// The byte-plane split (low plane first, then high plane) — the
    /// rearrangement that lifts the zlib ratio.
    static func planarBytes(from halves: [Float16]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: halves.count * 2)
        for index in 0..<halves.count {
            let bits = halves[index].bitPattern
            out[index] = UInt8(bits & 0xFF)
            out[halves.count + index] = UInt8(bits >> 8)
        }
        return out
    }

    /// The naive interleaved byte order (the smoke test's baseline — what
    /// zlib would see WITHOUT the rearrangement).
    static func interleavedBytes(from halves: [Float16]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: halves.count * 2)
        for index in 0..<halves.count {
            let bits = halves[index].bitPattern
            out[index * 2] = UInt8(bits & 0xFF)
            out[index * 2 + 1] = UInt8(bits >> 8)
        }
        return out
    }

    static func halves(fromPlanarBytes bytes: [UInt8]) -> [Float16] {
        let count = bytes.count / 2
        var out = [Float16](repeating: 0, count: count)
        for index in 0..<count {
            out[index] = Float16(bitPattern: UInt16(bytes[index]) | (UInt16(bytes[count + index]) << 8))
        }
        return out
    }

    // MARK: - Pack / unpack

    /// The packed envelope: magic + header length + JSON header + zlib'd
    /// planar float16 bytes.
    public static func pack(
        _ plane: SmartPreviewPlane, meta: Meta = [:]
    ) throws -> Data {
        let header = Header(
            width: plane.width, height: plane.height,
            version: formatVersion, meta: meta)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let headerData = try? encoder.encode(header) else {
            throw SmartPreviewFormatError.badHeader
        }
        guard headerData.count <= Int(UInt32.max) else {
            throw SmartPreviewFormatError.headerTooLarge
        }
        let planes = planarBytes(from: halves(plane))
        guard let compressed = Self.compress(planes) else {
            throw SmartPreviewFormatError.badHeader
        }

        var data = Data()
        data.reserveCapacity(magicData.count + 4 + headerData.count + compressed.count)
        data.append(magicData)
        var length = UInt32(headerData.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(headerData)
        data.append(compressed)
        return data
    }

    /// The read-back: envelope → plane + meta. Every malformed shape is a
    /// typed throw (the store deletes + rebuilds on any of them).
    public static func unpack(_ data: Data) throws -> (plane: SmartPreviewPlane, meta: Meta) {
        let bytes = [UInt8](data)
        let magicBytes = Array(magicData)
        guard bytes.count >= magicBytes.count + 4, Array(bytes[0..<magicBytes.count]) == magicBytes
        else { throw SmartPreviewFormatError.badMagic }

        let lengthOffset = magicBytes.count
        let headerLength = bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: lengthOffset, as: UInt32.self).littleEndian
        }
        let headerStart = lengthOffset + 4
        let headerEnd = headerStart + Int(headerLength)
        guard Int(headerLength) > 0, headerEnd <= bytes.count else {
            throw SmartPreviewFormatError.truncatedEnvelope
        }
        guard let header = try? JSONDecoder().decode(
            Header.self, from: Data(bytes[headerStart..<headerEnd]))
        else { throw SmartPreviewFormatError.badHeader }
        guard header.version == formatVersion else {
            throw SmartPreviewFormatError.badHeader
        }

        let expected = header.width * header.height * 4 * 2
        let compressed = Data(bytes[headerEnd...])
        guard let planes = decompress(compressed, byteCount: expected),
              planes.count == expected
        else { throw SmartPreviewFormatError.truncatedPlanes }

        let plane = SmartPreviewPlane(
            width: header.width, height: header.height,
            rgba: halves(fromPlanarBytes: planes).map(Float.init))
        return (plane, header.meta)
    }

    static var magicData: Data {
        Data(magic.utf8)
    }

    // MARK: - Deflate (the level-1-intent carrier — see the file header)

    static func compress(_ input: [UInt8]) -> Data? {
        guard !input.isEmpty else { return nil }
        let dstCapacity = input.count + input.count / 2 + 64
        var dst = Data(count: dstCapacity)
        let written = dst.withUnsafeMutableBytes { raw -> Int in
            input.withUnsafeBufferPointer { src in
                compression_encode_buffer(
                    raw.bindMemory(to: UInt8.self).baseAddress!, dstCapacity,
                    src.baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return dst.prefix(written)
    }

    static func decompress(_ input: Data, byteCount: Int) -> [UInt8]? {
        guard byteCount > 0, !input.isEmpty else { return nil }
        var dst = [UInt8](repeating: 0, count: byteCount)
        let written = input.withUnsafeBytes { raw -> Int in
            dst.withUnsafeMutableBufferPointer { buffer in
                compression_decode_buffer(
                    buffer.baseAddress!, byteCount,
                    raw.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == byteCount else { return nil }
        return dst
    }
}

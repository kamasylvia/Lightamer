import Foundation
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// AIWorkerProtocolTests (Plan M2-10-05 T1, KD-1 / AC#1) — the frame protocol
// pure-function face: round-trips over real pipes, the 8MB construction-time
// boundary, the survivable bad-frame shapes, and both OQ-10-C channel
// payload shapes. No process required here — the worker-process face lives
// in AIWorkerClientTests.
// ─────────────────────────────────────────────────────────────────────────────

final class AIWorkerProtocolTests: XCTestCase {

    // MARK: - Frame layout

    func testFramePrefixIsFourByteBigEndianLength() throws {
        let request = AIWorkerRequest(id: 7, op: "ping")
        let frame = try AIWorkerFrameCodec.encode(request: request)
        let payload = try JSONEncoder().encode(request)
        XCTAssertEqual(frame.count, 4 + payload.count)
        XCTAssertEqual(
            Array(frame.prefix(4)),
            withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Array($0) })
        // A 300+-byte payload carries a multi-byte big-endian length.
        let big = AIWorkerRequest(id: 1, op: "ping", payload: AIWorkerPayload(
            jpegBase64: String(repeating: "A", count: 300)))
        let bigFrame = try AIWorkerFrameCodec.encode(request: big)
        let bigPayload = try JSONEncoder().encode(big)
        XCTAssertGreaterThan(bigPayload.count, 255, "sanity: two-byte length")
        XCTAssertEqual(
            Array(bigFrame.prefix(4)),
            withUnsafeBytes(of: UInt32(bigPayload.count).bigEndian) { Array($0) })
    }

    // MARK: - Round trip over a real pipe

    func testRequestResponseRoundTripThroughPipeReader() throws {
        let pipe = Pipe()
        let request = AIWorkerRequest(
            id: 42, op: "open", profile: "probe-profile", units: "cpuOnly",
            payload: AIWorkerPayload(tokens: [101, 102], mask: [1, 1]))
        try pipe.fileHandleForWriting.write(contentsOf:
            AIWorkerFrameCodec.encode(request: request))

        let reader = AIWorkerFrameReader(handle: pipe.fileHandleForReading)
        guard case .frame(let payload) = try XCTUnwrap(reader.readFrame()) else {
            return XCTFail("expected a frame")
        }
        XCTAssertEqual(try AIWorkerFrameCodec.decodeRequest(payload), request)
    }

    func testResponseRoundTripKeepsEmbeddingPrecision() throws {
        let pipe = Pipe()
        let embedding = (0..<512).map { Float($0) * 0.001 - 0.25 }
        let response = AIWorkerResponse(
            id: 9, ok: true,
            result: AIWorkerResult(pid: 1234, embedding: embedding))
        try pipe.fileHandleForWriting.write(contentsOf:
            AIWorkerFrameCodec.encode(response: response))

        let reader = AIWorkerFrameReader(handle: pipe.fileHandleForReading)
        guard case .frame(let payload) = try XCTUnwrap(reader.readFrame()) else {
            return XCTFail("expected a frame")
        }
        let decoded = try AIWorkerFrameCodec.decodeResponse(payload)
        XCTAssertEqual(decoded, response)
        XCTAssertEqual(decoded.result?.embedding?.count, 512)
    }

    // MARK: - The 8MB boundary (OQ-10-C)

    func testOversizePayloadIsTypedExceptionAtConstruction() throws {
        let request = AIWorkerRequest(id: 1, op: "run", profile: "p", units: "all")
        // A tiny injected bound proves the typed rejection without moving
        // 8MB through JSON in a unit test.
        XCTAssertThrowsError(
            try AIWorkerFrameCodec.encode(request, maxBytes: 16)
        ) { error in
            XCTAssertEqual(
                error as? AIWorkerFrameError,
                .payloadTooLarge(
                    bytes: (try? JSONEncoder().encode(request).count) ?? 0,
                    limit: 16))
        }
    }

    func testOversizeFrameIsSkippedAndStreamStaysAligned() throws {
        let pipe = Pipe()
        // Two frames: the first exceeds the injected bound, the second is
        // good — the reader must skip EXACTLY the declared byte count and
        // land the next frame (the KD-1 survivable-corruption shape).
        let payload = Data(repeating: 0xAB, count: 200)
        var frame = Data([0, 0, 0, 200])
        frame.append(payload)
        try pipe.fileHandleForWriting.write(contentsOf: frame)
        let good = AIWorkerRequest(id: 5, op: "ping")
        try pipe.fileHandleForWriting.write(contentsOf:
            AIWorkerFrameCodec.encode(request: good))
        pipe.fileHandleForWriting.closeFile()

        let reader = AIWorkerFrameReader(handle: pipe.fileHandleForReading)
        XCTAssertEqual(
            try reader.readFrame(maxBytes: 100), .oversize(declaredBytes: 200))
        guard case .frame(let nextPayload) = try XCTUnwrap(reader.readFrame(maxBytes: 100))
        else { return XCTFail("the stream must stay aligned after a skip") }
        XCTAssertEqual(try AIWorkerFrameCodec.decodeRequest(nextPayload), good)
        XCTAssertNil(try reader.readFrame(maxBytes: 100))  // clean EOF
    }

    // MARK: - Bad-frame tolerance

    func testBadJSONSurfacesTypedExceptionAndReaderStaysAligned() throws {
        let pipe = Pipe()
        var bad = Data([0, 0, 0, 12])
        bad.append(Data("not-a-json!!".utf8))  // exactly 12 bytes
        try pipe.fileHandleForWriting.write(contentsOf: bad)
        let good = AIWorkerResponse(id: 3, ok: true, result: AIWorkerResult(pid: 1))
        try pipe.fileHandleForWriting.write(contentsOf:
            AIWorkerFrameCodec.encode(response: good))
        pipe.fileHandleForWriting.closeFile()

        let reader = AIWorkerFrameReader(handle: pipe.fileHandleForReading)
        guard case .frame(let badPayload) = try XCTUnwrap(reader.readFrame())
        else { return XCTFail("expected the bad frame's bytes") }
        XCTAssertThrowsError(
            try AIWorkerFrameCodec.decodeResponse(badPayload)
        ) { error in
            guard case AIWorkerFrameError.badFrame = error else {
                return XCTFail("expected badFrame, got \(error)")
            }
        }
        guard case .frame(let goodPayload) = try XCTUnwrap(reader.readFrame())
        else { return XCTFail("aligned stream expected") }
        XCTAssertEqual(try AIWorkerFrameCodec.decodeResponse(goodPayload), good)
    }

    func testMidFrameEOFFoldsIntoConnectionClosed() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data([0, 0, 0, 64, 1, 2]))
        pipe.fileHandleForWriting.closeFile()

        let reader = AIWorkerFrameReader(handle: pipe.fileHandleForReading)
        XCTAssertThrowsError(try reader.readFrame()) { error in
            XCTAssertEqual(error as? AIWorkerFrameError, .connectionClosed)
        }
    }

    // MARK: - The two OQ-10-C channel shapes

    func testSmallImageByteChannelPayloadShape() throws {
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let request = AIWorkerRequest(
            id: 11, op: "run", profile: "chinese-clip-vitb16-int8",
            units: "all",
            payload: AIWorkerPayload(
                jpegBase64: jpegBytes.base64EncodedString()))
        let frame = try AIWorkerFrameCodec.encode(request: request)
        let decoded = try Self.decodeRequestFrom(frame)
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(
            Data(base64Encoded: try XCTUnwrap(decoded.payload?.jpegBase64)),
            jpegBytes)
    }

    func testLargeImagePathChannelPayloadShape() throws {
        let tile = AITileParameters()
        let request = AIWorkerRequest(
            id: 12, op: "run", profile: "real-esrgan-x4plus-fp16",
            units: "cpuAndGPU",
            payload: AIWorkerPayload(
                inPath: "/tmp/lightamer-spike-in.tif",
                outPath: "/tmp/lightamer-spike-out.tif",
                tile: tile))
        let frame = try AIWorkerFrameCodec.encode(request: request)
        let decoded = try Self.decodeRequestFrom(frame)
        XCTAssertEqual(decoded.payload?.inPath, "/tmp/lightamer-spike-in.tif")
        XCTAssertEqual(decoded.payload?.outPath, "/tmp/lightamer-spike-out.tif")
        XCTAssertEqual(decoded.payload?.tile, tile)
        // The wire spelling of the units axis is contract.
        XCTAssertEqual(decoded.units, "cpuAndGPU")
        XCTAssertEqual(decoded.unitsKind, .cpuAndGPU)
    }

    // MARK: - Envelope leniency

    func testUnknownFieldsAndCulpritRoundTrip() throws {
        let json = #"{"id":6,"op":"run","profile":"p","units":"cpuOnly","futureField":true,"payload":{"inPath":"/x"}}"#
        let decoded = try JSONDecoder().decode(
            AIWorkerRequest.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, 6)
        XCTAssertEqual(decoded.unitsKind, .cpuOnly)

        let errorResponse =
            #"{"id":6,"ok":false,"error":"boom","culpritUnits":"all"}"#
        let response = try JSONDecoder().decode(
            AIWorkerResponse.self, from: Data(errorResponse.utf8))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.culpritUnitsKind, .all)
    }

    // MARK: - Helpers

    /// A direct encode→decode hop (no reader): drop the 4-byte prefix first.
    private static func decodeRequestFrom(_ frame: Data) throws -> AIWorkerRequest {
        try AIWorkerFrameCodec.decodeRequest(Data(frame.dropFirst(4)))
    }
}

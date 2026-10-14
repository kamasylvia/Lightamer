@testable import LightamerCore
import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Vision
import XCTest

/// PersonInstanceMaskTests (Plan M6-4-02 T3, KD-2/E2) — the person-instance
/// face pins WITHOUT any real inference on the extraction path:
/// ① the request assembly typed face (revision pinned, layer-A-form pin),
/// ② the LABEL COMPOSITE extraction helper over SYNTHETIC label-buffer
///    fixtures (single / multi / unknown label domain / zero coverage —
///    zero Observation dependency, zero entitlement: the fixture IS the
///    CVPixelBuffer, R4's unit-test extension),
/// ③ the max-union selection core (all / subset / empty = typed noSubject),
/// ④ the zero-observation classification (real built-in model on a blank
///    field → typed noSubject, never a plane),
/// ⑤ the plane format face (Float single channel at the label-map
///    resolution; the :507 maskPlane face on a float buffer).
final class PersonInstanceMaskTests: XCTestCase {

    // MARK: - synthetic label-buffer fixtures (E2)

    /// An 8-bit one-component label map ('L008' — the allInstancesMask
    /// format) painted by `paint`, bridged into the extraction helper's
    /// `CVReadOnlyPixelBuffer` face (`init(unsafeBuffer:)` — the fixture
    /// IS the buffer; zero Observation, zero entitlement).
    private func labelBuffer(
        _ w: Int, _ h: Int, _ paint: (_ x: Int, _ y: Int) -> UInt8
    ) throws -> CVReadOnlyPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, w, h, kCVPixelFormatType_OneComponent8, nil, &pb)
        XCTAssertEqual(status, kCVReturnSuccess, "fixture buffer creation")
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let p = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            for x in 0..<w { p[y * bpr + x] = paint(x, y) }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // (unlock BEFORE the bridge — the unsafeBuffer init is `sending`,
        // the buffer must not be touched afterward)
        return CVReadOnlyPixelBuffer(unsafeBuffer: buffer)
    }

    // MARK: ① request assembly typed face

    /// The revision is PINNED (revision1 — the only supported member on
    /// this OS) and the pin face is the LAYER-A form: a validated pin is
    /// legal (this request exposes the compute-device API — unlike the
    /// legacy person/faces requests; RESEARCH B2 probe: main =
    /// [ane, gpu, cpu]). NO asset gate exists on this family (OS built-in,
    /// no DownloadableAssetsRequest) — `buildPersonInstanceRequest`
    /// performs no store query, by construction (the one-shot's `assets`
    /// parameter is unconsumed; the DECISIONS entry carries the
    /// declaration).
    func testBuildPersonInstanceRequestTypedFace() throws {
        let plain = try AIMaskService.buildPersonInstanceRequest(device: .anePreferred)
        XCTAssertEqual(plain.revision, .revision1, "the revision is pinned")
        XCTAssertTrue(
            GeneratePersonInstanceMaskRequest.supportedRevisions.contains(.revision1),
            "revision1 is in the runtime's supported set")

        // The validated-pin leg: GPU (and CPU — B2 reports cpu supported)
        // must not throw; the pin validation reads the request's own map.
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU — the gpu-pin leg needs a device")
        }
        let pinned = try AIMaskService.buildPersonInstanceRequest(device: .gpuPinned)
        XCTAssertEqual(pinned.revision, .revision1)

        let supported = GeneratePersonInstanceMaskRequest()
            .supportedComputeStageDevices[.main] ?? []
        let hasCPU = supported.contains { d in
            if case .cpu = d { return true } else { return false }
        }
        let hasGPU = supported.contains { d in
            if case .gpu = d { return true } else { return false }
        }
        if hasCPU {
            _ = try AIMaskService.buildPersonInstanceRequest(device: .cpuPinned)
        }
        // The unsupported-device leg stays typed (never a trap): without a
        // GPU in the supported map the gpu pin surfaces deviceUnavailable.
        if !hasGPU {
            XCTAssertThrowsError(
                try AIMaskService.buildPersonInstanceRequest(device: .gpuPinned)
            ) { error in
                guard case AIMaskError.deviceUnavailable = error else {
                    return XCTFail("expected deviceUnavailable, got \(error)")
                }
            }
        }
    }

    // MARK: ② label-composite extraction (the four synthetic fixtures)

    /// The extraction helper over ALL FOUR label-buffer fixtures in one
    /// pass: ⑴ single instance (the block exactly), ⑵ multi instance
    /// (disjoint per-instance planes; the union covers both blocks), ⑶
    /// unknown label domain (foreign numbering — labels are just labels; a
    /// selection the buffer cannot cover = typed invalidMask), ⑷ zero
    /// coverage (all-zero buffer = typed invalidMask, never an empty
    /// plane). Zero Vision execution, zero entitlement (E2/R4).
    func testLabelCompositeExtractionFixtures() throws {
        // ⑴ single instance.
        let single = try labelBuffer(24, 16) { x, y in
            (x >= 4 && x < 12 && y >= 3 && y < 9) ? 1 : 0
        }
        let plane = try AIMaskService.labelComposite(
            labelBuffer: single, instances: IndexSet([1]))
        XCTAssertEqual(plane.width, 24)
        XCTAssertEqual(plane.height, 16)
        var inside = 0, outside = 0
        for y in 0..<16 {
            for x in 0..<24 {
                let v = plane.floats[y * 24 + x]
                if x >= 4 && x < 12 && y >= 3 && y < 9 {
                    XCTAssertEqual(v, 1, "inside the label block at \(x),\(y)")
                    inside += 1
                } else {
                    XCTAssertEqual(v, 0, "outside the label block at \(x),\(y)")
                    outside += 1
                }
            }
        }
        XCTAssertEqual(inside, 8 * 6)
        XCTAssertGreaterThan(outside, 0, "防空转")

        // ⑵ multi instance: disjoint planes; the union covers both blocks.
        let multi = try labelBuffer(32, 16) { x, y in
            if x >= 2 && x < 10 && y >= 2 && y < 12 { return 1 }
            if x >= 20 && x < 30 && y >= 4 && y < 14 { return 2 }
            return 0
        }
        let one = try AIMaskService.labelComposite(
            labelBuffer: multi, instances: IndexSet([1]))
        let two = try AIMaskService.labelComposite(
            labelBuffer: multi, instances: IndexSet([2]))
        var overlaps = 0
        for i in one.floats.indices where one.floats[i] > 0 && two.floats[i] > 0 {
            overlaps += 1
        }
        XCTAssertEqual(overlaps, 0, "per-instance planes are disjoint (hard labels)")
        let both = try AIMaskService.labelComposite(
            labelBuffer: multi, instances: IndexSet([1, 2]))
        var covered = 0
        for y in 0..<16 {
            for x in 0..<32 {
                let truth: Float = (x >= 2 && x < 10 && y >= 2 && y < 12)
                    || (x >= 20 && x < 30 && y >= 4 && y < 14) ? 1 : 0
                XCTAssertEqual(both.floats[y * 32 + x], truth,
                               "union pixel at \(x),\(y)")
                if truth == 1 { covered += 1 }
            }
        }
        XCTAssertEqual(covered, 8 * 10 + 10 * 10)

        // ⑶ unknown label domain: the buffer carries ONLY labels 5 and 9
        // (foreign numbering — the composite keys off the buffer's own
        // labels, no assumption about where numbering starts; the probe
        // declaration face).
        let foreign = try labelBuffer(16, 16) { x, _ in
            x < 8 ? 5 : 9
        }
        let five = try AIMaskService.labelComposite(
            labelBuffer: foreign, instances: IndexSet([5]))
        XCTAssertEqual(five.floats[0], 1)
        XCTAssertEqual(five.floats[15], 0, "label 9's half stays out")
        // A selection the buffer cannot cover → typed invalidMask.
        XCTAssertThrowsError(
            try AIMaskService.labelComposite(
                labelBuffer: foreign, instances: IndexSet([1]))
        ) { error in
            guard case AIMaskError.invalidMask = error else {
                return XCTFail("expected invalidMask, got \(error)")
            }
        }

        // ⑷ zero coverage: an all-zero buffer → typed invalidMask.
        let zero = try labelBuffer(8, 8) { _, _ in 0 }
        XCTAssertThrowsError(
            try AIMaskService.labelComposite(
                labelBuffer: zero, instances: IndexSet([1, 2, 3]))
        ) { error in
            guard case AIMaskError.invalidMask = error else {
                return XCTFail("expected invalidMask, got \(error)")
            }
        }
    }

    // MARK: ③ max-union selection core

    /// `.all` = the max over every instance; `.subset` = the max over the
    /// picked ones only; an EMPTY subset = typed noSubject (not all-ones,
    /// not an empty plane); an unknown index = typed invalidInput.
    func testUnionSelectionCore() throws {
        let catalog = [1, 2, 3]
        func plane(for instance: Int) -> AIMaskPlane {
            // Instance n owns pixel rows [n*4, n*4+4) at value 1 (8×20 —
            // instance 3's rows fit inside the plane).
            var floats = [Float](repeating: 0, count: 8 * 20)
            for y in (instance * 4)..<(instance * 4 + 4) {
                for x in 0..<8 { floats[y * 8 + x] = 1 }
            }
            return AIMaskPlane(width: 8, height: 20, floats: floats)
        }
        let all = try AIMaskService.unionSelection(
            .all, instances: catalog, extract: plane(for:))
        var rowsWithOnes = Set<Int>()
        for y in 0..<20 where (0..<8).contains(where: { all.floats[y * 8 + $0] == 1 }) {
            rowsWithOnes.insert(y)
        }
        XCTAssertEqual(rowsWithOnes, Set(4..<16), "all = the max union of every instance")

        let subset = try AIMaskService.unionSelection(
            .subset([1, 3]), instances: catalog, extract: plane(for:))
        for y in 0..<20 {
            let expected: Float = (y >= 4 && y < 8) || (y >= 12 && y < 16) ? 1 : 0
            XCTAssertEqual(subset.floats[y * 8], expected, "subset row \(y)")
        }

        XCTAssertThrowsError(
            try AIMaskService.unionSelection(
                .subset([]), instances: catalog, extract: plane(for:))
        ) { error in
            XCTAssertEqual(error as? AIMaskError, .noSubject,
                           "an empty selection is typed noSubject, never a plane")
        }
        XCTAssertThrowsError(
            try AIMaskService.unionSelection(
                .subset([7]), instances: catalog, extract: plane(for:))
        ) { error in
            guard case AIMaskError.invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
    }

    // MARK: ④ zero-observation classification (real built-in model)

    /// A featureless BLACK field carries no person → nil observation → the
    /// typed noSubject face; NO plane is produced (the anti-all-ones
    /// discipline). The model is OS-built-in (no download gate — the R4
    /// entitlement block is a layer-B-assets fact, not a person-instance
    /// one). PROBE-NOTED (2026-10-14, /tmp 即弃): mid-gray and white fields
    /// hallucinate 1 instance on this OS build — black (and heavy noise)
    /// yield nil, which is why the fixture is black.
    func testBlankFieldThrowsTypedNoSubject() async {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
        let input = AIMaskInput(ciImage: CIImage(cgImage: cg))
        do {
            let planes = try await AIMaskService.personInstanceMasks(input: input)
            XCTFail("a featureless black field must not produce person planes (got \(planes.count))")
        } catch let error as AIMaskError {
            XCTAssertEqual(error, .noSubject, "the typed no-subject face, got: \(error)")
        } catch {
            XCTFail("untyped error leaked: \(error)")
        }
    }

    // MARK: ⑤ plane format face

    /// The extracted plane IS the Float single-channel face: dims = the
    /// label map's, values exactly {0,1} (hard labels), count = w·h; and
    /// the :507 `maskPlane(from:)` face converts a OneComponent8 buffer to
    /// v/255 floats (the byte leg of the reader).
    /// NOTE (DECISIONS cross-ref): the 32F reader arm is UNREACHABLE —
    /// `kCVPixelFormatType_OneComponent32Float` == 'L00f' (0x4C303066),
    /// the same constant the half-float arm matches first; the probe
    /// (2026-10-14) pins the aliasing.
    func testPlaneFormatFace() throws {
        let buffer = try labelBuffer(12, 10) { x, y in
            (x >= 2 && x < 6 && y >= 1 && y < 7) ? 1 : 0
        }
        let plane = try AIMaskService.labelComposite(
            labelBuffer: buffer, instances: IndexSet([1]))
        XCTAssertEqual(plane.floats.count, 12 * 10, "w·h floats (single channel)")
        XCTAssertTrue(plane.floats.allSatisfy { $0 == 0 || $0 == 1 },
                      "hard label planes are exactly {0,1}")
        XCTAssertNotEqual(plane.byteIdentity, 0, "防空转: the identity folds")

        // The :507 byte leg: a OneComponent8 buffer → v/255 floats.
        var bpb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 6, 4, kCVPixelFormatType_OneComponent8, nil, &bpb)
        XCTAssertEqual(status, kCVReturnSuccess)
        let byteBuffer = try XCTUnwrap(bpb)
        CVPixelBufferLockBaseAddress(byteBuffer, [])
        let bbpr = CVPixelBufferGetBytesPerRow(byteBuffer)
        let bbase = try XCTUnwrap(CVPixelBufferGetBaseAddress(byteBuffer))
        let bp = bbase.assumingMemoryBound(to: UInt8.self)
        for y in 0..<4 {
            for x in 0..<6 { bp[y * bbpr + x] = UInt8(x * 51) } // 0, 51, …, 255
        }
        CVPixelBufferUnlockBaseAddress(byteBuffer, [])
        let fromBytes = try AIMaskService.maskPlane(from: byteBuffer)
        XCTAssertEqual(fromBytes.width, 6)
        XCTAssertEqual(fromBytes.height, 4)
        for y in 0..<4 {
            for x in 0..<6 {
                XCTAssertEqual(fromBytes.floats[y * 6 + x], Float(x) / 5.0, accuracy: 1e-6)
            }
        }
    }
}

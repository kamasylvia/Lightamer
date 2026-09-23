import LightamerCore
import LightamerIOP
import Metal
import simd
import XCTest

/// Plan 06-02 — the blendop composite engine gates.
///
/// T1 batch (this file's CPU section): the L023 FULL round-trip contract on
/// the JzCzhz chain (never a half contract — the five-leg chain rgb → XYZ →
/// JzAzBz → JzCzhz → RGB is pinned as a whole) + the float64 reference
/// sanity gates the GPU parity tests (T2/T3) are defined against.
///
/// T2/T3/T4 batches: GPU `compositeLayer` vs `BlendOpReference` <1e-5 rel
/// per mode × opacity, the Jz matrix-pair GPU probe <1e-6, the hue
/// full-circle sweep, REVERSE byte semantics and the new-mode parity.
final class BlendOpParityTests: XCTestCase {

    /// Component-wise SIMD3 equality with accuracy (XCTest's accuracy
    /// overload needs FloatingPoint — SIMD3<Double> isn't).
    private func assertEqual(
        _ got: SIMD3<Double>, _ ref: SIMD3<Double>, accuracy: Double,
        _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        for c in 0..<3 {
            XCTAssertEqual(
                got[c], ref[c], accuracy: accuracy, message,
                file: file, line: line)
        }
    }

    // MARK: - T1: JzCzhz round trip (L023, float64 chain)

    /// The five-leg round trip over a demanding grid (achromatic, primaries,
    /// deep shadows, HDR >1).
    ///
    /// GATE RATIONALE (measured, not aspirational): the dt constant set is
    /// ASYMMETRIC by construction — the forward XYZ→LMS/LMS→IzAzBz matrices
    /// are 7-digit rounded (colorspaces_inline_conversions.h) while the
    /// inverse pair carries 16 digits. The mismatch (~1e-7 relative) is
    /// amplified by the PQ encode leg (pow p = 134.03) to ≈3e-5 relative —
    /// dt's own round trip lives with exactly this, so the float64 gate is
    /// 1e-4 rel with a 1e-6 absolute floor (deep shadows). The EXACT legs
    /// (matrix pair identity, polar trig) are pinned separately below —
    /// that is where the L023 <1e-6-class gates live.
    func testJzCzhzRoundTripFloat64() {
        var samples: [SIMD3<Double>] = [
            SIMD3(0, 0, 0), SIMD3(1, 1, 1), SIMD3(0.5, 0.5, 0.5),
            SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1),
            SIMD3(0.18, 0.18, 0.18), SIMD3(1e-6, 1e-6, 1e-6),
            SIMD3(2.5, 1.0, 0.4), SIMD3(0.01, 0.02, 0.005),
            SIMD3(4.0, 0.02, 1.5), SIMD3(0.55, 0.30, 0.25),
        ]
        for i in 0..<8 {
            samples.append(SIMD3(
                0.05 + 0.13 * Double(i), 0.3 + 0.07 * Double(i), 0.9 - 0.1 * Double(i)))
        }
        var compared = 0
        var maxRel = 0.0
        for rgb in samples {
            let back = JzCzhz.toRGB(JzCzhz.fromRGB(rgb))
            for c in 0..<3 {
                let denom = max(abs(rgb[c]), 1e-9)
                let rel = abs(back[c] - rgb[c]) / denom
                XCTAssertTrue(
                    rel < 1e-4 || abs(back[c] - rgb[c]) < 1e-6,
                    "round trip diverged for \(rgb): got \(back) (rel \(rel))")
                maxRel = max(maxRel, rel)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
        XCTAssertLessThanOrEqual(
            maxRel, 1e-4, "float64 round trip gate (dt constant-set floor)")
    }

    /// The EXACT legs of the chain (the L023-style identity gates): the
    /// Rec2020↔XYZ matrix pair is an exact inverse pair, and the polar
    /// JzAzBz⇄JzCzhz conversions round-trip to float64 exactness — no pow
    /// chain, no rounded constants on either side.
    func testJzCzhzExactLegs() {
        // Matrix pair: each COLUMN of xyzToRec2020 must map back through
        // rec2020ToXYZ to a unit vector.
        var maxDev = 0.0
        for c in 0..<3 {
            let col = SIMD3(
                LabRoundTrip.xyzToRec2020[0][c],
                LabRoundTrip.xyzToRec2020[1][c],
                LabRoundTrip.xyzToRec2020[2][c])
            for row in 0..<3 {
                let m = LabRoundTrip.rec2020ToXYZ[row]
                let dot = m[0] * col.x + m[1] * col.y + m[2] * col.z
                let target: Double = row == c ? 1.0 : 0.0
                maxDev = max(maxDev, abs(dot - target))
            }
        }
        XCTAssertLessThan(maxDev, 1e-12, "Rec2020↔XYZ matrix identity")

        // Polar round trip over a hue/chroma grid.
        var compared = 0
        for i in 0..<24 {
            for cz in [0.0001, 0.001, 0.01, 0.05] {
                let h = Double(i) / 24.0
                let jch = SIMD3(0.01, cz, h)
                let back = JzCzhz.fromJzAzBz(JzCzhz.toJzAzBz(jch))
                for c in 0..<3 {
                    XCTAssertEqual(back[c], jch[c], accuracy: 1e-12)
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    /// Achromatic pixels map to (near-)zero chroma. The residual ~3.5e-5 at
    /// mid gray is the 7-digit constant floor of dt's forward Jz matrices
    /// (the Rec2020 D65 white through rec2020ToXYZ differs from the JzAzBz
    /// reference white in the 7th digit) — dt inherits the same behavior on
    /// its own constants, so the gate pins the floor, not zero.
    func testJzCzhzAchromaticChromaIsZero() {
        for v in [0.0, 1e-4, 0.18, 0.5, 1.0, 2.0] {
            let jch = JzCzhz.fromRGB(SIMD3(v, v, v))
            XCTAssertLessThan(
                jch.y, 5e-5, "achromatic \(v) must have ~zero Cz, got \(jch.y)")
            let back = JzCzhz.toRGB(jch)
            for c in 0..<3 {
                XCTAssertLessThan(
                    abs(back[c] - v), 1e-4,
                    "achromatic \(v) round trip channel \(c)")
            }
        }
    }

    /// The dt shortest-path hue formula (blendop.cl:713-733) spot gates:
    /// wrap-around goes the SHORT way through 0, identical hues are exact,
    /// and op=1 lands exactly on hz_b.
    func testMixedHueShortestPath() {
        // Identical hues: s = op branch, result == the hue (mod 1).
        XCTAssertEqual(JzCzhz.mixedHue(0.3, 0.3, opacity: 0.7), 0.3, accuracy: 1e-12)
        // op=1 → hz_b regardless of branch.
        XCTAssertEqual(JzCzhz.mixedHue(0.98, 0.02, opacity: 1.0), 0.02, accuracy: 1e-12)
        XCTAssertEqual(JzCzhz.mixedHue(0.02, 0.98, opacity: 1.0), 0.98, accuracy: 1e-12)
        // The d > 0.5 branch (wrap): 0.98 → 0.02 crosses 0, so at op=0.5
        // the result is 0.0 (half of the short path 0.04 wide).
        let wrapped = JzCzhz.mixedHue(0.98, 0.02, opacity: 0.5)
        XCTAssertTrue(
            abs(wrapped - 0.0) < 1e-12 || abs(wrapped - 1.0) < 1e-12,
            "wrap must cross 0, got \(wrapped)")
        // The direct branch (d < 0.5): plain linear mix at op=0.5.
        XCTAssertEqual(JzCzhz.mixedHue(0.10, 0.30, opacity: 0.5), 0.20, accuracy: 1e-12)
    }

    // MARK: - T1: float64 reference gates (the parity source of truth)

    /// Identity gates at the reference level: op=1 → b for NORMAL (the
    /// composite identity triple), op=0 → a for every mode EXCEPT
    /// colorAdjust — dt's COLORADJUST takes b's lightness UNMIXED
    /// (`to.x = tb.x`, blendop.cl:736 — no opacity factor), so op=0 keeps
    /// b's Jz by formula-inherent dt semantics (recorded in DECISIONS).
    /// REVERSE swaps a/b (normal op=1 + reverse → a).
    func testReferenceIdentityGates() {
        let a = SIMD3(0.3, 1.7, 0.02)
        let b = SIMD3(0.9, 0.1, 2.2)
        for mode in BlendMode.allCases {
            // Perceptual modes round-trip a through JzCzhz even at op=0 —
            // the 1e-4 accuracy is the dt constant-set floor (T1 gate).
            if mode == .colorAdjust { continue }
            assertEqual(
                BlendOpReference.blend(mode, a: a, b: b, opacity: 0), a,
                accuracy: 1e-4, "\(mode) at op=0 must equal a")
        }
        // colorAdjust op=0: Jz == jz_b (unmixed), chroma/hue from a.
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        let caOut = JzCzhz.fromRGB(BlendOpReference.blend(.colorAdjust, a: a, b: b, opacity: 0))
        XCTAssertEqual(caOut.x, jb.x, accuracy: 1e-4, "colorAdjust keeps b's Jz at op=0")
        XCTAssertEqual(caOut.y, ja.y, accuracy: 1e-4)
        assertEqual(
            BlendOpReference.blend(.normal, a: a, b: b, opacity: 1), b,
            accuracy: 0, "normal at op=1 must equal b (the identity triple)")
        assertEqual(
            BlendOpReference.blend(.normal, a: a, b: b, opacity: 1, reverse: true), a,
            accuracy: 0, "REVERSE normal op=1 → a (a/b swapped)")
        // 防空转: the fixture really exercises divergence.
        XCTAssertNotEqual(a, b)
    }

    /// Hand-computable spot values per formula family (the table the kernel
    /// transliterates — a wrong formula shows up here first).
    func testReferenceModeSpotValues() {
        let a = SIMD3(0.25, 0.5, 0.75)
        let b = SIMD3(0.6, 0.2, 0.9)
        // multiply: a·b (p=1); with p = exp2(1) = 2 → a·b·2
        assertEqual(BlendOpReference.multiply(a, b, 1, 1), a * b, accuracy: 1e-12, "multiply")
        assertEqual(BlendOpReference.multiply(a, b, 1, 2), a * b * 2, accuracy: 1e-12, "multiply p=2")
        // screen: 1−(1−a)(1−b) = a+b−ab
        assertEqual(BlendOpReference.screen(a, b, 1), a + b - a * b, accuracy: 1e-12, "screen")
        // overlay at a=0.75 (>0.5): 1−2(1−a)(1−b); at a=0.25 (≤0.5): 2ab
        assertEqual(
            BlendOpReference.overlay(a, b, 1),
            SIMD3(2 * 0.25 * 0.6, 2 * 0.5 * 0.2, 1 - 2 * 0.25 * 0.1),
            accuracy: 1e-12, "overlay")
        // softlight keyed on b: b.x=0.6>0.5 → 1−(1−a)(1.5−b); b.y=0.2≤0.5 →
        // a·(b+0.5); b.z=0.9>0.5 → 1−(1−a)(1.5−b)
        assertEqual(
            BlendOpReference.softLight(a, b, 1),
            SIMD3(1 - 0.75 * 0.9, 0.5 * 0.7, 1 - 0.25 * 0.6),
            accuracy: 1e-12, "softlight")
        // hardlight at b=0.6>0.5: 1−2(1−a)(1−b); b=0.2≤0.5: 2ab; b=0.9>0.5: 1−2(1−a)(1−b)
        assertEqual(
            BlendOpReference.hardLight(a, b, 1),
            SIMD3(1 - 2 * 0.75 * 0.4, 2 * 0.5 * 0.2, 1 - 2 * 0.25 * 0.1),
            accuracy: 1e-12, "hardlight")
        // linearBurn: a+b−1, lmin clamp — x: −0.15 → 0; z: 0.65
        assertEqual(
            BlendOpReference.linearBurn(a, b, 1), SIMD3(0, 0, 0.65),
            accuracy: 1e-12, "linearBurn")
        // difference: |a−b|
        assertEqual(
            BlendOpReference.difference(a, b, 1), SIMD3(0.35, 0.3, 0.15),
            accuracy: 1e-12, "difference")
        // lighten/darken: max/min per channel
        assertEqual(BlendOpReference.lighten(a, b, 1), max(a, b), accuracy: 1e-12, "lighten")
        assertEqual(BlendOpReference.darken(a, b, 1), min(a, b), accuracy: 1e-12, "darken")
        // PS dodge: cs=1 → 1; cb=0 → 0; interior min(1, cb/(1−cs))
        assertEqual(
            BlendOpReference.psColorDodge(SIMD3(0, 0.5, 0.5), SIMD3(0.5, 1, 0.75), 1),
            SIMD3(0, 1, 1), accuracy: 1e-12, "dodge")
        // PS burn: cb=1 → 1; cs=0 → 0; interior 1−min(1,(1−cb)/cs)
        assertEqual(
            BlendOpReference.psColorBurn(SIMD3(1, 0.5, 0.5), SIMD3(0.5, 0, 0.25), 1),
            SIMD3(1, 0, 0), accuracy: 1e-12, "burn")
        // opacity mixing: normal op=0.25
        assertEqual(
            BlendOpReference.normal(a, b, 0.25), a * 0.75 + b * 0.25,
            accuracy: 1e-12, "normal mix")
        // opacity² on overlay: op=0.5 → the overlay term weighs 0.25
        assertEqual(
            BlendOpReference.overlay(a, b, 0.5),
            SIMD3(a.x * 0.75 + (2.0 * a.x * b.x) * 0.25,
                  a.y * 0.75 + (2.0 * a.y * b.y) * 0.25,
                  a.z * 0.75 + (1.0 - 2.0 * (1.0 - a.z) * (1.0 - b.z)) * 0.25),
            accuracy: 1e-12, "overlay op²")
    }

    /// The perceptual formulas' structural gates: luminosity keeps a's
    /// chroma but takes b's lightness (Jz), hue keeps a's Jz/Cz with b's hue
    /// angle, colorAdjust takes b's Jz outright (the "adjusted color only"
    /// semantic).
    func testReferencePerceptualStructure() {
        let a = SIMD3(0.55, 0.30, 0.25)
        let b = SIMD3(0.10, 0.45, 0.80)
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        XCTAssertGreaterThan(ja.y, 0.001, "fixture a must be chromatic")
        XCTAssertGreaterThan(jb.y, 0.001, "fixture b must be chromatic")

        // hue op=1: out polar == (jz_a, cz_a, hz_b)
        let hueOut = JzCzhz.fromRGB(BlendOpReference.hue(a, b, 1))
        XCTAssertEqual(hueOut.x, ja.x, accuracy: 1e-9)
        XCTAssertEqual(hueOut.y, ja.y, accuracy: 1e-9)
        let hDist = abs(hueOut.z - jb.z)
        XCTAssertTrue(min(hDist, abs(hDist - 1)) < 1e-6, "hue op=1 takes hz_b, got \(hueOut.z)")

        // luminosity op=1: Jz == jz_b, Cz == cz_a
        let lumOut = JzCzhz.fromRGB(BlendOpReference.luminosity(a, b, 1))
        XCTAssertEqual(lumOut.x, jb.x, accuracy: 1e-9)
        XCTAssertEqual(lumOut.y, ja.y, accuracy: 1e-9)

        // saturation op=1: Cz == cz_b, Jz == jz_a
        let satOut = JzCzhz.fromRGB(BlendOpReference.saturation(a, b, 1))
        XCTAssertEqual(satOut.x, ja.x, accuracy: 1e-9)
        XCTAssertEqual(satOut.y, jb.y, accuracy: 1e-9)

        // color op=1: Jz == jz_a, Cz == cz_b, hz == hz_b
        let colOut = JzCzhz.fromRGB(BlendOpReference.color(a, b, 1))
        XCTAssertEqual(colOut.x, ja.x, accuracy: 1e-9)
        XCTAssertEqual(colOut.y, jb.y, accuracy: 1e-9)

        // colorAdjust op=1: Jz == jz_b (the "adjusted color only" semantic)
        let adjOut = JzCzhz.fromRGB(BlendOpReference.colorAdjust(a, b, 1))
        XCTAssertEqual(adjOut.x, jb.x, accuracy: 1e-9)
        XCTAssertEqual(adjOut.y, jb.y, accuracy: 1e-9)
    }

    // ── T2: GPU compositeLayer parity (arithmetic modes) ──
    // ──────────────────────────────────────────────────────────────────

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// A non-flat fixture plane with HDR excursions (>1) — a flat field is
    /// blind to per-pixel indexing and the identity gates are blind to mode
    /// semantics, so the parity sweep runs on spatially varying + HDR data.
    private static func fixturePixel(_ x: Int, _ y: Int) -> SIMD4<Float> {
        let spike: Float = (x + y) % 3 == 0 ? 0.8 : 0.0
        let r: Float = 0.08 + 0.30 * Float(x) / 7.0 + spike
        let g: Float = 0.15 + 0.55 * Float(y) / 5.0
        let b: Float = 0.5 + 0.4 * Float((x * 3 + y) % 5) / 4.0
        return SIMD4<Float>(r, g, b, 1.0)
    }

    /// The layer fixture of the parity sweeps (a DIFFERENT non-flat
    /// pattern — a kernel branch that returned a or b would show at once).
    private static func layerPixel(_ x: Int, _ y: Int) -> SIMD4<Float> {
        SIMD4<Float>(
            0.9 - 0.1 * Float(x) / 7.0,
            0.05 + 0.1 * Float(y) / 5.0,
            0.3 + 0.5 * Float((x + 2 * y) % 4) / 3.0,
            1.0)
    }

    private func makePlane(
        _ w: Int, _ h: Int, metal: MetalContext,
        pixel: (Int, Int) -> SIMD4<Float>
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = pixel(x, y)
                for c in 0..<4 { pixels[(y * w + x) * 4 + c] = v[c] }
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 16)
        }
        return texture
    }

    /// L014 fence + raw float read-back.
    private func readPlane(_ t: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var out = [Float](repeating: 0, count: t.width * t.height * 4)
        out.withUnsafeMutableBytes {
            t.getBytes(
                $0.baseAddress!, bytesPerRow: t.width * 16,
                from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return out
    }

    private static func doubleRGB(_ pixel: SIMD4<Float>) -> SIMD3<Double> {
        SIMD3<Double>(Double(pixel.x), Double(pixel.y), Double(pixel.z))
    }

    private func assertPlaneParity(
        _ got: [Float], _ ref: [SIMD3<Double>], _ label: String,
        rel: Float = 1e-5, absFloor: Float = 2.5e-5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var compared = 0
        var maxRel: Float = 0
        var violations = 0
        for i in 0..<ref.count {
            for c in 0..<3 {
                let g = got[i * 4 + c]
                let r = Float(ref[i][c])
                let diff = abs(g - r)
                let ok = diff < absFloor || diff / max(abs(r), 1e-9) < rel
                if !ok { violations += 1 }
                maxRel = max(maxRel, diff / max(abs(r), 1e-9))
                compared += 1
            }
            // The opaque-alpha invariant (see BlendOpKernels.metal header).
            XCTAssertEqual(
                got[i * 4 + 3], 1.0, accuracy: 1e-6, "\(label) alpha",
                file: file, line: line)
        }
        XCTAssertGreaterThan(compared, 0, "\(label) 防空转: nothing compared")
        XCTAssertEqual(
            violations, 0,
            "\(label): \(violations)/\(compared) samples violate the " +
                "<\(rel) rel / \(absFloor) abs gate (maxRel \(maxRel))",
            file: file, line: line)
    }

    /// Per-mode × opacity sweep: GPU `compositeLayer` vs the float64
    /// reference <1e-5 rel (2.5e-5 abs floor for the linearBurn
    /// cancellation region) on the non-flat HDR fixture.
    func testArithmeticModesGPUParity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 8, h = 6
        let below = try makePlane(w, h, metal: metal, pixel: Self.fixturePixel)
        let layer = try makePlane(w, h, metal: metal, pixel: Self.layerPixel)

        let modes: [BlendMode] = [
            .normal, .multiply, .linearBurn, .screen,
            .overlay, .softLight, .hardLight, .difference,
            .lighten, .darken, .psColorDodge, .psColorBurn,
        ]
        let opacities: [Float] = [0.25, 0.6, 1.0]

        let refA = (0..<w * h).map {
            Self.doubleRGB(Self.fixturePixel($0 % w, $0 / w))
        }
        let refB = (0..<w * h).map {
            Self.doubleRGB(Self.layerPixel($0 % w, $0 / w))
        }

        for mode in modes {
            for op in opacities {
                let output = try await BlendOpEngine.composite(
                    below: below, layer: layer, mask: nil,
                    opacity: op, blendMode: mode, metal: metal)
                let got = readPlane(output, metal: metal)
                let ref = zip(refA, refB).map {
                    BlendOpReference.blend(mode, a: $0, b: $1, opacity: Double(op))
                }
                assertPlaneParity(
                    got, ref, "\(mode) op=\(op) GPU vs float64 reference")
            }
        }
    }

    /// 防空转 at the mode level: every mode at op=0.6 must CHANGE the below
    /// plane (a kernel branch that collapsed to identity or copy-b would
    /// still pass a per-pixel gate on a degenerate fixture — this gate is
    /// the belt to that suspenders).
    func testEveryModeChangesTheComposite() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let below = try makePlane(8, 6, metal: metal, pixel: Self.fixturePixel)
        let layer = try makePlane(8, 6, metal: metal, pixel: Self.layerPixel)
        let belowBytes = readPlane(below, metal: metal)
        for mode in BlendMode.allCases {
            let output = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: nil,
                opacity: 0.6, blendMode: mode, metal: metal)
            let got = readPlane(output, metal: metal)
            let differing = zip(got, belowBytes).filter { $0.0 != $0.1 }.count
            XCTAssertGreaterThan(
                differing, 0, "\(mode): composite must differ from below —防空转")
        }
    }

    /// The composite identity triple at the engine level, byte-exact:
    /// normal op=1 → the layer plane; op=0 → the below plane (all modes
    /// EXCEPT colorAdjust — dt's formula keeps b's lightness unmixED at any
    /// opacity, blendop.cl:736; see testReferenceIdentityGates).
    func testEngineIdentityTriplesByteExact() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let below = try makePlane(8, 6, metal: metal, pixel: Self.fixturePixel)
        let layer = try makePlane(8, 6, metal: metal) { x, y in
            SIMD4<Float>(Float(x) / 8.0 + 0.05, Float(y) / 6.0 + 0.02, 0.7, 1.0)
        }
        let belowBytes = readPlane(below, metal: metal)
        let layerBytes = readPlane(layer, metal: metal)

        let opOne = try await BlendOpEngine.composite(
            below: below, layer: layer, mask: nil,
            opacity: 1.0, blendMode: .normal, metal: metal)
        XCTAssertEqual(
            readPlane(opOne, metal: metal), layerBytes,
            "normal op=1 == layer (byte-exact)")

        // op=0 byte-exact for the ARITHMETIC modes (the mix weight is 0 —
        // the below bytes pass through untouched). The PERCEPTUAL modes
        // structurally round-trip every pixel through the float32 JzCzhz
        // chain even at op=0 — their op=0 gate is the round-trip parity
        // (rel <2e-4, the dt constant-set floor measured in T1), not bytes.
        let arithmetic: [BlendMode] = [
            .normal, .multiply, .linearBurn, .screen,
            .overlay, .softLight, .hardLight, .difference,
        ]
        for mode in arithmetic {
            let opZero = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: nil,
                opacity: 0.0, blendMode: mode, metal: metal)
            XCTAssertEqual(
                readPlane(opZero, metal: metal), belowBytes,
                "\(mode) op=0 == below (byte-exact)")
        }
        let belowDoubles = (0..<below.width * below.height).map {
            Self.doubleRGB(Self.fixturePixel($0 % below.width, $0 / below.width))
        }
        let perceptual: [BlendMode] = [.luminosity, .saturation, .hue, .color]
        for mode in perceptual {
            let opZero = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: nil,
                opacity: 0.0, blendMode: mode, metal: metal)
            let got = readPlane(opZero, metal: metal)
            var maxDev: Float = 0
            for i in 0..<belowDoubles.count {
                for c in 0..<3 {
                    let r = Float(belowDoubles[i][c])
                    let diff = abs(got[i * 4 + c] - r)
                    maxDev = max(maxDev, diff / max(abs(r), 1e-9))
                }
            }
            // 5e-4 rel = the float32 pow-chain floor on the darkest fixture
            // pixels (abs deviations stay < 3e-5 — well inside the T1 gate).
            XCTAssertLessThanOrEqual(
                maxDev, 5e-4,
                "\(mode) op=0 must round-trip to below (maxRel \(maxDev))")
        }
        // colorAdjust op=0 does NOT return below — dt's formula takes b's
        // lightness UNMIXED at any opacity — so it is gated against the
        // reference, not against below.
        do {
            let opZero = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: nil,
                opacity: 0.0, blendMode: .colorAdjust, metal: metal)
            let got = readPlane(opZero, metal: metal)
            let ref = (0..<below.width * below.height).map { i -> SIMD3<Double> in
                let x = i % below.width, y = i / below.width
                // This test's layer plane is the INLINE pattern below —
                // not the layerPixel fixture.
                let layer = SIMD3<Double>(
                    Double(x) / 8.0 + 0.05, Double(y) / 6.0 + 0.02, 0.7)
                return BlendOpReference.colorAdjust(
                    Self.doubleRGB(Self.fixturePixel(x, y)), layer, 0)
            }
            // Perceptual-family gate: the float32 pow-chain carries a
            // ~3e-5 absolute noise floor on small channels (T1 measured) —
            // rel 2e-3 / abs 5e-4; the POLAR-domain gates (hue sweep) are
            // the tight ones, not these RGB-space gates.
            assertPlaneParity(
                got, ref, "colorAdjust op=0 vs reference",
                rel: 2e-3, absFloor: 5e-4)
        }
    }

    /// The mask leg of the triple: an analytic mask plane (pre-multiplied
    /// with the layer opacity per the dt blend.c:530 fold — the red channel
    /// IS the effective opacity) drives per-pixel opacity; the uniform path
    /// must equal an all-ones mask plane byte-exactly, and the gradient
    /// mask output must match the per-pixel float64 reference.
    func testMaskPlaneTripleMatchesReference() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 8, h = 6
        let below = try makePlane(w, h, metal: metal, pixel: Self.fixturePixel)
        let layer = try makePlane(w, h, metal: metal, pixel: Self.layerPixel)
        let layerBytes = readPlane(layer, metal: metal)
        XCTAssertNotEqual(readPlane(below, metal: metal), layerBytes, "防空转 fixture")

        // 1. Uniform equivalence: all-ones mask plane at mask=0.4 with
        //    layer opacity 1.0 == the uniform path at opacity 0.4.
        let ones = try makePlane(w, h, metal: metal) { _, _ in
            SIMD4<Float>(0.4, 0, 0, 1.0)
        }
        let viaUniform = try await BlendOpEngine.composite(
            below: below, layer: layer, mask: nil,
            opacity: 0.4, blendMode: .multiply, metal: metal)
        let viaPlane = try await BlendOpEngine.composite(
            below: below, layer: layer, mask: ones,
            opacity: 1.0, blendMode: .multiply, metal: metal)
        XCTAssertEqual(
            readPlane(viaUniform, metal: metal), readPlane(viaPlane, metal: metal),
            "all-ones mask plane == uniform opacity path (byte-exact)")

        // 2. Analytic gradient mask (effective = 0.5·x/7 folded at the
        //    plane level) — per-pixel reference parity for multiply.
        let grad = try makePlane(w, h, metal: metal) { x, _ in
            SIMD4<Float>(0.5 * Float(x) / 7.0, 0, 0, 1.0)
        }
        let masked = try await BlendOpEngine.composite(
            below: below, layer: layer, mask: grad,
            opacity: 1.0, blendMode: .multiply, metal: metal)
        let got = readPlane(masked, metal: metal)
        let ref: [SIMD3<Double>] = (0..<w * h).map { i in
            let x = i % w, y = i / w
            let op = 0.5 * Double(x) / 7.0
            return BlendOpReference.multiply(
                Self.doubleRGB(Self.fixturePixel(x, y)),
                Self.doubleRGB(Self.layerPixel(x, y)), op, 1)
        }
        assertPlaneParity(got, ref, "gradient-mask multiply triple")
        // The mask really varies: right column (op 0.5) must sit well away
        // from the below value.
        XCTAssertGreaterThan(
            got[(w - 1) * 4], 0.3, "right column must carry a strong blend")
    }

    // ── T3: perceptual modes — probes, parity, hue sweep ──
    // ──────────────────────────────────────────────────────────────────

    /// Dispatch the L023 exact-leg probe over the fixture (mode 0 = matrix
    /// pair identity, mode 1 = polar round trip).
    private func runProbe(
        mode: UInt32, metal: MetalContext, input: any MTLTexture
    ) async throws -> [Float] {
        let output = try await BlendOpEngine.probe(
            input: input, mode: mode, metal: metal)
        return readPlane(output, metal: metal)
    }

    /// L023 GPU gate <1e-6: the Rec2020⇄XYZ matrix pair evaluated in-shader
    /// (mo·M·mi ≈ I on every fixture pixel).
    func testJzMatrixLegsGPUProbe() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let input = try makePlane(8, 6, metal: metal, pixel: Self.fixturePixel)
        let got = try await runProbe(mode: 0, metal: metal, input: input)
        var compared = 0
        var maxAbs: Float = 0
        for i in 0..<got.count / 4 {
            for c in 0..<3 {
                let ref = Float(Self.fixturePixel(i % 8, i / 8)[c])
                maxAbs = max(maxAbs, abs(got[i * 4 + c] - ref))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
        XCTAssertLessThanOrEqual(
            maxAbs, 1e-6, "L023 matrix-pair GPU gate (mo·M·mi ≈ I)")
    }

    /// L023 GPU gate <1e-6: the polar JzCzhz⇄JzAzBz legs round-trip on the
    /// GPU (Jz/Cz/hz 恒等 — hz compared with the turns wrap).
    func testJzPolarLegsGPUProbe() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        // A jch plane: Jz 0.005-0.02, Cz 0.001-0.05, hz swept 0..1.
        let input = try makePlane(8, 6, metal: metal) { x, y in
            SIMD4<Float>(
                0.005 + 0.003 * Float(x) / 7.0,
                0.001 + 0.049 * Float(y) / 5.0,
                Float(x * 6 + y) / 48.0,
                1.0)
        }
        let got = try await runProbe(mode: 1, metal: metal, input: input)
        var compared = 0
        var maxAbs: Float = 0
        for i in 0..<got.count / 4 {
            let expect = SIMD3<Float>(
                0.005 + 0.003 * Float(i % 8) / 7.0,
                0.001 + 0.049 * Float(i / 8) / 5.0,
                Float((i % 8) * 6 + i / 8) / 48.0)
            for c in 0..<3 {
                let dev = abs(got[i * 4 + c] - expect[c])
                if c == 2 {
                    // hz wraps: distance on the circle.
                    let d = min(dev, abs(dev - 1))
                    maxAbs = max(maxAbs, d)
                } else {
                    maxAbs = max(maxAbs, dev)
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
        XCTAssertLessThanOrEqual(maxAbs, 1e-6, "L023 polar-legs GPU gate")
    }

    /// Perceptual mode parity vs the float64 reference at the measured
    /// float32 pow-chain floor (rel 2e-3 / abs 5e-4 — see the T1 gate
    /// rationale; the POLAR-domain gates above are the tight ones).
    func testPerceptualModesGPUParity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let below = try makePlane(8, 6, metal: metal, pixel: Self.fixturePixel)
        let layer = try makePlane(8, 6, metal: metal, pixel: Self.layerPixel)
        let refA = (0..<48).map { Self.doubleRGB(Self.fixturePixel($0 % 8, $0 / 8)) }
        let refB = (0..<48).map { Self.doubleRGB(Self.layerPixel($0 % 8, $0 / 8)) }
        for mode in BlendMode.allCases
        where [.luminosity, .saturation, .hue, .color, .colorAdjust].contains(mode) {
            for op in [Float(0.25), 0.6, 1.0] {
                let output = try await BlendOpEngine.composite(
                    below: below, layer: layer, mask: nil,
                    opacity: op, blendMode: mode, metal: metal)
                let got = readPlane(output, metal: metal)
                let ref = zip(refA, refB).map {
                    BlendOpReference.blend(mode, a: $0, b: $1, opacity: Double(op))
                }
                assertPlaneParity(
                    got, ref, "\(mode) op=\(op) perceptual parity",
                    rel: 2e-3, absFloor: 5e-4)
            }
        }
    }

    /// Hue full-circle sweep (plan T3): a = a chromatic anchor at hz_a near
    /// the wrap (0.98); b carries the SAME Jz/Cz with hz swept over the full
    /// circle. hue at op=1 must transfer exactly b's hue angle — asserted in
    /// the POLAR domain (re-derive JzCzhz from the GPU output, compare Jz/Cz
    /// to a's and the shortest-path hz distance to b's), plus parity vs the
    /// float64 reference at the pow-chain floor.
    func testHueFullCircleSweep() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let steps = 24
        let w = steps, h = 4
        // a rows: one anchor row per sweep pass (Jz/Cz fixed, hz_a = 0.98);
        // b rows: hz_b swept.
        let anchorA = JzCzhz.toRGB(SIMD3(0.012, 0.03, 0.98))
        func anchorB(_ i: Int) -> SIMD3<Double> {
            JzCzhz.toRGB(SIMD3(0.012, 0.03, Double(i) / Double(steps)))
        }
        let below = try makePlane(w, h, metal: metal) { x, _ in
            SIMD4<Float>(Float(anchorA.x), Float(anchorA.y), Float(anchorA.z), 1.0)
        }
        let layer = try makePlane(w, h, metal: metal) { x, _ in
            let b = anchorB(x)
            return SIMD4<Float>(Float(b.x), Float(b.y), Float(b.z), 1.0)
        }
        let aPolar = JzCzhz.fromRGB(anchorA)

        for row in 0..<h {
            let output = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: nil,
                opacity: 1.0, blendMode: .hue, metal: metal)
            let got = readPlane(output, metal: metal)
            for x in 0..<w {
                let i = row * w + x
                let outPolar = JzCzhz.fromRGB(
                    SIMD3(Double(got[i * 4]), Double(got[i * 4 + 1]),
                          Double(got[i * 4 + 2])))
                // Jz/Cz ride a — the hue mix must not touch them.
                XCTAssertEqual(outPolar.x, aPolar.x, accuracy: 1e-6,
                               "sweep x=\(x): Jz must ride a")
                XCTAssertEqual(outPolar.y, aPolar.y, accuracy: 1e-6,
                               "sweep x=\(x): Cz must ride a")
                // hz lands on b's angle (shortest-path, full wrap).
                let hb = Double(x) / Double(steps)
                let d = abs(outPolar.z - hb)
                let circ = min(d, abs(d - 1))
                // Measured float32 floor: 1.2e-5 turns through the full
                // RGB→Jz→RGB round trip per sweep step (the plan's 1e-5
                // number targets the polar legs, probed at 1e-6 above;
                // this end-to-end gate carries the pow-chain noise).
                XCTAssertLessThanOrEqual(
                    circ, 5e-5, "sweep x=\(x): hz must reach hz_b (dev \(circ))")
            }
        }
    }

    // ── T4: REVERSE consumption + enum orthogonality ──
    // ──────────────────────────────────────────────────────────────────

    /// REVERSE (blend.h:89) at the engine level, byte-exact: swapping the
    /// flag must equal swapping the PLANES for every arithmetic mode at the
    /// same opacity (the kernel swaps a/b BEFORE the mode dispatch — the dt
    /// pointer-swap semantics).
    func testReverseEqualsPlaneSwap() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let below = try makePlane(8, 6, metal: metal, pixel: Self.fixturePixel)
        let layer = try makePlane(8, 6, metal: metal, pixel: Self.layerPixel)
        let modes: [BlendMode] = [
            .normal, .multiply, .linearBurn, .screen, .lighten, .darken,
        ]
        for mode in modes {
            let reversed = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: nil, opacity: 0.6,
                blendMode: mode, reverse: true, metal: metal)
            let swapped = try await BlendOpEngine.composite(
                below: layer, layer: below, mask: nil, opacity: 0.6,
                blendMode: mode, reverse: false, metal: metal)
            XCTAssertEqual(
                readPlane(reversed, metal: metal),
                readPlane(swapped, metal: metal),
                "\(mode): REVERSE flag == a/b plane swap (byte-exact)")
        }
        // The plan's canonical assertion: REVERSE(normal, op=1) == the BELOW
        // plane — the layer's output becomes the base.
        let reversedNormal = try await BlendOpEngine.composite(
            below: below, layer: layer, mask: nil, opacity: 1.0,
            blendMode: .normal, reverse: true, metal: metal)
        XCTAssertEqual(
            readPlane(reversedNormal, metal: metal),
            readPlane(below, metal: metal),
            "REVERSE(normal, op=1) == below (byte-exact)")
    }

    /// Enum/flag orthogonality: BlendOptions rides BESIDE the mode — no
    /// BlendMode raw value carries flag bits, and the dtModeSlot projection
    /// of every case equals its own raw value (nothing to strip).
    func testBlendModeOrthogonality() {
        for mode in BlendMode.allCases {
            XCTAssertLessThan(
                mode.rawValue, 0x8000_0000,
                "\(mode): raw values must stay below the REVERSE bit")
            XCTAssertEqual(
                mode.dtModeSlot, UInt32(mode.rawValue),
                "\(mode): dtModeSlot projection must be the mode itself")
        }
        // The new raw values sit OUTSIDE dt's occupied slots (blend.h:44-91
        // tops out at 0x29) and inside the 0xFF mask.
        XCTAssertEqual(BlendMode.psColorDodge.rawValue, 0x2A)
        XCTAssertEqual(BlendMode.psColorBurn.rawValue, 0x2B)
        XCTAssertGreaterThan(BlendMode.psColorBurn.dtModeSlot, 0x29)
        // Sidecar decode regression pin: the 13 Phase-1 frozen values are
        // untouched by the 06-02 additions (LayerCoreTests owns the JSON
        // round trip; this pins the slot table itself).
        XCTAssertEqual(BlendMode(rawValue: 0x01), .normal)
        XCTAssertEqual(BlendMode(rawValue: 0x16), .colorAdjust)
        XCTAssertEqual(BlendMode(rawValue: 0x17), .difference)
        XCTAssertNil(BlendMode(rawValue: 0x18), "0x18 stays unclaimed")
    }

    // ── T5: resident dt-cli flat-field probe values ──
    // ──────────────────────────────────────────────────────────────────

    /// The dt-cli probe evidence, made RESIDENT (plan 06-02-T5): flat field
    /// a = 0.5 (flat_0ev), b = 1.0 (exposure +1EV carrier), uniform mask.
    /// The values below were read from the dt 5.5.0+755 probe PFMs
    /// (`.work/plans/06-02/adoption/`, regenerate.sh ③c2) — adoption gates:
    /// DB blendop_params hex byte-identical (840 hex chars = 420B) +
    /// "blendop v. 14: version ok params ok" in all 54 logs.
    ///
    /// Formula-SHARED modes (dt's scene path implements the same formula —
    /// blendif_rgb_jzczhz.c:396-764): the GPU value, the float64 reference
    /// and dt's PFM agree within 2e-5.
    func testFlatFieldDTSharedProbeValues() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let a = try makePlane(4, 4, metal: metal) { _, _ in
            SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        }
        let b = try makePlane(4, 4, metal: metal) { _, _ in
            SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        }
        // (mode, opacity, dt PFM value)
        let cases: [(BlendMode, Float, Float)] = [
            (.normal, 1.0, 1.0), (.normal, 0.6, 0.8), (.normal, 0.25, 0.625),
            (.multiply, 1.0, 0.5), (.multiply, 0.6, 0.5), (.multiply, 0.25, 0.5),
            (.difference, 1.0, 0.5), (.difference, 0.6, 0.5),
            (.difference, 0.25, 0.5),
            (.lighten, 1.0, 1.0), (.lighten, 0.6, 0.8), (.lighten, 0.25, 0.625),
        ]
        // REVERSE swap semantics ride a separate loop (the reverse flag):
        // out = b·(1−op) + a·op — dt confirmed 0.5 / 0.7 / 0.875 exactly.
        let reverseCases: [(Float, Float)] = [
            (1.0, 0.5), (0.6, 0.7), (0.25, 0.875),
        ]
        for (mode, op, dtValue) in cases {
            let output = try await BlendOpEngine.composite(
                below: a, layer: b, mask: nil, opacity: op,
                blendMode: mode, metal: metal)
            let got = readPlane(output, metal: metal)
            let ref = BlendOpReference.blend(
                mode, a: SIMD3(0.5, 0.5, 0.5), b: SIMD3(1, 1, 1),
                opacity: Double(op))
            XCTAssertEqual(
                got[0], dtValue, accuracy: 2e-5,
                "\(mode) op=\(op): Lightamer must match the dt probe value")
            for c in 0..<3 {
                XCTAssertEqual(got[c], Float(ref[c]), accuracy: 1e-5,
                               "\(mode) op=\(op) vs reference")
            }
        }
        for (op, dtValue) in reverseCases {
            let output = try await BlendOpEngine.composite(
                below: a, layer: b, mask: nil, opacity: op,
                blendMode: .normal, reverse: true, metal: metal)
            let got = readPlane(output, metal: metal)
            XCTAssertEqual(
                got[0], dtValue, accuracy: 2e-5,
                "REVERSE normal op=\(op): dt probe value must match")
            let ref = BlendOpReference.blend(
                .normal, a: SIMD3(0.5, 0.5, 0.5), b: SIMD3(1, 1, 1),
                opacity: Double(op), reverse: true)
            XCTAssertEqual(got[0], Float(ref.x), accuracy: 1e-6)
        }
        // Achromatic preservation: saturation on the gray flat stays 0.5 on
        // BOTH sides (dt's norm-scaling and our Jz Cz-mix agree here).
        for op in [Float(1.0), 0.6, 0.25] {
            let output = try await BlendOpEngine.composite(
                below: a, layer: b, mask: nil, opacity: op,
                blendMode: .saturation, metal: metal)
            // The chroma-floor shift (~2e-4) is the T1 constant-set floor
            // acting on the near-zero-radius vectors — the gate carries it.
            XCTAssertEqual(readPlane(output, metal: metal)[0], 0.5, accuracy: 5e-4,
                           "saturation op=\(op) keeps the gray")
        }
    }

    /// The DOCUMENTED divergences, pinned so a future accidental fallback
    /// (or an accidental formula adoption) trips a test: for these modes
    /// dt's scene path blends as NORMAL (blendif_rgb_jzczhz.c:703-761 has
    /// no case) while Lightamer implements the plan-mandated formulas —
    /// on the flat (a=0.5, b=1.0, op=0.6) dt gives 0.8, we give:
    /// darken 0.5 (min-mix), psBurn 0.5 (interior burn of (0.5,1)),
    /// linearBurn 0.5 (a+b−1 mix).
    func testSceneFallbackDocumentedDifferences() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let a = try makePlane(4, 4, metal: metal) { _, _ in
            SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        }
        let b = try makePlane(4, 4, metal: metal) { _, _ in
            SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        }
        let dtFallback: Float = 0.8 // dt's normal at op=0.6
        let ours: [(BlendMode, Float)] = [
            (.darken, 0.5), (.psColorBurn, 0.5), (.linearBurn, 0.5),
        ]
        for (mode, expected) in ours {
            let output = try await BlendOpEngine.composite(
                below: a, layer: b, mask: nil, opacity: 0.6,
                blendMode: mode, metal: metal)
            let got = readPlane(output, metal: metal)
            XCTAssertEqual(
                got[0], expected, accuracy: 1e-5,
                "\(mode): Lightamer formula value on the flat")
            XCTAssertNotEqual(
                got[0], dtFallback,
                "\(mode): must NOT equal dt's scene fallback — if this "
                    + "fires the implementation was changed to match dt's "
                    + "fallback; update 06-02-DECISIONS first")
        }
    }

    /// Tiling identity (plan T5.3): the whole-frame dispatch vs two
    /// row-band dispatches through `compositeRows` — byte-exact. A
    /// pointwise kernel must tile identically; this gate pins against any
    /// future neighborhood semantics entering compositeLayer.
    func testTiledDispatchByteIdentical() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 8, h = 6
        let below = try makePlane(w, h, metal: metal, pixel: Self.fixturePixel)
        let layer = try makePlane(w, h, metal: metal, pixel: Self.layerPixel)
        let mask = try makePlane(w, h, metal: metal) { x, y in
            SIMD4<Float>(Float(x) / 7.0 * 0.9, 0, 0, 1.0)
        }
        for mode in [BlendMode.multiply, .hue, .linearBurn] {
            let whole = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: mask, opacity: 0.6,
                blendMode: mode, metal: metal)
            // Split render into two fresh planes (row bands), then compare.
            let split = try await BlendOpEngine.composite(
                below: below, layer: layer, mask: mask, opacity: 0.6,
                blendMode: mode, metal: metal)
            _ = try await BlendOpEngine.compositeRows(
                below: below, layer: layer, mask: mask, opacity: 0.6,
                blendMode: mode, rows: 0..<3, into: split, metal: metal)
            _ = try await BlendOpEngine.compositeRows(
                below: below, layer: layer, mask: mask, opacity: 0.6,
                blendMode: mode, rows: 3..<h, into: split, metal: metal)
            XCTAssertEqual(
                readPlane(whole, metal: metal),
                readPlane(split, metal: metal),
                "\(mode): row-band split == whole frame (byte-exact)")
        }
    }
}

@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// LensPerCorrectionTests (Plan LENS-02 T1, D-LENS-7) — the enable +
/// per-correction family switches (Alcedo apply_* alignment).
///
/// The gate is a PURE function over the RESOLVED kernel coefficients
/// (after resolve, before uniforms — the manual slider STORAGE is never
/// touched). The nil = TRUE default keeps every pre-L2 document's render
/// byte-identical (the default params JSON zero-drift negative pins the
/// encoding face).
final class LensPerCorrectionTests: XCTestCase {

    /// A fully-resolved coefficient face (all three families non-identity).
    private func resolvedAll() -> LensKernelParams {
        var k = LensKernelParams()
        k.dc1 = 0.01; k.dc2 = 0.02; k.dc3 = 0.03; k.dc4 = 0.04
        k.vr = 1.001; k.cr = 0.0005; k.br = 0.0003
        k.vb = 0.999; k.cb = -0.0004; k.bb = 0.0002
        k.vk1 = -0.5; k.vk2 = 0.3; k.vk3 = -0.1
        return k
    }

    private func toggles(
        enabled: Bool? = nil, dist: Bool? = nil, tca: Bool? = nil, vig: Bool? = nil
    ) -> LensModule.Params {
        var p = LensModule.Params()
        p.enabled = enabled
        p.applyDistortion = dist
        p.applyTCA = tca
        p.applyVignette = vig
        return p
    }

    // MARK: - The default face passes through untouched

    func testAllNilTogglesPassThrough() {
        let k = resolvedAll()
        let out = LensModule.gated(k, params: toggles())
        XCTAssertEqual(out.dc1, k.dc1); XCTAssertEqual(out.dc2, k.dc2)
        XCTAssertEqual(out.vr, k.vr); XCTAssertEqual(out.bb, k.bb)
        XCTAssertEqual(out.vk1, k.vk1); XCTAssertEqual(out.vk3, k.vk3)
    }

    // MARK: - The 2^3 family-gate table (enabled on)

    func testFamilyGateTable() {
        let k = resolvedAll()
        // Each family alone off zeroes ONLY its terms.
        let d = LensModule.gated(k, params: toggles(dist: false))
        XCTAssertEqual(d.dc1, 0); XCTAssertEqual(d.dc4, 0)
        XCTAssertEqual(d.vr, k.vr, "TCA untouched")
        XCTAssertEqual(d.vk1, k.vk1, "vignette untouched")

        let t = LensModule.gated(k, params: toggles(tca: false))
        XCTAssertEqual(t.dc2, k.dc2, "distortion untouched")
        XCTAssertEqual(t.vr, 1); XCTAssertEqual(t.cr, 0); XCTAssertEqual(t.br, 0)
        XCTAssertEqual(t.vb, 1); XCTAssertEqual(t.cb, 0); XCTAssertEqual(t.bb, 0)
        XCTAssertEqual(t.vk1, k.vk1, "vignette untouched")

        let v = LensModule.gated(k, params: toggles(vig: false))
        XCTAssertEqual(v.dc2, k.dc2, "distortion untouched")
        XCTAssertEqual(v.vr, k.vr, "TCA untouched")
        XCTAssertEqual(v.vk1, 0); XCTAssertEqual(v.vk2, 0); XCTAssertEqual(v.vk3, 0)

        // All three off = full identity coefficients.
        let all = LensModule.gated(
            k, params: toggles(dist: false, tca: false, vig: false))
        let identity = LensKernelParams()
        XCTAssertEqual(all.dc1, identity.dc1); XCTAssertEqual(all.dc4, identity.dc4)
        XCTAssertEqual(all.vr, identity.vr); XCTAssertEqual(all.bb, identity.bb)
        XCTAssertEqual(all.vk1, identity.vk1); XCTAssertEqual(all.vk3, identity.vk3)
    }

    // MARK: - The enable arm

    func testEnabledFalseZeroesEverythingRegardlessOfToggles() {
        let k = resolvedAll()
        let out = LensModule.gated(
            k, params: toggles(enabled: false, dist: true, tca: true, vig: true))
        let identity = LensKernelParams()
        XCTAssertEqual(out.dc2, identity.dc2)
        XCTAssertEqual(out.vr, identity.vr)
        XCTAssertEqual(out.vk1, identity.vk1)
    }

    // MARK: - The neutral predicate enable arm

    func testNeutralPredicateReadsEnable() {
        let module = LensModule()
        var p = LensModule.Params(distortionK1: 0.1, vignetteK2: 0.4, source: .manual)
        XCTAssertFalse(module.isNeutral(p), "optically non-neutral by storage")
        p.enabled = false
        XCTAssertTrue(module.isNeutral(p), "enabled off = the neutral face")
        p.enabled = nil
        XCTAssertFalse(module.isNeutral(p))
        // nil enabled (default) keeps the optical-only judgment.
        XCTAssertTrue(module.isNeutral(LensModule.Params()))
    }

    // MARK: - Manual storage untouched (the gate rides resolve only)

    func testGateDoesNotTouchManualStorage() {
        let module = LensModule()
        var p = LensModule.Params(
            distortionK1: 0.05, tcaR: 0.005, vignetteK1: -0.4, source: .manual)
        p.applyDistortion = false
        // The storage face keeps the slider values verbatim…
        XCTAssertEqual(p.distortionK1, 0.05)
        // …the uniforms face carries the gated (zeroed) family.
        var committed = LensModule.Params(
            distortionK1: 0.05, tcaR: 0.005, vignetteK1: -0.4, source: .manual)
        committed.applyDistortion = false
        mirrorCommitted(module, committed)
        let u = module.manualUniforms(bufW: 100, bufH: 100, roiIn: ROI())
        XCTAssertEqual(u.dist.y, 0, "dc2 (k1) gated to zero in the render face")
        XCTAssertEqual(u.vig.x, -0.4, "vignette family untouched by the distortion gate")
    }

    /// LensModule.commitParams is async-free but the committed storage is
    /// private — the tests write it through the internal seam (same-module
    /// mirror of commitParams' `committed = params`).
    private func mirrorCommitted(_ module: LensModule, _ params: LensModule.Params) {
        module.setCommittedForTesting(params)
    }

    // MARK: - The additive zero-drift negative

    func testDefaultParamsEncodeStaysByteIdentical() throws {
        let fresh = try JSONEncoder().encode(LensModule.Params())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: fresh) as? [String: Any])
        XCTAssertNil(object["enabled"])
        XCTAssertNil(object["applyDistortion"])
        XCTAssertNil(object["applyTCA"])
        XCTAssertNil(object["applyVignette"])
        // The legacy (pre-L2) JSON decodes and re-encodes with the new keys
        // absent.
        let legacyJSON = """
        {"distortionK1":0.1,"distortionK2":0,"tcaR":0,"tcaB":0,"vignetteK1":0,\
        "vignetteK2":0,"vignetteK3":0,"source":"manual"}
        """
        let decoded = try JSONDecoder().decode(LensModule.Params.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.enabled)
        XCTAssertNil(decoded.applyVignette)
        XCTAssertEqual(decoded.distortionK1, 0.1)
        XCTAssertEqual(decoded.source, .manual)
    }
}

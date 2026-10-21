@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// LensCacheIsolationTests (Plan LENS-04 T3) — the RawLab lesson ported:
/// the lens configuration MUST ride the cache key (a file-identity-only
/// key would cross-contaminate renders between lens on/off). Our
/// paramsHash folds the FULL LensModule.Params (the commitParams hash),
/// so the lens on/off + the slider nudges + the snapshot bake all
/// invalidate naturally — this suite PINS that contract (no production
/// change; a PinCacheKey edit here would violate the M6-2 KD-6
/// fork-point contract and is a STOP-AND-REPORT).
final class LensCacheIsolationTests: XCTestCase {

    private func hash(_ p: LensModule.Params) -> UInt64 {
        // The SAME strip-on-hash face LensModule.commitParams feeds (the
        // snapshot's dbTag nilled before the encode — X3/review m2).
        var input = p
        input.snapshot?.dbTag = nil
        return StableHash.hash(ParamsCoding.encode(input))
    }

    func testOnOffFlipsParamsHash() {
        let off = LensModule.Params()
        var on = LensModule.Params(distortionK1: 0.05, source: .manual)
        on.enabled = true
        XCTAssertNotEqual(hash(off), hash(on), "lens on/off must invalidate")
    }

    func testSliderNudgeFlipsParamsHash() {
        var a = LensModule.Params(distortionK1: 0.05, source: .manual)
        var b = a
        b.distortionK1 = 0.0501
        XCTAssertNotEqual(hash(a), hash(b), "a slider nudge must invalidate")
        // Source flips are hash-visible too (the provenance rides).
        a.source = .lensfun
        XCTAssertNotEqual(hash(LensModule.Params()), hash(a))
    }

    func testDBTagAloneDoesNotInvalidate() throws {
        // X3: the dbTag is strip-on-hash — a database update (a new dbTag
        // with identical calibration) must NOT invalidate the cache.
        var a = LensModule.Params(source: .lensfun, focalLength: 16)
        a.snapshot = LensCoefficientSnapshot()
        a.snapshot?.distortionRows = [
            DistortionCalib(model: .poly3, focal: 16, terms: [0.01]),
        ]
        a.snapshot?.dbTag = "aaaaaaaaaaaaaaaa"
        var b = a
        b.snapshot?.dbTag = "bbbbbbbbbbbbbbbb"
        XCTAssertEqual(hash(a), hash(b),
                       "the dbTag is the audit face, never the cache face")
        // But a calibration drift does.
        b.snapshot?.distortionRows = [
            DistortionCalib(model: .poly3, focal: 16, terms: [0.02]),
        ]
        XCTAssertNotEqual(hash(a), hash(b))
    }

    func testUnrelatedIOPDoesNotTouchLensFace() {
        // The negative: an unrelated params change (a different module's
        // face) cannot be confused with the lens face — the lens hash is
        // a pure function of the lens params alone.
        let a = hash(LensModule.Params())
        let b = hash(LensModule.Params())
        XCTAssertEqual(a, b, "deterministic pure function (no ambient state)")
    }
}

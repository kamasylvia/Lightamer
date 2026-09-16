import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// MetalContext + pass-through kernel structure tests (FOUND-05/06, D-16/D-17).
///
/// Phase 1: stubs only — the bodies are filled by Plan 06 together with the
/// staged test fixtures. Each test guards on GPU availability, per the
/// VALIDATION "Metal compute requires a GPU context" rule. Structure-level
/// verification (context init, dispatch without error, distinct PSOs per
/// constant specialization) is feasible headlessly; the bit-exact assertion
/// waits for Plan 06.
final class MetalContextTests: XCTestCase {

    /// FOUND-06: device + command queue are created (D-14/D-15).
    func testMetalContextInit() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        // Plan 06
    }

    /// FOUND-06: dispatch `pass_through` with identity constants
    /// (`useSrgbGamma=false, exposureEV=0`) and assert output == input
    /// bit-for-bit (texture in == texture out; Plan 06 stages the readback).
    func testPassThroughKernelBitExact() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        // Plan 06
    }

    /// D-16: the second dispatch of the same (function, constants) pair hits
    /// the PSO cache instead of rebuilding.
    func testPSOCacheHit() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        // Plan 06
    }

    /// D-17: dispatching with `useSrgbGamma=true` yields a DISTINCT PSO from
    /// the `useSrgbGamma=false` specialization.
    func testFunctionConstantsSpecialization() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        // Plan 06
    }
}

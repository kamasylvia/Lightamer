import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// FOUND-03 structure tests: the `IOPModule` contract and its reference
/// conformance (`PassthroughModule`).
///
/// Phase 1: stubs — bodies are filled by Plan 06 together with the staged
/// fixtures. Each GPU-dependent test guards on device availability per the
/// VALIDATION "Metal compute requires a GPU context" rule.
final class IOPModuleTests: XCTestCase {

    /// FOUND-03: `PassthroughModule` conforms to `IOPModule` with the
    /// locked static surface (`opName`, `iopOrder` in the V50Order range,
    /// `flags`, `defaultColorspace`).
    func testPassthroughModuleConforms() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        // Plan 06
    }

    /// FOUND-03: `PassthroughModule.Params` is `Codable` (JSON round-trip)
    /// and `Hashable` (equal params hash equal — the Phase 2 cache key).
    func testPassthroughParamsCodableAndHashable() {
        // Plan 06
    }

    /// FOUND-03 + success criterion #3: `process` on known buffer contents
    /// is a true no-op (output == input, float32 RGBA bit-exact).
    func testPassthroughProcessIsNoOp() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        // Plan 06
    }
}

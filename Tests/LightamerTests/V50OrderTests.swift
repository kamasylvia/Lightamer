import LightamerCore
import XCTest

/// FOUND-03 structure tests for the `V50Order` table (the verbatim port of
/// Darktable `iop_order.c:298-415`).
///
/// Phase 1: stubs — bodies are filled by Plan 06. Note: the table ports to
/// 93 entries (the plan's ~76 estimate undercounted; the verbatim source
/// wins — see 01-04-SUMMARY), so `testEntriesCountApproximately76` asserts
/// the source count when Plan 06 fills it.
final class V50OrderTests: XCTestCase {

    /// The table matches Darktable's v50_order: 93 entries, positions
    /// 1.0 (rawprepare) → 78.0 (gamma).
    func testEntriesCountApproximately76() {
        // Plan 06
    }

    /// No duplicate opName anywhere; the ONLY position collision is the
    /// deliberate 28.5 cluster (channelmixerrgb/diffuse/censorize/
    /// negadoctor/blurs/primaries — six entries sharing 28.5).
    func testNoDuplicateOpNameExceptDeliberateCollisions() {
        // Plan 06
    }

    /// Canonical milestone lookups: rawprepare 1.0, demosaic 8.0,
    /// exposure 21.0, colorin 28.0, colorout 70.0, gamma 78.0; unknown
    /// opNames return nil.
    func testOrderForKnownModules() {
        // Plan 06
    }
}

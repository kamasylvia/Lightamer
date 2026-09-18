import LightamerCore
import XCTest

/// FOUND-03 structure tests for the `V50Order` table (the verbatim port of
/// Darktable `iop_order.c:298-415`).
///
/// Note: the table ports to **93 entries** — the plan's "~76" estimate
/// undercounted; the verbatim source wins (recorded in 01-04-SUMMARY and
/// the executor protocol), so the count test asserts the source count.
final class V50OrderTests: XCTestCase {

    /// The table matches Darktable's v50_order: 93 entries spanning
    /// rawprepare 1.0 → gamma 78.0, first/last locked.
    func testEntriesCountApproximately76() {
        XCTAssertEqual(V50Order.entries.count, 93, "verbatim iop_order.c port = 93 entries")
        XCTAssertEqual(V50Order.entries.first?.opName, "rawprepare")
        XCTAssertEqual(V50Order.entries.first?.order, 1.0)
        XCTAssertEqual(V50Order.entries.last?.opName, "gamma")
        XCTAssertEqual(V50Order.entries.last?.order, 78.0)
    }

    /// No duplicate opName anywhere (lookups are by name); the ONLY position
    /// collision is the deliberate 28.5 cluster — channelmixerrgb / diffuse
    /// / censorize / negadoctor / blurs / primaries share 28.5, and no other
    /// order value repeats.
    func testNoDuplicateOpNameExceptDeliberateCollisions() {
        let names = V50Order.entries.map(\.opName)
        XCTAssertEqual(Set(names).count, names.count, "every opName unique")

        let clustered = ["channelmixerrgb", "diffuse", "censorize", "negadoctor", "blurs", "primaries"]
        for name in clustered {
            XCTAssertEqual(V50Order.order(for: name), 28.5, "\(name) sits in the 28.5 cluster")
        }

        let orderCounts = Dictionary(grouping: V50Order.entries, by: \.order)
            .filter { $0.value.count > 1 }
        XCTAssertEqual(
            Set(orderCounts.keys), [28.5],
            "28.5 is the only shared position"
        )
        XCTAssertEqual(
            Set(orderCounts[28.5]!.map(\.opName)), Set(clustered),
            "exactly the six documented modules share 28.5"
        )
    }

    /// Canonical milestone lookups + nil for unknown opNames (incl. the
    /// Phase 1 spike module, which deliberately has no V50Order slot).
    func testOrderForKnownModules() {
        XCTAssertEqual(V50Order.order(for: "rawprepare"), 1.0)
        XCTAssertEqual(V50Order.order(for: "demosaic"), 8.0)
        XCTAssertEqual(V50Order.order(for: "exposure"), 21.0)
        XCTAssertEqual(V50Order.order(for: "colorin"), 28.0)
        XCTAssertEqual(V50Order.order(for: "colorout"), 70.0)
        XCTAssertEqual(V50Order.order(for: "gamma"), 78.0)
        XCTAssertNil(V50Order.order(for: "does_not_exist"))
        XCTAssertNil(V50Order.order(for: "passthrough_spike"), "spike module has no slot")
    }
}

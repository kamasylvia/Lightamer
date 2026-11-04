import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// McpFilmTests (spektra-module P1 T6' — APP bundle) — the MCP layer-only
// face: apply_params refuses spektraFilm (upsert AND remove), and the
// paste ledger carries the fifth token for layer-only payloads.
// ─────────────────────────────────────────────────────────────────────────────

final class McpFilmTests: XCTestCase {

    /// The upsert refuses (typed unknownOp — the op is absent from the
    /// MCP face even though the registry resolves it).
    func testApplyParamsRefusesSpektraUpsert() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        do {
            _ = try await EditingToolset.projectInstances(
                current: [], ops: [EditingToolset.ParamOp(
                    opName: SpektraFilmModule.opName, multiPriority: 0,
                    params: nil, enabled: nil, remove: false)],
                modules: registry)
            XCTFail("the spektraFilm upsert must refuse")
        } catch let error as McpToolError {
            guard case .unknownOp = error else {
                return XCTFail("expected unknownOp, got \(error)")
            }
        }
    }

    /// The remove refuses too (no partial face — the op is simply not
    /// addressable here).
    func testApplyParamsRefusesSpektraRemove() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        do {
            _ = try await EditingToolset.projectInstances(
                current: [], ops: [EditingToolset.ParamOp(
                    opName: SpektraFilmModule.opName, multiPriority: 0,
                    params: nil, enabled: nil, remove: true)],
                modules: registry)
            XCTFail("the spektraFilm remove must refuse")
        } catch let error as McpToolError {
            guard case .unknownOp = error else {
                return XCTFail("expected unknownOp, got \(error)")
            }
        }
    }

    /// An ordinary op still flows (the refusal is opName-exact).
    func testOrdinaryOpsStillFlow() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let projected = try await EditingToolset.projectInstances(
            current: [], ops: [EditingToolset.ParamOp(
                opName: ExposureModule.opName, multiPriority: 0,
                params: nil, enabled: nil, remove: false)],
            modules: registry)
        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected[0].opName, ExposureModule.opName)
    }
}

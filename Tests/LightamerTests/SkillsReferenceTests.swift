import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// SkillsReferenceTests (Plan M7-6-01 T4, SKILLS-01 — APP domain) — the agent
// skill docs' machine gate (OQ-M7-6-3 "the test IS the gate"):
//
//   1. `references/tools.md` is byte-compared against the LIVE registry —
//      the internal renderer assembles the union registry (the M7-5 wave's
//      union-right exercise promoted `McpFinalSnapshotTests.makeUnionRegistry`
//      to internal) plus the five per-domain registries for the domain
//      membership, renders the markdown, and any registration drift turns
//      the suite red. Zero script maintenance face.
//   2. `references/errors.md` must name all 19 closed-table codes (the
//      hard-coded loop — an error-code addition/removal turns it red).
//
// The bootstrap channel for tools.md: the internal renderer was run once
// through a temporary scaffolding test against the repo path (the writing
// test was removed before commit — the golden file is the artifact, the
// compare test is the gate; declared in M7-6-01 DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

final class SkillsReferenceTests: XCTestCase {

    /// The repo-root anchor (the AgentControlCoordinatorTests repoRoot form).
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LightamerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private var toolsReferenceURL: URL {
        Self.repoRoot()
            .appendingPathComponent("skills/lightamer-mcp/references/tools.md")
    }

    // MARK: - The renderer (internal static — the bootstrap channel's face)

    /// The five domain memberships from LIVE registries (never a duplicated
    /// list — a domain move flips the reference and the gate together).
    internal static func domainMembership() async -> [(domain: String, names: [String])] {
        let editing = await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }))
        let culling = await McpServerController.makeRegistry(
            culling: McpServerController.makeCullingContext(session: { nil }))
        let searchState = await McpServerController.makeRegistry(
            searchState: McpSearchStateContext())
        let project = await McpServerController.makeRegistry(
            project: McpProjectContext())
        let control = await McpServerController.makeRegistry(
            control: McpControlContext())
        return [
            ("editing", await editing.descriptors().map(\.name)),
            ("culling", await culling.descriptors().map(\.name)),
            ("searchstate", await searchState.descriptors().map(\.name)),
            ("project", await project.descriptors().map(\.name)),
            ("control", await control.descriptors().map(\.name)),
        ]
    }

    /// The live registry → the tools.md markdown. Deterministic: the
    /// descriptors ride the registry's stable name-sorted order and the
    /// domain sections the fixed enumeration above.
    internal static func renderToolsReference() async -> String {
        let union = await McpFinalSnapshotTests().makeUnionRegistry()
        let descriptors = await union.descriptors()
        let domains = await domainMembership()
        let byName = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0) })

        var out = """
        # Tools reference

        GENERATED FILE — `SkillsReferenceTests.renderToolsReference()` renders
        the live registry and byte-compares this file on every suite run
        (OQ-M7-6-3: the test IS the gate). Edit the toolset sources, not this
        file; a registration change lands here through the snapshot tests.

        \(descriptors.count) tools across five domains
        \(domains.map { "\($0.domain) (\($0.names.count))" }.joined(separator: " / ")).
        Hints mirror the `tools/list` annotation columns (`readOnlyHint`,
        `destructiveHint`); the schema is the verbatim `inputSchema` JSON
        (its per-field descriptions are the English argument semantics).
        The registry's tool-level descriptions are zh-catalog text (the
        zh localization family) — they stay OUT of this reference: the
        skill docs are en-only by decision (OQ-M7-6-2), and the domain
        boundaries in SKILL.md §3 carry the English semantics.

        """
        for (domain, names) in domains {
            out += "\n## \(domain) (\(names.count) tools)\n"
            for name in names.sorted() {
                guard let d = byName[name] else {
                    continue  // unreachable: the union covers every domain face
                }
                let readOnly = d.readOnlyHint == true
                let destructive = d.destructiveHint == true
                out += "\n### \(name)\n\n"
                out += "- readOnlyHint: \(readOnly)\n"
                out += "- destructiveHint: \(destructive)\n\n"
                out += "Schema (verbatim):\n\n"
                out += "```json\n\(d.inputSchemaJSON)\n```\n"
            }
        }
        return out
    }

    // MARK: - The gates

    /// Gate 1: the live-registry render vs the on-disk reference, BYTE for
    /// BYTE — registration drift turns the suite red.
    func testToolsReferenceMatchesTheLiveRegistryByteForByte() async throws {
        let rendered = await Self.renderToolsReference()
        let onDisk = try String(
            contentsOf: toolsReferenceURL, encoding: .utf8)
        XCTAssertEqual(rendered, onDisk,
                       "the tools reference is generated — edit the toolsets, "
                           + "then re-render the reference")
    }

    /// Gate 2: every code of the closed 19-error table is named in
    /// errors.md (the hard-coded loop — an addition/removal turns it red).
    func testErrorsReferenceNamesAllNineteenCodes() throws {
        let allCodes = [
            "unknownOp", "invalidParams", "imageLiveInEditor",
            "notSessionMember", "serverReadOnly", "renderFailed",
            "renderTimeout", "exportFailed", "invalidFilter",
            "roiOutOfBounds", "keywordContainsSeparator",
            "exportPresetNotApplicable", "unknownPreset", "projectReadOnly",
            "internalError", "modelUnavailable", "controlNotHeld",
            "controlRevokedByUser", "controlBusy",
        ]
        XCTAssertEqual(allCodes.count, 19, "the closed table is 19 codes")
        let onDisk = try String(
            contentsOf: Self.repoRoot()
                .appendingPathComponent("skills/lightamer-mcp/references/errors.md"),
            encoding: .utf8)
        for code in allCodes {
            XCTAssertTrue(
                onDisk.contains(code),
                "errors.md must name the code \(code)")
        }
    }
}

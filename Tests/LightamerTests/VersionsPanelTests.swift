import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// VersionsPanelTests (Plan M2-8-2 T1, KD-1; AC#1 — APP bundle, the
// VersionSwapTests real-chain precedent) — the Versions panel's UI-state face
// over a REAL EditorState + VersionCoordinator chain (checker E1: no
// backdoors — every command rides the same coordinator entries the panel
// buttons call; the static view faces (markers / badge / default-name) are
// the pure seams the rows render from):
//
//   1. EMPTY STATE: a fresh coordinator IS the implicit single version —
//      no rows, no badge, and the default-name face starts at index 1
//      (「版本 2」 for the first created version).
//   2. CREATE: the row list (materialized v1 + the created row), the
//      ACTIVE badge follows `activeVersionID`, updatedAt stamps.
//   3. RENAME: the inline-commit face — trims, refuses whitespace-only.
//   4. REMOVE FLOW: removing the ACTIVE row activates the list's FIRST;
//      removing the LAST row returns to the empty state (the guidance
//      copy's precondition).
//   5. ROW TAP = switch: the tapped row becomes active and its chain is
//      the live history (the byte-fidelity ride is VersionSwapTests').
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class VersionsPanelTests: XCTestCase {

    /// The default-name faces resolve through the CATALOG — the host locale
    /// picks zh (「版本 N」) or en ("Version N"). The tests mirror the
    /// production keys (the T1 KD-1 registration) instead of pinning one
    /// locale's literal.
    private static func panelDefaultName(_ ordinal: Int) -> String {
        String(localized: "versions_panel_default", defaultValue: "Version \(ordinal)")
    }

    private static var implicitMaterializedName: String {
        String(localized: "versions_default_name", defaultValue: "Version 1")
    }

    // MARK: - Assembly (the P1 swap-tests production-minus-window shape)

    private func makeCoordinator() -> (EditorState, VersionCoordinator) {
        let editorState = EditorState()
        let versions = VersionCoordinator()
        versions.attach(
            editorState: editorState, pipeCoordinator: PipeCoordinator())
        return (editorState, versions)
    }

    /// One committed exposure edit (the discrete commit face).
    private func commitEdit(_ editorState: EditorState, ev: Float, label: String) {
        var params = ExposureModule.Params()
        params.exposure = ev
        editorState.recordChange(
            ModuleInstance(module: ExposureModule.self, params: params), label: label)
    }

    // MARK: - 1: the empty state (the implicit single version)

    func testEmptyStateIsTheImplicitSingleVersion() {
        let (_, versions) = makeCoordinator()

        // No rows, no active id — the guidance copy's state.
        XCTAssertTrue(versions.slots.isEmpty)
        XCTAssertNil(versions.activeVersionID)
        XCTAssertFalse(versions.hasVersionStructure)

        // No badge anywhere: `isActive` is false for every UUID because
        // the active id is nil (the implicit semantics — P1 KD-2).
        XCTAssertFalse(
            VersionsPanelView.isActive(
                VersionSlot(
                    id: UUID(), name: "x", createdAt: Date(), updatedAt: Date(),
                    chain: nil),
                activeID: nil))

        // The default-name face: the FIRST created version is index 1 →
        // 「版本 2」 (the materialized implicit slot takes index 0).
        XCTAssertEqual(
            VersionsPanelView.defaultVersionName(slotsCount: 0),
            Self.panelDefaultName(2))
        XCTAssertEqual(
            VersionsPanelView.defaultVersionName(slotsCount: 1),
            Self.panelDefaultName(2))
        XCTAssertEqual(
            VersionsPanelView.defaultVersionName(slotsCount: 2),
            Self.panelDefaultName(3))

        // The stable marker faces (the E2/registration contract).
        let id = UUID()
        XCTAssertEqual(VersionsPanelView.panelMarker, "editor.versions.panel")
        XCTAssertEqual(
            VersionsPanelView.rowMarker(id: id), "editor.versions.row.\(id.uuidString)")
        XCTAssertEqual(
            VersionsPanelView.renameButtonMarker(id: id),
            "editor.versions.rename.\(id.uuidString)")
        XCTAssertEqual(
            VersionsPanelView.removeButtonMarker(id: id),
            "editor.versions.remove.\(id.uuidString)")
    }

    // MARK: - 2: create → rows + badge + updatedAt

    func testCreateLandsRowsBadgeAndUpdatedAt() throws {
        let (editorState, versions) = makeCoordinator()
        commitEdit(editorState, ev: 0.5, label: "e1")

        let before = Date()
        versions.createFromScratch(
            name: VersionsPanelView.defaultVersionName(slotsCount: 0))

        // Two rows: the materialized implicit 「版本 1」 + the created one
        // (the panel's default name face passed the name in — KD-1).
        XCTAssertEqual(versions.slots.count, 2)
        XCTAssertEqual(versions.slots[0].name, Self.implicitMaterializedName)
        XCTAssertEqual(versions.slots[1].name, Self.panelDefaultName(2))

        // The BADGE sits on the created row (create-ACTIVATE).
        XCTAssertEqual(versions.activeVersionID, versions.slots[1].id)
        XCTAssertTrue(
            VersionsPanelView.isActive(
                versions.slots[1], activeID: versions.activeVersionID))
        XCTAssertFalse(
            VersionsPanelView.isActive(
                versions.slots[0], activeID: versions.activeVersionID))

        // updatedAt stamps at the command instant.
        for slot in versions.slots {
            XCTAssertGreaterThanOrEqual(slot.updatedAt, before.addingTimeInterval(-1))
        }
        // The created version's slot holds NO chain copy (nil = ACTIVE —
        // its (empty) chain IS the live history), pristine-of-chain.
        XCTAssertNil(versions.slots[1].chain)
        XCTAssertTrue(editorState.history.items.isEmpty)
    }

    // MARK: - 3: the inline-rename commit face

    func testRenameTrimsAndRefusesBlank() throws {
        let (editorState, versions) = makeCoordinator()
        commitEdit(editorState, ev: 0.5, label: "e1")
        versions.createFromScratch(name: "v2")
        let id = try XCTUnwrap(versions.slots[0].id)

        // The rename command trims (the panel's inline commit).
        versions.rename(id, to: "  暖调  ")
        XCTAssertEqual(versions.slots[0].name, "暖调")

        // A whitespace-only draft is refused (the row keeps its name).
        versions.rename(id, to: "   ")
        XCTAssertEqual(versions.slots[0].name, "暖调")
    }

    // MARK: - 4: the remove flow (confirm-dialog payload semantics)

    func testRemoveActiveActivatesFirstThenLastRemovalReturnsEmptyState() throws {
        let (editorState, versions) = makeCoordinator()
        commitEdit(editorState, ev: 0.5, label: "e1")
        versions.createFromScratch(name: "v2")
        versions.createFromScratch(name: "v3")
        XCTAssertEqual(versions.slots.count, 3)
        XCTAssertEqual(versions.activeVersionID, versions.slots[2].id)

        // Removing the ACTIVE row (the dialog's destructive button face)
        // activates the list's FIRST row.
        versions.remove(try XCTUnwrap(versions.slots[2].id))
        XCTAssertEqual(versions.activeVersionID, versions.slots[0].id)
        XCTAssertEqual(editorState.history.items.map(\.label), ["e1"])

        // Removing the LAST row returns to the empty state (guidance copy
        // resurfaces); the current chain is kept.
        versions.remove(try XCTUnwrap(versions.slots[1].id))
        versions.remove(try XCTUnwrap(versions.slots[0].id))
        XCTAssertTrue(versions.slots.isEmpty)
        XCTAssertNil(versions.activeVersionID)
        XCTAssertEqual(editorState.history.items.map(\.label), ["e1"])
    }

    // MARK: - 5: row tap = switch

    func testRowTapSwitchesTheActiveChain() throws {
        let (editorState, versions) = makeCoordinator()
        commitEdit(editorState, ev: 0.5, label: "e1")
        commitEdit(editorState, ev: 1.0, label: "e2")
        versions.branchFromCurrent(name: "branch")
        commitEdit(editorState, ev: -2.0, label: "branch-edit")

        // Tap the FIRST row (v1): it becomes active, its chain returns.
        versions.switchTo(try XCTUnwrap(versions.slots[0].id))
        XCTAssertEqual(versions.activeVersionID, versions.slots[0].id)
        XCTAssertEqual(editorState.history.items.map(\.label), ["e1", "e2"])
        XCTAssertTrue(
            VersionsPanelView.isActive(
                versions.slots[0], activeID: versions.activeVersionID))

        // Tap the second row again: the branch chain returns (its tail edit
        // included — the jump point rides the chain, the redo tail stays).
        versions.switchTo(try XCTUnwrap(versions.slots[1].id))
        XCTAssertEqual(
            editorState.history.items.map(\.label), ["e1", "e2", "branch-edit"])
    }
}

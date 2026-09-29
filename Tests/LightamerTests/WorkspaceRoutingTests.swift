import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// WorkspaceRoutingTests (Plan M2-3-1 T2, AC #2/#3) — the two-workspace
// routing contract:
//
//   • the library → editor → library round trip restores the ENTIRE library
//     face FIELD FOR FIELD (filter rules / lexical plan / sort / selection /
//     page anchor / scroll position / inspector selection — the D2 red line)
//   • the editor face survives the round trip (re-entry without a new image
//     id reopens the last image)
//   • AppPhase switches are exhaustive with no `default` (a compile-time
//     proof helper pins the spelling; `git grep "case .editor"` is the
//     machine evidence on the production side)
//   • the gate=false host renders the shell + project-workspace markers;
//     the gate=true legacy marker set stays frozen (the existing
//     LibraryLegacyGateTests pin the same sets — untouched, both green)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class WorkspaceRoutingTests: XCTestCase {

    // MARK: - Fixtures

    /// A DISTINCT library face: every field non-default so a restoration bug
    /// cannot hide behind an accidental default match.
    private func makeDistinctLibraryState() -> LibraryPhaseState {
        LibraryPhaseState(
            filter: ExifSearchFilter(
                group: FilterPredicateGroup(
                    match: .all,
                    rules: [
                        FilterPredicateGroup.Rule(
                            field: .rating, op: .gte, value: .int(3)),
                        FilterPredicateGroup.Rule(
                            field: .colorLabel, op: .eq, value: .int(2)),
                    ]),
                plan: ExifSearchPlan(
                    ftsTerms: ["sony", "fe2470"],
                    structured: [
                        StructuredTerm(field: .iso, constraint: .equals(800)),
                    ],
                    dateRange: Date(timeIntervalSince1970: 1_717_224_000)
                        ... Date(timeIntervalSince1970: 1_717_400_400))),
            sort: FilterSort(key: .captureDate, ascending: false),
            selectedIDs: [3, 7, 11],
            pageAnchor: LibraryPageAnchor(
                keyValue: .double(1_717_310_400), imagePath: "Media/06.arw"),
            scrollPosition: WorkspaceScrollPosition(
                anchorImageID: 9, rowOffset: 42.5),
            inspectorSelection: .labels)
    }

    // MARK: - The D2 red line: lossless round trip, field for field

    func testRoundTripRestoresEveryLibraryField() {
        let workspace = WorkspaceModel()
        let original = makeDistinctLibraryState()
        workspace.updateLibraryState { $0 = original }

        workspace.openEditor(imageID: 42)
        XCTAssertEqual(workspace.phase, .editor)

        workspace.closeEditor()
        XCTAssertEqual(workspace.phase, .library)

        let restored = workspace.libraryState
        // filter — group rules field-by-field
        XCTAssertEqual(
            restored.filter.group.rules.count,
            original.filter.group.rules.count)
        XCTAssertEqual(
            restored.filter.group.rules.first?.field, .rating)
        XCTAssertEqual(restored.filter.group.rules.first?.op, .gte)
        XCTAssertEqual(restored.filter.group.rules.first?.value, .int(3))
        XCTAssertEqual(
            restored.filter.group.rules.last?.field, .colorLabel)
        // filter — the lexical plan's three segments
        XCTAssertEqual(
            restored.filter.plan.ftsTerms, original.filter.plan.ftsTerms)
        XCTAssertEqual(
            restored.filter.plan.structured.first?.field, .iso)
        XCTAssertEqual(
            restored.filter.plan.structured.first?.constraint,
            .equals(800))
        XCTAssertEqual(
            restored.filter.plan.dateRange, original.filter.plan.dateRange)
        // sort
        XCTAssertEqual(restored.sort.key, .captureDate)
        XCTAssertFalse(restored.sort.ascending)
        // selection
        XCTAssertEqual(restored.selectedIDs, Set([3, 7, 11]))
        // page anchor (key value + tiebreaker path)
        XCTAssertEqual(restored.pageAnchor?.keyValue, .double(1_717_310_400))
        XCTAssertEqual(restored.pageAnchor?.imagePath, "Media/06.arw")
        // scroll position (anchor id + row offset)
        XCTAssertEqual(restored.scrollPosition?.anchorImageID, 9)
        XCTAssertEqual(restored.scrollPosition?.rowOffset ?? -1, 42.5)
        // inspector selection
        XCTAssertEqual(restored.inspectorSelection, .labels)
        // and the whole struct equals, not just fieldwise
        XCTAssertEqual(restored, original)
    }

    func testEditorPhaseMutationsWhileInEditorDoNotLeakIntoTheLibraryFace() {
        // The preserve semantics: the library state an editor entry
        // snapshotted is EXACTLY what editor exit restores — library-face
        // writes that happen while the editor is up are discarded (the P2
        // grid cannot even reach them, the library face is not rendered).
        let workspace = WorkspaceModel()
        let original = makeDistinctLibraryState()
        workspace.updateLibraryState { $0 = original }

        workspace.openEditor(imageID: 42)
        workspace.updateLibraryState { state in
            state.selectedIDs = [99]
            state.sort = FilterSort(key: .iso, ascending: true)
        }
        workspace.closeEditor()

        XCTAssertEqual(workspace.libraryState.selectedIDs, Set([3, 7, 11]))
        XCTAssertEqual(workspace.libraryState.sort.key, .captureDate)
    }

    // MARK: - The editor face across the round trip

    func testEditorFaceSurvivesTheRoundTripAndReopensTheLastImage() {
        let workspace = WorkspaceModel()
        workspace.openEditor(imageID: 42)
        XCTAssertEqual(workspace.editorPhase.currentImageID, 42)
        XCTAssertEqual(workspace.editorPhase.filmstripScrollAnchor, 42)

        workspace.closeEditor()
        XCTAssertEqual(workspace.editorPhase.currentImageID, 42)

        // Re-entry WITHOUT an image id reopens the last image (Alcedo).
        workspace.openEditor(imageID: nil)
        XCTAssertEqual(workspace.editorPhase.currentImageID, 42)
        XCTAssertEqual(workspace.phase, .editor)
    }

    func testSwitchPhaseTogglesBothWays() {
        let workspace = WorkspaceModel()
        XCTAssertEqual(workspace.phase, .library)
        workspace.switchPhase()
        XCTAssertEqual(workspace.phase, .editor)
        workspace.switchPhase()
        XCTAssertEqual(workspace.phase, .library)
    }

    // MARK: - The exhaustive-switch proof (no `default` anywhere)

    /// The compile-time proof: this switch compiles ONLY because every
    /// AppPhase case is answered — adding a case breaks THIS file first.
    private func phaseLabel(_ phase: AppPhase) -> String {
        switch phase {
        case .library: "library"
        case .editor: "editor"
        }
    }

    func testAppPhaseSwitchIsExhaustiveWithoutDefault() {
        XCTAssertEqual(phaseLabel(.library), "library")
        XCTAssertEqual(phaseLabel(.editor), "editor")
    }

    // MARK: - The gate markers (AC #3)

    func testGateFalseHostRendersShellAndProjectWorkspaceMarkers() {
        XCTAssertEqual(
            WorkspaceHostView.faceMarkers(),
            [
                ThemeTokens.Markers.workspaceHost,
                ThemeTokens.Markers.projectWorkspace,
            ])
        XCTAssertEqual(ThemeTokens.Markers.workspaceHost, "shell.workspace.host")
        XCTAssertEqual(ThemeTokens.Markers.projectWorkspace, "library.project.workspace")
    }

    func testContentViewGateFalseMarkerFaceIsUnchangedByTheHost() {
        // The frozen pure-function face on ContentView (the M2-2-4 layer-2
        // mirror) keeps answering the project-workspace marker ONLY for
        // gate=false — the host marker is the HOST's own surface (the
        // LibraryLegacyGateTests pin this same set, untouched).
        XCTAssertEqual(
            ContentView.visibleContentFaceMarkers(legacyLibraryEnabled: false),
            ["library.project.workspace"])
    }

    func testContentViewGateTrueLegacyMarkersStayFrozen() {
        // The frozen M2-2-era set (re-pinned here as a second guard; the
        // canonical pin lives in the untouched LibraryLegacyGateTests).
        XCTAssertEqual(
            ContentView.visibleContentFaceMarkers(legacyLibraryEnabled: true),
            [
                "browser.mode.grid",
                "browser.mode.single",
                "browser.mode.culling",
                "toolbar.import",
                "toolbar.export",
                "browser.grid",
                "catalog.grid",
                "Inspector",
            ])
        // The two faces are disjoint across the gate.
        let gateOn = ContentView.visibleContentFaceMarkers(legacyLibraryEnabled: true)
        let gateOff = ContentView.visibleContentFaceMarkers(legacyLibraryEnabled: false)
        XCTAssertTrue(gateOn.isDisjoint(with: gateOff))
    }

    // MARK: - The menu IA matrix (Plan M2-3-1 T5, AC #7 — gate × phase,
    // every id asserted)

    func testMenuIAMatrixAcrossEveryGatePhaseCombination() {
        for phase in [AppPhase.library, .editor] {
            let gateOn = MenuCommandSet.visibleCommandIDs(gate: true, phase: phase)
            let gateOff = MenuCommandSet.visibleCommandIDs(gate: false, phase: phase)

            // gate=true = the M1 behavior baseline: the Session dead routes
            // stand EXACTLY, nothing of the new IA leaks in.
            XCTAssertEqual(gateOn, MenuCommandSet.sessionRoutes)
            for id in MenuCommandID.allCases {
                XCTAssertEqual(
                    gateOn.contains(id), MenuCommandSet.sessionRoutes.contains(id),
                    "\(id.rawValue) misplaces on the legacy channel (phase \(phase))")
            }

            // gate=false = the new shell: the Session dead routes are
            // REMOVED (the M2LIB-06 cleanup), the project/workspace/search/
            // view family stands, phase-independent.
            XCTAssertEqual(gateOff, MenuCommandSet.newShellRoutes)
            for route in MenuCommandSet.sessionRoutes {
                XCTAssertFalse(
                    gateOff.contains(route),
                    "\(route.rawValue) must be gone from the new shell (phase \(phase))")
            }
            for id in MenuCommandID.allCases {
                XCTAssertEqual(
                    gateOff.contains(id), MenuCommandSet.newShellRoutes.contains(id),
                    "\(id.rawValue) misplaces on the new shell (phase \(phase))")
            }
        }
    }

    func testSessionAndNewShellRegistriesAreDisjoint() {
        XCTAssertTrue(
            MenuCommandSet.sessionRoutes.isDisjoint(with: MenuCommandSet.newShellRoutes),
            "a command cannot belong to both IA families")
        // Every registered id falls in exactly one family.
        let union = MenuCommandSet.sessionRoutes.union(MenuCommandSet.newShellRoutes)
        XCTAssertEqual(union, Set(MenuCommandID.allCases))
    }

    func testWorkspaceCircuitIDsCarryTheKD6KeySemantics() {
        // The D11 table's command identity: ⌘E enters the editor, ⌘W closes
        // the image back to the library, ⌘F opens the search (the ids pin
        // the registry spellings the LightamerApp mapping quotes).
        XCTAssertEqual(MenuCommandID.workspaceEnterEditor.rawValue, "workspace.enterEditor")
        XCTAssertEqual(MenuCommandID.workspaceBackToLibrary.rawValue, "workspace.backToLibrary")
        XCTAssertEqual(MenuCommandID.librarySearch.rawValue, "library.search")
        XCTAssertEqual(MenuCommandID.sessionNew.rawValue, "session.new")
        XCTAssertEqual(MenuCommandID.sessionOpen.rawValue, "session.open")
        XCTAssertEqual(MenuCommandID.sessionClose.rawValue, "session.close")
        XCTAssertEqual(MenuCommandID.sessionImport.rawValue, "session.import")
    }
}

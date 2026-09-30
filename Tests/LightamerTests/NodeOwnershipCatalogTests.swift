@testable import Lightamer
import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// NodeOwnershipCatalogTests (Plan M2-4-1 T3, AC4/AC5) — the ownership face:
//
//   1. COMPLETENESS: the default-face registry set (terminal trio +
//      editingDefaultInstances(defaultFace: true)) is fully classified
//      with the non-grade members EXACTLY the pinned 13 (9 develop + the
//      DRT/Post four) — a catalog drift in either direction is red.
//   2. THE CATALOG TABLES equal the pinned constant lists (the table IS
//      the review surface — widening it forces this test to answer).
//   3. THE FOUR DRT/Post seats named one by one (+ the develop family,
//      including the disabled six and the two non-UI ops — classified
//      beyond the default face).
//   4. THE VALIDATE MATRIX: grade-interior refusals + unrestricted
//      endpoints (exhaustive over the 3×3 owner/target space).
//   5. THE APP SEAM: addModuleToLayer intercepts an owned op with the
//      toast face (no crash, no chain movement) while a grade-owned op
//      still lands (EditorState instance — checker E2 → LightamerTestsApp).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class NodeOwnershipCatalogTests: XCTestCase {

    // MARK: - The pinned sets (constants only — no string literals here)

    /// The DRT/Post four (the Alcedo Detail panel family).
    private static let pinnedDRTPost: Set<String> = [
        SharpenModule.opName,
        GrainModule.opName,
        BloomModule.opName,
        EqualizerModule.opName,
    ]

    /// The develop family (17): camera WB + geometry five + yiyin three +
    /// the disabled six + the two non-UI ops.
    private static let pinnedDevelop: Set<String> = [
        TemperatureModule.opName,
        LensModule.opName,
        AshiftModule.opName,
        FlipModule.opName,
        CropModule.opName,
        LiquifyModule.opName,
        BordersModule.opName,
        WatermarkModule.opName,
        TextOverlayModule.opName,
        FilmicRGBModule.opName,
        SigmoidModule.opName,
        AgXModule.opName,
        DenoiseProfileModule.opName,
        NLMeansModule.opName,
        BilateralModule.opName,
        PassthroughModule.opName,
        TestGainModule.opName,
    ]

    /// The default-face registry set: the terminal trio + the editing
    /// seed (defaultFace: true = the M2-1 narrowed production face).
    private func defaultFaceRegistryOps() async throws -> Set<String> {
        let registry = ModuleRegistry.makeDefault()
        var face = Set(await registry.makeDefaultInstances().map(\.opName))
        face.formUnion(
            LightamerIOPRegistry.editingDefaultInstances(defaultFace: true).map(\.opName))
        return face
    }

    // MARK: - 1: completeness (registry face ∖ classified = ∅)

    func testDefaultFaceRegistryIsFullyClassifiedWithPinnedNonGradeSet() async throws {
        let face = try await defaultFaceRegistryOps()
        // Totality: every face op resolves to a valid owner.
        for op in face {
            _ = NodeOwnershipCatalog.owner(of: op)
        }
        // The non-grade members of the face are EXACTLY the pinned set:
        // 9 develop (the disabled six are not in the default face) + the
        // DRT/Post four.
        let expectedNonGrade = Self.pinnedDRTPost.union(Self.pinnedDevelop)
            .filter { face.contains($0) }
        let nonGrade = Set(face.filter {
            NodeOwnershipCatalog.owner(of: $0) != .grade
        })
        XCTAssertEqual(
            nonGrade, Set(expectedNonGrade),
            "the face's non-grade classification drifted — pin it or fix the catalog")
        XCTAssertEqual(expectedNonGrade.count, 13)
    }

    // MARK: - 2: the catalog tables equal the pinned lists

    func testCatalogTablesEqualThePinnedSets() {
        XCTAssertEqual(
            Set(NodeOwnershipCatalog.drtPostOpNames), Self.pinnedDRTPost,
            "the drtPost table must be exactly the pinned four")
        XCTAssertEqual(
            Set(NodeOwnershipCatalog.developOpNames), Self.pinnedDevelop,
            "the develop table must be exactly the pinned family")
        // Disjointness: an op owns exactly one seat.
        XCTAssertTrue(
            Self.pinnedDRTPost.isDisjoint(with: Self.pinnedDevelop),
            "the ownership seats are exclusive")
        // Consistency: every table entry answers through its own list.
        for op in NodeOwnershipCatalog.drtPostOpNames {
            XCTAssertEqual(NodeOwnershipCatalog.owner(of: op), .drtPost)
        }
        for op in NodeOwnershipCatalog.developOpNames {
            XCTAssertEqual(NodeOwnershipCatalog.owner(of: op), .develop)
        }
    }

    // MARK: - 3: the named seats

    func testFourDRTPostSeatsAreNamed() {
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: SharpenModule.opName), .drtPost)
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: GrainModule.opName), .drtPost)
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: BloomModule.opName), .drtPost)
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: EqualizerModule.opName), .drtPost)
    }

    func testDevelopFamilyIsNamed() {
        for op in Self.pinnedDevelop.sorted() {
            XCTAssertEqual(
                NodeOwnershipCatalog.owner(of: op), .develop,
                "\(op) is a develop-family op")
        }
    }

    // MARK: - 4: the validate matrix (3×3 owner × target, exhaustive)

    func testValidateMatrix() {
        let owners: [NodeOwnership] = [.develop, .grade, .drtPost]
        let targets: [NodeOwnership] = [.develop, .grade, .drtPost]
        for owner in owners {
            for target in targets {
                let verdict = NodeOwnership.validate(owner: owner, into: target)
                switch target {
                case .develop, .drtPost:
                    XCTAssertNil(verdict, "endpoint targets are unrestricted")
                case .grade:
                    switch owner {
                    case .grade:
                        XCTAssertNil(verdict, "grade-owned ops enter grades")
                    case .develop:
                        XCTAssertEqual(verdict, .gradeRefuses(.develop))
                    case .drtPost:
                        XCTAssertEqual(verdict, .gradeRefuses(.drtPost))
                    }
                }
            }
        }
    }

    // MARK: - 5: the App seam (addModuleToLayer interception)

    /// An EditorState with one committed instance (the placeholder seed)
    /// and one adjustment layer.
    private func makeEditorStateWithLayer() -> (EditorState, UUID) {
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        let layer = editorState.addAdjustmentLayer()
        return (editorState, layer?.id ?? UUID())
    }

    func testAddModuleToLayerInterceptsOwnedOpsWithToast() throws {
        let (editorState, layerID) = makeEditorStateWithLayer()
        let stack = try XCTUnwrap(editorState.layerStack)
        XCTAssertEqual(stack.compositeLayers.count, 1)
        let preHistoryCount = editorState.history.items.count

        // A DRT/Post-owned op (sharpen): refused, no crash, NO history
        // item, the chain untouched, and the toast face raised (never
        // silent — D-M2-4-CONTEXT-8).
        let sharpen = ModuleInstance(
            module: SharpenModule.self, params: SharpenModule.Params())
        let refused = editorState.addModuleToLayer(layerID: layerID, template: sharpen)
        XCTAssertNil(refused, "a drtPost op must not enter a grade")
        XCTAssertNotNil(editorState.toast, "the refusal must toast (never silent)")
        XCTAssertEqual(editorState.history.items.count, preHistoryCount)
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layerID)?.chain.count, 0)

        // A develop-owned op (temperature — the camera WB twin): refused
        // too (the toast re-raises through presentToast's reset).
        let temperature = ModuleInstance(
            module: TemperatureModule.self, params: TemperatureModule.Params())
        XCTAssertNil(
            editorState.addModuleToLayer(layerID: layerID, template: temperature))
        XCTAssertNotNil(editorState.toast)
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layerID)?.chain.count, 0)

        // A grade-owned op (exposure — the seed twin): lands as before
        // (the zero-regression face of the seam). The toast is NOT
        // asserted nil here — the 4s auto-clear timer does not fire inside
        // the test, so the sticky text would be the prior refusal.
        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        let accepted = editorState.addModuleToLayer(layerID: layerID, template: exposure)
        XCTAssertNotNil(accepted, "grade-owned ops keep entering grades")
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layerID)?.chain.count, 1)
        XCTAssertEqual(editorState.history.items.count, preHistoryCount + 1)
    }
}

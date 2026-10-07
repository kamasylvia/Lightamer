import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Node ownership (Plan M2-4-1 T3, KD-3; D-M2-4-CONTEXT-8) — the ownership
// DIMENSION of the 18-catalog model: which pipeline stage owns each iop.
//
// THREE-WAY SPLIT (the dependency-direction constraint): Core cannot import
// LightamerIOP (the DAG is IOP → Core), and the ownership table must be
// built from `<Module>.opName` CONSTANTS (zero string literals — a module
// rename must fail compilation, the M2-1 Registry discipline). So:
//   1. Core (this file): the ownership enum + the pure validate function +
//      the typed error — no op knowledge at all.
//   2. LightamerIOP `NodeOwnershipCatalog`: the op → owner table (constants).
//   3. App `EditorState.addModuleToLayer`: the validation seam (the UI
//      insert face refuses develop/drtPost ops INTO a grade).
//
// GRACE POLICY (D-M2-4-CONTEXT-8, OQ-8-A): only the UI insert face enforces
// ownership in M2-4. Sidecar loading (degrade, never refuse), undo/redo,
// retouch and InsertFromJson restoration are validation-free — they are the
// user's own data. M2-5 activates the strict face when the 18 catalogs
// land; at that point only the TABLE changes, never the seam.
// ─────────────────────────────────────────────────────────────────────────────

/// The pipeline stage that owns an iop (the Alcedo 18-catalog ownership
/// axis — M2NODE-03; exhaustive, no default anywhere).
public enum NodeOwnership: Sendable, Equatable {

    /// The RAW Decode / develop-stage face (camera WB, geometry, the
    /// terminal/yiyin segment, the D1/D2 disabled set, dev-only ops).
    case develop

    /// The Color Grade face (the default — everything tunable inside a
    /// grade node).
    case grade

    /// The DRT/Post face (Alcedo Detail-panel family: Clarity / Sharpen /
    /// Halation / FilmGrain — applied once after the display transform,
    /// never inside a grade).
    case drtPost

    /// The pure validation: may an op with `owner` enter a node of
    /// `target`? nil = allowed; a typed error = refuse. Endpoints and the
    /// develop face are unrestricted targets in M2-4 (the grade is the
    /// only guarded interior — the Alcedo semantic).
    public static func validate(
        owner: NodeOwnership, into target: NodeOwnership
    ) -> NodeOwnershipError? {
        switch target {
        case .develop, .drtPost:
            return nil
        case .grade:
            switch owner {
            case .grade:
                return nil
            case .develop:
                return .gradeRefuses(.develop)
            case .drtPost:
                return .gradeRefuses(.drtPost)
            }
        }
    }
}

/// The typed ownership refusal (the Alcedo `color_grade_node_model.hpp`
/// typed-throw shape; exhaustive).
public enum NodeOwnershipError: Error, Equatable, Sendable {

    /// A develop/drtPost-owned op was offered to a grade node — the grade
    /// refuses (the M2NODE-03 typed error).
    case gradeRefuses(NodeOwnership)
}

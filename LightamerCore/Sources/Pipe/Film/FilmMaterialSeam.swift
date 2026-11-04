import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FilmMaterialSeam (spektra-module P1 T2', D-SM-13) — the material-store
// holder that makes FilmMaterialStore reachable from the IOP module face.
//
// DIRECTION (the FilmStatsSeam precedent, same file-shape discipline):
// Core HOLDS the holder + the resolution value type; the App installs the
// adapter at coordinator-attach time (T4' `attachFilmStore`), the QL appex
// installs its own at Env assembly (T6' D-SM-15②). IOP's SpektraFilmModule
// consumes through this seam — the Core→IOP import direction (D-03) stays
// intact because the seam type lives in Core and the CLOSURES cross.
//
// RESOLVED VALUE: the store lookup's two profiles + the pair hash — the
// module's process step needs exactly this triple (the factory's inputs).
// Uninstalled (pure Core/IOP harnesses) = nil → the module takes the
// blit-identity degrade (AC-T2'-8) — deterministic, silent-free.
// ─────────────────────────────────────────────────────────────────────────────

public enum FilmMaterialSeam {

    /// The resolved material triple (the store lookup's value face).
    public struct ResolvedMaterials: Sendable, Equatable {
        public let film: FilmProfile
        public let paper: FilmProfile
        public let materialPairHash: UInt64

        public init(film: FilmProfile, paper: FilmProfile, materialPairHash: UInt64) {
            self.film = film
            self.paper = paper
            self.materialPairHash = materialPairHash
        }
    }

    /// The installed resolver (App/QL install; tests inject fakes).
    /// nil result = unresolved (unknown stock) → the module's identity face.
    public nonisolated(unsafe) static var resolver:
        @Sendable (_ record: FilmRecord) -> ResolvedMaterials? =
            { _ in nil }
}

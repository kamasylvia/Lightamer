import Foundation
import LightamerCore
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────
// LensDefaultsWiring (B-2, LENS-01 acceptance 2nd) — the reloadDefaults
// production seams.
//
// DEFECT: `IOPModule.reloadDefaults` shipped with ZERO production call
// sites (git archaeology: `git log -S ".reloadDefaults(image" --all` hits
// nothing but tests since the Phase 02 introduction — 17 test call sites,
// no production caller). Every Lensfun write path built on the seam was
// dead in production: the auto-apply toggle flipped a UserDefaults key
// nobody read at runtime, the browser selection matched against EXIF-less
// params (missingFocal → identity + "no lens info" readout), and the
// synchronous coefficient bake (D-L4-1 option A, INSIDE reloadDefaults)
// had no reachable caller — "selection = correction" never held.
//
// The design seams (LENS-02 T2 auto-apply + LENS-01 T5 panel state
// machine + RESEARCH §Mutex):
//   ① EXIF-parse seam (`injectedLensSeed`) — the pristine image-load seed
//     folds the lens record through the REAL reloadDefaults: the EXIF
//     resolve-input snapshot always rides (D6), and the opt-in auto-apply
//     flips source + bakes synchronously in the SAME commit (D-L4-1
//     option A — the bake seam). The hard guards live INSIDE
//     reloadDefaults (autoApply key + embeddedGeometry == .notApplicable
//     only + non-empty lens EXIF); the call site duplicates none — the
//     three-state mutex has ONE source. Affects NEW images only; the
//     sidecar restore branch keeps persisted params verbatim.
//   ② Browser-selection seam (`committedSelection`) — the panel's
//     selection commit folds the resolve-input fields (focal/aperture/
//     maker/model/imageCrop/embeddedGeometry) through the SAME
//     reloadDefaults before the provenance flip, so a selection matches
//     on ANY document (fresh, restored, legacy). source/snapshot are NOT
//     folded — the selection owns them (selectedParams + the rematch
//     face's fresh bake, so a stale prior snapshot never survives a
//     missed re-selection).
// Both helpers are the EXACT functions the production call sites invoke
// (the coordinator load branch and the panel commit body stay thin I/O
// shells — the makeRunAssembly assembly-as-pure-function paradigm).
// ─────────────────────────────────────────────────────────────────────────

enum LensDefaultsWiring {

    /// Seam ① — the pristine-load seed with the lens record folded through
    /// `LensModule.reloadDefaults`. Identity-preserving (same UUID /
    /// multiPriority / iopOrder — `setParams` re-encodes + re-hashes the
    /// params payload only). A seed without a lens record returns
    /// verbatim (the terminal-trio-only chains).
    static func injectedLensSeed(
        into instances: [ModuleInstance], image: DecodedImage
    ) async -> [ModuleInstance] {
        guard let index = instances.firstIndex(where: { $0.opName == LensModule.opName })
        else { return instances }
        let params = await LensModule().reloadDefaults(image: image)
        var out = instances
        // The lens params schema encodes losslessly; on the impossible
        // failure keep the static seed record (typed degrade, no throw).
        try? out[index].setParams(params, as: LensModule.self)
        return out
    }

    /// Seam ② — the browser selection commit: the EXIF resolve-input fold
    /// (through reloadDefaults) + the provenance flip + the FRESH snapshot
    /// bake (the rematch face). nil image (no decode in session) skips the
    /// fold — the selection still lands with whatever inputs the params
    /// carry.
    static func committedSelection(
        base: LensModule.Params,
        candidate: LensProfileCandidate,
        image: DecodedImage?
    ) async -> LensModule.Params {
        var folded = base
        if let image {
            folded = await exifRefreshed(base: base, image: image)
        }
        let selected = LensProfileBrowserModel.selectedParams(base: folded, candidate: candidate)
        return LensfunStore.rematch(selected) ?? LensfunStore.clearSnapshot(selected)
    }

    /// The resolve-input fold for seam ②: the reloadDefaults EXIF snapshot
    /// fields ride into `base`; source / sliders / enable / scale /
    /// projections / snapshot stay the caller's (the selection commit owns
    /// the provenance flip and the bake).
    static func exifRefreshed(
        base: LensModule.Params, image: DecodedImage
    ) async -> LensModule.Params {
        let fresh = await LensModule().reloadDefaults(image: image)
        var out = base
        out.focalLength = fresh.focalLength
        out.aperture = fresh.aperture
        out.cameraMaker = fresh.cameraMaker
        out.cameraModel = fresh.cameraModel
        out.imageCrop = fresh.imageCrop
        out.embeddedGeometry = fresh.embeddedGeometry
        return out
    }
}

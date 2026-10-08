import Foundation

// ─────────────────────────────────────────────────────────────────────────
// SidecarSeedTopUp (fix-batch 2026-10-08, the LUT-page-blank queue line) —
// the restore-time seed top-up.
//
// ROOT CAUSE it addresses: a document's persisted base is a snapshot of the
// editing seed at its FIRST pristine write. `restoreFromSidecar` never
// re-merged the CURRENT seed, so any document whose base predates an op's
// seed membership (lut3d joined at Plan 12-5) restores WITHOUT that op —
// and its routed tab page (EditorTabRoutingTable.panels(for:)) renders zero
// rows and zero panel with NO empty-state: the LUT page was silently blank
// for every pre-12-5 document while rendering fine for pristine ones.
//
// The fix: on restore, seed identity records for the (opName, multiPriority)
// pairs that exist in the CURRENT seed but in NEITHER the persisted base NOR
// the restored history's effective set. The seed records are the SAME
// identity/neutral instances a pristine document would get
// (`LightamerIOPRegistry.editingDefaultInstances` — each row's neutral
// params are the documented cache-neutral form), so the topped-up document
// converges to what a fresh document of the current build would show, with
// zero pixel semantics (the L057-era per-op identity invariants hold).
//
// Pure function — the PipeCoordinator owns the seed and the degrade pass;
// this type only does the pair math (Core-testable, the Sidecar-domain
// test stance).
// ─────────────────────────────────────────────────────────────────────────

public enum SidecarSeedTopUp {

    /// The seed records missing from a restored document: every `seed` entry
    /// whose (opName, multiPriority) pair appears in NEITHER `persisted` NOR
    /// `effective`. Identity is freshly minted (the seed constructor's UUIDs)
    /// — never re-mapped onto existing records (NDE-1: existing identities
    /// are untouched; only ABSENT ops gain records).
    public static func missingSeedInstances(
        persisted: [ModuleInstance],
        effective: [ModuleInstance],
        seed: [ModuleInstance]
    ) -> [ModuleInstance] {
        var known = Set<Pair>()
        known.reserveCapacity(persisted.count + effective.count)
        for record in persisted {
            known.insert(Pair(opName: record.opName, multiPriority: record.multiPriority))
        }
        for record in effective {
            known.insert(Pair(opName: record.opName, multiPriority: record.multiPriority))
        }
        return seed.filter { !known.contains(Pair(opName: $0.opName, multiPriority: $0.multiPriority)) }
    }

    private struct Pair: Hashable {
        let opName: String
        let multiPriority: Int
    }
}

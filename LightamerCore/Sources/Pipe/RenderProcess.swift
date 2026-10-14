import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The per-photo render process ledger (Plan M6-2-01, KD-1/KD-6; OQ-1..4
// effective values). LightCraft `ProcessVersion`/`Process` analog
// (`docs/process-versions.md` + `crates/develop/src/settings.rs`, MIT OR
// Apache-2.0 — mechanism transcribed, Swift implementation written fresh,
// zero code ported).
//
// THE PROBLEM: iop render semantics (kernel formulas, tone models, slider
// response curves, default curves) live in CODE, not in the `.lra` —
// retuning an iop silently shifts EVERY old document's render. The process
// version is the discipline that roots the fix: a look-changing iop semantic
// change MUST open a new process number; old documents render frozen on
// their stored number until an explicit migration.
//
// TWO TYPES, TWO DOMAINS (the M1 double-gate note):
//   • `RenderProcessVersion` (this file, below) = the STORED number. Its
//     domain gate INCLUDES 0 (the legacy sentinel — "before the concept"
//     documents, semantically frozen forever).
//   • The sidecar's STORED-VALUE decode gate (LightamerSidecar v10) starts
//     at 1: a stored `0` / null / corrupt value normalizes to nil = the key
//     ABSENT on the next write (0 ≡ absent ≡ legacy are the same semantic).
//
// THE BUMP DISCIPLINE (OQ-4; registered in three places — this enum's case
// doc-comments, AGENTS.md「process 账本」, and the M6 iop-tuning plan AC
// template row):
//   1. A LOOK-CHANGING iop change (tone model / slider response / default
//      curve / stage interpretation) MUST bump `RenderProcessVersion
//      .current`, append a new `RenderProcess` case, keep the old number's
//      semantics reachable (the frozen branch — the exhaustive switch the
//      compiler points at), and deliver old+new golden pairs with the batch.
//   2. A NON-LOOK refactor (performance, internal structure) MUST NOT bump.
//   3. A crash/NaN/black-frame/decoder-mismatch FIX is not a look change —
//      repair in place (LightCraft "The rule").
//
// FORK-POINT CACHE-KEY CONTRACT (KD-6, the `edgeMapAlgorithmVersion`
// precedent, PipeCacheKey.swift:92-127): M6-2 has ZERO semantic forks, so
// `PipeCacheKey` stays byte-untouched. When a future stage genuinely
// branches on the process, THAT stage's cache identity folds the process
// value — and the fold form is **FOLD ONLY WHEN NON-LEGACY**
// (`process.rawValue > 0` folds the value; 0 / absent folds NOTHING), so a
// legacy document's key bytes stay identical to today's forever. Register
// the fold at the fork site + AGENTS.md + DECISIONS.
//
// ORTHOGONALITY (RESEARCH §3.6): `ModuleInstance.version` (modversion) is
// the PARAMS-SHAPE migration face and folds into `HistoryHash` — bumping it
// is SUPPOSED to move caches and must never carry a semantic change. The
// process version is the opposite requirement (semantics move, documents
// freeze). Never fold process into `ModuleInstance.version` or
// `HistoryHash` — the zero-diff red line machine-checks this.
// ─────────────────────────────────────────────────────────────────────────────

/// The per-photo process number AS STORED (the `.lra` document-level
/// `process` key's value type; LightCraft `ProcessVersion(pub u32)`
/// transparent-newtype analog — an `Int` value, not Codable on purpose: the
/// sidecar owns the lenient JSON decode/encode table, this type is only the
/// in-memory carrier).
///
/// Domain: `0...0xFFFF_FFFF` (u32 like the LightCraft original — a
/// hand-edited or future-written document cannot smuggle in a negative or
/// oversized number). `0` is the **legacy sentinel**: every document written
/// before M6-2 (the key absent) reads as `.legacy`, and its render semantics
/// are FROZEN — the zero-drift promise's本体.
public struct RenderProcessVersion: Hashable, Sendable {

    /// The stored number. `0` = legacy (pre-process冻结档); `1...` = real
    /// process generations.
    public let rawValue: Int

    /// The domain-gated constructor (`0...0xFFFF_FFFF` — anything else is
    /// nil; the sidecar decode additionally rejects stored values < 1, see
    /// the M1 double-gate note in the file header).
    public init?(rawValue: Int) {
        guard rawValue >= 0, rawValue <= 0xFFFF_FFFF else { return nil }
        self.rawValue = rawValue
    }

    /// The pre-process sentinel (the key ABSENT on disk; render semantics
    /// frozen at whatever the code did before the concept existed). Distinct
    /// from any real process number by design (RESEARCH §3.1).
    public static let legacy = RenderProcessVersion(rawValue: 0)!

    /// The number a NEW document is minted with ("this build's generation").
    /// The ONLY legal bump point: a look-changing iop semantic change bumps
    /// this, appends the matching `RenderProcess` case, keeps the old
    /// number's frozen branch, and ships old+new goldens (the file header's
    /// discipline).
    public static let current = RenderProcessVersion(rawValue: 1)!
}

/// The build's IMPLEMENTED render-process generations (LightCraft `Process`
/// enum analog). Compiler-exhaustive by construction: every semantic fork
/// site `switch`es over this enum, so appending a case walks the compiler to
/// every place that must grow the new branch.
///
/// # The ledger (case doc-comments ARE the ledger — LightCraft `ALL` form)
///
/// Keep `all` oldest-first; `current` = `all.last`. A case's number = its
/// 1-based position in `all` (`.v1` = 1, `.v2` = 2, …) — `resolving` maps
/// the stored number through that table with the two clamps:
///   • `raw ≤ 0` → the OLDEST case (a legacy document runs the oldest
///     generation's semantics arm — the freeze made executable);
///   • `raw > current` → `current` (a document from a NEWER build renders
///     clamped to the newest known generation — forward compatibility, the
///     LightCraft `ProcessVersion::process()` clamp).
public enum RenderProcess: Sendable {

    /// M6-2 时代基线渲染（Plan M6-2-01 起盖章的新档代际）。与 legacy 0 的区别
    /// = v1 是 mint 盖章的「本代」，0 是概念引入前的冻结档——**M6-2 时点两者
    /// 渲染逐位恒等**（尚无语义分叉；首个真实分叉由未来 iop 语义变更引入）。
    /// 首个语义分叉开 v2 时：①追加 case 于此（编译器逐点指向所有分叉处）
    /// ②`all` 尾插 ③`RenderProcessVersion.current` 升号 ④AGENTS.md 账本行
    /// ⑤新旧号 golden 三件套随批交付。
    case v1

    /// The implemented generations, OLDEST FIRST (the `resolving` clamp
    /// table's backbone; a case's number = its 1-based index here).
    public static let all: [RenderProcess] = [.v1]

    /// The newest implemented generation (the mint target + the
    /// forward-number clamp).
    public static var current: RenderProcess { all.last! }

    /// The clamp table: a STORED number → the generation this build renders
    /// it with. `raw ≤ 0` → the oldest case (the legacy freeze); a number
    /// newer than this build → `current` (forward compatibility — the stored
    /// value itself is NEVER rewritten, only the render clamps); an in-range
    /// number → its own case.
    ///
    /// M6-2 has NO production consumption point (KD-5 — the seam is armed,
    /// zero behavior); the first fork batch calls this at its match site and
    /// switches exhaustively over the result.
    public static func resolving(_ raw: RenderProcessVersion) -> RenderProcess {
        if raw.rawValue <= 0 { return all[0] }
        let index = raw.rawValue - 1
        guard index < all.count else { return current }
        return all[index]
    }

    /// The case's stored number (the inverse of `resolving`; a future
    /// fork-point cache fold consumes THIS through the「非 legacy 才折」
    /// contract in the file header). The exhaustive switch is the ledger's
    /// compile-time half: a new case fails compilation HERE first.
    public var processVersion: RenderProcessVersion {
        switch self {
        case .v1: return RenderProcessVersion(rawValue: 1)!
        }
    }
}

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

    /// The current document generation's number ("this build's generation").
    /// The ONLY legal bump point: a look-changing iop semantic change bumps
    /// this, appends the matching `RenderProcess` case, keeps the old
    /// number's frozen branch, and ships old+new goldens (the file header's
    /// discipline). M8-2 (2026-10-25): bumped 1 → 2 — the FSIM spectral
    /// film core's production generation (the film leg's `.v2` arm).
    /// M9-4 (2026-10-27): bumped 2 → 3 — the ColorWheels LGG+Offset
    /// tone-wheel generation (the colorWheels module's `.v3` arm).
    public static let current = RenderProcessVersion(rawValue: 3)!
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
    ///
    /// M8-2 起为本批 FROZEN ARM（M6-2 预案 ①-⑤ 全数兑现）：v1 文档的 film
    /// sub-run 走密度核（`assembleDensityFilmLeg` 逐字节冻结——密度核代码、
    /// 65³ bake、FilmFilterPackSolver、`film_subrun` kernel 全保留），缓存
    /// 键（seed 的 policyTag 段）保持 `lightamer.film.subrun.v1` 逐位恒等
    /// ——v1/legacy 文档渲染零漂移是 M8 双臂 golden 主门。
    case v1

    /// M8 光谱核代际（Plan M8-2 bump，2026-10-25）。FORK 点 = film leg 工厂
    /// （`PixelPipe.assembleFilmLeg` 的 exhaustive switch——编译器逐点指向）：
    /// `.v2` 文档的 film sub-run 走光谱核（tc_lut 缓存槽 per-pair 表 +
    /// `FilmRuntimeSolve.solveSpectral` 光谱域求解 + `SpectralFilmKernels`
    /// dispatch 编排 A→corr 模糊→B + RFC-025 strength mix）。冻结臂 = v1
    /// 密度核；光谱开关单源 = 文档级 `process` 键（D-M8-1——零 FilmRecord
    /// 字段、零 schema bump、零 sidecar 新键）；缓存折键「非 legacy 才折」
    /// = 光谱臂 policyTag 升 `lightamer.film.subrun.v2-spectral`（review
    /// m1：fold discriminator = resolved arm，窄于 header `rawValue > 0`
    /// 字面形——v1 键字节恒等是 filmRampPlaneHash 冻结主门）。sub-run 之外
    /// 的渲染面（主链/显示尾/导出递缝）v1/v2 零分叉。
    case v2

    /// M9-4 ColorWheels LGG+Offset 代际（Plan M9-4 T2 bump，2026-10-27）。
    /// FORK 点 = `ColorWheelsModule.process` 的 exhaustive switch（编译器
    /// 逐点指向）：`.v3` 文档的 colorWheels op 走 `grade_color_wheels_v3`
    /// 调度（ApplyToneWheel 四轮影调域语义——Offset/Lift/Gamma/Gain 分离，
    /// 旧 lift→offset 精确 + gamma/gain 最小二乘拟合的读入转换在渲染预解
    /// 层现算，D-M9SP-2 判别子：params `offset` 键在场 = v2 语义）。冻结
    /// 臂 = `.v1/.v2` 现行 dispatch（`grade_color_wheels` 逐字节）。缓存
    /// 折键「非 legacy 才折（resolved-arm 收窄形）」= per-box
    /// `processForkHash`（仅 `.v3` 臂折 `lightamer.colorwheels.v3` tag，
    /// `PixelPipe.prepareChain` 折一处——v1/v2/legacy 键字节恒等是冻结
    /// 主门，D-M9SP-8）。其余渲染面（film 腿/DRT 尾/导出递缝）零分叉。
    case v3

    /// The implemented generations, OLDEST FIRST (the `resolving` clamp
    /// table's backbone; a case's number = its 1-based index here).
    public static let all: [RenderProcess] = [.v1, .v2, .v3]

    /// The newest implemented generation (the mint target + the
    /// forward-number clamp).
    public static var current: RenderProcess { all.last! }

    /// The clamp table: a STORED number → the generation this build renders
    /// it with. `raw ≤ 0` → the oldest case (the legacy freeze); a number
    /// newer than this build → `current` (forward compatibility — the stored
    /// value itself is NEVER rewritten, only the render clamps); an in-range
    /// number → its own case.
    ///
    /// M8-2 owns the FIRST production consumption point: the film leg
    /// factory's exhaustive switch (`PixelPipe.assembleFilmLeg`) and the
    /// film seed's arm-tag fold (`FilmTailAssembly.policyTag(for:)`) —
    /// every other render face (main chain, display tail, export seam) is
    /// fork-free.
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
        case .v2: return RenderProcessVersion(rawValue: 2)!
        case .v3: return RenderProcessVersion(rawValue: 3)!
        }
    }
}

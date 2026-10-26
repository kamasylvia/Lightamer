# M9-2 CHECKER — plan v2 修复终验（2026-10-27）

```
验收对象: .work/gsd/phases/m9-2-bwspectral/M9-2-PLAN.md（v2）+ CONTEXT.md
修复依据: M9-2-PLAN-REVIEW.md（MAJ-1 + MIN-1..6 + OBS-1..6）
性质: 纯读评终验（零 commit / 零构建）；源锚亲核 11 处 + plan/CONTEXT 文本逐条核
结论: 放行（残项 1——文字级残留，不影响执行正确性）
计数: MAJ-1 ✓ / MIN-1..6 ✓（MIN-2 附 1 残项）/ OBS-1 采纳 ✓ / 残项 1
```

---

## 一、放行判定：放行

MAJ-1 与 MIN-1..6 全部在 plan v2 + CONTEXT 落真（落点逐条见 §二）；M9BW-01..03
goal-backward 零缺腿（§四）；ΔN +15..20 构成自洽、对账锚带式与 charter/GOAL-STATE
三方一致（§五）。唯一残项 = **R-1 ΔN 表 T2 落点「Layers」残留**（MIN-2 改写
只增 Library 未删 Layers——文字级，落域真相由 files_modified / T2 action 7 /
T5 action 1 三处正确承载，不影响执行路径与验收判据）；执行期顺手修即可，不构成退回。

---

## 二、逐条核验（MAJ + MIN + OBS-1）

### MAJ-1 paperGrade 编码裁决 → `String?` verbatim — ✓ 全落（7 处）

| 落点 | v2 实文 | 判定 |
|---|---|---|
| plan 已定裁决 3（:96-100） | 「paperGrade 编码 = `String?`（"00".."5" verbatim……三处消费面同此编码……裁决附注正本 = CONTEXT D-M92-4——MAJ-1，2026-10-27 评审修复）」 | ✓ |
| plan T2 action 2（:218-220） | `paperGrade: String?`（**编码裁决 MAJ-1**："00".."5" verbatim……gradeTag 折叠值/UI picker 数据源同此编码；nil = 现 solve） | ✓ |
| plan T2 action 6（:251-252） | grade picker「**数据源 = String 档 key verbatim**（MAJ-1 编码），直映 paper_grades 表 key」 | ✓ |
| plan T3 action 3（:310-311） | gradeTag = paperGrade **String 档 key verbatim**（"00".."5"——MAJ-1 编码），nil 不折 | ✓ |
| CONTEXT D-M92-4 附注（:88-95） | 完整裁决附注（"00" y_filter_neutral 199.0 与 "0" 137.9 两不同档、Int 歧义、上游无 grade Int 先例、三消费面同编码） | ✓ |
| CONTEXT D-M92-5（:111-112） | 折叠值 = 档 key **String verbatim**（"00".."5"，D-M92-4 编码裁决） | ✓ |
| CONTEXT X-M92-2（:202-203） | 非 nil 档（String "00".."5" verbatim——D-M92-4 编码裁决） | ✓ |

三消费面（sidecar v12 持久键 / gradeTag 折叠值 / UI picker）+ 裁决正本 + 两条
D/X 交叉引用全同步；评审建议的 `String?` 方案被采纳。

### MIN-1 midscale fold 两类理由分开 — ✓ 全落

- plan T3 action 4（:314-321）：log_sensitivity/channel_density/viewing_illuminant
  = 「**对齐消费集**（grep 实证在案）」；midscale = 「**预折**：引擎当前零消费
  （grep 实证——仅 FilmProfile decode/projected 自身面）……MIN-1：与 doc 注释
  矛盾以 DECISIONS 分开登记两类理由消解」。
- CONTEXT D-M92-5（:117-125）同款两类分开 + MIN-1 修正注记在案。
- **源锚亲核**：`grep midscaleNeutralDensity SpectralBuildEngine.swift` 零命中；
  全 Core 范围仅 FilmProfile.swift 自身面（CodingKeys :257 / decode :279/:315 /
  init :378/:392 / projected :578-581 / 注释 :232-233）——「引擎零消费、仅
  自身面」的表述与 grep 实证**逐点吻合**。

### MIN-2 SidecarV12Tests 落域 Layers → Library — ✓ 落（附 R-1 残项）

六处同步核验：frontmatter `test_bundles`（:10，含 Library）✓ / frontmatter
`expected_all`（:12，定向 bundle 列表含 Library）✓ / T2 action 7（:261-262，
「Library——SidecarV10/V11 双连 LIB 同位，MIN-2」）✓ / files_modified（:38，
注记同款）✓ / T5 action 1（:413，「Library×1 = SidecarV12〔V10/V11 同位，MIN-2〕」）✓ /
T5 action 2 定向 bundle 命令含 `--bundle Library`（:419-420）✓。

**源锚亲核**：BUNDLE-MAP :733 `LIB 15 SidecarV10Tests.swift`、:739
`LIB 5 SidecarV11Tests.swift` 双连 LIB 命中；M7-4 增行记录明文「plan 文
『Layers 域』按 V10 同位读解为 LIB 域」——同款漂移先例在案。

**残项 R-1**：plan ΔN 预算表 T2 行落点（:84）=「IOP·IOPParity·**Layers·
Library**·App」——Layers 未随 MIN-2 改写删除（T2 四个测试文件 PaperGradeTable
=IOP / BWSpectralGolden=IOPParity / SidecarV12=Library / FilmPanelBW=App，
**无 Layers 域文件**；全批 Layers 域唯一文件 = T1 BWProfileAssetsTests）。
CONTEXT ΔN 表（:368）同形。文字级残留：落域真相由三处正确文本承载，执行
路径不受影响——放行 + 执行期顺手修（T2 DECISIONS 或 SUMMARY 注记删 Layers
即可，plan 文本不必重开）。

### MIN-3 T2-T4 Project.swift 当批登记 — ✓ 全落

T2 action 8（:264-267）/ T3 action 8（:343-345）/ T4 action 5（:392-395）三处
末位 action 均含「数组行 + BUNDLE-MAP 增行同 commit + tuist generate 末位
（MIN-3，L041/E2）」；T5 action 1（:417-418）改「**只做全量核对**——各任务
已当批登记」；files_modified 的 Project.swift 注记（:44）同步「T1-T5 逐任务
……T5 只做全量核对」。

### MIN-4 封存面 15 → 17 件 — ✓ 全落（4 处）

frontmatter red_lines（:19）/ CONTEXT 红线 5（:296-307，17 件逐件枚举 + AGENTS
「15 项」简写口径注）/ T5 action 4（:425-426）/ Checker 关注点 3（:496）。

**源锚亲核**：`m7-6-station-close/M7-6-01-SUMMARY.md` :47 红线表 #5 原文
「封存面 17 件 | DrtRecord/…/GradeCatalog/**IOP Registry/ModuleInstance**」
——逐件清点确 17 件（含后两件）。plan 机检口径 = 17 件全集，与原始清单一致。

### MIN-5 isPristine 双面点名 — ✓ 落

T2 action 3（:231-236）注意项改「pristine 判定**两处面**同步扩」——Core
`isFilmRecordDefault`（synthesized == 自动覆盖 nil 档）+ App `FilmPanelModel.
isPristine`（:77-83 **手写逐字段判定**，cameraFilter/paperGrade 非 nil 档
须手扩，否则误判 pristine）。

**源锚亲核**：FilmPanelModel.swift `var isPristine` 实测 :78-84（声明 :78、
判定体 :80-83、doc 注释 :76-77 起）——手写逐字段（filmStock/paperStock/
mFilterShift/yFilterShift/contentAdaptiveShift/strength/exposureEv/hasActiveRecord）
与 plan 描述逐字段吻合；plan 引 :77-83 与实测 :78-84 一行偏差（77 = 注释首行），
判定面完整覆盖，实质命中。

### MIN-6 CodingKeys 三静默提醒 — ✓ 落

T2 action 2（:221-225）：「FilmRecord 手写 `init(from:)` + synthesized encode——
新 optional 字段不进 CodingKeys 时编译通过、decode 恒 nil、encode 静默丢键、
recordHash 不含（**一处三静默**），CodingKeys/decode/encode 三面须同批扩」。

### OBS-1 采纳核 — ✓

T2 action 3（:236-239）SUMMARY 落账登记句在位：「sidecar v12 = 封存面登记
（M7-6）以来首例 bump——豁免有据（文件自带 bump 章程 + persisted-face
先例链 + 本 plan 显式例外申报），SUMMARY 摘要节显式登记该事实」。

**源锚亲核**（豁免依据抽核）：LightamerSidecar.swift :245-254 bump 注释链
（v8 aiProvenance / v9 filmRecord / v10 process / v11 note）+ 章程原句
「**a persisted-face addition bumps**」+ `schemaVersionCurrent = 11`——
OBS-1 的事实链三依据之一亲证在案。

---

## 三、源锚亲核登记（11 锚，全命中）

| # | 锚 | 结果 |
|---|---|---|
| 1 | SpectralBuildEngine.swift grep `midscaleNeutralDensity` | ✓ 零命中（引擎零消费） |
| 2 | 全 Core grep midscale 仅 FilmProfile.swift 自身面（decode :257/:279/:315 + projected :578-581 + 注释） | ✓（MIN-1 表述逐点吻合） |
| 3 | BUNDLE-MAP :733 LIB SidecarV10Tests / :739 LIB SidecarV11Tests + M7-4 增行记录「Layers→LIB 同位读解」先例 | ✓（MIN-2） |
| 4 | FilmPanelModel.swift :78-84 isPristine 手写逐字段判定 | ✓（MIN-5；plan 引 :77-83 一行偏差、实质命中） |
| 5 | m7-6-station-close/M7-6-01-SUMMARY.md :47 封存面 17 件原文（逐件数确 17，含 IOP Registry/ModuleInstance） | ✓（MIN-4） |
| 6 | FilmMaterialStore.swift :115-158 foldProfile fold 集 = stock+logExposure+densityCurves+baseDensity+wavelengths | ✓ 确不含三谱键 + midscale（D-M92-5 实锤） |
| 7 | LightamerSidecar.swift :245-254 bump 注释链 + persisted-face 章程 + current=11 | ✓（OBS-1 依据） |
| 8 | SpectralBuildEngine.swift :428-453 窗口段（erf4 + per-channel 归一）→ tc 循环邻位 | ✓（X-M92-1 插入坐标精确） |
| 9 | GOAL-STATE.md :24「全套 4287/39/0」 | ✓（baseline 取值正确，OBS-4 复证） |
| 10 | REQUIREMENTS.md :738-740 M9BW-01..03 验收形态 | ✓（goal-backward 输入） |
| 11 | ROADMAP.md :141 M9-1「20-28N」/ :142 M9-2「M，15-20N」 | ✓（对账锚带 + charter 带双证） |

---

## 四、Goal-backward：M9BW-01..03 在 v2 全兑现（零缺腿）

| 需求 | 验收形态（REQUIREMENTS :738-740） | plan 承载 | 判定 |
|---|---|---|---|
| M9BW-01 | profile 入谱面体系 + MANIFEST 对账 + 中性/阶调 golden | T1（五 profile schema = FilmProfile decode 零改即接受 + MANIFEST.sha256 + NOTICE 来源表 ≥7 条 + BWProfileAssetsTests 四断言面）+ T2（中性门三通道散 ≤2e-3 ×4 卷 ×3 grade + 阶调门单调/1.3×/18% 灰带）；SC 逐面可机检 | ✓ |
| M9BW-02 | 变反差相纸 + 滤色镜：中性链零漂移负测 + 光谱透传 golden | T2（相纸 grade 全链：字段→printCC preset→bake→面板 + 阶调门）+ T3（负测组 ⑤ nil 档与 M8 基线逐字节一致 = ON/OFF 零漂移；⑥ factor 归一 |Δ|<0.01；⑦ 方向断言；⑧ 因子交叉 = 透传 golden 三面） | ✓ |
| M9BW-03 | per-film granularity 标定表 + 强度语义断言 | T4（grain_calibration.json + GrainCalibrationTests round-trip/确定性/单调 + GrainCalibrationSemanticsTests 推荐 strength 下合成灰面 RMS 与发表值同带 + GrainModule 零 diff 机检） | ✓ |

备注（不构成残项）：M9BW-01 验收形态原文「profile 入谱面体系」vs plan
frontmatter 摘写「BW profile 自建」——语义等价（自建落盘即入谱面，T1/SC
两面均承载「入谱面体系」实质），非逐字；属 REVIEW OBS-3「逐字一致」表述
略宽，非 plan 缺陷。

---

## 五、ΔN 构成与对账锚

- **ΔN 带**：下限 3+5+4+2+1 = **15** / 上限 4+6+5+3+2 = **20** —— 带 +15..20
  精确自洽；与 charter（ROADMAP :142「M，15-20N」）精确命中。
- **构成与文件对账**：九新测试文件（T5 action 1 清单 Layers×1 + Library×1 +
  IOP×3 + IOPParity×3 + App×1 = 9）与 files_modified 逐一对应 ✓；各任务法数
  区间与文件承载面合理。
- **对账锚带式**：`4287 ⊕ ΔN_R6（在飞） ⊕ ΔN_M9-1（charter 估 20..28——
  ROADMAP :141 亲核） ⊕ 本批 +15..20` —— plan baseline（:11）/ expected_all
  （:12）/ T5 验收（:446-447）与 CONTEXT（:376-381）四方一致；GOAL-STATE :24
  「4287/39/0」亲核吻合；开工前亲核义务（GOAL-STATE + R6/M9-1 SUMMARY 实数）
  在 baseline 与 T5 双落。带式一致 ✓。

---

## 六、残项清单（1 项，放行附带）

| # | 残项 | 级别 | 处置 |
|---|---|---|---|
| R-1 | plan ΔN 表 T2 落点（:84）「IOP·IOPParity·**Layers·**Library·App」——Layers 为 MIN-2 改写残留（T2 无 Layers 域测试文件；CONTEXT ΔN 表 :368 同形） | 文字级（不影响执行正确性：落域真相由 files_modified / T2 action 7 / T5 action 1 三处正确文本承载） | 执行期顺手修：T2 DECISIONS 或 SUMMARY 落账时注记「ΔN 表 T2 落点 Layers 应删（MIN-2 残留）」即可；不必重开 plan |

---

## 七、结论

**放行**。MAJ-1（7 处落点）+ MIN-1..6 + OBS-1 采纳全部落真；M9BW-01..03
goal-backward 零缺腿；ΔN +15..20 构成自洽、对账锚带式四方一致；11 处源锚
亲核全命中。残项 1（R-1 ΔN 表 T2 落点 Layers 文字残留）执行期顺手修。

—— checker：zcode 独立终验 subagent，2026-10-27；零 commit / 零构建。

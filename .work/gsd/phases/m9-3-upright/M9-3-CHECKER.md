# M9-3 修复终验 CHECKER（2026-10-25，零 commit 纯读评）

> 验收对象：`M9-3-PLAN.md`（**v2**，含「评审修复记录（v2）」节）。
> 输入 = `M9-3-PLAN-REVIEW.md`（PASS-with-notes：0 error / 3 minor / 4 obs）+ `CONTEXT.md`。
> checker 方式 = plan v2 全文逐条对照 + 亲核抽锚（本轮独立亲核 **30 锚**：我方仓 9 + lightcraft origin/main 14 + 台账/规划 6 + RESEARCH §5 1，全命中，零漂移）。

## 终裁：**放行**

- 修复面残项 = **0**（MIN-1..3 + OBS-3 全部真落，落点齐整、语义与 fixer 声称逐条吻合）。
- 已申报观察项 = **2**（晨审面/表述级，不阻断，见 §五）。
- Goal-backward 零缺腿；ΔN 带 +14..19 构成自洽（MIN-3 并法不破带）；带式对账锚三方一致。

---

## 一、MIN-1..3 + OBS-3 逐条核真落

### MIN-1 落域汇总数错 → ✅ 真落（2/2 改写点 + files_modified 自洽）

- ΔN 预算表合计行（PLAN :80）：「六新测试文件（**三 IOP + 一 IOPParity + 二 App**）」✓。
- T5 Action 1（PLAN :330-331）：「三 IOP / 一 IOPParity / 二 App」✓。
- files_modified 六行标注逐一复核（PLAN :23/:24/:29/:34/:35/:40）：UprightMath/CropFitAngle/StraightenDetect = IOP、UprightModuleParity = IOPParity、CropToolRotation/UprightGuidesInteraction = App——与修正后计数**逐行自洽**，无残留旧数（grep 全文「二 IOP」「三 App」零命中）。

### MIN-2 off 负测语义张力 → ✅ 真落（判定面钉死 + 推理链自洽）

- T2 验收首条（PLAN :190-194）：判定面 = **「off 恒等直通 byte-exact + params 持久仍合法」**，upright 进默认 seed ⇒ paramsData 恒写（ashift/flip 同形），「off 不写 sidecar」**分支禁止**；「pristine 惯例是 DRT/film document record 面语义，不适用 instance params 面」——review 建议的机器形态原样落定 ✓。
- frontmatter success_criteria T2 段（PLAN :8）同语义改写 ✓。
- 推理链闭合：T2 Action 3「upright 注册行族（默认 seed……upright 默认面启用）」（PLAN :185-186）⇒ 每文档恒有实例 ⇒ paramsData 恒写——判定面与注册形态无冲突（原 v1 的字面冲突已消除）。

### MIN-3 shouldAutoRefit 中段语义 → ✅ 真落（六落点全在 + upstream 依据亲核坐实）

裁决 = 收缩对齐 upstream（仍 fit 不动 / 不再 fit 绕中心收缩保 aspect / 非最大框永不放大）。落点亲核：

| 落点 | 位置 | 核验 |
|---|---|---|
| T1 `shrinkToFit` 闭式 | PLAN :128-134（含 #1794 中段裁决〔v2〕标注 + 双测试名引用 + 保守回退形申报） | ✓ |
| T1 验收 | PLAN :144-145「手调框不再 fit 绕中心收缩保 aspect（#1794 中段，upstream crop.rs 双测试语义同参）」 | ✓ |
| T3 Action 联动批 | PLAN :232-234（手调框保护三分支 + T1 `shrinkToFit` 件引用） | ✓ |
| T3 验收 golden | PLAN :256-259（收缩后仍内接 + 中心不变 + aspect 不变三断言） | ✓ |
| 风险节 | PLAN :377-378「#1794 → 非最大框不放大 + 不再 fit 绕中心收缩保 aspect 断言（v2 中段裁决 = 对齐 upstream）」 | ✓ |
| frontmatter T1/T3 段 + T5 走查①边界样张 | PLAN :8 / :339-340（「手调框 + 大角度 + 框不再 fit」收缩边界样张，obs-4 联动） | ✓ |

**upstream 依据独立亲核坐实**（lightcraft origin/main，`git show origin/main:crates/geom/src/crop.rs`）：`with_angle_keeps_a_crop_that_still_fits` :206 + `with_angle_shrinks_a_crop_that_no_longer_fits_keeping_its_aspect` :217 双测试**逐名命中**，另有 `with_angle_grows_a_fitted_crop_back_as_the_angle_returns` :229（角回 0 复原 = #1388 侧）——三分支 golden 的 upstream 参照系完整在案。

### OBS-3 upstream 读取纪律 → ✅ 真落（read_first 注记 + 三事实全真）

- T1 read_first 注记（PLAN :95-99）：「upstream 引用一律 `git show origin/main:<path>`，工作树文件不可信」+ 误判三例登记 ✓。
- 事实独立复核：lightcraft HEAD `0da998f2` 落后 origin/main `bb08a697` **恰 1031 commits**；工作树 upright.rs **611 行**（origin/main 634 行）；`tests_guided_guides.rs` 工作树**不存在**（origin/main 在 `crates/ui-egui/src/`）——注记三事实零漂移。

## 二、OBS-1/2/4 不采理由合理性 → ✅ 全部合理

- **OBS-1**（AshiftKernel enum 同形）：review 原文自判「无需改文」；plan T2 已有「`AshiftModule.swift:73` 同形」表述（PLAN :167-168）。本轮亲核 `AshiftModule.swift:73` 邻域 = `enum AshiftKernel { public static let functionName = "ashift_warp" }`——UprightModule 照建 `UprightKernel` 同形即得，不采合理。
- **OBS-2**（spread 门分域 1.2/1.5）：obs 本身标注「判别力仍足」非强制；plan 维持 1.5px 统一 + 修复记录表留「执行批愿收严可自便」口（PLAN :405）——不采合理。
- **OBS-4**（边界走查样例）：修复记录表标「未采」但实质**借 MIN-3 通道落地**（T5 走查①收缩边界样张在案，PLAN :339-340）——标签为「不作为独立修复项」，实质内容已采纳，优于纯不采。

## 三、Goal-backward：M9GEO-01/02 零缺腿 → ✅

REQUIREMENTS :741-742 原文亲核（本轮）：

- **M9GEO-01**（:741）「旋转 90/任意角 golden + sidecar 持久化 + 视口交互探针」三验收形态逐件承载：
  - 旋转 golden → T3 验收末条（flip 位集 + ashift.rotation 两腿，spread <1.5px + AABB 闭式，PLAN :260-262）✓；
  - sidecar 持久化 → T2 paramsData 恒写判定面（MIN-2 修复后更显式）+ T3 90° 位持久重读断言 ✓；
  - 视口交互探针 → CropToolRotationTests（App 域）+ 走查 MANIFEST ①②③⑤ ✓；
  - 「参数入 history，几何域 iop」→ 角度手柄/拉直写 ashift.rotation（几何域 iop）+ recordLinkedChanges history item ✓。
  - 勘误后真缺口六件（角度手柄/拉直滑杆/90°/联动重算/auto straighten 防呆/Constrain Crop）全落 T3 Action/验收，无悬空件。
- **M9GEO-02**（:742）「合成梯形畸变恢复 golden + 参考线交互探针」：
  - golden → T1 门 1（spread <1.5px + 四角差 <0.01）+ T2 产线 warp 梯形恢复复验（真实 kernel 腿，spread 门同值）双层承载 ✓；
  - 交互探针 → T4 UprightGuidesInteractionTests（upstream 5+5 法对照面）+ 走查 ④ ✓；
  - 「lightcraft upright.rs MIT 移植」→ T1 UprightMath（MIT 头注 + NOTICE 红线 4）；「M5-3 Pano 复用」与勘误的冲突在 CONTEXT charter 勘误节显式登记（晨审可翻）——处置合规。

## 四、ΔN +14..19 自洽 + 带式对账锚一致 → ✅

- **逐任务区间算术**：T1 5..7（UprightMath 4..5 + CropFitAngle 1..2）/ T2 3..4 / T3 4..5（StraightenDetect 2..3 + CropToolRotation 2）/ T4 2..3 / T5 0——下限和 14、上限和 19，闭合 ✓。
- **MIN-3 并法不破带**：#1794 三分支 golden 并入 T1 CropFitAngle 1..2 法（「收缩 golden 并法承载，一法多断言」，PLAN :75）；T3 收缩断言并入「原子批+联动谓词+手调框保护」一法（PLAN :77）——两处均一法多断言、零新法计数，+14..19 带不变 ✓。
- **越带申报三处在案**：frontmatter estimated_tests（:9）+ ΔN 表注（:82-86）+ 正文基线节（:69）；申报理由引用「RESEARCH §5 明列」经本轮亲核为真（§5 golden 形态 1-7 逐门在案，:265 起）✓。
- **带式对账锚三方一致且亲核命中**：
  - R6 终值 `4292/35/0` = `R6-SUMMARY.md:55` 精确命中（本轮亲核）；
  - ΔN_M9-1 = plan v2 `+20..29` = `m9-1-aimask/M9-1-PLAN.md` estimated_tests 精确命中（本轮亲核）；
  - ΔN_M9-2 = `+15..20` = `m9-2-bwspectral/M9-2-PLAN.md` estimated_tests 精确命中（本轮亲核）；
  - 三处表达（frontmatter baseline :11 / CONTEXT 头部 :37-40 / T5 Action 3 :335-336）一致，「开工前以 SUMMARY 实数落」条款齐备 ✓。
- **charter 带**：ROADMAP §M9 站 3「M，12-18N」亲核命中——plan 上沿 19 越 charter 至多 +1 与申报相符 ✓。

## 五、已申报观察项（不阻断）

1. **D-M9G-1 字面「用户手调过的框永不自动改」与 MIN-3 收缩裁决的字面张力**：CONTEXT D-M9G-1 行文（:93）写「永不自动改」，plan v2 将「不再 fit」支路裁决为收缩（非不动）。判定 = **已申报细化非暗改**——修复记录表显式登记「按 D-M9G-1『upstream 三代 issue 收敛件』意图细化中段语义，晨审可翻」+ 保守回退形在案；且 #1794 收缩语义是该裁决「三代 issue 收敛件」自我定位的应有之义（upstream 双测试钉死）、收缩三断言（仍内接/中心不变/aspect 不变）严格窄于「自动改」的滥用面（无放大、无重定位）。晨审若翻 = 回退形一字改（T1 谓词 + golden 断言），结构面无连锁。
2. **OBS-4 标签小瑕**：修复记录表列「未采（不强制）」而实质内容已借 MIN-3 落地（T5 走查①）——表述与实况的标签差，无实害（修复记录表自身已注明落点）。

## 六、本轮亲核锚点清单（30 锚，全命中）

- **我方仓（9）**：V50Order :48-49（ashift 15.0 → flip 16.0，15.5 空位实证）/ AshiftModule.swift:73（AshiftKernel enum + functionName 字符串常量）/ Registry :39-47（defaultFaceDisabledOpNames）/ Registry :515-519（「rotation + perspective share one kernel」共名）/ CropOverlayView.swift:27-28（旋转手柄 linkage 注记原文）/ HistoryStack.swift:342-350（单步 undo 无组机制）/ LightamerSidecar.swift:741-752（paramsData）/ LightamerSidecar.swift:255（schemaVersionCurrent = 11）/ EditorState.swift:217（recordChange，recordLinkedChanges 邻位）。
- **lightcraft origin/main（14）**：upright.rs 634 行 / solve_guided :508 / STRAIGHTEN_MAX_DEGREES :583=10.0 / STRAIGHTEN_MIN_LINES :587=3 / level_degrees :592 / crop.rs constrained :59 / with_angle :99 / crop_fit_angle :167 / #1794 双测试 :206+:217 / :229 角回 0 复原测试 / tests_guided_guides.rs 在 origin/main / HEAD 落后恰 1031 / 工作树 upright.rs 611 行 / 工作树无 tests_guided_guides.rs。
- **台账/规划（6）**：R6-SUMMARY.md:55（4292/35/0）/ REQUIREMENTS :741（M9GEO-01 原文）/ :742（M9GEO-02 原文）/ ROADMAP M9-3 站行（M，12-18N）/ M9-1-PLAN estimated_tests（+20..29）/ M9-2-PLAN estimated_tests（+15..20）。
- **RESEARCH（1）**：§5 golden 形态 1-7 逐门（越带申报理由引用真实性）。

---

**终裁：放行**——plan v2 修复面 4/4 真落（MIN-1..3 + OBS-3）、OBS 不采 3/3 合理（其一实质采纳）、goal 零缺腿、ΔN 带自洽、对账锚一致。移交执行批（T1 起）；晨审面观察项 2 条随 CONTEXT 既有推翻点索引流转，无需 plan 重开。

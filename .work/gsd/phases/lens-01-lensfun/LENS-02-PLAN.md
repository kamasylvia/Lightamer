---
phase: lens-01-lensfun
plan: "LENS-02"
title: "plan L2 — enable + per-correction 三 toggle + scale（auto 二分移植 + user 滑杆 + kernel 扩 scale 标量 + 接力 crop）+ auto-apply 开关（raster 域）+ profile browser（T1 enable/per-correction 语义 / T2 auto-apply / T3 scale + LensAutoCrop / T4 browser / T5 键族收口 / T6 收口）"
wave: 2
depends_on: ["LENS-01"]
autonomous: true
requirements: ["charter = UQ-R4（8bd94370）——FEAT-DEV-07 的 enable+scale+auto-detection UX 波", "research 正本 = phases/lens-01-lensfun/RESEARCH.md（b2b31909）§Route Matrix 吸收件 2/§Geometry Seam/§UI-UX/§Plan Split L2 行", "OQ 裁决正本 = 同目录 CONTEXT.md（D-LENS-1/-5/-7 + X5/X6 + 红线 15 条）", "基线 3991/37/0；本 plan 分账 +18..28（含 LENS-01 终态增量后的对账式）", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 LENS-03/04 并行波起跑"]
success_criteria: "SC 全可机检——T1：Params.enabled additive（nil=true）+ applyDistortion/applyTCA/applyVignette 三 toggle（默认 true）+ 中性谓词扩展 + 系数族门控组合逻辑纯函数 + 零漂移负测；T2：UserDefaults 恰一新键 lensfun.autoApply（默认 false，注入式读法）+ reloadDefaults auto 臂（生效域 = embeddedGeometry == .notApplicable 硬守卫）+ 表驱动测试；T3：LensWarpUniforms.scale 标量（默认 1.0）+ kernel 采样 ×1/scale + modifyROIIn 边框同步 + LensAutoCrop.minimumScale（RawLab 二分 GPL 移植 + 版权头）+ user 滑杆 + resolved readout + 接力 crop 按钮（Crop 面板单源）+ scale golden（IOPParity）；T4：profile browser 五段改造 §4（搜索 + 候选 + matched 置顶 + 40 档低置信标注）+ Apply/Clear 退役终形 + 40 分档不自动入选维持；T5：xcstrings 新键尾块 + zh-audit 双 PASS + AGENTS.md UserDefaults 键登记"
estimated_tests: "+18..28（T1 +3..5 / T2 +2..4 / T3 +7..11〔含 scale golden〕/ T4 +4..6 / T5 +2〔键族面〕；越带申报理由）"
test_bundles: [IOP, IOPParity, APP]
baseline: "3991/37/0 + LENS-01 终态（对账式——LENS-01-SUMMARY ΔN 终账为起算基）"
expected_all: "LENS-01 终态 + ΔN（LENS-02 分账 +18..28；--all 归 orchestrator 批准制——本 plan 验收 = 构建 + 定向 bundle〔IOP/IOPParity/App〕，全套归 LENS-04 收口轮）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 15 条；本 plan 特别面 = LensKernels.metal 改动限于 scale 标量采样坐标一处（投影数学 = LENS-03 域，本 plan 零触投影）；LensWarpUniforms 结构改动 = 纯尾插标量 + 对齐面复核（80 字节 struct 对齐纪律）。"
  - "UserDefaults 恰一键 lensfun.autoApply（红线 11）；注入式读法（KD-4——LensModule init 直读 .standard + 测试注入缝；面板 body 零直读）。"
  - "RawLab 二分移植合规（红线 7）：LensAutoCrop.swift 版权头 + 修改标注（NOTICE 条目登记归 LENS-03 T4 汇总，本 plan DECISIONS 预登记移植件清单）。"
  - "裁切真相单源：接力 crop 只写 Crop 面板建议框（CropModule 24.5 域），禁第二裁切实现（D-LENS-5）；crop_bounds/CIRCLE 零命中。"
  - "detected/unknown 态 auto 硬守卫零绕过（D-LENS-1——开关生效域 = notApplicable 唯一）；RAW 文档 auto-apply 恒不触发。"
files_modified:
  - LightamerIOP/Sources/Lens/LensModule.swift                # T1：Params.enabled/applyDistortion/applyTCA/applyVignette additive + 中性谓词扩展 + T2 auto 臂 + T3 uniforms scale 折入
  - LightamerIOP/Sources/Lens/LensfunMatch.swift              # T3：resolve→uniforms scale 传递（如分居 LensKernelParams 则随 actual 申报）
  - LightamerIOP/Sources/Lens/LensKernels.metal               # T3：lens_manual_warp 采样坐标 ×1/scale（单 pass 零结构改）
  - LightamerIOP/Sources/Lens/LensAutoCrop.swift              # T3：新建——RawLab 二分移植（GPL 头 + 修改标注）
  - App/Sources/Lightamer/UI/Inspector/LensPanelView.swift    # T1：§2 enable+三 toggle / T3：§3 scale 段+接力 crop / T4：§4 browser + Apply/Clear 退役
  - App/Sources/Lightamer/UI/Inspector/LensProfileBrowser.swift # T4：新建——browser 段（搜索+候选列表，View 薄壳 + 模型可测）
  - App/Sources/Lightamer/UI/Shell/EditorAreaView.swift       # T3：接力 crop 缝（如走 canvas 侧则随 actual 申报；建议框填入 Crop 面板的既定缝）
  - Resources/Localizable.xcstrings                           # T5：panel_lens §2/§3/§4 新键尾块纯插入
  - Tests/LightamerTests/LensPerCorrectionTests.swift         # T1：新建（IOP）
  - Tests/LightamerTests/LensAutoApplyTests.swift             # T2：新建（IOP）
  - Tests/LightamerTests/LensAutoCropTests.swift              # T3：新建（IOP——二分纯函数）
  - Tests/LightamerTests/LensScaleGoldenTests.swift           # T3：新建（IOPParity——kernel scale golden）
  - Tests/LightamerTests/LensProfileBrowserTests.swift        # T4：新建（App——browser 模型）
  - Project.swift                                             # T6：五个新测试文件入数组（IOP ×3 / IOPParity ×1 / App ×1）
  - .work/gsd/phases/lens-01-lensfun/LENS-02-SUMMARY.md       # T6
  - .work/gsd/phases/lens-01-lensfun/LENS-02-DECISIONS.md     # T6（Clear 终形 + 接力缝落点 + 移植件清单预登记）
---

# Plan LENS-02 — plan L2：enable/per-correction/scale/auto-apply/profile browser

> **裁决正本** = `CONTEXT.md`（D-LENS-1/-5/-7 + X5/X6）；规格正本 =
> `RESEARCH.md`（§Route Matrix 吸收件 2〔RawLab auto-crop〕/§Geometry
> Seam/§UI-UX 五段终表/§Plan Split L2 行）。本 plan 首触
> `LensKernels.metal`（scale 标量一处）——投影数学零触（LENS-03 域）。
>
> **前置**：LENS-01 闭环（params resolve 输入/readout/memo 在位）。
> **裁定权归属钉**：无用户裁决分支；扩面触发（crop_bounds/第二裁切真
> 相/detected 态 auto 绕过/投影提前）= 停手上报。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6。每任务独立 commit；重活前
> 过 `Scripts/machine-guard.sh`。
>
> **C 档停**：T6 闭环后**停汇报**；确认后 LENS-03/LENS-04 并行波起跑。

## ΔN 预算表（逐任务，LENS-02 分账带 +18..28；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 enable/per-correction | **+3..5** | toggle 组合门控 + 中性谓词 + 零漂移负测 | IOP |
| T2 auto-apply | **+2..4** | 生效域硬守卫表驱动 + 注入读法 | IOP |
| T3 scale + auto-crop | **+7..11** | 二分边界 golden + kernel scale golden + ROI 联动 + 接力换算 | IOP + IOPParity |
| T4 profile browser | **+4..6** | 搜索/排序/低置信标注/选型 commit | App |
| T5 键族收口 | **+2** | zh-audit 双 PASS + 键族断言 | App |
| T6 收口 | **0** | docs + Project.swift + tuist generate | — |
| **合计** | **+18..28** | 起算基 = LENS-01 终态 | 五新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **auto 生效域 = notApplicable 唯一**（D-LENS-1）；开关
   `lensfun.autoApply` 默认 false。
2. **scale 补偿 + 接力 crop；crop_bounds/CIRCLE 不采纳**（D-LENS-5）。
3. **vignetting 纳入三 toggle，默认 on**（D-LENS-7）。
4. **kernel 单 pass 零结构改**（X5）——scale = 采样坐标标量。
5. **40 分档仅 browser 排序提示**（D-LENS-4 延续——browser 低置信标注）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/lens-01-lensfun/CONTEXT.md`（D-LENS-1/-5/-7 + X5/X6
  + 红线 15 条）
- `.work/gsd/phases/lens-01-lensfun/RESEARCH.md` §Route Decision Matrix
  吸收件 2 / §Geometry Pipeline Seam / §UI-UX / §Plan Split L2 行
- RawLab `lutools/src/core/lens_correction.cpp:196-247`（auto-crop 二分
  正本——GPL 移植体）+ `lens_correction.h`（状态机对照）
- Alcedo `lens_calibration_resolver.hpp:36-51`（apply_*/use_user_scale_
  语义对照）
- `.work/LESSONS.md` L041 + AGENTS.md M2-5 节（seeder/注入式 defaults 先
  例）+ M3-1 节（D-H1 拖拽三件 + KD-4）

---

## T1 — enable + per-correction 三 toggle（Alcedo apply_* 对齐，D-LENS-7）

> 现状 enable = source 三态兼职（缺口表行 3）——补独立 enable +
> distortion/TCA/vignette 分开关。

**read_first**：`RESEARCH.md` §UI-UX §2 段 + Alcedo `LensCorrectionSettings`（:36-51 对照）；`LensModule.swift` Params/中性谓词/resolveUniforms 域；CONTEXT §X5 前置（系数族门控位置 = resolve 后、uniforms 前）。

- **action**：
  1. `Params` additive：`enabled: Bool?`（nil = true）+
     `applyDistortion/applyTCA/applyVignette: Bool?`（nil = true）——
     encodeIfPresent 零漂移专测随批。
  2. 系数族门控：resolve 结果 → toggle 门控（关 = 该族系数归零：畸变
     dc1..4 / TCA 六项 / 渐晕 vk1..3）——纯函数 `gated(resolve, toggles)`
     可测形态；中性谓词扩展 = `!enabled || 全族归零`。
  3. 面板 §2：enable 总开关 + 三 toggle（D-H1 拖拽三件 + 单 discrete
     commit，键族 `panel_lens_*` 尾块）。
  4. 测试：门控组合表驱动（2³ toggle × on/off）+ 中性谓词例 + 默认
     params 零漂移负测 + toggle off 族归零后 kernel 输入断言。
- **验收标准（机检）**：
  - 构建绿；默认 params encode == 旧 JSON 逐字节（零漂移专测在册）。
  - grep：三 toggle 字段恰一声明；`gated(` 纯函数恰一处；中性谓词含
    enabled 臂。
  - 既有 LensParityTests 零回归（默认 toggle 全 on = 现行为恒等——负测
    在册）。
- **commit**: `feat(lens02): add enable and per-correction switches to lens params`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（additive nil = 旧行
  为恒等）；偏差（门控落点）= DECISIONS 申报；**禁改 source 三态语义**
  （off/manual/lensfun 是系数来源面，与 enable 正交）；**禁让 toggle 影
  响 manual 滑杆参数存储**（门控在 resolve 后）。

## T2 — auto-apply 开关（D-LENS-1，raster 域生效）

**read_first**：`RESEARCH.md` §OQ-1 + §Mutex 三态行为表；CONTEXT D-LENS-1 + 红线 11；`LensModule.reloadDefaults`（T1 后形态）；LutLibraryStore 注入式 defaults 先例（AGENTS.md M2-5）。

- **action**：
  1. UserDefaults 键 `lensfun.autoApply`（Bool 默认 false）；读法 =
     注入式（`LensModule` 侧 static reader + init 注入缝——测试可注；
     面板/设置消费点零 UserDefaults 直读）。
  2. `reloadDefaults` auto 臂：`autoApply && embeddedGeometry ==
     .notApplicable && lensKey 非空` → source = .lensfun（匹配在 process
     期 memo 路径，miss = identity 现状）；detected/unknown = 硬守卫恒
     不触发。
  3. 面板 §2 尾部 auto-apply toggle（会话可见 + 持久写）；设置面归属 =
     LENS-03 §5 数据管理段一并（本 plan 只落面板臂）。
  4. 测试：生效域表驱动（notApplicable×on → 触发；detected/unknown×on
     → 不触发；off → 不触发）+ 注入读法断言。
- **验收标准（机检）**：
  - 构建绿；grep：`lensfun.autoApply` 键面恰一处声明 + reader 恰一处
    `\.standard` 直读（其余零直读）。
  - 硬守卫测试在册（detected/unknown 双负例）。
  - 默认（键缺席）= false = 现行为（reloadDefaults 默认 .off 恒等负测）。
- **commit**: `feat(lens02): add opt-in auto-apply for raster documents`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（reader 形态/
  面板落位）= DECISIONS 申报；**禁扩生效域到 detected/unknown**（D-LENS-1
  ——发现 = 停手上报）；**禁自动网络动作**（auto-apply 只用已装 DB）。

## T3 — scale（auto 二分移植 + user 滑杆 + kernel 标量 + 接力 crop）（D-LENS-5，X5）

> 本 plan 唯一 kernel 触碰点：采样坐标 ×1/scale 单标量；投影零触。

**read_first**：`RESEARCH.md` §Geometry Seam scale 折算节 + §OQ-5；RawLab `lens_correction.cpp:196-247`（二分正本——GPL 移植体逐行对照）；`LensKernels.metal:20-50`（半径约定/求值序头注释——scale 语义与半径约定一致性必核）；`LensModule.modifyROIIn`（边框点同步缩）；CONTEXT §X5 + 红线 2/3。

- **action**：
  1. GPL 移植 `LensAutoCrop.swift`（IOP）：`minimumScale(warp 边框映射
     函数, frame) -> Float?`——四边 inside 测试（全 RGB footprint）+
     zoom ×1.25 粗探至 8 + 18 轮二分 + ×1.00001 余量；超 8 = nil
     （UnsupportedInput 语义）；文件头 = RawLab 版权 + 修改标注（§X8）。
  2. `LensWarpUniforms` += `scale: Float`（默认 1.0，纯尾插 + 对齐复
     核）；kernel 采样坐标 `×1/scale`（半径约定零改——面核头注释）；
     `modifyROIIn` 边框点乘 1/scale 后再 AABB+2px。
  3. `Params` additive：`autoScale: Bool?`（nil = true）+ `userScale:
     Float?`（nil = 1.0）；resolved scale 折算 = auto ? LensAutoCrop :
     userScale（auto 失败回落 1.0 + readout 标注 unsupported）。
  4. 面板 §3：auto toggle + user 滑杆（D-H1）+ resolved readout + 「接
     力 crop」按钮（resolved scale ≠ 1 时可用）——换算建议裁切框填入
     Crop 面板既定缝（EditorAreaView/CropPanel 落点随 actual 申报）。
  5. 测试：二分纯函数 golden（合成 warp 已知最小 scale 例 + 超 8 nil
     例 + 余量断言）+ kernel scale golden（IOPParity——scale=1 恒等 +
     scale=1.25 采样域收缩对照，合成参考 gen_fixtures.py 扩节）+ ROI
     联动断言 + 接力换算纯函数例。
- **验收标准（机检）**：
  - 构建绿；`LensKernels.metal` diff = scale 采样一处（hunk 面核 +
    头注释半径约定零改）。
  - LensAutoCrop.swift 版权头三件套在位（grep RawLab/Modified/NOTICE
    指针）；DECISIONS 预登记移植件清单含本件。
  - scale=1 golden 恒等（默认中性零行为门）；scale golden 门内（1e-5
    warp 级）。
  - `crop_bounds`/`CIRCLE` 零命中（D-LENS-5 机检）。
- **commit**: `feat(lens02): add auto and user scale with rawlab bisection autocrop`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（scale=1 默认 = 零行
  为差）；偏差（uniforms 尾插序/接力缝落点）= DECISIONS 申报；**禁改半
  径约定与求值序**（头注释钉死面）；**禁内嵌裁切矩形**（D-LENS-5）；
  **禁无 fence 计时**（本任务如带 perf 观察 = L014 fence，正式 probe 归
  LENS-04）。

## T4 — profile browser（§4 段，Apply/Clear 退役终形）

**read_first**：`RESEARCH.md` §UI-UX §4 段 + §Auto-Detection 阈值节；RawLab `lens.chooser` 形态（搜索 + 候选 + matched 置顶）；`LensPanelView.swift` §3 现状（Apply/Clear :240-256）；CONTEXT §X6；T3 后面板五段缺 §4/§5。

- **action**：
  1. `LensProfileBrowser` 模型（App 侧可测纯模型）：搜索词 →
     `LensfunMatch.modelScore` 全库打分排序 → 候选列表（matched 置顶 +
     score 档标注；40 分档 = 「低置信」标注，不自动入选语义维持）；
     选型 = commit（source=.lensfun + lensKey 置选型 model + 触发
     snapshot-ready 状态——快照持久化 = LENS-04，此处保持 memo 路径）。
  2. View 薄壳（搜索框 + List + 置顶/低置信标注 + 选型动作）——
     body 零业务逻辑。
  3. Apply/Clear 按钮退役：Apply 语义由选型吸收；Clear = 回 manual 保
     留为 browser 空/禁用臂（终形 DECISIONS 申报）。
  4. 测试：排序/置顶/低置信标注/选型 commit/搜索去抖纯面。
- **验收标准（机检）**：
  - 构建绿；grep：`applyMatch()` 旧按钮 action 零命中（退役完成；
    Clear 语义新形态 DECISIONS 在案）；browser 模型恰一文件。
  - body 零全库打分（打分在模型层 + 缓存——browser 打开时一次，输入变
    化去抖重跑）。
  - `--bundle App` 定向零回归；T5 键族一并收口。
- **commit**: `feat(lens02): replace apply/clear with profile browser and confidence tiers`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 Apply/Clear 态）；
  偏差（Clear 终形/列表虚拟化面）= DECISIONS 申报；**禁在 browser 里改
  匹配阈值语义**（≥60/40 档 = LENS-01 定值）；**禁选型即写 snapshot**
  （LENS-04 域——本 plan 选型后 resolve 仍走 memo）。

## T5 — 键族收口 + 登记

- **action**：xcstrings 新键尾块纯插入（§2/§3/§4 全部新键，一次收口）；
  `zh-audit.py --check` + `--self-test` 双 PASS 留档；AGENTS.md
  UserDefaults 键族节追加 `lensfun.autoApply` 登记（M2-2 键族节格式）；
  DECISIONS 键清单终表。
- **验收标准（机检）**：双 PASS 输出留档；动态键/插值禁形零命中；
  AGENTS.md 登记行在库；历史键字节零触碰（xcstrings diff = 纯插入面
  核）。
- **commit**: `docs(lens02): register lens panel key family and autoapply default`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；零偏差面（键名清单
  差 = DECISIONS 申报）。

## T6 — 收口（Project.swift + tuist generate + docs）

- **action**：五个新测试文件入数组（IOP ×3 / IOPParity ×1 / App ×1）；
  `tuist generate` 恒末位；`--bundle IOP` + `--bundle IOPParity` +
  `--bundle App` 定向全绿；ΔN 对账（+18..28）；SUMMARY/DECISIONS 落盘；
  **C 档停汇报**（并行波放行点）。
- **验收标准（机检）**：定向三 bundle 全绿；Project.swift diff = 恰五
  行；SUMMARY/DECISIONS 在库。
- **commit**: `test(lens02): register lens scale and browser suites and close out l2`
- **回滚与偏差申报要求**：ΔN 越带 = SUMMARY 申报；禁漏 tuist generate。

---

## 风险与回退

- **kernel scale 触碰面**：单标量改动但 warp 是空间算子——scale=1 恒等
  golden 是回归底线；半径约定/求值序头注释面核必做（T3 验收）。
- **auto-crop 二分成本**：18 轮二分 × 边框采样 = CPU 侧每 commit 一次
  （非 per-frame）——量级毫秒级（RawLab 同构）；如实测超窗 = DECISIONS
  申报采样步长放宽（禁改语义）。
- **browser 大库列表**：~数千条目打分一次 ~可接受（L1 memo 同源）；列
  表虚拟化如缺 = DECISIONS 申报 LazyVStack 面。
- **接力 crop 落点**：Crop 面板建议框缝如现结构无直填口 = 最小缝新增
  （CropPanel 建议值 setter），禁改 CropModule 解析语义（24.5 域零触）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH 缺口表「enable/scale」两行 ↔ T1/T3；
   auto-detection UX 面 ↔ T2/T4。
2. **OQ 兑现核**：D-LENS-1（T2 硬守卫双负例 + 恰一键）/ D-LENS-5（接
   力 + crop_bounds 零命中）/ D-LENS-7（T1 三 toggle 含 vignette）。
3. **红线核**：LensKernels.metal 恰一处 diff；LensAutoCrop 版权头三件
   套；UserDefaults 恰一键 + 零 body 直读；scale=1 恒等 golden。
4. **SC 可机检性**：同 LENS-01 惯例。

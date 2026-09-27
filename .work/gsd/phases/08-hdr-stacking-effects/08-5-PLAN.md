---
phase: 8
plan: "08-5"
title: "dehaze + text overlay + Phase 收口签核（W3）：dehaze 14.0（四 kernel 直译 + A0/distance_max preview 算 full/export 复用 + guided filter 取 box 两遍近似裁决 + 合成雾反演 golden）+ text overlay 66.7（新非 dt 行只增不改 + CoreText→MTLTexture + YiyinFontStore 复用 + 层蒙版资格 <70.0；yiyin watermark 77.0 零改动）+ LUT HDR 域精度判定（12-5 移交消费，1e-3 断言写死）+ HDR-04 验证矩阵收口 + 全 Phase 验证 + VALIDATION 签核（C 档第 3 停）"
wave: 3
depends_on: ["08-3", "08-4"]
autonomous: true
requirements: [IOP-FX-04, IOP-FX-05, IOP-HDR-04]
files_modified:
  - LightamerIOP/Sources/Dehaze/DehazeModule.swift              # 新建：strength(−1..1,0.2)/distance(0..1,0.2)/adaptive 参数面（hazeremoval.c:66-67,576）+ A0/distance_max preview 管线算 + full/export 复用（模块内 cached + 输入 hash 校验——dt gui_data 同步坑同形规避）+ 窗口 w1=2+ceil(4·wscale)/w2=3+ceil(6·wscale)
  - LightamerIOP/Sources/Dehaze/DehazeKernels.metal             # 新建：四 kernel 直译 hazeremoval.cl:22-163（box_min_x/y + box_max_x/y 滑动 min/max + transision_map + dehaze）+ guided filter **v1 = box mean 两遍近似**（planner 裁决，见 T1）+ 还原式 t_min=clamp(exp(−d·dmax),1/1024,1)、out=(in−A0)/max(t,t_min)+A0
  - LightamerIOP/Sources/Dehaze/DehazeReference.swift           # 新建：float64 A0/t/还原全链参考实现（golden 正本）
  - LightamerIOP/Sources/TextOverlay/TextOverlayModule.swift    # 新建：内容(多行)/字体/字号/颜色/位置(归一 xy)/旋转/不透明度参数面 v1（描边/阴影不进 v1）+ 纹理缓存按 StableHash(textParams) 键 + iopOrder 66.7
  - LightamerIOP/Sources/TextOverlay/TextOverlayKernels.metal   # 新建：alpha 合成 kernel（CoreText 灰度+alpha 位图 → MTLTexture 采样；uniform 颜色/旋转/不透明度；无色彩矩阵——COLOR-2 不涉及）
  - LightamerIOP/Sources/TextOverlay/TextRasterizer.swift       # 新建：CoreText 排版 → 灰度+alpha 位图 → MTLTexture（排版/字体管理复用 YiyinFontStore；渲染目标不复用 YiyinTextRenderer 的 CGImage 出图）
  - LightamerCore/Sources/Foundation/V50Order.swift             # +1 行 textOverlay 66.7（66.5 skinSmooth 与 67.0 splittoning 空隙；非 dt 行纪律：只增不改）
  - LightamerIOP/Sources/Registry.swift                         # populate +2（dehaze/textOverlay）
  - App/Sources/Lightamer/UI/Inspector/DehazePanelView.swift    # 新建：strength/distance/adaptive（D-H1 三件套）
  - App/Sources/Lightamer/UI/Inspector/TextOverlayPanelView.swift # 新建：文本/字体/字号/颜色/位置/旋转/不透明度（D-H1 三件套）
  - App/Sources/Lightamer/UI/Inspector/IOPPanelProvider.swift   # +2 席（L010 identifier）
  - Resources/Localizable.xcstrings                             # dehaze/textOverlay zh+en 键（L025）
  - Tests/LightamerTests/V50OrderTests.swift                    # strip-to-93 钉同步 +1 行（textOverlay 66.7）
  - Tests/LightamerTests/DehazeTests.swift                      # 新建：合成雾反演容差/窗口式/A0 复用 hash 失效/float64 比对
  - Tests/LightamerTests/TextOverlayTests.swift                 # 新建：位置/旋转/不透明度解析断言/纹理缓存键/层蒙版局部化
  - Tests/LightamerTests/HDRPipelineMatrixTests.swift           # 扩：lut3d HDR 域列 + LUT 1e-3 精度判定断言 + preview 预算复核（08-1 建基的收口）
  - .work/gsd/phases/08-hdr-stacking-effects/perf.md            # 全 Phase 汇总节（各 plan 对账 + preview float32 预算复核结论 + EDR drawable ≈62MB 注记）
  - .work/gsd/phases/08-hdr-stacking-effects/08-5-SUMMARY.md
  - .work/gsd/phases/08-hdr-stacking-effects/08-5-DECISIONS.md
  - .work/gsd/phases/08-hdr-stacking-effects/08-VALIDATION.md   # 签核（C 档第 3 停）
  - .work/gsd/phases/08-hdr-stacking-effects/08-DISCUSSION-LOG.md # 终节（SC 证据指针 + 移交/遗留对表）
  - REQUIREMENTS.md                                             # IOP-HDR-01..05 / IOP-FX-01..05 翻账 Delivered（C 档第 3 停内，晨审追认）
  - TODO.md                                                     # Phase 8 收口
  - LESSONS.md                                                  # 如踩坑
---

# Plan 08-5 — dehaze + text overlay + Phase 收口签核（W3）

> 背景：W3 收尾 plan——两件效果 iop（dehaze FX-04 / text overlay FX-05）+ 三笔收口义务：①12-5
> 移交④/遗留#4 的 **LUT HDR 域精度判定**（rgba16Float texture3d 存储在 HDR 域样本点的 1e-3 相对
> 容差实测，判定写死进测试断言——D7 升格预案启用与否不留人肉判断）；②**HDR-04 验证矩阵收口**
> （08-1 T7 建基，本 plan 补 lut3d 列 + 真产物 preview 内存预算正式结论）；③**全 Phase 签核**
> （VALIDATION + REQUIREMENTS 翻账 + **C 档第 3 停**：VALIDATION 产出后停等用户过目）。
> text overlay 槽位 = **66.7 新非 dt 行**（66.5 skinSmooth 先例纪律：只增不改 + V50OrderTests
> strip-to-93 钉同步）；`< terminalTailFloor` 70.0（`LayerCompositeDriver.swift:110`）→ 层蒙版资格
> = 与 yiyin `WatermarkModule`（77.0 终端段）的本质分工——**yiyin 77.0 零改动**（D-08-CONTEXT-9；
> ROADMAP SC#4「order 77」编写期冲突按需求原文裁决，晨审注意项已过目）。

## read_first

1. `.work/gsd/phases/08-hdr-stacking-effects/08-RESEARCH.md`——§10（dehaze 参数终表 + 数学直译表
   四 kernel + **A0 preview 管线共享坑**（dt gui_data + hash 同步——Lightamer 同形：模块内 cached +
   输入 hash 校验，否则 full ROI 内 A0 估计不稳）+ guided filter 取舍 + 窗口式 + 合成雾 golden）、
   §11（text overlay 槽位 66.7 推导 + 渲染路径 + 参数面 v1 + 层蒙版合成）、§13（HDR-04 验证矩阵
   终表 + LUT 精度结论 + preview 预算口径）、§14 总表 dehaze/textOverlay 两行、§16 R5（guided
   filter 工程量）
2. `.work/gsd/phases/08-hdr-stacking-effects/08-CONTEXT.md`——D-08-CONTEXT-8（dehaze 暗通道先验 +
   CLAHE 否决）、D-08-CONTEXT-9（FX-05 独立轻量 iop + 66.x 新槽 + yiyin 77.0 不动 + ROADMAP 冲突
   裁决——**晨审注意项**）、D-08-CONTEXT-4（HDR-04 验证矩阵 + 12-5 LUT 消费义务）、继承定案节
   （V50Order 非 dt 行纪律 + `.xmp` 红线）
3. `.work/gsd/phases/08-hdr-stacking-effects/08-1-PLAN.md` T7 + `Tests/LightamerTests/
   HDRPipelineMatrixTests.swift`（08-1 建基的矩阵文件——本 plan T3 在其上扩列收口）
4. Darktable 移植正本（只读）：`src/iop/hazeremoval.c`（:66-67 参数 / :576 adaptive / :576-583 窗口
   式 / :~400-447 A0/distance_max / :595-645 preview-full 同步坑 / :678-692 还原）+ `data/kernels/
   hazeremoval.cl:22-163`（box_min/max_x/y + transision_map + dehaze 四 kernel）；`src/iop/watermark.c`
   （1561 行——仅参数结构参考，逻辑不复用）
5. Yiyin 复用面：`LightamerIOP/Sources/Yiyin/YiyinFontStore.swift`（字体管理复用）+
   `YiyinTextRenderer`（**只复用排版/字体管理面，渲染目标 CGImage 不复用**——research §11.2 核对
   结论）；`LightamerCore/Sources/Foundation/V50Order.swift:146-165`（66.0-67.0 邻域 + 66.5 非 dt
   行先例）+ `Tests/LightamerTests/V50OrderTests.swift`（strip-to-93 钉）
6. `LightamerIOP/Sources/Lut3d/CubeLutParser.swift:10-14`——DOMAIN remap 归一（HDR 域 .cube 采样
   坐标）+ `LightamerCore/Sources/Pipe/PipeResolution.swift:36-39`（preview float32 ≈70MB/平面注记
   ——T3 预算复核正本）
7. `LESSONS.md` L010/L013/L014/L020/L025/L031（全套同前 plan）+ `AGENTS.md`（Phase 执行模型 +
   暂停机制 + **C 档门控第 3 停**）+ `.work/GOAL-STATE.md`（Phase 8 续接点）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，
  Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前。
- **不 push**；**构建勿加 `-derivedDataPath`**；**每新建源/测试/面板文件后跑 `tuist generate`**（11-03
  教训）。
- **回归基线 = 1553/9skip/0fail（13-3 后基线）+ 08-1/08-2/08-3/08-4 新增**（以各 SUMMARY 终值为
  准）；每任务全套 suite 绿；**全 Phase 终轮 = 1553 + 全 Phase 新增，0 fail**。**在案 flake 归因
  条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 负载型 flake 若现，隔离 ×3 归因单列入 SUMMARY，
  不计违约。
- **L031 路由红线（本 plan Metal 面适用）**：dehaze 四 kernel/级联 blur 复用面/textOverlay 合成
  kernel 一切 GPU 提交走 `MetalContext.makeRoutedCommandBuffer()`（`MetalContext.swift:524`）唯一
  路由获取点；A0 统计读回守 L014 fence（drain()）；identity 快速路径中性种子恒等逐字节。
- **guided filter 取舍 = planner 裁决（写死，worker 不得改道）**：v1 用 **box mean 两遍近似替代
  guided filter**（kernel 表少一个复杂件；R5 消解）——视觉差记 Manual-Only 对比项；guided 全移植
  = Reversibility 后补位（DECISIONS 记录升级缝）。float64 参考实现与 kernel **同式**（同为 box
  近似形），parity 闭环不被该取舍破坏。
- **V50Order 非 dt 行纪律**：textOverlay 66.7 只增不改；`V50OrderTests` strip-to-93 钉同步 +1 行；
  禁动任何既有行序。
- **yiyin 77.0 零改动红线**：`WatermarkModule`/Yiyin 面任何文件不在本 plan files_modified 集内；
  发现分工疑义停手登记，不得顺手改。
- **LUT 判定写死红线**：1e-3 相对容差断言进测试代码——超限 → 启用 D7 rgba32Float 升格预案（判定
  分支也在测试内表达），**禁**放宽容差或人肉豁免（L020 同源）。
- **perf 口径 = 只记不设门**：全 Phase 各 plan 实测对 research §0 表汇总对账（>2× 归因注记）；
  preview float32 预算复核结论落 perf.md（预期合并不进 preview 缓存面、预算零增；EDR viewport
  16F drawable ≈62MB @3008×1692×8B 注记）。
- **C 档第 3 停（本 plan 内执行）**：T5 VALIDATION + REQUIREMENTS 翻账产出后**停等用户过目**
  （晨审可推翻翻账）；夜间授权先例可循但用户随时可推翻——停的位置 = 翻账 commit 之后、后续
  phase 推进之前。
- RESEARCH/CONTEXT 未覆盖细节（A0 百分位参数、雾 fixture 场景参数集、overlay 字体列表来源、面板
  分组）标注**执行期决策**入 `08-5-DECISIONS.md`，不臆造。

## Tasks

### T1 dehaze 14.0：四 kernel + A0 preview 复用 + box 近似裁决 + 雾 golden

- **action**
  1. 新建 `LightamerIOP/Sources/Dehaze/` 文件对三件。参数面 = `hazeremoval.c:66-67,576`：
     `strength`(−1..1,0.2)/`distance`(0..1,0.2)/`adaptive`；槽位 14.0 既有（`V50Order.swift:48`，
     零表迁移）。
  2. **四 kernel 直译**（`hazeremoval.cl:22-163`）：`box_min_x/y` + `box_max_x/y`（暗通道/亮通道
     滑动 min/max，O(N)）→ `transision_map`（t = 1 − min_c(p_c/A0_c)·strength，:338-352）→ box min
     细化（w1）→ **box mean 两遍近似替代 guided filter**（w2——planner 裁决写死，见纪律节）→
     `dehaze` 还原（t_min = clamp(exp(−distance·distance_max), 1/1024, 1)；out = (in−A0)/max(t,
     t_min)+A0，:678-692）。窗口：w1 = 2+ceil(4·wscale)、w2 = 3+ceil(6·wscale)、wscale = adaptive ?
     roi_in.scale/pipe.iscale : 1（:576-583）。
  3. **A0/distance_max 形状**：preview 管线算 + full/export 复用（模块内 cached 值 + 输入 hash
     校验失效——dt :595-645 gui_data 同步坑同形规避，research §10.2 定案）；统计读回 L014 fence。
  4. `DehazeReference.swift` float64 全链（A0/t/还原，与 kernel 同 box 近似式）。
  5. **合成雾 golden**（§10.4）：已知 A0、已知 t 场、线性合成 `I = J·t + A0(1−t)` → 反演
     `|Ĵ−J|` 容差断言（容差数值执行期决策钉 DECISIONS；多场景参数集）。scene-referred 零域翻译
     断言（线性域直挂 14.0 位）。
  6. `DehazePanelView`（strength/distance/adaptive）+ Provider +1 席 + zh/en；Registry 注册 dehaze。
- **证据**：`DehazeTests`——反演容差 golden / 窗口式 w1/w2 数值断言 / A0 复用 hash 失效（改输入
  → 重算）/ float64 比对 / CLAHE 不存在断言（防止legacy 槽位混淆——clahe 71.0 非 v50 表内）/
  注册 14.0。

### T2 text overlay 66.7：新非 dt 行 + CoreText→MTLTexture + 层蒙版资格

- **action**
  1. `V50Order.swift` +1 行 `("textOverlay", 66.7)`（66.5 与 67.0 空隙内，避开 66.5 邻近——
     research §11.1 推导）；`V50OrderTests` strip-to-93 钉同步 +1 行；禁动既有行。
  2. 新建 `LightamerIOP/Sources/TextOverlay/` 三件：`TextRasterizer`（CoreText 排版 → 灰度+alpha
     位图 → `MTLTexture`；字体管理复用 `YiyinFontStore`，排版惯例对位——渲染目标不复用
     YiyinTextRenderer 的 CGImage 出图）+ `TextOverlayKernels.metal`（alpha 合成 kernel：uniform
     颜色/旋转/不透明度；无色彩矩阵）+ `TextOverlayModule`（iopOrder 66.7 < 70.0 → 层蒙版资格
     天然成立；纹理缓存按 `StableHash(textParams)` 键，PSO 不变）。
  3. 参数面 v1：内容（多行）/字体/字号/颜色/位置（归一 xy）/旋转/不透明度；**描边/阴影不进 v1**
     （SC#4 无字面要求，additive 位）。
  4. `TextOverlayPanelView` + Provider +1 席 + zh/en；Registry 注册 textOverlay。
  5. **yiyin 分工断言**：`WatermarkModule` 77.0 终端段零改动（diff 边界自证）；两者可同链共存
     （66.7 非终端 + 77.0 终端）用例。
- **证据**：`TextOverlayTests`——位置/旋转/不透明度解析断言（合成位图已知角度/位移采样）/纹理
  缓存键 MISS/HIT / 层蒙版局部化（蒙版外零改动）/ strip-to-93 +1 行钉绿 / yiyin 77.0 零改动
  （V50OrderTests 全绿 + diff 边界声明）。

### T3 LUT HDR 域精度判定 + HDR-04 验证矩阵收口

- **action**
  1. **LUT 精度判定**（12-5 移交④/遗留#4 消费）：12-5 tetrahedral golden 面对 **HDR 域样本点**
     实测——`DOMAIN_MAX>1` 的 `.cube`（输出 >1.0）经 `CubeLutParser` DOMAIN remap + rgba16Float
     texture3d 采样，逐样本点相对误差断言：**任一点 >1e-3 → 断言红 = 启用 D7 rgba32Float 升格
     预案**（判定分支在测试内表达：升格路径可编译可达 + 结论翻转只需改常量）；全部 ≤1e-3 →
     rgba16Float 默认达标定案（half ~5e-4 先例口径）。**判定写死，禁人肉豁免**。
  2. **HDR-04 矩阵收口**（08-1 T7 建基上扩）：`HDRPipelineMatrixTests` 补 **lut3d 列**——合成
     float32 已知值 patch（0.001/0.5/1.0/4.0/16.0/65504 灰阶 + RGB 彩条）→ exposure → filmicrgb →
     sigmoid → toneequal → **lut3d（HDR 域 .cube）** 全链 parity；真合并产物（08-1 fixture 32F
     TIFF）→ preview 管线行正式结论。
  3. **preview float32 预算复核**：2560px long-edge float32 ≈70MB/平面参考实测 + EDR viewport
     16F drawable ≈62MB 注记 → perf.md；预期结论：合并不进 preview 缓存面新类，enforceBudget
     五档零改，预算零增（若超 → 归因注记 + 阈值注入缝评估，不设门）。
- **证据**：`HDRPipelineMatrixTests` 扩段全绿（LUT 判定断言 + 矩阵 lut3d 列）；perf.md 复核结论
  节；判定结论一行（16F 达标 or 启用 32F 升格）写入 SUMMARY + DECISIONS。

### T4 全 Phase 终轮回归 + perf 汇总 + SUMMARY + DECISIONS

- **action**：**全 Phase 终轮**（基线 **1553/9skip/0fail** + 08-1..08-4 全部新增 + 本 plan 新增，
  0 fail；flake 条款见纪律节）；`perf.md` 全 Phase 汇总节（各 plan 秒表/参考数 vs research §0 表
  对账 + preview 预算结论 + 手感类 Manual-Only 汇总指针）；TODO.md 08-5 勾选 + Phase 8 收口检查；
  `08-5-SUMMARY.md`（任务表/commit 表/证据/全 Phase 战果汇总）；`08-5-DECISIONS.md`（LUT 判定
  结论、雾反演容差、A0 百分位、字体来源、面板分组、其余执行期决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（1553 + 全 Phase 新增 → N，0 fail）；perf.md 汇总节；SUMMARY + DECISIONS
  落盘。

### T5 VALIDATION + 翻账 + C 档第 3 停

- **action**
  1. `08-VALIDATION.md`：status/nyquist frontmatter + **SC#1-4 逐条证据指针**（SC#1 → 08-1 E2E/
     golden；SC#2 → 08-3 T5；SC#3 → 08-4 T4 + Manual-Only 行；SC#4 → 08-2/08-5 T1/T2 + order-77
     冲突裁决注记）+ Per-Task Map + 缺陷处置表 + **Manual-Only 汇总**（XDR 目检/外接 HDR/
     bloom 手感/dehaze box 近似视觉差/灰卡两点标定/N=3 de-ghost 局限）。
  2. `08-DISCUSSION-LOG.md` 终节：SC 证据指针 + 移交/遗留对表（Phase 11 HDR 导出深度移交位 +
     Phase 8-yiyin 遗留对账）。
  3. **REQUIREMENTS 翻账**：IOP-HDR-01..05 / IOP-FX-01..05 → Delivered（证据指针列）。
  4. **C 档第 3 停执行记录**：翻账 commit 后停等用户过目 VALIDATION——后续 phase 推进待用户示意
     （本 plan 范围内不再派新任务）。
- **证据**：VALIDATION 落盘 + REQUIREMENTS 翻账 diff + 停等记录（GOAL-STATE 续接点由 orchestrator
  更新，本 plan 只交付材料）。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| dehaze | 雾反演 golden / 窗口式 / A0 hash 失效 / 14.0 注册 | `Scripts/test-direct.sh 'DehazeTests'` |
| text overlay | 解析断言 / 缓存键 / 层蒙版 / 66.7 钉 / yiyin 零改动 | `Scripts/test-direct.sh 'TextOverlayTests'` + `'V50OrderTests'` |
| LUT/矩阵 | 1e-3 判定写死 / lut3d 列 parity / preview 预算复核 | `Scripts/test-direct.sh 'HDRPipelineMatrixTests'` |
| 全 Phase 回归 | 0 fail（1553 + 全 Phase 新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |
| 签核 | VALIDATION + 翻账落盘 + C 档第 3 停记录 | 查 `08-VALIDATION.md` + REQUIREMENTS diff |

## 验收标准（Acceptance）

- [ ] dehaze 14.0：四 kernel 直译（滑动 min/max + transision_map + 还原式）+ 窗口式 w1/w2 +
      A0/distance_max preview 算 full/export 复用（cached + 输入 hash 校验）+ **box 两遍近似裁决
      遵守** + 合成雾反演 golden（float64 同式双写）+ CLAHE 零混入 + 面板四件套
- [ ] text overlay 66.7：V50Order 新行只增不改 + strip-to-93 钉 +1 + CoreText→MTLTexture
      （YiyinFontStore 复用）+ StableHash(textParams) 纹理缓存 + 层蒙版局部化 + 描边/阴影不进 v1 +
      yiyin 77.0 零改动 + 面板四件套
- [ ] LUT HDR 域精度判定：HDR 域样本点 1e-3 相对容差断言写死 + 升格预案分支可编译可达 + 结论
      入 SUMMARY/DECISIONS
- [ ] HDR-04 验证矩阵收口：lut3d 列 parity（已知值 patch 全链）+ 真合并产物 preview 行 + preview
      float32 预算复核结论落 perf.md
- [ ] 全 Phase 终轮 0 fail（1553 + 08-1..08-5 新增）；perf.md 全 Phase 汇总节对账
- [ ] `08-VALIDATION.md`（SC#1-4 证据指针 + Per-Task Map + Manual-Only 汇总）+ 08-DISCUSSION-LOG
      终节 + REQUIREMENTS 翻账 Delivered ×10；**C 档第 3 停执行记录在案**（停等用户过目）
- [ ] 每任务独立提交 + 边界查 config 开关；不 push；fixture 禁 UNITEK；SUMMARY + DECISIONS 落盘

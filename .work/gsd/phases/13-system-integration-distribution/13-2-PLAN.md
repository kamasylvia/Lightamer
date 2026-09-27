---
phase: 13
plan: "13-2"
title: "色彩完备（COLOR-02/03，D-COL3 预留位兑现）：BPC 可达性探针先行（CGColorConversionInfo intent/BPC 开关结论落档）+ 软打样 proof 段（coordinator 级 display 腿 runtime override、colorout 上游插入、ColorSync/CG 精确腿、永不进 Params/history/export）+ OOG gamut check 黑裁剪 + proof UI 面（toggle/picker/快捷键）+ 多显示器自动切换（通知 + window↔screen 追踪 → 既有 DisplayProfile.resolve/翻键）+ 手动 per-display 覆盖（Settings + .colorSyncFallback exact-TRC 兑现）+ F-12-5-2 dt-GUI golden 同轮（Manual-Only）"
wave: 2
depends_on: ["13-1"]
autonomous: true
requirements: [COLOR-02, COLOR-03]
files_modified:
  - .work/gsd/phases/13-system-integration-distribution/13-2-probes.md      # 新建：BPC 可达性探针报告（CGColorConversionInfo rendering intent 支持 + BPC 公开开关存在性；结论决定 proof 段形状）
  - LightamerCore/Sources/Foundation/SoftProofProfile.swift                  # 新建：proof 状态值类型（printer ICC 引用 + intent + BPC + gamut check 开关）——per-run override 语义，永不进 Params/history/export
  - LightamerCore/Sources/Pipe/Terminal/SoftProofStage.swift                 # 新建：proof 段变换——Rec2020 → 打印机 ICC（relative colorimetric + BPC 按 T1 结论）+ gamut check 黑裁剪；ColorSync/CG 精确腿
  - LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift                 # 如需：proof override 消费位（displayProfileOverride :128 / exportTargetOverride :143 双 socket 同形扩展；零改则不触）
  - App/Sources/Lightamer/State/PipeCoordinator.swift                        # proof override 注入面 + NSApplicationDidChangeScreenParametersNotification 订阅 + window↔screen 追踪 → per-window resolve re-commit（既有 NSScreen 触点旁）
  - App/Sources/Lightamer/UI/StatusBar.swift                                 # proof toggle / 打印机 profile picker / gamut check 开关挂点（视口工具条形态执行期决策）
  - App/Sources/Lightamer/UI/SettingsView.swift                              # 多显示器手动 per-display profile 选择（DisplayProfile.swift:31-32 预告落位）
  - Tests/LightamerTests/SoftProofStageTests.swift                           # 新建：proof OFF 逐字节直通 / proof ON 不进 history+export / OOG golden / BPC 行为锚
  - Tests/LightamerTests/MultiDisplayProfileTests.swift                      # 新建：切换仅 terminal 键翻转 / 上游平面存活 / 双窗双 profile 独立 / 手动覆盖 ICC 字节 identity
  - .work/gsd/phases/13-system-integration-distribution/13-2-SUMMARY.md
  - .work/gsd/phases/13-system-integration-distribution/13-2-DECISIONS.md
  - .work/gui-acceptance/                                                    # F-12-5-2 dt-GUI 对照截图证据
  - TODO.md                                                                  # 13-2 勾选 + Manual-Only 台账 F-12-5-2 关闭
  - LESSONS.md                                                               # 如踩坑
---

# Plan 13-2 — 色彩完备（W2，与 13-3 并行波）

> 背景：兑现 Phase 2 留好的 D-COL3 预留位（`ColorOutModule` Params.outputProfile/intent reservation + `DisplayProfile` 头注释预告），不是新管线（D-13-CONTEXT-4/5）。
> 三条主线：① **软打样（COLOR-02）**——「看」不是「改」：proof 状态是 coordinator 级显示腿 runtime override（形状同 `displayProfileOverride`/`exportTargetOverride` 双 socket 的 per-run data 先例），proof 段插在 colorout 上游（Rec2020 → 打印机 ICC，relative colorimetric + BPC），永不进 history stack / export 链；引擎 = ColorSync/CG 精确腿（Metal 快路径 deferred）；OOG = gamut check 开关（黑裁剪）。**头项 = BPC 可达性探针**（唯一可能改变管线形状的未知数），结论落档后才许写 proof 段实现。② **多显示器（COLOR-03）**——解析/翻键/缓存三层全是 02-04 已交付底座，缺的只是事件面：通知 + window↔screen 追踪 → per-window `DisplayProfile.resolve` → 既有 terminal-segment invalidation 自动工作；手动覆盖进 Settings 顺带兑现 `.colorSyncFallback` exact-TRC 文档债。③ **F-12-5-2**（12 移交⑤）——dt-GUI golden 人工交叉对照随本批同轮做（同一色彩参考环境）。内部任务序刚性：T1 探针 → T2 proof 段 → T3 OOG → T4 UI → T5 自动切换 → T6 手动覆盖 → T7 dt-GUI 同轮 + 收口。

## read_first

1. `.work/gsd/phases/13-system-integration-distribution/13-CONTEXT.md`——D-13-CONTEXT-4（软打样五裁决：override 非 Params/proof 段位置/ColorSync 腿/BPC 探针/黑裁剪）、D-13-CONTEXT-5（多显示器三裁决：通知驱动/手动覆盖 Settings/多窗独立）、继承定案（L014/单窗口 L012/L031）、验证红线（软打样零回归专项/多显示器专项——逐条为本 plan AC 正本）
2. `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift`——:54-56 D-COL3 reservation / :79-87 OutputProfile 导出枚举（**与打印机 profile 语义不同不混用**）/ :90-95 RenderingIntent（:93-95 intent 注释 = 本 plan 兑现位）/ :101-109 Params 持久化位 / :76 exportTargetOverride socket / :128 displayProfileOverride / :58-61 SC#2 terminal variant 机制注释
3. `LightamerCore/Sources/Foundation/DisplayProfile.swift`——:31-32 头注释 Phase 13 预告（manual profile selection + printer/soft-proof）/ :53-82 resolve 四级匹配表 / :84-88 `current()` coordinator 注入注释（D-COL2 window-screen 语义延伸位）/ :104-123 stableID 折叠（terminal-segment invalidation）/ :136-151 `.colorSyncFallback` linearCGColorSpace workalike 注释（exact-TRC 文档债正本）
4. `App/Sources/Lightamer/State/PipeCoordinator.swift`——displayProfileOverride 注入点 + 既有 NSScreen 触点（通知订阅挂点）；`App/Sources/Lightamer/UI/EditorMTKView.swift`（EDR/显示腿 blit 消费端——proof 后内容如何上屏的语境）
5. `.work/gsd/phases/12-metadata-presets-lut/12-VALIDATION.md` Manual-Only 表 `F-12-5-2` 行（dt-GUI 侧 .cube golden 人工交叉对照规程输入）+ `12-DISCUSSION-LOG.md` 遗留对表 #5（dt golden 参考为 CPU float64 双写、L017 先例）
6. `App/Sources/Lightamer/UI/SettingsView.swift`（手动覆盖挂点）+ `App/Sources/Lightamer/UI/StatusBar.swift`（proof toggle 候选位）
7. `LESSONS.md` L014（GPU 读回 fence）/ L017（dt-cli 本 host 空间损坏——dt-GUI 人工对照原因）/ L021（overlay/视口观察层量化——proof ON/OFF 截图差分参照）/ L025（zh 键纪律）+ `AGENTS.md` + `.work/GOAL-STATE.md`（凭据阻塞项登记提醒义务）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**（GitHub/凭据面属 13-4，本 plan 零触碰）。
- **构建勿加 `-derivedDataPath`**；本 plan 无新 target/目录级新增（新增文件在既有 target 内），每新建源文件后照例 `tuist generate` 一次。
- **回归基线 = 1553/9skip/0fail**；每任务全套 suite 绿；收尾轮 = 1553 + 新增，0 fail。**flake 归因条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 负载型 flake 隔离 ×3 归因单列 SUMMARY，不计违约。
- **凭据阻塞项提醒义务**：执行中若知悉 Developer ID/AC API key/GitHub 仓仍未就位，SUMMARY + GOAL-STATE 阻塞节登记提醒（13-4 供件），本 plan 不消费。
- **软打样零回归是硬闸（执行期不得放宽）**：① proof OFF = 显示腿**逐字节直通**——既有渲染 golden 矩阵全绿为每任务前置；② proof ON 不改 history（history 无新项）、不进 export（导出 golden 逐位不变断言）、不写 sidecar（字节不变）；③ **BPC 探针结论落档（T1）之前禁止开写 proof 段实现**（T2 硬序）。
- **L031 声明**：proof 段走 ColorSync/CG 精确腿（CPU 侧 ICC 变换），**无新 Metal kernel/无新 GPU 提交面**——`makeRoutedCommandBuffer()` 红线预期不触；如执行中发现需要即停下报告，不得自建队列。
- **GPU/像素读回纪律**：proof ON/OFF 对比、OOG 判定等一切测试读回前 fence（L014）；截图差分走 L021 观察层量化口径。
- **GUI 走查标注**：真机双屏切换实测、dt-GUI 对照（T7）均**需解锁控制台（Manual-Only 候补）**——自动化腿能钉的全在单测钉死，观感/真双屏项登记 13-4 走查批或当场人工走查。
- **zh 键同步**：proof 面板/Settings 覆盖页新 UI 每键 zh 同批（L025，smoke 数字随 suite 报）。
- RESEARCH/CONTEXT 未覆盖细节（proof toggle 入口位置与快捷键、打印机 profile 最近记忆条数、OOG 黑裁剪实现域、通知去抖）标注**执行期决策**入 `13-2-DECISIONS.md`，不臆造。

## Tasks

### T1 BPC 可达性探针（头项，结论落档后才许 T2）

- **action**
  1. 探针程序（独立可跑，落真机本地盘）：`CGColorConversionInfo` 构造 face 下实测 ① rendering intent 全集（perceptual/relative colorimetric/saturation/absolute colorimetric）在 display↔printer ICC 对上的行为锚（输出像素差异可证 intent 生效）；② **黑点补偿（BPC）公开开关存在性**——CGColorConversion API 面逐键核查（header/文档/实测行为对照：同 profile 对 relative colorimetric ±BPC 期望差异样本），若 BPC 无公开开关 → 结论 = 黑点补偿在 proof 段内手做（输入黑点→输出黑点映射 LUT）或降级注记，两案皆入报告。
  2. **结论落档** `13-2-probes.md`：可达性矩阵 + 行为锚数字 + 管线形状判定（直接开关 vs 手做补偿 vs 降级注记三选一，附依据）。
- **证据**：probes.md 落盘 + DECISIONS 引用条目。**本任务完成前 T2 不开工（计划内硬序）**。

### T2 软打样 proof 段（COLOR-02 本体）

- **action**
  1. 新建 `LightamerCore/Sources/Foundation/SoftProofProfile.swift`：值类型（printer ICC 引用 + intent（默认 relative colorimetric）+ BPC 行为（按 T1 结论）+ gamut check 开关）+ **per-run override 语义**（doc comment 显式写死：永不进 Params/history/export——`ColorOutModule.swift:76/:128` 双 socket 先例同形）。
  2. 新建 `LightamerCore/Sources/Pipe/Terminal/SoftProofStage.swift`：proof 段 = 工作空间 → **Rec2020 → 打印机 ICC**（relative colorimetric + BPC）→ 既有显示变换上游插入；引擎 = ColorSync/CG 精确腿（`CGColorConversionInfo`）。打印机 profile 来源 = ColorSync 已装档案列表（枚举 API）+ 最近记忆。**不占 `Params.outputProfile` 导出枚举**（:79-87 是导出目标，语义不同不混用）。
  3. `PipeCoordinator.swift`：proof override 注入面（coordinator 级 runtime override，per-window per-run data）；proof ON 时 re-commit 显示链，OFF 时零触碰。
  4. **零回归验证前置**：改动合入前先跑既有渲染 golden 矩阵全绿（proof OFF 路径逐字节直通——不改任何既有 kernel/Params 序列化）。
- **证据**：`SoftProofStageTests`——proof OFF 逐字节直通（golden 矩阵子集 + 直通断言）；proof ON 不进 history（history 步数不变）+ 不进 export（导出 golden 逐位不变）+ sidecar 字节不变；BPC 行为锚（按 T1 结论：开关生效或手做补偿黑点映射 golden）。

### T3 OOG gamut check（黑裁剪）

- **action**
  1. gamut check 开关（`SoftProofProfile` 字段）：开启时对 proof 段做**往返 gamut 判定**（工作空间色 → printer 域 → 回程不可逆 = 超域），超域像素以**黑裁剪**显示（dt softproof gamut check 同语义）。
  2. 已知超 printer 域样本集 golden（高饱和色卡类合成样本即可，DECISIONS 记样本构成）。
- **证据**：OOG golden 测试（超域像素判定命中 + 黑裁剪输出 + 关闭时直通对照）并入 `SoftProofStageTests`。

### T4 proof UI 面（toggle / picker / gamut 开关 / zh 键）

- **action**
  1. 视口工具条或 StatusBar（执行期决策定入口）：proof toggle + 打印机 profile picker（已装档案 + 最近记忆）+ gamut check 开关 + OOG 警示态显示；快捷键（执行期决策）。
  2. 每键 zh 同批（L025 smoke 数字随 suite 报）；UX 文案边界——软打样是显示模拟，不改变任何已存编辑（与 QL 预览语义教学同款措辞纪律）。
  3. UI 逻辑面（状态路由）单测钉死；真机观感走查**需解锁控制台（Manual-Only 候补）**。
- **证据**：wiring/状态路由单测 + L025 smoke 计数行贴 SUMMARY。

### T5 多显示器 ICC 自动切换（COLOR-03 事件面）

- **action**
  1. `PipeCoordinator.swift`：订阅 `NSApplicationDidChangeScreenParametersNotification`（拓扑/profile 统一信号）+ window↔screen 追踪（窗口移动/跨屏事件）→ 按**窗口所在屏**重跑 `DisplayProfile.resolve`（`DisplayProfile.swift:53-82` 四级匹配表原样，零改）→ coordinator 重 commit colorout params。
  2. **既有缓存语义自动工作**（不新造）：`stableID` 折叠进 piece.paramsHash，仅 terminal 段键翻转、上游平面存活（`DisplayProfile.swift:104-123` + `ColorOutModule.swift:58-61`）——本任务只补「何时重解析」事件面。
  3. 多窗独立：per-window 解析自然延伸（窗 A P3 内建屏、窗 B 外接屏互不污染；D-COL2 `current()` 注入语义 `:84-88` 延伸到双窗）。
- **证据**：`MultiDisplayProfileTests`——profile 切换序列 → **仅 terminal 段键翻转 + 上游平面存活**（SC#2 terminal variant 既有测试扩展）；双窗双 profile 独立性（注入两级 DisplayProfile 断言 per-window params 独立）；通知接线 = 构建走查，真双屏实测**需解锁控制台（Manual-Only 候补）**。

### T6 手动 per-display 覆盖（Settings + exact-TRC 兑现）

- **action**
  1. `SettingsView.swift`：每显示器 profile 选择（ColorSync 已装档案列表）——手动选择 = 把该屏解析结果替换为指定 ICC（走 `.colorSyncFallback` 精确腿）。
  2. **顺带兑现 fallback 腿 exact-TRC**（`DisplayProfile.swift:136-151`「sRGB workalike」文档化近似在手动指定精确 ICC 后消除）：fallback 腿精确路径落位 + doc comment 债清。
- **证据**：`MultiDisplayProfileTests` 扩段——手动覆盖后 fallback 腿 **ICC 字节 identity 断言**（resolve 产物 CGColorSpace 字节与指定 ICC 档案字节一致）；未覆盖屏走自动解析不受扰。

### T7 F-12-5-2 dt-GUI 同轮 + 全量回归收口

- **action**
  1. **F-12-5-2（12 移交⑤，Manual-Only 正主）**：dt-GUI 侧同一 .cube 样本 golden 人工交叉对照——12-5 自动化腿已钉数值/权重表 verbatim（遗留对表 #5：dt 参考为 CPU float64 双写 + L017 dt-cli 本 host 损坏先例），本任务 = dt-GUI 真环境观感一致确认，截图入 `.work/gui-acceptance/`，TODO Manual-Only 台账行关闭。**需解锁控制台（Manual-Only）**。
  2. 全 suite 终轮（基线 **1553/9skip/0fail** + 新增，0 fail）；TODO.md 13-2 勾选；`13-2-SUMMARY.md` + `13-2-DECISIONS.md`（探针结论引用、toggle 入口/快捷键、OOG 样本构成、通知去抖、其余执行期决策）；新教训候选评估入 LESSONS。
- **证据**：F-12-5-2 截图 + 台账关闭行；测试计数（1553 → N，0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| BPC 探针 | 可达性矩阵 + 管线形状判定落档 | probes.md 评审（T2 前置硬闸） |
| proof 段 | OFF 逐字节直通 / ON 不进 history+export / BPC 锚 | `Scripts/test-direct.sh 'SoftProofStageTests'` |
| OOG | 超域 golden + 黑裁剪 + 关闭直通对照 | `Scripts/test-direct.sh 'SoftProofStageTests'`（OOG 段） |
| UI 面 | wiring 单测 + zh 键 smoke 计数 | `Scripts/test-direct.sh`（wiring 段）+ SUMMARY 贴证 |
| 多显示器 | 仅 terminal 键翻转 / 上游存活 / 双窗独立 | `Scripts/test-direct.sh 'MultiDisplayProfileTests'` |
| 手动覆盖 | fallback 腿 ICC 字节 identity | `Scripts/test-direct.sh 'MultiDisplayProfileTests'`（覆盖段） |
| F-12-5-2 | dt-GUI 对照截图 + 台账关闭 | 人工走查（Manual-Only） |
| 回归 | 全 suite 0 fail（基线 1553+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] BPC 探针报告落档（probes.md）：intent 行为锚 + BPC 开关存在性结论 + 管线形状判定（直接/手做补偿/降级三选一有据）——**先于 proof 段实现**
- [ ] 软打样：proof 状态 = coordinator 级 per-run override（永不进 Params/history/export 三断言齐）+ proof 段插 colorout 上游（Rec2020→printer ICC relative colorimetric + BPC 按 T1）+ ColorSync/CG 精确腿 + printer profile 枚举/最近记忆 + 零回归（OFF 逐字节直通 + 导出 golden 逐位不变）
- [ ] OOG gamut check：开关 + 往返判定 + 黑裁剪 golden + 关闭直通对照
- [ ] UI 面：toggle/picker/gamut 开关 + zh 键同步（smoke 数字随 suite 报）+ 文案不暗示改编辑
- [ ] 多显示器：通知 + window↔screen 追踪 → 既有 resolve/翻键自动工作（仅 terminal 键翻转 + 上游平面存活断言）+ 双窗双 profile 独立 + 真双屏实测登记 Manual-Only 候补
- [ ] 手动覆盖：Settings per-display 选择 + `.colorSyncFallback` exact-TRC 兑现（ICC 字节 identity 断言）+ 未覆盖屏不受扰
- [ ] F-12-5-2 dt-GUI 对照关闭（截图 + 台账行）
- [ ] 全 suite 0 fail（1553+新增）；每任务独立提交 + 边界查 config 开关 ×7；不 push；SUMMARY + DECISIONS + probes.md 落盘

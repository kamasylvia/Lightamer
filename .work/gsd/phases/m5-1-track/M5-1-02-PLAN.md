---
phase: m5-1
plan: "M5-1-02"
title: "TRACK P2——S2 per-channel CDF 求解器（256-entry 曲线，整数秩逆查表）+ 多参考统计级加权矩池化（μ/Σ 二阶矩 + 直方图定权重整合 + 序规范化确定性）+ 65³ Float64 bake（concurrentPerform + LRU 16 + clamp 平台面 + 体素门 ≤1e-5）+ .cube 派生资产（.lra.colormatch/ 位 + params {assetRef, stableHash} + typed degrade + 重解闭合）+ colormatch LUT 臂（复用 lut3d_tetrahedral kernel 函数，零新采样 kernel）+ 面板与求解编排服务（ColorMatchPanelModel 三级读 + D-H1 strength + 参考选取/自动求解 + 统计提取适配器）+ 多参考列表 UI（权重滑杆）+ G1/G2/G5 扩展 golden + TRACK-02/04 兑现"
wave: 2
depends_on: ["M5-1-01"]
autonomous: true
requirements: ["TRACK-01（S2 半）", "TRACK-02（多参考池化 + 权重）", "TRACK-03（LUT 臂 + .cube 资产载体）", "TRACK-04（面板交互/强度/before-after）", "TRACK-05（G 门扩展）"]
estimated_tests: "+38..48"
test_bundles: [LAYERS, IOPParity, APP]
files_modified:
  - LightamerCore/Sources/ColorMatch/ColorMatchCDFSolver.swift   # 新建：S2 per-channel 256-entry CDF 映射曲线（直方图→CDF→整数秩逆查表，Float64 阶梯，禁插值）
  - LightamerCore/Sources/ColorMatch/ColorMatchPooling.swift     # 新建：多参考池化（μ/Σ 二阶矩加权 + 直方图定权重整合取整 + 按 refStatsHash 序规范化 = 顺序无关确定性）
  - LightamerCore/Sources/ColorMatch/ColorMatchBake.swift        # 新建：65³ Float64 bake（Rec2020→Oklab→CDF→α-lerp→Oklab⁻¹→Rec2020 逐体素；concurrentPerform 晶格切片；LRU 16 键 = fnv(solutionHash ⊕ α bits)；域端 clamp 平台面）
  - LightamerCore/Sources/ColorMatch/ColormatchCubeAsset.swift   # 新建：`.lra.colormatch/` 派生资产存取（LUT_3D_SIZE 65 文本写出/读入 + 字节哈希全验证 + typed degrade 值形态；RasterMaskStore 孪生；L009 同目录 tmp 原子晋升）
  - LightamerIOP/Sources/ColorMatch/ColormatchModule.swift       # 修改：additive solver case `.cdf` + assetRef/assetHash 字段（L013 decimal String）+ 资产 resolver 注入缝（Lut3dModule resolver 同形）+ LUT 臂 dispatch（lut3d_tetrahedral kernel 函数经 colormatch 自己的 PSO；恒等臂语义扩展 assetRef nil）
  - Tests/LightamerTests/ColorMatchCDFSolverTests.swift          # 新建（LAYERS/Core 级）：CDF 构造/逆查表/单调/恒等分布/截尾交互
  - Tests/LightamerTests/ColorMatchPoolingTests.swift            # 新建（LAYERS/Core 级）：二阶矩公式锚/权重归一/序规范化/N=1 退化
  - Tests/LightamerTests/ColorMatchBakeGoldenTests.swift         # 新建（LAYERS/Core 级）：体素门 ≤1e-5（对理想连续模型，LCG 常量种子）+ 双跑 bit-identity + 平台面 + α 折入精确性
  - Tests/LightamerTests/ColormatchCubeAssetTests.swift          # 新建（LAYERS/Core 级）：写出/读入位精确往返 + 哈希验证 + degrade 形态 + 原子晋升
  - Tests/LightamerTests/ColormatchModuleTests.swift             # 修改：LUT 臂 additive（.cdf serde/assetRef 缺席恒等/资产 degrade 恒等）
  - Tests/LightamerTests/ColormatchIdentityGoldenTests.swift     # 修改：S2 恒等态扩展（assetRef nil/资产丢失 degrade 逐字节直通）
  - App/Sources/Lightamer/State/ColorMatchService.swift          # 新建：求解编排（源统计 = PREVIEW 完成面 readback ≤512² box 降采样 → Core 提取；参考统计 = THUMBNAIL 桶 pristine 渲染同法；attach = addAdjustmentLayer+addModuleToLayer；重解缝）
  - App/Sources/Lightamer/UI/Shell/ColorMatchPanelModel.swift    # 新建：FilmPanelModel 孪生（三级读投影 + 单 discrete commit + strength D-H1 live 三件 + 求解动作 + readout）
  - App/Sources/Lightamer/UI/Shell/ColorMatchPanelView.swift     # 新建：参考选取（PanelPresentation 缝，L057 禁 runModal）+ solver picker + strength + readout（solver/effectiveSolver/statsHash/支撑域宽）+ before/after 既有三形态
  - App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift # 修改（如挂载需要）：colormatch 实例选中 → 面板内容区（照 grade op 既有机制；若机制零改则此行撤销——DECISIONS 申报）
  - Resources/Localizable.xcstrings                              # 修改：colormatch_* 面板键族尾块纯插入（预期 +14..18 键）
  - Tests/LightamerTests/ColorMatchServiceTests.swift            # 新建（APP/App 级）：提取适配器/attach 落位/重解/降级路径
  - Tests/LightamerTests/ColorMatchPanelModelTests.swift         # 新建（APP/App 级）：三级读/D-H1 commit/多参考列表动作
  - Project.swift                                                # 修改：新测试文件登记对应 target 数组 + tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 修改：新测试文件增行登记（E2）
  - .work/gsd/phases/m5-1-track/M5-1-02-SUMMARY.md               # 新建（收口）
  - .work/gsd/phases/m5-1-track/M5-1-02-DECISIONS.md             # 新建（收口）
  - .work/gsd/phases/m5-1-track/M5-1-02-ACCEPTANCE.md            # 新建（双重验收）
  - .work/GOAL-STATE.md                                          # 修改：续接点
  - .work/TODO.md                                                # 修改：M5-1 条目
  - .work/LESSONS.md                                             # 如踩坑
---

# Plan M5-1-02 — TRACK P2：S2 CDF + LUT 臂 + 多参考池化 + 面板交互（G 门扩展）

> **性质**：M5-1 三 plan 之二。本批交付：S2 per-channel CDF 求解器 → 65³ bake →
> `.cube` 派生资产载体 → colormatch LUT 臂（复用既有 tetrahedral kernel 函数）→
> 多参考统计级池化（Core + UI）→ 面板与求解编排服务（TRACK-04 全兑现）。**生产
> 行为可见变化 = colormatch 面板可用（单/多参考求解 + 强度 + before/after）+ S2
> 档位可选**；无实例渲染零变化不变（G5 扩展态钉死）。`match_color` MCP（G4 +
> 五门收口）= M5-1-03。规格正本 = `RESEARCH-NOTES.md` §3.2(S2)/§3.3(LUT 臂)/
> §3.4(域端)/§3.5(池化)/§4(交互)；裁决正本 = `M5-1-CONTEXT.md` 裁决记录
> （OQ-1..8 全按推荐）。
>
> **基线**：M5-1-01 验收后的实测全套值（对账链 = 3335/16/0 + M5-1-01 增量；
> bundle 分账以 M5-1-01-SUMMARY 为准）。本 plan 新增测试按 bundle 分账对账。

## 已定裁决（生效值，硬约束，不得重开）

本 plan 承载八项生效值中的 **①(S2)③(.cube 资产半)④(65³+平台面半)⑤(池化)** + ②④⑦⑧ 的 LUT 臂延伸：

1. **OQ-1（S2 档）**：per-channel CDF 匹配 = 三通道独立 256-entry CDF 映射曲线；已知弱点 = 通道独立破坏色相（面板披露 + strength 混合缓解）；strength 三档共用 Oklab 域 lerp 语义。
2. **OQ-2（Oklab 域）**：CDF 曲线作用在 Oklab 逐通道；bake 域 = Rec2020→Oklab→CDF→lerp→Oklab⁻¹→Rec2020 逐体素 Float64（应用域恒等直出 working linear Rec2020——LUT 无编码语义，LutEncodingCatalog 零触碰）。
3. **OQ-3（.cube 派生资产）**：LUT 臂烘焙 65³ float32 走 `.cube` 派生资产位；**params 存 `{assetRef, stableHash}`，资产丢失 = typed degrade + 按哈希重解**；**不进 paramsData**（65³ ≈ 3.3MB 红线——sidecar 膨胀失禁禁令）。
4. **OQ-4（65³ + 截尾/平台面）**：65³ float32（FilmPrintBake 先例：Float64 bake + LRU + 体素门）；域端 = **线性延拓/clamp 平台面**（M3-3 轴端平台面教训的正向应用端）+ 1%/99% 截尾支撑域（P1 已落）配合实际覆盖率 ≥98%。
5. **OQ-5（池化）**：统计级加权池化 `μ_pool = Σ w_i μ_i`；`Σ_pool = Σ w_i (Σ_i + (μ_i−μ_pool)(μ_i−μ_pool)ᵀ)`；CDF 族 = 直方图加权合并；权重 = 参考列表行滑杆（归一化）；N=1 恒退化自然。
7. **OQ-7（参考侧全图）**：参考侧统计域 = 全图（提取适配器无 region 参数）；源侧局部 = 蒙版即达（本 plan 零新蒙版面——supportsBlending 既有）。
8. **OQ-8（门扩展）**：G1 扩展 = solve→bake→.cube 全链 bit-identity + 重解闭合；G2 扩展 = LUT 臂零新采样 kernel（tetrahedral 既有 parity 面覆盖）+ 链路断言；G5 扩展 = S2 恒等态；G3 自然样张目测 = 本 plan GUI 走查（Manual-Only 行挂 gui-acceptance）。

**架构红线（本 plan 全程 + checker 机检面）**：
- **零新 SPM 依赖**；`Lut3dModule`/`CubeLutParser`/`LutLibraryStore`/`Lut3dKernels.metal` **零算法 diff**（LUT 臂只**复用** `lut3d_tetrahedral` kernel 函数——经 colormatch 自己的 PSO 引用同一 metallib 函数；若 kernel 签名需 uniform 适配，适配在 colormatch 侧 uniform 盒子，kernel 文件零触碰）。
- sidecar **零 schema 变更**（additive solver case + assetRef/assetHash 字段走 ModuleInstance paramsData 既有通道；LUT 字节永不入 paramsData——机检 = paramsData 尺寸上界断言）。
- `.metal` 新增面 = 零（本 plan 无新 kernel 文件；P1 的 ColorMatchKernels.metal 零 diff）。
- `FilmPrintBake`/`FilmTailPolicy`/Film 全域零触碰（只照体例）；`LutEncodingCatalog` 零触碰（OQ-2：线性臂无编码语义）。
- Panel 呈现纪律（L057）：一切文件面板走 `PanelPresentation.present`，`runModal` 族零命中（`grep -rn "\.runModal(" App/Sources` 收口自证）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 S2 CDF 求解器（T1，OQ-1；RESEARCH §3.2）

- 输入 = 源/参考 `ColorMatchStats`（P1 面直用——直方图即输入）；输出 = 每通道 256-entry 映射曲线（Float64 阶梯）。
- **构造**：src CDF(x) → 归一 → ref CDF⁻¹ 同分位查表（整数秩爬梯——累积计数对齐，**禁浮点插值**；两 CDF bin 数同 256 但域不同——映射在**分位空间**对齐：src bin i 的累积占比 p → ref 域内累积占比 ≥p 的首 bin j → 曲线[i] = ref 域值(j)）。
- 曲线端点 = 平台（低于 src 支撑域 → ref 端值；高于同）；截尾支撑域外输入 = 曲线端平台（P1 截尾与曲线域端一体面）。
- 恒等分布 → 恒等曲线（G3 扩展断言：同分布 → 曲线 ≈ identity，实测带）。
- 曲线中间产物**不持久化**（裁决：params 存 assetRef——曲线只活在 solve→bake 链上；重解 = 重提取统计重跑，G1 钉重解一致）。

### KD-2 多参考池化（T2，OQ-5；RESEARCH §3.5）

- **序规范化（确定性关键）**：池化输入先按 `referenceStatsHash` 升序排序再求和——**同参考集合任意列表序 → 逐字节同池化结果**（浮点求和顺序敏感的根治；G1 断言同集异序同字节）。
- 矩池化照裁决公式；直方图整合 = `h_pool[i] = round(Σ w_i·h_i[i])`（固定排序序求和 + 取整 → 回到整数计数，P1 整数秩分位纪律无断裂）；权重归一化（Σw=1）在池化入口。
- N=1 恒退化 = 恒等池化（单参考直接通过）；权重缺省 = 均分。
- 池化产物 = 标准 `ColorMatchStats`（statsHash 重算——池化哈希 = 求解缓存键的 ref 项，同池化同哈希）。

### KD-3 65³ bake（T3，OQ-4；FilmPrintBake 体例）

- 逐体素 Float64：晶格坐标 → Rec2020 linear（[0,1]³ 归一域）→ Oklab → 逐通道 CDF 曲线求值（阶梯查表）→ α-lerp（Oklab 域，与 P1 kernel 同式）→ Oklab⁻¹ → Rec2020 → Float32 存储。
- **α 折入 bake（显式裁）**：strength 在 LUT 臂 = bake 输入（`bakeKey = fnv(solutionHash ⊕ α 位模式)`，LRU 16）；D-H1 live 拖拽逐 tick 重 bake（内存 LRU，分辨率无关、65³ 并发 perform 预算 <50ms——实测入 DECISIONS）；**资产只在 commit 落盘**（tick 零 IO）。
- concurrentPerform 晶格切片 + 固定索引归并（FilmPrintBake 同款——双 bake BIT-IDENTICAL 断言）。
- **平台面**：输入 clamp [0,1]³ 后进 bake（晶格端体素即平台值；tetrahedral 采样 clamp 语义与 bake 域端一体——覆盖率 ≥98% 由截尾保证）；HDR >1 输入落端平台 = 裁决政策（面板 readout 披露支撑域宽）。
- **体素门**：bake vs 理想连续模型（同公式非量化直算）≤1e-5（LCG 常量种子随机体素集——M3-3 bake 体素门先例）；门值实测收窄钉门纪律同 G2。

### KD-4 .cube 派生资产（T4，OQ-3；RasterMaskStore 孪生）

- 路径 = `<原文件完整名>.lra.colormatch/<bakeKeyHex>.cube`（`.lra.masks/` 同款兄弟目录惯例）；内容 = 标准 `LUT_3D_SIZE 65` 文本格式（float 三元组，**最短往返表示法序列化——写→读位精确**，G1 断言字节往返）。
- `ColormatchCubeAsset`（Core，RasterMaskStore 结构孪生）：write（同目录 tmp 原子晋升——L009）/ load（**全验证**：尺寸 + 字节 FNV 对 params.assetHash；失配/缺失 = `LoadResult.degraded(reason)` 值形态非静默）；**同解前缀清理**（同 solutionHash 不同 α 的旧资产 commit 时 best-effort 删除——孤儿残留为观察项非门）。
- **typed degrade 闭环**：资产丢失/失配 → 模块恒等直通（degrade 值携带 reason 面板可见）+ **重解缝**（面板/服务按哈希重提取统计重跑 solve→bake→write——G1⑤重解产物与原表逐字节断言；参考图不可达 = degrade 维持 + 面板提示）。
- params 载体：`assetRef: String?`（库根相对风格 POSIX 相对路径——项目相对）+ `assetHash: String?`（L013 decimal String）。**paramsData 尺寸上界断言**（LUT 字节不进 sidecar 的机检面：<8KB 上界）。

### KD-5 LUT 臂 dispatch（T5，OQ-3；零新采样 kernel）

- 模块 additive：`ColorMatchSolverKind.cdf` case + `assetRef/assetHash` 字段（serde additive optional——P1 档字节零漂移专测延续）。
- **resolver 注入缝**：`ColormatchModule(resolver: ColormatchAssetResolving)`（LutLibraryStore.sharedResolver 同形——App 侧装配套注入项目路径解析；Core 测试注入内存表）。
- **应用 = `lut3d_tetrahedral` kernel 函数引用**（colormatch 自己的 PSO + 表纹理 rgba32Float——Lut3dModule 表纹理姿态）；identity 矩阵 uniform（若 kernel 签名含 colorspace 矩阵项——**executor 先亲核 `Lut3dKernels.metal` 签名**，适配全在 colormatch uniform 盒子，kernel 文件零 diff）。
- 恒等臂扩展：solver=.cdf 且 assetRef nil / 资产 degrade → blit（G5 扩展态）。
- **G2 延伸**：tetrahedral 采样 parity = Lut3dKernelTests 既有面（零新采样 kernel = 零新 parity 面）；本 plan 只加「colormatch LUT 臂输出 == 同表 lut3d 同采样路径」一条链路断言（IOPParity）。

### KD-6 面板与求解编排服务（T6，TRACK-04；RESEARCH §4）

- `ColorMatchService`（App/State）：**源统计** = PREVIEW 完成面 readback → CPU box 降采样 ≤512×512（固定序）→ 样本集 → Core 提取（P1 纯函数）；**参考统计** = 参考图 THUMBNAIL 桶 **pristine** 渲染（编辑关——KD 注记：edited-reference 挂 V2 走查反馈；pristine = 确定性 + MCP parity 前提）→ 同法提取。readback 前 fence（L014）。
- 求解 = 后台任务（BackgroundTaskHosting 三腿协议先例）；完成 → attach = `addAdjustmentLayer` + `addModuleToLayer`（grade 层）+ params 写入 = `recordChange` 单 discrete commit（**零新 history 键族**——colormatch 参数走 per-instance params 既有通道；strength D-H1 = M2-5 per-op live 会话形）。
- `ColorMatchPanelModel`（FilmPanelModel 结构孪生）：三级读（live 窗口值 → history 投影 → params 真相）；写 = 单 commit / D-H1。面板面：参考选取（库内选择器 + 文件面板走 `PanelPresentation.present`——L057）/ solver picker（gaussian-ot/reinhard/cdf）/ strength 滑杆 / Solve 按钮（重解 + 缓存 invalidateAll 缝）/ readout（solver/effectiveSolver/statsHash/支撑域宽/资产 degrade 提示）/ before/after（9-4 三形态既有面：split/hold/projectedState override）。
- 挂载 = grade op 选中实例 → 面板内容区（EditorAdjustmentStackView 既有机制；若机制零改则 files_modified 该行撤销并 DECISIONS 申报）。

### KD-7 多参考 UI（T7，TRACK-02；RESEARCH §3.5/§4）

- 参考列表行（add/remove + 缩略 = 既有缩略桥 + **权重滑杆**行内）；列表 = 面板会话态（**不持久化**——committed 真相 = 池化求解产物；重开图列表为空，重解 = 重新选取。KD 注记：列表持久化挂 V2 若走查暴露需求）。
- 求解 = 列表池化（KD-2）→ 单解单实例（v1 不做逐参考 α 混合——裁决备选 A 否）。
- N=1 = 单行默认态（TRACK-02 的 N≥1 语义自然覆盖单参考主流程）。

### KD-8 G 门扩展（T8，OQ-8）

- **G1 全链**：solve → bake → .cube 写出字节 → 读回，全程逐字节双跑断言；资产删除 → 重解（同统计重提取）→ 重 bake → 新文件与原文件逐字节（重解闭合）；池化同集异序同字节。
- **G5 扩展态**：solver=.cdf + assetRef nil → blit；资产 degrade → blit（逐字节直通对照既有 golden 输出）。
- **G3 自然样张目测** = 本 plan GUI 走查 Manual-Only 行（gui-acceptance 记录，OQ-8 备选 A 默认形态）——执行方出走查配方（`.work/gui-acceptance/m5-1/` MANIFEST 行），实测由验收轮完成。

## read_first

1. `.work/gsd/phases/m5-1-track/M5-1-CONTEXT.md`（裁决记录正本）+ `RESEARCH-NOTES.md` §3.2/§3.3/§3.4/§3.5/§4/§6
2. `LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift` 全文（65³/Float64/concurrentPerform/LRU/体素门体例正本）
3. `LightamerCore/Sources/Sidecar/RasterMaskStore.swift` 全文（派生资产存取/哈希验证/degrade 值形态/路径惯例正本）
4. `LightamerIOP/Sources/Lut3d/Lut3dModule.swift`（表纹理 rgba32Float/PSO/resolver 注入/tetrahedral dispatch——LUT 臂应用端直接先例）+ `LightamerIOP/Sources/Lut3d/Lut3dKernels.metal`（kernel 函数签名亲核——KD-5 适配面判定）
5. `App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift` + `FilmPanelView.swift`（面板孪生结构正本）+ `App/Sources/Lightamer/State/PipeCoordinator.swift`（D-H1 live 会话形 + PREVIEW 完成点 tap 面）
6. `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift` :380-500（FilmStatsSeam adapter 形——本 plan 提取适配器的体例参照）
7. `Tests/LightamerTests/FilmGoldenTests.swift`（bake golden 基建先例）+ `M2-4-0-BUNDLE-MAP.txt` IOPParity/APP 归属注记
8. `.work/gsd/phases/l057-panel-family/L057-DECISIONS.md`（PanelPresentation 缝正本——参考文件面板呈现）
9. M5-1-01-SUMMARY/DECISIONS（P1 实测带与折叠序记录——本 plan 全链 G1 的上游真值）

## 纪律（强制）

- 与 P1 同款全套（每任务独立提交 / caffeinate / test-direct 定向轮 / L014 / L048 / 零 diff 自证 / 资源监控 / 中文标注显式）；L041 `tuist generate` 尾闸；E2 BUNDLE-MAP 同 commit 登记。
- **收口机检追加**：`grep -rn "\.runModal(" App/Sources` 零命中（L057）；`git diff <P1基线>..HEAD -- LightamerIOP/Sources/Lut3d/` 零命中（lut3d 密封面）；paramsData 尺寸上界断言绿。
- zh-audit `--check` 对 `colormatch_*` 新键族绿（V14/V15 纪律：静态键显式，禁 `String.LocalizationValue("prefix_\(x)")` 形态）。

## Tasks

### T1 S2 CDF 求解器（KD-1）

- 验收：`ColorMatchCDFSolverTests`（LAYERS）——分位对齐构造（已知双高斯 → 曲线单调 + 端平台）；恒等分布 → 恒等曲线带；整数秩无插值（阶梯断言）；截尾交互（支撑域外 → 端平台）；双跑逐字节。

### T2 多参考池化（KD-2）

- 验收：`ColorMatchPoolingTests`（LAYERS）——二阶矩公式锚（两参考手算对照）；权重归一；**序规范化（同集任意排列 → 逐字节同池化）**；N=1 恒等退化；直方图取整回整数计数断言。

### T3 65³ bake（KD-3）

- 验收：`ColorMatchBakeGoldenTests`（LAYERS）——体素门 ≤1e-5（理想连续模型 + LCG 种子，实测收窄钉门）；双 bake BIT-IDENTICAL；α 折入精确性（bake(α) 体素 == Oklab 域手算 lerp）；平台面（端体素值 = clamp 坐标值）；bake 耗时实测入 DECISIONS（预算 <50ms）。

### T4 .cube 派生资产（KD-4）

- 验收：`ColormatchCubeAssetTests`（LAYERS）——写→读位精确往返；哈希全验证（篡改一字节 → degrade + reason）；原子晋升（中断态无半文件）；同解前缀清理行为记录；**paramsData 上界断言**（LUT 字节不进 sidecar 机检）。

### T5 LUT 臂模块接线（KD-5）

- 验收：`ColormatchModuleTests` 扩展——.cdf serde additive（P1 档零漂移延续断言）；assetRef/assetHash L013；resolver 注入；degrade → blit；**`ColormatchIdentityGoldenTests` 扩展**（S2 两恒等态逐字节）；链路断言（同表同采样 == lut3d 路径，IOPParity）；`git diff -- Lut3dKernels.metal` 零命中。

### T6 面板 + 编排服务（KD-6）

- 验收：`ColorMatchServiceTests`（APP）——源/参考提取适配器（合成平面 → 统计断言）；attach 落位（addAdjustmentLayer+addModuleToLayer+params commit 链）；重解缝；pristine 参考语义（参考编辑不改变统计——THUMBNAIL pristine 断言）；`ColorMatchPanelModelTests`（APP）——三级读/D-H1 commit 单 item/solver picker/readout 投影。
- 红线：runModal 零命中；文件面板走 PanelPresentation。

### T7 多参考 UI（KD-7）

- 验收：列表 add/remove/权重滑杆动作（PanelModelTests 扩展）；池化求解链（列表 → 池化 → 单解单实例）；N=1 默认态；权重变更 → 重解 commit。

### T8 G 门扩展 + 走查配方（KD-8）

- 验收：G1 全链四断言（solve→bake→cube→读回逐字节 / 重解闭合 / 池化异序同字节 / 缓存透明扩展）；G5 扩展态；G2 链路断言（T5 内，此处汇总）；**G3 走查配方落 `.work/gui-acceptance/m5-1/MANIFEST.md`**（自然样张对照行 = Manual-Only）。

### T9 收口

- SUMMARY/DECISIONS/GOAL-STATE/TODO 同批 + 零 diff 红线自证（lut3d 密封面/Film 域/LutEncodingCatalog/.metal 零新增）+ zh-audit 绿 + runModal 机检。
- 验收：定向轮 `--bundle LAYERS/IOPParity/APP` 全绿零 MEMFAIL；对账链 = P1 后基线 + 本批增量逐位。
- **双重验收**：zcode 独立验收 → **串行** omp 二次验收（严禁并发）；结论落 `M5-1-02-ACCEPTANCE.md`。

## 验收标准（AC 总表）

1. **生效值①（S2）**：per-channel CDF 求解器在册（分位对齐 + 整数秩 + 恒等曲线带）；面板 solver picker 三档可选。【T1/T6】
2. **生效值②（Oklab 域延伸）**：bake 全链 Oklab 域 CDF/lerp；`LutEncodingCatalog` 零触碰。【T3】
3. **生效值③（.cube 资产）**：`.lra.colormatch/` 派生资产位 + params `{assetRef, assetHash}`（L013）+ typed degrade + 重解闭合 + **paramsData 上界断言**（LUT 字节不进 sidecar）。【T4/T5】
4. **生效值④（65³ + 平台面）**：65³ Float64 bake + 体素门 ≤1e-5（实测收窄）+ clamp 平台面 + 截尾支撑域配合覆盖。【T3】
5. **生效值⑤（池化）**：统计级加权矩池化 + 直方图整合 + 权重滑杆 UI + N=1 退化 + 序规范化确定性。【T2/T7】
6. **生效值⑦（参考侧全图）**：提取适配器无 region 参数；参考 = THUMBNAIL pristine（edited-reference V2 注记在册）。【T6】
7. **TRACK-04**：面板参考选取（PanelPresentation 缝）/自动求解/强度 D-H1/before-after 三形态/readout 全落。【T6】
8. **G1 扩展**：全链 bit-identity + 重解闭合 + 池化序规范化。【T8】
9. **G2/G5 扩展**：零新采样 kernel（lut3d 密封面零 diff）+ 链路断言；S2 恒等态逐字节。【T5/T8】
10. **红线自证**：零新 SPM；.metal 零新增；sidecar 零 schema；Film 域/LutEncodingCatalog 零触碰；runModal 零命中；xcstrings 尾块纯插入 + zh-audit 绿。【T9】

## 风险与边界

- **tetrahedral kernel 签名适配**：若签名含 colorspace 矩阵/编码 uniform 项，colormatch uniform 盒子按 identity 适配；**kernel 文件零 diff 为硬门**——不可达时（签名耦合不可适配）停下上报 orchestrator，不硬改 kernel。
- **逐 tick 重 bake 时延**：65³ Float64 并发 bake 预算 <50ms；实测超带 → DECISIONS 记录并降级为「拖拽中沿用上次 bake + 松手重 bake」（语义偏差显式申报，不静默）。
- **S2 色相漂移（R3）**：已知弱点——面板 solver 描述行披露 + strength 缓解；默认档恒 S1（gaussian-ot）。
- **资产孤儿**：同解前缀清理 best-effort；残留孤儿 = 观察项（reconcile sweep 挂 V2）。
- **IOPParity 贴线**：新增测试小表/合成集；MEMFAIL 先查重测漂移。

## 提交约定

- T1 `feat(core): per-channel cdf color match solver`
- T2 `feat(core): weighted multi reference statistics pooling`
- T3 `feat(core): 65-cube float64 colormatch bake with plateau edges`
- T4 `feat(core): colormatch cube derived asset store`
- T5 `feat(iop): colormatch lut arm over shared tetrahedral kernel`
- T6 `feat(app): colormatch panel with solve orchestration service`
- T7 `feat(app): multi reference list with weight sliders`
- T8 `test(app): full chain bit-identity and gate extensions`
- T9 `docs(m5-1): close cdf lut arm batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。

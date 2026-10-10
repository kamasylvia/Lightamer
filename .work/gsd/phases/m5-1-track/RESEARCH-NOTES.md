# M5-1 RESEARCH-NOTES — TRACK 追色族（research 起草批，2026-10-11）

> Phase = M5-1（ROADMAP §Milestone 5 M5-1 行：TRACK 追色族 research + 执行，TRACK-01..05
> + MCP `match_color` 工具位）。本文 = 算法设计全文（读解正本）；裁决面 = 同目录
> `M5-1-CONTEXT.md`（D-M5-1-1..8 + OQ-M5-1-1..8 全带推荐）。
> 状态：research 起草完成 → **C 档第 1 停**：OQ 裁决前不进 plan。
> 许可红线：darktable 参考源 GPL-3.0 只读零复制（§1.1）；LumaRescue 方法论可读、
> 文本/代码禁搬（§1.3）；本文全部文字为本项目自写。

## §0 Summary & Scope

- **目标形态**：参考图色彩分布统计 → 确定性求解色彩变换（3D LUT 或等效参数组）→
  `colormatch` iop 实例非破坏落位（sidecar 持久化 + 可继续手调 + cache 正确）→
  GUI 拖入交互与 MCP `match_color` 编排皮并存。
- **追踪需求**：REQUIREMENTS TRACK-01..05（V2 节，→ M5-1 整族）+ MCP-09 研究项 C。
- **非目标**：神经网络风格迁移（AIV2 域，用户已裁「追色 = 统计算法非 AI」）；
  LUT 文件格式再发明（复用 `.cube` / 既有 kernel）；参考图侧局部 region 统计
  （v1 全图统计，region 挂 V2，OQ-M5-1-7）；非参数 Sinkhorn/离散 OT（成本高、
  照片场景收益边际，v2 另议，OQ-M5-1-1）。
- **差异化定位**：Alcedo Studio 无追色面（封闭调整目录 18 项无色彩迁移）——
  与 FSIM 同理是超集卖点，非 parity 补课（§1.4）。

## §1 参考面与许可边界

### 1.1 darktable（GPL-3.0，只读参考算法思路，代码零复制）

本仓参考版本 tip `18cf557fbd`。相关模块两件：

**`src/iop/colortransfer.c`（已弃用——GUI 自述 "will be removed... move to the
new color mapping module"）**：Reinhard 2001（《Color Transfer between Images》,
Reinhard / Ashikhmin / Gooch / Shirley）直译形态——
- 域 = CIELab；`HISTN = 1<<11`（2048 bins）；`MAXN = 5` 簇。
- L 通道：直方图 CDF 匹配（capture → `invert_histogram` 得映射表；apply 查表 +
  clamp 0..100）。
- a/b 通道：k-means 聚类（≤5 簇，各簇 mean/variance）；apply 时源图重新聚类 →
  簇间最近邻映射（`get_cluster_mapping`）→ 逐像素软权重混合
  `out_ab = Σ_c w_c · ((lab_ab − mean_src_c) · var_tgt[map]/var_src_c + mean_tgt[map])`。
- 采集工作流 = target 图按 Acquire 按钮采统计存 params，preset 化后到 source 图
  apply——**统计进 params、一次采集多次应用**的参数化形态。

**`src/iop/colormapping.c`（现役继任）**：同族强化——
- params：`n`（1..5 簇，default 3）+ `dominance`（色彩主导 vs 空间邻近，0-100）
  + `equalization`（L 通道直方图均衡强度，0-100，default 50 = 原始 L 与 CDF 映射
  的插值）+ source/target 双侧统计六组（ihist/mean/var/weight ×2）。
- OpenCL 双 kernel（`colormapping_histogram` + `colormapping_mapping`）。
- GUI 双 Acquire（source/target）+ a/b 平面 swatch 可视化（Lab L=53.39 中灰面
  投影 `cmsDoTransform` 回 RGB 画 palette 色块）。
- colorspace 声明 = "linear or non-linear, Lab"（模块自带 Lab 往返）。

**可借鉴的设计事实**（思路级）：①统计预计算 + 参数化映射（统计即参数 = 我方
「求解 → 落位」同构，天然非破坏 + cache 友好）；②亮度通道与色彩通道分离处理
（L 用 CDF、a/b 用矩迁移——两边破坏面不同）；③等权/等化为默认（安全默认档）；
④统计自 preview 管低分辨率面采集（分辨率无关 + 快）；⑤空间感知（dominance/
簇）是高级档而非必需——v1 全局统计已可交付主体价值。

### 1.2 最优传输文献（公开论文，无许可问题）

- **Reinhard et al. 2001**：对角统计迁移（均值 + 方差，Lab 域）——上述 dt 实现
  的源头；=S1 框架的「关协方差」特例。
- **Gaussian OT 闭式解（Bures-Wasserstein）**：两高斯分布间 2-Wasserstein 最优
  传输有闭式线性映射——源协方差白化后乘目标协方差的矩阵平方根
  （`M = Σ_t^{1/2} · U · Σ_s^{-1/2}`，U 来自一次 SVD 的极因子；平移项 = μ_t − Mμ_s）。
  对实际（非高斯）分布是良好近似——Pitié 迭代投影法的第一步收敛形态即此。
  确定性可控（SVD 符号约定固定后 bit-identical）；参数面 = 3×3 矩阵 + offset
  （12 floats）。
- **Pitié / Kokaram / Delahay 2007**（"Automated colour grading using colour
  distribution transfer"）：n 维 PDF 迭代投影匹配——实用 OT 族代表作；逐维 1D
  边缘 CDF 匹配迭代收敛到联合分布匹配。其「逐维 CDF + 迭代」形态 = S2 的
  多轮推广；v1 取单轮 3 通道独立 CDF 即 S2。
- **Sinkhorn / Cuturi 2013**：熵正则离散 OT——不做（R/非目标，OQ-M5-1-1）。

### 1.3 LumaRescue 许可边界

- REQUIREMENTS TRACK 节记忆锚（2026-09-26 再确认）：LumaRescue 类方法论**无色彩
  匹配算法**——其路线是 agent-vision 迭代评图调参，被 TRACK-02（多参考统计聚合）
  与 TRACK-05（确定性门）结构性排除；我方仅借鉴其「agent 编排皮」工作流语义
  （选参考 → 触发求解 → 强度/参数微调 → 预览验收循环），该语义由 §5 的
  `match_color` 工具面 + 既有 `apply_params`/`render_preview` 承载。
- **LICENSE 警示**：其文章/仓有许可限制——方法论层面可读、可自写；文本与代码
  一律不搬。本文及 M5-1 全部交付物文字均为本项目自写，零引用其文本。

### 1.4 Alcedo 对照

Alcedo Studio（GPL-3.0，本地 `f1fae5d`）封闭调整目录 18 项无色彩迁移类模块；
上游亦无此面。M5-1 = 差异化能力（同 FSIM 定位），不入 parity 对表范围。

## §2 我方底座盘点（全部在期，零新增基建）

| 底座 | 资产 | 对 M5-1 的意义 |
|---|---|---|
| 渲染管线 | linear Rec2020 float32 scene-referred（COLOR-1）；grade 层 iop + `supportsBlending` | colormatch 作为 grade 域 op 落位；蒙版自动可用（M2-7 蒙版体系） |
| LUT 面 | `Lut3dModule`（op `lut3d`，iopOrder 36.0，`lut3d_tetrahedral`/`trilinear` kernel；Params = lutName/colorspace/interpolation/inputEncoding/outputEncoding）+ `CubeLutParser` | LUT 臂应用端复用（tetrahedral kernel 形态先例 + .cube 解析/写出面） |
| 编码目录 | `LutEncodingCatalog` 17 行 + `LutTransferMath` Float64 正逆曲线族（M3-1） | 若 LUT 臂需显式应用编码（推荐不需要——working 域恒等 LUT，OQ-M5-1-2） |
| LUT 库 | `LutLibraryStore` 根相对键 / shared holder / 可配根（M2-5-3） | colormatch 产物若走 `.cube` 派生资产的存取惯例参照（§3.3） |
| 确定性先例 | `FilmSolveCache`（fnv 小端折叠键精确值钉死）/ 整数秩分位（FilmStatsSeam）/ `FilmPrintBake` 65³ Float64 + LRU bake 缝 / M3-3 golden 四门体例 | 求解缓存键 + 统计离散化 + LUT 烘焙 + golden 门四套先例直搬体例 |
| 统计腿先例 | `ScopeReduceKernels` 256-bin×4 通道 GPU 直方图（M2-3-3，PREVIEW 完成回调 tap） | 追色统计可同型复用（GPU bin 计数）或 CPU 整数秩（FilmStatsSeam 同构）；采样域 = THUMBNAIL/PREVIEW 桶（dt preview-pipe 先例同款） |
| MCP 面 | `McpToolRegistry` + `EditingToolset`（load_image / list_iops / apply_params / render_preview / export_image）+ `IopCatalog` schema 元数据 | `match_color` 以新工具挂载（§5）；colormatch 注册后自动入 list_iops 与 apply_params 面 |
| 持久化 | sidecar v9 + registry params 通道（paramsData = Data→base64，L013 decimal 纪律） | 新 op 参数随 module params 自动持久化——**零 schema 升级**（新增 op 不动 schema） |
| 合成族对照 | Phase 8 StackMergeService / MTB / 行带流式 / IOP-HDR-04 32f 矩阵 | M5-2 Mertens 底座（本 phase 不展开，见 ROADMAP M5-2 行） |

## §3 算法设计

### 3.1 统计提取（TRACK-01 前半）

- **统计域 = Oklab（推荐，OQ-M5-1-2）**：working linear Rec2020 → Oklab 为公开
  解析式（线性 RGB → LMS 锥响应矩阵 → 非线性 → opponent 轴），零外部依赖
  （dt 用 CIELab 需 cms 往返；我方 ColorSync 面在管线内不作为统计前置）；
  色相线性优于 Lab（混合/插值语义更稳）；转换 float32 直算、往返精度 golden
  覆盖。备选：CIELab（dt 对齐语义）与 ACEScc/AP1（矩阵已在库）。
- **统计量三档**（与求解族一一对应）：
  1. 均值 μ（3）+ 协方差 Σ（3×3 对称 6）——S1/S3 用；
  2. per-channel 256-bin 直方图 + 累积 CDF——S2 用；
  3. k-means 簇统计——**不裁入 v1**（dt 的簇主要服务 dominance/空间感知与
     a/b 平面可视化；全局二阶统计 + OT 已覆盖主体价值；簇版挂 v2 若走查暴露
     局部色彩失调需求）。
- **采样纪律**：统计在 THUMBNAIL/PREVIEW 桶低分辨率面提取（分辨率无关归一化；
  dt preview-pipe 先例 + 我方 ScopeReduce 同型）；直方图 = 整数秩 bin 计数
  （**禁浮点插值**——FilmSolveCache 先例）；统计哈希入求解缓存键（§3.3）。
- **鲁棒截尾**：统计前对源/参考分布做 1%/99% 分位截尾（离群点不进矩/CDF；
  兼作 LUT 域端支撑域定义，§3.4）。

### 3.2 求解族（TRACK-01 后半）——三档统一框架（推荐，OQ-M5-1-1）

统一形态：统计(源 S，参考 R) → 确定性求解 → 变换 T + strength α ∈ [0,1]
（T 与恒等的线性插值，Oklab 域；0 = identity，1 = full match）。

- **S1 Gaussian OT 闭式（主打）**：
  `M = Σ_t^{1/2} · U · Σ_s^{-1/2}`（U = SVD 极因子，符号约定固定），
  `x' = M(x − μ_s) + μ_t`。两高斯间 2-Wasserstein 精确解；实际分布的良好近似
  （Pitié 迭代第一步形态）；线性域全定义域（天然 HDR/广色域安全，§3.4）；
  **参数面 = 3×3 + offset（12 floats）**——sidecar 零负担、直入 params、
  kernel = 逐像素矩阵乘（量级同 colorWheels）。
- **S2 per-channel CDF 匹配**：三通道独立 256-entry CDF 映射曲线；可选亮度
  守恒混合（equalization 语义反向：strength 混回原通道）。已知弱点 = 通道独立
  破坏色相（dt 以 Lab L/a/b 分离缓解；Oklab 域同构可用）；参数面 3×256 float
  （3KB）；应用端走 LUT 臂（§3.3）或三 1D ramp kernel（`lut3d_1d` 形态先例）。
- **S3 Reinhard 对角**：S1 关协方差特例（μ + 逐轴 σ）；TRACK-01 原文点名项，
  实现成本 ≈ 0（S1 代码路径一开关）；作为「轻量档」与论文语义锚保留。
- **非参数 Sinkhorn/离散 OT：不做**（OQ-M5-1-1；照片场景收益边际、迭代成本与
  确定性维护负担高；v2 若有真实需求另立）。

### 3.3 colormatch iop 落位（TRACK-03）

- **op 形态：新独立 op `colormatch`**（推荐，OQ-M5-1-3）——iopOrder 36.x 邻
  lut3d；`supportsBlending + allowTiling` 同 lut3d 旗标；不塞进 `lut3d`
  （lutName 语义 = 用户库文件引用；colormatch = 求解器产物实例——身份、缓存、
  持久化语义均不同，混体面会在 lut3d 的既有密封面上开洞）。
- **两臂参数化**：
  - **线性臂（S1/S3）**：params 直存 `{solver, 矩阵+offset（Oklab 域）, strength,
    statsHash 对}`——极小、确定、可手调（strength/矩阵微调走既有 params 编辑面
    与 history 通道）；kernel = 新 `colormatch` 3×3 矩阵 kernel（Oklab 往返内联）
    或等效复用矩阵乘 kernel 面。
  - **LUT 臂（S2 / 未来族）**：65³ float32 3D LUT（FilmPrintBake 先例：Float64
    bake + LRU + 体素门），应用端走既有 tetrahedral kernel 形态；**资产载体 =
    `.cube` 派生资产**写项目旁派生位（`.lra` 同目录派生物惯例，参照
    `.lra.masks/` 先例——派生物可弃可重建，真身 = params 里的
    `{assetRef, stableHash}`；**不进 paramsData**——65³ float32 ≈ 3.3MB，base64
    后 ≈ 4.4MB 会让 sidecar 膨胀失禁）。params 另存统计/求解哈希供漂移检测与
    重建（资产丢失 = typed degrade + 按哈希重解）。
- **cache 语义**：渲染缓存由既有 paramsHash 驱动（零新机制）；求解缓存（如需）
  键 = `fnv(sourceStatsHash ⊕ refStatsHash ⊕ solverTag ⊕ paramsHash)`
  （FilmSolveCache 同构，小端折叠精确值钉死先例）。
- **持久化**：params 走 registry/sidecar 既有通道，**零 schema 升级**；重开图
  零重解（参数即真相，LUT/矩阵为确定性派生物）。
- **手调**：strength 滑杆（live 三件套 D-H1 先例：live 零 item、松手一 commit）
  + 矩阵微调为高级披露（折叠区）——「可继续手调」（TRACK-03）由 params 面天然
  兑现。

### 3.4 HDR/广色域与域端裁剪（TRACK-05 一部分）

- 工作域 = linear Rec2020 float32 直通：矩阵臂全定义域（无 8bit 量化面、无
  display-referred 负值钳制脏像素问题）；LUT 臂轴端 = 线性延拓/clamp 平台面
  （M3-3 golden 教训：平台面切片式穿 cell 的问题域在「反演轴端」；本处为应用
  端正向采样，平台面仅覆盖源统计支撑域外的少数输入——配合 §3.1 分位截尾定义
  支撑域，实际覆盖率 ≥98%）。
- 广色域：参考/源均为解码层统一后的 working space（RAW 解码或栅格链
  RasterColorDescription 归一），色彩空间差异天然归一；无跨 ICC 统计问题。
- 声明面：TRACK-05「裁剪策略明确」= 本节政策 + 面板 readout 一行
  （支撑域外输入占比，可选）。

### 3.5 多参考聚合（TRACK-02）

- **推荐统计级加权池化（OQ-M5-1-5）**：
  `μ_pool = Σ w_i μ_i`；
  `Σ_pool = Σ w_i (Σ_i + (μ_i − μ_pool)(μ_i − μ_pool)^T)`
  （混合分布二阶矩；CDF 族 = 直方图加权合并）。单解、确定、权重 UI =
  参考列表行滑杆（归一化权重）。
- 备选：逐参考求解后 α 混合（实现更简但语义弱——混映射 ≠ 混分布）；v1 不做，
  语义差异在 plan 期以测试注记。

## §4 交互面（TRACK-04）

- **入口**：Grade 层 add-module 菜单 `colormatch` → 面板「选取参考…」（库内图
  选择器 / 文件面板）；拖拽参考图入面板 = 快捷路径（复用既有导入 drag-drop
  语义）；选择后自动求解（后台任务，BackgroundTaskHosting 三腿协议先例）并
  切预览。
- **面板**：参考图缩略（复用 MaskThumbnailRenderer 同型 GPU 缩略先例）+ 求解
  readout（solver/statsHash/strength）+ strength 滑杆（D-H1 live 三件套）+
  before/after（9-4 三形态既有面：split / hold / projectedState override）。
- **性能预算**：求解 = 统计（preview 桶 GPU bin 计数，ms 级）+ 闭式解
  （μs 级）——交互即时；应用 = 线性臂 ≈ 一次 3×3 乘（同 colorWheels 量级，
  60fps 预算内）/ LUT 臂 = lut3d 同量级（既有预算内）。100MP 交互面复用
  PREVIEW 桶 + per-ROI cache（零新管线机制）。

## §5 match_color MCP 工具面（MCP-09 研究项 C 兑现）

- **工具签名草案**（OQ-M5-1-6 推荐最小面）：
  `match_color(reference, targets?, strength?, solver?, attach?)`
  - `reference`：库内 image id 或路径（load_image 语义同源）；
  - `targets`：缺省 = 当前图；数组 = 批量（**逐目标独立求解**——源统计逐图
    不同，同参考不同目标解不同；工具内 fan-out 一次调用）；
  - `strength`/`solver`：缺省 1.0 / gaussian-ot；
  - `attach`（默认 true）：自动落位 colormatch 实例（AddClean 同型命令缝）并
    返回 `{op, instanceId, params 摘要, statsHash/求解哈希}`；false = 只返回
    参数组由 agent 自行 apply_params 落位。
- **会话闭环**：match_color 落位 → agent 用既有 `apply_params` 微调
  strength/参数 → `render_preview` 验收（全部既有工具面，零新增）；colormatch
  注册后 `list_iops` / apply_params 元数据自动可用（IopCatalog 既有机制）。
- **确定性承诺**：同 reference + 同 target + 同 params → 同解哈希（G1 门，
  agent 可自行复验）；哈希随工具返回值披露。
- **安全面**：复用 MCP server 既有绑定/鉴权面（Phase 14；回环默认 + token）；
  零新网络面、零新依赖。

## §6 golden 与确定性门（TRACK-05）

| 门 | 内容 | 判据 |
|---|---|---|
| G1 求解确定性 | 同输入统计 → bit-identical 矩阵/LUT 字节 | 跨进程复跑逐字节；SVD 符号约定固定 + 整数秩统计 + 退化回落路径确定（FilmSolveCache bit-identity 先例体例） |
| G2 kernel parity | Metal kernel vs Float64 CPU 参考 | 线性域分级容差先例（M2-5 p99.9 ≤1e-5 目标；实测带收窄钉门纪律 = M3-3/M4-1 先例——1e-5 目标、实测值落带后钉实测） |
| G3 语义 golden | 合成参考对：合成源图 + 精确已知线性变换 → 参考图；求解应恢复该变换 | 恢复误差 ≤ 容差（解析可验）+ 自然样张目测走查 |
| G4 MCP 端到端 | match_color → apply → render_preview 与本地渲染量化一致 | Phase 14 SC#3 同型 |
| G5 恒等回归 | colormatch 缺席 / 禁用 / strength=0 | 逐字节直通（L031 恒等红线惯例；identityJSON 种子同型） |

## §7 交付切分建议（M5-1 内 plan 波次；OQ 裁决后 plan 期细化）

估 2-4 plans（执行分工照 Phase 执行模型 = omp 执行 + subagent 验收；测试落域
按 BUNDLE-MAP 规则 + `tuist generate` 尾闸）：

- **Plan 01**：统计提取（Oklab + 整数秩 + 截尾）+ S1/S3 求解器（Core 纯函数，
  零 UI）+ G1/G3 golden（Core/Library 域 bundle）。
- **Plan 02**：`colormatch` iop + kernel + 线性臂落位 + 面板交互（TRACK-03/04）
  + G2/G5（IOP/App bundle）。
- **Plan 03**：S2 CDF + LUT 臂（若 OQ-M5-1-1/-3 裁做）+ 多参考聚合 UI
  （TRACK-02）。
- **Plan 04**：`match_color` MCP 工具 + G4（App bundle；S2 裁不做时可并入
  Plan 03）。

## §8 风险

- **R1 SVD 符号/退化协方差**（秩亏源图，如单色/低方差）：符号约定固定 +
  正则化 ε + 退化回落对角特例（S3 路径天然兜底；回落行为进 G1 断言）。
- **R2 Oklab 转换精度**：float32 解析式直算，风险低；往返精度 G2 覆盖。
- **R3 S2 通道独立色相漂移**：已知弱点；strength 混合缓解 + OQ 裁做范围
  （不裁 S2 则面板默认档 = S1）。
- **R4 参考图分辨率/内容差异**：统计归一化 + 分位截尾；极端失配（如参考为
  单色卡）= 求解合法但视觉无意义——面板披露统计支撑域宽度 readout。
- **R5 sidecar 膨胀**：线性臂 12 floats 零负担；LUT 臂走派生资产位不进
  paramsData（OQ-M5-1-3 裁）。
- **R6 蒙版边缘一致性**：colormatch 走 grade 层蒙版 = 既有 blendop 语义
  （feather→invert→opacity→clamp），无新语义；蒙版内/外过渡 = 既有 Deriche
  feather 腿，无 R。

## §9 Open Questions 汇总

OQ-M5-1-1..8 全部带推荐——正文与推荐项见 `M5-1-CONTEXT.md`（C 档第 1 停裁决面）；
本文件各节已按推荐项展开设计，裁决推翻推荐时相应节随 plan 期修订。

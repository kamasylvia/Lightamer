---
phase: m5-1
plan: "M5-1-01"
title: "TRACK P1——Oklab 统计域转换（linear Rec2020↔Oklab，Float32 产线 + Float64 孪生）+ 统计提取纯函数面（256-bin 整数秩直方图 + 1%/99% 截尾支撑域 + 矩 + statsHash）+ S1 Gaussian OT 闭式求解 + S3 Reinhard 对角特例（SPD 平方根唯一性 + 退化回落确定）+ 求解缓存（FilmSolveCache 同构 LRU 8）+ colormatch op 核心（IOP 模块 + colormatch_linear kernel + V50Order 36.5 原生行 + GradeCatalog 第 20 行 + Registry 注册 + IopCatalog 行）+ 线性臂 params 直存 + G1/G2/G3/G5 四门 golden + G5 恒等三态 + 可加不可编占位落位"
wave: 1
depends_on: []
autonomous: true
requirements: ["TRACK-01（S1/S3 半 + 统计提取面）", "TRACK-03（op 核心与线性臂；面板/交互 = M5-1-02）", "TRACK-05（G1/G2/G3/G5 四门；G4 = M5-1-03）"]
estimated_tests: "+34..42"
test_bundles: [LAYERS, IOP, IOPParity, APP]
files_modified:
  - LightamerCore/Sources/ColorMatch/OklabMath.swift            # 新建：linear Rec2020↔Oklab Float32 产线 + Float64 golden 孪生（公开解析式；常数来源注释单源）
  - LightamerCore/Sources/ColorMatch/ColorMatchStats.swift      # 新建：ColorMatchStats 值类型（μ/Σ/3×256 整数直方图/支撑域界/statsHash）+ 样本级提取纯函数（整数秩分位 + Float64 矩累积）
  - LightamerCore/Sources/ColorMatch/ColorMatchSolver.swift     # 新建：S1 Gaussian OT 闭式 + S3 Reinhard 对角 + ColorMatchSolution（matrix/offset Float32 存储 + effectiveSolver + stableHash）+ strength 语义常量
  - LightamerCore/Sources/ColorMatch/ColorMatchSolveCache.swift # 新建：fnv(srcStatsHash ⊕ refStatsHash ⊕ solverTag) 键 + NSLock LRU 8 + invalidateAll（FilmSolveCache 同构）
  - LightamerIOP/Sources/ColorMatch/ColormatchModule.swift      # 新建：op `colormatch`——Params（solver/matrix[9]/offset[3]/strength/statsHash 对 L013 decimal String）+ identity blit（strength 0 / 未求解 = makeRoutedCommandBuffer，L031）+ iopOrder 36.5 + flags [.supportsBlending, .allowTiling]
  - LightamerIOP/Sources/ColorMatch/ColorMatchKernels.metal     # 新建：colormatch_linear 单 pass（px→Oklab→α-lerp 矩阵映射→Oklab⁻¹→out；Oklab 常数 MSL 直写、来源同 OklabMath 注释）
  - LightamerIOP/Sources/ColorMatch/ColorMatchUniforms.swift    # 新建：flat uniform ABI（3×3 + offset + strength，零 function constants；size-probe 钉 ABI）
  - LightamerIOP/Sources/Registry.swift                         # 修改：colormatch 注册（seed ABSENT——grade 目录 op 随面板入编辑种子惯例；defaultFaceDisabledOpNames 零触碰）
  - LightamerIOP/Sources/NodeOwnershipCatalog.swift             # 修改：GradeCatalog 第 20 行（owner .grade；identityJSON = Params() 恒等核）
  - LightamerCore/Sources/Foundation/V50Order.swift             # 修改：colormatch 36.5 原生行（add-only；lut3d 36.0 与 colortransfer 37.0 之间空隙；106→107）
  - App/Sources/Lightamer/MCP/Tools/IopCatalog.swift            # 修改：colormatch additive 行（strength/solver 标量 + matrix/offset 载体注记；guard 自动核键集）
  - Resources/Localizable.xcstrings                             # 修改：colormatch 显示名键尾块纯插入（按既有 grade 目录 op 显示名机制；预期 +1..2 键）
  - Tests/LightamerTests/ColorMatchOklabTests.swift             # 新建（LAYERS/Core 级）：公开常数锚 + 往返门 + Float32/Float64 孪生带
  - Tests/LightamerTests/ColorMatchStatsTests.swift             # 新建（LAYERS/Core 级）：直方图域映射/整数秩分位/截尾/矩/statsHash 逐字节
  - Tests/LightamerTests/ColorMatchSolverGoldenTests.swift      # 新建（LAYERS/Core 级，G1/G3）：bit-identity 双跑 + 退化回落确定 + 合成参考对恢复
  - Tests/LightamerTests/ColormatchModuleTests.swift            # 新建（IOPParity，模块面）：serde 往返/hash 零漂移/identity blit 路径/flags/order
  - Tests/LightamerTests/ColormatchKernelParityTests.swift      # 新建（IOPParity，G2）：kernel vs Float64 CPU 参考（L048 比较域纪律）
  - Tests/LightamerTests/ColormatchIdentityGoldenTests.swift    # 新建（IOPParity，G5）：缺席/禁用/strength=0 三态逐字节直通
  - Tests/LightamerTests/V50OrderTests.swift                    # 修改：106→107 + 36.5 行唯一性/邻域断言（additive 申报内更新；IOP bundle）
  - Tests/LightamerTests/GradeCatalogTests.swift                # 修改：第 20 行断言（19→20；APP bundle）
  - Project.swift                                               # 修改：新测试文件登记对应 target 数组（显式清单无 glob）+ tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：新测试文件增行登记（E2 纪律，随各自任务 commit）
  - .work/gsd/phases/m5-1-track/M5-1-01-SUMMARY.md              # 新建（收口）
  - .work/gsd/phases/m5-1-track/M5-1-01-DECISIONS.md            # 新建（收口）
  - .work/gsd/phases/m5-1-track/M5-1-01-ACCEPTANCE.md           # 新建（双重验收记录——zcode PASS 后串行 omp 二次验收）
  - .work/GOAL-STATE.md                                         # 修改：续接点
  - .work/TODO.md                                               # 修改：M5-1 条目
  - .work/LESSONS.md                                            # 如踩坑
---

# Plan M5-1-01 — TRACK P1：统计域 + S1/S3 求解器 + colormatch op 核心（G1/G2/G3/G5）

> **性质**：M5-1 三 plan 之首。本批交付追色族的**全部 Core 数学面 + colormatch op
> 线性臂**：Oklab 统计域转换 → 统计提取纯函数 → S1 Gaussian OT / S3 Reinhard
> 求解 → 求解缓存 → colormatch iop 注册落位（36.5）→ 四门 golden。**生产行为
> 唯一可见变化 = add 菜单出现 colormatch 行（可加不可编恒等占位——filmPlacement
> 先例）**；无实例 = 渲染逐字节零变化（G5 钉死）。面板/交互（TRACK-04）= M5-1-02，
> MCP `match_color`（G4）= M5-1-03。规格正本 = `RESEARCH-NOTES.md` §3.1/§3.2/§3.3/§3.4
> （file:line 均为 2026-10-11 HEAD 亲核）；裁决正本 = `M5-1-CONTEXT.md` 裁决记录
> （OQ-1..8 全按推荐，2026-10-11 用户回批）。
>
> **基线**：**3335/16/0**（M4-1-VALIDATION 2026-10-10 终验 `TOTAL|3335/16/0|1604s`
> 亲跑；逐 bundle IOP 562 / IOPParity 427 / Layers 394 / Library 619 / Sessions 279 /
> Export 350 / App 704；M4-2 删除批回落同值逐位验证）。M4-3 +31 后全套推算
> **3366/16/0 未跑 `--all`**（M4-3-VALIDATION 在案，定向三 bundle 1748）——本
> phase 对账链 = 「3335/16/0 + 各批增量」逐位推算；全套 `--all` 轮照批准制
> （AGENTS 资源监控节）。IOP 贴线纪律：本批全部新测试用小 fixture（≤4MP）/33³
> 网格/合成样本集，零 100MP 单测。

## 已定裁决（生效值，硬约束，不得重开）

M5-1 OQ-1..8 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-11，用户回批）。八项生效值的全 phase AC 落位分账：**本 plan 承载 ①②③(线性臂半)④(截尾+矩阵臂半)⑦⑧(G1/G2/G3/G5)**；③(.cube 资产半)④(65³+平台面半)⑤ = M5-1-02；⑥⑧(G4) = M5-1-03。本 plan 相关生效值逐条：

1. **OQ-1（三档全交付）**：S1 Gaussian OT 闭式线性映射（主打）+ S3 Reinhard 对角（= S1 关协方差特例，TRACK-01 点名项）本批交付；S2 per-channel CDF = M5-1-02；Sinkhorn 不做。
2. **OQ-2（统计域 Oklab）**：统计/求解/应用插值全部在 Oklab 域；应用域 = working linear Rec2020 恒等直出（不引入应用编码转换——线性臂无 LUT 无编码语义问题）。
3. **OQ-3（op 形态与载体）**：新独立 op `colormatch`（不塞 lut3d）；**线性臂（S1/S3）参数直入 params**（矩阵+offset+strength+哈希——sidecar 零负担、可手调、零 schema 升级）；LUT 臂 .cube 派生资产 = M5-1-02。
4. **OQ-4（截尾与域端）**：统计前 1%/99% 分位截尾定义支撑域（整数秩，禁浮点插值）；**矩阵臂全定义域**（无域端裁剪问题）；65³/平台面 = M5-1-02 LUT 臂。
7. **OQ-7（蒙版/region）**：colormatch 走 grade 层 = `supportsBlending` 旗标 + GradeCatalog owner `.grade`（既有蒙版体系自动可用，零新机制）；参考侧统计域 = 全图（本 plan 统计函数面即全图语义；提取适配器 = M5-1-02）。
8. **OQ-8（五门）**：G1 求解确定性 / G2 kernel parity / G3 语义 golden / G5 恒等回归本批落位；G4 = M5-1-03；五门收口复验 = M5-1-03。

**架构红线（本 plan 全程 + checker 机检面）**：
- **零新 SPM 依赖**（全站 M5 红线；Oklab = 公开解析式自写，零外部库）。
- `V50Order` add-only 纪律：仅增 `colormatch` 36.5 一行（原生行注记格式照 filmPlacement 20.8 先例）；不重排、不复位。`V50OrderTests` 106→107 为申报内更新。
- `defaultFaceDisabledOpNames` **零 diff**（colormatch seed ABSENT = 注册不种子，可加不可编占位，filmPlacement 先例）；`lut3d` 密封面（Lut3dModule/CubeLutParser/LutLibraryStore/Lut3dKernels.metal）**零触碰**。
- sidecar **零 schema 变更**（新 op 参数走 registry/ModuleInstance paramsData 既有通道）；`HistoryStack`/`HistoryHash`/`PipelineDocument`/`NodeGraphCommand`/`ModuleInstance`/`PipeCacheKey` 零触碰（paramsHash 驱动缓存 = 零新机制）。
- 全 `.metal` 新增面申报：仅 `ColorMatchKernels.metal` 一文件一 kernel（`colormatch_linear`）；零 function constants。
- Core↔IOP 边界：Oklab/stats/solver 全在 Core（`LightamerCore/Sources/ColorMatch/`，可单测）；IOP 只持模块 + kernel + uniforms（不 import 新 Core 面以外的任何东西）。
- M2-7 起的封存面清单（AGENTS M3-3 节）中 `Lut3dKernels.metal`/`PixelPipe`/`Registry` 密封语义不破——Registry 仅 additive 注册块（lut3d 注册块同款注释格式）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 Oklab 转换面（T1，OQ-2 生效值；RESEARCH §3.1）

- 公开解析式自写（Björn Ottosson Oklab 公开常数：linear RGB→LMS 锥响应矩阵→cube root→opponent 轴；常数为公开数学常数非任何 GPL 仓代码）。**常数来源注释单源**：`OklabMath.swift` 文件头注记来源与精度说明；MSL 侧常数注释指向同源。
- **Float32 产线 + Float64 孪生同文件**：产线（kernel 消费口径）= Float32；golden 孪生 = Float64（比较域纪律 L048：一律 decode 回 linear + `Double(Float(x))` 升维）。
- 转换面 = `linearRec2020ToOklab` / `oklabToLinearRec2020` 双向；往返门（ Float32 往返实测带写 DECISIONS，先验假设 ≤1e-6；G2 parity 消费同带）。
- working space 常数复用 `LightamerCore/Sources/Foundation/WorkingSpace.swift`（线性 Rec2020 已在库；零新色彩空间定义）。

### KD-2 统计提取面（T2，OQ-4 截尾半；RESEARCH §3.1）

- **输入 = 样本集**（`[[SIMD3<Float>]]` Oklab 域样本——平面 tap 适配器在 M5-1-02；本 plan 统计函数消费样本值，测试以合成样本直驱）。Core 纯函数、确定性、零 IO。
- `ColorMatchStats` 字段面：`mu: SIMD3<Float>` / `sigma: (Float, Float, Float, Float, Float, Float)`（对称 3×3 六元组，行主序 σxx σxy σxz σyy σyz σzz）/ `histograms: [[UInt32]]`（3×256 整数计数）/ `supportLo/supportHi: SIMD3<Float>`（1%/99% 截尾界）/ `sampleCount: Int` / `statsHash: UInt64`（FNV-1a over 字段规范序字节——L013 确定性字节面；哈希域 = 产线 Float32 位模式，非 Float64）。
- **直方图域映射（钉死）**：L ∈ [0,1] 线性映射 256 bin；a/b ∈ [−0.5, +0.5] 对称映射 256 bin；域外 clamp 到端 bin（计数不丢）。整数 bin 索引 = `Int((v−lo)/(hi−lo)·255)` 截断（Float32 序，禁插值——FilmSolveCache 整数秩先例）。
- **截尾**：逐通道 1%/99% 分位 = 直方图整数秩爬梯（累积计数 ≥ ⌈0.01·N⌉ 的首 bin / ≥ ⌈0.99·N⌉ 的首 bin）；支撑域界 = 截尾 bin 的域值。
- **矩**：支撑域内样本 Float64 累积（μ 与中心化二阶矩）；输出降格 Float32 存储。矩计算与直方图同遍（顺序固定 = 样本序）。
- statsHash 覆盖 = 直方图计数 + sampleCount（矩为派生物不重复入哈希——直方图即分布的充分统计面）。

### KD-3 求解族（T3，OQ-1 生效值；RESEARCH §3.2）

- **S1 Gaussian OT 闭式**：`M = Σt^{1/2} · A · Σs^{−1/2}`，`A = (Σs^{−1/2} Σt Σs^{−1/2})^{1/2}`；平移项 `offset = μt − M·μs`。数学关键面：**SPD 矩阵主平方根唯一**（与特征向量符号/基选取无关——对称特征分解的符号翻转在重构 `V D^{1/2} Vᵀ` 中不变）→ G1 bit-identity 数学可达；数值确定性 = **固定算法阶梯**（对称矩阵 Jacobi 特征分解、固定旋转扫描序 + 固定收敛门；禁调用 LAPACK/accelerate 跨版本不定路径）。
- **正则化与退化回落（R1，钉死）**：`Σ + εI`（ε = 1e-12·trace(Σ)）先行；最小特征值 < 1e-9·trace（秩亏——单色/低方差源图）→ **回落 S3 对角路径**（`effectiveSolver = .reinhardFallback` 记录；params solver 保持用户选择；G1 断言回落确定性）。
- **S3 Reinhard 对角**：`M = diag(σt_i/σs_i)`（逐轴，ε 地板同上）+ 同式 offset；= S1 关协方差特例，代码路径独立纯函数（不 share S1 内部）。
- **strength 语义（三档共用）**：`out_oklab = (1−α)·x + α·(M·(x−μs)+μt)`，α ∈ [0,1]；0 = 恒等。α 不进求解面（kernel 运行时 uniform——拖拽零重解）。
- `ColorMatchSolution`：`solver` / `effectiveSolver` / `matrix: [Float]`（9，行主序——**Float64 求解、Float32 存储的降格点钉死在此**，G1 断言存储字节面）/ `offset: [Float]`（3）/ `sourceStatsHash` / `referenceStatsHash` / `strength 默认 1.0 不入解`（strength 是 params 面）+ `stableHash()`（FNV-1a over sorted-keys JSON——L013/DrtRecord 同款）。
- **求解缓存**：`ColorMatchSolveCache`（FilmSolveCache 同构：NSLock + 插入序 LRU 8 + `invalidateAll()`）；键 = `fnv(sourceStatsHash ⊕ referenceStatsHash ⊕ solverTag)`（小端折叠序精确值钉死——FilmSolveCache 先例体例）。

### KD-4 G1/G3 golden（T4，OQ-8；RESEARCH §6）

- **G1 求解确定性**：①同统计输入双跑 → solution 逐字节（matrix/offset Float32 位模式 + stableHash）；②退化输入（单色/秩亏样本集）→ 回落路径确定（双跑同 effectiveSolver 同解）；③求解缓存命中/未命中同解（缓存透明性）；④缓存键折叠序 = DECISIONS 记录精确值（FilmSolveCache 折叠序钉死先例）。
- **G3 语义 golden**：合成参考对——LCG 常量种子（FilmPrintBake 先例）生成确定性源样本集（Oklab 域，含设定 μs/Σs）；参考集 = 已知 `T_true`（固定矩阵+offset）映射产物（矩精确匹配构造或大 N 采样——容差带写 DECISIONS）；solve(源, 参考) 恢复 `T_true`：矩阵元素相对误差 ≤ 1e-3（矩精确构造臂）/ 实测带（采样臂）；S3 同法对角恢复。自然样张目测 = M5-1-02 GUI 走查（OQ-8 备选 A 默认形态）。

### KD-5 colormatch op（T5，OQ-3/OQ-7 生效值；RESEARCH §3.3）

- **模块**：`ColormatchModule`（Lut3dModule 结构孪生：`opName = "colormatch"` / `iopOrder = 36.5` / `flags = [.supportsBlending, .allowTiling]` / `defaultColorspace = .RGB`）。
- **Params（线性臂直存，OQ-3）**：`solver: ColorMatchSolverKind`（枚举 `{gaussianOT, reinhard}`——`.cdf` case M5-1-02 additive，枚举本轮两值）/ `matrix: [Float]`（9，行主序）/ `offset: [Float]`（3）/ `strength: Float`（默认 0 = 恒等核）/ `sourceStatsHash: String?` / `referenceStatsHash: String?`（**L013 decimal String wrapper**——UInt64 入 sidecar 纪律）/ `effectiveSolver: ColorMatchSolverKind?`（回落诊断面，additive optional）。serde = decodeIfPresent 宽容（未知 solver rawValue → nil 恒等降格，Lut3dModule inputEncoding 同款）；**默认 Params() 编码逐字节 = 恒等核**（paramsHash 零漂移专测——M3-1 hash 零漂移专测同款）。
- **identity blit（L031 红线）**：`strength == 0` 或 statsHash 对缺一（未求解态）→ `makeRoutedCommandBuffer()` blit 恒等（cache-neutral、exposure-0EV style；Lut3dModule lutName nil 同款）。kernel 只在非恒等态 dispatch。
- **V50Order 原生行**：`("colormatch", 36.5)`——注记 = LIGHTAMER-NATIVE ROW（NOT a dt entry——Plan M5-1-01 T5，OQ-M5-1-3）：sits between lut3d (36.0) and the dt-verbatim colortransfer (37.0)——追色落在 lut3d 同邻域（creative band，层内合法性 < 70.0 floor）。dt 纪律（no reorder / unique / add-only）照 66.5/20.8 先例全文。dt 的 `colortransfer` 37.0 / `colormapping` 38.0 verbatim 行**零触碰、保持未注册**（dt 模块本身未移植；表行是 verbatim 港口）。
- **GradeCatalog 第 20 行**：`catalogID: "colormatch"` / owner `.grade` / `identityJSON = json(of: ColormatchModule.Params())` / `panelExposures: ["strength"]`（M5-1-02 面板消费；filmPlacement 先例——可加不可编占位至面板落地）。`NodeOwnershipCatalog` 18 目录注册表零新目录。
- **Registry 注册**：`register(opName: ColormatchModule.opName)`，**seed ABSENT**（CAT02 注记同款——grade 目录 op 随面板入编辑种子；本 plan 面板未落地 = 纯 addable）；注册块注释照 lut3d 块格式。
- **IopCatalog additive 行**：strength（number）/ solver（string）/ matrix（number[]）/ offset（number[]）/ sourceStatsHash 等（string）；guard（键集 == 模块默认编码键集 + version）自动核验——McpEditingToolsetTests 既有面零改动即覆盖新行（若 guard 需要 version 初值登记则随行）。

### KD-6 kernel 面（T6/T7）

- `ColorMatchKernels.metal` 单 kernel `colormatch_linear`：threadgroup 16 惯例；单 pass = px（linear Rec2020 float32）→ Oklab（MSL 内联常数）→ `(1−α)·x + α·(M·(x−μs)+μt)` → Oklab⁻¹ → out。**μs/offset 合并**：CPU 侧预合成 `b = offset + (1−α)·μs·? ` —— 不预合成（α 运行时可变；kernel 直算 `M·(x−μs)`，uniform 携 M/μs/α 13 floats + padding）——**executor 可在 bit-identity 前提下合并常数（预计算 `M·(−μs)+μt` 一项随 α 变化需重算——恒定项 = μt − M·μs 与 α 无关，α-lerp 展开为 `x + α·((M−I)·x + (μt−M·μs))`，uniform 携 `M−I` 与 `c = μt−M·μs` 12 floats + α，乘加 6 次——推荐此形，DECISIONS 记展开式与 G2 参考实现同步）**。
- `ColorMatchUniforms.swift`：flat struct（零 function constants；size-probe 钉 ABI——DrtAces2 uniform 588×16B 先例体例）。
- 失败形态 typed：PSO 建失败/device 错误 → `AppError` 族（模块 process throw 路径照既有 iop 惯例）。

### KD-7 G2/G5 门（T7/T8，OQ-8；RESEARCH §6）

- **G2 kernel parity**：`colormatch_linear` vs `OklabMath` Float64 CPU 参考（同解矩阵/offset 注入）。驱动集 = 33³ 网格 × {S1 解, S3 解, 随机解} × α ∈ {0.0, 0.25, 0.5, 1.0}；判据 = **p99.9 ≤ 1e-5 目标 + 实测带收窄钉门**（M3-3/M4-1 纪律：实测值落带后钉实测带为门——目标值不进最终断言）；L048 比较域纪律；fence 纪律 L014。
- **G5 恒等回归（L031 惯例）**：三态逐字节直通——①colormatch 缺席（默认 face，注册不种子）②实例存在但 disabled ③实例 enabled + strength=0。断言面 = 渲染输出逐字节（恒等链既有 golden 输出对照）+ 既有 IOP/IOPParity 全量逐位基线零漂移（本 plan 未触既有 op）。

### KD-8 可加不可编占位（filmPlacement 先例）

- P1 落位后：add 菜单可见 colormatch（GradeCatalog 行自动出现）；加实例 = Params() 默认 = strength 0 = 恒等（G5③钉死）；无编辑面板（M5-1-02 落地）。「可加不可编恒等占位」语义照 filmPlacement（M3-3-03）——**占位期间 xcstrings 仅显示名键**（solver/strength 等面板键 M5-1-02 随面板入册）。

## read_first

1. `.work/gsd/phases/m5-1-track/M5-1-CONTEXT.md`（裁决记录 = 八项生效值正本）+ `RESEARCH-NOTES.md` §3（算法设计全文——本 plan file:line 锚的正本）
2. `LightamerIOP/Sources/Lut3d/Lut3dModule.swift` 全文（模块结构/Params serde/identity blit/flags/order 先例——ColormatchModule 的直接孪生源）
3. `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift` :380-500（FilmStatsSeam 整数秩直方图 + statsHash FNV 字节面 + FilmSolveCache LRU 体例）
4. `LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift` 头注（65³/Float64/确定性先例——M5-1-02 bake 的体例正本，本 plan 只消费其纪律）
5. `LightamerCore/Sources/Foundation/V50Order.swift`（add-only 行注记格式：acesccIn 20.5 / filmPlacement 20.8 / skinSmooth 66.5 三例）+ `Tests/LightamerTests/V50OrderTests.swift`（count/unique/floor 断言面）
6. `LightamerIOP/Sources/NodeOwnershipCatalog.swift` :160-280（GradeCatalog 19 行 + filmPlacement 第 19 行先例）
7. `LightamerIOP/Sources/Registry.swift`（lut3d/CAT02 注册块注释格式 + seed ABSENT 惯例 + defaultFaceDisabledOpNames 面）
8. `App/Sources/Lightamer/MCP/Tools/IopCatalog.swift`（手写表 + guard 机制 + additive 扩展申报）
9. `LightamerCore/Sources/Foundation/StableHash.swift` + `WorkingSpace.swift`（FNV/线性 Rec2020 常数）
10. `Tests/LightamerTests/Lut3dKernelTests.swift` + `Lut3dGoldenImageTests.swift`（IOPParity GPU 测试基建：fence L014/网格驱动/L048 比较域）
11. `.work/gsd/phases/m3-3-fsim/M3-3-03-PLAN.md`（golden 门两级分解 + LCG 常量种子 + 平滑域筛选先例）+ `.work/gsd/phases/m4-1-tiff-raster/M4-1-01-PLAN.md`（本文件体例正本）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+ `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh --bundle <域>`（直启宿主）；全套 `--all` 需 orchestrator 批准，本 plan 收口轮才申请。
- **GPU 读回 fence（L014）**：parity/identity 测试读纹理前必须 queue fence（`drain()` 模式）。
- **比较域（L048）**：golden 一律 decode 回 linear + `Double(Float(x))` 升维；Oklab 域比较只在孪生带测试内做（产线断言回归 working 域）。
- **零 diff 红线自证**：收口任务跑 `git diff <基线SHA>..HEAD -- LightamerIOP/Sources/Lut3d/ LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Pipe/History/ LightamerCore/Sources/Pipe/PipeCacheKey.swift LightamerCore/Sources/Pipe/PipelineDocument.swift` 零命中并记录入 SUMMARY。
- **资源监控**（AGENTS）：跑测试宿主期间照常巡检；IOP/IOPParity 贴线 bundle 若 MEMFAIL 先查重测漂移再查本批（新测试均小 fixture/合成集，理论零增量）。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 Oklab 转换面（KD-1）

- read_first 1/9 → `OklabMath.swift`（双向 Float32 产线 + Float64 孪生 + 常数来源头注）。
- 验收：`ColorMatchOklabTests`（LAYERS）——公开常数锚点（白点/原色样本点对已发布参考值，硬编码）；往返门（Rec2020 色域角点 + 灰轴 + 随机集，Float32 往返实测带入 DECISIONS）；Float32/Float64 孪生带；负分量/超域输入行为断言（clamp 政策记录）。

### T2 统计提取面（KD-2）

- read_first 1/3 → `ColorMatchStats.swift`（值类型 + 提取纯函数：直方图/截尾/矩/statsHash）。
- 验收：`ColorMatchStatsTests`（LAYERS）——直方图域映射逐 bin（L 与 a/b 两域 + 端 bin clamp）；1%/99% 整数秩分位（构造分布精确断言）；矩对解析值（高斯样本集 vs 闭式）；statsHash 双跑逐字节 + 字段敏感（改一计数翻哈希）；空样本集 typed 行为。

### T3 S1/S3 求解器 + 缓存（KD-3）

- read_first 1/3/11 → `ColorMatchSolver.swift` + `ColorMatchSolveCache.swift`。
- 验收：编译绿；求解器单元面（SPD 平方根唯一性数学断言——同矩阵不同特征基路径同根）；缓存命中/未命中同解 + LRU 驱逐 + invalidateAll。**求解正确性主断言在 T4 G3**（本任务只钉结构面）。

### T4 G1/G3 golden（KD-4）

- read_first 1/11 → `ColorMatchSolverGoldenTests`（LAYERS）。
- 验收：G1 四断言（双跑逐字节/退化回落确定/缓存透明/键折叠序 DECISIONS 记录）；G3 合成参考对恢复（S1 矩精确构造臂 ≤1e-3 + S3 对角恢复 + 实测带入 DECISIONS）；LCG 种子可再生（生成器双跑同集）。

### T5 colormatch 模块 + 注册 + 目录行（KD-5）

- read_first 2/5/6/7/8 → `ColormatchModule.swift` + `Registry.swift` 注册块 + `V50Order.swift` 36.5 行 + `NodeOwnershipCatalog.swift` 第 20 行 + `IopCatalog.swift` additive 行 + xcstrings 显示名键。
- 验收：`ColormatchModuleTests`（IOPParity）——serde 往返/未知 solver 降格/默认 Params 编码逐字节恒等核（hash 零漂移专测）/identity blit 路径（strength 0 → blit 非 kernel）/flags/order 静态断言；`V50OrderTests` 107 + 36.5 唯一性 + floor 关系；`GradeCatalogTests` 20 行；zh-audit `--check` 对新键绿。

### T6 kernel + uniforms（KD-6）

- read_first 2/10 → `ColorMatchKernels.metal` + `ColorMatchUniforms.swift`。
- 验收：编译绿（`tuist generate` 尾闸）；PSO 建成；uniform size-probe 钉 ABI；常数与 OklabMath 同源注释在册；`.metal` 新增面申报 = 本文件（红线自证清单入 SUMMARY）。

### T7 G2 kernel parity（KD-7）

- read_first 10 → `ColormatchKernelParityTests`（IOPParity，fence 纪律）。
- 验收：33³ × 3 解 × 4 α 档 parity 实测带入 DECISIONS（p99.9 目标 1e-5、实测收窄钉门）；**kernel 展开式与 CPU 参考逐项同步**（KD-6 推荐形若采纳，参考实现同式——防「同值异式假 parity」）；L048 比较域纪律断言头注。

### T8 G5 恒等三态 + 基线零漂移（KD-7）

- read_first 10 → `ColormatchIdentityGoldenTests`（IOPParity）。
- 验收：三态逐字节直通（缺席/禁用/strength=0）；恒等链对照 = 既有 golden 输出（字节比对）；定向轮 IOP/IOPParity 全量逐位基线零漂移（本 plan 零触既有 op 的铁证）。

### T9 收口

- SUMMARY（任务序/实测带/bundle 分账/红线自证清单）+ DECISIONS（KD 偏差/G2 实测带/G3 恢复带/statsHash 折叠序/往返带）+ GOAL-STATE 续接点（M5-1-02 待启）+ TODO 同批。
- 验收：定向轮 `--bundle LAYERS/IOPParity/APP` 全绿（exit 0 + 零 MEMFAIL）；zh-audit `--check` 绿；零 diff 红线清单（KD 红线节全项）亲证入 SUMMARY。
- **双重验收（config `dual_acceptance = true`）**：zcode subagent 独立验收 PASS 后 → **串行** omp 二次验收（**严禁并发**——computer-use 单实例，config 硬约束）；两路结论落 `M5-1-01-ACCEPTANCE.md`；FAIL 回注修复批后重走验收。

## 验收标准（AC 总表）

1. **生效值①（三档之 S1/S3）**：S1 Gaussian OT 闭式 + S3 Reinhard 对角双求解器在册（`ColorMatchSolver`），S3 为独立纯函数路径，strength 三档共用语义常量在册。【T3/T4】
2. **生效值②（Oklab 域）**：统计/求解/应用插值全链 Oklab 域（转换面公开常数锚 + 往返门 + 孪生带）；应用域 = working linear Rec2020 恒等直出（kernel 出入域断言）。【T1/T7】
3. **生效值③（线性臂半）**：colormatch 独立 op 在册（iopOrder 36.5 + supportsBlending/allowTiling + seed ABSENT）；线性臂 params 直存（matrix/offset/strength/statsHash L013 decimal）；lut3d 密封面零触碰；sidecar 零 schema 变更。【T5】
4. **生效值④（截尾半）**：1%/99% 整数秩截尾 + 支撑域界在 `ColorMatchStats` 在册（构造分布精确断言）；矩阵臂全定义域（kernel 无域端钳制——HDR 值直通断言）。【T2/T7】
5. **生效值⑦（grade 层）**：GradeCatalog 第 20 行 owner `.grade` + supportsBlending = 既有蒙版体系自动可用（零新 blendop 面——BlendOp 路径零 diff 断言）；统计面全图语义（无 region 参数）。【T5】
6. **G1**：双跑 bit-identity + 退化回落确定 + 缓存透明 + 键折叠序记录。【T4】
7. **G2**：kernel parity 实测带收窄钉门（目标 1e-5），L048 纪律，uniform ABI size-probe。【T6/T7】
8. **G3**：合成参考对恢复 T_true（矩精确臂 ≤1e-3 + 采样臂实测带）+ LCG 可再生。【T4】
9. **G5**：三态逐字节直通 + IOP/IOPParity 既有基线逐位零漂移 + add 菜单可见但加实例 = 恒等（占位语义）。【T8】
10. **红线自证**：零新 SPM；V50Order add-only（106→107）；`defaultFaceDisabledOpNames`/lut3d 密封面/sidecar/HistoryStack/HistoryHash/PipeCacheKey/PipelineDocument 零 diff；`.metal` 新增 = ColorMatchKernels.metal 一文件。【T9】

## 风险与边界

- **SPD 平方根数值路径**：Jacobi 扫描序与收敛门固定后 bit-identity 可达；若实测带异常先查 FMA 熔合（swiftc/kernel 双侧哨兵——M4-1 R1-1 教训），命中即 pragma 处置并 LESSONS。
- **Oklab a/b 直方图域 [−0.5,0.5] 截断**：广色域极端值 clamp 端 bin——支撑域外样本不进矩（截尾语义覆盖），DECISIONS 记域宽选择依据（Rec2020 域 Oklab a/b 实测极值抽样入册）。
- **占位期误用面**：用户在 M5-1-02 前手工加 colormatch 实例（无面板、无求解）= 恒等占位，无数据风险（strength 0 直通）；面板落地后自然消解。
- **IOPParity 贴线**（基线 427 法，峰值历史 8104MB 贴 8192 门）：本批 parity 测试用 33³ 小网格 + 合成解（零 100MP/零大表）；若 MEMFAIL 先按 AGENTS 口径查重测漂移。
- **P2 衔接面**：`.cdf` solver case / .cube 资产 / 65³ bake / 面板 / 多参考池化全部在 M5-1-02；本 plan 交付面以 T9 红证清单为界。`ColorMatchSolverKind` 枚举本 plan 两值——P2 additive case 编译期破穷举 switch 的后果（IopCatalog/面板 switch 补臂）在 P2 申报。

## 提交约定

- T1 `feat(core): oklab conversion with float64 golden twin`
- T2 `feat(core): colormatch statistics with integer-rank trim`
- T3 `feat(core): gaussian-ot and reinhard color match solvers`
- T4 `test(core): solve bit-identity and synthetic recovery golden`
- T5 `feat(iop): colormatch op registration with v50 order row`
- T6 `feat(iop): colormatch linear kernel with oklab roundtrip`
- T7 `test(iopp): colormatch kernel parity golden`
- T8 `test(iopp): colormatch identity passthrough three states`
- T9 `docs(m5-1): close colormatch core batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。

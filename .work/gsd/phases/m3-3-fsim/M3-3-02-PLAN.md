---
phase: m3-3
plan: "M3-3-02"
title: "FSIM 管线批——film sub-run（负片段→滤色增益→印相段 baked LUT，fused kernel 单 pass）+ 运行期曝光归一统计腿（整数秩分位 + 求解缓存键）+ filmPlacement 可蒙版 grade op（V50 20.8 新行 + GradeCatalog 第 19 行）+ coordinator 持久化四件套 App 半面 + 导出 $jobFilmTail 递缝"
wave: 2
depends_on: ["M3-3-01"]
autonomous: true
requirements: ["FSIM-01a（管线面）", "FSIM-01b（运行期腿）"]
estimated_tests: "+36..46"
test_bundles: [Layers, IOP, IOPParity, App, Export]
files_modified:
  - LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift       # 新建：FilmTailPolicy/FilmTailParams/FilmTailAssembly（seed = fnv(recordHash ⊕ policyTag ⊕ solvedPackHash ⊕ upstream)）+ FilmSolveCache 键控
  - LightamerCore/Sources/Pipe/Film/FilmSubRunKernels.metal    # 新建：fused kernel（密度查表→底色→串扰→滤色增益→印相 LUT 四面体采样，单 pass）
  - LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift        # 新建：印相段 65³ 复合表 bake（Float64 CPU 参考 + concurrentPerform + LRU 16，bakedCompositeTable 同款机制；LutEncodingCatalog 零触碰）
  - LightamerCore/Sources/Pipe/PixelPipe.swift                 # 修改：filmTail 属性 + runFilmLeg（runDrtTailLeg 调用点同位前置——run() :723-724 / runSub() :864-865 两处）+ 终端驻留集降出查询点按 KD-1 3×2 矩阵扩臂 + RenderPipeline 传参（默认 nil = 零路径）
  - LightamerCore/Sources/Pipe/LayerCompositeDriver.swift      # 修改：filmTail 参数贯通（composite :204 签名 additive 默认参 + :546 终段管传递）
  - LightamerIOP/Sources/FilmPlacement/FilmPlacementModule.swift # 新建：filmPlacement grade op（RFC-023 恒等核+双侧支曲线，delta 形 bit-exact）
  - LightamerIOP/Sources/FilmPlacement/FilmPlacementKernels.metal # 新建：置位曲线 kernel
  - LightamerCore/Sources/Foundation/V50Order.swift            # 修改：LIGHTAMER 原生行 ("filmPlacement", 20.8)（acesccIn 20.5 与 exposure 21.0 之间）
  - LightamerIOP/Sources/NodeOwnershipCatalog.swift            # 修改：GradeCatalog 第 19 行（filmPlacement, owner .grade, identityJSON = 恒等点）
  - LightamerIOP/Sources/Registry.swift                        # 修改：注册 filmPlacement（默认面启用——恒等核）
  - App/Sources/Lightamer/State/PipeCoordinator.swift          # 修改：FilmRecord 持久化四件 App 半面（carrier/写腿/恢复腿/filmTailPolicy run 传点）+ 统计腿接线 + FilmMaterialStore 装配注入
  - App/Sources/Lightamer/State/EditorState.swift              # 修改：recordFilmChange/setFilmLive（recordDrtChange/setDrtLive 同构）
  - LightamerCore/Sources/Export/ExportRenderer.swift          # 修改：$jobFilmTail TaskLocal（$jobDrtTail 同款递缝三件套范式）+ process/processComposite 调用点传 filmTail
  - LightamerCore/Sources/Export/ExportQueue.swift             # 修改：Job.filmTail 字段（:60 drtTail 旁 additive）+ enqueue(filmTails:) per-image 索引参数 + precondition（:197/:203 同款）+ 渲染腿内 $jobFilmTail.withValue 包装（:417 嵌套一层）——checker 回注 2026-10-08 E1：detached 腿不继承 TaskLocal，载体面必须落本文件
  - App/Sources/Lightamer/State/ExportState.swift              # 修改：enqueueExportM2 恒装配 filmTail（drtOutput 强制联动同款）
  - Tests/LightamerTests/FilmLegTests.swift                    # 新建（LAYERS/Core 级）：seed 折叠/pristine 零路径/降出与重放序/DRT 叠序
  - Tests/LightamerTests/FilmPrintBakeTests.swift              # 新建（LAYERS/Core 级）：bake 确定性/LRU/域标定
  - Tests/LightamerTests/FilmPlacementDriverTests.swift        # 新建（LAYERS/Core 级）：ACEScc envelope 包裹/蒙版合法性/层链禁面不受扰
  - Tests/LightamerTests/FilmPlacementTests.swift              # 新建（IOP 级）：Params coding/注册面/恒等 JSON
  - Tests/LightamerTests/FilmPlacementKernelTests.swift        # 新建（IOPP 级）：恒等 bit-exact/单调性/膝点 m 阶接触（golden 体 = M3-3-03）
  - Tests/LightamerTests/FilmCoordinatorTests.swift            # 新建（APP/App 级）：carrier/写腿/恢复腿/thumbnail 恒 legacy/缺键 pristine
  - Tests/LightamerTests/ExportFilmChainTests.swift            # 新建（EXPORT/Core 级）：$jobFilmTail 递缝/装配恒联/无 film 零漂移
  - Project.swift                                              # 修改：测试登记（L041 批尾）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # 修改：增行登记（E2）
  - .work/gsd/phases/m3-3-fsim/M3-3-02-SUMMARY.md              # 新建
  - .work/gsd/phases/m3-3-fsim/M3-3-02-DECISIONS.md            # 新建
  - .work/GOAL-STATE.md                                        # 修改：续接点
  - .work/TODO.md                                              # 修改
  - .work/LESSONS.md                                           # 如踩坑
---

# Plan M3-3-02 — FSIM 管线批（wave 2）

> **性质**：M3-3 主打批——胶片段真正进入渲染。三根柱：①**film sub-run**（主链
> 顶面后固定点，负片段 fused kernel → 印相段 baked LUT，`DrtTailAssembly` 同款
> driver-constructed boxes + `runSub` 重放）；②**运行期统计腿**（曝光归一，整数
> 秩分位 + 求解缓存键）；③**filmPlacement 可蒙版 grade op**。持久化 App 半面与
> 导出递缝同批闭环。**FSIM-03 不立项**（D-M3-2-6：印相域蒙版载体 = film sub-run
> 内 mask plane，M4+ 候选——本批零实现零挂账，仅 DECISIONS 注记）。
> **光谱不可达边界**（承 01 架构注记）：本批一切 kernel 数学在 RGB 密度域，非
> 光谱重放。

## 已定裁决（生效值，硬约束，不得重开）

1. **① 承载形态**：document 级 FilmRecord + 主链顶面后**固定点 film sub-run** +
   filmPlacement 可蒙版 grade op；`DrtTailAssembly.seed(upstream:)` **签名零改**
   （film 输出 hash 作 upstream 传入——调用点换数，非改签名）；
   `TerminalTailPolicy` 枚举**零新 case**（film 走独立 `FilmTailPolicy`）。
2. **② 配光运行期**：曝光归一恒在（= printing.cpp 几何均值归一的 RGB 域简化：
   mid-gray 分位目标落点差 → 曝光 gain）；内容自适应通道偏移 = 可选档
   **默认关**（record.contentAdaptiveShift，01 已定字段）；**Y/M 手动偏移恒叠加**
   在自动解上（record.yFilterShift/mFilterShift，CC 点域）。
3. **确定性门（FSIM-01b）**：同统计 + 同材料对 + 同模式 → 同解；统计分位 =
   **整数秩**（累积计数折算，禁浮点比较分位）；求解器 = 01 闭式/有界迭代；
   求解结果缓存键 = **`fnv(材料对Hash ⊕ 统计Hash ⊕ 模式tag)`**（模式 =
   contentAdaptiveShift tag；缓存体 = (M0,Y0,曝光 gain)——printing.hpp「per-render
   重推、不 bake 进渲染」缓存纪律同构）。
4. **⑦ 置位 op**：独立 `filmPlacement`（RFC-023 语义：恒等核 + 双侧 smooth-min
   压缩支，参数 = 双侧 pull-back（stop 域）+ 滚降阶 m；**恒等核 bit-exact 直通**
   ——delta 形 `δ(E)=f(E)−E`，pull-back 全零 = 逐位现状）；可蒙版（scene-referred
   曝光操作，蒙版合法）。
5. **⑤ golden 纪律（承 M3-3-03 主门）**：本批 kernel/CPU 参考双写到位（Float64
   参考函数与 kernel 同批交付），逐像素门在 03。
6. **④ 宽容度面板 = M3-4**：置位参数**本批无面板**（op + params + 恒等注册即止；
   参数面消费 = M3-4 FSIM-02 面板；add face 可经 19 行 catalog 枚举到——恒等
   注册语义见 KD-5）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 film sub-run 缝位与降出臂（T1——本 plan 最高风险面，架构注记正本）

- **物理不变量**：film 消费 **pre-colorout 的 float32 working-linear 平面**
  （置位/grades 之后、显示编码之前）；film 输出 = float32 working-linear Rec2020，
  喂给显示尾段（legacy `colorout→gamma` 或 DRT tail）——两模式下序皆物理正确
  （display encoding 恒在 film 之后）。
- **机制——终端驻留集 × film 交互矩阵（3×2，逐格规范形）**：
  > checker 回注（2026-10-08，E4）：原文只给「legacy 显示三件降出」（连件数都
  > 与所列 ops 不符）——legacy(.sdrGamma)+film 时 borders 76/watermark 77 若留
  > 主链会被 film 调色（违反 M2-6 E2「印框/水印永不进 tone mapping」纪律）；
  > .edrLinear+film 则 film 会消费 post-colorout 平面（破坏物理不变量）且重放
  > 分类无 EDR 臂（重放 gamma 会错钳 SDR）。两缺口以本矩阵补全。
  >
  > | terminalTail \ film | off（零路径） | on |
  > |---|---|---|
  > | `.sdrGamma` | 现状：终端驻留集全驻主链，尾平面 bgra8（`isTerminalTailSkipped` 全 false） | **降出整个终端驻留集**（colorout 70 / borders 76 / watermark 77 / gamma 78——与 `.drt` 同法），主链顶 = pre-colorout float32 → film 腿 → 按 v50 序重放 **colorout → borders → watermark → gamma**（印框/水印在 film 后 = 恒不被调色）；终平面 bgra8（SDR gamma 族既有尾格式逻辑） |
  > | `.edrLinear` | 现状：仅 gamma 降出，colorout 驻主链，终平面 float32 linear | **colorout 随 film 臂加入降出**（降出集 = colorout+gamma），film 腿 → film 后**重放 colorout**；gamma 维持 EDR 档降出**不重放**（重放即错钳 SDR）；终平面保持 float32 linear |
  > | `.drt` | 现状：DrtTailAssembly 尾链（M2-6 E2 降出集+Post 四件） | 降出集**零改**（终端驻留集本就全降）；film 腿输出 = DRT 尾腿 input + upstreamSeed（见「序」）；DRT 尾链重放照旧 |
  >
  > 降出查询点（`splitTerminal` 的 ≥70.0 过滤 / `:258-304` 尾格式与降出 switch）
  > 扩臂 = **film 激活时按行扩 `isTerminalTailSkipped` 返回集**（.sdrGamma 行 =
  > 终端驻留集四件、.edrLinear 行 = colorout+gamma、.drt 行不变）；film 未激活 =
  > 该臂全短路（既有三档 `.sdrGamma`/`.edrLinear`/`.drt` 行为逐位现状——
  > DrtTailTests 族零改全绿为门）。
- **序**：`run()` 内 `runDrtTailLeg` 调用点**前置** `runFilmLeg`：
  > checker 回注（2026-10-08，m7）：原标「:864」张冠李戴——:864-865 属
  > `runSub()`，`run()` 的调用点在 :723-724；两处调用点同批接线（T1 action 已
  > 覆盖），本 KD 标注改正。
  main walk → film sub-run（`runSub` 重放，fresh tailPipe 同款形态，
  `isFilmTailLeg` 防重入标志）→ 显示尾段（按上表逐行重放链：.sdrGamma =
  colorout→borders→watermark→gamma 既有 box 原样 / .edrLinear = colorout /
  `.drt` = 尾链）→ 输出。`.drt` 模式下 DRT 尾腿 `input` = film 输出纹理、
  `upstreamSeed` = **film 输出平面 hash**（levelHash[top] → film 输出 hash 的
  数源替换——seed 签名零改的兑现点）。
- **fused kernel 单 pass**：负片段（log10 → density_curves 查表线性插值 →
  base 底色（01 KD-5 三点投影常数——E2 裁决，非谱形重放）→ 3×3 串扰 → 滤色
  密度增益 `+ k_y·[0,0,1] + k_m·[0,1,0]`）与印相段（baked 65³ LUT 四面体采样）
  在**一个 kernel 内完成**——中间密度平面不落显存（100MP 内存纪律；负片段出
  「归一化密度立方坐标」直接作 LUT 采样位）。
  > checker 回注（2026-10-08，E3）：滤色增益向量修正——M 吸绿 = [0,1,0]
  > （原 `k_m·[0,1,1]` 物理错，等制品红+黄混色）；Y [0,0,1] / C [1,0,0] 不变。
  曲线数据 = 256×3 float32 `MTLBuffer` + 域 uniform（log_exposure 轴 −3…+4）。
- **seed**（L013 折叠序，DrtTailAssembly.seed 同构）：`fnv(filmRecordHash ⊕
  filmPolicyTag("lightamer.film.subrun.v1") ⊕ solvedPackHash ⊕ upstream)`——
  solvedPackHash 折入 = 求解分量变更（统计/材料/模式变）只重跑 film sub-run；
  **strength/exposureEv/Y-M 偏移走 recordHash**（record 字段变更 → recordHash
  翻 → 同款只重跑 film 段）。
- **子 plane 格式**：film sub-run 全程 float32 working（负片段密度域不落平面 +
  LUT 输出 = working linear——「EOTF 之前尾平面恒 float32」M2-6 纪律同构）。

### KD-2 运行期统计腿（T2）

- **统计面**：`ScopeReduce.histogram(of:metal:)`（256 bins × 4 通道，L014 fence
  纪律）跑在**主链顶面全幅**——KD-1 的 film 腿入口处对 top plane 全幅 ROI 取
  缓存面一次（**禁逐 ROI 统计**：曝光归一 per-ROI 会导致瓦片间解漂移出缝——
  硬红线，测试钉「同图不同 ROI 同解」）。
- **分位整数秩**：直方图累积计数 → P0.1/P50/P99.9 的 bin 秩（整数域折算，
  RESEARCH §4.2「percentile 是 Fit 策略不是渲染参数」——本批统计只喂曝光归一）
  → `statsHash` = FNV over flattened 计数（L013）。
- **求解缓存**：`FilmSolveCache`（FilmTailPolicy.swift 内，NSLock + 字典 LRU 8）
  键 = `fnv(materialPairHash ⊕ statsHash ⊕ modeTag)`；值 = (M0, Y0, 曝光 gain,
  solvedPackHash)——solvedPackHash = 值域 bit-pattern FNV（入 seed）。
  材料对 hash 沿用 01 `FilmMaterialStore.materialPairHash`（跨 plan 单源）。
- **曝光归一解**：mid-gray（P50）当前落点 EV ↔ 相纸 mid-density 对应目标 EV 之
  差 → 线性 gain（Y 通道单值——「归一只动亮度不动滤色包的色」SpektraLab 语义）；
  内容自适应档（默认关）= mid-gray 三通道密度失衡向量在滤色增益基上的最小二乘
  投影 (ΔM,ΔY)——闭式 2×2 解，确定性同门（增益基 = KD-1 修正向量
  M=[0,1,0]/Y=[0,0,1]——E3 回注联动）。
- **手动臂恒叠加**：最终滤色 = (M0+ΔM_content+M_shift, Y0+ΔY_content+Y_shift)
  （CC 点域相加后钳 0-100 在消费点——Core 求解面不钳，与 DrtRecord.peakLuminance
  同款分工）；曝光 = 自动 gain × 2^exposureEv。

### KD-3 印相段 bake（T2，`FilmPrintBake.swift`）

- **域裁定（RESEARCH §4.3「精确域选择 plan 期定」的兑现）**：印相 LUT 输入域 =
  **归一化负片密度立方**（负片段密度 + 滤色增益后的域——研究候选「LUT 输入 =
  linear_rec2020」**不采纳**：滤色增益是密度域标量，线性域直套物理错位；
  采纳密度域 = 滤色「一 LUT 服务全滤色组合」成立的前提）。立方域界 = film
  profile 密度域 + base + 增益头量，per-pair 标定（store/bake 计算并随表携带；
  base = 01 KD-5 三点投影 RGB 常数——E2 回注联动，非谱形重放）。
- LUT 内容 = 相纸密度曲线 → 减 Dmin → **胶片中性曲线反转**（RFC-028：反转必须
  用胶片自身中性曲线——灰阶误差恰 0 的纪律）→ 强度混入（strength k 于 bake 外
  per-pixel 混——`out = in + k·(film − in)` 密度域，fused kernel 尾段）→ 输出
  working linear Rec2020。
- **机制同款非机制复用**：`bakedCompositeTable` 的 65³/Float64/concurrentPerform/
  LRU 16 形态照搬（`Lut3dModule.swift:230-264` 模板），但**自持于 FilmPrintBake**
  ——`LutEncodingCatalog` **零触碰零新行**（研究红线兑现：目录是用户 LUT 编码
  选择面，film bake 域是内部标定，不进目录）。
- 串扰矩阵：3×3 小型一阶矩阵（RFC-028 指导），**常量起步**（非 per-profile
  拟合——拟合缺口挂 M4+ 自建配置面）；值域/出处写 DECISIONS。

### KD-4 PixelPipe/RenderPipeline/Driver 传参（T3）

- `RenderPipeline.process` / `processComposite` / `LayerCompositeDriver.composite`
  各加 `filmTail: FilmTailPolicy? = nil` **默认参**（既有调用点零改动；additive
  签名纪律同 `terminalTail`/`tailFormatFloatOverride` 先例）；driver 终段管
  （:546 terminalPipe）贯通 filmTail。
- THUMBNAIL **恒 legacy**（`filmTailPolicy(for:)` 对 `.thumbnail` 返 nil——DRT
  thumbnail 恒 legacy 同款 KD；网格缩略图走显示就绪 SDR 面的在案口径不变）。

### KD-5 filmPlacement op（T4）

- 位置 `LightamerIOP/Sources/FilmPlacement/`（Module + Kernels 文件对惯例）；
  Params = `shadowsPullBack: Float`（stop 域 ≥0，默认 0）/ `highlightsPullBack:
  Float`（≥0，默认 0）/ `rolloff: Float`（m，默认 2，域 [1,8]）+ CodingKeys
  snake_case + identityJSON = 全零点（**kernel no-op 点**，GradeCatalog 惯例——
  panel 默认值概念不存在，本批无面板）。
- kernel：RFC-023 §5.4 曲线族 `g_m(Δ)=Δ(1+(Δ/H)^m)^(-1/m)`（**公式级文档转述，
  零 GPL 代码复制**；m=1 闭式、m≥2 有界二分+牛顿的 CPU 参考双写）；**delta 形
  实现**（`out = in + δ(in)`，pull-back 全零 → δ≡0 → **bit-exact 直通**）；log₂
  只出现在标量 gain 计算，输出恒 scene-linear；双侧膝 K_s/K_h 由 pull-back 深度
  与 descriptor 边界**解出**（本批 descriptor 缺席 = 膝点由 pull-back 直接参数化
  的简化臂——descriptor 解出臂 = M3-4 FSIM-02 交付物，DECISIONS 登记简化口径）。
- **V50Order 新行** `("filmPlacement", 20.8)`：acesccIn（20.5）与 exposure（21.0）
  之间——RFC-023「Scene Placement 是第一个映射」语义（camera WB/temp 3.0 在
  RAW 域先行，grade 域内置位最前）；LIGHTAMER 原生行注释纪律（skinSmooth 66.5
  先例——非 dt 行、add-only、不重排不重号）。
- **GradeCatalog 第 19 行**（NodeOwnershipCatalog.swift）：catalogID
  `"filmPlacement"`、owner `.grade`、identityJSON = 恒等点、panelExposures =
  `["shadowsPullBack", "highlightsPullBack", "rolloff"]`。**E7 完备性闭包**：
  op 入默认面注册即须 catalog 行。
  > checker 回注（2026-10-08，m8）：`GradeCatalogTests` 修订实为**多点**而非单
  > 「18→19」——执行按此清单全改（计数闭合修订 = 登记闭环，不属「既有断言需改
  > = 停下上报」红线；红线针对行为断言）：`:36` count 18→19；`:46` unique ids
  > 18→19；`:51` grade-owner 计数 14→15；`:91` unique catalog ops 17→18；
  > `:129` resolved 17→18；文件头注释（:6-16 的 18/14/17 记载）。DECISIONS 登记
  > 偏离「18 Alcedo 目录」口径的理由：Alcedo 无此面 = 差异化卖点，catalog 模型
  > 可扩。
  `defaultFaceDisabledOpNames` **零 diff**（恒等核默认启用安全——bit-exact）。
- **面板语义（m4 回注 2026-10-08）**：本批**无编辑面板** = filmPlacement 在
  M3-4 前为**可加不可编的恒等占位**（per-op 手写 provider 机制下无注册即无编辑
  面；add face 可枚举、参数恒零点 = 恒等直通）——02/03 措辞以此为准（03 裁④
  「已可达」高估措辞已同步修正），DECISIONS 注记登记；置位参数编辑面 = M3-4
  FSIM-02。
- ACEScc envelope：20.8 在 [20.5, 69.9] 包裹内（LayerCompositeSeam「≥1 目录 op
  包夹」机制自动生效——曲线数学在 ACEScc/log 域天然对位 EV delta，envelope 腿
  测试在 FilmPlacementDriverTests 钉）。

### KD-6 coordinator 持久化四件 App 半面（T5）

- **carrier**：WorkspaceModel per-url `FilmRecord?`（缺键 = pristine，**默认
  record 不入 map 不写 sidecar**——M2-6 四件套同构）；`hasFilmRecord(for:)` /
  `filmRecord(for:)` / `setSessionFilmRecord(_:for:)`。
- **写腿**：`updateFilmRecord(_:for:)`（updateDrtRecord :577 同构——carrier 已由
  调用方更新，此处只 `scheduleSidecarWrite()`）。
- **恢复腿**：`restoreFilmRecordLeg(document:url:)`（restoreDrtRecordLeg :598
  同构：nil 零动作 / 同值跳过 / 异值回注 carrier；sidecar 字段 vs history 投影
  失配 = 记日志、**字段 wins**）。
- **run 传点**：`filmTailPolicy(for resolution:) -> FilmTailPolicy?`（:656
  terminalTailPolicy 旁）：非 pristine carrier + 非 thumbnail →
  `FilmTailParams(record:postOpNames 不适用)`；thumbnail 恒 nil。既有
  `terminalTailPolicy` **零 diff**。
- **EditorState**：`recordFilmChange`（recordDrtChange :250 同构——单 discrete
  commit → commitFilm）+ `setFilmLive`（D-H1 live 腿——零 item，松手一 commit）；
  undo/redo/jump 后 carrier 从 history 真相同步（syncDrtCarrierWithHistory :677
  同构面 `syncFilmCarrierWithHistory`）。
- **FilmMaterialStore 装配**：App 组成根从 `Bundle.main.resourceURL/
  FilmProfiles/profiles` 注入 store（KD-4/01 注入式；坏目录/缺资产 = typed 降级
  + film 腿禁用 + D-26 toast 通道提示——不静默不崩）。

### KD-7 导出递缝（T6，M2-9 TaskLocal 三件套范式照办——含 ExportQueue 载体面三编辑点）

> checker 回注（2026-10-08，E1）：`$jobFilmTail` TaskLocal 在 detached 渲染腿
> **不自动继承**（ExportQueue.swift:408-413 注释原文即「the detached task
> inherits no TaskLocals, the wrapper sits inside」）——M2-9 `$jobDrtTail` 先例
> 实际落了三处 ExportQueue.swift 编辑，原 KD-7 漏列 = enqueueExportM2 到渲染腿
> 的值传递链断裂（executor 无法交付或产生未申报 diff）。补全如下；files_modified
> 已同步增列 `ExportQueue.swift`。`ExportQueueContract.swift` **零 diff 红线
> 不变**（Contract 与 Queue 是两个文件，M2-9 在案）。

- **ExportQueue 三编辑点（载体面，drtTail 先例同位）**：①`ExportJob.filmTail`
  字段（:60 `drtTail` 旁 additive optional）；②`enqueue(... filmTails:
  [FilmTailParams?]? = nil ...)` per-image 索引参数 + precondition count==images
  （:197/:203 drtTails 同款）；③渲染腿内 `$jobFilmTail.withValue(queued.filmTail)`
  包装（:417 `$jobDrtTail.withValue` 外再嵌套一层——两 TaskLocal 嵌套序 =
  drt 外 film 内，值域互不干扰）。
- `$jobFilmTail: FilmTailParams?` TaskLocal（`ExportRenderer.swift`，`$jobDrtTail`
  同款——**Contract 文件零 diff** 红线延续：per-job 载体走 TaskLocal 不动
  Request/Recipe 结构面）。
- `enqueueExportM2` 恒装配 filmTail（`drtOutput = drtRecord` 强制联动同款：
  carrier 非 pristine → 传 record 并组装 `filmTails:` 数组入 enqueue；M2 检查器
  无 film 专属 UI = 恒从 carrier 走，DECISIONS 注记）。
- ExportRenderer 渲染调用点（:487/:496）传 `filmTail`（TaskLocal 值解析）；
  导出尾平面 float32 裁定不受扰（quantizer 拥钳位——film 输出本就 working
  float32，序不变）。

## read_first

1. `LightamerCore/Sources/Pipe/PixelPipe.swift`——:124-160（terminalTail/
   isDrtTailLeg/filmTail 拟挂位）、:258-304（降出与尾格式查询点）、:722-728 与
   :860-925（两处尾腿调用点 + runDrtTailLeg 全形态——runSub/防重入/seed 数源）、
   :1152（尾平面格式腿）、:1554+（RenderPipeline.process/processComposite 签名）。
2. `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift`——:108-130
   （splitTerminal/terminalTailFloor）、:190-210（composite 签名）、:540-550
   （终段管 terminalTail 传递）；`ACEScc` envelope 缝（:152-157 + 
   `LightamerIOP/Sources/ACEScc/`）。
3. `.work/gsd/phases/m3-3-fsim/M3-3-01-PLAN.md`（上游 KD 全部——尤其 KD-1
   record 字段/KD-4 store/KD-5 求解器）+ 交付后的 
   `M3-3-01-SUMMARY.md`/`-DECISIONS.md`。
4. `LightamerIOP/Sources/Common/ScopeReduce.swift`（histogram 面 + L014 纪律）+
   `LightamerIOP/Sources/Contrast/ContrastModule.swift`（op 文件对/Params/
   identityJSON 形态模板）+ `LightamerIOP/Sources/Registry.swift`（注册面 +
   defaultFaceDisabledOpNames :39）+ `Tests/LightamerTests/GradeCatalogTests.swift`
   （E7 完备性断言——18→19 修订位）。
5. `App/Sources/Lightamer/State/PipeCoordinator.swift`——:569-689（DRT 四件套
   全形态：update/restore/didChange/effective/has/surface/sync/live）+:656
   （terminalTailPolicy）+:2192/:2203（渲染调用点）；`EditorState.swift` :250-253。
6. `LightamerCore/Sources/Export/ExportRenderer.swift`——:445-500（drtTail 
   TaskLocal 解析与调用点）；`ExportState.swift` enqueueExportM2 装配段（drtOutput
   联动位）；`ExportQueueContract.swift`（零 diff 红线体）；
   `ExportQueue.swift`——:60（Job.drtTail 字段位）/:182-206（enqueue drtTails
   per-image 参数 + precondition 形态）/:417（腿内 withValue 包装位）/:408-413
   （detached 腿不继承 TaskLocal 注释原文——E1 载体面三编辑点的先例锚）。
7. `Tests/LightamerTests/DrtTailTests.swift`（LAYERS 14 法——pristine 零路径/
   seed 折叠的断言形态模板）+ `DrtPersistenceTests.swift` + `DrtSidecarTests.swift`
   （APP 侧 carrier 断言形态）；`.work/LESSONS.md` L014（fence）/L031（queue）。

## 纪律（强制）

1. **封存面清单（零 diff 语义，`git diff --name-only` 机检）**：
   `TerminalTailPolicy` 枚举与 `DrtTailParams`/`DrtTailAssembly`（**签名与既有
   分支语义零改**——降出查询点扩臂是 PixelPipe 内条件表达式，非该类型面）、
   `DrtEotf.swift`、`Lut3dKernels.metal`、`LutEncodingCatalog`、
   `ExportQueueContract.swift`、六格式导出矩阵、`HistoryItem`/`HistoryHash`
   （01 已落，本批零触）、sidecar schemaVersion（9 已落，本批零触）。
   **PixelPipe.swift / LayerCompositeDriver.swift 允许 additive 修改**（filmTail
   属性/传参/腿），但既有分支在 film 未激活时**行为逐位不变**（DrtTailTests +
   LAYERS/IOPP 既有族零改全绿为机检门）。
2. **per-ROI 统计禁令**（KD-2 硬红线）：同图不同 ROI 必同解（测试钉死）。
3. **测试登记**（E2/L041）：七新测试文件同 commit 登记 Project.swift + 
   BUNDLE-MAP（归属按 front-matter：FilmLeg/FilmPrintBake/FilmPlacementDriver =
   LAYERS；FilmPlacement = IOP；FilmPlacementKernel = IOPP（`*Kernel*`/Golden 
   域惯例）；FilmCoordinator = APP；ExportFilmChain = EXPORT）；generate 恒批尾。
4. **GPL 零复制**：RFC-023 曲线 = 公式级文档转述 + 自研 MSL/Swift；printing.cpp
   语义 = 行为描述级借鉴。
5. **确定性**：统计整数秩、缓存键 L013、kernel 无 barrier 依赖的逐像素纯函数；
   probe/计时走 `LIGHTAMER_PERF_PROBE=1` 门控 + fence（L014）——本批无 perf 门
   （60fps@100MP 预算的 film 段计时 = M3-4/收口面，DECISIONS 挂账注记）。
6. **checker 四条**：①真链（DRT+film 叠序真渲染断言 + 导出链真 job 断言）；
   ②登记闭环（三方对表）；③语义断言（pristine 零路径负测 + per-ROI 同解 +
   恒等 bit-exact）；④边界核对（封存面零命中 + film 未激活行为逐位不变门）。

## Tasks

### T1 film sub-run 缝与降出臂（KD-1）

- **action**：FilmTailPolicy/FilmTailParams/FilmTailAssembly（seed）+
  PixelPipe filmTail 属性/runFilmLeg/降出扩臂（KD-1 3×2 矩阵）/两处调用点接线
  （run() :723-724 + runSub() :864-865——m7 回注改正标注）+ 按矩阵重放链
  （.sdrGamma = colorout→borders→watermark→gamma / .edrLinear = 仅 colorout /
  `.drt` = 尾链）；`FilmLegTests`（seed 折叠稳定性与差异面 / film nil 零路径
  逐位不变 / legacy+film 重放序 / drt+film 叠序 / 子平面格式 float32 / 防重入
  / **film+yiyin 边框组合（边框平面在 film 后 = 不被调色）** / **film+EDR 组合
  （输出 linear、无 gamma 重放）**——E4 回注补两格）。
- **验收标准**
  - [ ] LAYERS 定向轮绿 + DrtTailTests 族零改全绿（film 未激活行为逐位门）；
        `DrtTailAssembly`/`TerminalTailPolicy` 零 diff；KD-1 矩阵六格逐格有
        断言（off 三格 = 既有族，on 三格 = FilmLegTests）。

### T2 统计腿 + 印相段 bake + fused kernel（KD-2/KD-3）

- **action**：FilmPrintBake（65³ Float64 参考 + concurrentPerform + LRU）+
  FilmSubRunKernels.metal（fused：查表→底色→串扰→增益→LUT 采样→强度混）+
  FilmSolveCache（键控 fnv）+ ScopeReduce 统计接线（全幅）；`FilmPrintBakeTests`
  （bake 确定性/域标定/LRU 逐出/负域界 typed）。
- **验收标准**
  - [ ] LAYERS 定向轮绿；bake 双调用 bit-identical；`LutEncodingCatalog` 零 diff；
        kernel 编译入 Core metallib（M3-3-03 逐像素 golden 消费面就位）。

### T3 RenderPipeline/Driver 传参（KD-4）

- **action**：三签名 additive 默认参 + driver 终段管贯通 + thumbnail 恒 legacy。
- **验收标准**
  - [ ] 全仓既有调用点零改动编译；LAYERS/IOPP 既有族零改全绿。

### T4 filmPlacement op（KD-5）

- **action**：Module+Kernels 文件对 + Params/identityJSON + V50Order 20.8 行 +
  GradeCatalog 第 19 行 + Registry 注册 + GradeCatalogTests **多点修订**（:36/
  :46/:51/:91/:129 + 文件头注释——KD-5 m8 回注清单，全改不误停）；`FilmPlacementTests`
  (IOP)/`FilmPlacementKernelTests`（IOPP——恒等 bit-exact/单调/m 阶接触 smoke）/
  `FilmPlacementDriverTests`（LAYERS——envelope 包夹/蒙版合法/层链不受扰）。
- **验收标准**
  - [ ] IOP+IOPP+LAYERS 定向轮绿；`defaultFaceDisabledOpNames` 零 diff；
        V50Order 既有行零动（add-only）。

### T5 coordinator 四件 + 统计接线 + store 装配（KD-6）

- **action**：carrier/写腿/恢复腿/filmTailPolicy + EditorState 两 face + 
  syncFilmCarrierWithHistory + store 注入与坏目录降级；`FilmCoordinatorTests`
  （缺键 pristine / 恢复腿三态 / thumbnail nil / commitFilm 单 item / undo 同步 /
  坏目录降级不崩）。
- **验收标准**
  - [ ] APP 定向轮绿；`terminalTailPolicy` 零 diff；非 pristine 文档全链真渲
        （film 面生效、无 film 文档逐位不变）。

### T6 导出递缝（KD-7）

- **action**：$jobFilmTail TaskLocal + **ExportQueue 三编辑点**（Job 字段/enqueue
  `filmTails:` 参数/腿内 withValue 包装——KD-7 E1 回注）+ ExportRenderer 解析与
  传参 + enqueueExportM2 恒装配（`filmTails:` 数组入 enqueue）；`ExportFilmChainTests`
  （无 film job 零漂移 / film job 装配值达渲染 / **per-image fan-out：两图不同
  carrier 各达渲染腿**——E1 回注补 / Contract 零 diff 面）。
- **验收标准**
  - [ ] EXPORT 定向轮绿；既有 EXPORT 族零改全绿；`ExportQueueContract.swift`
        零 diff。

### T7 收口

- **action**：SUMMARY（测试增量对账链 + KD 落点核对 + FSIM-03 不立项注记）/
  DECISIONS（KD-1..7 + 串扰常量值域出处 + descriptor 简化臂 + thumbnail 恒
  legacy + **KD-1 3×2 交互矩阵与 E4 语义声明** + **filmPlacement 可加不可编
  恒等占位注记（m4，与 03 措辞一致）** + **修正滤色向量复核结论（E3，联动
  01 DECISIONS）**）/ GOAL-STATE / TODO；密封面机检对表。
- **验收标准**
  - [ ] 三方对表；封存面零命中；docs 完整。

## 验收标准（AC 总表）

| # | AC | 机检方式 |
|---|---|---|
| 1 | film sub-run 缝位正确（pre-display 平面进、working float32 出、DRT upstream = film 输出 hash、seed 签名零改）；**KD-1 3×2 交互矩阵逐格成立**（含 yiyin 边框后置不被调色、EDR+film 输出 linear 无 gamma 重放）；film 未激活全链逐位现状（DrtTail 族零改全绿） | T1 测试 + diff |
| 2 | 运行期腿确定性：整数秩统计 + 缓存键 `fnv(材料对⊕统计⊕模式)` + 同图跨 ROI 同解 + 手动 Y/M/exposureEv 恒叠加 | T2/T5 测试 |
| 3 | 印相段 bake：65³ Float64 concurrentPerform + LRU 16 + 密度域输入裁定落地；LutEncodingCatalog 零触碰 | T2 测试 + diff |
| 4 | filmPlacement：恒等 bit-exact、可蒙版、V50 20.8 add-only、E7 19 行闭合、envelope 包夹 | T4 测试 |
| 5 | 持久化四件 App 半面：缺键 pristine / 恢复腿三态 / thumbnail 恒 legacy / store 坏目录 typed 降级不崩 | T5 测试 |
| 6 | 导出：$jobFilmTail 递缝（**ExportQueue 三编辑点在案**，Contract 零 diff）+ enqueueExportM2 恒装配 + per-image fan-out 达渲染 + 无 film job 零漂移 | T6 测试 |
| 7 | 登记闭环（E2/L041）+ 封存面零命中 | 三方对表 + diff 机检 |

## 风险与边界

- **降出臂回归面（最高风险）**：终端驻留集降出（KD-1 3×2 矩阵——.sdrGamma 行
  从「无降出」变「film 激活时四件降出」、.edrLinear 行 colorout 随 film 臂加入）
  触碰主链 walk 的条件表达式——用 DrtTailTests + IOPP 既有族全绿作逐位门（film
  未激活 = 既有行为逐位现状）；任何**行为**断言需改 = 停下上报（非 additive =
  设计违反；GradeCatalogTests 计数闭合修订除外——KD-5 m8 回注清单在案）。
  > checker 回注（2026-10-08，m9——切分点预授权裁定）：**不切 02a/02b，02 内
  > T 序重排 + 预授权断点**。执行序调整为 **T1 → T3 → T4 → T2 → T5 → T6 → T7**
  > （T3 小任务前置给出 T4 独立交付窗；T2 重头戏后移——超支触发断点时 T4 已
  > 在 02 内交付、可 shedding 面只剩 T6）。**预授权断点**：若 T1+T2 合计实际
  > 超估算 ~2× 或单项硬阻塞 > 半天，**T6（导出递缝——M2-9 同款机械面，体量
  > 最小）移出为后续 plan M3-3-04**（T6 独立小收口，排在 03 之后；03 的
  > golden/确定性/面板不依赖 T6），orchestrator 无需二次裁决；**T1/T2 本体禁
  > 自缩**（降出矩阵与 fused kernel 是本 plan 不可让渡面），卡死 = 停下上报。
  > 裁定理由：七任务共享 FilmTailPolicy 类型与 seed 面，预切分产生跨 plan 类型
  > 稳定性约束 + 两轮验收开销；checker 建议的切分动机（T1/T2 超支保护）由断点
  > 条款等价覆盖且仅在触发时付费；03 置位曲线 golden 门依赖 T4 在 02 内交付
  > （预切 02b 会拖 03 主门），重排使该风险归零。
- **全幅统计的额外 pass**：film 激活每次 render 多一次 256-bin reduce（全幅缓存
  面命中时近零成本；FULL 冷缓存首帧多一腿）——DECISIONS 登记成本口径；M3-4
  宽容度面板复用同统计面（读数语义「after placement」本批已成立：统计腿吃
  主链顶面 = 置位后平面）。
- **descriptor 缺席的置位膝点简化**：pull-back 直接参数化 = M3-3 交付口径，
  RFC-023「K/H 由直方图分位与 descriptor 解出」完整臂 = M3-4（FSIM-02 面板 +
  descriptor 运行时同批）——交互语义不变、求解精度后补，DECISIONS 双登记。
- **FSIM-03 蒙版**：film sub-run mask plane 本批零实现（D-M3-2-6 注记即止）；
  印相域蒙版需求出现前不扩。
- **99th 百分位/膝点数值域**：pull-back stop 域与相纸白黑地板渐近线在 03 golden
  定标；本批只保证恒等 bit-exact + 单调（smoke）。

## 提交约定

- T1 `feat(core): film sub-run seam with demoted display tail replay`
- T2 `feat(core): print bake and fused film kernel with solve cache`
- T3 `feat(core): film tail pass-through in render pipeline signatures`
- T4 `feat(iop): filmPlacement masked grade op with catalog row`
- T5 `feat(app): film record persistence legs and material store wiring`
- T6 `feat(export): job film tail task-local seam for export chain`
- T7 `docs(m3-3): close film pipeline batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。

# M9-4 CONTEXT — 小件池（M9 末站，OQ-1..7 裁决落定批，2026-10-25）

> **裁决正本**：OQ-1..7 **全部按 `RESEARCH.md` §Open Questions 推荐落定**
> （M9-1/2/3、lumen-culling 批同款「OQ 全按推荐」auto-advance 制度。**晨审
> 可推翻**——推翻 = 用户晨审修订本文件对应 D-M9SP 条，下游 plan 受影响任
> 务面重开）。读解正本 = 同目录 `RESEARCH.md`；planner 2026-10-25 HEAD 亲
> 核 ~25 点（RenderProcess/PipeCacheKey/PixelPipe prepareChain+forwardWalk/
> IOPPiece stamp/ModuleBox.setParams/ColorWheelsModule+metal/golden/
> LutEncodingCatalog+LutTransferMath/FilmstripView+LibraryGridView+LibraryImageRow/
> CropOverlayHost+CropPanelView/PostExportActions/FilmMigrationAction+runProcess
> Migration/ParamsCoding/上游 e1effd8·c740f7b git 对象/R6-SUMMARY 4292 终值
> /M9-1..3 plan ΔN 带），**转写勘误四条 + planner 补强两条**随 §转写勘误与
> §决议登记，执行以勘误为准。
>
> **编排总纲**：单 plan 五任务串行 T1→T5（charter S-M 档；机器级单重活制
> 排除并行 plan）。**本站 = M9 末站**——开工前核 GOAL-STATE 与 R6/M9-1/
> M9-2/M9-3 四前站 SUMMARY 实数落基线表达式（M9-3 plan 同款带式纪律）。
> C 档门控：T5 闭环后停汇报（M9-4 收口 = M9 站收口前哨，phase VALIDATION
> 另批）。全套 `--all` = orchestrator 批准制 + 8G 门 + MEMFAIL 机检兜底；
> 重活起跑前必过 `Scripts/machine-guard.sh` + GUI 实例 ps 清零验证（运行时
> RSS 纪律）。执行期一切上游读法走 `git show <sha>:<path>`（勘误②——本地
> AlcedoStudio 工作区 stale）。

## Phase Goal（M9SM-01 主件 + M9SM-02 尾件四件）

ColorWheels 从上游 v1 公式 verbatim 升到 **v2 LGG+Offset 影调域语义**
（真 parity gap 修复）：`ApplyToneWheel` 新 kernel 臂（t 域四轮 Offset/
Lift/Gamma/Gain 分离）+ `ConvertLegacyColorWheel` 读入转换（lift→offset
精确 + gamma/gain 最小二乘拟合）+ **process v3 bump 五件套 + v1/v2 冻结双
臂**（旧档观感零漂移主门）+ **PipeCache 键 process 折入**（最高风险缝，
KD-6「非 legacy 才折」收窄形）+ 迁移 UX 复用 M8-3 通道（gate/marker/copy
泛化）；尾件四件 = LUT encodings 表扩（10 编码行 + 7 曲线 + 6 gamut =
23 表行，OQ-3 口径修正）+ Filmstrip stars 行/编辑态磁贴 + Show in Finder
（原图 reveal）+ XPan 类 ratio 三行（自主增强）。验收形态：构建绿 + 定向
bundle 全绿 + 全套 `--all` 对账（带式基线，§红线 12）+ golden 三面（v3
kernel-vs-ref/上游解析锚/转换锚 + 冻结臂零漂移负测）+ 缓存折键负测三件 +
zh-audit 双 PASS + 走查配方。ΔN **+11..15**（charter +10..15 带内）。

## 决议（D-M9SP-1..9，生效值，硬约束，执行中不重开）

### D-M9SP-1 冻结臂锚定我方现行字节（OQ-1）

- **裁决 = research 推荐**：v1/v2 冻结臂锚定**我方现行 kernel/golden 字节**
  （含 M2-5 移植期的 `1/γ_leg` 指数换算形态——`ColorWheels.metal:39-48`
  + `ColorWheelsModule.reference :305-325` 现状即冻结基准），**不回溯对齐
  上游 v1 数值**（上游 v1 metal 是 `γ_leg` 直指数——M2-5 catalog 侧语义
  换算差异，冻结 = 我方历史观感）。
- 现行 golden（`GradeKernelGoldenTests.swift:508-555` identity + 4 参数
  点）**原样保留**即冻结臂 golden（piece.renderProcess 缺省 `.legacy` →
  resolving → `.v1` 冻结臂，逐字节现状）；另加 v2 档 stamp 变体逐位断言。
- 证据：RESEARCH §2 表 kernel 行 + §风险 2；`ColorWheels.metal:39-48`
  亲核（`1.0f / gammaLegX` 指数形态）。
- 晨审推翻点：翻案 = 冻结臂回溯上游 v1 数值（我方 M2-5 以来全部历史观感
  变色，违背 process 冻结纪律本体，不建议）。

### D-M9SP-2 params 甲形态 + planner 两补强（OQ-2）

- **裁决 = research 推荐甲**：`Params.offset` 以 **additive optional +
  tolerant decode** 进 struct（DrtRecord/FilmRecord 先例），`colorOffset`
  中性基准**不改存量键义**；**零 modversion bump、零 sidecar schema bump
  （v11 保持）、旧档字节零改写**；v1 语义值在 v3 臂**渲染预解层现算转换**
  （memo 化），不落盘。乙形态（modversion bump + 落盘转换）弃——HistoryHash/
  paramsData 兼容面全动，收益仅可读性。
- **planner 补强①（判别子，结构性必需——research 甲形态未展开首编辑语
  义，无此则双语义同名键互撞）**：**`offset` 键在场与否 = v1/v2 语义判别
  子**。缺席 = v1 语义（v3 臂渲染期转换）；在场（含全零）= v2 语义（直
  读零转换）。v3 面板**首编辑物化**（normalization commit）：编辑起于
  `effective(params) = offset == nil ? ConvertLegacy(params) : params` 投
  影，commit 写**完整四轮 quad 且 offset 显式在场**——旧 shape 仅存于
  「从未在 v3 臂动过轮」的档（上游 `version_one_json` 机制的判别子转译：
  上游靠 version 键，我方靠 offset 键在场）。undo/jump 回旧 item = 回到
  缺席 shape，渲染期转换恢复——shape 判别随每个 history item 的
  paramsData 自带，undo 语义天然干净。
- **planner 补强②（v3 全保真读取通道）**：frozen 16-float 打包不携带
  offset，v3 预解不能从打包浮点重建 v2 语义 quad——`commitParams` 时模块
  **缓存完整 params 镜像**（`lastParams: Params` + NSLock，uniformsBuffer
  同款读写模式 + Lut3dModule Compose stateLock 先例；box 归属纪律下
  commit/process 同域），`process` 在 v3 臂从镜像 + `piece.renderProcess`
  预解 14-float（memo 键 = piece.paramsHash）。frozen 打包路径逐字节不动。
- **字节零漂移负测（硬门）**：`Params()`（offset nil）经 ParamsCoding
  encode 字节 == 现行字节（sortedKeys + encodeIfPresent 缺席——hash 常
  量钉死）；否则全量历史档 paramsHash/HistoryHash 假漂移。
- 证据：RESEARCH §3.3 甲/乙 + §风险 5；`ParamsCoding.swift:22-28`
  （sortedKeys 正本）；`ModuleBox.setParams`（hash adoption 注记——
  params identity = param bytes only）。
- 晨审推翻点：翻乙（迁移落盘转换，HistoryHash 全动 + modversion 双轨登
  记，不建议）。

### D-M9SP-3 LUT「+24」口径修正 = 10 编码行 + 7 曲线 + 6 gamut（OQ-3）

- **裁决 = research 推荐**：实缺 = **10 编码行**（用户可见缺口）+ **7 条
  新传递曲线**（flog2/clog2/log3g10/bmdFilmGen5/davinciIntermediate/dlog/
  gamma26）+ **6 新 gamut**（sgamut3cine/redwidegamutrgb/bmdwg_gen5/
  davinci_wide_gamut/dgamut/p3dci）= 23 新表行 ≈ REQUIREMENTS「+24」粗算
  口径。行值逐行照上游 `c740f7b` 表（含 `p3d65_gamma26` peakNits **48**
  〔DCI 参考白——非我方 display 行族 100 惯例，勘误④〕；`linearRec2020`
  我方独有行保留不动）。
- 证据：RESEARCH §4.1 表；上游表行亲核（`git show c740f7b:…catalog.cpp`
  六行 id 拼写逐一对上）。
- 晨审推翻点：翻案 = 砍曲线只加行（不可能——行依赖曲线；无实际翻案面）。

### D-M9SP-4 t 域外行为 golden 覆盖（OQ-4）

- **裁决 = research 推荐**：ACEScc 段 texel 可越编码域（−0.358..1.468 外
  extrapolation），v3 测试矩阵加**超域采样点**（t ∉ (0,1) 的 Lift/Gamma
  分支边界 + clamp/max 早退路径像素级断言——kernel 与 CPU 参考双跑）。
- 证据：RESEARCH §OQ-4。
- 晨审推翻点：无（纯加测试面）。

### D-M9SP-5 Filmstrip 双态 = 现有语义保留 + stars 行补齐 + 分档核验（OQ-5）

- **裁决 = research 推荐（轻臂）**：我方 accent edge（editing 语义）+
  selectedRing（selected 语义）**形态保留**，不按上游 bone well/ink frame
  视觉规范重做——**补 stars 行**（rating 数据已全通——勘误①）后按上游
  口径核视觉分档（editing 态最强/selected 态次之的双档层次走查项，不足
  则调 token 不改结构）。
- 证据：RESEARCH §4.2 + §OQ-5；`FilmstripView.swift:267-320`（现有双态
  overlay 亲核）；`LibraryGridView.ratingBadge :562-565`（星级行先例形）。
- 晨审推翻点：翻案 = 按上游 QML 视觉规范重做分档（成本升、观感收益待验，
  不建议本批做）。

### D-M9SP-6 XPan 三行具体值 = 65:24 + 2.75:1 + 6:17（OQ-6，自主增强申报）

- **裁决 = research 候选集采纳**：三行 = **65:24**（X-Pan 全幅全景
  24×65mm）+ **2.75:1**（Ultra Panavision 70，dn=(11,4)）+ **6:17**
  （中画幅宽幅 G617，dn=(17,6)）。上游 12 档无此三行——**自主增强非
  parity**（REQUIREMENTS 只点名 65:24「等三行」；值 planner 定，晨审可
  改）。整数对入现 Int 存储，零 schema 影响。
- 证据：RESEARCH §4.4；`CropOverlayHost.swift:25-40`（dn 形亲核）。
- 晨审推翻点：换值/砍行（纯数据行，晨审直改枚举即可）。

### D-M9SP-7 迁移 UX 复用 M8-3 通道 + 泛化，不复刻 LoadJson 即转换（OQ-7）

- **裁决 = research 推荐**：复用 M8-3「Update to Current Process」通道
  （`WorkspaceModel.setProcessVersion :404` 唯一运行时写脸 + 零自动迁移
  纪律不变）；**不复刻**上游「LoadJson 即转换渲染」——我方冻结臂保逐位、
  升号后才近似（拟合残差常见 ≤0.03 档/极端 ≈0.12 档，文案如实声明）。
- **泛化面（planner 精核——research 表述「复用」但 M8-3 通道现为 film
  专属，泛化工作量显式列，勘误③）**：①gate 泛化——
  `FilmMigrationAction.evaluate`（`EditorState+FilmMigration.swift:49-76`）
  现 gate = `hasFilmRecord`；扩为 `hasFilmRecord || colorWheels 非中性`
  （colorWheels-only 文档获得迁移行；双缺文档 identity 双臂逐位同 → 无
  行）；editingInFlight 守卫扩 colorWheels D-H1 窗。②marker 泛化——
  film 记录在场 = M8-3 film item VERBATIM（零 diff commit 形不动）；缺席
  = **colorWheels verbatim params item**（同 `history_process_migrate`
  label 族——M8-3「record VERBATIM as marker」同款语义，参数零 diff，
  不触 HistoryStack 封存面）。③copy 中性化——`panel_process_migrate_*`
  新键族（title/body/button/cancel/**confirm** 五键——film 族现役 5 键
  亲核，confirm sheet 保留 L057 sheet 形故 confirm 键随 copy 中性化）；
  `panel_film_migrate_*` 键留册停引
  用（xcstrings 字节零触碰）。④行挂点泛化——ProcessMigrationRow 从
  FilmPanel 专属扩为 FilmPanel + ColorWheelsPanel 双消费（单行单动作，
  双记录文档不双行）。
- **两代并存 UX 形态**：v1/v2 档面板 = 三轮 v1 语义视图（冻结视图与冻结
  渲染一致）+ 迁移行；v3 档 = 四轮 stops 视图 + 无迁移行（alreadyCurrent）。
  面板 fork 读 `coordinator.documentProcessVersion`（FilmPanelModel
  `:245-250` 同通道）。
- 证据：RESEARCH §3.3 迁移段；`PipeCoordinator.runProcessMigration
  :858-875` + `FilmPanelView ProcessMigrationRow :128-190` 亲核。
- 晨审推翻点：colorWheels 面板独立迁移行（双行冗余）；或 marker 不泛化
  （colorWheels-only 文档迁移历史不可见——可接受但不完整）。

### D-M9SP-8 PipeCache 折键 = prepareChain 级 per-box fork 折、discriminator = resolved arm（KD-6 收窄形，承 research §3.4-4 必查缝落定）

- **裁决（planner 落定，最高风险缝）**：colorWheels 平面走 chain position
  机制（键 = `levelHash[position]` = `box.paramsHash` 链，`PipeCacheKey
  .upstreamHash`——**现无 process 段，必查缝坐实**；且 box hash 在
  setParams 时刻提交，升号不触发 setParams → 折必须落 **run 级**）。
  折法 = **`ModuleBoxing` 增 `processForkHash(renderProcess:) -> UInt64?`
  协议要求（default nil，全模块零改）**；ColorWheelsModule 返回 v3 臂
  tag（`"lightamer.colorwheels.v3"` 的 StableHash）**当且仅当**
  `RenderProcess.resolving(renderProcess) == .v3`；`.v1/.v2/.legacy` →
  nil **零折**（键字节恒等——film v2 review m1 收窄形：fold
  discriminator = resolved arm，窄于 header `rawValue > 0` 字面形）。
  折叠点 = `PixelPipe.prepareChain`（`:946-976` 域，running chain 折一处）
  ——colorWheels 位及其一切下游位（含 layer sub-run 同机制）键翻转。
- **负测三件（T2 硬门）**：①同 params 字节、v1 臂 vs v3 臂 → chain hash
  不等（键不撞——冻结臂观感不污染新臂/反之）；②legacy/v1/v2 臂 → chain
  hash 与现行**逐位恒等**（零漂——旧档缓存全命中语义不变）；③v3 臂内
  params 变更 → 键仍随 paramsHash 翻转（折不吞参数维）。
- **IOPPiece stamp 预留位兑现**：`IOPPiece.renderProcess`（`IOPiece.swift
  :76-88`，M6-2-01 T2 stamp）doc 注释明文「a future fork point folds the
  process at ITS cache key per the『非 legacy 才折』contract」——本批即
  该预留缝的正主；`forwardWalk :995-999` 每位 stamp 已在，process() 读
  `piece.renderProcess` 即可，零新线程面。
- **渲染入口穿线核验（execute 必查；v2 按 plan 评审 M-1 改写如实叙事）**：
  `PixelPipe` 两入口（`:2209` run 族 / `:2276` composite）已带
  `renderProcess` 形参。**已穿（正资产，核验零工作量）**：coordinator
  主渲染双路（`PipeCoordinator.swift` renderCurrentChain
  `:2521/:2543` 传 `migratedProcess`）+ EXPORT 主腿
  （`ExportRenderer.swift:550/:562` `renderProcess: documentProcess`——
  M8-3 已穿，本批核验即可）。**未穿腿实测 9 处调用点**（全部 `.legacy`
  缺省，v3 文档下与主视图不同臂）：`QuickLookRenderer.swift:287/:296`
  （QuickLook 预览）、`PipeCoordinator.swift:2001`（eyedropper 线性链）/
  `:2073`（followEdgesSurface 层子 run）/`:2161`（filmic auto 采样）/
  `:2607/:2626`（EDR display override 双路）、`ColorMatchService.swift
  :205/:214`（colormatch 提取）——逐点改穿 doc stored 值，修正点登记
  DECISIONS；机检面 `grep -rn "RenderPipeline.process" App/Sources
  LightamerCore/Sources` 一网打尽（清单正本 = plan T2 Action 3③）。
- **THUMBNAIL 穿线 = M8-3 显式设计决定的修订（非补漏）**：实核
  `PipeCoordinator.swift:2508-2514`——`migratedProcess` 的
  `guard resolution != .thumbnail … return .legacy` 是 **M8-3 T3 在
  process 穿线层的显式 thumbnail guard**（注释明文「THUMBNAIL stays
  legacy … the thumbnail cache-key space never moves」），**不是**
  tail-policy 先例、更不是「`.legacy` 缺省腿漏穿」。本批让 thumbnail
  穿 doc 值 = **修订该 M8-3 设计决定**（v3 档缩略图须与主视图同臂，
  否则图库/胶条与编辑器撕裂——修订理由即红线 4 的撕裂论据）；M8-3
  注释（cache-key never moves 句）须同批修订。**DECISIONS 须单独申报
  「M8-3 thumbnail guard 设计修订」条目**——区别于其余 9 处的补漏
  性质（后者统一记一条「穿线修正清单」即可）。
- **豁免面（禁穿，`.legacy` 即正确值）**：①`SessionThumbnailRenderer
  .swift:42/:59`——文件头带「Phase 8 contract（禁改）」注释 + legacy
  session 面无 process 载体（legacy 库无 sidecar process 字段可读），
  机械套「一切渲染腿」会撞禁改契约，**无需也不应改**；②`CullingView
  .swift:227`——culling pristine 默认链（`makeDefaultChain()` + 每次新
  UUID + throwaway cache），无 doc stored process 可穿。豁免判断登记
  DECISIONS（m-3）。
- **「超 10 行停手上报」预告（计划内）**：穿线批（9 调用点 ×1-3 行 +
  thumbnail guard 修订 + M8-3 注释同步）**大概率触**plan 裁定权归属钉
  的「穿线修正超 10 行」停手线——触线时停手上报**属计划内流程、非方案
  失败**：plan 已预授权该缝的穿线扩面，上报后按 DECISIONS 登记实际
  行数与逐点清单即放行（执行者不得据此误判设计翻车）。
- 证据：`PipeCacheKey.swift:48-55`（upstreamHash 链语义）+
  `PixelPipe.swift:946-976`（prepareChain）/`:995-999`（stamp）亲核；
  film policyTag 先例（`RenderProcess.swift:124-135` 账本 review m1 注记）。
- 晨审推翻点：折 discriminator 改 `rawValue > 0` 字面形（v1/v2 键字节漂
  移 = 冻结主门破，禁）。

### D-M9SP-9 v3 bump 五件套 + 新 kernel 申报面清单（M8 解封先例）

- **裁决**：五件套照 M6-2 制度——①`RenderProcess` 追加 `case v3`（case
  doc-comment = 账本：ColorWheels LGG+Offset 代际）②`all` 尾插 `.v3`
  ③`RenderProcessVersion.current` 2→3（`RenderProcess.swift:90`——M8-2
  film 光谱核之后的第二 bump；M9-2/M9-3 零 bump 已声明，v3 归本站独占）
  ④AGENTS.md process 账本行 ⑤新旧 golden 三件套（冻结臂零漂 + 新臂
  kernel-vs-ref + 上游解析锚）。
- **新 kernel 申报面清单（全批唯一新增 kernel）**：`ColorWheels.metal`
  append `grade_color_wheels_v3` kernel + `ToneWheelUniforms` struct（14
  float 布局）。**零其它新 kernel**（Lut3dKernels.metal 等零 diff）。
  `ColorWheels.metal` 非封存面可 append，但**现行 `grade_color_wheels`
  函数体逐字节保留**（冻结臂语义 = 我方历史观感，D-M9SP-1）。
- 证据：`RenderProcess.swift:108-172`（枚举/账本/processVersion switch
  ——加 case 编译器逐点指向）+ M8-2 bump 先例（`:88-90, :124-135`）。
- 晨审推翻点：无（制度照单）。

## 设计承接钉死（X1..X6，plan 层硬约束）

### X1 ColorWheels v3 数学面（Plan T1；上游 `e1effd8` `color_wheel_tone.hpp/.cpp` 直译，GPL 归属）

- **影调坐标**：`ev = (c − CE_ACESCC_MIDDLE_GREY) × CE_ACESCC_B`；
  `t = (ev − kToneBlackEv) / (kToneWhiteEv − kToneBlackEv)`；
  `kToneBlackEv = −6`、`kToneWhiteEv = +6`（R = 12 档，中灰恰 t = 0.5）。
  ACEScc 常数自上游共享头（`git show e1effd8:` 定位；我方
  LutTransferMath acescc 族互验）。
- **四轮逐通道公式**（K = 该通道档数 = `ControlChannelStops(control)` =
  disc stops + master；执行序 **Offset → Lift → Gamma → Gain**）：
  - Offset：`ev' = ev + K`（ACEScc 增量 `K/B`，先加）
  - Lift：`t' = t + (K/R)·clamp(1−t, 0, 1)`
  - Gamma：`t' = t^p`，`p = ln(max(0.5 + K/R, 0.05)) / ln(0.5)`，仅
    `0 < t < 1`
  - Gain：`t' = t + (K/R)·max(t, 0)`
- **CPU 预解 `ResolveToneWheelKernelParams`** → `ToneWheelKernelParams`
  14 float：offset_acescc3 / lift_scale3（K/R）/ gamma_exponent3（缺省
  1）/ gain_scale3（K/R）/ tone_black_acescc / tone_range_acescc。kernel
  只做 `ApplyToneWheels` 查表级运算。**中性早退**：lift=0 ∧ p=1 ∧ gain=0
  时仅加 offset（逐位精确）；四轮全中性 → blit。
- **盘映射**：`DiscToChannelStops(x,y,strength)` = 零均值色相单位向量 ×
  strength·r（`cdlDelta` 同构，**去 clamp、strength 语义改档**）；
  `ChannelStopsToDisc` 反演（UI 回填 + 拟合迁移用）；`ClampDiscPoint`
  越界截单位圆。`kDiscMaxStops = 1.0`（strength 缺省值）、
  `kMasterMaxStops = 2.0`——四轮**同一组常量**（v1 的 gamma 符号翻转/
  strength clamp 0...0.1/luma ±1 全废除；v3 面板滑杆域同批换
  `strengthRange 0...1`、`luminanceRange ±2`——**常量面新增**，v1 常量
  保留供冻结视图）。
- **Params/identity**：`Params.offset: ColorWheelControl?` additive
  （encodeIfPresent/decodeIfPresent——D-M9SP-2）；`isIdentity` 现行 v1 形
  保留（frozen 打包 flag 面）+ `isIdentityV3`（四轮全中性 0 基）新增；
  commitParams frozen 16-float 打包**逐字节不动** + params 镜像缓存
  （NSLock）；v3 dispatch 自建 14-float buffer + memo（键 =
  piece.paramsHash）。
- **CPU 参考**：`referenceV3(acescc:params:)` Float64 镜（含转换物化语
  义：offset 缺席先 ConvertLegacy）；旧 `reference` 保留（冻结 golden 用）。

### X2 ConvertLegacyColorWheel 转换器（Plan T1；纯函数可单测，新文件 GPL 头）

- **lift→offset 精确转换**：`K = (color_offset[ch] + luminance_offset) ×
  CE_ACESCC_B`（v1 lift 是 ACEScc 加法 = 全影调同移 = 新 Offset 定义）。
- **gamma/gain→lift/gamma/gain 最小二乘拟合 `FitLegacyGammaGain`**：每通道
  −6..+6EV 25 采样点、旧公式（含旧 lift）输出为目标、Gauss-Newton（数值
  雅可比 step 1e-4、法方程 3×3 高斯消元、≤20 迭代、收敛 <1e-9）拟合三
  K；误差常见 ≤0.03 档、旧 lift ≈1.4 档同调 gamma 时两端可达 ≈0.12 档
  （结构性残差——新 Gamma 在 ±6EV 不起作用）。拟合 K 拆均值（→
  luminance_offset）+ 零均值部分（→ color_offset + `ChannelStopsToDisc`
  反演截单位圆）；**不截断**（渲染即拟合结果）。
- 消费双点：v3 渲染预解（offset 缺席 shape——memo 化）+ v3 面板编辑投影
  （首编辑物化基线，D-M9SP-2 补强①）。同一纯函数单源。

### X3 process fork + 缓存折键 + 渲染入口（Plan T2；D-M9SP-8/9 代码级）

- fork 点 = `ColorWheelsModule.process` 读 `piece.renderProcess` →
  `RenderProcess.resolving` exhaustive switch：`.v1/.v2` → frozen 路径
  （现 dispatch 逐字节）；`.v3` → v3 dispatch。加 case 编译器逐点指向
  （RenderProcess.swift processVersion switch 先破——账本半边）。
- 折键 = `ModuleBoxing.processForkHash` default nil + `ModuleBox` 转发 +
  `prepareChain` 折一处（`:946-976` 域）；PixelPipe 触碰**逐 hunk 申报**
  （封存面例外申报——M6-2 IOPiece stamp 注释预留缝兑现 + M8-2
  assembleFilmLeg fork 同文件先例）。
- 渲染入口穿线核验清单（execute）：已穿 = coordinator 主渲染双路 +
  EXPORT 主腿（ExportRenderer `renderProcess: documentProcess`）；未穿
  9 处调用点 + THUMBNAIL guard 设计修订 + 豁免面（SessionThumbnail
  Renderer/CullingView）——清单正本 = D-M9SP-8 第四段（v2 修订后）与
  plan T2 Action 3③。

### X4 迁移 UX 泛化 + 面板双形（Plan T2；D-M9SP-7 代码级）

- `FilmMigrationAction.evaluate` 输入扩（hasColorWheelsEdits + editing
  窗含 colorWheels）——文件名与类型名保持（历史沿革，DECISIONS 注记泛化
  史）；`runProcessMigration` guard/marker 泛化；`ProcessMigrationRow`
  copy 中性化 + 双面板挂点；v3 面板四轮 Section（Shadows/Midtones/
  Highlights/Offset 命名 + 英文副标题保留 + tooltip）+ stops 域滑杆
  （D-H1 三段）+ 编辑投影消费 X2 转换器。
- **面板 fork 面**：v1/v2 档 = 现三轮视图逐字节（冻结视图）；v3 档 =
  四轮 stops。读 `coordinator.documentProcessVersion` 单源。

### X5 LUT encodings 表扩（Plan T3；D-M9SP-3 代码级）

- `LutEncodingId` enum **尾插** 10 case（id 拼写照上游：sony_slog3_
  sgamut3cine / fujifilm_flog2_fgamut / canon_clog2_cinemagamut / red_
  log3g10_rwg / blackmagic_film_gen5_bmdwg / davinci_intermediate_dwg /
  dji_dlog_dgamut / p3d65_gamma26 / p3dci_gamma26 / rec2020_bt1886）；
  `LutTransferCurve` **尾插** 7 case + `encodeChannel/decodeChannel` 双
  落笔（Float64 正逆对，常数上游表直取——OCIO 2.5.1 port 注记随 NOTICE）；
  `gamuts` dict 增 6 键（primaries/white 逐值照上游矩阵）；`all` 表
  增 10 行（行序按上游 scene/display 分组尾插，我方 `linearRec2020` 行
  位置不动）。**既有 17 行 + 9 gamut + 既有曲线字节零触碰**（add-only）。
- golden：每曲线往返（正∘逆 = 恒等，1e-12 级）+ 单调 + 端点 + 6 gamut
  上游对拍 + 10 行 find(id:) typed lookup + 端到端 encode/decode 采样。

### X6 尾件三件（Plan T4）

- **Filmstrip stars/双态**：`FilmstripRowView` caption 区加星行
  （`row.rating` 直读——勘误①；`ratingBadge` 先例形 ★ 重复 + 「–」占
  位 + AX id `filmstrip.row.rating.<id>`）；editing/selected 双态分档
  走查核验（accent edge/selectedRing 保留，D-M9SP-5）。
- **Show in Finder**：图库 grid 行 contextMenu + Filmstrip 行 contextMenu
  + 编辑器 Image 菜单（AIEnhance 菜单同区——正本 execute 期定位）；
  `PostExportActions.revealInFinder(:174)` 先例同款调用（L057 无涉——
  `activateFileViewerSelecting` 非模态面板）。zh 键 `action_show_in_finder`
  + AX id。
- **XPan ratio 三行**：`CropAspectPreset` 尾插 3 case（rawValue
  "65:24"/"2.75:1"/"6:17"）+ `dn` 臂（(65,24)/(11,4)/(17,6)）+ picker
  3 行 + ratio bits 双向映射臂（`CropPanelView.swift:36-149` 域）+ zh 键
  3 枚（D-M9SP-6 值）。

## Hazards（五条，登记 + 消解绑定）

| hazard | 机理 | 消解绑定 |
|---|---|---|
| **H-SP1 缓存双臂错配（最高风险）** | 甲形态下 params 字节不变（offset 缺席）→ v1/v2/v3 臂同 paramsHash → chain 键同 → 冻结臂与新臂共用缓存平面（观感互污）；box hash 在 setParams 时刻提交，升号不触发重打包 | D-M9SP-8：run 级 prepareChain 折（per-box processForkHash，resolved-arm discriminator）+ 负测三件（键不撞/旧臂恒等/参数维不吞）——T2 硬门 |
| **H-SP2 paramsHash/HistoryHash 字节漂移** | offset 键若同步写出（非 encodeIfPresent）或编码序变化 → 全量历史档 paramsHash 假漂移 → 缓存全失效 + driftDetected 误报 | D-M9SP-2 字节零漂负测（`Params()` 编码 hash 常量钉死）+ sortedKeys 既有纪律复验（ParamsCoding.swift:22-28） |
| **H-SP3 拟合观感近似残差** | 升号后旧档观感 = 拟合近似非逐位（常见 ≤0.03 档/极端 ≈0.12 档）——用户感知「升级变色」 | 确认文案如实声明（panel_process_migrate_body 扩一句）+ golden 转换锚双档（常见域 0.03/极端域 0.12 带内）+ DECISIONS 登记偏离（对上游 LoadJson 即转换的更严纪律是有意设计） |
| **H-SP4 封存面触碰纪律** | PixelPipe 在 M7-6 封存清单；GradeCatalog identityJSON 若动中性值 = 触清单 | PixelPipe 逐 hunk 申报豁免（M6-2 stamp 预留缝 + M8-2 同文件先例）；**GradeCatalog identityJSON 零改（天然零改——`defaultLook` 无 colorWheels identityJSON 条目，`NodeOwnershipCatalog.swift:297` 亲核仅 exposure/contrast/saturation 三条，v3 臂转换不触 catalog〔v2 按 plan 评审 m-4 改措辞，结论不变〕；先例 = LUT 内置集 seeder 数据行替换未算破面，本批连数据行都不换）** |
| **H-SP5 曲线/矩阵常数手抄错** | 7 曲线 + 6 gamut 常数从上游/OCIO 转录，手抄错 = 静默色偏 | 上游表常数直取（git show c740f7b）+ 每曲线往返/单调/端点 golden + gamut primaries/white 逐值对拍——T3 机检 |

## 转写勘误（RESEARCH → 本批 planner 亲核批，执行以勘误为准）

1. **Filmstrip rating 数据面勘误**：RESEARCH §4.2 称「App 侧
   LibraryGridModel 行结构未带 rating（构造点 `LibraryGridModel.swift:222`
   等三处 keyValue 投影无 rating）」——实核：`LibraryImageRow`
   （`LibraryQueries.swift:95-130`）**已含 `rating: Int64?`（:112）**；
   Filmstrip 行直接消费 `grid.rows: [LibraryImageRow]`
   （FilmstripRowView `:271` `let row: LibraryImageRow`）；`:222/:320/:571`
   三处是**分页锚构造**（`keyValue: .int(nil)`），非行投影。且网格已有
   星级渲染先例（`LibraryGridView.ratingBadge :562-565` + AX id `:451`）。
   → **T4 stars = 纯 FilmstripView 行 UI 改动（零 Core / 零 GridModel 改
   动）**，成本低于 research 估的 1 天。
2. **上游工作区 stale**：本地 AlcedoStudio checkout HEAD = `6024386`
   （PR #409 merge），**早于**三锚点（`e1effd8` #446 / `7ccb0ec` /
   `c740f7b`）；锚点 commit 在对象库可读（`git show` / `git ls-tree` 亲
   核），工作区无 v2 文件（grep ApplyToneWheel 零命中）。→ 执行读法一律
   `git show <sha>:<path>`，**禁工作区直读**（lumen-culling「禁触其工作
   区」同款）。
3. **M8-3 迁移通道泛化面**：RESEARCH §3.3 称「复用 M8-3 通道」——实核
   `FilmMigrationAction.evaluate` gate = `hasFilmRecord`（**film 专属**，
   `EditorState+FilmMigration.swift:49-76`）、`runProcessMigration` 同
   guard + film 记录 marker（`PipeCoordinator.swift:858-875`）。v2 档
   colorWheels-only 文档当前**无迁移行**。→ 复用 = 通道形态复用，gate/
   marker/copy 泛化是本批真实工作量（D-M9SP-7 显式列）。
4. **peakNits 逐行照上游**：上游 `p3d65_gamma26` 行 peakNits = **48**
   （DCI 参考白）非我方 display 行族 100 惯例——表行照抄时 peakNits 逐行
   照上游值，勿按我方惯例归一。

## 红线 front-matter（共用正本，plan 逐条引用）

1. **v3 bump 五件套**（D-M9SP-9）：`RenderProcess` case v3 + `all` 尾插
   + `current` 2→3（`RenderProcess.swift:90`）+ AGENTS 账本行 + 新旧
   golden 三件套。禁裸改旧 case 语义（冻结纪律本体）。
2. **双臂纪律**：冻结臂（v1/v2 → 现行 kernel/打包/参考式/golden 逐字节）
   ；v3 = `ApplyToneWheel` 新 kernel `grade_color_wheels_v3`
   （ColorWheels.metal append——现行 `grade_color_wheels` 函数体逐字节
   保留）。**新 kernel 申报面清单全批唯一**（D-M9SP-9）；零其它新
   kernel（Lut3dKernels.metal 等零 diff）。
3. **PipeCache 折键**（D-M9SP-8）：prepareChain 级 per-box
   processForkHash、discriminator = resolved arm（v1/v2/legacy 零折 = 键
   字节恒等）；负测三件 T2 硬门；PixelPipe 触碰逐 hunk 申报。
4. **params 甲红线**（D-M9SP-2）：零 modversion bump、零 sidecar schema
   bump（v11 保持）、旧档字节零改写；offset additive optional +
   encodeIfPresent 字节零漂负测；转换不落盘（未物化档）；物化仅经 v3
   面板首编辑。
5. **封存面 17 件零 diff**：DrtRecord / TerminalTailPolicy /
   DrtTailAssembly / **PixelPipe（例外申报：prepareChain 折一处——逐
   hunk 申报豁免）** / Lut3dKernels.metal / DrtEotf / ExportQueueContract
   / 六格式导出矩阵 / NodeGraphCommand / LightamerSidecar（v11 不 bump）/
   HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order /
   **GradeCatalog（identityJSON 零改——天然零改：defaultLook 无
   colorWheels 条目，`NodeOwnershipCatalog.swift:297` 亲核）** /
   Registry / ModuleInstance。例外申报面全批恰两处：PixelPipe prepareChain
   折 + ColorWheels.metal append（后者本非清单内，登记为纪律面）。
6. **LUT 表 add-only**（X5）：enum/曲线/gamut/行全尾插；既有 17 行 +
   9 gamut + 既有曲线字节零触碰。
7. **xcstrings 尾块纯插入** + 收尾 `Scripts/zh-audit.py --check` +
   `--self-test` 双 PASS；动态键显式 switch 返回静态键（V14）；
   `String.LocalizationValue("prefix_\(x)")` 插值禁形零命中。
8. **GPL 归属（不可延后件）**：`color_wheel_tone` 公式族 + 转换器 +
   解析锚（上游 `e1effd8`，GPL-3.0-only + section 7 additional
   permission）与 encoding catalog 行/曲线常数（`c740f7b`，含 OCIO 2.5.1
   port 注记）——文件头保留上游版权声明 + 修改标注 + 根 `NOTICE` 新条目；
   零归属入库 = 流程违规。
9. **上游读法**：一律 `git show <sha>:<path>`（勘误②——工作区 stale）；
   禁触 AlcedoStudio 工作区。
10. **D-H1 三段提交**（四轮 stops 滑杆/strength/luma 全走）；L057（迁移
    confirm sheet 保持 SwiftUI sheet 形——M8-3 先例即合规）。
11. **测试落域 + L041**：新测试文件 → `Project.swift` 对应 bundle 显式
    数组 + `M2-4-0-BUNDLE-MAP.txt` 登记行；`tuist generate` 恒为该批最
    后一个动作。落域：kernel golden/转换/缓存折/LUT → **LightamerTestsIOP
    （IOP）**；迁移 gate/面板 fork/stars/Finder/XPan UI →
    **LightamerTestsApp（APP）**。跨 bundle 零重域。
12. **全套带式对账 + 机器级单重活**：基线链 = **R6 收口终值 4292/35/0
    （R6-SUMMARY:55 亲核）⊕ ΔN_M9-1（+20..29）⊕ ΔN_M9-2（+15..20）⊕
    ΔN_M9-3（+14..19）⊕ 本批（+11..15）** → 终带 4352..4375——**本站
    大概率最后执行，开工前亲核四前站 SUMMARY 实数落基线表达式**；全套
    `--all` = orchestrator 批准制 + 8G 门 + MEMFAIL 机检 + GUI 实例 ps
    清零验证 + monitor 伴跑；重活前过 `Scripts/machine-guard.sh`。
13. **UserDefaults 零新键**（本批无新设置面——XPan/LUT/stars/Finder 均
    无设置键；迁移 gate 是文档态非偏好）。
14. **commit-per-task**（Conventional Commits 全英文、只 add 相关文件、
    不 push）；**产品面提交带 issue 关联**（`fixes/closes/refs #NN`——
    AGENTS 提交与 Issue 节；`.work/gsd/**` 规划文档免关联）；前缀
    `feat(m94)`/`fix(m94)`/`test(m94)`/`docs(m94)`。
15. **C 档门控**：T5 闭环后停汇报（M9-4 = M9 末站；phase VALIDATION 与
    M9 收口另批）；开工前核 `.work/config.toml [gsd]` paused/auto。

## 测试策略总纲

- **冻结臂零漂主门**：现行 golden（identity 逐位 + 4 参数点）原样保留
  跑通（缺省 `.legacy` → v1 冻结臂）+ v2 stamp 变体逐位断言 + 缓存键
  legacy/v1/v2 恒等（H-SP1 负测②）。
- **新臂 golden 三面**：①kernel vs referenceV3 参数点族（四轮各一点 +
  combined + 超域采样——OQ-4）；②上游解析锚套件移植（每轮 +1 档目标
  影调 ΔEV≈1 / Lift-Gain 分离比 ≥4× / 四轮中性全影调 ≤1e-6 / disc↔stops
  往返 1e-4 / 越界截单位圆）；③转换锚（lift→offset 精确逐通道 + 拟合误
  差常见域 ≤0.03 档/极端域 ≈0.12 档带内 + 拟合不截断 + v3 JSON shape
  round-trip）。
- **缓存折键负测三件**（D-M9SP-8）：键不撞/旧臂恒等/参数维不吞——
  PipeHash.upstream 纯函数域表驱动（既有 PipeCacheTests 同域先例）。
- **params 字节零漂**：`Params()` 编码 hash 常量钉死 + offset 在场/
  缺席 round-trip + tolerant decode（旧 JSON 无 offset → nil）。
- **迁移 gate/marker 泛化**：evaluate 表驱动（film-only/colorWheels-
  only/双有/双无/editingInFlight 五态）+ marker 双形（film item / cw
  verbatim item）+ 面板 fork 双形读投影。
- **LUT golden**：7 曲线往返/单调/端点 + 6 gamut 对拍 + 10 行 typed
  lookup + 端到端采样（X5）。
- **UI 面**：stars 行渲染（rating 0-5 表驱动）/Finder 菜单可达（AX id）/
  XPan dn·bits 双向 + picker 三行/双态视觉走查配方（gui-acceptance
  m9-4 MANIFEST）。

## 晨审推翻点索引（可推翻面速查）

- **D-M9SP-1**：冻结臂锚我方字节 ↔ 回溯上游 v1 数值（历史观感变色，不建议）。
- **D-M9SP-2**：甲 + 判别子/镜像补强 ↔ 乙（modversion 落盘迁移，HistoryHash 全动）。
- **D-M9SP-5**：双态轻臂核验 ↔ 上游视觉规范重做（成本升）。
- **D-M9SP-6**：三行值 65:24 + 2.75:1 + 6:17 ↔ 换值/砍行（纯数据行直改）。
- **D-M9SP-7**：单行泛化 + 中性 copy ↔ 双行/不泛化 marker。
- **D-M9SP-8**：resolved-arm 折 ↔ `rawValue > 0` 字面形（旧键漂移，禁）。
- **红线 12**：基线带式表达 ↔ 实数落（前站 SUMMARY 亲核）。

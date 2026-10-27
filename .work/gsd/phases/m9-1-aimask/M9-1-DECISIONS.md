# M9-1 DECISIONS — AI Mask 工具 parity 执行批裁定记录

> 执行批 = 2026-10-27（HEAD 371a3d95 起，plan v2）。本文件登记执行期
> 全部裁定与偏差申报：plan 预授权面（M-1/M-2/m-1..m-5 落地形态）+
> 执行期新裁定 + 技术发现。OQ 裁决正本 = `CONTEXT.md`（D-M9A-1..10，
> 执行中未重开）。

## 一、plan 预授权面的落地形态

### D1. 候选传值缝选定形态（M-2 二选一）→ **② 候选专用合成臂**

`PipeCoordinator.candidateOverlayRequest: (texture: MTLTexture, strength:
Float)?` + `setCandidateOverlayRequest(_:)`——独立 request 变体，旁路
`applyMaskOverlayIfRequested` 的 spec 组装（该腿的 `unwrap(layer.mask)`
与 caller `hasAnyPayload` 门对无 layer.mask spec 的 session 候选结构性
不适用，判据与 plan 一致）；走同一 render 尾插入点（renderPreview 内
`candidateOverlayRequest` 分支先于 legacy `maskOverlayRequest` 分支，
newest-wins 门 = 现役 generation gate 复用）。**未选 ① request 形态扩
展**的理由：`maskOverlayRequest` 三元组被 LayersPanel/commitRasterMask/
MaskToolbarView 多点消费，加纹理位 = 全调用点类型侵入；专用臂 additive
零扰动。legacy switch 的 `.candidate` case 为防御分支（同 tint 降级），
正常运行不可达。

### D2. Expand CPU/GPU 合法偏离（m-1 申报句，收口登记）

`AIMaskMorphology` = CPU Accelerate vImage（`vImageDilate/Erode_PlanarF`），
**显式偏离 REQUIREMENTS M9AIM-03 与 ROADMAP M9-1 行的「GPU 算子」字样**
——零新 kernel 红线优先（D-M9A-9）。GPU 化 seam 注记在文件头（后续优
化批可走 M8 新核申报制 kernel 化）；本批零 `.metal` 触碰（grep 机检 0）。

### D3. 采样件落点 → **新文件 `LightamerCore/Sources/AI/AIMaskGeometry.swift`**

未并入 AIMaskTypes（execute 期定，plan 预授权二选一）：采样 = 独立纯
函数族（等弧长/格点/归一化/折叠），与类型定义文件职责分离；AIMaskTypes
保持零 diff 面（除 .scribble 撤除）。

### D4. `.scribble` 撤除形态（m-5 口径落地）

**全删**：`AISubjectSeed.scribble` case、`AIMaskError.scribbleNotSupported`
case、`buildLayerBRequest` throw 点、`recordSeed` guard、三处注释改写
（AIMaskTypes seed 文档 / LayerEditingState UPGRADE SEAM 段 / service
switch）。Path 落地形态 = refine 点序列（`AIMaskPathSampling.sampleStroke`
→ `addIncludedPoint` 既有路径，**不经 scribble seed**——Vision API 无
scribble seed 面，case 成死代码故删）。测试改写两处：
`AIMaskSemanticTests.testScribbleSeamThrowsTyped` →
`testPathStrokeSamplingFeedsTheRefineVector`（拒绝负测 → 采样激活正
测）；`LayerUIWiringTests` 的 recordSeed(.scribble) 段删除（编译期面 =
case 不存在）。grep `scribbleNotSupported` 全仓零残留（验收机检过）。

### D5. re-entry 意图变更注释（m-4）

`AIMaskEditing.swift` AIMaskSource.person 的注释由「a person re-bake
must never seed a segment session」改写为：自动联动仍禁（AI commit 不
得自动拉起 segment 会话）+ 用户显式 re-entry 走
`.segment/.subject/.person` 三源路由（`armSegmentSession` 扩源）。
depth/skin/手绘不路由（测试负测在册）。

### D6. paste 语义反转（D-M9A-8 申报件）

- **反转语义**：现行「mask 随 payload 走」（`AdjustmentTransfer.
  buildPayload` 原 :193-195 contentRevision 置 nil 后 mask 原样随行）→
  改为 **AI-baked raster 不入 payload**（上游 D18 对齐：AI 蒙版描述
  本图内容）。判据 = `AIMaskSource.source(ofFileName:) != nil`（唯一
  谓词，无第二份识别逻辑；消费点恰两处 = re-entry 路由 + paste 排除）。
- **保守臂**：只排可识别 AI 件（五前缀）；degrade/rename 蒙版（前缀
  消失）不排——R-2 判据脆弱性的申报处置。手绘 raster 无前缀 = 不排
  （负测在册）。
- **剥离粒度**：AI raster 从 mask 剥除；drawn/parametric 载荷保留；
  剥空（无任何 payload）→ 整 mask 置 nil。KD-3 的 contentRevision
  epoch reset 对一切保留 mask 维持。
- **名单呈现**：`AdjustmentTransferPayload.excludedAIMasks`（skip list）
  + paste 按钮处 count toast（`transfer_ai_masks_excluded %lld`，静态
  键 + String(format:) 惯例）。
- **存量断言翻转清单**：`AIMaskPatchFlowTests.testPersonMenuRouting
  SourceFace`（「person never seeds」断言 → 三源路由正测 + depth/skin/
  手绘负测）；`AdjustmentTransferTests` 零翻转（其断言面 = 枚举/选择/
  排除谓词，不涉 mask 随 payload 行为——9/0/0 全绿复核在案）。MCP 面
  `copy_adjustments`/`paste_adjustments` 共享 Catalog = 排除自动生效。

### D7. Expand→Feather 应用序（附带裁定维持）

bake 缝序 expand → feather → quantize（`RasterMaskStore.bake` 的
expandPx 前置 pass）。golden 钉死：合成序 == 手动链（expand 预处理 +
bake(featherRadius)）逐字节；反序（feather 先）在非线性面上确实不同
（对称线性斜坡上 blur/shift 数学交换——首版测试面踩坑后换随机+平台面，
见 D9 教训条）。上游 margin 式不锁序的证据维持。

## 二、执行期新裁定（plan 未预授权面）

### D8. vImage bias kernel 方向雷（技术发现，vImageDilate/Erode_PlanarF）

Swift overlay 导入 **C 原生参数序** `(src, dest, srcOffsetToROI_X,
srcOffsetToROI_Y, kernel, kernel_height, kernel_width, flags)`——首版
误传 `(3,3,kernel,1,1,…)` 实为 ROI=(3,3)（空 ROI → dest 未写）+
kernel 1×1。kernel 是**灰度形态学偏置核而非形状掩码**（Morphology.h
公式 + 独立 probe 实证：dilate/erode 均按 `src − k` 折叠，dilate =
MAX(src−k) − k[center]、erode = MIN(src−k) + k[center]）。形状 trick：
参与位 bias = **ε=1e-9**（±ε 往返 ≤50 步累积 1e-7 ≪ uint16 量化步
1.5e-5——**量化域精确**，R8 论证的对拍域）；排除位 bias **方向性**
±1e30（dilate 用 +1e30：src−1e30 恒输 MAX；erode 用 −1e30：src+1e30
恒输 MIN）——−∞ 不可用（dilate 的 MAX 累加器饱和传染，实测全 −inf）。
教训落 LESSONS 候选（本批 DECISIONS 登记）。

### D9. 对拍/序断言的测试面选择

对称线性斜坡上 blur 与平移（erode 的斜坡效果）数学交换——「expand→
feather ≠ feather→expand」断言首版在纯三角面上假阴性（两序逐字节相等
= 线性核在线性段上的交换律，非产线 bug）。换**非线性随机面 + 平台**
后序可分辨。同理 quantization 对拍落在 uint16 量化域（D8 的 ε 论证）。

### D10. 点删除手势 = 点击命中删除

plan 只定 `removePoint(at:)` 语义未定手势。落地面：tap 落在现有 marker
（屏幕距离 ≤12px）= 删除该 refine 点（含/excluded 两向量各自最近命中；
seed 点不在此列——seed 是 seed 不是 refine 点，其「删除」= recordSeed
重置语义，不混入）。删除后同样调度候选重解。

### D11. Path 无工具切换器（手势即工具）

上游 Prompt tools 三 icon（Point/Box/Path）不建——我方手势天然分流
（tap = point、⇧-drag = box、plain drag = Path），零切换器零状态。
`ai_path_tool` 键**不加**（零消费面 = 死键防御，M-1 同款精神；plan
键族清单里该项按此裁定豁免）。合法偏离登记（交互形态差,验收不照抄）。

### D12. T1 label 键迁移 + 三死键删除

任务面板化后 `ai_mask_subject`/`ai_mask_subject_inverted`/
`ai_mask_person_instance` 三键零消费 → zh-audit ORPHAN 守门 FAIL →
**删除**（非「触碰历史键」：本批产生的死键，Xcode 紧凑格式键块的配平
删除，JSON 有效性与 zh 完整性复核在册）。`ai_mask_feather_label` 等在
役键字节零触碰。

### D13. 候选面的 nil-stamp identity guard 语义

`runCandidateResolve` 不跑现役 `releaseIfIdentityChanged`（其 nil-stamp
语义 = 「nil stamps 只对活图 mismatch」会把**新鲜候选面**在首解前清
掉——测试踩出）。修正：仅 `patchImageURL != nil`（patch 流程在飞）时
跑该 guard；候选面的 teardown 由 eager release（select/load 的
`releaseLivePatchState` 已含 `releaseCandidate`）+ bake 侧 armedImageURL
门兜底。残留风险：程序化 `setSegmentActive(false)`（非 host 路径）不
清 coordinator 的候选 overlay request——host 的 onDisappear +
cancelSession 双路覆盖主路径；程序化调用点现役仅 setTool/armSegment
内部（无候选窗口）。注记在案，走查轮观察。

### D14. R-1 大图多步重解延迟门（数据引证 + 探针归属）

- 门值 P95 ≤500ms/步：**Layer B warm 基线 85-126ms/步**（25-102MP 全
  档，07-1-DECISIONS:30 在案实测）= 4× 余量门内；大图 100MP 上限预算
  ≤2s/步告警线（基线 126ms 距告警 15× 余量）。
- 冷启动 5.5s = 进程首启一次性（EntryGate 三态门现役）；首步 spinner
  + `ai_candidate_solving` 文案承接。
- debounce 300ms（`SegmentSession.candidateDebounceMs` 单源）合并连点；
  超门自适应（debounce 升 500ms）**未实装**——基线余量 4× 下无触发
  面，plan 降载方案 ③ 保留为后续预案（超门实测时再启，DECISIONS 预
  登记）。
- 真机 P95 探针：CI/test-built app entitlement 拦 DownloadableAssets
  （`ensureLayerBAssets` 门 = 测试环境 skip 既知形态）——**真机逐点延
  迟实测挂 gui-acceptance 走查轮**（omp computer-use 二次验收承载），
  本批以 07-1 基线引证 + debounce 设计余量申报。

### D15. ΔN 越带申报（+33 vs 带 +20..29）

实数：T1 5 + T2 9（Morphology 5 + FeatherPx 4）+ T3 14（PathSampling 6 +
Iterative 8）+ T4 5 = **+33**，越 plan 上限 29 超 4、越 charter 带
+20..28 超 5。构成剖析：T2 = 上限原位（9）；T1/T4 = 带内；**越带全部
落在 T3（14 vs 预算 6..9）**。理由：Iterative 8 法与 AI-06/交互断言
面一一对应（点删预算回收/debounce 合并/失败保留旧候选/样式白名单/
sidecar 零写入/commit 双清除/cancel 零 bake/色值单源——各自承载独立
红线，并法则掩盖独立断言面）；PathSampling 6 法 = 数学面独立（格点/
归一化/跨段弧长/短笔触/预算折叠/上限截断）。m-2 申报精神（golden 面
各承载独立红线论证不可省）的实数落地；收口轮按 33 如实对账。

## 三、红线复核（收口机检汇总）

- 封存面 17 件零 diff（git log 全批 file 面核对；PixelPipe 零触碰）。
- 零新 SPM（Accelerate 系统框架）；零新 AI 模型；零 `.metal` 新增。
- sidecar schema v11 零 bump、UserDefaults 零新键（featherPx/expandPx/
  candidatePlane/candidateState 全 UI 态——AI-06 负测在册）。
- xcstrings 尾块纯插入 + 三死键配平删除（D12）+ `mask_overlay_style_
  candidate`/`ai_path_tool` 零在册（死键防御）；zh-audit --check +
  --self-test 双 PASS。
- V50Order 零触碰；D-H1（slider session 态零 history 写入）；disable-
  not-unmount（Sky 槽恒 .disabled）；commit-per-task（T1..T5 各一）。
- GPL 零复制：形态学核序/σ 换算/采样常量/色值 = 公开数学与数值参数
  （上游 file 出处引 RESEARCH 附录表）。

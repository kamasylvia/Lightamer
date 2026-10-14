# M6-3-01-PLAN-REVIEW — M6-3-01 plan 独立评审报告（2026-10-13）

> 评审 = zcode 独立 subagent（plan_review_by_omp 制度的独立 plan 评审路，零共享
> 上下文；config 亲核 `auto=true / paused=false / dual_acceptance=true /
> plan_review_by_omp=true`——本路与串行 omp 二次验收双轨成立）。审查对象 =
> `M6-3-01-PLAN.md`（HEAD `207dcc58`）+ `M6-3-CONTEXT.md` + `RESEARCH.md`；
> 对照先例 = `M6-2-01-PLAN.md` + `M6-2-CHECKER.md`。全部 file:line 为 HEAD
> `207dcc58` 亲核（该 HEAD 相对 plan 锚定基线 `55eb8f3c` 仅 +docs，源码逐字节
> 同基——plan 锚点有效）。

## 结论

**须修后放行 / 2 error + 4 minor + 4 建议**

- E1/E2 = plan 文本级必须修订（一个修订批，不动六项 OQ 生效值）：E1 是
  validate 完备性缺口（第五门缺失——yiyin 组合产生结构性损坏的 MPF 容器），
  E2 是 PixelPipe 解封申报范围与代码事实不符（capture 闭包物理触点 ≠
  「runTerminalTails 单调用位」——照原文执行 T1 diff 自证必自相矛盾）。
- M1 = KD-3 一处与源码相反的事实 claim（retry token 复用），须改写；M2/M3 =
  UI 矛盾态处置规则缺失与 HDR-encoding EOTF 语义缺口（后者涉 OQ-5 生效值
  扩充，须 orchestrator 确认或走 CONTEXT 晨审通道补裁）；M4 = 臂级静默降级
  面，建议 fail-loud 一行。
- **六项 OQ 生效值（D-M6-3-1..6 全 A）无一需要重开**；CI 全服务路、四文件
  级零 diff 红线、box 交接（contract 载体不扩）、L009/F5/E4 三条 spike 结论
  的消费形全部与源码和 RESEARCH 一致——主体交付面成立，修订后可进执行。

---

## E1（error，维度 2）：validate 第五门缺失——`gainMapHDR ∧ yiyin` 组合结构性破坏 gain map 容器

**源码事实**：

- `ExportRecipe.swift:45-49`：`yiyin` 是 variant 一等字段（EXP-05 共享面）。
- `ExportRenderer.swift:466-473`：step 5 yiyin 注入对 `variant.yiyin` 无条件
  apply（与 drtTail 正交——`yiyin ∧ drtOutput≠nil` 是可构造组合）。
- `PixelPipe.swift:1741-1777`（DrtTailAssembly）：`.drt` 尾段回放序 =
  `[method 74 → post 74.1+ → EotfBox 75 → borders 76 → watermark 77]`——
  **borders 在 EotfBox 之后**，带边框时尾输出（→ exit 位图）画布尺寸**大于**
  EOTF-box 输入平面（capture 面）。`ExportRenderer.swift:248-251` Outcome
  注记亲证「outputWidth/Height — the borders canvas extension INCLUDED」。

**后果**：gain map 档的 SDR base = 出口位图（含边框画布），`.hdrImage` 输入
= capture 面（无边框画布）——两输入尺寸失配时 CI 的 gain 计算语义未定义
（spike 未覆盖此形态），边框区像素的 gain 比率被污染；产物 = 结构上成立但
语义损坏的 MPF 容器，比 typed 拒绝更糟。四门（KD-1）与 UI 三态门（KD-6）
均不覆盖 yiyin 维。

**可达性（诚实申报）**：M2 页 yiyin 恒 false（M2-9 既定），UI 不可达；但
variant 是 public API（Phase 12 preset 面 / 测试 / 直接构造），组合
`yiyin=true ∧ drtOutput≠nil ∧ gainMapHDR=true` 可过现有四门。

**修法**：validate 追加第五门 `gainMapHDR && yiyin → AppError.invalidParameter`
（一行 + 一条负测，KD-1 与 KD-7 各 +1 处）；KD-6 checkbox 可用门可不动
（UI 不可达），或顺手在不可用文案族预留。此为 planner 权限内的 validate
完备性修订，不触 OQ 裁决。

---

## E2（error，维度 1）：PixelPipe 解封申报范围失实——capture 闭包物理触点 = 4 处（同文件），非「runTerminalTails 单调用位」

**源码事实**：

1. **renderStage 持不住 pipe 实例**：`ExportRenderer.swift:499-522` 的 pipe
   装配窗是通过 `RenderPipeline.process / processComposite` 调用参数传缝
   （`terminalTail` / `tailFormatFloatOverride` / `filmTail` 三先例同形）——
   renderStage 没有可「置 pipe.linearGainCapture」的实例。capture 闭包必须
   作为 additive 缺省参数**穿 RenderPipeline 双入口**。
2. **RenderPipeline 在 PixelPipe.swift 内**（`PixelPipe.swift:2012`）——
   文件级申报成立；但入口参数 + pipe 属性赋值是两个额外 hunk（
   `:2081/:2095` 与 `:2143/:2155` 的 tailFormatFloatOverride 同位先例）。
3. **EotfBox 输入平面只在尾段 sub-run 的走查体可见**：`runTerminalTails`
   （`PixelPipe.swift:1126`）只持 top/final 平面；EOTF-box 的输入是尾段
   sub-run 内部中间面，唯一可捕获点 = `processRec` 走查体按 position 取
   upstream 平面处（`:1498-1596`，EotfBox 在位判定 `box is EotfBox` 全仓
   唯一构造点 `DrtTailAssembly.instances :1756`——回调只会在尾段 sub-run
   触发，主链零触发，这点对「窄缝」有利）。cache 命中臂同样可达（upstream
   解析先于 box 处理）。

**plan 失实处**：front-matter PixelPipe 行「runTerminalTails 的 EotfBox
输入点单调用位」+ KD-2「尾段回放在 EotfBox 消费前单点回调」+ T1 验收
「PixelPipe diff 范围 = capture 属性 + 单调用位」。照原文执行：executor 要么
在 runTerminalTails 找不到可捕获面（该函数看不到 EOTF 输入平面）硬写不出，
要么实现后 diff 自证（T1 验收 + checker 关注点 3）按「单调用位」口径误报
扩面——两态都红灯或未登记偏差。

**修法**（plan 文本三处同批修订）：申报范围改为——「capture 属性声明 +
RenderPipeline.process/processComposite additive 缺省参数两处 + pipe 属性
赋值两处 + processRec 走查体 EotfBox 位单回调点（全在 PixelPipe.swift 内，
共 ~5 hunk；`.metal` 零 diff 维持）」。checker 关注点 3 的机检口径同步。

---

## M1（minor，维度 1/KD-3）：retry「token 复用 = 覆盖写」与源码相反——box 清理语义须改写

**源码事实**：`ExportQueue.swift:320-341`（retry）——`seqCounter += 1;
job.seq = seqCounter`：**重试取 fresh seq**，重跑 render 腿 stash 写的是
**新 key**，失败尝试在旧 seq 下的残面**永不被覆盖**。plan KD-3「retry 重跑
render 腿覆盖写同 key——token 复用语义 = 覆盖，DECISIONS 注记」为假事实。

**后果**：若照原文入 DECISIONS = 账面入档假机制；若因此漏建失败路径清理 =
每个 failed/cancelled gain-map job 泄漏一张全分辨率 float32 owned-copy 面
（100MP ≈ 1.6 GB）至 queue 销毁——AGENTS 资源监控口径下不可接受。

**修法**：KD-3 生命周期段改写——①retry = fresh seq 新 key（旧 key 无覆盖
语义）；②清理责任落 actor：box 以实例属性（`init` 生产腿装配时创建，测试
注入腿时为 nil 零行为）供 `finish`/`finishCancelled`/generation 换代路径按
`queued.seq` 清除，retry 入队前清旧 seq 残面；③DECISIONS 注记按①②改写。

---

## M2（minor，维度 5）：embedICC ↔ checkbox 矛盾态无处置规则（plan 自我点名但 KD-6/T3 未闭环）

**事实**：embedICC toggle 在第 3 节（`ExportInspectorView.swift:318/:652`），
checkbox 在第 4 节（:382）——用户先启用 checkbox（jpeg ∧ peak≥203 ∧
embedICC 默认开）再上翻关 embedICC → 「UI 可用但 validate 门④ typed 拒」
矛盾态成立，整批 job 失败。同族面：checkbox 开启后切走 jpeg 格式（:438-449
formatSelection 不复位旗标）或 DRT 面板把 peak 改到 <203——旗标残留、
validate 拒。plan Checker 关注点 7 自己点名「检查有无裸露矛盾面」，但
KD-6 三态谓词只有 format/readout/peak 三维、T3 验收无一条覆盖该交互。

**修法**：KD-6 定一条联动规则（推荐：任一门破坏 → `model.gainMapHDR`
自动复位 false，同 collisionPolicy 会话态纪律；或 run-gate 拦截 + toast），
T3 +1 条负测（embedICC off → checkbox 态/旗标复位断言）。

---

## M3（minor，维度 2，须 orchestrator 确认）：HDR-encoding EOTF 与 gain map 语义冲突未设门——OQ-5 生效值的第五维盲区

**事实**：`DrtRecord.peakLuminance` 注记域 [100,1000]（`DrtRecord.swift:352`
段），而 `encodingEotf = st2084/hlg`（DRT-HDR 面，M2-6 四态）时 M2-9 JPEG
导出的「base」本身是 PQ/HLG 编码 + 对应 ICC（M4-1 SC#1 的 HDR 容器先例）。
UltraHDR/ISO 21496-1 语义要求 base = **SDR rendition**；现四门 + UI 三态门
（peak ≥ 203）**不排除** st2084/hlg 组合——HDR 编码的 peak 通常 ≥203，
checkbox 启用 → 产物 = PQ base + ISO gain map 的不自洽容器（SDR 屏不可读、
gain 比率对 PQ 码值取——恰是 E4 反证禁止的形态在 base 侧复现）。

**修法**：validate 追加 `gainMapHDR && isHdrEncoding(record.encodingEotf) →
typed 拒`（`DrtRecord.swift:463` Core 单源现成；UI 不可用文案或第三条说明
随批）。**注意**：此门是对 OQ-5 生效值可用门集的**收窄**（裁決原文 = 三条
件），超出 planner 独行权限——按 CONTEXT「晨审可推翻」通道由 orchestrator
确认，或作为 M6-3 补裁一条登记 CONTEXT；不确认则至少 DECISIONS 显式登记
st2084/hlg + gainMapHDR 组合的语义豁免与产物预期（当前 plan 对此零字，属
静默）。

---

## M4（minor，维度 1）：gain-map 臂静默降级面——capture 未装臂时产物无声变普通 JPEG

**事实**：capture 装配条件 = `variant.gainMapHDR && drtTail != nil`（KD-2），
而 validate 门② 查 `variant.drtOutput == nil`——两载体 API 级独立（M2 页
由 `enqueueExportM2` 双写强制同源，`ExportState.swift:526-528` 亲证；直接
构造 `Request` 的路径可只填 variant.drtOutput 不带 drtTail）。该组合四门
全过、capture 不装、`encodeStage` 走普通 JPEGEncoder——**无提示的无 gain
map 产物**。修法：`encodeStage` 臂首行 `guard !gainMapHDR || hdrGainPlane
!= nil else { throw AppError.invalidParameter(...) }`（fail loud，一行 +
一条负测；同时兜住 capture 回调异常未触发的面）。

---

## 建议 4 条（不阻断，随修订批顺带）

- **S1（维度 6）**：KD-7 基面保真法①的「采样点逐值相等」是两黑盒编码器
  （CI 内部 JPEG vs ImageIO JPEGEncoder）跨实现相等断言，仅本 host E2 单次
  亲证——与 plan 自己的「禁字节级全量（黑盒漂移防假红）」纪律存在张力。
  建议：该法纳入 gain band 同一 DECISIONS 漂移伞，预登记容差回退预案
  （如逐点带 ±1 LSB band 或样本数下限），防 macOS 升级假红。
- **S2（维度 1）**：风险节备选「encode 腿内二次尾段回放（缓存命中，成本低）」
  **不可行**——encode 腿只持 contract 冻结载体（量化 rgba8 平面 +
  `ExportRenderStage`，`ExportQueueContract.swift:247-286` 亲核无 float32
  上游面/box 链/metal 上下文），且 `PipeCache()` 是 renderStage 局部
  （`ExportRenderer.swift:488`）跨腿不存活；「缓存命中二次回放」等于整链
  重渲。若 box 形真被 checker 否决，真实备选 = 契约面解封申报修订（走 M4-1
  先例）或 encode 腿全链重渲（成本全新评估）。该行应改写，防 checker 否决
  box 后 executor 按不可行备选空转。
- **S3（维度 7）**：零 diff 机检族（T4）建议补 `ExportChainBuilder.swift` /
  `XMPWriter.swift` / `XMPContainerInjector.swift` / `ExportNamer.swift` /
  `ExportQuantizer.swift` 五文件（全部预期零触碰但未列机检——一行成本，
  防借道；checker 关注点 1 的「XMPContainerInjector 不得被 gain map 臂
  复用」由此获得机检托底）。
- **S4（维度 5）**：锚点/落点三处小勘误——①`ExportQueue.makeLegs` 实名
  `productionLegs`（`ExportQueue.swift:581-638`，plan 行锚 :590-636 指向
  正确函数体但符号名不存在，grep 不可达）；②「pump 双腿 :415-473」实为
  `execute` 内双腿段（pump = :377-389）；③KD-6「drivetTails」拼写
  （drtTails）。另「assembled.gainMapHDR = model.gainMapHDR」落点含混：
  RunAssembly.variant 由 `makeVariant`（`ExportInspectorView.swift:814-820`）
  构造，旗标自然落 makeVariant 一行；ExportState assembled 改写需新参数
  穿线——建议 plan 文本定死 makeVariant 落点（T3 测试面「RunAssembly
  gainMapHDR 进 variant」同向）。

---

## 通过项（逐维度，附亲核证据）

### 1. 技术可行性——窄缝成立（E2 修订申报后）、contract 冲突自洽

- EOTF-box 前取面的语义正本成立：`PixelPipe.swift:381`
  （`tailFormatFloatOverride → WorkingSpace.pixelFormat` = rgba32Float，
  `WorkingSpace.swift:31`）+ AGENTS M2-6「EOTF 之前的尾平面恒 working
  float32（display-referred 线性）」+ DrtTailAssembly 回放序（post 四件在
  EOTF 前 = capture 面含 display-referred 后处理，HDR 面完整）+ capture 面
  = 线性光（E4 反证约束满足，结构单点排除 PQ 码值直喂——AC1 双层成立）。
- `ExportRenderStage`/`ExportRenderArtifact`（`ExportQueueContract.swift
  :207/:247`）零 diff + box 交接 = 自洽（contract 载体确实不需要扩——
  `artifact.token = snapshot.seq`（`ExportQueue.swift:606`）作 key 可行）。
- box 生产腿装配/测试注入腿二态（`init :168-171`）与缺省参数零 diff 姿态
  一致；`render()` 合一入口（`ExportRenderer.swift:291-313`）缺省参零触。
- capture 触发面唯一性亲证：EotfBox 全仓唯一构造点 = DrtTailAssembly
  （grep 亲核），主链/editor 视口零触发。

### 2. validate 四门——三门半落位准确（缺口 = E1/M3/M4）

- `ExportRecipe.swift:119-136` validate 现状与 :129-135 既有 finite-positive
  闸与 plan 描述一致；四门全部 additive 追加可行；`decodeIfPresent ?? false`
  先例同构（:110-113 drtOutput/metadataPolicy/embedICC 三先例行）。
- 手写 decode + 合成 encode + 手写 CodingKeys（:97-100）——新键须补
  CodingKeys case（执行细节，additive 零漂移测试 T1 钉死，无风险）。
- 第五门缺失 = E1；EOTF 维 = M3；臂级 fail-loud = M4。

### 3. ExportICCStrip 双旁路——结构性排除成立（全消费点亲数）

- `stripICC` 生产消费点全仓**恰一处** = `ExportRenderer.swift:664`（encodeStage
  `!embedICC` 块 :663-672，行锚亲证一致）；`stripJPEGICC` 其余消费全在
  ExportICCStrip 本体与测试（grep 亲核）——encodeStage 臂级跳过 = §8.4 雷
  结构性排除，`ExportEncoder.swift` 文件零 diff 承诺自洽。
- `mountXMP` 生产消费点**恰一处** = `ExportRenderer.swift:681`（:681-689
  行锚亲证）——旁路完整；`XMPContainerInjector` 不被 gain map 臂复用已入
  checker 关注点（S3 补机检托底）。
- XMP 挂载改走 encoder 内 rewrap（`kCGImageDestinationMetadata`，F5 亲证形）
  = 单次注入无双 XMP——T2「APP1 xap 头单实例」断言可测。

### 4. CI 编码腿——输入要求与平台面全部兼容

- SDR base：量化 rgba8 平面 CGImage（既有 targetColorSpace）——E2 基面保真
  亲证 CI 不改写我方基面；HDR 面：rgba32Float linear Rec2020（F6/D1 兼容
  形，任意 primaries）；headroom = peak/203（≥1.0 门语义一致）。
- `imageBySettingContentHeadroom` 26+ 在 27 底线内零 `#available`（RESEARCH
  §1.1 header 表亲证）；`.hdrImage` 15+；aux 读回 15+——版本面成立。
- L009 同目录 tmp→原子晋升与 RESEARCH §8.5 一致；质量旋钮
  `spec.quality ?? 0.9` 与 `JPEGEncoder:188` 同语义亲证（:188）。

### 5. UI 三态门——锚点全部命中（缺口 = M2/M3/S4）

- `:309` metadataColorSection / `:350` 陈旧注记原文亲证（「the true HDR
  container (UltraHDR) is the M4 ALCE-02 face」）/ `:352-378` drtReadout
  （`:354` loadedImageURL 判据、`:368` isHdrEncoding）/ `:382` sdrSection /
  `:609` panel model / `:652` embedICC / `:814-820` makeVariant——全在位。
- `ExportState.swift:466` m2DrtTail / `:484` enqueueExportM2 / `:526-528`
  drtOutput 强制联动——行锚亲证一致。
- zh 4 键（label/hint/unavailable_format/unavailable_peak）与
  `export_embed_icc_unavailable` 家族拼写惯例对齐；UserDefaults 零新增成立
  （会话态 model 字段，collisionPolicy 先例 `:624-630` 同构亲证）。

### 6. 测试面——算术与归属全部闭合（留意 S1）

- 27 法 = Export 21（4+2+4+2+1+3+2+3）+ App 6，逐分项求和亲算成立；
  `estimated_tests "+24..30"` ⊃ 27 ✓；全套预期 3725+24..30 = 3749..3755 ✓。
- 基线亲证：`M6-2-VALIDATION.md:26/:43`——`TOTAL|3725/24/0|2113s`，段级
  Export **353/4/0**、App **801/4/0**——plan「Export 353+21 / App +6」对表
  基数正确。
- BUNDLE-MAP EXPORT/APP 行先例在案（:256-275/:425-437）；`Project.swift`
  显式清单 + L041 恒末位、test-direct 拼写 `--bundle Export/App`（注册表
  亲核 `BUNDLES=(IOP IOPParity Layers Library Sessions Export App)`）——
  无 M2 式缩写问题。
- golden 禁字节级全量裁定合理（CI 黑盒 gain/元数据；容器结构标记 + aux
  字典 + band 三层可证且抗 OS 漂移）；harness 先例在案（`DrtTailTests.swift`
  14 法 fence 形 / `ExportIccEmbedTests.swift` 8 法；`@testable import`
  使 internal `StageOutput.hdrGainPlane` 可测——import 风格亲核）。

### 7. 红线完备性——清单与 M3-3 封存面逐一对表

- 四文件级零 diff（ImageIOEncoders/WebPEncoder/ExportEncoder/
  ExportQueueContract）恰覆盖 M3-3 封存清单的导出面成员；
  `ExportFormatSpec` 与 ExportVariant 同文件（`ExportRecipe.swift`）的
  「面级零 diff」处理方式成立（hunk 级自证已入 T4）。
- PixelPipe 解封申报 = M4-1 先例同形（文件级申报 + DECISIONS 范围登记），
  修订后（E2）口径可机检。
- UserDefaults/xcstrings/dependencies/`.metal`/V50Order/sidecar schema/
  MCP 封闭集/appex 零触清单完备；`ExportGainMapEncoder` 落 Core 合法
  （CI 在 Core 既有消费先例：CIContextPool/QuickLookRenderer）。
- config 对账：`auto=true / paused=false / dual_acceptance=true /
  plan_review_by_omp=true`（`.work/config.toml` 亲核）——本评审 + 串行
  omp 二次验收 + C 档门控的编排落点正确。

---

## 处置摘要

1. **一个 plan 修订批**（orchestrator 回注或 planner 自修，六项 OQ 生效值
   不动）：E1（+第五门 yiyin + 负测）、E2（PixelPipe diff 范围申报三处
   改写）、M1（KD-3 生命周期段按 fresh-seq/actor 清理改写）、M2（KD-6
   联动规则 + T3 负测）、M4（encodeStage fail-loud guard + 负测）、
   S1..S4 顺带。修订后无需重跑本评审全量——定向复核 E1/E2/M1 相关四节。
2. **M3 单独走确认**：EOTF 门是对 OQ-5 生效值门集的收窄——orchestrator
   批准（推荐，一行门 + Core 单源现成）或明确豁免并登记 DECISIONS；不允许
   维持现状零字静默。
3. 其余全部维持：CI 全服务路、box 交接、四文件零 diff 红线、T1..T5 任务
   分解、SC 数字面、测试钉法主体。

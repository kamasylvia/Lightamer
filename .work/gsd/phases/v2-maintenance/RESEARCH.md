# RESEARCH — V2/Maintenance 修复批 + 清算批（2026-10-13/16 滚存队列全盘点）

> **状态**：research 定稿（C 档第 1 停——OQ-VM-1..5 待用户裁决，未进 plan）。
> 队列来源逐一读齐：TODO「M6 收口走查缺陷登记」+ GOAL-STATE 缺陷挂账节 +
> V2-PROPOSAL §七 + OQ.md + `research/ALCEDO-PARITY-2026-10.md` + REQUIREMENTS
> V2 节 + M6-2/M6-3/M6-4/M6-5 四 VALIDATION 挂账节 + omp-03 §3.1。全部
> file:line 为 2026-10-16 HEAD（`5e87bbe8`）亲核，非凭记忆。
> 基线：全套 `--all` = 3848/24/0（M6-5 T9 确认轮，对账基线正本）。

---

## 一、全队列盘点表

> 状态列 = 本 research 亲核结论（代码/账面双核对）。量级：S（单文件单点）/
> M（多文件或需侦查）/ L（独立 phase）。

### A. 缺陷族（D-1..D-5，GUI 收口走查批登记）

| # | 项 | 状态（亲核） | 量级 | 代码锚点 | 依赖/解锁 |
|---|---|---|---|---|---|
| D-1 | 追色按钮点击零响应（高） | **open；根因面已确认**（见 §二） | **M** | `ColorMatchPanelView.swift:187` binding get → `ColorMatchPanelModel.swift:99-111` params getter → `PipeCoordinator.swift:1667-1669` instanceRecord 读 `editorState.instances`；sample 84/84 flush + 297 sizeThatFits | 修复解锁 GUI-M6C-03/05/06/08 四行；**修复批首项** |
| D-2 | 编辑器视口绿染（高） | **open；假说排序 + 复现配方就绪**（见 §三） | **M** | 解码腿 `RAWDecoder.swift:120-152`（路由）/`:259-273`（RAW 9 automatic opt-in）；缩略 Tier A 内嵌预览 `SessionThumbnailProvider.swift:408-423` + `LibraryThumbnailBridge.swift:10-14`；working space `CIContextPool.swift:144-145` | **修复批第二项**——绿染未修前色彩目测类走查不可信（阻断 Manual-Only 汇编大部分行） |
| D-3 | filmstrip 点击不换图（中） | open；概率复现 ×1 + omp-02 o-ompre1 先例；本批定位了嫌疑缝（未采样） | S-M | `EditorWorkspaceShellView.swift:94-96`（`.task(id: currentImageID)` 重载腿）+ `:101-109`（grid selection onChange 腿）+ `:117-123`（filmstrip onOpen 只写 phase id）+ `:178`（`loadedImageURL != url` 守卫）——三条腿并发序未钉 | 修复批第三项 |
| D-4 | HDR 对话框「0 张」计数（低，cosmetic） | **open；根因已定位**：`.sheet` 内容闭包读**活的** `pendingTargets.count`，sheet 渲染时点选择集已空 → 标题取 0；正文是静态串故正确 | **S** | `SessionBrowserView.swift:340`；目录变体 `hdr_merge_dialog_title %lld` 在册（xcstrings:5092，键面无恙） | 修复批顺带（arm 时快照计数即可） |
| D-5 | 完成 toast 裸键名（低，zh） | **open；根因已定位 = specifier 错配**：插值是 Float（`holeFraction * 100`）→ 运行时查表键 `toast_hdr_merge_done %lf`，目录在册变体是 **`%lld`**（xcstrings:23513）→ 查表 miss 回退默认值面 =「裸键名 0.000000」 | **S** | `LightamerApp.swift:2019`（`String(localized: "toast_hdr_merge_done \(holeFraction * 100)")`） | **并入清算批**；V17 specifier 深检的活体论证（V16 只查前缀不查类型，`Scripts/zh-audit.py:358-365` 注释明言「Specifier deep-checking stays manual」） |

### B. 清算族（N-1 / V17 / 同族小件）

| 项 | 状态（亲核） | 量级 | 锚点 |
|---|---|---|---|
| **N-1** McpLauncher 三插值键 | **已清偿（盘点勘误）**——M6-6 T2 rider `d63cf79c` 提前清偿，`%lld` 变体三条亲证在册（xcstrings:32369/32386/32403）；M6-5 VALIDATION 挂账 #2 登记时点早于 M6-6 执行，「提前清偿偏差登记 VALIDATION §四.2」在案。**从待办队列剔除**；历史行不改写，本表即勘误注记 | — | `McpLauncherPanelView.swift:225/242/246`（调用面无恙） |
| **V17** zh-audit 门扩展 | **open**——V16 断言 5 只做前缀 PRESENT/ABSENT 三态（`zh-audit.py:358-365`），specifier 类型深检（Int→`%lld`/Float→`%lf`/String→`%@`）+ SwiftUI `Text("K \(x)")` 插值族（树内 11 处，3 活体 ABSENT）+ `String(` 跨行族（3 处）不设防；**D-5 是 specifier 缺口的活体样本** | S-M | `Scripts/zh-audit.py`（V16 基础在位，V17 = 断言 6 扩展） |
| Manual-Only 19 行汇编 | open（M6-5 ledger #4 正本 = `gui-acceptance/m6-5/MANIFEST.md` local-only）——**前置依赖 = D-2 修复**（色彩目测类行在绿染态下不可信）+ 供件（自然样张/真无人像照片/layer B 资产/HDR 屏） | — | GUI 批承载 |

### C. V2 九项（V2-PROPOSAL §七，登记 ≠ 立项，终裁在用户）

| # | 项 | 量级 | 触发条件 | 本批建议 |
|---|---|---|---|---|
| 1 | TRACK-MULTIREF（MCP 多参考 + preset 化） | S | agent 编排高频多参考工作流出现 | 留后（需求驱动） |
| 2 | RELEASE-DIRECT-INJECT（Release 直启 WebP framework 不对称） | S | Release 直启基准轮需求出现 | **可顺带清算波**（S 级工具链债；若用户近期要 Release 基准/分发则提级） |
| 3 | PANO-V2（预览画布/参考帧手选/use_edits/焦距/multiband 五件） | L | 全景用户反馈出现 | 留后（独立 research 环） |
| 4 | SESSION-LEGACY-READONLY | M | 用户诉求出现 | 留后（legacy 面默认隐藏，可见面趋零） |
| 5 | PROCESS-WIRING（接线四件套 + 迁移 UX） | M | **首个真实 iop 语义 bump 批触发**（触发条件档，by-design） | 留后（触发未现） |
| 6 | ULTRAHDR-EXIF（EXIF APP1 注入器批） | M | 用户/生态 EXIF 硬需求 | 留后（须与 C 路同批评估，禁自建 APP1 注入器裁决在案） |
| 7 | STACKS-SEMANTICS（栈顶顶替 + 计数口径合一） | M | 图库 stacks 用户反馈出现 | 留后 |
| 8 | SAM-COREML | L | 用户裁立项 = 另开独立 phase | 留后（3.4GB License + 全族自转换） |
| 9 | PATCH-LIVEPLANE（livePlane eager 释放 + patch pass 互斥锁） | S | V2 语义批一并裁 | **可顺带清算波**（S 级、登记级零用户可见面、主修 `b49215bb` 已闭环，余量小） |

### D. charter 挂账 / 留置（M6-5 ledger #5 指针，均 open 不入本批）

- A9 = L057-B 专项（queue 行在案，面板族加固独立批）
- A12 = lut3d add 行维持 M5-1 原判
- A16 = 贴线族 RSS ±3% 口径（AGENTS 在案观察）
- A19 = pano perf freed-but-resident 爬升（perf.md 在案观察）
- A20 = 全史瘦身手术第二次（主会话专属，strip 集重算非空才动手）

### E. 各 phase 残留挂账逐项对表（现状亲核）

| 来源 | 项 | 现状 | 归宿 |
|---|---|---|---|
| M6-1 ① | Manual-Only C 行目测 | open | Manual-Only 汇编（GUI 批） |
| M6-1 ② | 孤儿 fixture | **已根治**（M6-5 T1 `c749ee00`，轮毕复扫零命中） | 销账 |
| M6-1 ③ | legacy 只读回退面 | open | V2 #4 |
| M6-1 ④ | move 窗口 TOCTOU | 原裁零动作终局 | 销账 |
| M6-2 #1 | PROCESS-WIRING 四件套 | open（触发条件档） | V2 #5 |
| M6-2 #2 | SessionBatchApplier 字段丢弃 | **已清偿**（M6-5 T2 `bd81f859` 12 字段全带） | 销账 |
| M6-2 #3 | 孤儿 fixture 同源 | 同 M6-1 ② | 销账 |
| M6-3 #1 | EXIF 注入器批 | open（触发条件档） | V2 #6 |
| M6-3 #2 | 行序方向性断言 | **已清偿**（M6-5 T4 `76729922`） | 销账 |
| M6-3 #3 | gain map 臂 DPI | 原裁零动作终局（登记） | 销账 |
| M6-3 #4 | 门③载体分叉 API 注记 | **已清偿**（M6-5 T5 `c651bb51`） | 销账 |
| M6-3 #5 | 跨生态目检 | open 可选行 | Manual-Only 汇编 |
| M6-4 ① | 栈顶顶替 + 计数口径 | open | V2 #7 |
| M6-4 ②③ | GUI M-1..M-4 + D-06/D-07 补录 | open | Manual-Only 汇编 + GUI 轮补录 |
| M6-4 ④ | SAM CoreML | open | V2 #8 |
| M6-4 ⑤ | livePlane 残差两笔 | open（登记级） | V2 #9 |
| M6-4 ⑥ | M6-1 四项核查 | **已履行**（转 M6-5 完毕） | 销账 |
| M6-5 #1 | minor-1 勘误正本 | 已落账（闭环项） | 销账 |
| M6-5 #2 | N-1 | **已清偿**（M6-6 rider） | 销账（本表 §B 勘误） |
| M6-5 #3 | V17 候选 | **open** | 清算批 |
| M6-5 #4 | Manual-Only 19 行 | open | GUI 批（D-2 后） |
| M6-5 #5 | V2 九项 + 留置 5 | open | 终裁在用户 |
| M6-5 #6 | 3843 核销声明 | 已落账 | 销账 |

### F. EXPORT-PRESET-01（ALCEDO-PARITY-2026-10 §二，REQUIREMENTS :401）

- **现状**：登记候选，未立项。需求 = 导出面板命名预设层（格式/质量/位深/sizing/
  元数据/ICC/命名模板整组具名预设 + 一键套用 + 内置默认 + 用户预设管理）。
- **量级**：S-M——UI 加层面板 + 预设存储（UserDefaults JSON 族，`export.*`
  逐项记忆键是数据基座，加层不撞键族）；无 Core/管线触碰。
- **依赖**：零阻塞；独立性好，可与任何波搭车。
- **本批建议**：入清算波尾（OQ-VM-4 裁）。

---

## 二、D-1 根因确认（读码 + sample 栈对照）

### 2.1 证据链

sample（`evidence/defects/m6c-11-solve-hang.sample.txt`，3s @ 1ms）：

- 主线程 **84/84 样本**悬在 `flushObservers → NSHostingView.beginTransaction →
  ViewGraphRootValueUpdater → GraphHost.flushTransactions → AG::Subgraph::update
  → AG::Graph::UpdateStack::update()`——单个 SwiftUI 事务永不沉降；
- **297 个 sizeThatFits 帧**（`_FlexFrameLayout`/`InsetLayoutComputer.Engine`
  深递归）= layout 重测量风暴；
- 11 处 `LocationBox.update() → ProjectedLocation.update() →
  Binding.ScopedLocation.update()` 嵌套链，叶子 = `closure #2 in
  ColorMatchPanelView.solveSection(_:)` **ColorMatchPanelView.swift:187**（强度
  Slider 的 `get: { model.params.strength }`）→ `ColorMatchPanelModel.params.getter`
  **:102** → `PipeCoordinator.instanceRecord` **:1668** → `editorState.instances`。

omp-03 §3.1 的 AX 签名（两个 slider 同位重叠 196x16 value 0.0 + 强度行/readout
视觉缺失）= 更新风暴下视图身份/layout 反复重建的中间态残影，与机制自洽。

### 2.2 机制（@Observable 读触发链）

1. 强度 Slider 的 `Binding(get:)` 在 **Location 更新（update/layout 期）**被求值；
   getter 读 `model.params`——该 computed 穿**三个 @Observable 对象**：
   `liveParams`（面板模型）→ `editorState.instances`（经 `instanceRecord` 线性
   扫描 + 每次 `JSONDecoder` 解码 `ModuleInstance.paramsData`）→ `instance`。
2. @Observable 的观察注册跟随「当前正在更新的图属性」——layout 期的 binding get
   把热观察对象注册为 **layout 属性**的依赖；
3. 点击 Solve → `isSolving = true`（同步突变）→ 面板重评估 → Button label 换入
   `ProgressView` 引发 layout 重测 → binding get 再读热对象 → 事务被反复
   invalidate，永不沉降；**MainActor 饥饿**——solve 的 async Task（`extractSourceStats`
   起）永远排不上 → 无进度态 / 无 history item / 无 sidecar 落盘（与 D-1 三零
   症状逐一对上）；
4. footprint 2.8G/peak 4.4G = AttributeGraph 反复重建的分配风暴。

「概率性」与「P2 走查当时走通」的解释：`params` getter 首分支
`if let liveParams { return liveParams }` **短路时零热读取**——拖动窗内或
liveParams 在位的会话不穿 coordinator；liveParams 为 nil（打开面板未拖动）+
特定 layout 态才触发。回归窗口候选（omp-03 注记 M3-4/M4/SDK 漂移）中
M3-4-01 T4 把 InspectorView 挂载改到 `.inspector(isPresented:)` 复合 binding
（`ContentView.swift:205-219`）改变了面板挂载环境，修复批可顺带核对该环境差。

### 2.3 修法方向（不写码，plan 裁形）

- **主修（推荐方向）**：binding get 去「热观察读取」——params 快照为面板模型上的
  **普通存储属性**（非观察路径），仅在实例 revision/切换时经 `updateInstance`
  钩子刷新；`get` 退化为纯本地读（layout 期零注册、零 JSONDecoder）。
- 审**同构三级读面孪生**：FilmPanelModel / DrtPanelModel 的 slider binding 若同
  样在 get 里穿 coordinator/history 读取，同批钉住（同一潜伏 pattern）。
- 回归：AX 断言强度行在面板可见；solve 点击后主线程有界时间响应（XCUITest 点击
  → 1s 内 readout/进度态出现）；GUI-M6C-03/05/06/08 四行解锁复验。

---

## 三、D-2 绿染侦查（假说排序 + 复现配方）

### 3.1 事实面（MANIFEST local-only + 本次读码）

| 事实 | 读码结论 |
|---|---|
| 缩略图正常 | **缩略图从不走 CIRAW 解码**——Tier A = 内嵌 JPEG 预览（`SessionThumbnailProvider.swift:408-423` `CGImageSourceCreateThumbnailAtIndex`）；Library 面 hasEdits≠1 同走内嵌（`LibraryThumbnailBridge.swift:10-14`）。**「缩略图正常」完全不解罪解码腿**（分诊时最易误读的一条） |
| pano_slice TIFF 正常 | TIFF 族走 M4-1 原生腿 `RasterDecoder.decodeTIFF`（`RAWDecoder.swift:148-150`），与 RAW 腿完全异路 |
| ARW 饱和绿 / DNG 全黄，两图异色 | 指向 **per-file 解码元数据**（camera matrix / WB / profile / RAW 9 CoreML）而非全局通道序（后者应对所有 RAW 同色） |
| 跨 app 重启持续 | 解码是确定性的——每次重解码同毒即持续，**无需持久态假设**（进程内 memo `contentDedupeID` 不跨进程，排除纯缓存说） |
| 直方图证实像素毒化 | 毒化在管线上游平面，非显示端 colorspace 面 |

### 3.2 已排除/降权的通道

- **sidecar decodeParams 毒化 WB**：RAWDecoder 对 `neutralChromaticity` **只读不写**
  （`RAWDecoder.swift:452-457`）；可写 override 仅 NR/sharpness/boost/decoderVersion，
  全部 0...1 钳制——无通道级毒化能力。H-B 因此降权（但移走 `.lra` 一步仍可判）。
- DRT 载体毒化（H-B 变体）：thumbnail 恒 legacy 尾（DRT 先例）可解释缩略图逃逸，
  但 DRT 垃圾 uniforms 的表型是影调/色域塌缩，不是全画面单色饱和毒化——排后。

### 3.3 假说排序

- **H-A（首推）：CIRAW 解码输出本身对这两个文件有毒**——四事实全解、零持久态
  假设。子变体：
  - **H-Aa**：RAW 9 CoreML 解码器（automatic opt-in，`RAWDecoder.swift:259-273`
    — OS 27 + 文件报告支持即走 v9）对 7RM5 ARW / 该 DNG 特异中毒（beta 质量
    面，STACK 置信 Med 在案）；绿/黄异色 = per-file demosaic/WB 处理差异。
  - **H-Ab**：CIRAW 输出色彩空间与管线 working space（linear Rec2020，
    `CIContextPool.swift:144-145`）per-file 错配（异常内嵌 profile / 缺 matrix
    文件 → CI 转换出通道级偏差；两图异色吻合 profile 差异方向）。
- **H-B（次推）：sidecar 持久态毒化**（drtRecord/其他载体）——靠复现配方第 2 步
  一步判；若第 2 步消除绿染即翻正。
- **H-C（弱）：输入平面 memo / EDR 视口态**——进程内态不跨重启，单独不成立；
  仅可能与 H-A 复合（首渲即毒被 memo 冻结，跨重启 = 重新再毒，非缓存说）。

### 3.4 复现配方（修复批直接用；探针 /tmp 即弃）

1. **基线**：重启 app 开两图 → 确认绿/黄持续（证据已有 `m6c-green-render-*.png`）。
2. **sidecar 切断**：两图 `.lra` 移走 → 重启开图 → 绿染消失 = H-B 翻正；仍在 = H-A。
3. **新项目导入**：/tmp 新项目导入两文件副本 → 开编辑器 → 项目级状态判定。
4. **解码探针**（`swiftc` /tmp 直编，无 GUI；复用 M2-7 进程内真链探针方法论）：
   两文件各跑 `RAWDecoder.decode`（`.automatic` vs `.forceV8`）小尺寸渲，dump
   每通道均值/直方图——v9 毒而 v8 净 = H-Aa 坐实（候选修法：automatic 收紧 /
   受影响机身 v8 白名单 / 解码后通道健全性门）；两版皆毒 = CIRAW 层。
5. **CIRAW options 二分**（v8 仍毒时）：NR off / vendor lens-correction off 逐项
   → opcode 路径定位。
6. **管线侧双臂**（解码净而编辑器绿时）：同文档 harness 探针 `terminalTail`
   强制 legacy vs `.drt` 平面统计比对 → H-B 残余/尾段。
7. **交叉证人**：`/Applications/AlcedoStudio.app` 开同两文件——Alcedo 正常 =
   CIRAW 特异；Alcedo 同异常 = 文件本身特异（弱化我方缺陷定性）。

---

## 四、分批编排建议（推荐，OQ-VM-1 裁）

**推荐 = 两波、同一 research 治理（本文档为共同输入）：**

- **波 1「缺陷修复批」**（1-2 plan）：
  1. **D-1**（首项，M——解锁 GUI-M6C 四行）；
  2. **D-2**（第二项，M——侦查探针 bisect 先行（§3.4 配方 1-4 步可入 plan 侦查
     任务），修法随 bisect 结论裁；解锁色彩目测走查）；
  3. **D-3**（S-M，插桩复现优先）；
  4. **D-4 + D-5 顺带**（各 S：D-4 arm 时快照计数；D-5 补 `%lf` 变体）。
  验收门 = 定向 bundle + 全套 `--all`（3848 基线 + ΔN，8G 门 + orchestrator 批准）。
- **波 2「清算批」**（1 plan）：
  1. **V17**（zh-audit specifier 深检 + Text 插值族 + `String(` 跨行族——D-5 修复
     同批落门防复发，活体样本现成）；
  2. **Manual-Only 19 行 GUI 走查批**（前置 = D-2 修复 + 供件；omp computer-use
     或人工）；
  3. **PATCH-LIVEPLANE**（V2 #9，S 级顺带候选，OQ-VM-3 裁）；
  4. **RELEASE-DIRECT-INJECT**（V2 #2，S 级顺带候选，视 Release 基准需求）；
  5. **EXPORT-PRESET-01**（S-M，清算波尾候选，OQ-VM-4 裁）。

**不合一波的理由**：修复批验收门（全套 `--all`）不应被清算小件拖批次；两波各自
闭环、各自翻账更干净。**不三波的理由**：GUI 走查批强依赖波 1 的 D-1/D-2 落地，
独立成波只会插入空转等待。

**V2 大件（#1/#3/#4/#5/#6/#7/#8）全部留后**：全部是需求/触发条件驱动
（V2-PROPOSAL §七触发条款字面），无一波与缺陷修复抢窗口；SAM-COREML 本就
「用户裁立项另开独立 phase」。

---

## 五、OQ-VM 清单（C 档第 1 停，待用户裁决）

### OQ-VM-1：波次切分

- **A（推荐）**：两波——波 1 缺陷修复（D-1→D-2→D-3→D-4/D-5）+ 波 2 清算
  （V17 + Manual-Only GUI 批 + S 件顺带）；两波同 research 治理。
- B：一波合并（缺陷 + 清算 + S 件同 plan 序列）——批次大、验收门混杂。
- C：三波（缺陷 / 清算 / GUI 分立）——GUI 批强依赖 D-2，独立波空转。

### OQ-VM-2：D-2 修法路线

- **A（推荐）**：修复批内先跑 §3.4 侦查 bisect（配方 2-4 步），修法随结论裁
  （H-Aa 坐实 → automatic 收紧/白名单/健全性门三选再裁）；假说未收敛前不预设修法。
- B：直接押 H-Aa，按「RAW 9 automatic 收紧 + forceV8 面板引导」修复——若真因是
  H-Ab/H-B 则返工。
- C：D-2 暂缓（本批只修 D-1/D-3..D-5）——绿染不修则 Manual-Only 走查与一切色彩
  目测持续不可信，不建议。

### OQ-VM-3：V2 S 件顺带范围

- **A（推荐）**：PATCH-LIVEPLANE（V2 #9）+ RELEASE-DIRECT-INJECT（V2 #2）两个
  S 件列为清算波顺带候选，入批与否随波 2 容量定。
- B：全留后（两 S 件不进本批）——最小批次。
- C：再加 SESSION-LEGACY-READONLY（V2 #4，M 级）——legacy 可见面趋零，不建议。

### OQ-VM-4：EXPORT-PRESET-01 是否入本批

- **A（推荐）**：入清算波尾（S-M、UI 加层面、键族基座在位、独立性好；
  Alcedo 对标 charter 下是真实 UI 面）。
- B：留 M7+ 导出打磨批（REQUIREMENTS 原注「V2 站裁量」保守面）。

### OQ-VM-5：GUI 走查批（Manual-Only 19 行 + M6-4 M-1..M-4）时机

- **A（推荐）**：波 1 的 D-1 + D-2 验收闭环后即排（走查批与波 2 清算批并行度
  高——走查不占源码面）；供件（自然样张/真无人像照片/layer B 资产/HDR 屏）
  由用户/orchestrator 备料。
- B：与波 2 同批串行——批次拉长。
- C：再挂后——色彩目测类判断持续积压。

---

## 六、边界与纪律

- 本文为 research 定稿；**未进 plan、未改代码**（D-2 复现配方仅为文档；
  侦查探针 /tmp 即弃）。
- N-1 已清偿的勘误以本表 §B 为注记正本；历史行（M6-5 VALIDATION 等）不改写。
- 全套 `--all` 轮在修复批验收时须 orchestrator 批准 + 8G 门监视（AGENTS 资源
  监控节）；基线 = 3848/24/0。
- 修复批触碰面红线：AGENTS.md 各「架构增量」节封存面清单（DrtRecord/sidecar
  schema/V50Order/六格式矩阵等）零 diff 纪律照旧；zh 新键尾块纯插入。

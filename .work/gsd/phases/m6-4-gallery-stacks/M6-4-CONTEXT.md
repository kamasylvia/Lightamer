# M6-4 CONTEXT — 图库 stacks + auto-stack + AI 分割蒙版原生 spike（OQ 裁决落签批，2026-10-14 夜间）

> Phase = M6-4（ROADMAP §Milestone 6 M6-4 行 + REQUIREMENTS M6INT-02/03 +
> charter 六裁决点④⑤：④AI 蒙版先零成本 spike Vision 达标即收 ⑤stacks +
> auto-stack 优先，用户回批 2026-10-11）。本文 = OQ 裁决正本；读解正本 =
> 同目录 `RESEARCH.md`（面 A LightCraft stacks 语义实测 + 面 B Vision SDK
> compile-probe + LightCraft SAM 3 盘点 + OQ-M6-4-1..7 原文 + R1-R6）。
>
> **授权注记：本裁决为夜间全自动授权批落签（先例 D-07-3-T5-1；M6-3 CONTEXT
> 同款），七项全按 RESEARCH 推荐采纳；晨审/用户可随时推翻，推翻项回注 plan
> 修复批重走（M6-3 先例形）。**
>
> 状态：research 定稿（`RESEARCH.md`，commit f498e5f5）→ OQ 裁决落签（本文）
> → plan round（`M6-4-01-PLAN.md` + `M6-4-02-PLAN.md` 同批起草，两面独立、
> 执行串行 01→02）。

## Phase Goal（ROADMAP M6-4 行锚定）

- **面 A（stacks + auto-stack，plan 01）**：`.lalb` 手动堆叠——封面/展开/收起
  + 网格堆叠徽章 UI + auto-stack（拍摄时间间隔阈值聚类，LightCraft 全套语义）
  + `LibrarySchema` v4→v5 additive 迁移。验收形态 = stack 迁移 + round-trip ✓
  + auto-stack 聚类 golden ✓。
- **面 B（AI 分割蒙版原生 spike，plan 02）**：对照 Phase 7 AI-01 已交付面盘点
  LightCraft SAM 3 能力集缺口；**原生零模型成本路达标即收**——点击精修（07-3
  已交付）+ hi-res patch 组装 + Edge 羽化参数化三件 native 组装；Describe 文本
  选择 = 原生不可达（Vision 零文本分割 API，B2 实测）→ 挂账 V2。验收形态 =
  spike 结论落档（达标判据 plan 期定；达标即收不达标挂账）✓。

## 裁决（D-M6-4-N，全按 RESEARCH 推荐；生效值 = 硬约束）

### D-M6-4-1 schema v5 落点 = 两新表 join 形态（OQ-M6-4-1）

`stacks` + `stack_content`（WITHOUT ROWID，PK (stack_id, image_id)）+ UNIQUE
索引 `idx_stack_content_image`（一图一栈 = DB 级不变量 + stack_of 反查）。
理由：album_content/version_ref 先例同形；`images` 冻结列清单（29 列 verbatim
断言面）零触碰；CASCADE 自动跟随图删；images 侧列方案省一次 join 但侵入冻结面
且 ref_count 型计数无必要。封面 = position 0 成员（单真相，不设 cover 列）。

### D-M6-4-2 auto-stack = LightCraft 全套语义（OQ-M6-4-2）

gap 默认 60s 用户可调 + preview 只报组数不动库 + 拍摄时间升序相邻 ≤ gap 归簇
+ runs ≥2 才成栈 + 跳过已堆叠/无 capture 时间 + 结果落普通栈（collapsed）+
不存 auto 出处（撤销面 = 手动解栈；我方图库域无 undo 基建，与 LightCraft
catalog-op undo 的偏离在 plan DECISIONS 登记）。bracket/burst 无专门检测——
纯时间阈值与 Lightroom 同型。

### D-M6-4-3 分页 × 堆叠 = 收起态 SQL 谓词 + 展开态页内 fixup（OQ-M6-4-3）

收起态 = `searchPage`/`searchNullTail` 纯谓词排除非封面成员
（`NOT IN (SELECT image_id FROM stack_content WHERE position > 0)` 形）——
keyset seek 零改动、无 R1 风险；展开态 = App 侧页内 adjacency fixup
（成员向前聚拢 + 有界补拉 + 已显示集合去重，**forward-only**——已在早前页
显示的成员不回拉，与 LightCraft gather-to-first-member 的有界偏离在 plan
DECISIONS 登记）。替代方案（SQL 端 ORDER BY 栈键重排）伤 keyset seek，否。
fixup 细则 = plan 01 T4 定案（OQ 预留的 plan 期定案点）。

### D-M6-4-4 merge 产物自动成栈 = 顺带做，落点 = 导入缝（OQ-M6-4-4）

采纳「顺带做」。**plan 期落点核实（2026-10-14 亲核）**：merge 产物落 Session
域（`landStackProduct` 写 session root；完成钩子 `refreshGridAfterMerge` →
`sessionIndexController.reconcile` 刷 Session 浏览格，**零 `.lalb` 接触**）——
merge 完成点无栈可成（栈是 `.lalb` 驻留面）。产物入项目图库的唯一路径 =
**用户导入**，故自动成栈的生效点 = **ImportService 导入批完成缝**：导入图像
的 `.lra` 带 merge 族 provenance（`hdr-merge` / `hdr-merge-mertens` /
`pano-merge`）且 `sources[].relPath` 全部解析到库内行（同批或既存）→
`LibraryStore.stackWith`（产物 = 封面 + collapsed）一次性成栈；源不全 →
typed skip 无副作用。匹配细则与 skip 计数 = plan 01 T6。

### D-M6-4-5 原生能力组装范围 = patch 组装入 spike 判据 + 羽化参数化顺带（OQ-M6-4-5）

hi-res patch 组装（layer B `regionOfInterest` + quality 三档延迟重析 + patch
合成）入 M6-4 spike 达标判据（判据细则 plan 02 定案——ROADMAP 授权的 plan
期定案点）；Edge 羽化 ±100 语义参数化顺带（`MaskCombiner.blur` sigma 面
已交付，纯应用层映射，**零新 kernel**）。均为应用层小件，理由 = 不启动 SAM
大件即可把「点击精修之外」的两件 LightCraft 能力差距关掉。

### D-M6-4-6 scribble 种子 = 本 phase 不激活（OQ-M6-4-6）

`AISubjectSeed.scribble` case 与 SDK `init(seedScribbleBuffer:)` 缝保持现状
（v1 构造即 typed 拒绝的负测维持）；本 phase 零激活工作。理由 = UI 输入形态
（笔迹采样/缓冲/手势）工程量不小，单列后续小件；激活缝已在 07-1 登记，保持
即零成本。

### D-M6-4-7 Describe 缺口 = 挂账 V2，M6-4 以「原生不可达」收口（OQ-M6-4-7）

Vision macOS 27 全 API 面实测零文本提示分割 API（B2 swiftinterface 全文
grep）；M2-10 CLIP 为图像级 embedding 无像素掩码——Describe 文本选择原生
无路。SAM CoreML 大件**不在本 phase 启动**（3.4GB Meta SAM License 永不
入仓/不随发行 + ViT/DETR/CLIP 全族自转换 + 分发成本三重）；ModelAssetStore
安装链 + AIWorkerProtocol 第四腿已备，挂账 V2，若用户裁定 SAM 立项 = 另开
独立 phase（charter「大件另裁」）。

## 裁决附带澄清（执行面判定，非新 OQ）

- **worker 腿复用判定（plan 02 落点）**：`GeneratePersonInstanceMaskRequest`
  = Vision 内置 struct API（macOS 15+），**主进程 Vision 直调**（既有
  `personSegmentationMask`/layer A 同形，`AIMaskService` additive）；M4-3
  worker 四腿是 ONNX 第三方模型的隔离面（MiDaS/enhance/semantic），Vision
  内置请求不入 worker——07-1/07-2 先例同构，RESEARCH 面 B 推荐的原生
  零成本路即此。
- **「SAM 类新 API 若 macOS 27 有」问句收口**：无（B2 实测——`VNStatefulRequest`
  是 macOS 11 视频跟踪基类与分割无关；macOS 27 新分割面 = layer B，07-1
  已交付）。plan 02 不含任何 VNStatefulRequest 工作。
- **MCP 对账（R3）收口**：M6-4 零 MCP 面——PhotoProjection 维持 flat keyset
  序（arrange 是网格 UI 域关注点），MCP 快照族零 diff = plan 01 红线机检项。
- **R4 验收形态**：layer B 资产测试宿主 entitlement 阻断（07-3 先例）——
  plan 02 涉 layer B 真实推理的验收走 GUI 真机轮（证据 = `.work/gui-acceptance/
  m6-4/` MANIFEST）；单测面走纯函数（请求组装/平面组装）不触 Vision 执行。

## Plans（两面独立，执行串行 01→02）

| plan | 面 | 内容 | 测试落域 |
|---|---|---|---|
| `M6-4-01-PLAN.md` | A | schema v5 迁移 + stacks CRUD + auto-stack 聚类 + 分页×堆叠 + App UI + 导入缝 merge 成栈 | Library（Core）+ App |
| `M6-4-02-PLAN.md` | B | hi-res patch 组装 + 羽化参数化 + 人物实例蒙版入口 + spike 判据与 GUI 轮 + 结论落档 | Layers（Core）+ App |

## 裁决记录（夜间全自动授权批，2026-10-14）

**OQ-M6-4-1..7 全部按 RESEARCH 推荐采纳（全 A）**：①两新表 join 形态 +
UNIQUE 一图一栈 ②LightCraft auto-stack 全套语义（60s 缺省可调 + preview +
runs ≥2 + 跳过已堆叠，不存出处）③收起态 SQL 谓词 + 展开态页内 fixup
（forward-only 有界偏离登记）④merge→stack 顺带做、落点 = 导入缝（Session
域完成点零 `.lalb` 接触已亲核）⑤patch 组装入 spike 判据 + 羽化参数化顺带
⑥scribble 不激活缝保持 ⑦Describe 挂账 V2、原生不可达收口。

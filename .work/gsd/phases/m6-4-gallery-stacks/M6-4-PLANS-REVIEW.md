# M6-4-PLANS-REVIEW — M6-4 两 plan（01 stacks + 02 AI 分割蒙版）独立评审报告（2026-10-13）

> 评审 = zcode 独立 subagent（plan 评审独立路，替代 omp 路，零共享上下文）。审查
> 对象 = `M6-4-01-PLAN.md` + `M6-4-02-PLAN.md` + `M6-4-CONTEXT.md`（裁决记录
> 2026-10-14）+ `RESEARCH.md`（commit `f498e5f5` 面 A/B）；工作区 HEAD =
> `05948db9`（两 plan 入库 commit，源码相对 plan 锚定零漂移——全部 file:line 为
> 该 HEAD 亲核）。对照先例 = `phases/m6-3-ultrahdr/M6-3-01-PLAN-REVIEW.md`
> （findings 形态）。SDK 事实经 macOS 27.0.sdk
> `Vision.swiftinterface/arm64e-apple-macos.swiftinterface` 亲查。

## 结论

**两 plan 均须修后放行 / 合计 2 error + 7 minor + 9 建议（每 plan 各 1 error）**

- **01 的 E1**：KD-6 导入缝源匹配候选集漏 `<folderName>/` 段——主匹配规则在
  规范导入流**结构性恒 miss**（ImportService 无条件 folderName 前缀亲证），
  照原文执行 T5 要么假绿（手拼 fixture）要么红灯（真流程 fixture）。
- **02 的 E2**：人物实例蒙版提取腿未钉——swiftinterface 亲证该请求的 Result
  与 layer A **同为 `InstanceMaskObservation`**，其 `generateScaledMask` 在
  本 OS 双损坏（07-1 在案）直达此 API 族；plan 对提取 API 零字，爆炸点推迟
  到 GUI 轮（单测 entitlement 不可达）。
- **七条 minor** 中 M1（收起态谓词丢「封面被滤首可见成员顶替」语义，RESEARCH
  A1 明文在案而 plan/DECISIONS 零字）与 M5（KD-3 缝勘察漏既有
  `bake(featherRadius:)` GPU 羽化 plumbing，RESEARCH B4 自证「已覆盖」）为
  设计依据级缺口，须同批改写；其余为计数载体、断言可实现性、风险预判方向、
  内存姿态、键族归属。
- **七项 OQ 生效值（D-M6-4-1..7 全 A）无一需要重开**：schema v5 两新表
  join 形、LightCraft auto-stack 全套语义、分页谓词+fixup、导入缝落点、
  patch 入判据、scribble 不激活、Describe 挂账——全部与源码和 RESEARCH
  一致，主体交付面成立。

---

## Plan 01（stacks + auto-stack）findings

### E1（error，维度 3 导入缝）：KD-6 源匹配候选集漏 `<folderName>/` 段——主匹配规则在规范导入流结构性恒 miss

**源码事实**：

- `ImportService.swift:220-228`（makePlan）：`mediaRelativePath =
  folderName + "/" + relative`——**folderName 前缀无条件**（sourceFolder
  lastPathComponent）。
- `ImportService.swift:579-583`（writeRow）：`imagePath = "Media/" +
  item.mediaRelativePath` = `Media/<folderName>/<relative>`。
- sidecar 侧 `sources[].relPath` = **相对 session root**（`ProvenanceReplay
  .swift:13-15/:81` 明文；`StackMergeService.swift:2195-2198` 构造点亲证——
  session root 前缀剥离，root 外源回落 lastPathComponent）。

**推演**：导入 session 根目录（规范流）→ 源图行 `image_path =
Media/<rootName>/Burst/IMG_001.CR2`；sidecar `relPath = Burst/IMG_001.CR2`。
plan KD-6 候选 `["Media/" + relPath, relPath]` = `Media/Burst/IMG_001.CR2` /
`Burst/IMG_001.CR2`——**两候选皆 miss**。仅 `importFile` adopt 面（无
folderName 段，`ImportService.swift:630-655`）可命中——非导入批路径。结果 =
规范流下全部组落在「末段 stem 唯一命中」兜底；stem 撞名（同名不同目录重导）
即整组 skip。plan 风险节「copy/move 模式 image_path = `Media/` + relPath」
同错（漏 folderName 段）。

**后果**：T5 fixture 若走真 ImportService 流建库 → 断言红；若手拼
`Media/+relPath` 形 image_path → 假绿（测试与生产路径分叉，恰是 checker
关注点 4 要抓的形态）。

**修法**：KD-6 匹配细则改写——①候选改**后缀匹配**（`image_path` 以
`"/" + relPath` 结尾，relPath 结构段随导入树保真，覆盖任意 folderName 前缀
与 root 外源回落名）；或②批内候选三式（`Media/<本批 folderName>/ + relPath`
——同批导入的源与产物共享前缀）+ 既有两式 + stem 兜底。风险节 image_path
公式同步勘误；T5 fixture 指定走真导入流。

### M1（minor，维度 2 查询/分页）：collapsed 谓词丢「封面被滤时首可见成员顶替」语义——RESEARCH A1 明文在案，plan/DECISIONS 零字静默

**事实**：RESEARCH A1（LightCraft arrange_stacks 语义，转写正本）明文
「collapsed 栈只显示顶图，**顶图被当前过滤隐藏时由首个可见成员顶替**」。
plan KD-5 谓词 `NOT IN (SELECT image_id FROM stack_content WHERE position
> 0)` 把该语义整体丢掉：封面被 filter/语义腿滤掉时（如 filter = rating ≥3
而封面无星、成员有星；或语义搜索命中成员不命中封面），**整栈从网格消失**
（成员被谓词排除、封面被 filter 排除），含成员在内的全部匹配图不可达。
语义全走查腿同病（KD-7 明写「收起态谓词在语义全走查腿同样生效」→ 语义命中
成员被谓词吃掉 = 搜索漏召回）。CONTEXT D-M6-4-3 选了纯谓词（keyset 零扰动
的代价），裁决成立不重开——但该用户可见行为损失在 plan 全文（KD/AC/风险/
T8 偏离申报清单）**零登记**，属 M6-3 M3 同款「静默」形态。

**附**：overviewCount/groupCounts（`LibraryQueries.swift:274/:290`）不加
stackMode → 收起态下 Overview 总数与分组计数按全量行统计、网格按封面行
显示，两口径分裂（Lightroom 收起态计数只数封面）——同样零字。

**修法**：不重开裁决；①T8 DECISIONS 偏离清单增列「过滤隐藏封面时整栈隐藏
（无顶替）」+ 语义腿漏召回面，标 V2 候选（App 侧语义腿顶替可行——hit 集是
有限 id 表；keyset 腿顶替需 SQL 改动 = 裁决已排除的形态）；②overviewCount
口径差一句申报（或顺带给 stackMode 参数，可选）。AC/风险节各一行。

### M2（minor，维度 6 SC 机检性）：T4②「SQL 组装零 diff 断言」无可落缝

**事实**：runPage 的 SQL 为函数内私有装配（`LibraryQueries.swift:223-269`
，`handle.prepare(sql)` 内联，无 SQL 捕获/注入缝），LIB 测试拿不到装配后
SQL 字节。checker 关注点 2 自己要的是「调用点清单 grep + 行级恒等测试」，
T4② 却写「字节恒等的行级代理 + SQL 组装零 diff 断言」——后半句按字面
不可实现，执行方要么虚报要么临场造缝（触 runPage 签名 = 违反「唯一合法
diff 位」自身红线）。

**修法**：T4②/AC4 改写为双证据——缺省参调用点 grep 清单（searchPage/
searchNullTail 全仓调用点零改，MCP PhotoProjection/filmstrip/semanticHits
点名）+ 行级恒等测试；删「SQL 组装零 diff 断言」字样。

### M3（minor，维度 1 schema/风险预判方向反了）：既有测试**必然**浮出两处，风险节「预期不浮出」失准 + AC7 口径自相矛盾

**事实**（亲读 LibrarySchemaTests）：

- `testPackageTablesCreated`（:149）：extras **allowlist 断言**（:163-169）
  ——`tables.subtracting([13 表])` 必须全是 FTS shadow 表；`stacks`/
  `stack_content` 入库即**硬红**。
- `testFreshCreateStampsUserVersionFourAndSeedsProjectMeta`（:181）：钉
  `user_version == 4`（:187）——v5 出生面必须定向改 5。

plan 风险节预判「预期不浮出——数组遍历形断言为主」方向失实（数组遍历形
确实无害，但 allowlist/user_version 两形必浮）；风险节的处置路径（additive
定向更新 + DECISIONS 申报）本身已授权，矛盾在 AC7「既有 Library/Import
测试族**原样绿**」——定向更新后的测试非「原样」。

**修法**：风险节改为指名两法（:149 extras allowlist 增 `stacks`/
`stack_content` 两名 + :181/:187 user_version 4→5）+ AC7 措辞改「既有
Library/Import 测试族除指名定向更新点外原样绿」。

### M4（minor，维度 3）：KD-6 skip 计数无载体——T5③ 要求断言的计数器不存在

**事实**：KD-6「任一源解析失败 → 整组 typed skip（**计数上浮**，零半栈）」
+ T5③「skip 计数」断言；但 ImportOutcome additive 只申报
`mergeStacksCreated: Int = 0` 一个字段，skip 无处落。既有 ImportOutcome
（`ImportService.swift:132-147`）无 merge 域计数。

**修法**：ImportOutcome additive 补 `mergeStacksSkipped: Int = 0`（同款
显式默认值零漂移），T5③ 断言落到该字段；或 KD-6 改口「skip 仅 DECISIONS
记档不计数」并删 T5③ 的计数断言——二选一，不能两头。

### Plan 01 建议（不阻断，随修订批顺带）

- **S1**：link 模式 product 侧无 `.lra`（`executeLink` 不迁移 sidecar，
  `ImportService.swift:436-446`——⑤明文 `.lra` 留原点）→ link 导入的
  merge 产物永不自动成栈。安全侧行为，但 plan 零字——KD-6/风险节补一句
  登记（「自动成栈限 move/copy 导入」）。
- **S2**：KD-7 fixup 正确性论证中「后页补拉到前页位置的成员，其 keyset
  位置 ≤ 当前 anchor，后页 keyset seek 永不再取」不成立——前拉成员的
  keyset 位可**后**于当前 anchor（封面在前页、成员 keyset 位在后页，fixup
  在前页把成员拉前）；无重复实由 displayed-set 守卫保证（后页行 append
  时命中跳过），anchor 推进取 raw page last 不受扰。论证改写，三件套
  测试面不变（union golden 本就跨页覆盖此形态——checker 关注点 3 的
  「成员与封面分处两页 fixture」保留）。
- **S3**：`LibraryGridStackTests` 归 APP，而同模型先例
  `LibraryGridModelTests` = LIB（BUNDLE-MAP :356；LIB target 依赖
  Lightamer App 模块——`Project.swift:618-622` `.target(name: "Lightamer")`
  亲证，两 bundle 对 App 侧 Library 模型均可达）。若非有意（如需 APP
  host 面），建议归 LIB 聚拢 Library 模型族；保持 APP 则 DECISIONS 一行
  理由（同模型测试族跨两 bundle 的分账依据）。
- **S4**：格式键命名——既有格式键惯例是键内带「 %lld」后缀（
  `focus_stack_dialog_title %lld` / `stack_denoise_dialog_title %lld`
  在册实证）；`library_stack_auto_preview_fmt` / `library_stack_members_hint`
  建议对齐（`library_stack_auto_preview %lld` 形），scanner/zh-audit
  口径一致。
- **S5**：KD-7「语义覆盖面……KD-3 既有纪律的延伸」悬空引用——本 plan
  KD-3 = 无 undo 偏离登记，语义/非语义两腿互斥纪律正本 = M2-10-02/M2-3
  的 semanticHits 裁决（LibraryGridModel.swift:44-49 头注）。改实名引用。
- **S6**：`splitStack(stackID:atImageID:)` 在 atImageID = 封面（前缀空）
  的边界未定义——「后缀 ==1 → 出栈」与「任一半 <2 → 该半解散」两规则在
  空前缀时交叠（结果 = 原栈原地保留 or 重建同成员新栈，观测等价但 id 变
  化面不同）。T2⑫ 补一断言钉死（推荐：空前缀 = no-op 保原栈 id）。

---

## Plan 02（AI 分割蒙版 spike）findings

### E2（error，维度 4 蒙版面）：人物实例提取腿未钉——Result 与 layer A 同为 `InstanceMaskObservation`，已知双损坏 API 直达此族，plan 零字

**源码/SDK 事实**：

- macOS 27.0.sdk Vision swiftinterface :1934：
  `public struct GeneratePersonInstanceMaskRequest : Vision::ImageProcessingRequest`
  ，**`public typealias Result = Vision::InstanceMaskObservation?`**——
  与 layer A `GenerateForegroundInstanceMaskRequest` 同一观察类型
  （`AIMaskService.swift:599-604` AIInstanceCatalog 持有的即此类型）。
- 该观察类型的 per-instance 像素提取只有两路：`generateScaledMask(for:
  scaledToImageFrom:)` 与 `allInstancesMask` 标签图合成。前者在
  macOS 27.0b **双损坏已在案**（07-1 D-07-1-T2-4 探针实证：subset 语义错
  + 几何 +3/16 偏移；`AIMaskService.swift:176-183` 头注亲录），layer A
  已全线绕行标签合成。
- plan 02 KD-2 只写「返回 = per-instance `AIMaskPlane` 数组（实例序 =
  Vision 观察序）」——**提取 API 零字、07-1 破损记录零引用**。T3④ 只测
  「平面格式面」，单测面按 R4 零 Vision 执行依赖 → 若执行方按「per-
  instance plane」直觉走 `generateScaledMask`，破损在 GUI 轮（T5）才炸，
  且 READ research B2 的 compile-probe 只验编译不验提取（探测面盲区）。

**修法**：KD-2 钉死提取腿 = `allInstancesMask` 标签合成（07-1 D-07-1-T2-4
绕行同款——person 实例在标签图中即标签，`labelCompositeMask`（
`AIMaskService.swift:211-243`）可复用/参数化）+ `generateScaledMask` 显式
禁用注记（Apple 修复后升级缝同 07-1 在案形）；T3 增一断言（提取走标签图
路径的编译面/结构面证据）。若探针实测 person 观察的标签图语义与 layer A
有出入（实例编号域不同等），DECISIONS 申报——但默认腿必须是标签合成。

### M5（minor，维度 4 KD-3 缝勘察不完整）：既有 `bake(featherRadius:)` GPU 羽化 plumbing 全程缺席——缝选择论证对缝景观失实

**源码事实**：

- `RasterMaskStore.swift:88-99`：`bake(featherRadius: Float = 0)`——
  **07-1 T4 已交付的 raster 腿羽化**：量化前单通道高斯预 Pass，直传
  `MaskCombiner.blur`（Deriche IIR GPU），门 `> 0.1`，0 = 字节恒等
  （头注明文「Plan 07-1 T4 additive, default 0 = the EXACT pre-07-1
  behavior」）。
- `AIMaskEditing.swift:133/:168`：`commitRasterMask(featherRadius: Float
  = 0)` 已穿线至 bake——**「bake 时域、会话参数、不触 sidecar」的羽化缝
  早已在位**，缺的只是 UI 滑杆 + percent→sigma 映射 + 负（收缩）语义。
- RESEARCH B4 自己的判定：「Edge 羽化 | `MaskCombiner.blur` 羽化在册
  （07-1 D-07-1-T4-1）| **已覆盖**（±100 语义参数化为小件）」。

**plan 失实处**：KD-3 缝裁决只对照 `MaskCombiner.postProcess/effectivePlane`
两缝并以「raster-only spec 不达 postProcess」（:623-635，亲证属实）立论，
对 `commitRasterMask/bake` 的既有 featherRadius 链**零字**——暗示 raster
腿无既有羽化缝，与 RESEARCH B4 及源码两面相悖。照现文执行：新建 CPU
`applyFeather` 与既有 GPU featherRadius 并存（两套羽化原语；AI 路径若
有调用点传了 featherRadius 即双羽化——现四调用点均缺省 0，暂无实炸路径），
DECISIONS 将入档「羽化缝 = 新建 CPU 面（无既有 raster 羽化）」的假前提。

**修法**（二选一，KD-3 改写 + DECISIONS 申报）：①**正腿复用**既有
featherRadius（percent→sigma 映射 + MaskToolbar 滑杆 + 会话值穿
commitRasterMask 即可；仅负腿需要新 CPU `1−blur(1−x)` 路径——正负分腿
各一行申报）；②维持新建 CPU `applyFeather` 为 AI 路径唯一羽化（负腿
同原语、正负对称的理由成立）——但须同批钉死「AI 路径恒传 bake
featherRadius = 0」防双羽化 + 申报与既有 GPU 原语的重复债与归宿。
两案 `.metal` 零 diff 均守住。

### M6（minor，维度 4）：patch「会话活平面拼回」的平面驻留面未定义——字段缺失 + 内存姿态零字

**事实**：`SegmentSession`（`LayerEditingState.swift:682-724` 亲读）持有
seed/refine/rebakeFileName/isGenerating——**无生成产物平面字段**；patch
重析后「会话活平面拼回 → 重烘」要求基础 Float 平面驻留会话。files_modified
对 LayerEditingState 只列「羽化值 + patch 状态面（idle/refining/done 计数）」
——活平面字段不在清单。accurate = 全分辨率直出（RESEARCH B1），100MP
float32 单通道 ≈ 400MB 级**会话期驻留**——与 AGENTS 资源监控口径
（GUI app >3G 触发线）直接相关，不能零字。

**修法**：KD-1 App 调度段补平面持有策略——字段落 SegmentSession（
files_modified 同步）、持有窗口（首次 bake 后是否释放/仅保留至 patch
完成/100MP 门的降档策略）+ 内存姿态入风险节；或改语义（patch 重析基于
重新生成基础平面，不驻留）——二选一写死。

### M7（minor，维度 7 键族命名）：`mask_tool_person_instance` 键族错位

**事实**：`mask_tool_*` = `MaskTool` **画笔工具族**的 labelKey 派生键
（`LayerEditingState.swift:45` `mask_tool_\(rawValue)`；xcstrings 在册
6 键与 6 case 一一对应：brush/eraser/gradient/ellipse/path/followEdges）。
AI **生成入口族** = `ai_mask_*`（ai_mask_subject/ai_mask_subject_inverted/
ai_mask_depth 等在册）。新项按 KD-5 自述是生成入口（tap →
personInstanceMasks → checkbox overlay），不入 MaskTool 枚举（入了就会
被 toolbar ForEach 渲染成画笔 radio 工具——行为错位）。

**修法**：键改 `ai_mask_person_instance`（与兄弟项同族）；其余 4 键
（mask_feather_label/reset、mask_patch_refining、mask_person_none）无
家族冲突，维持。

### Plan 02 建议（不阻断，随修订批顺带）

- **S6'**：`segmentPatch` = `segmentSubject` 既有 ROI 形的薄包装——
  `segmentSubject` 已带 `regionOfInterest: AIMaskRect? = nil` 全链
  （`AIMaskService.swift:266/:288-290/:332-334`）。plan 宜明写「委托
  segmentSubject、零新 Vision 装配」，防执行方照「additive segmentPatch」
  另写第二条请求装配路径（与「零改 buildLayerBRequest/segmentSubject」
  自我约束打架）。
- **S7**：person 实例会话态宿主未列——arm 态/实例清单/选中态落哪个面
  （LayerEditingState additive？还是 MaskToolbarView @State 如 layer A
  `pendingInstances` 形，:51-54 先例）files_modified 未枚举；
  `SegmentEditingOverlayHost` 列入 read_first 5 但不在 files_modified
  ——若 person 流纯 toolbar/sheet 驱动则补一句「overlay host 零触」，
  否则补登记。
- **S8**：对账机制补一句——T7 建议显式「以 plan 01 **实际收口** TOTAL
  重算本 plan 预期带」（02 front-matter 的 3811..3817 是对 01 的预测；
  01 出带时 02 front-matter 数字连带失配，checker 7 的「出带 = 申报」
  兜底已在，补重算规则更干净）。

---

## 通过项（逐维度，附亲核证据）

### 1. 01 schema 面——v4→v5 迁移设计与现库结构全兼容（除 M3 的测试浮出预判）

- 迁移槽先例三代同形亲证：`migrate(from:to:)` 单 `BEGIN IMMEDIATE` +
  ROLLBACK + 全腿走查（`LibrarySchema.swift:762-783`）；v3→v4 槽 =
  `createSemanticTables` 幂等 `CREATE IF NOT EXISTS` 族（:790-795）——
  plan 的 `createStackTables` + `if from <= 4 && to >= 5` 槽与
  `createVersionRefTable`（:801-804）先例逐位同构。
- **快照轮换无漏**：hook 条件 = `stored < schemaVersion` 动态判定
  （`ProjectFileStore.swift:275-293`），generation 命名
  `.pre-migrate.<stored>-<to>.bak` + 同名 stale 清除重拍——v4 包在 v5
  binary 下首开自动入轮，无 hardcoded 腿清单可漏。
- UNIQUE 与既有数据共存：迁移时 `stacks/stack_content` 出生即空表，
  UNIQUE 索引零冲突面；`WITHOUT ROWID` + 二级 UNIQUE 索引 + 双 FK
  CASCADE（父键均为 rowid-alias PK）SQLite 形合法。
- CASCADE 解散事务边界：`removeImage`（`LibraryStore.swift:405-416`）
  单事务内 DELETE → FK cascade 掉 stack_content 行 → sweep <2 解散——
  与 album_content「store 同事务收尾」先例（removeAlbum :227-279 先减
  后删同形）一致。
- 冻结面：`reservedTableNames` 三名零改、`triggerNames` 零改、
  `indexNames` 一行追加（checker 关注点 1 可机检）；DDL 列序/命名
  （`idx_stack_content_image` = `idx_album_content_image` 孪生拼写）
  与冻结面文风一致。
- futureSchema 拒绝先例在册（`LibrarySchemaTests.swift:330`
  `.futureSchema(version: 5)`），T1⑤ 的 version:6 同形可测。

### 2. 01 查询/分页面——谓词插点与 fixup 可测性成立（缺口 = M1/M2/S2）

- 谓词插点 = `appendFilterLeg` 返回后、seek 腿前（FTS 腿同位，
  `LibraryQueries.swift:518-521` 形）——keyset seek 形状零改动成立；
  nullTail 腿（`image_path > ?` seek）与谓词同属 WHERE 自洽。
- `.flat` 缺省参 = 既有调用点零编译改（MCP PhotoProjection/filmstrip/
  semanticHits 全走查均无参调用）——零回归门成立（验证方式按 M2 修订）。
- fixup 不扰游标：anchor 系 `mainAnchor/tailAnchor` 独立字段
  （`LibraryGridModel.swift:72-74`），行数组重排不回写 anchor——设计自洽。
- fixup 纯函数 LIB 可测：**LIB target 依赖 Lightamer App 模块**
  （`Project.swift:618-622` 亲证；LibraryGridModelTests 等 6 个 App 侧
  文件已在 LIB 域）——plan 01 将 fixup 置 App 侧模型 + LIB 测试不矛盾
  （复核了 M6-3 先例评审无此先例点，本评审补证）。

### 3. 01 导入缝——机制骨架成立（缺口 = E1/M4/S1）

- merge kind 白名单三值拼写逐字核对 `ProvenanceReplay.swift:39-50` ✓
  （hdr-merge / hdr-merge-mertens / pano-merge；focus-stack/stack-average/
  stack-median/stack-sigma 排除面与 plan 一致）。
- product `.lra` 在位性：产物 sidecar 与产物同目录原子写
  （`StackMergeService.swift:2226-2233`）→ move/copy 导入随行
  （migrateSidecars :522-551）→ 探测可行。
- D-M6-4-4「Session 完成点零 `.lalb` 接触」亲证：`refreshGridAfterMerge`
  （`LightamerApp.swift:2002-2010`）= sessionReconciler.reconcileHandler +
  browserModel.reload，零 Library 面触碰——导入缝落点推导成立。
- ImportOutcome additive 默认值零漂移成立（memberwise init 缺省参 +
  `ImportOutcome()` 构造点 ：287 零 diff；Equatable 合成比较缺省 0 无扰）。

### 4. 02 蒙版面——worker 裁定、pin 纪律、0 短路、符号语义全部亲证成立（缺口 = E2/M5/M6）

- **worker 裁定复核成立**：M4-3 worker = 第三方 ONNX 模型隔离面
  （ModelAssetCatalog 三族 = CLIP embedding / MiDaS depth / enhance——
  `ModelAssetCatalog.swift:19-24` 亲证）；Vision 内置请求 07-1/07-2
  先例 = 进程内 `ImageRequestHandler` 直调（`AIMaskService.swift:156/:291/
  :379`）。`GeneratePersonInstanceMaskRequest` 主进程直调判定正确。
- **pin 面 = layer A apply() 形亲证**：swiftinterface :1934 起该请求为
  **struct** + `setComputeDevice`/`supportedComputeStageDevices` +
  `supportedRevisions = [revision1]`——plan 的「layer A 既有形（可 pin）」
  与「revision/quality 显式钉」全部成立；layer B pin 拒面在位
  （`AIMaskService.swift:441-455` macOS 27 一律 typed 拒）→ R2 纪律
  「segmentPatch 不 pin」由 buildLayerBRequest 既有字节自动继承 ✓。
- **LightCraft 符号语义亲核**：`lightcraft/docs/ai-masks.md:24`——
  「Edge (per selection, −100…100): below 0 a crisper border, above 0
  a feathered one (up to 2 %…)」——正 = 羽化 / 负 = 收缩，与 plan KD-3
  全量程语义一致；sigma 约定族 = dt「sigma = blur_radius」直传形
  （`MaskCombiner.swift:99-100` 头注）——golden 表手算约定可落。
- **0 羽化短路可测**：AIMaskPlane 值类型 + `floats` 同值返回 = 字节恒等
  trivially 成立；测试断言形（byteIdentity 比对，:89-99）在册。
- **raster-only spec 不达 postProcess 亲证**：`MaskCombiner.swift:623-635`
  ——`if let parametric = spec.parametric` 门，raster-only（parametric
  nil）跳过 postProcess ✓（KD-3 的这一半勘察属实；另一半 = M5）。
- scribble 缝零触成立：`AISubjectSeed.scribble` typed 拒（
  `AIMaskService.swift:328-329` + `AIMaskTypes.swift:71`）原样保持即合规。

### 5. 两 plan 交接——机制已写、红线一致、批序无冲突

- 串行 01→02 双 plan 头 + CONTEXT Plans 节一致；02 对账基线 =
  「plan 01 收口值」（AC8/checker 7 两处）——机制成立（S8 补强一句）。
- 共享红线集一致：`.metal` 零 diff / 零新 SPM / V50Order / 六格式导出
  矩阵 / MCP 快照族 / sidecar schema / UserDefaults 零新键 / L041/E2/
  L057/L070/M2-7-3 parentage——两 plan 无冲突无遗漏对表。
- 文档批序：AGENTS（01 面 A 段 → 02 面 B 段）、ROADMAP（01 注记 → 02
  翻 ✅）、xcstrings（01 尾块 13 键 → 02 尾块 5 键）、Project.swift
  （01 六行 → 02 四行）——顺序 commit 无 conflict 面。
- 账面锚亲证：REQUIREMENTS :409 = M6INT-02、:410 = M6INT-03 ✓；
  ROADMAP :75 M6-4 行 ✓；基线 3759/24/0 两路亲跑同值
  （`M6-3-01-ACCEPTANCE.md:23` + `ACCEPTANCE-2ND.md:26` +
  `VALIDATION.md:33`）✓。

### 6. SC 机检性与数字对账——除 M2 一处不可落缝，全部有载体

- 数字算术闭合亲算：01 = 8+16+8+9+4 = 45（LIB）+ 10（APP）= 55 ∈
  `+52..58` ✓；3759 + 52..58 = **3811..3817** ✓。02 = 9+6+4 = 19
  （LAYERS）+ 4（APP）= 23 ∈ `+21..25` ✓；3811..3817 + 21..25 =
  **3832..3842** ✓（两段滑差叠加正确）。
- bundle 注册表拼写分用正确：`BUNDLES=(IOP IOPParity Layers Library
  Sessions Export App)`（`Scripts/test-direct.sh:165`）；plan 01 命令
  `--bundle Library` / plan 02 `--bundle Layers`——front-matter 的
  LIB/APP/LAYERS 为 BUNDLE-MAP 域标签（:341-370 LIB / :290-324 LAYERS
  先例亲证），散文缩写不入命令行纪律两 plan 自洽。
- 新测试文件名零碰撞（LibrarySchemaV5Tests/LibraryStackStoreTests/
  AutoStackClusteringTests/StackPaginationTests/ImportMergeStackTests/
  LibraryGridStackTests/AIPatchAssemblyTests/AIMaskFeatherTests/
  PersonInstanceMaskTests/AIMaskPatchFlowTests——现有树无同名）。
- AIMask 新测试归 LAYERS 与五文件先例（BUNDLE-MAP :290-324）一致；
  App 流程测试归 APP 先例一致（除 S3 的 01 侧归属商榷）。

### 7. 独立猎残——OQ/plan 矛盾清点（除 M1/M7 外无新矛盾）

- OQ-2「LightCraft 全套语义」与 M6INT-02「burst/bracket」字面：RESEARCH
  A1 明载「burst/bracket 无专门检测——纯时间阈值与 Lightroom 同型」+
  D-M6-4-2 生效值同文——无矛盾（M6INT-02 的「（burst/bracket）」括注
  为需求侧口语，裁决正本已收窄）。
- `splitStack` 空前缀边界（S6）为唯一未定语义边界；`group` 全并自身栈
  的幂等（并组结果 == 原栈）建议 DECISIONS 一句（实现自然收敛 no-op，
  非阻断）。
- 01 的 `stacks.added_time/modified_time REAL` 可空与 albums 行惯例
  一致 ✓；`position` 稠密重编号由 store 全写路径承担（KD-2）——
  读面 `stackMemberships` 的 position/size 一致性由单事务写保证 ✓。

---

## 处置摘要

1. **一个两 plan 修订批**（orchestrator 回注或 planner 自修；七项 OQ
   生效值不动）：
   - Plan 01：E1（KD-6 匹配细则改后缀/批内候选 + 风险节公式勘误 +
     T5 fixture 走真导入流）、M1（DECISIONS 增「无顶替」偏离 + 语义腿
     漏召回申报 + overviewCount 口径一行）、M2（T4②/AC4 改双证据口径）、
     M3（风险节指名两法 + AC7 措辞）、M4（mergeStacksSkipped 或删
     计数断言二选一）、S1..S6 顺带。
   - Plan 02：E2（KD-2 钉标签合成提取腿 + generateScaledMask 禁用注记 +
     T3 增断言）、M5（KD-3 缝勘察补全二选一 + 双羽化钉死或复用既有
     featherRadius）、M6（活平面持有策略 + 内存姿态入风险节）、
     M7（键改 ai_mask_person_instance）、S6'..S8 顺带。
2. 修订后无需重跑本评审全量——定向复核 E1/E2/M1/M5 四节。
3. 其余全部维持：两新表 join 形、auto-stack 全套语义、分页谓词+fixup
   形态、导入缝落点、patch 判据五表、GUI 轮 R4 形态、任务分解、SC
   数字面、测试钉法主体。
4. **两 plan 分开表态**：01 = 须修后放行（E1 为导入缝核心机制级，修订
   前 T5 不可开工）；02 = 须修后放行（E2 为提取腿钉死级，修订前 T3
   不可开工；M5 不阻断 T1/T2 纯函数面）。执行串行 01→02 不变。

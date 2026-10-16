# M7-4 CONTEXT — MCP O4 跨图批量 + note 归属 + UQ-A2 原子终写 + M7-3 挂账清算（OQ 裁决落定批，2026-10-13）

> **裁决正本**：OQ-M7-4-1..10 **全部按 `M7-4-RESEARCH.md` §7 推荐落定**（M7 站
> charter 授权站内 auto-advance + OQ 全按推荐；先例 M6-3/M6-4、M7-2/M7-3 同款）。
> **晨审可推翻**——推翻 = 用户晨审修订本文件对应 D 条，下游 plan 受影响任务面
> 重开（已执行部分按「晨审推翻先例」惯例处理）。读解正本 = 同目录
> `M7-4-RESEARCH.md`（§0 结论摘要 / §1 O4 测绘 / §2 S1 修复 / §3 S2 三选一 /
> §4 UQ-A2 / §5 match_color 勘正 / §6 测试策略 / §7 OQ 表；file:line 经
> planner 2026-10-13 HEAD `0b34d199` 逐点亲核复核吻合——armStdioEOFReleaseOnce
> poll `events: 0` + `poll(-1)` / isAdjustmentTransferable :35-38 + enumerate
> :241-265 + pastePayload :302-324 + 排除单源头注 / apply_params body :591-685
>（gate → live 硬拒 → probe → boundedWait → apply → flushForTeardown 写达后方
> 返）/ get_history author 占位 :897-900 / McpTimeouts.applyBatch 60s 既有档 /
> write-five `requireRelPaths max: 1000` :348 / HistoryItem CodingKeys :131-133
> 现 9 键无 note/author / HistoryHash 只折 enabled instances + layer 面（item
> 元数据不入折）/ ExportRenderer renderStage 步 9 :625-638 + encodeStage :655
> + ExportNamingCarrier :133-161 + gain-map 臂 :683-706 / ExportQueue 占名快照
> :470-477 + gate ③ :506-516 + render 腿 namingCarrier 装配 :489-493 + encode
> 腿 :521-528 + productionLegs :710-732 / ExportNamer `.fail` 抛
> BaseNameOccupiedError :133-137 / LightamerApp match_color provider :1364-1372
> 传 .lalb 文件 URL / MatchColorToolset.resolveReference :549-602 /
> SessionBatchApplier.apply :232-296 / PasteSemantics.paste :69-100 /
> EditorToolRailView historyRow :199-235 / union 现 27（all27 :219 / 计数 ×4
> :249/:299/:327/:479 / destructive 9 件 :255-260 / descriptionKeys :334）/
> union 外计数钉现 21（McpRegistrySnapshotTests :203 / McpSearchStateToolsetTests
> :274 / McpHostTests :243/:697 / McpLauncherTests :200——**M7-3 后行号已漂移，
> 上列为本波 fresh 坐标**））。
>
> **夜间全自动授权在案**（先例 D-07-3-T5-1；晨审可推翻）：本 phase 执行批
> （omp/subagent 执行 + 独立验收 + 全套 `--all` 轮〔批准制——执行时
> orchestrator 派发 prompt 即批准〕）可夜间全自动推进，不需逐任务等待用户
> 确认。
>
> **C 档门控行使记录**：RESEARCH 自标「C 档第 1 停（OQ 裁决前不进 plan）」——
> 该停由站 charter 授权链行使（OQ 全按推荐落定即裁决，本文即落定载体）；
> C 档第 2/3 停（plan 闭环汇报 / VALIDATION 签核）照常保留——站内
> auto-advance 只覆盖第 2 停的**等待面**（闭环汇报照发，不停等确认），第 3 停
> （VALIDATION 签核给用户过目）不受站内授权覆盖，仍走人工过目。
>
> **plan 修订批（2026-10-13/17，REVIEW F1-F14 落定，orchestrator 已裁）**：
> D-M7-4-7 机理勘正（F2——poll 超时只封阻塞相、不构成速率限制；忙旋消解本体
> = 纯 POLLIN 臂 250ms sleep）/ D-M7-4-8 预热 3→**4** 装配点（F5 补
> startReadOnlyHTTPHost 只读臂）+ 测试语境 env 门（F14，LIGHTAMER_SKIP_LUT_
> PREHEAT）/ D-M7-4-5 author 真位式消截断二义（F8）/ 红线③ LightamerSidecar
> carve-out（F1——SidecarHistoryItemRecord 恰两字段镜像 + schemaVersion 10→11
> bump 已申报，v8/v9/v10 先例链）/ 红线① 计数钉 21→**23** 算术勘正（F3——
> editing 7→9 → 双域面 = 9+14 = 23，M7-3 H1 家族防复发）。OQ-M7-4-1..10 裁决
> 值本身零翻案（D-M7-4-8 装配点清单补全 = 裁决值忠实化——只读臂宿主属「无头
> 宿主 start」面）。修订正本 = 同目录 `M7-4-01-PLAN-REVIEW.md`。
>
> **快照改动权（本波显式取权）**：M7-2/M7-3 改动权已用讫；O4 additive 两工具 +
> apply_params note 参数 → union 27→29 **显式取权**（research §1.5 评估：M7-4
> 在 M7-5 前串行执行，取权合法；红窗纪律 = 快照触碰只发生在工具落地 commit）。
> **M7-4 持权窗口内禁并行派发 M7-5**（orchestrator 编排保证；若误并行派发 =
> 立即停手上报，禁抢先合并快照表）。

## Phase Goal（ROADMAP §M7-4 行锚定）

`copy_adjustments` / `paste_adjustments`（MCP2-08 跨图批量：GUI Copy Adjustments
面的 MCP 同构——枚举预览 + 批量 overwrite 粘贴）+ MCP 写工具 note/author 归属
（MCP2-09：HistoryItem additive 两字段 + `get_history` 读面 + GUI 历史行显示）
+ UQ-A2 导出 FAIL 档原子不覆盖（终写 `link()` EEXIST 拒晋升，TOCTOU 窗闭合）
+ M7-3 挂账清算（S1 stdio EOF watcher 修复批首项 / S2 裁决 A+C / S3 正臂补一
腿 / match_color provider projectDirectory 勘正）。对应 REQUIREMENTS
MCP2-08..09（:438-439）+ UQ-A2（:459）；对表锚 = Alcedo adjustments 面
（export_service.cpp `6203791` / `e75cf2a` / `9f9fc5e`）+ 输出防覆盖
`1f12551`（GPL 只读语义对表，代码零复制）。

## 决议（D-M7-4-1..10，生效值，硬约束，执行中不重开）

### D-M7-4-1 paste targets 域 = session relPaths（OQ-M7-4-1）

- **裁决 = RESEARCH 推荐（①session 域）**：`paste_adjustments` targets =
  open-session relPaths 数组（maxItems 1000，write-five 同帽）——与全部既有
  MCP 写工具一致；headless 臂 = typed `notSessionMember` 诚实拒（session 工具
  在无 session 宿主的诚实臂，render_preview 先例同形）。
- **库域批量写不立**：`.lalb` 无 claim 面、sidecar 直写 + 投影刷新缺口——设计
  缺口不是 additive 能补的；挂 **UPSTREAM-QUEUE 观察项**（万级库域批量需求实测
  出现才立项）。
- 被否备选：②库 id（需库域写投影设计）③双形态 targets（写面只认 session 域
  ——读面才双形态，见 D-M7-4-2）。

### D-M7-4-2 copy source = 库 id + session relPath 双形态（OQ-M7-4-2）

- **裁决 = RESEARCH 推荐（①双形态）**：`copy_adjustments` source 走
  `MatchColorToolset.resolveReference` verbatim 复用（digits = 库 id →
  `LibraryStore.image` → `ImageLinker.resolve`〔kind0/1/2〕；否则 =
  `EditingToolset.resolveMember` session relPath）——读面双形态廉价且与读工具
  （get_history/list_versions 双地址制）一致。库 id stale = typed
  `notSessionMember` 携 relink reason（match_color 同文案族）。
- **editor-current 哨兵不立**（显式 > 隐式，D5）：agent 无「当前图」概念，哨兵
  是为交互层设计的隐式面。
- 前置依赖：**match_color provider projectDirectory 勘正（§顺路件⑤/T5）随本波
  先落**——kind0/id 行正式进入 MCP 写面路径前，目录锚病必须先清（同一缝两波
  触碰 = churn）。

### D-M7-4-3 两动词形态 = 无状态双动词，无服务端剪贴板（OQ-M7-4-3）

- **裁决 = RESEARCH 推荐（①无状态）**：`copy_adjustments` = 只读枚举预览
  （readOnlyHint:true，不落任何服务端状态）；`paste_adjustments` = source +
  targets[] 一次性写，载荷 = 源链**无状态重读**（非 copy 应答缓存）——多客户端
  交错安全 + D5 无状态纪律；Alcedo 三动词（items/copy/paste）收敛为二（items
  面并入 copy 应答）。
- **不引入 `list_tasks`/`wait_task`**：apply_params 先例证明「写达后方返」
  （flushForTeardown）的同步形在 MCP 帖面成立；compose 零渲染红线保证 claim 段
  小常数 + `McpTimeouts.applyBatch` 60s 窗 ≤1000 目标批够用；tasks 面代价 =
  两新工具（union 27→31）+ 通用任务 tracker 基建。挂 **UPSTREAM-QUEUE 观察项**
  （万级目标批实测超窗才升级）。
- 被否备选：②服务端剪贴板 token（交错不安全 + 状态面）。

### D-M7-4-4 author 盖章值 = 固定 `"mcp"`（OQ-M7-4-4）

- **裁决 = RESEARCH 推荐（①固定 token）**：MCP 写工具（apply_params /
  paste_adjustments）写 commit 时 HistoryItem `author = "mcp"`（固定 token，最
  小面）；note = 参数透传（非空校验同 append_note minLength 1 形；缺省 = 无
  note 字段不入 bytes——nil 不编码）。
- **版本级 author 悬置**：VersionsPanelView 零触（版本行无 author 列）。
- **GUI 写腿零 diff**：交互层写 commit author 恒 nil（Alcedo「默认 user」语义
  的省略形——nil 即 user，无显式 user 徽章面）。
- 被否备选：②serverName（可变身份）③可变 agent 身份参数（面大无收益）。

### D-M7-4-5 get_history 顶层 author = 最新 kept item 的 author（OQ-M7-4-5）

- **裁决 = RESEARCH 推荐（①翻转占位）**：`get_history` per-item dict 加
  `"note"`/`"author"` 两键（缺省 .null）；顶层 `author` 占位（:897-900 M7-2
  注记「M7-4 (MCP2-09) fills this」）翻转为 **position 位 item 的 author**
  （实现式 = `stack.position >= 0 ? stack.items[stack.position].author : null`
  ——真 position 位 item，与截断无关；无截断时即最新 kept item——修订批 F8
  消截断二义〔suffix kept 红尾态下两者不是同一 item〕）；pristine/空链
  = .null。
- 被否备选：②恒 null 保留占位（占位注记已承诺兑现）③删键（破 pristine 形状
  一致性）。

### D-M7-4-6 paste 不建 per-target 版本（OQ-M7-4-6）

- **裁决 = RESEARCH 推荐（①v1 不建）**：paste 走既有 OVERWRITE-paste epoch 语义
  （`PasteSemantics.paste` .overwrite + UUID recast + label "MCP
  paste_adjustments" 可自查）——既有语义零新面；版本结构不进 historyHash 的
  M2-8 判断不受扰。
- 被否备选：②per-target +1 版本行（Alcedo `e75cf2a` 同构）——挂
  **UPSTREAM-QUEUE 观察项**（预贴态隔离需求实测出现才立项）。

### D-M7-4-7 S1 poll 循环形态 = bounded re-poll 250ms + 纯 POLLIN 臂 250ms sleep（OQ-M7-4-7；修订批 F2 措辞勘正——机理以本版为准，RESEARCH §2.2 原句按惯例不改）

- **裁决 = RESEARCH 推荐（①bounded re-poll）**：`armStdioEOFReleaseOnce` poll
  改 `events: POLLIN` + 超时形 `poll(&fds, 1, 250)`；醒后按 `revents` 分流——
  `revents & (POLLHUP|POLLERR)` → `takeStore()?.close()` + `exit(0)`；纯 POLLIN
  → **只清 `revents` + sleep 250ms** 续 poll 不消费字节（「清位」指 revents 非
  events——措辞在 plan 写实防误读）。**机理勘正（REVIEW F2）**：`poll(2)` 的
  timeout 只封**阻塞相**上界——fd 已就绪（测试面 dup2 /dev/null 恒可读）时
  `poll(&fds, 1, 250)` **照样立即返回**，超时形本身不构成速率限制；忙旋消解的
  本体 = **纯 POLLIN 臂的 250ms sleep**（恒可读 fd 上 = 4Hz .utility 帽；真管道
  数据就绪臂亦睡 250ms——watcher 零字节消费，请求读取线程独占消费，无请求延迟
  面）。真管道 HUP 语义不变（HUP 到达时下一轮 poll 立即返 HUP → 分流 break，
  不经 sleep 臂）；250ms 窗对 12s 活性断言无影响。
- once guard / M1 mode 自守卫 / http 臂不 arm 语义全部零改。
- 被否备选：②`-1` 阻塞 + 测试面接受自旋（甲〔sleep 臂〕已消解自旋，乙无残余
  优势——修订批 F2 后否决理由更新）。

### D-M7-4-8 S2 裁决 = A 预热 + C 文案（OQ-M7-4-8）

- **裁决 = RESEARCH 推荐（①A+C）**：
  - **A 启动后台预热**：宿主装配点 `Task.detached(priority: .utility) { _ =
    LutLibraryStore.shared }`（GUI 装配 + 无头 stdio / http / **只读 http**
    三宿主 start 共 **4 点**——修订批 F5 补 `startReadOnlyHTTPHost`
    〔heldByOther 只读臂 :652-708 同服 list_luts〕；共享一行 helper）——预热
    完成后 agent 首调即答；启动期 ~50s 后台 CPU（.utility 让位渲染）。
    **测试语境禁用（修订批 F14 落形）**：helper 内 env 门
    `LIGHTAMER_SKIP_LUT_PREHEAT`（非空即早退）——e2e/仲裁 spawn 的真宿主
    fixture 注入该 env（McpProjectArbitrationTests spawn 已有 env 注入缝
    :70-72，成本一行），免每测试进程 50s .utility 解析 + 向真实用户 LUT 根
    seeding。
  - **C 文案如实化**：`mcp_tool_desc_list_luts` 原位值改——description 注记冷
    首调代价（预热残余窗内首调至多 ~50s，短超时客户端注意重试）。
  - **B 协作化不采**：withTimeout v2 abandon 形是独立语义族专项（~20 工具共
    用），挂 **UPSTREAM-QUEUE 候选**（M7-5+ 评估）。
  - **新档支线不行使**：`McpTimeouts` **零 diff**（不加 `listLuts` 档——A 预热
    消解真实痛点后，残余窗口由 C 文案诚实覆盖即可；既有档值零改红线 D-M7-2-3
    延续，测试盲区 = golden replaceShared 小 store 形维持现状不入本波）。

### D-M7-4-9 UQ-A2 typed 错误 = 复用 `BaseNameOccupiedError`（OQ-M7-4-9）

- **裁决 = RESEARCH 推荐（①复用）**：`link()` EEXIST → 抛
  `ExportNamer.BaseNameOccupiedError(name:)`（既有 typed，:36/:136）——表面与
  render 步快照检查一致（job fail typed 同形），错误码 16 档封闭表零新增；
  其它 errno → `internalError` 兜底。
- **保留 render 步快照检查**（与上游 `6203791` 唯一分歧）：我方快照在渲染前 =
  doomed job 免付全渲染成本（成本门非正确性门）；正确性门 = link() EEXIST。
  分歧理由 DECISIONS 申报。
- 被否备选：②新 typed case（错误码表新增面，违封闭表红线）。

### D-M7-4-10 includeDrt / include 默认面 = DRT 默认随行 + include 缺省全贴（OQ-M7-4-10）

- **裁决 = RESEARCH 推荐（①）**：`includeDrt` 默认 true（DRT 行默认随行，
  `includeDrt: false` opt-out）；`include`（instanceId 列表）缺省 = 全部
  transferable——GUI「默认全选可贴 + DRT 默认勾」语义镜像。
- mask 纪元重置随载荷构建恒生效（`contentRevision` 置 nil——源图在飞 mask
  writer 不得对贴后图生效，跨图粘贴正确性关键，M2-8 KD-3）。
- 被否备选：②DRT 默认不随 + opt-in（GUI 语义不镜像，agent 每次多传一参）。

## 顺路件（M7-3 挂账单一清单清算；正本 = M7-3-VALIDATION §挂账）

| # | 项 | 本波处置 |
|---|---|---|
| ① | S1 stdio EOF watcher `poll(events: 0)` 永不醒（M6-1 `1f981f9b` 潜伏缺陷） | **T1 修复批首项**（POLLIN + revents 分流 + bounded re-poll 250ms〔D-M7-4-7〕+ /tmp/m73_probe 三层探针迁 evidence + e2e 真断连回归〔12s 活性 + `.lalb-wal`==0 checkpoint 断言〕） |
| ② | S2 `list_luts` 冷首调 50.2s 超 10s 声明窗 | **T2 行使 A+C**（D-M7-4-8）；B → UPSTREAM-QUEUE |
| ③ | S3 GUI 差分谓词正臂零覆盖 | **T2 补一腿**（`makeGuiShapedProvider(stub:heldTargets:)` 传非空 heldTargets → typed projectReadOnly 正臂可达；零产线代码）；O1 同形复制漂移 = 测试桩内复制体，产线单源由 T3 Catalog 抽取建立——漂移注记维持不另抽 |
| ④ | 第二路验收事故自我申报 | 无动作（已按 M2-7-3 parentage 教训指针化登记） |
| ⑤ | match_color provider projectDirectory 传 .lalb 文件 URL（kind0 锚病） | **T5 勘正**（GUI 装配点一行 `deletingLastPathComponent()` 目录锚 + 两测试 provider 同形 + 新 kind0 锚腿测试；fix `20997721` 先例形——O4 copy 库 id 形骑同一 provider 面，写面前卫生前提） |
| ⑥ | EOF http-absence 偏离 + 双臂不对称措辞 | **T1/T6 同批复核注记**：修后 stdio 优雅面**成真**（此前双臂皆惰性）；不对称变为「stdio graceful / http kernel-floor」的真实差异。**M7-3 签核文档不回改**（DECISIONS H3③ / VALIDATION 挂账⑥ / 特殊事项 5 三处）——校订以 M7-4 DECISIONS 注记为准（M7-3 CONTEXT L1「历史签核文档不回改」先例形） |

**FIX2③ 维持不承载**：修法落点 `LibraryProjectController.swift` 尾部，本波
design 不触该文件——controller 零 diff 门连续第三波兑现；若执行期行使须显式
申报。

## 键族 / 登记面

- **xcstrings 尾块纯插入 3 键**：`mcp_tool_desc_copy_adjustments` /
  `mcp_tool_desc_paste_adjustments` / `editor_history_author_badge`（author
  徽章 AX label；note 无需键——原文字面直显）+ **原位值改 1 键**：
  `mcp_tool_desc_list_luts`（en defaultValue + zh 译文同批——冷首调代价句；
  非尾块插入，DECISIONS 申报）。zh-audit `--check` 对账 source keys 数 +3；
  `--self-test` PASS。
- **UserDefaults 零新键**（copy/paste 无状态纪律 D-M7-4-3；预热面无记忆键）。
- **登记纪律**：新测试一律 additive 到既有文件（AdjustmentTransferTests /
  McpEditingToolsetTests / McpProjectArbitrationTests / ExportRendererE2ETests
  / SidecarV10Tests 等）——**预期 Project.swift / BUNDLE-MAP 零行变更**；若执
  行期必须新建文件（如 S1 e2e 独立成文件）= 恰一行 + BUNDLE-MAP 恰一行 +
  `tuist generate` 恒为该批最后一个动作（L041）+ DECISIONS 申报。

## 红线（正本移交 `M7-4-01-PLAN.md` front-matter `red_lines`，此处摘要）

①union 27→29 **显式取权**（冻结表 +2 行 + apply_params schema note 行两层
consciously change together + destructive 集 9→10〔paste_adjustments
destructiveHint〕+ union 外五处计数钉 21→**23** 显式改〔editing 7→9 → 双域面
= 9+14 = **23**——修订批 F3 算术勘正，M7-3 H1 家族防复发〕+ 残漏 grep；
M7-5 禁并行）。
②零新 SPM。③HistoryHash **零 diff**（note/author additive 不入折——负测钉
死）；HistoryItem 仅 additive optional 两字段（drtRecord/filmRecord 同族先例，
tolerant 双向 decode、nil 不编码）；**LightamerSidecar carve-out（修订批
F1）**：`SidecarHistoryItemRecord` 恰 additive 两字段镜像投影（note/author，
Keys + init + decode/encodeIfPresent + `item` 重建全链——filmRecord :826-829
同族镜像形）+ **schemaVersion 10→11 bump 已申报**（sidecar 面增必 bump 先例
链：v8 aiProvenance / v9 filmRecord / v10 process）——除 carve-out 外
LightamerSidecar 类型/schemaVersion 零 diff。④错误码 16 档封闭表
零新增（copy/paste 全走既有码；UQ-A2 复用 BaseNameOccupiedError）。⑤封存面
零触 + 申报内例外：encodeStage 仅 additive 默认参一处（exclusiveFinalWrite，
缺省 = 既有调用方零 diff）；ExportQueueContract leg 形零 diff（policy 递缝走
`$jobNamingCarrier` wrapper——`$jobExifSoftware` 同款第四例）；ExportNamer /
ExportCollisionPolicy / 六格式矩阵 / UI ExportInspectorView / schema 零触；
PixelPipe / V50Order / GradeCatalog / Lut3dKernels.metal / DrtRecord /
TerminalTailPolicy / DrtEotf / PipelineDocument / Registry / ModuleInstance /
LightamerSidecar 类型零 diff。⑥McpTimeouts 零新档零改档（applyBatch 60s 既有
档消费）。⑦Alcedo GPL 代码/文案零复制零翻译（6203791/e75cf2a/9f9fc5e/1f12551
只对表命令语义）。⑧xcstrings 3 尾块插入 + 1 原位改 + zh-audit 双 PASS；
UserDefaults 零新键。⑨`.runModal(` App/Sources 零命中；LocalizationValue 插值
禁形零命中（描述键一律 String(localized:defaultValue:) 显式形态）。⑩`--all`
全套轮批准制 + 8G 门 + MEMFAIL 机检 + 运行中保持监视；测试宿主清理先核
parentage（`ps -o ppid`）。⑪controller（LibraryProjectController）文件零 diff
（FIX2③ 第三波维持）。

---

## 晨审推翻点索引（可推翻面速查）

- **D-M7-4-7**：S1 bounded re-poll 250ms + 纯 POLLIN 臂 250ms sleep（修订批
  F2 勘正后的真忙旋消解形——sleep 臂是速率限制本体）——若晨审倾向「-1 阻塞 +
  测试面接受自旋」= 改 D-M7-4-7 与 plan T1 对应面（e2e 判据不变）。
- **D-M7-4-8**：S2 新档支线（`McpTimeouts.listLuts` 60s）本波不行使——若晨审
  认为预热窗内首调仍需长窗保护 = 显式行使（新档非改档，须 DECISIONS 申报 +
  快照/SC 同批）；预热 4 装配点 + env 门同属本 D 条修订面（修订批 F5/F14）。
- **D-M7-4-1/2**：库域批量写 / 双形态 targets 若晨审要求提前 = 越出 additive
  面，须重开 research 缺口设计（非本 plan 承载）。

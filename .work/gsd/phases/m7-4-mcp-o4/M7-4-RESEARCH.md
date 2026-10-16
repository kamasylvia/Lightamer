# M7-4 RESEARCH — MCP O4 跨图批量 + note 归属 + UQ-A2（MCP2-08..09 + UQ-A2）+ M7-3 挂账清算

```
phase:        M7-4
title:        MCP O4 跨图批量 research（copy_adjustments / paste_adjustments / note 归属
              attribution）+ UQ-A2 导出 FAIL 档原子不覆盖 + M7-3 挂账清算（S1 修复首项 /
              S2 裁决三选一 / S3 顺路腿）+ match_color projectDirectory 勘正
status:       research-draft — C 档第 1 停（OQ-M7-4-1..10 待裁决，裁决前不进 plan）
baseline:     3905/35/0（M7-3 三路全套同值，本批 doc-only ΔN=0）
date:         2026-10-13
input:        ROADMAP §M7-4 行 + REQUIREMENTS MCP2-08..09（:438-439）+ UQ-A2（:459）+
              M7-3 VALIDATION §挂账单一清单（①S1 修复批首项 / ②S2 裁决三选一 / ③S3 顺路 /
              ⑥措辞校订，正本 = phases/m7-3-mcp-o2o3/M7-3-VALIDATION.md :75-84）+ 双
              ACCEPTANCE S1 三层复现与探针指针（/tmp/m73_probe/ 迁移源）+ S2 sample 栈证据 +
              research/ALCEDO-CLI-AI-SURVEY.md 块一 O4 面（:118/:120/:256/:260/:262/:267/:270/
              :288/:304）+ UPSTREAM-QUEUE UQ-A2 行 + Alcedo 本地源对照（export_service.cpp
              6203791 / adjustments 面 e75cf2a、9f9fc5e，GPL 只读对表）+ 我方现状 = M2-8 Copy
              Adjustments 面（AdjustmentTransfer.swift isAdjustmentTransferable 单谓词 /
              VersionCoordinator.pasteChain）+ Phase 9 SessionBatchApplier 三段批 +
              Phase 12 note/keywords/rating MCP 面 + M7-2 SearchStateToolset context provider
              形态 + M7-3 ProjectToolset/box 面 + M6-1 单写者锁 + ExportCollisionPolicy FAIL 档
red_lines:    ①MCP 快照 union 显式改——M7-2/M7-3 改动权已用讫移交 M7-5；本波 additive 工具
              触快照须 **显式取权**（union 27→29；M7-4 在 M7-5 前串行执行，取权合法；
              M7-4/M7-5 禁并行派发维持）②零新 SPM ③Alcedo GPL 代码/文案零复制零翻译
              （只对表命令语义）④不改码（本批 doc-only）⑤错误码 16 档封闭表零新增
              ⑥McpTimeouts 既有档值零改（CONTEXT D-M7-2-3 红线；S2 若走「新档」支线须
              晨审显式裁决）⑦--all 全套轮仍须 orchestrator 批准（research 零产线）
estimate:     1 plan（S1 修复首项 + O4 两工具 additive + note/author 面三件 + UQ-A2 一缝 +
              S2/S3/match_color 三顺路 + union 27→29 显式改 + parity/TOCTOU/E2E goldens）
```

## §0 结论摘要

1. **O4 两工具全 additive 可落地，单源齐备，零新依赖、零新错误码**（§1）：
   - **`copy_adjustments`（只读枚举预览）+ `paste_adjustments`（批量写）** 的完整链 =
     M2-8 枚举单源（`isAdjustmentTransferable` 单谓词 + `LayerStackProjection.rebuild` +
     mask `contentRevision` 新纪元置 nil）→ `PasteSemantics.paste`（overwrite epoch，UUID
     recast）→ `SessionBatchApplier` 三段批（compose/claim/serial write）——四层全部现成，
     apply_params 已单图走通同链（EditingToolset :591-685 即「单图版 paste」全框：write gate
     → live 拒 → probe → boundedWait → apply → flushForTeardown 写达后方返）。
   - **无状态双动词**（推荐）：copy = 源链枚举只读预览（readOnlyHint）；paste = source +
     targets[] 一次性写，**不设服务端剪贴板**（D5 无状态纪律 + 多客户端交错安全）。
     Alcedo 三动词（items/copy/paste）收敛为二（items 面并入 copy 应答）。
   - **writer 面**：requiresWriter:true + rejectIfProjectReadOnly probe + write gate 串行 +
     imageLiveInEditor 硬拒（活图不入批循环，MCP 无 interactive layer 不能静默 skip）——
     write-five/match_color/apply_params 三先例同框拼装，零新机制。
   - **不引入 `list_tasks`/`wait_task`**（推荐）：apply_params 先例证明「写达后方返」的同步
     形在 MCP 帖面成立（compose+claim 快 + sidecar drain 由 flushForTeardown 收口），
     applyBatch 60s 窗够 ≤1000 目标批；Alcedo tasks.wait 语义挂起条件（后台任务）不触发。
2. **note/attribution（MCP2-09）= HistoryItem 两个 additive optional 字段**（`note: String?` +
   `author: String?`）：HistoryHash 只折 instances/layers 投影（HistoryHash.swift :37-130 亲证
   item 元数据不入折）→ **注记字段零 hash 漂移、零 schemaVersion 变更**；新旧双向 tolerant
   decode。MCP 写工具盖章 author="mcp"；get_history per-item note/author 键 + 顶层 author
   占位翻转；GUI 面 = EditorToolRailView 历史行 note 副标题 + author 徽章（验收走查面）。
3. **S1 修复落点唯一且小**（§2）：`McpServerController.armStdioEOFReleaseOnce` :388-408，
   poll `events: 0` → `POLLIN` + 醒后 `revents & POLLHUP` 分流。**研究新发现一处设计风险**：
   修后「纯 POLLIN 清位续 poll」形在恒可读 fd（测试面 dup2 /dev/null stdin）上退化为忙旋——
   建议 bounded re-poll（如 250ms 超时）消化（OQ-M7-4-7）。回归 = /tmp/m73_probe 三层探针
   迁仓（真二进制 + 真 EOF + 12s 活性窗 + **`.lalb-wal`==0 checkpoint 断言**）。波及面 =
   M7-3 挂账⑥ + DECISIONS H3③ 两处「优雅面」措辞同批校订 + VALIDATION 特殊事项 5 dup2
   卫生注记维持必要性；GUI 臂（M1 自守卫）与 http 臂（kernel 地板，挂账⑥）零变化。
4. **S2 三选一测绘完毕，推荐 A 预热 + C 文案组合、B 协作化不推荐**（§3）：无 launch 预热
   是两臂共同现状（grep 零命中——GUI 臂靠首次 LUT 面板打开摊销，agent 臂独吃）；预热 =
   宿主装配点 `Task.detached { _ = LutLibraryStore.shared }` ~10 行；文案 = description 注记
   冷首调代价 ~5 行；协作化依赖 withTimeout v2 abandon 形（语义族改动越出顺路面）。
5. **UQ-A2 = encodeStage additive `exclusiveFinalWrite` 参数 + tmp 同目录 encode + `link()`
   EEXIST 拒晋升**（§4）：现状 TOCTOU = render 步 9 occupiedNames 快照检查与 encode .atomic
   rename（Darwin rename 覆盖语义）之间他进程建文件即被覆盖；修法走 naming carrier 到
   encode leg（TaskLocal additive wrapper，$jobExifSoftware 同款纪律，零新载体）；与上游
   6203791 唯一分歧 = **保留 render 步快照检查**（我方检查在渲染前 = 省一次全渲染成本的
   快速失败门，非正确性门；正确性门 = link() EEXIST——分歧理由在案）。
6. **match_color 勘正 = 一行 + 一测试，本波顺路判定 YES**（§5）：O4 copy 源的库 id 形态骑
   同一 provider 面（MatchColorToolset.installLibraryProvider）——同一缝两波触碰 = churn，
   本波一并勘正（`deletingLastPathComponent()` 目录锚，fix `20997721` 先例形）。
7. **快照 union 权评估**：O4 additive 两工具 → union 27→29 **显式取权**（红窗纪律 =
   快照触碰只发生在工具落地 commit，同 M7-2/M7-3 形）；apply_params schema 加 note 参数
   = editing 域层 McpRegistrySnapshotTests 同批显式改（两层 consciously change together，
   render_preview 先例）。M7-5 串行禁并行注记维持。
8. **主域判定**：O4 两工具落 **editing 域**（EditingToolset 扩展——Seams 的
   session/projectWriteProbe/liveImageURL/modules 四缝全部现成，Alcedo 同族 = editor
   adjustments 动词；不立第六域）。xcstrings 两新键尾块纯插入；错误码零新增
   （notSessionMember/invalidParams/projectReadOnly/imageLiveInEditor/internalError 全复用）。

---

## §1 O4 跨图批量测绘（MCP2-08 copy/paste_adjustments + MCP2-09 note/attribution）

### §1.1 现有单源盘点（file:line）

| 层 | 单源 | 位置 | O4 消费形 |
|---|---|---|---|
| 排除谓词 | `isAdjustmentTransferable(_:)` | App/Sources/Lightamer/State/AdjustmentTransfer.swift :35-38（头注 :25-27 明令「no second copy of the exclusion logic may appear at the view layer」） | copy 枚举 + paste 载荷物化，**直调复用**（App 层自由函数，MCP toolset 同在 App 层零 import 面） |
| 枚举投影 | `AdjustmentTransferModel.enumerate(chain:)` | AdjustmentTransfer.swift :241-265（LayerStackProjection.rebuild → nodes/items + transferable 计数） | **纯函数抽取**——现嵌在 @MainActor @Observable model 里；O4 抽 `AdjustmentTransferCatalog` 型纯 helper（枚举 + 载荷构建），GUI model 与 MCP toolset 双消费（消二份，S3 顺路 O1 同族注记见 §6） |
| 载荷物化 | `pastePayload()`（mask 新纪元） | AdjustmentTransfer.swift :302-324（checked 实例平铺 + layer snapshot + **mask.contentRevision = nil** :311-313 + DRT 行） | 同上抽取；mask 纪元重置是跨图粘贴正确性关键（源图在飞 mask writer 不得对贴后图生效） |
| 粘贴语义 | `PasteSemantics.paste` | LightamerCore/Sources/Pipe/History/PasteSemantics.swift :69-180（overwrite/merge 双 mode；UUID recast :92-96；seed 回填 :139） | paste_adjustments 走 `.overwrite`（M2-8 OVERWRITE-paste epoch 既定语义） |
| 批量写 | `SessionBatchApplier.apply` 三段 | LightamerCore/Sources/Session/SessionBatchApplier.swift :232-296（compose 零渲染红线 :25-28；claim 单事务 :261-270；serial writer drain :286-290；**CarriedDocumentState 12 字段携带** :65-93 = V2M-01 先例） | paste_adjustments 批量腿 verbatim（relPaths 数组 + liveRelPaths 硬拒前置） |
| MCP 单图先例 | `apply_params` body | App/Sources/Lightamer/MCP/Tools/EditingToolset.swift :591-685（write gate McpRenderGate 串行 :605-607 → imageLiveInEditor 硬拒 :609-618 → rejectIfProjectReadOnly :621-623 → boundedWait `McpTimeouts.apply` :625-634 → SessionBatchApplier.apply 单 relPath `.overwrite` label "MCP apply_params" :666-672 → **flushForTeardown 写达后方返** :676-678） | paste_adjustments = 同框的数组版；「写达后方返」契约即同步形成立证 |
| MCP 批先例 | write-five registerOne | CullingToolset.swift :316-366（timeout→service→membership→probe→outcome JSON 五件套框；maxItems 1000） | relPaths 帽与超时档参照（applyBatch = 60s ≤1000，McpToolRegistry.swift :220） |
| 双形态寻址 | match_color resolveReference | MatchColorToolset.swift :549-602（digits = 库 id → LibraryStore.image → ImageLinker.resolve〔kind0/1/2〕；否则 = resolveMember session relPath） | copy source 两形态 verbatim 复用（OQ-M7-4-2 推荐） |
| 读面归属 | get_history | SearchStateToolset.swift :789-905（per-item 五键 + 顶层 note/keywords/rating/flag/colorLabel/**author 占位 .null** :899-900 注记「M7-4 (MCP2-09 commit attribution) fills this」） | per-item note/author 键 + 顶层 author 翻转 |
| HistoryItem | `HistoryStack.HistoryItem` | LightamerCore/Sources/Pipe/History/HistoryStack.swift :61-185（现七键 id/snapshot/label/timestamp/layerScope/stackSnapshot/pasteSet + drtRecord/filmRecord additive；**无 note/author**） | additive `note: String?` + `author: String?`（CodingKeys decodeIfPresent/encodeIfPresent 惯例） |
| hash 面 | HistoryHash | HistoryHash.swift :37-130（只折 enabled instances + layer identity/props/chain/mask；**item 元数据不入折**） | note/author 零 hash 漂移的机制证（负测仍补一法钉死） |
| GUI 显示面 | 历史行 | App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift :202-235（label + timestamp 行） | note 副标题（截断）+ author 徽章——验收「note/author 面板显示走查」落点 |

### §1.2 工具语义设计（无状态双动词）

**`copy_adjustments(source, includeParams?)` —— READ，readOnlyHint:true**

- source = 库 image id（digits）| open-session relPath（match_color 两形态 resolveReference
  同形；库 id 走 ImageLinker.resolve，stale = typed `notSessionMember` 携 reason）。
- 应答 = 枚举预览 JSON：`{source, versions[]（v7 版本行 + active 标记）, selectedVersion,
  grades[]（每 Grade 层 {id, name, chainCount, transferableCount, items[{instanceId, opName,
  multiPriority, enabled, transferable}]})，drt: {present, eligible} , summary}`——
  `isAdjustmentTransferable` 单谓词过滤，不可贴行 greyed 面（visible-not-silent，M2-8 头注纪律）。
- 不落任何服务端状态（无剪贴板 box）——agent 把 copy 应答当作 paste 的 `include` 参数源。

**`paste_adjustments(source, targets, note?, include?, includeDrt?, version?)` —— WRITE，
requiresWriter:true，destructiveHint**

- source 同 copy 两形态；targets = session relPaths 数组（**maxItems 1000**，与 write-five 帽
  一致；session 域判定见 OQ-M7-4-1）。
- 载荷 = 源链再枚举（无状态重读，非 copy 应答缓存）→ `include`（instanceId 列表，缺省 =
  全部 transferable）→ `AdjustmentTransferCatalog.buildPayload`（含 mask 纪元重置 + DRT 行
  `includeDrt` 默认 true）→ `PastePayload` 物化 → `SessionBatchApplier.apply(mode: .overwrite,
  label: "MCP paste_adjustments", seed: editingSeed 同源)`。
- per-target 前置：membership（requireMembers 同形）→ imageLiveInEditor **硬拒**（不是
  skip——MCP 无 interactive layer，「live 目标留给交互层」的 SessionBatchApplier 语义在
  MCP 帖面必须翻成 typed 拒，match_color attach 先例同判）→ projectWriteProbe。
- 应答 = per-target 结果列 `{targets: [{relPath, status: applied|rejected(reason)}],
  appliedCount, note, author}`（SessionBatchApplier outcome 三列 + typed 拒分账）。
- 超时档 = `McpTimeouts.applyBatch`（60s，既有档零改）；「写达后方返」契约 =
  flushForTeardown（apply_params :676-678 同款）——agent 的下一步 get_history/render_preview
  读到新状态，无 drain race。

**不引入 `list_tasks`/`wait_task` 的论证**：Alcedo tasks.wait 的触发条件 = paste 走后台任务
（「其余走后台任务、完成态列每图结果」）。我方 v1 同步形已成立（apply_params 先例 + compose
零渲染红线保证 claim 段耗时与目标数线性的小常数 + 60s 窗）；引入 tasks 面代价 = 两新工具
（union 27→31）+ 任务 tracker 基建（get_state.tasks 面已有 M2 导出队列投影，无通用 tracker）。
**推荐同步形；tasks 面挂 UPSTREAM-QUEUE 观察项**（万级目标批实测超窗才升级）。

### §1.3 note/attribution（MCP2-09）

1. **sidecar 面**：HistoryItem additive `note: String?` + `author: String?`——tolerant decode
   双向（旧 app 读新档忽略未知键；新 app 读旧档 decodeIfPresent 缺省 nil）；
   **schemaVersion 不动**（additive optional 先例 = DrtRecord/filmRecord；版本结构不进 hash
   的同族判断在此自动成立——HistoryHash 不折 item 元数据）。
2. **盖章面**：MCP 写工具（apply_params / paste_adjustments）写 commit 时
   author = `"mcp"`（固定 token；serverName/可变身份 = OQ-M7-4-4 备选），note = 参数透传
   （非空校验同 append_note minLength 1 形；缺省 = 无 note 字段不入 bytes——nil 不编码）。
   GUI 写腿零 diff（author 恒 nil = user 隐式，Alcedo「默认 user」语义的省略形）。
3. **读面**：get_history per-item dict 加 `"note"`/`"author"` 两键（缺省 .null）；顶层
   `author` 占位翻转为「position 位 item（最新 kept item）的 author」（推荐，OQ-M7-4-5）。
4. **GUI 显示面**：EditorToolRailView 历史行 = label + timestamp + **note 副标题（单行截断）+
   author 徽章**（"mcp" 显示为徽章文本；nil = 无徽章）。zh 键族 ≤2 尾块纯插入
   （author 徽章 AX label；note 无需键——原文字面直显）。VersionsPanelView 不触
   （版本级 author 悬置，OQ-M7-4-4 注记）。

### §1.4 writer 面 / 单写者锁交互

- requiresWriter:true（registry writer gate + writeCallCount 计数自动覆盖，McpToolRegistry
  :343-350）+ rejectIfProjectReadOnly（M6-1 probe；GUI held 时 typed projectReadOnly 携
  holderSummary——write-five :351-355 逐字同缝）。
- write gate（McpRenderGate 串行）：paste_adjustments 与 apply_params/match_color attach 互斥
  串行——M3-1-03 已登记「窗内并发 FULL 缺 denoise」风险的 coordinator 余量在此复用，
  不新增并发面。
- S3 顺路（挂账③）：McpProjectToolsetTests 差分谓词正臂补一腿——
  `makeGuiShapedProvider(stub:heldTargets:)`（:444-469 现成 stub 形）传非空 heldTargets，
  断言 `before==nil ∧ after!=nil ∧ store 未变 → typed projectReadOnly` 正臂可达；零产线代码。
  O1 同形复制漂移评估：复制体在测试桩内，抽 App 内可测 helper 消二份与 §1.1 枚举抽取
  同批权衡（能抽则抽，不能则漂移注记维持——plan 裁）。

### §1.5 快照 union 取权评估（红线①）

- 工具面 additive：editing 域 +2（copy/paste）→ **union `McpFinalSnapshotTests` 27→29
  显式改**（冻结表 +2 行 + 计数断言 ×4 + descriptionKeys +2 + 装配点零改——editing 域
  已注册）。apply_params schema 加 note = schema 字节变 → **editing 域层
  `McpRegistrySnapshotTests` 同批显式改**（render_preview 先例：两层 consciously change
  together）。
- 串行权：M7-4 在 M7-5 前执行 → 本波取权合法（M7-2/M7-3 同形先例）；**M7-4 持权窗口内
  禁并行派发 M7-5**（orchestrator 编排保证，VALIDATION 特殊事项 4 注记延续）。红窗纪律 =
  快照触碰只发生在工具落地 commit（cf49c046/3ef68910/bb6026f1 零快照触碰先例）。

---

## §2 S1 修复方案（M7-3 挂账①，修复批首项）

### §2.1 病灶与落点

- `App/Sources/Lightamer/MCP/McpServerController.swift` :388-408
  `armStdioEOFReleaseOnce(mode:)`——:396 `pollfd(fd: STDIN_FILENO, events: 0, revents: 0)`
  + :398 `poll(&fds, 1, -1)`。macOS 管道写端关闭后 `events: 0` 形永不唤醒（双路三层复现：
  C 探针 ≥12s/20s 不醒；`POLLIN` 形 0.38s/2.001s 醒 `revents = 0x11`；真产线二进制
  `--mcp-stdio` + project_create arm 后关 stdin 12s+ 不退，sample 卡 :398；归因
  `git log -S "events: 0"` = M6-1 `1f981f9b`，先前性钉死）。
- 后果：「agent 断连 → checkpoint 优雅释放」面（M6-1 KD-4/OQ-7/D-M7-3-7）实际惰性——
  断连后进程滞留持 flock，直到外力 kill（kill -9 = WAL 留待下次 open 回放 + kernel 锁释放，
  无 graceful checkpoint）。

### §2.2 修法形态（双路验收建议 + 研究补一处设计风险）

双路一致建议形（挂账①原文）：poll 改 `events: POLLIN` 请求；醒后按 `revents` 分流——
`revents & (POLLHUP|POLLERR)` → `takeStore()?.close()` + `exit(0)`；纯 POLLIN → 清位续
poll 不消费字节（保 M6-1「watches HUP without stealing bytes」原意图——请求读取线程独占
消费）。once guard / M1 mode 自守卫 / http 臂不 arm 语义全部零改。

**研究新发现（双路 ACCEPTANCE 未覆盖）**：「纯 POLLIN 清位续 poll」形在**恒可读 fd** 上
退化为忙旋——McpProjectToolsetTests setUpWithError 将 STDIN_FILENO dup2 /dev/null
（VALIDATION 特殊事项 5），/dev/null 的 poll 恒返 POLLIN → `poll(-1)` 立即醒 → 清位 →
立即再 poll = .utility QoS 满转空旋。两个消化形：

- **甲（推荐）**：bounded re-poll——`poll(&fds, 1, 250)` 超时形，醒后同分流；恒可读 fd
  退化 4Hz 低频循环（.utility 后台无害），真管道 HUP 语义不变（poll 阻塞至事件）。
- 乙：保持 `-1` 阻塞 + 测试面接受自旋（套件级短生命周期，卫生差）。

→ OQ-M7-4-7 裁决。**分流条件亲核**：HUP 判定保持 `revents & (POLLHUP|POLLERR)`（现体
:400 同式）；纯 POLLIN 分支**绝不清 events 位**（清位 = 只清 `fds[0].revents = 0`，现体
:403 同式——「清位」指 revents 非 events，措辞在 plan 里写实防误读）。

### §2.3 回归脚本复用形态

- **迁移源**：/tmp/m73_probe/（第二路验收遗产，VALIDATION 留痕 :98 标注「修复批取用时
  迁入仓内 evidence 面」）——现存 `probe.c`（最小 C 探针）/ `harness.c` + `harness.sh`
  （pipe/fork/exec events:0 vs POLLIN 对比）/ `e2edrv*.c`（真产线二进制驱动三轮）。
  迁移落点 = `phases/m7-4-mcp-o4/evidence/`（小件文本随 doc commit；若走 B 分仓政策则
  evidence 仓，plan 定）。
- **正式 e2e 测试形**（入 App 测试 bundle）：
  1. spawn 真产线二进制 `--mcp-stdio`（build-for-testing products 定位，第二路 E2E 先例）；
  2. initialize → `project_create`（arm watcher）；
  3. 关 stdin（真 EOF 断连面——McpProjectArbitrationTests 的 `child.terminate()` SIGTERM
     从未真跑 HUP，VALIDATION 特殊事项 5 注记此网 moot；本测试是第一个真 HUP 腿）；
  4. 活性断言：进程 ≤12s 退出（修复前此形 ≥12s 不退 = 已知失败形）；
  5. **checkpoint 断言**：`.lalb-wal` 文件 size == 0（close 的 TRUNCATE checkpoint 兑现证
     ——graceful face 的正面证据，kill 形不可能产生此状态）。
  6. 附：12s 窗内进程持有锁期间第二 `project_open` = typed projectReadOnly（graceful 面
     的锁语义侧写；可选腿）。
- **单元层**：watcher 循环分流逻辑若抽纯函数（revents → action 三值函数）可单测零进程；
  或维持内联 + e2e 承载（现体 20 行，抽函数属 plan 权衡）。

### §2.4 波及面（checkpoint 优雅释放首次真正生效）

1. **措辞校订两处**（挂账⑥ + S1 修复批同批）：M7-3 DECISIONS H3③「checkpoint 优雅面仅
   stdio」——修后 stdio 优雅面**成真**（此前双臂皆惰性：http = kernel 地板、stdio = watcher
   惰性）；VALIDATION 挂账⑥「http-absence 偏离 + 双臂不对称」注记同批复核——修后不对称
   变为「stdio graceful / http kernel-floor」的**真实**差异（不再是「都惰性」的措辞高估）。
2. **VALIDATION 特殊事项 5 dup2 卫生**：修后**仍必要且更 load-bearing**——无 dup2 时测试
   宿主真 stdin 的关闭会真触发 exit(0) 自噬测试进程；有 dup2 + 甲形 bounded re-poll =
   4Hz 循环不自噬不忙旋。S1 修复批同批复核该 setUp 注记措辞。
3. **GUI 臂零变化**：armStdioEOFReleaseOnce 的 M1 自守卫（`mode == .stdio` gate + 内部
   再检）原样保留——http daemon stdin 可能已闭、GUI 嵌入臂 stdin 非管道，一律不 arm。
4. **http 臂零变化**：挂账⑥ kernel 地板语义维持（进程退出 = 锁释放地板）。
5. **运行面正向变化**：agent 断连 → checkpoint（WAL TRUNCATE）+ flock 释放 + exit(0)——
   下一 agent 立即可开项目；此前僵尸进程持锁须外力 kill。M2-2 WAL 纪律（synchronous=
   NORMAL + close TRUNCATE）在此首次被断连路径真实兑现。

---

## §3 S2 三选一测绘（M7-3 挂账②裁决输入）

### §3.1 机制现状（精确链）

- `LutLibraryStore.shared`（LightamerIOP/Sources/Lut3d/LutLibraryStore.swift :105-116）=
  `static var sharedInstance = LutLibraryStore()`——**首次访问触发 swift_once init**：
  init → 默认根分支 `seedBuiltIns`（:225-231，内置 40 张拷入 BuiltIn/）→ `rescan()`（:232）
  → 逐文件 parse-cache miss 即解析（:244-257）。40 × 65³ .cube 纯 CPU 解析 ≈ 50s
  （第二路实测冷进程首调 list_luts 应答 50.2s；sample 栈亲证 dispatch_once → rescan →
  CubeLutParser.parse；非死锁，长解析）。
- **两臂皆无 launch 预热**（grep warm/preheat/预热 零命中）：GUI 臂靠首次打开 LUT 面板
  （LutPanelView :39/:279 `LutLibraryStore.shared`）摊销——交互式宿主一次性延迟可容忍；
  **stdio agent 臂独吃**（首调 list_luts = 50s；EditingToolset :176 直读）。
- 超时救援不可能：`McpCullingToolset.withTimeout` v1「stuck body blocks」形（任务组 scope
  退出 await loser，CullingToolset :208-226）——不响应取消的 CPU body 使 10s 超时错误在
  race 里永远赢不了（`McpTimeouts.list` = 10s，McpToolRegistry.swift :216——声明窗被
  实际应答时长决定）。
- 测试盲区机制：golden 用 `replaceShared` 注入小 store（testListLutsGoldenSeededProjection）
  不触默认根全库解析——套件全绿与 50s 现实无交集。

### §3.2 三选项量级与副作用

| 选项 | 改动量级 | 效果 | 副作用 / 风险 |
|---|---|---|---|
| **A 宿主启动后台预热** | ~10 行 × 2-3 装配点（GUI 装配 + 无头 stdio/http writer 臂 start 各一 `Task.detached(priority: .utility) { _ = LutLibraryStore.shared }`） | 预热完成后首调即答（<10ms）；agent 首调通常在进程启动数秒后——窗口概率性收窄至启动邻域 | 预热窗内（~50s）到达的首调仍阻塞在 swift_once（至多 50s）——**概率性非确定性消除**；启动期 +50s 后台 CPU（.utility 让位渲染；GUI 机与其它启动工作并发，实测无感面待走查） |
| **B 解析协作化挂起** | 中大：CubeLutParser 循环取消检查（per-file yield/isCancelled）+ withTimeout v2 abandon 形（detached + continuation race，per-call-site 不动 v1 全族）+ 局部 parse-cache 续跑语义 | 10s 超时错误**真实兑现**；body 后台续跑/中止；重试续跑 | withTimeout 语义族风险（~20 工具共用，须严格 per-call-site）；abandoned task 资源语义（caller 放弃后 CPU 仍耗）；局部缓存并发面；**越出顺路波面** |
| **C 文案如实化** | ~5 行（list_luts description 注记冷首调代价 +（可选支线）`McpTimeouts` **新增** `listLuts` 档 60s——新档非改档） | 诚实声明；长超时客户端（60s+）无感 | 短超时客户端（30-60s 常见档）仍会误杀——**真实痛点不消**；新档支线须晨审显式裁决（红线⑥：既有档值零改不含「新增档」，但 M7-3 红线「McpTimeouts 零 diff 零新档」为该波机检，本波新增 = 显式申报形） |

### §3.3 推荐排序

**A + C 组合（推荐）**：预热消真实痛点（agent 视角首调即答），文案盖残余窗口（预热窗内
首调 + 文档诚实）；合计 ~15 行，零语义族风险。**B 不推荐**：withTimeout v2 是独立专项
（挂 UPSTREAM-QUEUE / M7-5+ 候选），顺路波不承载。裁决前禁改既有档值（CONTEXT
D-M7-2-3 红线延续）；C 的「新档」支线若行使 = OQ-M7-4-8 显式裁决项。

---

## §4 UQ-A2 导出 FAIL 档终写原子不覆盖

### §4.1 现状 TOCTOU 窗（精确）

- `.fail` 现语义 = **快照检查**：renderStage 步 9 name（ExportRenderer.swift :625-638）调
  `ExportNamer.destinationURL(collisionPolicy: .fail)`（ExportNamer.swift :133-137）——
  occupiedNames 集合 = 队列在 job 开头的目录枚举快照（ExportQueue.swift :470-477
  `occupiedNamesProvider` + :743-751 defaultOccupiedNames 含 dot files）；命中即抛
  `BaseNameOccupiedError`（job fail typed）。
- **终写 = 覆盖语义**：encodeStage（:655-782）→ encoder in-memory encode → `.atomic`
  rename（L009）——Darwin rename **无条件替换**已存在目标；gain-map 臂
 （:683-706 ExportGainMapEncoder）同形直写 destination。
- **TOCTOU 窗** = 快照枚举（job 开头）与 rename（encode 尾）之间他进程/他 job 建同名文件
  → 被静默覆盖。`.fail` 的契约（Alcedo FAIL = loud failure）在此窗内失效。
- 上游正主 = Alcedo `6203791`（FAIL 不覆盖）：macOS `renameatx_np(RENAME_EXCL)` /
  Linux `renameat2(RENAME_NOREPLACE)` / 其他 POSIX `link()+unlink()`；EEXIST →
  "output file already exists"；**删除了独立 exists() 检查**；REPLACE 保持 plain rename。

### §4.2 修法落点（tmp 同目录 encode + `link()` EEXIST 拒晋升）

1. **encodeStage additive 参数** `exclusiveFinalWrite: Bool = false`（:655 签名尾追，缺省 =
   既有调用方零 diff）。true 时：
   - encode 目标改 **同目录隐藏 tmp**（`.<name>.<uuid>.tmp`——同目录 = 同卷，link() 跨卷
     EXDEV 消解于构造）；
   - post-encode 两腿（ICC strip :744-758 / XMP mount :761-777）在 tmp 上原位跑（文件内
     操作，与目标无关）；
   - 晋升 = `link(tmpPath, destPath)`：**成功** → `unlink(tmp)`（双链接收敛单链接）；
     **EEXIST** → `unlink(tmp)` + 抛 typed（复用 `BaseNameOccupiedError(name:)`，表面一致
     ——OQ-M7-4-9）；其它 errno → internalError 形（16 档封闭表零新增）；
   - gain-map 臂同 wrap（其 post-encode 腿本就跳过，tmp+link 直包 ExportGainMapEncoder
     的 destination 形参即可）。
2. **policy 到 encode leg 的递缝**：encode leg（ExportQueue productionLegs :710-732）不持
   policy——**naming carrier 已有 collisionPolicy 字段**（ExportRenderer.ExportNamingCarrier
   :131-155）；queue 的 encode-leg 调用点（:521-528）加一层 `$jobNamingCarrier
   .withValue(namingCarrier)` additive wrapper（`$jobExifSoftware` 同款纪律——AGENTS
   M2-9「递缝三件套」范式第四例），encodeLeg 内读
   `ExportRenderer.jobNamingCarrier?.collisionPolicy == .fail` 传参。contract-frozen leg
   签名零 diff。直连 renderStage+encodeStage 的测试/E2E 调用方显式传参。
3. **保留 render 步快照检查（与上游唯一分歧，理由在案）**：上游 6203791 删除 exists()
   检查因其紧贴 rename（同一 commit 函数内冗余）；我方快照检查在**渲染前**—— doomed
   job 免付一次全渲染成本（100MP 渲染秒级），是成本门非正确性门。正确性门 =
   link() EEXIST。分歧写进 DECISIONS。
4. **零触面**：ExportNamer.swift 零 diff（命名逻辑不动）；ExportCollisionPolicy 三档枚举
   零动；`.replace` 保持覆盖（plain rename 语义 = 上游同判）；`.increment` 字节冻结；
   UI/ExportInspectorView 零触；schema 零触。

### §4.3 测试形态（验收形态③「TOCTOU 负测：并发建文件不被覆盖」的可判定化）

真并发竞速不可判定（时序非确定）；**确定性交错点** = queue 的 render→encode 边界
（gate ③，ExportQueue.swift :510-516——渲染产物在此丢弃或移交 encode，正是快照与终写
之间的自然缝）：

1. **TOCTOU 负测**（Core 级确定性）：renderStage（name 已解析，destination 落在
   StageOutput）→ **手工在 destination 建文件**（交错注入）→ encodeStage(
   exclusiveFinalWrite: true) → 断言 typed 错误 + **destination 字节不变**（预植内容
   byte-compare）+ 目录无 tmp 残留（glob 断言）。
2. **正向恒等**：exclusive 形与非 exclusive 形写同平面 → 产物字节逐位一致（exclusive 只
   改晋升方式不改产物）。
3. **`.replace` 负面守卫**：目标存在 + replace 档 → 覆盖仍发生（exclusiveFinalWrite=false
   路径，负测钉住不误伤）。
4. **`.increment` 字节冻结**：既有 E2E increment face 不动（既有测试即守卫，零新增）。
5. **queue 级腿**（可选）：.fail job + occupiedNamesProvider 返回空集但文件在 encode 前真建
   → job typed fail 无覆盖（走真 queue 腿验证 wrapper 递缝成立）。
6. **gain-map 臂**（可选，M6-3 fixture 就绪度由 plan 定）：同形 1 的 gain-map 变体。

---

## §5 match_color projectDirectory 勘正（M7-2 挂账⑤顺路）

- **病灶**：GUI 装配点 App/Sources/Lightamer/UI/LightamerApp.swift :1364-1372——
  `MatchColorToolset.installLibraryProvider` 传 `url = libraryProjects.projectURL`
  （**.lalb 文件 URL**）充作 projectDirectory。ImageLinker.resolve kind0 臂
  （ImageLinker.swift :152-156）`projectDirectory.appendingPathComponent(imagePath)` →
  文件 URL 锚产出坏路径；kind1 快路径的 volumeUUID(of:)/volumeRoot(of:) 同病。未爆 =
  match_color golden 走 absolute kind 行（McpMatchColorToolsetTests :177/:402 两 provider
  传 packageURL 同病）；M7-2 fix `20997721` 已勘正 searchState 两装配点
  （`url.deletingLastPathComponent()` 目录锚，WorkspaceHostView urlResolver 先例形）。
- **修法**：GUI 装配点一行（`:1371` return 行改目录锚）+ 两测试 provider 同形勘正 +
  **新 kind0 腿测试**：库种行（imagePath = `Media/x.jpg`, pathKind = 0）→ id 形 resolve →
  resolved URL == `<projectDir>/Media/x.jpg`（锚正确性正面证据——absolute kind 永远抓不到
  此病，这是 T5 golden 抓获 20997721 的同族教训）。
- **顺路判定 = YES 本波**：O4 copy source 的库 id 形态（OQ-M7-4-2 推荐）骑同一 provider
  面——同一缝两波触碰 = churn；且本波触碰后 kind0/id 行正式进入 MCP 写面路径，
  勘正是写面前的卫生前提。
- **headless 臂注记**：match_color provider 无头臂未装配（id 形 = typed notSessionMember
  诚实臂，`--project` 有开库但 provider 缺席——现行为如实维持，不在本波扩；O4 的 headless
  可用性随 OQ-M7-4-1 域判定走）。

---

## §6 测试策略与 ΔN 估算

| 域 | 测试腿 | 估算 |
|---|---|---|
| O4 copy | 枚举 golden（同链 → GUI model pastePayload 与 MCP 纯 helper 产物实例集逐参恒等——「no second copy」红线机检正面）+ 两形态寻址（库 id kind0/绝对 + session relPath）+ 不可贴 greyed 计数 + DRT present 面 | ~4 |
| O4 paste | per-target applied/rejected 分账 + live 硬拒 + probe held 拒 + membership 拒 + include 子集 + includeDrt=false + mask 纪元重置断言（贴后 contentRevision == nil）+ label "MCP paste_adjustments" 进 HistoryItem + flush 写达后方返 | ~6 |
| MCP2-09 | note/author round-trip（sidecar 字节 + tolerant 旧档 decode 负测）+ **HistoryHash 不变负测**（同编辑态 note/author 有无 → hash 逐位同）+ get_history per-item 键 + 顶层 author 翻转 | ~4 |
| S1 | e2e 真断连（真二进制 + 真 EOF + 12s 活性窗 + WAL==0 checkpoint 断言）+（可选）分流纯函数单测 | ~2 |
| S2 | 预热探针（env 门，修后 list_luts 冷窗收敛观察项；非门值）| ~1 |
| S3 | heldTargets 非空正臂腿（零产线代码） | ~1 |
| UQ-A2 | §4.3 六腿（1-4 必做） | ~4 |
| match_color | kind0 锚腿 + provider 勘正后两测试 provider 绿 | ~2 |
| 快照 | union 27→29 显式改 + editing 域层 schema 行显式改（apply_params note 参数）——非新测试，显式改批 | 0 |

**ΔN 预估 +22..28**（S1 e2e 进程腿与 S2 探针有 env/稳定性门风险，plan 期按 bundle 归域
规则落 BUNDLE-MAP 同批登记 + tuist generate 恒末位）。

**S3/O1 抽取权衡**（挂账③附注）：§1.1 枚举/载荷纯 helper 抽取（AdjustmentTransferCatalog）
消 GUI model 与 MCP toolset 二份——与「no second copy」头注红线同向；抽取幅度（全量 vs
仅 payload 构建）plan 期定，GUI model 行为零 diff 门（M2-8 既有测试面作守卫）。

---

## §7 OQ-M7-4-1..10 清单（带推荐；station auto-advance 按推荐行使，晨审可推翻）

| # | 问题 | 选项 | 推荐 |
|---|---|---|---|
| OQ-M7-4-1 | paste targets 域归属 | ①session relPaths（与全部 MCP 写工具一致；headless = 诚实 notSessionMember）②库 id（需库域写投影设计——.lalb 无 claim 面，sidecar 直写 + 投影刷新缺口）③双形态 | **①**（session 域；库域批量挂 UPSTREAM-QUEUE 观察项） |
| OQ-M7-4-2 | copy source 形态 | ①库 id + session relPath 双形态（match_color resolveReference verbatim）②仅 session relPath ③加 editor-current 哨兵 | **①**（双形态只读面廉价且与读工具一致；哨兵不推荐——显式 > 隐式，D5） |
| OQ-M7-4-3 | 两动词形态 | ①无状态双动词（copy=只读枚举预览 + paste=source+targets 一次性，无剪贴板）②服务端剪贴板 token | **①**（无状态纪律 + 多客户端交错安全 + Alcedo items 面并入 copy 应答） |
| OQ-M7-4-4 | author 盖章值 | ①固定 `"mcp"` ②serverName ③可变 agent 身份参数 | **①**（固定 token 最小面；版本级 author 悬置不触 VersionsPanelView） |
| OQ-M7-4-5 | get_history 顶层 author 语义 | ①= 最新 kept item 的 author ②恒 null 保留占位 ③删键 | **①**（M7-2 占位注记「M7-4 fills this」兑现；删键破 pristine 形状一致性） |
| OQ-M7-4-6 | paste 是否 per-target 建版本（Alcedo e75cf2a 同构） | ①v1 不建（OVERWRITE epoch 既定语义，label 可自查）②建（每目标 +1 版本行，预贴态隔离） | **①**（既有语义零新面；②挂 UPSTREAM-QUEUE 观察项） |
| OQ-M7-4-7 | S1 poll 循环形态 | ①bounded re-poll 250ms（/dev/null 忙旋消解，HUP 语义不变）②-1 阻塞 + 测试面接受自旋 | **①**（研究 §2.2 新发现；250ms 窗对 12s 活性断言无影响） |
| OQ-M7-4-8 | S2 裁决 | ①A 预热 + C 文案 ②单 C ③B 协作化；C 支线新 `McpTimeouts.listLuts` 档与否 | **①**（A+C，不推荐 B；新档支线随 ① 一并裁决——行使则显式申报） |
| OQ-M7-4-9 | UQ-A2 typed 错误面 | ①复用 `BaseNameOccupiedError` ②新 typed case（错误码表新增面） | **①**（表面一致 + 错误码 16 档封闭表零新增红线） |
| OQ-M7-4-10 | includeDrt / include 默认面 | ①DRT 默认随行 + includeDrt:false opt-out + include 缺省全 transferable ②DRT 默认不随 + includeDrt:true opt-in | **①**（GUI「默认全选可贴 + DRT 默认勾」语义镜像） |

**FIX2③ 默认不承载维持注记**（GOAL-STATE 输入清单④延续）：修法落点
LibraryProjectController 尾部，本波 design 不触该文件——controller 零 diff 门连续第三波
兑现；若执行期行使须显式申报。

---

## §8 留痕

- 本文件 = M7-4 research 正本；doc-only commit（全英文 message；不 push）。
- 台账同批：TODO M7-4 行（research ✅ 起草注记）+ GOAL-STATE 续接点注记。
- 探针遗产指针：/tmp/m73_probe/（S1 回归迁移源，§2.3）——plan 执行批取用时迁入
  `phases/m7-4-mcp-o4/evidence/` 或 evidence 仓（政策 B 由 plan 定）。
- 上游对表 commit：Alcedo `6203791`（FAIL 不覆盖）/ `e75cf2a`（adjustments copy/paste）/
  `9f9fc5e`（目标 Grade 默认值保留）/ `1f12551`（输出防覆盖）——GPL 只读语义对表，
  代码零复制。

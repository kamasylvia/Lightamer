# Plan 14-3 — 筛选面（W2b）执行 SUMMARY

**Executor:** ZCode executor subagent worker · **Date:** 2026-09-28
**Plan:** `.work/gsd/phases/14-mcp-server/14-3-PLAN.md`（W2b，与 14-2 并行）
**Status:** 完成（6 tasks / 6 commits，未 push；2026-09-28 独立验收 PASS-with-notes，
验收修正随文末节）

## 任务表与提交

| Task | 内容 | Commit | 证据 |
|---|---|---|---|
| T1 | 真人像 landmark 补测（R5 关闭）+ `PhotoProjection` 25 列投影 + list_photos（FilterSQL 直连 + keyset 游标 + 谓词往返） | `2e24a21` | 补测数字见下；投影冻结/往返/游标/invalidFilter 矩阵 10/0 |
| T2 | 写五件（MetadataService 单源）+ GUI 联动走查 + preset 三件套（D8 软跳） | `0f14d30` | 写回三断言 parity + live 软跳/claim 不动负例 + preset 三件 19/0 |
| T3 | 图像三件套（双档直读/stale 三态/CG 联系表/ROI 裁剪）+ `McpImageBudget` 上限表落码 | `370b184` | budget verbatim 测试 + CJK 标注条 glyph 门 + 像素采样 + stale 计数腿 25/0（12 工具快照） |
| T4 | list_bursts（2.0s+camera_model 聚类 + StableHash id）+ get_face_regions（Vision 直发 + 像素框换算） | `7050a4b` | 聚类 golden + 换算逐值 + 空数组负例（真 Vision 跑）22/0（14 工具快照齐） |
| T5 | SC#5/SC#6 筛选端到端（InMemoryTransport 第三宿主形态） | `5d37d0b` | 两链绿 + 写回三断言 + MCP-08 封闭集证明 + 预算对账 25/0 |
| T6 | 全量回归 + 本文档 + DECISIONS + TODO/PROGRESS | 本提交 | 终轮计数见下 |

另：Core 加法缝一处——`SessionIndexStore.query(extraPredicate:)`（keyset 游标谓词的
调用点拼装位，默认 nil 既有调用者字节不变；FilterSQL 零触碰）随 T1 提交。

## 真人像 landmark 补测（探针局限①收口，R5 关闭）

- 样张来源：本机 ~/Downloads 8 张真实人像（2699×1518 ×7 + 1279×1919 ×1，每张 1 脸）；
  一次性 Swift 脚本 /tmp 即弃，图片字节零入库（L009）。
- 实测（warm 串行 3 轮均值）：**检测主干（faceRectangles）4.83ms/图；landmarks
  （检测+精化）2.23ms/图——精化增量 ≤ 0**（landmarks 路径主干共享/排队差异）。
- 结论：架构不受影响（per-request 不缓存裁决维持）；成本模型「~4ms/图」量级成立
  （research 无脸探针 3.9ms 同量级），工具描述保留该标注。

## 预算对账（research §RQ-14-8 注脚，SC#5 实测）

- get_thumbnails：3 张实测 **16,335B**（合成渐变 JPEG 极小；20 张/请求预算 ~730KB
  由上限常量 + 测试界 <800KB 钉住）。
- get_contact_sheet：2×2 网格 3 cell 实测 **18,612B** base64（上限 2MB，服务端
  强制断言在 handler 内）。
- 上限表落码：`McpImageBudget` 一处常量 + 逐值 verbatim 测试（含 render_preview
  四常量 1024/85/2048/90——14-2 并行已先落同值常量，14-4 收口统一消费位，见
  DECISIONS D-14-3-T3-1）。

## GUI 联动走查结论（R7）

- 自动化钉死：MCP 写 → claim 事务 → lindex 行即时更新 → 网格/过滤面的 query face
  立即可见（SC#5 写回三断言）。
- **编辑器当前打开图的 inspector 行不跟随**（claim 面不推 GUI 状态对象——inspector
  数据源是编辑器内存 doc，属单源汇合语义的预期行为）：R7 处置位（通知缝或刷新钩子
  小改）登记 **14-4 收口批**评估，本 plan 不扩面。

## 交织与并行纪律

- 与 14-2 并行共享 `App/Sources/Lightamer/MCP/` 目录：本 plan 提交均为文件级 add，
  14-2 的未提交 WIP（EditingToolset.swift 等）零触碰；共享装配
  McpServerController.swift 曾缺 `import LightamerIOP`（14-2 中间态），补一行使其
  可编译——该行留在共享文件随 14-2 后续提交走，未入本 plan 提交。
- 14-2 提交 0062575 引用了其未落盘的 `Seams.yiyinInjector`（他们快速迭代中的中间
  态），主工作区一度编译不过——本 plan 每任务边界构建与终轮全套在 **/tmp git
  worktree**（HEAD + 本 plan 申报文件；共享装配两文件回退 37add39 绕开其未收敛
  引用——worktree 私有不提交）内完成（D-14-3-T6-1）。
- `McpJSON.boolValue`：本 plan PhotoProjection 的重复声明已删除；HEAD 的共享
  McpToolRegistry 尚无该访问器（在 14-2 未提交 WIP 内），本 plan 提交面亦无消费方
  ——`get_thumbnails` 的 regenerate 参数以 pattern match 解析（不依赖对方访问器
  时序）。（原句「改为消费共享版」经 14-3 独立验收校正——HEAD 状态与其不符。）

## 分层/域自证

```
$ grep -rn "FilterDomain" App/Sources/Lightamer/MCP/        # 零命中（exit 1）
$ grep -rn "^import MCP\|^import NIO" \
    App/Sources/Lightamer/MCP/Tools/                        # 零命中（registry 缝纪律延伸到工具层）
```

- v1 求值域恒当前会话：工具 schema 无 domain 参数（快照钉死）；无会话 = typed
  `notSessionMember`（"no open session…"）。
- 万张级零像素渲染：list_photos/list_bursts 纯查询（PERF-07 语义）；测试断言 burst
  链零解码。

## 回归

- 基线口径：14-1 收口 1794/11skip/0fail；0062575（14-2 T1）合并 HEAD + 本 plan
  新增 = 终轮基线。
- 本 plan 新增测试：culling 快照/投影/游标/写面/preset/burst/脸框/SC#5/SC#6 =
  **25**（McpCullingToolsetTests）+ **6**（McpCullingImageBudgetTests）= 31。
- 终轮实测：见 PROGRESS.log 追加行（worktree 全套 caffeinate -dis
  Scripts/test-direct.sh）。
- 在案 flake（LayerE2E/ToneEqual/QuickLook 计时类）未现身/按归因条款单列。

## 交付物清单（files_modified 对照）

- `App/Sources/Lightamer/MCP/Tools/CullingToolset.swift` ✓（14 工具装配 + context
  + McpImageBudget + 纯换算函数 + 超时 helper）
- `App/Sources/Lightamer/MCP/Tools/PhotoProjection.swift` ✓（25 列投影一处拼装 +
  FilterPredicateGroup 直作 + 游标编解码 + McpJSONSerialization + McpJSON 便利
  访问器〔boolValue 归共享版〕）
- `LightamerCore/Sources/Session/SessionIndexStore.swift` ✓（query 加法参数
  extraPredicate + ExtraPredicate 结构）
- `Tests/LightamerTests/McpCullingToolsetTests.swift` ✓（25 测试：快照段随任务演进
  1→9→12→14）
- `Tests/LightamerTests/McpCullingImageBudgetTests.swift` ✓（6 测试）
- 本文档 / `14-3-DECISIONS.md`（15 条 + 验收 2 条）/ TODO.md / PROGRESS.log ✓

## 独立验收（2026-09-28，ZCode acceptance subagent，零共享上下文）

- **结论:PASS-with-notes**。复跑（/tmp git worktree 隔离，配方见 D-14-3-ACC-2）:
  `McpCullingToolsetTests` **27/0**（executor 25 + 验收新增 2）+
  `McpCullingImageBudgetTests` **6/0**；全套 **1836 tests / 89 skipped / 0 failures
  （474.7s）**——与 executor 申报 1834/89skip/0fail 严格对账（+2 = 验收新增测试，
  skip 同额）。
- **验收修正（fix(14-3) 提交，test-first）**:list_photos 游标两处逻辑缺陷——
  ①值类谓词缺 `OR (k IS NULL)` 桥（NULL 双向排尾；页边界恰落在最后一个非 NULL
  行时 NULL 尾不可达、短页伪造耗尽）；②`cursorValue(.scanEpoch)` 恒 `.null`
  （合法排序键 scanEpoch 翻页自第二页起静默截断）。修复前两新测试红（27 tests /
  2 failures，executor 25 全绿）→修复→27/0 绿。详见 D-14-3-ACC-1。
- **文档勘误**:状态行「5 tasks / 5 commits」实为 6；「boolValue 改为消费共享版」
  与 HEAD 不符（见上校正）；D-14-3-T6-1 worktree 配方不可编译（ACC-2 勘误）。
  另注:list_bursts golden 的「2.0s gap stays」注释未实际钉 2.0 边界对
  （gap-ok→gap-cut 为 2.1s cut；2.0 含边界由代码 `<=` 承载），留 14-4 顺带补钉。

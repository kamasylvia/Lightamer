---
phase: 14
plan: "14-3"
title: "筛选面（W2b，与 14-2 并行）：真人像 landmark 补测（R5）+ list_photos（FilterSQL 直连零新翻译层 + 22 列投影 + keyset 游标 + 谓词往返）+ 写五件（MetadataService 单源 + GUI 联动走查）+ preset 三件套（live 软跳 D8）+ 图像三件套（双档直读/stale/CG 联系表/ROI 裁剪 + base64 上限表）+ list_bursts + get_face_regions + SC#5/6 筛选端到端"
wave: 2
depends_on: ["14-1"]
autonomous: true
requirements: [MCP-05, MCP-06, MCP-07, MCP-08, MCP-09]
files_modified:
  - App/Sources/Lightamer/MCP/Tools/CullingToolset.swift             # 新建：筛选面 14 工具 handler 装配（list_photos/get_thumbnails/get_contact_sheet/get_detail_crop/list_bursts/get_face_regions/写五件/preset 三件套）——纯 Swift，消费 Core 既有面
  - App/Sources/Lightamer/MCP/Tools/PhotoProjection.swift            # 新建：SessionIndexRow → MCP dict 22 列显式投影表（§RQ-14-7③ 一处拼装）+ FilterPredicateGroup JSON ↔ 入参映射 + keyset 游标编解码
  - Tests/LightamerTests/McpCullingToolsetTests.swift                # 新建：culling 域快照（14 工具）+ 22 列投影冻结 + 谓词往返 + 游标分页 + 写五件联动 parity + live-target 负例 + burst/联系表/ROI/脸框断言
  - Tests/LightamerTests/McpCullingImageBudgetTests.swift            # 新建：base64 上限表落码断言（四工具默认/上限）+ 联系表 CG 拼图（中文 fixture R9）+ stale 语义
  - .work/gsd/phases/14-mcp-server/14-3-SUMMARY.md
  - .work/gsd/phases/14-mcp-server/14-3-DECISIONS.md
  - TODO.md                                                         # 14-3 勾选
  - LESSONS.md                                                      # 如踩坑
---

# Plan 14-3 — 筛选面（W2b，与 14-2 并行）

> 背景：SC#5/6 主体（D-14-CONTEXT-8）。四个「复用黑体」全部有具名落点，本 plan 是接线：
> ① **list_photos = FilterSQL 直连零新翻译层**（12 移交③字面兑现）——`FilterPredicateGroup`
> JSON 直作入参（Codable 已持久化就绪）→ `FilterSQL.translateConjoining` + 
> `SessionIndexStore.query` 消费；**v1 求值域恒当前会话**（`FilterDomain.session`，D-14-CONTEXT-9：
> 16 期字面 defer，domain 缝留而不接——inputSchema 不暴露 domain 参数）；返回 = 22 列投影
> （34 列逐列裁决终表，frozen spelling 零改动）+ keyset 游标（16 期 RQ-16-6 同源形状，追加
> 谓词拼在 query 调用点，**不触碰 FilterSQL**）；② **写五件 = MetadataService 单源汇合**
> （GUI/MCP 同一入口，结构性无险）+ claim 面 live-target 保护既有；③ **图像三件套** =
> 双档缩略直读（09 期 appointment 语义）+ 纯 CG 联系表拼图（无管线风险）+ RAWDecoder ROI
> 裁剪；④ **burst/脸框** = 查询层聚类 + Vision 直发（SkinRegionLocator 不硬套——脸框工具
> 只取 boundingBox，per-request 不缓存，3.9ms/图探针在案）。
> **D8 钉板（本 plan 半边）**：apply_preset 的 GUI-live 处理 = `PresetApplier` 既有
> `liveRelPaths` skip 机制 → live 图进 `skippedRelPaths` **报告面软跳**（不报错不阻塞批量）
> ——与 14-2 apply_params 单图硬拒不同，两语义各有测试负例。
> 内部任务序刚性：T1（补测+list_photos）→ T2（写面）→ T3（图像三件套）→ T4（burst/脸框）
> → T5（端到端）。与 14-2 并行纪律见下。

## read_first

1. `.work/gsd/phases/14-mcp-server/14-RESEARCH.md`——§RQ-14-7（**本 plan 正本**：入参形状/
   keyset 游标/不返回总数裁决/**22 列投影终表**[暴露 22/不暴露 12 逐列]）、§RQ-14-9（burst
   聚类键 2.0s+camera_model/查询形状/`burst-<首图path-hash8>` id/singles）、§RQ-14-10
   （Vision 直发/boundingBox 换算/3.9ms 成本/空数组=无脸/relPaths≤20/per-request 不缓存）、
   §RQ-14-8（get_thumbnails 双档/stale 语义/get_contact_sheet 256 q80 ≤30 格 24px 标注条
   ≤2MB/get_detail_crop ROI 上限 1536）、§RQ-14-3③⑥（只读降级消费/GUI 可见性联动走查项
   [inspector 行跟随 R7]）、§A 工具表 #5-10+11-15+16-18、§C 风险 R5/R7/R8/R9
2. `.work/gsd/phases/14-mcp-server/14-CONTEXT.md`——D-14-CONTEXT-8（筛选面落位四复用黑体）、
   D-14-CONTEXT-9（Catalogs defer——v1 恒会话域，domain 不暴露）、D-14-CONTEXT-5①（元数据
   单源）、D-14-CONTEXT-4（inline 上限表）+ 继承定案（FilterSQL 单一翻译面禁第二层/批量
   事务纪律 one bulk change = one transaction/万张级零像素渲染 PERF-07 语义）+ 验证红线
   （写回联动 parity/批量三段回归/live-target 负例/双宿主一致性）
3. `LightamerCore/Sources/Session/FilterPredicate.swift`：FilterPredicateGroup Codable
   （:212-266）+ `FilterField` 16 字段白名单（:54-71 全暴露）+ `FilterOp` 12 op（:76-89）+
   `legalOps`/`legalValueKinds` 合法性矩阵（:274-314 → `invalidFilter` 映射）
4. `LightamerCore/Sources/Session/FilterSQL.swift`：排序白名单 `FilterSortKey` 六键（:56）/
   `translateConjoining`（:160）+ **FilterDomain 缝（:135-137——留而不接，v1 恒 .session，
   零改动自证）**；`LightamerCore/Sources/Session/SessionIndexStore.swift`：query 消费面
   （:561-584——追加游标谓词的拼装位）/ `claimMetadataApply`（:1177，live-target 既有保护）
5. `LightamerCore/Sources/Session/MetadataService.swift`：六 API（:81/:91/:100/:117/:128/
   :141——set_keywords :117-124 整组替换语义 + `|` 分隔符校验）；`SessionBatchApplier.swift`
   + `BatchSidecarWriter.swift`（三段管线）；`LightamerCore/Sources/Presets/PresetApplier.swift`
   （:10-32 + **live targets skip（:92）**——apply_preset 软跳[D8]）/ `PresetsStore.swift`
   （:73/:200 清单面）
6. `LightamerCore/Sources/Session/SessionThumbnailProvider.swift`：tier appointment + 
   has_edits 裁决红线（:43-50）；`ThumbnailDiskStore.swift:75`（read 直读）+
   `SessionIndexSchema.swift`：`thumb_state`（:76）/`has_edits`（:84）/34 列 frozen spelling
   （:66-102——22 列投影的源；13 期 frozen-spelling 契约跨进程延伸，列改动须过 frozen 断言）
7. `LightamerIOP/Sources/SkinSmooth/SkinRegionLocator.swift:12`（Vision 基建对照——**不硬套**
   ，get_face_regions 直发 `VNDetectFaceLandmarksRequest`）；`LightamerCore/Sources/Decode/`
   RAWDecoder 面（detail crop 解码腿）
8. `LESSONS.md` L009/L013/L020（失败语义同源）/L025 + `AGENTS.md` + `.work/GOAL-STATE.md`
   （Phase 14 续接点）+ `.work/gsd/phases/14-mcp-server/14-1-SUMMARY.md`（若已落——registry
   缝/serverReadOnly 钩子消费形态）

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits，英文 message，只 add 本任务申报
   文件）；**不 push**。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建（`xcodebuild build-for-testing` 先行）；
   **构建勿加 `-derivedDataPath`**；**新建文件后跑 `tuist generate`**（T1 提交前一次，
   后续每新建文件同）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行（Executed 0 = 判据失败）。**回归基线 = 14-1 收口后最新**（1768 + 14-1 新增，
   读 `.work/GOAL-STATE.md` 续接点取最新；与 14-2 并行期间以两 plan 合并后 HEAD 计收尾轮）；
   每任务全套 suite 绿，**0 fail 目标**；在案 flake（`LayerE2E`/`ToneEqual` 负载型）隔离
   ×3 归因单列入 SUMMARY，不计违约。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线（本 plan 有渲染触发腿——L031 全款适用）**：①**L031 路由红线**：stale
   regenerate=true 腿（tier B 单图重渲）**只消费 SessionThumbnailRenderer 既有装配与队列
   路由**——禁止自建 command queue/硬编 editor queue；发现需要新队列 = 停下报告；联系表
   拼图与标注条**纯 CoreGraphics/CoreText**（无 Metal 触点，越界即停）；②**FilterSQL 单一
   翻译面**：list_photos 禁止第二翻译层——谓词 JSON = FilterPredicateGroup 直作，合法性
   校验只消费 `legalOps`/`legalValueKinds` 既有矩阵；**FilterDomain 分派缝零改动**（v1 恒
   .session；`grep -n "FilterDomain" App/Sources/Lightamer/MCP/` 零命中自证入 SUMMARY）；
   ③**MCP 永禁直写 sidecar 文件字节**——写五件只走 MetadataService、preset 只走
   PresetApplier；④**万张级操作零像素渲染**（PERF-07 语义：list/burst 类工具禁触发任何
   解码/渲染）；⑤L009：fixture 禁 UNITEK 盘（真实 RAW/人像样张不入库——隐私与版权，
   .work/ 为 gitleaks 排除面或本地临时目录，样张缺失时测试显式 skip + 记录）；⑥L013：
   burst id 等跨进程身份 StableHash FNV-1a decimal String（`burst-<首图path-hash8>`）。
6. **执行期决策登记**：标注条渲染细节（字体/字号/星符拼写）、游标 JSON 键序、stale
   regenerate 的 QoS、真人像样张来源与路径等入 `14-3-DECISIONS.md`，不臆造。

## Tasks

### T1 真人像 landmark 补测（R5）+ list_photos（22 列投影 + keyset 游标 + 谓词往返）

- **action**
  1. **真人像补测**（探针局限①收口，首动作）：真实人像样张 10 张（不入库；缺失 → 显式
     skip + SUMMARY 记录）跑 `VNDetectFaceLandmarksRequest` 直发——landmark 精化增量实测
     数字入 SUMMARY（架构不受影响：per-request 已裁，补测只校成本模型「~4ms/图」量级）。
  2. 新建 `PhotoProjection.swift`：**22 列投影表**（§RQ-14-7③ 终表逐列——路径身 3/文件 2/
     has_edits/layer_count+summary/几何 3/capture_date/thumb_state/rating/color_label/
     keywords/flag/note/EXIF 7；**不暴露 12 列**：scan_epoch/imageID/sidecar_present+mtime/
     params_hash/thumb_path+params_hash/orphan_sidecar/dirty）；`SessionIndexRow` → MCP
     dict 显式映射一处拼装。
  3. list_photos handler：`filter` = FilterPredicateGroup JSON 直作（16 字段 × 12 op 全
     暴露；`legalOps`/`legalValueKinds` 校验 → `invalidFilter`）；`sort` = FilterSortKey
     六键直映；`limit` 默认 200 上限 1000；**keyset 游标** = base64(`{sort 键终值, path}`)，
     追加 `(key, path) > (?, ?)` 谓词**在 query 调用点拼装**（:561-584 消费面，不触碰
     FilterSQL）；返回 `{rows, nextCursor}` **不返回总数**（COUNT 第二趟全扫省略——agent
     游标耗尽感知终页）。
  4. **谓词往返测试**：同一 FilterPredicateGroup GUI chips 与 MCP 入参同 SQL 同结果
     （12-2 翻译层 fixture 复用）——零新翻译层自证。
  5. culling 域快照改：list_photos 注册（原子同 commit，`McpCullingToolsetTests` 快照段）。
- **证据**：`McpCullingToolsetTests`——22 列投影冻结断言（逐列名/不暴露列零出现）+ 谓词
  往返等值 + 游标分页（首屏/翻页/耗尽/换排序键游标失效）+ invalidFilter 矩阵负例；
  补测数字入 SUMMARY。

### T2 写五件 + GUI 联动走查 + preset 三件套（D8 钉板）

- **action**
  1. **写五件**（set_rating/set_flag/set_color_label/append_note/set_keywords）：
     MetadataService 六 API 单源直映（set_keywords :117-124 整组替换语义 + `|` 分隔符 →
     typed error `keywordContainsSeparator`）；relPaths[] 批量入参；返回 MetadataEditOutcome
     映射；`serverReadOnly`/`notSessionMember` 骨架；元数据写超时 5s（`McpTimeouts`）；
     destructiveHint 注解（MCP-08 边界：写回限元数据字段，像素/文件删除移动零工具面——
     快照封闭集即证明）。
  2. **GUI 联动走查**（§RQ-14-3⑥）：MCP 元数据写 → lindex 行即时更新（claim 事务）→
     浏览器网格 badge/过滤面经既有刷新缝同步（自动化断言：写后 query 行 + 既有通知缝
     触发计数）；**编辑器当前打开图的 inspector 行是否跟随**走查入 SUMMARY（claim 面不推
     GUI 状态对象——若不跟随属实，登记 R7 处置位「通知缝或刷新钩子小改」至收口批，不在
     本 plan 扩面）。
  3. **preset 三件套**：`list_presets`（kind=develop|export，PresetsStore :73/:200 清单面）/
     `apply_preset`（PresetApplier.apply 直复——**live 图进 `skippedRelPaths` 软跳**[D8：
     MCP 场景无 GUI 交互层，live skip 直接落报告面，不报错不阻塞批量]；`exportPresetNotApplicable`
     照既有校验；mode/selection 透传）/ `diff_presets`（op 键集 diff；`unknownPreset`）。
  4. 测试负例双向钉板：**apply_preset live 软跳**（skippedRelPaths 含 live 图 + 其余图
     成功）vs **apply_params live 硬拒**（14-2 半边——本 plan 只测自己半边，两语义对照表
     入 DECISIONS）；批量三段语义回归（one bulk change = one transaction）+ serverReadOnly
     （只读降级钩子消费，14-1 落）+ GUI-live 图元数据写 claim 面行为不变负例（CONTEXT
     验证红线字面：元数据写 claim 保护不动）。
  5. culling 域快照改：+8 工具（写五件 + preset 三件套）注册（原子同 commit）。
- **证据**：`McpCullingToolsetTests`——写五件单源往返（sidecar 真身 + lindex 行 +
  GUI 可见性缝）+ live 软跳/元数据 claim 不动负例 + preset 三件套 + 快照 culling 段
  9 工具。

### T3 图像三件套 + base64 上限表落码

- **action**
  1. **get_thumbnails**：relPaths ≤20/请求；双档直读（档 A embedded / 档 B
     `ThumbnailDiskStore.read`，09 期 appointment 语义 `SessionThumbnailProvider.swift:43-50`
     沿用 + has_edits 裁决红线）；`thumb_state=3` → 返回 `stale: true` 标记 + 可选
     `regenerate`（默认 false 只标记不阻塞批量；true = tier B 单图重渲——**L031：只消费
     SessionThumbnailRenderer 既有装配路由**）；20 张/请求预算 ~730KB。
  2. **get_contact_sheet**：cell 256/q80；cols×rows ≤ 6×5=30 格 + 每格 24px 标注条
     （文件名短标 + rating 星符 + flag 色条，**CoreGraphics/CoreText 纯 CG**）；单拼图
     base64 ≤ 2MB 上限断言；**中文文件名 fixture 测试**（R9：CoreText/NSAttributedString
     标注条——zh 文件名渲染不豆腐块）；入参 relPaths 或 filter 二选一。
  3. **get_detail_crop**：ROI 原图像素坐标 `{x,y,w,h}`（合法性 = orientation/width/height
     换算——list_photos 几何列即坐标系来源，22 列投影消费闭环）；输出 longEdge 1024/q85
     /上限 1536；ROI 越界 = `roiOutOfBounds`；v1 单 ROI 单请求（多 ROI 数组 = additive 位
     不开）；RAWDecoder 解码腿 + `McpRenderGate` 串行。
  4. **base64 上限表落码断言**（`McpCullingImageBudgetTests`）：四工具（含 14-2
     render_preview 的常量交叉引用）默认/上限值 = research §RQ-14-8 预算表 verbatim
     （常量一处——越界即测试红）；stale 语义三态（fresh/stale+默认/stale+regenerate）。
  5. culling 域快照改：+3 工具注册（原子同 commit）。
- **证据**：`McpCullingImageBudgetTests`——上限表逐项 + 联系表中文渲染（像素采样断言
  非 DIY OCR）+ stale 三态 + ROI 越界；`McpCullingToolsetTests` 快照 culling 段 12 工具。

### T4 list_bursts + get_face_regions

- **action**
  1. **list_bursts**：聚类键 = `capture_date` 间隔阈值（`gapSeconds` 参数化默认 **2.0s**）
     + `camera_model` 参与分组（换机不并组）；跨日自然切断无特殊边界；查询 = 单扫
     `ORDER BY capture_date ASC` + 内存 O(n) 聚类（不用 FilterSQL 谓词——专用查询；仍走
     同一 actor handle 零新锁面；**万张级 <1ms，零像素渲染**）；返回
     `{bursts:[{id: "burst-<首图path-hash8>"[L013 StableHash], count, members}], singles}`；
     组合查询 recipe 写工具描述（agent 以 members relPath 自组二次过滤——不加专用参数）。
  2. **get_face_regions**：relPaths ≤20；`VNDetectFaceLandmarksRequest` 直发（**不经
     SkinRegionLocator 编排**——hull/保护区是磨皮域孪生）；boundingBox 归一化坐标 ×
     图像 width/height → 原图像素框；landmarks 点集可选返回；**空数组 = 无脸（非错误）**
     语义钉死；per-request 不缓存（3.9ms/图量级，文档标注成本模型）；请求内串行。
  3. culling 域快照改：+2 工具注册（原子同 commit）——**culling 域 14 工具齐**。
- **证据**：`McpCullingToolsetTests`——burst 聚类 golden（2.0s 阈值边界/换机切组/跨日/
  singles/哈希 id 稳定性）+ 脸框换算（已知 fixture 归一化→像素框逐值）+ 空数组负例 +
  relPaths 21 张拒绝；快照 culling 段 14 工具。

### T5 筛选端到端（SC#5/6 全链）

- **action**
  1. SC#5 全链（InMemoryTransport 自动化）：list_photos（列含 rating/flag/EXIF）→
     get_thumbnails → get_contact_sheet → get_detail_crop（脸部 ROI，衔接 T4 脸框）→
     写回 set_rating + set_flag + set_color_label → **sidecar 真身 + lindex 行 + GUI
     同步可见**三断言（写回联动 parity，12 期 MetadataService 测试形态跨入口复用）；
     全程零像素写回/零文件删除移动（MCP-08 自证：操作集快照封闭）。
  2. SC#6 culling 流组合：list_bursts → 组内 get_face_regions → 脸部 ROI
     get_detail_crop → set_rating 写回——「全图阵列 → 相似组联系表 → 脸部细节 → 写回」
     方法论链自动化。
  3. HTTP 形态复验（同一 handler 集双宿主一致性红线）；批量 ≤20 张缩略 + 30 格联系表
     实测预算对账（research §RQ-14-8 预算表注脚）。
- **证据**：`McpCullingToolsetTests` 端到端段（或独立段申报一处）——SC#5/SC#6 两链绿 +
  三断言 + 预算对账数字。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 = 两 wave 合并后最新 + 本 plan 新增，0 fail；与 14-2
  收尾轮对表——后合入方负责合并 HEAD 终轮）；TODO.md 14-3 勾选；`14-3-SUMMARY.md`（任务
  表/commit 表/landmark 补测数字/inspector 走查结论[登记]/证据）；`14-3-DECISIONS.md`
  （live 软跳语义[D8 本 plan 半边]、22 列投影终表执行确认、标注条渲染细节、其余执行期
  决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| list_photos | 22 列投影冻结 + 谓词往返等值 + 游标分页全形状 + invalidFilter | `Scripts/test-direct.sh 'McpCullingToolsetTests'` |
| 写面 | 写五件单源往返 + live 软跳/claim 不动负例 + 批量三段回归 | `Scripts/test-direct.sh 'McpCullingToolsetTests'` |
| 图像三件套 | 上限表落码 + 联系表中文渲染 + stale 三态 + ROI 越界 | `Scripts/test-direct.sh 'McpCullingImageBudgetTests'` |
| burst/脸框 | 聚类 golden + 脸框换算 + 空数组语义 + 哈希稳定 | `Scripts/test-direct.sh 'McpCullingToolsetTests'` |
| SC#5/6 端到端 | 列 → 缩略/联系表 → 细节 → 写回三断言 + culling 流组合 | `Scripts/test-direct.sh 'McpCullingToolsetTests'`（端到端段） |
| 回归 | 全 suite 0 fail（合并 HEAD 基线 + 新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |
| defer 自证 | FilterDomain 缝零改动（v1 恒 session） | `grep -n "FilterDomain" App/Sources/Lightamer/MCP/`（零命中，输出入 SUMMARY） |

## 验收标准（Acceptance）

- [ ] 真人像 landmark 补测数字在案（R5 关闭；样张缺失显式 skip 记录）
- [ ] list_photos：FilterPredicateGroup JSON 直作零新翻译层（16 字段 × 12 op）+ 22 列
      投影终表逐列（不暴露 12 列零出现）+ keyset 游标（query 调用点拼装，FilterSQL 零
      触碰）+ 不返回总数 + 谓词往返等值
- [ ] 写五件：MetadataService 单源 + claim 保护不动 + `keywordContainsSeparator` +
      GUI 联动（lindex/网格/过滤面）+ inspector 走查结论登记
- [ ] preset 三件套：apply_preset live **skippedRelPaths 软跳**（D8）+ exportPresetNotApplicable
      + diff op 键集 + 快照原子演进
- [ ] 图像三件套：双档直读 + stale 三态（regenerate 默认 false）+ 联系表 ≤30 格 24px
      标注条 ≤2MB（中文 fixture 过）+ ROI 裁剪 `roiOutOfBounds` + 上限表落码断言
- [ ] list_bursts：2.0s+camera_model 聚类 + StableHash id + singles + 零像素渲染；
      get_face_regions：Vision 直发 + 像素框换算 + 空数组=无脸 + per-request 不缓存
- [ ] SC#5/6 端到端绿（写回三断言 + culling 流组合；双宿主一致）；v1 恒会话域自证
      （FilterDomain 零命中）
- [ ] culling 域快照 14 工具逐字；全 suite 0 fail；每任务独立提交 + 边界查开关；不 push；
      SUMMARY + DECISIONS 落盘

# Plan 14-3 — 执行期决策（DECISIONS）

> 纪律条款：RESEARCH/CONTEXT 未覆盖的细节登记于此，不臆造。

## D-14-3-T1-1 列数正本 = research §RQ-14-7③ 终表（25 暴露 / 9 不暴露）

plan 正文与 files_modified 注释通篇写「22 列投影」「不暴露 12 列」；research 终表逐列
清点 = 暴露 25 / 不暴露 9（34 列守恒），且 coordinator 派发指令明确「checker M-2 修正
后的正确列数 = 25」。**执行以 research 表为正本**：25 列投影落码 + 9 隐藏列零出现测试
（projection 冻结测试同时断言 25+9=34 守恒）。

## D-14-3-T1-2 投影键拼写 = 冻结 SQL 列名（snake_case），全键恒在

投影 dict 键用 `SessionIndexSchema.imagesColumns` 的字面拼写（`file_size` 非
`fileSize`）——与 frozen spelling 契约同源、与 schema 文档互查零翻译。NULL 列骑
`McpJSON.null` 显式出现（稳定行形状：client 按 key 取值，不按 key 存在性分支）。

## D-14-3-T1-3 keyset 游标 = base64(sortedKeys JSON)，双谓词形状

cursor 载荷 `{k: sortKey, d: asc|desc, p: path, v: {kind, ...}}`，JSONEncoder
sortedKeys + base64（确定性字节）。谓词两类：
- 值类：`((k > ?) OR (k = ? AND path > ?))` / DESC 用 `<`（path tiebreaker 双向恒
  ASC，per `FilterSort.orderBySQL` 冻结拼写）；
- NULL 类（排序键为 NULL 的行在双向都排尾）：`(k IS NULL AND path > ?)`。
游标校验键+方向 mismatch → typed `invalidParams`（换排序键游标失效负例）。**不返回
总数**：短页即终页信号（nextCursor 只在 rows.count == limit 时发出）。

## D-14-3-T1-4 游标谓词的落点 = `SessionIndexStore.query(extraPredicate:)` 加法参数

`(k, path) > (?, ?)` 是排序键元组比较，不是 FilterPredicateGroup，进翻译层即破
「FilterSQL 单一翻译面」。落点 = query face 的新增可选参数 `extraPredicate`（默认
nil，既有调用者字节不变），SQL 组装序列 = translated WHERE → AND extra → ORDER BY
→ LIMIT，bind 顺序对齐。FilterSQL 零触碰（12-2 回归锁字节不变，FilterSQLTests 全绿
随全量）。

## D-14-3-T1-5 真人像 landmark 补测（R5 关闭）：landmark 精化增量 ≤ 0

一次性 Swift 脚本（/tmp 即弃，L009 不入库）：~/Downloads 扫出 8 张真实人像
（2699×1518 ×7 + 1279×1919 ×1，每张 1 脸），warm 串行 3 轮均值——
**VNDetectFaceRectanglesRequest（检测主干）4.83ms/图 vs
VNDetectFaceLandmarksRequest（检测+landmark 精化）2.23ms/图**，精化增量实测 ≤ 0
（landmarks 路径的回归主干共享/排队差异使其不慢于纯检测）。成本模型「~4ms/图」量级
成立（无脸探针 3.9ms 与真人像 2.2–4.8ms 同量级），per-request 不缓存裁决不受影响，
get_face_regions 文档标注保留「~4ms/图」。

## D-14-3-T2-1 写五件不拒 GUI-live（与 apply_params 硬拒的非对称钉板）

元数据写（set_*）不做 live-target 拒绝：claim 面（claimMetadataApplySQL）结构上无
live 保护，D-8 红线 = 元数据写不翻 params_hash/不 stale/不进 history——GUI 内存 doc
与盘 doc 的分叉风险只存在于 params 面。负例测试钉「live 图元数据写行为不变」（applied
而非 skipped）。对照表：apply_preset live → **软跳**（skippedRelPaths 报告面，D8）；
apply_params live → **硬拒**（imageLiveInEditor，14-2 半边）；set_* live → **照常
写**（claim 面行为不变）。

## D-14-3-T2-2 unknownPreset 的判定面 = registry row 或磁盘文件任一缺席

`PresetsStore.loadDocument(id:)` 对不存在的 id 抛 `PresetError.unreadableFile`（文件
缺失的存储侧拼写）而非 `notFound`（那是 registry 面）。id 寻址语义上两者都是「unknown
preset」——apply_preset/diff_presets 把 `notFound` 与 `unreadableFile` 都映射为
`unknownPreset`；其余 PresetError（corrupt/invalid）→ `internalError`（服务器配置
面问题，不归 agent 处置）。

## D-14-3-T2-3 apply_preset 的 seed = 空数组、mode 默认 merge

- `seed: []`（pristine 目标的 identity seed）：GUI 面传默认模块 seed 是因为交互流
  需要完整默认链；MCP 面的 apply 语义 = 「预设内容上载」，空 seed 使 pristine 目标
  的最终状态恰为预设实例（可预期、可 diff）。
- `mode` 默认 `merge`（append 语义，非破坏默认）；overwrite 需显式声明。

## D-14-3-T3-1 McpImageBudget 常量一处 + 14-2 常量的收口统一位

budget 表常量落 `McpImageBudget`（含 render_preview 四常量 1024/85/2048/90——
checker M-3 指定的共享缝位）。执行事实：14-2 并行已先落自己的 `previewDefault*`
常量（值 = research 表同值，双向无漂移），**14-4 收口批统一让 EditingToolset 消费
McpImageBudget**（登记 TODO 遗留）；本 plan 的 budget 测试逐值 verbatim 断言，
任何一侧漂移即红。

## D-14-3-T3-2 缩略 dual-tier READ 的字节面：tier B 文件直读、tier A 重编码 q85

- tier B（rendered）：`ThumbnailDiskStore.read` 解码后**不重新编码**——thumb_path
  的 JPEG 原字节直透（零质量损失，磁盘字节即所存）。
- tier A（embedded）：`SessionThumbnailProvider.embeddedPreview(url:)`（public
  nonisolated，既有 720px downsample 腿）取帧后按 `ThumbnailDiskStore.jpegData`
  q85 重编码（与 09-3 磁盘缓存同质）。
- appointment 裁决在 READ 时消费 `SessionThumbnailProvider.tier(forRow:)` 本体
  （has_edits only + stale-regen clause）——不复制裁决逻辑。
- 输出面 = 一个 JSON manifest（relPath/stale/missing/byteLength/index）+ 按序的
  image blocks；missing（state 0 未生产/读失败）= manifest 行 missing:true，不出
  image block（诚实缺面，不静默跳过）。

## D-14-3-T3-3 stale regenerate=true 的路由 = provider.thumbnail(for:visible:true)

L031 消费形态：tier B 重渲走 `SessionThumbnailProvider` 既有队列（visible:true 跳
过 idle delay 优先执行），渲染腿仍是宿主装配注入的 `SessionThumbnailRenderer.
renderLeg`——零新 command queue、零私有渲染路径。宿主无 provider（头less 最小装配）
时 regenerate → typed `internalError`（不静默降级为标记）。

## D-14-3-T3-4 联系表 = 纯 CG/CoreText；行几何 caption 在 photo 带之下

- 拼图/标注条零 Metal 触点（红线②越界即停——执行中一次行几何笔误〔caption 带被推
  出画布〕被像素采样断言当场抓获修复，即该测试的存在价值）。
- 标注条细节（执行期决策落定）：背景 #141414、文字 #F2F2F2 12pt system UI face、
  rating = `★`×rating（无空心星）、flag 色条 8px（1 pick = green 0.2/0.8/0.3、
  2 reject = red 0.9/0.2/0.2）、左留白 14px 给色条。
- CJK 渲染 = CTLine 绘制时的系统 cascade（UI face 不含 CJK 字形但 CTLine 走
  cascade 到 PingFang SC）；测试的 glyph 门显式用 PingFang SC 直查（
  CTFontGetGlyphsForCharacters 不做 cascade——UI face 对 CJK 恒返回 notdef，那不是
  渲染缺陷）。

## D-14-3-T3-5 get_detail_crop 坐标系 = 解码后像素域（top-left origin）

ROI 合法性按**解码后 extent**校验（ground truth；index 几何列仅是文档面），
`CGImage.cropping` 的 rect 即 top-left 像素域。输出 ≤ longEdge 不放大。该工具读
RAW 原像素（不反映编辑态——编辑态归 render_preview/14-2），工具描述明示。

## D-14-3-T4-1 burst id = "burst-" + StableHash 全量 decimal（L013 绑定规则优先）

research §RQ-14-9 写 `burst-<首图path-hash8>`（hash8 = 8 hex 位缩写）；L013 纪律 =
跨进程身份用 StableHash **decimal String**。执行取 L013 为绑定规则：id =
`burst-<FNV-1a 64 全量十进制>`（无截断、无 hex）。测试以 `StableHash.hash("b1.arw")`
重算对比钉 id 稳定性。

## D-14-3-T4-2 burst 聚类边界语义

- NULL capture_date 行无法定位时间轴 → singles（诚实分类）。
- 1 照片的「组」→ singles（burst 需 ≥2 成员；gap-ok/gap-cut/lonely 三行的测试即钉
  此边界——断言初版漏掉 lonely 被测试失败当场纠正）。
- camera_model NULL 与 NULL 同类（空串类），换机切组以 camera 相等为准。
- gapSeconds ≤ 0 → invalidParams；跨日无特殊逻辑（大间隔隐式切断）。

## D-14-3-T5-1 超时的兑现形态 = 任务组竞速、取消落后者、作用域出口等待

`withTimeout` 用 ThrowingTaskGroup 竞速（body vs sleep+throw），胜出后
cancelAll；group 作用域出口仍 await 不响应取消的 body——无 void 任务泄漏（QL
boundedWait 的「finishes into the void」姿态在 handler 层不复制；卡死 body 阻塞
而非泄漏，诚实且安全）。超时错误码：渲染族 = `renderTimeout`、其余族 =
`internalError`（错误码封闭集无 metadataTimeout/listTimeout 槽位，新增码属快照
面变更，v1 不开）。

## D-14-3-T6-1 并行共享工作区的验证隔离 = git worktree 私有验证环境

14-2 并行 worker 的 WIP（EditingToolset.swift 等未提交中间态）曾使主工作区编译不
过（缺 import / 引用未落成员），且其 0062575 提交本身引用了尚未落盘的
`Seams.yiyinInjector`。本 plan 的每任务边界构建与终轮全套在 **/tmp git worktree**
（HEAD + 本 plan 申报文件 + 14-2 已提交文件，另将共享装配两文件回退 37add39 以
绕开其未收敛引用——worktree 私有、不提交不 push）内完成；主工作区只承载本 plan
的提交（文件级 add，14-2 的 WIP 文件零触碰，仅共享装配 McpServerController 补过
一行 `import LightamerIOP` 修复其缺 import——该行随 14-2 后续提交走）。

## D-14-3-T6-2 inspector 走查结论（R7 处置位，登记不扩面）

自动化面：MCP 写 → claim 事务 → lindex 行即时更新 → 过滤/网格的 query face 立即可
见（测试三断言钉死）。**编辑器当前打开图的 inspector 行不跟随**：inspector 数据源
是编辑器内存 doc（PipeCoordinator/EditorState），claim 面结构上不推任何 GUI 状态
对象（D-14-CONTEXT-5① 的单源汇合语义即是「写 sidecar+index」，不含 GUI 通知）。
属预期行为而非缺陷；R7 处置（通知缝或刷新钩子小改）登记 14-4 收口批评估，本 plan
不扩面。

---

# 验收期决策（2026-09-28 独立验收 subagent 追加）

## D-14-3-ACC-1 list_photos 游标两处逻辑缺陷（验收修正，test-first）

独立验收发现并以 `fix(14-3)` 修复（test-first：修复前 27 tests / 2 failures——恰
两新测试红、executor 25 全绿；修复后 27/0）：

1. **值类游标谓词缺 NULL 桥**：`((k op ?) OR (k = ? AND path > ?))` 不含
   `OR (k IS NULL)`。NULL 双向排尾（`FilterSortKey.orderByTerm` 的旗标项无方向、
   恒 ASC）——当页边界恰落在最后一个非 NULL 行时，NULL 尾部行不可达，短页伪造
   「耗尽」信号（rating DESC + limit 恰切分非 NULL 段 → 未评分照片永久翻不到）。
   executor 的 `testCursorDescendingAndNullClassContinuation` 页尾恰落在 NULL 行
   内（limit 6 切进 NULL 类），未覆盖该转接缝。修复 = 值类三形（text/int/double）
   尾加 `OR (k IS NULL)`；新增 `testCursorValueToNullTailTransitionReachable`。
2. **`cursorValue(.scanEpoch)` 恒 `.null`**：scanEpoch 是六键白名单合法排序键，
   且生产行恒带非 NULL scan_epoch——`.null` 载荷使第二页只匹配 NULL-epoch 行
   （空页），第一页后静默截断。修复 = 携真实值 `.int`（cursor 为 base64 不透明
   token，无泄漏面）；新增 `testCursorPagingByScanEpochFullCoverage`。

测试作者附注：扫描 fixture 的裸 INSERT 必须显式带 `orphan_sidecar = 0`——
`baselineClause(.session)` 恒 AND 进每次 query（FilterSQL.swift:194），NULL 行被
静默过滤——「裸 COUNT 可见、query 不可见」的行消失假象即此，非产品缺陷。

## D-14-3-ACC-2 T6-1 worktree 隔离配方勘误（验收实测）

D-14-3-T6-1 记载「共享装配两文件回退 37add39」——实测该配方不可编译：
①McpToolRegistry 在 37add39..HEAD 零改动（回退为无操作）；②回退
McpServerController 使 HEAD 的 `LightamerApp.makeEditingSeams` 调用断链
（makeEditingSeams 系 0062575 新增，LightamerApp:903 消费）。可行配方 = 两共享
文件保持 HEAD 态 + worktree 私有给 `EditingToolset.Seams` 补 `yiyinInjector`
成员 shim（该成员在 14-2 未提交 WIP 内）——隔离目的不变，绕开方式由「删引用」
修正为「补成员」。时效注记：14-2 随后已落盘该成员（`6b87fd2` EditingToolset:79），
现 HEAD 起隔离构建不再需要 shim。另 SUMMARY「boolValue 改为消费共享版」措辞
过头：HEAD 的共享
McpToolRegistry 无该访问器（在 14-2 WIP 内），本 plan 提交面亦无消费方
（regenerate 走 pattern match）——已随验收批校正。

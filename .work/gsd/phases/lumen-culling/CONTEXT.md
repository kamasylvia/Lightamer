# LUMEN-CULLING CONTEXT — 图库选片增强批（UQ-LU1..LU5 五件一体，OQ 裁决落定批，2026-10-22）

> **裁决正本**：OQ-LU-1..10 **全部按 `RESEARCH.md` §Open Questions 推荐落定**
> （research 正本 = `ee73da34`；先例 M6-3/M6-4、M7-2..M7-6、LENS-01 批同款
> 「OQ 全按推荐」auto-advance 制度。**晨审可推翻**——推翻 = 用户晨审修订
> 本文件对应 D-LU 条，下游 plan 受影响任务面重开，已执行部分按「晨审推翻
> 先例」惯例处理）。读解正本 = 同目录 `RESEARCH.md`（§Summary / §UQ-LU2 /
> §UQ-LU1 / §UQ-LU3 / §UQ-LU4 / §UQ-LU5 / §依赖与切分 / §风险 / §OQ /
> §键族与登记预案）；planner 2026-10-22 HEAD `ee73da34` 抽核 ~20 点亲核，
> 吻合为主，**转写勘误四条**随 §转写勘误节登记（①FilterField 实为 16 案；
> ②EditingToolset.Seams 装配单点发现——FIX2③ 必须适配；③④引用微差），
> 执行以勘误为准。
>
> **特别登记一（hazards 三条，消解绑定到 plan，§Hazards 正表）**：
> ①分析任务与导出/AI 的调度互斥面（分析趟若不设暂停 = 与导出渲染抢
> CPU/IO + UI 卡顿风险）→ Plan A T5 三防落地（QoS .utility + 并发 cap
> 2 + 导出/AI 期挂起语义 + BackgroundTaskRegistry 进度/取消）；②`.lalb`
> v5→v6 迁移的用户数据安全（迁移失败/半程 = 用户项目库不可开）→ Plan A
> T1 纯 additive 七列 + 零回填 + ProjectFileStore pre-migrate
> `sqlite3_backup` 快照缝（`:276` hook 先例）+ 幂等探针 ALTER + ONE
> `BEGIN IMMEDIATE` 单事务（`LibrarySchema.migrate` 既有纪律，四代先例）；
> ③float16 精度声明的验证策略（缓存命中与未命中画面必须逐位一致，否则
> 「缓存不改变观感」承诺破产）→ Plan B T1/T3：Lumen `quantize()` 一致性
> 规则照抄（**新解码也过 float16 round-trip** → 命中/未命中同源同值）+
> round-trip golden 专测 + 相对误差 <0.05% 断言（Lumen 实测口径引用）+
> **编辑管线全分辨率工作平面零触**红线（缓存只服务预览/选片/重开档位）。
>
> **特别登记二（MIT 归属为不可延后件）**：Lumen RAW（MIT）三件算法移植
> ——SharpnessAnalyzer/Signature16 + BurstAnnotator（Plan A）+
> MaskRefine（Plan C）——文件头归属注记 + 根 `NOTICE` 新条目（「算法思
> 想与常量标定源自 LUMEN RAW（MIT），实现独立」+ 上游版权声明）。MIT 宽
> 松但**零归属入库 = 流程违规**（GPL 件同款纪律；与 spectral-film-lut
> 许可证登记同款流程，AGENTS M2-5 节先例）。Plan A T3/T6 与 Plan C T1
> 随件落地，不得延后。
>
> **编排总纲**：单 phase `lumen-culling`、**三 plan 串行 A→B→C**（D-LU-9
> ；机器级单重活制排除并行 plan）——**Plan A「分析地基」= LU2+LU1**
> （schema v6 + EXIF serial/SubSec + 分析纯函数族 + 分析趟服务 +
> BurstAnnotator + 智能相册 SQL 条件 + 网格徽章，ΔN +12..15）→ **Plan B
> 「缓存+选片视图」= LU4+LU3**（SmartPreviewStore + 消费方接线 + CullFace
> 窗体/键位/对比/预读/组跳，ΔN +14..18）→ **Plan C「蒙版精细化」= LU5**
> （MaskRefine + 编排 + MCP refine_masks，ΔN +6..7；与 A/B 无依赖、可独
> 立换序——若用户晨审上调 LU5 优先级，C 可提到 B 前）。**C 档门控：每
> plan 执行+验收闭环后停汇报**，等用户确认再放行下一 plan（charter 门 +
> AGENTS 暂停机制 + `.work/config.toml [gsd]` paused/auto 双开关，开工
> 前必读）。全套 `--all` = orchestrator 批准制 + 运行监视 + 8G 门 +
> MEMFAIL 机检兜底（AGENTS 资源监控节）；**本批执行排 F0'-prod +
> LENS-01 验收链收口之后**（机器级单重活——编排注记，2026-10-22 planner
> 时尚见 f0prime acc 链在飞，`.work/gsd/phases/f0prime-prod/` 未收口）；
> 执行批一切重活起跑前必过 `Scripts/machine-guard.sh`。

## Phase Goal（UQ-LU1..LU5 五件锚定）

把 Lumen RAW 五件高/中价值能力原生落地：**LU2 清晰度+闭眼批量分析**（分
析地基，Vision landmarks 眼睑比自算，零模型下载）+ **LU1 连拍分组与
best-of-burst**（签名相似 + 睁眼优先，查询期纯函数注记）+ **LU4 智能预览
缓存**（解码级 float16 持久 LRU，重开 ≤100ms 级）+ **LU3 快速选片视图**
（主窗第三 face，零 RAW 解码显示 + 100% 对焦检查 + C 并排对比 + 组间跳）
+ **LU5 AI 蒙版精细边缘**（采样式抠图 alpha 精细化，零新模型零新
kernel）。验收形态：构建绿 + 定向 bundle 全绿 + 全套 `--all` 对账（基线
**4112/40/0**（r12-repairs R3-ACCEPTANCE:8,:93 亲核），批 ΔN **+32..40**
→ 终值带 **4144..4152**，skip 增量逐族申报）+ golden 三面（清晰度公式/
连拍分组 Lumen 同输入对照/float16 round-trip）+ 眼睑比标定集机制 + 缓存
键/淘汰/并发测试 + FilterSQL 四案智能相册集成 + GUI 走查（选片评级流/
徽章/缓存命中探针）。三 plan 分账：**A +12..15 / B +14..18 / C +6..7**
（合计 +32..40；越带申报理由）。

## 决议（D-LU-1..10，生效值，硬约束，执行中不重开）

### D-LU-1 选片视图窗体 = 主窗第三 face（OQ-LU-1）

- **裁决 = RESEARCH §OQ 推荐**：`WorkspaceHostView` 加第三 face
  （library/editor/cull），与既有 library↔editor 路由同机制
  （`WorkspaceHostView.swift:432-449` 的 `libraryFace` 装配 +
  `onOpen → workspace.openEditor` 缝亲核）；零新窗口状态、Esc/G 回图库。
  独立 NSWindow（Lumen Qt 形）与全屏 presentation 不采纳——F0' 壳 =
  NSApplicationDelegate + NSHostingView 单主窗，多窗要新增
  window-controller 面，且机器单重活纪律下资源确定性差。
- 理由一句：既有 face 路由复用 + 键位聚焦面单一 + 单重活制下资源面确定。
- 证据：RESEARCH §UQ-LU3 窗体形态 (a) 臂 + §OQ-1；
  `WorkspaceHostView.swift:426-470`（libraryFace 先例）。
- 晨审推翻点：翻案 = 独立 NSWindow（Lumen 形态忠实度更高，成本 = 新
  window-controller 面 + 单重活资源面变宽，不建议）。

### D-LU-2 连拍折叠形态 = 查询期虚拟折叠 + 「转为堆栈」手动动作（OQ-LU-2）

- **裁决 = RESEARCH §OQ 推荐**：连拍分组是**查询期注记**（BurstAnnotator
  纯函数输出，零落库零实体）；网格折叠显示 = 注记 + 「1/5」序号徽章 +
  best 标记；实体化 = 手动「转为堆栈」动作复用 `LibraryStore.createStack`
  （`LibraryStore.swift:625` 亲核）——堆栈保持用户实体语义不污染
  （M6-4 stacks 实体表零写面）。`StackClustering`（`:20-64`，纯时间 60s
  阈值）与 MCP `list_bursts`（legacy session 域）**零触**——语义不同，
  本批不收编。
- 理由一句：分组是推导物、堆栈是用户意图，两语义混一 = 撤组即删栈的事故面。
- 证据：RESEARCH §UQ-LU1 我方缝位 + §OQ-2；`StackClustering.swift:20-64`
  亲核（LightCraft 形独立实现，头注自述）。
- 晨审推翻点：翻案 = 分组自动落 stacks 实体（用户实体语义污染，不建议）。

### D-LU-3 智能预览缓存落点 = app 缓存目录（OQ-LU-3）

- **裁决 = RESEARCH §OQ 推荐**：`~/Library/Caches/Lightamer/smart-previews/`
  （Lumen 同形：per-user 缓存目录、重建物、跨项目共享）；**不进 .lalb 包**
  （包可移植性优先——包内 `.lapreviews/` 臂弃：污染包目录 + 跨项目重开同
  源图无共享）。键 = `sourcePath|size|mtime|process version（M6-2
  per-photo，sidecar v10 载体）|缓存格式版本` → sha1——**比 Lumen 多
  process 维**（我方特有：渲染语义变更 = 旧缓存自然失效）。
- 理由一句：缓存是重建物，真相在包、体积在缓存，两账不混。
- 证据：RESEARCH §UQ-LU4 落点 + §OQ-3；M6-2 process version 纪律
  （AGENTS 里程碑表）。
- 晨审推翻点：翻案 = 包内 `.lapreviews/`（随项目走但牺牲可移植性与跨项目
  共享，不建议）。

### D-LU-4 闭眼口径 = 组内相对排序免阈值（主路径）+ 校准集绝对提示（副路径）（OQ-LU-4）

- **裁决 = RESEARCH §OQ 推荐**：**两者都要**。best-of-burst 睁眼优先 =
  组内 `max(右,左)` 开度相对排序，**完全免阈值**（主路径，零标定负担）；
  绝对「可能闭眼」提示 = 眼睑比阈值，带 **10-20 张我方实拍人工标注校准
  集**定标（初值借 Lumen 0.16 语义——`culling.py` CLOSED 常量；Vision 76
  点 vs MediaPipe 478 点采样密度差一个量级，**0.16 数值不可移植**，定标
  记录落 evidence、定标值入常量单源）。标定集机制：样张不入 CI 门（实拍
  样片不可 CI 依赖——LENS-04 T4 同款纪律），CI 只钉数学面（比值计算表驱
  动 + 合成 landmarks 正负例）。
- 理由一句：相对排序覆盖 90% 价值（选片），绝对阈值是提示性 UI 文案
  （「可能闭眼」，非判定性）——精度责任与提示语义相称。
- 证据：RESEARCH §Vision 结论（无公开闭眼 API；`VNFaceLandmarks.h:170-180`
  isBlinking 注记）+ §风险 3 + §OQ-4；`CullingToolset.swift:1281-1370`
  （landmarks 调用链 + 像素换算先例，~4ms/张实测）。
- 晨审推翻点：翻案 = 砍绝对提示只留组内排序（徽章「可能闭眼」面消失，
  LU2 提示条价值折损；若翻 = Plan A T4 的阈值臂转观察项）。

### D-LU-5 分析趟 = 默认开 + 导出/AI 期自动暂停 + Settings 开关（OQ-LU-5）

- **裁决 = RESEARCH §OQ 推荐**：`LibraryAnalysisService` 默认开；
  UserDefaults `library.analysis.enabled`（Bool 默认 true，typed 读 +
  注入式 defaults，body 零直读——KD-4 惯例）；暂停语义 = 导出/AI 活跃时
  挂起、空闲恢复（Lumen `paused()/kick()` 直译——
  `library_tasks.py:44-58`）；进度/取消挂 `BackgroundTaskRegistry`
  （`BackgroundTaskHosting.swift:80-127` 亲核）。单张不可读写 = 写空分析
  （`analysis_version` 置当前值 + 空产物）防重试风暴（Lumen `:162` 先例）。
- 理由一句：分析是后台推导物，任何前台重活都有路权优先权。
- 证据：RESEARCH §UQ-LU2 后台执行段 + §OQ-5 + §风险 2。
- 晨审推翻点：翻案 = 默认关（首装零分析产物，LU1/LU3 提示面全哑，不建
  议）。

### D-LU-6 选片 100% 内存全尺寸层 = LRU ≤2 张（OQ-LU-6）

- **裁决 = RESEARCH §OQ 推荐**：内存级 100% 全尺寸 LRU cap 2（Lumen
  `FULL=2` 直译）——对焦检查是选片硬需求；每张 150-200MB、cap 2 = 峰值
  可控（机器级 8G 门内）。
- 理由一句：100% 检查不可等解码，预读命中是体验本体。
- 证据：RESEARCH §UQ-LU3 预读段 + §OQ-6；测试宿主 8G 门（AGENTS 资源监
  控节）——GUI 进程不占测试门但同机器纪律适用。
- 晨审推翻点：翻案 = cap 1（对比 Pane 与 100% 并存时换页抖动，不建议）。

### D-LU-7 蒙版精细化触发 = 自动（默认开）+ 手动入口 + Settings 可关（OQ-LU-7）

- **裁决 = RESEARCH §OQ 推荐**：分割成功后自动触发精细化（Lumen
  `fine_masks` 默认开同形）；「精细化所选蒙版」手动入口并存；UserDefaults
  `mask.fineAuto`（Bool 默认 true，typed 读 + 注入式）；**失败保快速蒙版**
  + toast 原因（蒙版域永不因精细化失败而空——RESEARCH §风险 9）；完成 =
  raster 置换 + 一步 history commit（复用 M6-4 既有蒙版 history 缝——
  HistoryStack/LightamerSidecar 零 diff 红线，X8）。
- 理由一句：精细化是质量增强不是新语义，自动档最大化收益、失败面保底。
- 证据：RESEARCH §UQ-LU5 编排段 + §OQ-7；`AIMaskFeather.swift:15-31`
  （logit-gain 羽化——精细化与羽化正交共存：精细化产出更准 alpha 面，
  Edge 羽化仍在其上按用户半径作用，零冲突）。
- 晨审推翻点：翻案 = 只手动（自动档收益归零，不建议）。

### D-LU-8 MCP culling 域重挂 = 挂后批（OQ-LU-8）

- **裁决 = RESEARCH §OQ 推荐**：本批 GUI 优先；LU1/LU2 的 MCP 查询面
  （`analyze`/`bursts` 查询，`.lalb` 域）重挂是独立决策（现 14 工具绑
  legacy session 域——`CullingToolset.swift:29-32` 注记亲核「v1 evaluation
  domain = the CURRENTLY OPEN session」，默认项目 face 下 dormant 是既存
  事实），涉及域模型决策，独立小批处理。**本批唯一 MCP 增量 = Plan C 的
  `refine_masks` 入 EditingToolset**（X8——编辑域工具，非 culling 域重挂）。
- 理由一句：域重挂 = 域模型决策 + 14 工具逐个审计，塞进本批 = 预算失控。
- 证据：RESEARCH §Summary 架构缝 + §风险 10 + §OQ-8；
  `McpServerController.swift:909`（makeCullingContext session pair 注入，
  headless = `{ nil }`——`:501/:634/:742/:830` 四构造点亲核）。
- 晨审推翻点：翻案 = 本批加重挂（建议独立小批先行 design，不并入）。

### D-LU-9 里程碑形态 = 单 phase 三 plan 串行 A→B→C（OQ-LU-9）

- **裁决 = RESEARCH §OQ 推荐**：A（LU2+LU1，分析地基+分组闭环）→ B
  （LU4+LU3，缓存底座+选片视图）→ C（LU5，独立可换序）。拆两 phase 的
  备选仅在 A 体量失控时启用；五件共享 culling 域上下文与 xcstrings 键
  族，单 phase 内聚更省。每 plan 独立 C 档门控（执行+验收闭环后停汇报）。
- 理由一句：依赖链 LU2→LU1 / LU4→LU3 天然两波，C 独立垫尾；单重活机排
  除真并行。
- 证据：RESEARCH §依赖与切分 + §OQ-9。
- 晨审推翻点：翻案 = 拆二 phase / C 提前（C 提前合法——与 A/B 无依赖；
  拆 phase 仅 A 失控时启用）。

### D-LU-10 清晰度分析基准图 = 1600px 内嵌预览灰度（OQ-LU-10）

- **裁决 = RESEARCH §OQ 推荐**：分析基准 = ImageIO 内嵌预览 ≤1600px 灰度
  （Lumen `SHARPNESS_EDGE=1600` 直译——公式与标定口径 1.2px≈55 分/
  2px≈30 分直接可用）；2560px 是 LU3 显示档、**不混用**（两档两用途，
  `CullViewLoader` 内分档命名钉死）。
- 理由一句：公式参数与标定跟分辨率绑死，换档 = 全部重新标定。
- 证据：RESEARCH §UQ-LU2 清晰度段 + §OQ-10；`culling.py:34-51` 常量面。
- 晨审推翻点：翻案 = 2560 基准（标定作废重做，不建议）。

## 设计承接钉死（X1..X8，plan 层硬约束）

### X1 schema v6 DDL 终式 + 迁移缝（Plan A T1）

- `LibrarySchema.schemaVersion` 5→**6**（`:116` 单点）；`images` 表
  additive 七列（DDL 尾段、`default_look_pending` `:307` 同位追加，
  frozen 列位置/拼写零触碰）：`analysis_version INTEGER`（版本戳，
  ANALYSIS 常量 = 1，落后即重算）+ `sharpness REAL` + `faces INTEGER` +
  `eyes_closed INTEGER` + `signature BLOB` + `face_boxes TEXT`（JSON 框）
  + `camera_serial TEXT`（LU1 分组键）。
- `migrate(from:to:)` 加腿 `if from <= 5 && to >= 6 { try
  addCullingAnalysisColumns(on:) }`——**幂等探针 ALTER**（`PRAGMA
  table_info(images)` 列存在性 probe 逐列跳过，`addImagesDefaultLookPendingColumn`
  `:899-909` 同款先例）；ONE `BEGIN IMMEDIATE` 单事务纪律不动
  （`LibrarySchema.swift:836-860` 亲核）。
- pre-migrate `sqlite3_backup` 快照 = ProjectFileStore dispatch 既有自动
  hook（`ProjectFileStore.swift:276` + `backup(to:)` `:358-420` 在线一致
  拷亲核）——**零新机制，回归断言即可**（快照轮换纪律不触）。
- 零回填（分析趟懒填）；`LibrarySchemaV5Tests` 存量族旁落
  `LibrarySchemaV6Tests`（LIB bundle——BUNDLE-MAP `:370` 先例同形）。
- 未来 schema 回退枚举（futureSchema typed refuse）不受扰（additive 零
  改列——RESEARCH §风险 1 亲核）。

### X2 EXIF serial / SubSecTime 读法（Plan A T2）

- `ExifSearchIndexer.readProperties`（`:123-161` 亲核——现读
  Make/Model/LensModel/ISO/Focal/FNumber/ExposureTime/DateTimeOriginal，
  无 serial 无 SubSec）：补 `kCGImagePropertyExifBodySerialNumber`
  （Exif dict 为主、TIFF dict 最佳努力——ImageIO 键名面 execute 期按实拍
  样张核对，ExifTool 读法≠ImageIO 读法，RESEARCH §风险 4）；SubSec =
  `kCGImagePropertyExifSubSecTimeOriginal`（缺回落
  `SubSecTime`/`SubSecTimeDigitized`）折进 `captureDate`（epoch +
  subsec/1e6——`capture_date REAL` 亚秒精度）。
- 写腿 = ImportService 索引趟（既有 `ExifRead` 结构 additive 两字段）；
  `images.camera_serial` 列写点同批；**旧行零回填**——分析趟顺路懒补
  （LU2 分析趟读 EXIF 时若 serial/SubSec 缺 = 顺路 UPDATE，RESEARCH §UQ-LU2
  缝位 2 同款）。
- serial 缺失回落 = make+model（同型号双机身误组——登记接受，RESEARCH
  §风险 4）；SubSec 缺失 = 文件名 tiebreak（Lumen 同形，RESEARCH §风险 5）。

### X3 分析纯函数族直译边界（Plan A T3/T4）

- 新 `LightamerCore/Sources/Library/CullingAnalysis.swift`：
  `SharpnessAnalyzer`（输入 = 1600px 灰度平面；高斯 σ0.5 → 32px 块四方向
  （0/45/90/135°）一阶/二阶导数能量比（固定 3×3 核直译 `culling.py:46-51`）
  → 结构块筛选（一阶能量 P75 且 >2e-5）→ 比值 P90 → 四方向 min →
  `log2((min+4)/5.5)*100` 钳 0-100——**公式参数逐字直译，禁重标定**，
  D-LU-10）+ `Signature16`（16×16 灰度 256 字节，INTER_AREA 同义缩放）。
  实现域 = Accelerate/vDSP（零 OpenCV——v1 依赖红线）；文件头 MIT 归属
  （Lumen `culling.py:68-94`——特别登记二）。
- 新 `LightamerCore/Sources/Library/EyeClosureAnalyzer.swift`：
  `VNDetectFaceRectanglesRequest`（替代 YuNet——零下载零模型管理，M2AI
  可选安装纪律零负担）→ `VNDetectFaceLandmarksRequest` 76 点 → 眼睑比 =
  眼 region 上下点对纵向跨度均值 / 眼角横向跨度（左右各一，取
  `max(右,左)` 语义与 Lumen `max(右,左) < CLOSED` 同形）；**注入式
  request 工厂**（测试合成 landmarks 面——Vision 请求不可 CI 依赖）；
  人脸框输出（`face_boxes` JSON 载体）；阈值 = 注入参数（默认 0.16 语义
  初值，标定集定标后换常量单源——D-LU-4）。
- Vision 眼睑比数学 = Lumen 思想 + Vision landmarks 词汇——归属注记与
  SharpnessAnalyzer 同文件头（Lumen CLOSED 语义出处）。

### X4 BurstAnnotator 直译边界（Plan A T6）

- 新 `LightamerCore/Sources/Library/BurstAnnotator.swift`：**查询期纯函数**
  （输入 = `LibraryQueries` 行集：camera_make/model/serial + capture_date
  + signature + rating/flag 既有列——零落库零实体）；Lumen
  `annotate_bursts`（`library_db.py:822-900`）直译：
  1. 排序键 = `(make, model, serial)` 三元组 + `captured_ts` + 文件名
     tiebreak；无 ts 行永不归组。
  2. 副本排除（`_copy` 直译）：同一时刻（±1e-3s）+ 文件名 stem 前缀互含
     → 非连拍帧（看最近 3 个已收行）。
  3. 归组 = 同机身 + 相邻间隔 ≤2.0s + 签名相似（16×16 各自零均值/单位
     方差（σ+4 防爆）后逐像素 MAD ≤0.6）。
  4. best = `max(睁眼优先, sharpness 降序, 组内序稳定)`；组 ≥2 才成组。
  5. blurry 注记 = sharpness <22 或（组内且组最佳 − 自身 >14）（提示条
     消费——绝对 <22 可入 SQL 面待后续，组相对部分留注记层）。
- **组 id = StableHash（FNV-1a 64）decimal string**（L013 红线；
  `list_bursts:1243` 先例同款）；Swift `Hasher` 禁入。
- 近亲零触：`StackClustering`（`:20-64`）与 MCP `list_bursts`
  （`CullingToolset.swift:1174+`）零 diff（D-LU-2）；MIT 归属头（特别
  登记二）。
- golden = Lumen 同输入对照（MIT 合规直取其测试向量——`tests/` 侧
  annotate_bursts 向量；上游无现成向量时自织向量 + 直译双实现对拍，
  execute 期取证申报）。

### X5 智能相册四案 + FilterSQL 直比边界（Plan A T7）

- `FilterField` += 4 案：`sharpness` / `faces` / `eyesClosed` / `hasBurst`
  （16→20 案——勘误①：现值 16 非 17；`FilterPredicate.swift:54-84` 亲
  核）。op 支配：sharpness = gt/gte/lt/lte/eq；faces/eyesClosed =
  eq/gt/gte；hasBurst = eq(true)。
- `FilterSQL` `.library` 域翻译腿（`FilterSQL.swift` 白名单纪律——ORDER BY
  注入守卫同款）：sharpness/faces/eyes_closed = **纯 SQL 直比列**；
  `hasBurst` = **查询期注记不可纯 SQL** → 智能相册 builder 对 hasBurst =
  typed「不支持」臂（UI 置灰 + 说明文案；case 保留供选片视图/网格注记消
  费）——RESEARCH §UQ-LU2 缝位 6 裁定延续（v1 智能相册只收纯 SQL 条件）。
- `blurry` 组相对部分留选片视图提示条（`annotate_hints` 语义——Plan B
  T6）；智能相册 v1 无 `burst:best` 裸词（后批注记期条件域，随 MCP 重挂
  一起评估——D-LU-8 关联）。
- 集成测试 = 建库 → 灌注记行 → createAlbum(filterGroup:) 四案直比 +
  hasBurst 不支持臂（LIB bundle——`LibraryFilterDomainTests` `:352` 先例
  同域）。

### X6 SmartPreviewStore 格式/键/落点/一致性（Plan B T1-T3）

- 新 `LightamerCore/Sources/Decode/SmartPreviewStore.swift`（解码链出口
  包装层——`RAWDecoder.decode` `:120` 之上，零改 RAWDecoder 本体签名）。
- 格式 = LPV1 形直译（magic + 头长 + JSON 头 + 平面数据）：我方平面 =
  **working-space 线性 float16 量化 + 字节平面重排（低/高字节分平面提升
  zlib 压缩率）+ zlib level 1**，读回升 float32（管线 float32 RGBA
  premultiplied 纪律——读回即合成 RGBA 面）。**量化一致性规则照抄**
  （Lumen `quantize()` `:79-81` 先例）：**新解码也过 float16 round-trip**
  → 缓存命中与否画面逐位一致；相对误差 <0.05%（Lumen 实测口径，golden
  专测钉——H-LU3 消解）。
- 键 = `sourcePath|size|mtime|process version（M6-2 per-photo，RenderProcess
  单源读点）|缓存格式版本` → sha1（D-LU-3；**process 维 = 我方特有**，
  Lumen stamp 无此维——渲染语义 bump = 旧缓存自然失效）。哈希入 index
  表 = hex string（L013 邻域纪律——sha1 本身 hex，无 decimal string 面）。
- 存储 = index SQLite（WAL + entries(key,kind,bytes,used) 表形直译）+
  平面文件（同目录 tmp + 原子晋升——**L009：禁 /tmp 跨卷 rename**，同目
  录内 replace）；LRU 默认 4GB（UserDefaults `previews.cacheMB`，0=关，
  trim 到 90% 按最旧 used 逐出，每 16 写一巡——直译）；损坏即删重建
  （cache rebuildable，降级直解码永不阻塞打开——Lumen `:307-318` 语义）。
- 内存层 = 解码平面 LRU 6 张 float32 + **in-flight 去重**（同 key 并发解
  码合并——`LibraryThumbnailBridge` gate actor 同款先例形态）+ 全尺寸
  LRU cap 2（D-LU-6，选片面自有）。
- **红线（H-LU3 第二臂）**：缓存只服务预览/选片/重开档位——编辑管线全
  分辨率工作平面**零触**（`PixelPipe` 封存零 diff 的必然推论）；DRT/film
  尾平面不缓存（显示格式重算成本低——RESEARCH §UQ-LU4 红线注记）。
- 消费方四门：①PipeCoordinator 载入腿预览档平面 ②图库档B 真渲染腿
  （`LibraryThumbnailBridge.RenderLeg` 生产侧）③LU3 RAW 回落腿 ④MCP
  `decodeImage` 腿（`CullingToolset.swift:68` seam——进程内三消费方 +
  MCP = Lumen「三前门」同构）。

### X7 CullFace 装配与键位（Plan B T4-T6）

- `WorkspaceHostView` 第三 face `cullFace`（`libraryFace` `:432-449` 同
  机制）；路由 = 图库 onCull 缝（网格工具栏/快捷键入口）→ face 切换；
  Esc/G 回图库。
- 新 `CullViewLoader`（actor，App 侧 Library 域）：显示档 =
  `CGImageSourceCreateThumbnailAtIndex` max pixel 2560（Lumen VIEW_EDGE
  直译——**不复用 720 档**，`SessionThumbnailProvider.embeddedPreviewMaxPixel
  :144` 零触）；LRU 视图 12-16 张 + 全尺寸内存 LRU 2（D-LU-6）+ ±3 预读
  （低优先级尾插，`prioritize` 反向操作同形）；生产门复用
  `ThumbnailProductionGate` 形（`LibraryThumbnailBridge.swift:38-80` 亲
  核，cap 2）。`full_size` 判定直译（内嵌 ≥50% sensor px——
  `CGImageSourceCopyPropertiesAtIndex` 比对 EXIF 尺寸）；无合格内嵌 →
  回落 RAWDecoder 解码腿（走 LU4 缓存命中）。
- **键位（G/D 钉死）**：`G` = 回图库（Lumen Esc-G 映射——Esc 归 SwiftUI
  焦点系，G 独占）；`D` = 进编辑器（Lumen Enter 显影映射）；`0-5` 星级 /
  `P` 留用 / `X` 排除 / `U` 取消 / `6-9` 色标 / `A` 评级后前进 / `C` 并
  排对比 / `F` 人脸框 / `←→` 换候选 + `Tab` 切侧 + `↑` 候选晋升（对比
  态） / `↑↓` 组间跳（连拍态）。键位帮助行常驻底部。
- **legacy `CullingView` 纪律继承**（`App/Sources/Lightamer/UI/
  CullingView.swift:30-37,91-120` 亲核）：双 Pane cap 2 + 错峰解码（Pane
  A 平面落页后 B 才起——anti-storm gate）+ pair-identity `.task(id:)` 重
  跑语义 + 自拥有平面释放纪律（pair change 释放旧平面）。legacy
  `CullingView` 本体**零触**（session 域退役面）。
- 评级写腿 = `LibraryStore.setMetadataMarks`（`:455` 亲核）+ 评级后前进
  （A 开关）；胶片条复用 `LibraryThumbnailBridge` 96px 档；提示条读
  sharpness/eyes_closed/blurry/burst 注记（Plan A 产物）；分析插队 =
  当前 ±(−2..+6) 窗未分析行 `first=True` 插队（Lumen `:426-429` 直译——
  经 LibraryAnalysisService 优先队列缝）。
- xcstrings `cull_*` 键族尾块纯插入（Plan B 批内）。

### X8 MaskRefine 算法边界 + 编排 + MCP refine_masks 缝（Plan C T1-T3）

- 新 `LightamerCore/Sources/AI/MaskRefine.swift`：`fine(alpha: AIMaskPlane,
  guide: 平面, networkPx: Int, grow: Double, shrink: Double) -> AIMaskPlane`
  ——Lumen `selection.py fine()` 直译五步：①快速 alpha 升采样 + band =
  0.75 网络像素 + inside/outside erode（α≥.99 / α≤.01，椭圆核 2·band+1）
  → 不确定带；②带内 `_spread` 多尺度归一化卷积扩散前景/背景色（σ =
  band·{.5,2,8,32}，支撑不足逐级填充）；③投影混合比 alpha（`clamp(⟨guide−
  bg, d⟩/|d|²)`）+ 置信（残差与分离度式 `:194-198` 直译）；④门控（置信 ×
  max(边缘陡度, 照片细节) 钳制平方——宽缓坡保快速蒙版）；⑤混合 + 距离
  变换 smoothstep 过渡 + grow/shrink 钳。guide = 显影后显示域 ≤4096px
  （PipeCoordinator 预览档平面家族——1480px 档不够，限边解码 ≤4096 一档）。
- 实现域 = **Accelerate/vImage 全 CPU**（boxFilter=vImage tent、Gaussian=
  vImage、erode/dilate=vImage morphology、distanceTransform=两遍 chamfer
  自写 ~30 行、归一化卷积=vDSP）——**零新 Metal kernel**（
  Lut3dKernels.metal 零 diff 红线顺守）；MIT 归属头（特别登记二）。
- **与 logit-gain 羽化正交共存**：精细化产出更准 alpha 面（MaskRefine 输
  出），Edge 羽化（`AIMaskFeather` `:15-31`）仍在其上按用户半径作用——
  两缝零接触（`AIMaskFeather.swift` 零 diff）。
- 编排（App 侧）：单飞 + 等待队列（Lumen `auto_masks.py:121-219`
  `refine_masks_later` 直译）；完成 = 置换 layer 蒙版平面 + **一步
  history commit**（**复用 M6-4 既有蒙版 history 键族与 revision/epoch
  通道**——HistoryStack/LightamerSidecar/V50Order 零 diff 红线，蒙版置
  换非新 item 类型非新 params 面）；失败保快速蒙版 + toast（D-LU-7）；
  触发 = 分割成功自动（`mask.fineAuto`）+ 手动入口；sky 类参数化 grow/
  shrink（Lumen refine_fine .3/.02 先例值——参数面 execute 期 DECISIONS
  申报终值）。
- **MCP `refine_masks` 入 EditingToolset**（非 culling 域——D-LU-8 边
  界）：`EditingToolset.Seams` additive optional `refineMasks`（默认 nil
  ——`yiyinInjector`/`projectWriteProbe` additive `var` 先例同形，
  `EditingToolset.swift:91-118` 亲核）；nil = typed 不可用脸（headless/
  既有构造点零 diff）；渲染类串行 `McpRenderGate`（解码 4096px 属渲染
  级——`McpToolRegistry.swift:256` gate 先例）；**生产装配 = McpServerController
  makeEditingSeams（`:961`）内 additive 装配行恰一处 = FIX2③ 适配唯一
  例外**（勘误②——Seams 全部装配单点在该函数，红线 1 精确化）；工具面
  快照测试随批（`McpRegistrySnapshotTests` APP bundle 先例同域——工具面
  是安全面）。

## Hazards（三条，登记 + 消解绑定）

| hazard | 机理 | 消解绑定 |
|---|---|---|
| **H-LU1 分析任务与导出/AI 调度互斥面** | 分析趟若不设暂停 = 与导出渲染/AI 推理抢 CPU+IO（.lalb 读 + 内嵌预览解码），UI 卡顿 + 导出时长劣化；机器 16GB 上与重活叠加 = 单重活纪律破口 | Plan A T5：QoS `.utility` + 并发 cap 2 + 导出/AI 活跃挂起（BackgroundTaskRegistry 状态查询）/空闲恢复 + 进度/取消注册 + Settings 开关（D-LU-5）；单张不可读写空分析防重试风暴（Lumen :162 先例） |
| **H-LU2 `.lalb` v5→v6 迁移用户数据安全** | 迁移失败/半程 = 用户项目库不可开（数据面事故）；ALTER 非幂等重跑 = duplicate column 错 | Plan A T1：纯 additive 七列零回填零改列 + pre-migrate `sqlite3_backup` 快照自动 hook（ProjectFileStore:276 既有，零新机制）+ 幂等列探针 ALTER（:899-909 先例）+ ONE BEGIN IMMEDIATE 单事务 + 半程快照重跑干净测试（四代迁移先例同款断言族） |
| **H-LU3 float16 精度声明** | 缓存命中与未命中画面若不一致 = 「缓存不改变观感」承诺破产 + 用户可见回归；编辑平面被量化 = 逐位语义漂移 | Plan B T1/T3：quantize() 一致性规则（新解码也过 round-trip）+ round-trip golden 专测 + <0.05% 相对误差断言 + **编辑全分辨率工作平面零触**红线（缓存档位 = 预览/选片/重开；PixelPipe 封存零 diff 是结构面保证） |

## 转写勘误（RESEARCH → 本批 planner 亲核批，非矛盾、执行以勘误为准）

1. **FilterField 案数勘误（17 → 16）**：RESEARCH §UQ-LU2 缝位 6「
   FilterField 17 字段（`FilterPredicate.swift:54-70`）」= stale——实数
   **16 案**（`FilterPredicate.swift:54` enum 起，rating/colorLabel/
   keywords/flag/note/cameraMake/cameraModel/lensModel/iso/focalLength/
   aperture/exposure/captureDate/hasEdits/filename/dir，数案亲核；区间
   实到 :84）。对本批影响 = Plan A T7 加 4 案后 **20 案**（非 21）；引用
   一律 :54-84。
2. **EditingToolset.Seams 装配单点发现（FIX2③ 适配依据）**：RESEARCH 未
   载——`EditingToolset.Seams` 全部生产装配经
   `McpServerController.makeEditingSeams`（`:961`，GUI 侧
   `LightamerShell.swift:1112` 消费）单点；refine_masks 的生产缝供给必然
   在该函数内一行 additive 装配 → **FIX2③ 必须精确化**（红线 1：唯一例
   外 = Plan C 恰一装配行；lens 批「MCP 面零交集」前提在本批不成立）。
   additive `var` 默认 nil 先例（`yiyinInjector` :91-118）保证既有构造点
   （`:501/:634/:742/:830/:975`）零 diff。
3. **makeCullingContext 函数签名行微差**：RESEARCH 记 `:904-935`——注释
   区 :900-908、`static func makeCullingContext` 签名实位 **:909**；语义
   零差，仅引用修正。
4. **BackgroundTaskRegistry 行微差**：RESEARCH 记「:61-127」——protocol
   `BackgroundTaskHandle` :53、class `BackgroundTaskRegistry` **:80-127**
   ；语义零差，仅引用修正。
5. 其余抽核点全部吻合：`LibrarySchema.swift:116`（v5）/:278-307（images
   DDL——camera_make :283/camera_model :284/capture_date :290，**serial
   确无**）/:899-909（幂等 ALTER 先例）/:836-860（migrate 单事务纪律）；
   `ProjectFileStore.swift:276/:358-420`（快照 hook + backup 本体）；
   `LibraryStore.swift:116（createAlbum）/:455（setMetadataMarks）/:625
   （createStack）/:879（autoStack）`；`StackClustering.swift:20-64`（60s
   纯时间）；`ExifSearchIndexer.swift:123-161`（readProperties 无
   serial/SubSec 亲核）；`FilterSQL.swift`（FilterSortKey 白名单 + column
   拼写守卫）；`SessionThumbnailProvider.swift:144（720 常量）/:411-424
   （embeddedPreview）`；`LibraryThumbnailBridge.swift:5-31（双档注记）/
   :38-80（ThumbnailProductionGate）`；`CullingView.swift:30-37（paneCap
   2/1480px）/:91-120（错峰 + pair-identity task）`；
   `WorkspaceHostView.swift:432-449（libraryFace + onOpen→openEditor）`；
   `CullingToolset.swift:29-32（session 域绑定注记）/:68（decodeImage
   seam）/:1174+（list_bursts）/:1278+（get_face_regions）`；
   `AIMaskService.swift:68（AIMaskPlane）/:285（segmentSubject）/:350
   （segmentPatch）`；`AIMaskFeather.swift:15-31（logit-gain）`；
   `RAWDecoder.swift:120（decode 入口）`；`McpToolRegistry.swift:256
   （McpRenderGate）`；`Project.swift:298-817`（七测试 bundle 名）；
   `M2-4-0-BUNDLE-MAP.txt:352-370（LIB 域）/:294-335（LAYERS AI 族）/
   :196-227（APP MCP 族）`；`NOTICE`（无 Lumen 条目亲核）；基线
   4112/40/0（r12-repairs R3-ACCEPTANCE:8,:93 亲核）。

## 三 plan 红线 front-matter（共用正本，三 plan 逐条引用）

1. **FIX2③ 精确化（勘误②）**：`App/Sources/Lightamer/Mcp/
   McpServerController.swift` 零 diff，**唯一例外 = Plan C T3
   makeEditingSeams（:961）内 refine_masks 生产缝装配 additive 恰一行**
   （`:501/:634/:742/:830/:975` 等既有构造点零 diff；A/B 两 plan 全程
   McpServerController 零 diff）。触达例外之外任何 McpServerController
   面 = 停手上报 orchestrator（FIX2③ 修订属 orchestrator 权）。
2. **封存面零 diff**：`DrtPanelModel/DrtPanelView/DrtRecord/
   TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels.metal/
   DrtEotf/ExportQueueContract/六格式导出矩阵（ExportFormatSpec·
   ImageIOEncoders·WebPEncoder）/NodeGraphCommand/LightamerSidecar
   （schemaVersionCurrent 11 不 bump——分析产物全在 .lalb，本批零 sidecar
   面）/HistoryStack/HistoryHash/PipelineDocument（Core）/V50Order/
   GradeCatalog/Registry/ModuleInstance` 全程零 diff；本批零新 iop
   （V50Order 零新增）；Plan C 蒙版置换走 M6-4 既有蒙版 history 键族与
   revision/epoch 通道（X8）；`LibrarySchema.swift` 是 Library 域自有
   面（schema v6 = 本批正业，非封存面）；`AIMaskFeather.swift` 零 diff
   （X8 正交共存）。
3. **xcstrings 尾块纯插入**：新键一律 append 至 `Resources/
   Localizable.xcstrings` 的 `"strings"` 尾部（历史键字节与顺序零触碰）
   ；每批收尾 `Scripts/zh-audit.py --check` + `--self-test` 双 PASS；
   动态键一律显式 switch 返回静态键（V14）。
4. **LocalizationValue 禁形零命中**：`String.LocalizationValue("prefix_
   \(x)")` 插值动态查表键禁（M2-9 F-2）。
5. **L041 tuist generate 恒末位**：新测试文件 → `Project.swift` 对应
   bundle 显式数组（无 glob）同批更新 + `M2-4-0-BUNDLE-MAP.txt` 登记行；
   `tuist generate` = 该批最后一个动作。落域绑定：Library 域（schema/
   纯函数/服务/注记/FilterSQL）→ **LightamerTestsLibrary（LIB）**；
   Decode 域（SmartPreviewStore）→ **LightamerTestsIOP**；CullFace UI
   模型 → **LightamerTestsApp（APP）**；AI 蒙版族（MaskRefine）→
   **LightamerTestsLayers（LAYERS）**（AIMaskFeatherTests :296 先例）；
   MCP 工具面 → **APP**（McpRegistrySnapshotTests :221 先例）；跨 bundle
   零重域。
6. **机器级单重活 + 执行排程**：执行批一切重活（xcodebuild/test-direct/
   GUI 走查）起跑前必过 `Scripts/machine-guard.sh`（--wait 轮询）；
   **本批执行排 F0'-prod + LENS-01 验收链收口之后**（编排注记，链在飞 =
   等，不并行起跑）；构建产物交接不重建（BUILD-HANDOFF 形）。
7. **MIT 归属（不可延后件）**：SharpnessAnalyzer/Signature16 +
   BurstAnnotator（Plan A）+ MaskRefine（Plan C）文件头 = Lumen RAW
   上游版权声明 + 「算法思想与常量标定源自 LUMEN RAW（MIT），实现独立」
   注记；根 `NOTICE` 新增 Lumen RAW 条目（Plan A 随 T3 落地首条目，
   Plan C T1 复核同一条目覆盖三件）；零归属入库 = 流程违规。
8. **L013 StableHash**：跨进程身份哈希一律 StableHash（FNV-1a 64，
   decimal string 入 JSON）——BurstAnnotator 组 id（X4）；Swift `Hasher`
   与未排序 JSON 禁入任何身份面。
9. **L009 原子写**：SmartPreviewStore 平面文件与 index 写 = 同目录 tmp +
   原子晋升；禁 /tmp 跨卷 rename。
10. **默认中性零行为门**：A = 零分析产物行时网格/查询/渲染逐字节现状
    （`analysis_version` NULL 行 = 无注记无徽章）；B = SmartPreviewStore
    命中与否画面逐位一致 golden（H-LU3）+ 编辑工作平面零触；C = 未触发
    /失败态蒙版域零行为（保快速蒙版）；三 plan 各带默认中性负测。
11. **UserDefaults 新键登记制**：本批恰三键——`library.analysis.enabled`
    （Bool 默认 true，A）+ `previews.cacheMB`（Int 默认 4096，B）+
    `mask.fineAuto`（Bool 默认 true，C）；typed 读 + 注入式 defaults +
    body 零直读（KD-4）；键登记随各 plan DECISIONS 入 AGENTS.md 键族节。
12. **--all 批准制 + 运行监视**：orchestrator 批准 + 8G 门
    （RSS_LIMIT_MB=8192）+ MEMFAIL 机检 + caffeinate -dis 包裹 + 测试宿主
    清理先核 parentage（`ps -o ppid`，M2-7-3 先例）。
13. **C 档门控**：A→B→C 每 plan 执行+验收闭环后停汇报，等用户确认再放
    行下一 plan；C 与 A/B 无依赖、可独立换序（D-LU-9）。
14. **perf probe 纪律**：LU4 重开命中 ≤100ms 级 + LU5 精细化时长（Lumen
    33MP≈7s 参照）+ 分析趟吞吐——`LIGHTAMER_PERF_PROBE=1` +
    XCTSkipUnless（默认套件 skip）；探针读钟前 queue fence（L014——无
    fence 计时 = 假数）；skip 增量逐族申报。
15. **L057 缝**：一切文件面板走 `PanelPresentation.present` async 缝；
    `.runModal(` 在 `App/Sources` 零命中（本批预期无文件面板——Settings
    键均为数字/开关，红线预防性保留）。
16. **测试落域**：按红线 5 绑定表归唯一 target；BUNDLE-MAP 同批登记；
    跨 bundle 零重域；`tuist generate` 恒末位（红线 5 合并条款）。
17. **commit 纪律**：每任务独立 commit（Conventional Commits 全英文、
    只 add 相关文件、不 push、零 issue ref——规划文档免 issue 关联）；
    执行 commit 前缀 `feat(lumena)/fix(lumena)/test(lumena)/docs(lumena)`
    （A）/ `lumenb`（B）/ `lumenc`（C）。

## 测试策略（三 plan golden/集成面总纲）

- **BurstAnnotator golden（Lumen 同输入对照）**：MIT 合规直取其测试向量
  （v2.0.1 `tests/` annotate_bursts 向量集）；上游向量缺失时自织向量 +
  直译双实现对拍（execute 期取证申报）。覆盖：同机身 2.0s 阈内归组/跨机
  身不组/签名 MAD 判/副本排除（RAW+JPEG 对）/无 ts 永不组/best 睁眼优先
  /组内序稳定（Plan A T6）。
- **清晰度公式 golden**：Lumen `culling.py` 同输入对照（合成图样 +
  NumPy 参考输出双写——M2-4 golden 惯例）；标定锚点断言（1.2px 高斯模糊
  ≈55 分、2px≈30 分带内）；四方向表驱动（Plan A T3）。
- **闭眼眼睑比标定集**：数学面 CI 钉死（合成 landmarks 表驱动——睁/闭/
  侧脸漏检/左右取 max）；绝对阈值定标 = 10-20 张实拍人工标注样张
  （evidence 机制，不入 CI 门——LENS-04 T4 同款纪律），定标记录 + 阈值
  常量单源换发随 DECISIONS 申报（Plan A T4）。
- **缓存键/淘汰/共享并发测试**（Plan B T1/T2）：pack/unpack round-trip
  golden（float16 量化 <0.05%）+ 键失效（mtime/size/process version 变更）
  + LRU trim 90% 逐出序 + in-flight 同 key 合并 + 损坏重建降级直解码 +
  多消费方并发共享。
- **FilterSQL 四案智能相册集成测试**（Plan A T7）：建库 → 灌注记行 →
  createAlbum(filterGroup:) sharpness/faces/eyesClosed 直比命中/未命中 +
  hasBurst typed 不支持臂 + 注入列 NULL 行缺省语义。
- **迁移回归族**（Plan A T1）：v5 包开 v6（七列在位 + 旧数据零漂移）+
  幂等重跑（半程快照干净）+ 快照文件存在断言。
- **GUI 走查面**（execute/validate 道）：选片评级流（G/D/P/X/A 全键位）+
  C 对比缩放同步 + 徽章/折叠 + 重开命中探针（≤100ms 级）+ 蒙版精细化
  失败保底。

## 晨审推翻点索引（可推翻面速查）

- **D-LU-1**：主窗第三 face ↔ 独立 NSWindow（Lumen 忠实度高，成本高）。
- **D-LU-2**：虚拟折叠 + 手动转栈 ↔ 自动落 stacks 实体（语义污染）。
- **D-LU-3**：app 缓存目录 ↔ 包内 `.lapreviews/`（可移植性换随项目走）。
- **D-LU-4**：组内排序 + 校准集绝对提示 ↔ 砍绝对提示（徽章面消失）。
- **D-LU-5**：默认开 + 暂停语义 ↔ 默认关（提示面全哑）。
- **D-LU-6**：内存全尺寸 cap 2 ↔ cap 1（对比态换页抖动）。
- **D-LU-7**：自动精细化默认开 ↔ 只手动（收益归零）。
- **D-LU-8**：MCP culling 重挂后批 ↔ 本批加重挂（预算失控）。
- **D-LU-9**：单 phase 三 plan ↔ 拆二 phase / C 提前（C 提前合法）。
- **D-LU-10**：1600px 基准 ↔ 2560px（标定作废重做）。
- **红线 1**：FIX2③ 例外恰一行 ↔ 零例外（refine_masks 生产缝改走 GUI
  侧装配旁路 = 第二装配点，违单点纪律，不建议）。

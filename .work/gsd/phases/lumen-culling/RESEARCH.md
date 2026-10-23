# Lumen Culling 批 Research（UQ-LU1..LU5 五件一体）

> 阶段：research（纯只读文本侦察，零构建/测试/GUI）。
> 源 = Lumen RAW v1.7.0/v2.0.0/v2.0.1（MIT，可复制带归属）；正本增量 = `.work/gsd/research/LUMEN-RAW-NOTES.md` 2026-10-21 节 + UPSTREAM-QUEUE L60-64。
> 用户 2026-10-21 裁定：高价值（LU1/LU2）+ 中价值（LU3/LU4/LU5）五件全部落地。
> Lumen 本地克隆工作区停在 v1.6.2（`6a2b631`），五件代码以 `git show v2.0.1:<path>` 只读取证，未触碰其工作区。
> Lumen 引用行号 = v2.0.1 tag 文件行号；我方引用 = 本仓 HEAD file:line。

## Summary

- **LU2（清晰度+闭眼批量分析）是五件的底座**：分析产物（sharpness/eyes/signature）既喂 LU1 的 best-of-burst，又喂 LU3 的提示条与智能相册条件。算法面清晰度纯数学（MIT 可学可抄带归属）、闭眼走 **Apple Vision 原生 landmarks + 自算眼睑比**（Vision 无现成闭眼 API——见 §Vision 结论），零模型下载。
- **LU1 连拍分组在我方已有两处近亲**：`StackClustering`（纯时间阈值）与 MCP `list_bursts`（时间+型号）——但都缺序列号、签名相似与 best 选择；Lumen 的签名归组 + 睁眼优先算法可整件移植为 Core 纯函数。
- **LU3 选片视图的解码缝现成**：`SessionThumbnailProvider.embeddedPreview`（ImageIO 内嵌预览，10.6ms/张 @86MP 实测）就是 Lumen「相机内嵌预览零 RAW 解码」的同构缝，缺的是 ≥ 屏幕分辨率档位 + ±3 预读 LRU + 键位 UI + C 对比缩放同步。我方还有 legacy 会话域 `CullingView`（双Pane 对比先例）可作形态参照。
- **LU4 智能预览缓存 = 全新层**（我方只有缩略图级持久缓存 `.lathumbs`）：Lumen 的 float16+字节平面重排+zlib 持久 LRU 形态完整可移植；与 M2-3 档A（720px 内嵌）不同构——它是**解码级**缓存（1600px 线性 float），服务编辑重开/选片/MCP 三前门。
- **LU5 采样式抠图（`selection.fine`，MIT）是零新模型的 alpha 精细化**：不确定带内前景/背景色归一化卷积扩散 → 投影混合比即 alpha → 置信门控与快速蒙版混合。落点 = M6-4 蒙版管线的第二段（快速 Vision 分割 → 精细化），与 logit-gain 羽化正交共存。
- **关键架构缝（本批新发现）**：MCP culling 域 14 工具挂 **legacy session 域**（`McpCullingContext.store` = SessionIndexStore，`McpServerController.makeCullingContext`），默认项目 face（剥离门 false）下无 open session → 14 工具全答 `notSessionMember`。LU1/LU2 落 `.lalb` 后，MCP 面的重挂是独立决策（OQ-LU-8）。
- **推荐里程碑形态**：单 phase `lumen-culling` 三 plan 串行——A = LU2+LU1（分析地基+分组，ΔN≈12-15）、B = LU4+LU3（缓存底座+选片视图，ΔN≈14-18）、C = LU5（蒙版精细化，ΔN≈6-7）。C 与 A/B 无依赖可独立。
- **风险集中三点**：Vision 眼睑比阈值需自校准（Lumen 0.16 不可移植，但组内排序免阈值）；`.lalb` v6 迁移纯 additive（低风险，快照缝现成）；分析任务不阻塞 UI（QoS+暂停+注册表三防）。

## Sources

### Lumen v2.0.1 实读（`git show v2.0.1:` 取证）

| 文件 | 行 | 内容 |
|---|---|---|
| `lumen/culling.py` | 34-51 | 常量与导数核（SHARPNESS_EDGE=1600 / DETECT_EDGE=1280 / MIN_FACE=.03 / CLOSED=.16 / 四方向一阶二阶核） |
| `lumen/culling.py` | 68-94 | `sharpness()` + `signature()` 全式 |
| `lumen/culling.py` | 97-179 | `Faces`：YuNet 检测 + MediaPipe Face Mesh 478 点眼睑比 |
| `lumen/culling.py` | 199-210 | `analyse()` 总入口（view 级输入，无 RAW 解码） |
| `lumen/library_db.py` | 34-67 | SCHEMA=2 / ANALYSIS=1 / BURST_GAP=2.0 / BURST_DIFFERENCE=.6 / photos 列 |
| `lumen/library_db.py` | 822-900 | `signature_difference` / `_copy` / `annotate_bursts` / `annotate_hints` 全式 |
| `lumen/library_tasks.py` | 44-58, 141-200 | 3 低优先级线程 + `paused()` 停转 + `_run_analysis` |
| `lumen/preview_cache.py` | 41-49, 69-101, 117-227, 307-365 | LPV1 格式 / stamp 键 / pack-unpack float16 / LRU trim / in-flight 去重 / prefetch |
| `lumen/previews.py` | 182, 244-303 | VIEW_EDGE=2560 / `jpeg_view`（DCT draft）/ `embedded_view`（full_size=≥50% sensor px）/ `camera_view` |
| `lumen/cull_view.py` | 32-37, 67-132, 251-578 | VIEWS=14 / AHEAD=3 / FULL=2 / `full_view`（100% 优先内嵌全尺寸 JPEG）/ ViewLoader 双线程 / 全屏窗 + 键位 + 对比 |
| `lumen/selection.py` | 88-118, 122-252 | `refine`（1.6.1 导向滤波贴边）/ FINE_EDGE=4096 / `fine()` 采样式抠图全式 / `refine_fine`（sky grow=.3 shrink=.02） |
| `lumen/auto_masks.py`（v1.7.0） | 121-219 | `refine_masks_later`：独立线程单飞 + 等待队列 + raster 置换 + 一步 undo |
| `lumen/catalog.py` | 275-285, 360-392 | 智能相册字段语法（faces/eyes/sharpness/burst）+ 匹配语义 |

### 我方实读（file:line）

| 文件 | 行 | 内容 |
|---|---|---|
| `LightamerCore/Sources/Library/LibrarySchema.swift` | 116 | `schemaVersion = 5`（v6 = LU 迁移槽） |
| 同上 | 277-309 | `images` 表 DDL（camera_make/model 有、**serial 无**、capture_date REAL **无亚秒**） |
| 同上 | 418-441 | stacks/stack_content（M6-4 实体堆栈） |
| 同上 | 76-115 | v1→v5 迁移注记（additive ALTER + 快照缝先例） |
| `LightamerCore/Sources/Library/StackClustering.swift` | 20-64 | 纯时间阈值聚类（默认 60s，LightCraft 形） |
| `LightamerCore/Sources/Library/ExifSearchIndexer.swift` | 108-161 | `readProperties`：CGImageSource 元数据读（无 serial/无 SubSecTime） |
| `LightamerCore/Sources/Library/LibraryStore.swift` | 116-155, 879 | `createAlbum(kind:filterGroup:)` 智能相册 + `autoStack` |
| `LightamerCore/Sources/Session/FilterSQL.swift` | 58-76 | FilterSortKey 白名单 + `.library` 域 |
| `LightamerCore/Sources/Session/FilterPredicate.swift` | 54-70 | FilterField 17 字段（无 sharpness/faces/eyes/burst） |
| `LightamerCore/Sources/Session/SessionThumbnailProvider.swift` | 144, 411-424 | `embeddedPreviewMaxPixel = 720` + ImageIO 内嵌预览缝 |
| `App/Sources/Lightamer/Library/LibraryThumbnailBridge.swift` | 5-31, 129 | 档A/档B 双档 + .lathumbs 磁盘 + 内存 LRU + 生产门（≤4） |
| `App/Sources/Lightamer/UI/CullingView.swift` | 30-37, 91-120 | legacy 会话域双 Pane 对比（1480px 档、错峰解码、自拥有平面） |
| `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift` | 426-470 | `libraryFace` 装配（左网格 + 右 Inspector；onOpen/onAIUpscale/onAIDenoise 缝） |
| `App/Sources/Lightamer/MCP/Tools/CullingToolset.swift` | 29-32, 1171-1276 | culling 域 session 域绑定 + `list_bursts`（时间+camera_model，无签名无 best） |
| 同上 | 1281-1370 | `get_face_regions`：VNDetectFaceLandmarksRequest（~4ms/张实测）+ landmark 像素换算 |
| `App/Sources/Lightamer/MCP/McpServerController.swift` | 904-935 | `makeCullingContext`：session pair 注入，headless = `{ nil }` |
| `LightamerCore/Sources/AI/AIMaskService.swift` | 12, 143, 285-350 | Layer A（GenerateForegroundInstanceMask，macOS 15 struct API）/ Layer B（GenerateIterativeSegmentation）+ patch 组装 |
| `LightamerCore/Sources/AI/AIMaskFeather.swift` | 15-31 | logit-gain 负腿羽化（0.5 等值线保持） |
| `App/Sources/Lightamer/Library/BackgroundTaskHosting.swift` | 61-127 | BackgroundTaskHandle/Registry（进度+取消面） |
| Vision SDK（本机 macOS 27 SDK） | `VNFaceLandmarks.h:170-180` | leftPupil/rightPupil「may be inaccurate if the face isBlinking」（blink 概念内部存在、**未暴露 API**） |
| Vision SDK | `VNCalculateImageAestheticsScoresRequest.h` | 美学评分请求（macOS 15+，黑盒总分，本轮不立项、登记观察） |

## UQ-LU2 清晰度 + 闭眼批量提示（分析地基，先做）

### Lumen 实现面

- **清晰度**（`culling.py:68-87`）：输入 = 相机视图灰度（`camera_view` ≤2560px，零 RAW 解码）→ 缩到 1600px → 高斯 σ0.5（抑 JPEG 块/噪点）→ 32px 块上算四方向（0/45/90/135°）一阶/二阶导数能量比（固定 3×3 卷积核，`culling.py:46-51`）→ 结构块筛选（一阶能量 P75 且 >2e-5）→ 比值取 P90 → 四方向取 min → `log2` 映射 `(min+4)/5.5*100` 钳 0-100。标定口径：1600px 视图 1.2px 高斯模糊 ≈55 分、2px ≈30 分。**不依赖对比度**（雾天不算糊）、浅景深按主体算（结构最多块）、单向运动模糊可检出（min-of-4 方向）。
- **签名**（`culling.py:90-94`）：16×16 灰度 256 字节，INTER_AREA 缩放，喂 LU1。
- **闭眼**（`culling.py:97-179`）：YuNet（OpenCV FaceDetectorYN，1280px 上检测，长边 3% 门）→ MediaPipe Face Mesh 478 点（256×256 裁剪、先按双眼连线滚平再从自身点精化一次）→ 眼开度 = 上下眼睑点对距离均值 / 眼角距（`culling.py:141-145`，`CLOSED=.16`）→ `max(右,左) < 0.16` 判闭眼。模型共 2.7MB 离线。性能口径：61MP ARW 读 0.3s + 分析 0.2s。
- **入库**（`library_db.py:284-285, 656-677`）：photos 表 additive 列 `analysis INTEGER`(版本戳) + `sharpness REAL` + `faces INTEGER` + `eyes_closed INTEGER` + `signature BLOB` + `face_data TEXT`(JSON 框) ；分析版本号 `ANALYSIS=1`，旧结果版本落后即重算（`library_db.py:661-669`）。
- **后台执行**（`library_tasks.py:44-58, 141-200`）：3 条低优先级线程（QThreadPool LowPriority），三类任务优先级 = EXIF 索引 > 可见缩略图 > 选片分析；`paused()` 真（AI/导出期）即停、`kick()` 复启；不可读文件写空分析防重试风暴（`library_tasks.py:162`）；进度经 Qt signal。
- **智能相册语法**（`catalog.py:275-285`）：`faces:N` / `eyes:closed|open` / `sharpness>=N` / `sharp|blurry` 裸词；匹配在注记后的行对象上进行（`annotate_hints` 的 blurry = 绝对 <22 或低于组最佳 14，`library_db.py:882-900`）。

### Vision 原生能力结论（关键调查项）

- **Vision 没有公开的闭眼/眨眼 API**。本机 macOS 27 SDK `Vision.framework/Headers` 全清单核对：无 blink/eye-state 请求；`VNFaceLandmarks.h:170-180` 的 leftPupil/rightPupil 文档注明「may be inaccurate if the face **isBlinking**」——证明其模型内部感知眨眼，但**未暴露**。Web 交叉核对同结论（社区标准做法 = landmarks + 自算 eye aspect ratio）。
- **Vision 给的原料**：`VNDetectFaceLandmarksRequest` 76 点模型，含 `leftEye`/`rightEye` 轮廓 region（约 8 点/眼）+ `leftPupil`/`rightPupil` 单点；我方 `CullingToolset.get_face_regions`（`CullingToolset.swift:1281-1370`）已有整套调用 + 像素换算（含底左→顶左翻转），实测 ~4ms/张。**眼睑比可自算**：eye region 上下点对纵向跨度的均值 / 眼角横向跨度——数学同 Lumen，landmark 词汇不同。
- **替代 YuNet**：`VNDetectFaceRectanglesRequest` 原生人脸框（macOS 10.13+），零下载、零模型管理（M2AI 可选安装纪律零负担）。
- **精度差异要如实评估**：Vision 76 点 vs MediaPipe 478 点，眼睑采样密度低一个量级；Lumen 的 0.16 阈值是 MediaPipe 索引对标定集调出来的，**不可移植**。但 **best-of-burst 的睁眼优先只需要组内相对排序（max(右,左) 开度最大者优先），完全免阈值**；绝对「可能闭眼」提示才需要阈值——带小校准集定标（OQ-LU-4），初值借用 0.16 语义。
- **可加分项（登记不立项）**：`VNCalculateImageAestheticsScoresRequest`（macOS 15+，美学总分+utility 判定）——黑盒行为，与清晰度提示同台展示有解释性风险，列观察。

### 我方缝位与落点

1. **schema v6**（`LibrarySchema.swift:116` 下一档）：`images` additive 六列 `analysis_version INTEGER` + `sharpness REAL` + `faces INTEGER` + `eyes_closed INTEGER` + `signature BLOB` + `face_boxes TEXT`（JSON）。迁移走既有缝：`ProjectFileStore` 预迁移 `sqlite3_backup` 快照 → `migrate(from:to:)` 加腿 → 列存在性探针幂等 ALTER（`default_look_pending` 先例，`LibrarySchema.swift:908`）。零回填（分析趟懒填）。
2. **EXIF 增量**（喂 LU1，同批做）：`ExifSearchIndexer.readProperties`（:124-161）补读 `kCGImagePropertyExifBodySerialNumber`（TIFF/Exif 各最佳努力）→ `images.camera_serial TEXT` additive 列；补读 `SubSecTime*` 折进 `capture_date`（REAL 亚秒精度）——旧行懒回填（分析趟顺路）。
3. **Core 纯函数**（新 `LightamerCore/Sources/Library/CullingAnalysis.swift`）：`SharpnessAnalyzer`（vDSP/Accelerate 直译 Lumen 四方向公式，MIT 归属 NOTICE）+ `Signature16`（256B）；golden 测试用 NumPy 参考输出对拍（M2-4 golden 惯例）。
4. **闭眼分析**（Core，`LightamerCore/Sources/Library/EyeClosureAnalyzer.swift` 或并入上文件）：Vision landmarks → 眼睑比；注入式 request 工厂（测试合成面）。
5. **分析趟**（新 `LibraryAnalysisService`，Core actor）：扫描 `analysis_version < CURRENT AND missing=0` 行序 → ImageIO 内嵌预览读（复用 `embeddedPreview` 缝、max pixel 1600）→ sharpness/signature → 有脸再 Vision → `LibraryStore.setAnalysis` 批写。并发 2-3 Task QoS `.utility`；暂停语义 = 导出/AI 活跃时挂起（BackgroundTaskRegistry 状态查询 + 设置页开关，OQ-LU-5）；进度/取消挂 `BackgroundTaskRegistry`（`BackgroundTaskHosting.swift:80-127`）。
6. **智能相册条件**：FilterField 加 4 案（`sharpness`/`faces`/`eyesClosed`/`hasBurst`——`FilterPredicate.swift:54-70`）+ FilterSQL `.library` 域翻译腿（纯 SQL 可达部分：sharpness/faces/eyes_closed 直比列）；**burst/blurry 例外**：分组是查询期注记（Lumen 同形），`burst:best` 类条件无法纯 SQL——v1 智能相册只收纯 SQL 条件，`blurry` 的组相对部分留在选片视图提示条（OQ-LU-2 关联）。
7. **网格徽章**：LibraryGridView 行角标（可能模糊/闭眼/连拍序号）+ xcstrings 键族登记。

## UQ-LU1 连拍分组 + best-of-burst

### Lumen 实现面

`library_db.py:851-879` `annotate_bursts`（查询期纯函数，不落库）：

1. 排序键 = `(make, model, serial)` 三元组 + `captured_ts` + 文件名 tiebreak；无 ts 行永不归组。
2. **副本排除**（`_copy`，:838-848）：同一时刻（±1e-3s）+ 文件名 stem 前缀互含（`IMG_0001` vs `IMG_0001-Lumen`、RAW+JPEG 对）→ 不算连拍帧，看最近 3 个已收行。
3. 归组 = 同机身 + 相邻间隔 ≤2.0s + **签名相似**（16×16 各自零均值/单位方差（σ+4 防爆）后逐像素 MAD ≤0.6，:828-835）。
4. **best** = `max(睁眼优先, sharpness 降序, 组内序稳定)`（:876）；组 ≥2 才成组。
5. `annotate_hints`（:888-900）：blurry = sharpness <22 或（在组内且组最佳 − 自身 >14）。
6. UI 面：网格「3/7」序号 + best 标记 + 折叠；选片视图 ↑↓ 组间跳（`cull_view.py:491-504`）；智能相册 `burst` / `burst:best` 裸词。

### 我方缝位与落点

- **近亲盘点**：`StackClustering.swift:20-64`（纯时间 60s 阈值，M6-4 实体堆栈用）与 MCP `list_bursts`（`CullingToolset.swift:1171-1276`，时间+camera_model 2.0s，无签名无 best）都缺序列号/签名/best——**不改动两者**（语义不同：堆栈=用户实体、MCP=legacy 域），新写 `BurstAnnotator` Core 纯函数（`LightamerCore/Sources/Library/BurstAnnotator.swift`），Lumen 算法直译（MIT 归属）+ L013 纪律（组 id = StableHash decimal string，同 `list_bursts:1243` 先例）。
- **输入**：`LibraryQueries` 行集（camera_make/model/serial、capture_date、signature——LU2 产物）+ 评分/旗标列已在 `images` 表。
- **消费面**：① 图库网格折叠显示（虚拟折叠 = 查询期注记 + 行高亮「1/5」徽章，不建 stacks 实体——OQ-LU-2 推荐「虚拟 + 手动『转为堆栈』动作」复用 `LibraryStore.createStack`）；② LU3 选片视图组间跳转 + best 标记；③ best-of-burst = 睁眼排序（Vision 相对开度，免阈值）→ sharpness 降序。
- **域绑定**：作用于 `.lalb` 项目域查询面（`LibraryQueries`）；legacy session 域的 `list_bursts` 不动（剥离门语义）。

## UQ-LU3 快速选片视图

### Lumen 实现面

- **窗体**（`cull_view.py:251-349`）：独立全屏 `QWidget` 窗（`showFullScreen`），头栏（文件名/序号/EXIF/提示条/评级后前进开关/对比钮）+ 主 Pane（单/双）+ 底部胶片条（96px 缩略图）+ 键位帮助行。
- **零 RAW 解码**（`cull_view.py:67-80` + `previews.py:284-303`）：显示 = `camera_view`（RAW 取最大内嵌预览，`embedded_view`）经缓存 JPEG；100%（Z/单击）= `full_view` **优先全尺寸内嵌 JPEG**（`full_size` 判定 = 内嵌 ≥50% sensor 像素，`previews.py:269`），否则 RAW 解码显影（回落腿）；等原图期间放大显示 2560px 视图插值（`:170-176`）。
- **预读**（`cull_view.py:32-37, 411-430`）：ViewLoader 双线程 + LRU（视图 14 张 @2560 ≈13MB/张、全尺寸 2 张）；±3 张预读（低优先级尾部）；0.7s 悬停预解码（对应我方可省）。
- **C 并排对比**（`cull_view.py:451-489`）：左=选定右=候选，←→换候选、Tab 切评级侧、↑ 候选晋升为选定；**缩放与位置同步**（`sync_zoom` :476-483）。
- **连拍**：组内「3/7」+ best 标记 + ↑↓ 组间跳；**分析插队**（:426-429）：当前 ±(−2..+6) 窗内未分析行以 `first=True` 插队分析趟。
- **键位**（:529-578）：0-5 星 / P 留用 / X 排除 / U 取消 / 6-9 色标 / A 评级后前进 / F 人脸框 / Enter 显影 / Esc-G 返回。

### 我方缝位与落点

- **窗体形态（OQ-LU-1）**：三个选项——(a) **主窗 face 切换**（推荐）：`WorkspaceHostView` 加第三 face（library/editor/cull），与既有 library↔editor 路由（`WorkspaceHostView.swift:426-470` 的 onOpen → `workspace.openEditor`）同机制，零新窗口状态、Esc 回图库;  (b) 独立 NSWindow（Lumen 形；我方 F0' 壳 = NSApplicationDelegate + NSHostingView 单主窗，多窗要新增 window-controller 面）；(c) NSWindow 全屏 presentation。推荐 (a)，理由 = 机器单重活纪律下的资源确定性 + 既有 face 路由复用 + 键位聚焦面单一。
- **解码缝**：新 `CullViewLoader`（actor，App 侧 Library 域）——档位 = ImageIO 内嵌预览直读 `CGImageSourceCreateThumbnailAtIndex`（max pixel = 屏幕分辨率上限，2560 同 Lumen VIEW_EDGE；720 现档是缩略图档、不复用）；LRU 视图 12-16 张 + **内存级** 100% 全尺寸 ≤2 张（OQ-LU-6）；±3 预读（低优先级尾插，同 `LibraryThumbnailBridge.prioritize` 反向操作）。生产门复用 `ThumbnailProductionGate` 形（`LibraryThumbnailBridge.swift:38-80`，cap 2）。
- **100% 腿**：`full_size` 判定直译（内嵌 ≥50% sensor px——`CGImageSourceCopyPropertiesAtIndex` 比对 EXIF ExifImageWidth/Height 或传感器尺寸缓存）；无合格内嵌 → 回落 RAWDecoder 解码腿（档B 家族，走 LU4 缓存则命中）。
- **对比 Pane**：SwiftUI 双 `Pane`（legacy `CullingView.swift:30-120` 的错峰解码 + 自拥有平面纪律直接继承）+ 缩放/位置共享 state + Tab 侧切换。
- **评级写腿**：`LibraryStore.setMetadataMarks`（`LibraryStore.swift:455`）+ 评级后前进（A 开关）；胶片条复用 `LibraryThumbnailBridge` 96px。
- **提示条**：读 `sharpness/eyes_closed/blurry/burst` 注记（LU1/LU2 产物）。
- **MCP 不新增**（选片是 GUI 面）；`refine_masks` 属 LU5。

## UQ-LU4 智能预览缓存

### Lumen 实现面

`preview_cache.py`（441 行全读）：

- **三层内容**：①解码预览 = 线性 float 像素 **float16 量化 + 字节平面重排（低/高字节分平面提升 zlib 压缩率）+ zlib level 1** ≈7MB/1600×1067 + info JSON 头（`pack/unpack` :96-114，读 ~40ms）；②相机视图 JPEG q90（2560px）；③缩略图 320px 存 index DB。
- **缓存键**（`stamp` :69-76）：`normcase(resolved path)|size|mtime_ns|FORMAT|app version|language` → sha1——mtime/size 变更即失效，版本/语言入键（解码元数据受其影响）。
- **存储**：per-user 缓存目录（env 可覆写），`index.db` SQLite WAL（entries(key,kind,bytes,used) + thumbs(key,data BLOB)）；文件写 = tmp + `os.replace` 原子晋升（与我方 L009 同形，无跨卷问题——同目录内 replace）。
- **LRU**：默认 4GB（0=关，1-32GB 档），trim 到 90% 按最旧 used 逐出（:211-227）；每 16 次写触发一次 trim（:248-258）；内存 LRU 6 张 float32（≈20MB/张）+ **in-flight 去重**（同 key 并发解码合并 Future，:322-343）。
- **量化一致性**：`quantize()`（:79-81）对**新解码**也过 float16 round-trip——缓存命中与否画面逐位一致（相对误差 <0.05%）。
- **三前门共享**：编辑器/CLI/MCP 共用进程级 `default()`；prefetch 单线程逐张（:345-365）；缓存不可读写（权限/盘满）永不阻塞打开（降级直解码，:307-318）。
- 实测口径：重开 50ms / 预读命中 2ms（61MP 原解 1.9s）。

### 我方缝位与落点

- **层级判定**：M2-3 档A（720px 内嵌预览，会话内存+.lathumbs 磁盘）与 Lumen 1600px float16 **不同构**——档A 是「显示代理」，LU4 是「解码级缓存」（解码链出口的线性 float 平面持久化）。插点 = **解码链出口**：`RAWDecoder.decode`（`RAWDecoder.swift:120`）之上的新包装层 `SmartPreviewStore`（Core，`LightamerCore/Sources/Decode/SmartPreviewStore.swift` 或 Pipe/），消费方 = ①编辑器重开/切图（PipeCoordinator 载入腿）②图库档B 真渲染腿（`LibraryThumbnailBridge.RenderLeg` 生产侧）③LU3 的 RAW 回落腿 ④MCP `decodeImage` 腿（`CullingToolset.swift:106`——同进程天然共享，我方无独立 CLI 进程，「三前门」简化为「进程内三消费方」）。
- **格式**：直译 LPV1 形（magic+头长+JSON 头+平面重排 float16+zlib）；我方平面 = float32 RGBA premultiplied（管线纪律）——缓存态 = **working-space 线性平面 float16**，读回升 float32；量化一致性规则照抄（新解码也过 float16 round-trip）。**红线**：只在预览/选片/重开档位应用，编辑管线逐位语义不变（OQ 注记：DRT/film 尾平面不缓存——尾平面是显示格式，重算成本低）。
- **落点（OQ-LU-3）**：推荐 app 缓存目录 `~/Library/Caches/Lightamer/smart-previews/`（Lumen 同形：重建物、跨项目共享、不进 .lalb 包——包可移植性优先）；备选 = 包内 `.<stem>.lapreviews/`（随项目走但污染包目录 + 跨项目重开同源图无共享）。
- **键**：`sourcePath|size|mtime|process version（M6-2 per-photo process，sidecar v10）|缓存格式版本`——比 Lumen 多 process 维（我方特有），sha1。
- **容量**：默认 4GB 可调（Settings 页 + UserDefaults 键登记 `previews.cacheMB`）；index SQLite WAL + trim 90% 直译；损坏即删重建（cache rebuildable）。
- **测试**：pack/unpack round-trip golden + LRU 逐出序 + in-flight 合并 + 失效（mtime 变更）。

## UQ-LU5 AI 蒙版精细边缘

### Lumen 算法全读（`selection.py:167-219` `fine()`，MIT）

两段式：快速蒙版（网络 ~1s + 1.6.1 导向滤波贴边 `refine()`）→ 后台在原图（≤4096px，`fine_size` :226-229；显影+镜头校正后 `fine_guide` :232-239）精细化：

1. 快速 alpha 升采样到目标尺寸；`band = 0.75 网络像素`；`inside = erode(α≥.99)` / `outside = erode(α≤.01)`（椭圆核 2·band+1）→ 中间为**不确定带**。
2. 带内每像素颜色解释为**近邻前景/背景色的混合**：`_spread`（:138-154）= 多尺度归一化卷积（σ = band·{.5,2,8,32}，支撑不足逐级填充）从已知区扩散前景/背景色。
3. **采样式抠图核**：`d = fg−bg`；投影混合比 `projected = clamp(⟨guide−bg, d⟩/|d|²)` 即 alpha；残差与分离度给置信 `confidence = |d|²/(|d|²+.08²) · exp(−(residual/(.25|d|+.02))²)`（:194-198）。
4. **门控**：置信再乘 `max(边缘陡度, 照片细节)` 的钳制平方（:202-206）——蒙版宽缓坡（雾/深度/网络不确信）处颜色不可判 → 保快速蒙版；天空只在 ≥30% 置信处扩、暗树枝可从天空切出（`refine_fine` 的 sky `grow=.3, shrink=.02`，:242-252）。
5. 混合：色导向 alpha（`_guided`）与采样 alpha 按置信线性混 → 距离变换 smoothstep 过渡进已知区（:207-213）→ **grow/shrink 钳**（相对快速蒙版只能在其允许带内修正，:216-218）。
6. **编排**（v1.7.0 `auto_masks.py:143-201`）：独立线程（不占图像作业队列）、一次一档、后续请求排队；完成 raster 置换（含 NL 结果内同 raster 置换）= 一步可撤销 commit；失败**保快速蒙版** + 状态栏原因。33MP 点击到精细 ≈7s。

### 我方缝位与落点

- **两段式插点**：M6-4 快速段 = `AIMaskService.segmentSubject/segmentPatch`（Layer A/B + patch 组装，`AIMaskService.swift:285-350`）→ LU5 精细段 = 新 `MaskRefine`（`LightamerCore/Sources/AI/MaskRefine.swift`）：`fine(alpha: AIMaskPlane, guide: 平面, networkPx: Int, grow:shrink:) -> AIMaskPlane`。**零新模型**（Vision 结果即快速 alpha；Lumen 的「网络像素」概念映射为我方快速蒙版的生成分辨率）。
- **guide 腿**：精细化要「显影后显示域」原图 ≤4096px——管线等价物 = PipeCoordinator 预览档平面（1480px 档不够，需 ≤4096px 一档解码；与放大共用解码是 Lumen 语义，我方对应 = `RAWDecoder` 限边解码 + 现管线到显示域）。裁切/镜头状态对齐：我方 Vision 蒙版生于全辨析率请求 + patch ramp（M6-4 形态与 Lumen 320² 上采样不同），快速 alpha 分辨率本就较高——精细化的**增量收益**主要在发丝/枝叶级边缘，预期收益面比 Lumen 窄，但算法同形可用（判定维持「中」）。
- **与 logit-gain 羽化共存**：正交——精细化产出更准的 alpha 面，Edge 羽化（`AIMaskFeather`，`AIMaskFeather.swift:15-31`）仍在其上按用户半径作用；零冲突。
- **编排**：App 侧单飞 + 等待队列（Lumen 形直译）；完成 = 置换 layer 的蒙版平面 + **一步 history commit**（`EditorState.recordChange` 语义）；失败保快速蒙版 + toast。
- **MCP `refine_masks`**：EditingToolset 增工具（入参 = 蒙版 id 集合；渲染类串行 `McpRenderGate`——解码 4096px 属渲染级）。
- **实现选型**：Lumen 用 OpenCV（erode/dilate/boxFilter/GaussianBlur/distanceTransform）——我方零 OpenCV；Accelerate/vImage 可承载（boxFilter=vImage tent/convolve、GaussianBlur=vImage、erode/dilate=vImage morphology、distanceTransform=两遍 chamfer 自写 ~30 行、归一化卷积=vDSP）；全部 CPU 域，无 Metal 新 kernel（零新 kernel 红线顺守）。golden 对拍用 NumPy 参考移植。
- **性能**：≤4096px 钳底；实测目标（App SiliconAccelerate）待 execute 探针，预期与 Lumen 33MP≈7s 同量级或更优。

## 依赖与切分（plan 推荐）

```
LU2 分析地基（schema v6 + 分析趟 + Vision 眼睑比 + 智能相册 SQL 条件）
  └─> LU1 连拍分组（签名/闭眼/sharpness 全部消费 LU2 产物；EXIF serial/SubSec 同批）
LU4 智能预览缓存（解码出口层，独立成立但 LU3 的 RAW 回落腿直接受益）
  └─> LU3 选片视图（±3 预读/100% 腿/提示条消费 LU1 注记 + LU4 缓存；窗体 face 化）
LU5 蒙版精细化（全独立，仅共享 M6-4 蒙版域）
```

- **推荐里程碑形态（OQ-LU-9）**：**单 phase `lumen-culling`、三 plan 串行**（机器级单重活制排除了并行 plan）：
  - **Plan A「分析地基」= LU2+LU1**（ΔN≈12-15）：schema v6 + EXIF serial/SubSec + CullingAnalysis 纯函数族 + 分析趟服务 + BurstAnnotator + 智能相册 SQL 条件 + 网格徽章。P1 闭环判据 = 分析趟跑通全项目 + 智能相册「可能模糊/闭眼」可查 + 连拍折叠徽章可见。
  - **Plan B「选片视图」= LU4+LU3**（ΔN≈14-18）：SmartPreviewStore + 消费方接线 + CullFace（窗体/键位/对比/预读/组跳）。P1 闭环判据 = 全屏选片视图走通评级流 + 重开命中缓存 ≤100ms 级。
  - **Plan C「蒙版精细化」= LU5**（ΔN≈6-7）：MaskRefine + 编排 + MCP refine_masks。与 A/B 无依赖（可与 B 换序，若 LU5 优先级上升）。
- 拆两 phase 的备选（A｜B+C）仅在 A 体量失控时启用；五件共享 culling 域上下文与 xcstrings 键族，单 phase 内聚更省。
- **omp 复审三档适用**：A/B/C 各 research/plan/execute/validate 四道；research（本文档）/plan = 纯文本读评并行；execute 二次验收 computer-use 串行；validate 同前例。

## 风险

1. **`.lalb` schema v6 迁移**：纯 additive 六列 + camera_serial，零回填零改列；预迁移 `sqlite3_backup` 快照缝 + 幂等 ALTER 先例齐备（`LibrarySchema.swift:76-115`）——低。未来 schema 回退枚举（futureSchema typed refuse）不受扰。
2. **分析任务不阻塞 UI**：三防 = QoS `.utility` + 并发 cap（2-3）+ 暂停语义（导出/AI 期挂起，复用 `BackgroundTaskRegistry` 状态）；Lumen「3 低优先级线程 + paused()/kick()」直接映射；单张不可读写空结果防重试风暴（Lumen :162 先例）。图库滚动路径零接触（分析只写 DB，行更新经既有行变更通道）。
3. **Vision 眼睑比精度**：76 点眼轮廓 vs MediaPipe 478 点，绝对阈值不可移植——**主路径 = 组内相对排序（免阈值）**；绝对提示阈值带校准集定标（初值 0.16 语义，样本集 10-20 张人工标注，OQ-LU-4）；侧脸/大角度/遮挡漏检与 Lumen 同病（提示性语义、非判定性，UI 文案「可能闭眼」）。
4. **camera serial 缺失**：部分机身 EXIF 无 BodySerialNumber → 序列号 nil 回落 make+model（同型号双机身会误组——登记接受，真实拍摄场景罕见）；ExifTool 读法（Lumen）与 ImageIO 读法键名面需 execute 期按样张核对。
5. **SubSecTime 缺失**：无亚秒 RAW 同秒多帧排序退化为文件名 tiebreak（Lumen 同形：`_dt` 秒 + name tiebreak）——连拍间隔 <1s 的极端连拍可能跨组，登记。
6. **LU4 float16 视觉回归**：量化在解码出口统一应用（Lumen `quantize()` 先例）保命中/未命中逐位一致；相对误差 <0.05%（Lumen 实测口径，引用）；golden 对比测试钉。缓存档位不含编辑管线中间态（红线）。
7. **100% 内嵌 JPEG 可用性**：非全机型/全尺寸档有全尺寸内嵌（Lumen `full_size` = ≥50% sensor px 判定）——无合格内嵌回落 RAW 解码腿（走 LU4 缓存则命中）；CR3 HEVC 预览类死角在我方不存在对应问题（ImageIO 统一处理），但**需 execute 期抽验** Canon PQ 档内嵌可读性。
8. **缓存磁盘占用**：默认 4GB（app 缓存目录，重建物）；trim 90% + 每 16 写一巡；DerivedData >8GB 巡检告警纪律不受扰（缓存目录独立）。
9. **LU5 计算量与失败面**：≤4096px 钳；Accelerate 移植性能待探针（Lumen 33MP≈7s 参照）；任何失败保快速蒙版（Lumen 语义）——蒙版域永不因精细化失败而空。
10. **MCP culling 域域错位（既存事实，本批不修）**：14 工具绑 legacy session 域，默认 face 下 dormant——LU1/LU2 的 MCP 面（`analyze`/`bursts` 查询）重挂 `.lalb` 是独立决策（OQ-LU-8），不塞进本批 plan A。

## Open Questions（全带推荐）

| # | 问题 | 推荐 |
|---|---|---|
| OQ-LU-1 | LU3 选片视图窗体：主窗第三 face / 独立 NSWindow / 全屏 presentation？ | **主窗第三 face**（与 library↔editor 路由同机制、零新窗口状态、Esc 回图库；独立窗是 Lumen Qt 形态，我方 F0' 单主窗壳下多窗成本高） |
| OQ-LU-2 | 连拍折叠形态：查询期虚拟折叠 + 徽章（Lumen 形）/ 落 M6-4 stacks 实体？ | **虚拟折叠 + 「转为堆栈」手动动作**（堆栈 = 用户实体语义不污染；实体化走既有 `createStack` 一键） |
| OQ-LU-3 | LU4 缓存落点：app 缓存目录（跨项目共享、重建物）/ 包内 `.<stem>.lapreviews/`？ | **app 缓存目录** `~/Library/Caches/Lightamer/smart-previews/`（Lumen 同形；包可移植性；键含源路径+mtime+size+process 版本） |
| OQ-LU-4 | 闭眼绝对阈值口径：Vision 眼睑比自校准 / 只做组内排序不做绝对提示？ | **两者都要**：组内排序免阈值（best-of-burst 主路径）+ 绝对提示带 10-20 张校准集定标（初值 0.16 语义；校准集 = 我方实拍样片） |
| OQ-LU-5 | 分析趟开关与暂停语义：默认开 + 导出/AI 期自动暂停 + Settings 开关？ | **是**（Lumen 同形「AI/导出期暂停，可关」；挂 BackgroundTaskRegistry 进度/取消） |
| OQ-LU-6 | LU4 100% 全尺寸层：内存 LRU ≤2 张（Lumen FULL=2 形）/ 不做内存级全尺寸？ | **做**（选片 100% 对焦检查是硬需求；每张 150-200MB、cap 2 = 峰值可控） |
| OQ-LU-7 | LU5 触发形态：分割后自动精细化（Lumen fine_masks 默认开）/ 手动按钮？ | **自动（默认开）+ 「精细化所选蒙版」手动入口**（Lumen 同形；Settings 可关） |
| OQ-LU-8 | MCP culling 域重挂：LU1/LU2 的 MCP 查询面（`.lalb` 域）本批加 / 挂后批？ | **挂后批**（本批 GUI 优先；现 14 工具 legacy 域 dormant 是既存事实，重挂涉及域模型决策，独立小批处理） |
| OQ-LU-9 | 里程碑形态：单 phase 三 plan（A=LU2+LU1, B=LU4+LU3, C=LU5）/ 拆二 phase？ | **单 phase 三 plan 串行**（A→B→C；C 独立可换序；拆 phase 仅在 A 失控时启用） |
| OQ-LU-10 | LU2 清晰度分析基准图：1600px 内嵌预览灰度（Lumen 形）/ 我方 2560px 视图？ | **1600px**（与 Lumen 公式标定一致、公式参数直用；2560 档是 LU3 显示档，不混用） |

## 键族与登记预案（供 plan 引用，非本批动作）

- **UserDefaults 预登记**：`previews.cacheMB`（LU4）+ `library.analysis.enabled`（LU5→OQ-LU-5）+ `mask.fineAuto`（LU5→OQ-LU-7）——typed 读 + 注入式 defaults 惯例。
- **xcstrings 预登记**：`library_hint_blurry/eyes_closed/burst_index` 族 + `cull_*` 视图键族（plan A/B 各自尾块纯插入）。
- **NOTICE 归属**：SharpnessAnalyzer/BurstAnnotator/MaskRefine 三件算法源自 LUMEN RAW（MIT）——NOTICE 署名 + 「算法思想借鉴，实现独立」注记（与 spectral-film-lut 许可证登记同款流程）。
- **封存面核对**：本批零触及封存清单（DrtRecord/TerminalTailPolicy/PixelPipe/Lut3dKernels.metal/导出矩阵/sidecar schema……）——**sidecar schema 不动**（分析产物全在 `.lalb`）；V50Order 零新增；Lut3dKernels.metal 零 diff。

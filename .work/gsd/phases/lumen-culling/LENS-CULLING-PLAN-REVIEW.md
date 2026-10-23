# LENS-CULLING-PLAN-REVIEW — 图库选片批三 plan 独立 goal-backward 评审（2026-10-23）

> 评审对象：`CONTEXT.md` + `LUMEN-A/B/C-PLAN.md`（HEAD `ea89267f`）；上游 = `RESEARCH.md`（`ee73da34`）+ 产线源码 + Lumen RAW v2.0.1（`git show v2.0.1:` 只读取证，其工作区未触碰）。
> 评审方式：只读 + 本报告落盘；零源码触碰。坐标亲核 40+ 点（正反双向：我方产线 + Lumen 上游逐行）。

## 结论头

**PASS / 1 blocking + 5 major + 12 minor**

- **blocking 1 条**：blocking = plan 文本自身缺陷，**必须先修 plan 再执行**（修后按处方点改，无需全文重审）。本批其余面（迁移安全架构、ΔN 算术、编排兼容、直译骨架、坐标语料）经亲核**成立**。
- 5 major = 执行必然撞墙或裁决不闭环的面（都会在执行早期暴露/可修复，但 plan 文本须先改）。
- 12 minor = 转写细节、指针漂移、未申报的语义裁定点——随 DECISIONS 消化即可。

---

## 一、Blocking（1 条，先修后执行）

### B-1 sharpness 公式转写错位（X3 / Plan A SC+T3 / 风险面四处同源）

- **severity**: blocking
- **证据**：Lumen `culling.py:84-87`（v2.0.1 实读）：
  ```python
  levels.append(np.log2(np.percentile(second[strong] / first[strong], 90)))
  return float(np.clip((min(levels) + 4) / 5.5 * 100, 0, 100))
  ```
  即：**每方向先 log2(P90 比值) → 四方向取 min → (min+4)/5.5*100 钳 0-100**（log2 单调 ⇒ min(levels)=log2(min 比值)，两读法等价于 `(log2(min)+4)/5.5*100`）。
  而 `CONTEXT.md` §X3、`LUMEN-A-PLAN.md` front-matter SC、T3 action、§风险与回退四处一致写作 `log2((min+4)/5.5)*100` 钳 0-100——按自然解析 = log2 施加于 `((min+4)/5.5)`，**是另一个函数**：min 比值 =1 时 Lumen = (0+4)/5.5×100 ≈ 72.7 分，转写式 = log2(1)×100 = 0 分。`RESEARCH.md` §UQ-LU2 的措辞（"`log2` 映射 `(min+4)/5.5*100`"）歧义但偏正确读法；CONTEXT/plan 的记法把 min 与 log2 的先后写反了。
- **为什么 blocking**：D-LU-10 红线 =「公式参数逐字直译禁重标定」——plan 文本即规格；executor 按文直译会实现出错误曲线且 grep 机检（`log2` 命中）照样通过。golden 标定锚（1.2px≈55 / 2px≈30）最终会拦住它，但那是执行期返工 + 一次假阳性「golden 失配停手」。
- **处方**：四处统一改写为「各方向 log2(P90 比值) → 四方向取 min → `(min+4)/5.5*100` 钳 0-100」；T3 golden 补两分支转录：`strong.any()==false → 0.0`（`culling.py:83`）与 `min(gray.shape)<64 → nil`（`culling.py:79`）。

---

## 二、Major（5 条）

### M-1 T1 漏 `imagesColumns` 第二登记点（frozen contract 面 freezes 失配）

- **severity**: major
- **证据**：`LibrarySchema.swift:156-186` `imagesColumns` 数组（doc 自述 frozen contract）——`default_look_pending` **双点在册**（DDL `:307` + 数组 `:184`）。消费方 = 两个 frozen 测试：`LibrarySchemaTests.swift:114-118`（`testImagesTwentyNineColumnsVerbatim`）与 `LibrarySchemaV5Tests.swift:307-310`（`assertColumns(images, frozen: LibrarySchema.imagesColumns)`）。Plan A T1 SC 写「七列拼写各恰一处（**DDL 内**）」——只字未提 imagesColumns；按 SC 执行 → 实表 36 列 vs 数组 29 项 → **两个存量 frozen 测试必失败**。
- **处方**：T1 action 补第三步 = imagesColumns 尾段同批追加七项（`default_look_pending :184` 同位）；测试面 = 29→36 命名/断言更新（`LibrarySchemaTests` + V5Tests 冻结面）+ V6Tests 新冻结族；SC 的 grep 判据改为「七列拼写各恰**两**处（DDL + imagesColumns）」。

### M-2 Plan A 缺 App 装配面（分析趟无启动点 = LU2 P1 判据不可达）

- **severity**: major
- **证据**：`LibraryAnalysisService` 为 Core actor（Plan A T5，`LightamerCore/Sources/Library/`），但 Plan A `files_modified` **零 App 侧文件**（唯一 App 文件 = T7 徽章 LibraryGridView）。①服务的构造/启动点（项目打开事件、注入 store/probe/defaults、paused/auto 门）无归属——「默认开」（D-LU-5）与 research §依赖与切分 A 行 P1 判据「分析趟跑通全项目」没有装配就不发生；②「进度/取消挂 BackgroundTaskRegistry」——Registry 是 **App 侧** `@MainActor` 类（`BackgroundTaskHosting.swift:80-127`），Core 不可 import App，进度/取消注册必须经 App 侧适配 handle（protocol `:53`，register `:87`），该适配器文件不在清单。
- **处方**：T5（或 T7）补 App 侧装配件（形态 = KD-5 ShellView sink 装配先例 / shared holder 先例）：项目打开启动 + `library.analysis.enabled` 门 + 导出/AI 活跃探针注入 + Registry 适配 handle；`files_modified` 增列对应文件；测试补装配/门控面（APP 域）。

### M-3 D-LU-5「Settings 开关」行缺失（裁决不闭环）

- **severity**: major
- **证据**：D-LU-5 生效值 =「Settings 开关」；RESEARCH OQ-LU-5 推荐 =「默认开 + 自动暂停 + **Settings 开关**」。Plan A T5 只落 UserDefaults 键 `library.analysis.enabled`（typed 读 + 注入式），**无任何 Settings 页行任务**——对照 B T7（previews.cacheMB 行）与 C T4（mask.fineAuto 行）各有着落，A 独缺。键注册了但用户不可达 = 承诺面断一半。`App/Sources/Lightamer/Settings/SettingsPages.swift` 在库（已核实）。
- **处方**：Plan A 补 Settings 行（SettingsPages.swift additive 一节 + 标签/说明 xcstrings 两键），挂 T5 或 T7；红线 11 键族登记不变。

### M-4 FIX2③「makeEditingSeams 恰一行」机械不成立（改用 GUI post-assignment 形则 McpServerController 零 diff）

- **severity**: major
- **证据**：`McpServerController.makeEditingSeams`（`:961-987`）为静态会话域装配函数，形参仅 session/liveImageURL/yiyinInjector——**生产 refineMasks 闭包的原料（pipeCoordinator/EditorState）不在其作用域**。同域两先例：①yiyinInjector = makeEditingSeams 新形参 + `:984` 赋值（≥2 行 McpServerController diff，触 plan C 自己的「恰一行 = 停手」硬门）；②**projectWriteProbe = GUI 侧构造后 post-assignment**（`LightamerShell.swift:1112` 构造、`:1126` `editingSeams.projectWriteProbe = projectWriteProbe`）——refine_masks 的生产闭包只能在 GUI 域供给（编辑器态），②形**完全适配且 McpServerController 零 diff**，FIX2③ 根本无需开例外。勘误②「生产缝供给必然在该函数内一行」的前提判断有误（Seams 装配单点在 makeEditingSeams ✓，但**供给**可走 GUI post-assignment，先例在案）。
- **处方**：三 plan 红线 1 文本二选一改写：**(a)**（推荐）refine_masks 生产缝 = LightamerShell `:1126` 同款 GUI post-assignment ⇒ McpServerController **零 diff**、FIX2③ 零例外（更严于现条款）；**(b)** 保留 makeEditingSeams 形但例外改「签名参数(default nil) + 赋值行 = additive 恰两行」。orchestrator 裁定后同步 CONTEXT §红线 1 / 勘误② / Plan C T3 SC（「恰一行 diff」机检判据随之改）。

### M-5 Plan B/C 新测试文件路径为不存在的目录（违平铺惯例明文）

- **severity**: major
- **证据**：仓库测试**全部平铺** `Tests/LightamerTests/`，bundle 归属 = Project.swift 显式数组，三处同文注释「**No directory glob**: the 231 test files stay flat in Tests/LightamerTests/ and belong to exactly ONE domain target each」（`Project.swift:388-392`〔IOP〕、`:583-589`〔LIB〕、`:811-815`〔App〕）；`ls Tests/` = `Fixtures/ LightamerTests/ LightamerUITests/`，**无** `Tests/LightamerTestsIOP|App|Layers/`。Plan B `files_modified` 列 `Tests/LightamerTestsIOP/SmartPreviewStoreTests.swift`、`Tests/LightamerTestsApp/CullFaceModelTests.swift`；Plan C 列 `Tests/LightamerTestsLayers/MaskRefineTests.swift`、`Tests/LightamerTestsApp/…`×2——五个新路径全为不存在目录（Plan A 的 `Tests/LightamerTests/*.swift` 正确）。`Tests/LightamerTests/AIMaskFeatherTests.swift` 入 LightamerTestsLayers 数组（`Project.swift:525`）即「目录平铺 + 数组定域」的现形。
- **处方**：B/C 五个新测试路径统一改 `Tests/LightamerTests/<Name>.swift`；bundle 归属表述改「Project.swift 对应 target 数组显式行 + BUNDLE-MAP 登记行」（落域裁定不变：IOP/APP/LAYERS）。

---

## 三、Minor（12 条）

| # | severity | 位置 | 发现与证据 | 处方 |
|---|---|---|---|---|
| m-1 | minor | Plan A T1 回滚注记 | 「已迁移包回落 = v6 列残留无害——typed decode 宽容」机制误述：回退后 v5 二进制开 v6 包 = `LibraryError.futureSchema` 硬拒（`ProjectFileStore.swift:271-273` guard `stored <= schemaVersion`）。结论（单 commit 回滚安全、数据无损）不变 | 措辞改「futureSchema 拒开（by design），数据无损，新二进制重开即愈」 |
| m-2 | minor | Plan A T5/T7 | 「行更新经既有**行变更通道**通知」无既有机制：`LibraryStore/LibraryQueries` 零通知面（AsyncStream/NotificationCenter grep 空）；网格刷新靠调用方 reload（`LibraryGridModel.swift:169-194`） | T5 明示 additive 通知缝（或声明 stale-until-refresh 语义）+ T7 徽章刷新挂接点 |
| m-3 | minor | Plan A T6 golden | Lumen `tests/` 全清单核（v2.0.1 tag 38 文件）——**无 annotate_bursts 向量**；T6 golden 主臂（「直取其测试向量」）空，回落臂（自织 + 双实现对拍）实为默认路径。另 `tests/test_v170_masks.py` 有 4 个 fine-pass 测试（twigs/broad-ramps/guide-size/raster-blocks）可作 LU5 场景参照 | CONTEXT §测试策略措辞改「上游向量缺失（已核）→ 自织向量 + 直译对拍为正路径」；C T1 顺手参照其场景 |
| m-4 | minor | Plan C read_first | `auto_masks.py:121-219` = **v1.7.0 行号**；v2.0.1 实读 `refine_masks_later` 在 `:143`（区块整体后移 ~4-22 行）。RESEARCH 已正确标注（v1.7.0），C 的「`git show v2.0.1:` + :121-219」组合错配 | C 指针改「v2.0.1 `:143-219`」或「v1.7.0 `:121-219`」 |
| m-5 | minor | Plan A T6 比较器 | best 输入映射未钉：Lumen 用 `eyes_closed` 布尔桶（`library_db.py:876` `(not eyes_closed, sharpness, -index)`），我方 D-LU-4 主路径 = 相对开度 ratio 免阈值——「Lumen 同输入对照」在 best 维不可字面对拍。附两处直译细节未转录：`_similar` 对 nil 签名返回 True（`:825-827`，无签名行仍可归组）；组 id StableHash 的**输入内容**未定义（确定性面） | DECISIONS 钉：比较器形态（双字段 `(not eyes_closed, ratio, …)` 或 golden 语义换算）+ nil 签名行为 + 组 id 哈希输入（成员 id+机身+ts 的 canonical 串） |
| m-6 | minor | D-LU-2 UI 面 | 「网格折叠显示」未落具体行为（隐藏行 vs 徽章指示）；「转为堆栈」动作在 A T7 为「顺路最小接线，超出即停手上报」死胡同条款，B/C 无归属——裁决的实体化动作悬空 | A T7 显式收编（contextMenu → `LibraryStore.createStack :625` 一键）或 DECISIONS 声明降级挂账 |
| m-7 | minor | Plan B files_modified | T3 消费门①（PipeCoordinator 载入腿）与 T4 路由缝（图库 onCull 入口 → LibraryGridView/GridModel）文本均预见触达，但清单漏 `PipeCoordinator.swift` 与网格入口文件——与其自身「≤3 触点清单 DECISIONS 申报」自相矛盾 | B files_modified 补列（或注明「T3/T4 申报制触点」） |
| m-8 | minor | B/C 红线引用 | 编号错位：B/C 红线 front-matter 用**本地**编号，正文引用混用（C T2「禁新 history item 类型（红线 4）」实指 **CONTEXT** 红线 2 封存面——C 本地 4 = 失败保快速蒙版；B T3「红线 4」= 本地 MCP 条 ≠ CONTEXT 4 = LocalizationValue） | 统一引「CONTEXT 红线 N」全局编号 |
| m-9 | minor | Plan B T2 | SmartPreviewStore 四门共享前提 = **单实例**（index DB 句柄 + 内存 LRU + in-flight 表共享）；共享形态未钉。Lumen 进程级 `default()`；我方 shared holder 先例在案（M2-5 LutLibraryStore.shared + NSLock/replaceShared） | T2 补形态裁定（shared holder 形）+ 并发测试挂单例假设 |
| m-10 | minor | Plan B 范围 | Lumen 缓存三层（float16 解码面 + 2560 JPEG 相机视图 + 320 thumbs 入 index DB，RESEARCH §UQ-LU4）——plan 只移植 float16 层，2560 层弃（CullViewLoader 每次 ImageIO 直读，10.6ms/张可接受）、thumbs 层由 .lathumbs 承担——**弃层未申报**。附键维 mtime 精度（Lumen `mtime_ns`，`preview_cache.py:75`）未钉 | DECISIONS 声明弃层 + mtime 精度钉 ns（同秒连拍防撞） |
| m-11 | minor | Plan A T7 跨域外溢 | FilterField 为 Session/Library 共享 enum（CaseIterable）——加 4 案后 `.session` 域翻译臂与（若存活的）session 过滤 UI 面 behavior 未声明（SessionIndexSchema 34 列 frozen 契约无 sharpness 列，`.session` 臂必须 typed unsupported） | T7 补「.session 域四案 = typed unsupported 负测」；grep 机检加负向判据 |
| m-12 | minor | 勘误计数口径 | CONTEXT 头「转写勘误**四条**」vs 节内 5 条（⑤=其余吻合，非勘误）vs Plan A front-matter「勘误**五条**」 | 统一「勘误四条 + 吻合抽核记录一条」 |

---

## 四、亲核通过面（正面清单，反证未立）

### 4.1 我方产线坐标（26 点全中，勘误①②③④属实）

| 引用 | 实核 | 判定 |
|---|---|---|
| `LibrarySchema.swift:116` schemaVersion=5 | ✓ | 吻合 |
| DDL `:283 camera_make / :284 camera_model / :290 capture_date / :307 default_look_pending` | ✓（grep 定位逐点） | 勘误⑤吻合；serial 确无 |
| `:899-909` 幂等探针先例 | ✓（func `:902`、probe `:905`、ALTER `:908`） | 吻合 |
| `:836-860` migrate 单事务 | ✓（BEGIN IMMEDIATE `:847`、ROLLBACK `:861-863`） | 吻合 |
| `ProjectFileStore.swift:276` 快照 hook | ✓（dispatch `:265-295`、hook `:284-292`、轮换命名 `.pre-migrate.<stored>-<to>.bak`） | 吻合 |
| `:358-420` backup 本体 | ✓（`backup(to:)` `:362`、sqlite3_backup `:412-419`） | 吻合 |
| 勘误① FilterField 16 案 | ✓（cases `:55-70` 恰 16；FilterOp 至 `:84`） | **属实** |
| 勘误③ makeCullingContext `:909` | ✓ | **属实** |
| 勘误② 装配单点 `:961` + 构造点 `:501/:634/:742/:830/:975` | ✓（五点逐核；`:975` = `EditingToolset.Seams(` 构造） | **属实**（但见 M-4 供给形） |
| EditingToolset additive var 先例 | ✓（`yiyinInjector :91`、`projectWriteProbe :112`、`decodeLeg :95`） | 吻合 |
| `WorkspaceHostView.swift:432-449` libraryFace + onOpen→openEditor | ✓（`:428-452`） | 吻合 |
| 勘误④ BackgroundTaskHandle `:53` / Registry `:80-127` / register `:87` | ✓ | **属实** |
| `LibraryStore.swift:116/:382/:455/:625/:879` | ✓（createAlbum/INSERT/setMetadataMarks/createStack/autoStack） | 五点全中 |
| `StackClustering.swift:20-64`（60s） | ✓ | 吻合 |
| `ExifSearchIndexer.swift:108/:124`（ExifRead/readProperties 无 serial/SubSec） | ✓ | 吻合 |
| `SessionThumbnailProvider.swift:144（720）/:411-424` | ✓ | 吻合 |
| `LibraryThumbnailBridge.swift`（gate/RenderLeg） | ✓（gate init `:44`、RenderLeg `:87`） | 吻合 |
| `CullingView.swift:30-37（paneCap 2/1480px）/:91-120` | ✓ | 吻合 |
| `CullingToolset.swift:29-32/:68/:106/:1174-1194/:1281+` | ✓ | 吻合 |
| `AIMaskService.swift:68/:285/:350`；`AIMaskFeather.swift:15-31`（logit-gain） | ✓ | 吻合 |
| `RAWDecoder.swift:120`；`McpToolRegistry.swift:256`（McpRenderGate） | ✓ | 吻合 |
| 基线 4112/40/0 = r12-repairs R3-ACCEPTANCE `:8/:93` | ✓ | 吻合 |
| BUNDLE-MAP `:352-370` LIB 域（`:370` = LibrarySchemaV5Tests） | ✓ | 吻合 |
| NOTICE 无 Lumen 条目 | ✓ | 吻合（A T3 首条目成立） |
| `Project.swift:298-817` 七测试 bundle | ✓（IOPParity `:298` … App `:817`） | 吻合 |
| `FilterSQL.swift:58-76` FilterSortKey 白名单 | ✓ | 吻合 |

### 4.2 schema v6 迁移安全（架构面成立）

- 纯 additive 七列、frozen 前缀零触碰、零回填：与四代先例（v2 探针 ALTER `:902-909`、v3/v4/v5 `CREATE IF NOT EXISTS`）同构；ONE `BEGIN IMMEDIATE` + ROLLBACK（`:847-863`）= 半程原子；pre-migrate 快照自动 hook + 代际轮换（`ProjectFileStore.swift:284-292`）既有在产，T1 零新机制成立。
- **用户数据零丢失论证成立**：迁移失败 → ROLLBACK + 原文件未动；半程 → 同名快照清除断言重跑干净（M2-8-1 先例语义）；快照先于迁移产生。
- 附加亲核：FTS 触发器为 `AFTER UPDATE OF exif_search_words` 列限定（`LibrarySchema.swift:362-363`）——分析批写零 FTS 重建放大；`LibraryStore` 为 `public actor`（`:101`）——分析写与用户标记写同队串行，无写冲突（评审清单第 3 项并发面结构闭合）。
- 遗留给 M-1（imagesColumns）与 m-1（回滚措辞）。

### 4.3 Lumen 直译忠实性（v2.0.1 逐行）

- **annotate_bursts 五点全忠实**：排序键三元组+ts+文件名、无 ts 永不组（`:851-856`）；副本排除 ±1e-3s + stem 互含 + 最近 3 已收行（`_copy :838-848`）；归组同机身 + `0<=Δ<=2.0s` + `(x-mean)/(std+4)` 归一后 MAD≤0.6（`_similar/:830-836`，BURST_GAP/BURST_DIFFERENCE 常量 `:55/:61`）；best 元组 + 组≥2（`:876-879`）；blurry <22 / 组差 >14（BLURRY/BURST_BLURRY `:883-886`，annotate_hints `:889-900`）。L013 组 id = 我方域适配（`list_bursts:1243` 先例），合法偏离已声明。
- **preview_cache 直译忠实**：LPV1 magic/头长/JSON 头/字节平面重排（`reshape(-1,2).T`）/zlib level 1（`pack/unpack :96-114`）；quantize 对**新解码也过 round-trip**（load 路径 `rgb = quantize(rgb)` 先于缓存——H-LU3 一致性规则是 Lumen 原样，非我方发明）；stamp 键形 `:69-76`；LRU 4GB/trim 90%/每 16 写一巡（`:248-258`）；in-flight Future 合并（`:322-343`）；降级永不阻塞（`:307-318`）；prefetch 单线程（`:126`）；内存 6 张（`MEMORY_ITEMS :52`）。441 行全读声明属实。
- **cull_view/previews/library_tasks**：VIEWS=14/AHEAD=3/FULL=2（`:33-37`）；分析插队 `focus-2..focus+6` + `first=True`（`:426-429`）；sync_zoom（`:476`）；键位 Esc/G、Enter/D（`:552-554`——G/D 钉死是 Lumen 同形子集）；VIEW_EDGE=2560（`previews.py:182`）；full_size ≥50% sensor（`:269`）；paused()/kick()（`library_tasks.py:57`）；不可读写空分析（`:160-162`）。
- **selection.fine 五步**：SC 缩写与源一致（band `max(3, round(pixel*.75))`、erode α≥.99/≤.01 椭圆核 2·band+1、σ=band·{.5,2,8,32} 逐级填充、投影 `/(|d|²+1e-4)`、置信 `.08²/.25|d|+.02`、门控钳制平方、双 guided 混合、距离变换 smoothstep、grow/shrink 钳；sky .3/.02 = `refine_fine :250`）。
- 唯一实质转写缺陷 = B-1（sharpness）。行号唯一漂移 = m-4（auto_masks）。

### 4.4 ΔN 算术与编排（闭合）

- 分账：A 2..3+1..2+2..3+2+2+2+1..2+0 = **12..15** ✓；B 3..4+3+2+3..4+2+1..2+0..1 = **14..18** ✓；C 3..4+2+1+0..1 = **6..7** ✓；合计 **32..40** ✓；4112+32..40 = **4144..4152** ✓。A 终态带 4124..4127 ✓；B 终态带 4138..4145 ✓；C 换序先于 B（A+6..7=4130..4134 → +B 14..18）终带仍 4144..4152 ✓——换序稳健。
- 编排与机器级单重活兼容：A→B→C 串行、每 plan C 档门控停汇报、`depends_on`（B←A、C←A only）支撑「C 可垫底换序」条款；执行排 F0'-prod + LENS-01 链后 + machine-guard + --all 批准制 8G 门全部在条款内（红线 6/12）。

### 4.5 红线 17 条与勘误四条

- CONTEXT §红线 front-matter 恰 17 条（FIX2③/封存面/xcstrings/LocalizationValue/L041/单重活/MIT/L013/L009/默认中性/UserDefaults 恰三键/--all/C 档/probe fence/L057/落域/commit）——三 plan front-matter 逐条引用面覆盖完整；键族登记三键与 RESEARCH §键族预案一致。
- 勘误①②③④经亲核**全部属实**（§4.1 表）；⑤吻合抽核点抽验 12 处亦吻合。引用精度整体为近期 plan 批中最高之列——B-1/M-1/M-4/M-5 是仅见的四处实质失真。

### 4.6 评审清单逐项判定（对应任务书 9 项）

1. **schema v6 迁移安全**：架构成立（§4.2）；M-1（登记点）+ m-1（回滚措辞）+ 用户数据零丢失论证成立。
2. **BurstAnnotator 直译忠实性**：成立（§4.3）；m-5（best 比较器映射/nil 签名/组 id 输入）待钉；L013 兼容 ✓。
3. **LU2 三防 + 并发面**：QoS/cap/暂停/开关条款在（T5）；M-2（App 装配+Registry 适配缺失）为唯一断点；分析写 vs 用户标记写 = actor 串行无冲突 ✓；m-2（行变更通道）。
4. **LU4 SmartPreviewStore**：格式/键/zlib/round-trip/LRU/in-flight/降级直译忠实；键含 process version ✓；编辑平面零触红线有负测判据 ✓；m-9（单例形态）+ m-10（弃层/mtime ns）。
5. **LU3 选片视图**：第三 face 机制成立、2560 升档不复用 720 ✓、legacy CullingView 本体零触 + 纪律继承条款清晰（并存关系写清——session 域退役面 vs library 域新 face）；G/D 与 F0' 壳交接兼容性 = T5 表驱动 + F0' 先落地，兼容（建议 DECISIONS 记键捕获缝验证一笔，未计 finding）。
6. **LU5 MaskRefine**：五步 golden 可操作（NumPy 对拍 + m-3 的上游场景参照）；logit-gain 正交共存条款成立（AIMaskFeather 零 diff 双 plan 面核）；MCP 缝 = M-4（恰一行机械缺陷）+ FIX2③ 边界本身（EditingToolset 编辑域非 culling 域）判定正确。
7. **ΔN 算术与坐标抽查**：闭合（§4.4）；坐标 40+ 点亲核、4 处实质失真已列（B-1/M-1/M-4/M-5）。
8. **红线 17 条 + 勘误四条 + 编排**：成立（§4.5/§4.4）。
9. **遗漏**：RESEARCH 信息丢失面 = 无实质丢失（三层缓存弃层 m-10 为唯一未申报裁剪）；晨审推翻点索引完备（10 D-LU + 红线 1）；**分析开关 UX 落位缺失 = M-3**。

---

## 五、修复轮处方汇总（供 plan 修订最小集）

1. **B-1**：CONTEXT §X3 + Plan A SC/T3/风险面四处公式改写 + 两分支转录。（文本点改）
2. **M-1**：Plan A T1 加 imagesColumns 追加步 + frozen 测试更新 + grep 判据改「恰两处」。
3. **M-2**：Plan A 补 App 装配件 + Registry 适配 handle + files_modified 增列。
4. **M-3**：Plan A 补 Settings 开关行 + 两 xcstrings 键。
5. **M-4**：orchestrator 裁 FIX2③ 形态（推荐 GUI post-assignment ⇒ McpServerController 零 diff），同步三 plan 红线 1 + Plan C T3 SC 判据。
6. **M-5**：Plan B/C 五个测试路径改 `Tests/LightamerTests/` 平铺。
7. m-1..m-12 随各 plan DECISIONS/文本点改消化，不设独立修复轮。

修完 1-6 即可放行 LUMEN-A 执行（C 档门控照常）。

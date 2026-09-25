# Phase 9 计量基线（.work/09/perf.md）

> 记录约定（RESEARCH §7 / CONTEXT 继承定案）：**一切门数字在内置 SSD 上测得**（fixture
> 位于 `FileManager.temporaryDirectory`），UNITEK USB 卷只做记录性观测（L009——冷读
> ~250ms/文件前科，fixture 禁放 USB 卷跑门）。执行环境：macOS 27.0 / M4（LaniakeadeMac-mini）、
> Debug 构建（test-direct.sh 直启宿主）。门数字若后续需 Release 复核，按对应 plan 的
> 验收面标注执行。

## 开卷计量（09-01 T7）

| 项 | 口径 | 数字 | 判定 |
|---|---|---|---|
| 开卷 10k（暖索引，第二次开卷 = 重扫 + 零 diff） | SSD 临时目录 fixture、Debug、含扫描流 + 增量 diff 事务 + 回填空转 | **0.426–0.437s** | **≤2s 目标达成**（余量 ~4.6×） |
| 开卷 10k（冷，首次 = 全扫 + 10k INSERT + 回填两腿） | 同上 | **0.465–0.544s** | 记录不设门（RESEARCH §7：冷开卷只落账；USB HDD 冷盘为 L009 风险卷——分钟级预期，渐进 ingest 不阻塞开卷） |
| 渐进 ingest 生效性 | 结构断言：首页 256 行在**全树扫描结束前**吐出、总页数 ≥3 | `testScanIsProgressiveMultiPage` 绿 | 流式成立（9-3 网格边扫边出的缝已开） |

- 测试名：`SessionTreeScannerTests.testOpenSessionTenThousandWarmAndColdBaseline`
  （打印 `SESSION-OPEN-10k COLD/WARM seconds`）。
- 冷/暖差异小是因为暖开卷同样重扫全树（stat 10k 文件）——增量收益在「diff 零行时
  无 INSERT/UPDATE/回填」；真正的 USB 冷盘风险在 stat 本身（L009），渐进流式 +
  不阻塞开卷是对策，本 Phase 不设门。

## 索引 DB（09-01 T6）

| 项 | 口径 | 数字 | 判定 |
|---|---|---|---|
| 10k 行单事务 UPDATE（9-4 段2 演练：temp-table join 全量置 stale+dirty） | SSD、Debug、单事务含临时表构建 + 10k 行 INSERT + JOIN UPDATE | **0.0129s**（12.9ms） | dt 对标「sqlite 10k 单事务 <1s 量级」成立，余量 ~77×；PERF-07 段2 前提坐实（正式门 = 9-4 Release 万张 ≤5s） |
| 删库重建 parity | 50 张混合态 fixture（pristine/unedited/edited/编辑+2 层 sidecar、5 EXIF JPEG、5 孤儿 .lra）→ 删 `session.lindex` → 全扫重建 → 13 列 × 50 行逐列比对 | 全列相等（compared > 400） | SESS-07 门：索引可无损重建 |
| WAL 崩溃恢复 | 未提交事务句柄作用域销毁（进程内进程死亡等价）→ `PRAGMA integrity_check` | "ok"；已提交事务存活、未提交 INSERT 不可见 | 崩溃安全成立（WAL + synchronous=NORMAL 钉死） |

- 测试名：`SessionIndexStoreTests.testTenThousandRowSingleTransactionUpdateTiming`
  （打印 `BULK-UPDATE-10k single transaction seconds`）、
  `testDeleteAndRebuildParityColumnByColumn`、
  `testWALCrashRecoveryCommittedSurvivesUncommittedRollsBack`。

## PERF-06/07 状态（Phase 9 挂账）

- **PERF-06**（万张滚动 60fps）：基线计量义务在 9-3（grid + 缩略图管线落地后 signpost
  hitch 计量）；60fps 门在 Phase 15 清算。
- **PERF-07**（批量 apply 万张段1+段2 ≤5s）：正式门在 9-4；本 Phase 的 12.9ms 单事务
  计时为段2 前提证据。段3 sidecar drain 与缩略图再生只计量落账不设门。

## 执行环境注记（L009）

- 本仓库与常规工作卷 = `/Volumes/UNITEK`（USB HDD）。所有计时 fixture 建在
  `FileManager.temporaryDirectory`（内置 SSD）；跨机器复测口径：任何门数字必须在内置
  SSD 上复核后钉（本表即 SSD 复核值）。

## 浏览模式与缩略图管线(09-03 T8)

> 口径:SSD 临时目录 fixture、Debug 构建(test-direct.sh 直启宿主)、单测内
> ContinuousClock 计量(测试名见各条)。PERF-06 的 60fps 门在 Phase 15 清算
> (ROADMAP Phase 15 Notes);本表是工作基线。Release 分栏:Release 计量随
> Phase 15 门清算一并进行(当前执行流 Debug 直启,test-direct.sh 硬编码
> Debug 产物;Release 复核 = Phase 15 义务,届时跑 `-configuration Release`
> 后同款直启)。

| 项 | 口径 | 数字(Debug) | 判定 |
|---|---|---|---|
| 档 A 吞吐(嵌入预览) | 真 Sony 86MP ARW、`CGImageSourceCreateThumbnailAtIndex` @720、3 轮取最小 | **10.6 ms/张** | RESEARCH §5.2 预算 10-50ms/张 ✓(测试 `testThumbnailThroughputBaselineTierAAndTierB`) |
| 档 B 吞吐(真渲染) | 同源图、`RAWDecoder.decode` + display trio @ THUMBNAIL 360 + sRGB 转换,单次 | **2.87 s/张**(86MP,Debug) | RESEARCH 预算 0.5-2s/张量级(Debug 构建偏慢,Release 复核挂 Phase 15);磁盘缓存后二次浏览 0 渲染 |
| 10k 行 collection reload | `SessionIndexStore` ORDER BY path 全读 + 行投影 + 选择修复,单次 | **26 ms**(10,000 行) | 10k 内存数组零压力(RESEARCH §5.1)✓(测试 `testTenThousandRowCollectionReloadBaseline`) |
| culling 双 100MP 开启 | 真 GFX100S 100MP uncompressed ×2、错峰 decode(A 落地后 B 起)、Debug | **total 2.9 s**(paneA 1.5 s) | 错峰生效:首格 1.5s 内出图,不双解码风暴(Risk #6)(测试 `testCullingDualHundredMPStaggeredOpenBaseline`) |
| culling 常驻内存/平面 | gamma 尾 bgra8Unorm display plane @1480 长边 | **~5.8 MB/平面**(双格 ~12 MB 常驻) | D-09-CONTEXT-6 的 ~23MB/平面 = 瞬态 float32 工作平面(run 内 throwaway);常驻账本 12MB(测试 `MemoryBudgetTests.testCullingDualPaneLedgerStaysOnTheBudgetFace`) |
| LRU 逐出精确性 | 注入小预算逐出序列逐字节断言 | 逐出序列 + 驻留 ≤ 预算全等 | 防空转 ✓(`ThumbnailMemoryCacheTests` 7 tests) |
| 磁盘缓存规模估算 | 360px JPEG q85 | 实测单张 ~2-3KB(合成)/真图 30-60KB 量级;10k ≈ **0.3-0.6 GB 上限** | RESEARCH §5.3 预算内注记(删除行清理挂接已测) |

### 滚动 hitch(PERF-06 主项)

- **结构面已就位**:可见优先队列(跳队 + 跳空闲延迟)、LRU/磁盘两级命中、
  LazyVGrid 复用、渐进 ingest 占位。10k 行 reload 26ms 意味着数据面不构成
  hitch 源。
- **真机 hitch 计量**(滚动中 >50ms 帧间隙,PERF-04 signpost 方法)= 09-3
  T9 GUI 验收轮真机走查项,数字落 FINDINGS 09-3 节;60fps 门本体 Phase 15
  清算(挂账不变)。

### 双档观感抽检结论(09-03 T7 / DECISIONS D10)

- 实测 mean diff 74/52/61(ARW/NEF/RAF,8-bit 通道均差)——**可辨**。
- 根因证据:档 B = 编辑器同链同形渲染(Phase 8 GUI 截图同色调);差异 =
  v1 基础 trio 管线的色彩形态 vs 相机嵌入预览域,Phase 3+ 色彩 iop 校准后
  收敛。全走档 B 退路**否决**(10k × 秒级首扫与 PERF-06 吞吐冲突)。
- 常驻复核:`testDoubleTierVisualSpotCheckThreeRealRAWs` 随管线演进出真值。

## PERF-07 批量 apply 计量门（09-04 T5）

> 口径：10k sidecar fixture（8 字节原片占位 + 真 `.lra` JSON，apply 不解码原片）
> 建在 `FileManager.temporaryDirectory`（内置 SSD，L009——UNITEK 卷禁跑门数字）；
> Debug = test-direct.sh 直启宿主，Release = `xcodebuild build-for-testing
> -configuration Release` + 同款直启（hardened runtime 需以本地证书重签 +
> disable-library-validation entitlement 方可注入——一次性环境处置，未改工程）。
> 测试名：`Perf07MassApplyTests.testTenThousandMassApplySegmentOneAndTwoGate`
>（打印 `PERF07-GATE segments1+2 10k`）。

| 项 | 口径 | 数字 | 判定 |
|---|---|---|---|
| **PERF-07 门：段1+段2 万张**（内存 compose + 索引单事务） | **Release、SSD** | **0.419s**（composeSegment 0.409s + claim 0.010s） | **≤5s 门达成，余量 ~12×** |
| 同门 Debug 分栏（harness 锚定） | Debug、SSD | **0.518s**（compose 0.504s + claim 0.014s） | Debug/Release 几乎重合 → 瓶颈为 I/O+SQL 非 JSON 优化，门数字稳健 |
| 段3 sidecar 串行写队列 drain（10k） | Release、SSD、逐图 tmp 晋升 + journal + dirty 回写 | **6.23s（~1606 docs/s）** | 只记录不设门（RESEARCH §7；dt 把 XMP 同步放循环外同语义） |
| 段3 UNITEK（USB HDD）对照 | 100 张裸 JSON 写采样（顺序写，暖盘） | 0.44s（~0.2 ms/张；Debug 采样 0.87s） | 只记录标卷型（L009）；随机小文件冷态会更病态，渐进队列不阻塞 UI |
| 开卷 10k（fixture 首扫 + 全量 sidecar 回填解码） | Release、SSD | 1.37s | 非 gated 旁证（回填含 10k 次 sidecar JSON 解码） |

### 执行期发现（修复 + 决策）

- **段2 首版 O(n²) 实测（已修复）**：`claimBatchApply` 初版按「temp table + `WHERE
  path IN (SELECT …)`」形态写、且 per-row 重复执行该语句——SQLite 每次执行都全表扫
  `images` 再探 temp 表，10k² 次探测 = **77.5s（Release）**，且 Debug/Release 数字
  重合（77.0/77.5s）证明是算法问题而非优化问题。修复 = 单条 prepared
  `WHERE path = ?`（PK seek）在**同一事务内**执行 10k 次 → **0.010s**（~7700×）。
  「10k 行 = 一个事务」纪律不变；教训：批量 SQL 的 bulk-IN 形态只适用于**常量值集
  单次执行**，per-row 值必须走 PK seek 循环。
- **Release 直启注入的签名处置**：Release app 为 hardened runtime，注入
  libXCTestBundleInject 需 `codesign --force --deep --sign "Lightamer Dev"` +
  `disable-library-validation`/`allow-dyld-environment-variables` entitlements；
  每次 Release 重建后须重做（重签覆盖）。工程默认未改。
- 段3 SSD 吞吐 ~1600 docs/s ⇒ 万张 sidecar 落盘 ~6s（SSD）；USB 卷按 L009 预期
  分钟级——队列后台化 + 进度上报 + dirty 徽章即为该现实的 UI 对策（dt 同构）。

## PERF-07 门终值复核（09-05 T1，2026-09-26 01:0x）

> 9-4 验收必办项⑤「9-5 终账时以最终代码再复核门数字」。口径：**clean Release
> 构建**（`xcodebuild build-for-testing -configuration Release -derivedDataPath
> build`——增量 Release 构建曾产出 host/框架不一致产物，排障实录见
> 09-05-DECISIONS D-09-05-T1-2，终账以 clean 构建为准）+ 直启注入 + 内置 SSD
> fixture（L009）。测试名同门：`Perf07MassApplyTests.testTenThousandMassApplySegmentOneAndTwoGate`。

| 项 | 9-4 执行轮 | 9-4 验收复跑 | **09-05 终账复跑（clean）** | 判定 |
|---|---|---|---|---|
| 段1+段2 万张（Release/SSD） | 0.419s | 0.435s | **0.490s**（compose 0.476s + claim 0.014s） | **≤5s 门达成，余量 ~10.2×** |
| 段3 SSD drain 10k（只记） | 6.23s / 1606 docs/s | — | 8.683s / 1152 docs/s | 同量级（fixture 随机化噪声带内），不设门不变 |
| 开卷 10k 回填旁证（只记） | 1.37s | — | 1.599s | 一致，非 gated |

- 三轮同量级稳定（0.419 → 0.435 → 0.490），无漂移趋势，**门维持达成，不触发带病签核条款**。
- 直启注入布局增量（本轮固化，后续 Release 复测直接复用）：干净构建已自动内嵌
  `LightamerTests.xctest` 入 `PlugIns/`（Debug 同形）；需补三件 = `libXCTestBundleInject.dylib`
  （取自 Debug app）+ XCTest 依赖闭包符号链（XCTest/XCTestCore/XCUIAutomation/
  XCTAutomationSupport/libXCTestSwiftSupport → Xcode platform 目录）+ 本地证书重签
  （D-09-04-D9 惯例延续）。

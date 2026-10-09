# M4-1-02-ACCEPTANCE — 双重验收记录（dual_acceptance = true）

> 验收对象 = M4-1-02（TIFF 开发链切换与收口批 wave 2，7 commits
> `1b2b520..e6effc3`，基线 `1220581` = 01 收口 + zcode 验收 docs）。零共享上下文
> 独立验收：亲跑 + 亲读 + 逐 commit 边界核对，不轻信 SUMMARY/DECISIONS。验收日期
> = 2026-10-10 晨（build-for-testing @ HEAD exit 0 → 全套 `--all` 亲跑）。
> 首验路 = zcode（本文件）；omp 串行二次验收由 orchestrator 编排后在本文件追加。

## 结论

**zcode 路：PASS / 0 error + 0 minor + 3 observation（全部登记不修，不阻塞）。**

**omp 路（串行二次验收）：待 orchestrator 编排**——按 config `dual_acceptance =
true` 在本文件追加 omp 路结论后方可闭环；**VALIDATION 仅在双验收 PASS 后成文**
（当前在案 = 未成文，m1 工序正确执行）。

---

## §一 亲跑数字（全套 `--all` 独立复跑，对账 3335/16/0 逐位命中）

`caffeinate -dis xcodebuild build-for-testing`（exit 0）→
`caffeinate -dis Scripts/test-direct.sh --all`（1584s，exit 0，零 MEMFAIL）：

| bundle | 本验收亲跑 | 申报（DECISIONS §9） | M3 收口基线 | 判定 |
|---|---|---|---|---|
| IOP | **562/1/0**（peak 7531MB） | 562/1/0 | 483 | ✅ 逐位命中 |
| IOPParity | **427/3/0**（peak 6998MB） | 427/3/0 | 408 | ✅ 逐位命中 |
| Layers | **394/3/0**（peak 1138MB） | 394/3/0 | 378 | ✅ 逐位命中 |
| Library | **619/4/0**（peak 613MB） | 619/4/0 | 598 | ✅ 逐位命中 |
| Sessions | **279/4/0**（peak 1619MB） | 279/4/0 | 279 | ✅ 逐位命中 |
| Export | **350/1/0**（peak 6480MB） | 350/1/0 | 342 | ✅ 逐位命中 |
| App | **704/0/0**（peak 2831MB） | 704/0/0 | 686 | ✅ 逐位命中 |
| **TOTAL** | **3335/16/0** | 3335/16/0 | 3174 | ✅ |

- **对账链两式互证亲算**：逐 bundle 加总 562+427+394+619+279+350+704 = 3335；
  基线链 3174 + 102（01）+ 59（02 增量 = IOP +18〔RasterRouting 12 +
  RasterDecodeLeg +6〕+ Library +21〔16+4+1〕+ App +17〔7+5+5〕+ Export +3）
  = 3335，两式闭合。
- **L055 双保险亲核**：七 bundle 末条 Executed 行全挂总计段（562/427/394/619/
  279/350/704 逐条目验）+ 崩溃签名（`terminated abnormally` /
  `Restarting after unexpected exit`）七日志零命中。
- **7 新 suite 运行期 passed 行亲核**（时间戳 = 本验收轮）：RasterRoutingTests
  05:38 / ImportCategoryTests + ImportTransportTiffTests 05:52 /
  RasterRoundTripTests 05:58 / ImportCategorySelectorTests 06:02 /
  RasterEditFaceTests + RasterHdrViewportTests 06:03。
- **zh-audit `--check` 亲跑复现：PASS 1610 source / 1848 catalog**（逐位命中）；
  xcstrings diff = 425 insertions / 0 deletions，键级 +25 / 移除 0 / 既有键改动
  0（尾块纯插入亲证，Python 键级比对）。

## §二 翻转面审计（本波灵魂——E2 普查 + 抽样 8 文件逐个核处置）

**普查数亲测**：执行期基线 `1220581` 上 `git grep -l '\.tif\|\.tiff' -- Tests` =
**45 文件**；与 `decode(` 交集 = **17 文件**（精确命中）。DECISIONS §2 记
43/17——交集面一致，文件总数差 2（grep 口径差，`\ .tif` 前缀已覆盖 `.tiff`），
逐文件定性内容不受影响（obs-1）。

抽样 8 文件处置逐个核（覆盖 ①②两类 + 翻转 + 新增）：

| # | 文件 | 申报处置 | 亲核证据 | 判定 |
|---|---|---|---|---|
| 1 | VersionSwapTests（①） | JSON decode；.tif 仅临时文件名 | :138 仅 `appendingPath…(…).tif` 临时名 | ✅ |
| 2 | DrtViewportTests（①） | 合成 DecodedImage | :240 直构 `DecodedImage(`，零 decode 调用 | ✅ |
| 3 | ImportFilterTests（②翻转） | 恰一处原位改名 | `testNoExtensionAndNonWhitelistedFormatsRejected`：photo.tif 移出拒绝循环 + `XCTAssertNil(map["photo.tif"])` + 设计内翻转注记；其余四名仍 `.extensionNotWhitelisted` | ✅ |
| 4 | Fixtures/GoldenColorTests（②） | NeutralTarget 换容器 | `neutralTarget()` → `raster("NeutralTarget","png")`；PNG 18324B 在盘；「禁回转 TIFF」注记在（Fixtures.swift:112-114） | ✅ |
| 5 | HDRPipelineMatrixTests（②不改） | ①′ 矩阵支 | 本批 **empty diff**；torture :92-95 `writeFloatTIFF` → `RAWDecoder().decode` 回流在；IOPP 427/3/0 = E1 终证 | ✅ |
| 6 | ImportServiceTests（②契约钉） | C1 钉 `categories: .raw` | helper :116-118 显式传 `.raw` + RAW 时代计数注记 | ✅ |
| 7 | RasterDecodeLegTests（②golden 翻转） | 翻转 + 退役臂快照 | `testProductionDecodeRoutingTakesTheNativeLeg`（新腿）+ **`testProductionDecodeRoutingRetiredArmStaysReachable`：直调 `decodeRaster` → rasterColor/rasterNative 双 nil + ciImage 在 = pre-M4-1 快照钉** + windowedPayload 5 法（1:1 字节拷贝 top-first / 子窗 / box 平均 / 确定性 / 空窗 typed 拒） | ✅ |
| 8 | RAW03Tests（②不改） | row0=TOP 钉 | 本批 **empty diff**；pinned (x,y,value) 表在（:28）；全套绿 = 新腿与 CI 腿同向（top-first）的实测证据链，DECISIONS §3 成立 | ✅ |

**row0=TOP 证据链评价**：DECISIONS §3 的三段链（CI 腿自 02-06 全绿 → 首版
bottom-first 位移 8 行被 RAW03 抓 → 回退 top-first 逐位命中）与代码注释
（windowedPayload「TOP-ROW-FIRST」+ Fixtures「row 0 = image BOTTOM」终末腿注记
并存不矛盾）自洽；`testWindowedPayloadIdentityCopyTopFirst` 钉死输入面。

## §三 翻转本体读码核（T1/T2）

1. **decode() 分流序**（RAWDecoder.swift:135-151）：RAW（isRAWUTI）→
   **TIFF（isTIFFUTI → `RasterDecoder.decodeTIFF`）** → 其余 decodeRaster。
   `isTIFFUTI`（:427-431）= `public.tiff` identifier 等值 + conform 兜底。
   decodeRaster 本体零改 + :310-313 退役头注 + BandStreamer 头注刷新（亲读）。
2. **renderInputPlane 分派**（PixelPipe.swift:659-663）：`rasterColor != nil`
   分派于三 CI return 之前（checker m2 订正形态兑现——分派键非 rasterNative）。
   两子形（:714-762）：native → `windowedPayload` → `stage.run`；
   iccLutConverted → `renderConvertedCIPlane`（同三腿形态 + 同 dedupeKey）→
   `stage.runDisplayInverse`（TRC 恒等，RasterInputStage:84-97 缓存同契约）。
3. **windowedPayload**（RasterDecoder.swift:150-280）：top-first 循环 +
   **LE 读回**（sourceComponent 小端组装，DECISIONS §4 自抓 bug 修正形态在码）+
   1:1 纯拷贝 / box 平均（≤1px 取整）/ upscale nearest 兜底 + 探针 ≤4096 格。
4. **dedupeKey 折叠**（PixelPipe.swift:241-266）：亲对比 1220581 旧实现——
   nil descriptionHash 时新折叠序列 = 旧两元折叠（content → params）逐字节；
   `testFoldedDedupeKeyZeroDriftWithoutDescription` 以独立期望式机检同事实。
5. **JPEG/PNG/HEIC 零回退机检锚**：RasterRoutingTests 三法（:100/:108/:116）
   逐 UTI 断言 CI 臂形态 + `testPipeDispatchRidesTheRasterLeg` 用**判别值断言**
   （code-128 中心值 ≠ CI 腿 sRGB 线性化 0.2159，容差 0.02）——真判别非冒烟。
6. **E1 回流断言**：`testLinearICCFloat32ProductReentersSceneLinear`——
   BandStreamer 产品 → decode() → referral==.sceneLinear + transfer==.linear +
   rgb32Float；与 HDRPipelineMatrixTests 逐位基线（IOPP 全绿）互为表里，
   「IOP/IOPP 基线 × 路由翻转自洽」终证成立。

## §四 seed 三支 + 编辑面（T3）

1. `WorkspaceModel.seedRasterDrtRecord`（:295-303）：②非 raster 零动作 /
   ①carrier 已有零动作（restore·幂等先）/ ③derive → `setSessionDrtRecord`。
   **carrier-only 亲证**：`setSessionDrtRecord`（:267-273）只写 map，无
   scheduleSidecarWrite——sidecar 写腿只在 updateDrtRecord/drtRecordDidChange
   等既有 commit 面。
2. 调用点（PipeCoordinator:1227）：load 完成点、restore 腿后、首次 render 前；
   `syncDrtCarrierWithHistory`（:682-698）raster 臂 = history 无 record 时
   **derive 重铺替换 stale carrier**（undo 到顶 DRT 恒在，与 RAW 偏离登记）。
3. mint skip（EditorState:518-523）：`decoded.rasterColor != nil` → 跳过
   default look mint，日志行在。
4. RawDecodePanelView：rasterDescription 门二分——raster 走 readout 四行
   （profile/origin/transfer/peak，AX id 在）/ RAW 走 rawSections（原面板
   byte-identical 形态保留）。
5. **RasterEditFaceTests 7 法全真链**：零写断言 = 真 sidecar 路径存在性检查
   （300ms 静置后文件不存在）；restore 胜 derive = 真 write path 构造持久编辑
   + flushUntilPersisted + **fresh assembly 重开**；undo 到顶 / 幂等重开 /
   mint skip 各一。全套轮亲绿。

## §五 HDR TIFF 链（T4 + DECISIONS §6）

- iccLutConverted CI 臂走线亲读：decodeTIFF 头注（RasterDecoder:28-34）钉
  「LUT-ICC = 唯一 CI 腿」+ PixelPipe 逆腿接线（§三.2）——KD-1 唯一 LUT 面兑现。
- RasterHdrViewportTests 5 法亲绿：PQ/HLG fixture → derive(rec2020,
  st2084/hlg) → MTKView 16F + `wantsExtendedDynamicRangeContent` +
  `itur_2100_PQ/HLG` colorspace（真 CAMetalLayer 断言）；peak 1000/4000 贯通；
  ExportVariant.validate 峰值门零扰动；followGate 互斥。
- **SC#1 HDR 行**（RasterRoundTripTests:186-198）：rec2020/st2084 导出落地 →
  重导入断言 `origin == .iccLutConverted` + `transfer == .linear` +
  `rasterNative == nil` + primaries 经 `limitingSpace` 同秩——与 DECISIONS §6
  实测面逐字一致；srgbPiecewise 行 round-trip + γ22 行 u8Fixed8 网格
  （2.2→2.1992 邻域 <0.01）断言在。三行均经**真 ExportQueue**（enqueue →
  waitUntilIdle → done 态 → 落盘文件重 decode）。

## §六 导入面（T5/T6）

- ImportCategory OptionSet（raw=1/tiff=2/all）+ `library.import.categories`
  （ImportFilter.swift:283-297：缺键 = .all、域 0...3 外 = .all、setCategories
  全量替换）+ `LibrarySchema.tiffRasterExtensions = {"tif","tiff"}` 硬编码
  （:244，不入 rawExtensions——两键正交兑现）。
- ImportFilter ③ 改写亲读：①hidden ②sidecar 原样在前，③ TIFF 族先行 →
  掩码含 .tiff ? accept : `.excludedType`；RAW 白名单同式；其余
  `.extensionNotWhitelisted`（含无扩展）。`ImportProgress.excludedType`
  additive 缺省 0（:73-87）。
- 选择器 UI（ImportModeDialog:150-230）：两可勾族（checkbox + 计数）+ 其他
  类型不可勾（lock 图标）+ `importEnabled` 门；countText = **显式 switch 返回
  静态键**（V14 形态；插值只在 defaultValue 非 key——F-2 禁令合规）；
  `LibraryProjectController` 传 `categories: choice.categories`（T5 接线，
  ImportFilter.select 的 `categories: = .all` 缺省保既有调用零漂移）。
- ImportTransportTiffTests 4 法亲绿（move/copy/link 字节 + .lra 随行 +
  重复跳过 + link 外部替换 → 描述重解析）；ImportCategoryTests 16 +
  ImportCategorySelectorTests 5 亲绿。
- `library.import.rawExtensions` 正本零触碰：ImportDefaults whitelist 面
  逐行零改语义 + C1 契约钉 `.raw`（§二#6）。

## §七 红线机检（亲跑）

- `git diff 1220581..HEAD` 定向零 diff：**Aces2Kernels.metal /
  LightamerIOP/ / Sidecar/ / Pipe/History/ / Graph/DrtRecord.swift** 全零命中。
- 全量 changed 清单 40 文件 = front-matter ∪ SUMMARY 申报外扩 ∪ 两处登记缺行
  （obs-2）；无第六类越界面。
- 六格式导出矩阵零改动（产线 Export 文件零触碰；RasterRoundTripTests 为新增
  测试）；sidecar/`.lalb` 零 schema 变更（Sidecar/ 零 diff）。
- RAW 文档零变化：分派键 = rasterColor（RAW/CI-raster 路径不触）+ RAWDecoder
  RAW 臂零改；JPEG/PNG/HEIC 零回退 = §三.5 机检锚亲绿。

## §八 逐 commit 边界（7 commits，未 push）

| commit | 任务 | 文件数 | 判定 |
|---|---|---|---|
| `1b2b520` | T1+T2 合并（可构建性裁定，DECISIONS §1） | 17 | ✅ 边界内 |
| `db7f7dc` | T3 seed+门控 | 7 | ✅ |
| `ad9f7dc` | T4 HDR 视口 | 2 | ✅ |
| `a565f1e` | T5 导入掩码+选择器 | 10 | ✅ |
| `5790526` | T6 三模式运输 | 1 | ✅ |
| `ef0183c` | T7 SC#1 | 1 | ✅ |
| `e6effc3` | T8 docs | 5 | ✅ |

- 7 枚（派发令「八提交」为 T1..T8 八任务口径，T1+T2 合一后实发 7——SUMMARY
  同口径，无分歧）。commit message 与 plan 提交约定逐字同（全英文
  Conventional Commits）；逐枚 `git show --name-status` 无越界文件。
- T8 docs 三件套（SUMMARY/DECISIONS/GOAL-STATE/TODO/AGENTS）内容亲读：
  AGENTS M4-1 增量节 9 条与代码事实一致；GOAL-STATE/TODO 续接点与申报数字
  一致。VALIDATION 未成文 = m1 工序正确（双验收后才成文）。

## §九 observation（3 条，登记不修，不阻塞）

- **obs-1**：E2 普查总数口径差——执行期基线实测 45 文件含 `.tif/.tiff`
  （DECISIONS §2 记 43），交集 17 精确一致；差额为 grep 模式口径
  （`\.tif` 前缀匹配已覆盖 `.tiff`，两模式并集 ≡ 单模式），逐文件定性与
  处置内容零影响。
- **obs-2**：SUMMARY「申报外扩面」清单漏列两实触文件——`RasterDecoder.swift`
  （windowedPayload 本体；T2 任务行有提名）与
  `App/.../LibraryProjectController.swift`（T5 categories 传参接线；任务行仅
  写「runImport 传掩码」未提名文件）。逐 commit 边界零越界、内容全在任务范围
  ——纯登记面缺行，后续 plan 外扩面清单建议以 `git show --name-status` 逐枚
  机械导出为准（M4-1-01 obs-2 同族）。
- **obs-3**：IOPParity 峰值两轮方差——申报轮 8104MB（贴线 88MB）vs 本验收轮
  **6998MB**（余量 1194MB）；两轮均 <8192 门、零 MEMFAIL、零干预。14% 差超
  SPIKE ±3% 重测漂移注记的典型带（by-design GB 级重测顺序敏感），MEMFAIL
  机检兜底在位且两轮零触发——贴线记录保持，连续 MEMFAIL 才按 AGENTS 口径
  干预（本轮不构成）。

## §十 行为变化登记核（DECISIONS §7 三条全数在测试面钉住）

1. CMYK TIFF open 时 typed 拒 = `testCmykTiffTypedRejectSurfacesThroughDecode`
   亲绿（翻转前静默 CI → 现 decode 错误上浮，设计内）。
2. undo 到顶 raster 文档渲染恒 DRT = `testUndoToTopKeepsRasterDrtCarrier` 亲绿。
3. TIFF 无内嵌预览图库首屏（Tier A ImageIO 全解码缩小）= 登记观察项，不做
   后台预生成（plan 风险节兑现）；Tier A fallback 钉测
   （LibraryThumbnailBridgeTests:207）亲绿。

## §十一 验收批增量

本文件 + GOAL-STATE 验收条目（单 docs commit，未 push）。无产线代码触碰，
无测试修改。omp 二次验收由 orchestrator 串行编排后在本文件追加；双 PASS 后
VALIDATION 成文 → C 档停，等用户签核 M4-1 phase。

## §十二 M4-1 phase 终态意见（验收方）

- SC 三列可对表状态：**SC#1** = RasterRoundTripTests 3 法亲绿（真队列 + 描述
  一致 + 8e-3 带 + 编辑重放）；**SC#2** = 01 全矩阵在 IOP/IOPParity 本轮全绿
  再证；**SC#3** = RasterHdrViewportTests 5 法亲绿。数字门 3335/16/0 双路
  （执行 + 验收）命中；红线零 diff 双路亲跑。
- **zcode 路判定 = 具备签核条件**；phase 收官前置 = ①omp 串行二次验收 PASS
  ②VALIDATION 成文（SC 三列 + 基线对账链 3335）③C 档用户签核。遗留观察项
  （深影饱和中性化 / HDR TIFF LUT 臂面 / CMYK·16-bit gray typed 拒 UX /
  16-bit gray 补腿待供件）均已登记，不阻塞签核。

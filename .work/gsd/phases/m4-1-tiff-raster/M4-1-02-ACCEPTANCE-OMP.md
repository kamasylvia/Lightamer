# M4-1-02-ACCEPTANCE-OMP — omp 串行二次验收记录

> 验收对象 = M4-1-02（TIFF 开发链切换与收口批 wave 2，7 commits
> `1b2b520..e6effc3` + zcode 验收 commit `48b6485`，基线 `1220581`）。
> 独立第二遍：亲跑 + 亲读 + 实机走查，不轻信首验结论。
> 验收日期 = 2026-10-10 晨。派发程序五步逐条执行。

## 结论

**omp 路：PASS / 0 error + 1 minor + 2 observation。**

- minor-1：Export bundle `testEditReplaySurvivesFlushAndReload` 清理缺口——
  轮后在仓库 fixture 目录遗留 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`
  孤儿（28KB），且该孤儿确定性污染**下一轮** App bundle
  `testRestoreWinsOverDerive`（跨 bundle 轮间污染）。产线零影响，测试卫生问题，
  不阻塞签核（见 §一.3 + §六）。
- 与首验分歧点：见 §六（首验 obs-1 口径差确认；首验漏记本报告 minor-1；
  JPEG 走查项口径澄清；obs-2 增补一处）。

---

## §一 定向复跑（程序第 2 步）

### 1. Library bundle：619/4/0 逐位命中 ✅

```
BUNDLE|Library|619/4/0|peakRSS=612MB|82s|sampling=time
TOTAL|619/4/0|82s — OK (direct launch, no testmanagerd)
```

对首验 §一 Library 行（619/4/0，peak 613MB）：测试数/skip/fail 逐位一致，
RSS 612 vs 613MB（1MB 采样噪声）。

### 2. App bundle：干净树 704/0/0 逐位命中 ✅（首轮 704/0/1 系轮间污染，见 §一.3）

```
BUNDLE|App|704/0/0|peakRSS=2831MB|352s|sampling=time
TOTAL|704/0/0|352s — OK (direct launch, no testmanagerd)
```

对首验 §一 App 行（704/0/0，peak 2831MB）：四数**逐位一致**（含 peak RSS
2831MB 精确命中）。L055 双保险抽核：末条 `Executed 704 tests` 挂 All tests 段
（/tmp/la-direct-tests-App.log :1649/:1651），崩溃签名零命中（本轮亲跑日志）。

### 3. 首轮 App 704/0/1 根因：Export→App 跨 bundle 轮间污染（minor-1 证据链）

三轮对照实验（同一 HEAD `48b6485`，除孤儿文件外树零变化）：

| 轮 | 前置条件 | 结果 |
|---|---|---|
| R1 全量 App | 首验 `--all` 轮遗留 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 在盘（mtime 06:03:40 = 首验 Export bundle 窗口） | **704/0/1**：`RasterEditFaceTests/testRestoreWinsOverDerive` :192 失败——读回 `encodingSpace=rec709/peak=100`（孤儿 `.lra` 的 restore 值），期望 `p3d65/400`（editedRecord） |
| R2 定向 7 法 | 删孤儿后 | **7/0/0** ✅ |
| R3 全量 App | 干净树 | **704/0/0** ✅（轮后孤儿复现，mtime 06:23:53 = 本轮窗口——但 App bundle 内无写该路径的测试） |
| R4 定向 7 法 | R3 遗留孤儿在盘 | **7/0/1** ✅ 同失败复现（确定性） |

机制：

1. **写方** = Export bundle `RasterRoundTripTests/testEditReplaySurvivesFlushAndReload`
   （:288-291）：`source = fixture("srgb-matrix-8.tif")`（**仓库内 fixture 原路径**）+
   真 `LightamerSidecar.sidecarURL(for:)` 写腿 + `defer removeItem` 清理。
   defer 在"测试函数正常返回"时清理——但该测试在 CI 宿主直启环境下，
   轮后孤儿**稳定复现**（首验轮 + 本验收 R3 轮两次独立复现，mtime 均落 Export
   窗口）。defer 未生效的确切机制未深挖（候选：`flushSidecar` 的 hop Task 在
   tearDown 后仍落盘——write-behind 竞速；或 `XCTUnwrap`/断言抛错路径绕过——
   但本轮 Export 全绿，故更疑前者）。无论机制，**仓库 fixture 目录被测试写污染
   是事实**（`git status` 显 `?? Tests/Fixtures/TiffRaster/*.lra`）。
2. **读方** = App bundle `RasterEditFaceTests/testRestoreWinsOverDerive`（:173-195）：
   同 fixture 原路径 + 同 `.lra` 伴生路径。测试假设"起始无 sidecar"——先 forge
   editedRecord 落盘、fresh assembly 重开断言 restore 胜 derive。孤儿在盘时，
   first assembly 的 load 即 restore 孤儿值（rec709/100），随后
   `recordDrtChange(editedRecord)` 的 commit 语义被预存态干扰，second assembly
   读回 ≠ editedRecord → :192 失败。
3. 同文件 `testSeedIsCarrierOnlyNoSidecarWrite` 用 `no-icc-8.tif`（无写方污染）
   故不受影响；`testUndoToTopKeepsRasterDrtCarrier` 等内存态测试不受影响——
   与"恰一失败"吻合。

定级 minor（非 error）理由：①产线零影响（纯测试夹具路径卫生）；②单 bundle
内 / 干净树全套轮全绿（首验 `--all` 亲跑 3335/16/0 即干净树证据）；
③修复方向明确（写方改 tmp 域 fixture 拷贝——`DrtPersistenceTests` 的
`UUID().uuidString` tmp 面即先例；或读方 setup 先清孤儿）。**建议修复批**：
`testEditReplaySurvivesFlushAndReload` 首行加 `try? removeItem(sidecarURL)`
前清 + 改 tmp 拷贝（双保险），`testRestoreWinsOverDerive` 同加前清一行。
本验收后已删孤儿（树干净）。

### 4. zh-audit 复跑：PASS 1610/1848 逐位命中 ✅

```
zh-audit --check PASS (1610 source keys, 1848 catalog keys, zh complete, locale codes = {en, zh})
```

xcstrings 键级比对（Python 独立脚本）：移除 0 / 新增 25 / 既有键改动 0——
尾块纯插入亲证。25 键 = `import_dialog_types` + `import_type_*` 6 +
`rawdecode_raster_*` 18，与首验 §一一致。

---

## §二 实机走查（程序第 3 步）

通道 = DEBUG 构建（DerivedData `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`，
二进制 mtime 10-10 04:43，早于 HEAD docs-only commits——产线字节与 02 收口一致）
+ `-la_film_probe /tmp/omp-m4102-walk` 缝（stay-alive）。素材 =
`srgb-matrix-16.tif`（仓库 fixture 拷贝）+ `photo.jpg`（sips 转制）。
probe 日志（/tmp/omp-m4102-probe.log）：

```
[editor-probe] project created — importing omp-m4102-walk
[editor-probe] row id=1 file=srgb-matrix-16.tif sidecar=no ... iso=nil
[editor-probe] load file=srgb-matrix-16.tif loaded=yes rendered=yes texture=srgb-matrix-16.tif
[editor-probe] film page final = true — staying alive
```

`.lalb` 独立验库：`images` 表恰 1 行
`(1, 'srgb-matrix-16.tif', 'private/tmp/omp-m4102-walk/...', 'tif', None)`。

| # | 动作 | 证据 | 判定 |
|---|---|---|---|
| 1 | TIFF 导入 | probe `row id=1` + `.lalb images` 表 1 行 + 左列缩略图 `srgb-…` 蓝框选中 | ✅ 导入链通 |
| 2 | TIFF 加载渲染 | probe `loaded=yes rendered=yes` + 视口 64×64 彩条测试图正常显示（非黑屏/错色） | ✅ 新腿渲染 |
| 3 | DRT 面板活跃（raster「DRT 恒在」） | 点「显示变换」tab → 方法 ACES 2.0（蓝高亮）+ 编码空间 Rec.709 + EOTF Gamma 2.2 + 峰值 100 nits + 限色 Rec.709，全件活跃可编辑（非置灰） | ✅ 开箱即 DRT |
| 4 | 编辑（峰值滑杆拖拽 100→1000 nits） | 拖拽后读数 **1000 nits**；落盘 `/tmp/omp-m4102-walk/srgb-matrix-16.tif.lra`（23KB）：history 1 item（`更改显示编码`）position 0 + `displayTransform.peak_luminance=1000` | ✅ 编辑→commit→sidecar 全链 |
| 5 | JPEG「导入图库可浏览零回退」 | **口径澄清**：JPEG 从不在导入族内（`rejectReason` ③末行 `.extensionNotWhitelisted`，M2-2 既有语义；probe 行只列 tif；`.lalb` 无 photo.jpg 行）——故"JPEG 导入图库"非本批行为面。**零回退面** = decode 路由：`RasterRoutingTests` jpeg/png/heic 三法（CI 臂形态断言）在 R3 全绿轮内亲绿 + `testPipeDispatchRidesTheRasterLeg` 判别值断言（code-128 ≠ CI 腿 0.2159）在同轮亲绿 | ✅ 机检锚替代（见 obs-2） |

证据盘：`.work/gui-acceptance/m4-1-02/`（`omp-01-drt-active.png` 1354×931 /
`omp-02-peak-1000.png` / `omp-03-full.png` 1504×846）。走查后实例已 quit，
throwaway 项目与素材留 /tmp（`editor-probe-*.lalb*`、`omp-m4102-walk/`），
defaults 零触碰。

注：走查中 AI 标注 sheet（「用 AI 分析照片内容？」）遮挡视口——合成点击曾因
Retina 点/像素 2× 系数两度脱靶，改点坐标后一次命中「暂不」关闭；属走查环境
事项，与本批无关。

---

## §三 读码抽查（程序第 4 步）

四处全部亲读源码确认：

1. **`isTIFFUTI` conform**（RAWDecoder.swift:427-431）：`public.tiff` identifier
   等值 + `UTType(uti).conforms(to: .tiff)` 兜底；`decode()` 分流序（:137-151）=
   isRAWUTI → **isTIFFUTI → `RasterDecoder.decodeTIFF`** → decodeRaster。
   `decodeRaster` 本体零改（退役头注在 :310-313 已亲读——首验 §三.1 行号引用
   实为退役注记段，核对一致）。✅
2. **`renderInputPlane` 分派键**（PixelPipe.swift:659-663）：`image.rasterColor != nil`
   分派于三 CI return（:665/:687/:693）之前；两子形 `renderRasterInputPlane`
   → native 经 `windowedPayload` + `stage.run`、iccLutConverted 经 CI 转换平面 +
   `stage.runDisplayInverse`（RasterInputStage:84-97 缓存同契约亲读）。
   `windowedPayload` LE 读回（DECISIONS §4 修正形态在码）+ top-first 循环亲读。✅
3. **seedRasterDrtRecord 三支**（WorkspaceModel.swift:295-303）：② description nil
   零动作 / ① carrier 已有零动作（restore·幂等先）/ ③ derive →
   `setSessionDrtRecord`（:267-273 纯 map 写，无 scheduleSidecarWrite——
   carrier-only 亲证）。调用点 PipeCoordinator:1227（load 完成、restore 腿后、
   首次 render 前）；`syncDrtCarrierWithHistory` raster 臂（:682-698）=
   history 无 record 时 derive 重铺替换 stale carrier（undo 到顶恒 DRT）。
   mint skip（EditorState:518-523，`rasterColor != nil` 门 + 日志行）亲读。✅
4. **ImportCategory 缺键/域外双开**（ImportFilter.swift:57-63 OptionSet raw=1/
   tiff=2/all；:282-289 `resolvedCategories`：缺键 → .all，域外 → .all；
   :293-295 `setCategories` 全量替换）：判定序 ①hidden ②sidecar 原样在前
   （:96-109），③ TIFF 族先行 → 掩码判 `.excludedType`（:110-121）；
   `LibrarySchema.tiffRasterExtensions = {"tif","tiff"}` 硬编码（:244 亲读，
   不入 rawExtensions——两键正交）。选择器 `countText` = 显式 switch 返回静态键
   （ImportModeDialog:222-229，F-2 禁令合规——插值只在 defaultValue 非 key）。✅

抽查外溢（红线相关）：`BandStreamer.swift` diff = 纯头注 4+/1-（亲读 diff）；
ImportService diff = `excludedType` additive 字段（缺省 0）+ `categories: = .all`
缺省参（既有调用零漂移）；Export 产线目录零文件触碰。

---

## §四 红线机检（程序第 5 步）

基线锚 = `1220581`（首验 §七同锚）：

```
git diff --name-only 1220581..HEAD -- Aces2Kernels.metal LightamerIOP Sidecar Pipe/History Graph/DrtRecord.swift
→ 零命中 ✅
```

- 定向零 diff 亲跑：`Aces2Kernels.metal` / `LightamerIOP/` / `Sidecar/` /
  `Pipe/History/` / `Graph/DrtRecord.swift` 全零命中（命令输出首段空）。
- 全量 changed = 41 文件 = 首验 40 + 本验收已知 1（`M4-1-02-ACCEPTANCE.md`
  自身，属验收批 commit `48b6485`——逐 commit 边界 §五已单列）。
- 六格式导出矩阵：产线 Export 文件零触碰（RasterRoundTripTests 为新增测试文件）。
- sidecar/`.lalb` 零 schema 变更（Sidecar/ 零 diff）。
- 逐 commit 文件数复核：17/7/2/10/1/1/5/2（T1+T2 合并 17 枚内含 NeutralTarget
  容器对 + Tier A 钉测 + omp-minor-1 订正三件——与首验 §八一致，边界零越界）。

---

## §五 逐 commit 边界（独立复核）

`git show --name-only` 逐枚亲跑（8 枚含验收批）：

| commit | 任务 | 文件数 | 判定 |
|---|---|---|---|
| `1b2b520` | T1+T2 合并 | 17 | ✅ 边界内（含 RESEARCH-NOTES omp-minor-1 订正） |
| `db7f7dc` | T3 seed+门控 | 7 | ✅ |
| `ad9f7dc` | T4 HDR 视口 | 2 | ✅ |
| `a565f1e` | T5 导入掩码+选择器 | 10 | ✅（含 LibraryProjectController 接线） |
| `5790526` | T6 三模式运输 | 1 | ✅（Transport 测试独占；T6 零产线改=设计内） |
| `ef0183c` | T7 SC#1 | 1 | ✅（RoundTrip 测试独占） |
| `e6effc3` | T8 docs | 5 | ✅（SUMMARY/DECISIONS/GOAL-STATE/TODO/AGENTS） |
| `48b6485` | zcode 验收 | 2 | ✅（ACCEPTANCE + GOAL-STATE；无产线触碰） |

message 与 plan 提交约定逐字同（全英文 Conventional Commits）；未 push
（`git status` 工作区仅 3 个 untracked：本报告待写 + `dt-clone-archive/`
研究目录 + 已删孤儿——验收时孤儿已清）。

---

## §六 与首验分歧点 + 本路观察项

### 与首验分歧（4 项）

1. **minor-1（首验漏记）**：Export→App 跨 bundle 轮间污染（§一.3）。首验
   `--all` 为干净树首轮故未触发；任何**第二轮**（定向或全套）必现 704/0/1。
   首验 §九未登记——本报告补记为 minor，不阻塞签核（修复方向明确，见 §一.3）。
2. **obs-1 确认**：E2 普查 43 vs 45 口径差——首验归因（`\.tif` 前缀已覆盖
   `.tiff`）成立，本路不再复测（交集 17 为灵魂面，一致）。
3. **obs-2 增补**：SUMMARY 外扩面漏列 `RasterDecoder.swift` 与
   `LibraryProjectController.swift`（首验 obs-2）之外，`RasterColorDescription.swift`
   + `RasterColorDescriptionTests` + `RasterIccSemanticsTests` + RESEARCH-NOTES
   虽在 SUMMARY §「申报外扩面」第 4 条以 omp-minor-1 名义申报，但 plan
   front-matter `files_modified` 无此四项——属"申报了但 front-matter 未同步"，
   与 obs-2 同族（登记面事项，内容全在任务范围，边界零越界）。
4. **JPEG 走查口径澄清**：派发令「JPEG 导入图库可浏览零回退」中的"导入图库"
   在现行设计下不可达（JPEG 恒 `.extensionNotWhitelisted`，M2-2 既有语义，
   非本批行为）。本路以机检锚替代验证（§二#5：jpeg/png/heic 路由三法 +
   判别值断言在 R3 轮亲绿）+ 实机确认 JPEG 被拒（probe 行/`.lalb` 均无
   photo.jpg——**设计内拒绝，非回退**）。首验 §七「JPEG/PNG/HEIC 零回退 =
   机检锚亲绿」口径与本路一致，无实质分歧。

### 本路观察项（2 条，登记不修，不阻塞）

- **obs-omp-1**：`testEditReplaySurvivesFlushAndReload` 的 defer-cleanup 在直启
  宿主下疑似 write-behind 竞速（flush 的 hop Task 在 tearDown 后落盘）——
  若属实，同形态的真写腿测试（DrtPersistenceTests 等 tmp 面）虽无跨测污染
  （UUID tmp 路径），也可能留 /tmp 残余。建议修复批一并排查（低优先级）。
- **obs-omp-2**：IOPParity 峰值方差（首验 obs-3：8104 vs 6998MB）——本路未跑
  IOPParity bundle（派发令只定 App/Library），不追加数据点；首验处置口径
  （贴线记录保持 + MEMFAIL 兜底）认可。

---

## §七 验收批增量

本文件（`M4-1-02-ACCEPTANCE-OMP.md`）+ `.work/gui-acceptance/m4-1-02/` 三证据图。
无产线代码触碰，无测试修改。工作区清理：孤儿 `.lra` 已删，GUI 实例已 quit，
defaults 零触碰。双验收状态：zcode PASS（0E+3obs）+ **omp PASS（0E+1minor+2obs）**
→ VALIDATION 可成文 → C 档停等用户签核 M4-1 phase。

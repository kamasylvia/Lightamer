---
phase: m4-1
plan: "M4-1-02"
title: "TIFF 开发链切换与收口批（wave 2 = RESEARCH §6 W5..W6）——decode() UTI 分流（TIFF 整体切新腿；旧 CI 臂退役代码保留）+ PixelPipe input 装配接线（描述指纹入键 + 缩略图 Tier A/B）+ raster 默认 record 装配点（carrier-only seed / restore 优先 / sidecar 编辑后才写 + pristine 语义例外）+ defaultLook mint 跳过 + RAW Decode 面板门控 + 输入色 readout + HDR EDR 视口贯通 + 导入类别掩码/选择器 UI/excludedType 分账 + import 三模式验证 + round-trip SC 收口 + 全套回归"
wave: 2
depends_on: ["M4-1-01"]
autonomous: true
requirements: ["RASTER-IN-01（2026-10-08 收窄注记 = TIFF only）", "ALCE-02（推迟注记——零触碰）"]
estimated_tests: "+40..46"
test_bundles: [IOP, Library, App, Export]
files_modified:
  - LightamerCore/Sources/Decode/RAWDecoder.swift                # 修改：decode() UTI 分支插 TIFF 臂 → RasterDecoder.decodeTIFF（:135-140 分流点；decodeRaster 本体零改——退役保留）；isTIFFUTI 判定
  - LightamerCore/Sources/Pipe/PixelPipe.swift                   # 修改：run/renderInputPlane input 装配分派点（:628-664 三条 return 之前）——rasterColor → RasterInputStage（M3-3 封存面解封申报②本体，diff 收窄到该分派点）；inputPlaneDedupeKey 折叠描述指纹显式字段（L013）
  - App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift          # 修改：raster carrier seed 面（seedRasterDrtRecord——carrier-only，restore 优先，sidecar 编辑后才写；KD-2）
  - App/Sources/Lightamer/State/PipeCoordinator.swift            # 修改：load 路径 seed 调用点 + terminalTailPolicy 零改（carrier 已含 record 自动进 .drt 臂）
  - App/Sources/Lightamer/State/EditorState.swift                # 修改：defaultLookPending mint 点跳过 raster 文档（:434/:513 消费点 isRaster 门）
  - App/Sources/Lightamer/UI/Shell/RawDecodePanelView.swift      # 修改：raster 文档隐藏 WB/降噪/demosaic 控件 + 输入色 readout 行（profileDescription + origin 文案）
  - App/Sources/Lightamer/Library/ImportModeDialog.swift         # 修改：文件类型行（raw/tiff checkbox + 计数 + 其他类型计数不可勾；上游 §9.3 收窄形）
  - LightamerCore/Sources/Library/ImportFilter.swift             # 修改：ImportCategory 型 + categories 面 + Reason 增 excludedType（三序 ①②不动，③改类别掩码驱动；KD-4）
  - LightamerCore/Sources/Library/ImportService.swift            # 修改：categories 消费传入 + ImportProgress.excludedType additive 计数（缺省 0 零漂移）
  - LightamerCore/Sources/Library/LibrarySchema.swift            # 修改：tiff 域常量（{"tif","tiff"} hardcoded，不入 rawExtensions——两键正交，OQ-5）
  - Tests/LightamerTests/RasterRoutingTests.swift                # 新建（IOP/Core 级）：tiff→新腿 / jpeg-png-heic-webp→CI 通路零回退 / lut-icc→CI 腿 / 缓存键描述指纹折叠
  - Tests/LightamerTests/ImportCategoryTests.swift               # 新建（LIB/Core 级）：三序 × 类别掩码 / excludedType 分账 / 默认双开 / reset / 持久化 round-trip
  - Tests/LightamerTests/ImportTransportTiffTests.swift          # 新建（LIB/Core 级）：move/copy/link 三模式 TIFF 字节运输 + .lra 随行 + link 外部替换 → contentDedupeID 翻新 → 描述重解析
  - Tests/LightamerTests/ImportCategorySelectorTests.swift       # 新建（APP/App 级）：checkbox/计数聚合/记忆键读回/导入键 = 扫描完成 && 允许数 > 0
  - Tests/LightamerTests/RasterEditFaceTests.swift               # 新建（APP/App 级）：seed 语义三支（carrier-only/sidecar 编辑后写/restore 胜 derive）+ mint skip + 面板门控 + readout
  - Tests/LightamerTests/RasterHdrViewportTests.swift            # 新建（APP/App 级）：PQ fixture → DRT-HDR 视口臂（colorspace/16F）+ peak 贯通 + 手动 EDR 互斥零扰动
  - Tests/LightamerTests/RasterRoundTripTests.swift              # 新建（EXPORT/Core 级）：SC#1 导出×位深×ICC 抽样 → 重导入描述逐字段一致 + inverse→forward 带 + 编辑参数重放稳定
  - Tests/LightamerTests/LibraryThumbnailBridgeTests.swift       # 修改：TIFF Tier A 缩略解码 fallback 法（无内嵌预览常态）
  - Project.swift                                                # 修改：新测试文件登记（显式清单）+ tuist generate 恒为该批最后动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 修改：新测试文件增行（E2 纪律，随各自任务 commit）
  - AGENTS.md                                                    # 修改：M4-1 架构增量节（raster pristine 例外 / RGC-off 政策 / srgbPiecewise 注册 / 封存面解封注记收尾）
  - .work/gsd/phases/m4-1-tiff-raster/M4-1-02-SUMMARY.md         # 新建（T8）
  - .work/gsd/phases/m4-1-tiff-raster/M4-1-02-DECISIONS.md       # 新建（T8）
  - .work/gsd/phases/m4-1-tiff-raster/M4-1-02-ACCEPTANCE.md      # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收）
  - .work/gsd/phases/m4-1-tiff-raster/M4-1-VALIDATION.md         # 新建（T8——phase 签核面，SC 三列对表 + 基线对账链）
  - .work/GOAL-STATE.md                                          # 修改：续接点
  - .work/TODO.md                                                # 修改：M4-1 条目
  - .work/LESSONS.md                                             # 如踩坑
---

# Plan M4-1-02 — TIFF 开发链切换与收口批（W5..W6：路由切换 → 编辑/导入面 → round-trip 收口）

> **性质**：M4-1 后继 plan（依赖 M4-1-01 全绿）。本批执行**生产行为切换**：
> ①`decode()` UTI 分流——TIFF 整体进 M4-1-01 新腿（OQ-6 生效值：旧 CI TIFF 臂退役
> 但代码保留，dt 禁用纪律同款）；②raster 默认 record 装配点与编辑面（OQ-1 生效值
> 的生产落点）；③导入类型选择器（OQ-5/OQ-7 生效值）；④round-trip SC 收口 + 全套
> 回归。JPEG/PNG/HEIC/WebP/PSD 通路**字节零回退**为本批第一红线。
>
> 基线 = M4-1-01 收口值（3174 + 01 批增量，01-SUMMARY 记账后起算；SC 数字对账 =
> `--all` 终验轮亲跑 + BUNDLE-MAP×Project.swift×文件实数两式互证，M3-4-02 先例）。
> **全套 `--all` 轮 = orchestrator 批准 + 运行中保持监视 + MEMFAIL 机检**（AGENTS
> 资源监控口径；运行门 8G）。

## 已定裁决（生效值，硬约束，不得重开）

承接 M4-1-01 已列 1-4 号生效值；本 plan 承载：

5. **OQ-5 = 默认 raw+tiff 双开 + `library.import.categories` 新键**（掩码 Int：raw=1/tiff=2/缺省 3；ImportDefaults 全量替换 + reset 同族语义）；`library.import.rawExtensions` **正本不动**——tiff 不混入 RAW 表（两键正交）。
6. **OQ-6 = TIFF 编辑链路整体切新分支**（decode UTI 分流）；`decodeRaster` 退役代码保留（未来「快速浏览模式」可复活）；JPEG/PNG/HEIC/WebP 照走 CI 通路零回退；缩略图 Tier A（未编辑）ImageIO 缩略解码 fallback / Tier B（已编辑）pipe 新腿。
7. **OQ-7 = import 三模式零特例**（move/copy/link 纯字节运输 + `.lra` 随行照旧）；link 模式外部替换 → 描述 decode-time 重解析跟随（contentDedupeID mtime 腿）登记 by-design；进度计数分账 `excludedType` vs `extensionNotWhitelisted`（上游 excluded_type/unsupported 两计数的对应物）。

**红线（继承 01 全部 + 本批特有）**：sidecar/`.lalb` 零 schema 变更；`DrtRecord` 结构零改；导出矩阵六格式零改动；`Aces2Kernels.metal` 零 diff；IOP/IOPParity 逐位基线（**自洽条件 = 01 KD-1 ①′「linear ICC + float32 → sceneLinear」规则在位**——BandStreamer/StackMergeService 的 linear-Rec2020 float32 产品与 HDRPipelineMatrixTests 的 torture 源/merge 产品经 `decode()` 回流走**矩阵支**、不施逆 ODT；T1 回流断言 + T7 HDRPipelineMatrixTests 逐位亲证，checker E1）；legacy Sessions 导入面（`LIGHTAMER_LEGACY_LIBRARY=1` 回切通道）零触碰——选择器只落现行项目导入流；`library.import.rawExtensions` 既有测试面零回退（TIFF 类别是新增面，RAW 白名单语义原样）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 路由分流（T1，OQ-6 生效值落点）

`decode()`（RAWDecoder.swift:135-140）UTI 分支插入顺序：RAW → **TIFF**（`UTType.conforms(to: .tiff)` 族判定，含 `.tif/.tiff` 扩展与 `public.tiff` UTI）→ 其余 raster → `decodeRaster`（本体零改）。`decodeTIFF` 内部：描述 origin == `iccLutConverted` → CI 腿（`CIImage(cgImage:)` 全色彩管理——RESEARCH §3.2.4 唯一分叉；**该 CI 转换平面仍属 raster 文档——装配进 RasterInputStage 的 `raster_input_display` display 逆腿、TRC=linear 恒等（01 KD-5/KD-6 m4① 同款钉死），见 KD-3 分派规则**）；否则原生字节腿。**JPEG/PNG 零回退断言**：fixture 直驱 `decode()` 逐 UTI 断言返回面形态（CIImage 臂 vs rasterNative 臂）——防未来路由回归的机检锚。

### KD-2 raster 默认 record 装配点（T3，OQ-1 生效值的生产落点 + pristine 例外）

- **seed 语义三支**（`WorkspaceModel.seedRasterDrtRecord(url, description)` 单点）：
  ①sidecar 已有 drt carrier（恢复腿先跑）→ **restore 胜 derive**（用户历史编辑优先）；
  ②carrier 已有（重复 open 幂等）→ 零动作；
  ③都无 → carrier 写入 `RasterDefaultRecord.derive(from: description)`（**carrier-only：不触发 updateDrtRecord 写腿，sidecar 零写入**）。
- **pristine 语义例外（AGENTS 增量节必写）**：raster 文档「.lra 缺席 = 观感 pristine」的判定面**不变**（has_edits 仍按 history items/position）；变化仅是渲染面——carrier 有 derive record → `terminalTailPolicy` 自动 `.drt`（零代码改，:656 既有读取面）。用户不编辑 = 永不写 sidecar；编辑（含 DRT 面板任一 commit）= `updateDrtRecord` 既有 2s debounce 照常。undo 回到全默认档 = carrier 保持 derive record（渲染恒 DRT，Alcedo「DRT 恒在」语义；与 RAW 文档「undo 到顶 = 无 DRT 尾」的显式偏离，DECISIONS 登记）。
- **defaultLookPending mint 跳过**：EditorState mint 点（:434/:513 消费面）加 `rasterColor != nil` 门（上游 D2：中性 Color Grade，RAW default look 不套）。
- **seed 时序**：load 完成点（DecodedImage 在手、首次 render 之前）——PipeCoordinator load 路径单调用点；`drtEditSeed`（:713）在 seed 之后读，零时序竞争（同 actor 串行）。

### KD-3 PixelPipe 装配与缓存键（T2）

- `renderInputPlane`（:628-664）分派点（**三条 return 之前**——PixelPipe 无 `load(image:)` 函数名，真身 = `run(image:)` :686（:714 写 decodedImage）+ 装配腿 `renderInputPlane`）：`image.rasterColor != nil` → `RasterInputStage.makePlane(bucket:dedupeKey:)`（01 交付面）——**两子形**：`rasterNative != nil` = 原生字节上传腿；`origin == iccLutConverted` = CI 转换平面进 `raster_input_display`（display 逆腿、TRC=linear 恒等——01 KD-5/KD-6 m4①）；否则既有 CI render 腿字节原样。`inputPlaneDedupeKey`（:241）折叠**描述指纹显式字段**（`rasterColorDescriptionHash`——L013 字段显式纪律；`decodeParamsHash` 语义族，非 JSON 序）。

  > checker 回注（2026-10-09）：m2②——原「`load(image:)` 分派点」函数名在库不存在（grep 亲证）；分派点语义按真身锚改写（run/renderInputPlane，行号亲证）。分派键由 `rasterNative != nil` 改 `rasterColor != nil` 与 m4①/E1 一致（LUT-ICC rasterNative=nil 但仍是 raster 文档，须进逆腿）。
- **缩略图**：Tier A——`SessionThumbnailProvider.embeddedPreview` 对 TIFF 无内嵌预览常态走 `CGImageSourceCreateThumbnailAtIndex` fallback（App 侧纯 ImageIO，零管线路径）；Tier B——pipe THUMBNAIL 分辨率自动流经新腿（01 bucket-uniform 已备）。
- 内存纪律：u8/u16 原生深度上传到 linearize 为止（100MP u16 ≈800MB 瞬态，开发输出级缓存后 DecodedImage 释放）；float32 100MP ≈400MB/平面 + 工作面双份——贴 8G 运行门场景由 MEMFAIL 机检兜底（AGENTS 口径）。

### KD-4 导入类别掩码（T5，OQ-5/OQ-7 生效值）

- `ImportCategory` = OptionSet `{raw=1, tiff=2}`；`ImportDefaults` 增 `categoriesKey = "library.import.categories"`（Int 掩码；**缺键 = 3 双开**——OQ-5 默认值；typed 读 + 域校验 0...3，域外 = 缺席 = 双开；`setCategories`/`reset` 与 rawExtensions 同族全量替换语义）。
- `ImportFilter.select(urls, whitelist:, categories: = .all)`——判定序 **①hidden ②sidecar 不动**；③改写：ext ∈ {tif,tiff}（LibrarySchema 新 hardcoded 常量，**不入 defaultRawExtensions**）→ categories 含 .tiff ? accept : `.excludedType`；ext ∈ whitelist（RAW 族）→ categories 含 .raw ? accept : `.excludedType`；其余 → `.extensionNotWhitelisted`（含无扩展）。`Reason` 增 `excludedType` case（三序纪律与「LAST extension」契约逐字保留，既有测试面零回退——TIFF 双开缺省下旧断言中「tif 被拒」预期翻转为「tif 被受」，属设计内翻转，AC 逐条列名）。**翻转断言面（checker m3 亲证恰一处）**：`ImportFilterTests.testNoExtensionAndNonWhitelistedFormatsRejected`（:79-87，`photo.tif` 在拒绝循环内）——处置 = `.tif` 移出该循环或改判 accepted（新预期登记 AC）；tiff 双扩展变体（如 `photo.xmp.tif`）无第二断言面（亲证）；ImportServiceTests 的 `.tif` 运输 fixture（`shot1/shot2.tif` 噪声文件）随 T5/T6 翻转登记。
- `ImportProgress` 增 `excludedType: Int`（additive，缺省 0 = 既有档零漂移）；ImportService 分账填充。
- **选择器 UI**（ImportModeDialog 确认流）：文件类型行 = 每类 checkbox + 计数（计数 = `ImportFilter.select` 纯分账聚合，dialog 层零新扫描逻辑）；其他类型（jpeg/png/…）计数展示**不可勾**（上游 §9.3 收窄形）；导入按钮门 = 扫描完成 && 允许数 > 0。记忆 = 选择即写 `categories` 键（下次打开回读）。
- **legacy 面零触碰**：`LIGHTAMER_LEGACY_LIBRARY=1` 回切通道下的 Sessions 导入 RAW-only 原样（选择器只在现行项目导入流）。

### KD-5 HDR EDR 贯通（T4，OQ-4 生效值的生产落点）

- PQ/HLG fixture（01 矩阵在盘）open → derive record eotf ∈ {st2084, hlg} → 既有 DRT-HDR 视口臂自动激活（16F + EDR content + `itur_2100_PQ/HLG` colorspace——M2-6 交付面，本批零新建渲染代码）→ 断言面 = 视口 typed 状态（DrtViewportTests 同款断言形态）。
- **peak 语义贯通**：描述 peak → record.peakLuminance → EotfBox → 视口 headroom；`ExportVariant.validate` peak 闸门既有（nil 不触发）零扰动回归一条。
- **手动 EDR 互斥**：`followGateActive = !edrActive && !drtTailActive`——raster 默认 DRT 下手动 EDR 开关置灰纪律零改动（互斥回归既有面 + raster 一条）。
- scene-linear float32 内容探针旗标（>1.0）→ 文档 HDR readout 面（面板 readout 行随 T3 落地）。

### KD-6 round-trip SC 收口（T7，charter SC 对表）

- **SC#1 round-trip**：导出（`enqueueExportM2` 既有链，drd 恒装配）→ 位深 {8,16,32F} × ICC {sRGB, P3, Rec2020} 抽样 → 重导入 → 描述逐字段一致 + inverse→forward 像素带（01 实测带为门）+ 编辑参数重放稳定（.lra save→reopen→replay 像素一致）。**32F 行走 display 分支注记（checker E1）**：我方导出链 `DrtOutputColorSpace` 对 `.linear` 全空间 throw illegal（:72/:83/:92/:101/:112/:121 亲证）——导出从不产出 linear-ICC 文件，SC#1 的 32F 行恒携 gamma/piecewise TRC ICC → 重导入走 display 逆腿（逆→forward 像素带测试不经矩阵支，与 01 KD-1 ①′ 零冲突）。
- **SC#2 ICC 语义** = 01 T3 全矩阵复跑（收口轮绿即达标）。
- **SC#3 HDR** = T4 断言面 + peak 贯通。
- **全套回归**：`caffeinate -dis Scripts/test-direct.sh --all`（orchestrator 批准 + 监视 + MEMFAIL 机检）→ 基线对账链（01 收口值 + 本批增量；BUNDLE-MAP×Project.swift×文件实数两式互证）→ `Aces2Kernels.metal` / sidecar / History 面零 diff 终证。
- **回归红线断言**：JPEG/PNG/HEIC/WebP/PSD `decode()` 路由零回退（KD-1 机检锚）+ IOP/IOPParity 逐位基线（全套轮覆盖）。

## read_first

1. `.work/gsd/phases/m4-1-tiff-raster/M4-1-01-SUMMARY.md` + `M4-1-01-DECISIONS.md`（01 交付面/实测带/KD 偏差——本 plan 全部消费面以此为准）
2. `M4-1-CONTEXT.md` 裁决记录（5/6/7 号生效值）+ `RESEARCH-NOTES.md` §3.6/§3.7/§4.4
3. `LightamerCore/Sources/Decode/RAWDecoder.swift` :118-141（分流点）/ `RasterDecoder.swift`（01 交付）/ `DecodedImage.swift`（additive 字段）
4. `LightamerCore/Sources/Pipe/PixelPipe.swift` :219-241（decodedImage/inputPlaneDedupeKey）/ `run` :686（:714 写 decodedImage）/ `renderInputPlane` :628-664（输入平面装配腿——分派点落其三条 return 之前）
5. `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift` :249-277（drtRecords carrier 面）+ `PipeCoordinator.swift` :577-:724（DRT 四件套/seed 时序）
6. `App/Sources/Lightamer/State/EditorState.swift` :434-:513（defaultLookPending mint 面）
7. `LightamerCore/Sources/Library/ImportFilter.swift` 全文（三序/LAST-extension 契约）+ `ImportService.swift`（ImportProgress/三运输）+ `App/Sources/Lightamer/Library/ImportModeDialog.swift`
8. `App/Sources/Lightamer/Library/LibraryThumbnailBridge.swift`（Tier A/B seam）
9. `Tests/LightamerTests/DrtViewportTests.swift` + `DrtPersistenceTests.swift`（HDR 断言与 seed 测试的形态先例）
10. 上游 raster plan §6.6/§9.3/§10（GPL 只读——面板门控/选择器计数/round-trip 自证形态）

## 纪律（强制）

- 与 01 相同全款（每任务独立提交 / E2+L041 / caffeinate / L014 fence / L048 比较域 / 中文标注显式）。
- **生产行为切换批专项**：T1 合入前 JPEG/PNG 既有图库断言面（LibraryThumbnailBridge/Sessions 相关）定向轮先绿再切；切后立即跑 IOP+APP 两 bundle 定向轮。
- **C 档门控**：本 plan 执行+验收闭环后停——汇报战果 + SC 对表，等用户确认再 Phase 签核（VALIDATION）。
- 全套 `--all` 轮：**先获 orchestrator 批准**，运行中保持进程监视（GUI app 与测试宿主同名 Lightamer——按 parentage 区分，处置线不同；AGENTS 测试宿主口径），MEMFAIL/内存压力转红立即 kill 上报。
- zh-audit `--check` 对本批新键（readout 行/选择器/面板门控文案——xcstrings 尾块纯插入 + 动态键显式 switch 返回静态键，V14/V15 纪律）。

## Tasks

### T1 decode() UTI 分流（KD-1）

- read_first 3 → RAWDecoder 分支插入 + `isTIFFUTI` 判定 + 旧臂退役注记（decodeRaster 头注补「TIFF 自 M4-1 起分流，路径保留」；BandStreamer :24-28 头注「round-trips through decodeRaster」措辞随分流刷新为 decode() 新腿——纯注记）。
- **decode() 真链消费面普查（checker E2）**：`grep -l 'decode(' Tests` × `.tif` 字面量交集（亲证 27 个测试文件用 `.tif/.tiff`）逐文件定性入 DECISIONS——①synthetic `DecodedImage` 载体面 = **安全判据 `rasterColor == nil` → seed 跳过 → pristine 逐位不变**（EditorMetalLegRegressionTests/DrtViewportTests/FilmCoordinatorTests 等，亲证不受翻转影响，避免执行期误伤扩大）；②真 decode 面逐个处置（fixture 换容器 vs golden 重钉 + DECISIONS 逐条登记）——至少含 `HDRPipelineMatrixTests`（:92-95 torture 源/:800 merge 产品）、`ImportServiceTests`、`ImportFilterTests`（m3 翻转）、`ImportDropTests`、`HDRMergeMathTests`/`StackAggregateTests`/`ProvenanceV4Tests`（RAWDecoder().decode 直驱产品回流面，本批亲证补录）。
- 验收：`RasterRoutingTests`（IOP）——tiff→rasterNative 臂 / lut-icc tiff→CI 臂（rasterNative=nil）/ jpeg/png/heic/webp/psd→CI 通路零回退逐 UTI 断言 / CMYK typed 拒上浮 / **linear-ICC float32 产品回流断言（E1：`BandStreamer.writeFloatTIFF` 产品 → `decode()` → referral=sceneLinear → 矩阵支——IOPP 逐位基线与本批翻转自洽的机检锚）** / **普查清单入 DECISIONS（上方 E2 交付）**；T1 合入前后 IOP+APP 定向轮各一次全绿（纪律节）。

### T2 PixelPipe 装配 + 缓存键 + 缩略图（KD-3）

- read_first 4/8 → `renderInputPlane` 分派点（三条 return 之前，KD-3 两子形）+ dedupeKey 显式字段折叠 + Tier A thumbnail fallback。
- 验收：分派点 diff 收窄入 SUMMARY（封存面申报②兑现）；描述指纹折叠断言（同文件改 ICC → 键翻新 → 平面重算）；Tier A fallback 单测（LibraryThumbnailBridgeTests 增法）；100MP 级不动（单测小 fixture）。

### T3 默认 record 装配点 + 编辑面（KD-2）

- read_first 5/6 → WorkspaceModel seed 面 + PipeCoordinator 调用点 + mint skip + RawDecodePanelView 门控与 readout 行。
- 验收：`RasterEditFaceTests`（APP）——seed 三支逐条 / undo 到顶渲染恒 DRT（Alcedo 语义）/ sidecar 零写入直到编辑（2s debounce 后 flushNow 检点）/ restore 胜 derive / mint skip / 面板控件隐藏 + readout 文案；zh 键入册（zh-audit 绿）。

### T4 HDR EDR 贯通（KD-5）

- read_first 9 → PQ/HLG fixture 视口臂断言 + peak 贯通 + 互斥回归。
- 验收：`RasterHdrViewportTests`（APP）——DRT-HDR 臂（16F + PQ/HLG colorspace）/peak 值贯通（fixture 1000/4000 两档）/`ExportVariant.validate` 零扰动/手动 EDR 置灰纪律一条。

### T5 导入类别掩码 + 选择器 UI（KD-4）

- read_first 7 → ImportCategory/ImportDefaults/ImportFilter ③改写/ImportService 分账/ImportModeDialog 类型行。
- 验收：`ImportCategoryTests`（LIB）——三序 × 掩码矩阵 / excludedType vs extensionNotWhitelisted 分账 / 缺键=双开 / 域外=双开 / reset / rawExtensions 零触碰回归；`ImportCategorySelectorTests`（APP）——checkbox/计数/记忆/导入门；「tif 旧被拒→今双开被受」翻转列名 AC（**恰一处**：`ImportFilterTests.testNoExtensionAndNonWhitelistedFormatsRejected` :79-87——`.tif` 移出循环或改判 accepted；ImportServiceTests `.tif` 运输 fixture 随本任务翻转登记）。

### T6 import 三模式 TIFF 验证（OQ-7 生效值）

- read_first 7 → `ImportTransportTiffTests`（LIB）。
- 验收：move/copy/link 三模式 TIFF 字节运输 + `.lra` 随行（既有纪律复用断言）/link 模式外部替换 → contentDedupeID 翻新 → 重开描述重解析（改 ICC 的替换 fixture 一条）/校验回滚既有面零回退。

### T7 round-trip SC + 全套回归（KD-6）

- read_first 1/10 → `RasterRoundTripTests`（EXPORT）→ orchestrator 批准 `--all` 终验轮。
- 验收：SC#1 抽样矩阵全绿（描述一致 + 像素带 + 重放稳定；32F 行 display 分支注记见 KD-6）；SC#2 复跑绿；基线对账链两式互证（01 收口值 + 本批增量）；零 MEMFAIL；红线零 diff 终证（Aces2Kernels.metal/sidecar/History）；JPEG/PNG 图库面零回退终证；**`HDRPipelineMatrixTests` 逐位基线亲证（E1——torture 源 :92-95 与 merge 产品 :800 经 `decode()` 新腿 sceneLinear 矩阵支，IOPP 全绿即「逐位基线 × 路由翻转」自洽终证）**。

### T8 收口与签核

- SUMMARY/DECISIONS/VALIDATION（SC 三列对表 + 基线对账 + Manual-Only 行配方登记 GUI 走查如需）+ AGENTS M4-1 架构增量节（pristine 例外/RGC-off 政策/srgbPiecewise 注册/封存面解封注记收尾）+ GOAL-STATE/TODO 同批。
- **双重验收（config `dual_acceptance = true`，m1）**：zcode subagent 独立验收 PASS 后 → **串行** omp 二次验收（**严禁并发**——computer-use 单实例，config 硬约束）；两路结论（PASS/FAIL + 证据）落 `M4-1-02-ACCEPTANCE.md`；FAIL 回注修复批后重走验收；VALIDATION 仅在双验收 PASS 后成文。
- 验收：VALIDATION 成文；C 档停——汇报等用户签核。

## 验收标准（AC 总表）

1. **OQ 生效值⑤**：`library.import.categories` 新键在册（缺省双开/typed 校验/reset）；rawExtensions 正本零触碰回归。【T5】
2. **OQ 生效值⑥**：TIFF UTI 整体走新腿（路由断言）；decodeRaster TIFF 臂退役保留（头注 + 代码在）；JPEG/PNG/HEIC/WebP/PSD 零回退机检锚；缩略图 Tier A fallback + Tier B 新腿。【T1/T2】
3. **OQ 生效值⑦**：三模式零特例（move/copy/link 断言）+ link 替换重解析 by-design + excludedType 分账。【T5/T6】
4. **OQ 生效值①落点**：raster open 即 DRT 渲染（carrier seed 三支）+ sidecar 零写直到编辑 + restore 优先 + mint skip + 面板门控/readout。【T3】
5. **OQ 生效值④落点**：HDR TIFF → DRT-HDR 视口臂 + peak 贯通 + 手动 EDR 互斥零扰动。【T4】
6. **SC 三列**：round-trip ✓ / ICC 语义 golden ✓（01 复跑）/ HDR EDR ✓。【T7/T4】
7. **数字门**：全套 `--all` 终验轮亲跑（基线对账链两式互证）+ 零 MEMFAIL + 红线零 diff。【T7】
8. **签核面**：VALIDATION 成文 + AGENTS 增量节落账 + C 档停汇报。【T8】

## 风险与边界

- **路由切换的隐 consumers（checker E1/E2 方向纠正）**：两个方向分账——①直调者方向：grep `decodeRaster` 调用点只能找到**直调者**（本批亲证：全仓唯一调用点 = `decode()` 本体 :139，BandStreamer :28 仅头注引用；QuickLook/Spotlight 直调面 = 空集，照登记）；②**产品回流方向（真正的消费面）**：stack merge / HDR merge 的 linear-Rec2020 float32 产品（`BandStreamer.writeFloatTIFF` 落盘 `StackMergeService:1006/:1396`）与测试 torture 源经 `RAWDecoder().decode()` **回流**——grep decodeRaster 找不到它们，处置 = 01 KD-1 ①′ sceneLinear 规则（矩阵支、不施逆 ODT）+ T1 回流断言 + E2 普查清单，HDRPipelineMatrixTests 逐位基线为终证（T7）。
- **seed 时序竞争**：同 actor 串行假设必须由测试钉（restore 与 seed 顺序两 branch 都有断言）。
- **「tif 旧被拒→今被受」翻转**：既有测试面**恰一处**（checker m3 亲证）——`ImportFilterTests.testNoExtensionAndNonWhitelistedFormatsRejected`（:79-87，`photo.tif` 在拒绝循环内），双开缺省下必翻；设计内翻转，AC 列名更新（`.tif` 移出循环或改判 accepted），禁静默改断言；tiff 双扩展变体无第二断言面；ImportServiceTests `.tif` 运输 fixture 随 T5/T6 翻转登记。
- **TIFF 无内嵌预览 Tier A fallback 的质量**：ImageIO 缩略解码 = 全解码缩小（大文件首屏慢于 JPEG 内嵌预览）——观察项登记，不做后台预生成（超范围）。
- **8-bit 源阴影 banding 经 inverse 放大**：RESEARCH 已登记观察项（不做去带）；readout 面不承载。
- **100MP float32 内存贴线**：u8/u16 上传到 linearize 为止 + MEMFAIL 机检兜底；贴线 bundle 连续 MEMFAIL 先查重测漂移（AGENTS 口径）。
- **IOP/IOPP 基线漂移归因**：全套轮若 IOP/IOPParity 出现非 M4-1 域失败——先隔离复跑定位（01/02 两批零触碰 IOP 算法面），按 M2-7-3 宿主清理教训核 parentage。

## 提交约定

- T1 `feat(core): route tiff uti to the native raster develop leg`
- T2 `feat(core): wire raster input stage into pixelpipe with fingerprint key`
- T3 `feat(app): raster default drt record seeding and edit face gating`
- T4 `feat(app): hdr tiff edr viewport with peak threading`
- T5 `feat(library): import category mask with selector ui and excluded type`
- T6 `test(library): tiff transport across move copy and link modes`
- T7 `test(export): round-trip sc close with full suite regression`
- T8 `docs(m4-1): close tiff develop chain with validation and ledger`
- 全英文 Conventional Commits；不 push。

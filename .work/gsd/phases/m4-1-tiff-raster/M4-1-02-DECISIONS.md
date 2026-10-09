# M4-1-02-DECISIONS — 执行期偏差、实测发现与普查处置

> 正本补充 = SUMMARY;本文件只收执行期发现。KD 编号引用 plan。

## §1 T1+T2 合并为单 commit(可构建性裁定)

T1(路由翻转)与 T2(管线分派)共享 RasterRoutingTests/RasterDecodeLegTests 两文件
且分派测试引用 T2 面——拆分提交会留下编译不过的中间态(破坏 bisect)。裁定:两任务
合一 commit(`1b2b520`,message 双段),T3 起恢复逐任务提交。

## §2 E2 消费面普查(TIFF decode() 真链消费,checker E2 交付)

`grep -rl '\.tif\|\.tiff' Tests` = 43 文件;与 decode( 调用交集 17;逐文件定性:

**① 合成载体面(安全判据 `rasterColor == nil` → seed 跳过 → pristine 逐位不变)**:
DrtPersistenceTests / VersionSwapTests(JSON decode;.tif 仅为临时文件名)、
AdjustmentTransferTests / AIWorkerClient·Protocol / EnhanceCopy / ExportPhaseE2E /
ExportRecipe / HistoryRowJump / LightamerPreset / ExportNamer·Encoder·XMP 族
(.tif 为**导出目的地**扩展名,零 TIFF decode 输入)、ImportDropTests(分类字符串)、
EditorMetalLegRegression / DrtViewport / DrtPanelModel / FilmCoordinator /
FilmPanel / FilmCard(合成 DecodedImage)——**不受翻转影响,亲证零触碰**。

**② 真 decode 面逐个处置**:

| 消费面 | 处置 | 验证 |
|---|---|---|
| GoldenColorTests + Fixtures.neutralTarget(9 套件:FilmicRGB/GeometryGolden/LayerComposite/ToneEqualParity/ColisaParity/LevelsParity/TemperatureParity 等) | **fixture 换容器**:NeutralTarget.tif → 16-bit PNG(pypng,像素恒等 roundtrip 亲证);未标记 PNG 走 ImageIO 合成 sRGB = 原 sRGB 标记同数值转换 → 全部套件留在 CI 臂,golden 语义零变 | App/Library 轮全绿 |
| HDRPipelineMatrixTests(torture :92-95 / patch :143 / merge 产品 :800) | **不改**——线性 Rec2020 tagged float32 → ①′ sceneLinear 矩阵支(01 预置) | IOPParity 427/3/0 = **E1 终证** |
| HDRMergeMathTests :328 / StackAggregateTests / StackMergeServiceTests / ProvenanceV4Tests :172·:331 | 不改(产品回流走矩阵支) | IOP 562/1/0 全绿(Sessions --all 覆盖) |
| ImportFilterTests :79-87 | **设计内翻转**(恰一处):photo.tif 判 nil,原拒绝循环收窄 + 翻转注记原位改名 | Library 615/4/0 |
| ImportServiceTests C1 | 契约钉 `categories: .raw`(RAW-only 时代数字不变)+ .tif 噪声分账改 `.excludedType` | 10/0/0 |
| RasterDecodeLegTests 路由 golden | 翻转为 native-leg + **退役臂快照**新测(decodeRaster 直调仍 CI 面) | IOP 562/1/0 |
| RAW03Tests(RAW-03 float 保真钉) | 不改——翻转后 TIFF 行走新腿,pinned 位置钉**输入平面 row0=TOP 约定**(见 §3) | IOP 562/1/0 |

**③ 本批新增消费面**:RasterRouting/RasterEditFace/RasterHdrViewport/
ImportCategory·Selector·Transport/RasterRoundTrip(各自任务交付)。

## §3 管线平面方向约定(执行期实测钉死,推翻 planner 假设)

**输入平面 row0 = TOP**。证据链:RAW03Tests 的 pinned 对角钉值在 CI 腿自
02-06 起全绿 → CI bitmap+replace 输入渲染 row0 = 图像顶。Fixtures.swift 的
「row 0 = image BOTTOM」注记描述的是**终末 gamma/显示腿**的采样面
(GoldenColor 采样最终 8-bit 平面),非管线内部约定。第一版 windowedPayload
按 bottom-first 交付导致 RAW03 值整体位移 8 行(诊断过程在案),回退为
top-first 后逐位命中。**raster 腿与 CI 腿同向,top-first;无翻转成本**。

## §4 windowedPayload 字节序 bug(自抓自修)

首版 sourceComponent 按大端读 native.data,而 extractNativePixels 写入为
**小端**(pushLE16/LEF32)→ u16/f32 全部字节交换错值(RAW03 读出 ~0/denormal
垃圾)。修正为 LE 读回;窗口 1:1 时为纯字节拷贝,u16/f32/u8 三载体
windowed 测试逐字节钉死。≤1px 源边取整(整数 span box 平均)登记为已知近似。

## §5 NeutralTarget 容器转换(E2 处置的副产申报)

TIFF(6.3MB)→ PNG(18KB,patch 网格压缩)像素恒等;bundle 资源随 Tuist
folder glob 自动更新。**禁回转 TIFF**:会走 M4-1 原生腿并重钉 ~10 套件
(Fixtures.swift 注记)。

## §6 HDR TIFF 重导入走 LUT 臂(SC#1 HDR 行实测面)

rec2020/st2084 导出行:落地 16-bit PQ TIFF,系统名 ITUR_2100_PQ ICC 经
ColorSync 序列化后**呈现 LUT 型**(A2B0)→ 解析序①判 LUT → 重导入走
`iccLutConverted` CI 臂(ColorSync 全色彩管理,PQ 语义在管理内幸存)——KD-1
钦定的唯一 LUT 面,管线侧 `raster_input_display` 逆腿(TRC 恒等)已由 T2 接线。
行断言钉 origin/transfer/nil-rasterNative;primaries pin 由
`limitingSpace(for:)` 同秩比较承载(rec2020)。UltraHDR peak 容器仍挂
ALCE-02 M4(M2-9 账面不动)。

## §7 行为变化登记(设计内,用户可见)

- **CMYK TIFF / 16-bit gray TIFF 在 open 时 typed 拒**(decode 错误 alert)——
  翻转前静默走 CI 解码可开;01 KD-5/D4 的 typed 拒面随翻转生效。16-bit gray
  补腿仍挂 01 DECISIONS §8 待供件。
- **TIFF 无内嵌预览的图库首屏**:Tier A 走 ImageIO 全解码缩小(慢于 JPEG 内嵌
  预览,plan 风险节登记的观察项,不做后台预生成)。
- **undo 到顶的 raster 文档渲染恒 DRT**(derive 重铺替换 stale carrier)——
  与 RAW「undo 到顶 = 无 DRT 尾」的显式偏离(Alcedo「DRT 恒在」语义)。

## §8 导入选择器工程注记

- `ImportService.recursiveFiles` private→public:App 模块存在 Session 域同名
  `ImportService` 枚举(裸名解析歧义),调用点须 `LightamerCore.ImportService.` 限定。
- 扫描复用唯一 walker(dialog 零新扫描逻辑);`ImportTypeSummary.aggregate` =
  一次 `ImportFilter.select(.all)` 纯分账;掩码记忆 = checkbox 即写。
- App 全量 704/0/0 内含选择器 5 测;真机 checkbox 交互挂 gui-acceptance
  (Manual-Only,如需)。

## §9 全套终验数字(--all 亲跑,2026-10-10 收口轮)

`caffeinate -dis Scripts/test-direct.sh --all` = **TOTAL|3335/16/0|1604s**,exit 0,
零 MEMFAIL;IOPParity 峰值 RSS **8104MB < 8192 门**(贴线 88MB,IOP 8018 /
Sessions 1656 / Export 7003 / App 2831 / Layers 1152 / Library 613);L055 双
保险亲核:末条 Executed 全挂 'All tests' + 七 bundle 崩溃签名零命中。

逐 bundle(基线 M3-4-02 收口 3174 分解 → 本轮):

| bundle | 本轮 | M3 收口基线 | Δ | 分解 |
|---|---|---|---|---|
| IOP | 562/1/0 | 483 | +79 | 01 +61 + 02 +18 |
| IOPParity | 427/3/0 | 408 | +19 | 01 +19 |
| Layers | 394/3/0 | 378 | +16 | 01 +16 |
| Library | 619/4/0 | 598 | +21 | 02 +21(16+4+1) |
| Sessions | 279/4/0 | 279 | 0 | — |
| Export | 350/1/0 | 342 | +8 | 01 +5 + 02 +3 |
| App | 704/0/0 | 686 | +18 | 01 +1 + 02 +17(7+5+5) |

对账链:2962→3024→3081→3125→3152→**3174**(M3 收口)→3276(M4-1-01 预期,
--all 留 02 收口轮)→**3335** = 3174 + 102(01)+ 59(02),两式互证逐位闭合。
派发令「≈3276」系漏乘 01 批增量的粗估(§11.3)。skip 恒 16。

## §10 BUNDLE-MAP 勘误与登记

- omp-obs-1 五处订正:RasterColorDescriptionTests 14→28、RasterIccSemanticsTests
  18→20、RasterDecodeLegTests 16→19(01 实况 13 + 本批 +6)、Aces2InverseTests
  6→8、RasterDefaultRecordTests 15→14;T9 漏同步 DrtEotfTests 12→15、
  DrtViewportTests 6→7。omp-obs-2:ExportDrtChainTests 行补 `.swift` 后缀。
- 新行 7 文件(方法数 = 文件实数):IOP RasterRoutingTests 12 / APP
  RasterEditFaceTests 7 + RasterHdrViewportTests 5 + ImportCategorySelectorTests 5 /
  LIB ImportCategoryTests 16 + ImportTransportTiffTests 4 / EXPORT
  RasterRoundTripTests 3。

## §11 偏差与登记清单(晨审可裁)

1. T1+T2 合并 commit(§1)。
2. plan front-matter 漏列实触:RasterInputStage.swift(§申报外扩 1)、
   BandStreamer 头注、Fixtures.swift + NeutralTarget 转换、ImportServiceTests、
   LibraryThumbnailBridgeTests、RESEARCH-NOTES 勘误(SUMMARY §4-§6 全数申报)。
3. plan 数字门「≈3276」系派发令粗估;实算 Δ=59 → 3233(逐 bundle 两式互证)。
4. HDR 行 SC#1 断言按 §6 实测面落笔(非 plan 字面的 st2084 重解析)——LUT 臂
   为 KD-1 设计内面,像素往返由 srgb 行 band + ColorSync 管理承载。

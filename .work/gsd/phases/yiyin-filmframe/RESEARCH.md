# 胶片相框（Film Edge）Research（2026-10-31，omp lane）

> 功能定义（用户指令）：当前印框/水印功能（yiyin 移植）增**胶片相框**风格——照片以
> SpektraLab 式胶片边框呈现：片边排版（胶片品牌/型号文字沿边）、帧号、日期后背
> （日期+拍摄数据）、可选 DX 条/片孔形态。落位 = yiyin 面板新相框风格（与既有
> 画布边框并列），非整卷画布重构。
> 调研方法：上游 `git show origin/main:` 读法（本地树 stale，behind 518）；我方
> scout 落点测绘 + 本体亲读。纯文本，零 commit 零构建。

---

## 一、上游测绘：SpektraLab Film Edge + Date Back

### 1.1 架构总览：曝光语义（与我方提案的最大分野）

上游 film edge 不是「画上去的边框」，而是**底片上的曝光**（`overscan.cpp:1-22`
注释明示，RFC-032 §26 立论）：

- 画布建在 raw exposure 上（metering/boost 之后、halation 之前），edge print /
  fog / gate 阴影 / rebate 颗粒全部作为曝光参与后续显影流水线；
- 「drawn border cannot pass for one」（§26）：画上去的边框冒充不了真 overscan。
- 随机性三级分离（§26.1）：**film data**（per-stock 固定：边缘文案/周期/编号/
  DX，确定性）/ **camera**（`camera_seed`：gate 角/边摆/片门间隙/穿孔相位/漏光侧）
  / **frame**（`frame_seed`：过片误差/抖动/扫描旋转/fog 实现；120 非齿孔锁定，
  边缘号落位也是 frame 级）。

**对我方的含义**：我方 yiyin 印框是 terminal 段（colorout 之后 display-referred）
的画布合成，与上游「曝光语义」架构性不同。我方胶片相框 = 上游明确否定的
"drawn border"——这是用户指令已接受的形态（yiyin 新风格，非画布重构），research
只登记此分野，不立项仿真上游曝光链。

### 1.2 文件级出处（`origin/main`，行数 = 该版本实测）

| 文件 | 行数 | 职责 |
|---|---|---|
| `engine/src/pipeline/overscan.cpp` | 2223 | 引擎本体：格式表/边缘观感表/排版 op 生成/CoreText 光栅化/DX 位/片门形态/三 node |
| `engine/src/shaders/overscan.metal` | 394 | 三 kernel：画布→胶片坐标、gate SDF、穿孔/片基/漏光/雾化（261 float 参数块 `OsP`，cpp 侧为 index 单源） |
| `engine/src/core/params.hpp` | — | `OverscanParams`（:156-188，12 字段）+ `DateImprintParams`（:193-211，9 字段） |
| `engine/tests/overscan_checks.py` | 759 | 34 用例：DX 回读/off 逐字节/seed 确定性/格式拒收等 |
| `API-SPEC-callable-render-service.md` §13 | ~L690-950 | 20 wire 字段表 + 排版语义长注 |
| `modern_UI/.../Model/FilmEdge.swift` | 434 | App 侧模型：`FilmEdgeFormat`（10 格式）/ `FilmEdgeSettings` / `DateBackSettings`（三面/lcd-dots-data）/ wire 装配 |
| `modern_UI/.../Model/Session+FilmEdge.swift` | 587 | host 解析面：`ShootingData`（EXIF→6 字段）/ `edgeText(for:gauge:)`（stock→边缘文案表）/ `resolvedFilmEdge` / crop-gate 互锁 |
| `modern_UI/.../Panels/Sections/FilmEdgeSection.swift` | 640 | 面板：format/view/framing/gate/holes/body/advance/frameNumber/fog/leaks + edge print 注释行 |
| `modern_UI/.../Panels/Sections/DateBackSection.swift` | 306 | 面板：face/order/placement/corner/size/brightness/withData/customText |
| `modern_UI/.../Model/StockCatalog.swift` | — | `Stock.formats`（gauge 白名单：135/120/35mm_motion，D3 门控 Format 菜单灰显） |
| `modern_UI/SpektrafilmTests/FilmEdge{,Section,Session}Tests.swift` | — | 三测试文件 |

注：RFC-031/032 **文档本体不在仓内**（`git log --all --diff-filter=A` 零命中；
RFC 只到 RFC-030；commit message 与代码注释引用其章节号）。`reference_film/`
实测底片扫描目录同样不在 `origin/main` 文件树（719 文件零命中）——实测数据
（px/mm 标定）只以注释形式沉淀在代码里。

### 1.3 格式/片门尺寸表（`overscan.cpp:104-124`，实测值非标称）

| format | film_w | gate across×along | 穿孔 | gate 族 |
|---|---|---|---|---|
| 135 | 35.0 | 24.3×36.25（七条实测均值；距穿孔 0.55mm） | ✅ | square |
| 135_half | 35.0 | 24.0×18.0（4 穿孔 19.00mm advance） | ✅ | square |
| 120_645 | 61.0 | 56×41.5（Mamiya 标称） | ❌ | eared/rounded |
| 120_6x6 | 61.0 | 56×56 | ❌ | kicked/square |
| 120_6x7 | 61.0 | 56×69.5 | ❌ | square |
| 120_6x8 | 61.0 | 56×76.0（gate 偏置：耳距片边 1.1-1.35mm） | ❌ | shouldered |
| 120_6x9 | 61.0 | 56×84.0 | ❌ | square |
| 135_xpan | 35.0 | 24×65（14 穿孔 66.5mm advance，齿孔相位沿用） | ✅ | square |
| 120_6x12 / 6x17 | 61.0 | 56×112 / 56×168 | ❌ | square |

片门形态（`gate_shape`，L351-468）：5 族（square/rounded/eared/shouldered/kicked）
+ 8 quad 特征 + 毛刺（0.04-0.12mm）+ 机加工粗糙度 + 三谐波边摆；`shouldered`
（6x8）含 t- 侧两级台阶 recess，边缘文案走耳间 recess。

### 1.4 每 stock 边缘排版（`overscan.cpp:131-230` + `imprint_groups` L1384+）

**观感表 `kEdgeLooks`**（20 条 stock 行 + 默认行）：每 stock = 135 布局枚举 ×
120 布局枚举 × 打印机三层光权重 × 曝光 EV × 细体标志 × Fuji-120 后缀码。
135 五布局：`Kodak`（DX 条 + Helvetica：Gold/Portra/UltraMax/C200）/
`FujiSlide`（无条，点阵 + 双边粗号：RVP/RDP）/ `FujiNeg`（14.1mm DX 条 + 双边
点阵号：X-Tra）/ `Cine`（EASTMAN 产品号 + 38mm dash：Vision3）/ `Ilford`
（Kodak 双带转半圈 + 5x7 方体：HP5）。120 两布局：`Kodak`（单边计数+名、
对边三角+隔一数字）/ `Fuji`（单边 5x7 点阵：号+标记+名+码）。

**排版 op 系统**（L231-258）：`Op{Text/Poly/Circle}`，胶片 mm 坐标（s 沿片、
t 横片、t 下为正），Text 走 CoreText（Helvetica Neue 家族，加宽/字距/斜切/
advances 缩放），Poly/Circle 走自绘（七段数码、点阵字、DX 条、箭头、三角）。

**字体面**：Helvetica Neue Bold/Regular/Medium（Kodak 系，数字加宽 x1.25，
120 扩展黑体 x1.3 含 advances 缩放，字谷 0.714 em）+ 自研点阵五族
（`kFaceNames/Numbers/Small/Tiny/57`，L1324-1328，glyph 位图 L1144-1322）
+ 5x7 通用点阵（`glyph5x7`，L985：0-9/A-Z/mvs`./-+:'()`，小写升大写回退）
+ LCD 七段（`seven_seg_polys`，8° 斜切，L259-298）。

**数据来源**：全部来自 owner 实测底片扫描（`reference_film/`，2026-10-03 起；
135 用穿孔 pitch 4.75mm 定 px/mm，120 用片宽 61mm 定）+ DX 数据库
（dxdatabase CC BY-SA 4.0 经 NegativeConverter MIT 转摘，四条码实测回读修正：
Gold 200 1548 / Portra 160 1534 / C200 1550 / X-Tra 628）。**无内置文案文件**：
边缘文案 = 引擎布局（固定）+ host 传 `edge_text` 字符串（`Session.edgeText`
按 stock×gauge 查表，20 条 own 表 + 回落大写营销名，push 后缀不印）。

### 1.5 DX 条（L1044-1086）

ISO 1007 frame-number 版：31 module（Kodak 系 12.7mm / Fuji 负片 14.1mm /
Ilford 13.06mm，实测非标称 13.0）× 双轨（clock 轨近穿孔：5-23交替-3；
data 轨近片边：起 b/w/b/w/b + 23bit + 止 b/w/b）。23 bit：
`[0]=0 / [1..7] DX part1 / [8]=0 / [9..12] DX part2 / [13..18] 帧号(0-63钳) /
[19] 半格位 / [20]=0 / [21] 奇偶 / [22]=0`。`dx_extract_for` 表 15 条
（part1×16+part2）；电影卷/无码卷（Kodachrome）印空边——「空边真于编造码」。
测试 `decode_dx` 从渲染底带按读码器语义回读（parity + 帧号 + 半格位）。

### 1.6 Date Back（L1900-2038 + wire 表）

一机三面：`lcd`（七段，字高 1.3mm）/ `dots`（5x7 点阵正体，0.95mm）/
`data`（5x7 拍摄数据行，0.50/0.55mm）。位置：135 框内四角（film 系角，
随相机旋转）或 `rebate` 帧间（F6/MF-28 式竖读，需 film edge；date+data
可同印，1.3.1 新增）；120 片边 margin 沿片横读（data 自前沿起、date 止于
末沿，永不相遇）；全景格式无日期。host 格式化文本（`ShootingData.dataText`：
`1/250 F5.6 A +0.3 24mm`，F6 式，22 字符上限自右截断，无 ISO——E7 裁定；
日期 `DateBackSettings.format`：US `10 1 '26` / Japan `'26 10 1`，无前导零）。
EXIF 只取 6 字段（DateTimeOriginal/ExposureTime/FNumber/ExposureProgram/
ExposureBiasValue/FocalLenIn35mmFilm），缺字段留空永不编造；f-number 另供
gate 半影。

### 1.7 上游可移植清单（供 §三对照）

| 上游资产 | 可移植性 | 备注 |
|---|---|---|
| 格式/片门/mm 尺寸表 | ✅ 事实数据 | 实测值转录须自测或注来源；XPan/6x12/17 为 square 假设 |
| 布局枚举思想（Kodak/Fuji/Cine/Ilford × 135/120） | ✅ 思想 | 版式按思想重做，不抄 op 参数 |
| stock→边缘文案表（20 条 own 文案） | ⚠️ 自建 | 短语境下事实性短语风险低，但按任务书要求**自建 28+4 表零复制** |
| DX 编码算法（ISO 1007） | ✅ 标准 | 公开标准，可独立实现；DX 码值走公开 DX 数据库自查 |
| 点阵字形位图/七段几何 | ❌ 不移植 | 上游原创表达；我方用 CoreText 系统字体 + 自绘七段（几何思想可借鉴） |
| 曝光链/node/metal kernel | ❌ 不移植 | 架构不匹配（terminal 合成 vs 曝光） |
| ShootingData 六字段纪律/缺值留空 | ✅ 方法学 | 直接采用 |

许可：上游代码 GPL-3.0-or-later；我方 GPL-3.0 同许可复制允许但本 lane
**零代码复制**，只取思想/事实/标准。

---

## 二、我方落点测绘（file 级）

### 2.1 yiyin 印框/水印管线现状

| 文件 | 规模 | 职责/关键符号 |
|---|---|---|
| `LightamerIOP/Sources/Yiyin/BordersModule.swift` | 837 行 | 印框画布 IOP（v50 `76.0`，terminal：colorout→borders→watermark→gamma）。`Params(mode/mainImageWidthRate/miniTopBottomMargin/aspectRatio/landscapeOutput/cornerRadius/shadow/textBottomOffset/adaptiveBackdrop)`；`BackdropMode.solid(color:)/blur(amount:)` 二态，**无 style 枚举**；`jointLayoutOverride` 缝；`modifyROIOut` 膨胀画布 |
| `LightamerIOP/Sources/Yiyin/WatermarkModule.swift` | 485 行 | 水印 IOP（v50 `77.0`）。`Params(templates/font/fields/dateFormat/lineSpacing/anchor/logoOpacity)`；`JointContext` + `makeJointLayoutRecord`；`captureExif/personalSign/logoProvider/captureTimeZone` |
| `LightamerIOP/Sources/Yiyin/YiyinLayout.swift` | 394 行 | 纯 float64 七步联排（yiyin v1.7.1 镜像）。`YiyinLayoutRecord(canvasSize/mainImageOrigin/...)`；`YiyinNineGridAnchor`（默认 bottomCenter） |
| `LightamerIOP/Sources/Yiyin/YiyinKernels.metal` | ~230 行 | `yiyin_composite`（solid/blur band + overlay + shadow + 主图圆角）+ `yiyin_shadow_sdf` + `yiyin_box_downsample` + `yiyin_watermark_row` |
| `LightamerIOP/Sources/Yiyin/YiyinTextRenderer.swift` | 497 行 | **CoreText 行渲染器**：量测+8-bit sRGB premult 位图，L013 StableHash 缓存（budget 48）；`ctFont`（PingFang SC 回退）；缺竖排/旋转 |
| `LightamerIOP/Sources/Yiyin/YiyinTemplate.swift` | 481 行 | `{Field}` 模板引擎，15 字段；`rotation` 预留未消费 |
| `LightamerIOP/Sources/Yiyin/YiyinColor.swift` | ~180 行 | sRGB hex→display-linear；`overlayGrayTiers` 4 档 |
| `LightamerIOP/Sources/Yiyin/YiyinFontStore.swift` | ~200 行 | 系统族枚举 + 用户字体导入（AppSupport + registry.json） |
| `LightamerIOP/Sources/Yiyin/YiyinLogoStore.swift` | ~330 行 | 13 品牌×明暗内嵌 PDF + 用户上传，`rasterHeight=512` |
| `App/Sources/Lightamer/Yiyin/YiyinPanelView.swift` | 745 行 | 单面板双 Section（印框+水印+模板 CRUD）；`YiyinPanelProvider/YiyinBordersPanelProvider` 双派发（opName `watermark`/`borders`） |
| 注 | — | `YiyinSheetSizing.swift`（~270 行）与胶片无关（Inspector sheet 拖拽）；`TextOverlay/` 为并行通用文字模块，非挂点 |

### 2.2 数据源：FilmRecord / EXIF / stock 表

| 文件 | 关键事实 |
|---|---|
| `LightamerCore/Sources/Graph/FilmRecord.swift`（~280 行） | `filmStock/paperStock: String` **开放 id**（`""`=未绑定）；pristine 缺键门；`stableHash()` FNV-1a |
| `LightamerCore/Sources/Film/FilmMaterialStore.swift`（~280 行） | `profile(id:)` 按 `info.stock` 索引，未知 id→nil typed degrade；`materialPairHash` solve 缓存键 |
| `LightamerCore/Sources/Film/FilmProfile.swift`（583 行） | `Info(stock/name/type/support/stage/targetPrint/channelModel/densitometer/...)` 可作边缘文案源 |
| `Resources/FilmProfiles/profiles/*.json`（28）+ `Resources/FilmProfilesBW/profiles/*.json`（5：4 卷+1 相纸） | 28 film stocks + 4 BW film + 相纸；`info.name` 即营销名（见 §2.4 表） |
| `LightamerCore/Sources/Decode/CaptureMetadata.swift`（~140 行） | App 层拍摄事实总入口：快门/光圈/ISO/日期/焦距（含 35mm）/档位/测光/白平衡/镜头，全 Optional |
| `LightamerCore/Sources/Decode/YiyinExifFormat.swift`（458 行） | 15 字段显示值层（`YiyinExifField`，含 `formatDate` + 品牌归一化），水印模板已消费 |
| 外挂表先例 | `GrainCalibration.publishedRms(forStock:)`（BW grain 标定）：per-stock 外挂表形态可仿 |

### 2.3 注入三腿与导出约束

- **预览腿**：`PipeCoordinator.injectYiyinRunContext`（`State/PipeCoordinator.swift:2982`，
  每 render 前）→ `watermark.captureExif/logoProvider/jointContext` +
  `borders.jointLayoutOverride`。`currentFilmRecord` 同文件可顺手取。
- **导出腿**：`ExportRenderer.renderStage` **Step 5**（`Export/ExportRenderer.swift`）：
  `if variant.yiyin { injector.apply(boxes, built.instances, entryPlane, decoded.capture) }`；
  生产填充 `ExportState.makeYiyinInjector`（:314-336）。**签名无 film 位**，需扩展
  （加参或 `$jobFilmEdge` TaskLocal 仿 `$jobFilmTail`）。
- **缩略图腿**：`SessionThumbnailRenderer.runContextInjector`（:79），contract twin
  第三份注入。
- **导出约束（继承）**：`.drt` terminal policy 管内降级 borders/watermark；
  `ExportRecipe.validate()` 门 ⑥ gainMap 与 yiyin 互斥——胶片相框走 yiyin 模块即
  自动继承（OQ-7 确认是否适用）。

### 2.4 我方 28+4 卷 stock 清单（边缘文案表自建输入）

film（28）：fujifilm_c200 / pro_400h / provia_100f / velvia_100 / xtra_400 /
kodak_ektachrome_100 / ektar_100 / gold_200 / kodachrome_64 / portra_160 /
portra_400 / portra_800(+push1/push2) / ultramax_400 / verita_200d /
vision3_50d/250d/200t/500t / vision_2383/2393（拷贝片！）+ BW4：
tri_x_400 / tmax_100 / neopan_acros_100_ii / hp5_plus_400。
相纸 6（crystal_archive_typeii / ektacolor_edge / endura_premier / portra_endura /
supra_endura / ultra_endura / multigrade_iv_rc 计 7——注：BW 目录 1 相纸 + 彩色 6
= 7 相纸）：**相纸无片边概念**，边缘文案表只覆盖 32 film stocks。
特殊行：`kodachrome_64`（K-14 已停产，无 DX 码，上游亦无）、`verita_200d`（虚构
测试卷）、`2383/2393`（拷贝正片，非拍摄卷）、push1/push2（push 是工艺非卷，
边缘文案 = Portra 800 本体）。

---

## 三、设计提案：yiyin 新 frame style「胶片相框」

### 3.1 形态（与既有画布边框并列）

- **风格开关**：`BordersModule.Params` 新增 `frameStyle: .canvas | .filmEdge`
 （默认 `.canvas` = 现状逐字节；枚举 additive，旧档缺键解码 = canvas）。
  面板落 `YiyinPanelView` borders Section 顶部 Picker（`BackdropMode` 二态保留，
  仅 canvas 臂消费；film 臂自有配色）。
- **film 臂画布几何**（`YiyinLayout` 新分支，纯函数；单位 = 相对主图短边比，
  非 mm——terminal 合成无物理标尺）：
  - 上下片边带（135 拟态：带高 = 短边 × ~7%，含片孔行 + 品牌行 + 帧号）；
  - 左右窄边（~2%，纯片基色，无孔）；
  - 主图区 = gate 内（圆角恒 0，阴影恒 off——胶片无阴影；`shadow` 参数 film 臂忽略）。
  - 幅面门：主图须 3:2（135 拟态唯一幅面；非 3:2 时 film 臂拒绝并 toast，仿上游
    gate-shape 拒收。120/全景 = 二期，OQ-1）。
- **片孔拟态**：圆角矩形孔行（8 孔/帧沿上边 + 8 孔/帧沿下边，孔 = 纯白/纯黑二档
  `holes: white|black`，仿上游 `overscan_holes`），孔几何走 SDF 解析式进
  `yiyin_composite` 新分支（或新 kernel `yiyin_filmedge_composite`；推荐新 kernel，
  旧 kernel 零 diff 红线）。
- **元素开关**（逐元素 Bool，默认全开，Params additive）：
  `brandLine`（品牌/型号沿边）/ `frameNumber`（帧号 N/NA 对）/ `dateBack`（日期）
  / `dataLine`（拍摄数据）/ `dxBars`（DX 条）/ `sprockets`（片孔）。
  六开关 + `holes` 二档 + `brandSide`（品牌行在上/下带，默认上）= 参数面全集。
- **文字渲染**：复用 `YiyinTextRenderer`（CoreText）+ 新 `FilmEdgeRowBitmap` 装配：
  边缘行 = 横排（首期无竖排；`rotation` 预留位不动，OQ-5）。字体：系统
  Helvetica Neue Bold（拉丁）+ PingFang SC 回退（现有 `ctFont` 缝）；Fuji 式
  点阵/DX 条 = 自绘几何（矩形拼，不移植上游位图）。

### 3.2 数据流

```
FilmRecord.filmStock（开放 id，""=未绑定）
  → FilmEdgeCopyTable[stock]（新建，Core Film/，32 film 行：edgeName135/edgeName120?/dxCode?/layoutKind[square135]/inkHue）
      ├─ 未命中/"" → 回落：info.name 大写（仿上游回落）+ 无 DX + Kodak 式通用版
      └─ 相纸 id / 非法 id → 同回落（typed degrade，不报错）
  → BordersModule.filmEdgeCopy（run-scoped 注入，仿 captureExif）
  → YiyinLayout.filmEdgeRows（联排）→ TextRenderer 位图 → kernel 合成

CaptureMetadata（captureTime/shutter/aperture/iso/focal35/program/bias）
  → YiyinExifFormat（复用 15 字段层）→ dateBack/dateText + dataLine
  → 缺字段留空永不编造（上游 ShootingData 纪律）
  → 帧号：session 内序号（`frames.firstIndex % 99 + 1`，仿上游 seedFilmEdge；
     单图打开 = 0 → 印空或 "00"，OQ-4）

注入三腿同步加 film-stock 位：
  预览：injectYiyinRunContext 内读 currentFilmRecord（一行）
  导出：ExportYiyinInjector.apply 加 filmStock 参（签名扩展；或 $jobFilmEdge TaskLocal）
  缩略图：runContextInjector 同构
```

### 3.3 渲染路径

- **CPU**：`YiyinLayout.filmEdge` 联排（float64，仿现有七步）→ `YiyinTextRenderer`
  边缘行位图（StableHash 缓存，key 追加 film 维）→ DX 条/孔位几何表。
- **GPU**：新 kernel `yiyin_filmedge_composite`（单遍：片基底色 + 孔 SDF 戳 +
  行位图贴 + DX 矩形 + 主图 1:1 贴，无圆角无阴影）。旧 `yiyin_composite` 零碰。
- **色彩**：片基色 = per-layout 常量（Kodak 系暖灰 / Fuji 系偏黄 / BW 中灰，
  sRGB hex 经 `YiyinColor` 同链 linearize）；边缘字 = 片基上近白（opacity 烘焙，
  仿 logo 烘焙）。display-referred 终段，无曝光语义（§1.1 分野登记）。

### 3.4 工作量分级

| 包 | 内容 | 级 |
|---|---|---|
| A. 参数+面板 | `frameStyle` + 六开关 + holes/brandSide；`clamp/isNeutral` 同步；`YiyinPanelView` 新控件 + 本地化键 + 历史 label | **S**（~2-3 天） |
| B. 文案表 | `FilmEdgeCopyTable` 32 行自建（edgeName/DX/layoutKind/inkHue）+ 回落 + 单测 | **S**（~1-2 天；DX 码值需公开库自查一条） |
| C. 联排+文字 | `YiyinLayout.filmEdge` 分支 + 边缘行装配 + TextRenderer 复用 + 缓存键 film 维 | **M**（~3-5 天） |
| D. kernel | `yiyin_filmedge_composite`（孔 SDF + 行贴 + DX 矩形）+ golden（孔位/行位像素断言） | **M**（~3-5 天） |
| E. 注入三腿 | 预览一行 + 导出签名扩展 + 缩略图同构 + 导出 golden | **S**（~1-2 天） |
| F. 日期/数据/帧号 | `YiyinExifFormat` 复用 + dateBack/dataLine 行 + session 帧号缝 + 缺值留空 | **S**（~1-2 天，含面板 date 格式复用决策） |
| 全量 | A→F 串行（A/B 可并行先行） | **M-L**（~2-3 周单人；首期 135 拟态唯一幅面） |
| 二期（不入首期） | 120 版式/全景/XPan、竖排字、Fuji 点阵拟态、片门圆角族、fog/leak 做旧 | L（逐项 S-M） |

### 3.5 与既有约束的相容性

- V50Order：零新增 op（borders 内新 style），add-only 纪律天然满足。
- 封存面：`YiyinKernels.metal` 不在封存清单；`ExportQueueContract` 加参需走
  封存例外申报（或 TaskLocal 递缝零 diff——推荐后者，M2-9 三件套范式已有
  `$jobFilmTail` 可仿）。
- process version：filmEdge 是 yiyin terminal 表现层，非 film 显影语义——
  **不 bump process**（但边缘文案随 filmStock 变：缓存键必须含 stock 维，
  否则换卷不换边 = 陈旧文案 bug，P0 机检项）。
- sidecar：Params additive optional 键，旧档缺键 = canvas，零迁移。
- 120/120日期：首期只做 135 拟态；120 边缘 = 二期（上游 120 版式已测绘，
  §1.4 可直接作为二期输入）。

---

## 四、OQ 清单（带推荐值）

| # | 域 | 问题 | 推荐值 | 理由 |
|---|---|---|---|---|
| OQ-1 | 范围 | 首期只做 135 拟态（3:2 门），还是连 120 版式一起？ | **只做 135** | 120 版式（三角/计数边/margin 日期）是另一套联排；上游亦分两套枚举。120 入二期 |
| OQ-2 | 形态 | 非 3:2 主图开 film 臂：拒绝+toast，还是拉伸/裁切适配？ | **拒绝+toast**（仿上游 gate-shape 拒收） | 拉伸/裁切破坏「相框」语义；拒绝语义诚实且实现 trivial |
| OQ-3 | 数据 | 32 行 edgeName 文案：营销名大写直用，还是考证每卷真实片边印字？ | **营销名大写直用**（回落语义做唯一语义） | 真实考证需底片实测（上游 2026-10-03 实测投入）；首期用 `info.name` 大写 + push 去后缀 |
| OQ-4 | 数据 | 帧号来源：session 序号 / EXIF 无此字段 / 允许手输？ | **session 序号**（`index%99+1`），单图=空；**加手输覆盖**（0=自动） | 仿上游 `frame_number`（0=seed 自动）；手输覆盖 trivial（Params 一 Int） |
| OQ-5 | 形态 | 边缘字横排先行，还是首期做竖排/旋转？ | **横排先行** | `rotation` 预留未消费，激活= C 包增量 M；横排覆盖 Kodak/Cine/Ilford 三系观感 |
| OQ-6 | 范围 | DX 条首期入围吗？（需 15+ 条 DX 码自查） | **入围，但只做「有码才印」**（无码卷印空带） | 仿上游「空边真于编造码」；码值走公开 DX 库自查，不抄上游表 |
| OQ-7 | 性能/约束 | DRT 管内降级 + gainMap 互斥是否适用于 film 臂？ | **适用（继承，不开例外）** | film 臂仍是 borders 模块内分支；开例外 = ExportChainBuilder 分叉，成本>收益 |
| OQ-8 | 性能 | 边缘行位图缓存：film 维 key 粒度（stock 全 id vs layoutKind）？ | **stock 全 id** | 不同 stock 同 layout 文案不同；budget 48 够（32 卷轮换极少同屏） |
| OQ-9 | 形态 | 片孔 white/black 默认哪档？ | **white**（默认） | 仿上游默认；扫描观感，暗房 print 感走 black 手动档 |
| OQ-10 | 数据 | 日期格式：复用 yiyin `dateFormat` 还是 date-back 专用（`'26 10 1`）？ | **专用格式**（Japan/US 两档，仿上游 order） | yiyin `dateFormat` 是水印语义；date-back 专用两档 trivial（`YiyinExifFormat.formatDate` 旁新函数） |
| OQ-11 | 范围 | 相纸 stock（7）选中 filmStock 时 film 臂行为？ | **回落通用版**（typed degrade，不拒绝） | 相纸无片边；拒绝会卡住「先选纸后换卷」流程 |
| OQ-12 | 形态 | 做旧（fog/leak/portal 颗粒）入围吗？ | **不入首期**（挂二期） | 上游 fog/leak 是曝光语义，做旧在 display 段仿真=滤镜感；且与 grain/halation 站重叠 |

---

## 五、收割指针（orchestrator 用）

- 上游 file 级正本 = §1.2 表（`git show origin/main:<path>` 复读；本地树 stale
  behind 518，勿读工作树）。
- 上游思想可取：布局枚举思想（§1.4）、ISO 1007 DX 算法（§1.5，公开标准独立实现）、
  ShootingData 六字段+缺值留空纪律（§1.6）、session 帧号（§1.6）。
- 上游不取：点阵字形位图（原创表达）、曝光链/kernel（架构不匹配）、20 条 own
  文案逐字（任务书要求自建零复制）、RFC 本体（不在仓）。
- 我方挂点：`BordersModule.Params.frameStyle`（§3.1）+ `YiyinLayout.filmEdge`
  + 新 kernel + `FilmEdgeCopyTable`（Core Film/）+ 注入三腿 film 位（§3.2）。
- 工作量：首期 M-L（~2-3 周单人，A-F 包见 §3.4）；OQ 12 条待用户裁决（§四）。
- 首个 plan 切分建议：P1 = A+B（参数+面板+文案表，可并行）→ P2 = C+D（联排+kernel）
  → P3 = E+F（注入+日期帧号）→ 每 P 独立 golden + 全套回归。

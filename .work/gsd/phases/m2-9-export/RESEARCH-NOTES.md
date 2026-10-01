# M2-9 Research Notes — 导出选项 Alcedo 化（实测清单 + 差异矩阵）

**Gathered:** 2026-09-29（discuss/research 起草 subagent）
**Status:** research input for M2-9-CONTEXT.md — C 档第 1 停前置材料，OQ 交用户裁决前不进 plan
**参考纪律:** Alcedo 仓（`/Volumes/UNITEK/Documents/Development/AlcedoStudio`，GPL-3.0）只读参考——只对标**行为语义与选项面**，代码不复制入库（本项目 MIT）。

---

## 1. Alcedo 源码实测清单（选项全集 + 默认值 + 语义）

### 1.1 Recipe 模型（正本：`alcedo_studio/src/include/io/image/export_recipe.hpp`）

| 选项面 | 定义处 | 默认值 | 语义 |
|---|---|---|---|
| **尺寸四模式** `ExportResizeMode` | hpp:18-23 | `ORIGINAL_PIXELS` | ORIGINAL / LONG_EDGE_PIXELS / BOUNDING_BOX_PIXELS / PHYSICAL_SIZE |
| **物理单位** `ExportPhysicalUnit` | hpp:25 | `INCHES` | INCHES / CENTIMETERS / MILLIMETERS |
| `ExportResizeSpec` | hpp:27-38 | mode=ORIGINAL, `allow_upscale_=false`, `maximum_edge_pixels_=0` | long_edge / width×height px / physical w×h + unit + dpi；upscale 显式开关；0 = 无最大边上限 |
| `ExportPixelSize`/`ExportResolutionResult` | hpp:40-50 | — | 解析产物含 success + pixels + dpi + message（typed 失败） |
| **元数据策略** `ExportMetadataPolicy` | hpp:52-62 | mode=`STANDARD`；exif/xmp/iptc=true；**location/serials/editing_history=false（默认剥离）** | mode ∈ {NONE, STANDARD}；README:93 明文「定位、设备序列号、编辑历史默认剥离」 |
| **ICC 策略** `ExportIccPolicy` | hpp:64, recipe 默认 :127 | `EMBED_OUTPUT_PROFILE` | EMBED / OMIT |
| **Alpha 策略** `ExportAlphaPolicy` | hpp:65, :128 | `PRESERVE_IF_SUPPORTED` | PRESERVE / DISCARD |
| **冲突策略** `ExportCollisionPolicy` | hpp:66, :129 | `FAIL`（legacy 路径 = REPLACE，cpp:266） | FAIL / REPLACE |
| **文件名模板** `ExportFileNameField` 12 字段 | hpp:68-81 | parts 默认 `[SOURCE_STEM]`（:90-94） | LITERAL / SOURCE_STEM / CAPTURE_DATE / CAMERA_MAKE / CAMERA_MODEL / LENS_MODEL / ISO / APERTURE / SHUTTER_SPEED / FOCAL_LENGTH / RATING / SEQUENCE（`number_width_` 补零位宽） |
| `ExportFileNameContext` | hpp:102-115 | `sequence_=1` | 模板求值上下文：stem/capture datetime/make/model/lens/iso/aperture/shutter(num+denom)/focal/rating/sequence |
| `output_color_`（输出编码三元组） | hpp:131-135 | `std::optional`（**无默认，入队前必须已解析**） | `ExportColorProfileConfig{encoding_space, encoding_eotf, peak_luminance}`——从本图 DRT 派生 |
| **入队闸门** `RequireResolvedExportOutputColor` | hpp:141-150 + cpp:280-285 | throw | space/EOTF/peak 未解析（peak 非有限正数）= 拒绝入队（render 与 ICC 共用此编码） |
| 输出色彩默认（对照） | `export_color_profile_config.hpp:11-15` | REC709 / GAMMA_2_2 / 100.0f | 仅作类型默认；生产值来自本图 DRT |

### 1.2 尺寸解析数学（`alcedo_studio/src/io/image/export_recipe.cpp`）

- **ScaleIntoBox** cpp:31-61：fit-inside 取 `min(w_max/w_src, h_max/h_src)`；`!allow_upscale` 时 `scale=min(scale,1.0)`；`llround` 取整 + clamp [1, INT_MAX]。
- **ApplyMaximumEdgeLimit** cpp:63-80：max(width,height) > cap 时按 box 再缩；**DPI 随宽度比例同步修正**（cpp:74-78）——物理打印尺寸保持一致。
- **ResolveExportResolution** cpp:287-325：ORIGINAL 直通（dpi=max(0,dpi)）；LONG_EDGE = ScaleIntoBox(p, p)；BOUNDS = ScaleIntoBox(w, h)；PHYSICAL **要求 dpi>0**（cpp:309-311 否则 typed 失败），像素 = physical/units_per_inch × dpi 再 fit-inside；**maximum_edge_limit 对全部模式尾段生效**（cpp:324）。
- **格式白名单** cpp:327-341：仅 JPEG/PNG/TIFF/EXR 可导出（WEBP/BMP 注释 deprecated）；扩展名 `.jpg/.png/.tif/.exr`（cpp:343-359）。

### 1.3 格式参数（`alcedo_studio/src/include/type/supported_file_type.hpp:34-57`）

- JPEG `quality_=95`；PNG `compression_level_=5`（UI 0–9）；TIFF `NONE/LZW/ZIP` 默认 NONE；`BIT_DEPTH` 8/16/32 默认 16。
- `HDR_EXPORT_MODE` = `ULTRA_HDR` / `EMBEDDED_PROFILE_ONLY`；`ultra_hdr_quality_=95`（gain map）+ `ultra_hdr_dither_enabled_=true`；Ultra HDR 自动 8192px 上限（`startExport` 固定实参，QML:313）。
- UI 位深可达面（QML:98-108, 179-192）：JPEG=8；PNG=8/16；TIFF=8/16/32；EXR=16/32；非法组合自动回落合法位深（:194-198）。

### 1.4 文件名模板引擎（`export_recipe.cpp`）

- **Token 语法** cpp:210-259：`{source}` / `{date:yyyy MM dd}` / `{cameramake}` / `{cameramodel}` / `{lens}` / `{iso}` / `{aperture}` / `{shutter}` / `{focal}` / `{rating}` / `{sequence:0000}`（sequence 实参必须全零数字，否则解析失败——位宽编码在零的个数里）；token 名大小写不敏感（cpp:216-217）。
- **转义与错误** cpp:376-422：`{{`/`}}` 字面转义；未闭合花括号 / 未知字段 / 空模板 = typed message（不静默容错）。
- **字段渲染** cpp:136-171：date 默认格式 `yyyyMMdd`、token 表 yyyy/MM/dd/HH/mm/ss（cpp:113-118）；ISO=0 → 空串；aperture 1 位小数；shutter = `分子-分母`（`1-500` 形态——`/` 在文件名非法所以用 `-`）；focal 1 位小数 + `mm` 后缀；rating clamp 0-5；sequence 按位宽补零。
- **Sanitize** cpp:183-197：控制字符与 `<>:"/\|?*` → `_`；首尾空格/点剔除；Windows 保留名（CON/PRN/AUX/NUL/COM1-9/LPT1-9）补 `_`；**stem 上限 200 字符**。
- **Fallback** cpp:369-371：渲染结果空 → `fallback_stem_`（默认 `"image"`，hpp:93）；再空 = typed 失败。
- **命名预设**（`ExportNamingEditor.qml:35-52`）：3 内置——`{source}`（Source）/ `{date:yyyy MM dd}-{sequence:0000}`（Date + No.）/ `Export-{sequence:0000}`（Export）+ 用户自存预设（存储走 `album_backend/import_export.cpp:511-590`，QSettings 持久化，支持改名替换 `replacedName`）+ Custom 尾项；**live 预览**（QML:19-20，样本 = 队列首行名）；token 插入按钮 11 枚（QML:56-67）。

### 1.5 UI 形态与队列（`alcedo_studio/src/ui/alcedo_main/qml/ExportInspectorPanel.qml`）

- **面板形态**：检查器（Inspector）内嵌页，**注释明示取代了旧 modal AlbumExportDialog**（QML:10-11）。
- **控件默认值** QML:27-46：JPEG / 8bit / TIFF NONE / PNG level 5 / subfolder 关（默认文案 `"Processed"`）/ metadata 开 / ICC embed 开 / resize=original / longEdge 文本 2048 / bounds 2048×2048 / 物理 210×297 / mm / 300 dpi。
- **校验域** QML:49-63：longEdge 256..16384（:802）；bounds 1..100000（:840,:873）；物理 0.01..100000 双精度 2 位（:916）；DPI 1..10000（:1008）。naming pattern 无效 = 整页 startExport 禁用（:64）。
- **Destination 节** QML:445-558：目录 TextField + Browse（FolderDialog）+ `Put in Subfolder` checkbox + 子目录名；`effectiveOutDir` 拼接（:84-89）。
- **File Naming 节** QML:560-589：内嵌 ExportNamingEditor（预设下拉 + token 按钮 + 模式串 + 预览 + 存/删预设）。
- **Metadata & Color 节** QML:591-646：**单开关**「Include photo metadata」+ 说明文案「Writes EXIF, XMP, and IPTC. Location, device serials, and edit history stay excluded.」（:621）——**细粒度档位未上 UI**（模型有、UI 单开关）；「Embed output ICC profile」checkbox（:628-636）。
- **SDR Export 节** QML:649-1026：Format 四段切换 / Bit Depth / JPEG quality 滑杆（1-100 默认 95）/ PNG level 滑杆（0-9 默认 5）/ TIFF compression / Size 四模式切换 + 各模式字段 + 单位切换 + DPI。
- **HDR Export 节** QML:1028-1075：**队列含 HDR 项才可用**（`hasHdrItems` gate，QML:23）；Ultra HDR quality 滑杆 + Dithering checkbox。
- **队列** QML:1077-1250：「Add selected to queue」+「Clear」；行 = SDR/HDR 图标 + 文件名 + 状态点（Queued/Exporting/Done/Failed 四态，:200-236）；预览上限 36 行 + `...(N more)` 汇总行（:47, :129-143）；列表高 180px 内滚。
- **进度** QML:1259-1318：`completed/total` + 进度条 + error summary 红字。
- **质量跨会话记忆** QML:271-288 + `import_export.cpp:43,491-499`：QSettings 键 `export/sdrQuality`（默认 95，clamp 1-100）+ Ultra HDR quality 独立键；面板 `preparePage` 载入、导出/离页时写回（:285-288, :353-358）。

### 1.6 导出服务链（`alcedo_studio/src/app/export_service.cpp`）

- RunExportRenderTask cpp:98-222：require resolved output color（:107）→ 名字解析（模板，:131-143）→ tmp 路径 → 全幅渲染（`FULL_RES_EXPORT` + `export_output_color_` 传入管线，:177-178——**渲染与 ICC 共用同一编码**）→ encode 到 tmp → 校验非空（:206-210）→ 原子 commit（:213）。
- **CommitExportFile** cpp:69-93：`FAIL` = 已存在即 throw；`REPLACE` = 覆盖（Windows `MOVEFILE_REPLACE_EXISTING` / POSIX rename）。
- 元数据收集 cpp:30-53（EXIF 显示面 + rating normalize）；`metadata_written_` 仅 STANDARD 模式为真（:217-218）；`icc_embedded_` 仅 EMBED 且 profile 有值（:219-220）；`resolution_tags_written_` = dpi>0（:221）。
- ICC 解析器独立成件：`alcedo_studio/src/io/image/export_icc_profile_resolver.cpp`（285 行，config → profile 构建）。

---

## 2. Lightamer 现有 EXP 面锚点

### 2.1 Core 层（`LightamerCore/Sources/Export/`）

- **`ExportRecipe.swift`**：`ExportVariant`（:23-101）= `sizing: YiyinExportSettings`（OQ-11-6 正主：original/longEdge/shortEdge + 永不放大钳）+ `scalePercent` 载体（:33，`effectiveSizing` :95-100 折算）+ `format: ExportFormatSpec`（六格式 :165-307，每格式精确旋钮 + 嵌套位深枚举类型级非法组合不可构造）+ `colorSpace: ExportColorSpace` 五选菜单（:314-320）+ `yiyin: Bool` + `outputTag`。`ExportRecipe = [ExportVariant]`（:105）；v1 不持久化（D-11-CONTEXT-3，Codable 预留 Phase 12）；**无哈希字段红线**（:11-12）。多 variant tag 派生 `resolvedOutputTags`（:118-138）。
- **`ExportNamer.swift`**：`<stem>[_<tag>].<ext>` + 大小写不敏感 `-1/-2` 递增；sanitize 仅 `/`+`:` → `-`、trim、`Untitled` 兜底（APFS 宽容政策）。
- **`ExportQueue.swift`**：actor + generation epoch（:100）+ **并发 1**（内存红线 D-11-CONTEXT-2）+ FIFO pump（:303+）+ retry 显式（:246-267）+ 两层进度快照（:280）+ per-job completion hook（:114-124，post-actions EXP-08 路径制）。
- **`ExportRenderer.swift`**：`Request`（:71-117）含 `instancesOverride: [ModuleInstance]?`（:100-104——**nil = 读盘上 sidecar（真相）；非 nil = 活编辑面**）+ `editorSignature`（TIFF Software 预留）；renderStage/encodeStage 两段拆分（取消跨界零落盘）；`ExportYiyinInjector` 注入缝（:56-64，Core 不点名 yiyin 模块——App 供生产注入器）；decode leg 缝（导出恒全幅解码一次）。
- **`ExportChainBuilder.swift`**：gamma 必剔 + **colorout 保留 + target 覆写**（`exportTargetOverride` socket，出口转换恰一次不变量）。
- **`ExportEncoder.swift`**：EXIF round-trip 走 properties 路径（:18）；ICC 嵌入 = CGImage 色彩空间（:101-102，转换与嵌入一体）；`editorSignature` = TIFF Software（:113-115）；`xmp:CreatorTool` 经 ImageIO 不可写（已文档化）。
- **`ImageIOEncoders.swift`**：`kCGImageDestinationMetadata` = 本宿主唯一存活 metadata 写路径（:15）。
- **`XMPWriter.swift`/`XMPContainerInjector.swift`**：编辑摘要 XMP packet（D-11-CONTEXT-5——**注意与 Alcedo「editing history 默认剥离」的语义冲突，见 §3 矩阵 M5**）。
- **`Presets/PresetsStore.swift`**：`~/Library/Application Support/Lightamer/Presets/<uuid>.lightamer-preset`（:7-11, :85-91）——PRES 面是**调整栈预设**，非导出 recipe；目录惯例可复用。

### 2.2 DRT 与版本投影（M2-8 交接面）

- **`LightamerCore/Sources/Graph/DrtRecord.swift:344+`**：12 字段——`method`(aces_2_0/open_drt)、`encodingSpace`（rec709/p3_d65/p3_d60/p3_dci/xyz/rec2020，:46-57）、`encodingEotf`（linear/st2084/hlg/gamma_2_6/bt1886/gamma_2_2，:62-76）、`peakLuminance` [100,1000]、limitingSpace、look/tonescale/creativeWhite 预设等。默认 = rec709/gamma22/100（:383-395）。**与 Alcedo `ExportColorProfileConfig{space,EOTF,peak}` 三元组同构**。
- **`LightamerCore/Sources/Pipe/History/HistoryStack.swift`**：`effectiveDrtRecord()`（:471-475，指针跟随 newest-wins）+ `projection(upTo:)`（:440-455，instances+layerSnapshot）。
- **`LightamerCore/Sources/Pipe/PixelPipe.swift`**：`.drt(DrtTailParams)` 终段 leg（:135-145, :701-706, :846-847）——`[DrtMethodBox] → [EotfBox] → colorout/borders/watermark` 尾段重放；`.drt` 时终平面像素格式跟随 record EOTF（:273-295）。**导出链当前剔除 gamma、覆写 colorout（11 先例），DRT 尾段在导出链的消费 = M2-9 planner 的核心接线题**（CONTEXT D-4/OQ-7）。
- **M2-8-3-SUMMARY.md:156-162 交接**：`EditorState.instances/layerStack` 投影 + `effectiveDrtRecord` 载体随 active 链走；6 格式 Export 管线零改动；`.lalb` 版本投影列（导出 manifest 消费）如需 = 注入 sink 形态复用。
- **App 侧消费**：`App/Sources/Lightamer/State/PipeCoordinator.swift:595-607`（drtCarrier 与 history 投影一致性守卫）+ `VersionCoordinator.swift:207`（版本切换全路径扫 `effectiveDrtRecord`）。

### 2.3 13-2 色彩资产（ICC 复用面）

- `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift`：`exportTargetOverride` / `displayProfileOverride` 双 socket（13-2 同形扩展先例）；OutputProfile 导出枚举。
- `LightamerCore/Sources/Foundation/DisplayProfile.swift`：`resolve` 四级匹配 + exact-TRC parser（matrix-shaper XYZType）+ `.colorSyncFallback` linearCGColorSpace workalike + `LinearVariantCache`（per-ICC-byte-hash，13-2 修复批）——**DRT space/EOTF → CGColorSpace/ICC 的映射资产现成**。
- `SoftProofStage`（13-2）：结构性永不进 history/sidecar/export（四断言钉死）——软打样与导出正交，不触碰。

### 2.4 App 层 UI 现状

- `App/Sources/Lightamer/Export/ExportPanelView.swift`（821 行）：**sheet 形态**（toolbar 导出按钮 raise，session 必须开着），recipeSection（VariantEditor：sizing Picker original/longEdge/shortEdge + percent、format/quality/depth、colorSpace 五菜单、yiyin toggle）/ destinationSection / postActionsSection / queueActionSection / queueStatusSection。
- 挂载点：`App/Sources/Lightamer/UI/ContentView.swift:337-340`（`.sheet(isPresented: $exportPanelRequested)`）。
- **M2 默认面 = ProjectWorkspaceFace**（ContentView.swift:647+，gate=false 隐藏 Sessions 双区）——现有导出 UI 挂在 Sessions 域 shell 上，M2 工作区（项目上下文）无导出入口；`LibraryLegacyGate`（`LIGHTAMER_LEGACY_LIBRARY=1`）= QA 回切通道。
- `App/Sources/Lightamer/State/ExportState.swift`（307 行）：面板状态载体（recipe/destination/post-actions/队列快照）。

### 2.5 命名模板上下文素材（12 字段可达性）

- `LightamerCore/Sources/Decode/CaptureMetadata.swift:8-35`：cameraMake/cameraModel/lensModel/focalLength/aperture/shutterSpeed(Double 秒)/iso/`DateTimeOriginal`（IPTC DateCreated 回落）——模板 8 字段现成；**rating 在 sidecar/META 面**（Phase 12）；**sequence = 队列内序号**（需导出面新算）；stem = 源文件名。
- Render 链已在 `ExportRenderer` 的 yiyin 注入签名中携带 `CaptureMetadata`（:56-64）——模板求值可走同源数据。

---

## 3. 差异矩阵（Alcedo vs Lightamer EXP vs M2-9 处置）

| # | 选项面 | Alcedo（实测） | Lightamer 现状 | M2-9 处置（ROADMAP/推荐） |
|---|---|---|---|---|
| F1 | **格式集** | JPEG/PNG/TIFF/EXR + Ultra HDR（WEBP/BMP deprecated，cpp:327-341） | 六格式 JPEG/PNG/TIFF/HEIC/AVIF/WebP（`ExportFormatSpec`） | **保留六格式零改动**（用户终裁）；EXR/UltraHDR = V2（ALCE-02/03）；编码器红线不动 |
| F2 | 位深面 | JPEG 8 / PNG 8,16 / TIFF 8,16,32 / EXR 16,32 | JPEG 8 / PNG 8,16 / TIFF 8,16,32f / HEIC 8,10 / AVIF 8,10,12 / WebP 8 | 不变（六格式各自面已超 Alcedo） |
| S1 | **尺寸模式** | Original/LongEdge/Bounds/Print(in-cm-mm+DPI)（hpp:18-25） | original/longEdge/shortEdge + percent（`YiyinExportSettings` + `scalePercent`） | **新增 Bounds/Print 两模式**（M2EXP-01）；shortEdge/percent 保留（超集不删） |
| S2 | **upscale 开关** | `allow_upscale_=false` 显式开关（cpp:48-50） | 永不放大硬钳（无开关） | **加开关，默认 false**（M2EXP-01；现行为 = 默认档不变） |
| S3 | **最大边上限** | `maximum_edge_pixels_=0`=关，尾段全模式生效 + DPI 修正（cpp:63-80） | 无 | **新增**（M2EXP-01；Ultra HDR 8192 上限先例语义） |
| S4 | Print 模式 DPI 缺失 | typed 失败（cpp:309-311） | DPI 独立旋钮 1..2400（EXP-03） | Print 模式内嵌 DPI 必填；独立 DPI 旋钮保留（写入面已交付） |
| M1 | **元数据策略** | STANDARD/NONE + 三默认剥离 location/serials/editing_history（hpp:52-62；UI 单开关，QML:609-626） | EXIF round-trip + XMP 编辑摘要 packet，**无剥离**（D-11-CONTEXT-5） | **加策略模型 + 默认剥离三项**（M2EXP-02）；现 XMP 编辑摘要 packet 默认应归入「editing history」档 → 默认不嵌（见 CONTEXT OQ-6） |
| M2 | EXIF 写本 app 版本 | 0.2.9 起导出文件 EXIF 写 Alcedo 版本（FEATURE-MAP §7） | 仅 TIFF Software `editorSignature` 预留；EXIF Software 未写 | **EXIF Software = `Lightamer <version>`**（M2EXP-02；properties 路径可写，决策非 OQ） |
| C1 | **输出 ICC/色彩** | `EMBED/OMIT` + 输出编码 = 本图 DRT 三元组，**入队前强制已解析**（hpp:127,141-150；渲染与 ICC 共用，service cpp:177-178） | `ExportColorSpace` 五选菜单（sRGB/P3/AdobeRGB/ProPhoto/Rec2020），与 DRT 无关 | **替换为 DRT 派生强制联动**（M2EXP-04）；五菜单退役（Codable 无迁移负担——recipe 未持久化）；映射走 13-2 资产；EMBED/OMIT checkbox 对齐 |
| C2 | HDR 输出 | Ultra HDR（gain map+dither）或 EMBEDDED_PROFILE_ONLY（PQ/HLG 文件直出） | SDR 白钳位（D-11-CONTEXT-7）；EDR 输出 v2 | v1 维持钳位口径，PQ/HLG 编码图的输出语义 = OQ（CONTEXT OQ-8）；Ultra HDR = V2 |
| N1 | **文件名模板** | 12 字段 token 语法 + 转义 + typed 解析错误 + sanitize(200 字符) + fallback "image"（cpp:210-259,376-422,183-197） | `<stem>[_<tag>].<ext>`，无模板 | **新增模板引擎**（M2EXP-03；语法选型 = CONTEXT OQ-4）；tag 派生与模板并存（tag = variant 维度、模板 = 文件名维度） |
| N2 | **冲突策略** | FAIL/REPLACE，默认 FAIL（hpp:66,129） | 恒 `-N` 递增（D-11-CONTEXT-4） | **加 FAIL/REPLACE 档**（M2EXP-03）；默认档 = OQ（CONTEXT OQ-5；现递增行为去留一并裁） |
| N3 | **子文件夹** | checkbox + 文案（默认 `"Processed"`，开关默认关）（QML:31,525-556） | 无 | **新增**（M2EXP-03；默认关） |
| N4 | 命名预设 | 3 内置 + 用户自存（改名替换）（QML:35-52；import_export.cpp:511-590） | 无 | 新增（范围/存储 = CONTEXT OQ-9） |
| Q1 | **队列 UI 形态** | **检查器内嵌页**（取代旧 modal，QML:10-11） | sheet 对话框（11-04） | ROADMAP 明写「检查器内」→ 迁检入器（CONTEXT OQ-1 裁形态与旧 sheet 去留） |
| Q2 | 队列四态 | Queued/Exporting/Done/Failed（QML:200-236） | 队列快照有进度/取消/重试，UI 四态未逐项对齐 | 对齐四态（M2EXP-05；queue 数据面已有） |
| Q3 | **质量跨会话记忆** | QSettings `export/sdrQuality` 等（cpp:43,491-499） | 无 | 新增（UserDefaults；键面 = CONTEXT OQ-10） |
| Q4 | 并发/取消/重试 | 串行（单个 in-flight `exportInFlight` gate） | actor + 并发 1 + generation cancel + retry（EXP-06 超集） | **零改动**（并发 1 红线；Alcedo 面是我们子集） |
| P1 | post-actions | 无 | 路径制脚本 + Finder reveal（EXP-08） | **保留**（超集，Alcedo 无此面） |
| P2 | yiyin 终步 | 无（FEATURE-MAP §「flip/borders/watermark: 无」） | variant.yiyin + 注入器（EXP-05） | **保留适配**（ROADMAP 明写；唯一注意点 = yiyin sizing 语义与新四模式并存） |
| D1 | 默认落点 | `defaultExportFolder`（后端提供，QML:239-240） | `SessionLayout.outputDirectory`（Sessions 域常量） | M2 项目上下文无 Session → **默认落点重定义**（CONTEXT OQ-3） |
| D2 | recipe 预设 | 无（仅命名预设） | v1 不持久化（D-11-CONTEXT-3，Phase 12 PRES 挂载预留） | 全 recipe 预设不在 M2-9 范围（挂账 PRES 交汇；OQ-9 一并裁） |

---

## 4. 依赖面落实路径（M2-8 交接 → 导出渲染链）

1. **instances/layerStack 投影**：`ExportRenderer.Request.instancesOverride` 缝已存在（ExportRenderer.swift:100-104）——App 层入队时以 `EditorState.history.projection(upTo:)`（instances + layerSnapshot）构造 override；版本切换后随 active 链走（M2-8-1 T2 测钉）。**Core 渲染器零改动**，接线全在 App 装配点。
2. **effectiveDrtRecord 进 ICC 联动**：入队闸门（Alcedo `RequireResolvedExportOutputColor` 同构）= App 层从 `EditorState.history.effectiveDrtRecord()`（nil → `DrtRecord()` 默认）取三元组，随 job 下发；CGColorSpace/ICC 构建复用 13-2 资产（DisplayProfile/exact-TRC/LinearVariantCache）。
3. **DRT 尾段在导出链**：现导出链剔 gamma + 覆写 colorout（11 先例）；M2-6 后管线的 `.drt` 终段 leg（PixelPipe.swift:701-706）在 export route 的重放语义 = planner 接线核心题（可能形态：export pipe 以 `.drt` 尾段替代 gamma+colorout 对，输出编码即 DRT 编码）。
4. **6 格式编码器零改动红线**：`ExportFormatSpec`/`ImageIOEncoders`/`WebPEncoder` 不触碰；上游变更止步于 chain assembly + quantizer 入口分层（若 OQ-8 裁 PQ/HLG 不钳位，quantizer 分档 = 唯一可能触碰点，需 golden 重冻结评估）。
5. **队列并发 1**：ExportQueue actor 不动；新选项全部走 `ExportVariant`/Request 载体扩容。
6. **`.lalb` 版本投影列**（导出 manifest）：如需 = 注入 sink 形态复用（AGENTS.md M2-8 节）；v1 可不做。

---

## 5. 性能/批量面

- 并发 1 + 专用低优先级 MTLCommandQueue（D-11-CONTEXT-2）不动；全幅 float32 ≈ 800MB@100MP 内存推导不变。
- 命名模板求值 = 纯字符串纯函数（Alcedo 同构），逐 job 一次，无性能面。
- maximum_edge_pixels 缩放发生在 sizing 数学内（fit-inside 一次），无二次渲染。
- 队列预览行上限（Alcedo 36 行 + 汇总行）= UI 层截断，SwiftUI List 同构做法。

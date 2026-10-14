# M6-3 RESEARCH — ALCE-03 UltraHDR gain map JPEG 导出解冻（spike 结论 + 两臂对照 + 集成面测绘）

> Phase M6-3 research worker 落盘（2026-10-14 夜间批，夜间授权先例 D-07-3-T5-1，晨审可推翻）。
> charter 正本 = ROADMAP §Milestone 6 M6-3 行；M6-1 前瞻底稿 = `phases/m6-1-interop/RESEARCH-NOTES.md` §5。
> spike probe 全部在 `/tmp/m63probe/`（即弃，不入仓）；关键输出已 inline 摘录本文。
> 本文档 doc-only，零源码改动。

---

## Summary（结论一览）

1. **ImageIO 直挂 aux（M6-1 §5 的 A 路）在 macOS 27 实测为死路**：`CGImageDestinationAddAuxiliaryDataInfo` + `kCGImageAuxiliaryDataTypeISOGainMap` 在 JPEG destination 上对所有 payload 形态（raw bitmap / ISO blob / 带 metadata / 带 colorspace / 带 PixelFormat description）一律 `finalize=false`——**连 disparity 对照臂都同样被拒**（API 面本身不接受此 host/direction），非 payload 形态问题。
2. **`kCGImageDestinationEncodeGenerateGainMapWithBaseImage` 键族（B 路）同样死路**：AddImage 时被**静默忽略**（产物无 gain map 无 MPF）；JPEG destination `count=2` 直接构造失败（`CGImageDestinationCreateWithData` 返 nil）；`CopyImageSource` 跨 UTI（HEIC→JPEG）按契约拒绝。
3. **真正可行的原生路 = Core Image 全服务写（M6-1 未列的第四臂）**：`CIContext.writeJPEGRepresentation(of: sdrCIImage, to:, colorSpace:, options: [.hdrImage: hdrLinearCIImage, quality])`（`kCIImageRepresentationHDRImage`，macOS 15+；Swift renamed `.hdrImage`）——**CI 自算 gain map（HDR/SDR 比率）并写出完整 ISO 21496-1 容器**：MPF APP2 索引 + ISO APP2 URN 标记 + 尾部 gain map 副图 + Apple `HDRToneMap` 元数据，全部亲证落盘。
4. **读回路径全通**：`CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeISOGainMap)` 返完整字典（Data + DataDescription{PixelFormat 'L008', Width, Height, BytesPerRow} + HDRToneMap metadata + ColorSpace）；CI 侧 `kCIImageAuxiliaryHDRGainMap` 读回亦通；properties 暴露 `Headroom` / `PrimaryImage` 键。
5. **元数据 rewrap 缝走通**：`CGImageDestinationCopyImageSource`（JPEG→JPEG，须带 metadata 字典键，properties-EXIF 路被 typed 拒）+ `kCGImageDestinationMetadata`(XMP) → **gain map 结构逐字节存活（isoURN/MPF/aux 读回全 PRESENT）且自定义 XMP 落盘**。
6. **推荐：原生 CI 全服务路为主臂，LightCraft Rust 移植（C 路）降级为兜底**——容器字节已达标即收（charter 纪律「原生路容器字节达标即收，不达标落移植」）；C 路唯一不可替代点 = gain map 副图内嵌 `hdrgm` XMP（老 Android/Chrome 兼容），挂 OQ 裁决。
7. **ALCE-03 冻结理由已化解**（详见 §6）：V2 冻结理由 =「gain map 构造需 research（Apple Adaptive HDR API 面）」——API 面已由本 spike 实测定型；HDR rendition 基建已由 M2-6（DRT 尾）+ M2-9（drtOutput 强制联动 + peak 闸 + HDR ICC 臂）+ M4-1（HDR TIFF 16-bit PQ 先例）交付。

---

## 1. Spike 实测（macOS 27 SDK / macOS 27.0 host，swiftc 6.4 直编，/tmp 即弃）

### 1.1 环境与常量核对（headers 实测）

| 常量 / API | SDK 声明 | 版本 |
|---|---|---|
| `CGImageDestinationAddAuxiliaryDataInfo` | CGImageDestination.h:401 | macOS 10.13+ |
| `CGImageSourceCopyAuxiliaryDataInfoAtIndex` | CGImageSource.h:577 | macOS 10.13+ |
| `kCGImageAuxiliaryDataTypeHDRGainMap`（Apple 旧档） | CGImageProperties.h:2373 | macOS 11.0+ |
| `kCGImageAuxiliaryDataTypeISOGainMap` | CGImageProperties.h:2374 | **macOS 15.0+** |
| `kCGImageDestinationEncodeRequest` / `EncodeToSDR` / `EncodeToISOHDR` / `EncodeToISOGainmap` / `EncodeRequestOptions` / `EncodeBaseIsSDR` / `EncodeTonemapMode` | CGImageDestination.h:405-415 | **macOS 15+** |
| `kCGImageDestinationEncodeIsBaseImage` / `EncodeBaseColorSpace` / `EncodeBasePixelFormatRequest` / `EncodeGenerateGainMapWithBaseImage` / `EncodeGainMapPixelFormatRequest` / `EncodeGainMapSubsampleFactor` / `EncodeAlternateColorSpace` | CGImageDestination.h:417-423 | **macOS 16+** |
| `kCIImageRepresentationHDRImage`（Swift `.hdrImage`） | CIContext.h:744 | **macOS 15+** |
| `kCIImageRepresentationHDRGainMapImage` / `hdrGainMapAsRGB` | CIContext.h:752-772 | 11.0+ / 15.0+ |
| `CIImage.imageBySettingContentHeadroom(_:)` | CIImage.h:611 | **macOS 26+**（27 底线内） |
| `kCIImageAuxiliaryHDRGainMap`（读） | CIImage.h:290 | macOS 11+ |

**两代 CGImageDestination 键族（15/16）在 headers 全部在案但零文档注释**——语义只能 probe；结论见下：两代键族在 JPEG 写向上均不生效。

### 1.2 Exp-A 臂：手动 aux 挂载（死路，六变体全拒）

fixture：64×48 SDR sRGB RGBA8 基图 + 自算 gain（log2((hdr+off)/(sdr+off))，scale 2 块均值，min/max 归一 u8，32×24 单通道）+ 自写 ISO 21496-1 blob（URN + 版本 + flags + headroom/逐通道 rational×1e6，参考二进制布局转写）。

| 变体 | aux dict 形态 | 结果 |
|---|---|---|
| A1 | Data=raw u8 bitmap + Description{Width,Height,BytesPerRow} | **finalize=false** |
| A2 | Data=ISO blob 本体 + 同上 Description | **finalize=false** |
| A3 | 同 A1 → HEIC destination | **finalize=false**（0 字节） |
| A4 | A1 + Metadata=CGImageMetadataRef（hdrgm XMP） | **finalize=false** |
| A5 | Data=完整二级 JPEG（ImageIO 自编 gain bitmap） | **finalize=false** |
| A6（对照） | `kCGImageAuxiliaryDataTypeDisparity` 标准深度形态 | **finalize=false** ← 关键对照 |
| A7 | `kCGImageAuxiliaryDataTypeHDRGainMap`（Apple 旧型） | **finalize=false** |
| E1 | DataDescription 镜像读回形态（+PixelFormat 'L008' fourcc 数值）+ Metadata + ColorSpace | **finalize=false** |

**结论**：A6 对照被拒证明不是 payload 形态问题——`CGImageDestinationAddAuxiliaryDataInfo` 在本 host 的 JPEG/HEIC 写向上对该调用形态整体拒绝（可能仅接受 read-side 回填的内部字典，或已事实废弃）。**A 臂淘汰，不再投入。**

### 1.3 Exp-B 臂：destination 生成键族（死路，四形态全否）

| 变体 | 形态 | 结果 |
|---|---|---|
| B1 | 单 AddImage（linear Rec2020 f32 HDR）+ `GenerateGainMapWithBaseImage: true` | finalize=true 但**键被静默忽略**：isoURN=false、MPF=false、aux 读回 nil |
| B2 | 同 B1、PQ-tagged Rec2020 f32 源 | 同 B1（静默忽略） |
| B3 | 双 AddImage（base `IsBaseImage=true` + HDR） | **destination 构造失败**：JPEG `CGImageDestinationCreateWithData(count:2)` 返 nil（JPEG 单图容器） |
| B4 | `kCGImageDestinationEncodeRequest: EncodeToISOGainmap`（macOS 15 代键） | 同 B1（静默忽略） |
| B5 | `CopyImageSource` HEIC(HDR)→JPEG + 三个键组合 | 全部 `copyImageSource=false`（跨 UTI 按契约拒绝：「image type of destination must match image source」） |
| B7 | 同 B1 → HEIC destination | finalize=true 但无 gain map（键对 HEIC 也不生效） |

**结论**：15/16 两代 destination 生成键族在本 host 对 JPEG 写向**不产生 gain map**（键存在、被消费层静默丢弃）。B 臂淘汰。

### 1.4 Exp-D/E/F 臂：Core Image 全服务路（✅ 全通 = 推荐主臂）

核心调用（Swift renamed 常量）：

```swift
try ciContext.writeJPEGRepresentation(
    of: sdrBaseCIImage,                 // SDR 基面（RGBA8 + 输出 ICC 色彩空间）
    to: url, colorSpace: outputCGColorSpace,
    options: [
        .hdrImage: hdrLinearCIImage.imageBySettingContentHeadroom(headroom),  // macOS 26+
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9,
    ])
```

| 实验 | 结果 |
|---|---|
| D1 linear Rec2020 f32 HDR（headroom 8.0） | ✅ 15636B；**isoURN=true MPF=true**；aux 读回 PRESENT：data=3072B（64×48 全分辨率 L008），desc={PixelFormat:'L00\8', W:64, H:48, BytesPerRow:64}，metadata=HDRToneMap{BaseHeadroom 0, AlternateHeadroom 2.9665, GainMapMin 0.1137, GainMapMax 3.3826, Gamma 1.0, BaseOffset≈1e-5, BaseColorIsWorkingColor True}，colorspace=PQ-tagged ICC |
| D2 + `.hdrGainMapAsRGB: true` | ✅ RGB gain map（PixelFormat '444f'，BytesPerRow 128）；注意：读回侧 Data 键被 reader 扣留（JuniperPhoton 同报）——v1 用亮度单通道即可，无影响 |
| D3 同选项 → HEIF | ✅ 同样工作（aux 7680B L008）——顺带确认 HEIF 档亦可达（非本期目标） |
| D4 手动 ImageIO 四键 dict（含 PixelFormat/ColorSpace） | ❌ finalize=false（与 A/E 臂一致，再次证明手动路死） |
| E2 基面保真 | **d1 基面解码 == 纯 JPEG 编码对照（四采样点逐值相等：8/129/250/194 vs 8/129/250/194）**——CI 不改写我方基面像素、无双重压缩 |
| E3 质量旋钮 | ✅ q=0.5 → 15427B，q=0.95 → 15676B（`kCGImageDestinationLossyCompressionQuality` 被 CI 写路接受） |
| E4 PQ 码值直喂 `.hdrImage` | ⚠️ 容器合法但 **gain 语义错误**（对 PQ 编码码值取比率；AlternateHeadroom 2.30 / GainMapMax 14.1 明显非物理）——**必须喂线性光 HDR 面**（f32/16F 均可，任意 primaries） |
| F6 16F（RGBA half）HDR 输入 | ✅ 与 f32 同构工作（AlternateHeadroom 2.967 ≈ log2(8.2)，符合 fixture 8×） |
| F2 纯 `CopyImageSource`（无选项） | ✅ 无损容器拷贝，isoURN/MPF 存活 |
| F3/F4 `CopyImageSource` + properties-EXIF 字典 | ❌ **typed 拒绝**：「One of kCGImageDestinationMetadata, kCGImageDestinationOrientation, kCGImageDestinationDateTime, kCGImageMetadataShouldExcludeXMP, or kCGImageMetadataShouldExcludeGPS is required.」——CopyImageSource 只认 metadata 字典键，不认 properties 键 |
| F5 `CopyImageSource` + `kCGImageDestinationMetadata`(XMP) | ✅ **gain map 全存活**（isoURN/MPF/aux 读回 PRESENT）+ 自定义 XMP（xmp:CreatorTool）落盘 + Headroom=7.816 可读 |

D1 容器结构定格（marker dump）：

```
0xE0 JFIF → 0xE1 EXIF → 0xE2 MPF\0（多图索引）→ 0xE2 "urn:iso:std:iso:ts:21496:-1"（版本标记）
→ DQT/DHT/SOS 主图 scan → 主图 EOI → [尾部 gain map 副图 JPEG（MPF 索引指向，内嵌 ISO APP2 + HDRToneMap XMP）] → 文件尾 EOI
```

与 UltraHDR / ISO 21496-1 MPF 容器布局一致（同 LightCraft 手工构建的结构）。

### 1.5 外部校验现状

- `sips` 解码 ✅（pixelWidth/Height/space=RGB 正常）。
- exiftool 本机不可用；Preview/Photos HDR 渲染目检 + Android/Chrome 跨生态 → **Manual-Only 走查批**（gui-acceptance 配方随 plan 落，§8 风险）。

---

## 2. LightCraft 对照臂评估（C 路）

正本 = `lightcraft/crates/codecs/src/gainmap.rs`（834 行含测试；HEAD 25ef65c v0.7.0）+ `crates/engine/src/export.rs encode_gain_map_jpeg`。

### 2.1 算法面（可移植，MIT OR Apache-2.0）

- **gain 计算**：`log2((hdr+off)/(sdr+off))`，off=1/64（黑位有限 + 噪声压默）；scale 1/2/4 块均值降采样；单通道亮度（默认；Apple reader 只认单通道）或 RGB 三通道；min/max 归一 + gamma 到 u8。`apply` = 双线性采样 + `(code/255)^(1/γ)` 反归一 + `(base+off)·2^(g·weight) - off_alt`。
- **headroom 语义**：`base_headroom=0`（SDR 基图）、`alternate_headroom=max(gain)`——按内容测得，非外部 peak 输入。
- **量化补偿细节**（值得抄）：LightCraft 把**已编码 8-bit 基面 decode 回线性**再取比率（`trc.decode(p/255)`）——gain map 把基面 8-bit 量化损耗还回去；CI 路是拿未量化基面直接算（无补偿），感知差异可忽略。
- **容器面**（移植成本大头）：手工 JPEG 段装配——副图 JPEG（ISO APP2 + hdrgm XMP APP1 + Apple apdi/HDRGainMap/HDRToneMap 三命名空间描述）→ 主图（Container XMP + ISO 版本标记 APP2 + MPF 占位）→ MPF 偏移回填 → 拼接。**无 MPF 时部分 reader 不认**。

### 2.2 移植成本与义务

| 件 | 行数估计（Swift） | 风险 |
|---|---|---|
| compute/apply 纯数学 | ~200 行 | 低（golden 可对拍） |
| ISO 21496-1 blob writer/parser | ~120 行 | 低 |
| hdrgm/Apple XMP 装配 | ~120 行 | 低 |
| JPEG 容器装配 + MPF 回填（依赖其 jpeg_par 自研编码器） | **~400+ 行 + 段级 golden 全套** | **高**——我方无自研 JPEG 段写入器，须自建段级装配/回填/解析，回归面大 |

- **许可义务**：MIT OR Apache-2.0——代码级移植合法，**成段移植须 NOTICE 归属同 commit 登记**（LIGHTCRAFT-NOTES §五既定）。若只走 C 路（不移植），零义务。
- **对读价值**：即便不移植，LightCraft 产物可作 C 路对读参照（其 reader 可读我方 CI 产物与否 = plan 期交叉验证项）。

### 2.3 两臂对比表

| 维度 | 原生 CI 全服务路（推荐） | LightCraft Rust 移植（兜底） |
|---|---|---|
| 容器字节有效性 | ✅ 本 spike 亲证（MPF+ISO+副图+元数据） | ✅（上游量产验证） |
| 容器代码量 | **零**（CI 全包） | ~400+ 行 + 段级 golden 全套 |
| gain 语义控制 | CI 黑盒（线性光比率 + contentHeadroom；参数仅 RGB/亮度 + headroom） | 全自控（scale/offset/gamma/单多通道逐字段） |
| gain map 副图内嵌 `hdrgm` XMP（老 Android/Chrome） | ❌ 只有 ISO APP2 + Apple HDRToneMap（primary XMP 可经 rewrap 补 `hdrgm:Version`） | ✅ 三命名空间全写 |
| EXIF/元数据 | rewrap 走 `kCGImageDestinationMetadata`（XMP ✅ 实证；EXIF 键族待验证 = OQ-2） | 其 EncodeMeta 直带 EXIF+XMP+ICC |
| 质量旋钮 | ✅（E3 实证） | ✅ |
| 基面 ICC/输出空间 | ✅ colorSpace 参数（D1 嵌 sRGB ProfileName 可读） | ✅（自建 named profile） |
| 原子写 | CI 直写 URL——链上走 tmp + 晋升（L009 保持） | 内存 Data → 既有 atomic 写（更顺） |
| 维护面 | 依赖 CI 行为（黑盒；OS 升级漂移风险） | 自有代码（可控但自养） |
| 许可 | 零义务 | 成段移植须 NOTICE |

**推荐：原生 CI 全服务路为主臂**（charter 判据「原生路容器字节达标即收」——字节已亲证达标）；C 路不移植、**只在 OQ-M6-3-3 裁定「副图内嵌 hdrgm XMP 为硬需求」时激活**。达成即收纪律 = 裁决④同款。

---

## 3. 集成面测绘（ImageIOEncoders JPEG 腿 additive 缝）

### 3.1 现状链（M2-9 面正本）

`ExportVariant(drtOutput:record, format:.jpeg(q), colorSpace…)` → queue（`drtTails` per-image 载体 → `$jobDrtTail` TaskLocal）→ `ExportRenderer.renderStage`（`terminalTailPolicy` `.drt` + `tailFormatFloatOverride` float32 尾平面）→ exit 转换（`DrtOutputColorSpace.drtOutputColorSpace(space:eotf:)` = 输出 ICC）→ `ExportQuantizer` rgba8 → `JPEGEncoder`（`ImageIOEncodeCore.writeAtomically`：quality + `mountMetadata` EXIF/Software + DPI）→ atomic 晋升 → 后处理（`ExportICCStrip` / XMP 注入）。

### 3.2 gain map 档的 additive 缝（建议形，plan 细化）

1. **ExportVariant additive 字段**（KD-2 同款：decodeIfPresent + 默认值 + 合成 encode 旧档零漂移）：`public var gainMapHDR: Bool = false`（命名随 plan；语义 = 「该 JPEG variant 附带 HDR gain map 层」）。validate：`gainMapHDR && format != .jpeg` → typed 拒（六格式矩阵其余五格式 = typed 不可达说明，沿用 ExportICCStrip 文案形）；`gainMapHDR && drtOutput == nil` → typed 拒（HDR 面来源 = DRT record）；headroom 域门 = `drtOutput.peakLuminance` 既有 finite-positive 闸不触，新增 headroom = `peakLuminance / 203`（SDR 参考白）≥ 1.0 派生校验。
2. **双 rendition 渲染**：同一 job 两次 stage 消费——SDR 面 = 既有链（variant 的 DRT record 原样）；HDR 线性面 = **同一 DRT 尾在 EOTF-box 之前的线性级取平面**（display-referred linear float32；`DrtEotf.linear` 臂已存在——legalEOTFs linear 特例即此通道）。两平面同尺寸同 primaries，接 CI 契约（E4 教训：**绝不喂 PQ/HLG 编码码值**）。
3. **编码腿**：`JPEGEncoder.encode` 增 `gainMapHDR` 分支——不走 `writeAtomically`，改 `ExportGainMapEncoder`（新文件，`LightamerCore/Sources/Export/`）：plane→CIImage(RGBA8 + colorSpace)、HDR 面→CIImage(RGBAf/RGBAh + linearRec2020 + `imageBySettingContentHeadroom(peak/203)`) → `writeJPEGRepresentation` 到**导出 tmp 目录** → `CopyImageSource`+`kCGImageDestinationMetadata` rewrap（XMP：Container 目录 + `hdrgm:Version` + Software 签名，F5 实证形态）→ 原子晋升（L009）→ 既有后处理（ICC strip 可用性 = APP2 walker 不触 MPF/副图，需 plan 期核）。
4. **enqueue 面**：`enqueue(gainMapHDRs:)` 沿 `drtTails` 同款 per-image 载体 + M2 页 checkbox（仅 `drtOutput != nil` 且 JPEG variant 时可用）——UI 归 plan。
5. **读回兼容**：gain map JPEG 重导入走 M4-1 raster 链 `decodeRaster` → 解出 SDR 基面（gain 忽略）= 正确降级；未来 HDR-aware 重导入可走 `kCIImageAuxiliaryHDRGainMap`（spike D5 已证可读）。

### 3.3 六格式矩阵红线

`ExportFormatSpec` / `ImageIOEncoders` 既有五编码器 / `ExportEncoderRegistry.expectedLayout` / quantizer 阶梯**全部零改动**；新文件 `ExportGainMapEncoder` + `JPEGEncoder.encode` 内一个分支 + `ExportVariant` 一字段 + registry 一行 dispatch = additive 面（对齐 M2-9「encode core hunk-frozen、assembly 换缝」惯例）。

---

## 4. 版本与依赖边界

- 零新 SPM 依赖（CI/ImageIO 全原生）。
- macOS 27 底线内：`.hdrImage` 15+、`imageBySettingContentHeadroom` 26+、aux 读回 15+、CopyImageSource 元数据路 10.8+（metadata 键语义本批亲验）。无 `#available` 需求。
- sidecar/HistoryHash/presets：零触（export variant 不持久化，M2-9 既定）。

## 5. 键族/文案预登记（plan 期正式化）

- xcstrings 候选：`export_gainmap_label` / `export_gainmap_hint` / `export_gainmap_unavailable_*`（非 JPEG/DRT 缺席两态说明，ExportICCStrip 文案形）——尾块纯插入。
- UserDefaults：无新增（gain map 开关 = 会话内 recipe 面，随 M2-9 裁定）。

---

## 6. ALCE-03 冻结理由复核

| 冻结时的理由（V2-PROPOSAL §ALCE-03 / REQUIREMENTS） | 现状 |
|---|---|
| 「gain map 构造需 research（Apple Adaptive HDR API 面）」 | ✅ 本 spike 定型：destination 键族死、aux 手挂死、**CI `.hdrImage` 全服务路可行且容器亲证**——API 面未知性消除 |
| HDR rendition 依赖（DRT/EDR 链） | ✅ M2-6 DRT 尾（SDR/HDR 双 EOTF + 线性级）+ M2-9 `drtOutput` 强制联动 + peak 闸 + `DrtOutputColorSpace` HDR ICC 臂 + M4-1 HDR 导出先例（16-bit PQ TIFF）——双 rendition 取平面基建在位 |
| 与 ALCE-02（EXR）捆绑 research | ✅ 已解绑（M6 charter 单独立项；EXR 维持 V2 挂账不受影响） |

**结论：冻结理由全部化解，解冻成立。**

## 7. Open Questions（OQ-M6-3-*，每条带推荐）

- **OQ-M6-3-1（HDR 面取平面点）**：HDR 线性面取法 = ①同一 DRT 尾在 EOTF-box 前线性级取平面（**推荐**——单一 record 单源、两臂逐字节同链只差终级；linear 特例通道已在 legalEOTFs）vs ②独立 EDR 渲染链（第二真相源，弃）。
- **OQ-M6-3-2（EXIF on gain map 导出）**：CI 写路 + rewrap 面当前只实证 XMP；EXIF 选项 = ①metadata-namespace EXIF 标签经 rewrap（**推荐先 probe**，F5 同缝一次验证）②v1 接受 gain map 档无 EXIF round-trip（挂账文案，six-format 矩阵行为仅此 additive 档偏离）③自建 APP1 EXIF 注入器（XMPContainerInjector/ICCStrip 同款段级解析，~150 行，后补）。推荐 ①→② 降级路径，③ 不入首批。
- **OQ-M6-3-3（`hdrgm` XMP 跨生态兼容档位）**：CI 产物副图只有 ISO APP2 + Apple HDRToneMap（现代 Android 13+/Chrome 读 ISO；老 UltraHDR reader 读副图 hdrgm XMP——**CI 产物缺**）。选项 = ①接受（primary XMP 补 `hdrgm:Version` 即可，**推荐**——目标生态 Apple 全量 + 现代 Android/Chrome）②激活 C 路（LightCraft 容器移植，NOTICE 义务 + 400 行容器代码，仅当老 Android 为硬需求）。推荐 ① + Manual 走查留证。
- **OQ-M6-3-4（gain map 通道数）**：单通道亮度（**推荐**——CI 默认、Apple 生态标准 'L008'、文件更小；`hdrGainMapAsRGB` 不开）vs RGB（'444f'，读回侧 Data 键被 reader 扣留）。推荐单通道。
- **OQ-M6-3-5（M2 页 UI 位）**：gain map 开关落 SDR 导出节 checkbox（`drtOutput != nil` ∧ `.jpeg` 才可用，不可用态给 ExportICCStrip 文案形说明）（**推荐**）vs DRT readout 节联动。推荐前者（格式级旋钮归格式节）。
- **OQ-M6-3-6（命名/输出 tag）**：gain map 档不引入新 tag/formatName（仍 "jpeg"，与普通 JPEG 同池冲突递增）（**推荐**——容器本就是超集 JPEG）vs 加 "-hdr" tag。推荐前者。

## 8. 风险与边界

1. **跨生态目检缺口（中）**：Preview/Photos HDR 渲染、Android/Chrome 对读、与 LightCraft 参考产物互读——headless 不可达 → Manual-Only 走查批（gui-acceptance 配方：导出样张 × Preview 目检 × （如有）Android 设备/模拟器）。本 spike 已覆盖 sips + ImageIO/CI 双读回。
2. **CI 黑盒行为漂移（低-中）**：gain 计算/元数据格式由 CI 内部决定（本批亲验值已入档）；macOS 大版本升级可能微调——golden 钉「容器结构 + 读回字典」而非字节级全量（字节级钉不住第三方黑盒）。
3. **`kCGImageAuxiliaryDataInfoMetadata`/`ColorSpace` 键写入面未实证（低）**：读回两侧都带，但写入侧只经 CI；手动路已死无影响。
4. **ICC strip 与 MPF 共存（低）**：`ExportICCStrip.stripJPEGICC` 只删 APP2 ICC_PROFILE 段、原位压缩——MPF 偏移是文件内绝对偏移，删段会**使 MPF 副图偏移失效**。plan 须核：gain map 档 `embedICC=false` 不可达（typed 说明，副图 ICC 在 ColorSync 管理内本就不经此 strip）或 strip 后重写 MPF。**本条为 plan 期必须消解的实现雷**。
5. **CI 写路直出 URL（低）**：非 in-memory——链上写导出 tmp 目录再晋升，L009 语义保持。
6. **GPL 边界**：darktable/Alcedo/SpektraLab 零接触（本 phase 无参考需求）；LightCraft = MIT/Apache，仅 OQ-3-3② 激活时产生 NOTICE 义务，当前零代码移植。

## 9. Sources

- 本仓：`LightamerCore/Sources/Export/{ExportRecipe,ExportEncoder,ImageIOEncoders,ExportQueue,DrtOutputColorSpace,ExportChainBuilder}.swift`（M2-9 面亲读）；AGENTS.md「M2-9 架构增量」「M4-1 架构增量」节
- charter/前瞻：`.work/gsd/ROADMAP.md` §M6 M6-3 行；`.work/gsd/REQUIREMENTS.md` ALCE-03 行（663）；`.work/gsd/phases/v2-station/V2-PROPOSAL.md`（97/146）；`.work/gsd/phases/m6-1-interop/RESEARCH-NOTES.md` §5（底稿）
- LightCraft 本地仓（只读）：`/Volumes/UNITEK/Documents/Development/lightcraft` `crates/codecs/src/gainmap.rs`（834 行亲读）+ `crates/engine/src/export.rs:1374-1395,1628-1678`；`research/LIGHTCRAFT-NOTES.md` §二.5/§三/§四
- Apple SDK headers（macOS 27 SDK，本批亲读）：ImageIO `CGImageDestination.h:250-260,380-423`、`CGImageProperties.h:2336-2400,2437-2439`、`CGImageSource.h:559-577`；CoreImage `CIContext.h:730-772,850-870`、`CIImage.h:278-290,598-611,684-686`
- JuniperPhoton（PhotonCam 作者，RGB gain map pitfalls）：aux dict 四键（Data/DataDescription/Metadata/**ColorSpace**）与读侧 '420f' 拒收行为——https://juniperphoton.substack.com/p/pitfalls-and-workarounds-when-dealing
- spike 产物（即弃于 /tmp/m63probe/，不入仓）：probe main/round2-round6 源 + 全部输出 jpg/heic + probe*.log

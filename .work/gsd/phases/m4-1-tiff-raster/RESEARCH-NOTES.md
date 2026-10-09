# M4-1 RESEARCH-NOTES — TIFF 栅格开发链（RASTER-IN-01 收窄版）

> Phase M4-1 research 环产物（2026-10-10）。讨论/裁决正本 = 同目录 `M4-1-CONTEXT.md`（OQ 带
> 推荐，C 档第 1 停的用户过目点）；本文件是技术正本。charter 正本 = ROADMAP §Milestone 4
> M4-1 行；需求正本 = REQUIREMENTS RASTER-IN-01（收窄注记）+ ALCE-02（推迟注记）。
> 上游参考 = `/Volumes/UNITEK/Documents/Development/AlcedoStudio/docs/roadmap/alcedo_studio/
> edit/raster_image_input_plan.md`（GPL 项目文档——只读参考设计语义，零复制入库）。

## 0. 范围（charter 摘录 + 边界）

- **入**：TIFF 导入即开发——ImageIO 原生解码（8/16/32-bit float）+ 内嵌 ICC 解析
  （源 color description）→ display-referred 输入经 DRT 逆链（ACES 2.0 逆变换路径）进编辑
  管线；HDR TIFF（HDR 旗标 → EDR 面）；导入面文件类型选择器对齐上游 #264 形态（收窄版 =
  RAW + TIFF 两类）。
- **不出**：JPEG/PNG 维持图库可浏览现状**不进开发链**（零回退红线）；EXR 连同 ALCE-02 推迟
  （依赖对比存档 = V2-PROPOSAL OQ-V2-5）；导出矩阵零改动红线（六格式不动）；OpenDRT 逆链
  不做（上游同样只做 ACES 2.0 inverse——Alcedo plan §1 Non-goals「An inverse for OpenDRT」）。
- **defer 候选**（plan 阶段可再裁）：Input profile 手动覆盖（Alcedo D5 `input.profile_override`
  + sidecar 记录）——首波建议只做 Auto（文件即真相）+ 面板只读 readout，覆盖面挂账。

## 1. Alcedo 上游对表（`raster_image_input_plan.md`，R1–R5 全完成 + macOS 验证记录）

### 1.1 上游架构一句话

`RasterInputLoader`（按内容魔数分类，TIFF 魔数无相机数据 = raster）→ `RasterColorDescription`
（ICC/PNG chunk/EXR attribute 解析 + usable 三检查 + sRGB 默认带 `default_reason_`）→
`LinearizeRaster`（TRC 解码，upload 步内跑）→ `DisplayToAp1`（display-referred = OCIO 2.5.1
ACES 2.0 inverse 闭式逐像素；scene-linear = 3×3 矩阵；同一 pass 双分支）→ 写 ACEScc AP1 进
`develop_output`（缓存，Color Grade 滑动不重跑）→ 既有 Color Grade/DRT 链原样消费。持久化 =
描述存 Develop 节点 `input` 对象（root 文档内，`profile_override` 唯一可编辑字段）。

### 1.2 上游裁决表（§12，逐条与我方对齐状态）

| 上游 | 语义 | 我方 M4-1 对应 |
|---|---|---|
| D1 | inverse 遵循 OCIO 2.5.1（Academy 参考），非自家 forward 反跑；经自家 forward 回看**不必**精确 | **改造**：我方 forward 本就是 aces-core v2.0 参考移植（M2-6-2），逆变换直接移植 aces-core `outputTransform_inv` 同族（见 §3.3/OQ-3）——round-trip 对自家 forward 可要求更紧 |
| D2 | raster 默认文档 = 中性 Color Grade + DRT=ACES 2.0（limiting/peak/EOTF 随源）+ 新增 `DrtEotf::SrgbPiecewise` | **待裁 OQ-1**（我方 pristine 语义 = 无 DRT 尾，与 Alcedo「DRT 恒在」是显式偏离，需用户裁决） |
| D3 | EXR 与 float-TIFF（linear ICC 或无 ICC）= scene-linear，只过矩阵 | **采纳**（TIFF 收窄版 = float32 无 ICC / linear ICC → 矩阵分支） |
| D4 | LUT-based RGB ICC 由 lcms2 host 侧转换；CMYK 导入即拒 | **等价改造**：我方零第三方——LUT profile 走 ColorSync/CI 腿转换（§3.2.4）；CMYK typed 拒绝 |
| D5 | Input profile 手动覆盖入 history | **defer 候选**（§0） |
| D6 | Alpha 丢弃 | **采纳**（ premultiplied 不还原，按存储色渲染） |
| D7 | 文件夹导入类型选择记忆在 QSettings | **采纳**（UserDefaults 新键，见 §3.6/OQ-5） |
| — | 兼容：无 DDL、无版本 bump、既有数据逐字节 | **同纪律**（我方 sidecar/`.lalb` 零漂移惯例延续，见 §3.7） |

### 1.3 上游 Metal 验证教训（macOS verification record，2026-10-05——对我方 Metal 移植直接可用）

1. **FMA contraction 陷阱**：Apple clang 把 `a*b+c` 熔合成 FMA，舍入差异使 ACES 2.0 inverse
   表在近黑区漂出容差（host 与 Metal 同表同源仍漂）——上游修法 = `#pragma clang fp
   contract(off)`。**我方对策**：inverse 的 Float64 authority 与 Metal kernel golden 门（§4.3）
   若近黑失配，第一嫌疑即 FMA；Swift 侧 Float64 reference 本身也可能被 swiftc 熔合（同
   pragma 需求）。
2. **ACEScc 近黑陡峭**：1e-3 ACEScc 差 = 1e-7 线性光差——上游容差改「线性光 1e-6 内亦收」。
   我方比较纪律已有先例（L048：比较一律 decode 回 linear + f32 产线常数升维），inverse
   golden 的比较域按此设计。
3. **逐位暗像素容差分档**：HLG 暗区单像素 1e-3 差异按域分档收，不做整体放宽。
4. 资源完整性：`display_to_ap1.metallib` 曾漏出 bundle（FEATURE-MAP 增补节教训）——我方
   `.metal` 随 target 源内编译无此患，但新增 metal 文件须过 `tuist generate` 尾闸（L041）。

### 1.4 上游逆变换性能/结构事实（§5.4）

- 闭式、无循环无迭代：两次 CAM16 转换 + 一次 hue 表界内搜索 + ≤2 次 gamut-compress 估值 +
  闭式逆 tonescale + 两个 rational toe。forward DRT 同量级（实测 3840×2160 上 5.2ms vs
  forward 5.8ms，比值 0.90 ≤ 1.25 目标）。
- **宿主表**：reach M / hue / cusp / upper-hull gamma 打包单块（上游 1902 floats）单 buffer，
  per-key 上传一次；表构建新 key ≤20ms（实测 4.6ms）。我方 M2-6 forward 已有同款表族
  （TABLE_reach_M/hues/gamut_cusps/upper_hull_gamma + hue_linearity_search_range，
  `Aces2Reference.swift` 结构图 Pre-run 段）——**inverse 需要的表与 forward 表族大量同源**，
  增量主要是逆方向的查找/闭式解组织。
- **3D LUT 方案被上游否决**（§5.4）：逆变换在 gamut 边界最陡，恰是 LUT 插值误差最大处；
  16-bit/PQ 输入需更细网格；输出反正有缓存，逐像素闭式成本不在滑杆路径。
- **精度标定（上游 R2）**：cusp J/M 对 OCIO ~1e-6；upper-hull gamma 阈值搜索本性 ~2.7e-4；
  逆 tonescale 近顶病态 → 99.9% 通道 + 逐点 OCIO-forward 回验的双判据。我方 golden 门
  （§4.3）引用同思路但锚换 aces-core 参考值。

## 2. 我方底座盘点（现状事实，file:line 为 2026-10-10 HEAD）

### 2.1 解码面

- `LightamerCore/Sources/Decode/RAWDecoder.swift`：统一入口 `decode(_:)`（D-24）——RAW UTI
  → `decodeRAW`（CIRAW）；非 RAW → `decodeRaster`（`CGImageSourceCreateImageAtIndex` 单路，
  多页 TIFF 取第 0 页 :299-334）。**TIFF 今天已在 decodeRaster 通路里**（JPEG/HEIC/PNG/
  WebP/TIFF/PSD-flat）。
- **RAW-03 float 判定（02-06 宿主实证，:302-315）**：32F TIFF 经该路 bpp=32 保真直达
  float32 管线输入平面，极值 0.0/2.0/65504.0 位近精确幸存；`CIImage(contentsOf:)` fallback
  未采纳。**含义：TIFF 的位深保真已被钉死可用，M4-1 不必重证**。
- `DecodedImage`（Decode/DecodedImage.swift）：`ciImage` + `rawTech` + `capture` +
  `decoderVersionUsed`（raster 恒 `.v8`）+ `contentDedupeID`（path⊕size⊕mtime，GUI-22）。

### 2.2 输入平面与色彩语义（现状缺口的定位）

- `CIContextPool.init`（Metal/CIContextPool.swift:144-149）：CIContext 以
  `.workingColorSpace = WorkingSpace.colorSpace`（**linear Rec2020**，Foundation/
  WorkingSpace.swift:22）创建。`CIImage(cgImage:)` 携带 CGImage 的 ICC 色彩空间 → 渲染时
  **CI/ColorSync 自动做 primaries+TRC → linear Rec2020 的转换**。
- **缺口本体**：今天打开 JPEG/TIFF，输入平面 = display-referred 数值（已线性化+色域映射进
  Rec2020），管线的后续（exposure/temperature 等按 scene-referred 语义设计）把它当
  scene-linear 消费，尾段 gamma 直出屏幕——「栅格 = display-referred 输入经 DRT 逆链」的
  语义从未形式化（FEATURE-MAP 增补节原话）。这就是 M4-1 要补的正式链。

### 2.3 DRT 尾段（逆链的对应物）

- `Graph/DrtRecord.swift`：method ∈ {`aces_2_0`, `open_drt`}；默认 record = opendrt/rec709/
  gamma22/peak100（:370-381）。M2-6 尾段 sub-run：`[DrtMethodBox 74 → Post 四件 → EotfBox 75
  → borders 76 → watermark 77]`；pristine 档 = `.sdrGamma` 直通（无 DRT 段）。
- `Pipe/Drt/Aces2Reference.swift`：**forward 是 aces-core v2.0（069b0bc3，Apache-2.0）移植**，
  Float64 authority + 结构图 [0]Rec2020→AP0 → [1]RGC（KD-3 默认 ON，ACES 1.3 LMT）→
  [2]clamp AP0→AP1 → [3]RGB→JMh(AP0) → [4]tonemap+chroma compress → [5]gamut compress →
  [6]JMh→RGB(limiting) → [7]×(100/peak)（**EotfBox 契约：1.0 = peak nits**）。文件头明注
  **`outputTransform_inv` 未移植（forward-only render path）——M4-1 的移植对象就在上游同一
  CTL 库内**。`Aces2Kernels.metal` 是 Float64 authority 的逐 stage 镜像（588 float4 单
  buffer uniform，零 function constants）。
- `Pipe/Drt/DrtEotf.swift`：7 值 {linear, st2084, hlg, gamma26, bt1886, gamma22, gamma18}
  ——**无 sRGB 分段曲线**（上游为此新增 `DrtEotf::SrgbPiecewise`；我方对应缺口，OQ-1 联动）。
- 视口 EDR（M2-6 已交付）：DRT-SDR（bgra8+calibrated）/ DRT-HDR（16F + EDR content +
  PQ/HLG colorspace）双臂 + `followGateActive`（`!edrActive && !drtTailActive`）——**HDR TIFF
  的 EDR 面主体是复用，不是新建**（§3.5）。

### 2.4 传递曲线资产（linearize 工具箱）

- `LightamerIOP/Sources/Lut3d/LutEncodingCatalog.swift` + `LutTransferMath.swift`
  （M2GRADE-08 交付）：display 6 行 = rec709_bt1886 / **rec709_srgb（分段）** / rec709_gamma22 /
  displayp3_srgb / rec2100_pq1000 / rec2100_hlg1000，**Float64 正逆族双落笔**（golden =
  各标准公开参考值）。
- **模块边界注意**：`LightamerIOP` 依赖 Core（IOPModule 协议在 Core/Pipe），**Core 不可反向
  import IOP**——TIFF 输入腿若在 Core/Decode 层组装，TRC 求值不能直接调 `LutTransferMath`。
  三条出路：(a) 曲线族下沉 Core（搬家成本 + IOP 反向兼容面）；(b) kernel 内自持公式
  （sRGB 分段/gamma/PQ/HLG 均为公开标准闭式，MSL 直写 + golden 对表——**推荐**，同
  `Aces2Kernels` 常数纪律注记）；(c) App 层烘焙 1D LUT 纹理喂 kernel（最简但多一次上传与
  插值地板）。plan 阶段定，倾向 (b)。

### 2.5 导出对称面（round-trip 的另一半）

- `Export/ImageIOEncoders.swift` TIFFEncoder（:231-273）：8/16/**float32**（`ExportRecipe`
  `TIFFBitDepth: eight/sixteen/float32`，float 保持 linear——RESEARCH §3.3 D-11 判定）×
  压缩 {none/lzw/zip}（JPEG-in-TIFF 有意缺席）；ICC 经 `DrtOutputColorSpace`（space×eotf
  穷举解析器，SDR 幂臂自建 ICC v4 字节）；`ExportICCStrip` 剥 ICC = TIFF tag 34675 原位压缩。
- **round-trip 自证资产现成**：导出链产出的「位深 × ICC」组合就是重导入 golden 的权威
  fixture 源（上游 §10 同构：Alcedo 导出必须以相同 primaries/TRC 重导入）。

### 2.6 导入面（类型选择器的落点）

- `Library/ImportFilter.swift`：RAW-only 门（隐藏 → sidecar 表 → 扩展名白名单三序判定）；
  `LibrarySchema.defaultRawExtensions` = 14 扩展（**无 tif/tiff**）+ 用户可配白名单
  （UserDefaults `library.import.rawExtensions`，ImportDefaults 全量替换语义 + reset）。
- 导入三模式（M2LIB-07）：`ImportService` move/copy/link 三运输 + `.lra` 随行 + 校验回滚。
- UI 落点：`App/Sources/Lightamer/Library/ImportModeDialog.swift`（三模式 Picker）+
  ImportProgressView（typed 进度/拒绝计数面——上游把 `unsupported_` 拆 `excluded_type_` 两
  计数，我方对应拆法见 §3.6）。
- 图库缩略图（`App/.../Library/LibraryThumbnailBridge.swift`）：Tier A（未编辑）= ImageIO
  内嵌预览；Tier B（已编辑）= 注入式 render leg（pipe THUMBNAIL 分辨率）。**TIFF 无内嵌
  预览属常态 → Tier A 对 TIFF 走 ImageIO 缩略解码；Tier B 走 pipe → TIFF 开发输入腿必须
  bucket-uniform（full/preview/thumbnail 同一盒子族）**。

### 2.7 编辑面联动

- RAW Decode 页签（M2-3-3 `RawDecodePanelView`）：WB/降噪/demosaic 控件——对 raster 文档
  应隐藏（上游 §6.6 同款）；输入色 readout 行（"Display P3 — embedded ICC" 形态）是 M4-1
  新增 UI。
- default look mint（M2-5-2 KD-5 `defaultLookPending`）：RAW 默认观感铸造——**raster 文档
  应跳过 mint**（上游 D2：中性 Color Grade，RAW default look 不套）。
- v50 链序：温度 iop（3.0）等对 raster 保持 identity/缺席即可（pristine seed = terminal
  trio + 空调整栈的现状面零改动）。

## 3. 设计方案（推荐形，逐条挂 OQ）

### 3.1 管线分支：新 TIFF 开发分支（OQ-2 推荐 A 的论证）

**为什么不能复用 CI 通路再补逆变换**：CIContext working-color-space 渲染已把源 primaries
映射进 Rec2020（矩阵变换先于逆 ODT 发生）。逆 ACES 2.0 的 limiting gamut **必须是源原生
primaries**（上游 §5.2；sRGB 源按 Rec2020 limiting 求逆 = 把文件当 Rec2020 显示器产物解释，
gamut/色调语义错位——矩阵与非线性 ODT 不可交换，数值上不可逆回收源域表示）。故 TIFF 开发
链需要**解码后保源原生 primaries 的数值表示**，即绕开 CI 的色彩管理渲染、自己上传原始像素。

**推荐形（Alcedo 同构、我方域适配）**：

```
CGImageSource(TIFF)
  ├─ 描述解析（§3.2，只读 header，一次）
  ├─ 像素解码：CGImageSourceCreateImageAtIndex（RAW-03 已证位深保真）
  │    → 原始字节取出【不做色彩管理转换】→ MTLTexture 上传（u8/u16/float32 三档；
  │      灰度→RGB 复制；alpha 丢弃；CMYK typed 拒绝）
  └─ Metal 输入腿（新 kernel，bucket-uniform）：
       LinearizeRaster（TRC 解码 → 源 primaries 域 display-linear；
         scene-linear 输入直通）
       → DisplayToWorking（display-referred = ACES 2.0 inverse [limiting=源 primaries,
         peak=源 peak] → AP0 scene-linear → AP0→linear Rec2020 定矩阵 → 管线 working 平面；
         scene-linear = 矩阵分支 [源白 CAT02 → Rec2020 白] + clamp）
       → 产物缓存（develop-output 级：key = 描述指纹 ⊕ 几何；Color Grade/DRT 滑动不重跑）
```

- 缓存缝：`PipeCache` 位置 0 现按 `decodeParamsHash` 键控——TIFF 腿的「decode 参数」=
  解析出的描述（源文件字节函数）+ `contentDedupeID` 已含文件身份；**hash 折叠面沿用 L013
  字段显式纪律**，描述进 `decodeParamsHash` 类似物（新显式字段，非 JSON 序）。
- 现有 `decodeRaster` CI 通路：**JPEG/PNG/HEIC/WebP 保留原样**（图库可浏览现状零回退红线）；
  TIFF 从该通路**分流**到新腿（`decode()` 的 UTI 分支加 TIFF 臂）。旧 TIFF CI 路径代码保留
  不删（同 dt 禁用纪律；未来若做「快速浏览模式」可复活）。

### 3.2 RasterColorDescription（Core 新型）

```swift
// Sources/Decode/RasterColorDescription.swift（命名对齐上游语义；我方 Swift 拼写）
enum RasterReferral { case displayReferred, sceneLinear }
enum RasterTransferKind { case linear, srgbPiecewise, gamma(Double),
                           iccParametric(type: UInt8, params: [Double]),
                           iccSampled([Float]), st2084, hlg, bt1886 }
enum RasterColorOrigin { case iccMatrixShaper, iccLutConverted, iccCicp, tiffNoIccFloatLinear,
                          defaultSrgb }   // TIFF 收窄版不需要 PNG chunk/EXR/EXIF 族
struct RasterColorDescription {
    var referral: RasterReferral
    var primariesXY: SIMD8<Float>      // Rx Ry Gx Gy Bx By Wx Wy（native white）
    var transfer: RasterTransfer
    var peakLuminanceNits: Float       // SDR=100 / PQ=mDCv,MaxCLL,1000 阶梯 clamp[100,10000] / HLG=1000
    var origin: RasterColorOrigin
    var profileDescription: String?    // ICC 'desc'，UI readout 用
    var defaultReason: String?         // 落默认时记录为何（walkthrough 观察面）
}
```

- **解析序（TIFF）**：① 内嵌 ICC（tag 34675，ImageIO 侧 = `CGImageGetColorSpace` /
  `CGColorSpaceCopyICCData`）→ matrix-shaper（rXYZ/gXYZ/bXYZ 反 chad 回 native 白；
  TRC 参数化或采样化）或 v4.4 `cicp` tag（覆盖 TRC/primaries）或 LUT-based（§3.2.4）；
  ② 无 ICC 且 float → **scene-linear Rec.2020 默认**（上游 D3；〔omp-minor-1 勘误
  2026-10-10：本行原写 Rec.709，实际落地 = rec2020 primaries——无 ICC 色域未知时
  limiting 取最大包络更保守，行为面自洽，字面订正〕）；③ 其余无 ICC → sRGB 默认
  （上游产品 owner 钦定的唯一默认，我方建议沿用）。
- **usable 三检查**（上游 §4.2）：primaries 非退化三角 / 白点在三角内 / 曲线单调——败者记
  `defaultReason` 顺位下落，不是错误。
- **HDR 判定线索**：ICC 曲线 2e-4 内贴近 ST 2084 / 1000-nit HLG → canonicalize 为
  `st2084`/`hlg`（上游 R1 教训：其自家 PQ 导出 profile 存 4096 点表，不 canonicalize 就会
  以「SDR 采样曲线 + 100 nit」错读回来）；命名色彩空间比对（`CGColorSpace(name:
  .iTUR_2100_PQ)` 等）为快速路径。
- **API 面候选**（plan 阶段实测定型）：`CGImageSourceCopyPropertiesAtIndex`
  （`kCGImagePropertyProfileName` / 像素尺寸 / DPI / orientation）、
  `CGColorSpaceCopyICCData` + 自解析 ICC 头（tag 表，零第三方——matrix-shaper/cicp/LUT 判别
  所需字段都 ICC 规范公开）、`CGColorSpaceGetPrimaries/WhitePoint`（calibrated 快路径）。
  **不引第三方 ICC 库**（依赖最小化红线；lcms2 上游形态不复刻）。

### 3.2.4 LUT-based ICC（零第三方等价形）

上游用 lcms2 在 host 把像素转 linear Rec2020（`IccLutConverted` origin）。我方等价物 =
**ColorSync/CI 腿**：该文件保持 `CIImage(cgImage:)` 全色彩管理渲染（现有
`renderToTexture`）得 linear Rec2020 display-linear 平面，描述记
`{rec2020 primaries, linear transfer, displayReferred, origin=iccLutConverted}` → 逆腿只跑
**矩阵分支语义的逆**（见 3.3 分支二）。profile hash（SHA-256）入描述防「描述与文件失配」
（上游 §4.3 同款）。即：LUT profile 是**唯一**走 CI 腿的 TIFF 输入形态，其余走原生字节腿。

### 3.3 逆变换：aces-core `outputTransform_inv` 移植（OQ-3 推荐 A）

- **对象**：aces-core v2.0 `lib/Lib.Academy.OutputTransform.ctl` 的 `outputTransform_inv`
  （M2-6-2 文件头明注未移植，正是为本次预留）；同族 `Lib.Academy.Tonescale.ctl` 已有
  `tonescale_fwd/inv` 双落笔（:77-97 移植注记）。
- **与我方 forward 的对偶**：上游 [0]..[7] 逐段反走——[7']×(peak/100)（EotfBox 契约对齐）、
  [6']RGB→JMh(limiting=源)、[5']逆 gamut compress（≤2 次估值闭式）、[4']逆 chroma compress +
  逆 tonescale（闭式）、[3']JMh→RGB(AP0)、[0']AP0→**linear Rec2020**（我方 working space，
  非 ACEScc AP1——与上游最大的结构分叉，尾矩阵 = AP0→Rec2020 常数矩阵，Float64 求好进
  uniform）。
- **RGC 问题（诚实偏差登记）**：我方 forward 默认带 RGC 前置（KD-3 ON，stage [1]）。逆腿
  **不做 RGC 逆**（同上游：OCIO inverse 不含 RGC 逆；其接受面 = 经自家 forward 回看非精确，
  偏差在阴影/饱和暗部）。我方等价接受面：raster 文档若默认 DRT=aces20+RGC，则回看 =
  RGC 再压缩一次。**消解选项**：(a) 沿用接受面（上游先例，零新工作）；(b) raster 默认
  record 关 RGC；(c) 移植 RGC 逆（ACES 1.3 RGC 文档给出正向；社区有近似逆，规范级逆不存在
  ——不推荐）。倾向 (a)+(b) 组合，OQ-1 一并裁。
- **scene-linear 分支**（float 无 ICC / linear ICC）：矩阵 only（源 primaries+白 CAT02 →
  Rec2020 白）+ 超 AP1 值 clamp（上游 §5.5 同理由：EXR/float 可存 AP1 外值；我方 working
  space 本身就是 Rec2020，`clamp [0, 8·r_hit]` 类上限是否引入 = 对齐 forward 输入域，plan
  实测定）。
- **失败形态**：peak ≤0 / 奇异矩阵 / device 错误 → typed `AppError`（上游 R2 失败链同构）。

### 3.4 Kernel 与缓存

- 新文件建议：`LightamerCore/Sources/Pipe/Input/RasterInputKernels.metal`（linearize +
  display-to-working 可一 pass 融合——上游把 linearize 放 upload 步、DisplayToAp1 独立 pass
  是因为其「缩略图线性域 GPU 降采样」需要中间面；我方 preview 链已有 longEdge 缩面机制，
  融合与否 plan 阶段按内存峰值定）。零新 PSO 形态沿用 `Aces2Uniforms` 平面式单 buffer。
- 表族：逆方向需要的 reach/hue/cusp/upper-hull 表与 forward 表族同源——**Float64 authority
  新建 `Aces2InverseReference.swift`（Pipe/Drt/，同目录同范式），kernel 逐段镜像**；表打包
  布局 = 逆腿自己的 ABI（不与 forward buffer 复用，防签名耦合）。
- 缓存：develop-output 级缓存位（ PipeCache 新位置或输入平面 memo 扩展），key =
  fnv(描述指纹 ⊕ 几何 ⊕ 分支 tag)；滑动 Color Grade/DRT/post 不重跑（上游 §5.4 缓存语义）。

### 3.5 HDR TIFF → EDR 面

- **旗标判定**（推荐）：`referral/transfer ∈ {st2084, hlg}` 或（scene-linear 且 float32 且
  内容探针 max > 1.0）。旗标消费两处：① 面板/检查器 readout；② 默认视口臂。
- **视口**：复用 M2-6 DRT-HDR 臂（16F + EDR content + PQ/HLG colorspace）——HDR TIFF 的
  DRT record（编辑或默认，OQ-1）encoding=st2084 时视口自动进 EDR；非 DRT 手动 EDR 开关
  与 DRT 尾互斥的既有纪律不动。**新建面趋近于零，主要是「HDR TIFF 打开时默认 record 怎么
  给」的语义**（OQ-1/OQ-4 联动）。
- peak 语义贯通：源 peak（描述）→ 默认 record `peakLuminance` → EotfBox → 视口 headroom。
  `ExportVariant.validate` peak 闸门既有（nil 不触发）不受扰。

### 3.6 导入类型选择器（#264 收窄形）

- **类别面**：`ImportCategory { raw, tiff }` 两类（上游 `ImportFileCategory` 五类的收窄）；
  扫描分类按扩展名（case-insensitive：`.tif/.tiff`），**内容复核**维持 ImportFilter 既有
  三序（sidecar 表/隐藏判定不动，白名单判定改为类别掩码驱动）。
- **UI**：ImportModeDialog（或其后的确认流）加「文件类型」行——每类 checkbox + 计数；
  其他类型计数展示不可勾（上游 §9.3 形态）；导入键 = 扫描完成 && 允许数 > 0。
- **记忆**：UserDefaults 新键（建议 `library.import.categories`，值 = 类别掩码/JSON；默认
  raw+tiff 双开）；**不动** `library.import.rawExtensions`（RAW 细粒度白名单保持独立正本，
  tiff 不混入 RAW 表——两键语义正交，OQ-5）。
- **进度计数**：`ImportRejection.Reason` 增 `excludedType`（类别未勾）与既有
  `extensionNotWhitelisted` 的分账——上游 excluded_type/unsupported 两计数的对应物。
- **三模式适配**（OQ-7）：move/copy/link 对 TIFF 零特例（纯字节运输 + `.lra` 随行纪律
  照旧）；link 模式下外部替换源文件 → 描述 decode-time 重解析天然跟随（contentDedupeID
  的 mtime 腿保证缓存翻新）——登记为 by-design 语义即可。

### 3.7 持久化与零漂移纪律

- **推荐**：描述**不持久化**（文件即真相，decode-time 解析每次开图重算——header 级读取，
  毫秒级；与 sidecar「编辑态真相」分工一致）。既有 sidecar（`.lra`）与 `.lalb` **零
  schema 变更**（上游 §7.1「无 DDL 无 bump」纪律同构；`images` 表 file_ext 已有，类别
  判定查询侧 derive）。
- 若 OQ 裁决要 `profile_override`（defer 候选）：sidecar v10 additive document-level record
  （DrtRecord/FilmRecord 先例形：缺键 = Auto，默认不入 map 不写 sidecar，hash 隔离专测）。
- 首波不做覆盖面 ⇒ **零持久化面、零迁移**是本设计的默认闭合态。

## 4. Golden 策略（SC 验收形态对表：round-trip ✓ + ICC 语义 golden ✓ + HDR TIFF EDR ✓）

### 4.1 fixture 矩阵（`Tests/Fixtures` 产品资产在盘纪律；生成器脚本入仓）

| 维度 | 组合 |
|---|---|
| 位深 | 8-bit / 16-bit / 32-bit float |
| ICC | sRGB matrix / Display P3 matrix / AdobeRGB matrix / Rec2020 matrix / ProPhoto matrix（AP1 外 limiting 分支）/ LUT-based RGB（CI 腿）/ **无 ICC** / PQ-tagged（cicp 或表式 PQ ICC）/ HLG-tagged |
| 特形 | 多页 TIFF（取第 0 页）/ 灰度 ICC（灰→RGB 复制）/ alpha（丢弃）/ CMYK（typed 拒绝）/ 退化 primaries ICC（usable 检查 → 默认 + reason）/ 无 ICC float32（scene-linear 判定）/ L057 教训：全部走 `PanelPresentation` 之外的纯 Core 测试面，不依赖 GUI |
| 自证源 | 我方导出链产出：TIFFEncoder 8/16/32F × DrtOutputColorSpace 各 profile → 重导入描述逐字段一致（上游 `ExportedIccProfilesReimportWithSamePrimariesAndTransfer` 同构） |

生成器：Python + Pillow/tifffile（uv run）离线生成入库（SPEKTRALAB 五件套先例：资产
物理隔离 + 来源注记）；fixtures 属产品资产**在主仓**（pack 政策 B 剥的是 evidence 大对象，
Tests/Fixtures 在盘纪律不受影响——GOAL-STATE 分仓续接点验证五项明载 fixtures 在盘）。

### 4.2 ICC 语义 golden（SC#2）

- 描述解析逐 fixture 断言（referral/primaries/transfer/peak/origin/defaultReason 逐字段）。
- 传递曲线 golden：linearize 输出对 `LutTransferMath` 逆族公开参考值（或标准文档值）双锚
  （Core 内 kernel 公式自持形态下，用 host Float64 小函数对表）。
- usable 检查负测 + 默认回落 reason 断言。

### 4.3 逆变换 golden（M2-6-2 范式延续）

1. **Float64 authority ↔ Metal kernel**：33³ display RGB 网格 × limiting 集 {Rec709/P3/
   AdobeRGB/Rec2020@100nit + Rec2020@1000nit}，kernel vs `Aces2InverseReference` ≤1e-5 级
   band（p99.9 + 近黑线性光双判据，§1.3-2/3 教训入门）；近黑失配先查 FMA（编译旗标/pragma）。
2. **锚点**：display 黑 → 0；源白 → AP0 中性（max/min−1 < 1e-4，0.05%..90% 峰值带）。
3. **round-trip**：display → inverse → **我方 forward（Aces2Reference）** → display：
   误差带 = 同源一致性优势点（上游做不到的紧度），目标带 plan 实测定（先给 1e-3 级假设，
   RGC 叠加面单独记）。
4. **交叉验证资产（可选）**：OCIO ACES 2.0 reference 的公开参考值转录测试（REQUIREMENTS
   注记先例：上游 8f8e712 变换 = parity 测试资产机会）——OCIO 不入库，只转录数值。

### 4.4 round-trip SC#1 与回归门

- SC#1 = 「TIFF 开发链 round-trip」：导出（位深×ICC 矩阵抽样）→ 重导入 → 描述一致 +
  inverse→forward 像素带 + 编辑参数重放稳定。
- 回归门：IOP/IOPParity 逐位基线零漂移（forward `Aces2Kernels.metal` 零 diff 红线——逆腿
  新文件，不触 forward）；`--bundle` 定向轮 + 收口全套 `--all`（orchestrator 批准 + MEMFAIL
  机检口径不变）。新增测试归 bundle 按 BUNDLE-MAP 域模式（Decode/描述类 = Core 级 → 现行
  bundle 归属 plan 申报时对表）。
- HDR TIFF EDR（SC#3）：PQ fixture 打开 → DRT-HDR 视口臂激活（colorspace/16F 断言）+
  peak 贯通断言；手动 EDR 互斥回归零扰动。

## 5. 风险登记

| 风险 | 处置 |
|---|---|
| FMA contraction 漂移（§1.3-1） | Float64 authority 与 kernel 双侧编译纪律 + 近黑双判据门；命中即 pragma/旗标 |
| 大图内存峰值（100MP float32 TIFF ≈400MB/平面，上传+工作面双份） | u8/u16 原生深度上传到 linearize 为止（上游 §10 同策）；运行门 8G + MEMFAIL 机检兜底；贴线 bundle 先查重测漂移（AGENTS 测试宿主口径） |
| 8-bit 源量化地板被 inverse 放大（阴影 banding） | 观察项登记；不做去带（超范围）；文档注记 |
| LUT-based ICC 的 CI 腿与原生腿双路径分叉 | 唯一分叉点收在描述 origin（`iccLutConverted`）；测试矩阵覆盖两腿 |
| 描述与文件失配（link 模式外部替换） | decode-time 重解析 = 文件真相；缓存 mtime 翻新；登记 by-design |
| srgbPiecewise 进 `DrtEotf` 破穷举 switch | 设计内扩展路径（M2DRT-06 注册口语义），编译器兜底；封存面清单（M3-3）的解封注记随 plan 申报 |
| Core↔IOP 边界（TRC 求值不可反向 import） | kernel 自持公式 + host 对表小函数（§2.4 倾向 b） |
| 中间产物渲染回归（thumbnail Tier B 走新腿） | bucket-uniform 盒子族 + THUMBNAIL 分辨率 golden 抽样 |

## 6. Wave 草案（plan 阶段细化）

- **W1**：`RasterColorDescription` 型 + TIFF 解析序 + usable 检查 + fixture 矩阵 + ICC 语义
  golden（§4.2）——纯 Core，零管线触。
- **W2**：`Aces2InverseReference` Float64 移植 + 锚点/round-trip golden（§4.3-1..3）——纯
  Swift，零 GPU。
- **W3**：原生解码腿（u8/u16/32F 上传）+ `RasterInputKernels`（linearize +
  display-to-working）+ 缓存缝 + bucket-uniform 接线 + scene-linear 矩阵分支。
- **W4**：HDR 旗标 + 默认 record/视口 EDR 语义（随 OQ-1/OQ-4 裁决形）+ srgbPiecewise（若
  OQ-1 采 A）。
- **W5**：导入面（类别掩码 + 选择器 UI + 计数分账 + UserDefaults 键）+ 面板 readout/RAW
  Decode 页签门控 + defaultLook mint 跳过。
- **W6**：round-trip SC 收口 + 全套回归 + 文档批（SUMMARY/DECISIONS/AGENTS 增量节）。

## 7. OQ 索引

OQ-1..7 正本 = `M4-1-CONTEXT.md`（带推荐）。本文件 §2.3/§3.1/§3.3/§3.5/§3.6/§3.7 为各
OQ 的论证正文。

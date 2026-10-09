---
phase: m4-1
plan: "M4-1-01"
title: "TIFF 开发分支底座批（wave 1 = RESEARCH §6 W1..W4）——RasterColorDescription（ICC tag 自解析/usable 三检查/PQ-HLG canonicalization/sRGB 与 float-linear 默认）+ fixture 矩阵与 ICC 语义 golden + aces-core outputTransform_inv Float64 移植（RGC 逆不移植）+ 逆变换 golden（锚点 + 对自家 forward round-trip）+ 原生字节解码腿（u8/u16/32F 保源 primaries，decode() 路由不切）+ RasterInputKernels（linearize + display-to-working 单 pass + scene-linear 矩阵分支）+ kernel parity golden + develop-output 缓存缝 + bucket-uniform + srgbPiecewise 全族（DrtEotf additive case + legalEOTFs + 导出 ICC 臂）+ raster 默认 record 推导与 HDR 旗标（纯函数面）"
wave: 1
depends_on: []
autonomous: true
requirements: ["RASTER-IN-01（2026-10-08 收窄注记 = TIFF only）", "ALCE-02（推迟注记——本 plan 零触碰）"]
estimated_tests: "+75..85"
test_bundles: [IOP, IOPParity, Layers, Export]
files_modified:
  - LightamerCore/Sources/Decode/RasterColorDescription.swift   # 新建：描述型 + RasterTransfer/RasterReferral/RasterColorOrigin + usable 三检查 + 解析序 + canonicalization + peak 阶梯（KD-2）
  - LightamerCore/Sources/Decode/RasterIccParser.swift          # 新建：ICC 头/tag 表自解析（matrix-shaper primaries 反 chad/TRC 参数化与采样化/v4.4 cicp/LUT 判别；DisplayProfile 零触碰，KD-2 注记）
  - LightamerCore/Sources/Decode/RasterDecoder.swift            # 新建：decodeTIFF 原生字节腿（CGImageSource 像素取出零色彩管理转换 + u8/u16/32F 三档 + 灰→RGB + alpha 丢弃 + CMYK typed 拒 + 多页取 0；KD-5）——RAWDecoder.decode() 路由本 plan 不切
  - LightamerCore/Sources/Decode/DecodedImage.swift             # 修改：additive optional 双字段 rasterColor/rasterNative（缺省 nil = 既有档逐字节零漂移）
  - LightamerCore/Sources/Pipe/Drt/Aces2InverseReference.swift  # 新建：outputTransform_inv Float64 移植（Aces2Reference 同目录同范式；逆腿自持 Params 复用 rgcOn:false 档；KD-4）
  - LightamerCore/Sources/Pipe/Input/RasterInputKernels.metal   # 新建：raster_input_display（linearize+inverse 融合单 pass）/ raster_input_scene_linear（矩阵分支）双入口 + TRC 公式 kernel 自持（KD-6）
  - LightamerCore/Sources/Pipe/Input/RasterInputUniforms.swift  # 新建：逆腿自己的 flat uniform ABI（不与 Aces2Uniforms 复用，防签名耦合；RESEARCH §3.4）
  - LightamerCore/Sources/Pipe/Input/RasterInputStage.swift     # 新建：输入腿装配（原生字节上传 → kernel dispatch → develop-output 级缓存位；bucket-uniform 单盒子族；KD-7）——PixelPipe 接线 = M4-1-02
  - LightamerCore/Sources/Pipe/Drt/Aces2Reference.swift         # 修改：文件头 NOT-ported 注记更新（outputTransform_inv 已移入 Aces2InverseReference——纯注记，零算法 diff）
  - LightamerCore/Sources/Pipe/Drt/DrtEotf.swift                # 修改：additive case srgbPiecewise（rawValue "srgb_piecewise"，Alcedo 序列化拼写）+ serde/gamma/描述面 switch 补臂（KD-8；M3-3 封存面解封申报①）
  - LightamerCore/Sources/Pipe/Drt/DrtEotfKernels.metal         # 修改：EOTF encode 镜像增 sRGB 分段臂（Aces2Kernels.metal 零 diff 红线不触）
  - LightamerCore/Sources/Graph/DrtRecord.swift                 # 修改：legalEOTFs(for:) SDR 族增 srgbPiecewise（accept-set==legalEOTFs 不变式保全）；DrtRecord 结构零改
  - LightamerCore/Sources/Export/DrtOutputColorSpace.swift      # 修改：SDR 幂臂增 srgbPiecewise 解析（自建 ICC v4——TRC 用 curv 表非 para，L053 教训；KD-8）
  - Tests/LightamerTests/RasterColorDescriptionTests.swift      # 新建（IOP/Core 级，decode 家族先例）：解析序/usable 负测/canonicalization/默认回落
  - Tests/LightamerTests/RasterIccSemanticsTests.swift          # 新建（IOP/Core 级）：逐 fixture 描述断言 + TRC Float64 对表双锚（公开标准值硬编码）
  - Tests/LightamerTests/RasterDecodeLegTests.swift             # 新建（IOP/Core 级）：u8/u16/32F 保真/灰→RGB/alpha/CMYK 拒/多页/DecodedImage additive 零漂移
  - Tests/LightamerTests/Aces2InverseTests.swift                # 新建（IOPP 级，数学 golden 族先例 Lut3dEncoding）：Float64 锚点 + round-trip 对 Aces2Reference（rgcOn:false 双侧）
  - Tests/LightamerTests/RasterKernelParityTests.swift          # 新建（IOPP 级，*Parity* 域惯例）：kernel vs Float64 33³×limiting 集 + 近黑线性光双判据
  - Tests/LightamerTests/RasterInputPlaneTests.swift            # 新建（IOPP 级）：缓存键/滑动不重跑/bucket-uniform 三分辨率/typed 失败形态
  - Tests/LightamerTests/DrtEotfTests.swift                     # 修改：srgbPiecewise 增法（serde/gamma/公开标准参考值 golden）
  - Tests/LightamerTests/RasterDefaultRecordTests.swift         # 新建（LAYERS/Core 级）：描述→record 映射表逐行 + HDR 旗标 + RGC-off 政策纯函数 + stableHash 零漂移负测
  - Tests/LightamerTests/ExportDrtColorSpaceSrgbTests.swift     # 新建（EXPORT/Core 级）：srgbPiecewise ICC 臂 round-trip（导出→重导入描述一致）
  - Scripts/gen-tiff-fixtures.py                                # 新建：fixture 生成器（uv run；gen-float-fixtures.py 先例）
  - Tests/Fixtures/TiffRaster/                                  # 新建：fixture 矩阵在盘（位深×ICC×特形；生成器可再生；KD-3）
  - Project.swift                                               # 修改：新测试文件登记对应 target 数组（显式清单无 glob）+ tuist generate 恒为该批最后动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：新测试文件增行登记（E2 纪律，随各自任务 commit）
  - .work/gsd/phases/m4-1-tiff-raster/M4-1-01-SUMMARY.md        # 新建（T11）
  - .work/gsd/phases/m4-1-tiff-raster/M4-1-01-DECISIONS.md      # 新建（T11）
  - .work/GOAL-STATE.md                                         # 修改：续接点
  - .work/TODO.md                                               # 修改：M4-1 条目
  - .work/LESSONS.md                                            # 如踩坑
---

# Plan M4-1-01 — TIFF 开发分支底座批（W1..W4：描述 → 逆变换 → 解码腿 → 默认 record 面）

> **性质**：M4-1 两 plan 之首。本批交付 TIFF 开发链的**全部新代码面**，但**不切
> `RAWDecoder.decode()` 的生产路由**（TIFF 仍走既有 CI 通路；新腿由测试直驱）——
> 生产行为唯一可见变化 = DRT 面板 EOTF picker 增 sRGB 行（legalEOTFs 三方镜像
> 不变式保全的必然后果，见 KD-8，C 档停点向用户报备）。路由切换/装配接线/编辑
> 面门控/导入选择器/round-trip 收口 = M4-1-02。规格正本 =
> `RESEARCH-NOTES.md` §3/§4（file:line 均为 2026-10-10 HEAD 亲核）；裁决正本 =
> `M4-1-CONTEXT.md` 裁决记录（OQ-1..7 全按推荐）。
>
> **基线**：3174/16/0（M3-4-02-VALIDATION 2026-10-10 终验轮亲跑 1470s；bundle 分账
> IOP 483/1/0〔7651MB〕/ IOPP 408/3/0〔5843MB〕/ Layers 378/3/0 / Library 598/4/0 /
> Sessions 279/4/0 / Export 342/1/0 / App 686/0/0）。IOP 贴线纪律：本批全部新测试
> 用小 fixture（≤4MP）/33³ 网格/1D ramp，零 100MP 单测。

## 已定裁决（生效值，硬约束，不得重开）

M4-1 OQ-1..7 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-10，用户回批）。本 plan 承载其中 1/2/3/4 号生效值；5/6/7 号 = M4-1-02：

1. **OQ-1 = A（Alcedo D2 同形）**：raster 文档默认挂 aces20 DRT record（limiting/peak/EOTF 随源描述；跳过 defaultLook mint）；`DrtEotf` 增 `srgbPiecewise` additive case（rawValue `"srgb_piecewise"`，Alcedo 序列化拼写）。
2. **OQ-2 = A（新分支）**：原生解码保源 primaries（绕开 CI 色彩管理渲染的 working-space 映射）；逆变换 limiting gamut = 源原生 primaries。
3. **OQ-3 = A（aces-core 移植）**：`outputTransform_inv` 与 M2-6 forward 同源（v2.0 main SHA `069b0bc3`，Apache-2.0）；**RGC 逆不移植**；配套 **raster 文档 RGC 恒关**（KD-9，消解双压缩叠加——RESEARCH §3.3 倾向 (a)+(b) 组合随全推荐裁生效）。
4. **OQ-4（HDR 旗标）**：旗标 = `transfer ∈ {st2084, hlg}` 或（scene-linear float32 且内容探针 max > 1.0）；视口走 M2-6 DRT-HDR 既有臂；HDR 徽标 defer（图库面不入本 phase）。

**架构红线（本 plan 全程 + checker 机检面）**：
- `Aces2Kernels.metal` **零 diff**（forward 既有面；逆腿全部新文件）。
- IOP/IOPParity 逐位基线零漂移；JPEG/PNG/HEIC/WebP/PSD 通路字节零回退（本 plan 路由不切，天然成立；02 复验）。
- sidecar/`.lalb` **零 schema 变更**（描述不持久化，文件即真相）；DrtRecord **结构零改**（无新字段）。
- 导出矩阵六格式（ExportFormatSpec/ImageIOEncoders/WebPEncoder）零改动；`DrtOutputColorSpace` 仅 additive SDR 臂（KD-8）。
- `V50Order`/`Registry`/`HistoryStack`/`HistoryHash`/`PipelineDocument`/`NodeGraphCommand`/`ModuleInstance` 零触碰。
- **M3-3 封存面解封申报（两件半）**：①`DrtEotf`（additive case + 各 switch 补臂——M2DRT-06 注册口语义，编译期破 switch 兜底）②`PixelPipe`（本 plan 仅 additive seam 面：`RasterInputStage` 独立文件，PixelPipe 本体 diff 收窄到 input 装配分派点一处——**实际本体 diff 落在 M4-1-02**，本 plan 零 PixelPipe 触碰）附 `DrtEotfKernels.metal`（EOTF 镜像补臂）与 `DrtOutputColorSpace`（additive 臂）。`Aces2Reference.swift` 仅文件头注记更新，算法体零 diff。
- Core↔IOP 边界：TRC 求值 kernel 自持 + Core 内 host Float64 孪生小函数（不 import LightamerIOP；LutTransferMath 对表只在 IOPP 测试内做交叉锚）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 描述型与解析序（T1，RESEARCH §3.2 逐条落地）

- `RasterColorDescription` 字段面照 RESEARCH §3.2 草案：`referral` / `primariesXY: SIMD8<Float>`（Rx Ry Gx Gy Bx By Wx Wy，native 白）/ `transfer: RasterTransfer` / `peakLuminanceNits: Float` / `origin: RasterColorOrigin` / `profileDescription: String?` / `defaultReason: String?`；`RasterTransfer` 枚举 = `{linear, srgbPiecewise, gamma(Double), iccParametric(type: UInt8, params: [Double]), iccSampled([Float]), st2084, hlg, bt1886}`。
- **解析序（TIFF，只读 header）**：①内嵌 ICC（`CGColorSpaceCopyICCData` + 自解析 tag 表）→ matrix-shaper（rXYZ/gXYZ/bXYZ，有 chad tag 则反 chad 回 native 白；TRC 参数化/采样化）或 v4.4 `cicp` tag（覆盖 TRC/primaries）或 LUT-based（判别即止，像素不在此路解）→ ②无 ICC 且 float32 → **scene-linear Rec.709 默认**（origin=`tiffNoIccFloatLinear`）→ ③其余无 ICC → sRGB 默认（origin=`defaultSrgb`，记 `defaultReason`）。
- **usable 三检查**（顺位下落非报错）：primaries 非退化三角 / 白点在三角内 / 曲线单调；败者记 reason 落下一顺位，全败 = sRGB 默认。
- **canonicalization（2e-4 门）**：ICC 采样曲线逐点对 ST 2084 / 1000-nit HLG 公式，全部 2e-4 内 → `st2084`/`hlg`（上游 R1 教训：自家 PQ 导出 profile 存 4096 点表，不 canonicalize 会以「SDR 采样曲线 + 100 nit」错读回来）；命名色彩空间快路径（`CGColorSpace(name: .iTUR_2100_PQ)` 等系统名）先行。
- **peak 阶梯**：SDR=100 / PQ = mDCv → MaxCLL → 1000 递补，clamp [100, 10000] / HLG=1000。
- **DisplayProfile 零触碰**：ICC tag 走读代码在 `RasterIccParser.swift` 自持（display 域与文件域的 fallback 链语义不同，合并会耦合两族回退路径；`DisplayProfile.swift` 的 xyzTag walk 只作模式参考）。
- 零第三方 ICC 库（依赖最小化红线）。

### KD-2 fixture 矩阵（T2，RESEARCH §4.1 全表）

生成器 `Scripts/gen-tiff-fixtures.py`（`uv run` 离线；`gen-float-fixtures.py` 先例）+ 产物入盘 `Tests/Fixtures/TiffRaster/`（产品资产在盘纪律；每 fixture 文件名编码维度，来源注记 README 随目录）。矩阵：**位深** {8, 16, 32F} × **ICC** {sRGB matrix, DisplayP3 matrix, AdobeRGB matrix, Rec2020 matrix, ProPhoto matrix（AP1 外 limiting 分支）, LUT-based RGB（CI 腿样本）, 无 ICC, PQ-tagged（cicp + 采样表两形态）, HLG-tagged} × **特形** {多页取 0, 灰度 ICC, alpha 丢弃, CMYK typed 拒, 退化 primaries ICC（usable → 默认 + reason）, 无 ICC float32（scene-linear 判定）}。PQ/HLG 采样表 fixture 用产线公式生成后**扰动一位有效数字**（防 golden 同义反复——表值与 canonicalization 门 2e-4 之间留实证距离）。全部 fixture ≤512×512（IOP 贴线纪律）。

### KD-3 逆变换移植面（T4，RESEARCH §3.3 + M2-6-2 范式）

- **上游获取**：`lib/Lib.Academy.OutputTransform.ctl` + `lib/Lib.Academy.Tonescale.ctl` 于 SHA `069b0bc3e1f6c62820f19fdae2fecec3f4fc0f80`（github.com/ampas/aces-core v2.0 main，Apache-2.0）；网络失败走 `px --up` 代理（AGENTS §6）；逐函数锚注 :line（M2-6-2 同款纪律）。`NOTICE` §2 aces-core 条目 additive 追加 inverse 函数清单（版本/SHA 不变）。
- **复用既有资产**：TSParams（`tonescale_fwd/inv` 已双落笔，Aces2Reference.swift:14 注记）/ CAM16 JMh 正逆族（Cam16.swift）/ `ap0ToRec2020` 常数矩阵（Cam16.swift:182——逆腿尾矩阵就是它，Float64 求好进 uniform）/ 表族构建（`params(space:peak:rgcOn:)` **以 `rgcOn:false` 档复用**——逆腿无 RGC 任何方向，paramsCache 键已含 rgc 位）。
- **新移植函数族**：`chroma_compress_inv`、逆 tonescale 的 JMh 参数化消费组装、`gamut_compress_inv`（≤2 次估值闭式）、逆方向 stage 编排。**逆腿 stage 图（与 forward 共享词汇表）**：
  ```
  [i7'] ×(peak/100)                          ← EotfBox 契约逆（1.0 = peak nits）
  [i6'] RGB→JMh（limit_params = 源 limiting）  ← forward [6] 之逆
  [i5'] gamut_compress_inv（≤2 估值闭式）      ← forward [5] 之逆
  [i4'] chroma_compress_inv → tonescale_inv   ← forward [4] 之逆
  [i3'] JMh→RGB（input_params = AP0）          ← forward [3] 之逆
  [i0'] AP0 → linear Rec2020（ap0ToRec2020）   ← forward [0] 之逆
  （[1] RGC / [2] clampAP0ToAP1 无逆段：RGC 恒关；合法 display 域的逆值天然落在 AP1 内）
  ```
- **FMA 纪律（上游 macOS 教训 R1-1）**：Swift Float64 侧近黑失配第一嫌疑 = swiftc 熔合；kernel 侧同。golden 近黑双判据门（T8）先于一切调参；命中即编译旗标/pragma 处置并记 LESSONS。

### KD-4 golden 门（T5/T8，RESEARCH §4.3 两级 + M3-3 E5 分解先例）

- **T5（Float64 级）**：①锚点——display 黑 → 0；源白（0.05%..90% 峰值带）→ AP0 中性（max/min−1 < 1e-4）；②**round-trip 对自家 forward**：display → inverse → working（linear Rec2020）→ `Aces2Reference.runPixel`（rgcOn:false 同参）→ display，目标带 1e-3 级假设（同源一致性优势点，上游 OCIO 逆做不到；实测带写 DECISIONS，若超带先查 FMA 再查表族）；③limiting 集 = {Rec709, P3-D65, AdobeRGB, Rec2020}@100nit + Rec2020@1000nit 五键全覆盖。
- **T8（kernel parity 级）**：33³ display RGB 网格 × 上述五键，kernel vs `Aces2InverseReference` band 目标 ≤1e-5（**比较域纪律 L048：一律 decode 回线性 + `Double(Float(x))` 升维**；p99.9 + 近黑线性光 1e-6 内亦收双判据——ACEScc 近黑陡峭教训 R1-2）；scene-linear 矩阵分支对 host Float64 矩阵乘 parity 同门。
- （可选交叉资产：OCIO ACES 2.0 参考值转录测试——OCIO 不入库只转录数值；时间盒内可割。）

### KD-5 原生解码腿（T6，RESEARCH §3.1/§3.4）

- `RasterDecoder.decodeTIFF(_ url:)`：`CGImageSourceCreateImageAtIndex(0)` 位深保真（RAW-03 02-06 宿主已证，不重证）→ **像素字节取出零色彩管理转换**（`CGImageDataProvider` 直取 + 手工布局归一）→ `RasterNativePixels`（`{data, width, height, bitsPerComponent ∈ {8,16,32}, channelLayout}`）→ `MTLTexture` 上传（u8 = `.r8Uint`→rgb8 / u16 / float32 三档；灰→RGB CPU 侧复制；alpha 通道丢弃按存储色渲染——premultiplied 不还原，D6；CMYK → typed `AppError.decodeFailed`；多页取 0）。
- **描述与像素同批产出**：`decodeTIFF` 返回 `DecodedImage` + additive 双 optional 字段（`rasterColor`/`rasterNative`，缺省 nil——既有 init 调用点与档位逐字节零漂移，负测钉死）。LUT-based ICC：`decodeTIFF` 判别即转 CI 腿（`CIImage(cgImage:)` 全色彩管理，现有 `renderToTexture` 面）+ 描述记 `{rec2020 primaries, linear, displayReferred, iccLutConverted}`——**唯一走 CI 腿的 TIFF 形态**（RESEARCH §3.2.4）；CI 腿时 `rasterNative = nil`。
- profile hash（SHA-256 截断）入描述防「描述与文件失配」（上游 §4.3 同款）；`decode()` 路由本 plan **不切**（TIFF 仍走 `decodeRaster`，:135-140 分支零 diff）。
- `contentDedupeID` 沿用（path⊕size⊕mtime）；描述指纹 = 描述显式字段 FNV 折叠（L013 字段显式纪律，非 JSON 序）。

### KD-6 kernel 面（T7，RESEARCH §3.4）

- 新文件 `Pipe/Input/RasterInputKernels.metal`，**双入口**：`raster_input_display`（linearize → [i7'..i0'] 融合单 pass——省 100MP float32 中间面 ≈1.6GB，融合裁定依据）/ `raster_input_scene_linear`（TRC=linear 直通 → 源 primaries+白 CAT02 → Rec2020 定矩阵 + 负值钳 0，**上限不钳**——HDR float 内容探针依赖 >1.0 幸存；DRT 尾的 `clampAP0ToAP1` 天然接管 forward 输入域）。
- **TRC 公式 kernel 自持**（sRGB 分段 / 纯 gamma / PQ / HLG / BT.1886 公开标准闭式，MSL 直写；Core host 孪生小函数供 golden——Core 不 import LightamerIOP）。
- uniform = 逆腿自己的 flat struct（`RasterInputUniforms.swift`，不与 `Aces2Uniforms` 复用——RESEARCH §3.4 防 ABI 签名耦合）；表族打包沿用平面式单 buffer 零 function constants 纪律。
- 失败形态 typed：peak ≤0 / 奇异矩阵 / device 错误 → `AppError` 族。

### KD-7 缓存与 bucket-uniform（T8，RESEARCH §3.1/§2.6）

- **develop-output 级缓存位**（`RasterInputStage` 新型持有；key = `fnv(描述指纹 ⊕ 几何 ⊕ 分支 tag)`）——Color Grade/DRT/post 滑动不重跑（上游 §5.4 语义）。PixelPipe 本体接线（position 0 分派点 + `decodeParamsHash` 类显式字段折叠）= **M4-1-02 T2**；本 plan 缓存位在 Stage 内自证（单测直驱）。
- **bucket-uniform**：full / preview / thumbnail 三分辨率同一 kernel 盒子族（THUMBNAIL 分辨率 golden 抽样一条）；`PreviewBucket` 零改（分辨率参数从既有 negotiation 流入）。

### KD-8 srgbPiecewise 全族（T9，OQ-1 生效值①）

- `DrtEotf.srgbPiecewise` additive case（rawValue `"srgb_piecewise"`）；编译器破出的穷举 switch 逐个补臂：serde/gamma 表/`DrtEotfKernels.metal` EOTF encode 镜像/`DrtRecord.legalEOTFs(for:)`（**SDR 族增行——accept-set==legalEOTFs==Alcedo cpp 三方镜像不变式保全，HDR 族不动**）/`DrtOutputColorSpace`（SDR 幂臂解析 srgbPiecewise → 自建 ICC v4，**TRC 用 curv 采样表非 para tag**——L053：macOS 27 para 误解析在案）。
- **本批唯一生产可见变化**：RAW 文档 DRT 面板 EOTF picker 增 sRGB 行（picker 数据源 = legalEOTFs 单源，自动出现；panel/model 代码零 diff）。C 档停点向用户报备。
- golden：公开标准 sRGB 参考值硬编码（IEC 61966-2-1 表值）+ IOPP 交叉锚一条（对 `LutTransferMath.srgbEncode/DecodeChannel`——LightamerIOP 反向对表只在 IOPP 测试面做）+ 导出 round-trip（srgbPiecewise ICC 导出 → 重导入描述 canonicalize 回 `srgbPiecewise`——02 的 SC#1 预演半面，本 plan 先落 EXPORT 单测）。

### KD-9 raster 默认 record 推导 + RGC 恒关（T10，OQ-1/OQ-3 生效值）

- **描述 → DrtRecord 纯函数**（`RasterDefaultRecord.derive(from:)`）：method=`aces20`；`limitingSpace` 映射表 {sRGB→rec709, DisplayP3→p3d65, AdobeRGB→adobeRGB, Rec2020→rec2020, ProPhoto→proPhoto, 其余→rec2020+defaultReason}；`peakLuminance`=描述 peak；`encodingEotf` 映射表 {srgbPiecewise→srgbPiecewise, st2084→st2084, hlg→hlg, 纯 gamma 2.2→gamma22 / 2.6→gamma26 / 1.8→gamma18 / 2.4→bt1886（最近邻，miss→gamma22+reason）, linear→linear}；`encodingSpace` 与 primaries 同族映射（同上表 + xyz 例外→rec2020+reason）。
- **RGC 恒关（render-side 政策，非 record 字段）**：raster 文档的 aces20 臂 `Aces2Reference.params(..., rgcOn: false)` / 逆腿同参——**DrtRecord 零新字段、零持久化、零 hash 面**（封存面零触碰；`rgcOn` 已是 params 运行时开关 :1065 默认 true，只改调用点传入值）。政策纯函数 `isRasterDocument(rasterColor != nil)` 单源，EotfBox/臂装配点消费（02 接线，本 plan 纯函数 + 单测）。若用户按记录编辑 peak 等，RGC-off 是文档类政策不随编辑翻转（Alcedo D2 同形——其 aces20 变换无 RGC 任何方向）。**晨审可翻点**：若要求 per-record RGC 位则升级为 additive `rgcOn: Bool?`（stableHash nil 零漂移钉死纪律）——当前裁 render-side。
- **HDR 旗标纯函数**（OQ-4 生效值）：`isHdrRaster(description, contentProbeMax) = transfer ∈ {st2084, hlg} ∨ (referral == .sceneLinear ∧ float32 ∧ probe > 1.0)`；内容探针 = decode 期 CPU 次采样 ≤4096 格确定性 max（T6 腿产出）。默认 record 的 encoding eotf ∈ {st2084, hlg} → 既有 DRT-HDR 视口臂自动激活（02 联通）。

## read_first

1. `.work/gsd/phases/m4-1-tiff-raster/M4-1-CONTEXT.md`（裁决记录 = 生效值正本）+ `RESEARCH-NOTES.md` §2/§3/§4（本 plan 全部 file:line 锚的正本）
2. `LightamerCore/Sources/Pipe/Drt/Aces2Reference.swift` 全文头注 + stage 图（:1-54）+ `params(space:peak:rgcOn:)`（:1064 起，paramsCache 键含 rgc 位 :1043）——逆腿的范式与复用面
3. `LightamerCore/Sources/Pipe/Drt/Cam16.swift`（JMh 正逆族 + `ap0ToRec2020` :182）
4. `LightamerCore/Sources/Graph/DrtRecord.swift`（DrtEotf 七值/legalEOTFs/isHdrEncoding/默认 record :370-381）
5. `LightamerCore/Sources/Decode/RAWDecoder.swift`（`decode` :118-141 / `decodeRaster` :316-334 / RAW-03 注记 :299-315）
6. `LightamerCore/Sources/Decode/DecodedImage.swift`（additive 字段落点）
7. `LightamerCore/Sources/Foundation/DisplayProfile.swift`（ICC tag walk 模式参考 :200-293；零触碰）
8. `LightamerCore/Sources/Foundation/StableHash.swift` + `WorkingSpace.swift`（FNV/线性 Rec2020 常数）
9. `Tests/LightamerTests/Aces2KernelGoldenTests.swift` + `DrtKernelGoldenTests.swift`（golden 测试基建：fence 纪律 L014/网格驱动/比较域）
10. `.work/gsd/phases/m2-6-drt/M2-6-2-SUMMARY.md`（移植纪律先例）+ `Scripts/gen-float-fixtures.py`（fixture 生成器先例）
11. 上游 CTL（T4 期获取，KD-3）+ `/Volumes/UNITEK/Documents/Development/AlcedoStudio/docs/roadmap/alcedo_studio/edit/raster_image_input_plan.md` §5/§10（GPL 只读——FMA 教训与 round-trip fixture 自证形态）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+ `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh --bundle <域>`（直启宿主；全套 `--all` 需 orchestrator 批准，本 plan 收口轮才申请）。
- **GPU 读回 fence（L014）**：kernel parity/缓存测试读纹理前必须 queue fence（`drain()` 模式）。
- **比较域（L048）**：golden 一律 decode 回 linear + `Double(Float(x))` 升维；禁 ACEScc 域直接比。
- **零 diff 红线自证**：收口任务跑 `git diff 3174基线..HEAD -- LightamerCore/Sources/Pipe/Drt/Aces2Kernels.metal LightamerIOP/ LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Pipe/History/` 零命中并截屏入 SUMMARY。
- **资源监控**（AGENTS）：跑测试宿主期间照常巡检；IOP 贴线 bundle 若 MEMFAIL 先查重测漂移再查本批（新测试均小 fixture，理论零增量）。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 RasterColorDescription 与 ICC 解析（KD-1）

- read_first 1/4/7/8 → 实现 `RasterColorDescription.swift` + `RasterIccParser.swift`（解析序/usable/canonicalization/peak 阶梯/默认回落全落）。
- 验收：`RasterColorDescriptionTests`（IOP）——解析序每顺位一法、usable 三检查各一负测 + 顺位下落 reason 断言、canonicalization 2e-4 门正负测、peak 阶梯边界（100/10000 clamp）、sRGB/float-linear 双默认；**DecodedImage 既有档零漂移负测**（additive 字段缺省 nil 序列化/构造逐字节）。

### T2 fixture 矩阵（KD-2）

- read_first 11 → `Scripts/gen-tiff-fixtures.py`（uv run 可再生）→ 生成全矩阵入 `Tests/Fixtures/TiffRaster/` + README 来源注记 → `Project.swift` 登记（folderReference/资源面照 FilmProfiles 先例——裸目录须 `Resource.folderReference`，Tuist 4.208 教训）。
- 验收：生成器幂等重跑字节一致；矩阵清单文件数 = 计划数（DECISIONS 记清单）；CMYK/退化 primaries/LUT/PQ 表式特形 fixture 各在盘。

### T3 ICC 语义 golden（T1/T2 验收面，RESEARCH §4.2）

- read_first 1/9 → `RasterIccSemanticsTests`：逐 fixture 逐字段断言（referral/primaries/transfer/peak/origin/defaultReason）+ TRC host Float64 对表双锚（sRGB/gamma/PQ/HLG/BT.1886 公开标准值硬编码）+ usable 负测接 fixture。
- 验收：全 fixture 绿；对表值域带 ≤1e-6（公式级）写明于测试头注。

### T4 Aces2InverseReference Float64 移植（KD-3）

- read_first 2/3/11 + 获取上游 CTL（px --up 兜底）→ `Aces2InverseReference.swift`（KD-3 stage 图逐段落笔 + 逐函数上游锚注）→ `Aces2Reference.swift` 头注 NOT-ported 行更新（纯注记）→ NOTICE additive。
- 验收：编译绿；文件头 stage 图与 KD-3 一致；零 forward 文件算法 diff（`git diff -- Aces2Reference.swift` 仅头注行）。

### T5 逆变换 golden（KD-4 Float64 级）

- read_first 9 → `Aces2InverseTests`（IOPP）：黑/白锚点 + round-trip 对 forward（五 limiting 键 × 峰值带抽样）+ FMA 近黑哨兵（1e-3 ACEScc / 1e-6 线性光带）。
- 验收：round-trip 实测带写 DECISIONS（1e-3 假设修正为实测）；失配处置路径（FMA 哨兵）有结论行。

### T6 原生解码腿（KD-5）

- read_first 5/6 → `RasterDecoder.swift` + `DecodedImage` additive 双字段 → fixture 驱动单测。
- 验收：`RasterDecodeLegTests`（IOP）——8/16/32F 位深保真（极值 0/1/2.0/65504 幸存断言，灰 fixture 延续 RAW-03 法）/灰→RGB/alpha 丢弃/CMYK typed 拒/多页取 0/LUT-ICC CI 腿分流（rasterNative=nil + 描述 iccLutConverted）/`decode()` 路由零 diff 断言（TIFF UTI 仍返 CI 通路——防提前切换）。

### T7 RasterInputKernels（KD-6）

- read_first 2/9 → `.metal` 双入口 + `RasterInputUniforms` + TRC 自持公式 + `RasterInputStage` 装配（上传/dispatch/缓存位）。
- 验收：编译绿（`tuist generate` 尾闸）；两入口 PSO 建成；`RasterInputStage` 单测直驱出平面（几何/格式断言）。

### T8 kernel parity golden + 缓存/bucket（KD-4 kernel 级 + KD-7）

- read_first 9 → `RasterKernelParityTests`（IOPP，fence 纪律）+ `RasterInputPlaneTests`（缓存滑动/bucket 三分辨率/typed 失败）。
- 验收：33³×五键 parity band ≤1e-5（p99.9+近黑双判据）实测入 DECISIONS；缓存滑动不重跑断言（run 计数器）；三分辨率同值带（bucket-uniform）。

### T9 srgbPiecewise 全族（KD-8）

- read_first 4 → `DrtEotf` additive case + 全 switch 补臂 + `DrtEotfKernels.metal` 镜像臂 + `legalEOTFs` SDR 增行 + `DrtOutputColorSpace` curv 表臂。
- 验收：`DrtEotfTests` 增法（serde `"srgb_piecewise"`/gamma 值/标准 golden）+ `ExportDrtColorSpaceSrgbTests`（EXPORT，导出→重导入描述 canonicalize 回 srgbPiecewise）+ **红证**：`git diff -- Aces2Kernels.metal` 零命中；legalEOTFs 不变式断言（accept-set 集合等式测试既有面更新）。

### T10 默认 record 推导 + HDR 旗标 + RGC 政策（KD-9）

- read_first 4 → `RasterDefaultRecord` 纯函数面（映射表/HDR 旗标/RGC-off 政策/内容探针消费）。
- 验收：`RasterDefaultRecordTests`（LAYERS）——映射表逐行（含 ProPhoto→proPhoto 与 xyz 例外）/HDR 旗标三支（TRC 旗标/float 探针/双否）/RGC 政策纯函数/stableHash 零漂移负测（默认 record hash 与 M2-6 基线逐位——DrtRecord 零字段变更的铁证）。

### T11 收口

- SUMMARY（任务序/实测带/bundle 分账）+ DECISIONS（KD 偏差/FMA 结论/round-trip 实测带/fixture 清单）+ GOAL-STATE 续接点（M4-1-02 待启）+ TODO 同批 + 全零 diff 红线自证清单。
- 验收：定向轮 `--bundle IOP/IOPParity/Layers/Export` 全绿（exit 0 + 零 MEMFAIL）；zh-audit `--check` 对本批新键（readout 面本 plan 无 UI——预期零新键，跑了再记）。

## 验收标准（AC 总表）

1. **OQ 生效值①**：`DrtEotf.srgbPiecewise` 在册（serde/镜像/legalEOTFs/导出臂四通）且默认 record 推导对 sRGB 源产出 eotf=srgbPiecewise 的 aces20 record。【T9/T10】
2. **OQ 生效值②**：逆腿 limiting gamut = 源 primaries（五键 golden 覆盖 + KD-3 stage 图在文件头）；解码面绕开 CI 色彩管理（原生字节三档位深保真断言）。【T4/T5/T6】
3. **OQ 生效值③**：`outputTransform_inv` 移植自成 `Aces2InverseReference`（上游锚注逐函数）；RGC 逆零移植 + raster RGC-off 政策纯函数在册；`Aces2Kernels.metal` 零 diff。【T4/T10】
4. **OQ 生效值④**：HDR 旗标纯函数三支全断言；PQ/HLG fixture 描述 canonicalize 生效（非「SDR 采样表错读」回归）。【T1/T3/T10】
5. **golden 矩阵**：fixture 全矩阵（位深×ICC×特形）描述 golden 绿；TRC 双锚对表绿。【T2/T3】
6. **round-trip**：inverse→forward 实测带入 DECISIONS（目标 1e-3 级）+ srgbPiecewise ICC 导出→重导入一致。【T5/T9】
7. **缓存与 bucket**：develop-output 缓存滑动不重跑断言 + full/preview/thumbnail 三分辨率同值带。【T8】
8. **零漂移红线**：DecodedImage/DrtRecord/`decode()` 路由/Aces2Kernels.metal/sidecar/IOP-IOPP 基线全部零 diff 断言或亲证；IOP/IOPP/Layers/Export 四 bundle 定向轮全绿零 MEMFAIL。【T11】

## 风险与边界

- **FMA 熔合漂移**（上游实证）：Float64 与 kernel 双侧哨兵先行（T5/T8 双判据）；命中即 pragma/旗标并 LESSONS。
- **round-trip 带超 1e-3**：先查 FMA → 再查表族（upper-hull gamma 阈值搜索本性 ~2.7e-4，上游 R2 标定）→ 带写 DECISIONS 不硬凑（禁调 golden 凑带）。
- **IOP 贴线**：全批小 fixture；若 IOP bundle MEMFAIL 先按 AGENTS 口径查重测漂移。
- **`DrtOutputColorSpace` SDR 幂臂自建 ICC 的 L053 坑**：curv 表非 para；macOS 27 CalibratedRGB 坑绕行（复用既有 SDR 臂骨架换 TRC 表）。
- **上游 CTL 获取失败**：px --up 代理；仍失败 = 阻塞上报（不凭先验默写公式）。
- **P2 衔接面**：PixelPipe 接线/路由切换/编辑面/导入面/收口全套回归全部在 M4-1-02；本 plan 交付面以 T11 红证清单为界。

## 提交约定

- T1 `feat(core): raster color description with icc tag parsing and usable checks`
- T2 `feat(assets): tiff raster fixture matrix with offline generator`
- T3 `test(core): icc semantics golden over the fixture matrix`
- T4 `feat(core): port aces-core outputTransform_inv as float64 reference`
- T5 `test(iopp): inverse transform anchors and round-trip golden vs forward`
- T6 `feat(core): native tiff decode leg preserving source primaries`
- T7 `feat(core): raster input kernels with fused linearize and inverse`
- T8 `test(iopp): kernel parity and develop-output cache golden`
- T9 `feat(core): srgb piecewise eotf across serde kernel legal set and export icc`
- T10 `feat(core): raster default drt record derivation with hdr flag and rgc policy`
- T11 `docs(m4-1): close raster base batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。

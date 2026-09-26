# Plan 11-02 — 执行决策（DECISIONS）

> 执行期决策边界（plan 纪律）：RESEARCH 未覆盖 / API 事实与 plan 字面冲突 / 探针
> 实证的实现细节在此登记。编号 D1..D12 按产生顺序；体例照 11-01-DECISIONS。
> 全部为 11-02 范围内决策（标注可逆性）。探针日期 = 2026-09-26（macOS 27.0 / Apple M4）。

## D0（前置）：HEAD 编译破裂修复 = 独立 `fix(11-01)` 提交 `de796c4`

`db8fa32`（11-01 验收 fix）把 `canTransition` 内层 `default:` 换显式列表时**丢了
自迁移 target case**（`.rendering`→`.rendering`、`.encoding`→`.encoding`），穷尽
switch 不再穷尽——11-02 首次 build-for-testing 即败。修复 = 补回两个自 case
（truth table 与原 default 形式完全一致），契约测试 12/12 绿（向量未动）。
记为前置独立提交，不混入 T1。
Reversibility: 无关（纯修复）。

## D1: ProPhoto CGColorSpace 来源 = 系统 ROMM profile（`kCGColorSpaceROMMRGB`）

plan T2 留给执行期的二选一。裁决 = **系统 ColorSync profile**：嵌入 ICC 名为
「ROMM RGB: ISO 22028-2:2013」（探针实证），ROMM 是 ProPhoto 的标准前身
（primaries 近同、D50 白），零自造 ICC 数据负担。**不用**手工构造 ROMM。
伴随事实：typed CGColorSpace overlay 在本 SDK **无** `rommRGB`/`ITUR_2020`
成员拼法（`sRGB`/`linearSRGB`/`displayP3`/`adobeRGB1998`/`linearITUR_2020` 有）
→ `ExportColorSpaceMapper` 统一走 raw `kCGColorSpace*` 常量字符串（同
WorkingSpace 的「系统常量恒在」安全性论证），集中一处。
Reversibility: 高（mapper 单点）。

## D2: 线性 ICC 变体系统只供 sRGB/P3/Rec2020——adobeRGB/proPhoto 32f 抛 typed error

探针：`kCGColorSpaceLinearAdobeRGB1998`/linear ROMM 均 UNAVAILABLE。32f TIFF
必须保线性（D-11-CONTEXT-7），display-TRC profile 会静默弯值 →
`linearCGColorSpace(for: .adobeRGB/.proPhoto)` 抛 `.invalidParameter`（8/16-bit
TIFF 不受影响，走 display 变体）。32f 菜单实际配对 = sRGB/P3/Rec2020 × 线性。
Phase 13 如需宽域线性 32f，自备 ICC 数据即解。
Reversibility: 高（单 switch 分支）。

## D3: R5 终判 = XMP 全格式**不写**（宿主 API 事实）；EXIF 走 properties 路径全五格式通过

RESEARCH §1.3-1 的「整体替换模式」在宿主上不成立——三途径全部字节级验证为空：

1. 源 metadata 继承 + `kCGImageDestinationMetadata`（不带 Merge）→ XMP 无、
   **EXIF 也丢**（metadata 对象整写 = 什么都不序列化）；
2. fresh `CGImageMetadataCreateMutable` + `xmp:CreatorTool` set 成功返回 → 不落；
3. `CGImageDestinationMergeMetadata: true` → EXIF 仍丢（RESEARCH 的「merge 保
   EXIF/IPTC」在本机同样不成立）；
4. `CGImageMetadataCreateFromXMPData`（真 XMP packet 解析，tags 3 个）→ 不落；
5. `"{XMP}"` properties dict → 不落。

**可行路径 = properties dict**：`kCGImagePropertyExifDictionary` 直上 AddImage
properties → **五格式 EXIF round-trip 全通过**（DateTimeOriginal + LensModel 实
测）；与 metadata 对象并存时 EXIF 仍活。D-11-CONTEXT-5 的裁决意图（EXIF
round-trip）照常落地，机制改走 properties；XMP packet（CreatorTool/rating/
flag）= 全格式文档化限制 + golden 反向锚（断言 XMP 缺席，宿主行为变化即红）
+ Phase 12/14 复审。Editor signature 唯一活载体 = TIFF Software tag
（`kCGImagePropertyTIFFSoftware`；EXIF Software 无公开属性常量，实测写不进）。
Reversibility: 高（golden 锚固化现状；宿主升级翻锚即触发重审）。

## D4: R1 位深终值 = HEIC 10-bit ✓ / AVIF 10-bit ✓ / **AVIF 12-bit 落 10-bit**

- HEIC：16bpc 源直达 **depth=10**（无需 `kCGImageDestinationEncodeBasePixelFormatRequest`）。
- AVIF：16bpc 源 → depth=10 ✓；12-bit 请求（`l12p` base-pixel-format fourcc）仍
  落 10 → **R1 文档化降级**：`.twelve` 变体编码出 10-bit 文件（不 throw——出片
  优于失败；降级显式记录在编码器头注 + golden 锚 `testAVIFGoldens` 断言
  depth==10，宿主能力变化即红）。libavif 协议缝保留（AVIFEncoder 类型后换
  conformer 即可）。
- 奇数尺寸（33×17）五格式精确回读（HEIC/AVIF 对齐由编码器内部处理——RESEARCH
  §3.4 预判证实）。
Reversibility: 高（锚测试固化终值）。

## D5: 出口腿签名 = `TextureBox` renounce 包；width/height 从纹理推导

plan 字面 `renderToEncodedBitmap(_:sourceColorSpace:toSpace:width:height:)` 两处
修正：① Swift 6 region isolation 下 `any MTLTexture` 跨 actor 复发即报
sending 风险（测试需多目标复用同一纹理）——采用 ColorOutModule 先例的
`TextureBox`（@unchecked Sendable renounce 语义，「本调用消费该平面」）；②
width/height 从 `input.texture` 推导，独立参数是漂移面。checker E3 契约
（sourceColorSpace 参数化默认 WorkingSpace）逐字落地。
Reversibility: 高（签名加法兼容）。

## D6: **CI 纹理读回 = 垂直镜像 host finding**——出口腿内 `.downMirrored` 复位；姊妹 `convertTexture` 同病未修（移交）

程序化探针钉死：`CIImage(mtlTexture:)` 以 CI 的底向上 origin 约定读纹理，裸
`render(toBitmap:)` 产出相对纹理行序**垂直镜像**的 bitmap（vflip 映射 0
mismatch / identity 64 mismatch；非 180° 旋转）。出口腿内部
`.oriented(.downMirrored)` 复位，契约 = 「bitmap 行序 == 纹理行序」，
`testExitLegBitmapRowsMatchTextureRows` 常驻钉死（修复前 64/64 错位——不修则
导出文件全部上下颠倒）。
**范围外同病**：`convertTexture`（colorout ColorSync **fallback** 路径）存在完
全相同的镜像——fast path 不经过它，生产从未内容级验证过该腿的定向，属休眠
缺陷。11-02 范围外不修（动它需 GUI 走查兜底），登记 LESSONS L029 + 移交：
修复 = 同款 `.downMirrored` + fast/fallback 双腿内容级 parity 测试。
Reversibility: 高（单行 + 锚测试）。

## D7: TIFF 32f 数值恒等 = 1 float32 ULP（5.96e-8）；bitwise 不可达

探针：50/256 样本差 1 ULP（2^-24，写入/归一化上下文舍入步）→ golden 断言改
逐样本 `1e-6`（观测最差 16× 余量）。8/16-bit 维持逐位相等（全压缩变体过）。
Reversibility: 无关（golden 校准）。

## D8: WebP mux 探测终判 = Swift-WebP 全源**零** mux/EXIF/ICC 面 → OQ-11-5 v1 例外维持

对 DerivedData checkout 的 Swift-WebP 0.6.1 全 Sources grep：无任何 WebPMux/
EXIF/ICC 符号。WebP = 无内嵌元数据（文档化例外），结构级锚 = 测试内 RIFF
chunk walker 断言容器只含 `VP8/VP8L/VP8X/ALPH` 四cc——双向变化（未来 mux 面
露头或宿主 ImageIO 获得 WebP 写）都会让锚变红触发重审。
Reversibility: 高。

## D9: lossless quality→effort 折算 = `round(quality×9)` 钳 [0,9]

`ExportFormatSpec.webp(quality:lossless:)` 的 0...1 knob 与
`WebPEncoderConfig.losslessPreset(level:)` 0-9 的映射。libwebp lossless 各级
均逐位精确，knob 只换编码时间 → 线性折算无保真语义损失；向量钉
WebPEncoderTests。
Reversibility: 高（纯函数）。

## D10: 出口腿 Metal 值经 CI 读回的定向断言落在**行序测试**而非逐点假说

fence 测试首跑失败形态（样本位移假象）暴露：对 CI 读回定向的猜测必须程序化
枚举候选映射（identity/vflip/rot180/offset ×4）而非逐点手算——探针形式固化
为行序契约测试后，fence 测试回归纯竞态语义。方法论教训入 L029。
Reversibility: 无关。

## D11: `AppError` additive 补 `.encodeFailed(String)`

Export 编码域此前无 typed 归口（`.sidecarWriteFailed` 语义不符）。additive
case + errorDescription 行 + UI tiering 注记；零既有 case 语义变更。
Reversibility: 高。

## D12: 「AVIFEncoder 协议缝」落位 = 具体 struct 类型背后的 conformer 替换位

D-11-CONTEXT-1 的缝不做成独立 `protocol AVIFEncoder`（注册表分派已有
`ExportEncoder` 协议，二重协议是空转）——v1 `AVIFEncoder` struct = 原生
ImageIO 实现；若未来引 libavif，同型 struct 换入注册表单行即换实现。
类型头注钉此意图。
Reversibility: 高。

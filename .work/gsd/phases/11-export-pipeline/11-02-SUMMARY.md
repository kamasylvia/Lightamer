# Plan 11-02 — SUMMARY（编码面：量化链 + 出口转换腿 + 六格式 encoder + golden，W2）

> 执行：2026-09-26，ZCode executor subagent worker（11-01 同款协议）。
> 基线全 suite **1187/6skip/0fail** → 终轮 **1220/6skip/0fail**（322.9s，净增 33）。
> 未 push；每任务边界检查 `.work/config.toml [gsd]`（全程 auto=true/paused=false）；
> 构建 `caffeinate -dis` 包裹，单测全走 `Scripts/test-direct.sh`（零弹窗）。

## 任务表

| 任务 | 交付 | commit | 证据 |
|---|---|---|---|
| T0（前置） | HEAD 编译破裂修复（11-01 验收 fix 丢自迁移 case） | `de796c4` | build-for-testing 绿 + 契约测试 12/12（truth table 不变） |
| T1 ExportQuantizer 量化链 | `ExportQuantizer.swift` + `ExportQuantizerTests.swift` | `67eb61e` | 12 tests：dt `roundf(CLAMP(v·0xff/0xffff))` 同款（127.5→128 换 truncation 即红向量）+ CLAMP 边界含 dt CLAMPF NaN→下界 + 16/10-in-16/12-in-16 精确阶梯 + 32f 位级恒等 + 中性恒中性 + packed 三面（RGBA8/RGBA16 host-endian/float32）+ 计数校验 |
| T2 出口转换腿 | `CIContextPool.renderToEncodedBitmap` + `EncodedBitmap` + 出口段 goldens | `4fca688` | 7 tests：五目标（sRGB/P3/AdobeRGB/ROMM/BT.2020）中性恒中性 + 各 profile TRC 已知值（±2/255）+ sRGB 0.5 线性→187-188 钉点 + 黑白角点 + Rec2020 原色→P3 主导通道精确 + **checker E3 双态**（恒等路径 == 输入 ±0.01 + 双重编码可检性反向断言 >0.1 + 默认路径恰一次转换）+ fence（GUI-22 测法：未等待 dispatch 后立即出口渲染观察全平面）+ 行序契约（CI 读回镜像复位钉死） |
| T3 五原生 encoder + golden | `ExportEncoder.swift`（协议/注册表/色彩空间映射/平面类型）+ `ImageIOEncoders.swift`（JPEG/PNG/TIFF/HEIC/AVIF）+ `AppError.encodeFailed`（additive）+ encoder 段 goldens | `c14295c` | 5 tests：PNG/TIFF 8\|16 逐位（×none/lzw/zip 三压缩全过）+ JPEG/HEIC/AVIF 已知点带 + EXIF round-trip 五格式（properties 路径）+ DPI + ICC profile 名逐格式 + XMP 缺席反向锚 + 奇数尺寸 33×17 精确回读 + HEIC 10-bit depth==10 + AVIF 10/12-bit 探针（12→R1 降级钉 10）+ TIFF 32f 1-ULP 数值恒等（线性 Rec2020 profile）+ TIFF Software 签名载体 |
| T4 WebP encoder + golden | `WebPEncoder.swift` + `WebPEncoderTests.swift` | `44d05d6` | 5 tests：lossless 逐位 round-trip（37×19 随机平面，WebPDecoder 归一）+ lossy 已知点（±7 带）+ 奇数尺寸 + quality→effort 折算向量 + **RIFF chunk walk 元数据缺席结构锚**（OQ-11-5）+ 注册表 tier guard |
| T5 注册表 + UTI 锚 | `ExportEncoderGoldenTests` Section 3 | `0d759d9` | 4 tests：UTI 写能力常驻锚（五原生在/webp 不在，双向漂移即红）+ 六格式 13 组合分派类型校验 + expectedLayout 对齐 + tier 不匹配六向量 typed throw + 32f 线性变体边界（adobeRGB/proPhoto typed throw） |
| T6 收尾 | 本文件 + DECISIONS + TODO + PROGRESS log + LESSONS L029 | T6 本提交 | 全 suite **1220/6skip/0fail**（322.9s） |

## 六格式 × 断言矩阵（T3/T4/T5 证据汇总）

| 格式 | 位深 | 像素断言 | ICC 嵌入 | EXIF | DPI | XMP | 奇数尺寸 |
|---|---|---|---|---|---|---|---|
| JPEG | 8 | 有损带 + 已知点 | ✅ "sRGB…" | ✅ properties 路径 | ✅ 144 | ❌（反向锚） | ✅ 33×17 |
| PNG | 8/16 | **逐位** | ✅ | ✅ | ✅ | ❌（反向锚） | ✅ |
| TIFF | 8/16/32f | 8/16 逐位；32f 1-ULP 恒等 | ✅（32f = 线性变体） | ✅ | ✅ | ❌（反向锚） | ✅ |
| HEIC | 8/**10** | 有损带 + 已知点 | ✅ | ✅ | ✅ | ❌（反向锚） | ✅ 33×17 |
| AVIF | 8/10/**12→10（R1 降级）** | 有损带 + 已知点 | ✅ | ✅ | ✅ | ❌（反向锚） | ✅ 33×17 |
| WebP | 8 | lossless **逐位**/lossy 带 | ❌（OQ-11-5 例外） | ❌（例外） | ❌ | ❌（RIFF 结构锚） | ✅ 33×17 |

**位深探针终值（R1）**：HEIC 10 ✅（16bpc 源直达 depth=10）；AVIF 10 ✅；
**AVIF 12-bit 请求落 10-bit**（`l12p` fourcc 无效）→ 文档化降级 + `AVIFEncoder`
conformer 缝保留 + golden 锚钉（宿主能力变化即红）。

**XMP 终判（R5）**：三途径（源 metadata 整体替换 / fresh mutable /
`CGImageMetadataCreateFromXMPData` 真包解析）× 五格式全不序列化（字节级验证）；
`kCGImageDestinationMetadata` 在本机连 EXIF 都不序列化（merge 同）→ EXIF
round-trip 改走 **properties dict 路径**（五格式全通）。CreatorTool 载体 =
TIFF Software tag（唯一活口）；rating/flag = Phase 12 面临时挂空。

## Verification 对照

| 验收面 | 判据 | 结果 |
|---|---|---|
| 量化链 | `Scripts/test-direct.sh 'ExportQuantizerTests'` | ✅ 12/12 |
| 出口腿 | `Scripts/test-direct.sh 'ExportEncoderGoldenTests'`（出口段 7） | ✅ 7/7 |
| 五原生格式 | 同上（encoder 段 5 + 锚段 4） | ✅ 9/9 |
| WebP | `Scripts/test-direct.sh 'WebPEncoderTests'` | ✅ 5/5 |
| 锚 | `Scripts/test-direct.sh 'ExportEncoderGoldenTests'`（UTI 锚在内） | ✅ |
| 回归 | 全 suite 0 fail（1187 → N） | ✅ **1220/6skip/0fail** |

## 执行期发现（新知，均已入 DECISIONS）

1. **HEAD 编译破裂**（D0）：11-01 验收 fix 的穷尽 switch 漏自迁移 case——每笔
   验收后首构建即暴露，独立 fix 提交。
2. **CI 纹理读回垂直镜像**（D6/L029）：`CIImage(mtlTexture:)` 底向上读 + 渲染
   顶向下写 = 纯 vflip；出口腿内复位并锚死。**姊妹 `convertTexture` 同病未修**
   （colorout fallback 腿休眠缺陷，范围外——修复需 GUI 走查兜底，移交）。
3. **XMP 全格式不序列化 + metadata API 整体失效**（D3）：RESEARCH §1.3-1 的
   事实修正在本机进一步加深——EXIF 的唯一活路是 properties dict。
4. **ColorSync float 域行为**：out-of-gamut 通道以近线性负值透传（不钳不编），
   量化器独占饱和（角点测试改为主导通道精确 + 支配序）。
5. **TIFF 32f 1-ULP**（D7）：float 路径 bitwise 不可达，1e-6 带（16× 余量）。
6. **系统线性 ICC 变体只有 sRGB/P3/Rec2020**（D2）；ProPhoto = ROMM 系统档案
   （D1）；typed overlay 缺 ROMM/ITUR_2020 成员 → mapper 走 raw 常量。

## AC 自检（plan 验收标准逐条）

- [x] 量化链三域分层 + `roundf` 同 dt + chroma 不裁语义（出口先转换后钳）golden 钉死（ExportQuantizerTests 12）
- [x] 出口腿 `renderToEncodedBitmap`：fence 挂 pool 队列 + `cacheIntermediates:false`（init 处）+ 直出 CPU buffer + sourceColorSpace 双态（恒等 vs 默认，反向断言钉死）+ COLOR-2 已知点并入（中性灰/sRGB 0.5→187-188）
- [x] 六格式 encoder 齐备（JPEG quality/PNG 8|16/TIFF 8|16|32f×3 压缩无 JPEG-in-TIFF/HEIC 8|10 探针/AVIF native 12-bit 探针/WebP lossy+lossless）；**零新增 SPM 依赖**（Swift-WebP 11-01 已入）
- [x] 每格式 golden round-trip：像素（逐位/有损容差+已知点）+ ICC == 目标 + EXIF tag round-trip + DPI + XMP 存在性逐格式矩阵（实测全缺席 → 反向锚 + 文档化，properties 路径 EXIF 全通）
- [x] WebP 元数据 v1 文档化例外落地（OQ-11-5）+ mux 探测结论入 DECISIONS（零 mux 面 + RIFF 结构锚）
- [x] UTI 回归锚测试在册（public.avif 在/WebP 不在）；R1 位深终值钉 DECISIONS（HEIC 10 / AVIF 10 / 12→10 降级）
- [x] 全 suite 0 fail（1220/6skip）；每任务独立提交 ×6（含 D0 前置 fix）+ 边界查开关 ×6；不 push；fixture 全在临时目录（goldenDir()/NSTemporaryDirectory + teardown 清理）；SUMMARY + DECISIONS 落盘

## 新增测试计数

ExportQuantizerTests 12 + ExportEncoderGoldenTests 16（出口 7 + encoder 5 + 锚段 4）+ WebPEncoderTests 5 = **33**（1187 → 1220）。

## 遗留 / 移交下波（非阻塞）

- **`convertTexture` 潜在垂直镜像**（D6/L029）：colorout ColorSync fallback 腿
  休眠缺陷（fast path 不经它），修复 = 同款 `.downMirrored` + 双腿 parity 内容
  级测试 + GUI 走查——建议 11-05 收口批或独立 fix plan 处置，非 11-02 义务。
- XMP 面（CreatorTool/rating/flag）：宿主 API 全断 → Phase 12 元数据面复审时
  裁（自写 XMP mux / 第三方 / 放弃内嵌）；TIFF Software 载体已通。
- AVIF 12-bit：宿主封顶 10-bit；libavif 路线 = 需求出现时经 `AVIFEncoder`
  conformer 替换位引入（11-02-DECISIONS D12）。
- `ExportRenderArtifact` 真载荷（11-01 D3 预告）= 11-04 接线时换
  `ExportQuantizedPlane` 身份。
- 11-03 消费注意：出口腿已是「bitmap 行序 == 纹理行序」契约，导出链 colorout
  target 覆写后传**目标 colorSpace** 进 `sourceColorSpace:` 即恒等语义（双态
  测试已钉两侧）。

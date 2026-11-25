# CIRAW9 × Sony A7R5 真实性验证

- 日期：2026-11-25
- 仓库 HEAD：`9fd17bb418bcace322557c73dfa667ef4eb13db9`（验证开始时亲核；产品树零改动）
- 机器：macOS 27.3 / build 26C5035r（arm64）、Xcode 27.0 / 27A266a、Swift 6.4
- 探针：`.work/gsd/phases/rawspeed-backend/raw9-probe.swift`（`/tmp/raw9probe`）
- 参考实现：`.work/gsd/phases/rawspeed-backend/raw9-lrmean.cpp`（LibRaw 通道均值）
- 证据：`evidence/raw9-*.csv`、`evidence/raw9-*.txt`（均为文本；用户文件只用别名）
- 隐私：用户实拍文件只做本机只读 EXIF/解码；图像字节与缩略图未写入任何报告、日志或 commit；报告只含别名、型号、固件、字节数、受支持版本、耗时、差值统计

## §0 结论头

**有。在 macOS 27.3 / 26C5035r 上，RAW 9（`CIRAWDecoderVersion.version9`）真的在解码 Sony A7R5 原片；它不是被静默降档的 v8。**

一句话证据链：

1. 13 个 A7R5 原片（固件 v1.00 / v3.00 / v4.00；lossless compressed、lossy compressed、uncompressed、S35 uncompressed）逐文件 `supportedDecoderVersions` 全部为 `v7,v8,v9`；强设 v9 后 `filter.decoderVersion` 读回 `9`，渲染耗时 3.05–3.24 s，而同文件 v8 为 0.70–0.78 s（3.9–4.4×），输出像素**不**逐位相同（max |Δ| 0.009–0.826，mean |Δ| 4.7e-5–6.7e-3 in linear float）。
2. 反向对照 GFX100S（逐文件只有 `v7,v8`）强设 v9 → 读回仍为 `8`、输出与显式 v8 **逐位相同**、耗时相同（762 vs 775 ms）。这证明本方法能检出“静默降档”；A7R5 的观测不是这种签名。
3. 阳性对照 X-T5（RAW 9 名单内）v9 1.609 s vs v8 0.428 s（3.76×），输出明显不同——本方法能检出真实的 v9。
4. DNG 包装路径同样成立：同一 A7R5 马赛克做 DNG 后 `v6dng,v7dng,v8dng,v9dng`；v9dng 2.974 s vs v8dng 0.252 s（11.8×），像素不同。
5. 旧记录里的“v9 经色彩管理后绿通道 G/R≈3.9×”缺陷在本机 27.3 的产品色彩形状下**不复现**：v9dng G/R=1.2162（v8dng 1.2076，LibRaw 线性参考 1.3367）。

**置信度：高**（对 26C5035r + 上述 13 个 A7R5 文件 + 原片/DNG 两条路径）。
**适用范围：** macOS 27.3 26C5035r、A7R5 原片 ARW（含 lossless/lossy/uncompressed/S35）与 rawspeed DNG 包装路径。
**不覆盖：** macOS 27.0.1（darktamer 的另一台/另一构建）以及 darktamer 当时使用的具体文件；本机无法复现“A7R5 逐文件只有 v7,v8”的记录。

## §1 T1 逐文件受支持版本

### 1.1 方法

- 逐文件：`CIRAWFilter(imageURL:)` → `supportedDecoderVersions`（打印字符串与 rawValue）。
- 类级：`CIRAWFilter.supportedCameraModels(with: .version8)` 与 `.version9`。
- 匹配三档：
  - **eq**：列表条目与 EXIF Model **整串相等**；
  - **substr**：列表条目 **包含** EXIF Model 子串（大小写敏感）；
  - **loose**：去空格/点/连字符/下划线并大写后，归一化相等或互相包含。
- 类级计数：version8 = **465** 台，version9 = **69** 台。

### 1.2 关键匹配事实（A7R5）

- v8 名单有 `Sony Alpha ILCE-7RM5`：substr / loose 命中。
- v9 名单**没有** `ILCE-7RM5` 字样；A7R5 在 v9 名单里的条目是 **`Sony Alpha ILCE-7R V`**。
- 对 EXIF Model `ILCE-7RM5`：v9 的 eq、substr、loose **三档全部不命中**（归一化后 `SONYALPHAILCE7RV` vs `ILCE7RM5`，尾段是 `V` 不是 `M5`）。
- 这是**营销名 vs 机身代码**的别名：`ILCE-7R V` = A7R V = `ILCE-7RM5`（Mark 5 = V）。任何只按型号字符串匹配类级名单的查询都会得到“A7R5 不在 v9 名单”的假否定。

同一张表也说明宽松匹配不可靠：

- `GFX100S` 的 v8 substr 会命中 `Fujifilm GFX100S II`（另一台机）；
- `Canon EOS R10` 的 v9 loose 会命中 `Canon EOS R` / `Canon EOS R1`（前缀污染）；
- `NIKON Z 8` 只有 loose 命中 `Nikon Z8`（空格差异）。

**因此：逐文件 `supportedDecoderVersions` 才是权威信号；类级名单既不是必要条件也不是充分条件。** 本机实测 Canon R10 不在 v9 类级名单，但逐文件有 v9，且强设 v9 真的运行（1.256 s vs v8 0.257 s，像素不同）。

### 1.3 CC0 集（`~/Library/Application Support/Lightamer/TestRAW/`）

目录共 9 个文件；其中 7 个 RAW，另有 `Nikon_Z8_raw_14_bit_lossless_compression-preview2.tif` 与 `...-preview4.jpg` 两个非 RAW 预览件，未纳入 T1。

| 文件 | Make | Model | Software | 字节 | 逐文件 supported | v8 eq / substr / loose | v9 eq / substr / loose |
|---|---|---|---:|---|---|---|---|
| 7RM5-LosslessCompressedLarge.ARW | SONY | ILCE-7RM5 | ILCE-7RM5 v1.00 | 85,950,464 | v7,v8,v9 | — / Sony Alpha ILCE-7RM5 / 同左 | — / — / — |
| ColorChecker.ARW | SONY | ILCE-7RM4 | ILCE-7RM4 v1.10 | 123,197,440 | v7,v8,v9 | — / Sony Alpha ILCE-7RM4, Sony Alpha ILCE-7RM4A / 同左 | — / — / — |
| 5G4A9394-compressed-lossless.DNG | Canon | Canon EOS 5D Mark III | Adobe DNG Converter 9.8 (Windows) | 23,206,642 | v6dng,v7dng,v8dng,v9dng | Canon EOS 5D Mark III / 同左 / Canon EOS 5D, 5D Mark II, 5D Mark III | Canon EOS 5D Mark III / 同左 / 同左 |
| DSCF0021.RAF | FUJIFILM | X-T5 | Digital Camera X-T5 Ver1.00 | 43,113,376 | v7,v8,v9 | — / Fujifilm X-T5, X-T50 / 同左 | — / Fujifilm X-T5, X-T50 / 同左 |
| Fujifilm-GFX100S-14bits-uncompress-4_3.RAF | FUJIFILM | GFX100S | Digital Camera GFX100S Ver1.00 | 210,059,904 | v7,v8 | — / Fujifilm GFX100S, GFX100S II / 同左 | — / — / — |
| IMG_4276.CR3 | Canon | Canon EOS R10 | — | 31,010,650 | v7,v8,v9 | Canon EOS R10 / Canon EOS R10 / Canon EOS R, R1, R10 | — / — / Canon EOS R, R1 |
| Nikon_Z8_raw_14_bit_lossless_compression.NEF | NIKON CORPORATION | NIKON Z 8 | Ver.01.00 | 60,842,580 | v7,v8,v9 | — / — / Nikon Z8 | — / — / — |

补充：ColorChecker.ARW 是 **ILCE-7RM4**，不是 A7R5；它逐文件也有 v9，但 v9 类级名单里没有 7RM4 字面条目（与 Canon R10 同类的“类级名单不完整”现象）。

### 1.4 用户实拍库（20 个文件，只读；别名）

抽取口径：5 个顶级类目、12 个不同拍摄日期、20 个文件；其中 11 个 ILCE-7CR、9 个 ILCE-7RM5。软件字段只报固件版本号。

| 别名 | Model | 固件 | 字节 | 逐文件 supported | v8 substr | v9 substr |
|---|---|---|---:|---|---|---|
| USER-01 | ILCE-7CR | v2.00 | 72,011,776 | v7,v8 | Sony Alpha ILCE-7CR | — |
| USER-02 | ILCE-7CR | v2.00 | 68,579,328 | v7,v8 | 同左 | — |
| USER-03 | ILCE-7CR | v2.00 | 68,972,544 | v7,v8 | 同左 | — |
| USER-04 | ILCE-7CR | v2.00 | 69,353,472 | v7,v8 | 同左 | — |
| USER-05 | ILCE-7CR | v2.00 | 33,243,136 | v7,v8 | 同左 | — |
| USER-06 | ILCE-7RM5 | v3.00 | 70,098,944 | v7,v8,v9 | Sony Alpha ILCE-7RM5 | — |
| USER-07 | ILCE-7RM5 | v3.00 | 71,073,792 | v7,v8,v9 | 同左 | — |
| USER-08 | ILCE-7RM5 | v3.00 | 65,892,352 | v7,v8,v9 | 同左 | — |
| USER-09 | ILCE-7RM5 | v4.00 | 59,027,456 | v7,v8,v9 | 同左 | — |
| USER-10 | ILCE-7RM5 | v4.00 | 72,925,184 | v7,v8,v9 | 同左 | — |
| USER-11 | ILCE-7RM5 | v4.00 | 68,337,664 | v7,v8,v9 | 同左 | — |
| USER-12 | ILCE-7RM5 | v3.00 | 71,028,736 | v7,v8,v9 | 同左 | — |
| USER-13 | ILCE-7CR | v1.00 | 69,214,208 | v7,v8 | 同左 | — |
| USER-14 | ILCE-7CR | v2.00 | 76,161,024 | v7,v8 | 同左 | — |
| USER-15 | ILCE-7CR | v2.00 | 68,485,120 | v7,v8 | 同左 | — |
| USER-16 | ILCE-7CR | v2.00 | 72,171,520 | v7,v8 | 同左 | — |
| USER-17 | ILCE-7CR | v2.00 | 70,447,104 | v7,v8 | 同左 | — |
| USER-18 | ILCE-7CR | v2.00 | 35,168,256 | v7,v8 | 同左 | — |
| USER-19 | ILCE-7RM5 | v3.00 | 69,853,184 | v7,v8,v9 | 同左 | — |
| USER-20 | ILCE-7RM5 | v3.00 | 71,684,096 | v7,v8,v9 | 同左 | — |

**压缩方式说明（重要）：** ImageIO 对全部 Sony ARW 报 `{TIFF} Compression=6`（JPEG 旧式 tag），它**不能**区分 Sony 的 lossless / lossy / uncompressed。上表只给字节数；下表的压缩类别来自 raw.pixls.us 文件命名（公共 CC0 样张）与字节量级，不是从 EXIF 读出的。

为排除“压缩模式/裁切模式”变量，另从 raw.pixls.us 取同一 ILCE-7RM5 的 3 个 CC0 变体（公共样张，非用户照片）：

| 文件 | 字节 | 像素 | 逐文件 supported | 强设 v9 读回 | v8 ms | v9 ms |
|---|---:|---|---|---|---:|---:|
| 7RM5-LosslessUncompressed.ARW | 134,701,056 | 9504×6336 | v7,v8,v9 | 9 | 809.3 | 2777.0 |
| 7RM5-LossyCompressed.ARW | 72,286,208 | 9504×6336 | v7,v8,v9 | 9 | 950.4 | 3037.5 |
| 7RM5-S35-LosslessUncompressed.ARW | 58,249,216 | 6240×4160 | v7,v8,v9 | 9 | 155.5 | 1194.1 |

结论：**固件 v1.00/v3.00/v4.00、lossless/lossy/uncompressed、全幅/S35，全部都有逐文件 v9，且 v9 都真的运行。** 压缩模式与裁切模式不是 darktamer 记录的成因。

## §2 T2 原片上强设 v9 对 v8（决定性实验）

### 2.1 方法

- 同一文件分别以 `decoderVersion = v7 / v8 / v9` 创建新 `CIRAWFilter`（每次 rep 都新建，避免滤镜内缓存）。
- 渲染到 `RGBAf`（32-bit float/通道），颜色空间 = `extendedLinearSRGB`，全分辨率（不缩放）。
- 计时：`CIContext.render(toBitmap:)` 调用前后的单调钟；滤镜创建/元数据读取不计入渲染计时；每版本先热身 1 次，再 5 次计时取中位。
- 像素比较：先 `memcmp`；不等则分块 `vDSP_vsub` + `vDSP_vabs` 求 max/mean |Δ|。
- 读回：设置后与渲染后各读一次 `filter.decoderVersion.rawValue`；`filter.properties` 顶层键扫描（无 version/decoder 键）。

### 2.2 结果（全分辨率）

| 文件 | 像素 | v7 中位 ms | v8 中位 ms | v9 中位 ms | v9/v8 | v9−v8 max \|Δ\| | v9−v8 mean \|Δ\| | 逐位相同 | 读回 before/after |
|---|---|---:|---:|---:|---:|---:|---:|---|---|
| CC0-A7R5-LLC-L | 9504×6336 | 588.2 | 776.5 | 3237.8 | 4.17× | 0.8256 | 6.73e-3 | 否 | 9 / 9 |
| USER-01 | 9504×6336 | 537.4 | 724.5 | 3210.2 | 4.43× | 0.2288 | 1.68e-3 | 否 | 9 / 9 |
| USER-02 | 6336×9504 | 523.2 | 779.6 | 3054.4 | 3.92× | 0.6342 | 2.18e-3 | 否 | 9 / 9 |
| USER-03 | 6336×9504 | 530.0 | 714.6 | 3092.1 | 4.33× | 0.6060 | 6.36e-4 | 否 | 9 / 9 |
| USER-04 | 6336×9504 | 515.5 | 702.9 | 3111.4 | 4.43× | 0.00924 | 4.73e-5 | 否 | 9 / 9 |
| USER-05 | 6336×9504 | 557.5 | 739.3 | 3154.0 | 4.27× | 0.5594 | 3.34e-3 | 否 | 9 / 9 |

（差值单位 = linear float，0…1 量级；`maxAD255` 见 `evidence/raw9-diffs.csv`。）

判据与判定：

- 判据：v9 与 v8 **逐位相同**，或差异只在 **1e-6** 量级 → 视为没有真的运行 v9。
- 实测：6 个文件全部**不逐位相同**；mean |Δ| 最小 4.73e-5（USER-04 是一张极暗帧），最大 6.73e-3；max |Δ| 0.009–0.826。最小差异仍比 1e-6 高 47×，且与 v8 的耗时差 3.9–4.4×。
- **判定：A7R5 原片的 v9 真的运行，不是降档。**

旁证细节：

- v7 vs v8 也有非零差异（mean 3.45e-5–4.25e-3），说明这条渲染路径对版本变化是敏感的，不是“所有版本都同一输出”。
- 所有 rep 的 `readback_before` 与 `readback_after` 都是请求的版本；没有 nil output；没有“设置 9、读回 8”的降档签名。
- `filter.properties` 顶层键只有 `ColorModel, Depth, Orientation, PixelHeight, PixelWidth, ProfileName, {ExifAux}, {Exif}, {IPTC}, {PictureStyle}, {TIFF}`；**没有**“实际使用版本”这类输出键。版本只能靠 `decoderVersion` 读回 + 行为（耗时/像素）判定。

### 2.3 反向对照（方法有效性）

GFX100S（逐文件 `v7,v8`，v9 类级名单也没有它）：

| 请求版本 | 读回 before | 读回 after | 中位 ms | 与显式 v8 的像素 |
|---|---|---|---:|---|
| v8 | 8 | 8 | 774.9 | 基准 |
| v9 | **8** | **8** | 762.1 | **逐位相同**（max/mean = 0） |

这正是 darktamer 描述的“静默降档”签名：设置 v9 → 读回 8 → 输出与 v8 逐位相同 → 耗时不变。**本方法能检出它；A7R5 的观测与它相反。**

## §3 T3 DNG 包装路径

### 3.1 生成与版本

- 用 spike 的 `rs2dng` 从 CC0 A7R5 原片（`7RM5-LosslessCompressedLarge.ARW`）重建无压缩 CFA DNG：`9568×6376`、`122,011,840` 字节、`mosaic_fnv1a64=0xbd81df79e1a15f93`（与 SPIKE.md 记录一致，证明是同一马赛克）。
- 逐文件版本：`v6dng,v7dng,v8dng,v9dng`；默认 `v8dng`；强设 `v9dng` 读回 `9.dng`。

### 3.2 像素与耗时（全分辨率，5 次中位）

| 版本 | 中位 ms | min / max ms | 读回 | 与对方 max \|Δ\| | mean \|Δ\| | 逐位相同 |
|---|---:|---|---|---:|---:|---|
| v8dng | 252.3 | 237.4 / 265.7 | 8.dng | — | — | — |
| v9dng | 2974.2 | 2941.3 / 3092.9 | 9.dng | 0.6296 | 4.20e-3 | 否 |

v9dng/v8dng = **11.8×**；与 spike 的“v9DNG 稳态 ~2.7 s、v8DNG ~0.18 s”同量级，且这次是 5 次中位 + 显式读回。

### 3.3 颜色健全性（产品色彩形状）

两套形状都测：

1. **产品 `CIContextPool` 形状**（`workingColorSpace = outputColorSpace = linear Rec2020`、`workingFormat = RGBAh`、`cacheIntermediates = false`），渲染到 `RGBAf`/linear Rec2020，fit 2560；
2. 普通 `extendedLinearSRGB`，全分辨率。

| 路径 / 形状 | 版本 | 中位 ms | R 均值 | G 均值 | B 均值 | G/R | B/R |
|---|---|---:|---:|---:|---:|---:|---:|
| DNG / Rec2020（产品形状，fit 2560） | v8dng | 211.6 | 0.250468 | 0.302458 | 0.089559 | 1.2076 | 0.3576 |
| DNG / Rec2020（产品形状，fit 2560） | v9dng | 2625.0 | 0.249614 | 0.303586 | 0.087220 | **1.2162** | 0.3494 |
| DNG / extLinearSRGB（全分辨率） | v8dng | 252.3 | 0.231734 | 0.310807 | 0.065367 | 1.3412 | 0.2821 |
| DNG / extLinearSRGB（全分辨率） | v9dng | 2974.2 | 0.229962 | 0.312375 | 0.062752 | **1.3584** | 0.2728 |
| A7R5 原片 / Rec2020（产品形状，fit 2560） | v8 | 1212.9 | 0.283483 | 0.368624 | 0.123719 | 1.3003 | 0.4364 |
| A7R5 原片 / Rec2020（产品形状，fit 2560） | v9 | 3163.9 | 0.284160 | 0.372173 | 0.123168 | **1.3097** | 0.4334 |
| **LibRaw 独立参考**（原片，linear sRGB，camera WB，AHD，no auto bright） | — | — | 0.124589 | 0.166541 | 0.043098 | **1.3367** | 0.3459 |

判读：

- **G/R≈3.9× 的旧缺陷不复现。**v9dng 在产品形状下 G/R=1.2162，v8dng=1.2076，两者差 0.7%；原片 v9=1.3097 vs v8=1.3003，差 0.6%。若存在 3.9× 绿偏，v9 的 G/R 应在 4.7 左右（v8 的 1.21×3.9），或至少与 v8 有数倍差距。
- v9dng 的 G/R 与 LibRaw 参考（1.3367）在 9% 内；绝对均值差异来自 CIRAW 默认 tone curve/boost（本探针没有把 boost 归零），因此**只比较比值，不比较绝对值**。
- B/R：v9dng 0.349（产品形状）/0.273（全分辨率），参考 0.346；没有通道塌陷或互换。全分辨率与产品形状的 B/R 差异来自 `RGBAh` 中间格式与 fit 缩放，量级正常。
- 结论：**v9DNG 路径当前没有 `RAWDecoder.swift` 注释里那个绿通道偏色缺陷**；该注释是旧构建/旧探测形状的历史记录，不应继续作为禁用 v9 的唯一理由（但仍需用真实显示器/导出台再验一次）。

### 3.4 资源

- T3 全分辨率双缓冲 2×976 MB，`/usr/bin/time -l` 峰值 RSS = **5.36 GB**；单文件串行，未触发 machine-guard 的 8/9 GB 线。

## §4 T4 阳性对照

CC0 集内存在阳性对照：**Fujifilm X-T5**（`DSCF0021.RAF`，逐文件 `v7,v8,v9`，v8/v9 类级名单的 loose 命中均为 `Fujifilm X-T5`）。

| 版本 | 中位 ms（5 次，fit 2560） | 读回 |
|---|---:|---|
| v7 | 294.4 | 7 |
| v8 | 427.8 | 8 |
| v9 | **1608.7** | 9 |

- v9/v8 = **3.76×**；v9−v8 max |Δ| = 0.3140，mean = 2.28e-3，非逐位相同。
- 这就是“真实的 v9”在本方法下的签名：读回 9 + 数倍耗时 + 非零像素差。
- 附加佐证：Canon EOS R10（逐文件 `v7,v8,v9`，但**不在** v9 类级名单）v9=1.256 s vs v8=0.257 s（4.9×），像素不同；再次说明逐文件列表才是权威。

**阳性对照存在，因此 T2 的“有差异 + 数倍耗时”结论不需要降级表述。**

## §5 产品怎么选版本（只读走查）

### 5.1 选择逻辑（`LightamerCore/Sources/Decode/RAWDecoder.swift`）

- `DecoderRequest`：`automatic` / `forceV8` / `forceV9`（:43-47）。
- `resolveDecoderVersion`（:266-295）：
  - `forceV8` → v8；
  - `forceV9` → 仅当 `isRAW9Available`（macOS 27+）且逐文件 `supported` 含 `version9` 时返回 v9，否则 v8；
  - `automatic` → **恒 v8**（V2M-01 T2 / defect D-2，:276-291）。
- 真实滤镜：`CIRAWFilter(imageURL: url, options: options)`（:199），`filter.decoderVersion = requested`（:202）。
- `decoderVersionUsed`：在创建滤镜前由 `requested == .version9` 直接置为 `.v9`（:182-185），**没有**在渲染后读回 `filter.decoderVersion`。
- 日志：`EditorState.swift:597` 打 `decoded <file> v<decoderVersionUsed>`；sidecar 也写同一字段（`PipeCoordinator.swift:1926`）。
- 降档提示：`RawDecodePanelView.swift:290-294` 的 `showsV9DowngradeHint` 只在 `versionRequest == .forceV9 && decoderVersionUsed == .v8` 时显示——它依赖的也是上面那个“请求值”，不是运行时读回。

### 5.2 A7R5 的实际选择

- 默认 `automatic` → **v8**。
- 用户显式 `forceV9` → A7R5 逐文件列表含 v9，所以请求 v9；本机实测该请求会真的得到 v9（读回 9，3.1–3.2 s）。
- **没有“降档日志”这种东西**：只有一个 os_log 行记录合成后的 `decoderVersionUsed`，以及一个面板提示。两者都不能发现“逐文件列表说 v9、但运行时静默降回 v8”的极端情况；当前 A7R5 不存在这种情况，但这是产品记录真实性的一个缺口。

### 5.3 GUI 1.57 s 更像哪个版本

`GUI-lightamer.md:12` 的 A7R5 点击→preview 中位 **1.57 s**（1.53/1.59），同报告 :16 明写“CIRAW v8”。本探针：

- v8 在 2560 fit 的纯渲染：0.70–1.21 s（本机文件/形状不同）；
- v9 在 2560 fit 的纯渲染：**3.05–3.24 s**（全分辨率也一样，v9 的 CoreML 成本与输出尺寸关系不大）。

1.57 s 的总链路（含 30 个 IOP 平面、装配、overlay）不可能是 v9；**更像 v8**，且与产品的 `automatic → v8` 一致。

## §6 两条旧记录为什么对不上

### 6.1 已排除的差异

| 假设 | 实测 | 结论 |
|---|---|---|
| 固件差异（v1 vs v3/v4） | v1.00（CC0 + 3 个下载变体）、v3.00、v4.00 全部 v7,v8,v9 | 排除 |
| 压缩模式（lossless vs lossy vs uncompressed） | LLC-L、lossy、uncompressed、S35 uncompressed 全部 v7,v8,v9，强设 v9 均运行 | 排除 |
| 全幅 vs S35 裁切 | 两者都 v7,v8,v9；S35 v9 1.19 s vs v8 0.16 s | 排除 |
| 默认版本 = v8 说明“v9 没启用” | X-T5（确定支持 v9）默认也是 v8；v9 是显式 opt-in | 排除 |
| 新旧 API 路径 | `CIRAWFilter(imageURL:)`、`CIRAWFilter(imageURL:options:)`（产品路径）、旧 `CIFilter(imageURL:options:)` 三者都能读 v9/运行 v9 | 排除（见下条例外） |
| `CIRAWFilter(imageData:)` 单参 | 返回私有 `CIRAWFilterImpl`，**没有** `decoderVersion` / `supportedDecoderVersions` selector；访问会崩，不会给出 v7,v8 | 排除为“v7,v8”来源 |
| 类级名单 strict/loose 匹配 | v9 名单的 A7R5 条目是 `Sony Alpha ILCE-7R V`，对 `ILCE-7RM5` 三档匹配全不中；v8 名单有 `Sony Alpha ILCE-7RM5` | **最可能的假否定来源** |
| 逐文件 vs 类级 | Canon R10 不在 v9 类级名单但逐文件有 v9 且真的运行；A7R4 同样 | 类级名单不能当逐文件判据 |

### 6.2 最可能的原因

1. **查询面混用（最可能）**：darktamer 的记录说“逐文件 `supportedDecoderVersions` 只有 v7,v8”，但其可复现的字符串事实是——**v9 类级名单只有 `Sony Alpha ILCE-7R V`，没有 `ILCE-7RM5`；v8 名单两者都有**。任何按 EXIF Model 对类级名单做严格/宽松匹配的探针，都会得到“A7R5 无 v9、只有 v8”。这与记录的现象逐字吻合。若他们的探针实际读的是类级名单（或把类级名单结果写成了逐文件结论），就会得到该记录。
2. **构建差异（不能排除）**：darktamer 先在 macOS 27.0.1 测，后在 27.3 beta 1 26C5035r 测。本机是 27.3 26C5035r，结论是“有 v9”。27.0.1 我们没有机器/构建，无法验证；如果 27.0.1 真的没有 A7R5 的 v9，而 27.3 的复测又沿用了旧文件/旧结论，就会留下这条记录。
3. **文件差异（可能性低）**：我们已覆盖 A7R5 的 13 个文件、4 种压缩/裁切形态、3 个固件，找不到“逐文件只有 v7,v8”的 A7R5。若 darktamer 手里的文件是某种我们没拿到的变体（例如第三方转封装、损坏/截断、或非零售固件的工程样机），才可能不同；需要他们提供文件哈希与 `CIRAWFilter` 探针源码才能定案。
4. **“静默降档 + 逐位相同”本身是真的**：在 GFX100S 这类逐文件只有 v7,v8 的文件上，我们完整复现了该签名。darktamer 的描述作为**机制**没有错；错的是把它归到了 A7R5 的逐文件能力上。

### 6.3 给后续的判定口径

- 判断某机型是否有 RAW 9：**只信逐文件 `CIRAWFilter.supportedDecoderVersions`**；类级 `supportedCameraModels(with: .version9)` 只能当参考，且必须处理营销名/机身代码别名（`ILCE-7R V` ↔ `ILCE-7RM5`）与子串污染（`GFX100S II`、`Canon EOS R1`）。
- 判断 v9 是否真的运行：**三件套**——`decoderVersion` 读回 = 9、耗时呈 v9 特征（本机 A7R5 约 3.1 s，v8 约 0.7 s）、输出与 v8 非逐位相同。只看 `supportedDecoderVersions` 不够；只看耗时也不够；只看像素差可能是 v7/v8 的正常差异。

## §7 风险与未验项

1. **darktamer 的原始文件未拿到**：无法对他们的具体文件做逐字节复现；§6 的“查询面混用”是强假设，不是已证事实。
2. **macOS 27.0.1 未测**：本机只有 27.3 26C5035r；27.0.1 的行为可能不同。
3. **“真的 RAW 9”是行为级证据**：读回 9 + CoreML 级耗时 + 像素差 + 反向对照，足以判定“v9 管线在跑”；但没有内部 instrumentation 证明跑的是 A7R5 专用模型而不是通用 v9 模型。v9 类级名单含 `Sony Alpha ILCE-7R V`，支持“专用”判断。
4. **色彩检查的形状**：用了 `CIContext.render(toBitmap:)` + 产品 `CIContextPool` 的 working/output/format 选项，但没有走产品真正的 Metal texture 渲染链；G/R 3.9× 缺陷是否在 texture 路径的某个角落复现，仍需真实 App 出图复核（本报告只能判定“当前探针形状不复现”）。
5. **用户样本量**：9 个 A7R5 用户文件、6 个拍摄日期、v3/v4 两种固件；文件命名前缀不止一种，无法在不读序列号的前提下确认是否同一机身，不能代表所有 A7R5 机身/固件。
6. **L/M/S lossless 只测了 L（全尺寸）**；M/S 的逐文件 v9 未测（raw.pixls.us 有 M/S 文件，未下载）。S35 uncompressed 已测。
7. **内存**：全分辨率双缓冲峰值 5.36 GB；若未来并行多文件会超 machine-guard 线，必须串行。
8. **模型资源**：本机 v9 运行成功，说明所需资源已在位；未测 `downloadResources` 的离线/联网行为。
9. **USER-04 是极暗帧**：其绝对差值小（mean 4.7e-5），但耗时 4.4× + 读回 9 仍足以判定 v9 运行；不要只引用该行的绝对差值。
10. **隐私**：用户文件只出现在本地路径与别名映射中；报告/CSV/日志不含文件名、路径、作者、GPS、序列号。

## §8 issue #24 评论草稿（English）

```markdown
## RAW 9 on Sony A7R5: verified on macOS 27.3 (26C5035r); the earlier "v8-only" record does not reproduce

Tested at HEAD `9fd17bb` with a dedicated CIRAWFilter probe (per-file `supportedDecoderVersions`, forced `decoderVersion` read-back, full-resolution float32 pixel diff, 5-rep medians).

**Result.** 13 A7R5 files (firmware v1.00 / v3.00 / v4.00; lossless-compressed, lossy-compressed, uncompressed, S35 uncompressed) all report `v7,v8,v9` per file. Forcing v9 reads back `9`, renders in 3.05–3.24 s vs 0.70–0.78 s for v8 (3.9–4.4x), and the output is not bit-identical (max |Δ| 0.009–0.826, mean 4.7e-5–6.7e-3 in linear float). The DNG path is the same: `v6dng…v9dng`, v9dng 2.974 s vs v8dng 0.252 s (11.8x), pixels differ.

**Controls.** GFX100S (per-file `v7,v8` only) forced to v9 silently clamps back to `8`, is bit-identical to v8, and has the same render time — i.e. the exact downgrade signature the earlier record describes. X-T5 (a known RAW 9 body) runs v9 in 1.609 s vs 0.428 s and differs in pixels. So the method detects both real v9 and silent downgrade.

**Why the old record likely said "no v9".** The class-level v9 list contains `Sony Alpha ILCE-7R V`, not `ILCE-7RM5`; the v8 list contains `Sony Alpha ILCE-7RM5`. Strict, substring, and normalized matching of the EXIF model against the v9 class list all miss. Per-file capability is the authoritative signal, and the class list is neither necessary nor sufficient (Canon R10 is absent from the v9 class list yet has per-file v9 and really runs it).

**Product.** `automatic` resolves to v8; `forceV9` correctly requests v9 on A7R5. `decoderVersionUsed` is currently derived from the request, not read back from the filter — consider reading `filter.decoderVersion` after `outputImage` so the panel/log cannot claim v9 if a future file silently downgrades. The GUI 1.57 s A7R5 click→preview is v8 (v9 alone is ~3.1 s).

**Colour.** The historical G/R≈3.9x green skew does not reproduce in the product CIContext shape: v9dng G/R 1.216 vs v8dng 1.208 (LibRaw linear reference 1.337). Still worth a real-App export check before re-enabling v9 by default.

Artifacts: `.work/gsd/phases/rawspeed-backend/RAW9-A7R5.md`, `evidence/raw9-*.csv`.
```

## 附录 A：复现命令

```bash
# probe（从仓根）
swiftc -O -o /tmp/raw9probe .work/gsd/phases/rawspeed-backend/raw9-probe.swift

# T1
/tmp/raw9probe info <file...>
/tmp/raw9probe models "ILCE-7RM5"

# T2（原片，全分辨率，5 次中位）
/tmp/raw9probe compare <A7R5.ARW> --versions v7,v8,v9 --reps 5

# T3（DNG）
/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/bin/rs2dng \
  /Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/rawspeed/data/cameras.xml \
  <A7R5.ARW> /tmp/a7r5-raw9-ds0.dng
/tmp/raw9probe compare /tmp/a7r5-raw9-ds0.dng --versions v8dng,v9dng --reps 5

# 产品色彩形状（linear Rec2020 + RGBAh）
/tmp/raw9probe compare /tmp/a7r5-raw9-ds0.dng --versions v8dng,v9dng --reps 1 --fit 2560 --rec2020

# LibRaw 参考
c++ -std=c++20 -O2 -arch arm64 -I/opt/homebrew/include \
  .work/gsd/phases/rawspeed-backend/raw9-lrmean.cpp -o /tmp/lrmean \
  -L/opt/homebrew/lib -lraw
/tmp/lrmean <A7R5.ARW>
```

## 附录 B：证据文件

| 文件 | 内容 |
|---|---|
| `evidence/raw9-t1.csv` | 27 个文件（7 CC0 + 20 用户）的 EXIF、字节、逐文件版本、v8/v9 三档匹配 |
| `evidence/raw9-t1-variants.csv` | 3 个 raw.pixls.us A7R5 变体（uncompressed / lossy / S35） |
| `evidence/raw9-t1-cc0.txt` / `raw9-t1-users.txt` | 探针原始输出（用户文件已替换为别名） |
| `evidence/raw9-runs.csv` | 35 条渲染记录：耗时、读回、均值、G/R |
| `evidence/raw9-diffs.csv` | 28 条两两像素差（bitEqual/max/mean） |
| `evidence/raw9-t2-users.txt` | 5 个用户 A7R5 的全分辨率 5-rep 原始日志（别名） |
| `evidence/raw9-t2-controls.txt` | CC0 A7R5、GFX100S 反向对照、Rec2020 色彩检查 |
| `evidence/raw9-t3.txt` | DNG v8dng/v9dng 全分辨率 5-rep |
| `evidence/raw9-t4.txt` | X-T5 阳性对照 5-rep |
| `evidence/raw9-variants.txt` | 3 个 A7R5 压缩/裁切变体的 v8/v9 对比 |

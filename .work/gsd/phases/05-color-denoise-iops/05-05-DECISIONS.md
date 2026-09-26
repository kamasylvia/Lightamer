# 05-05-DECISIONS.md — Plan 05-05 决策记录

> monochrome（64.0，Lab 色轮 + dt 3D grid bilateral 腿）执行期决策。
> 惯例：推荐可逆且已论证、可审阅推翻（05-CONTEXT 既定授权模式）。

## D1: sigma² 钉 CPU 版（plan 级纪律点，T1）

- **裁决**：kernel 按 CPU 公式 `σ² = 2·(size·128)²`（monochrome.c:205）；
  CL 腿 `σ² = (size·128)²`（:257）记已知偏离（kernel 头注 + manifest）。
- **对照源**：
  - CPU process :204-205：`const float sigma2 = 2.0f * (d->size * 128.0f) * (d->size * 128.0f)`；
  - CL process_cl :257：`const float sigma2 = (d->size * 128.0) * (d->size * 128.0f)`；
  - CL filter kernel（basic.cl:3007）与 apply（:3029）均以 `2.0f * size` 为除数
    （调用方传 sigma2 作 `size` 形参——`/(2·size)`；CPU 腿 `_color_filter`
    :174 以 `dbl_size`（= sigma2CPU）为除数。两者数学形一致
    （`/(2σ²_CL)` vs `/σ²_CPU`，σ²_CPU = 2σ²_CL），分歧即 2× 常数。
- **golden 互证**：dt-cli 无 OpenCL 走 CPU 路径——参考实现与 kernel 均用
  CPU 版；manifest 记录该已知分歧（T3 落账）。
- **证据**：`MonochromeCommitTests`（sigma2CPU(2)=131072 / sigma2CL(2)=65536
  pin + commit uniforms 写 CPU 值）。
- **Reversibility**: reversible — uniforms 常数一切换即 CL 版。

## D2: seed DISABLED（T1）

- **裁决**：monochrome 进 `editingDefaultInstances` 为 DISABLED。
- **论证**：默认参数（a=0, b=0, size=2, highlights=0）非像素恒等——
  size=2 ⇒ σ² 有限 ⇒ filter ≠ 1（除 achromatic 像素外）；highlights=0 ⇒
  t ≡ 1 ⇒ `Lout = F·Lin/100`（标量乘，非恒等）。不存在零参数恒等式
  （filter→1 需 size→∞，非有限参数）——恒等语义只经 disabled piece 成立。
- **同处置先例**：colorbalancergb D1（05-02）/ channelmixerrgb D1（05-03）/
  highpass+soften D11（04-05）。
- **轨 B 论证**：disabled ⇒ `PixelPipe.processRec` 直接跳过（不读 uniforms、
  不占 levelHash）——既有 GeometryGolden 双判据已覆盖（05-02 T5 同论证）；
  显式插入腿恒真故不加（防空转纪律）。
- **Reversibility**: reversible — seed 政策是注册表一行。

## D3: dt_fast_expf vs 精确 exp（T1，divergence 记录）

- **记录**：dt `_color_filter` 用 `dt_fast_expf`（math.h:418-430，~exp——
  0 处 −0.06 偏置，>0 域爆炸；定义域本用例 (−1, 0]）；我方 kernel 与
  float64 参考均用精确 `exp`。
- **量化**：t = 0.0295（warm 默认参数，flat_0ev）时 fast/exact = 0.97993/
  0.97090（相对 +0.93%）；t → 0 时偏置 → −6%（fast(0) = 0.94？实测
  fast(−0.0296) = 0.97993 vs exp = 0.97090——fast 系统性偏大 ~1%）。
- **处置**：parity 门 <1e-3 吸收（实测全链 maxRel ~1e-6——参考与 kernel
  同源精确 exp，门内无 fast 腿）；commit 门 pin fast/exact 上界（in-test，
  非 parity）。
- **Reversibility**: n/a — 单边精度高于 dt，不构成兼容债。

## D4: bilateral grid 步长转置事故（T2/T3，跨 plan 影响）

- **事故**：`BilateralGrid3D` 的 splat/slice 偏移混用了 CL 腿 x-minor 步长
  （ox=1, oy=sizeX, oz=sizeX·sizeY）配 CPU 腿 z-minor 基址
  （base=(xi+yi·sizeX)·sizeZ+zi）——dt CPU 步长（bilateral.c:204-206
  ox=size_z, oy=size_x·size_z, oz=1）vs CL 步长（bilateral.cl:69-71
  ox=1, oy=sizex, oz=sizex·sizey）本是两套自洽布局（z-minor vs x-minor），
  初版混搭。
- **暴露**：monochrome 首个 GPU 消费者——gray_staircase（120px → 7×7×5
  非立方网格）splat 越界（IndexError，Python 镜）；立方网格（5×5×5）
  恰好不越界（max 124 < 125），05-01 测试全绿掩盖。
- **修复**：Swift 参考 + Metal splat/slice + Python 镜三处同步改 dt CPU
  步长（ox=sizeZ, oy=sizeX·sizeZ, oz=1）；blur 腿（闭包 stepping，非
  偏移制）经核对本就正确（x 步长 sz、y 步长 sx·sz、z 步长 1——dt :389-393
  编排一致）。`BilateralGrid3DTests` 5/5 回绿（步长修后，立方门不受影响）。
- **05-01 还账**：D-05-01-T7 网格语义审计补注记（步长制 + 非立方门缺失）。
- **Reversibility**: n/a — 事故修复（单正确值）。

## D5: grid σ scale 折算——CPU max 钳制（T2）

- **裁决**：`MonochromeGridLeg.sigmas` 按 CPU 形
  `scale = max(iscale/roi.scale, 1)`（monochrome.c:220）；CL 形（:260，
  无 max）记偏离（`sigmasCL` pin：PREVIEW 放大侧 σ_s=40 vs CPU 20）。
- **L021 落点**：scale = roi.scale ÷ piece.iscale（05-01 API；禁对 dscIn
  ×scale）；`tileHalo` 取 `ceil(4·σ_s)`（dt tiling_callback :315
  `overlap = ceilf(4*sigma_s)`——plan「≈2σ_s」是欠估计，dt 原文 4σ_s 为准）。
- **Reversibility**: reversible — 标量折叠位置（GridLeg 一函数）。

## D6: dt 三证据——4/4 采纳 + 平场 probe BROKEN-route 定向（T3）

- **采纳**：4 case XMP → `params v. 2: version ok params ok` +
  `successfully loaded module monochrome` + DB op_params hex == XMP blob
  （byte-identical，4/4；证据 `.work/plans/05-05/adoption/`）。
- **平场 probe**：colorin/colorout 在本机构建树 stale（`libcolorin.so`/
  `libcolorout.so` dlopen 符号缺失——05-04 D-T3-4 同族），导出管跑
  monochrome 于未转换域（fixture RGB 直作 Lab：L=0.5, a=b=0.5）。
  - neutral（size=100）：输出 RGB (0.5, 0, 0) 精确——filter→1 + apply 还原
    L=0.5 + a=b=0 强制，BROKEN-route 下仍精确（恒等式与域无关）。
  - warm：输出 R=0.49015（G=B=0 精确）——方向正确（filter<1 压暗），数值
    与任一正路（精确 0.4648 / fast 0.4687）差 ~5%（域错 + fast 双重）。
- **处置**：probe 作 BROKEN-route 定向证据（shadhi 先例 D-05-04-T3-4 同口径；
  R>0/G=B=0 + 压暗方向），不作数值 parity；数值 parity 由合成参考全链
  <1e-6 承载（T3 parity 门）。
- **Reversibility**: n/a — 环境约束记录（dt 重建后补跑）。

## 定值表（T2 tileHalo/摊销，plan 纪律要求）

| 量 | 值 | 依据 |
|---|---|---|
| σ_s（FULL scale=1） | 20 | monochrome.c:222（σ_s=20/scale，CPU max 钳制） |
| σ_r | 250 | monochrome.c:221（与 scale 无关） |
| detail | −1 | monochrome.c:223（基底层） |
| tileHalo | ceil(4·σ_s)=80（FULL） | dt tiling_callback :315（plan ≈2σ_s 欠估计，原文为准） |
| grid dims（FULL 512×384） | 27×20×5=2700 cells | grid_size 直译（05-01 T7） |
| grid bytes（CL 对偶 memory_use） | 2 buffers × cells × 4B = 21600B | bilateral.c:94-96 HAVE_OPENCL 腿 |
| B/px（512×384） | 16 + 21600/196608 → 16（摊销 <1 归零） | tiling_callback :309-310 factor 形 |
| B/px（100MP FULL） | 16 + 10214160/101756928 → 16 | 同上（grid 摊销恒 <1——monochrome 永不触发 tiling？见下） |
| 100MP tile 网格 | halo=80 < tile side（512MB 预算/16B/px → ~5.6k side） | TilingPlan sane（无反转） |

- **注**：grid 摊销恒 <1（grid cells ~ W·H/400）⇒ B/px ≡ 16 ⇒ tiling 触发
  只看 `16·W·H > 512MB`（100MP = 1.6GB > 预算 ⇒ 触发，分块==整幅门已钉
  <1e-3）。05-01 预演占位值（halo=40/B/px=24）正式替换为本表值。

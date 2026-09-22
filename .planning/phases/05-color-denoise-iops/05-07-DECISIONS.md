# Plan 05-07 Decisions — denoiseprofile

> 决策记录（续跑 executor 补全；T1/T2-T4 决策由前任落在本文件同名条目，
> T5/T6 决策为本班新增）。行号锚 = darktable 树 dc58cf0ba1。

## D-05-07-T2-1 — wb_adaptive 实现口径：wb ≡ (1,1,1)（coeffs==0 分支）

dt 读 `pipe->dsc.temperature.coeffs`（temperature 模块通道增益）；Lightamer
管线无 dsc 状态、CIRAW 不暴露解码器内部 WB 增益 ⇒ v1 走 compute_wb_factors
的 coeffs==0 分支（wb 归一为 (1,1,1)，:1230-1236）。完整推导保留参数化
（`wbCoeffs: SIMD3<Float>?`），未来管线级 stamp 接入不改公式。已知分歧，
manifest/模块头注双落账。

## D-05-07-T2-2 — seed 参数：DISABLED（colorbalancergb D1 同处置）

dt 经 auto profile 默认启用 denoiseprofile，但**不存在零参恒等**：force 0.5
⇒ thrs > 0 ⇒ 软阈值必然移动噪声像素；且 auto profile 使默认值图像相关。
恒等只经 disabled piece 成立 ⇒ seed 以 `enabled: false` 入链。

## D-05-07-T5-1 — VST 的 strength 折算分腿：波列 2.5 / NLMeans 1（CPU 权威）

dt CPU/C两路径分歧：process_wavelets Y0U0V0 模式折
`strength·compensate_strength=2.5`（:1511），而 nlmeans_precondition CPU
(:1682-1688) **不折任何 compensate_strength**（仅 strength·scale）。旧内联
CL 路径折 2.5 与 CPU 不一致——golden 权威取 CPU 路径（dt-cli 无 OpenCL）。
`makeVSTUniforms` 以显式 `compensateStrength` 参数分腿调用（波列 Y0U0V0=2.5
/ RGB=1，NLMeans 腿恒 1）。

## D-05-07-T5-2 — dt `const int` 强转 = 向零截断

nlmeans_scattering 散射偏移枚举（:1638-1657）Swift/Python 双端以
`Int(v)`（truncation toward zero）复刻，不用 round——散射 0 时两者一致，
非零散射差 1px。scattering 案例实测截断语义。

## D-05-07-T5-3 — SC#2 基线 = clean truth（非加噪图自身）

方向断言的 RMS 基线用 **clean ramp_8ev**（truth），输入用其种子化加噪变体。
identity pipe 对加噪图自身残差恒 0（构造性），不可作基线。量化：noisy
0.00175 → 正确剖面 0.00071 < generic 0.00075 < ISO125 错配 0.00111。

## D-05-07-T5-4 — dt 采纳经 05-06 conf（opencl=false）解除环境受阻

任务简报预期「OpenCL 桩坏 → 采纳受阻落账」；实测 05-06 adoption conf
（darktablerc `opencl=false`）+ `--core --configdir conf` 即可让
denoiseprofile CPU 路径正常加载/导出，三证据 8/8 齐全。其余 CL 插件
（colorzones/filmic 等）dlopen 失败为非致命噪声。坑：sqlite `hex()` 返回
大写，与 XMP 小写 hex 的 byte 比较须经 `bytes.fromhex` 归一。

## D-05-07-T6-1 — 面板滑块交互程（soft extent）裁剪

7 滑块交互程取 dt 硬限内的实用档：radius 1-8、nbhood 1-15、strength 0-10、
shadows 0-1.8（dt 全程）、bias −10-2、scattering 0-3、central 0-2。硬极值
（如 strength $MAX 1000）params 域仍程序可达——NLMeans 面板 soft-max 同
先例。

## D-05-07-T6-2 — profile 行口径：面板只展示 params 记录可携带的量

ModuleInstance 无图像上下文 ⇒ maker/model 只读展示无数据源；面板提供
Auto(EXIF)/Manual/Generic 三态 Picker（isoOverride nil / set / a=1e-4
具体档）+ 手动 ISO 滑块 + 生效剖面只读摘要（a₁/b₁ 数值）。Auto 的
sentinel（a[0]=−1）由 reloadDefaults 载入时解析，commit 侧
`resolvedProfile` 消费。

## D-05-07-T6-3 — force 曲线 tab 结构：ALL / Y0U0V0 双 tab

dt 面板按 RGB(4 行)/Y0U0V0(2 行) 模式分行展示；Lightamer 面板以
ALL(行 0 = all 通道)/Y0U0V0(tab 内 Y0 实线 + U0V0 虚线) 双 tab 覆盖
6×7 全表。Canvas 锚点 = `forceRow` 的 **uint16 量化值**（kernel 实消费值），
连线 = `forceCurveSamples`（同一条 Catmull-Rom 64 采样）——展示与消费
同源（CorrectionLUT 模式）。`forceRow`/`forceCurveSamples` 升 public。

## D-05-07-T6-4 — 波列 band 数无降载裁剪（与 nlmeans K clamp 的差异）

nlmeans 有 K clamp 3 + decimate 降载；波列 band 数由 20% 支撑域规则从
**run 级 dscIn** 全幅导出（tile 内稳定的前提，L021）——不做 preview 裁剪，
PREVIEW 经 TilingPlan 分块摊薄（FULL 100MP 35 tiles / 单 tile 读平面
0.059GB）。PERF7：2048×1536 → max_scale 7 ⇒ 31 趟 41.7ms（Debug）。

# PERF-5 记录 — Phase 5 全链与 denoise 增量（Plan 05-08-T6.3 收口）

> 测试机：M 系列 Apple Silicon（Debug 产物，直启宿主 test-direct.sh）。
> 帧型 = 真实拖拽形状：稳定 imageID + params tick per frame（全链 hash miss
> 重渲），PREVIEW 2560 bucket，PSO 启动预热先行。只对 SC#4 设门，全链重渲
> 只记录不设门（03-06 分配）。

## 基线与全链

| 轮 | 链 | 配置 | 中位帧时 | 备注 |
|---|---|---|---|---|
| 03-06-T7 | 编辑种子 11 iop + colorin | Release | 36.23 ms | 预算 16.6ms 未达 → 杠杆分配 |
| 04-07 | 同上（Phase 4 后） | Release | 33.42 ms | 杠杆兑现（PSO 预热 + 稳定 input） |
| **05-08** | 同上（Phase 5 全模块 seed 内，全部 disabled/neutral） | Debug | `PERF5` 行见测试日志 | 与 04 基线同域（种子增 3 件 disabled 无链增量） |

## SC#4 拖动门两链（05-08-T6.1 终测，`testPhase5DragGateTwoChains`）

| 链 | 组成 | 拖动滑块 | Debug 中位 | 60fps(16.6ms) 判定 |
|---|---|---|---|---|
| ① color 七件全启用 | 种子 + colorin；colorbalancergb/channelmixerrgb 翻 enabled + 种子已有五件 enabled（channelmixer/colorzones/vibrance/velvia/colorcontrast） | vibrance amount | **4.8 ms**（4.3–6.7） | **达标** ✓（Debug 即 <16.6ms） |
| ② denoise 单件启用 | 种子 + nlmeans enabled @ defaults（PREVIEW 降载 K=3+decimate=57 趟档） | nlmeans strength | **85.7 ms**（84.0–89.8） | **未达** ✗ |

- Debug/Release 比对本管线历史 ≈0.92（GPU-bound，03-06/04-07 两轮实测），Release 外推 ≈79ms，仍 ≫16.6ms——**denoise 单件链 60fps 判定为未达标，与配置无关**。
- 降载路径命中证据（05-06 引擎级实测）：降载档 57 趟 = 57.8ms vs 满血 481 趟 = 430.9ms（7.5×）——降载已兑现，剩余成本是 NLMeans 本征趟数，非 Lab 往返（见判定）。

## 判定（D-05-08-T6-1 摘要）

- **SC#4 前半（color/toning 拖动）**：60fps 达标 ✓——Phase 5 color 七件全启用链拖动 4.8ms，预算余量 3.5×。
- **SC#4 后半（denoise 单件拖动）**：未达标 ✗——批合并/降载杠杆已兑现（K clamp + decimate + PSO 预热 + 稳定 input）仍 85.7ms。按 D-05-CONTEXT-6 触发条件，**Open#9 应急判定 = 成立**；但判定依据同时表明：nlmeans 链成本在 NLMeans 本征趟数（57 趟降载档），Lab 往返共享（应急 plan 的杠杆）只省每模块 2 趟，对 60fps 缺口贡献 ~5%——**应急 plan 启动不改变结论**，真正的剩余杠杆是更深的 denoise 预览降载（K/window/预览分辨率），移交 Phase 6+ / 独立 perf plan（TODO 登记 本 plan 记录判定依据后收口，应急工作不在本 plan 内）。
- tiling fallback 承重（SC#4 后半）：nlmeans/denoiseprofile/bilateral/monochrome 四消费者分块==整幅全绿（TileNegotiation/NLMeans/DenoiseProfile/Bilateral 四套件）；bilateral FULL 100MP Δfootprint 有界（MemoryBudgetTests）。

## PERF 增量表（对 04 基线 33.42ms Release）

| 场景 | 链增量 | 来源 |
|---|---|---|
| color 七件启用（拖动） | +4.8ms Debug 全帧（种子基线内含五件 neutral） | testPhase5DragGateTwoChains |
| nlmeans 单件启用（拖动，降载档） | +~50ms Debug | 同上（85.7 − 全链基线 ~36 Debug） |
| bilateral 启用 PREVIEW | ≈0（σs 折算后 rad≤6 直连单趟，<0.1ms 级） | 路径决策：PREVIEW σs≈0.55 → rad 2 直连 |
| monochrome 启用 PREVIEW | 单趟 filter+apply + 3D grid（05-05 已记录） | 05-05 perf 记录 |

# Plan 07-1 Summary — Vision 基建 + AI-01 主体隔离

**Status: COMPLETE**（2026-09-24；5/5 任务；全 suite **812/5skip/0fail**（基线 788→812 +24，skip 3→5 为 2 条层 B 测试宿主 entitlement 跳过，见下）；未 push）

## 任务完成表

| 任务 | commit | 交付 | 验证数字 |
|---|---|---|---|
| T1 SDK 复核 + benchmark 基线 | `fb2cf3e` | 零漂移复核结论（D-07-1-T1-1）+ `.work/07/perf.md` 基线表 + `bench.swift` 可重跑脚本 + SC#5 门建议（D-07-1-T1-3）| warm layer A 14-16ms / layer B accurate 85-126ms；模型下载 3-11ms；设备面三项 beta 现实（D-07-1-T1-2）|
| T2 AIMaskService 核心 + 层 A | `a7f74c3` | `LightamerCore/Sources/AI/`（AIMaskTypes/AIMaskService/AIAssetStatus）+ L014 fence 输入腿 + 层 A 两段 API（catalog→label 合成 mask）+ 跨进程探针（app init 时机）| 确定性门 6 测试 0 fail：层 A gpuPinned 逐字节恒等（进程内 + 跨进程 byteIdentity 相等）；supported 枚举含 GPU；CPU pin → typed error 不崩 |
| T3 层 B + 下载三态 + 回落 | `649a41b` | segmentSubject（种子/质量/ROI/精修点 + 13/11 预算门 + scribble 缝拒绝）+ AIAssetStore 状态机（注入式探针）+ AIDownloadPrompt（首启提示/失败重试非静默/L010/catalog zh）| 语义门 10 测试 0 fail：IoU ≥0.9 + 背景环 ≤0.1 + 双主体 subset 双向断言 + noSubject typed + 预算边界 + 状态机矩阵（downloading 中态/失败可重试/ready 幂等）|
| T4 bake 接线 | `333cc79` | AIMaskResample（像素中心双线性 + grow-only + 纹理上传）+ `RasterMaskStore.bake` 羽化增件（默认 0 零字节改动）+ 同 maskID 覆盖重 bake 验证（hash 翻转→stableHash 翻转→缓存 MISS 记账）| 几何 6/6（[0,0.25,0.75,1] 权重 + 行 0=图顶 + Y 翻转向量 + 羽化剖面 mid≈0.5 单调 + 默认 0 byte-identical）；raster round-trip 9/9（含 AI 平面 uint16 恒等 + 覆盖重 bake 账本）|
| T5 收口 | 本 commit | 全量回归 ×2（touch + build-for-testing 复跑）+ TODO/GOAL-STATE/本文件 | 812/5skip/0fail ×2 |

## 关键执行期发现（正本 = 07-1-DECISIONS.md，共 10 条）

1. **设备 pin 现实（D-07-1-T1-2，回注 planner）**：CPU 不在两层 supportedComputeStageDevices（pin 即 SIGTRAP）；层 B pin 任何设备进程崩（Vision beta bug）；层 A GPU pin 合成图可用且逐字节确定、100MP 实拍图崩。**测试确定性策略 = 层 A gpuPinned + 层 B 不 pin（default，探针实证逐字节恒等）**；服务层 pin 全部先验校验（typed error 防 trap）。
2. **`generateScaledMask` 双重损坏（D-07-1-T2-4，回注 planner）**：subset 语义坏 + all 集合几何双轴 +3/16 偏移——层 A stage 2 统一走 `allInstancesMask` 标签合成腿（正确性两案实证），scaled 保留为 Apple 修复后的升级缝。
3. **测试宿主 entitlement 阻断层 B 资产（D-07-1-T3-3）**：xcodebuild 注入的 test entitlements 下 `downloadAssets()` 后 `assetStatus` 恒 notReady（普通二进制正常）——2 条层 B **推理**测试 skip-with-reason；层 B 服务逻辑全量已测；**07-3 GUI 轮在真实 app 复验层 B 端到端（已登记 07-3 前置项）**。
4. **benchmark 读数（perf.md）**：SC#5「单次生成 ≤1s」建议按 warm 路径裁定 PASS（全部 ≪1s）；cold = 进程内模型首编译（layer A 最高 5.5s，一次性，spinner 承接）；层 B balanced/accurate 直接产全分辨率 mask（双线性上采样只对 fast 256×256 生效）。

## 交付面（移交 07-2/07-3）

- `AIMaskService.subjectMask / detectInstances / segmentSubject`——07-2 皮肤腿（landmarks/personSeg 复用同一 handler/fence/device 骨架）与 07-3 MaskToolbar（AI 组按钮 + instance 勾选浮层 + tap-to-segment 视口模式）的消费接口。
- `AIAssetStore` + `AIDownloadPrompt`——07-3 三态门控复用同一 actor（无第二状态机）。
- `AIMaskResample.upsampleToDecodeFrame` + `RasterMaskStore.bake(featherRadius:)`——AI 蒙版 → `MaskSpec.raster` 的完整通道（移交清单①③落位；②层栈写入在 07-3）。
- L014 fence 在 `AIMaskInput(texture:)` 固化（commit 空 buffer + waitUntilCompleted → CIImage(mtlTexture:)）。

## 验收标准对账

- [x] SDK 复核结论落 DECISIONS（零漂移）；benchmark 基线 + SC#5 门建议落账
- [x] 层 A：确定性恒等（gpuPinned 逐字节，进程内+跨进程）+ 合成图 IoU ≥0.9/背景 ≤0.1 + 多 instance 子集 + 无主体 typed（不落 mask、不降级全一）——**pin 设备由 CPU 改 GPU（D-07-1-T1-2 现实，回注 planner）**
- [x] 层 B：seedPoint/seedBox + 含/排点 + 超限 throws + Y 翻转单测 + scribble 缝——**推理腿在测试宿主 skip（entitlement），服务逻辑全测，07-3 复验**
- [x] 下载三态 + 首启提示 + 双后端回落（层 B 未就绪 typed 拒绝、层 A 不受影响实证）；失败非静默（reason 透出 + 重试）
- [x] bake 接线：双线性（像素中心 + 对齐断言）+ 羽化（默认零改动回归钉死）+ 同 maskID 覆盖重 bake（hash 翻转 + 缓存失效记账，零新机制）
- [x] 测试 device 断言 = supportedComputeStageDevices 含 GPU（CPU 现实缺席→typed error 断言）；L014 fence 固化在输入构造
- [x] 全 suite 0 fail（812/5skip）；无 /tmp 过程产物入工作区；决策入 07-1-DECISIONS.md（10 条）；SUMMARY 落盘

## 遗留/风险

1. **层 B 端到端在测试宿主不可达**（entitlement 阻断）——07-3 GUI 验收轮真实 app 复验（probe 证据已存 perf.md）。
2. **Vision beta API 漂移面**：scaledMask 偏移/subset 坏、层 B pin 崩、CPU 不在 supported 集——三项均可能随 macOS 27 正式版修复；服务层已留缝（scaledMask 升级缝 + cpuPinned 校验路径 + pin 拒绝逻辑在 `#available` 下可收回）。
3. **层 A 蒙版分辨率 = 标签图分辨率**（512 级，bake 双线性升）——软边精度低于 scaled 的理论全分辨率；Apple 修复后切回。
4. benchmark 的层 A 两张实拍样张均无前景主体（studio 空白场景）——层 A 真实照片 IoU 未在 perf 轮覆盖，语义门以合成图为准（07-3 GUI 轮补真机主体样张目检）。

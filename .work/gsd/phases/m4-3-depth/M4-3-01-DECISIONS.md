# M4-3-01 DECISIONS — Depth 蒙版批执行期裁决与事实记录

> 执行批正本。plan = `M4-3-01-PLAN.md`；裁决生效值正本 = `M4-3-CONTEXT.md` 裁决记录
> （2026-10-10）。本文件记执行期 spike 事实 / 门值钉值 / 勘误 / 安装命令 / 许可审计；
> 收口轮（T8）补全。

## §1 D-4 spike：F16 件 feature 元数据亲核（T1，2026-10-10）

方法：`MLModel.compileModel` + `modelDescription` 亲读 + 真前向实跑（synthetic BGRA
输入），模型 = HF `apple/coreml-depth-anything-v2-small` revision
`cfef6f6f2a70783dedc0bfae40cecbc2052285d3` 的 `DepthAnythingV2SmallF16.mlpackage`。
探针源码（一次性，即弃 /tmp）事实转录如下。

### 钉死事实（KD-3 接线依据，T3 按此实现，另一臂代码不落）

| 项 | 亲核值 | 对 plan 的影响 |
|---|---|---|
| 输入 feature 名 | `image`，**image 类型**（MLFeatureType.image） | **臂 a 胜出**：模型收 image input、预处理已烘焙 → 直接喂 CVPixelBuffer，无 CPU 侧 ImageNet 归一化（臂 b 代码不落） |
| 输入形状 | **W=518 × H=392**（imageConstraint pixelsWide=518, pixelsHigh=392），静态 | **plan「518×396」勘误：真值 392**（research 从 HF 卡转抄，实件 392）。`inputSize=518`（长边）+ `inputShortEdge=392`；D-4 的 (long,short) 对解释不变（checker m2 的 (H,W) 单源 = 本表） |
| 输入像素格式 | BGRA（pixelFormatType 1111970369 = 'BGRA'） | worker 输入腿以 BGRA CVPixelBuffer 喂入 |
| 输出 feature 名 | `depth`，**image 类型** | 读 `imageBufferValue`，非 multiArray |
| 输出格式 | **OneComponent32Half**（'L00h' = 1278226536；≠ OneComponent32Float 1278226534），518×392，bytesPerRow=1088（half 2B/px + 对齐） | 读回按 UInt16 half 逐行（用 bytesPerRow 步进）→ 转 Float32 |
| 输出值域 | 实测 [0.171, 1.0]（合成输入），**越大越近**（inverse depth） | 约归一但非严格 [0,1] 钉死——四段管线的 percentile 归一吸收任意线性域，无影响 |
| isfinite | 合成输入下非有限值 = 0 | m3 产线守卫照加（worker 前向写出前全查） |
| 元数据 | license = "Apache 2"；preview type depthEstimation；author "Original Paper: Lihe Yang et al. (Depth Anything V2)" | NOTICE 署名面一致 |

### 前向实测注记

- 首次 `prediction` 2272 ms（含编译）；warm 后进 25-33 ms 带（T7 perf 探针正式测量）。
- **F32 件同形**：`DepthAnythingV2SmallF32.mlpackage` 同 revision 同 (518,392)
  image in/out — 精度门参考件直用官方 F32 包（`gen-depth-golden.py` 输入），
  无需自转 F32。

### digest 锁定值（构建脚本自检输出，2026-10-10）

- zip = `depth-anything-v2-small-f16.mlpackage.zip`
- **byteCount = 45,759,882**
- **sha256 = `3824a48c6d17d2c5d76607bd0c0dea8427f062b7b014fa916d54e2aac91d9da9`**
- **确定性打包**：脚本修复首版非确定 zip（two-run sha 漂移）→ 固定 mtime
  （202601010000）+ `zip -X` + 排序条目后，**两次完整构建（含重新下载）逐字节
  一致**（3824a48c… == 3824a48c…）——digest 可复现，rebuild 不破锁。
- zip 内容（自检断言步全绿）：`LICENSE` / `NOTICE` /
  `depth-anything-v2-small-f16.mlpackage/{Manifest.json, Data/com.apple.CoreML/
  model.mlmodel, Data/com.apple.CoreML/weights/weight.bin}` / `MANIFEST.sha256`。
  mlpackage 目录名从上游 `DepthAnythingV2SmallF16.mlpackage` 重命名为
  `depth-anything-v2-small-f16.mlpackage`（= assetFileName 去 .zip 后缀；
  Manifest.json 只含相对路径引用，重命名安全；resolver 单名查目录所需）。

### spike 对 plan 文本的勘误汇总（checker m2 落点）

1. **392（非 396）**：全部 (518,396) 字样按 (518,392) 执行；AC#11 的
   「静态形状 518×396」按 (long=518, short=392) 对兑现。
2. **臂 a 钉死**：KD-3 两臂择一 → 臂 a；`selection.py:65` ImageNet 归一化仅作
   Lumen 参照注记，我方无 CPU 侧归一化代码。
3. **输出读回**：8 字节头 + F32 LE 的 outPath 形态不变（half→F32 转换在
   worker 内完成，editor 侧只见 F32）。

## §2 T1 执行期补记

- **构建脚本两 bug 亲踩**：①`rm -rf $RELEASE_DIR` 后未重建父目录即 `mv`（rename
  ENOENT）→ 补 `mkdir -p`；②嵌入 python 漏 `Path()` 包装 → 补。两修后脚本
  幂等重跑全绿。
- **hfFallback.file 对 depth = provenance 面**（checker o6 兑现注记）：钉
  `DepthAnythingV2SmallF16.mlpackage/Data/com.apple.CoreML/weights/weight.bin`
  ——HF 直链没有单文件 zip 形态，该 rung 即使可达也必然 checksumMismatch
  fail-closed（D-M2-10-CONTEXT-7 既有架构），不视为缺陷。
- **digest 先行入库**（plan 允许顺序）：release 上传（T8 ops）前 digest 真值
  已入库；fail-closed 面只影响「可下载」（404 → allSourcesFailed typed），
  无半态风险。
- m4 落点裁定 = **处方①（build 脚本自检步）**：zipinfo 清单断言（6 条目缺一
  exit≠0）+ NOTICE 署名行断言（"Depth Anything" / "apple/coreml-depth-anything-
  v2-small"）内嵌脚本；DECISIONS（本节）记录自检输出。env 门控单测路线（处方②）
  不取（zip 在仓外机器位，LIB 单测不可见）。

## §3 T2 执行期数学事实：守卫 (b) 对非 NaN 输入不可达（plan KD-4 字面修正注记）

- **事实**：任何通过守卫 (a)（`high−low > max(1e−6, 1e−4·scale)`）的平面，
  `P(v ≥ p95) ≥ ~5%`（p95 = 95 分位定义），且这些像素 `relative ≥ 1 → α=1` →
  `mean(α>0.5) ≥ ~5% ≫ 3e−4`。即 **默认参数下守卫 (b) 是 NaN backstop only**
  （NaN 使 α 全 NaN、`α>0.5` 全 false → coverage=0 → (b) throw）。
- **为什么 Lumen 可达而我方不可达**：Lumen 的 `(alpha>.5).mean() < .0003` 计数
  在 guided-filter **refine 之后**（`selection.py:75→77`，refine 把高 α 抹开），
  且其非深度腿（U2NetP 等）不走 percentile 窗化；我方四段纯函数无 refine
  （OQ-5 裁定），窗化后覆盖下界 5% 是解析事实。
- **处置**：守卫 (b) 代码照 plan/KD-4 原样保留（Lumen parity + NaN backstop +
  `coverageFloor` 参数缝 = 后手 refine 档的预留面）；「近空覆盖」的真实用户面
  由守卫 (a) 承担（无分层场景 p95−p10 ≈ 0 → degenerate）。plan T2 验收的
  「近空覆盖负测」经 `coverageFloor` 参数缝确定性触发（DepthMaskPipelineTests
  testNearEmptyCoverageThrowsTyped 注记内联）。checker m6 的「两级靶近区 ≤5%
  落守卫 (a)」与本事实同向（(a) 是真负测门）。

## §4 T3/T4 执行期补记

- **front-matter 边界增补（T5 申报）**：`App/Sources/Lightamer/UI/
  LightamerApp.swift`（@State + .environment 两行）不在 plan files_modified
  清单——DepthMaskService 的环境注入点（AIDownloadModel 单实例模式同款）。
  机制必需，非顺手改动；后续 plan 起草时 app-root 注入点应默认入清单。
- **DepthMaskService 并发形态**：progress sink 以 WeakBox 桥接（init 期闭包
  不得捕获未初始化 self）；`nonisolated static let profileID`（@MainActor 类
  的 static 属性隔离默认跟随类型）。
- **真子进程 crash hook 语义**：hook 值 = 裸 profile 名（每次 open 崩）；
  `@units` 后缀 = 限定 units 列表（非通配）——DepthWorkerLegTests 初版误用
  `@all` 当通配，已被既有 AIWorkerClientTests 语义纠正。

## §5 模型安装命令（验收机走查用，T6 ops）

```bash
ditto -x -k ~/Library/Caches/LightamerModels/depth/depth-anything-v2-small-f16.mlpackage.zip \
  ~/Library/Application\ Support/Lightamer/models/depth-anything-v2-small-f16/
```

（与运行时 DepthPackageResolver 同路径同工具；装后 DepthGoldenTests/
DepthWorkerLegTests 的门控轮在真机全真跑。本机已装，2026-10-10。）

## §6 T6 golden 门值钉值与排查实录

- **门值钉值**：abs-rel ≤ 0.01（三在门 fixture 实测 0.0023/0.0029/0.0036，
  ≈3× 余量于 Apple 自报 0.0089）+ max-abs ≤ 0.02（在门实测 max 0.0117 +
  余量）。两排除件为域/余量裁定（horizon 0.0092=门 92% 余量卫生、ramp
  0.0237 无结构 OOD），非调门凑数；全表在 fixture README。
- **排查实录（三假说两证伪）**：①ICC 缺失致 CG/PIL 输入分歧——证伪（嵌
  sRGB profile 前后数字逐位不变；全平面 byte-diff=0）；②ANE/CPU 设备分叉
  ——证伪（standalone .cpuOnly session 与 coremltools CPU predict 逐位一致
  max-diff=0.000000）；③**真因 = 测试参考块错索引**（gateFixtures 枚举序
  ≠ 生成器五输入序，edges 对上 horizon 的参考块 → 0.16 假失败）——
  referenceOrder 单源映射修复后 .all 生产腿全绿。教训入 LESSONS 候选：
  「golden 对照先证参考侧对位，再疑产线」。
- **fixture 生成器偏离申报**：「真实 RAW 降采样样张」不可满足（隐私红线：
  个人照片不入开源仓；许可证红线：参考仓图像为 GPL UI 截图）→ 确定性
  合成自然样张替代（seed 20261010），README 偏差节在案。

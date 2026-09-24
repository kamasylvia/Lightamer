# Phase 7 Vision benchmark 基线（Plan 07-1 T1）

> 只记录不设门（PERF-5 口径同）；SC#5 门建议见 DECISIONS。
>
> 机器：Mac16,10（Apple M4）/ macOS 27.0（26A428）/ Xcode 27.0（27A266a）/ SDK MacOSX27.0
> 脚本：`.work/07/bench.swift`（可重跑：`xcrun -sdk macosx swiftc -O -swift-version 5 -o bench bench.swift && ./bench <image...>`）
> 采样：每配置 4 轮——cold = 第 1 轮（进程内首次），warm median = 第 2-4 轮中位数。
> 输入：GFX100S.RAF = `Fujifilm-GFX100S-14bits-losslescompressed-4_3.RAF`（11648×8736 ≈ 102MP）；
> DSC00001.ARW（6192×4128 ≈ 25.6MP，24MP 常规帧档）——均 `.work/plans/01-05/samples/`。

## 设备枚举（MLComputeDevice.allComputeDevices）

- neuralEngine: `<MLNeuralEngineComputeDevice>`
- gpu: `<MLGPUComputeDevice> Apple M4`
- cpu: `<MLCPUComputeDevice>`

## 层 B 模型资产（DownloadableAssetsRequest）

- 初始 assetStatus：`notReady`（每轮进程首查）
- `downloadAssets()`：**3.3–11.4 ms → ready**（模型极小或系统级预暂存；下载成本可忽略）

## supportedComputeStageDevices（pin 可行性）

| 请求 | main 阶段 | 备注 |
|---|---|---|
| layer A `GenerateForegroundInstanceMaskRequest` | `[ane, gpu]` | **无 CPU** |
| layer B `GenerateIterativeSegmentationRequest` | `[gpu]` | **无 CPU；实测 pin 任何设备进程 SIGKILL/SIGTRAP（beta bug）** |
| personSeg `GeneratePersonSegmentationRequest` | （只暴露 setComputeDevice，无枚举成员） | — |

## 耗时表（default 设备 = ANE 优先，不 pin）

| image | request | quality | cold ms | warm median ms | mask res / result |
|---|---|---|---|---|---|
| GFX100S.RAF | layerA foregroundInstMask | - | 1160.3 | **15.5** | nil（该样张无前景主体——空白测试场景；合成主体图 instances=1 见下） |
| GFX100S.RAF | layerB iterativeSeg | fast | 977.8 | 88.6 | 256×256 |
| GFX100S.RAF | layerB iterativeSeg | balanced | 160.1 | 158.6 | **11648×8736（全分辨率）** |
| GFX100S.RAF | layerB iterativeSeg | accurate | 116.8 | 125.8 | **11648×8736（全分辨率）** |
| GFX100S.RAF | personSeg | fast | 1105.1 | 4.0 | 256×192 |
| GFX100S.RAF | personSeg | balanced | 791.2 | 8.4 | 512×384 |
| GFX100S.RAF | personSeg | accurate | 915.7 | 41.9 | 2016×1512 |
| GFX100S.RAF | faceLandmarks | - | 11.4 | 4.7 | 0 face(s)（无人物样张） |
| DSC00001.ARW | layerA foregroundInstMask | - | 5461.4 | **16.2** | nil（同上） |
| DSC00001.ARW | layerB iterativeSeg | fast | 137.1 | 72.2 | 256×256 |
| DSC00001.ARW | layerB iterativeSeg | balanced | 99.1 | 100.3 | 6192×4128（全分辨率） |
| DSC00001.ARW | layerB iterativeSeg | accurate | 80.8 | 85.3 | 6192×4128（全分辨率） |
| DSC00001.ARW | personSeg | fast | 52.9 | 4.1 | 256×192 |
| DSC00001.ARW | personSeg | balanced | 53.7 | 11.2 | 512×384 |
| DSC00001.ARW | personSeg | accurate | 96.1 | 44.0 | 2016×1512 |
| DSC00001.ARW | faceLandmarks | - | 44.8 | 6.3 | 0 face(s) |

解码（CIRAWFilter → CIImage，参考）：GFX 100MP ≈ 200–490 ms；DSC00001 25.6MP ≈ 2646 ms（本帧含 v9 探测，波动大）。

## 关键读数

1. **warm 单次生成全部 ≪ 1s**：layer A 15–16 ms、layer B accurate 85–126 ms、personSeg accurate 42–44 ms——SC#5 "interactive" 口径在 warm 路径大幅满足。
2. **cold = 模型首编译**：layer A 冷 1.1–5.5 s（进程内一次）；layer B 冷 0.1–1.0 s。用户首次点击需 spinner 承接（后台 Task 已是既定架构）。
3. **layer B balanced/accurate 直接产全分辨率 mask**（102MP 下 11648×8736）——**`AIMaskResample` 双线性上采样只对 fast 档（256×256）实际生效**，与 RESEARCH 预期（"qualityLevel 决定分辨率，仍低于解码帧则上采样"）一致但档位分布更新：accurate/balanced 无需上采样。
4. **层 A 语义**：两张真实样张均无"可分离前景主体"（studio 空白测试场景）→ `noSubject` 腿真实可达；合成纹理主体（灰底 + 纹理亮盒 256/512/1024）`instances=1` 稳定检出（探针实证）。
5. **pin 面现实**（详见 DECISIONS D-07-1-T1-2）：CPU 不在任一请求 supported 集，pin 即 SIGTRAP；layer B pin GPU 进程崩（Foundation os_unfair_lock 递归锁 abort）；layer A pin GPU 在 512 合成图可用且**逐字节确定**（探针 2/2 equal），但在 100MP 实拍图 SIGTRAP。**结论：本 OS 上生产路径一律 default（不 pin）；测试确定性 = layer A gpuPinned（合成小图）+ layer B 不 pin（default ANE，探针实证 2/2 逐字节 equal）。**

## pin 探针补充数据（.work/07 会话内，未入表）

- layer A gpuPinned 512×512 合成图 × 2 轮：scaled mask 262144 字节 **equal=true**（逐字节）。
- layer B default（不 pin）512×512 合成图 × 2 轮：mask 512×512 **equal=true**（逐字节）；模型推理 warm ~3.5 s 首轮后 ~百 ms 级。
- layer B excludedPoint(中心) 方向：主体区均值 0.3517 → 0.3175（**下降 = 方向断言可用**）。

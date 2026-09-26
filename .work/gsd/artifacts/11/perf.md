# Phase 11 计量总账（.work/11/perf.md）

> **口径（11-05 T2，只记不设门）**：Phase 11 的所有导出计量数字**仅记录、不设门**——
> 60fps/内存/吞吐的正式清算全部挂在 **Phase 15 性能专项**（ROADMAP §Phase 15；
> RESEARCH §7-5 决议）。本文件是 Phase 15 的输入基线。
>
> 执行环境：macOS 27.0 / Apple M4（16GB）/ **Debug 构建**（test-direct.sh 直启宿主）；
> fixture 与计时全部 `FileManager.temporaryDirectory`（**内置 SSD**，L009——UNITEK
> USB 卷禁入计时面）；合成源经注入 decodeLeg（float32 linear Rec2020 2560×1707）。
> 计时探针 = `ExportPerfProbeTests`（`EXPORT-PERF` 打印行，`/tmp/la-direct-tests.log`
> 可复跑取证）；每格式先暖（PSO/pool 摊销）后计。

## 1. 分段耗时（renderStage / encodeStage per 格式）

2560×1707 全幅（~4.4MP），Debug，SSD。renderStage = decode→pipe(.export 无缓存)→
出口腿→量化；encodeStage = 编码→tmp 同目录原子晋升。

| 格式 | renderStage（含注入 decode ≈1.8s） | encodeStage | 备注 |
|---|---|---|---|
| JPEG q0.9 sRGB | 3729ms | **8ms** | ImageIO 有损，编码近零成本 |
| PNG 16 sRGB | 3649ms | 240ms | deflate 无损 |
| TIFF 32f linear Rec2020 | 2525ms | 116ms | 未压缩 float 写盘 |
| HEIC 10-bit P3 | 3763ms | 47ms | |
| AVIF 10-bit sRGB | 4016ms | 175ms | |
| WebP q0.85 sRGB | 3620ms | **5719ms** | **libwebp 有损编码是全链最重单段**（Debug；effort=round(q×9)=8） |
| 注入 decode-only 基准 | ≈1825ms | — | 合成 float32 缓冲构造成本，**非**真实 RAW decode（真实解码计量属 Phase 15 §3 RAW 解码战场） |

- 净渲染段（renderStage − decode 注入）≈ **0.7–2.2s @4.4MP Debug**——Debug 构建
  含全部断言/无优化的 kernel 路径，Phase 15 以 Release 计量为准。
- **WebP 编码瓶颈**：5.7s@4.4MP（Debug）在六格式中断层领先，Phase 15 若需 WebP
  批量吞吐，effort 折算（11-02 D9）与并发策略是杠杆位。

## 2. 内存峰值与并发 1 红线复核（D-11-CONTEXT-2 推导对账）

- 探针：8192×5461（**44.7MP**）PNG16 全链 renderStage，30ms 间隔采样
  `task_vm_info.phys_footprint`（进程级，含注入 decode 缓冲与 CI 内部副本）。
- 实测峰值增量 **3604MB @44.7MP** → 线性外推 **100MP ≈ 8057MB（7.9GB）**。
- **对账结论**：D-11-CONTEXT-2 的「≈5GB@100MP」推导**低估**——管线同时存活
  入口平面 + 双 scratch ping-pong（11-03 尺寸感知复用修复后的形状）+ 出口腿 CI
  bitmap + 量化平面，float32 每平面 100MP = 1.6GB，4 平面级存活即 6.4GB，实测
  外推 8GB（含 CI/ColorSync CPU 侧副本）量级自洽。
- **红线维持**：并发 1 是硬约束（并发 2 即 ~16GB 触顶——`ExportQueueContract.
  concurrency = 1` 常量钉死，`ExportQueueTests` ⑦ 并发探针在案）；Phase 15 的
  杠杆 = 平面复用率（出口腿 bitmap 直写量化平面等）而非调大并发。
- 16GB 机器上 100MP 单 job 可行但紧（系统 + app 常驻 ~4GB + 8GB 峰值）；
  TilingPlan 窗口化（PERF-6 战场）是 Phase 15 的正解方向。

## 3. 32f TIFF 落盘尺寸

| 项 | 数字 | 对账 |
|---|---|---|
| 2560×1707 TIFF 32f（none 压缩） | **69,924,114 B（66.7MiB）** | = W×H×16B + 头（69,924,480 理论值 −对齐差），未压缩 float 写盘数学精确吻合 |

- 面板「32f 大文件警告位」（`export.warning.large_tiff`）阈值语义由 11-04 面板
  承载；本记录确认量级：100MP 32f TIFF 未压缩 ≈ **1.6GB/张**。

## 4. 编辑并发观感（导出运行中编辑）

- **结构性不阻塞证据链**（本轮复核）：导出渲染走独立 `exportCommandQueue`
  （`!==` 编辑队列，11-03 T1 身份锚）+ 并发 1 + Utility QoS + TaskLocal 结构化
  包裹（detached 不继承即静默回编辑域——反向锚在案）；导出 job 的 CPU 侧段
  （CI/ColorSync 出口腿、编码）在 utility 优先级，不占主线程。
- **主观观感**：headless 探针无法产生「人眼帧率」证据——**Manual-Only 挂账**
  （导出 100MP 运行中拖动滑块/缩放的观感复核随 verify-work/Phase 15 走查）。
  结构面上编辑管线零染导出域（`ExportPipeTests` 编辑路径队列身份反向锚）。

## 5. 08-3 遗留 #5 —— 模糊腿 Release 复测

> 08-3-SUMMARY 遗留 #5：「模糊腿 Release 性能：Debug 极值在案；Phase 11 导出腿
> 复测。」本轮以 **Release 构建**（默认容器 `-configuration Release` build-for-testing
> + 直启宿主，`PackageFrameworks` 显式入 DYLD 路径 + Lightamer Dev 重签）复测
> `YiyinBordersTests.testPreviewDragInitialTimingRecorded`（2560 PREVIEW median ×5）兑现。

| 构建型 | solid | blur+overlay | solid+radius+shadow | 来源 |
|---|---|---|---|---|
| Debug（08-1 记录基线） | ~250-270ms | 全链首渲冷值 163.9s（PSO 冷 + 21-pass 分解）；模块腿 proxy+blur ≈7.3s@5.4Mpx | ~280-380ms | 08-1-SUMMARY / 08 perf.md |
| **Release（本轮，median ×5）** | **244.5ms** | **163,831.5ms（≈164s）** | **109.8ms** | `BORDERS-PERF` Release 直启（Executed 1/1，0 fail） |

- **读数**：solid/shadow 两档 Release 略优于 Debug 基线；**blur+overlay 恒 ≈164s/渲染
  （warm，Release）**——与 Debug 首渲冷值同量级，说明该腿的代价主体不是 PSO 冷启动
  而是 **blur(amount:100) → √N 21-pass 分解在 2560 画布上的固有算力**（每 pass 全幅
  GPU dispatch，Release 优化不改变 pass 数）。
- **定性**：SC 门 = 观感（08-3 GUI 轮已过，真机「~2min 内首渲、后续参数调全缓存命中」），
  本记录不设门；**遗留转 Phase 15**：blur 腿 pass 数/半径分解策略（mip 链或 downsample
  blur）是明确的优化杠杆位。08-3 遗留 #5 就此关闭（复测在账）。
- 复测脚本（直启变体）：Release 产物路径 + `DYLD_FRAMEWORK_PATH` 增补
  `Products/Release/PackageFrameworks` + 主 app/WebP 框架以 `Lightamer Dev` 重签
  （Release 产物 Team ID 失配 + WebP 包框架未入 app 嵌入路径，Debug 不受影响——
  已录 11-05-DECISIONS 供 Phase 15 Release 计量复用）。

## 6. Phase 15 清算注记（挂账清单）

1. PREVIEW 60fps 全链 warm median ≤16.6ms（导出面无关，挂总账）。
2. 导出分段 Release 计量（本文件 §1 为 Debug 基线；Release 只复测了模糊腿）。
3. 100MP 内存 8GB 外推的平面复用优化（§2——并发 1 维持，杠杆在平面数）。
4. WebP 编码吞吐（§1——effort/并发/批量策略）。
5. 真实 RAW 解码计量（§1 注——Phase 15 §3 战场，本 Phase 注入 decode 不代表）。
6. 编辑并发观感 Manual-Only 行（§4）。
7. 导出 GPU 争抢实测（11-04 D15 mask-fence 收编评估的 Phase 15 复评位——与
   `yieldsToEditor` 接口位一并评估）。

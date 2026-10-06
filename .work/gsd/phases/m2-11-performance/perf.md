# M2-11 perf.md — PERF 计量正本（M2-11-02 wave 2 落账，2026-10-07）

> 机器口径：Mac mini（Laniakea），macOS 27.0.1 (26A434)，M4-class Apple Silicon。
> Debug = `Scripts/test-direct.sh` 直启宿主（`xcodebuild build-for-testing` Debug 产物）；
> Release = `build/Build/Products/Release` clean 构建 + 本地证书重签直启（D-09-04-D9
> 惯例延续；本轮布局增量记录于 09 perf.md §档 A/B Release 复核节）。
> 纪律：L009 SSD 样张、三轮中位、L014 fence（计时读数前 drain）、`PERF|` 行落
> `/tmp/la-direct-tests-*.log` 逐值誊录（本文件每一数字可回溯日志行）。
> 样张：100MP 列 = `Fixtures.raf100MP`（GFX100S 100MP，在库本地 fixture 非 tracked）；
> 60.2MP 交叉列 = `input/RAW/DSC00012.ARW`（A7R V，repo 相对路径）。

## §PERF-01 M2 默认面 PREVIEW warm 复测（OQ-5-A 链面；M2-10 交接件 ① 复测闭合）

链面 = terminal trio（displayP3 committed）+ GradeCatalog.defaultLook 三件
（+1.5EV/+15/1.3，mint 同源解码）+ `terminalTail: .drt(DrtTailParams(record: DrtRecord()))`
（SDR 缺省 record）。preview-2560，PSO 预热先行，逐帧 exposure tick（全链 miss）。

### 静态 warm bench（`M2DefaultChainPerfTests/testM2DefaultChainPreviewWarm`）

| 列 | 口径 | decode cold/warm | pipe cold | warm ×3 → 三轮中位汇总 |
|---|---|---|---|---|
| RAF 100MP | Debug | 0.201/0.070 s | 748.8-767.4 ms | 38.9 / 42.0 / 14.0 → **带 14-42 ms**（双峰噪声，见观察项 O-1） |
| ARW 60.2MP | Debug | 0.198/0.108 s | 136.6-601.9 ms | 13.4 / 13.0 / 13.6 → **13.4 ms** |
| RAF 100MP | Release | 0.199/0.072 s | 313.9 ms | 47.5 / 29.6 / 37.2 → **37.2 ms**（单轮） |
| ARW 60.2MP | Release | 0.268/0.105 s | 408.7 ms | 13.2 / 13.2 / 12.0 → **13.2 ms** |

- 对照在案：M2-6-3 bench（合成图 preview-2560，DRT 尾段全链）cold 117 / warm 85 ms——
  真样张 warm 同量级（ARW 稳定 13ms；RAF 带 14-42ms），**交接件 ① 复测闭合：M2-10 全链
  加载后 warm 无回归**。
- 判定：PERF-01 重述门（60fps 16.6ms）对静态 warm 列——ARW 双构建达标（13.2-13.6）；
  RAF Debug 中位 14-42 带（噪声内 14ms 档达标、40ms 档超），Release 37.2——**RAF 100MP
  静态 warm = 未稳态达标**（见 O-1 + 判定移交 M2-11-04 重述批）。

### 拖动两档（`testM2DragGateTwoChains`，KD-2 形态平移；本表 = T3 降载尝试 before 列）

| 档 | 列 | Debug 中位 ×3 轮 | Release 中位 ×3 轮 | 60fps(16.6ms) 判定 | vs 05 perf SC#4 在案 |
|---|---|---|---|---|---|
| ① color 七件拖 vibrance | RAF | 17.8 / 11.3 / 11.9（尾尖峰 27-52 带） | 21.0 / 15.2 / 9.7 | **带内 ✓**（ARW 稳达；RAF 中位带跨 16.6，best-round 9.7-11.9） | 在案 4.8ms（2048×1536 合成、无 DRT 尾）——M2 面 +DRT 尾 + 真样张后 8.1-21 带内 |
| ① 同上 | ARW | 8.6 / 8.6 / 8.9 | 8.7 / 8.2 / 8.1 | **达标 ✓**（余量 ~1.9×） | 同上 |
| ② nlmeans 拖 strength（57 趟档） | RAF | 65.5 / 67.6 / 63.9 → ~65 | 63.8 / 64.5 / 64.4 → ~64 | **未达 ✗** | 在案 85.7（2048×1536 合成）→ M2 面 ~65（Debug/Release 比 ≈1.02，瓶颈本征） |
| ② 同上 | ARW | 57.7 / 57.8 / 56.9 → ~57.5 | 56.9 / 57.3 / 57.4 → ~57.3 | **未达 ✗** | 同上 |

## §OQ-7-A nlmeans bounded 降载尝试（T3 终态 = revert 挂账，产线零 diff）

尝试序（E4 方向：decimate 加深 57→~37→~29；65/73 更浅档禁入），逐档复测 KD-2 ②
（Debug 直启 ×2 轮/档）+ 引擎级（`testNLMeansPreviewDowngradeTiers`，2048×1536）：

| 档 | decimate step | 趟数 | 拖动② Debug（RAF/ARW 中位带） | 引擎级 Debug（2048×1536） | 16.6ms 判定 |
|---|---|---|---|---|---|
| committed | 2（隔一取一） | 57 | ~65 / ~57.5 ms | 57.8 ms（05 perf 在案锚） | ✗ |
| 尝试 1 | 3 | 9×4+1 = **37** | 50.9-51.3 / 45.6-45.8 ms | 33.1 ms | ✗ |
| 尝试 2 | 4 | 7×4+1 = **29** | 46.2-47.6 / 40.7-41.4 ms | 26.5 ms | ✗ |

- **结论：三档试尽全不达，revert（OQ-7-A 默认退出路径）**。趟数 57→29（-49%）帧仅
  -29%（46-51 vs 63-67）——收益递减；引擎级单腿（26.5ms @29 趟）已独自超 16.6ms 门，
  decimate 杠杆数学不可达（除以趟数的线性外推：达线需 ≤8 趟 = 观感崩坏档，禁入）。
  剩余杠杆 = kernel 重写/时域复用 = C 案（超本 phase 半径，禁）。
- 处置：`NLMeansModule.swift` 工作树改动全部 revert（`git checkout`，产线 diff 零命中）；
  `NLMeansParityTests` 零重钉（committed 档位 pin 原样成立，IOPParity 定向轮 362/3/0 绿）；
  V2 备选语义（「denoise 拖动降档预览」）移交 M2-11-04 重述批注记。
- Release 对照（committed 57 趟档）：拖动② RAF ~64 / ARW ~57.3（上表）——Debug≈Release
  ±2%，T3 尝试期间未跑 Release 档位轮（Debug 双档已证不可达，Release 线性平移不改判定）。

## §PERF-05 open→首帧端到端（T4；`testQLRenderLatencyGrid` 内部分段，`LA_QL_PERF=1`）

| 列 | decode cold | decode warm | 首帧 512 总和（门对象） | 首帧 2560 总和（记录档） |
|---|---|---|---|---|
| RAF 100MP | 0.220 s | 0.073 s | **0.172 s ✓** | 2.806 s |
| ARW 60.2MP | 0.176 s | 0.110 s | **0.194 s ✓** | 5.061 s（首帧含 per-size PSO 结转；grid warm 中位 1.941） |

- **OQ-6-A 门：warm 缩略桶 512 首帧 ≤500ms → 双列达标**（0.172/0.194，余量 2.6-2.9×）。
- RAW9 CoreML 编译冷单列：本轮实测 decode cold 0.176s = **磁盘缓存命中态**（CoreML 编译
  产物跨进程缓存；在案 2.62s 为首编译态，不清系统缓存不可复现——DECISIONS §5 如实登记）。
- grid 表 warm 中位 vs 13 perf 在案（连续性 ✓）：512 = 0.160/0.194（在案 0.166/0.194）、
  2560 = 2.074/1.941（在案 2.080/1.925）。grid 冷列口径变化注记：PERF05 腿先行消费
  decode 冷 + PSO 冷（grid 冷格退化为「decode 热的格首渲」）。

## §PERF-03/04 Instruments 归档 + hitch 计量（T6；证据 = `profile/` + `gui-acceptance/m2-11/`）

| 项 | 结果 |
|---|---|
| trace ① 编辑会话（Time Profiler 60s，probe 全链：建项目→import→100MP 打开→渲染上屏） | `profile/m2-11-edit-session.trace`（33MB，盘上归档） |
| trace ① MainActor 长任务（Hangs 仪器 ≥250ms 档） | **potential-hangs = 0 行**（Open+渲染+模态处置全程无 250ms+ 主线程挂起） |
| trace ② Animation Hitches 35s（attach 同会话，AX 驱动色温轨道 click ×8） | `profile/m2-11-hitch-edit.trace`（432MB，盘上归档；导出证据 = `hitches-export-edit-session.xml` 135KB + `hitch-edit-session-summary.txt`） |
| hitch >50ms 帧间隙（滑块拖动场景） | **0**（498 hitch 全部 = 单帧 16.67ms「expensive app update」档；总 hitch 时长 8.3s/35s = 单帧翻转级） |
| hitch 缩放/平移/万张滚动三场景 | **Manual-Only**（computer-use SDK 本执行面不可用——主 agent 专属；AX 深树滑块遍历超时、LazyVGrid AX 滚动不可设值；10k fixture 已备 `code /tmp/m2-11-perf/scrollsession` 未消费） |

- 驱动通道注记：computer-use SDK 返回 "Computer Use is not available in subagent"（主
  agent 专属策略）→ 回退 System Events AX（表单/按钮/轨道点击实测可达）；trace 归档
  细节 = `profile/TRACE-NOTES.md`。

## §对账与计数

- 测试基线：2955/16/0（M2-10-07 终值）+ 本波 Δ = **+2**（M2DefaultChainPerfTests 2 法；
  QL 探针 E3-a 零新 func → 预期 **2957/16/0**）。本波未跑全套 `--all`（批准制未申请）；
  实测定向/全量轮：IOP 定向多轮全绿（1/0/0 ×N、2/0/0）、IOPParity 全量 362/3/0
  （peak 5995MB）、Export 定向 1/0/0、SESS Release 直启 1/0/0——skip 零新增。
- 峰值观测义务（checker m5）：本波 IOP 新 bench 增量轮 peak 943-1097MB，远低于既有
  IOP 主导峰 7865MB（M2-4-0 SPIKE），bundle 峰值不变；零 MEMFAIL。
- 观察项 **O-1（RAF 100MP warm 双峰噪声）**：静态 warm RAF 在 14ms 档与 ~40ms 档两态
  跳变（三轮内即见 13.6/40.8；ARW 无此现象）。疑源 = 入口平面腿/CI 解码状态机或 GPU
  时钟态，未定位；不判缺陷，移交 GUI 验收轮（M2-11-05）顺带观察 + 必要时 spike。

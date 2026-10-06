# M2-11 perf.md — PERF 计量正本（M2-11-02 wave 2 落账，2026-10-07；M2-11-03 wave 3 增 §SpektraLab 对标节）

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
- **证据注记（M2-11-02 验收批 2026-10-07，minor-1）**：现存 `/tmp` 尝试期引擎行标签打印
  `downgraded(57 passes) 26.5 ms`——标签按 `offsets(K:3, decimate:true)` 默认 step 计算，
  尝试期 runtime 档加深后不随之变（stale label 伪影）。归档正确性经满血腿判别亲证：full
  481 趟（kernel 自 a61f746 09-22 与 05 锚同码）430.9 → 370.6 = 仅 -14% 机器态漂移，26.5
  属 57 趟档需 -54% 不可能；26.5 ≈ 49.7（57.8×0.86）× 29/57，与上表「26.5 = 29 趟档」
  归档吻合。判定链不受影响。正本 = `M2-11-02-ACCEPTANCE.md` §一。

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

## §SpektraLab 对标两硬门（M2-11-03 wave 3 落账，2026-10-07）

> 口径：`FullRenderBenchmarkTests`（IOP，T1 新建）+ `DrtTailTests` 计时两腿（LAYERS，
> T2 扩展）。语义映射正本 = RESEARCH §B（B.1 全渲染 → FULL 桶全链；B.2 重印 → 尾平面
> 命中重渲；B.3 二进制不对标）。样张列 = 60.2MP ARW 主列（**>45MP = 更严口径**，
> DECISIONS 签注）+ 100MP RAF 加列（fixture 在场）。计时纪律同 §PERF-01（L014 fence
> /三轮中位/PSO 预热/首轮不计入）；Release = clean `build-for-testing
> -configuration Release -derivedDataPath build` + 重签直启（M2-11-02 T5 同链路，
> XCTest 闭包 + WebP PackageProduct 手动嵌入 + `Lightamer Dev` 重签，本轮照配方重做）。

### 对标① FULL 桶全链渲染 warm < 1s（OQ-2-A①，硬门 → **PASS**）

| 列 | Debug warm 中位（三轮） | Release warm 中位（三轮） | <1s 判定 | Release 轮次 |
|---|---|---|---|---|
| ARW 60.2MP | **170.3 ms**（175.4/167.5/170.3；cold 189.9） | **168.2 ms**（168.2/168.5/167.3；cold 655.1） | **PASS ✓**（余量 ~5.9×） | 轮 1 |
| RAF 100MP | **280.1 ms**（274.6/305.6/280.1；cold 763.5） | **300.6 ms**（331.0/300.6/296.8；cold 696.7） | **PASS ✓**（余量 ~3.3×） | 轮 1 |
| ARW 60.2MP（稳定性轮 2） | — | 164.2 ms（164.2/168.1/160.5） | PASS ✓（跨轮 -2.4%，带内） | 轮 2 |
| RAF 100MP（稳定性轮 2） | — | 273.8 ms（292.3/273.8/273.4） | PASS ✓（跨轮 -8.9%，带内） | 轮 2 |

- **KD-4 未触发**：两列两构建 warm 全部 <1s，门如实 PASS，无降门/挂账。
- Debug ≈ Release（60MP 170.3 vs 168.2；100MP 280.1 vs 300.6，±2-9%）——带宽主导
  本征（02 波 nlmeans 同现象，perf.md §OQ-7-A 注记同源），Debug 分栏数字有效。
- 语义注记：60.2MP > 45MP = 登记线更严侧；SpektraLab 45MP 为全分辨率印相出图，
  我方 FULL 桶全链（decode warm → terminal trio + defaultLook grade + DRT SDR 尾）
  同构映射（RESEARCH §B.1）。冷列单值记录不设门（缓存冷 + 首渲 PSO 变体噪声）。

### 对标② 尾平面缓存命中重渲 ≤ 10ms（OQ-2-A②，硬门 → **PASS 两腿**）

| 腿 | Debug 中位 ×7 | Release 中位 ×7 | ≤10ms 判定 |
|---|---|---|---|
| ① 同参二次渲染（全命中腿；前置断言 hits>0 && misses==0） | **0.034 ms** | **0.021 ms** | **PASS ✓**（余量 ~476×） |
| ② 单参数 tick 尾段重放（EOTF 基座 + record 单字段 tick；前置断言 misses==2 && hits==1） | **4.637 ms** | **5.009 ms** | **PASS ✓**（余量 ~2×） |

- 语义对齐（RESEARCH §B.2 原文语义）：SpektraLab 重印 0.01s = 同配置数据热重贴 →
  我方对应物 = 尾平面命中后的重渲腿（腿①全命中 = 重印本义；腿②单 tick 重放 =
  参数变更只重跑尾段）。腿①亚毫秒（纯缓存 blit 级）；腿② ~5ms（两尾 box 在
  preview-2560 平面真实重渲）。
- 前置命中语义断言在先（命中语义回归先红，计时门其次——KD-2 纪律）；L014 drain
  在计时窗内；首轮不计入（warm = 数据热平面，`PipeCache`）。

### 分解探针（KD-4 归因输入恒采；对标①两列数字）

| 段 | ARW 60.2MP（Release） | RAF 100MP（Release） | 说明 |
|---|---|---|---|
| decode 腿（warm） | 0.108 s | 0.073 s | 进程内二次解码（RAW9 磁盘缓存命中态） |
| 全链帧（.drt 尾，warm 中位） | 168.2 ms | 300.6 ms | 门对象 |
| 主链对照（.sdrGamma 帧，warm 中位） | 184.7 / 149.9 ms | 259.3 / 246.9 ms | 主链含 colorout+gamma 软编码尾；与 .drt 帧同量级 = DRT 尾增重非主导 |
| 同参 FULL 重渲（观测腿） | 0.0-0.1 ms（hits=2 misses=0） | 0.0-0.1 ms（hits=2 misses=0） | FULL 桶缓存（input+final）命中下限亚毫秒 |

- **主导项判定**：全链帧 ≈ 主链对照（±10-20% 轮间方差内），DRT 尾增重非主导；
  FULL warm 300ms 级 @100MP ≈ float32 全幅带宽 × 主链趟数的本征成本，无意外缺陷
  形态（尾平面在 FULL 桶漏缓存/格式转换冗余拷贝均未观察到——同参重渲亚毫秒即
  缓存腿健康的直接证据）。引擎级杠杆（TilingPlan 实战化/链趟合并）在 <1s 达标
  面前无立项必要（OQ-4-A 不触发）。
- stats 口径注记：同参 FULL 重渲腿的 hits=2 = 主链 input+final 两平面（尾段 sub-run
  的 stats 在 `runDrtTailLeg` 丢弃点不进主 run 统计——既有形态，0.1ms 时间值证明
  尾平面全命中，语义不受计数口径影响）。

### 峰值观测（checker m5）

| 轮 | peak RSS（ru_maxrss） | 判定 |
|---|---|---|
| FULL bench Debug 定向（IOP） | 4373 MB | <8G ✓ |
| FULL bench Release 直启轮 1 | 4486 MB | <8G ✓ |
| FULL bench Release 直启轮 2 | 5831 MB | <8G ✓ |
| IOP bundle 全量（本波新 bench 在内，470 tests） | **7840 MB** | **<8192 门 ✓**（零 MEMFAIL；vs SPIKE 7865 = -0.3%，贴线方差带内） |

- 100MP 跑完 footprint-now 高水位 6764-6784MB（缓存/池驻留）不回落——IOP 全量轮
  实测未推破 8G 门（池复用），维持观察；若后续连续 MEMFAIL 先查本 bench 顺序位
  （SPIKE 处置序）。

### 记录档与不对标注记（KD-3）

- **preview 全链 warm = 记录档，不参与对标**：02 波实测 ARW 13.4/13.2 ms、RAF
  14-42 ms 带（§PERF-01）+ 在案 M2-6-3 bench 合成图 85 ms——语义差异注记
  （RESEARCH §B.2 原文语义）：SpektraLab 0.01s = LUT 重贴级重印；我方全链场景
  渲染不同语义，**对标行在尾命中腿（对标②），preview 全链 warm 不与 0.01s 对标**。
- **二进制 32MB 不对标**：SpektraLab 单二进制 32MB 为我方无对应单一体——内置 AI
  模型 ≈193MB by-design（`Resources/AIModels`，`M2-10-01-SUMMARY.md:42` 锚）+
  Swift/框架面；开源 DMG 分发体积非 M2PERF SC 族（RESEARCH §B.3）。

### 对账与计数（wave 3）

- 基线 2957/16/0（02 波终值）+ 本波 Δ = **+3**（FullRenderBenchmarkTests 1 法 +
  DrtTailTests 计时 2 法）→ 预期 **2960/16/0**。实测：Layers 定向 `DrtTailTests`
  14/0/0（12+2 精确，Debug；Release 直启同 14/0/0）、IOP 定向 1/0/0（Debug+Release
  双构建 ×2 轮）、**IOP 全量 470/1/0**（Debug；469+1 精确）——skip 零新增（两样张
  在场；无样张机器口径 = FULL bench 1 法 + DrtTail 计时 2 法不 skip【合成图】，
  仅 FULL bench fixture 缺席时 1 skip）。
- 本波未跑全套 `--all`（批准制未申请）；`--all` 终值对账留 M2-11-05 终验。
- 证据日志：`/tmp/la-direct-tests-IOP.log`（Debug FULL bench + IOP 全量）、
  `/tmp/la-direct-tests-Layers.log`（Debug 尾计时）、`/tmp/la-release-m2-11-03-full.log`
  + `-full2.log`（Release FULL 双轮）、`/tmp/la-release-m2-11-03-tail.log`
  （Release 尾计时）。

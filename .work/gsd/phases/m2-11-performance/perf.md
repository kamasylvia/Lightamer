# M2-11 perf.md — PERF 计量正本（M2-11-02 wave 2 落账，2026-10-07；M2-11-03 wave 3 增 §SpektraLab 对标节；M3-2 裁⑥ spike 增 §O-1 SPIKE 根因判定节，2026-10-08）

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

## §PERF-02 内存三分法落地（M2-11-04 wave 4 落账，2026-10-07；OQ-1-A 裁决正本）

> 三分口径总纲（OQ-1-A，不得重开）：**①GUI 编辑器交互稳态工作集 ≤3GB（本节实测）**
> **②FULL 管线瞬态 = TilingPlan 窗口有界断言（不设绝对数，维持零新增）**
> **③测试宿主 8G 运行门不变（`Scripts/test-direct.sh:59 RSS_LIMIT_MB=8192` 零触碰——
> 8G = 运行门（MEMFAIL 机检），非内存 SC 门；M2-4-0 SPIKE `70e09e5` 已证 <3G 宿主侧
> 数学不可达，证据正本 = `phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md`）**。

### 口径① GUI 稳态工作集实测（KD-1；`profile/r{1,2,3}-footprint-*.txt`）

- **读数口径**：`/usr/bin/footprint`（macOS 27.0.1）`--noCategories` 摘要，主判据 =
  **phys_footprint**（与 AGENTS.md 资源监控同族口径，Instruments VM Tracker
  Dirty+Swapped 汇总同源）；辅读 = ps resident（参考列）。B 判据 = 三轮（三次独立
  app 会话）**中位 ≤3GB**。
- **场景脚本（可复现，`profile/memprof-round.sh` + `profile/cgdrive.swift` 驱动源）**：
  probe 缝建项目（link 导入**单图项目**）→ 正常 GUI 启动 → File/Open Recent 开项目 →
  网格双击开图（M2 默认链 = Develop + defaultLook(+1.5EV/+15/1.3) + DRT SDR 自动应用）
  → 编辑序列 = Z(100% 实际大小) + 滚轮平移 + F(适应屏幕) + **色温/色调轨道 drag ×10**
  （每 drag ~1.6s 间隔触发 live 重渲 + discrete commit）+ 反向滚轮平移（缩放×2 平移×2）
  → **静置 60s**（clearCaches 60s Task sweep 窗）→ 读数。
- **样张列**：RAF 100MP = `Fujifilm-GFX100S-14bits-uncompress-4_3.RAF`（`Fixtures.raf100MP`
  同源 TestRAW 镜像文件，硬链入 /tmp 单图项目；**用列 = 100MP**，KD-1 任一列口径）。
  AX 驱动 = System Events 菜单/键盘 + CGEvent double-click/scroll/drag（拖动序列 ×10
  实测每 drag 均改值——首轮 click 不改值发现，slider 需 drag 语义，驱动源在档）。

| 轮 | T0 编辑尾 phys_footprint | **T60 稳态 phys_footprint（主判据）** | resident(T60) | peak（辅助列） |
|---|---|---|---|---|
| R1 | 2392 MB | **2427 MB** | 1.68 GB | 6317 MB |
| R2 | 1914 MB | **1975 MB** | 1.14 GB | 8556 MB |
| R3 | 1809 MB | **1856 MB** | 1.10 GB | 8558 MB |
| **中位** | 1914 MB | **1975 MB ≈ 1.93 GB** | — | — |
| **门判定** | | **≤3GB → PASS（余量 ~1.55×）** | | |

> **验收复测（2026-10-07 验收 subagent R4 独立轮）**：T0 1807 / **T60 1856 MB** /
> peak 8556 MB（`r4` 正本 `/tmp/m2-11-memprof/r4-footprint-t{0,60}.txt`，会话随录）——
> T60 与 R3 逐位一致，落 1.8-2.4GB 带，场景可复现性成立；四轮中位 1915.5MB 判定
> 不变。R1 T0 2391→2392 与 resident 列 1.64→1.68 / 1.11→1.14 为验收批对照
> `profile/r{1,2,3}-footprint-*.txt` 正本的换算勘误（参考列，主判据 T60 列原值无误）。

- R1 略高（2.43GB）：R1 会话含 AX 通道调试动作（直方图→波形 toggle click-test）——
  scope 平面切换一次的会话面；R2/R3 = 纯脚本序列。中位口径对此稳健。

### 机制核验（KD-1；enforceBudget/LRU 实活）

- **三轮统一日志查询**（`/usr/bin/log show` predicate `enforceBudget|evict`，--info，
  会话全程窗）= **零命中**（`profile/r{1,2,3}-mech.log` 仅表头）+ **D-26 toast 零出现**
  （>500MB 释放才 toast）→ 稳态 footprint 低于 3GB 预算 → `enforceBudget` 60s sweep
  **no-op（设计语义：超阈值才逐出，`PipeCache.enforceBudget` guard 分支）**。
- **如实注记（触发态证据边界）**：三轮均在预算内运行 → GUI 会话内「预算执行器触发态」
  证据不可得（未越界即无触发日志/toast）——触发面机制证据由**口径①断言层（T2
  MemoryBudgetTests 注入阈值用例）**承载：越界即逐出 = footprint 有界的机制上界在
  单测钉死，与本节稳态负证两层互证（KD-2① 分工）。insert-time LRU 逐出
  （`evictUnderBudget`）无日志面（代码事实）——其正确性同样由 MemoryBudgetTests
  既有 keep/evict 矩阵钉死。

### 观察项 O-2（新登记）：100% 缩放腿瞬态峰

- `phys_footprint_peak` 三轮 6317 / 8556 / 8558 MB——峰值腿 = **Z(100% 实际大小) 缩放
  瞬态**（100MP 全幅显示管线工作面）；F(适应屏幕) 回落后稳态回落至 1.8-2.4GB。
- 口径注记：稳态门 = OQ-1-A①（T60 中位），**瞬态不入门**；瞬态峰 8.6GB 与宿主 8G
  运行门数字无关（口径③ = 测试宿主全套轮 ru_maxrss，不同主体不同语义）。移交
  M2-11-05 GUI 走查轮顺带观察（16GB 机器 100% 缩放 100MP 体验如遇 swap 压力，
  归 O-2 处置：TilingPlan 窗口化在显示腿的杠杆评估——超本 plan 半径，禁改码）。

### 口径② FULL 窗口（负证，零新增）

- `MemoryBudgetTests.testNLMeansFullFootprintBudget`（bilateral FULL Δfootprint <3GB
  D-C1 门）+ `testCompositeFullWindowedPlaneSizes`（FULL 窗口化 O(视窗) 精确台账）+
  `PreviewChainPerfTests.testFullToneEqualMemoryBudget`（:178）**零触碰且在册绿**——
  T2 定向轮复跑在案（本节下方对账）。FULL 瞬态 = TilingPlan 窗口有界断言**维持**，
  不设绝对数（OQ-1-A②）。

### 口径③ 宿主 8G 运行门（负证，零触碰）

- `Scripts/test-direct.sh:59 RSS_LIMIT_MB=8192` **零变化**（`git diff Scripts/` 空，
  T4 机检）；8G = **运行门**（MEMFAIL 机检兜底）非内存 SC 门——防误读口径行，SPIKE
  证据指针见节首引文。

### 对账与计数（wave 4 增量）

- 基线 **2960/16/0**（03 波终值）+ 本波 Δ = **+1**（MemoryBudgetTests 新增 1 法，
  T2）→ 预期 **2961/16/0**。T1 为 GUI 实测轨零新测（checker E1 真链 = 真 GUI app
  真样张三轮）。**T2 实测**：`--bundle IOP MemoryBudgetTests` 定向 **14/0/0**（13 既有
  + 1 新增精确，func test 13→14）+ IOP 全量 **471/1/0**（470+1 精确，149s，peak 7650MB
  < 8192 门零 MEMFAIL；唯一 skip = 既有 SkinRegion Vision 环境件，基线内）。全套
  `--all` 终值对账留 M2-11-05 终验（批准制）。

## §PERF-07 终验带内复核（M2-11-05 T2，2026-10-07）

- **终验净轮**（第 3 试全套 `TOTAL|2961/16/0|1081s` 干净绿；恢复协议两轮前置——
  App bundle ToneEqual 崩溃家族四红二绿，台账见 GOAL-STATE Flaky 清算台账追加行）
  内 `Perf07MassApplyTests` 双测绿：`PERF07-GATE segments1+2 10k: **0.543s**
  (gate ≤ 5.000s)` + `PERF07-PROBE composeSegment: 0.524s` / `claimBatchApply:
  0.020s` / `FIXTURE-BUILD: 1.655s`；config 行 = Debug harness record（门本体 =
  Release 轮，`Perf07MassApplyTests.swift:181/192`）。
- 判定：**带内即过**——vs 在案 0.490s（09 perf 在案锚）= +10.8% 机器态漂移，
  门余量 ~9.2×（≤5s）；万张 apply Delivered 终态维持。证据 =
  `/tmp/la-direct-tests-Sessions.log`（净轮 Sessions bundle 内）。

## §O-1 SPIKE RAF 100MP warm 双峰根因判定（M3-2 裁⑥ 补批，2026-10-08；RESEARCH-NOTES §8 设计的兑现）

> 方法：**工作树探针测试**（未入 git，源码快照 + 日志正本 =
> `phases/m3-2-fsim-research/evidence/M3-2-SPIKE-README.md` 文件索引；产线
> diff = 0）。每帧 ContinuousClock 计时窗内含 L014 drain（M2 bench 同形）+
> 进程内协变量（主 run hit/miss/planesRendered、PipeCache 字节、
> phys_footprint）+ 外部 1s 采样（ioreg Renderer Utilization、
> memory_pressure、swap）。GPU 频率直读（powermetrics/IOReport）需 sudo，
> 本环境不可用——以间接判别式替代（RESEARCH §8 ③④：分段相关性 + 状态变量
> 二分）。分段口径注记：以**每帧统计 + 相位对照**替代 os_signpost（分辨率
> 更高；既有 signpost 面只覆盖 decode/pixelpipe 整段，无箱内分段）。

### 状态变量二分结果（探针六相位 × RAF/ARW 双列 + 列序反转）

| 相位（RAF 列，recap 轮正本） | n | min | 中位 | max | 判读 |
|---|---|---|---|---|---|
| base（bench 形状：tick + 共享 cache，前 5 帧） | 5 | 21.4 | — | **81.0** | **瞬态带**（decode 后第 0-8 帧随机 21-98ms） |
| base（同相位 i≥5 稳态） | 35 | 15.1 | ~17 | 24.5 | 稳态带（= O-1 的「14ms 档」本态） |
| fresh（每帧新 PipeCache，分配回收态） | 25 | 15.7 | 17.4 | 25.1 | **稳态无瞬态**——缓存增长/换页churn 缺席即瞬态缺席 |
| same（不 tick，全命中） | 12 | 0.03 | 0.04 | 0.11 | 计算面地板（整条管线的确定性下限） |
| gap（帧间 400ms 空闲） | 15 | 16.6 | 22.0 | 28.8 | **空闲衰减效应**（ARW gap 中位 20.7 同现——双格式共有） |
| sdr（.sdrGamma 无 DRT 尾） | 20 | 15.2 | 16.0 | 26.8 | DRT 尾非主导（与 .drt 同带） |
| clr（每帧 clearCICaches） | 15 | 15.0 | 16.2 | 25.2 | CI 内部态非主导 |
| ARW base（第二列，全程） | 40 | 13.7 | 15.0 | 18.7 | ARW 在 RAF 6+ 帧之后 = 无瞬态（= 在案「ARW 稳定」的成因） |

- **列序反转（testProbeARWFirst，4 探针合跑轮）**：ARW 作为进程**第一列**时
  同样出现瞬态——base i0-i5 = 18.3/18.7/**53.3/80.0/46.3**/27.6，i6 起回落
  14-19。**瞬态非 RAF 专属**；在案 bench「ARW 无此现象」= ARW 恒列第二
  （吃进 RAF 已扰动的分配器稳态）+ 60MP 开图内存增幅小，非格式免疫。
- **120 帧连跑（testProbeRAFGrind）**：n=120，min 13.58 / med 15.16 /
  p90 18.65 / max 45.04——**仅帧 5-7 为瞬态（27.6/45.0/28.3），其后 113 帧
  零自发翻态**。稳态渲染自身确定性，双峰非管本征。
- decode 腿排除：进程内 warm decode 稳定（RAF 74-81ms、ARW 110-112ms，
  跨列跨轮零漂移），且在计时窗外——「CI 解码状态机」候选排除。
- 系统态排除：全程 pmset 无热警告、系统空闲 ≥80%、swap 零活动、GPU util
  1s 均值 ≤10%——「系统热节流/内存压力带」候选排除。
- LUT 烘焙 LRU 静态排除：bench 链 = terminal trio + defaultLook 三件
  （exposure/contrast/saturation），**无 lut3d**，`LutEncodingCatalog` 烘焙
  缝不在本 bench 消费面——候选①出局。

### bench 形状进程内复刻 + 跨进程复跑（判定链收口）

- **进程内复刻**（testProbeBenchShapeReplica，bench 形状 ×6 轮/列）：
  RAF round0 = cold 750.4 → warms 15.0/14.2/**49.5**（瞬态尾部一帧落进计时
  窗）；round1-5 cold 14-15.6、warms 全带 13.9-15.6。ARW round0 warms
  13.7/13.4/13.1。**瞬态只在「fresh decode + 冷管线」后的头几帧存活，
  且落窗位置随机**。
- **跨进程真 bench 复跑 ×4**（run4-7，日志存档）：

| 轮 | RAF cold | RAF warm ×3 → 中位 | ARW warm ×3 → 中位 |
|---|---|---|---|
| run4 | 2.5 ms | 82.1 / 57.5 / 51.7 → **57.5** | 13.6/15.6/14.5 → 14.5 |
| run5 | 223.4 ms | 44.7 / 81.1 / 37.1 → **44.7** | 13.5/12.3/12.8 → 12.8 |
| run6 | 746.4 ms | 15.0 / 50.2 / 46.5 → **46.5** | 13.4/13.1/13.2 → 13.2 |
| run7 | 759.9 ms | 14.7 / 50.6 / 92.6 → **50.6** | 13.3/13.3/13.7 → 13.3 |

  RAF 三帧中位 44.7-57.5（原 O-1 带 38.9/42.0/14.0 同型），单帧跨
  14.7-92.6；ARW 四轮 12.3-15.6 全稳。**14↔42 双峰按需复现**。

### 根因判定（O-1 结案）

**判定 = bench 采样窗伪影 + 交互态空闲衰减，两层环境效应叠加；非管线缺陷，
非 RAF 解码状态机，零产线 diff 保证。**

1. **主因（bench 14↔42 中位翻态）**：M2 bench 的 3 个计时 warm 帧落在
   「fresh decode + 冷管线」后第 4-6 帧——恰为**开图内存增长瞬态带**
   （PipeCache 向 3GB LRU 预算增长期的 Metal 纹理新分配/换页 churn，单帧
   21-98ms，持续 0-8 帧、逐轮随机）。3 帧中位落进瞬态 = 40ms 档，错过 =
   14ms 档；run4（cold 2.5ms，重活在 decode 侧）整窗全瞬态 = 57.5。RAF 的
   瞬态窗更宽（100MP 开图 fp 增幅 5.1→6.4GB + 冷 CIRAW GB 级中间面 vs
   ARW 2.5→3.9GB）→ 命中概率更高——格式差异是**幅度差**而非机制差。
2. **次因（拖动尾尖峰 10-52ms 带，补充裁定）**：帧间空闲 ≥ 数百 ms 后下一
   帧 +50-100%（RAF gap 中位 22.0 vs 连跑 ~17；ARW 20.7 vs ~15），双格式
   共有、连跑即消失——空闲期资源衰减（GPU 功率态或 VM 回收，本环境无
   sudo 不可分辨，判别止于此层）。人速拖动天然带帧间间隔 → 拖动帧型的
   尖峰带由此解释；bench 连跑帧型不受影响。
3. **稳态结论**：preview-2560 全链 warm 稳态 RAF 14-19ms（p90 18.65）/
   ARW 12.3-15.6ms，全命中地板 0.03ms——PERF-01 判定移交 M2-11-04 的
   「RAF 未稳态达标」观察项自此有根因解，**维持不判缺陷、不设门**的在案
   裁决；如需稳态数字，bench 侧补偿 = 加深 settle（≥8 帧）或扩大采样窗
   （≥10 帧），属测试基建改造（未实施，不在本批半径）。

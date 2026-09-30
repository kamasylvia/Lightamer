# M2-6-1 SUMMARY — OpenDRT 核（wave 1，8 任务）

> 执行：ZCode subagent worker，2026-10-01 夜间连跑（`paused=false`/`auto=true` 每任务边界核过）。
> 正本 = M2-6-1-PLAN.md（checker 修正版 905e979）。基线 = 2327/16skip/0fail。

## 任务逐条（commit SHA）

| 任务 | 交付 | commit |
|---|---|---|
| T1 | `DrtRecord.swift`（四枚举 + 53 参数 + 12 顶层 + legalEOTFs + isHdrEncoding + stableHash）+ DrtRecordTests 17 方法（LAYERS） | `feat(core): drt record schema with eotf linkage` |
| T2 | `DrtEotf.swift`（Float64 七函数）+ `DrtEotfKernels.metal`（encode/decode/constants_probe）+ DrtEotfTests 13 方法（LAYERS） | `feat(core): eotf encode kernels for display transform` |
| T3 | `OpenDrtReference.swift`（Float64 参考实现，25 阶段结构图头注）+ DrtKernelGoldenTests T3 段 10 方法（IOPP） | `feat(core): opendrt float64 reference implementation` |
| T4 | `OpenDrtKernels.metal`（drt_opendrt 单 kernel + uniforms 大小探针）+ golden 探针三件套 × 参数四点（同文件 +5 方法 = 15） | `feat(core): opendrt metal kernel with golden probes` |
| T5 | `DrtPresets.swift`（look 7 + tonescale 14 + white 7 + applyPreset/isCustomLook/resolved）+ 仓根 `NOTICE` + DrtPresetsTests 11 方法（LAYERS） | `feat(core): opendrt preset snapshots with provenance notice` |
| T6 | sidecar v6 additive（schemaVersionCurrent 6 + displayTransform 双向）+ DrtSidecarTests 8 方法（APP） | `feat(sidecar): schema v6 display transform record` |
| T7 | `TerminalTailPolicy` 收敛（edrDisplayLeg 派生化）+ DrtMethodBox/EotfBox + drtTail 尾段装配 + E1 四传点/测试传点机械替换 + DrtTailTests 12 方法（LAYERS） | `feat(pipe): drt tail segment with terminal tail policy` |
| T8 | 本文件 + DECISIONS + GOAL-STATE 续接点 | `docs(m2-6): close out plan 1 opendrt core` |

## 测试数变化（对账 = BUNDLE-MAP 行）

- 基线 2327/16skip/0fail → **终态 2403/16skip/0fail**（+76 = 17+13+10→15+11+8+12，逐行对账精确）。
- 七 bundle 终态：IOP 467/1、IOPParity 357/3、Layers 234/3、Library 430/4、Sessions 279/4、Export 260/1、App 376/0（skip 全部为既有在案 skip）。
- 全套跑法：**逐 bundle 定向轮**（`--bundle <X>`，每 bundle 独立进程，MEMFAIL 8G 机检内置未触发；全程峰值 947MB@Layers）。`--all` 单进程串行等价覆盖，未触发报备需求。

## 容差谱实测（KD-8 逐断言签注 → 详见 DECISIONS §D4）

| 层级 | 计划带宽 | 实测 | 结论 |
|---|---|---|---|
| EOTF 规范锚点 | ≤1e-4 | PQ100=0.50808（4 位表值精确命中）；PQ1000=0.751827（表值 0.752 三位 → 锚点带 1e-3，签注）；HLG 0.75→0.264963 | ✅ |
| Swift Float64 往返 | ≤1e-6 | 七函数 × 三峰值 ramp 全 ≤1e-9 量级 | ✅ |
| GPU vs Float64（EOTF encode） | p99.9≤1e-5 / max≤5e-5 | max ≤7.3e-6（七函数全绿） | ✅ |
| GPU vs Float64（st2084 decode） | p99.9≤1e-5 | p99.9=2.9e-5 → **签注升带 5e-5**（灾难性消去源分析见 §D4；numpy float32 仿算同量级） | ⚠️ 签注 |
| OpenDRT kernel golden（12 组合） | p99.9≤1e-5 / max≤5e-5 | **worst p99.9=5.4e-7，max=6.9e-7**（float32 量化地板；KD-8 升级协议未动用） | ✅ |

## kernel PSO 编译耗时观察

- 单 PSO（drt_opendrt）lazy build 在首次 dispatch 内完成，测试无感（<100ms 量级，未单独计时——>2s 的 E3 观察线未触发）。参数 buffer 化（244B）验证：同 PSO 同输入位精确、参数点切换零重编译（golden 四参数点复用同一 PSO key）。

## EOTF 常数终式引用（DECISIONS §D2）

- PQ：ITU-R BT.2100 分式（m1=2610/16384, m2=2523/32, c1=107/128, c2=2413/128, c3=2392/128），encode=decode 精确逆。
- HLG：reference OOTF γ=1.2 + 逆 OETF，**OOTF 在绝对 1000-nit 域上做**（任意峰值 round-trip 精确——域换算在边界一次进出）。
- BT.1886：Lb=0 → β=0 → 纯 2.4 幂（dctl 同型）。
- gamma 族：纯 1/γ 幂，[0,1] clamp（D-COL4 clamp 家园）；linear = 无 clamp 恒等（EDR headroom 腿）。

## 结构图头注与 dctl 逐段对应（AC#4 清单）

参考实现 25 阶段（[0]–[24]）↔ dctl `transform()`（OpenDRT.dctl:737-1211）逐段行号：
[1]:962-964 · [2]:967-971 · [3]:974-976 · [4]:979-983 · [5]:985-1013 · [6]:1016-1022 · [7]:1024-1036 · [8]:1038-1044 · [9]:1046-1055 · [10]:1062-1072 · [11]:1080-1088 · [12]:1090-1100 · [13]:1108-1110 · [14]:1112-1114 · [15]:1122-1130 · [16]:1133 · [17]:1135-1137 · [18]:1139-1140（→display_gamut_whitepoint :593-732）· [19]:1142-1152 · [20]:1154-1155 · [21]:1157-1160 · [22]:1174 · [23]:1177-1180 · [24]:1183 · 前置常数 :943-959 · EOTF 段 :1185-1195 = 本计划 EotfBox（分离，KD-4）。
**执行期修订一处**：KD-3 预勘的阶段骨架（21 阶段）与 dctl 实读有出入（hue contrast 在 hyperbolic 之后、mid-purity 三段结构）——以 dctl 为准重排为 25 阶段，头注即终版（DECISIONS §D5）。

## 偏差与发现

1. **HLG 峰值归一**：首版把 peak 换算混进 OOTF 幂项 → 非参考峰值 round-trip 失败；改为绝对域进出（DECISIONS §D2），往返精确。
2. **Metal gamma 族通道 bug**（自测抓到）：`float3(scalar)` 构造 splat 覆盖未变换通道 → 改逐通道 helper。
3. **尾平面格式与 blit**（T7）：resident watermark/borders 的 blitIdentity 用 blit 拷贝，blit 不能跨格式转换 → 尾段全平面携带显示格式（SDR unorm 量化=最终量化，字节等价）。
4. **walk skip**（T7）：skipped 模块的 ROI 钩子也必须跳过，否则 borders 画布协商进主链平面。
5. **测试 L014 自伤**（T7）：DrtTailTests 初版读回无 fence → 全零误诊；补 drain 后全绿。诊断中间产物已清除。
6. **版本 pin 机械同步**（T6，申报内）：SidecarV5Tests 1 处 + SidecarMetadataV3Tests 3 处 v5 字面量随 bump 同步（断言零弱化，T6 commit body 申报）。
7. **flake 记录**：SidecarV5Tests write-leg 文件未找到 ×1（异步 store 时序），隔离复跑即绿 + App 全量复跑绿；归因 = 测试时序，非产品代码。

## P3/M2-6-2/P2 交接面

- P3 面板消费：`DrtPresets.applyPreset`（单 discrete commit）+ `legalEOTFs` 吸附 + `resolvedCreativeWhiteOrdinal`；historyHash 折叠载体 = P3 history item（本计划零触 HistoryStack，DrtSidecarTests 已 pin 解耦面）。
- M2-6-2（P2）：aces20 渲染臂 = `DrtMethod.isRenderImplemented` 翻 true + DrtMethodBox 分派臂 + kernels；NOTICE 条目 2 占位。
- M2-6-3（P3 T5）：Post 四件插槽 = DrtMethodBox 与 EotfBox 之间（74/75 之间序位锁死，guard 断言在册）；display-referred 强度标定同批。

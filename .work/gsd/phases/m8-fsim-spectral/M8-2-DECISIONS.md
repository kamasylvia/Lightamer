# M8-2-DECISIONS — FSIM 管线集成执行期裁决（2026-10-25）

> 正本关系：charter = `CONTEXT.md`（D-M8-1/D-M8-8 + X3/X4/X7 + 红线 17 条）；
> 执行正本 = `M8-2-PLAN.md`（checker `40bccfd3` + fixer `dd9490fe` + R1 `bc2baf39`
> 后 HEAD）。本文 = 执行期偏差申报 + 分叉点登记（五件套之⑤）+ 折键收窄差
> + K 标定终值。行内 `(deviation)` = plan 文本偏离；`(review)` = 评审回注承接；
> `(measured)` = 实测锚定。证据正本 = lightamer-evidence 私仓
> `m8-fsim-spectral/evidence-m82/DUAL-ARM-GOLDEN.md`（pack policy B）。

## 一、process 账本 bump 五件套勾对（红线 17，收口门）

1. **case doc** ✓ — `RenderProcess.v2` doc = 账本行（fork 点/冻结臂/折键
   契约/单源键声明）；v1 doc 追加冻结臂登记（M6-2 预案 ①-⑤ 兑现注记）。
2. **AGENTS 账本行** ✓ — 架构索引「process version」不变量行扩 process 账本
   （v1 → v2 全登记）+ 里程碑表 M8 行 + UserDefaults 零新键声明（红线 11）。
3. **新旧 golden 三件套** ✓ — v1 零漂移：FilmDeterminismTests 全套源级零改
   跑绿（filmRampPlaneHash `14_365_179_805_968_017_957` 主门）+ legacy/v1
   端到端逐位 + 缓存键零增量（A1/A2）；v2 光谱：ramp 哨兵
   `3613671270926763817` + fixture 哨兵 `7557687968680693683` + 中性闭合
   注册值（三件套正本 = SpectralDualArmGoldenTests）。
4. **mint 升号** ✓ — `RenderProcessVersion.current = 2`；App 层 mint 点零改
   （current 即 2）；sidecar 写面 `"process": 2` 断言在册（RenderProcessLedger
   Tests）+ HDR/Mertens birth stamp pin 随 bump 机械移动（30a05d20 申报）。
5. **分叉点登记（本条 = ⑤）** ✓ — 两处 exhaustive switch，编译器逐点指向：
   - `PixelPipe.assembleFilmLeg`（:1262 域）——arm 分派 + 私有
     `assembleDensityFilmLeg`（冻结臂，pre-M8-2 字节原样）/ `assembleSpectralFilmLeg`
     （光谱臂：tc_lut 缓存槽 → solveSpectral → SpectralGPUPayloads）；
   - `FilmTailAssembly.policyTag(for:)`——arm 折叠 tag（`.v1` =
     `lightamer.film.subrun.v1` 逐位不变 / `.v2` = `lightamer.film.subrun.v2-spectral`）。
   `processVersion` 反查 switch + `resolving` clamp 表 = 账本编译期半（第四处
   指向点，RenderProcess.swift 内）。

## 二、折键收窄差登记（review m1，charter 契约的修订面申报）

- fold discriminator = **resolved arm**（`RenderProcess.resolving` 的输出），
  **窄于** RenderProcess header `rawValue > 0` 字面形（:41-43 的契约字面含
  v1 折值）。v1 文档（raw=1）与 legacy（absent/0）走同一 tag
  `lightamer.film.subrun.v1` → seed 及全部下游缓存键**逐位恒等**——这是
  filmRampPlaneHash 冻结主门的键半要求（A2 端到端实测：legacy → v1 渲染
  misses/totalBytes 零增量）。字面形若照抄会把 v1 档键全体迁移 = 主门破产。
  本条 = charter「非 legacy 才折」的精化非违背：光谱核开关（≥2）才是语义
  分叉面，v1 是冻结代际非新语义。负测：v2 seed = 四项 canonical 序 + 光谱
  tag 的独立 FNV 重算精确值钉死（RenderProcessLedgerTests）。

## 三、K 标定终值（T2，plan「K 标定 = 光谱域重标」正本）

- 光谱域 K 标定 = **build 期自解中性对（solvedPrintCC）+ midgrayFactor**，
  随表交付；运行时 solve 面对它**零追加**（无独立运行时 K 项）——build 的
  2D Newton 梯自解 (m,y) 驱动中灰 log 通道比归零，实测链头 print raw 通道散
  ≈3.7e-6（中灰印相反射中性恰 0 纪律的光谱域形态，RFC-028 我方域）。
  portra×portra_endura 终值 = **(M=33.05, Y=26.84)**。
- `(deviation)` plan 预设「neutral_print_filters ±10 CC sanity 带续用」不成立
  （实测偏移 M −18.5 / Y −25.7 CC）：该带写作时点早于 M8-1a III.1 的 build
  期自解 pivot——自近似 dichroic/SPD（X6）解自己的中性，与实测表的 premises
  不同域（0.441 散 @ 实测 CC 实录在案）。不变量改为**中性本身**
  （gray-error-0，test 2 钉死）+ 偏移注册值 ±2 CC 漂移带（test 1 钉死）；
  锚 JSON byte-verbatim 不动。M8-3 面板 readout 语义不受扰（readout 数值随
  核变 = by design，D-M8-7）。
- exposureEv = solve gain 消费层兑现（D-M8-8）：totalGain = autoGain × 2^ev，
  施加面 = print 曝光槽（log10_print_exposure += log10(gain)，印相曝光归一
  语义；expose 链头 ev_scale 恒 ≡ 1——引擎表值 + uniform 写面双钉）。
  record 项不入缓存键（T2 test 4 一条缓存项断言）。

## 四、coupler 臂形态（X3/D-M8-4 的 M8-2 兑现面）

- 降采样臂 = **1/4**（M8-1B probe ③ 裁决消费；payload 构造 decimation: 4）。
- **`(deviation)` 生产 v1 couplers-off**：D-M8-4 裁「v1 含 coupler correction」，
  但 profile 资产集**无 coupler 矩阵 / Langmuir 数据**（28 张 JSON 键面实测
  零 coupler 键；dt pack 本地无克隆，spektra_fetch 运行时拉取域不入仓）——
  数据未至，诚实务实态 = `.neutral`（couplers-off）出厂。结构与算子全在位
  （stage A + 分离模糊对 + B 内 bilinear 上采样 + Kr/K=0 哨兵 + ds 1/4 臂），
  激活 = 数据摄取后 payload 构造一行换 face。couplers-off 跳过 A+blur
  dispatch = **value-identical**（零矩阵 → develop_corr ≡ 0 → develop 减零；
  T1 测试逐位断言），同时兑现 8G 超门 fallback 档（砍 coupler）的默认安全面。
  8G 超门 fallback 无需运行时判定——默认即 fallback 档，全帧无新增中间面。
- corr blur 20µm 物理面（M8-1B 移交）：随 coupler 激活一并接线（数据未至
  = 挂账 M8-3+）；当前 blurRadius/blurSigma = 载体默认（不消费）。

## 五、strength mix 与曝光施加形态（T1 编排切分申报）

- `(deviation)` **新增 kernel 一枚**：`spectral_film_strength_mix`
  （SpectralFilmKernels.metal 尾部追加，RFC-025 密度域 log mix +
  共享多项式 log10/pow10；七 stage fused 族零触碰）。理由：strength < 1 的
  mix 是面板一 etc. 一等公民滑杆，光谱臂必须兑现（D-M8-7 面板零新增 =
  面板继续工作）；无既有 kernel 可承载 mix（ABI 无 slot），七 stage/kernel
  族的 bit-exact 金面不重开。T1 SC 文件集随之扩一枚（本条即申报）；
  FilmSubRunKernels.metal 恒零 diff 维持 ✓。
- mix 路径 = strength < 1 时 stage B → 中间面 → mix(intermediate, input) →
  output；**strength ≥ 1（默认档）B 直写 output，中间面不存在**（H-M2
  内存姿态的默认面兑现；B1 ramp 哨兵 = 直写面逐位）。
- mix 输入腿 = log10(orig·gain)（密度 kernel 同形：gain 介入 inLog，
  strength 0 时输出 = gained input）。
- `(deviation)` 扩展 uniform face：slots 34/35（mixStrength/mixGain）——
  kernel 侧 SF_U_TOTAL=34 define 属冻结族，mix kernel 按字面 index 读；
  Swift 侧 UniformSlot.total 36（KernelGolden 体积/计数断言 total 相对，
  全绿零改）。

## 六、曝光/CC 施加点形态（T2 落地面，dispatch doc 同文）

- solve gain → `log10_print_exposure += log10(gain)`（print 曝光归一 = 印相
  曝光归一语义，D-M8-8 的 letter 兑现；expose 链头 ev_scale 恒 1）。
- CC delta → `enl_lo[1] += kM; enl_lo[2] += kY`（E3 滤波向量形：print 表
  **输入坐标**密度移位 = 冻结密度 kernel `density.g -= kM` 的代数孪生）。
- **`(measured)` kM/kY = delta 非总量**（fix `8e7d6947`，T5 ramp golden 抓出）：
  光谱表经 dichroic 光携带 build 中性 CC，运行时移位必须相对
  `tables.solvedPrintCC` 取 delta；密度臂形态相反（其 LUT 反演 post-pack
  系统 → kernel 减总量）。两臂构造性不对称，dispatch doc + 测试双钉
  （neutral face 零 delta 逐位；+10 CC M 位移输出）。
- 手动 Y/M / content-adaptive delta 走同一 enl_lo 形（E3 一次近似：dichroic
  光谱质变化 = 二阶，挂账登记——逐 CC 表族重建 = 秒级带不可作滑杆路径）。

## 七、tc_lut 缓存槽（X7 承载形态申报）

- 三槽并存、各自 LRU（T3）：**tc 槽 = 整 bundle**（SpectralFilmTables——
  tc_lut 含上游拟合+展开+积分全成本，引擎单体 Float64 build 与 PCHIP 集
  不可分，引擎零 diff 冻结）；print/scan 槽 = 33³ PCHIP 具名切片
  （同一次 build 扇出填充）。容量 **tc 6 / print 8 / scan 8**（bundle
  ≈5.6MB → tc 槽 ≈34MB 上界）。键 = materialPairHash（FilmSolveCache 键形
  先例）；bakeCount 可观测同形（fill 计数，touch 不计）。
- 消费面 = T1 光谱臂 payload 构造（assembleSpectralFilmLeg → tables(forPairHash:)）；
  GPU payload **每 run 从缓存表重造**（run-scoped 实例——M5-1-03 单主纪律，
  uniforms 无跨 run 竞态；「禁每 run 重建」的禁对象 = 秒级表构建，命中面
  T3 测试钉死）。payload 重建成本 = 5.6MB 缓冲上传 + cmax 表（64×720×18
  轮二分，一次性）——若实测构成帧热点，cmax 表升格为第二缓存面（挂账
  M8-3+ 观察项）。

## 八、T4 diff 面申报（编译器指向的必然连带）

- `(deviation)` plan T4 SC「diff 恰 RenderProcess.swift + AGENTS.md」不可满足
  于 exhaustive switch 纪律下：`.v2` case 落地时编译器强制分叉点补臂
  （assembleFilmLeg + policyTag(for:)）——**补臂必须与 case 同 commit**
  （bump 前后语义由编译期保证 = plan 自己的红线），本批即如此落地
  （T4 commit 含 PixelPipe.swift + FilmTailPolicy.swift）。
- `(deviation)` 机械移动的既有 pin 随 bump 同 commit 修订（M8-1a
  deliberate-re-open 先例）：SidecarV10Tests（all/current 账本面）、
  RenderProcessSeamTests（stamp 表 verbatim face）、StackMergeServiceTests
  （HDR/Mertens birth stamp 字面 1 → current.rawValue）、SpectralLegForkTests
  （T1 时的 pre-bump clamp/分叉/逐位面 → post-bump 形态，30a05d20——含
  couplers-off 测试的 CC delta face 适配）。

## 九、中性闭合带偏离（T5 B3）

- `(deviation, measured)` plan 带 ≤2e-3 = 密度臂反演构造的 premise；光谱链
  无反演面，实测闭合 = **0.1301（13.0%）** 注册钉死（±0.01 漂移带）。机制：
  链头 print raw 通道散 ≈3.7e-6 ✓（K 标定兑现）→ paper 密度曲线三通道差
  （≈0.14 密度 @ mid 曝光）+ scan 光谱积分残差 = 输出面 ~13%。上游同面
  在本资产域不闭合（M8-1A III.1 同族申报）。证据正本 = evidence 私仓
  DUAL-ARM-GOLDEN.md。

## 十、哨兵登记（probe ④ 消费形态）

- M8-1b probe ④ `10129511468721193651` **消费 = 登记**非生产复现：probe 的
  runChain blur 对跑两遍（probe-only 序列，σ 翻倍）+ 合成 coupler face——
  与生产面（单 blur 对 + couplers-off 直写）结构不同，哨兵不可互换。
  生产哨兵 `3613671270926763817`（ramp512）+ `7557687968680693683`
  （fixture）为 T5 新钉；legacy `14_365_179_805_968_017_957` 源级不动。
  正本 = evidence 私仓 DUAL-ARM-GOLDEN.md。

## 十一、ΔN 记账（分账带 +20..26）

| 任务 | commit | 测试增量 | plan 带 |
|---|---|---|---|
| T1 换臂分叉 | `ba568763` | SpectralLegForkTests **6** | +2..3 |
| T2 solve 光谱域 | `9440f271`（见 git log） | SpectralSolveTests **5** | +4..5 |
| T3 bake 家族 | 见 git log | SpectralBakeTests **5** | +3..4 |
| T4 process v2 | 见 git log | RenderProcessLedgerTests **5** | +3..4 |
| T5 双臂 golden | 见 git log | SpectralDualArmGoldenTests **8** | +5..6 |
| fix CC delta | `8e7d6947` | 0（回归随 T1 文件修订） | — |
| 机械 pin 移动 | `30a05d20` | 0（既有 pin 改写） | — |
| T6 收口 | 本 commit | DualArm +**2**（矩阵/导出冒烟） | +3..4 |
| **合计** | | **+31** | +20..26 |

- **越带申报**（+5）：①T1 +3——分叉骨架测试外，光谱 dispatch 编排接线面
  （plan 归 T1 的 SpectralPayloads 接线）需自有直接面（couplers-off 逐位
  复现/序独立性/strength mix/CC delta/probe 跟随/nil degrade），plan 的 +2..3
  未给编排面单列测试行；②T5 +2——缓存级折键端到端（A2）与 FilmRecord 键
  集冻结 grep（C2）是「折键负测 + 零新键 grep」SC 的端到端形态，plan 行只
  计了 seed 负测与 sidecar 组；③T6 −1..2——sidecar 往返 + 零漂移负测组在
  T5 文件内先行交付（plan T6 行的重复列项），T6 实际 +2。
- 全套预期 = 基线带 M8-1b 终态 4242 + 31 = **4273 ∈ [4256, 4274] ✓**（顶带）；
  --all 对账归 M8-3 收口轮。新 skip = 0（probe 族 5 skip 为 1b 存量）。

## 十二、环境观察（非本批缺陷）

- IOPParity 全量首轮 GoldenColorTests 2 法失败（ColorSync low-end-zone
  unbounded + neutral patches 全零渲染）：**环境型 flake 家族**——同 build
  隔离轮 6/2/0 全绿，且失败时点早于任何 M8-2 测试在 bundle 内执行
  （字母序 GoldenColor 先行）。非 M8-2 面（色彩管理零触碰）。全套 --all
  对账轮（M8-3）按 M2-11-01 verdict 口径复核。

## 十三、偏差清单汇总（逐条）

1. `(deviation)` T1 SC 产线文件集 + SpectralFilmKernels.metal（strength mix
   kernel 一枚；七 stage 族零触碰）——本文五。
2. `(deviation)` 中性 ±10 CC 带 → 注册偏移带 + 中性不变量——本文三。
3. `(deviation)` 生产 couplers-off（数据未至；结构与 1/4 臂在位）——本文四。
4. `(deviation)` strength mix 中间面（strength < 1 才存在）+ uniform 34/35
   扩展——本文五。
5. `(deviation)` tc 槽 = 整 bundle（引擎单体不可分）——本文七。
6. `(deviation)` T4 diff 面（编译器强制分叉点同 commit）+ 机械 pin 移动——
   本文八。
7. `(deviation)` 中性闭合带 2e-3 → 注册 13.0%——本文九。
8. `(deviation)` probe ④ 哨兵 = 登记消费非生产复现（probe 双 blur 序列）——
   本文十。
9. `(measured)` kM/kY delta 修复（8e7d6947）——本文六（非偏离，缺陷修复 +
   回归钉死登记）。
10. `(measured)` ΔN +31（越带 +5 申报）——本文十一。

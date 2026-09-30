# M2-5-1-ACCEPTANCE — Grade 新件核 wave 1 独立验收报告

> 验收批：2026-09-30（独立验收 subagent）。对象 = plan `M2-5-1-PLAN.md`
> （checker 修正版 `87c039d`）+ 执行批 8 commits（T1 `ba70717` / T2
> `1853026` / T3 `8d3d145` / T4 `0434afd` / T5 `2e84312` / T6 `e2aa894` /
> T7 `9f00277` / T8 `fd13a46`）+ 验收批修复 1 commit（见文末）。验收方式
> = 逐 AC 机检核对 + 五重点抽查（Alcedo 源码逐式数学验算，GPL 仓只读）
> + 三域定向独立复跑（`--bundle IOP` / `--bundle Layers` / `--bundle App`，
> 全套 `--all` 不重跑——批准门纪律）。

## 结论

**PASS / 0 error + 2 minor（本批已修）+ 1 observation**

- 执行批 8 commits 全部按 plan 交付，AC 12/12 独立复核全绿。
- 三域复跑与声明 `--all` 终跑逐值一致（IOP 467/1/0、Layers 179/2/0、
  App 346/0/0；声明 TOTAL|2287/14/0|716s EXIT=0）。
- 四悬决点 kernel 数学对 Alcedo 源码**逐式验算全部忠实**（详见下节）；
  唯 Tint 归因不实（Alcedo Tint 是悬空目录 op）——minor，已签注修正。
- 签核 VALIDATION 归 verify-work 独立步（C 档门控第 3 条，输入 = 本文件）。

## 五重点核查

### 重点① kernel 数学忠实性（四悬决点 + CAT02 + ACEScc，逐式验算）

| 件 | Lightamer 落点 | Alcedo 对照源 | 验算结论 |
|---|---|---|---|
| ACEScc 编解码 | `ACESccMath.metal:45-74` | `primary_grade.metal:34-57` ContrastAcesccEncode/Decode | **逐常数一致**（A 9.72/B 17.52/offset 2^-16/transition 2^-15；负值线性延伸段 `kFloor+value` 与中段 `offset+value·0.5` 均 Alcedo 自身口径——非 ACEScc 规范字面（规范中段为 `2^-16+2x`），忠实优先正确；encode∘decode 互逆成立） |
| LGG 幂式 | `ColorWheels.metal:39-48` | `primary_grade.metal` behavior 11 + `adjustment_runtime.cpp:242-255` 装配 | **忠实**：`gammaLeg=max(gamma.color+gamma.luma,1e-4)`；`out=sign·|c+lift.color+lift.luma|^(1/gammaLeg)·gain.color`；装配 values[i·4..+3]=colorOffset+luminanceOffset 逐位对应；disc/strength 不进装配、gain.luminanceOffset 装配不消费——两处"照抄不动更正确"签注属实（DECISIONS D1）；IsIdentity 判定与 `color_wheel_model.cpp:46-56` 逐条对应（lift 全零含 disc；gamma/gain colorOffset==(1,1,1)） |
| Contrast OkLab | `Contrast.metal:64-77` | `primary_grade.metal:96-113` ApplyOkLabContrast（CUDA 同式） | **忠实**：slope=2^(c/100)、pivot=0.5646216=cbrt(0.18)、shape=tanh(3·log2(L/pivot)/2.5)、gain=2^((slope−1)·2.5·shape/3)、chromaScale=√slope·min(gain,1)、OkLab/AP1 矩阵常数全同；SignedCbrt≡pow·sign 数学等价；plan 工作假设（luma 轴幂曲线）被源码否定后按源码落——DECISIONS D2 签注 + 色相度量基改 OkLab atan2（HSL 基对忠实公式固有 2-4° 漂移，论证成立） |
| White·Black 端点 | `WhiteBlack.metal` + `WhiteModule.swift:62` | behavior 3/4 | **忠实**：White gain=1+max(v,0)·0.005（负半区恒等式 + CPU flag 早退覆盖）；Black offset=v·0.001；与 `scalar_operator_model.hpp` WhiteTraits/BlackTraits（"white"/"black"，0，±100）键/默认/范围全同 |
| HLS Gaussian 窗 | `Hls.metal:63-96` | `primary_grade.metal` ApplyHls | **逐行同构**：weight=2^(−d²/w²)（d=圆周色相距，w=max(range,1)）、权归一平均、|adj|≤1e-6 早退、angle=adj_h·2.25·π/180、scale=2^(adj_s·2.25·(≥0?4.5:3.25)) 非对称、luma+=adj_l·1.125、YIQ 系数（0.596/−0.274/−0.322；0.211/−0.523/0.312；重构 0.956/0.621/−0.272/−0.647/−1.106/1.703）全数命中；**plan raised-cosine 假设被源码否定，DECISIONS D4 按"以 Alcedo 为准"条款签注** |
| CAT02 WB | `Cat02WBModule.swift:186-830` + `Cat02WB.metal` | `develop_color_transform.cpp:822-869` | **忠实**：M=XYZ_D60→AP1·CAT02⁻¹·diag(dst/src@1e-10)·CAT02·AP1→XYZ_D60 与 BuildAp1Cat02WhiteBalanceMatrix 同构；CAT02 阵/逆、kXyzD60ToAp1/逆常数同；tint 通道 duv=tint/3000 沿 locus 法线（kTintScale=3000.0、delta_k=clamp(cct·0.001,0.5,3250) 同）；identity 默认 (5999.9934, 9.7112783)=`cat02_white_balance_model.hpp:23-24` 常数 |
| Saturation | `Saturation.metal:41-53` | behavior 9 | **忠实**：scale=value 直乘（0-4）、AP1 luma-pivot、**peak-raise 限幅**（scale>1.5 且 (peak−l)(scale−1)>0.1 → scale=1+0.1/max(peak−l,1e-6)）逐行对应 |
| Tint | `Tint.metal` | Alcedo Tint = **悬空目录 op** | ⚠️ 见 findings F1 |

### 重点② E1 落位 + E2 条件

- **E1**：acesccIn 20.5 < exposure 21.0（V50Order 十行实测）；排序断言
  `ACESccEnvelopeTests.testExposureChainSortsEnvelopeFirstAndLast` 真实存在且
  双腿齐全——①wrap+sort 面首末断言 + ②真 runSub 后 `pipe.pieces.first/last`
  == acesccIn/acesccOut + ③20.5 < V50Order(exposure) < 69.9 机检。
- **E2**：包夹条件 = `ACESccEnvelope.needsEnvelope` →
  `GradeCatalog.item(opName:)` 查询面（`ACESccInModule.swift:126-128`），
  非白名单散抄 ✓；非目录链跳过测试在册
  （`testNonCatalogAndEmptyChainsAreNotWrapped`——TestGain 纯链 + 空链 +
  目录 op 翻转三段；skinSmooth 同属非目录集，同一谓词覆盖）。
- 架构缝：Core 不可 import IOP（D-03）→ driver 腿 2 行调
  `LayerCompositeSeam.acesccEnvelope`（默认恒等包装）+ IOP populate 注入
  `ACESccEnvelope.install()`——plan 字面内联片段的合法架构变体，半径红线
  内核对通过（blend/retouch/base/terminal/struct 零改动亲核 diff）。

### 重点③ CAT02 identity 双断言 + Planck 积分

- 双断言在册：`testCat02IdentityPairSolvesToACESWhite`（xy 1e-4 门 + 实际
  <1e-5）+ `testCat02IdentityMatrixIsIdentity`（1e-5 门 + 实际 <1e-6）。
- Planck 积分实现 = Planck 定律 × CIE 1931 2° CMF（1nm 360-830，471 点
  梯形）——**CMF 为公开 CIE 018:2019 数据集，非 Alcedo 派生表拷贝**；
  Alcedo 表生成同源 c2=1.4387774e-2 ✓；UV→xy 转换式正确。GPL 表数据零入库
  达成。

### 重点④ V50Order 判据 + V50OrderTests 越界签注

- add-only 形态判据：`git show ba70717 -- V50Order.swift` 逐 hunk 核 =
  **零删除行/零修改行**（m3 判据精确满足）；十行终位与 DECISIONS §二一致
  （black 42.0→41.95 = KD-3 ±0.05 挪位条款，42.0 撞未注册 rgbcurve，
  例外仅 colorWheels↔colorbalance 一处——论证成立）。
- V50OrderTests 越界（95→105 + 簇集 {28.5}→{28.5,41.0} + 剥离集 +10）：
  申报外越界但**已声明**（commit body + DECISIONS §七）——静态 count 字面
  与"既有测试全绿"物理不可兼得，93→94→95 先例同构；**签注合理，接受**。
  m3 判据"不锚行数"的本意即此。

### 重点⑤ golden 比较空间 + E2 零放宽盘点

- 比较空间 = **linear 域**（双侧 decode 后比较）——encode 对数腿零点斜率
  750× 放大 f32 固有 epsilon 的论证成立（LESSONS L048 同源）；f32 出厂常数
  升 Double（`Double(Float(17.52))`）规避常数舍入系统差（~4e-5 decode 斜率
  偏置）——KD-8 纯函数 1e-6 / GPU 1e-5@p99.9 + 5e-5 max 硬顶 / identity
  容差 0 三级实配正确；窗裁剪实现为 `abs(ref) ≤ 2.5`（DECISIONS 文面
  [-0.5,2.5]，实现是更宽的包含窗 = 更严门，无害）；(2000K,+150) 病态角点
  1e-3/5e-3 单独签注 + 全窗裁空只做 bounded/NaN 断言的豁免逻辑在册。
- E2 盘点（DECISIONS §五）：五表逐条核对成立——唯一入面包夹 =
  ExportPipeTests（无像素断言，零放宽）；其余目录 op 用法均在 base 链或
  record 语义面。**零断言放宽、零静默改**结论可信；域盲五件的结构性备忘
  （非 identity 参数层内 kernel 收到 ACEScc 值）如实登记，P2 对齐归账明确。

## AC 逐条复核（plan 12 条）

| # | AC | 复核结果 |
|---|---|---|
| 1 | GradeCatalog 18/14/完备性/owner 矩阵/m5 | ✅ 18 行五元组（17 唯一 op，shadows/highlights 共 shadhi）+ gradeItems 14 + owner 矩阵含 `owner(of:)` 消费面断言 + defaultLook 三 entry（+1.5/+15/1.3）+ m5 五件 no-op 断言（shadhi 两值分立钉死）+ E7 三事实断言（testgain DEBUG/Release 双臂）；唯一缺口 = E7 注释引用的 T7 全闭合测试缺失（F2，本批已补） |
| 2 | V50Order add-only + 十行 + 唯一性 | ✅ 零删除/零修改行机检 + 唯一性三不变量 + 同位例外声明在册 |
| 3 | envelope 全套断言 | ✅ 往返 1e-5@p99.9（非空洞守卫）/空链·非目录链跳过/E1 排序双腿/base+terminal 字节恒等/cache 二次 HIT/retouch 腿结构性不经过（stroke 走 RetouchEngine）/E2 盘点零放宽 |
| 4 | envelope 零可见面 + 红线零 diff | ✅ `git grep ACESccIn Registry.swift` 零命中；PixelPipe/PipeCacheKey/Sidecar/LayerStack/MaskSpec/LibrarySchema 全零 diff（87c039d..HEAD 机检） |
| 5 | CAT02 identity 双断言 + 角点 golden | ✅ 六参数点（四角 + 3200K + 7000K/25）+ 病态角点签注容差实配 |
| 6 | Contrast 不变量 + White/Black 端点 | ✅ identity@0 容差 0（flag 早退）+ 12hue×3luma 单调 + OkLab hue ≤2° + golden 0/+15/±100 + 端点有界/NaN 断言 |
| 7 | Saturation 0-4 + Tint ±100 | ✅ 1.0 恒等容差 0 + 0/4 端点无 NaN；Tint 0 恒等 + ±100 golden（语义归因见 F1） |
| 8 | colorWheels params/IsIdentity/golden | ✅ 字段+CodingKeys 同拼写（disc/strength/color_offset/luminance_offset）+ IsIdentity 判定式逐条对照测试 + 三 identity 容差 0 + 组合 golden |
| 9 | HLS params/权重窗/映射/8bin | ✅ defaults 全同 hls_model.hpp（bins 0..315/45 表/target {0,0.5,1}/l·s_range 0.1）+ Gaussian 窗解析断言（全表归一 + w=1 零泄漏 2^-2025）+ applyTargetEdit 终式 = editor_hls_model.cpp:321-342 逐字段对照（±30/±100/1000/target{hue,0.5,0.5}/l·s_range 1.0）+ Float64 对照 ≤1e-6 + 8 bin 遍历 |
| 10 | 全套 0 fail ≈2240+47 | ✅ 声明 2287/14/0（2240+47 精确）；三域复跑逐值一致（下节）；本批 +1 测试后基线顺移 2288 |
| 11 | diff 边界 == 申报集 | ✅ 32 文件逐一名单核对：front-matter 全含 + V50OrderTests（已声明偏差）+ 四收口 md；红线文件零 diff |
| 12 | 四文件 × 双登记 | ✅ Project.swift 四行（:278/:347/:426/:654）+ BUNDLE-MAP 四行在册；行计数陈旧为 F3（本批已修） |

## 独立复跑 vs 声明

| bundle | 声明（fd13a46 --all） | 本批复跑 | 判定 |
|---|---|---|---|
| IOP | 467/1/0，peak 7378MB | **467/1/0**，peak 7553MB | 一致（峰值波动在 8G 门内） |
| Layers | 179/2/0 | **179/2/0** | 一致 |
| App | 346/0/0 | **346/0/0** | 一致 |

- 任务书预期"IOP 467→477 / App 346→360"为派发侧口径误差：声明终值 467/346
  **已含** +47 新增（IOP 457+10、App 332+14），复跑以声明 BUNDLE 行为对账
  基准——三域全中。
- 修复后复跑（`xcodebuild build-for-testing` 重建后）：App **347/0/0**
  （+E7 闭合测试；注：重建前的首轮 App 复跑 346 = test-direct.sh 是
  test-without-building、跑在执行方终跑产物上——L047 同族"产物陈旧"信号，
  重建后 +1 到位）+ IOPParity **326/2/0**（声明值一致；tint 头注改动过
  golden 全套无扰）。

## Findings 与处置

- **F1（minor，已修）Tint 像素语义归因不实**：Tint.metal/TintModule 头注称
  "the Alcedo tint op (primary_grade behavior 14)"，实测 Alcedo 0.3.0 Tint
  是**悬空目录 op**——`TryResolveAdjustmentBehavior`（adjustment_runtime.cpp
  :98-117）不解析 Tint（无 AdjustmentBehavior、无 GPU 腿，入链即 throw）；
  behavior 14 按现行枚举 = Sharpen（neighborhood op，永不进 pointwise），
  该数值分支在 Alcedo 自身派发下不可达。公式本身（scale=1+v·0.0025 luma
  pivot）是文件内唯一 source-shaped 语义，选型可接受，但**归因必须如实**。
  处置 = 头注三处改写 + DECISIONS §八签注（目录面照抄无误，像素语义为
  source-shaped 选型 + plan 风险节条款依据；上游若补 runtime 语义以彼时
  源码重钉）。
- **F2（minor，已修）E7 全闭合机检缺失**：GradeCatalogTests.swift:83 注释
  引用 `testAllCatalogOpsAreDefaultFaceRegistered`（DECISIONS §3(b)"T7 后
  全 18 目录 op ∈ face"）但测试从未落盘——E7 三事实断言只覆盖 (a)(c)。
  处置 = 补测试（17 唯一 op 经 populate(defaultFace:true) 后 makeBox 全
  解析；seed 成员面刻意不断言——grade ops 随 P2 面板入 seed）。
- **F3（minor，已修）BUNDLE-MAP 行计数陈旧**：GradeKernelGoldenTests 行 4
  （T3 落行时点值，终态 18）、GradeParamsCodingTests 行 3（终态 10）——
  T4-T7 增量未随动，头注"对账以各行 method 数为准"失守。处置 = 4→18、
  3→10、GradeCatalogTests 14→15（F2 新增）+ 勘误注记行。
- **O1（observation，不处置）**：golden 窗裁剪实现 `abs(ref)≤2.5` 与
  DECISIONS 文面 [-0.5,2.5] 措辞不一（实现为更宽包含窗 = 更严统计门，方向
  安全）；后续如有人按文面收窄实现属收紧非放松，无需动作。

## 翻账清单（本批同 commit）

- `.work/gsd/REQUIREMENTS.md`：**M2GRADE-01 勾选 + Delivered 注记**（18 目录
  参数面对齐 + LGG 新件 + ACEScc 域包夹 + CAT02 创意 WB 语义；UI 面/严格面
  收窄/mint 接线归 M2GRADE-03 与 M2-5-2）；**M2GRADE-02 部分注记**（LGG
  params/kernel/IsIdentity 交付 = M2-5-1；trackball UI + Reset wheels 归
  M2-5-2 P2）。
- 本报告落盘；DECISIONS §八 + BUNDLE-MAP 勘误随修复 commit。

## 修复 commit

- `fix(m2-5-1): tint attribution, e7 closure test, bundle-map counts`
  （Tint 归因三处 + GradeCatalogTests +1 + BUNDLE-MAP 勘误 + DECISIONS §八
  + 本报告 + REQUIREMENTS 翻账）

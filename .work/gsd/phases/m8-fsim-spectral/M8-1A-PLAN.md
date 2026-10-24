---
phase: m8-fsim-spectral
plan: "M8-1a"
title: "plan 1a — FSIM 数学核-数据面（T1 FilmProfile 谱面 additive 解码六项 / T2 常量资产五件自装配 / T3 tc 光谱上采样自拟合器 / T4 Float64 构建期引擎全链 + golden / T5 收口）"
wave: 1
depends_on: []
autonomous: true
requirements: ["charter = 本 phase CONTEXT.md（D-M8-1..8 + X1..X3/X6）——FSIM 光谱升维数据地基波", "research 正本 = phases/m8-fsim-spectral/RESEARCH.md（9b256482）§1.2（tc 表数学）/ §2（数据包与常量集）/ §3.3（资产缺口）/ §6.1 M8-1a 行", "OQ 裁决正本 = 同目录 CONTEXT.md（全按推荐 + 亲核登记八条——T1 范围以登记②六项清单为准）", "基线 4206/41/0（CONTEXT §亲核登记①证据链）；本 plan 分账 +18..24", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 M8-1b 起跑；执行排程在图库选片批验收链后（机器级单重活）"]
success_criteria: "SC 全可机检——T1：FilmProfile additive 解码恰六项（logSensitivity/channelDensity/midscaleNeutralDensity/adaptationWindowParams/adaptationSurfaceParams/viewingIlluminant——CONTEXT 亲核登记②清单，tolerant decodeIfPresent + 默认缺键旧 JSON decode 逐字节零漂移专测）+ 28 张全量 decode 冒烟（谱形状 sanity：81 点/轴一致/值域带）；T2：常量资产五件落库（CMFs[81×3]/illuminant SPD 集/dichroic[81×3]/locus 多边形/拟合域常量——generated Swift + provenance 头）+ sanity 门（D65 白点 CMFs 积分 xy 散 ≤1e-6 带 / locus 闭合 / SPD 值域非负）；T3：SpectralTcFit Float64 拟合器（Jakob-Hanika sigmoid 三系数 + tri2quad 全域 192²）+ 质量门三件（覆盖率无 NaN/发散 cell + 邻 cell 系数梯度上限 + 白点积分散 ≤1e-6）+ 谱重建精度门（目标谱 vs 重建谱带——分级 1e-3 相对带）；T4：SpectralBuildEngine Float64 构建期全链（tc_lut 442KB + 中性配平 + PCHIP 33³ 印相/扫描表 + cmin/cmax 钳位面 + 常量块）+ 光域单元 golden（expose 积分 vs 独立复算 ≤1e-6；PCHIP vs 逐点精确臂 ≤带宽；中灰闭合通道散 ≤2e-3）+ NumPy 对拍 evidence + dt 同源对表 evidence；T5：登记 + 文档收口"
estimated_tests: "+18..24（T1 +2..3 / T2 +3..4 / T3 +5..7 / T4 +6..8 / T5 +2；越带申报理由）"
test_bundles: [IOP, IOPParity]
baseline: "4206/41/0（CONTEXT §亲核登记①——LUMEN-BC 4204 + r13 d2bcaf06 +2；HEAD 9b256482 = research docs-only 产线零漂移）"
expected_all: "4206 + ΔN（本 plan 终态带 4224..4230；--all 归 M8-3 收口轮统一对账——本 plan 验收 = 构建 + 定向 bundle〔IOP/IOPParity〕）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 17 条（FIX2③ / 封存面 / 零 FilmRecord 字段+零 schema bump / xcstrings 尾块 / LocalizationValue 禁形 / L041 tuist 末位 / machine-guard+图库选片批后排程 / probe fence / --all 批准制 / C 档门控 / UserDefaults 零新键 / 默认中性零行为 / L057 缝 / 测试落域 / commit 纪律 / GPL 合规 / process 五件套〔本 plan 零触，归 M8-2〕）。"
  - "产线触碰面 = 恰 FilmProfile.swift additive 解码 + Film/ 域新文件四件（X1/X6 资产与引擎）——PixelPipe/FilmTailPolicy/RenderProcess/一切 .metal 本 plan 零 diff（数学核不进产线运行期）。"
  - "GPL 纪律：Jakob-Hanika 数学面 + BSD 方法参考 = 思想移植零拷码；dt 读解 = 定位引用零转录；上游表/常量零字节进仓（fallback 启用才走 GPL 移植纪律，plan 内分支申报）。"
  - "irradiance kind 单臂（X1）；reflectance kind 预留不实现；24-bit/浮点常数一律字面量 + 注记来源（provenance 头）。"
files_modified:
  - LightamerCore/Sources/Film/FilmProfile.swift                  # T1：谱面 additive 解码六项（亲核登记②清单）
  - LightamerCore/Sources/Film/SpectralConstants.swift            # T2：新建——常量资产装配面（CMFs/SPD/dichroic/locus/拟合域常量的类型面）
  - LightamerCore/Sources/Film/SpectralConstantsData.swift        # T2：新建——generated 数据表（81 波长轴/CMFs/SPD 集/dichroic，provenance 头）
  - LightamerCore/Sources/Film/SpectralTcFit.swift                # T3：新建——Jakob-Hanika 三系数拟合器 + tri2quad 域 + 质量门
  - LightamerCore/Sources/Film/SpectralBuildEngine.swift          # T4：新建——Float64 构建期全链（tc_lut/中性配平/PCHIP 33³/常量块）
  - Tests/LightamerTests/SpectralProfileDecodeTests.swift         # T1：新建（IOP bundle）
  - Tests/LightamerTests/SpectralConstantsSanityTests.swift       # T2：新建（IOP bundle）
  - Tests/LightamerTests/SpectralTcFitTests.swift                 # T3：新建（IOP bundle）
  - Tests/LightamerTests/SpectralBuildGoldenTests.swift           # T4：新建（IOPParity bundle——*Golden* 域模式）
  - Project.swift                                                 # T5：四新测试文件入对应 bundle 显式数组
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt    # T5：四行落域登记
  - .work/gsd/phases/m8-fsim-spectral/evidence/                   # T4：NumPy 对拍脚本+输出 / dt 同源对表转录（非 CI）
  - .work/gsd/phases/m8-fsim-spectral/M8-1A-SUMMARY.md            # T5：执行摘要（逐任务记账 + ΔN 终账）
  - .work/gsd/phases/m8-fsim-spectral/M8-1A-DECISIONS.md          # T5：裁定记录（拟合质量门终值 + 法务注记 + 各偏差）
---

# Plan M8-1a — FSIM 数学核-数据面：谱解码 + 常量资产 + tc 自拟合器 + Float64 构建期引擎

> **裁决正本** = `CONTEXT.md`（D-M8-1..8 + X1..X3/X6；晨审可推翻）；规格
> 正本 = `RESEARCH.md`（§1.2 tc 表精确数学 / §2 常量集形态 / §3.3 资产缺口
> / §6.1 M8-1a 行；planner 抽核吻合 + 亲核登记八条见 CONTEXT）。本 plan =
> **纯 Core 数学面**，零产线运行期触碰（无 .metal / 无 PixelPipe / 无
> RenderProcess），产物 = M8-1b GPU 面消费的确定性表数据面。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T5 形态 = CONTEXT D-M8 落定
> 值 + 亲核登记②清单）。执行中如触「必须扩面」（reflectance kind / 直接谱
> 表形态 / 上游表字节进仓 / 产线运行期文件）= 停手上报，不得自裁扩界；
> **拟合器质量门不达的 fallback = D-M8-2 GPL 表移植分支**（plan 内分支，
> DECISIONS 申报后走红线 3 GPL 移植纪律，不破段结构——下游 M8-1b 消费面
> 形态不变）。
>
> **执行序**：T1 → T2 → T3 → T4 → T5。每任务独立 commit（Conventional
> Commits 全英文，只 add 相关文件，不 push）；重活起跑前过
> `Scripts/machine-guard.sh`（本 plan 无 GPU probe，构建/测试仍是重活）。
>
> **C 档停**：T5 闭环后**停汇报**；确认后 M8-1b 起跑。
>
> **基线**：**4206/41/0**（CONTEXT 亲核登记①）。全套预期 4206 + ΔN（本
> plan 分账 +18..24；全套对账归 M8-3 收口轮）。

## ΔN 预算表（逐任务，本 plan 分账带 +18..24；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 谱面 additive 解码 | **+2..3** | 六项解码正例 + 缺键零漂移负测 + 28 张全量冒烟 | IOP（SpectralProfileDecodeTests） |
| T2 常量资产五件 | **+3..4** | CMFs 白点积分/locus 闭合/SPD 值域/dichroic 形状 sanity | IOP（SpectralConstantsSanityTests） |
| T3 tc 自拟合器 | **+5..7** | tri2quad 往返/sigmoid 重建/质量门三件/精度带/确定性双跑 | IOP（SpectralTcFitTests） |
| T4 构建期引擎 golden | **+6..8** | expose 积分独立复算 ≤1e-6/PCHIP vs 精确臂/中灰闭合/tc_lut 白点/端到端 golden 双跑 | IOPParity（SpectralBuildGoldenTests） |
| T5 收口 | **+2** | 28 张全表构建冒烟（构建耗时 + 内存 sanity 机检）+ evidence 登记 | IOPParity |
| **合计** | **+18..24** | 4206 → 本 plan 终态带 4224..4230 | 四新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **自拟合首选 + GPL fallback**（D-M8-2）——拟合失败 = plan 内分支申报，
   不是停工理由。
2. **系数表存储 + 构建期展开**（X2）——直接谱表形态否决。
3. **irradiance kind 单臂**（X1）——reflectance 预留 case 不实现。
4. **PCHIP 33³ + cmin/cmax 钳位面全盘平移**（D-M8-3）——精确臂仅 golden
   参照。
5. **additive 解码范围 = 亲核登记②六项**——baseDensity/wavelengths 既有
   零改。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m8-fsim-spectral/CONTEXT.md`（D-M8-1..8 + X1..X3/X6 +
  hazards + 红线 17 条 + 亲核登记八条 + 晨审索引）
- `.work/gsd/phases/m8-fsim-spectral/RESEARCH.md` §1.2（tc LUT 构建 3664-
  3861 读解段）/ §2（pack 常量集）/ §3.3（资产缺口表）/ §4.3（probe ①——
  T5 冒烟口径）
- `.work/gsd/phases/m3-3-fsim/M3-3-03-DECISIONS.md`（golden 门分级带先例：
  1e-4/1e-5 分级 + 比较空间纪律 L048——decode 回 linear + f32 产线常数）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位——本 plan 四个新测试文件
  必触发）+ L013（跨进程身份哈希 StableHash——本 plan 无身份键，备忘）+
  AGENTS.md M2-4-0 E2（测试落域 + BUNDLE-MAP）

---

## T1 — FilmProfile 谱面 additive 解码（亲核登记②六项）

> 现状：`FilmProfile` 类型面只解码 `logExposure/densityCurves/baseDensity/
> wavelengths` 四项 + Info.referenceIlluminant；谱面输入在 JSON 里、类型面
> 缺席（M3-3-01 KD-3 当时的消费面裁决在 M8 语境自然重开）。本任务 = 纯
> additive 解码，JSON 零改、字节原样纪律不变。

**read_first**：CONTEXT §亲核登记②（六项清单正本）；`FilmProfile.swift`
全文（DataKeys nested-container 形态 + tolerant decode 惯例）；
`Resources/FilmProfiles/profiles/` 抽样 JSON（键形/形状亲核：81 点/嵌套
数组/param 对象）；RESEARCH §3.3。

- **action**：
  1. `FilmProfile` additive 六字段：`logSensitivity: [[Float]]`（81×3）/
     `channelDensity: [[Float]]`（81×3）/ `midscaleNeutralDensity:
     [Float]`（81）/ `adaptationWindowParams: FilmProfileAdaptationParams?`
     / `adaptationSurfaceParams: FilmProfileAdaptationParams?`（15 系数
     deg4 族 typed 载体，tolerant）/ `Info.viewingIlluminant: String?`。
     全部 `decodeIfPresent`（缺键 = nil，宽容惯例）；**encodeIfPresent
     同式**——缺键 profile 的 re-encode 逐字节零漂移专测。
  2. 形状校验：轴一致性断言（logSensitivity/channelDensity 行数 ==
     wavelengths.count；midscale 同）在 typed init 门（违形 = nil 降级不
     throw——M3-3-01 宽容同式）。
  3. 测试（IOP bundle）：六项解码正例（真 profile fixture 抽 2 张：负片
     + 相纸各一）+ 缺键旧形态 JSON decode→encode 逐字节零漂移负测 +
     28 张全量 decode 冒烟（81 点/轴一致/值域带 sanity——logSensitivity
     有限值 + 值域 [-6,6] 量级带）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一产线文件（FilmProfile.swift）。
  - 缺键零漂移专测在册（decode→encode 字节恒等断言）。
  - 28 张全量冒烟通过（计数断言 28）。
  - 既有 FilmProfile 侧测试零回归（`--bundle IOP` 定向）。
- **commit**: `feat(m81a): decode spectral profile fields additively`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（additive optional，零
  消费方行为差）；偏差（字段命名/typed 载体形态/形状校验档位）= DECISIONS
  申报；**禁触既有四字段与 Info.referenceIlluminant 解码语义**；**禁改
  Resources/FilmProfiles/ 任何字节**（byte-verbatim 纪律）。

## T2 — 常量资产五件自装配（X6 资产面）

> 全部公开标准数据/公开公式自建，零 GPL 数据依赖；generated Swift 文件
> （测试域零资源加载、确定性），provenance 头逐表登记来源与生成式。

**read_first**：RESEARCH §2（常量集形态：wavelengths[81]/cmfs/illuminants/
dichroics/locus）+ §3.3 资产缺口表；CONTEXT §X6；CIE 1931 2° CMF 公开数据
（81 点 @5nm 380-780 抽值）；CIE D 系列 SPD 公开公式（S0/S1/S2 分量式）；
`Resources/FilmProfiles/profiles/*.json` 的 `info.reference_illuminant`/
`viewing_illuminant` 取值集（illuminant 需求面清单推导输入）。

- **action**：
  1. `SpectralConstantsData.swift`（generated，头注 = 来源 URL/公式引用/
     生成脚本指认/生成日期）：wavelengths 轴（380-780@5nm，81 点——与
     profile 轴一致性断言随 T1 数据面）+ CMFs[81×3] + illuminant SPD 集
     （profile illuminant 取值集 ∪ D 系列 + A + TH-KG3 自近似 + ENL）+
     dichroic[81×3]（公开描述自近似）+ locus 多边形（由 CMFs 导出的代码
     计算，不存死表——导出函数在 SpectralConstants）。
  2. `SpectralConstants.swift`（类型面 + sanity 计算面）：SPD 按名查表 +
     locus 多边形导出 + tri2quad/quad2tri 纯函数（RESEARCH §1.2 1719-1762
     数学面独立实现）+ 中性配平锚常量（sRGB 中灰 0.184 语义面——上游
     SF_MIDGRAY 同值公开事实）。
  3. 测试（IOP bundle）：D65（或任一 D 系列）CMFs 白点积分 xy 散 ≤1e-6
     带 + locus 多边形闭合性 + SPD 值域非负有限 + dichroic 曲线形状
     sanity（[0,1] 透过率域）+ wavelengths 轴 == profile 轴。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两新产线文件（SpectralConstantsData/
    SpectralConstants）。
  - provenance 头在库（每表来源可溯）；grep 零上游表字节引用（dt pack
    零依赖断言——常量文件内无外部资源加载调用）。
  - 白点积分散 ≤1e-6 测试在册。
- **commit**: `feat(m81a): assemble spectral constant assets`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（illuminant 集
  取舍/TH-KG3 近似形态/locus 离散度）= DECISIONS 申报 + 值域 sanity 带
  对照（dt pack 参照仅记录不入仓）；**禁从 dt 仓拷贝任何数值表**；**禁
  资源文件形态**（generated Swift 单源——Core 测试域无 bundle 加载惯例）。

## T3 — tc 光谱上采样自拟合器（X1/X2）

> Jakob & Hanika 2019 sigmoid 谱族独立实现（论文数学 + BSD 方法参考，零
> 拷码）；拟合目标 = 每 cell 81 点谱；产物 = 192²×3 系数表（构建期中间量，
> 不落资产——X2）。

**read_first**：RESEARCH §1.2（上游表构建六段：sens_w/adaptation/逐 cell
积分/kind 语义/remap——形态学参照）+ §OQ-2 细化；CONTEXT §X1/X2；Jakob &
Hanika 2019 论文数学节（sigmoid 参数化 + 拟合目标式；公开学术面）；
`SpectralConstants.swift`（T2 tri2quad 面）。

- **action**：
  1. `SpectralTcFit.swift`：拟合目标谱生成（每 cell：cell 色度 → 谱重建
     目标 = 该色度 metameric 谱的构造式——论文式；拟合器 = 非线性最小二乘
     （Levenberg-Marquardt 或分域牛顿，Float64，确定性迭代上限 + 固定
     初值表——双跑逐位恒等门））+ 192² 全域批量拟合 + 质量门三件（覆盖
     率：无 NaN/发散 cell；平滑度：邻 cell 系数梯度上限带；白点积分散
     ≤1e-6）。
  2. 谱重建面（系数 → 81 点谱，M8-1b 构建期展开的同一函数——单源）。
  3. 测试（IOP bundle）：tri2quad/quad2tri 往返恒等 + sigmoid 谱重建
     精度带（目标 vs 重建相对误差 ≤1e-3 带抽样）+ 质量门三件 + 双跑
     确定性逐位恒等 + 中性色 cell 白点特判（中性配平核验）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件（SpectralTcFit.swift）。
  - 双跑确定性断言在册（同输入逐位恒等——L013 精神的数学面延伸）。
  - 质量门三件测试全绿（终值入 DECISIONS）。
- **commit**: `feat(m81a): add tc spectral upsampling fitter`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（迭代器选择/
  网格边长偏离 192 的申报理由）= DECISIONS 申报；**质量门不达 = D-M8-2
  fallback 分支申报**（GPL 表移植走红线 3 纪律 + DECISIONS 登记，段结构
  不变——下游消费面 = 积分后 tc_lut，来源对下游不透明）；**禁把拟合产物
  落成仓内资产文件**（X2——构建期中间量单源）。

## T4 — Float64 构建期引擎全链 + golden（测试策略门 2/6）

> 构建期引擎 = 光谱核的「CPU 参考实现」：per-sim 全部表（tc_lut 442KB /
> PCHIP 33³×2 套 + slopes + cmin/cmax / 矩阵常量块）从 profile + 常量
> 资产出发表出——M8-1b kernel 的黄金参照与表供给者。

**read_first**：RESEARCH §1.2-§1.5（expose 积分/显影/印相/扫描四段数学
读解正本）+ §4.3 probe ①；CONTEXT §测试策略门 1/2/6 + X5（Float64 参照
纪律）；`FilmPrintBake.swift`（Float64 + concurrentPerform + 确定性先例
——机制参照非消费）；M3-3-03 DECISIONS（golden 分级带 + L048 比较空间
纪律：decode 回 linear + `Double(Float(x))` 升维）。

- **action**：
  1. `SpectralBuildEngine.swift`：per-sim 构建（输入 = FilmProfile 谱面 +
     SpectralConstants + 目标空间参数；输出 = `SpectralFilmTables` 值类型
     ——tc_lut[192²×3 f32] + print/scan PCHIP 表集（33³ + slopes +
     cmin/cmax）+ m_in/m_out/CAT/OkLab 常量块 + 曲线网格归一化面）：tc
     展开（T3 系数 → 谱 × `10^log_sensitivity` 折 adaptation_window ×
     逐 cell 积分——81 波长循环只在构建期）；中性配平（midgray 链头跑
     得中灰密度谱 + 几何均值归一——RESEARCH §1.4 数学面）；印相/扫描
     表（81 波长精确积分 → 33³ Float64 → float 存储Built + PCHIP 预备
     面）；黑白点拟合臂（默认关，参数面预留）。
  2. golden 测试（IOPParity bundle，*Golden* 命名）：expose 积分独立复算
     ≤1e-6（独立实现 = 测试内直积式复算，非引擎同函数）+ PCHIP 表 vs
     逐点精确臂偏差 ≤带宽（分级带终值 DECISIONS 申报）+ 中灰闭合（中灰
     过链头通道散 ≤2e-3）+ tc_lut 白点积分散 ≤1e-6 + 端到端双跑逐位。
  3. NumPy 对拍 evidence：`evidence/numpy_crosscheck.py` + 输出（CMFs
     积分/tri2quad/sigmoid 重建/PCHIP 四点对拍表）；dt 同源对表 evidence：
     上游单测/读解数值转录 + 对拍记录（GPL 转录纪律头注）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件（SpectralBuildEngine.swift）。
  - golden 五门全绿（≤1e-6 / ≤带宽 / ≤2e-3 / ≤1e-6 / 逐位）。
  - evidence 目录含 numpy 输出 + dt 对表记录（provenance 头）。
  - 表体积机检断言（tc_lut 442KB 量级 + 每套 PCHIP ≈2.5MB 量级——
    RESEARCH §4.1 载体预算对账）。
- **commit**: `test(m81a): pin spectral build engine golden`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（分级带终值/
  引擎拆文件）= DECISIONS 申报；**禁在引擎内引入产线运行期依赖**
  （MetalContext/像素管线零 import——构建期纯 CPU Float64 单源）；**禁
  log10/pow10 走 libm 于将来 kernel 对拍路径**（X5 三板斧的 host 侧
  形态本任务预埋——共享多项式常量面在本文件落笔，M8-1b MSL 侧同表）。

## T5 — 收口（全表构建冒烟 + 登记 + tuist）

- **action**：
  1. `Project.swift` 四新测试文件入对应 bundle 显式数组（IOP ×3：
     SpectralProfileDecode/SpectralConstantsSanity/SpectralTcFit；
     IOPParity ×1：SpectralBuildGolden）+ BUNDLE-MAP 四行登记。
  2. `tuist generate` = 本批最后一个动作（L041）。
  3. `--bundle IOP` + `--bundle IOPParity` 定向全绿；ΔN 实数对账（预算
     +18..24）。
  4. 28 张全表构建冒烟测试（IOPParity）：全 profile 集构建耗时 + 内存
     sanity（RESEARCH §4.3 probe ① 口径——tc 构建估 <100ms 级/表的量级
     带 + 白点散；耗时上限带 = DECISIONS 申报）。
  5. SUMMARY（逐任务记账 + ΔN 终账 + 拟合质量门终值）+ DECISIONS（法务
     注记 X6 + fallback 分支判定〔若触发〕+ 各偏差）落盘。
  6. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿零回归；Project.swift diff = 恰
  四行数组插入；BUNDLE-MAP 登记行在库；tuist generate 后无生成物入 git；
  SUMMARY/DECISIONS 在库；冒烟测试在册。
- **commit**: `test(m81a): register spectral data plane suites and close out`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY 申报
  理由；禁漏 tuist generate（数组改后不生成 = 编译面漂移）。

---

## 风险与回退

- **拟合器质量长杆**：覆盖率/平滑度/白点三门不达 → D-M8-2 fallback（GPL
  表移植：版权头 + NOTICE 增补 + `SpectralTcFit` 位换「表载入 + 积分展开」
  形，下游消费面不变）；plan 内分支不破段结构；DECISIONS 申报触发记录。
- **CMF/SPD 数值面漂移**：公开数据多版本（2°/10°、多表源）→ 以单一生成
  脚本 + provenance 头钉版；白点积分散门 ≤1e-6 是版本错的灵敏度哨兵。
- **kind 语义误配**：irradiance 单臂下 profile reference illuminant 缺失
  档（相纸类）→ 印相段消费 illuminant 集、负片段消费 reference——typed
  面显式分域，测试双臂覆盖。
- **构建耗时超带**：192²×81 全域拟合若实测超 <100ms 级估 → DECISIONS 申
  报 + 构建缓存面评估（M8-1b 载体消费形态不变——表是 per-sim 一次，非逐帧）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §3.3 资产缺口五行 ↔ T1（谱解码）/T2（常量
   五件）/T3（tc 表）逐行闭合；§6.1 M8-1a 交付四件 ↔ T1/T2/T3/T4。
2. **OQ 兑现核**：D-M8-2（自拟合 + fallback 分支在案）/ X1（tri2quad 全域
   + 质量门三件）/ X2（系数表形态 + 不落资产）/ 亲核登记②（T1 恰六项，
   midscale/viewing 两项在列）。
3. **红线核**：产线 diff 恰 FilmProfile.swift + Film/ 域新文件；零 .metal
   零 PixelPipe 零 RenderProcess；Resources/FilmProfiles 字节零动；GPL 零
   拷贝；xcstrings 本 plan 零触碰（无 UI 面）；Project.swift 数组段 diff +
   tuist generate 末位。
4. **SC 可机检性**：每条 SC 有命令级判据（grep / git diff --stat / 定向
   bundle / 数值带断言）；ΔN 对账式非死数；golden 门 = 分级带非单点。

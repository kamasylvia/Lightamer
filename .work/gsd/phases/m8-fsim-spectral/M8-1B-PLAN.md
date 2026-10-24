---
phase: m8-fsim-spectral
plan: "M8-1b"
title: "plan 1b — FSIM 数学核-GPU 面（T1 七 stage Metal kernel 族 + 三板斧 / T2 表构建上传载体 / T3 CPU-GPU bit-exact 断言 / T4 perf probe 批五件 / T5 收口）"
wave: 2
depends_on: ["M8-1a"]
autonomous: true
requirements: ["charter = 本 phase CONTEXT.md（D-M8-3/D-M8-4 + X3/X5 + H-M1/H-M2）——光谱核 GPU 执行面波", "research 正本 = phases/m8-fsim-spectral/RESEARCH.md（9b256482）§1.6（CPU/GPU 双路与 bit-exact 纪律）/ §4（性能预算与 corr 内存面）/ §4.3（probe 设计五件）/ §6.1 M8-1b 行", "OQ 裁决正本 = 同目录 CONTEXT.md（PCHIP 臂采纳 + coupler 降采样臂 + 三板斧逐项）", "基线带 = M8-1a 终态（预期 4224..4230）；本 plan 分账 +12..18", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 M8-2 起跑；执行排程在图库选片批验收链后（机器级单重活）"]
success_criteria: "SC 全可机检——T1：SpectralFilmKernels.metal 七 per-pixel stage（expose/lograw/develop_corr/develop/print_expose/print_develop/scan——expose 的 tc fetch 语义含构建期预折的输入 gamut 压缩 remap〔review M1〕）+ fused 两 dispatch 形（A=expose+lograw+corr 生成 / B=develop+print_expose+print_develop+scan）+ corr 降采样臂（1/4-1/8，probe ③ 裁决终值 DECISIONS 申报）+ 三板斧逐项落（显式 fma 钉形/host double 单次取倒 rounded-to-float/共享 log2-exp2 多项式——host 侧常量面 import 自 M8-1a 引擎文件，MSL 侧同表双落笔）+ PCHIP 单调插值（8-cell hermite + slopes/cmin/cmax 钳位）+ 2D Mitchell cubic（B=C=1/3 反射边界）+ NaN 硬化（cubic_base_fraction 落低支/Y=0→xy=0×bb=0）+ 文件头 GPL 归属块与 NOTICE 登记行在库〔review m5〕；T2：SpectralPayloads 表载体（tc_lut texture2d rgba32Float〔alpha pad，体积门按 442KB 量级——review m9〕+ PCHIP 表 buffer 集 + 常量块 buffer）+ SpectralBuildEngine→GPU 上传面（L014 fence 纪律）+ nil-payload blit identity degrade 面预备（M8-2 消费）；T3：bit-exact 断言逐项（CPU Float64 参考 vs kernel float 分歧带门——表构建逐位 / 逐像素 ≤1e-6 带域 / 分段边界专项例×3 板斧各一专项）；T4：probe 批五件（①tc 构建耗时/白点散 ②kernel microbench 合成 ramp+真图 100MP 全帧+分段 signpost ③RSS 峰值 corr 两方案对照 ④pristine/strength-0 基线+光谱臂新 ramp 哨兵计算 ⑤钉形 vs 裸形分歧度量）——LIGHTAMER_PERF_PROBE + XCTSkipUnless + L014 fence；T5：登记 + 文档收口"
estimated_tests: "+12..18（T1 +2..3 / T2 +2..3 / T3 +3..5 / T4 +4..6〔skip 族〕/ T5 +1；越带申报理由）"
test_bundles: [IOPParity]
baseline: "M8-1a 终态带 4224..4230（基线 4206/41/0 + 1a 分账；本 plan 开工前亲核 M8-1A-SUMMARY 实数）"
expected_all: "M8-1a 终态 + ΔN（本 plan 终态带 4236..4248；--all 归 M8-3 收口轮统一对账——本 plan 验收 = 构建 + 定向 bundle〔IOPParity〕+ probe 报告）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 17 条（本 plan 高相关 = 红线 2 封存面〔新 .metal 为豁免正业、film_subrun.metal 零 diff〕/ 红线 7 machine-guard+排程 / 红线 8 probe 纪律 / 红线 14 测试落域 / 红线 16 GPL 移植合规〔review m5——kernel 族是本批最大 GPL 衍生面：.cl→MSL 移植版权头 + Modified by Lightamer + NOTICE 登记纪律〕）。"
  - "产线触碰面 = 新建 SpectralFilmKernels.metal + SpectralPayloads.swift——既有 FilmSubRunKernels.metal / FilmTailPolicy.swift / PixelPipe.swift / RenderProcess.swift 本 plan 零 diff（dispatch 编排/换臂归 M8-2；本 plan kernel 经独立测试宿主路径验证）。"
  - "三板斧是 H-M1 消解本体非风格项：kernel 内一切矩阵/累加显式 fma；一切倒数 host Float64 一次；log2/exp2 共享多项式——T3 各配专项断言，缺一 = 收口门拒绝。"
  - "probe 读钟前 queue fence（L014——无 fence 计时 = 假数）；RSS 口径 = /usr/bin/time -l ru_maxrss；8G 门 + MEMFAIL 兜底；corr 全幅方案只作 probe 对照臂，产线臂 = 降采样（H-M2）。"
files_modified:
  - LightamerCore/Sources/Pipe/Film/SpectralFilmKernels.metal      # T1：新建——七 stage kernel 族（fused A/B + corr 降采样 + PCHIP + Mitchell + 三板斧钉形）
  - LightamerCore/Sources/Pipe/Film/SpectralPayloads.swift        # T2：新建——表载体（tc_lut texture2d + PCHIP buffers + 常量块）+ 上传面
  - Tests/LightamerTests/SpectralKernelGoldenTests.swift          # T3：新建（IOPParity）——CPU vs GPU 分歧带门 + 三板斧专项
  - Tests/LightamerTests/SpectralPerfProbeTests.swift             # T4：新建（IOPParity，probe skip 族）——probe 五件
  - Project.swift                                                 # T5：两新测试文件入 IOPParity 显式数组
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt    # T5：两行落域登记
  - .work/gsd/phases/m8-fsim-spectral/evidence/probe-m81b/        # T4：probe 报告（耗时/RSS/分歧度量数据正本）
  - .work/gsd/phases/m8-fsim-spectral/M8-1B-SUMMARY.md            # T5：执行摘要（逐任务记账 + ΔN 终账 + probe 真值）
  - .work/gsd/phases/m8-fsim-spectral/M8-1B-DECISIONS.md          # T5：裁定记录（corr 1/4 vs 1/8 裁决 + golden 分级带终值 + 各偏差）
---

# Plan M8-1b — FSIM 数学核-GPU 面：七 stage kernel 族 + 三板斧 + probe 批

> **裁决正本** = `CONTEXT.md`（D-M8-3/D-M8-4 + X3/X5 + H-M1/H-M2；晨审可推
> 翻）；规格正本 = `RESEARCH.md`（§1.6 bit-exact 纪律三件真实分歧案例正本
> / §4 性能预算 / §4.3 probe 设计；planner 抽核吻合）。本 plan = **kernel
> 与载体面**，零产线编排触碰（FilmMethodBox 换臂/dispatch 编排归 M8-2）；
> 消费 M8-1a 的 `SpectralBuildEngine`（表供给 + host 侧多项式常量面）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（corr 1/4 vs 1/8 = probe ③ 数
> 据裁决非用户面；砍 coupler fallback 仅 RSS 超 8G 门才启用）。执行中如触
> 「必须扩面」（产线编排文件 / 全幅 corr 产线化 / 第三插值臂 / 零新 kernel
> 红线解封外的新 kernel 用途）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5（T3 依赖 T1+T2；T4 依赖 T3 门通过
> ——分歧度量在钉形落定后才有效度）。每任务独立 commit；重活（xcodebuild
> / probe）起跑前过 `Scripts/machine-guard.sh`。
>
> **C 档停**：T5 闭环后**停汇报**；确认后 M8-2 起跑。
>
> **基线**：M8-1a 终态（带 4224..4230；开工前亲核 M8-1A-SUMMARY 实数）。
> 全套预期 = 基线 + ΔN（本 plan 分账 +12..18；全套对账归 M8-3 收口轮）。

## ΔN 预算表（逐任务，本 plan 分账带 +12..18；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 kernel 族 | **+2..3** | 编译/加载冒烟 + dispatch 形状（A/B 两 dispatch + 降采样中间面尺寸）断言 | IOPParity |
| T2 表载体 | **+2..3** | 上传往返（Engine 表 → GPU 载体 → 读回比对 ≤1e-7 带域——上传无损面）+ nil-payload degrade 面断言 | IOPParity |
| T3 bit-exact | **+3..5** | 七 stage CPU vs GPU 分歧带门 + 三板斧各一专项（fma 钉形违反检测例/取倒唯一性/共享多项式逐位）| IOPParity（SpectralKernelGoldenTests） |
| T4 probe 批 | **+4..6** | probe 五件各 1 测试（skip 族——LIGHTAMER_PERF_PROBE 门）| IOPParity（SpectralPerfProbeTests） |
| T5 收口 | **+1** | evidence 登记 + probe 报告汇编断言 | IOPParity |
| **合计** | **+12..18** | 基线带 → 本 plan 终态带 4236..4248 | 两新测试文件（skip 增量 = T4 族逐条申报） |

## 已定裁决（生效值，硬约束，不得重开）

1. **PCHIP 单调插值臂**（D-M8-3）——8-cell hermite + slopes/cmin/cmax
   钳位面全盘平移；禁四面体/其它插值臂。
2. **corr 降采样臂**（D-M8-4/X3）——dispatch A 生成 → 1/4-1/8 降采样 →
   分离模糊 → 上采样 → dispatch B；全幅 corr 仅 probe 对照臂。
3. **三板斧逐项**（X5/H-M1）——fma 钉形/host double 取倒/共享多项式。
4. **逐像素无 81 波长循环**（RESEARCH §1.2 确认面）——积分全部预折表。
5. **kernel 家族解封登记**（「零新 kernel 红线」在光谱核语境自然重开）——
   新建 SpectralFilmKernels.metal = M8 解封申报面（CONTEXT 红线 2 适配注
   记）， FilmSubRunKernels.metal 零 diff。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m8-fsim-spectral/CONTEXT.md`（D-M8-3/D-M8-4 + X3/X5 +
  H-M1/H-M2 + 红线 17 条 + 晨审索引）
- `.work/gsd/phases/m8-fsim-spectral/RESEARCH.md` §1.6（34 kernel 清单/
  sf_sim_gpu_t 载体/三板斧三案例/NaN 硬化/POCL 精度）/ §4.1-§4.3（成本
  对账/内存/probe 设计）
- `.work/gsd/phases/m8-fsim-spectral/M8-1A-SUMMARY.md` + `M8-1A-DECISIONS.md`
  （表供给面 + 分级带终值 + corr 裁决输入）
- `LightamerCore/Sources/Pipe/Film/FilmSubRunKernels.metal`（既有 fused
  kernel 结构参照——零 diff 只读）
- `.work/LESSONS.md` L014（fence）+ L041（tuist 末位——两个新测试文件）+
  AGENTS.md M2-4-0 E2（测试落域）

---

## T1 — 七 stage Metal kernel 族（X3/X5 钉形）

> 上游 per-pixel 色科学 7 kernel + 空间效果族分离的架构事实（§1.6）同构
> 平移：我方空间效果不入（grain 等挂账），仅 corr 模糊是链内空间步。

**read_first**：RESEARCH §1.1（五 stage 纯逐像素 + 调用侧空间）/ §1.3
（coupler 矩阵 + Langmuir + Kr=0 哨兵）/ §1.4（PCHIP 2137-2247 + dichroic
build 期）/ §1.5（OkLab/knee 顺序 3215-3243 + cmax bilinear）/ §1.6（cl
93-float 常量块 + fma 注记原文）；`SpectralBuildEngine.swift`（表供给 +
host 侧共享多项式常量面——MSL 侧同表双落笔的另一半）； FilmSubRunKernels.metal
（结构参照）。

- **action**：
  1. `SpectralFilmKernels.metal`：七 per-pixel stage 函数（expose = m_in
     mat + Σxyz=Y + xy 互倒〔host 预倒值〕+ tri2quad + 16-tap Mitchell
     cubic 2D gather〔B=C=1/3 反射边界〕+ ×Y×ev_scale；**tc fetch 语义 =
     输入 gamut 压缩 remap 已由 M8-1a T4 预折进表——运行期零额外 remap
     步**〔review M1——上游默认 on（input_gamut_compress，spektra_sim.h:
     601），预折入表即上游同构形态；kernel 面无 remap 代码，fetch 走已压
     缩域寻址〕；lograw = 共享
     log2 多项式；develop_corr = silver×coupler 矩阵〔fma 钉形〕+ Langmuir
     供体侧；develop = (lograw−corr) 256 点 1D 线性查表；print_expose =
     PCHIP 3D + log 域印相曝光加法；print_develop = 3× 1D 查表；scan =
     PCHIP 3D + pow10 共享多项式 + CAT02 mat + OkLab〔cbrt〕+ cmax
     bilinear + lightness knee(0.7,1,2.2) 先/chroma knee(C/C_max;0,1,6)
     后〔顺序纪律〕+ out_scale）。
  2. fused dispatch 形：A = expose+lograw+corr 生成 fused；corr 降采样
     （1/4-1/8）→ 分离模糊 pass（复用现有 blur 域 kernel 形态——本文件
     内最小 Gaussian pass，非 blur 基建 import）→ 上采样；B = develop+
     print_expose+print_develop+scan fused。中间 plane 全 float4（上游
     stage 分解纪律）。
  3. NaN 硬化平移：cubic_base_fraction NaN 落低支 / expose Y=0 或非有限
     → xy=0 ×bb=0 / Kr=0 → 1e30 线性哨兵。
  4. 测试（IOPParity）：device library 构建/加载冒烟 + dispatch 形状断言
     （A/B 中间面尺寸 = 降采样因子函数）+ 三板斧源级 grep 断言（kernel
     源内 `fma(` 计数下限 / 裸 `*`+`+` 混合乘加于矩阵路径零命中〔启发式
     grep 门，误报豁免 DECISIONS 申报〕）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件（SpectralFilmKernels.metal）。
  - `git diff` 既有 .metal 文件零命中（FilmSubRunKernels/Lut3dKernels/
    其余全仓 .metal 零 diff）。
  - 7 stage 函数 + A/B fused 入口 + corr 降采样 pass 在库（grep 计数）。
  - NaN 硬化三例在测试在册（T3 消费）。
  - GPL 归属机检〔review m5〕：`SpectralFilmKernels.metal` 文件头 GPL
    归属块（dt 衍生 + `Modified by Lightamer` 标注）与 NOTICE 登记行
    在库（grep 双断言——红线 16 纪律）。
- **commit**: `feat(m81b): port spectral metal kernel family`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（新文件，零既有面差）；
  偏差（fused 边界切分/降采样 pass 形态/常量块布局）= DECISIONS 申报；
  **禁触既有 kernel 文件**；**禁在 kernel 内 derive 倒数**（host 预倒值
  纪律）；**禁 81 波长循环入 kernel**。

## T2 — 表构建上传载体（sf_sim_gpu_t 同构）

**read_first**：RESEARCH §1.6（sf_sim_gpu_t 全 float 集合清单 + 表全部
build 期构建运行期只读）；`SpectralBuildEngine.swift`（SpectralFilmTables
值形态）；CONTEXT §X5（fence 纪律）；L014。

- **action**：
  1. `SpectralPayloads.swift`：`SpectralGPUPayloads` 载体（tc_lut
     texture2d **rgba32Float（alpha pad）或 buffer**〔review m9——Metal 无
     float3 像素格式；形态二选一与 kernel 消费签名一致，体积门按 442KB
     量级弹性措辞〕 + print/scan PCHIP 表 buffer 集〔lut+slopes+
     cmin/cmax〕+ 曲线网格 + 常量块 buffer〔m_in/m_out/CAT/OkLab/inv
     步长族——host double 一次取倒 rounded-to-float〕）+ build/upload
     面（`SpectralBuildEngine` 表 → GPU 资源；upload 后读回比对门测试
     供 T3 用）+ run-scoped 生命周期（FilmMethodBox instance 载体消费
     形预备——M8-2 接线，本面只管构造/持有/失效）+ nil-payload blit
     identity degrade 语义预备（nil = 透传，M8-2 消费）。
  2. 测试（IOPParity）：上传往返读回比对（float32 逐位——上传无损面断
     言）+ 载体失效面（deinit/清缓存语义）+ 表体积断言（442KB/2.5MB
     量级对账——RESEARCH §4.1 预算）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件（SpectralPayloads.swift）。
  - 上传往返逐位断言在册；体积断言在册。
  - `SpectralBuildEngine.swift` 零 diff（消费不改动——若需 host 侧配
    合 = DECISIONS 申报理由）。
- **commit**: `feat(m81b): add spectral gpu table payloads`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（载体拆分/常量
  块对齐形态）= DECISIONS 申报；**禁运行期写表**（表只读纪律）；**禁
  texture3d 形态漂移**（tc_lut = texture2d rgba32Float〔alpha pad——
  Metal 无 float3 像素格式，review m9〕或 buffer、PCHIP = buffer——与
  kernel 消费签名一致）。

## T3 — CPU/GPU bit-exact 断言（三板斧逐项 + 分歧带门）

> 测试策略门 3 正本（CONTEXT）。比较空间纪律 L048：一律 decode 回 linear
> + `Double(Float(x))` 升维比对。

**read_first**：CONTEXT §测试策略门 3 + §X5；RESEARCH §1.6（三案例正本
——fma contract/取倒/多项式放大）；M3-3-03 DECISIONS（分级带先例）；
`SpectralKernelGoldenTests` 消费的 Engine 参考面（M8-1a T4）。

- **action**：
  1. 七 stage 逐级 CPU（Engine Float64 参考）vs GPU（kernel 经测试宿主
     dispatch，fence 后读回）分歧带门：表构建路径逐位（常量块/倒值/多项
     式系数表）；逐像素 ≤1e-6 带域（合成 ramp + 常数场 + 中性场三输入）；
     分段边界专项例（曲线查表 256 点边界 ±1 ULP 步进 / PCHIP cell 边界 /
     knee 拐点）。
  2. 三板斧专项：①fma——同一矩阵路径钉形 vs 裸形双 kernel 变体对照（裸
     形分歧 > 0 的实证度量例——probe ⑤ 输入）②取倒——host 预倒值 vs
     device 重 derive 对照（分歧实证例）③共享多项式——Swift/MSL 同表
     log2/exp2 逐位恒等断言（固定抽样点集）。
  3. NaN 硬化三例（Y=0 场/NaN 注入场/Kr=0 哨兵）行为断言。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新测试文件。
  - 分级带门全绿（带终值 = DECISIONS 申报；超带 = 停手上报非放宽）。
  - 三板斧专项各在册；NaN 三例在册。
  - 既有 IOPParity 套件零回归（`--bundle IOPParity` 定向）。
- **commit**: `test(m81b): pin cpu-gpu bit exact discipline`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（抽样点集/带终
  值分级）= DECISIONS 申报；**禁放宽带门凑绿**（超带 = 根因排查——三板斧
  漏项排查表先行）；**禁跳过读回 fence**（L014）。

## T4 — perf probe 批五件（RESEARCH §4.3 + 一增）

**read_first**：RESEARCH §4.3（probe ①-⑤ 设计正本）；CONTEXT §测试策略
门 4；LensPerfProbeTests/GradeEnvelopePerfProbeTests（probe 形态先例——
LIGHTAMER_PERF_PROBE + XCTSkipUnless + L014 fence）；CONTEXT 红线 8/9。

- **action**：
  1. probe ①：tc 表构建耗时（28 张全量 + 单表 median）+ 白点散。
  2. probe ②：kernel microbench——合成 ramp + 真图 100MP（fixture 面），
     全帧 FULL + 分段 signpost（A/corr 模糊/B 三段）；100MP FULL 预算
     带 40-160ms 对照。
  3. probe ③：RSS 峰值——corr 1/4 vs 1/8 两方案对照（全幅对照臂仅本
     probe 内构造）→ **裁决数据**：1/4-1/8 终值 + corr 高频损失对 golden
     偏差带双门 → M8-1B-DECISIONS 申报；8G 门 + MEMFAIL 兜底（超 = 砍
     coupler fallback 申报）。
  4. probe ④：pristine/strength-0 基线逐位对照 + 光谱臂 ramp 哨兵值计算
     登记（legacy 哨兵 14_365_179_805_968_017_957 不动——亲核登记④）。
  5. probe ⑤：T3 fma/取倒钉形 vs 裸形分歧度量汇编（golden 门精度定级
     输入——分级带合理性复核）。
  6. probe 报告落 `evidence/probe-m81b/`（耗时/RSS/分歧度量数据正本 +
     corr 裁决双门数据）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新测试文件 + evidence 目录。
  - probe 测试 5-6 条在册且默认 skip（LIGHTAMER_PERF_PROBE 门）；实跑
    轮 = DECISIONS 附执行记录（skip 增量逐条申报）。
  - corr 裁决双门数据在 DECISIONS（1/4 vs 1/8 终值 + 偏差带）。
  - probe 实跑轮全程 machine-guard + caffeinate -dis（红线 7/9）。
- **commit**: `test(m81b): add spectral perf probe batch`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（probe 增减/
  100MP fixture 面）= DECISIONS 申报；**禁无批准实跑 --all 形重活**
  （本 probe = 定向 bundle 范畴，orchestrator 知会即可）；**禁全幅 corr
  进产线载体**（probe 对照臂域）。

## T5 — 收口（登记 + tuist + probe 报告汇编）

- **action**：
  1. `Project.swift` 两新测试文件入 IOPParity 显式数组 + BUNDLE-MAP 两行
     登记。
  2. `tuist generate` = 本批最后一个动作（L041）。
  3. `--bundle IOPParity` 定向全绿；ΔN 实数对账（预算 +12..18；skip 增
     量逐条申报）。
  4. SUMMARY（逐任务记账 + ΔN 终账 + probe 真值汇编 + kernel 解封申报
     面）+ DECISIONS（corr 裁决 + 分级带终值 + 各偏差）落盘。
  5. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿零回归；Project.swift diff = 恰
  两行数组插入；BUNDLE-MAP 在库；tuist generate 后无生成物入 git；
  SUMMARY/DECISIONS/evidence 在库。
- **commit**: `docs(m81b): close out spectral gpu plane`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY 申
  报理由；禁漏 tuist generate。

---

## 风险与回退

- **CPU/GPU 分歧超带**：三板斧漏项排查表（fma 漏钉位置 grep + 倒值 derive
  点清单 + 多项式表哈希比对）先行；根因 = 上游三案例同型复发的概率最高
  （§1.6 教训直指）；放宽带门 = 禁止，超带即停手上报。
- **RSS 超 8G 门**：降采样 1/4 实测仍超 → 砍 coupler fallback 档（X3），
  DECISIONS 申报模型完整性降档；全幅方案永久排除（H-M2）。
- **100MP 预算越带（>160ms）**：scan 段超越函数密度是主疑（§4.1 上修右
  端注记）→ probe ② 分段数据定位；处置 = M8-2 集成后按 FULL 渲染容忍域
  评估申报（不阻塞本 plan——真值先行，优化不在本批范围）。
- **kernel 编译失败/设备差异**：Metal 3 特性面保守使用（无 mesh shader/
  无 tile shader 依赖——本 kernel 族是纯 compute + 采样器面）；编译门随
  T1 冒烟先行。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §4.3 probe 五件 ↔ T4 逐件；§1.6 三板斧 ↔
   T1/T3 逐项；§4.2 corr 两方案 ↔ X3 降采样臂 + probe ③ 裁决。
2. **OQ 兑现核**：D-M8-3（PCHIP 臂 + 钳位面）/ D-M8-4（降采样 + 空间族
   零入）/ H-M1（三板斧 = 消解本体在 T3 断言）/ H-M2（全幅排除 + 兜底）。
3. **红线核**：既有 .metal 全仓零 diff；FilmTailPolicy/PixelPipe/
   RenderProcess 零 diff；probe 纪律三件（门/fence/RSS 口径）；Project.
   swift 数组段 + tuist 末位。
4. **SC 可机检性**：带门数值化 + grep 断言 + probe skip 计数；corr 裁决
   = 双门数据非拍脑袋。

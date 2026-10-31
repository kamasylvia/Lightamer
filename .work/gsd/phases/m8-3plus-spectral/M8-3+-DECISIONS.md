# M8-3+ DECISIONS — 裁定记录（seed 终式/轮数/回退公式/反转 id/阈值/kernel/分配器/偏差）

> 与 SUMMARY 同批落地（T7 收口 commit）。自审报告 = `SELF-REVIEW.md`
>（结论 PASS / 3 error + 12 minor；3 error 全修码，12 minor 全 cure——修码或
> 本文件登记）。

## 终式登记

- **seed 终式**：`fnv(recordHash ⊕ policyTag ⊕ solvedPackHash ⊕ upstream)` 不变；
  五腿经 `record.stableHash()` 自动折入（FilmTailParams :57 + :156 亲证）；
  anchored seed 不入 bake 键（收敛 seed 不变性——ULP 带近似成立，o5）。
- **轮数**：HOLD 32（velvia×crystal 烧满 32——反转档永不收敛；`rounds` 常量钉死）。
- **回退公式**：墙钉 + 自由拨盘 1D 黄金分割 40 轮 + 通道仿射增益
  `gain[c] = gm/raw[c]`（uniform log-add 消费；PCHIP 表零动）。
- **反转 id**：`"direct-positive"`（`SpectralNeutralSolve.directPositiveMode`
  单源；未知串 tolerant nil）。
- **阈值终值**：100px 起步值维持（重标 pending——σ_low ≈ 8 平台 + 144x+ 像素缩减；
  交点法定探针挂 T7+；三处注释已诚实化）。
- **kernel 终清单（16，超 12 预算——D7 扩预算）**：grain 五 +
  blur 对 2 + wide 三 + bank/mix/combine/apply 4 + gauss 对 2（8 调用面全消费，
  无死 kernel）。
- **分配器峰值**：100MP 全开 3.2GB（2 rgba32F 平面）≤ 3.5GB 门（串行复用峰值 =
  max 非 sum）。
- **B-1 注记（T6 A4）**：守恒回退改 build 产物 midgain，不经 ColorWheels 1/γ
  target——面不相交；负测由安全档零漂移主门覆盖。
- **v4 预留登记**：三算子 on 档语义冻结代际 + 反转 B 默认翻转代际——未来任一语义
  变更即 mint v4（`assembleFilmLeg` 穷举 switch 编译期指向已在；本批零 bump，
  current 恒 3）。

## 机器门

- guard G4 透明越门（Data 卷 ~16-20G 现实基线，free 70%+；起跑前清 /tmp 残留）+
  `--monitor 21600 &` 全程伴跑（monitor-exec.log）+ ps 清零（测试宿主 parentage
  核对——M2-7-3 教训）。
- 全套 `--all` 归 orchestrator 批准轮（本批只跑定向五 bundle + 带式对账）。

## 偏差全申报（D1..D13）

| # | 偏离 | 处置 | 证据 |
|---|---|---|---|
| D1 | seed 逐位→1e-9 带（K1 判据→CC 点量级） | 接受（Newton 路径依赖；注释/测试名 T7 已同步） | T1 message + 派生单测注释 |
| D2 | Evidence C / §1.3 C200 行印值被 replay 推翻 | 接受（定标漂移；C 位成立） | REPLAY-RECORD calibration notes |
| D3 | 轮数 HOLD 32 | 接受（反转档烧满） | T1 message + 轮数门单测 |
| D4 | A1 单调门→终值不爬升；A4 残差门 +1.0 | 接受（初版比错对；跨 target 比较无意义） | T2 单测注释 |
| D5 | 28 对 hash→finite | 接受降级（单 ramp512 哨兵 + verbatim + 全套绿；考古 27 hash 挂账） | T4 message |
| D6 | bake HIT→源码 census | 接受（脆但诚实；行为腿挂账） | T3 单测注释 |
| D7 | kernel 16>12 | 扩预算（8 面全消费；K7 登记 cure） | 本文件终清单 |
| D8 | print 腿座位无 on 面；probe 未更新 | scope 声明（print 腿挂账；probe 沿用旧测点） | 代码注释 |
| D9 | 阈值未法定 | pending 声明（100 起步值维持） | T5 message + m2 注释 |
| D10 | ΔN +52（越上沿 +12） | 越带理由：T3/T4/T5 覆盖性超交（honest over-delivery） | 各 message + MAP |
| D11 | C200 修前对照表缺修前钉值 | 缺口声明（修前 3% 引 R9 文献；>200 steps 修前 posterize 无钉值——考古挂账） | T2 message |
| D12 | T6 A4 B-1 注记 + v4 预留 | 本文件已登记（见上） | — |
| D13 | E2/E3 | 已修码（E2 picker 绑 converged；E3 RMS tag 接线） | T7-F1 批复验 |

## 自审回注处置

| 项 | 处置 | 复验 |
|---|---|---|
| E1 referenceUm | 47→10 + 单测单源 + 钉值 | IOP 6/0/0 |
| E2 C 收敛死面 | picker 绑 converged + 注释修正 | App Clamped（终验轮） |
| E3 npart 占位 | RMS tag 接线（runtime-only） | 随全套（金腿复跑） |
| m1/m2/m4/m9 | 注释/名诚实化 + 三翻转 + 断言软化 | 定向复验 |
| m3/m5/m6/m7/m8/m10/m11 | DECISIONS 登记 cure（D5/D6/D7/D8/D4/D10） | — |
| m12 脚本幂等 | 挂账（RECORD 标注复跑可刷新） | — |
| T7-F1 冻表 | +10 ids + D-M8-7 修订口径 | App 单腿 1/0/0，终验全轮 |

## GPL 转录清单

- `data/kernels/grain.h` 全文（hash/Poisson/particle/多项式）→
  SpectralSpatialKernels.metal sfg_* twin
- `data/kernels/spektrafilm.cl:510-660`（grain 五 kernel）→ grain 五
- `data/kernels/spektrafilm.cl:1013-1068`（wide 三件）→ wide 三件
- `src/common/spektra_core.c:391-422`（plan）→ SpectralWideBlurPlan
  （TRUE-σ 偏离显式申报）；`:437-560`（down/up twins）→ host twins；
  `:780-900`（sf_halation）→ still 基线 + 腿；`:936-1000`（族表/bank）→
  SpectralSpatialTables
- `src/common/spektra_sim.c:100-122`（still 默认）→ 基线值；`:2569-2592`
  （nl==1 臂）→ SpectralGrainSublayer
- 树号：`4d1fb6a95b`；NOTICE 3b/3c；版权头（metal 全头 + Swift 归属注）。

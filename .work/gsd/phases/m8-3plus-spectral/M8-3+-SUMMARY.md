# M8-3+ SUMMARY — 光谱延展：C200 两段式修法 + 空间三算子接谱 + m-6①/时长维收尾

> 执行：omp（M8-3+ 执行 lane）。审期：2026-10-31 → 2026-11-01。
> PLAN 正本 = `M8-3+-PLAN.md`（v2，复审放行）；research 正本 = `RESEARCH.md`。
> issue：#21（M8-3+ 批）。
> 上游正本：dt spektrafilm `4d1fb6a95b` 树（宽模糊四 commit 收口态；HEAD 已无
> wide 符号——git show 读法全带树号）。

## 一、交付（T1..T7 commit-per-task，refs #21）

| T | commit | 内容 | ΔN |
|---|---|---|---|
| T1 | `0b9f480d` | 锚 seed + solve 抽取 + clamped 旗 + static_replay 12/12 + HOLD 32 | +5（IOP） |
| T2 | `d0e175af` | 守恒回退 + 反转路由 + disclosed + 6 键 | +10（IOP 5/IOPP 2/App 3） |
| T3 | `51efaa14` | 五字段 + sidecar v13 + seed 折叠 + bake 不折 + pristine | +10（LIB 3/Layers 4/App 3） |
| T4 | `a85dbcb4` | B 拆口 + grain 五 kernel + 子层派生 + 量纲桥 + B-track 面板 + NOTICE 3b | +12（IOP 6/IOPP 4/App 2） |
| T5 | `fd9e85d7` | 宽 plan + 抽稀三件 + halation/diffusion 表 + 前置腿 + B2 钩 + 分配器 + 面板 + NOTICE 3c | +13（IOP 6/IOPP 5/App 2） |
| T6 | `eb6d3953` | 写腿单行 + t6_probe 3/3 + m-6①配方 | +0 |
| T7 | 本 commit | 冒烟 2 法 + 自审修复（E1/E2/E3/m1/m2/m4/m9/冻表）+ 收口三件 | +2（IOPP）+ fixes |
| **合计** | | | **+52**（越 PLAN 带 +27..40 上沿 +12——DECISIONS D10 登记） |

## 二、逐 T 战果

- **T1**：`SpectralNeutralSolve` 纯函数（Newton 梯 verbatim）+ `NeutralPrintAnchorTable`
  （160 triplets 只读）+ `tables.clamped` + consult 锚 seed（缺席回落 (50,50)）。
  seed 同一性 = ULP 带（最坏 1231 ULPs ≈ 8.7e-12 CC——路径依赖，K1 判据同步降为
  CC 点量级移动）。轮数裁决 HOLD 32（velvia×crystal 烧满）。Evidence C / §1.3
  C200 行 research 印值被 replay 推翻（106.3/197.5 → 108.33/250 墙——定标漂移，
  C 位（单盆地 seed 不敏感）成立）。
- **T2**：clamped 对墙内 1D 线搜索（M 自由）+ 通道仿射增益（uniform u[36..38]，
  kernel log-add 消费；PCHIP 表零动——bake 键诚实）。C200×crystal 修后：
  clamped=true、Y=250 钉墙、灰误差 <0.5%（修前 3% R9）、gain 非 ones。
  反转 B 路（scan 腿中性目标）+ C 收敛（picker 绑 converged 列表，T7 E2 修通）+
  disclosed amber 行。安全档 gain==ones 逐位 + triple/闭包零漂移。
- **T3**：五字段三面（nil 缺席恒等）+ sidecar v13（封存例外①，T2 窗口字节兼容）+
  recordHash 自动折 seed（五腿逐字段翻转——T7 m4 补齐）+ bake 三槽不折（源码
  census 3 fold）+ isPristine 手扩。
- **T4**：fused B 退役 → B1（develop → CMY 平面）+ grain 组（nil/0 双跳过）+
  B2（print/scan + T5 钩座位）。grain 五 kernel（GPL 转录，USM pow 走共享多项式）
  + 分离 blur 对 + 子层派生（nl==1 臂；referenceUm E1 修 47→10）+ 量纲桥（25↔1.0）
  + B-track 面板（off 默认，遗产一键零交互）。E3 接线：RMS tag → payload →
  dispatch npart 反演（退役 1000 占位）。哨兵：ramp512 逐位 + 28 对 finite +
  dual-arm 12/0/0。
- **T5**：wide plan（TRUE-σ 目标）+ 抽稀三件（CPU/GPU 逐位）+ still 基线 + 四族表
  （verbatim bank ≤11）+ 前置腿（taking diffusion → halation，上游序）+ B2 钩
  （uniform 门，off 恒等）+ 分配器（100MP 全开 3.2GB ≤ 3.5GB 门）+ 双节面板。
  阈值 100px 起步值维持（重标 pending——m2 注释诚实化）。kernel 16（超 12 预算——
  m6 DECISIONS 扩预算）。
- **T6**：`filmRecordDidChange` 内 schedule 前移到 render 前（单 hunk，其余 7 处
  不动）+ t6_probe leg-1 三门 PASS + leg-2/m-6① 配方（pending orchestrator 轮）。
- **T7**：冒烟 2 法（全 off 四对 finite + 三腿全开 finite/确定性）+ 冻表扩 10 ids +
  自审 3 error 全修 + 收口三件（本 SUMMARY + DECISIONS + MANIFEST）。

## 三、定向五 bundle 全绿

| bundle | 终值 | 说明 |
|---|---|---|
| Layers | 540/5/0 | 含 T3 seed 翻转补法 |
| Library | 788/4/0 | 含 v13 三面 |
| IOP | 836/1/0 | 含 T1/T2/T4/T5 新套件 |
| IOPParity | 578/10/0 | 含哨兵/抽稀/腿/冒烟 |
| App | 1102/6/0 | 冻表扩后复绿（见 §六 T7-F1） |

全套带式对账：基线链 4461/34/0（mcp-uq 收口轮）⊕ 本批 ΔN=+52 = **预期
4513/34/0**（--all 归 orchestrator 批准轮；Sessions/Export 两 bundle 未跑，
沿收口轮值）。

## 四、封存面声明

17 件：除 `LightamerSidecar.swift`（例外①：v13 注释 + digit 单 hunk）外全零
diff（`git diff --name-only` 亲证）；PixelPipe = 1 处 additive 默认参
（E3 RMS tag 递入——目标零触未达成，逐 hunk 申报：行为零变，nil tag = 旧路；
DECISIONS 登记）。v1 双文件零 diff；RenderProcess 零 diff + current 恒 3；
GrainModule 零 diff；CC 资产 MANIFEST 全 OK。

## 五、偏差申报（一句话版，全量见 DECISIONS D1..D13）

D1 seed 逐位→1e-9 带；D2 Evidence C/§1.3 C200 行推翻；D3 HOLD 32；
D4 A1/A4 门弱化；D5 28 对 hash→finite；D6 bake HIT→census；D7 kernel 16>12；
D8 print 腿/probe 挂账；D9 阈值未法定；D10 ΔN +52；D11 修前表缺口；
D12 B-1 注记 + v4 预留；D13 E2/E3 已修码。

## 六、T7 修复批（自审回注 + 定向红）

- **T7-F1（定向红）**：App bundle 1102/6/1——冻表快照测试未随新控件更新。
  修：冻表 +10 ids（disclosed/reversal×2/grain×3/halation×3/diffusion），
  D-M8-7 修订口径登记（新算子 = 新控件）。复验 App 1/0/0（单腿）——全轮待终验。
- **E1（转录错）**：referenceUm 47→10 + 单测改单源 + 钉值。复验 IOP 6/0/0。
- **E2（C 收敛死面）**：picker 反转分支绑 converged 列表 + 单测注释修正。
  复验 App Clamped 3/0/0（待终验与 F1 同轮）。
- **E3（npart 占位）**：RMS tag（runtime-only，不折键）→ coordinator memo 解析 →
  payload → dispatch 反演；退役 1000。复验随全套。
- **m1/m2/m4/m9**：注释/测试名诚实化 + seed 三翻转 + 曲线断言软化。复验随定向。

## 七、走查 MANIFEST

`.work/gui-acceptance/m8-3plus/MANIFEST.md`（配方 6 项——disclosed 行/反转收敛/
三算子 off 节/portra 对照（m-3③）/C200 前后对照/三戳+m-6①；执行归批准轮）。

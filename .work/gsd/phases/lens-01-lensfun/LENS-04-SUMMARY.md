# LENS-04 SUMMARY — plan L4:系数快照 + process 裁决 + 测试收口 + perf probe

> status: executed | date: 2026-10-21 | 起算基 = LENS-03 终态(626c0e09)
> 裁决正本 = CONTEXT.md(D-LENS-3 + X3 + H-L1/H-L2 + 红线 15 条)

## 逐任务记账

| 任务 | commit | 内容 | ΔN | 验收 |
|---|---|---|---|---|
| T1 | `87ca36c1` | LensCoefficientSnapshot(标定提取面——分辨率无关行 + 元数据,非 kernel-ready)+ bakeCommitted/rematch/clearSnapshot + install-time dbTag(16 hex)+ Params.snapshot(internal)+ commitParams strip-on-hash + resolveUniforms SNAPSHOT-FIRST(虚拟 entry 零 DB 重解析)+ reloadDefaults auto 同步 bake(D-L4-1 option A)+ 面板 Re-match/选型 bake + 标定结构 Codable/Hashable 化 + LensSnapshotTests 5 | +5 | IOP 5/0/0 |
| T3 | `be85ec89` | LensCacheIsolationTests 4(on/off 翻转/nudge/dbTag strip/纯函数负例) | +4 | IOP 4/0/0 |
| T4 | evidence repo commit + SUMMARY 本文件 | golden 总账全绿(projection 5 对 + coincident + scale 2 面 + narrowing + warp/TCA/vig track-A);RawLab 抽查 = **环境缺口延后供件**(host libraw 0.22.1 < 0.22.2;pinned 源缺席;evidence repo `lens-01-lensfun/rawlab-sampling-ENVIRONMENT-GAP.md` 含复跑配方,非静默跳过) | +0(测试面已由 L2/L3 golden 承载) | golden 总账表在本文件下方 |
| T2 | `aff1269b` | process version 裁决:八项 × 三问全表(含 L1 匹配硬化 legacy 档 + L4 快照)→ **全默认中性 = 不 bump**;RenderProcess.swift 零 diff(机检面);默认中性 golden 对 = LensDefaultNeutralGoldenTests 2(batch-default face = identity blit 逐字节 + 投影前缀恒等)+ CacheIsolation strip 对齐 | +6(2 golden + 4 cache;cache 兼 T3) | IOPParity 2/0/0;IOP 4/0/0 |
| T5 | `ef6c8ca2` | LensPerfProbeTests(skip-gated 3)+ **实测数字**:distortion-100MP 32.7ms / projection 15.5ms(plain 32.8,0.47x)/ memo first 1.02ms → hit 0.005ms(~200x)+ **全套 --all 三轮 4088/40/0 同值** | +3(probe 族 skip)+ --all | probe 3/0/0 |
| T6 | 本 commit | docs + MANIFEST 申报 | 0 | — |

**ΔN 终账 = +26**(5+4+0+6+3)。预算 +12..16 越带 +10:T2 的 cache-isolation 4 法(+T3 名义)与中性 golden 2 法合计 6 法因测试落域调整挂 L4;probe 族 skip +3 申报(skip 40 = 37 基线 + probe 3)。

## 全套 --all 三轮对账(orchestrator 批准已给;G3 惰性平台偏差记录 D-L4-4)

| 轮 | TOTAL | rc | 峰值 RSS(max bundle) |
|---|---|---|---|
| 1 (092311) | **4088/40/0** | 0 | IOP 7657MB |
| 2 retry (101717;首跑 Library flake 作废轮 2458/20/1 单测复绿 3x) | **4088/40/0** | 0 | 同型 |
| 3 (113746) | **4088/40/0** | 0 | 同型 |

对账:基线 3991 + ΔN 97(L1 36 / L2 33 / L3 20 / L4 8)= **4088 精确** ✓。**越带申报:全批 ΔN +97 vs 带 4050..4079,越 +9**(上限 88;表驱动密度逐 plan 已申报:对称断言面 + 环境容错例为实体覆盖非灌水)。七 bundle 全部 <8G 门(MEMFAIL 零)。

## golden 总账(T4)

| 面 | 测试 | 门 |
|---|---|---|
| warp/TCA/渐晕(track-A EXR)| LensParityTests | 1e-5 rel |
| 匹配/插值 | LensfunDBTests + LensMatchHardening | 手算 pin |
| scale(L2 序)| LensScaleGolden(scale=1/1.25 + narrowing 零畸变精确 1/s)| 1e-5 |
| projection(L3 五对 + coincident)| LensProjectionGolden | 帧内 1e-5 / 折叠域 2e-3(登记)|
| 默认中性对(批仲裁证据)| LensDefaultNeutralGolden | 逐字节 |
| 快照 round-trip/消序/dbTag | LensSnapshotTests | 逐字节/等值 |
| RawLab 抽查 | **延后供件**(evidence repo 环境缺口 + 复跑配方)| 非 CI 门 |

## 红线核验

- LightamerSidecar 零 diff ✓(快照骑 paramsData);RenderProcess 零 diff(不 bump 机检)✓
- bake 写入点恰二处(auto-apply 同步 bake / browser 选型)✓;dbTag strip-on-hash 断言 ✓(双测试)
- probe fence(L014)✓;--all 三轮同值 + MEMFAIL 零 ✓;probe 族 skip 申报 ✓

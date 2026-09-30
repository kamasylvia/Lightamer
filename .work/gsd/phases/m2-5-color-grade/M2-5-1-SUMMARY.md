# M2-5-1 SUMMARY — Grade 新件核 wave 1 收口（2026-09-30 夜间批）

> plan = M2-5-1-PLAN.md（checker 修正版 87c039d）。执行 = 本 subagent（ZCode），T1-T8 逐任务独立提交、每任务边界读 config.toml [gsd]（paused=false/auto=true 全程未变）。签注正本 = 同目录 M2-5-1-DECISIONS.md。

## 提交链

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `ba70717` | GradeCatalog 18 目录五元组 + defaultLook + V50Order 十行 + 七件参数载体 + GradeCatalogTests |
| T2 | `1853026` | ACESccMath/Convert + envelope op 对 + driver 包夹缝（LayerCompositeSeam）+ ACESccEnvelopeTests |
| T3 | `8d3d145` | CAT02 WB 完整件（Planck 积分 xy + CAT02 适应阵）+ golden/coding |
| T4 | `0434afd` | Contrast（OkLab S 曲线）+ White/Black 端点对 + golden/coding |
| T5 | `2e84312` | Saturation（luma-pivot + peak 限幅）+ Tint + golden/coding |
| T6 | `e2aa894` | colorWheels LGG（power 腿式）+ IsIdentity 照抄 + golden/coding |
| T7 | `9f00277` | HLS 8-bin（Gaussian 窗 + YIQ 旋转）+ applyTargetEdit + golden/coding |
| T8 | （本提交） | SUMMARY/DECISIONS/GOAL-STATE 收口 |

## 七件 v50 终位表（KD-3；black 挪位签注见 DECISIONS §二）

| op | order | 模块 |
|---|---|---|
| acesccIn | 20.5 | ACESccInModule（不注册，driver 直构） |
| colorWheels | 41.0 | ColorWheelsModule（与未注册 dt colorbalance 同位 = 声明例外） |
| cat02WhiteBalance | 41.4 | Cat02WBModule |
| contrast | 41.6 | ContrastModule |
| white | 41.8 | WhiteModule |
| black | 41.95 | BlackModule（42.0 撞 rgbcurve，±0.05 挪位） |
| saturation | 42.2 | SaturationModule |
| tint | 42.4 | TintModule |
| hls | 42.6 | HlsModule |
| acesccOut | 69.9 | ACESccOutModule（不注册） |

## 测试数变化（BUNDLE-MAP 对账）

- 基线 2240/14skip/0fail（M2-5-1 起算）。
- 新增四测试文件：GradeCatalogTests（APP，14）+ ACESccEnvelopeTests（LAYERS，5）+ GradeKernelGoldenTests（IOPP，18）+ GradeParamsCodingTests（IOP，10）= **+47 测试方法**。
- V50OrderTests 既有方法数不变（15），断言内钉值更新（count 95→105、同位簇 {28.5}→{28.5, 41.0}、剥离集 +10）。
- 预期全套终值 ≈ 2287/14skip/0fail（2240 + 47；全套 --all 终跑数字见下节）。

## 全套回归终跑（--all）

收口终跑（coordinator 报备批准后实跑，2026-09-30）：

```
BUNDLE|IOP|467/1/0|peakRSS=7378MB|113s|sampling=time
BUNDLE|IOPParity|326/2/0|peakRSS=5987MB|229s|sampling=time
BUNDLE|Layers|179/2/0|peakRSS=947MB|19s|sampling=time
BUNDLE|Library|430/4/0|peakRSS=295MB|17s|sampling=time
BUNDLE|Sessions|279/4/0|peakRSS=1636MB|69s|sampling=time
BUNDLE|Export|260/1/0|peakRSS=6679MB|191s|sampling=time
BUNDLE|App|346/0/0|peakRSS=1479MB|78s|sampling=time
TOTAL|2287/14/0|716s        （EXIT=0）
```

- **2287 = 2240 基线 + 47 新增精确**（GradeCatalogTests 14 + ACESccEnvelopeTests 5 + GradeKernelGoldenTests 18 + GradeParamsCodingTests 10）；skip 14 不变；**MEMFAIL 零触发**（峰值 IOP 7378MB < 8192 门；次峰 Export 6679MB）。七 bundle 全绿 0 fail。
- Library/Sessions/Export 三 bundle 本 plan 零代码触碰，计数与基线继承一致（430/279/260），回归干净。

## 容差实配值（详见 DECISIONS §六）

| 面 | 实配 | 依据 |
|---|---|---|
| 纯函数（矩阵/xy/映射） | ≤1e-6 | KD-8 |
| GPU vs Float64 参考（linear 域比较） | p99.9 ≤1e-5，max ≤5e-5 | KD-8 + 空间选型签注 |
| 输出窗 | [-0.5, 2.5] 裁剪统计 | plan KD-8 原文条款 |
| CAT02 (2000K,+150) 病态角点 | p999 ≤1e-3 / max ≤5e-3 + bounded | DECISIONS §六 |
| ACEScc 往返（envelope） | 绝对 ≤1e-5 @p99.9（max ≤5e-5） | KD-2 |
| identity 参数点 | 像素容差 0（flag 早退） | KD-8 |

## envelope 半径 diff 自核（T2 提交 1853026）

- `PixelPipe.swift` / `PipeCacheKey.swift`：**零 diff**（`git diff 87c039d..HEAD -- <file>` 空输出）。
- `LayerCompositeDriver.swift`：3 hunk——①adjustment 腿 `let`→`var` + 1 行 seam 调用（+4 注释行）；②文件尾新增 public `LayerCompositeSeam` 持有器（Core 不可 import IOP 的合法缝，D-03）；③seam MARK 注释。blend 公式/retouch 腿/base sub-run/terminal 段/结果 struct **零改动**。
- `Registry.swift`：`ACESccEnvelope.install()` 1 行 + 七处 register + prewarm 8 行 + default face seed 注释（seed 本体未动——grade ops 面板驱动，P2 接线）。
- AC #4 机检：`git grep -n "ACESccIn" LightamerIOP/Sources/Registry.swift` 零命中（install 调用点名 `ACESccEnvelope`，不含子串）。

## AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | GradeCatalog 18 项/gradeItems 14/完备性（E7 执行解读）/owner 矩阵/m5 五件断言/shadhi 分立/既有所有权测试零改动 | ✅ GradeCatalogTests 14 + NodeOwnershipCatalogTests 6 全绿 |
| 2 | V50Order add-only 形态（零删除/零修改行）+ 十行 + 唯一性三不变量 | ✅ git diff 仅新增 hunk；GradeCatalogTests 唯一性断言 |
| 3 | 往返 identity/空链·纯非目录链跳过/retouch·base·terminal 零包夹/E1 排序/键稳定/E2 盘点 | ✅ ACESccEnvelopeTests 5 + DECISIONS §五 |
| 4 | envelope 零注册/零 sidecar/零可见面；PixelPipe/PipeCacheKey 零 diff | ✅ grep 机检 + diff 机检 |
| 5 | CAT02 identity 两断言 + 四角点/参数点 golden | ✅（病态角点签注 §六） |
| 6 | Contrast identity@0/单调/色相漂移 ≤2°（OkLab 基）/White·Black 端点有界 | ✅ |
| 7 | Saturation 0-4（1.0 恒等、端点无 NaN）/Tint ±100 | ✅ |
| 8 | colorWheels params 逐字段 + CodingKeys 同拼写 + IsIdentity 照抄 + 三 identity 容差 0 + golden | ✅ |
| 9 | HLS params 逐字段 + 权重窗断言（Gaussian 签注）+ applyTargetEdit ≤1e-6 + 8 bin 遍历 | ✅ |
| 10 | 全套回归 0 fail，计数 ≈2240+47 | 见 --all 结果节 |
| 11 | diff 边界 == 申报集 | ✅ 唯一越界 = V50OrderTests（T1 已声明偏差） |
| 12 | 四新测试文件 × Project.swift + BUNDLE-MAP 双登记 | ✅ |

## 已知限制 / 移交

- **域盲五件**：exposure/shadhi/vibrance/tonecurve/lut3d kernel 不换域——非 identity 参数的层内行为随包夹改变（D1 零代码的结构性后果；面板/语义对齐归 P2，详见 DECISIONS §五备忘）。
- **envelope GPU 代价**（OQ-11 观察项）：+2 全屏轻 ALU pass/层；性能走查归 P3 收口三查，本 plan 只证正确性/键稳定。
- **色相度量基**：Contrast 的色相保持按 OkLab hue 钉（DECISIONS §一 D2）——P2 面板若需 HSL 口径文案，按实际算子基标注。
- **seed 未动**：八新 op 不在 editingDefaultInstances（pristine seed 保持 terminal trio + tone 面）；P2 面板接线时决定 grade ops 是否入 seed。

## flake 记录

无在案 flake 复现。T2 开发期一次 `ModuleBox.apply` precondition 崩（测试自身 fresh UUID 错配）与一次假黑场（floatPlane 误读 bgra8 显示面）均为测试脚手架缺陷，已修；非产品代码问题。

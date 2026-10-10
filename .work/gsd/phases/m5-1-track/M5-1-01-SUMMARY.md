# M5-1-01 SUMMARY — TRACK P1：统计域 + S1/S3 求解器 + colormatch op 核心

> 执行 2026-10-11（夜间全自动授权）；基线 `dcd02a8`；8 commits
> `47a27be..b83db8f`；不 push。规格正本 = RESEARCH-NOTES §3 + PLAN M5-1-01
> （checker 回注 E1/E2/E4/E7/m1/m2/m3 全部落地）；实测带与钉死值正本 =
> 同目录 `M5-1-01-DECISIONS.md`。

## 任务序与 commit

| 任务 | 内容 | commit | 状态 |
|---|---|---|---|
| T1 | `OklabMath.swift`（Float32 产线 + Float64 孪生，M1C/M1C⁻¹ 预合并单矩阵，符号保持 cbrt，零 clamp）+ `ColorMatchOklabTests` 7 法 | `47a27be` | ✅ 7/0/0 |
| T2 | `ColorMatchStats.swift`（μ/Σ 六元组 + 3×256 整数直方图 + 1%/99% 整数秩截尾 + 支撑域 + statsHash 折 μ/Σ 位模式）+ Tests 10 法 | `1d16b5f` | ✅ 10/0/0 |
| T3 | `ColorMatchSolver.swift`（S1 对称三明治 + S3 标准差比对角 + R1 正则化/回落）+ `ColorMatchSolveCache.swift`（NSLock LRU 8） | `c4fa099` | ✅ 编译绿（结构断言随 T4） |
| T4 | `ColorMatchSolverGoldenTests` 10 法（G1 双跑 bit-identity/退化回落确定/缓存透明/键字面钉死 + E1 数学结构双门 + G3 矩精确/采样/对角恢复 + T3 SPD 根基不变） | `97a1c32` | ✅ 10/0/0 |
| T5 | `ColormatchModule`（Params 直存 + 显式 null + identity blit + L069 锁）+ Registry seed ABSENT + V50Order 36.5（106→107）+ GradeCatalog 第 20 行 + IopCatalog additive 行 + templateInstance case（E2 前置缝）+ 五测试文件钉数同步 + `ColormatchModuleTests` 7 法 | `518bd87` | ✅ 全绿 |
| T6 | `ColorMatchKernels.metal`（colormatch_linear 单 pass，OklabMath 常数同源，precise::pow）+ `ColorMatchUniforms.swift`（52B ABI） | `0817115` | ✅ metallib 吸收亲证 |
| T7 | `ColormatchKernelParityTests` 2 法（G2 双面门） | `fff0635` | ✅ 2/0/0 |
| T8 | `ColormatchIdentityGoldenTests` 2 法（G5 三态逐字节直通 + 反空转） | `b83db8f` | ✅ 2/0/0 |
| T9 | 收口（本文 + DECISIONS + GOAL-STATE + TODO + 红线自证） | 本 commit | ✅ |

## 定向轮四 bundle（本批终值，全绿零 MEMFAIL）

```
BUNDLE|Layers   |438/3/0|peakRSS= 958MB|160s
BUNDLE|IOP      |563/1/0|peakRSS=6848MB|164s   （< 8192 门，余量 ~16%）
BUNDLE|IOPParity|438/3/0|peakRSS=6667MB|566s
BUNDLE|App      |711/4/0|peakRSS=2832MB|362s
```

本批新增 **38 测试法**（6 文件）：Oklab 7 / Stats 10 / SolverGolden 10 /
Module 7 / KernelParity 2 / Identity 2。逐 bundle 增量对账：IOP +1
（V50OrderTests +1 法）、IOPParity +11（Module 7 + Parity 2 + Identity 2）、
Layers +27（本批三文件）+ M4-3 存量增量、App +7 全为 M4-3 存量（本批 App
侧零新测试文件，钉数修订在既有文件内）。全套 `--all` 轮未跑（照批准制，
基线推算 = 3335 + M4-3 批增量 + 本批 38，待 M5-1-03 收口统一申请）。

## 五门状态（OQ-8 分账）

- **G1 求解确定性 ✅**：双跑 Float32 位型 + stableHash 逐位；退化回落确定
  （零 trace → 恒等+offset；秩亏 → S3）；缓存透明 + LRU 驱逐 + invalidateAll；
  键折叠序字面钉死（DECISIONS §3）。
- **G2 kernel parity ✅（双面门）**：良态子集 p99.9 scale-aware ≤1e-5；
  全网格 abs p99.9 ≤4e-3 / max ≤5e-2（cbrt 交越机制注记 + 实测带钉门，
  DECISIONS §2/§6）。**plan 的 1e-5 单一目标在交越像素上数学不可达**（机制
  在案，非降级交付——良态面已兑现 1e-5 级）。
- **G3 语义 golden ✅**：矩精确臂恢复 T_true（commuting 族构造，DECISIONS
  §4）≤1e-3；采样臂 1.73e-2（trim shuffle 机制）；S3 对角恢复 ≤1e-6。
- **G4 = M5-1-03**（未启）。
- **G5 恒等回归 ✅**：缺席（seed ABSENT 双面结构断言）/ 禁用 / strength=0
  三态逐字节直通 + 反空转（solved strength-1 实动像素）；定向轮 IOP/IOPParity
  全量绿 = 既有 op 零触碰的旁证。

## 红线自证清单（`git diff dcd02a8..HEAD` 亲证）

- [x] 零新 SPM 依赖（Project.swift diff 仅测试编列 6 行）
- [x] `V50Order` add-only：仅 `("colormatch", 36.5)` 一行，106→107；
      V50OrderTests 16 法绿（unique/floor/邻域全断言）
- [x] `defaultFaceDisabledOpNames` 零触碰（grep diff 0 命中）
- [x] 密封面零 diff：`LightamerIOP/Sources/Lut3d/`、
      `LightamerCore/Sources/Sidecar/`、`Pipe/History/`、`PipeCacheKey.swift`、
      `PipelineDocument.swift`、`Graph/NodeGraphCommand.swift`（checker m3
      路径集）零命中
- [x] sidecar 零 schema 变更；HistoryStack/HistoryHash/ModuleInstance 零触碰
- [x] `.metal` 新增面 = `ColorMatchKernels.metal` 一文件一 kernel，零
      function constants（申报面 = 实际面）
- [x] lut3d 密封面（Lut3dModule/CubeLutParser/LutLibraryStore/Lut3dKernels.metal）
      零触碰
- [x] `zh-audit --check` PASS（1617 source / 1855 catalog keys；xcstrings
      零改动——占位期无消费点，DECISIONS §5）
- [x] `defaultFaceOps() == 16`（机制修正，DECISIONS §5）；`defaultFaceOps()
      相邻钉 15 不动` 的 plan 原文按机制证伪改 16

## 交付面边界（P2 衔接）

本批交付 = 统计函数面（样本级；平面 tap 适配器未做）+ S1/S3 求解 + 缓存 +
colormatch op 线性臂（可加不可编恒等占位，filmPlacement 先例）。**未交付**
（M5-1-02）：面板/交互、S2 CDF、`.cube` 派生资产、65³ bake、多参考池化、
prewarm 名单补位、xcstrings 面板键族。M5-1-03：`match_color` MCP + G4。

## 已知风险与移交注记

- 交越不稳定（DECISIONS §2）是 Oklab f32 正向的固有数学面：极端离群像素上
  lab 误差 ~1e-3 级。渲染观感影响 = 交越像素（对消到 LMS≈0 的色彩，实践上
  近黑/近原色边界）的亚毫级偏差——GUI 走查观察项挂 M5-1-02 走查清单。
- 采样臂 1.73e-2 恢复带 = trim shuffle 机制，非缺陷；M5-1-02 的求解 UX
  （参考图统计提取走同一 extract）继承同一带。
- `CatalogAddFaceTests` 的 identityJSON 逐字节断言自动覆盖 colormatch 新行
  （Params() == 行 identityJSON）。

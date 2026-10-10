# M5-1-02 DECISIONS — TRACK P2：S2 CDF + LUT 臂 + 池化 + 面板交互

> 执行批 2026-10-11（夜间全自动授权「开跑，不要停」）；基线 M5-1-01 验收后
> HEAD `e4acb70`，7 commits `14d032d..4cc1c52`。任务序 T1..T8 与 PLAN 一致
> （T6+T7 合并提交，申报见 §6）；本文只记**偏离、实测带、钉死值与机制发现**。

## 1. S2 求解器（T1）——支撑 bin 的推导面勘误

- **支撑 bin 不从 `supportLo/Hi` 浮点值反推**（执行期首轮实测抓到的机制缺陷）：
  `binIndex(binValue(bin))` 在 Float32 截断下可低一格（L 通道 1% 分位实测差一
  bin），P1 的 extract 从不依赖该逆映射（样本直接进 binIndex），S2 首轮把它当
  支撑还原器用即翻车。终形 = **支撑 bin 由直方图分位走查重推导**（与 extract
  同一轮梯）——直方图本就是 S2 的完整输入（E4 充分性注记的自洽兑现），存储的
  supportLo/Hi 只作面板读数。
- 分位对齐 = **整数交叉相乘**（`cumRef·totalSrc ≥ cumSrc·totalRef`，两侧
  < 2^64 精确）——零浮点比较，整数秩纪律无断裂。
- 平台面终形：源支撑外 bin → 参考支撑端值；支撑内梯位 **clamp 进参考支撑**
  （输出恒在参考 1%..99% 内——覆盖 ≥98% 裁定）。
- solutionHash = 共享 solve-cache 键折叠（`cacheKey(.cdf)`）——bake 键继承
  P1 的折叠序字面钉死；`.cdf` cacheTag 字面 = `colormatch.solve.cdf.v1`。

## 2. 池化（T2）——补全面

- support 池化 = **逐分量并集**（min lo / max hi，序无关）；plan 未钉，取混合
  分布的诚实面。sampleCount = round(Σ w·N)。
- 直方图取整 = sorted-order 浮点和 + `.rounded()`（schoolbook 半远离零）；
  2.5→3 / 22.5→23 专测钉死。

## 3. 65³ bake（T3）——实测带与预算裁决

| 面 | 实测 | 门 |
|---|---|---|
| 体素门 vs 理想连续模型（LCG 常量种子 4096 体素） | worst **7.6e-8** | ≤1e-5 |
| 恒等 bake 带（支撑内 vs 坐标） | **0.0233** | ≤0.03（机制带） |
| bake 耗时（Debug 套件 probe，best-of-3） | **295ms** | （生产预算 50ms） |
| 隔离 -O 算术探针（同 concurrentPerform+pow 形，65³ 全载） | **~1-3ms** | — |

- **体素门未触发收窄钉门**：实测带（Float32 存储 epsilon 量级）离计划门两个
  数量级，钉 7.6e-8 无信息量——门保持 1e-5，实测带记录在案。
- **恒等带机制注记**：阶梯截断每通道读「bin 的下格点值」（一步低），三通道经
  Oklab⁻¹ 非线性回传放大到 ~2e-2——恒等解的 bake ≠ 恒等映射（截尾平台外的
  体素更是按政策走平台）。恒等面 = idealModel 公式严格相等（1e-6）+ 带内
  （0.03）双层断言。
- **bake 预算裁决**：Debug 套件 295ms 是 -Onone 主导（裸 -O 探针同形算术
  ~1-3ms），生产 50ms 预算判定可达；**Release 测试产物缺 WebP 框架嵌入**
  （`build-for-testing -configuration Release` 的 Team ID 签名怪癖 + 包产品缺
  嵌——非本批引入，未追）致生产精确数暂缺，挂 GUI 走查顺路实测。**拖拽降级
  杠杆（拖拽中沿用上次 bake + 松手重 bake）备而未启**；预算探针 =
  `LIGHTAMER_PERF_PROBE=1` 观察记录非门（M2-5 惯例）。

## 4. .cube 资产（T4）——钉死形

- 文件名 = `<solutionHex16>-<alphaBitsHex8>.cube`——**同解前缀清理键**；
  assetRef = `<图名>.lra.colormatch/<fileName>`（图相对）。
- 序列化 = Swift `String(Float)` 最短往返（m5 回注：locale 不变专测断言无逗号
  形态）；读回 = colormatch 自有 parser（CubeLutParser 零触碰维持），
  write→read **元素级 Float32 位精确**（nasty 值集：±0/指数/denormal 邻域）。
- params 载体 = **additive omit-nil**（M3-1-01 inputEncoding 先例）——默认
  编码与 P1 档 blob 重编码逐字节不变（paramsHash 零漂移契约 + sidecar 漂移检
  测不误伤）；P1 三 optional 的显式 null 惯例仅在册键集上维持。

## 5. LUT 臂（T5）——三臂状态机与共享 kernel

- commit/process 按 **Arm{identity, linear, lut}** 分派；LUT 臂 = 模块自有
  PSO 引共享 `lut3d_tetrahedral` 函数 + rgba32Float texture3D + **恒等
  uniform 盒**（`ColormatchLutUniforms` = MSL `Lut3dUniforms` 字段级镜像，
  fwd/inv 恒等 + [0,1] 域——bake 产物即工作空间映射，kernel 零 diff 硬门
  亲证 0 行）。
- α-into-bake 双路：**会话曲线路**（resolver.cdfSolution → bakeKey LRU 16，
  每 α 一 bake、重访命中）与**恢复路**（资产 verbatim，零 bake）——
  `bakeCountForTesting` 钉两路面行为。
- E5 提取 tap = 模块内**一次性 armed 捕获**（fence + 全面 readback + ≤512²
  固定序 stride 采样 + Oklab + P1 extract）；入点 tap 即旁路构造（solve-twice
  稳定性的结构面）。
- **shared resolver forward**（`ColormatchResolverBox` +
  `ColormatchSharedResolverForward`，LutLibraryStore.sharedResolver 同形）：
  registry 工厂捕获 forward，调用时读盒——会话 resolver 换装不弃已建 box。
- prewarm 补 `colormatch_linear`（P1 DECISIONS §8 移交兑现；tetrahedral 已在
  列，PSO 缓存去重）。

## 6. 服务与面板（T6+T7）——E5/E6 落地与申报

- **E6 提取面**：`extractStats(document:bucket:)` = `ColorMatchDocument` 值面
  （DecodedImage + instances + layerStack + imageID）→ materialize boxes →
  **throwaway PipeCache** 渲染（HERMETIC，不碰活缓存）→ armed box tap 消费。
  无 colormatch 实例时注入恒等 armed box（首解面）；有则 arm 真实 box 的输入
  平面（重解面）——两解同平面（E5）。**源桶钉 512**（solve-twice 分辨率半
  边）；参考桶 = THUMBNAIL pristine（instances=[] 的同一 API，OQ-7；edited-
  reference 挂 V2 注记维持）。
- **attach = store 级投影缝**：`projectColormatch`（(opName, multiPriority)
  upsert，identity/iopOrder 保持——apply_params projectInstances 同缝语义）
  + live 腿 recordChange / addModuleToBaseChain 恰一 commit；幂等投影零新
  history item（solve-twice 测试钉死）。MCP match_color（M5-1-03）复用同缝。
- **T6+T7 合并提交申报**：参考列表 UI 与编排服务共享全部文件，拆分即人为
  （全局 §2.1 相关变更合并）；commit message 双 TRACK 并记。
- **EditorAdjustmentStackView 行撤销申报**（plan files_modified 该行预授权）：
  面板挂载走 provider 注册（InspectorState）+ 路由表行，该文件零改动。
- **面板新增两行非 plan 面**（机制必需，申报）：①路由表 `.lut` 页 colormatch
  行（v50 家族位邻 lut3d；EditorStackRoutingTests 钉数 41→42 + TAB-MATRIX 补
  行——m3 断言域的强制同步面）；②InspectorView localizedLabel colormatch
  case（P1 DECISIONS §5 承诺的 zh 名随面板入册）。
- **D-H1 测试时间线发现**（机制注记非缺陷）：压缩测试时间线下，前一 tick 的
  render Task 续体可在 commit 的 upsert 之后重建 instances（读 pre-commit
  history）——生产滑杆事件间距不重叠；测试以显式 `historyDidChange()` 排干
  后断言。模型读链因此走 coordinator 的活记录查找（`instanceRecord`），杜绝
  面板缓存陈旧 record 把已解 assetRef 族拖回旧值（真实缺陷，已修）。
- **M4-1 挂账 #6 第三度发作**（App 轮晚到 debounce 再生
  `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`）：删孤儿净树复跑
  724/4/0 ✓——修复批催办维持。
- xcstrings **20 键**（plan 预期 +14..18；实为面板 10 + 读数 4 + 错误 3 +
  module/history 2 + 空态 1——尾块纯插入 340 行，zh-audit 绿）。

## 7. 批量账目

- 新测试 6 文件 **47 法**（CDFSolver 8 / Pooling 6 / BakeGolden 6+1probe /
  CubeAsset 8 / Module +5 / Identity +1 / Service 7 / Panel 6）；BUNDLE-MAP
  增行 8。
- 定向轮终值（全绿零 MEMFAIL；App 首轮 1 fail = M4-1 #6 孤儿，删后净轮）：
  **Layers 466/4/0（1154MB）/ IOPParity 444/3/0（7006MB）/ App 724/4/0
  （2832MB）/ IOP 563/1/0（7884MB < 8G 门）**。
- 全套 `--all` 未跑（批准制；推算基线 = 3335 + M4-3 增量 + P1 38 + 本批 47，
  待 M5-1-03 收口统一申请）。

## 8. 红线自证（`git diff e4acb70..HEAD` 亲证）

- [x] `LightamerIOP/Sources/Lut3d/` **0 行**（tetrahedral 共享零触碰）
- [x] `LightamerCore/Sources/Pipe/Film/` 0 行（Film 域零触碰）
- [x] `LutEncodingCatalog` 0 行；Sidecar/History/PipeCacheKey/PipelineDocument/
      Graph 0 行（sidecar 零 schema + history 零触碰）
- [x] `.metal` 本批 **0 行 diff、0 新文件**（申报面 = 实际面）
- [x] 零新 SPM（Project.swift diff 仅测试编列 8 行）
- [x] `runModal` 机检 0 命中（App/Sources）；`String.LocalizationValue("prefix_…")`
      禁形 0 命中
- [x] zh-audit `--check` PASS（1637 source / 1875 catalog，+20 键全 zh）
- [x] paramsData <8KB 上界断言绿（LUT 字节不进 sidecar 机检面）

## 9. 移交 M5-1-03

- `match_color` MCP：直接消费 `ColorMatchService`（extractStats/solveAndAttach/
  projectColormatch 全部就位）；headless 批量目标走同缝 + SessionBatchApplier
  写盘腿（本批未做——GUI 面板无此需求）。
- G4 MCP e2e + 五门收口复验 + 全套 `--all` 申请。
- GUI 走查实测（`.work/gui-acceptance/m5-1/MANIFEST.md` 九行）+ bake 生产耗时
  顺路实测（§3 遗留）。

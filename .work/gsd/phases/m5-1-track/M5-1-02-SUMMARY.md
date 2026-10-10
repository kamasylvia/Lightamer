# M5-1-02 SUMMARY — TRACK P2：S2 CDF + LUT 臂 + 多参考池化 + 面板交互

> 执行 2026-10-11（夜间全自动授权）；基线 M5-1-01 验收后 HEAD `e4acb70`；
> 7 commits `14d032d..4cc1c52`；不 push。规格正本 = RESEARCH-NOTES §3.2/3.3/
> 3.4/3.5/§4 + PLAN M5-1-02（checker 回注 E5/E6/m5 全部落地）；实测带与钉死
> 值正本 = 同目录 `M5-1-02-DECISIONS.md`。

## 任务序与 commit

| 任务 | 内容 | commit | 状态 |
|---|---|---|---|
| T1 | `ColorMatchCDFSolver.swift`（三通道 256-entry Float64 阶梯；整数交叉相乘分位对齐；支撑 bin 直方图重推导 + 截尾平台；`.cdf` solver case + cacheTag）+ Tests 8 法 | `14d032d` | ✅ 8/0/0 |
| T2 | `ColorMatchPooling.swift`（二阶矩混合 + 序规范化 + 直方图取整回整数）+ Tests 6 法 | `d04b0ab` | ✅ 6/0/0 |
| T3 | `ColorMatchBake.swift`（65³ Float64 → Float32 存储；α 折入 bake；bakeKey = fnv(solutionHash⊕α)；concurrentPerform 固定索引归并）+ Tests 6 法+1probe | `69748bd` | ✅ 6/0/1probe |
| T4 | `ColormatchCubeAsset.swift`（.lra.colormatch/ 位 + 最短往返序列化 + 自有 reader + 全验证 degrade 值形态 + L009 原子晋升 + 同解前缀清理）+ Params additive omit-nil 载体 + Tests 8 法 | `e73e188` | ✅ 8/0/0 |
| T5 | ColormatchModule 三臂状态机（LUT 臂 = 共享 lut3d_tetrahedral + 恒等 uniform 盒 + bake LRU 16 + resolver forward + E5 armed tap）+ prewarm + Tests +6 | `b59623d` | ✅ IOPParity 444/3/0 |
| T6+T7 | ColorMatchService（E6 管线级提取 + 池化求解 + 资产 commit + store 级投影缝 attach）+ PanelModel/View（三级读 + D-H1 + solver picker + 参考列表权重滑杆 + readout）+ 路由表/提供者/xcstrings 20 键 + Tests 13 法 | `6bdcd18` | ✅ App 全绿 |
| T8 | G1 全链真解位精确断言 + G3 走查配方（gui-acceptance/m5-1/MANIFEST.md，证据域留盘） | `4cc1c52` | ✅ |
| T9 | 收口（本文 + DECISIONS + GOAL-STATE + 红线自证） | 本 commit | ✅ |

## 定向轮终值（全绿零 MEMFAIL；App 首轮 1 fail = M4-1 #6 孤儿再生，删后净轮）

```
BUNDLE|Layers   |466/4/0|peakRSS=1154MB|164s   （438 + 本批 28）
BUNDLE|IOPParity|444/3/0|peakRSS=7006MB|555s   （438 + 本批 6）
BUNDLE|App      |724/4/0|peakRSS=2832MB|370s   （711 + 本批 13）
BUNDLE|IOP      |563/1/0|peakRSS=7884MB|160s   （零新增，Registry 触碰面回归绿）
```

本批新增 **47 测试法**（6 文件 + 2 既有文件扩展）。全套 `--all` 未跑（批准制；
推算 = 3335 + M4-3 增量 + P1 38 + 本批 47，待 M5-1-03 收口统一申请）。

## 五门状态（OQ-8 分账）

- **G1 求解确定性 ✅（扩展）**：solve-twice 逐字节 params（源平面 = colormatch
  实例输入平面，重解无反馈回路——checker E5）；全链真解位精确（solve→bake→
  serialize→write→load 元素级 bit-pattern）；池化同集异序同字节；双 bake
  BIT-IDENTICAL；bake LRU 命中值不可见。
- **G2 kernel parity ✅（扩展）**：零新采样 kernel（Lut3d/ 密封面 0 行 diff
  硬门亲证）+ 链路断言（colormatch LUT 臂 GPU 输出 == 共享 tetrahedral CPU
  双写 ≤1e-5）。
- **G3 语义 golden ◐**：合成对恢复 = P1 面（S1/S3）+ S2 恒等曲线带（T1）+
  恒等 bake 公式严格面（T3）；**自然样张目测 = 走查配方已落**
  （`.work/gui-acceptance/m5-1/MANIFEST.md` Manual-Only 九行，验收轮实测）。
- **G4 = M5-1-03**（未启）。
- **G5 恒等回归 ✅（扩展）**：S2 两恒等态（assetRef nil / 资产 degrade）逐字节
  直通 + LUT 臂反空转（真表实动像素）。

## TRACK 兑现

- TRACK-01（S2 半）：per-channel CDF 求解器在册，面板三档可选（默认恒 S1）。
- TRACK-02：多参考统计级加权池化（μ/Σ 二阶矩 + 直方图定权重整合 + 权重滑杆
  UI + N=1 退化 + 序规范化确定性）。
- TRACK-03：colormatch iop LUT 臂 + `.cube` 派生资产载体（params 存
  {assetRef, assetHash}，typed degrade + 重解闭合）。
- TRACK-04：面板参考选取（PanelPresentation 缝）/自动求解/强度 D-H1/before-
  after 既有三形态继承（9-4 面对任意实例生效，零新代码）/readout 全落。
- TRACK-05：G 门扩展（上表）。

## 红线自证清单（`git diff e4acb70..HEAD` 亲证）

- [x] 零新 SPM 依赖（Project.swift diff 仅测试编列 8 行）
- [x] `Lut3d/` 密封面（Lut3dModule/CubeLutParser/LutLibraryStore/
      Lut3dKernels.metal）**0 行 diff**——LUT 臂只复用 kernel 函数
- [x] `.metal` 本批 0 行 diff、0 新文件；Film 域/LutEncodingCatalog/Sidecar/
      History/PipeCacheKey/PipelineDocument/Graph 0 行
- [x] sidecar 零 schema；HistoryStack/HistoryHash 零触碰；params 走
      paramsData 既有通道（零新 history 键族）
- [x] paramsData <8KB 上界断言绿（65³ LUT 字节不进 sidecar）
- [x] `runModal` 机检 0 命中；参考文件面板走 PanelPresentation.begin 缝
- [x] zh-audit `--check` PASS（1637 source / 1875 catalog；xcstrings 尾块纯
      插入 340 行 / +20 键全 zh）
- [x] V50Order/GradeCatalog/Registry seed 面 add-only（P1 已落，本批零改动）

## 交付面边界（P3 衔接）

本批交付 = S2 全链（求解→bake→资产→LUT 臂渲染）+ 池化 + 面板/交互全兑现 +
管线级提取 API。**未交付**（M5-1-03）：`match_color` MCP 工具（G4 + 五门收口
复验）、headless 批量目标的盘写腿（SessionBatchApplier 缝在 MCP 侧接）、全套
`--all` 申请、GUI 走查实测 + bake 生产耗时顺路实测（DECISIONS §3/§9）。

## 已知风险与移交注记

- S2 色相漂移（通道独立 CDF 已知弱点）：面板披露 + strength 缓解 + 默认档恒
  S1——走查行 9 目测确认。
- bake 生产耗时的 Release 精确数暂缺（Release 测试产物 WebP 嵌入怪癖，
  DECISIONS §3）；-O 算术探针 ~1-3ms 支撑 50ms 预算可达判定；拖拽降级杠杆
  备而未启。
- 编辑态参考图不进统计（pristine 裁定）——走查反馈若暴露真实需求挂 V2。
- D-H1 压缩时间线的 render 续体重建窗口（DECISIONS §6 机制注记）——生产事件
  间距不重叠；coordinator 渲染串行化仍是 M4 架构余量。

# 06-06 DECISIONS — liquify (IOP-GEO-05, base 链槽位 18.0)

> 执行期决策（Plan 06-06，2026-09-23/24 夜间 subagent）。dt 正本 = `src/iop/liquify.c` +
> `data/kernels/liquify.cl`（tree dc58cf0ba1）。红线：L020（坐标系前提）/L021（dscIn 平面像素）/
> L023（半边契约钉全往返）/L017（合成参考替代 dt-cli）。

## D-06-06-T1-1 路径坐标 = 归一化存储（dt 存像素 + 每 run 乘 scale 的分歧）
- **裁决**：`LiquifyPathData` 全部几何（point/strength/radius/ctrl1/ctrl2）以**模块入口帧的归一化分数**入 sidecar；场构建期按 `frame`（run 的 dscIn / mapper 传播尺寸）解到平面像素。
- **理由**：① 分辨率无关——PREVIEW/FULL run 共用同一 params，`iscale` 重标定链整体消失；② 与蒙版点模型（D-06-CONTEXT-7 全解码帧归一化）同构；③ overlay 直接以归一化 ↔ 视口映射。dt 存 raw 像素并在 `_build_global_distortion_map` 逐次乘 pipe scale——等价信息，不同参数化。
- **半径语义**：`radiusScalar = |radius − point|` 解析到 `max(frame.w, frame.h)`（圆在非方帧下保持为圆）。强度向量按 x/y 分量各自乘帧（方向保形）。
- Reversibility: reversible（存储换像素+迁移器即可），v1 不需要。

## D-06-06-T1-2 params 只保几何 + 语义字段（dt GUI 态不入盘）
- dt `dt_liquify_path_data_t` 的 `selected`/`hovered`（纯 GUI 态）与 `prev`/`idx`/`next`（数组链）不入 Lightamer params——选中态属 UI session，链由数组顺序推导（MOVE 起链，LINE/CURVE 续链，lone MOVE = 单 stamp）。status 保留（builder 消费 INTERPOLATED 位）。dt 把 GUI 态泄进 params 是它的实现巧合，非语义。
- Reversibility: reversible。

## D-06-06-T1-3 场 extent 裁到 run 区域（dt 的 region union 可越界的收紧）
- dt `_get_map_extent` 的 region union 允许网格越过 roi_out；Lightamer 把 stamp 并集**裁进 bounds**（模块 = roiOut，mapper = 全帧）。输出像素只读自身 roi 内的 cell，越界 cell 永不被读；mapper 的双线性采样对界外取零。防病态大半径把网格撑到帧+半径的量级。
- Reversibility: reversible（放开即去掉 clamp）。

## D-06-06-T1-4 lookup 表的 dt 右锚定 quirk 逐字保留
- dt `build_lookup_table`（liquify.c:858-861）的重参数化插值**锚在右样本**（`y[cptr] + frac·(y[cptr] − y[cptr−1])`）——分段内外推而非左锚插值，剖面在段内有轻微过冲。这是 dt 的实现 quirk（不是文档公式）。**实现与 float64 参考同式复刻**（fidelity 规则）——T1 解析门（<1e-6）据此才可能全绿；若"修成"左锚插值则与 dt 行为分歧。
- 附带防护：平 x 段（dx1 ≤ 0）dt 除零，Lightamer 取段末 y（唯一数值防护性偏离，D-06-06-T1-4a）。

## D-06-06-T1-5 零半径弧长环 break（dt 会死循环）
- `interpolate_paths` 的 `arc += |radius|·0.1` 步进在 radius == 0（`init_warp` 的默认态！）时步长为零——dt 该路径会死循环（GUI 实际总给半径手柄赋值所以未暴露）。Lightamer 步长 ≤ 0 即 break。测试 `testCurvePathInterpolation` 钉住。

## D-06-06-T2-1 空路径 = blit 恒等 + seed ENABLED 中性
- 空路径是液化的常态（RESEARCH Risk 9）：模块 blit 直通（逐字节恒等，常驻回归），seed 携 enabled 空实例（exposure-0EV 式缓存中性），面板/overlay 有实例可驱动。

## D-06-06-T2-2 tiling：halo 声明 + 摊销工作集（dt 不允许 tiling 的保守性收窄）
- dt flags 只有 SUPPORTS_BLENDING（不允许 tiling）。Lightamer：`tileHalo` = 位移上界（0.5·|strength−point| 的帧向最大值）+ 核半宽 + 1；`tileWorkingSetBytesPerPixel` = 场网格字节摊销到平面（典型小场 < 预算 → 不分块，行为同 dt；全帧大场 100MP FULL 合理进 tile 驱动）。强制分块 == 整幅 <1e-6（实测 0.0）由 T5 测试承重。
- Reversibility: reversible（工作集归 0 即回到 dt 行为）。

## D-06-06-T2-3 重采样核 = 每实例参数（dt 取全局 userpref）
- dt 的核族来自 interpolation userpref；Lightamer 钉在 `Params.interpolation`（默认 lanczos3，kdesc resolution 100 同 dt）。侧car 可逐实例选择 bilinear/bicubic/lanczos2/lanczos3。
- kmix 的 `k[i+1]` 对索引钳到表尾（t == size 的可达边界：fx == 0 且最外 tap）；dt 该处 OOB 读其分配尾页——latent bug 不复刻。

## D-06-06-T3-1 roundtrip 门 0.5 px（宽于几何模块的 0.1 px 档）
- 几何段（crop/flip/ashift/lens）往返 ~1e-12 px（解析精确/牛顿收敛）；liquify 的 forward 腿是**定点迭代解**（q + F(q) = p，24 步护栏 + 1e-8 残差早停），inverse 腿精确（q + F(q)）。实测：单段 8.4e-11 px、五段链 2.5e-10 px——远优于 0.5 px 门。门宽的理由：位移场的逆采样精度档（计划原文），以及 GPU 侧蒙版栅格的 float32 双线性（端到端锚定实测 0.039 value 漂移，含 1px 采样量化）。
- **排序断言**：五段链 segments = [lens, ashift, flip, liquify, crop]（liquify 界于 flip 16 与 crop 24.5）。

## D-06-06-T3-2 蒙版栅格 GPU 腿的分段矩阵分解（staged decomposition）
- liquify 位序被 flip 与 crop 夹住 → 单投影矩阵无法承载其逆。`stagedInverseComposite` 把链拆成 post（liquify 之后的段，逆序最先行）→ liquify 网格腿 → pre（liquify 之前的投影段）→ lens 腿；mid 帧 = 首个 post 段的 inSize。无 liquify 链逐位回退到历史单矩阵（post = identity，pre = 全折叠）。`MaskRasterUniforms` 增 post0..2 + liq0/liq1（16B 块），analytic kernel 与 stamp fragment 共用 `mask_inverse_content` 新签名 + buffer 3/1 绑定。
- **已知继承缺口（未修，登记）**：蒙版平面缓存键（maskKey = imageID+pipeType+layerID+maskHash+roi）不含几何/液化状态——**06-03 起** ashift 旋转变化（同 roi）即可能命中陈旧蒙版平面，liquify 参数变化同理。修复属蒙版缓存键所有者（折叠 mapper 稳定哈希），建议 06-05/06-07 或验收轮处理；本 plan 不静默扩键。

## D-06-06-T4-1 面板/overlay 选择态不互同步（v1）
- 面板的节点选择（slider 编辑目标）与 overlay 的拖拽手柄各自独立；overlay 拖拽不改面板选中。合并选择态留 06-05（MaskToolbar 状态机）一并做。

## D-06-06-T4-2 overlay 坐标 v1 假设无上游改帧几何
- overlay 以 display texture 的 aspect-fit rect 直接映射归一化节点——上游 lens/ashift/flip/crop 启用时 overlay 与场坐标失准（常见人像液化路径 = 无上游几何时精确）。dt 用 distort 管线映射——Lightamer 待 overlay 接 GeometryPointMapper（记录于 SUMMARY 遗留）。
- Reversibility: reversible（overlay 换算处单点接入 mapper）。

## D-06-06-T4-3 overlay 手势互斥 = 选中面板键（v1 状态机）
- liquify overlay 挂载条件 = `inspectorState.selectedPanel == liquify 实例 id`；选中期间 crop overlay 卸载，切出即恢复。完整编辑模式状态机（mask/retouch/crop/liquify 多态）归 06-05。

## 测试数值总账（验收对照）
| 项 | 实测 | 门 |
|---|---|---|
| 三 warp 类型场解析（float64 独立参考） | 2.4e-7 / 1.2e-7 / 1.2e-7 | <1e-6 |
| warp kernel parity（vs float64 重采样，27,648 采样） | 0.0 | <1e-5 双键 |
| 空路径恒等 | RGBA 逐字节 | 逐字节 |
| 场缓存 | 1 次构建/参数变化才重建 | 精确 |
| 五段链 roundtrip | 2.5e-10 px | <0.5 px |
| 蒙版内容锚定端到端（真 GPU 栅格） | 0.039（45 内容点） | <0.05 |
| 强制分块 vs 整幅（4 tiles） | 0.0 | <1e-6 |
| 轨 B 空路径插链 | 逐字节 | 逐字节 |
| 全 suite | 747 / 3 skip / 0 fail（基线 723 +24；ToneEqualPerf 一轮 120.9 vs 120 门为负载 flake，隔离复跑 116.2 过） | 0 fail |

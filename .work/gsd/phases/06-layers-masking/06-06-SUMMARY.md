# 06-06 SUMMARY — liquify（IOP-GEO-05，base 链槽位 18.0）

**执行**：2026-09-23/24 夜间 ZCode subagent；5 commits（`366b2ea` T1 → `e1ffa48` T2 → `e550f10` T3 → `a211d52` T4 → closeout T5）。
**全套**：**747 / 3 skip / 0 fail**（基线 723 → +24；touch Tests + build-for-testing 重编复跑；其中一轮 ToneEqualPerf 120.9 vs 120 门为负载 flake，隔离复跑 116.2 过——GOAL-STATE 既有 perf flake 同族）。

## 交付面（对照 plan Tasks）

### T1 扭曲场构建（CPU）— `366b2ea`
- `LiquifyPathData`：`dt_liquify_path_data_t` 直译（MAX_NODES=100；三 warp 类型；`init_warp` 默认 control1 0.5/control2 0.75；lone MOVE = 单 stamp）。**归一化存储**（D-06-06-T1-1）——PREVIEW/FULL 分辨率无关，iscale 重标定链消失，与蒙版点模型同构。
- `LiquifyDistortionField`：`interpolate_paths` + `mix_warps`（角度连续混合）+ 三次 bezier（多项式基）+ 弧长重参数化（restart cookie）+ `build_lookup_table`（**dt 右锚定 quirk 逐字**，D-06-06-T1-4）+ `apply_round_stamp` 四象限沉积坍缩式（逐项核对 liquify.c:978-1013）。零半径弧长环 break 防死循环（dt 会挂，D-06-06-T1-5）。
- `DisplacementField`（Core/Pipe，D-03 分层必需）：逐像素位移网格 + 双线性采样 + maxMagnitude；语义 = 后向采样图 `out(q) = in(q + F(q))`（L020 同域前提钉死：网格坐标 == kernel 采样坐标）。
- 解析参考：三 warp 类型各一 case vs 独立 float64 复刻——**2.4e-7 / 1.2e-7 / 1.2e-7**（门 1e-6，14,641 cell/型，compared>0）。

### T2 warp kernel + 模块 + 注册 — `e1ffa48`
- `liquify_warp`（LiquifyKernels.metal）：`warp_kernel`（liquify.cl:73-131）直译——逐像素位移查表（cell = 帧像素 − extent 原点）+ kmix 表驱动 lanczos3/bicubic/bilinear 离散卷积（taps 1−a…a 归一化）；零位移像素逐字节直通（dt copy 腿）；CL→MSL 像素中心 +0.5 / clamp_to_edge 对齐 sampleri；kmix i+1 越界钳位（dt 尾页 OOB 读不复刻）。
- `LiquifyModule`（18.0，RGB，SUPPORTS_BLENDING = liquify.c:313；DISTORT|GEOMETRY tags 记录于头注）：空路径 blit 恒等（常驻逐字节回归）；`modifyROIIn` = stamp extent ∪ roi + 插值 margin（a 低/a+1 高）钳 bufIn（dt :1213-1285，L020/L021 无 ×scale）；tileHalo = 位移上界 + taps；摊销网格字节为 tile 工作集（D-06-06-T2-2）；kernelTable = dt :1470-1497（resolution 100）；**场缓存**按 (paramsHash, plane, roiOut)，`fieldBuildCount` 探针。
- Registry：注册 + prewarm + seed ENABLED 中性（空路径，exposure-0EV 式）。
- parity：**0.0**（27,648 采样，双键门 1e-5，280 px 真位移防空转）；V50 槽位邻域 17<18<19<20<21 断言。

### T3 GeometryPointMapper liquify 项 — `e550f10`
- `.liquify(DisplacementField)` 段：inverse = q + F(q)（精确，采样图）；forward = 定点迭代解（lens `.radial` 对偶）。空路径 = 无段（6-3 预留兑现）。
- `stagedInverseComposite`：post（crop⁻¹）→ 网格腿 → pre（flip/ashift⁻¹）→ lens——liquify 位序夹在 flip/crop 之间，单矩阵不可承载；无 liquify 链逐位回退历史单矩阵。
- 蒙版栅格 GPU 腿：`MaskRasterUniforms` +5×16B 块；`mask_inverse_content` 分段化 + 双线性网格腿；analytic kernel（buffer 3）与 stamp fragment（buffer 1）共绑。
- roundtrip：单段 **8.4e-11 px**、五段链 **2.5e-10 px**（门 0.5 px，D-06-06-T3-1）；分段分解 vs 段走 1e-9；**蒙版内容锚定端到端**（真 GPU 栅格）：45 窗内内容点 maxDrift **0.039**（门 0.05）+ maxPlaneDiff 0.42（防空转）。教训钉进测试：场小于蒙版梯度带时锚定测试退化为常量区（maxPlaneDiff 守卫 + 注释）。

### T4 overlay 交互 + 面板 — `a211d52`
- `LiquifyOverlayHost`：锚点/强度/半径手柄 + 子路径折线渲染（Canvas）；16pt 命中；拖拽 = D-H1 三件套；空画布点按加首节点。归一化 ↔ aspect-fit 映射（v1 无上游改帧假设，D-06-06-T4-2）。
- `LiquifyPanelView`：节点 Picker（MAX_NODES=100 上界 UI 态：禁用添加 + cap 文案）、warp 类型 Picker、强度/半径滑块（连续三件套）、删除/添加（离散一 commit）。
- 互斥路由：液化面板选中 → viewport 归液化 overlay，crop overlay 卸载（D-06-06-T4-3）。
- `module_liquify` 行 label + 16 条 zh/en catalog；PanelWiring +2。
- **GUI 复验（真机解锁屏，4 张截图 + FINDINGS 06-06 节）**：面板选中/互斥/加节点/强度手柄 cliclick 拖拽（滑块实时 0.00→10.11、viewpoint 径向放大实时预览）/⌘Z 恰一 commit 撤销回 0.00。当场修两处本地化接线（node_n 键补 %lld；滑块 label 需预本地化 String）。

### T5 golden + 回归 — closeout（本 commit）
- 强制分块 vs 整幅（4 tiles，halo 7）：**0.0**（门 1e-6）；轨 B 空路径插链：**逐字节零增量**。
- 全 suite 终轮 **747 / 3 skip / 0 fail**（touch + build-for-testing 重编复跑）。

## 验收标准对照（plan Verification 表）
| 对象 | 判据 | 结果 |
|---|---|---|
| 位移场解析 | <1e-6 | 2.4e-7 ✓ |
| warp parity | 三类型 <1e-5 + 空路径逐字节 | 0.0 + 逐字节 ✓ |
| 映射器 roundtrip + 内容锚定 | <0.5 px + 端到端 | 2.5e-10 px + 0.039 ✓ |
| 交互 overlay + Manual-Only | 走查 + 登记 | FINDINGS 06-06 ✓ |
| 强制分块 vs 整幅 + 轨 B 零增量 | <1e-6 + 逐字节 | 0.0 + 逐字节 ✓ |
| 全 suite 绿 + 独立提交 + SUMMARY/DECISIONS | 0 fail | 747/0 + 5 commits ✓ |

## 遗留 / 风险（非阻塞）
1. **蒙版平面缓存键不含几何态**（06-03 继承缺口，D-06-06-T3-2）：ashift/liquify 参数变化（同 roi）可能命中陈旧蒙版平面——建议 06-05/06-07 或验收轮折叠 mapper 稳定哈希入 maskKey。
2. **overlay 坐标 v1 假设**（D-06-06-T4-2）：上游 lens/ashift/flip/crop 启用时 overlay 失准——接入 GeometryPointMapper 单点改造，06-05 一并做。
3. **面板/overlay 选择态不互同步**（D-06-06-T4-1）——归 06-05 编辑模式状态机。
4. Manual-Only 三行（拖拽手感细粒度/100MP 预览延迟/crop 切换残留）见 FINDINGS——待人工复验项，不阻塞。
5. toneequal tile halo 声明下 liquify tile 工作集摊销公式未做 100MP 实测账（典型场远小于预算；全帧大场行为由 T5 强制分块测试承重）。

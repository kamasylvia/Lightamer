# Plan 05-08 — Decisions

> bilateral（IOP-DENOISE-03）实现决策 + OQ7 定稿 + IOP-DENOISE-04 defer 决议 +
> SC#4 拖动门判定 + Open#9 启用判定。执行期记录，签核（T6）后随 VALIDATION 归档。

---

## D-05-08-T1-1: `_compute_sigmas` 逐行核对照表（bilateral.cc:320-327）

dt 原文（tree dc58cf0ba1）与 Swift 实现逐字段对照。**Med confidence 在此钉死。**

| dt（bilateral.cc） | 语义 | Lightamer Swift |
|---|---|---|
| `sigma[0] = data->sigma[0] * scale / iscale`（:321） | σx = radius × scale ÷ iscale | `BilateralModule.spatialSigma(radius:roiScale:iscale:) = radius * roiScale / iscale` |
| `sigma[1] = data->sigma[1] * scale / iscale`（:322） | σy 同 σx（commit_params :352-353 令 sigma[0]==sigma[1]==radius） | 同上（单 σs——两维同值，直连核空间权也只用 σx，:190 单 σ 形） |
| `sigma[2] = data->sigma[2]`（:323） | σr = red（**不折算**） | `params.red` 直传 |
| `sigma[3] = data->sigma[3]`（:324） | σg = green（不折算） | `params.green` 直传 |
| `sigma[4] = data->sigma[4]`（:325） | σb = blue（不折算） | `params.blue` 直传 |
| 调用点 `:258`：`_compute_sigmas(sigma, data, roi_in->scale, piece->iscale)` | scale=roi.scale、iscale=piece.iscale，**run-level 常量**（tile 驱动不改写） | process/tileHalo 同源：`roiIn.scale ÷ piece.iscale`；**L021 合规**——标量补偿式，dscIn 禁再 ×scale |

- dt 的 nlmeans/denoiseprofile 用 `fmin(roi.scale,2)/fmax(piece.iscale,1)` clamp 族——bilateral **没有** clamp（裸乘除），实现照裸式，钉参测试 `testComputeSigmasLineByLine` 固定（scale 2/iscale 0.5 → σs 60 无 clamp）。
- σ 折算仅影响 spatial 维；prad/rad 推导（:265-266）与 tiling overlap（:370）全部消费折算后 σs。

## D-05-08-T1-2: thumbnail 跳档语义 = pipeType 驱动

dt :268-271：`rad < 1 || (rad <= 6 && dt_pipe_is_thumb)` → identity copy——**直连档在 thumbnail 上整体跳过**（CPU naive 慢），grid 档 thumbnail 照跑。Lightamer 按 `piece.pipeType == .thumbnail` 判定（`BilateralModule.leg`），语义与 dt 一致；预览/FULL 不受影响。路径决策纯函数测试钉住（`testLegPathSwitching`：rad 5/6 直连、rad 7/8 grid、σ<0.1 恒等、rad 收缩、thumbnail 跳直连）。

## D-05-08-T1-3: seed DISABLED（plan 原文中性 seed 前件不成立）

plan T1 原文「seed（σ→0 恒等 → 中性 seed enabled）」的**前件不成立**：params radius $MIN 1.0（dt bilateral.cc:55），σ→0 不可达——radius 1.0 仍给 rad=4 窗口平滑，**无零参恒等**。按 colorbalancergb D1 / nlmeans D-05-06-T2-1 处置：seed DISABLED，identity 只经 disabled piece 成立。另注：dt 侧 bilateral.cc 无 `default_enabled` 覆写（dt 默认启用）——我们的 seed 纪律优先，差异在此记录。

## D-05-08-T2-1: OQ7 定稿——5D grid 内存预算（plan 期决策 T）

**grid_bytes 公式**（`BilateralModule.gridPlan`）：

```
cells_spatial = clamp(⌈ext/σs_eff⌉ + 1, 4, 3000)     # ext = 平面 W/H（dt 3D grid dim-clamp 同款）
cells_range   = max(⌈1/σc⌉ + 1, 4)                    # 值域 [0,1] clamp（bilateral.cl image_to_grid 语义）
grid_bytes    = Πᵢ cellsᵢ × 16B                       # payload float4 = (w·r, w·g, w·b, w)
```

- 有效 σ 由 clamp 后 dims 反推（dt src/common/bilateral.c:47-89 `dt_bilateral_grid_size` 的 5 维推广）：σs_eff = max(W/cx, H/cy)、σc_eff = 1/(cells−1)——kernel 端 p/σc ∈ [0, cells−1] 映射自洽。
- **预算** = 1.5GB（`gridMemoryBudgetBytes`；FULL tile working 预算族半值）。超预算 → σ 等比放粗 c = (bytes/budget)^(1/5)·1.05 重算（dt dim-clamp/re-derive 语义的预算泛化），≤8 轮必收敛（dims 下限 4⁵ = 1024 格 = 16KB ≪ budget）。

**100MP 大半径上界表**（`testOQ7BudgetFormulaAndBounds` 固定）：

| 场景 | σs / σr =σg=σb | cells (x,y,r,g,b) | bytes | 放粗 |
|---|---|---|---|---|
| 测试平面 512² | 6 / 0.1 | 88,88,11,11,11 | 156 MB 级 | 1.0（未放粗） |
| PREVIEW 2560² grid 档 | 2 / 0.05 | ~1335²,21,21,21 | < budget | 1.0 |
| **FULL 100MP（11640²）dt 默认** | 15 / 0.005 | 87²,23³ | **1.47 GB** | **×9.23**（σ 等比放粗） |
| 极限预算 16KB | 15 / 0.005 | 触底 | ~16-40KB | 收敛（4⁵ 下限） |

**超预算回落策略二选一——选 ① TilingPlan 分块（dt maxbuf 对应物），拒绝 ② UI 参数软上限**：
- ① tileWorkingSetBytesPerPixel = 32 + plane 级协商 grid_bytes ÷ plane pixels（dt tiling_callback :359-368 `hash_bytes/(16·px)` 摊销同形）——FULL 大平面由 `executeTiledNegotiated` 自动分块，每 tile 本地网格（坐标平面锚定，见 T2-3），内存 = tile-proportional。
- ② UI 软上限拒绝理由：dt 无对应物（maxbuf/grid_size clamp 全是自动机制）；把内部网格预算泄漏成用户可见参数约束伤 UX；自动放粗已给出有界退化。
- 放粗（coarsening）作为终端兜底保留在 gridPlan 内：对 tile 化后仍超预算的参数做 σ 等比放粗，输出有界、语义退化可解释（等效更宽的 domain/spatial 核）。

**直连档** tileWorkingSet = 32 B/px（plan 钉值；factor 2.0 平面半账 + 窗权 buffer 摊销）；恒等/直 leg 不报 grid 摊销（leg-aware）。

## D-05-08-T2-2: grid 档算法 = dt lattice 同族近似——双参考结构 + spatial-only blur

执行期实测钉死的三个算法级决策（RESEARCH §5.8「grid 参考按 grid 逻辑复刻」路线的落实）：

1. **稠密 5D 网格替代 permutohedral lattice**。dt CPU 侧 5D 用 permutohedral 稀疏格（bilateral.cc:266-310，无 CL 腿）；Metal 上稠密网格 = 同族近似（splat pentalinear 32 角原子散射 → grid blur → slice val/w 归一），cell = 1σ 粒度与 lattice 一致。稀疏哈希 5D 在 Metal 上等价于重写 lattice——超出 v1 工程边界，不采用。
2. **range 维不做 grid blur（稠密格 adaptation）**。dt lattice 的全维 blur 是稀疏格的填充需求；稠密格上 range blur 会把值桶互相抹平（域有效 σ ×~1.4，暗 dip 实测 +0.5 绝对偏差）。改为仅 spatial x/y blur（bilateral.cl blur_line edge 形），域响应由 slice 五线性插值承载——暗 dip 恢复到与精确公式一致（delta 远场逐位回到平场）。
3. **双参考结构（对 plan 容差口径的修正）**。plan T2.3/T3 的「grid vs 直连公式 <1e-3」对 cell=σ 粒度的网格算法**不可达**（结构化内容 maxAbs ~0.02、dip 处 rel ~0.3；dt lattice 同族同理——dt 生产中从不与 naive 对比）。修正为：
   - **轨 A 正门 = 同算法 float64 参考**（gen_fixtures.py `bilateral_grid_reference`，与 GPU kernel 逐式对偶；nlmeans Goossens 参考同性质）——**<1e-3 容差档内实测 ~8e-7**；
   - 直连档 case 参考 = 精确窗口公式 float64（bilateral.cc:219-247）——**<1e-5 实测 ~8e-7**；
   - vs 精确公式的偏差保留为**近似包络测量**（crossing 测试 maxAbs <0.05 回归界 + 数字落本档），不是 parity 门。
   - L020 注：比较域 = 滤波支撑内区（rad 环除外）——dt 边界拷贝是直连档实现细节，grid 档全程 clamp 滤波，环上两算法不可比。

**平场锚**：平场 → 域权恒 → grid/直连两档输出 == 输入（<1e-6 实测 2.9e-7）；σ→0（σs<0.1）恒等逐字节（dt :259）。

## D-05-08-T2-3: 网格平面锚定 + 整数基 cell（分块==整幅的结构前提）

tile 执行与整幅执行落同一物理网格：网格坐标 = `(gid + roiIn.origin)/σ`（逐位同式浮点采样），tile 本地网格以**整数基 cell**（baseX = ⌊roiIn.x/σ_eff⌋）索引约简——禁用 `offset − base·σ` 的浮点折叠（实测引入 ~0.24 cell 相位差 → 分块/整幅 rel 0.19）。halo = rad ≥ 3σs+1 px ≥ 3 cell + 余量，覆盖 pentalinear ±1 cell 与 blur ±2 cell 的支撑。实测分块==整幅 **maxRel 4.5e-7**（4 tiles @ 1MB 预算）。

**执行期缺陷修复归档（防复发）**：
- blur_line 的混合进制线解码两处错：① 线基数误排除 axis 因子（真步长必须含全维）→ 修复为压缩位权解码 + 真步长基址；② dt CL 逐元素滚动的标量 tmp 被跨通道复用 → val/w 比被污染（平场 0.18→0.495）→ 修复为 float4/SIMD4 逐通道滚动。两错均为移植期引入（dt 原文正确），教训：**CL 标量核的 4 通道并行化必须逐 tmp 审计通道归属**。

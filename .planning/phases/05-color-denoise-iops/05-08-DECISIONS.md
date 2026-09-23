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

---

## D-05-08-T4-1: IOP-DENOISE-04 defer 决议（hotpixels / dark-frame / chromatic / cacorrect）

IOP-DENOISE-04 拆解决议（需求文字「hot-pixel/dark-frame/chromatic-noise reduction」四半边的最终落位；SC#3 措辞落差「NLMeans, bilateral/surface blur, and hot-pixel/dark-frame/chromatic-noise reduction all…」在 05-VALIDATION 以需求注记行澄清）：

| 半边 | 决议 | 证据 / 承载 |
|---|---|---|
| **chromatic noise** | **已交付**（非 defer） | 05-06 nlmeans `chroma` 参数（`NLMeansParityTests.testChromaZeroLumaOnlySmoothing` 等方向门）+ 05-07 denoiseprofile Y0U0V0 色度模式（`DenoiseProfileParityTests` 色度腿）——色度去噪由 denoise 双件原生承载。 |
| **hot pixels** | **正式 defer**（需求解释权裁决，非缺口） | 双重证据：① hotpixels.c:94 `IOP_CS_RAW`——Bayer 单通道域，管线入口（CIRAW 显影 linear Rec2020）不可达；② Spike A 实证 CIRAW 无 hot-pixel/despeckle 键（04 Phase 1 spike A 在案）。类比 04 对 IOP-DETAIL-01「高斯/拉普拉斯变体」的口径：需求文字覆盖不可达域时按域证据裁决。重启条件 = v2 自研 RAW 解码路径论证。 |
| **dark frame subtraction** | **正式 defer** | 需解码前传感器级访问（暗场帧标定数据 + raw 域逐像素扣除），CIRAW 不暴露暗场合成/原始帧访问——v1 无实现路径（hotpixels 同一 Bayer 域论证，rawdenoise.c:161/510/538 `dt_image_is_raw` 门同证）。 |
| **cacorrect 复议** | **维持 defer**（04-05 D-04-05-T0-0 结论复核成立） | 同一 Bayer 域论证（cacorrect 5.0 在 demosaic 前，单通道 RAW 域）；**与 Phase 6 无关**——Phase 6 是蒙版/图层域（LAYER/MASK 需求族），cacorrect 是 RAW 域问题，**不随 Phase 6 接收**；重启条件 = v2 自研 RAW 解码路径论证（与 hotpixels/dark-frame 同一门）。 |

**Phase 6 移交口径**：cacorrect/hotpixels/dark-frame 三件均为 RAW 域 defer 终局结论（本次签核定稿），Phase 6 计划无需再复议；rgbcurve/rgblevels（D-05-CONTEXT-1）另列（Phase 6+ stretch，非 defer）。

## D-05-08-T4-2: 面板交互口径（继承既定框架，无新决策）

BilateralPanelView = NLMeansPanelView 模式复用：LightamerSlider 三件套（拖动实时 → 松手恰 1 commit，D-H1）+ 离散复位 applyDiscrete；量程 = dt soft range（radius 1-30、σ 0.0001-0.1 @ 4 位小数——dt gui_init；硬上限 50/1.0 编程可达）；280pt 约束（滑块 only）；a11y id `inspector.slider.bilateral.{radius,red,green,blue}` + zh/en catalog 8 keys + InspectorView zh 显示名同轮落位（05-06 教训预防性）；`PanelWiringTests` +2（dispatch + 拖动恰 1 commit + 复位还原 pristine hash）。5D 网格预算不进 UI（D-05-08-T2-1）。

## D-05-08-T6-1: SC#4 Open#9 应急判定（denoise 链 60fps 未达的收口）

- **判定**：denoise 单件链（nlmeans 降载档）拖 strength 中位 85.7ms，未达 16.6ms 预算；预览降载三件套已兑现（57 趟 vs 满血 481 趟 = 7.5×）后仍不达 → Open#9 应急预案（管线级 Lab 往返共享）**判定启用条件成立**，但量化表明 Lab 往返共享对本缺口的贡献仅 ~5%（每模块省 2 趟，NLMeans 本征趟数为体）——**非正杠杆**。
- **收口**：正杠杆（更深预览降载 + dispatch 批合并）移交 Phase 6+/独立 perf plan；TODO 公开挂账（PERF-01 未勾与 PERF-5 清账注记同源）。
- **证据**：`.work/05/perf.md`（判定摘要）+ 05-08 验收独立复跑（color 4.8ms ✓ / denoise 85.7ms ✗）。

## D-05-08-T1-1 补充：bilateral.cc 行号引用勘误（2026-09-23 复验）

plan/文档所引 bilateral.cc 行号系统性漂移：_compute_sigmas 实际 :109（非 :320-327）、调用点 :158/:334（非 :258/:360）、commit_params :297（非 :352-353）、tiling_callback :326（非 :359-368）；:48/:52-58 正确。语义核对不受影响（以 pinned 树 dc58cf0ba1 实读为准）。

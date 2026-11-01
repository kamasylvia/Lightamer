# darktable tone equalizer 曝光方式调研

> 调研员：omp（纯文本零 commit 零构建）· 2026-11-01 · 全程中文
> 上游锚点：darktable `18cf557fbd`（`src/iop/toneequal.c` 3992 行，`data/kernels/toneequal.cl` 600 行）
> 我方锚点：`LightamerIOP/Sources/ToneEqual/`（CorrectionLUT.swift / ToneEqualModule.swift / ToneEqualKernels.metal）+ `LightamerIOP/Sources/Exposure/` + `App/.../Inspector/ToneEqualPanelView.swift`（308 行）+ `ExposurePanelView.swift`

**任务书事实勘误（先行）**：任务书称「我方 toneequal iop（M3-4 落地的宽容度面板）」——**不准确**。
M3-4 落地的是 **Film 面板**的宽容度（latitude）section（`FilmPanelModel.swift`：EV 轴直方图 + `ProfileLatitudeDescriptor` useful-EV 虚线 + below/inside/above shares），属 film 域，与 toneequal 无关。
我方 toneequal 是 Plan 03-05 落地的：9 EV 带 → RBF 逼近 → 80001 LUT → EIGF/guided 五档细节保留 → 曲线图面板。
结论不受影响（宽容度面板仍是"我方唯一的直方图+EV 轴 UI 范式"，见 G3 实现路径），但归属须正名。

---

## 1. dt toneeq 曝光机制深读

### 1.1 总览：三段式「估计 → 塑形 → 施加」

dt toneeq 的曝光调整不是"一个滑杆改一个增益"，而是三段流水线（`toneequal.c:20-85` 文档头自述：relighting the scene）：

```
输入 RGB → ① luminance mask（把 RGB 压成一幅"曝光图"）→ ② RBF 曲线（曝光→补偿量的连续映射）→ ③ apply（逐像素乘补偿）
```

三段各有一个独立的"曝光"概念，极易混淆，先立术语表：

| 术语 | 含义 | 单位/域 | dt 源码 |
|---|---|---|---|
| pixel exposure | 像素亮度的 log2（`log2(luminance)`） | EV，钳 [-8, 0] | `:869` |
| band gain | 用户 9 个带的期望补偿 | EV，±2 | params `:175-183` |
| RBF factors | 8 个高斯基的线性系数（伪逆解出） | 线性增益 | `:198-199` data |
| correction | 像素最终乘的补偿量 | 线性，钳 [0.25, 4] | `:911` / `:1897` |
| exposure_boost | mask 段的曝光平移（只动 mask，不直接动输出） | EV→exp2 线性乘 | `:2318` |
| contrast_boost | mask 段绕 fulcrum 的对比扩张 | EV→exp2 斜率 | `:2317` |

**核心洞察**：toneeq 有**两层曝光**——mask 层（exposure_boost/contrast_boost，只决定"每个像素落在曲线的哪个 x 位置"）与补偿层（9 带曲线，决定"每个 x 给多少补偿"）。用户拖动 9 带时改的是补偿层；auto 按钮改的是 mask 层。这是 dt toneeq 与"全局 EV 偏移"最本质的区别。

### 1.2 第一段：luminance mask（曝光估计）

**七估计器**（`src/common/luminance_mask.h:40-48`）：mean / lightness / value / norm1 / norm2（默认）/ power norm / geomean。dt 文档头自述（`:34-44`）：工作在 camera RGB → XYZ **之前**，算不出人眼 Y，只能用 RGB 范数近似"像素能量"；物理最准是欧氏范数，观感最好常是 power norm（无理论依据的黑魔法）。

**mask 塑形公式**（`:71-75`，逐估计器都是同一句）：

```
lum' = linear_contrast(exposure_boost × norm(RGB), fulcrum, contrast_boost)
linear_contrast(p, f, c) = max((p − f) × c + f, exp2(−16))
```

即：先线性乘（平移直方图），再绕 fulcrum `exp2(−4)`（`:135` CONTRAST_FULCRUM）做斜率变换（扩张/压缩直方图）。注意 fulcrum = −4EV 恰是 9 带中心（−8…0 的中点）——mask 塑形的目标就是**把图像曝光分布搬到 [−8, 0] 控制窗的中央**（`:969-975` 注释明说：guided 类滤波会把 mask 压平成均值 ±2EV，只剩 2–3 个带可用，必须先铺开）。

**五档细节保留**（`compute_luminance_mask :940-1014`）：

| 档 | contrast 是否生效 | 滤波 |
|---|---|---|
| NONE | 否（fulcrum=0, c=1） | 无——纯逐像素 = 退化为一条 1D tone curve（预设 `:503` "simple tone curve" 即此用法） |
| AVG_GUIDED / AVG_EIGF | 否 | 表面模糊，GEOMEAN 混合 |
| GUIDED / EIGF（默认 EIGF） | **是**（fulcrum=−4EV） | 表面模糊，LINEAR 混合 |

关键语义：contrast_boost **只在 GUIDED/EIGF 两档生效**（`show_guiding_controls :2370` 连 UI 可见性都按档开关）。AVG 档无此能力——这是"阈值面"形态差异的根源之一。

### 1.3 第二段：RBF 曲线（9 带 → 连续补偿函数）

**数学**（`:1855-1877` 注释 + `:2030-2043` + `:1880-1899`）：

1. 9 个用户带（−8…0 EV 整点，EV 域 ±2）→ `exp2` 转线性增益（`:1919-1931`，log2/exp2 flip-flop）；
2. 构造 9×8 插值矩阵（9 个整点 × 8 个高斯基，基中心 `centers_ops` 把 [−8,0] 七等分，σ = smoothing 默认 √2）；
3. 9 方程 8 未知数 → **法方程 + Cholesky 伪逆**（`pseudo_solve`，`iop/choleski.h`）→ 8 个 RBF 系数；
4. 系数 → LUT（80001 条 = 8EV × 10k/EV，`:1880`）、钳 [0.25, 4]（= ±2EV）。

**有意丢一个自由度**（`:1860-1863` 原文）："Losing 1 degree of freedom makes it an approximation rather than an interpolation but helps reducing oscillations and fills a full AVX vector."——9 点拟合 8 基是**逼近**不是插值，代价是全零带也有 ~1e-2 纹波（我方 CorrectionLUT.swift 头注释已如实记录此纹波），收益是抗振荡。

**smoothing（σ）的形态语义**（`:50-52`）：σ 大 = 更平滑但可能振荡；σ 小 = 更单调但可能不平滑。σ 是**曲线的"保护形态"旋钮**——拖某带 ±2EV 时，相邻带的联动宽度与过冲形态全由 σ 决定。GUI 上 σ 走 log 映射（`:2433`）。

### 1.4 第三段：apply（施加补偿）

```
exposure = clamp(log2(luminance[k]), −8, 0)          // 查表横轴
correction = LUT[round((exposure + 8) × 10000)]      // 纵轴
out[4k+c] = correction × in[4k+c]  ∀c ∈ {0,1,2,3}    // 含 alpha
```

两处 verbatim quirk：① **alpha 也乘**（`for_each_channel` = 4，我方已跟随）；② RBF 在 [−8,0] 外"quickly diverge"，靠钳位保命（`:866`）。

**OpenCL 路径注释**（`:879-881` + `toneequal.cl:126-184`）：GPU 上直接求 8 个高斯比上传 320KB LUT 便宜——dt 新版（2026 年版权头）已把 toneeq CL 化，此前 CPU-only。我方头注释称"dt 无 OpenCL（:313 TODO）"**已过时**（见 OQ-1）。

### 1.5 auto 双按钮：直方图分位 → mask 层自动塑形

这是任务书所问"阈值面自动计算"的正体。两个 quad（魔术棒）按钮，各自一套闭式解：

**统计量**（`compute_log_histogram_and_stats :2047-2121`）：512-bin 扩展直方图（[−10,+6] EV）→ 取 **5%/95% 分位**（first/last decile，命名 decile 实为 5% 尾）→ average = 两分位中点（`:2135`）。另有一份 256-bin [−8,0] 显示直方图叠在曲线图下。

**auto exposure_boost**（`:2493-2557`，目标：分布中心 → −4EV）：

```
// 先把当前 boost/contrast 的变换逆回去，得"裸分布"分位
fd_old = ((exp2(fd_new) − F)/c + F)/e ; ld_old 同式
// 闭式解：加权调和式
p->exposure_boost = log2(F × (s1+s2) / (fd_old×s2 + ld_old×s1))
其中 s1 = F − exp2(−7), s2 = exp2(−1) − F, F = exp2(−4)
```

**auto contrast_boost**（`:2560-2635`，目标：90% 分布铺满 [−7,−1] EV）：

```
c = log2(mix / (F × (ld_old − fd_old)) / c)   // mix 同上式分子
// 再加 EIGF/GUIDED 经验回归修正（:2613-2622）：滤波会改直方图，回归系数来自"一组图像拟合"
//   EIGF 且 c>0: correction = −0.0276 + 0.01823×feathering + (0.7566−1)×c（feathering 分段加权）
//   GUIDED 且 c>0: c = 0.0235 + 1.1225×c
p->contrast_boost += c
```

要点：① auto **不碰 9 带**，只动 mask 层两旋钮——"阈值面自动计算"校准确说是"mask 窗口自动对齐"；② 闭式解依赖"逆当前变换"（可重复按，不会漂移）；③ contrast auto 带**滤波器相关的经验回归**（EIGF/GUIDED 各一套系数）——移植时必须连带，否则 auto 结果在默认 EIGF 档下系统性偏；④ 守卫：预览管线忙 / mask 未就绪则拒绝并提示（`:2515`）。

### 1.6 交互式画布编辑：局部曝光补偿的"点选"形态

任务书所问"局部曝光补偿"在 dt 有两层：

- **区域感知（渲染层）**：EIGF/guided 边缘保持表面模糊——同一 EV 的像素按其**所在区域的平均曝光**（mask 值）而非自身值查曲线，细节保留。这是渲染数学，我方已有（见 §2）。
- **点选直调（交互层）**：鼠标悬停 → 读模块 buffer 该点 mask 亮度 → `cursor_exposure`（EV，`:2772`）；滚轮 → `set_new_params_interactive`（`:2801-2857`）：以 cursor_exposure 为中心、σ²/2 为带宽的高斯，把 ±0.25（Shift ±1.0 / Ctrl ±0.1）EV 散布到 9 带（线性域乘 `exp2(g×offset)`），**重解伪逆**、回写 9 带；画布叠加十字光标：in/out 双灰环（gamma 2.2 预览）、±2EV 楔形、"+x.x EV" 标签（`:2955-3059`），并高亮曲线图上最近节点（半径阈 0.45EV，`:3047`）。伪逆不稳定时打回并提示"减小 curve smoothing"（`:2828`）——σ 与交互稳定性直接挂钩。

另有 **mask 显示开关**（`:2638-2672` + `display_luminance_mask :1021`）：mask 归一 [−8,0]→[0,1] + sqrt（"gamma 2.0 便于看清阴影"）灰度显示——调 mask 层两旋钮时的**所见即所得**面。我方无。

### 1.7 预设曲线族：高光/阴影保护的配方形态

`init_presets :484` 登记 7 预设，其中两族是"保护曲线"配方：

- **compress**（`:448-464`）：以 −4EV 为中心，暗部 +step、高光 −step 的 S 形（系数 1, 5/3, 5/3, 1, 0, −1, −5/3, −5/3, −1；step ∈ {0.25, 0.45, 0.65} 三档），配 `exposure_boost=−1.57`（中灰搬 −4EV）+ blending 2% + feathering 50——"压高光提阴影"的标准起手式；
- **dilate**（`:467-482`）：反向 S（系数 −15/9…+15/9 渐变），配 details=NONE——**无滤波 1D tone curve 形态**下的反压缩（撤销 compress 用）。

要点：dt 的"保护"不是独立曲线对象，而是 **9 带 S 形配方 + mask 窗口预置**的组合。拖曝光时曲线形态变化 = RBF 连续插值 + σ 形态 + LUT 双端钳，三者共同决定。

### 1.8 兄弟模块 exposure.c 的曝光 auto（对照）

dt 的**全局曝光** auto 与 toneeq 的 mask auto 正交，调研一并登记（我方 exposure 差距评估用）：

- **spot correct/measure**（`exposure.c:909-1000`）：取色 → input profile 矩阵 → XYZ → Lab（去色只留明度）→ correct 档：`white = Y_in/Y_target` 反解白点；measure 档：显示当前曝光下该点 Lab。近黑（Y<1e-5）拒绝。
- **deflicker 自动档**（`:386-474`）：RAW 直方图百分位（默认中值）→ `correction = target_level − EV(pct)`，target 默认 −4EV。延时去闪专用。
- **bias 补偿**（`:572-620`）：EXIF exposure bias 回减 + 高光保留模式的欠曝回加；默认首实例 black=−0.00024414、bias 补偿开。

---

## 2. 我方现状精确测绘

### 2.1 我方 toneequal：渲染核 ≈ 完整，交互/auto 层 ≈ 空白

| 能力 | dt 源 | 我方 | 状态 |
|---|---|---|---|
| 9 带 params（±2EV）+ 五档 details + 七估计器 + iterations | `:173-193` | `ToneEqualModule.Params` 逐字段镜像，默认 EIGF/NORM2/iter 1 | ✅ 有 |
| commit 派生（blending/100、feathering 倒数、boosts exp2） | `:2310-2318` | `derive()` 逐式 | ✅ 有 |
| RBF 伪逆（Cholesky 法方程、Float 逐位）+ 80001 LUT + 钳 [0.25,4] | `:1880-1931` | `CorrectionLUT`（weights/lut/lutIndex 全） | ✅ 有 |
| luma 七估计器 + linear_contrast（fulcrum exp2(−4)） | mask.h | `toneeq_luma_estimate` + `TE_CONTRAST_FULCRUM` | ✅ 有 |
| EIGF/guided 双腿 + AVG 变体 + NONE 直通 | `:940-1014` | `toneeq_*` kernel 图全套 | ✅ 有 |
| apply 四通道乘（含 alpha quirk） | `:852-875` | `toneeq_apply` | ✅ 有 |
| 曲线图（y=0.5−log2(g)/4 同插值）+ 9 带 slider + 两 boost slider + 五档/method picker | `:2143-2164` | `ToneEqualPanelView`（Form 四 section + Canvas 曲线） | ✅ 有 |
| **smoothing σ slider** | `:185` params + `:2433` log 映射 | Params 有字段、曲线消费它，但**面板无 slider**（只有 section 标题借名） | ❌ 缺（半缺） |
| **auto exposure_boost（分位→−4EV 闭式）** | `:2493-2557` | 无 | ❌ 缺 |
| **auto contrast_boost（90%→[−7,−1] 闭式 + 回归修正）** | `:2560-2635` | 无 | ❌ 缺 |
| **直方图统计（512-bin 分位 + 256-bin 显示）** | `:2047-2139` | 无（toneeq 域；film 域有 256-bin 面板直方图先例） | ❌ 缺 |
| **画布点选直调（悬停读 EV + 滚轮高斯散布 + 重解伪逆）** | `:2801-2930` | 无 | ❌ 缺 |
| **画布 EV 光标（in/out 双环 + 楔形 + 标签 + 节点高亮）** | `:2955-3059` | 无 | ❌ 缺 |
| **mask 显示开关** | `:2638+1021` | 无 | ❌ 缺 |
| **预设族（compress/dilate 三档 + blending 预置）** | `:448-482, 503-591` | 无 toneeq 预设面 | ❌ 缺 |
| show_guiding_controls（按 details 档显隐 contrast/quantization 行） | `:2370` | 面板恒显全部行 | ⚠️ 差异（小） |

面板位置注记：toneequal 在 Tone 页「Darktable 兼容件」折叠组（`EditorTabRoute.swift:215`），属可编辑但非 Alcedo 主面——任何 toneeq 交互增强须先过 IA 决策（放兼容组内增强 vs 提升为主面）。

### 2.2 我方 exposure：手动核完整，auto 面全缺

| 能力 | dt 源 | 我方 | 状态 |
|---|---|---|---|
| 手动 EV（±18）+ black（±1），`white=exp2(−EV), scale=1/(white−black)` | basic.cl | `ExposureModule` verbatim + golden | ✅ 有 |
| spot correct/measure 取色自动曝光 | `exposure.c:909` | 无（params 无 spot 位） | ❌ 缺 |
| deflicker 百分位自动档 | `:442-474` | Mode 位保留但面板 disabled（divergence #2 明示） | ❌ 缺（已登记） |
| EXIF bias 补偿 / 高光 bias 补偿 | `:572-620` | 位保留未接线（divergence #4） | ❌ 缺（已登记） |
| 默认 0.7EV 中灰种子 | `:361` | 我方刻意中性默认（divergence #1，CIRAW 域已含基线） | ➖ 故意不跟 |

### 2.3 我方 film 宽容度面板（M3-4）：可复用的相邻资产

`FilmPanelModel/LatitudeSectionView`：256-bin 直方图 Canvas（EV 轴 [−6.56,+2.44]，`binEV` 单源）+ descriptor useful-EV 虚线 + shares readout + coordinator 镜像快照机制（`filmStatsSnapshot`）。toneeq auto 所需的"直方图统计 → 面板呈现"链路已有**同构先例**，G3 可直接抄机制（c）。

---

## 3. 差距逐条评估

编号 G1…G8，按"用户所指的 toneeq 曝光方式"相关度排序。

### G1. auto 双按钮（mask 窗口自动对齐）——**核心缺口**

- **dt 做了什么**：§1.5。5%/95% 分位 → 两闭式解 → exposure_boost（中心→−4EV）+ contrast_boost（90%→[−7,−1]，EIGF/GUIDED 回归修正）。不碰 9 带。
- **我方**：无。用户只能盲拖 ±16EV 两 slider，无任何"对准"手段——这是 toneeq 上手门槛高的主因（dt 文档头 `:75-79` 明说 auto helpers 就是为解决"不是所有带每图都有用"而设）。
- **是否需要**：**要**。这是"dt toneeq 调整曝光的方式"里最可摘的一颗：纯计算、无渲染改动、效果立竿见影。
- **实现路径**：① 统计源：toneeq 模块输入平面（mask 输入 = 模块输入 buffer）跑 512-bin log 直方图——`HistogramReduce`（Common 已有）或复用 film stats 链路（`FilmStatsSeam` 256-bin，但其输入是 film 腿平面**不是** toneeq 输入——统计源不同，须新开一条轻统计或把直方图探针挂到 toneeq `process` 前）；② 分位→闭式解纯函数移植（含回归修正系数 verbatim）；③ 面板加两按钮（D-H1 discrete commit）；④ 守卫：管线忙/统计未就绪则禁用（dt `:2515` 同款）。
- **价值**：高。单点投入，中高回报；且是 G4（画布直调）的前置——cursor_exposure 读数依赖 mask，而 mask 窗口不对齐时读数无意义。

### G2. smoothing σ 面板旋钮 ——**半缺，易补**

- **dt 做了什么**：σ 默认 √2，GUI log 尺度（`:2433`），控制 RBF 联动宽度/振荡倾向；σ 还决定交互伪逆稳定性（`:2828` 打回提示）。
- **我方**：Params/commit/LUT/曲线全消费 σ，但面板无 slider——σ 被冻结在默认值。用户拖 9 带时的"保护曲线形态"**不可调**。
- **是否需要**：**要**（顺手项）。G1/G4 落地前也应先补——否则 auto/交互文案里的"减小 smoothing"无处可减。
- **实现路径**：面板加一 slider（range 照 dt bauhaus 语义换算 log 域；或直接线性 0.5…4  Lime 简化——dt 的 log 映射只是手感，OQ-3），D-H1 接线。零渲染改动。
- **价值**：中低。单旋钮，但补上"曲线形态"调节能力闭环。

### G3. 直方图呈现（曲线图下叠显示直方图）

- **dt 做了什么**：256-bin [−8,0] 直方图画在均衡器曲线图下（`update_histogram` + Cairo 绘制 `:3114+`），与 9 节点同 x 轴——用户一眼看出"分布落在哪些带上"。
- **我方**：toneeq 曲线图（`ToneEqualCurveView`）只有曲线无直方图；但 film 宽容度面板已有"EV 轴直方图 Canvas + coordinator 镜像快照"全套机制（§2.3）。
- **是否需要**：**要**（与 G1 打包）。auto 按钮按下去"发生了什么"，必须有直方图可视化承接，否则用户不信任 auto 结果。
- **实现路径**：抄 film 机制（c）：toneeq 输入平面直方图 → coordinator 快照 → `ToneEqualCurveView` Canvas 叠 bars（x 轴 [−8,0] 与现有曲线同轴）。统计与 G1 共用同一探针。
- **价值**：中。与 G1 绑定交付。

### G4. 画布点选直调（悬停读 EV + 滚轮散布）

- **dt 做了什么**：§1.6。悬停读模块 buffer mask→EV；滚轮高斯散布→重解伪逆→回写 9 带；光标叠加 in/out/楔形/标签；节点高亮。
- **我方**：无。视口是 MTKView + 覆盖层体系（crop/ashift 等已有手柄先例，但"悬停读数+滚轮改参"形态无先例）。
- **是否需要**：**要，但排后**。这是 dt toneeq 交互皇冠（"指哪打哪"的局部曝光感主要来源），但依赖 G1（mask 窗口须先对齐）+ 视口覆盖层新形态 + `CorrectionLUT.weights` 已具备重解能力（`weights()` 纯函数可直接复用——好消息：伪逆已在 Swift 侧，只需包 `set_new_params_interactive` 等价逻辑）。
- **实现路径草案**：① mask 读数缝：toneeq `process` 后把 mask 平面（已有 scratch 纹理）下采样一份给 coordinator（读数用缩略图精度即可，dt 读的也是 preview buffer）；② 视口 hover → 采样读数 → 浮层标签（SwiftUI overlay，不必 Metal 自绘）；③ 滚轮/scroll 手势 → 高斯散布（σ²/2 带宽 verbatim）→ `CorrectionLUT.weights` 重解 → discrete commit（注意 dt 是每次滚轮一格一 history item——我方 D-H1 语义下应合并为手势级单 commit，偏离须登记）；④ 节点高亮：曲线图已有节点绘制，加一 active 态。
- **价值**：高（体验），成本亦高（视口交互新形态 + 跨层读数缝）。建议 G1+G2+G3 先行，G4 单独立项。

### G5. mask 显示开关

- **dt 做了什么**：§1.6 末。mask 灰度可视化（归一 + sqrt），调 mask 层两旋钮时的所见即所得。
- **我方**：无。
- **是否需要**：**可要**（G1 附带）。G1 auto 落地后，用户想验证"窗口对齐得对不对"，mask 显示是最直接的面。成本低（mask 纹理已有，只需一条显示腿 + 开关）。
- **实现路径**：toneeq `process` 加 `displayMask` 分支（读 scratch mask 平面 → 归一/sqrt → 输出），面板一 Toggle（会话态，不进 params——dt 的 `mask_display` 也是纯 GUI 态 `:244`）。注意 thumbnail/导出腿恒关。
- **价值**：中低。调试/教学价值大于日常价值。

### G6. 预设曲线族（compress/dilate + blending 预置）

- **dt 做了什么**：§1.7。两族 S 配方 × 三档 step + mask 预置（exposure_boost=−1.57 / blending / feathering / details=NONE 变体）。
- **我方**：无 toneeq 预设面（预设体系在 12-metadata-presets-lut / MCP apply_preset 侧，与 toneeq 未接）。
- **是否需要**：**暂不要**（或极简版）。配方本身 trivial（9 个数 + 4 个 mask 值），但价值依赖"预设体系"存在——在 Lightamer 预设体系落地前，单给 toneeq 开预设 UI 是孤岛。替代方案：把 compress-0.45 一组数写进文档/验收脚本当"标准起手式"零成本交付。
- **实现路径**：预设体系就绪后，9 带数组 + mask 四元组 verbatim 转录即可（注意 dt 预设 `method=NORM_POWER` vs 我方默认 NORM2——差异须显式决策，OQ-4）。
- **价值**：低（当前阶段）。

### G7. exposure 全局 auto（spot/deflicker/bias）

- **dt 做了什么**：§1.8。spot correct/measure、deflicker 百分位、EXIF bias 回减、高光 bias 回加。
- **我方**：全缺（deflicker/bias 已在 ExposureModule 头注释登记为 divergence #2/#4）。
- **是否需要**：**部分要**。① spot correct（点选中灰→反解白点）与 G4 同构（都是"视口取色→反解参数"），可与 G4 同一批视口取色基建；② deflicker 是延时摄影专用——Lightamer 无时间线面，**不适用**；③ EXIF bias 回减：CIRAW 域基线已含曝光（divergence #1 同理），且需 RAW-06 元数据管线——排后。
- **实现路径**：spot correct 复用 G4 的视口取色 + `white = Y_in/Y_target` 一式；measure 档是纯读数面。
- **价值**：中（spot correct）/ 低（其余）。

### G8. 按 details 档显隐面板行 + OpenCL 注释过时

- **dt 做了什么**：`show_guiding_controls` 按档显隐 contrast_boost/quantization 等行（AVG/NONE 档下 contrast 无效故隐藏——防"拖了没反应"的困惑）。
- **我方**：恒显全部行。用户在 NONE 档拖 contrast_boost = 无操作（静默无效）。
- **是否需要**：**要**（卫生项）。一行 `.disabled(details == .none || isAveraged)` + 说明文案即可，比 dt 的显隐更温和（SwiftUI 显隐会跳布局，disabled 不跳）。
- 另：我方两处头注释称"dt 无 OpenCL"已过时（dt 2026 版已 CL 化 `toneequal.cl` 全套）——文档卫生，顺手改（OQ-1 落定后）。

---

## 4. 可学习点结论

### 立即可学（纯加法、零渲染改动、单批可交付）

| # | 学习点 | 改动面 | 验收形态 |
|---|---|---|---|
| L1 | **auto 双按钮**（G1）：分位统计 + 两闭式解 + 回归修正 verbatim | 新统计探针（toneeq 输入平面 512-bin）+ 纯函数 + 面板两按钮 | 同图连按两次结果稳定（幂等）；与 dt-cli 同图 auto 值 ±0.05EV |
| L2 | **σ slider**（G2）：smoothing 面板旋钮 | 面板一 slider（D-H1） | 拖 σ 曲线图联动宽度实时变；LUT golden 复跑零漂移（σ 默认值不变） |
| L3 | **直方图叠加**（G3）：曲线图下叠 256-bin [−8,0] | 抄 film 机制（c）+ Canvas 加 bars（与 L1 共探针） | 分布峰与 auto 对齐结果一致（峰中心 ≈ −4EV ±0.5） |
| L4 | **无效行置灰**（G8）：NONE/AVG 档 contrast 置灰 + 说明 | 面板条件 disabled | 切 NONE 档 contrast 行置灰；文本说明原因 |

建议打包为一批：「toneeq auto 面」（L1+L2+L3+L4）。

### 需要设计（跨层/新形态，单独立项）

| # | 学习点 | 设计点 |
|---|---|---|
| D1 | **画布点选直调**（G4） | 视口 hover+滚轮新形态；mask 读数缝（缩略图精度）；滚轮→history 合并语义（偏离 dt 逐格 commit）；与 crop/ashift 手柄体系的共存 |
| D2 | **mask 显示腿**（G5） | 显示分支的腿位（thumbnail/导出恒关）；会话态 Toggle 位置 |
| D3 | **spot correct**（G7-①） | 与 D1 共视口取色基建；input-profile 矩阵源（我方 CIRAW 域 ≠ dt camera RGB，Y 反解公式须重推——OQ-2）；measure 档读数面形态 |

### 不适用 / 暂缓

| # | 项 | 理由 |
|---|---|---|
| N1 | deflicker 自动档 | 延时专用，无时间线面 |
| N2 | 预设族 UI（G6） | 等预设体系；先以文档"标准起手式"零成本交付 |
| N3 | dt 默认 0.7EV 中灰种子 / compress 预设 method=NORM_POWER | 我方 CIRAW 域基线已含（divergence #1）；method 默认差异待 OQ-4 |
| N4 | EXIF bias 回减 | 等 RAW-06 元数据管线；CIRAW 域语义待定 |

---

## 5. OQ 清单

| # | 问题 | 背景 | 决策影响 |
|---|---|---|---|
| OQ-1 | 我方头注释"dt 无 OpenCL"已过时——是否顺手刷新注释 + 评估 dt CL 版 `toneequal_apply`（直接求高斯、免 LUT 上传）对我方 Metal 腿的启示？ | dt 2026 版 `toneequal.cl:126-184` 全套 CL 化；我方 `toneeq_apply` 走 LUT 查表 | 文档卫生必做；腿形态评估可选（我方 LUT 路 golden 已定，动腿=重验全套） |
| OQ-2 | spot correct 的 Y 反解在我方 CIRAW 域是否成立？ | dt 公式依赖"模块在 colorin 之前 + input profile 矩阵"；我方解码域是 CIRAW 显示域 | D3 立项前置：须先确认反解公式的域适配，否则 correct 算出的 white 是错的 |
| OQ-3 | σ slider 用 dt 的 log 映射还是线性简化？ | dt `:2433` log 尺度只是手感 | 建议线性 0.5…4 简化（手感差异可走查定），plan 时一句话裁定 |
| OQ-4 | compress 预设转录时 method 取 dt 的 NORM_POWER 还是我方默认 NORM2？ | dt 预设 `:489` 用 NORM_POWER；dt 文档头称 power norm"观感最好但无理论依据" | G6/N2 落地时定；建议跟 dt（预设是配方，配方含 method） |
| OQ-5 | toneeq 增强放"Darktable 兼容件"折叠组内，还是借机提升 IA 地位？ | 当前 toneeq 在 Tone 页 compat 组；auto/画布直调是强交互面 | L1 批（按钮+直方图）在组内即可；D1（画布直调）是跨页能力，须 IA 决策 |
| OQ-6 | 统计探针挂哪：toneeq 输入平面实时算，还是复用 film stats 链路？ | film stats 输入是 film 腿平面 ≠ toneeq 输入；toneeq 输入 = 链上游实时平面 | 建议 toneeq `process` 前轻探针（512-bin log 直方图 GPU reduce，`HistogramReduce` 有先例）；film stats 不可复用（源不同）——plan 时确认 |
| OQ-7 | auto 结果的 history 语义：单 discrete commit 还是并入用户手势？ | dt `dt_dev_add_history_item(TRUE)` 单 item | 建议单 discrete commit（与 D-H1 discrete 同形），plan 时一句话裁定 |

---

## 6. 源码索引（行号 = 上游 `18cf557fbd` 实测）

| 内容 | 位置 |
|---|---|
| 模块文档头（relight 设计哲学） | `src/iop/toneequal.c:20-85` |
| params 结构（9 带 + mask 五旋钮 + 两 boost + details/method/iter） | `:173-193` |
| 高斯核 / 钳位常量 | `:824-845` |
| apply 双版（LUT 现行 / 直接求高斯参考） | `:847-918` |
| 五档 mask 计算 | `:940-1014` |
| mask 显示 | `:1021-1062` |
| RBF：LUT / gains / 插值矩阵 | `:1880-1899` / `:1901-1931` / `:2030-2043` |
| 直方图分位统计 | `:2047-2121`，average `:2135` |
| commit（派生 + 双路伪逆 + LUT 烘焙） | `:2293-2351` |
| 按档显隐 | `:2370-2409` |
| **auto exposure / auto contrast** | `:2493-2557` / `:2560-2635` |
| 交互散布 / 滚轮 / 画布光标 | `:2801-2857` / `:2860-2930` / `:2955-3059` |
| 七估计器 + linear_contrast | `src/common/luminance_mask.h:40-48, 71-75` |
| CL 版 mask/apply（免 LUT 上传注记） | `data/kernels/toneequal.cl:52-123, 126-184` |
| 预设配方（compress/dilate） | `src/iop/toneequal.c:448-482, 498-591` |
| exposure spot/deflicker/bias | `src/iop/exposure.c:909-1000` / `:386-474` / `:572-620` |

我方对照：`LightamerIOP/Sources/ToneEqual/{CorrectionLUT,ToneEqualModule,ToneEqualKernels}.{swift,swift,metal}` · `LightamerIOP/Sources/Exposure/ExposureModule.swift` · `App/Sources/Lightamer/UI/Inspector/{ToneEqualPanelView,ExposurePanelView}.swift` · film 宽容度先例 `App/.../Shell/{FilmPanelModel,FilmPanelView}.swift`。

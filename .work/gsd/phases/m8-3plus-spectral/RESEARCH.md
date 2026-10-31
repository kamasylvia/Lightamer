# M8-3+ RESEARCH — 光谱延展批：C200 撞墙修复 + 空间三算子接谱 + m-6①/时长维机理

```
phase: M8-3+ (spectral extension)
status: drafted
date: 2026-10-31
researcher: omp (M8-3+ research lane)
正本: R9 R9-{SUMMARY,DECISIONS}.md（m-3①②③）+ M8 CONTEXT/DECISIONS（D-M8-4 挂账族）
     + M9-2 RESEARCH/DECISIONS（同管线最近交付）+ dt spektrafilm 宽模糊 4 commits
红线: 零 commit / 零构建 / 零测试 / 零 GUI —— 纯文本调研，产物 = 本文件
```

---

## 0. 结论先行（orchestrator 速读）

1. **C200 撞墙不是"差一点"，是"dichroic 杠杆耗尽 + 工作点近分叉"的结构性缺口**：
   静态复演证明 Y=250 处 dichroic dim 系数已饱和至 0.9968（再加 150 CC 只换 0.003
   光量），同时 C200 对的中性解对中灰密度谱高度敏感（midgray CMY 代理在 ±0.5 dex
   内解从 Y=46 摆到钳制）。修法推荐 = **两段式：实测锚 seed（`neutral_print_filters.json`
   只读作初值）+ 收敛失败 typed 降级（neutral 守恒回退 + 面板 disclosed 态）**，
   域扩展（250→400）单独上是安慰剂——光空间只剩 0.3% 可调量。
2. **28 profile 静态 Y 需求分布**：16 负片中 14 个收敛 Y<80 安全；C200/Xtra400 是
   唯二近墙族（静态 Y 85-250，crystal 纸上最紧）；4 反转片在印相纸上本就不该中性
   求解（静态 ektachrome 撞墙 + velvia 残差 18%），修法必须含"反转片×印相纸"路由
   决策（OQ-M83-3）。
3. **三算子接谱**：grain = 密度域调制（上游五 kernel 形态直搬，落点 = stage B 的
   develop 后 print 前，需拆 B 或加 C 段）；halation/diffusion = film sub-run 外
   的前置/印相腿空间算子（上游调用侧形态），宽模糊一律走 dt 宽模糊抽稀设计
   （`sf_wide_blur_plan` 三阈值 + 中央方差扣减 + 拆双 kernel + ROI 网格锚定）。
4. **m-6①（undo 腿未重走）**：源码面 carrier 同步在位（`undo()/redo()` 双 sync），
   R8"undo 不恢复"在 R9 冷 build 窗理论下自洽——M8-3+ 无需修，只需验收批补一条
   undo 腿实测。**时长维（2 分钟写腿差异）**：唯一机理候选 = film 启用 path 的
   `historyDidChange()` 触发 4-5 分钟 tc 冷 build，MainActor 串行化把去抖写饿死
   至 build 窗后——可机检证伪（oslog 时间戳对账），修法 = 写腿与渲染腿解耦
   （OQ-M83-8）。
5. **OQ 共 9 条**（§6），全部带推荐值；process 号结论：C200 修法与三算子若改默认
   渲染面 = v4 候选（§7），默认 off 形态可 v3 内 additive。

---

## §1 C200 Y 撞墙修复设计

### 1.1 R9 定罪复述（输入，不重证）

- `SpectralBuildEngine.swift:730-747` 2D Newton 梯：32 轮、seed (50,50)、钳制域
  [0,250]，驱动中灰 log 通道比归零（C 钉 0）。
- C200 × Crystal Archive II：solvedPrintCC=(0,108.3,**250.0=钳制**)，灰误差 3%；
  Portra400 × Endura：(0,33.1,26.8)，灰误差精确 0。
- R9 m-3 三条不确定性（本研究输入）：
  ①「3% 灰误差 → posterize」机制链待补像素值证据；
  ② M/Y 巧合（108.3 vs 108.32 实测锚 Y）待 verdict 复核；
  ③ 真照片 portra 对照腿缺失。

### 1.2 本研究的新证据（静态复演，方法学登记）

**方法**：Python 独立复算（`SpectralConstantsData.swift` 的 dichroic 表 +
TH-KG3 SPD 正则抽取 verbatim；`illumPrintFor`/`printRaw`/Newton 迭代逐行转录；
film 中灰密度谱 = base + channelDensity × CMY₀，CMY₀ = density_curves 在
logE≈log₁₀(0.184) 最近行——代理，见 §1.5 方法学诚实面）。

**证据 A——portra 代理稳定，C200 代理失稳（结构性发现）**：

| 对 | CMY₀ 在 idx 60..180（logE −1.35..+1.94）扫 | 解 Y 范围 |
|---|---|---|
| portra400 × portra_endura（真值 33.1/26.8） | CMY₀ 全程扫 | M 28-38 / **Y 18-27（稳定，真值落带内）** |
| C200 × crystal（真值 108.3/250 钳制） | CMY₀ 全程扫 | M 31-109 / **Y 46→250（失稳，idx120 起撞墙）** |

判读：portra 对的代理在 ±1 dex 密度扰动下解漂移 <10 CC——代理有效，真值可信。
C200 对在同样扰动下解从 Y=46 摆到 250 钳制——**该对的工作点靠近中性流形的分叉/
折叠区**，小密度移动引起解的大跳变。这解释了为什么"换个 seed/多几轮"救不了
C200：问题不在求解器收敛性，在解的存在性裕度。

**证据 B——钳制墙外没有光（域扩展是安慰剂）**：

dichroic dim 系数 dim(Y)=1−10^(−Y/100)：Y=100→0.90、150→0.968、200→0.99、
250→0.9968、300→0.999、400→0.9999。d(dim)/dY 在 250 处 = 7.3e-5/CC。
C200 真解（若存在）按"~2× 越域"口径在 Y≈400-500——但 250→500 的光量变化只有
0.9968→1.0000 = **0.3%**。结论：**把钳制域从 250 放到 400/500，
中性残差的改善上限是光空间 0.3%，灰误差 3% 基本不动**。域扩展单独上 = 安慰剂。

**证据 C——seed 不敏感（初值改进救不了 C200）**：
C200 × crystal 在 7 个 seed（(50,50)/(85.9,108.3) 实测锚/(0,0)/(100,100)/
(150,150)/(50,200)/(200,50)）下静态解逐位同值
（M=106.3/Y=197.5/err=0.000%）。Newton 盆地在该对上是全局单盆——
**初值改进对 C200 零收益**（但对别的对仍有加速价值，见 §1.4 修法②的定位）。

**证据 D——m-3② M/Y 巧合复核**：
实测锚 C200 × crystal = [0, 85.91, 108.32]，求解值 = (M=108.3, Y=250钳制)。
巧合项是**求解 M=108.3 ≈ 实测 Y=108.32**——跨通道数值巧合，非同通道。
静态复演在 idx120（CMY₀≈[1.04,0.86,0.88]）给出 M=108.3 精确命中——说明求解 M
对密度谱敏感且该值是真解的 M 分量，与实测 Y 的数值接近是两套 premises
（自近似 dichroic vs 真实放大机头）在该对上的偶然交叉。**复核结论：巧合，
无机制含义**——但它恰好证明自解与实测表是"不同域"（M8-2 DECISIONS 三已登记
M −18.5/Y −25.7 CC 偏移），实测表只能作 seed/参考，不能作真值。
m-3② 关闭。

**证据 E——m-3① 机制链补块（静态侧）**：
Y 钳制 → print 表在偏色工作点构建 → 偏色方向 = 蓝通道印相曝光过高
（Y dial 管蓝通道衰减，钳制 = 蓝减不下去）。scan 表随后把偏蓝的打印密度映到
输出——posterize（色调分离）的候选机理 = print PCHIP 表在偏色工作点 + 33³
格点在饱和区的插值硬化。但**静态侧只能给到"偏蓝工作点"这一步**，
"偏蓝 → posterize 台阶"的像素值证据必须执行批在真 build 产物上取
（print 表切片 + 输出直方图断层计数）。m-3① 部分关闭：方向已定（蓝偏），
像素值证据列执行批验收项（§1.4 修法验收）。

### 1.3 28 profile Y 需求静态分布（全表）

口径：20 film（含 4 反转）× 8 paper = 160 对，CMY₀ = logE≈log₁₀(0.184) 最近行
代理（portra 校准：真值落带内；C200 方向：真值在代理上界之上——即**本表是
Y 需求的下界估计**，真需求只会更紧）。

| film | Ymin | Ymax | Ymean | Mmax | worst paper | 失稳带（CMY₀扫 crystal） |
|---|---|---|---|---|---|---|
| fujifilm_c200 | 85 | 198 | 108 | 106 | crystal_archive | **161-250（近墙）** |
| fujifilm_xtra_400 | 90 | 249 | 119 | 109 | crystal_archive | **193-250（近墙）** |
| kodak_ektachrome_100 | 76 | 250钳制 | 106 | 59 | crystal_archive | 236-250（反转，见注） |
| fujifilm_provia_100f | 76 | 177 | 103 | 50 | crystal_archive | 158-250（反转） |
| kodak_kodachrome_64 | 72 | 151 | 93 | 41 | crystal_archive | 134-250（反转） |
| fujifilm_velvia_100 | 32 | 102 | 54 | 13 | crystal_archive | 98-250（反转，残差 18%） |
| kodak_gold_200 | 27 | 61 | 37 | 57 | crystal_archive | 61-77 稳定 |
| kodak_ultramax_400 | 30 | 64 | 40 | 58 | crystal_archive | 63-73 稳定 |
| kodak_portra_800 系列 | 28-31 | 60-64 | 38-41 | 60-61 | crystal_archive | 58-79 稳定 |
| kodak_verita_200d | 29 | 58 | 39 | 60 | crystal_archive | 57-69 稳定 |
| kodak_vision3 系列 | 20-24 | 48-53 | 31-35 | 45-53 | crystal_archive | 48-58 稳定 |
| kodak_portra_400/160 | 13-19 | 40-45 | 24-29 | 48-53 | crystal_archive | 38-61 稳定 |
| fujifilm_pro_400h | 10 | 36 | 19 | 42 | crystal_archive | 32-37 稳定 |
| kodak_ektar_100 | 1 | 28 | 10 | 48 | crystal_archive | 29-51 稳定 |

分布判读（四档）：

1. **安全档（14 负片）**：Ymax < 80，失稳带全程 < 80——修法零影响面，
   回归负测锚定档。
2. **近墙档（C200/Xtra400，唯二）**：静态 Y 已 85-249，真值撞墙——修法正主。
3. **反转档（4 反转片）**：ektachrome 静态即撞墙（残差 2%），velvia 残差 18%
   （M 钉 0 下界——求解器想往负 M 走，被 0 下界拦住）。
   物理判读：反转片 × 印相纸（RA-4）在暗房本就是非标准流程（反转片印相应走
   R-3/Ilfochrome），中性解不存在或病态是**预期内**——修法必须路由决策，
   不能当 bug 修（OQ-M83-3）。
4. **纸面规律**：worst paper 20/20 全是 crystal_archive_typeii——Fuji 纸的
   蓝敏乳剂谱形与自近似 dichroic 的组合最紧。默认材料对 = 首排序对恰 C200 ×
   crystal（R9 D-R9-3 已登记）= 最紧对当默认——路由优先级加重成立。

### 1.4 修法设计（推荐：两段式，域扩展否决单上）

**否决臂——单纯域扩展（250→400/500）**：证据 B 已证伪。光空间只剩 0.3%，
灰误差 3% 不动；还会把"钳制"判据推后，让更多对进入"收敛了但工作点荒谬"
的静默坏态。不建议单独上；若上，仅作为两段式第二段的配套（见下）。

**否决臂——单纯初值改进（实测锚 seed）**：证据 C 已证 C200 零收益。
但实测锚 seed 对 14 安全档是免费加速（32 轮 → 实测约 5-10 轮可收敛到同值，
逐位验证后可降轮数省 build 时间），且对反转档可能改变盆地归属。定位 =
两段式的第一段 + 全族加速，不单独作为 C200 修法交付。

**推荐臂——两段式（求解 + 守恒降级）**：

- **第一段（求解加固）**：
  1. seed = 实测锚（`neutral_print_filters.json` 只读，film×paper 查表；
     缺席项回落 (50,50)；反转片四项恒 50 在册 = 无信息 seed，见 §1.3）；
  2. 钳制域 [0,250] 维持（物理 dial 域诚实面——放大机头本来就这么大）；
  3. 收敛判据加严：残差 |r.x|+|r.y| 终值 + 是否触钳制墙，双输出
     （`solvedPrintCC` 附 `clamped: Bool`——build 产物面 additive，
     不进 sidecar，不 bump schema）；
  4. 轮数 32 维持（seed 改进后实测若全族 <12 轮收敛，可降 16 轮——执行批
     实测裁决，DECISIONS 申报）。
- **第二段（守恒降级，C200/反转档的正业）**：
  触墙（clamped=true）时不把偏色工作点当无事构建，而是走 typed 降级三选一
  （OQ-M83-1 裁决，推荐值 = ②）：
  ① 白名单：触墙对标记"该材料对中性未收敛"，build 继续但面板 readout
   disclosed（amber 行）+ 渲染面照旧（诚实面：用户知情）；
  ② **守恒回退（推荐）**：print 表构建改用"墙内最优 + 残差补偿"——即在
  Y=250 墙内解 M/Y 使残差最小（1D 线搜索，M 自由），残差剩余量折进
  `midgrayFactor` 的通道相关修正（几何均值归一 → 通道仿射归一，
  只在 clamped 对上启用，安全档逐字节零漂移）；灰误差 3% → 预期 <0.5%
  （执行批实测钉值）；
  ③ 销档：触墙对拒绝启用（typed degrade + toast）——最保守，但 C200 是
  默认对，销档 = 新用户启用即 toast，不建议。
- **反转档路由**（OQ-M83-3，推荐值 = B）：
  A. 反转×印相纸走同一求解（现状，ektachrome 撞墙/velvia 残差 18%）；
  B. **反转片的中性求解改"正片直印"语义**：反转片密度谱的 polarity 与负片
  相反——求解目标从"印相曝光中性"改为"扫描输出中性"（scan 腿后），
  或等价地把反转×印相对标记为"需手动 CC"（面板 Y/M 手动项是现成载体）；
  C. 反转片暂时只配 2383/2393（print film，电影印片——反转印片的物理近邻），
  RA-4 纸配对隐藏。推荐 B（语义诚实 + 零销档），C 作 B 的配套 UI 收敛。

**修法验收（m-3① 的像素值证据一并收）**：
C200 × crystal 真 build：solvedPrintCC + clamped 标志 + 灰误差 + print 表
蓝通道切片 + 合成灰阶输出直方图断层计数（posterize 判据）——修前修后对照；
14 安全档 solvedPrintCC 逐位零漂移负测（第一段 seed 改进的回归面）；
portra 真照片对照腿（m-3③ 关闭项——执行批在验收面补，不在 research 面）。

### 1.5 方法学诚实面（静态复演的边界）

1. CMY₀ 代理 ≠ 真 chain head：真值 = sRGB 0.184 经 m_in → tc gather → 链头
   曝光 → lograw → **未归一 stock 曲线**查表。代理用 logE≈log₁₀(0.184) 行直读，
   跳过了 tc gather 与曝光归一。portra 校准（真值落带）证明代理在稳定对上有效；
   C200 的失稳带（161-250 vs 真值 250 钳制）证明方向正确但数值是下界。
2. 通道密度取向：`channel_density` 行取 [λ][c]（与引擎 `filmChanDens[l][c]`
   装配一致，`SpectralBuildEngine.swift:402-413` 亲核）；None 插值用线性
   （引擎用 `channelDensityProjected()` 的 null-aware 投影——同族不同实现，
   数值差在插值带内）。
3. 本表只覆盖 TH-KG3 单放大机光源（默认参数）；换 enlarger 光源 = 换 SPD =
   需求分布整体平移——执行批若动光源集，本表重跑（脚本 30 行，落 evidence）。

---

## §2 grain/halation/diffusion 接谱设计

### 2.1 上游形态正本（dt spektrafilm，`4d1fb6a95b` 树 = 宽模糊四 commit 收口态）

管线座位（`spektrafilm.c:20-60` 模块头，verbatim 结构）：

```
scene-linear work RGB
  → CAT16 → tc 上采样 × film sens          = camera exposure
  → [highlight boost → diffusion → scatter/halation]   (linear, SPATIAL)  ← 算子①②
  → log exposure → DIR coupler 纠正（blurred）= film development
  → CMY film density → grain               (density, SPATIAL)             ← 算子③
  → enlarger 印相                            = print exposure
  → print diffusion（可选）                   (linear print exposure)      ← 算子②第二座位
  → print density curves
  → scan（viewing SPD × CMFs → CAT02 → OkLCh）= scanning
```

关键结构事实：**五个引擎 stage 全逐像素，空间效果全在调用侧**
（`spektra_sim.h:31-37` 头注 "intentionally not in this engine"）。
我方 M8-1b 把七 stage fuse 成 A/B 两 dispatch——接谱设计必须回答每个算子
插在 fused 链的哪里（§2.2-2.4 逐算子落点）。

### 2.2 grain 接谱（密度域调制/显影耦合）

**上游数学**（`grain.h` + `spektrafilm_grain_{gen_raw_sl,accumulate_1c,
finalize_channel,add,usm}` 五 kernel）：

1. **粒子模型**：每乳剂子层 Binomial(Poisson(λ), p) 经 Poisson thinning 塌缩为
   单 Poisson(λ·p)（`grain_layer_particle`）；λ<12 精确 Knuth 分支（`grain_exp_neg`
   自实现 exp，bit-exact 纪律），λ≥12 正态近似（`grain_normal` = Irwin-Hall
   四均匀和，sqrt(3) 归一；plain `sqrt()` 禁 `native_sqrt`）。
2. **种子**：`grain_pixel_seed` = Teschner 空间哈希（绝对图像坐标 → pan/zoom
   稳定）× 通道/子层 decorrelate 常数。
3. **四件套装配**：子层采样 → dye-cloud blur（per-sublayer σ，常 <1px 仍有效，
   `sf_blur_plane1` 单通道面）→ 通道累加 → finalize（减 floor/减原密度 ×
   amount → delta）→ `grain_add` 加到 CMY 密度 → **clump blur（作用在
   合并后的 grained density 上，不是孤立 grain 层——`_finalize_grain` 参照语义）**
   → 乘法 USM 恢复 acutance（`D·(D/blur(D))^amount`，floor 回加防阴影病态，
   ratio 钳 [1/4,4]，`pow()` 的 16 ULP 上游已知残留）。
4. **显影耦合点**：grain 消费 develop 后的 CMY 密度 + 每子层 (dmax, npart,
   dmin, curve) 表——即**grain 是显影的下游，不是独立叠加层**；density floor
   （`grainDensityMin`，我方 `Parameters` 已有载体 `:220`，v1 恒 0）是粒子基座。

**我方现状**：GrainModule（dt 遗产，v50 slot 65.0）= 3-octave simplex 噪声 ×
strength/100 × 0.15 × paper-response 包络，加在 linear Rec2020 luma 上
（等量加 RGB 三通道，零色度噪声）。M9-2 T4 已交付 per-film granularity 标定层
（`GrainCalibration`：发表 RMS → 推荐 strength，面板 readout + 一键应用，
GrainModule.swift 零 diff）——即**标定面已就绪，缺的是算子接谱面**。

**接谱设计（推荐：双轨并存，process 门控）**：

- **轨道 A（遗产轨，v1-v3 冻结）**：GrainModule 现状逐字节冻结——存量档零漂移。
- **轨道 B（光谱轨，v4 候选）**：film sub-run 内新增 grain 段，位置 =
  stage B 的 develop 后、print_expose 前（上游座位 verbatim）。
  落点二选一（OQ-M83-4）：
  - B1（推荐）：拆 stage B 为 B1（develop → grain 缓冲）+ grain 四件套
    dispatch 组 + B2（print_expose → scan）。代价 = fused 链开一次口，
    中间面 = CMY 密度平面（float3 @100MP = 1.2GB——与 corr 场同量级，
    必须走 decimated 粒度或 tile 流，见性能预算）；
  - B2：grain 以"密度域调制函数"形态 fuse 进 stage B（每像素 Poisson 采样
    inline，无中间面；dye-cloud/clump blur 走 decimated 小面）。
    代价 = stage B kernel 重开（M8-1b 冻结面破一次，golden 重钉）。
  推荐 B1（结构诚实，blur 面独立可验证；B2 的 inline Poisson 让 B 的
  golden 调试面爆炸）。
- **数据面**：每 film 的子层表 (dmax/npart/dmin/curve) ——28 profile JSON 无此键
  （M8-2 DECISIONS 四：无 coupler/Langmuir 数据同族缺口）。granularity 标定
  （M9-2 T4）是每 film 单值 RMS，可作 npart 的反解锚（Poisson 方差 = D(Dmax−uD)/N
  → N 可解），dmax/dmin 从 density_curves 端点读，curve 从 density_curves 归一——
  即**子层表可从现有谱面 + granularity 标定派生，零新资产**（派生公式执行批钉，
  单层近似起步，多子层挂账）。
- **与 M9-2 标定的关系**：`recommendedStrength` 的语义从"遗产 kernel 强度"
  升格为"光谱 grain 的 amount 初值"（B 轨启用时面板一键应用改投 B 轨参数；
  量纲桥 = 遗产 strength∈[0,100] vs 上游 amount∈[0,8]，执行批标定）。
- **性能预算**：Poisson 采样每像素 ~13 hash（精确分支）或 4 hash（正态分支）+
  dye-cloud blur（σ<1，小核直接卷积）+ clump blur（σ~1-2，
  现有 `spectral_film_blur_row/col` 复用）+ USM（含 `pow()`——Metal `pow`
  精度与上游 OpenCL 同族问题，golden 带放宽到 1e-3 或共享多项式，OQ-M83-5）。
  全帧 @100MP 估计 +30-80ms（B1 中间面分配主导；decimate 后 +15-30ms）。
  默认 off（amount=0 早退，零中间面——D-M8-7 面板零新增的对应：grain 开关
  复用现有 GrainModule 面板？不——B 轨开关是 film 面板新控件，D-M8-7 修订案，
  OQ-M83-6）。

### 2.3 halation 接谱（宽模糊抽稀设计的主消费方）

**上游数学**（`sf_halation`，`spektra_core.c:790-900`）：

- **stage 1 scatter（乳剂内）**：core（per-channel 高斯，`sc_core[c]·scl/pixel_um`）
  + tail（三高斯混合：amp=[0.1633,0.6496,0.1870]，radius×=[0.536,1.5236,2.7684]，
  per-channel `sc_tail[c]`），core/tail 按 `w_s[c]` 混成 scattered 场，
  凸混 `(1−s)·raw + s·scattered`（s∈[0,1] 钳制——>1 进负权重鬼影，上游注释明示）。
- **stage 2 halation（背反射多弹跳）**：3 bounces，σ_k = first_sigma·hscl/pixel_um·√k，
  权重 decay=[1,0.5,0.25]/1.75，加性 `raw += a_tot·blur`（a_tot = per-channel
  strength × amount）。
- **参数源**：`sc_core/sc_tail/w_s/halation_strength/first_sigma_um` 全 per-film
  （pack `film_render_defaults[stock].halation`，缺席 = 通用 still/强抗光晕基线）。
- **座位**：linear 域，expose 后 develop 前（调用侧，印相前）。

**宽模糊抽稀设计（四 commit 读解正本，本批锚定参照）**：

| commit | 设计点 | 我方移植形态 |
|---|---|---|
| `bb3e11cd48`（OpenCL cleanup） | ① YVV 递归改增量形 `v=w1+(B(x−w1)+B2(w2−w1)+B3(w3−w1))`（DC 增益恒 1，B~2e-6 @σ126 时直接形的系数舍入曾把增益甩到 0.84-1.09）；② σ≥16 起抽稀：box 平均降采样 k=⌊σ/8⌋ → 精确核模糊降 σ → 双线性插回，降 σ 扣减 box 方差 (k²−1)/12 + 插值方差 k²/6；块网格锚定绝对图像坐标（tile 一致）；CPU/GPU 同序同运算（fma 钉死、host 建倒数表、CPU 循环防 fast-math 重排），CPU 路与 kernel 逐字转录 bit 一致 | YVV 我方无（corr blur 是精确核分离高斯）——只移植②抽稀臂。增量形教训记 OQ：若 M8-3+ 引入递归高斯，an 增量形起步 |
| `24109e85c1`（宽度匹配） | 抽稀模糊瞄准"递归路给同 σ 的方差"而非 σ 本身：`_yvv_ref_variance` 闭式（由 YVV 系数算 2(P²/S²+Q/S)，double），n 级联 pass 方差相加；实测递归路小 σ 偏宽 8-11%（5→5.56）、σ>120 偏窄（150→137.88） | 我方无递归路 legacy——**瞄准真 σ**（方差扣减只扣 box+插值两项）。但若 grain/halation 复用 Deriche IIR（我方 MaskCombiner 有 Deriche 基建），则宽度匹配纪律适用（OQ-M83-7） |
| `9fd80e6db3`（抽稀扩面） | `SF_WIDE_BLUR_EFFECT_SIGMA`=100px 阈值：diffusion bank + halation bounces 从此 σ 起走抽稀；<100 递归路误差 <5e-3 而抽稀真高斯与递归滤波器非高斯形差 ~1e-2（无收益）；≥100 递归路漂移 1.2e-2→5e-2（+均值偏 9e-3），抽稀路 ≤2e-4；默认 halation（15-35px）与中度 diffusion 全在阈值下 = 默认渲染零变化 | 阈值制直搬：我方默认 halation 同量级 → 默认面走现有精确核/Deriche，宽档走抽稀。阈值数值（100px）在 Metal 上重标（执行批 probe，OQ-M83-7） |
| `4d1fb6a95b`（拆双 kernel） | `wide_down` 拆 `wide_rows`（每块行求和，一 item 一（块列，图像行））+ `wide_down`（折叠行和，一 item 一块）：k=60-130 时单 item 读 4k-17k 像素 → 每 item k 读；运算与序不变，CPU 路仍 bit 一致；0179 集成测试 GPU 5.5s→10.3s 退化修复 | Metal 移植 verbatim：`spectral_film_wide_rows/down/up` 三 kernel + host `wideBlurPlan`（Swift 纯函数，`sf_wide_blur_plan` 同构）+ host 倒数表。并行度论证在 Apple GPU 同成立（threadgroup 占用） |

**halation 接谱落点**：film sub-run 外的前置腿（上游座位 verbatim）——
输入 = 主链顶面（pre-colorout float32 working-linear，即 film 腿输入面），
输出 = 同面（原地加性/凸混）。形态 = `SpectralPayloads` 新增
`dispatchHalationLeg(input:output:)`（stage A 之前调用；与 coupler arm 正交——
halation 在 lograw/develop_corr 上游）。per-film 参数表缺席（28 JSON 无
halation 键）→ 通用基线起步（still/强抗光晕两档，上游注释值转录，GPL
同许可），per-film 表挂 M8-3++ 资产批。

**性能预算**：默认档（bounces 15-35px）：精确核分离高斯 3 bounces × 2 pass，
@100MP 每 pass ~10-25ms → ~60-150ms（halation 默认 on 时；off 早退零成本）。
宽档（σ≥100）：抽稀路 k² 倍像素缩减（σ=300 → k=37 → 1369× 像素缩减，
降面模糊 79 tap 精确核 @降 σ<13）→ 宽档反而比中档便宜（上游同结论）。
ROI padding：halo 半径 4σ（上游 `modify_roi_in` padding 先例）——我方
film box 不入 tile 不变式下 = 全帧一次 dispatch，padding 恒 0（全帧面无 tile
缝）；若未来 film 腿入 tile，padding 纪律按上游 4σ（注记，不立项）。

### 2.4 diffusion 接谱（高斯 bank + 双座位）

**上游数学**（`sf_diffusion_build_plan` + `sf_diffusion_filter`）：

- **bank 构造**：core（2 分量）+ halo（3 分量，per-channel warmth 轴加权
  `SF_HALO_WARMTH_AXIS`）+ bloom（4 分量）≤ 11 分量；每分量 = 指数核
  exp(−r/λ) 的矩匹配高斯代理（σ=λ√3，二阶矩匹配；与 `SF_EXPTAIL_*` 混合的
  Σa·r²=2.988≈3 自洽）；`p_s` = strength→散射分数映射（族相关曲线）。
- **应用**：每分量独立高斯模糊原平面 → per-channel 权重累加成 scatter 场 →
  凸混 `(1−p_s)·in + p_s·scatter`。
- **双座位**：taking diffusion（linear 域，expose 后，halation 前）+
  print diffusion（print log 曝光域，print_expose 后 print_develop 前，
  上游 `spektrafilm.c:2484-2495`：pow10 → diffusion → log10 包夹）。
- **bloom 量级**：cinebloom/pro-mist 的 bloom 分量达 2500µm/1625µm
  （6000px 帧上 ~1000px）——这就是抽稀路 k=60-130 的来源工况。

**接谱落点**：taking 座位与 halation 同腿（前置腿内序：boost → diffusion →
halation，上游序 verbatim；boost/glare 不入 M8-3+，座位预留不同时上）；
print 座位 = stage B 内 print_expose 后（B 拆口与 grain 同——B1/B2 拆分一次
容纳 grain + print diffusion 两个插入点，OQ-M83-4 联动）。
族表（4 族 diffusion family 参数）GPL 同许可转录（数值表 + 权重公式，
归属纪律）。

**性能预算**：bank ≤11 分量 × 每分量 2 pass 分离高斯 = 最多 22 pass；
默认档分量 σ 小（精确核）但分量多 → @100MP ~100-250ms（diffusion 默认 on
时最重——默认 off 起步，OQ-M83-6）；宽分量走抽稀后单分量 <10ms。
内存：bank 累加需 acc 平面（float3 @100MP = 1.2GB）+ comp 平面——与 corr 场
同族，必须 decimated 粒度或分量流式（acc 在降面累加后上采样——精度纪律：
累加在降面做 vs 全面做的差 = 上采样插值误差 ~1e-3，golden 带登记）。

### 2.5 三算子与 film sub-run 缝的总装图

```
主链顶面（pre-colorout float32）
  │ ① 前置腿（新增，SpectralPayloads.dispatchSpatialPreLeg）
  │    taking diffusion（bank）→ halation（scatter+3 bounces）
  │    [boost/glare 座位预留，不入 M8-3+]
  ▼
stage A（expose+lograw+corr 生成 @降面）→ corr blur → ┐
stage B1（develop → CMY 密度平面）                        │ B 拆口（OQ-M83-4）
  │ ② grain 四件套（Poisson 采样→dye blur→累加→finalize→add→clump→USM）
  ▼                                                      │
stage B2（print_expose → [print diffusion] → print_develop → scan）
  │ ③ strength mix（现状）
  ▼
film 输出 → DRT tail → display replay（现状零改）
```

seed/缓存键影响：前置腿与 grain 段的参数（amount/σ族/family）必须折 seed
（`solvedPackHash` 语义扩 或 recordHash 经 FilmRecord 新字段——OQ-M83-6 联动：
若算子参数走 FilmRecord 新字段，recordHash 自动折 + sidecar bump；
若走独立载体，需新 seed 项——推荐前者，与 paperGrade/cameraFilter 先例一致）。
bake 键：grain 子层表（派生自谱面+标定，pair 确定）不新增长期键；
halation/diffusion 参数是运行时的（非 build 期表）→ 只折 solve seed，
不折 bake 槽键（与 strength 同——运行时 uniform 面）。

---

## §3 m-6① + 时长维机理

### 3.1 m-6①：undo 腿未重走——源码面已闭合，无需修

R8 实测"⌘Z 撤销旋转后视口仍黑"（`36b`），R9 解释为冷 build 窗瞬态但未重走
undo 腿（m-6① 挂账）。本研究源码亲核：

- `PipeCoordinator.undo()`（`:2044-2048`）：`performUndo()` → 双 carrier
  同步（`syncDrtCarrierWithHistory()` + `syncFilmCarrierWithHistory()`）→
  `historyDidChange()` → 重渲染。redo/jump 同构。**film carrier 在导航面
  与 history 真相同步——undo 的 film 腿在位**，无 R8 假说的"film leg 转置错帧"
  残留面（R9 D-R9-2 机检已脱罪）。
- R8 的"undo 不恢复"在 R9 时间线下自洽：CW90 提交 → 渲染挂起在 4-5 分钟 tc
  冷 build 窗 → 20s 内 undo → 重渲染仍挂同一 build 窗 → 仍黑。不是 undo 腿坏，
  是 undo 后的渲染与 undo 前的渲染挂在同一个未完成的 build 上。
- **M8-3+ 动作**：零代码。验收批补一条"undo 腿实测"（冷 build 窗外 undo →
  即时恢复），关闭 m-6①。附带：`syncFilmCarrierWithHistory` 与
  `syncDrtCarrierWithHistory` 的双调用序在 undo/redo/jump 三面一致——
  无序依赖风险（两 carrier 正交域）。

### 3.2 时长维：2 分钟写腿差异——机理假设（可证伪）

R8 实测"启用胶片 2 分钟未落盘"（vs 旋转/crop/曝光秒级），R9 降为 obs
（R9 侧落盘正常 items 3）。本研究源码亲核写腿链：

- 启用链：`enableFilm()` → `recordFilmChange`（history commit + `notifyFilmChange`）
  → `filmRecordDidChange`（`:833-838`）：`syncFilmCarrierWithHistory()` →
  `await historyDidChange()`（**重渲染，全 await**）→ `scheduleSidecarWrite()`。
- 关键序：**sidecar 写排在重渲染之后**。film 启用触发的重渲染 = 含 4-5 分钟
  tc 冷 build 的光谱腿（R9 D-R9-1③：C200 278s）。`historyDidChange()` 在
  MainActor 上 await build → `scheduleSidecarWrite()` 被饿死至 build 窗后。
  旋转/crop/曝光的重渲染是毫秒级 → 写秒级落盘。**机理假设：写腿饥饿
  （render-await starvation），非写腿缺陷**。
- 证伪面（执行批机检，不用猜）：oslog/探针日志取"启用胶片 commit 戳" vs
  ".lra mtime 戳" vs "tc build 完成戳"三戳对账——若 .lra mtime ≈ build 完成戳
  +2s 去抖，假设成立；若 .lra mtime ≈ commit 戳 +2s（R9 侧观测），则 R8 轮是
  观测问题（`ls` 时机/去抖窗），假设不成立。
- R8/R9 观测分歧的解释：R9 探针轮可能命中 tc 缓存（同 pair 二次 build = HIT，
  秒级）→ 写正常；R8 首轮冷 build → 写饿死。两轮都是真实现象，条件不同。
- **修法候选**（OQ-M83-8）：A. 写腿前提（`scheduleSidecarWrite()` 移到
  `historyDidChange()` 之前——commit 即调度，渲染饿不死写；2s 去抖本来就容忍
  渲染中途的写，LAST-write-wins 语义不变）；B. 维持现状（写饿死 ≤ build 窗，
  build 窗后自恢复——R9"瞬态"口径的延续）。推荐 A（单行移动，
  语义零漂移——去抖合并本来就不是"渲染完成后才写"的语义）。

---

## §4 性能预算总表（100MP 全帧，M8-3+ 全开上限）

| 段 | 形态 | @100MP 估计 | 默认面 |
|---|---|---|---|
| 现行光谱腿（A/B/mix） | 存量 | ~40-160ms（M8 RESEARCH §4.1） | 常开 |
| C200 修法第一段（锚 seed） | build 期 CPU | build 加速（32→~8 轮，省 ~50% Newton 时间；Newton 占 build 小头——tc LM 全网格是大头 269-278s，见 R9） | 常开 |
| C200 修法第二段（守恒回退） | build 期 CPU | +1D 线搜索（~ms 级，可忽略） | 仅 clamped 对 |
| grain（B1 拆口 + 四件套） | GPU + 1 中间面 | +30-80ms（全面）/ +15-30ms（decimated） | 默认 off，早退零成本 |
| halation（默认 15-35px） | GPU 3 bounces | +60-150ms（on 时） | 默认 off（OQ-M83-6） |
| halation（宽档 σ≥100） | GPU 抽稀路 | 单 bounce <10ms | 同上 |
| diffusion taking（≤11 分量） | GPU bank | +100-250ms（on 时最重） | 默认 off |
| diffusion print（bank 子集） | GPU bank @B2 | +50-120ms | 默认 off |
| 写腿前提（OQ-M83-8 A） | CPU 序调整 | 零（单行移动） | 常开 |

RSS 门：grain CMY 中间面（1.2GB）+ diffusion acc/comp（2.4GB）+ corr 场
（降面 19-75MB）+ 现行腿面——全开同时存在 = 超 8G 门风险。纪律：三算子中间面
**串行复用**（前置腿面 → 释放 → grain 面 → 释放 → B2 面，同一分配器槽位），
峰值增量 ≤ max（单面）= 2.4GB（diffusion acc+comp）——执行批分配器纪律
（OQ-M83-9）。默认全 off 时峰值增量 = 0。

---

## §5 golden 真值源与验证形态

1. **C200 修法 golden**：真 build 双值（solvedPrintCC + clamped + 灰误差 +
   print 表蓝切片 hash）修前修后对照；14 安全档 solvedPrintCC 逐位零漂移；
   portra 真照片对照腿（m-3③ 关闭——验收面）。
2. **grain golden**：合成净密度灰阶 ×（遗产轨/光谱轨）双臂输出 hash +
   Poisson 统计门（均值/方差 vs λ·p·od·sat 理论值，χ² 带）+
   CPU/GPU bit-exact（grain.h 纪律移植：共享多项式/`grain_exp_neg`/
   plain sqrt——上游真实分歧案例三件同款防护）。
3. **halation/diffusion golden**：合成点源/边缘场 ×（精确核/抽稀路）双臂
   （抽稀阈值两侧各一腿）+ 上游 `sf_wide_blur_plan` 数值对表
   （k/σ_low/lw/lh/ox/oy 逐值——GPL 同许可转录件对拍形态，M8 测试策略门 1
   同款）+ CPU 参考（Swift Float64 `wide_down/up` 转录）vs Metal 逐位。
4. **m-6①/时长维**：undo 腿实测（窗外 undo 即时恢复）+ 三戳对账机检
   （commit/build/lra mtime）。

---

## §6 OQ 清单（9 条，全带推荐值）

| OQ | 问题 | 推荐 | 理由一句 |
|---|---|---|---|
| OQ-M83-1 | 触墙降级三选一：①白名单 disclosed / ②守恒回退 / ③销档 | **② 守恒回退**（墙内最优 + 通道仿射归一） | ①诚实但 3% 误差留存，③把默认对销档不可接受；②安全档零漂移 + 误差预期 <0.5% |
| OQ-M83-2 | 钳制域 [0,250] 动否 | **不动**（物理 dial 域诚实面） | 证据 B：墙外无光，扩域是安慰剂 + 静默坏态风险 |
| OQ-M83-3 | 反转×印相纸路由：A 同求解 / B 正片直印语义 / C 配对隐藏 | **B + C 配套** | A 的 velvia 残差 18% 是语义错不是 bug；B 语义诚实，C 收敛 UI |
| OQ-M83-4 | grain/print-diffusion 插入：B1 拆 B / B2 fuse 进 B | **B1 拆 B**（B1 develop → grain → B2 print/scan） | B2 让 B 的 golden 调试面爆炸；B1 一次拆口容纳两插入点 |
| OQ-M83-5 | USM `pow()` 精度：放宽带 1e-3 / 共享多项式 | **共享多项式**（X5 三板斧延续） | 上游已知 16 ULP 残留；我方 X5 纪律已建多项式基建，放宽是倒退 |
| OQ-M83-6 | 三算子 UI 面：默认 on/off + 参数载体（FilmRecord 新字段 vs 独立载体） | **默认全 off + FilmRecord 新字段**（recordHash 自动折 seed，sidecar bump，paperGrade/cameraFilter 先例） | D-M8-7 修订案：核换代不改面板，但这是新算子不是核换代；新字段 = seed/sidecar/面板三面一次对齐 |
| OQ-M83-7 | 抽稀阈值/宽度纪律：100px 直搬 vs Metal 重标；瞄准真 σ vs 递归路宽度 | **Metal 重标阈值 + 瞄准真 σ**（无递归 legacy）+ 若复用 Deriche 则宽度匹配纪律适用 | 上游 100px 是 float-YVV 误差曲线的交点，我方误差曲线不同；瞄准真 σ（无 legacy 要兼容） |
| OQ-M83-8 | 写腿饥饿：A 写腿前提 / B 维持现状 | **A 写腿前提**（`scheduleSidecarWrite()` 移到 `historyDidChange()` 前） | 单行移动，去抖 LAST-write-wins 语义零漂移；B 让每次冷 build 饿写 5 分钟 |
| OQ-M83-9 | 三算子中间面分配器：串行复用槽 vs 独立分配 | **串行复用槽**（峰值增量 ≤2.4GB） | 独立分配全开超 8G 门；复用纪律执行批落分配器单源 |

---

## §7 process 号与 sidecar 影响

- **C200 修法**：第一段（锚 seed）= 同值加速（solvedPrintCC 逐位不变）→
  零 bump；第二段（守恒回退）只改 clamped 对（现行 clamped 对渲染 = 偏色坏态，
  无"正确旧观感"可守）→ **v3 内 additive**（坏态修复非观感变更，M8-FIX-1 先例
  口径）。反转 B 语义（OQ-M83-3）改反转档渲染面 → 若反转档已有用户存量，
  需 process 门（v4 候选，见下）。
- **三算子**：默认全 off = 缺席恒等（nil-face 零漂移，M9-2 先例）→ v3 内
  additive；但算子 on 档的渲染面是新语义 → 建议 **process v4 预留给"三算子
  on 档的语义冻结"**（mint 不升，v4 = 算子语义代际，OQ-M83-6 的 FilmRecord
  新字段缺席 = v3 语义恒等）。
- **sidecar**：FilmRecord 新字段（grain/halation/diffusion 参数，OQ-M83-6）→
  **schema v13**（M9-2 v12 先例：additive 字段批走 bump）；`clamped` 标志不入
  sidecar（build 派生面，重建可复得）。

---

## §8 Sources

### 我方正本

- `.work/gsd/phases/r9-repairs/R9-{SUMMARY,DECISIONS}.md`（C200 定罪 + m-3/m-6）
- `.work/gsd/phases/r8-repairs/R8-ACCEPTANCE-OMP.md`（M-1 原表型 + 2 分钟 obs）
- `.work/gsd/phases/m8-fsim-spectral/`（CONTEXT D-M8-4/D-M8-7/D-M8-8 +
  M8-2/M8-3-DECISIONS + RESEARCH §1 上游数学）
- `.work/gsd/phases/m9-2-bwspectral/`（RESEARCH §1-4 + DECISIONS §1/§2 +
  SUMMARY——同管线最近交付形态）
- `LightamerCore/Sources/Film/SpectralBuildEngine.swift:708-750`（Newton 梯）
- `LightamerCore/Sources/Film/SpectralConstantsData.swift`（dichroic/SPD 表）
- `LightamerCore/Sources/Pipe/Film/{FilmTailPolicy,SpectralPayloads}.swift`
  + `SpectralFilmKernels.metal`（film 腿 dispatch 链）
- `LightamerIOP/Sources/Grain/`（GrainModule + GrainCalibration + kernels）
- `App/Sources/Lightamer/State/{PipeCoordinator,EditorState}.swift`
 （写腿/undo 腿）+ `LightamerCore/Sources/Sidecar/SidecarStore.swift`（2s 去抖）
- `Resources/FilmProfiles/{neutral_print_filters.json,profiles/28}`（谱面数据）

### 上游（dt，GPL-3.0 只读，本批 `4d1fb6a95b` 树；本地 master 同步）

- `4d1fb6a95b`（拆双 kernel：wide_rows + wide_down 并行度修复）
- `9fd80e6db3`（抽稀扩面：SF_WIDE_BLUR_EFFECT_SIGMA=100px + 误差对照表）
- `24109e85c1`（宽度匹配：`_yvv_ref_variance` 闭式 + 级联方差相加）
- `bb3e11cd48`（OpenCL cleanup：YVV 增量形 + 抽稀首版 + opencl-diffstat 实测表）
- `src/common/spektra_core.{h,c}`（`sf_halation`/`sf_diffusion_filter`/
  `sf_wide_blur_plan`/`_wide_down3`/`_wide_up3` 全文）
- `data/kernels/{spektrafilm.cl,grain.h}`（五 grain kernel + wide 三 kernel +
  Poisson/粒子采样数学）
- `src/iop/spektrafilm.c:20-60`（管线座位头注）

### 方法学注记

- 静态复演脚本未落盘（research lane 纯文本纪律；执行批按 §1.2 方法段 30 行重建，
  输入 = Swift 源码正则抽取 + profile JSON，输出 = 本文件 §1.2-1.3 全表）。
- 本文件零源码引用转录（定位引用 + 数值结论），GPL 合规面干净。

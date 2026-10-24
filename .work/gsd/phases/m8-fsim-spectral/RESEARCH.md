# M8-1 RESEARCH — FSIM 光谱升维（Spectral Film Core）

> 正式 research 环交付（取代 `RESEARCH-PRE.md` 的预告底稿地位；PRE 的 §2 三分口径 /
> §3 数学草案 / §7 OQ 推荐被本版**全量消读后落实、细化或修正**——修正处以
> 「PRE→本版」标注，PRE 原文按惯例不改）。日期：2026-10-24。
> 纪律：上游 darktable spektrafilm 模块族 = **GPL-3.0 同许可可移植**（2026-10-20
> 切换；保留版权 + 许可证文本 + 标注修改），本版为**逐段读解正本**（file:line 定位），
> 移植批再按 GPL 归属纪律落 NOTICE。
> 外部输入：本地 darktable 克隆 `src/iop/spektrafilm.c`（6314 行）+
> `src/common/spektra_sim.{c,h}`（5391+722）+ `spektra_core.{c,h}`（915+236）+
> `spektra_fetch.{c,h}`（1667+186）+ `data/kernels/spektrafilm.cl`（1163）+
> 单测 `test_spektra_sim.c` / `test_spektra_pack.c` + 集成测试 `0179-spektrafilm`，
> 全文消读；我方侧 = M3 族全部正本 + 产线源码逐文件核对。

---

## §1 上游管线数学全量摸清（逐段读解正本）

### 1.1 全链与分域（spektrafilm.c:19-60 模块头 + spektra_sim.h:39-56）

```
work RGB (D50 相对线性)
 ① expose:     m_in(CAT16·rgb2xyz) → xyz → xy → tri2quad → tc LUT 2D cubic
               fetch(float3 曝光) → ×Y×2^ev                    = 胶片曝光
   [调用侧] highlight boost → diffusion → scatter/halation（线性域，空间）
 ② lograw:     log10(raw + 1e-10)
   develop_corr: 曲线查表(silver) → 3×3 coupler 矩阵 → corr 场
   [调用侧] corr 高斯核 20µm + 可选指数尾(3-gaussian 混合)模糊
   develop:    (lograw − corr) → 曲线查表                      = CMY 胶片密度
   [调用侧] grain（密度域，空间）
 ③ print_expose:   3D 表(PCHIP)或逐像素 81 波长积分 → log 印相曝光
   [调用侧] print diffusion（可选）
   print_develop:  曲线查表                                    = 相纸密度
 ④ scan:       3D 表或逐像素积分 → log XYZ → 10^x →(可选 boost/黑白点线性拟合)
               → m_out(CAT02·xyz2rgb) → OkLCh gamut 压缩 → out_scale = work RGB
```

五个引擎 stage（`sf_sim_expose/lograw/develop_corr/develop/print_expose/
print_develop/scan`，spektra_sim.h:651-704）全部**纯逐像素**；空间效果
（grain/halation/diffusion/boost/glare/blur）全部在调用侧 `spektra_core`
（spektra_sim.h:31-37 头注释明确「intentionally not in this engine」）。dt 模块
定位 = **scene-to-display view transform，替代 sigmoid/filmic/agx 启用**
（spektrafilm.c:54-55）——我方对应物 = film sub-run 位置语义（grades 后 DRT 前），
双链正交，PRE §4.1 结论维持。

### 1.2 光谱上采样（expose 前半）——tc LUT 的精确数学

- **tri2quad**（spektra_sim.c:1719-1727）：`u=(1−x)²`、`v=y/(1−x)`——把全色度
  平面（光谱轨迹内部含）映射到单位方；逆变换 quad2tri:1756-1762。PRE §3.1 记述
  正确。
- **sigmoid 谱模型**：`hanika_sigmoid(z,max) = z/√(1+(z/max)²)`（软界代数
  sigmoid，spektra_sim.c:1732-1737）——注意这是 dt 侧**只用于 surface 修正的
  限幅**，谱重建本身在 pack 的 spectra 表里（192²×81 f32，构建期已由上游
  exporter 拟合好），**dt 运行时不含 Jakob-Hanika 拟合代码**。这修正了 PRE §3.2
  的一个隐含印象：上游 tc 表 = 预重建谱（每 cell 存完整 81 波长谱，非三系数），
  我方自拟合可在「每 cell 三系数 + 构建期展开成谱」与「直接拟合谱表」两条路里选
  （OQ-M8-2 细化，见 §6.2）。
- **per-sim tc LUT 构建**（spektra_sim.c:3664-3861，`sf_sim_build` 拍摄段）：
  1. `sens_w = 10^log_sensitivity`（81×3，spektra_sim.c:3677-3683）；
  2. **adaptation_bandwidth**（erf4 谱窗，白平衡保持）：窗函数折进 sens_w 后逐
     通道再归一（3689-3712）；
  3. 逐 cell 积分：`tc_lut[i,j] = Σ_l spectra[l]·sens_w[l]`（3716-3734，
     irradiance kind）——**81 波长循环只在此发生，每 sim 一次**；
  4. reflectance kind：先 `spec×E_ref` 重打光（3727）、再按表自身场景白经
     Mitchell cubic 采样出的中性逐通道归一（3745-3775，注意中性取值必须走与
     运行期相同的插值器，2003-2036 注释）；
  5. **adaptation_surface**（默认关）：逐 cell 15 系数 deg4 多项式（常量项弃，
     spektra_sim.c:1743-1754）→ hanika sigmoid 限幅 ±2 stop → `×2^stops`
     （3801-3824）；
  6. **输入 gamut 压缩 remap**：`new[tc]=old[compress(tc)]` 径向 xy Reinhard
     (0,1,6) 压向光谱轨迹多边形（3826-3851 + 1778-1847）——**预折进表**，运行期
     零成本；
  7. float 副本（3852-3860）。
- **运行期 expose**（spektra_sim.c:3363-3406 / NEON 批 4664-4702）：
  `m_in·rgb → Σxyz=Y → xy=(X/Y, Z/Y 互倒一次) → tri2quad → 16-tap Mitchell
  cubic gather（B=C=1/3，反射边界）→ ×Y×ev_scale`。**逐像素无 81 波长循环**——
  PRE §3.1 的「积分预折」判断全文消读后确认。
- m_in = `CAT16(input_white→proj_xy) · input_rgb_to_xyz`（3657-3661）；proj_xy =
  胶片参考光源 xy（irradiance）或表场景白（reflectance，3636-3656）。

### 1.3 显影（DIR coupler）——唯一链内空间步

- **coupler 矩阵**（spektra_sim.c:3992-4031）：3×3 = 同层 γ 对角 + 层间 γ 项，
  ×inhibition ×amount；B&W 单乳剂塌缩为 3 同值对角（4013-4016，含 1.79x/2.28x/
  1.87x 列污染教训注释）。
- **Langmuir 饱和 coupler**（dev/0.4+ packs，4033-4100）：供体侧
  `g(D)=D(K+Dref)/(K+D)`（负片，K=k·dmax、Dref=dmax/2）；接收侧
  `S(c)=c(Kr+cref)/(Kr+c)`（正片，在扩散模糊**之后**应用）；Kr=0 → 1e30 线性
  哨兵（4076-4085 NaN 防御）。
- **corr 场生成**（4733-4768）：逐像素 silver（正片 = dmax−d）×矩阵；**模糊在
  调用侧**（spektrafilm.c:2219-2257）：高斯核（pack 每胶片 `coupler_diff_um`，
  默认 20µm）+ 可选指数尾 = 3-gaussian 混合近似（A0/A1/A2=0.1633/0.6496/0.1870，
  R0/R1/R2=0.536/1.5236/2.7684，spektra_sim.h:419-426）——CPU 路把 corr 复制
  4 份分别模糊再加权混合（spektrafilm.c:2232-2249）。
- **develop**（4770-4801）：`(lograw − corr) → 256 点 log-exposure 网格 1D 线性
  查表`（curves_norm 无 coupler / curves_before 有 coupler 两套）。曲线本体 =
  pack 每胶片 `density_curves[256][3]`（可含 n≤8 子层曲线模型
  sf_curves_model_t，spektra_sim.c:335-341），build 期归一化（去 mn）+
  可选 push/pull / developer exhaustion morph（3867-3912）。

### 1.4 印相（enlarger）——dichroic 配光 + 相纸感光

- **dichroic CC 滤光**（spektra_sim.c:2976-2989）：
  `illum_print[l] = src[l]·Π_c(1−(1−F[l][c])·(1−10^(−cc_c/100)))`——81 波长
  一次，build 期。
- **中性配平**（midgray，4203-4250）：build 期取 sRGB 中灰 0.184
  （SF_MIDGRAY:113）经 sRGB 矩阵（**非工作空间**，3410 注释）跑一遍链头得中灰
  密度谱，再以印相曝光的**几何均值**归一（exposure_factor:3441-3454）；
  normalize/compensation 两开关四分支（4242-4249）。→ 我方 M3 的 K 标定同构物。
- **preflash**（4251-4260）：穿过 base_density 的一次性印相曝光。
- **enl 表**：build 期 `build_lut3d(cmy_to_print_lograw, enl_lo=[−grain_floor],
  enl_hi=[nanmax curves], 33³)`（4541-4548 + 4262-4271）——`cmy_to_print_lograw`
  = **81 波长精确积分**（2997-3016：`Σ_l illum_print·10^(−(base+Σchan·cmy))·
  print_sens`），33³=35937 次积分每 sim 一次。运行期 = 单调 PCHIP 3D 插值
  （2137-2247：8 cell hermite + 预备 slopes/cmin/cmax 钳位表）+ 印相曝光在 log
  域加 `log10_print_exposure`（4847-4852）。精确臂（lut_steps=0）逐像素重积分仅
  CPU 参考/GPU 不可达（spektra_sim.h:246-252「exact spectral has no GPU path」）。

### 1.5 扫描（scan）——观察光源 × CMFs → 工作空间

- `cmy_to_log_xyz`（3071-3086）：`Σ_l illum_view·10^(−(scan_base+Σchan·cmy))·
  CMFs[l] / xyz_norm` → log10——同构 81 波长积分，同样 build 期折 33³ scan 表
  （4590-4596）。
- m_out = `output_xyz_to_rgb · CAT02(view_xy→output_white)`（4332-4342）；
  view_xy 从观察光源 SPD×CMFs 导出（4293-4338）。
- **输出 gamut 压缩**（OKLCH 默认）：build 期 C_max(L,h) 表（64×720，每格 18 次
  二分求输出 RGB 立方内最大 chroma，3144-3178）；运行期 OkLab（cbrt 族）→
  **lightness knee(0.7,1,2.2) 先、chroma knee(C/C_max; 0,1,6) 后**（3215-3243，
  顺序注释 3232）；备选 ACES RGC 逐通道膝（3251-3262）。
- **黑白点拟合**（build 期，4345-4530）：正片扫描 / 负纸印相两臂——胶片两端密度
  穿链得 Y_black/Y_white，线性拟合 scan_bw_m/q + 中灰回位曝光修正（折叠进
  log10_print_exposure 或 ev_scale）。默认关。
- **ev_scale_f 最后取**（4532-4538）：所有 build 期曝光修正落定后才有 float
  副本——GPU/CPU 一致性教训（注释记载真实 CPU/GPU 分歧案例）。

### 1.6 CPU/GPU 双路与 bit-exact 纪律（spektrafilm.cl + host 注释族）

- **34 个 kernel**（spektrafilm.c:652-689）：per-pixel 色科学 7 个
  （expose/lograw/develop_corr/develop/print_expose/print_develop/scan）+ 空间
  效果族（grain 5 / yvv-gauss row-col ×4c/1c 8 / scatter/halation/boost/
  diffusion 6 / usm/glare/crop/passthrough 6+）+ stage 分解（每 stage 独立
  dispatch，中间 plane float4）。
- **GPU 表载体** = `sf_sim_gpu_t`（spektra_sim.h:253-335）全 float 集合：m_in/
  m_out/couplers/rgb2xyz/xyz2rgb/oklab×4 矩阵（cl 侧 93-float 常量块，
  spektrafilm.cl:78-89）+ tc_lut(192²×3 f32=442KB) + 两套 33³ PCHIP
  （lut+slopes×3+cmin/cmax，每套 ≈2.5MB，spektrafilm.c:2098-2106 tiling
  overhead 计算）+ 曲线/黑白点/语言参数。**表全部 build 期构建、运行期只读**。
- **bit-exact 三板斧**（移植我方 Metal 时必带）：
  1. `#pragma OPENCL FP_CONTRACT OFF` 在设备编译器上**无效**——所有矩阵/累加
     显式 `fma()` 钉形（spektrafilm.cl:91-103 注释：host 真 honoring
     `-ffp-contract=off`，device 不 honored，裸 `a*b+c*d` 会差 1 ULP）；
  2. 倒数在 host double 算一次 rounded to float（`inv_le_step`/
     `enl_inv_range`/`scan_inv_range`，spektra_sim.h:262-266/278-282——on-device
     重.derive 是**已发生的真实 CPU/GPU 分歧源**）；
  3. log10/pow10 走共享自定义多项式（`grain_log2f/exp2f`，host 与 cl 编译同一
     头文件 grain.h）而非 libm/设备内建——内建 ≤3ULP 差异会被 grain Poisson
     采样放大成整数值差（spektrafilm.cl:251-265）。我方无 grain 但曲线查表分段
     边界同理敏感。
- **NaN 硬化**：cubic_base_fraction 对 NaN 落低支（spektra_sim.c:1897-1927）；
  expose 的 Y=0/非有限 → xy=0 ×bb=0（3394-3405）。POCL 对 CPU 验证 ~1e-6
  （spektrafilm.c:57-60）。
- **验证基座**：单测 `test_spektra_sim.c`（stage 级双臂对照）/ 
  `test_spektra_pack.c`（容器/头解析）/ 集成 `0179-spektrafilm`（端到端 XMP）。

### 1.7 空间效果面（M8 不消费，挂账）

`spektra_core`：grain（多子层 Poisson 采样 + dye-cloud blur + clump blur +
乘法 USM 四件套）、halation（双 stage：emulsion scatter 核+尾 / 背反射多弹跳）、
diffusion（4 族 Gaussian bank ≤11 分量）、highlight boost、glare、YVV 递归
高斯（σ>150 float32 系数发散教训，spektra_core.h:188-209）。dt 为此扩 ROI
（`modify_roi_in` padding = 4σ×最宽 halo，spektrafilm.c:2023-2052）+ tiling
factor 6.5/9.75（2054-2109）。我方 M8 v1 不入（PRE OQ-M8-4 维持），但 grain/
halation 作为 v2 挂账项的**空间效果与色科学分离**结构对本项目是直接可搬的
架构事实（我方 equivalents 已有独立基建：grain 挂 dt 遗产面，halation 未建）。

---

## §2 数据包形态、体积与分发（spektra_fetch + sf_pack_t 实测）

- **pack 目录** = `pack.json` + `spectra_lut.f32` + `profiles/`（每 stock 一
  JSON）（spektra_fetch.h:24-31）。两处安装位：用户手装顶层优先、下载缓存
  `packs/<hash>/`（37-44）。
- **表文件**：32 字节头（int32 dims[3] + int32 dtype + uint32 lut_hash +
  int32 id_len，spektra_fetch.c:300-345）+ `192×192×81` f32 谱 = **≈11.97MB**
  （「~12 MB」spektrafilm.c:627-629 注释一致；侧读上限 SF_TC_N_MAX=4096，
  spektra_sim.h:70-74）。**pack 总体积 ≈ 12MB LUT + ~5.6MB profiles（我方同款
  28 张实测）+ pack.json ≈ 18-20MB**——PRE「tens of MB」的精确化。
- **pack.json 键**（spektra_sim.c:291-333 消费侧反推）：`pack_format`
  （容器版本 2/3，MIN/MAX 门 spektra_sim.h:98-99）+ `pack_hash`（整包身份）+
  format 3 起表声明（identifier/lut_id/kind/scene_illuminant，≤SF_MAX_TABLES=8
  张）+ 常量集：wavelengths[81]、log_exposure[256]、cmfs[81][3]、spectral
  locus 多边形、illuminants 名→SPD[81]（hash 表）、dichroics 品牌→[81×3]、
  neutral_filters 数据库（pack/print/film 三键 CC 三元组，
  sf_pack_neutral_filters spektra_sim.h:203-209）、film_defaults（每胶片 coupler
  γ/halation/grain/coupler-diffusion/Langmuir 预设）。
- **身份纪律**：`lut_hash`（表内容哈希）= 编辑档记录的渲染身份；`pack_hash`
  （整包）= 「编辑对着哪个包开发」——表可跨版字节不动而 profiles 移动，故双哈希
  （spektra_fetch.h:42-47）。编辑档 mismatch = 警告 + 换默认表渲染而非黑帧
  （spektra_sim.h:583-592 + spektrafilm.c:1848-1886）。**我方对应物 = process
  number + record stableHash，语义同构**（§4.2）。
- **分发**：`darktable-org/darktable-spektrafilm` 数据仓（packs + 下载 manifest +
  exporter `tools/spektrafilm_export_data.py`，spektrafilm.c:44-48）；模块内置
  后台下载（libcurl，sf_fetch 状态机 + generation 计数器，spektra_fetch.h:112-175）。
  本地无克隆（2026-10-24 核）；**许可待验面维持 PRE OQ-M8-2 判断**：LUT/常量集
  = dt 生态产物（GPL 侧），profiles/ = CC BY-SA 同款（我方已有）。**自拟合路线
  下的净需求**（§6.2 OQ-M8-2 细化）：CMFs CIE 1931 2°（公开标准）、D 系列光源
  SPD（公开公式）、TH-KG3/ENL 光源 SPD 与 dichroic 曲线（公开描述 + 近似自建，
  值域 sanity 带参照 dt pack）、locus 多边形（由 CMFs 导出）——即**自装配常量集
  + 自拟合表，零 GPL 数据依赖**，dt pack 仅 sanity 带参照。

---

## §3 我方缝位（产线源码逐点核对）

### 3.1 位置与缝：零改结论维持（PRE §4.1 逐点落锚）

- film sub-run = `runTerminalTails`（PixelPipe.swift:1145-1192）①位——
  `filmTail` 非空即 `runFilmLeg`（1207-1254：stats → solve → payload → 子管线
  runSub）→ ② DRT tail → ③ display replay（1377-1402）。光谱核替换的只是
  `assembleFilmLeg`/`assembleFilmPayloads`（1262-1367）工厂的**臂**与
  `FilmMethodBox` 消费的 kernel；三 leg 编排/seed 折叠
  （FilmTailPolicy.swift:100-112）/3×2 降出矩阵/导出递缝（`$jobFilmTail`）全部
  零改。
- `FilmMethodBox`（FilmTailPolicy.swift:197-331）：iopOrder 74.0 单 box 子管线、
  `runPayloads` 实例载体（M5-1-03 并发修复后形态）、nil payload = blit identity
  degrade——光谱核同构复用（payload 集换形）。
- `FilmStatsSeam`/`FilmSolveCache`/`FilmRuntimeSolve`（FilmTailPolicy.swift:
  411-657）：key = `fnv(materialPairHash ⊕ statsHash ⊕ modeTag)`、AUTO 核缓存 +
  record 项消费层叠加、`invalidateAll()` 面板缝——光谱域求解换内核、键形不变
  （modeTag 扩光谱段，§4.3）。
- `FilmPrintBake`（FilmPrintBake.swift:51 level=65，Float64 CPU +
  concurrentPerform + per-pair LRU）——光谱印相/扫描表的 bake 机制家族同位替换。
- `FilmPlacementModule`（20.8，film 腿上游）零改。
- 宽容度 descriptor：`FilmDescriptorProbe` 走 `assembleFilmLeg` **同工厂**
  （PixelPipe.swift:1222 注释「the descriptor probe constructs through the SAME
  path」）——核换臂后 probe 自动跟随，ISO 6846 归约/面板数学零改
  （FilmDescriptor.swift:8-38）。`ProfileLatitudeDescriptor.response` 语义 =
  print reflectance luma，光谱核下读数变、面不变。

### 3.2 process version 双臂（M6-2 首个真实分叉）

- 机制现状：`RenderProcess` 账本 = `[.v1]`、`current=1`、`resolving` clamp 表
  （RenderProcess.swift:107-150）；sidecar `process` 键 v10 起在册
  （LightamerSidecar.swift:385，v11 现行）；子管线继承
  （PixelPipe.swift:1242/1395 `filmPipe.renderProcess = renderProcess`）；
  **产线尚无任何语义消费点**（KD-5 缝已武装零行为）。
- M8 分叉形态（`RenderProcess.swift:109-115` 的 v2 case doc-comment 即预案）：
  追加 `.v2` → `all=[.v1,.v2]` → `current=2` → 分叉点（film leg 组装）exhaustive
  switch：`.v1/.legacy` = 密度核（**冻结 legacy 臂**——密度核代码与 65³ bake、
  FilmFilterPackSolver、film_subrun kernel 全保留）；`.v2` = 光谱核。缓存折键按
  「非 legacy 才折」契约（RenderProcess.swift:37-44）：光谱臂 seed 折
  `process` 段或光谱 policyTag（charter 钉折叠序 + 负测——legacy 档键字节恒等）。
- 账本五件套随 v2 批交付（case doc / AGENTS 账本行 / 新旧 golden 三件套 /
  mint 升号 / 分叉点登记）——M6-2 预案直接执行。
- **零 FilmRecord 新字段**映射维持 PRE OQ-M8-1 推荐：`process ≥ 2` = 光谱核单源；
  `FilmRecord.engine` 字段不设（需求实证出现再议）。

### 3.3 资产缺口清单（本版新交付——PRE 未盘点）

我方 profile JSON **谱面输入已随文件携带**（28 张实测键面）：
`data.log_sensitivity[81×3]`、`data.channel_density[81×3]`、
`data.base_density[81]`、`data.hanatos2025_adaptation_window_params`、
`data.hanatos2025_adaptation_surface_params`、`info.reference_illuminant` /
`info.viewing_illuminant`——但 Swift 类型面（`FilmProfile`，FilmProfile.swift:
161-174）按 M3-3-01 KD-3 只解码 `logExposure/densityCurves/baseDensity/
wavelengths` 四项，**谱字段在 JSON 里、类型面缺席**。M8 解码面 additive 扩展
（synthesized decode 宽容惯例）即可，JSON 零改。

**缺失必须自建/自装配的常量**（本仓 grep 零命中）：
| 项 | 用途 | 来源路线 |
|---|---|---|
| CIE 1931 2° CMFs[81×3] | scan 积分 + illuminant xy 导出 | 公开标准数据 |
| D 系列 / A 光源 SPD[81] | illuminants 集（film ref/view/enlarger） | D 系列公开公式；A/ENL 公式；TH-KG3 = 卤素+滤光公开描述自近似 |
| dichroic 曲线[81×3] | 印相配光 | 公开描述自近似；dt pack 值域 sanity 带 |
| spectral locus 多边形 | 输入 xy 压缩 + tc 域 | 由 CMFs 导出（代码资产） |
| tc 上采样谱表 192²×81 | expose | **自拟合**（Jakob-Hanika 数学 + BSD 方法参考；OQ-M8-2） |
| neutral_print_filters | 中性印相配平 seed | **已有**（Resources/FilmProfiles/，CC BY-SA 字节原样） |

许可注记（PRE §6 维持 + 一点收窄）：自拟合产物 = 数学拟合系数/公开标准数据装配，
倾向非 CC BY-SA 衍生（PRE OQ-M8-2 附则待 charter 法务注记）；**GPL 同许可切换后
（2026-10-20）**「上游表许可待验」的僵局已松——若自拟合不达标，GPL 侧表按同许可
移植合法（保留版权 + NOTICE），但**首选仍自拟合**（域合身：Rec2020 working +
我方光源集；PRE 理由维持）。

---

## §4 性能预算（100MP 全帧，预览/导出分档）

### 4.1 逐像素成本对账（上游形态 → 我方光谱核）

| 段 | 上游 GPU 逐像素 | 相对现行 film_subrun |
|---|---|---|
| expose | 3×3 mat + 1×16-tap Mitchell 2D gather（442KB 表，L2 友好） | 新增 |
| lograw+develop | log2 多项式 + 2× 1D 曲线查表 + 3×3 mat | ≈现行曲线查表 |
| print_expose | 1× PCHIP 3D（33³，8-cell hermite + slopes） | ≈现行四面体（8 tap trilinear 级） |
| print_develop | 3× 1D 查表 | 新增（轻） |
| scan | 1× PCHIP 3D + pow10 + CAT02 mat + OkLab(2 cbrt) + cmax bilinear + 2× pow knee | 新增大头 |
| **合计** | ≈2×3D 表 fetch + 1×2D cubic gather + 4-6× 1D 查表 + 4×mat3 + OkLab/ Knee 超越函数 | **≈2-5× 现行腿**（PRE 2-4× 上修右端：scan 段 OkLab cbrt/knee pow 是我方现行腿没有的超越函数密度，Apple GPU native special function 速率是主要不确定项，probe 定真值） |

- 表常驻显存：tc_lut 442KB + 2×2.5MB PCHIP 集 + 常量块 ≈ **5.5MB**（对比现行
  65³ rgba32Float bake 表 4.4MB——同数量级，`assembleFilmPayloads` 载体面直接
  扩展）。
- 预算推算：现行 film 腿全帧 ~15-40ms（M3-3 probe 域）→ 光谱腿 **~40-160ms
  @100MP** 全帧 FULL；预览 512-1024 长边亚 ms-几 ms；全在 100MP FULL 容忍域。
  PRE §5.2 维持、上修区间。

### 4.2 中间面与内存（最大风险项复核）

- DIR coupler corr 场 = 唯一新增全幅中间面：float3 @100MP = **1.2GB**，超预算形
  （上游 CPU 路 plane+corr+scratch ≈2.8GB 同样不可接受；GPU 路 factor_cl=9.75
  tile 内多 buffer）。**方案 ①（推荐，PRE OQ-M8-4 维持）**：corr 生成 + 降采样
  （1/4-1/8 res，19-75MB）→ 分离模糊 pass → 上采样参与 develop——`film box
  不入 tile` 不变式下全帧一次 dispatch 可保持；dispatch 形态 = A（expose+lograw+
  corr 生成 fused）→ corr 模糊（现有 blur 基建）→ B（develop+print+scan fused），
  两 dispatch + 一小中间面，或 v1 砍 coupler（模型完整性让位预算）。
-其余段全逐像素，无中间面。8G RSS 门机检 + probe 批实测（probe ③）。

### 4.3 probe 设计（维持 PRE §5.4 四件 + 一增）

① tc 表构建耗时/数值 sanity（中性配平：irradiance 表白点积分散 ≤1e-6 带）；
② 逐像素 kernel microbench（合成 ramp + 真图 100MP，全帧 + 分段 signpost）；
③ RSS 峰值（corr 两方案对照）；④ 与密度核 pristine/strength-0 基线 +
`filmRampPlaneHash` 新哨兵；⑤（增）fma/倒数钉形 vs 裸形的 CPU-GPU 分歧度量
（§1.6 纪律在我方 Metal 上的实证——golden 门精度定级输入）。

---

## §5 OQ-M8-1..7 全带推荐（PRE §7 经全量消读后的终推荐）

- **OQ-M8-1 核拓扑**：维持——**process 驱动单源**（`.v2` = 光谱 current；
  `RenderProcess` 第二 case 即账本；零 FilmRecord 新字段；零 schema bump，
  `process` 键 v10 已在册）。§3.2 五件套执行。
- **OQ-M8-2 tc 表来源**：维持自拟合首选，**fallback 从「评估上游许可」升格为
  「GPL 同许可合法移植」**（2026-10-20 切换的直接后果；首选不变——域合身与
  NOTICE 简洁）。自拟合形态细化：拟合目标 = 每 tc cell 81 点谱（sigmodal 族，
  Jakob-Hanika 2019 数学），fit 到 Rec2020 域 + 我方光源集；上游形态学参照 =
  pack 存**谱**而非三系数（§1.2），我方可存系数表构建期展开（442KB 运行期面
  两条路等价，charter 定）。
- **OQ-M8-3 重积分形态**：维持运行时 3D 表臂 + 细化——**PCHIP 单调插值臂
  推荐采纳**（上游双路 bit-exact 工程纪律 §1.6 + 单调性对密度反演的保形价值；
  我方现行 rtne 四面体不保形。33³ @Float64 CPU 构建 + float 表 +
  cmin/cmax 钳位面全盘平移）；golden 参照 = Float64 逐像素精确臂独立复算
  （M3-3-03 主门形态平移）。
- **OQ-M8-4 DIR coupler 与空间面**：维持——v1 **含** coupler correction
  （模型完整性；矩阵/Langmuir 数学已全摸清 §1.3），模糊场 1/4-1/8 降采样
  （§4.2 ①）；grain/halation/diffusion/boost/glare 不入 M8（spektra_core 挂账
  不消费；我方 grain 已有 dt 遗产面独立承载）。
- **OQ-M8-5 范围与阶段切分**：维持 M8-0 charter → M8-1 数学核+probe →
  M8-2 管线集成 → M8-3 面板接线+golden/收口；见 §6。
- **OQ-M8-6 FSIM-01c 措辞修订**：维持——M8-2 落地批同批修订 NOTICE 消费披露行
  + 用户可见措辞升格「光谱重建材质模拟（逐波长），非场景光谱重放」；历史文档
  勘误行追加。
- **OQ-M8-7 UI 对齐面**：维持——Alcedo 无光谱面，UI = 现行 Film 面板平移
  （材料 picker / Y·M / Solve / 宽容度面板数学零改）；上游 upsampling 表选择器 /
  带宽自适应控件 v1 不引入（模型面恒自拟合单表）。新增注记：上游 adaptation
  bandwidth/surface 两开关（spektrafilm.c:324-332）我方 v1 **不暴露**——profile
  系数已携带，bandwidth 恒 on / surface 恒 off（上游 reference 同款解析，
  spektra_sim.h:483-497），参数面留 build 期常量。

**新增 OQ-M8-8（本版提出）——曝光/EV 语义对齐**：上游 `exposure_ev` 进 sim 键
且 fold 进 expose（`×2^ev`，spektrafilm.c:1514/1780；push/pull 折 γ 不折曝光
1806-1835）；我方 `exposureEv` 走 solve gain（消费层）。光谱臂语义
（曝光修正点在链头 vs solve 增益）charter 期钉——推荐维持我方 solve-gain 消费
层形态（recordHash 已折，缓存键不变）。

---

## §6 plan 切分建议 + ΔN 粗估 + 里程碑形态

### 6.1 切分（L 预算，4 plan；每 plan 独立「实现→自测→验收」）

| plan | 对象 | 关键交付 | ΔN 粗估 |
|---|---|---|---|
| M8-0（charter 批，非 plan） | OQ 裁决 + phase 表 + SC 门 | 五正本 | — |
| **M8-1a 数学核-数据面** | FilmProfile 解码面 additive 扩展（谱四字段）+ 常量集装配（CMFs/D-SPD/locus/dichroic 自建）+ tc 表自拟合器（Float64 拟合 CLI/测试域）+ 光域单元 golden（expose 积分 vs 独立复算 ≤1e-6；中性配平带；PCHIP vs 精确臂 ≤带宽） | 谱解码 + 常量资产 + 拟合器 + 构建期引擎（Swift Float64 参考实现全链） | 18-24 |
| **M8-1b 数学核-GPU 面** | Metal kernel 族（expose/lograw/develop_corr/develop/print_expose/print_develop/scan，fused 两 dispatch 形 + corr 降采样臂）+ 表构建/上传载体 + fma/倒数钉形 + `LIGHTAMER_PERF_PROBE` 探针批（perf/RSS 真值 + corr 方案裁决数据） | kernel 全家 + probe 报告 + `filmRampPlaneHash` 新哨兵 | 12-18 |
| **M8-2 管线集成** | `assembleFilmLeg` 光谱臂 + `FilmMethodBox` payload 换形 + FilmSolveCache 光谱域求解（中性配平/曝光归一重推导，modeTag 扩段）+ FilmPrintBake 光谱表 bake（PCHIP 33³ 家族）+ **process v2 bump 五件套** + 冻结 golden 三件套（密度核 legacy 臂零漂移 + 光谱臂 golden）+ CC BY-SA 谱面消费 NOTICE 修订 + OQ-M8-8 裁决落地 | 光谱核产线上线（v2 档）+ 密度核冻结 | 20-26 |
| **M8-3 面板接线 + 收口** | Film 面板平移（核感知 readout）+ 宽容度 descriptor/面板换臂 + 「Update to Current Process」迁移 UX（M6-2 §6 挂账正主）+ VALIDATION + gui 走查 | 全阶段闭环 | 10-14 |

**ΔN 合计 ≈ 60-82**（中值 ~70；对比 M3-3 批 ≈45-55、M2-9 批 ≈60——L 档成立）。
风险集中 M8-1b（GPU 数值纪律 §1.6 三板斧是我方首次全链应用）与 M8-2（双臂
golden 面最大）；M8-1a 拟合器质量（覆盖率/平滑度门）是长杆，失败回落 GPL 表移植
（OQ-M8-2 fallback，plan 内分支不破段结构）。

### 6.2 里程碑形态

M8 = 单 phase（M8-0 charter + 4 plan），charter-pending → M7 收口后随正常流转
立项；无外部阻塞依赖（数据自装配路线零下载面；dt pack 仅 sanity 参照，可选）。

---

## §7 Sources

### 上游（GPL-3.0，同许可移植纪律，本版读解正本）

- `darktable/src/iop/spektrafilm.c`（19-60 头注 / 189-410 params / 1490-1918
  _ensure_sim / 2023-2109 ROI+tiling / 2135-2495 process / 627-645 pack 单例）
- `darktable/src/common/spektra_sim.h`（39-56 stages / 68-104 常量 / 119-123
  kind / 253-335 gpu 表 / 477-619 params）
- `darktable/src/common/spektra_sim.c`（291-364 容器/曲线模型 / 101-112 knee
  常量 / 1719-1847 tri2quad+sigmoid+poly2d+Reinhard / 1853-2120 Mitchell cubic
  / 2137-2247 PCHIP / 2976-3016 dichroic+print 积分 / 3071-3086 scan 积分 /
  3092-3262 OkLab+cmax+compress / 3363-3454 expose+midgray / 3463-3503
  build_lut3d / 3529-4650 sf_sim_build 六段 / 4657-4949 per-pixel 七函数）
- `darktable/data/kernels/spektrafilm.cl`（62-103 FP_CONTRACT+矩阵 / 107-248
  Mitchell+PCHIP / 251-286 log10/knee / 302-324 cmax / 332+ 七 per-pixel kernel）
- `darktable/src/common/spektra_core.{c,h}`（空间效果接口 + YVV σ150 发散教训）
- `darktable/src/common/spektra_fetch.{c,h}`（pack 目录/hash 身份/下载状态机）
- `darktable/src/tests/unittests/common/test_spektra_{sim,pack}.c` +
  `src/tests/integration/0179-spektrafilm/`（验证基座形态）

### 我方正本

- `LightamerCore/Sources/Pipe/RenderProcess.swift`（107-150 账本 + 109-115 v2
  预案 doc-comment）
- `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift`（85-185 assembly+seed /
  197-331 FilmMethodBox / 336-399 payloads+uniforms / 411-657 stats+solve）
- `LightamerCore/Sources/Pipe/PixelPipe.swift`（1145-1192 runTerminalTails /
  1207-1367 film leg+factory / 1377-1402 replay）
- `LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift`（65³ bake 家族）；
  `LightamerCore/Sources/Film/Film{Profile,Descriptor,FilterPackSolver,
  MaterialStore}.swift`；`LightamerIOP/Sources/FilmPlacement/FilmPlacementModule.swift`
- `Resources/FilmProfiles/`（NOTICE/LICENSE/CHANGELOG/MANIFEST.sha256 +
  profiles/ 28 JSON + neutral_print_filters.json；谱字段在册实测）
- `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（385 process 键）
- `.work/gsd/phases/m8-fsim-spectral/RESEARCH-PRE.md`（被本版取代的预告底稿）+
  `phases/m3-2-fsim-research/RESEARCH-NOTES.md` + `phases/m3-3-fsim/
  M3-3-0{1,2,3}-DECISIONS.md` + `phases/m3-4-latitude/` +
  `phases/m6-2-process-version/RESEARCH-NOTES.md`

### 公开数学/标准

- Jakob & Hanika 2019《A Low-Dimensional Function Space for Efficient Spectral
  Upsampling》（EPFL RGL；官方参考实现 mitsuba-renderer/rgb2spec，BSD）；
  colour-science `colour.recovery`（BSD）
- CIE 1931 2° CMFs / CIE D 系列 SPD 公式 / CAT16 / CAT02 / OkLab（公开标准）
- darktable-org/darktable-spektrafilm 数据仓（packs + manifest + exporter；
  本地无克隆，形态自 spektrafilm.c:44-52 + spektra_fetch.h 读解）

# darktable spektrafilm 引入进度调研（2026-11-01）

> 调研员：omp。读法：dt 侧一律 `git show github/master:<path>`（本地
> `origin/master` stale 无 spektra 代码）；数据仓走 raw.githubusercontent
> 直读 manifest/pack.json。纯文本零 commit 零构建。
> 我方基线 = M8（process v2 光谱核）+ M8-3+（空间三算子接谱，HEAD `eb6d3953`
> 后 T7 收口态，2026-11-01）。
> 许可：dt spektrafilm 族 = GPL-3.0，同许可可移植（保留版权 + NOTICE，
> 2026-10-20 切换）。

---

## §0 结论先行

1. **dt spektrafilm 已落地**：2026-09-05 首版合入（`d81ccfe23b` #21967），列入
   darktable 5.8 RELEASE_NOTES "The Big Ones" 首条，定位 scene-to-display
   view transform（替代 sigmoid/filmic/agx）。10-12 后 master 无新 spektra
   commit（静默 20 天），当前态 = 10-12 收口态。
2. **我方已跟进到上游 10-09 树**：M8-3+ RESEARCH 以 `4d1fb6a95b` 树为正本，
   宽模糊抽稀（含 block-average 双 kernel 拆分）已移植
   （`SpectralWideBlurPlan` + `spectral_film_wide_rows/down/up`）。
3. **净新增缺口小**：10-09 后 dt 只有 2 个实质 commit（`9fd80e6db3` 抽稀扩到
   diffusion/halation + `24109e85c1` 递归宽度对齐——后者我方 TRUE-σ 路线已
   显式不移植）；其余全是 GUI/文案/翻译/参数迁移。
4. **数据面有 3 卷可直接拿**：dt 数据仓 `packs/0.3.3` 共 31 卷，我方 28 卷
   之外多 `kodak_2302 / kodak_doublex / kodak_trix`（B&W 族，我方零覆盖），
   走 SPEC-02 verbatim 通道。
5. **值得学的只有两件**：① print diffusion 跑在线性域（`6d92ef5814`——我方
   B2 钩已留座位，需核对 log/linear 域）；② YVV 增量式求值保 DC 增益
   （`bb3e11cd48` 前半——我方 exact-kernel 路线天然免疫，记为已免疫项）。

---

## §1 dt spektrafilm 当前态（github/master @37d514c78c，2026-10-14）

### 1.1 文件清单

| 文件 | 行数 | 职责 |
|---|---|---|
| `src/iop/spektrafilm.c` | 6509 | 参数（74 字段）+ GUI（5 tab）+ pack 解析 + ROI/tiling + CPU/GPU 调度 |
| `src/common/spektra_sim.c` | 5405 | 逐像素色科学引擎（expose/develop/print/scan 七 stage） |
| `src/common/spektra_core.c` | 1189 | 空间效果（grain/halation/diffusion/boost/blur） |
| `src/common/spektra_fetch.c` | 1668 | 数据包定位 + 后台下载（libcurl） |
| `src/common/spektra_sim.h` | 722 | 引擎 API + `sf_sim_gpu_t` GPU 载体 |
| `src/common/spektra_core.h` | 326 | 空间效果 API + 宽模糊计划 |
| `src/common/spektra_fetch.h` | 186 | fetch API |
| `data/kernels/spektrafilm.cl` | 1266 | 33 个 OpenCL kernel |
| `data/kernels/grain.h` | — | CPU/GPU 共享采样器数学（同一源码双编译） |
| `src/tests/unittests/common/test_spektra_{sim,pack}.c` | — | stage 级双臂对照 + 容器解析单测 |
| 集成测试 `0179-spektrafilm` | — | 端到端 XMP（含 print diffusion GPU 计时） |

首版→当前 diff 量：五主文件 +4431/−1074；iop GUI 控件 142→163 个。

### 1.2 核心功能清单（用户可见）

管线（`spektrafilm.c:26-38` 头注释，CPU `process` / GPU `process_cl` 同序）：

```
work RGB
 ① expose（光谱上采样 tc LUT 192²·Mitchell cubic）
 ② 线性域空间：highlight boost → diffusion → halation（scatter 两阶段）
 ③ develop：lograw → coupler corr（20µm 高斯 + 指数尾模糊）→ CMY 密度
 ④ grain（密度域：多子层 Poisson → dye-cloud → clump blur → 乘法 USM）
 ⑤ print（scan_film 跳过）：print_expose → print diffusion → print_develop
 ⑥ scan：3D 表 → 黑白点 → CAT02 → OkLCh/ACES 压缩 → out_scale → scan USM/glare
```

GUI 五 tab 参数（74 字段全表见 M8 RESEARCH §1 / scout 报告归档）：

| tab | section | 我方对照 |
|---|---|---|
| film | exposure（exposure_ev/push_pull） | exposureEv ✓；push_pull ✗（无） |
| film | chemistry（显影时间/film_gamma×3/exhaustion） | ✗ 全无（M3-4 descriptor 只读） |
| film | DIR couplers（amount/inhibition×2/diffusion/tail×2） | coupler 矩阵+Langmuir ✓（M8 核内）；UI 参数 ✗ |
| film | diffusion（family×4/strength/scale/warmth） | 四族表 ✓（M8-3+ T5，off 默认）；scale/warmth ✗ |
| film | advanced（upsampling 表选择/adaptation×2/gamut） | tc 自拟合 ✓；adaptation 恒常量无 UI（M8-3 T1 钉死）；gamut 恒 OkLCh |
| print | exposure/chemistry/filtration/preflash/diffusion | Y/M 滤色 ✓（M3）；preflash ✗；print_gamma ✓（T2 仿射增益异构）；per-channel gamma ✗ |
| grain | emulsion×5/texture×4 | grainAmount ✓（M8-3+ T4，off 默认）；余 ✗ |
| halation | scatter×2/halation×2/boost×3 | halationAmount ✓（T5，off 默认）；scatter/boost ✗ |
| scanner | output×2（含取色器）/sharpness/glare/bw×4 | ✗ 全无 |

film/paper 选择：扫 pack `profiles/*.json` info 头；paper 三态
（none=scan / auto=跟胶片 target_print / pinned）；正片自动进 scan 模式；
`film_format_mm` 画幅（硬 5..250 / 软 8..130）定全部空间尺度。

### 1.3 数据包机制（fetch）

- pack = `pack.json` + `spectra_lut.f32`（192²×81 f32 ≈ 12MB）+ `profiles/`。
- 两安装位：手装顶层（优先）/ 下载缓存 `packs/<hash>/`。
- 三哈希：`pack_hash`（整包身份）> `upsampling_hash`（显式选表）>
  `lut_hash`（盖戳的默认表）。mismatch = 警告 + 替代渲染，不黑帧。
- 容器版 `pack_format` 2/3（2=单 irradiance 表；3=多表声明，
  含 reflectance 表，走 relight+自身场景白投影消费）。
- 仓库：`darktable-org/darktable-spektrafilm`，`manifest.json` + 按文件
  sha256 校验的单遍下载；`sf_fetch_check_start` 可查新版。

---

## §2 近期演进时间线（2026-08-01 → 2026-11-01，全 62 commits 中关键节点）

### 2.1 首版与早期修正（9-05 → 9-15）

| 日期 | commit | 摘要 |
|---|---|---|
| 09-05 | `d81ccfe23b` | 首版合入 #21967（模块 + 引擎 + 空间 + fetch + 单测 + 0179） |
| 09-05 | `dba9b27b24` | POTFILES 登记（i18n 起点） |
| 09-05 | `4bb18e8dbe` | RELEASE_NOTES 条目润色 |
| 09-06 | `351669cab2` | 无 OpenCL 编译修复 |
| 09-07 | `3d2473bab1` | CPU/GPU 分歧修 #22176（第一轮） |
| 09-07 | `c6b708df25` | 正片禁用 viewing glare（疏漏修） |
| 09-09 | `e5d4978c67` | housekeeping |
| 09-09 | `1a431af9be` | lut hash 盖戳修 + 删 stale 码 |
| 09-09 | `354814ed85` | 默认改 kodak gold + print contrast 1.1 |
| 09-10 | `f1fa23240b` | GPU/CPU 再对齐（非 spektra 前缀，并入门） |
| 09-10 | `f4c6cb3beb` | 安装严格 fail-safe |
| 09-10 | `4ef51fd7d3` | 小 GPU/CPU 不一致修 |
| 09-10 | `c1f51a6280` | 子层 particle scale 修 |
| 09-10 | `bfc8ece793` | density floor 改 scale 形态 |
| 09-11 | `84bd69c54e` | print diffusion 滑杆守 print 门 |
| 09-13 | `f150e0b921` | 法语翻译 |
| 09-14 | `c30d188767` | section 撤销修 |
| 09-15 | `6a2f19f4e3` | CPU/GPU 标量数学单源码 #22282（grain.h 双编译） |

### 2.2 pack v3 与数据身份（9-21，PR #22335 `d9d4fe731c` 10-01 合入）

| 日期 | commit | 摘要 |
|---|---|---|
| 09-21 | `10d45dc8f3` | per-channel print gamma（三滑杆，print chemistry 节） |
| 09-21 | `13421bd5c2` | fetch：枚举已装包 |
| 09-21 | `1e3b22170c` | 新编辑 grain clump blur 取上游 0.89（旧档 0.8 保留） |
| 09-21 | `c9047ad838` | 引擎消费 pack_format 3 reflectance 表 |
| 09-21 | `bee1fd4f6c` | auto paper：GUI 与管线同解析 |
| 09-21 | `1b16d045a0` | pack 身份（pack_hash）+ 编辑匹配 |
| 09-21 | `c980665a53` | 每编辑选 upsampling 表（upsampling_hash） |
| 09-21 | `bcb98dcc5d` | 查仓库新版包（check 不下载） |
| 09-21 | `3387d15e1f` | 黑白点暴露给 scan/print（四控件） |
| 09-21 | `b85ad7ce9c` | 下载失败点名缺哪个包 |
| 09-28 | `905e41137c` | 删 quality 设置（恒 33³ 表渲染，params v3） |
| 09-28 | `fb35039185` | pre-compression boost tooltip 说明 |
| 09-30 | `489c3a00e0` | 单测 pack_format 3 upsampling 表 |
| 09-30 | `2557419ab2` | `_sf_morph_channel` order 数组零初始化 |
| 10-01 | `868c4aa304` | upsampling tooltip 澄清 |

### 2.3 精度/性能收口（10-05 → 10-12）

| 日期 | commit | 摘要 |
|---|---|---|
| 10-05 | `8b5b4321bc` | boost 上限外沿切线延拓（防 exp 溢出→NaN 漫帧） |
| 10-05 | `6d92ef5814` | print diffusion 改线性域（原 log 域几何混合不守恒） |
| 10-05 | `9ef307dad8` | 宽递归 blur 级联代箝位（σ>150 拆 n×σ/√n，预览/导出同晕） |
| 10-05 | `5a9b1ceacb` | `-ffp-contract=off` 作用到模块 target（原写错地无效） |
| 10-05 | `1ce6ad6a93` | grain 采样器前剩余乘加钉 fma（含 halation double→float） |
| 10-05 | `a80f62013b` | film_format_mm 硬范围扩 5..250（容 Super8/8×10 预设） |
| 10-05 | `42895cc537` | grain 采样胶片曲线模型全部子层（原丢层致负均值） |
| 10-05 | `1be930d162` | GUI 默认/缺纸回退与渲染一致 |
| 10-05 | `6bfc8a1a1c` | pack 加载/sim 构建坏输入硬化（缺曲线/网格/成员） |
| 10-05 | `3d05828629` | boost 取色器测量时 out_scale 置 1（解耦后级） |
| 10-05 | `3b1a26a7c7` | grain 采样器处 CPU/GPU 余量分歧清零（0179 0.8% 坏点→合） |
| 10-06 | `1da6750de2` | 离 scan 模式保留 pinned paper |
| 10-06 | `f150ca3ada` | 读单显影 base_density 列矩阵（Tri-X 0.3.4 包形态） |
| 10-07 | `5f1a471b85` | highlight boost section 改名 |
| 10-07 | `0fb8943f60` | tooltip 注 boost 无视 halation 开关 |
| 10-07 | `202f2544d1` | print gamma 默认改 1.0（跟上游，按纸定标） |
| 10-08 | `9e65633926` | 级联 YVV 每遍 device 同步（防 amdgpu ring 锁死 abort） |
| 10-08 | `bb3e11cd48` | OpenCL 宽 blur 清理：YVV 增量求值 + coupler 宽 blur 抽稀 |
| 10-08 | `5ffc7b4b63` | GCC 15 `-Wstringop-overread` 修（_auto_paper_entry） |
| 10-09 | `4d1fb6a95b` | 宽 blur block-average 拆双 kernel（k=60..130 并行度修，0179 GPU 10.3s→回） |
| 10-10 | `24109e85c1` | 抽稀 blur 取递归路径宽度（YVV 闭式方差目标） |
| 10-10 | `9fd80e6db3` | 抽稀扩到 diffusion/halation 宽 blur（≥100px；误差表见 §3.1） |
| 10-11 | `6271f53787` | 翻译批量 bm20261009 #22556 |
| 10-12 | `23a3eaf5c9` | PR #22548 合入（diffdump 余量修，10-12 后无新 spektra commit） |

---

## §3 可学习点逐条评估

### 3.1 宽模糊抽稀（`bb3e11cd48` + `9ef307dad8` + `4d1fb6a95b` + `24109e85c1` + `9fd80e6db3`）

- dt 配方：σ≥16 即 `k=⌊σ/8⌋` 块均值抽稀 → 低面 exact 核（≤79 taps）
  → 双线性插回；σ_low 扣 box 方差 `(k²−1)/12` + 插值 `k²/6`；
  块网格锚绝对坐标（tile 一致）；≥100px 才用于 diffusion/halation
  （默认渲染全在此下，外观零变）；block-average 拆 rows/down 双 kernel
  保 GPU 并行度；CPU 与 device 逐位一致（fma 钉 + host 倒数 + 防重排循环）。
- 精度实证（3200×2400 vs 双精度参考）：σ149 max 1.2e-2→2.0e-4；
  σ300 3.2e-2→1.6e-5；σ450 5.5e-2→1.0e-5。
- 我方：**已有等价**（M8-3+ T5：`SpectralWideBlurPlan` + 抽稀三件 +
  CPU/GPU 逐位 + 16 kernel）。差异仅 `24109e85c1` 的 YVV 宽度目标——我方
  exact-kernel 路线无递归遗产，TRUE-σ 目标是正确的不移植（R-M83P-5 ②）。
- 结论：**已学完**。`9fd80e6db3` 的 100px effect 阈值我方已取作起步值
  （重标 pending，M8-3+ m2）——dt 的 3200×2400 误差表可作我方重标参照输入。

### 3.2 分叉修族（`3b1a26a7c7` + `1ce6ad6a93` + `5a9b1ceacb` + `42895cc537`）

- 内容：grain 采样器前全链路乘加钉 fma（coupler 和/lerp/halation 混合/
  diffusion 累加/tail 权重）；halation CPU 侧 double 混合改 float（与 kernel
  同字面量）；grain.h 不再依赖 FP_CONTRACT pragma（显式 fmaf shim）；
  PCHIP/slope/Cmax/knee/bw/USM/glare 同处理；grain 采样全部子层（丢层致
  负均值）；`-ffp-contract=off` 落到真 target。
- 我方：bit-exact 三板斧（X5 nail ①②③：fma 钉 + host 倒数 + 共享 log/exp
  多项式）**语义已覆盖**；`42895cc537` 的丢层负均值——我方 T4 子层派生走
  nl==1 臂，需核对多层档（28 卷中多层拟合档）是否同坑。
- 结论：**M8-3+ 顺路核对一项**：多层曲线档的子层求和完备性（grain 臂；
  纯核对，无参面）。其余已免疫。

### 3.3 OpenCL 清理（`bb3e11cd48` 前半 + `9e65633926`）

- 内容：YVV 增量式求值（DC 增益恒 1，不随系数舍入漂；σ100/135/150 增益
  0.965/0.836/1.087 → 1）；级联每遍 device 同步（防长提交 amdgpu 看门狗 abort）。
- 我方：exact-kernel 路线**天然免疫**（无 YVV 递归）；Metal 无 amdgpu ring
  语义，但级联长 dispatch 链的 watchdog 风险同理——我方 kernel 16 个短链，
  无百遍级联。
- 结论：**不适用**（免疫项，记备忘）。

### 3.4 GCC 兼容（`5ffc7b4b63`）

- 内容：纯 GUI 循环不变量外提，消 GCC 15 `-O3 -Wstringop-overread` 误报。
- 我方：Swift/Clang 工具链，无 GCC。
- 结论：**不适用**。

### 3.5 print diffusion 线性域（`6d92ef5814`）

- 内容：原对 log10 印相曝光模糊 = 几何混合，高光不晕进暗区且不守恒；
  改转线性 → 滤波 → 转回（CPU grain_exp2f/log2f，GPU 两新 kernel 配对函数）；
  filter 非 no-op 才转域（inactive 双路零触）。
- 我方：M8-3+ T5 B2 钩已留座位（uniform 门，off 恒等）。**必须核对**我方
  前置腿/print 钩消费的是 log 面还是线性面——若 log 面，同 bug 在我方复现。
- 结论：**立即可学（核对项）**：查 B2 钩域 + 前置腿域，log 面则修线性。
  数据层零动，kernel 微调。

### 3.6 highlight boost 天花板（`8b5b4321bc`）

- 内容：固定天花板（midgray·2^(protect+4)，4EV 跨度，不取帧峰——tile 一致）；
  上限外沿切线延拓（C1 有界，防 +12EV 溢出 float → YVV inf−inf=NaN 漫帧）；
  常量 `sf_boost_build_plan` 一次构建。
- 我方：boost 座位预留未调度（`SpectralPayloads:1290` 明确 never dispatched）。
- 结论：**挂账观察**：boost 立项时把"固定天花板 + 切线延拓 + tile 一致论证"
  整套搬（设计已定型，无需再调研）。

### 3.7 print gamma 默认 1.0（`202f2544d1` + `10d45dc8f3`）

- 我方：T2 仿射增益已覆盖通道级修正（异构实现）；默认语义=按纸定标一致。
- 结论：**不适用**（语义已有）。

### 3.8 黑白点四控件（`3387d15e1f`）

- 内容：正片 scan 端点放置（sRGB 编码 levels 0.01/0.98，原编译期常量暴露）。
- 我方：scan 腿反转 B 路已有中性目标；端点 UI 无。
- 结论：**挂账观察**（scan 模式 UI 立项时再议）。

### 3.9 pack 身份/表选择/版本检查（`1b16d045a0` + `c980665a53` + `bcb98dcc5d`）

- 内容：pack_hash 整包身份；每编辑 pin 表（upsampling_hash）；仓库查新。
- 我方：process number + record stableHash 语义同构（M8 RESEARCH §2 已论证）；
  tc 表自拟合内置，无外部包。
- 结论：**不适用**（架构不同源，语义已有）。

### 3.10 输入硬化（`6bfc8a1a1c` + `f150ca3ada`）

- 内容：缺 density_curves_model 的纸走实测曲线；film/print 网格不一致拒建；
- 我方：`f150ca3ada` 直接相关——§4 的 Tri-X verbatim 引入时**必须带此读法**
  （(81,1) 列矩阵）；网格一致拒建可入 SPEC-02 校验门。
- 结论：**立即可学（随 §4 三卷引入同批）**。

### 3.11 取色器解耦（`3d05828629`）

- 内容：boost 探针 hold out_scale=1（后级不污染前级测量）。
- 我方：无取色器。
- 结论：**不适用**。

---

## §4 数据/资产面（dt 数据仓 vs 我方 28 卷）

源：`darktable-org/darktable-spektrafilm` `manifest.json`（format 1，
单包 `packs/0.3.3`，`lut_hash 565f4ec4`，pack_format 2，
`spectra_lut.f32` 5972022 B = 32 字节头 + 22 字节 lut_id（`irradiance_xy_tc@0.3.3`）+ 192²×81 fp16（5971968 B，逐字节对上——**盘上是半精度**，与 M8 RESEARCH §2 的"f32 ≈12MB"记述差一倍，M8 侧读解勘误）。

| 对照 | 卷 |
|---|---|
| dt 31 卷 − 我方 28 卷（可拿） | `kodak_2302`（印片/正片纸）、`kodak_doublex`（B&W 负片，5 显影时间家族）、`kodak_trix`（Tri-X 400 B&W，单显影列矩阵形态） |
| 我方有 dt 无 | 无（我方 28 卷 ⊆ dt 31 卷） |

- 三卷全是 B&W/印片族：我方现行 28 卷零 B&W 覆盖，属**新域**（B&W 单乳剂
  塌缩/achromatic grain 臂我方核内已结构在位但无档可跑）。
- `doublex` 5 显影时间家族 → 我方显影时间维无面（M8-3+ m-6①只做配方），
  引入后取代表成员（dt `select_development_time(None)` 中间成员语义）。
- `trix` 列矩阵读法见 §3.10。
- pack.json 常量集（cmfs/illuminants 8 光源/dichroic/film_render_defaults/
  neutral_filters/locus）：我方自装配常量集已建成（`SpectralConstantsData`），
  dt 包只作 sanity 带参照（M8 既定路线，不变）。
- 0.3.4 包：f150/1e3b commit 提及（Tri-X 列矩阵 + grain 0.89），但数据仓
  `packs/0.3.4` 404、manifest 仍单包 0.3.3——**0.3.4 未发布**，dt master 10-12
  后静默与此一致（等上游包）。

---

## §5 差距表（功能面：dt 有 / 我方态）

| # | dt 功能 | 我方态 | 差距 |
|---|---|---|---|
| G1 | 74 参数 5 tab 全 UI | FilmRecord 13 字段（7 M3 + 3 M8-3+ B-track + 3 可选） | 参数面大（预期内：我方面板最小面策略） |
| G2 | push/pull（曝光+1.15/stop 反差） | 无 | 小参面 |
| G3 | chemistry（显影时间/gamma/exhaustion） | 只读 descriptor | 中（M3-4 后续） |
| G4 | coupler UI 参数 | 核内有，UI 无 | 小 |
| G5 | diffusion scale/warmth | 表有，参数无 | 小 |
| G6 | preflash | 无 | 小 |
| G7 | grain 纹理 4 参 | grainAmount 一参 | 小 |
| G8 | scatter/boost | 座位预留未调度 | 中（设计已定，待立项） |
| G9 | scan 模式（正片直扫/glare/bw） | 反转 B 路核内，UI 无 | 中 |
| G10 | B&W 三卷 | 零覆盖 | 数据（三卷 verbatim 关门） |
| G11 | reflectance 表 | 自拟合单 irradiance 表 | 架构（reflectance 立项时再议） |

---

## §6 引入建议（逐项裁决）

| 项 | 裁决 | 说明 |
|---|---|---|
| 宽模糊抽稀全套 | ✅ 已学完 | M8-3+ T5 已移植；100px 阈值重标时用 dt 误差表作参照 |
| print diffusion 线性域 | 🔴 立即可学 | 核对 B2 钩/前置腿消费域，log 面则修（M8-3+ 顺路批） |
| Tri-X 列矩阵读法 + 网格拒建门 | 🔴 立即可学 | 随三卷引入同批（SPEC-02 通道） |
| kodak_2302/doublex/trix 三卷 | 🔴 立即可学 | SPEC-02 verbatim，B&W 新域；doublex 取代表显影成员 |
| 多层档子层完备核对 | 🟡 M8-3+ 顺路 | grain 臂丢层负均值核对（纯核对） |
| highlight boost 定型设计 | 🟢 挂账观察 | 立项即搬（天花板+切线+tile 论证） |
| 黑白点/chemistry/push-pull/preflash/scale/warmth 参数面 | 🟢 挂账观察 | 面板扩面时逐项议 |
| scan 模式 UI | 🟢 挂账观察 | 反转 B 路核内已有，UI 立项时议 |
| reflectance 表 | 🟢 挂账观察 | 自拟合第二表立项时议 |
| YVV 增量求值/device 同步 | ⚪ 不适用 | exact-kernel 路线免疫 |
| GCC 修 | ⚪ 不适用 | 工具链无关 |
| pack 身份/表选择/版本检查 | ⚪ 不适用 | 语义同构已有（process+stableHash） |
| print gamma 默认/per-channel | ⚪ 不适用 | 语义已有（T2 仿射增益） |
| 取色器解耦 | ⚪ 不适用 | 无取色器 |

---

## §7 Sources

- dt 代码：`github/master`（HEAD `37d514c78c` 2026-10-14）
  `src/iop/spektrafilm.c` / `src/common/spektra_{sim,core,fetch}.{c,h}` /
  `data/kernels/spektrafilm.cl` / `data/kernels/grain.h` /
  `src/tests/unittests/common/test_spektra_{sim,pack}.c`。
- dt 时间线：`git log --all --since=2026-08-01 --grep=spektra -i`（62 commits）
  + 文件域 log 交叉（`fa3fc72294` mutex 维护 / `fdbeac6225` 美式拼写 /
  `f1fa23240b` GPU/CPU 对齐三 commit 无 spektra 前缀但触及同文件，已并入）。
- 数据仓：`https://raw.githubusercontent.com/darktable-org/darktable-spektrafilm/main/manifest.json`
  + `packs/0.3.3/pack.json`（直读，2026-11-01）。
- 我方：M8 RESEARCH §1-§4 / M8-3 SUMMARY / M8-3+ RESEARCH + SUMMARY /
  `LightamerCore/Sources/{Film/Spectral*,Pipe/Film/Spectral*}` /
  `Resources/FilmProfiles/`（28 卷 + MANIFEST.sha256）。
- 深读 scout 报告：`agent://SimCoreScout`（sim/core/cl 全量）+
  `agent://IopGuiScout`（iop 74 参数 + GUI 树）——注：scout 读的是本地
  stale 检出（6314/5391/915 行），10 月新机制（抽稀/YVV/切线延拓）由
  orchestrator 按 `github/master` 亲核， scout 报告 §4/§8 中"无抽稀"
  结论已过期，以本文件 §3.1 为准。

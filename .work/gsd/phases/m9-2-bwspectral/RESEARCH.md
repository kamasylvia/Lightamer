# M9-2 RESEARCH — 光谱延展：黑白族 + 滤色镜（M9BW-01..03）

```
phase: M9-2
status: drafted
date: 2026-10-25
researcher: zcode subagent (M9-2 station)
上游正本: SpektraLab origin/main (behind 518; 经 git show origin/main 读解, GPL 只读)
我方正本: .work/gsd/phases/m8-fsim-spectral/ (M8 已收口) + AGENTS M3-3 节
红线: 零 commit / 零构建 / 黑白数据自建 (厂商发表规格数字化, 非 GPL 复制)
```

---

## 0. 调研总结论（一句话版）

1. **上游黑白域 = 纯数据形态，引擎渲染数学零改动**——BW profile 就是普通
   谱面 schema，`channel_model:"bw"` 只是三通道**同值**（panchromatic 单乳剂写
   三通道）+ `channel_density` 每波长 [1/3,1/3,1/3]（中性银）；变反差相纸是
   **同 schema 的三通道不同值**（三乳剂不同谱 + 盲色截止 560nm）——我方 M8
   谱链 `SpectralBuildEngine` 逐字节复用，**零 kernel / 零引擎改动**。
2. **滤色镜 = build 期 CPU 乘法，不进 per-pixel kernel**——上游在
   `film_sensitivity`（tc 表构建入口）把 81 点透射谱乘进感光度谱并按
   绿通道积分归一（滤镜因子给定，18% 灰曝光不变）；我方同构缝 =
   `SpectralBuildEngine.swift:431-451` 的 `sensW` 窗口段之后 / tc 展开
   循环（`:453-474`）之前——**两个 .metal 全零 diff 可守**。
3. **granularity = App/wire 层乘数，grain 算子本体零改动**——上游
   `FilmParams.ownGrain(of:)` 四 case 静态表（wire 值 = 发表 RMS µm×0.1：
   1.70/0.74/0.64/1.49），滑杆 1 = 发表值，色片恒 1；我方 GrainModule
   （dt 遗产，strength ∈[0,100] dt 相对量）加 per-film 标定面即可。
4. **数据面全部公开可得**（最难一件 = Wratten 8/11/12/15/21/47/58 透射表——
   上游引用的 mat.uc.pt filter-data.html 实测**只含 25/29/70+IR 系**，8 个
   滤镜的表在 Usenet 系列帖/镜像，已有两个独立替代源可达，见 §2.5）。
5. **最大架构缝 = bake 键扩展**：`FilmMaterialStore.materialPairHash` 的
   fold 集**不含谱面键**（`FilmMaterialStore.swift:115-151` 只折
   log_exposure+density_curves+base_density+wavelengths）；滤色镜/相纸
   grade 改变 build 输出 → 必须把 filterTag/gradeTag 折进
   `SpectralPrintBake` 槽键，否则同 pair 不同滤镜撞缓存出**错误复用**。
6. **process 号结论：本站零 bump**——BW = 新 stock id（存量照片不可达）；
   滤色镜/grade = 新 optional 字段缺席即恒等 → 全部 v2 内 additive；
   **v3 继续留给 M9-4 ColorWheels**（编号协调无需让位）。

---

## 1. 上游测绘（SpektraLab origin/main，file 级出处）

### 1.1 黑白胶片族 profile（数据结构正本）

- **资产**：`engine/resources_product/profiles/`——
  `kodak_tri_x_400.json` / `kodak_tmax_100.json` /
  `fujifilm_neopan_acros_100_ii.json` / `ilford_hp5_plus_400.json` +
  `ilford_multigrade_iv_rc.json`（相纸）+ `paper_grades.json` +
  `neutral_print_filters.json` + `NOTICE.md`。
  落地 commits：`4599179`（Tri-X + Multigrade IV RC + bw_checks.py）→
  `c0f8c7e`（T-Max/Acros II/HP5 三卷）→ `4bc2b20`（Debug 上架）→
  `b38e81f`（Release 上架，2026-10-09 owner 决定）。
- **schema = spektrafilm 同一 schema 的子集**（我方 `FilmProfile.swift`
  consumer face 完全覆盖）：`metadata`（datasource + tags 假设标注 +
  copyright + license）+ `info` + `data`。
  - `info` 增量键：`channel_model:"bw"`、`densitometer:"diffuse_visual"`
    （胶片侧；彩色片是 status_M）、`log_sensitivity_density_over_min:0.3`
    （相纸 0.6）、`target_print:"ilford_multigrade_iv_rc"`、
    `reference_illuminant:"D55"`（Acros 是 5400K 黑体谱）。
  - `data` 九键全同我方 consumer 面：wavelengths(81)、log_sensitivity
    (81×3)、channel_density(81×3)、base_density(81)、
    midscale_neutral_density(81)、log_exposure(256)、density_curves(256×3)、
    density_curves_layers(256×3×3)、density_curves_model（3-CDF 解析模型
    centers/amplitudes/sigmas——我方不消费，属 consumer face 之外的键）。
- **BW 数值形态**（Tri-X 实测 dump）：`log_sensitivity` 81 行**三通道逐位
  相同**（380nm -0.715 → 780nm -9.32，668nm 以上假设 log-linear 尾
  -0.0526 dex/nm 外推）；`channel_density` 全表 1/3；`base_density` 谱平
  0.286（135 base+fog @ CI 0.56）。
- **metadata 假设标注法**（我方自建资产直接照抄此纪律）：每个数组键注
  `SHEET`（表上量的）/`ASSUMED`（假设外推的）+ 具体外推率/锚——例如
  Tri-X `log_sensitivity` = "SHEET 380-668 nm (upper curve of p7),
  ASSUMED log-linear tail -0.0526 dex/nm above 668 nm; scale MEASURED so
  grey 0.184 -> raw 1"；`density_curves` = "SHEET for log_exposure
  -1.74..2.04 (D-76 large tank 7.72 min = CI 0.56, interpolated between
  the 6 and 8 min curves); ASSUMED flat toe below, ASSUMED straight line
  slope 0.473 into a ceiling of gross D 3.0 above"。
- **`channel_model` 在引擎里的消费 = 只有加载**（`engine/src/core/
  profile.cpp:60` 读 string，`profile.hpp:38` 默认 "color"；引擎渲染链
  grep 零分叉消费）——真正的 BW 语义（单通道化/中性银）全部由**数据本身**
  （三通道同值 + 1/3 密度）在通用谱链上涌现。App 侧消费 =
  `modern_UI/.../StockCatalog.swift:24`（`monochrome` 列表分组位）+
  `FeatureFlags.blackAndWhite` 上架门（`b38e81f` 起 Release 常开）。

### 1.2 变反差相纸（Multigrade）配对形态

- **相纸 profile = 三乳剂三通道谱**（ilford_multigrade_iv_rc.json 实测
  dump）：380-440nm 三通道同值（盲色公共段）；**460-540nm 三通道分裂**
  （480nm 处 ch0=0.272 / ch1=-0.487 / ch2=-1.439——三乳剂不同速度）；
  **≥560nm 全 -10**（盲色纸红光零感光）。`channel_density`=[1,1,1]，
  `reference_illuminant:"TH-KG3"`（放大机光源），`base_density`=0.06
  （相纸 Dmin）。
- **`paper_grades.json`**：grade "00"–"5"（无半档——表上没有）每档
  `{m_filter_neutral, y_filter_neutral, print_exposure}` 三元组，例：
  grade 2 = (m 0, y 68.0, exposure 1.0)；grade 5 = (m 151.7, y 0,
  1.3507)。拟合于 Tri-X，`bw_checks.py` 验证同表把其余三卷中灰打到
  同密度（"the pack is the paper's"）。
- **wire 机制**（`engine/src/core/params.cpp:71-73`）：
  `c_filter_neutral/m_filter_neutral/y_filter_neutral` ∈ [0,200] PRINT 域；
  引擎消费（`engine/src/core/printing.cpp:99-107`）= `cc[3]` = C 钉
  neutral + M/Y offset by shift → `color_enlarger(light, dichroics, cc,
  print_illuminant)` 谱域修正放大机光。App 侧另有
  `FilmParams.multigradeFilter2 = (c:0, m:0, y:68)` 常量（Params.swift，
  与 grade 2 表行一致）。
- **与我方映射**：我方 `SpectralBuildEngine.Parameters.printCC:
  SIMD3<Double>?`（`SpectralBuildEngine.swift:211`——nil = 自解中性
  pack，非 nil = 钉死）+ 印相腿 `illumPrintFor(cc m, y)`
  （`:558-572`，dichroicTransmissions 谱乘）——**grade 档 = printCC
  preset，逐字段平移，零新数学**。

### 1.3 camera_filter（滤色镜）——SHOOT 域，tc 表之前

- **数据**：`engine/src/core/camera_filters.hpp`——8 个 Wratten（w8 黄/
  w11 黄绿/w12 深黄/w15 深黄/w21 橙/w25 红/w47 蓝/w58 绿）各 81 点
  `double t[81]`（380-780nm 5nm）。来源注记 = "the Kodak B-3 tables,
  400-700 nm at 10 nm, as transcribed by P. Repacholi (Usenet, 1992;
  mat.uc.pt/~rps/photos/filter-data.html), linear to 5 nm, run out
  linearly below 400 and held above 700"。**交叉验证** = 对 Tri-X
  F-4017 p1 滤镜因子：7 个中 6 个 ≤0.21 档，No.58 偏 0.67 档。
- **wire**（`params.cpp:206,431`）：`camera_filter` 字符串枚举
  （''/w8/…/w58）SHOOT 域（"it changes the light the negative is made
  of"）；非法名 typed 拒绝。
- **作用数学**（`engine/src/core/hanatos.cpp:165-196` `film_sensitivity`
  内，**tc 表构建的输入侧**）：
  1. `out = 10^log_sensitivity`（感光度谱）；
  2. `factor = Σ(out_G·t·light) / Σ(out_G·light)`——**绿通道整卷单
     factor**（"One factor for the whole film, the green-sensitive
     layer's, so a colour film keeps the filter's cast; on a
     one-emulsion film the three are the same and 18% grey keeps its
     exposure — the filter factor is given"）；
  3. `out[l][c] *= t[l] / factor`——透射谱除 factor 归一后乘进感光度谱。
  同函数内还有 native `filter_uv/filter_ir` 带通（per-channel 归一）
  与 hanatos2025 window（我方 M8 已有同款 `:432-451`）。
- **边界**：film edge/date back 读未滤光谱（bw_checks.py check 5）。

### 1.4 granularity（per-film ownGrain）

- **commit `d610ac9`**（app 层 3 文件，引擎零改）：
  `modern_UI/Spektrafilm/Spektrafilm/Model/Params.swift` 的
  `FilmParams.ownGrain(of:)`——四 case 静态表：
  `kodak_tri_x_400: 1.70 / ilford_hp5_plus_400: 1.49 /
  kodak_tmax_100: 0.74 / fujifilm_neopan_acros_100_ii: 0.64 / default 1`
  （色片恒 1 = 零帧漂移）。
- **语义**：wire `grain_amount` 单位 = 发表 RMS granularity（µm 口径
  ×0.1：发表 17µm → 1.70）；换算公式 =
  `grain_amount = effects.grain × ownGrain(of: filmStock)` clamp 到
  `EffectStrengths.grainRange`（上限 2 → Tri-X 滑杆 1.18 到头、HP5
  1.34 到头——上游明示此 UX 短板）。
- **实测标定**（doc 注记，方法在 `research/bw-films/grain/`——该目录
  **不在此仓**，origin/main 无 research/ 顶层）：引擎自身 grain 1 在
  「6µm 像素 / 单层 / net density 1.0 / 48µm 孔径」下 RMS 10-11；四卷
  实测 17/8/7（Microfine 下限）/16。**即 wire 语义直读 RMS、乘数把滑杆
  归一到各厂发表值**。
- **stock 上架门**：`StockCatalog.swift` shared init 里
  `filter { FeatureFlags.blackAndWhite || !$0.isMonochrome }`。

### 1.5 上游验收 harness（golden 门形态直接参考）

`engine/tests/bw_checks.py`（python + ctypes dylib，overlay resources
目录）：五色块 chart（18% 灰/红/绿/天蓝/深蓝）+ 七档 ramp，五 check：
1. **中性**：Multigrade 印相 chart 三通道散 < 2e-3（银盐无色偏）；
2. **中灰**：filter 2 印 18% 灰 = displayed density 0.55-0.95 带；
3. **grade 单调**：00 < 2 < 5 密度跨度且 5 > 1.3×00；
4. **滤色镜**：w25/w47 下 18% 灰不动（|Δ|<0.01）+ 色块朝玻璃方向动
   （红滤镜红亮/天暗/蓝暗，蓝滤镜反之，阈值 0.05）；
5. edge 不透镜。
另 `neutral_print_filters.json`（product 版）= 四 BW 卷 + (Multigrade,
TH-KG3) 的 filter-2 pack，形态同 spektrafilm 表（我方 M3 已 vendor
彩色版同款文件）。

---

## 2. 数据面调研（本站特有重点）

### 2.1 厂商 datasheet 可得性（全部公开 PDF，逐份直链）

| 胶片 | 出版本 | 直链（2026-10-25 实测可达） | 图形态 |
|---|---|---|---|
| Kodak Tri-X 400 (400TX) | F-4017（上游用 Feb 2016 版） | business.kodakmoments.com 资源页（KODAK PROFESSIONAL TRI-X 320/400 Films PDF，9 页）；Scribd 有拷贝 | **矢量路径**（PDF 内嵌矢量图） |
| Kodak T-Max 100 (100TMX) | F-4016（June 2018 版） | `business.kodakmoments.com/sites/default/files/files/resources/f4016_TMax_100.pdf`（9 页） | 矢量路径 |
| Fuji Neopan 100 Acros II | AF3-0258E | `asset.fujifilm.com/.../AF3-0258E_PIB-NEOPAN-100-ACROSII-135-3_data-sheet.pdf`（4 页，Fuji 官方 asset CDN） | **300dpi 栅格**（上游按 600dpi 重采样描点） |
| Ilford HP5 Plus | HARMAN "HP5 PLUS Technical Information" Nov 2018 | `ilfordphoto.com/amfile/file/download/file/1903/product/691`；digitaltruth.com 镜像 `products/ilford_tech/hp5.pdf` | 栅格 |
| Ilford Multigrade IV RC | "MULTIGRADE RC PAPERS Technical Information" June 2019 | `ilfordphoto.com/wp/wp-content/uploads/2021/01/MULTIGRADE-IV-RC-Papers-060619.pdf`（5 页）；emsdiasum 镜像 | 栅格 + ISO R/P 表 |

每卷需要数字化：谱灵敏度曲线（~350-700nm 对数坐标）+ 特性曲线族
（D-76/显影时间组）+ 锚（ISO 速度、base+fog、log_exposure 锚——上游
Tri-X 锚 = 文献式 `0 = log10(0.8/400)+1.0 = -1.699 log lux-s`）。

### 2.2 数字化工作流（上游方法面，行为对照）

- 矢量 PDF（Kodak 两卷）：**抽矢量路径坐标**（上游 "vector paths of
  p7/p8"）——pdfplumber/pikepdf 抽 path 顶点，精度 = PDF 坐标系全精度，
  误差只来自轴标定（取轴刻度两端做仿射映射）。我方工具 =
  `uv run python3` + pdfplumber（红线允许；零新 SPM——这是数据工具链
  脚本，不进 app）。
- 栅格 PDF（Fuji/Ilford 三份）：600dpi 重采样 + 描点（上游 "charts are
  300 dpi images in the PDF, traced at 600 dpi"）；曲线提取 = 颜色阈值
  + 亚像素质心（曲线像素带宽 1-2px → 精度 ~1/600 inch，对数轴回读误差
  ~0.01-0.02 dex 量级）。
- **Acros II 特别注记**：谱图是 "spectrogram to daylight (5400K)"——
  上游把 5400K 黑体谱**除掉**还原感光度；HP5 谱图是钨丝灯 2850K——上游
  "taken as drawn"（该读法复现 Ilford 公表的日光滤镜因子）。这两条照抄
  上游口径（事实判断，非创意）。
- **谱尾外推假设**（380 以下/668-780 以上）：上游 log-linear 尾外推 +
  谱平 base —— 我方照抄形态、逐卷标注 ASSUMED 标签。
- **假设标注纪律**：每数组 SHEET/ASSUMED 标签进 metadata.tags（§1.1）——
  我方自建资产同款，golden 真值源 = 自建参考数学（§5）。

### 2.3 granularity 发表值独立溯源（须逐 PDF 核对）

上游 wire 值 1.70/0.74/0.64/1.49 ↔ 发表 RMS 17/7.4/6.4/14.9 µm。
公开检索佐证：T-Max 100 现行 F-4016 多处引 **RMS 8**（与上游 0.74=
7.4 有出入）；Acros II 一代 sheet 引 RMS 7（二代 6.4 待核）；Tri-X
17 与 HP5 14.9 无争议。**结论：四值全部以下载的官方 PDF 数据行核对为
准（执行批 T1 首任务），上游值只作交叉参考**——这正是「我方须独立
溯源确认」的本意。已知口径事实：Kodak 用整数 RMS（48µm 孔径扩散密度
1.0），Ilford 用一位小数，Fuji 按显影液别给值——不同厂测量口径本身
有 ±0.5µm 级差异，标定面按「发表值原样入表 + 口径注记」处理。

### 2.4 许可红线（数据面）

- **事实数据不受版权保护**（版权法传统立场；数字 = 测量事实）：厂商
  PDF 曲线采样点、RMS 值、Wratten 透射百分比——自建数字化合法，NOTICE
  引来源出版物编号即可（上游 NOTICE.md 同款立场："Built from Kodak
  publication F-4017. See NOTICE.md"）。
- **商标**：上游 NOTICE 注记 Kodak/Tri-X/T-Max/Fujifilm/Neopan/Acros/
  Ilford/HP5/Multigrade 是各自 owners' trademarks，名字只说数据出处。
  我方同款注记。
- **禁止**：复制 SpektraLab `resources_product/` 的任何数组（GPL 仓产品
  数据；即便 2026-10-20 起 GPL 同许可复制合法，charter 红线选择自建 =
  NOTICE 干净 + 无传染面，同 MIT LUT/CC BY-SA 谱面物理隔离先例）。
  上游 `camera_filters.hpp` 的 81 点表**不得复制**——从 B-3 转录源独立
  重录（数字同值不可避免——同一物理事实——但录入路径独立）。
- 我方资产落位：`Resources/FilmProfiles/profiles/` 追加自建 JSON？
  **不行**——该目录 = CC BY-SA spektrafilm 包（MANIFEST.sha256 对账 +
  逐字节冻结纪律）。自建 BW 族应落**新目录**（如
  `Resources/FilmProfilesBW/`，或同目录分层——plan 批 KD 裁决），
  NOTICE/MANIFEST 独立，许可注记 = "digitized from manufacturer
  publications, factual data"。

### 2.5 Wratten 透射数据源（最难一件的解法）

上游引用页 `mat.uc.pt/~rps/photos/filter-data.html`（Repacholi 1992
Usenet 转录）**实测只含 No.25/29/70 + IR 系（89B/88A/87/87B/87C）+ 1A**
——8/11/12/15/21/47/58 不在该页（应在同系列 Usenet follow-up 帖，页面
未收全）。独立替代源（已检索确认存在）：

1. **karmalimbo.com "Transmission of Wratten Filters" PDF**——8 页 B-3
   手册数字化表，10nm 间隔 400-700nm，含 No.8/15/21/25 等（百分比
   数值表）——最直接的独立转录源；
2. **Kodak 官方 Wratten 2 页**（kodak.com/en/motion/page/
   wratten-2-filters）——官方可下载透射曲线（现代复刻版玻璃，曲线与
   历史 B-3 同源）；
3. 兜底：archive.org B-3 手册扫描本 / FSU microscopy primer 图表。

**风险处置**：多源交叉（karmalimbo vs Kodak Wratten 2 曲线）取一致值；
**上游 camera_filters.hpp 表可作只读对照**（第三源交叉验证，6/7 滤镜
因子 ≤0.21 档的验证法照抄——用我方 Tri-X 谱乘我方透射表算滤镜因子对
F-4017 p1 表）。数据格式 = 400-700nm 10nm（B-3 原表）→ 线性插值 5nm
→ <400 线性外推 / >700 持平（上游处理法，§1.3）。

### 2.6 数据量汇总（工作量表）

| 条目 | 数量 | 工时估 |
|---|---|---|
| BW 胶片 profile | 4 卷（谱曲线 + 特性曲线族 + 锚 + tags） | 矢量 2 卷（工具化后各 ~0.5 天）+ 栅格 2 卷（各 ~1 天） |
| 相纸 profile | 1 份（三乳剂谱 + grade 曲线族 + ISO R/P 表） | ~1 天（最重——三通道谱 + 多 grade 曲线） |
| paper_grades 表 | 7 档 × (m,y,exposure) | 计算件非数据件：我方 solve 链拟合 + 四卷中灰验证（~0.5 天） |
| Wratten 透射表 | 8 滤镜 × 81 点 | ~0.5 天（转录 + 双源交叉 + 插值） |
| granularity 表 | 4 值（逐 PDF 核对） | ~0.5 小时 |
| 数字化工具脚本 | pdfplumber 抽路径 + 栅格描点 + 轴仿射 | ~1-1.5 天（一次建成，后续 profile 复用） |

---

## 3. 我方基建盘点（file:line）

### 3.1 M8 光谱核（消费面全就绪）

- **profile schema**：`LightamerCore/Sources/Film/FilmProfile.swift:148,160`
  ——`channelModel`（channel_model）**已在 consumer face decode**（M8-1a
  已开）；`logSensitivity/channelDensity/midscaleNeutralDensity` 六谱键
  已 decode（`:225-233`，tolerant + null-aware projection 家族）。
  BW profile 落盘即被现有 loader 全量接受，**schema 零改动**。
- **tc 展开消费链**：`LightamerCore/Sources/Film/SpectralBuildEngine.swift`
  ——`build(film:paper:parameters:)` `:354`；`filmSens = 10^logSensitivity`
  `:374-381`；window 乘+归一 `:431-451`（滤色镜同构插入点）；**tc 展开
  循环 `:453-474`**（`acc[c] += spectrum(λ)·sensW[l][c]`——滤色镜改
  `sensW` 即改全链，零 kernel 触碰）；印相腿 `illumPrintFor(cc m,y)`
  `:558-572`（dichroicTransmissions 谱乘——grade 档直接消费）；
  `Parameters.printCC` `:211`（nil=solve / 非 nil=钉死——**grade 的
  天然载体**）。
- **bake 家族**：`LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift:287-343`
  （密度臂 Cache LRU 16）+ `:345-` SpectralPrintBake（M8-2 X7 三槽：
  tc 6 / print PCHIP 8 / scan PCHIP 8，键 = materialPairHash）。
- **film leg 装配**：`LightamerCore/Sources/Pipe/PixelPipe.swift:1206-1266`
  `runFilmLeg`——统计腿 + `assembleFilmLeg`（X4 process fork：v1 密度 /
  v2 光谱）+ seed 折叠（solvedPackHash + policyTag
  `lightamer.film.subrun.v2-spectral`，`FilmTailPolicy.swift:99`）。
- **kernel 冻结红线**：`FilmSubRunKernels.metal`（M3-3-02 密度臂 v1，
  冻结）/ `SpectralFilmKernels.metal`（M8-1b 光谱臂，dt spektrafilm.cl
  GPL-3.0 移植，M8 收口冻结）——**本站预期两个 .metal 全零 diff**。
- **process**：`RenderProcess.swift:90` current = 2（光谱核生产代）。

### 3.2 M3 密度域 s_m/s_y（滤色镜光谱精确化的对照基线）

- `LightamerCore/Sources/Film/FilmFilterPackSolver.swift:70-74`——
  `magentaExposurePerCC = 0.0085` / `yellowExposurePerCC = 0.017`
  （2:1 dichroic 经典比，M dial 只作用 GREEN、Y 只作用 BLUE 的密度域
  简化向量 `[0,1,0]/[0,0,1]`）。**光谱域精确化后此简化仍是 v1 密度臂
  语义**（冻结），光谱臂用 dichroicTransmissions 谱乘（M8 已建）——
  滤色镜与 dichroic 是两回事（镜头前置 vs 放大机头），互不替代。
- `FilmRecord` 七字段（`Graph/FilmRecord.swift:51-80`）：filmStock/
  paperStock/yFilterShift/mFilterShift（CC 0-100 manual shift）/
  contentAdaptiveShift/strength/exposureEv——**无 cameraFilter、无
  paperGrade**（本站两个新字段位）。
- solve 缓存键（M3-3-02）：`fnv(materialPairHash ⊕ statsHash ⊕ modeTag)`
  ——滤色镜进 record 后须折 recordHash（stableHash 含新字段自动生效，
  `FilmRecord.swift:44-48`）。

### 3.3 grain IOP（M9BW-03 标定面）

- `LightamerIOP/Sources/Grain/GrainModule.swift:50-75`——dt 遗产三滑杆：
  scale（dt 域 [20/213.2, 6400/213.2]，UI 显 ISO = scale×213.2）、
  strength ∈[0,100] 默认 25、midtonesBias。**无 per-film 概念，strength
  = dt 相对量**——与上游「滑杆 1 = 发表 RMS」语义不同，标定面 = 在
  film→grain 之间建换算（见 §4 方案）。

### 3.4 缺口清单（差距）

| 面 | 现状 | M9-2 差距 |
|---|---|---|
| BW profile 资产 | `Resources/FilmProfiles/profiles/` 28 卷全彩色（CC BY-SA） | 4 BW 卷 + 1 相纸自建（新目录 + 独立 NOTICE/MANIFEST） |
| channelModel 消费 | decode 即弃（无 UI/逻辑消费） | stock 分组位（Film 面板 picker）；BW 与色片行为差异全由数据涌现 |
| paper grades | 无（只有连续 m/yFilterShift manual shift） | grade 离散档（printCC preset + printExposure）+ UI picker |
| camera_filter | 全仓零面 | FilmRecord 新字段 + build 期乘法 + bake 键扩展 + UI |
| granularity 标定 | 无 | per-film 表 + 强度语义换算 + 断言 |
| materialPairHash | fold 集不含谱面键（§0.5） | bake 键扩展（filter/grade tag 折入）——**本站最重架构件** |
| Film 面板 | film/paper 双 picker 现成（`FilmPanelModel.swift:93-100`） | grade picker + filter picker 两新控件 + BW 分组 |

---

## 4. 差距矩阵 + 方案骨架（M9BW-01..03 → 交钥匙缝）

### M9BW-01 黑白胶片族 profile 自建

| | |
|---|---|
| 复用件 | FilmProfile schema（零改）、FilmMaterialStore（目录注入自动索引 BW stock）、SpectralBuildEngine 全链（零改）、SpectralPrintBake、FilmPanelModel picker（自动出现）、FilmRecord.filmStock/paperStock |
| 新建件 | ① 数字化工具脚本（pdfplumber 矢量 + 栅格描点 + 轴仿射 + tags 生成）；② 4 卷 BW profile JSON（SHEET/ASSUMED 标注法照抄）；③ 相纸 1 份；④ 独立 NOTICE/MANIFEST（新资源目录）；⑤ 中性/阶调 golden（§5） |
| 交钥匙缝 | **黑白域 = 谱面包新条目，仅此而已**——三通道同值数据经现有谱链自然单通道化；BW stock 默认 target paper = Multigrade（FilmRecord.paperStock 默认值在 UI 层给） |
| 验收映射 | REQUIREMENTS「profile 入谱面体系 + MANIFEST 对账 + 中性/阶调 golden ✓」→ golden = §5 门 1/2 |

### M9BW-02 变反差相纸 + 镜头滤色镜

| | | |
|---|---|---|
| **相纸 grade** | 复用：`Parameters.printCC` 钉死缝 + `illumPrintFor`；新建：`paper_grades` 自建表（grade→(m,y,exposure)，我方 solve 链拟合 + 四卷中灰验证 = 上游 bw_checks 法平移）+ FilmRecord `paperGrade: Int?`（nil = 现 solve 行为零漂移）+ grade picker UI；缝 = **bake 家族新 pair 变体**——grade 改变 print/scan PCHIP 输入，printCC 必须折进 SpectralPrintBake print/scan 槽键（tc 槽不受影响） |
| **camera_filter** | 复用：`sensW` 窗口段邻位（SpectralBuildEngine `:431-451` 后插 t[λ]/factor 乘法，hanatos.cpp:171-183 同构——绿通道 factor 归一保 18% 灰）；新建：8 滤镜透射表资产（独立 JSON，双源转录）+ FilmRecord `cameraFilter: String?`（nil/""=无，SHOOT 域语义 = decode 后 film leg 输入即乘，我方 decode 段无对应 iop——**film leg 是唯一正确座位**，不上 v50 序新 iop）+ filter picker UI + **bake 键扩展**（filterTag ⊕ pairHash——tc_lut 是 sensW 的函数，同 pair 不同滤镜必须分槽）；缝形态 = **材料链前置算子（build 输入侧），非 coupler 扩展、非新 iop** |
| 验收映射 | 「滤色镜 ON/OFF 中性链零漂移负测」= 无 filter 档逐字节 = 现行输出（seed fold + 恒等分支）；「光谱透传 golden」= §5 门 3/4 |

### M9BW-03 per-film granularity 标定

| | |
|---|---|
| 复用件 | GrainModule 本体（零 diff——D-M8-4 空间族挂账不解冻算子）、FilmMaterialStore 索引 |
| 新建件 | per-film 标定表（stock → published RMS µm + 口径注记，逐 PDF 溯源后入表；落位候选 = BW 资产目录侧表或 profile metadata 新键——plan KD）+ **强度语义换算件**：film 面板/grain 面板之间的桥（形态候选 A = 上游 ownGrain 式静态乘数、形态候选 B = GrainModule 强度标定曲线 per-film 重释义——**注意我方 strength 是 dt [0,100] 而 wire 语义不同，须做量纲桥**：滑杆语义重定义 = 观感变更 → 若改 GrainModule 默认渲染面则触 process 红线，若只在「film stock 感知的推荐强度」层做则零 bump——plan KD 裁决）+ 强度语义断言单测 |
| 交钥匙缝 | 仅标定面（OQ-M9-8 推荐），grain 算子接谱继续挂 M8 D-M8-4 族 |

### process 号协调（§0.6 展开）

| 变更 | 存量观感 | 判定 |
|---|---|---|
| BW 新 stock | 不可达（新 id） | 零 bump |
| cameraFilter 字段 | 缺席 = 恒等分支 + seed 不折（「非 none 才折」先例 = DRT policyTag 折叠法） | v2 内 additive |
| paperGrade 字段 | 缺席 = printCC nil（现行为） | v2 内 additive |
| granularity 标定 | grain iop 参数面不动（若 KD 选推荐强度层） | 零 bump |
| **结论** | — | **本站全站零 bump；RenderProcess.current=2 不动；v3 留给 M9-4 ColorWheels（其 LGG 公式重写 = 真观感变更）**。若 granularity KD 选「strength 语义重定义」臂则该子件单独评估（建议避开） |

sidecar：FilmRecord 两新 optional 键（cameraFilter/paperGrade）decode
tolerant；按 M7-4 note 归属先例（additive 字段批走 bump），建议
**schema v12**（plan KD 确认；v11 内 additive 亦技术上可行——
decodeIfPresent 语义两向兼容）。

---

## 5. golden 真值源（无上游可对照——自建参考数学）

四门（bw_checks.py 形态平移 + 我方 golden 纪律 L048 比较 space）：

1. **中性门**（BW 数据正确性）：五色块 chart（18% 灰/红/绿/天蓝/深蓝）
   过 (BW film, Multigrade) 全链 → 输出三通道散 ≤2e-3（银盐印相无色偏
   ——三通道同值谱数据 + 1/3 密度的结构性验证）；
2. **阶调门**：grade 00<2<5 密度跨度单调 + 5>1.3×00 + 18% 灰 displayed
   density 落 0.55-0.95 带（printCC preset 正确性）；
3. **滤色镜零漂移负测**：cameraFilter nil 档输出与 M8 基线逐字节一致
   （恒等分支 + seed 折叠验证）+ filter 档 18% 灰 |Δ|<0.01（factor 归一
   验证）+ w25/w47 色块方向断言（红滤镜红亮天暗蓝暗 / 蓝滤镜反之）；
4. **数字化精度门**（数据面真值）：采样曲线 vs 厂商 PDF 控制点回读
   （轴仿射后残差 ≤ 读图精度带；特性曲线斜率段 vs sheet 标称 gamma/CI）
   + 滤镜因子交叉（我方谱×我方透射表算 factor 对 F-4017 p1 表，
   上游 6/7 ≤0.21 档基准）。

精度预算（风险量化）：矢量 PDF 抽路径 ≈ 坐标全精度（误差 ~1e-3 dex）；
栅格 600dpi 描点 ~0.01-0.02 dex（对数轴）→ 对 golden 带 2e-3 中性门
无碍（中性门是结构性的，不依赖绝对标定）；对特性曲线形状的影响 =
打印观感级差异，无 bit 对照对象（自建即正本），登记即可。

---

## 6. 风险与 OQ

### 风险表

| # | 风险 | 量级 | 处置 |
|---|---|---|---|
| R1 | **bake 键不扩展 → 滤镜/grade 撞缓存出错误复用**（materialPairHash fold 集本就不含谱面键，`FilmMaterialStore.swift:115-151`） | 高（正确性） | 本站必做件：filterTag/gradeTag 折入 SpectralPrintBake 三槽键 + materialPairHash fold 集与消费集对齐（谱键入 fold——顺带修 M8 遗留漂移，注意 CC 资产 hash 变更无碍：hash 只做缓存键不做持久身份） |
| R2 | Wratten 8 滤镜表独立源转录（mat.uc.pt 页不含） | 中 | §2.5 双源交叉 + 滤镜因子验证法；若两源都缺某滤镜 → 该滤镜砍掉（8→N，UI 列表跟数据走） |
| R3 | 栅格 PDF 描点无现成自动化（Fuji/Ilford 三份） | 中 | 工具脚本一次建成（§2.6）；Acros 5400K 除谱、HP5 2850K 口径照抄上游判断 |
| R4 | granularity 发表值口径差（T-Max 8 vs 7.4 等） | 低 | 逐 PDF 核对 + 口径注记入表；标定面按发表值原样 |
| R5 | Multigrade IV RC 已停产（2023，替代 MG V）——历史 sheet 仍官方可下载 | 低 | 照上游用 IV RC 2019 sheet（产品语义 = 经典暗房；MG V 留后续资产增量） |
| R6 | tc_lut 构建秒级 × 滤镜变体 → 缓存槽压力（tc 6 槽） | 低-中 | 滤镜档构建按需 + LRU 淘汰；probe RSS 面监控（滤镜切换交互预算 = 构建一次后缓存命中） |
| R7 | BW 相纸三乳剂数据数字化工作量（grade 曲线族 × 7 档） | 中 | 相纸谱 + 2-3 条代表 grade 曲线入 profile；全 7 档 m/y/exposure 走**拟合**（计算件）而非逐档描曲线 |

### OQ 清单（新开，plan 批裁决）

| OQ | 问题 | 推荐 |
|---|---|---|
| OQ-M92-1 | granularity 标定落位：profile metadata 键 vs 独立表 vs GrainModule 静态表 | 独立表（BW 资产目录侧 grain 标定 JSON）——grain iop 零 diff 最稳 |
| OQ-M92-2 | granularity 强度语义形态：推荐强度层（零 bump）vs strength 量纲重定义（触红线） | 推荐强度层（面板给 per-film 推荐值 + 换算 readout；不动 GrainModule 渲染语义） |
| OQ-M92-3 | BW 资产目录形态：`Resources/FilmProfilesBW/`（与 CC 谱面物理隔离）vs FilmProfiles 子目录 | 独立目录（NOTICE/MANIFEST 独立、许可注记干净——LUT/FilmProfiles 先例） |
| OQ-M92-4 | sidecar bump：v12 vs v11 内 additive | v12（M7-4 先例：additive 字段批走 bump，语义清晰） |
| OQ-M92-5 | bake 键扩展形态：filterTag⊕pairHash（推荐）vs Parameters 全量序列化键 | filterTag⊕pairHash（同 policyTag 折叠法先例）；grade 同款 gradeTag 折 print/scan 槽 |
| OQ-M92-6 | 滤色镜 UI 座位：Film 面板 SHOOT 节 vs 独立 picker | Film 面板新节（SHOOT 域语义标注） |
| OQ-M92-7 | BW stock 分组：picker 混排 vs 分节（channelModel 消费位） | 分节（monochrome 分组位 = StockCatalog 形态对照；零 GPL 复制） |
| OQ-M92-8 | 滤镜集合裁剪：8 全上 vs 首发砍 w58（上游因子验证偏 0.67 档的那枚） | 8 全上 + 数据侧注记（用户可自见偏差异；砍不砍留晨审） |

**process 号协调建议（汇报项）**：本站零 bump（§4 表）；RenderProcess
v3 预定继续归 M9-4 ColorWheels（真观感变更），两站无冲突、无需让位。

---

## 7. 证据锚点速查

| 事实 | 锚 |
|---|---|
| BW = 三通道同值纯数据 | `SpektraLab origin/main: engine/resources_product/profiles/kodak_tri_x_400.json`（log_sensitivity 三通道逐位同 / channel_density=1/3；dump 在案） |
| 相纸三乳剂谱分裂 + 盲色截止 | 同上 `ilford_multigrade_iv_rc.json`（480nm 0.272/-0.487/-1.439；≥560nm 全 -10） |
| grade→(m,y,exposure) 表 | `engine/resources_product/paper_grades.json`（grade 2 = m0/y68/1.0） |
| 滤色镜乘法点（tc 前 + factor 归一） | `engine/src/core/hanatos.cpp` `film_sensitivity`（kCameraFilters 循环 + 绿通道 factor） |
| 滤色镜数据 + B-3 转录源 + 因子验证 | `engine/src/core/camera_filters.hpp`（头注：Repacholi 1992 mat.uc.pt；6/7 ≤0.21 档） |
| ownGrain 四值 + 实测 17/8/7/16 + wire 上限 2 | commit `d610ac9`（Params.swift ownGrain + 注记） |
| 上游验收五 check | `engine/tests/bw_checks.py`（中性/中灰/grade 单调/滤镜方向/edge） |
| channel_model 仅加载无消费 | `engine/src/core/profile.cpp:60` + `profile.hpp:38`（默认 color） |
| 上游 NOT ICE/许可立场 | `engine/resources_product/NOTICE.md`（"Built from Kodak publication F-4017" + 商标注记） |
| 我方 channelModel 已 decode | `LightamerCore/Sources/Film/FilmProfile.swift:148` |
| 我方 tc 展开循环（滤镜插入点） | `LightamerCore/Sources/Film/SpectralBuildEngine.swift:453-474`（窗口段 `:431-451` 邻位） |
| 我方 printCC 钉死缝（grade 载体） | `SpectralBuildEngine.swift:201-211` + `illumPrintFor :558-572` |
| 我方 bake 三槽 + 键 = pairHash | `LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift:345-` |
| hash fold 集不含谱面键（R1） | `LightamerCore/Sources/Film/FilmMaterialStore.swift:115-151` |
| s_m/s_y 密度域常量 | `LightamerCore/Sources/Film/FilmFilterPackSolver.swift:70-74` |
| grain dt 遗产参数面 | `LightamerIOP/Sources/Grain/GrainModule.swift:50-75` |
| FilmRecord 七字段（无 filter/grade） | `LightamerCore/Sources/Graph/FilmRecord.swift:51-80` |
| process v2 + policyTag | `LightamerCore/Sources/Pipe/RenderProcess.swift:90` + `FilmTailPolicy.swift:99` |
| sidecar v11 现行 | `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:255` |
| Film 面板双 picker | `App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift:93-100` |
| M8 挂账（空间族不入） | `.work/gsd/phases/m8-fsim-spectral/CONTEXT.md` D-M8-4 |
| Tri-X F-4017 官方 PDF | business.kodakmoments.com（KODAK PROFESSIONAL TRI-X 320/400 Films） |
| T-Max F-4016 官方 PDF | `business.kodakmoments.com/sites/default/files/files/resources/f4016_TMax_100.pdf` |
| Acros II AF3-0258E 官方 PDF | `asset.fujifilm.com/.../AF3-0258E_PIB-NEOPAN-100-ACROSII-135-3_data-sheet.pdf` |
| HP5+ 官方 PDF | `ilfordphoto.com/amfile/file/download/file/1903/product/691`（digitaltruth 镜像） |
| Multigrade IV RC 官方 PDF | `ilfordphoto.com/wp/wp-content/uploads/2021/01/MULTIGRADE-IV-RC-Papers-060619.pdf` |
| Wratten 替代转录源 | karmalimbo.com "Transmission of Wratten Filters" PDF（B-3 数字化 10nm 表）+ kodak.com Wratten 2 官方页 |

（上游读解全部经 `git show origin/main:` 于本地 SpektraLab 仓完成，
零 clone、零改动。）

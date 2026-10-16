# M8 RESEARCH-PRE — FSIM 光谱升维（Spectral Film Core）轻量 research

> 性质 = **提前排队件**：M8 预告立项（charter-pending，M7 收口后正式 charter）的输入底稿，
> 非正式 research 环交付。正式 charter 时本文件 §7 Open Questions 转裁决点、§3/§4/§5
> 转 plan 输入；不足处以 charter 批补research（如需）。
> 日期：2026-10-17（夜间自动批；授权先例 D-07-3-T5-1，晨审可推翻）。
> 上游输入 = M3 FSIM 族全部增量（AGENTS「M3-3/M3-4 架构增量」节 + `phases/m3-2-fsim-research/RESEARCH-NOTES.md` + `phases/m3-3-fsim/M3-3-0{1,2,3}-DECISIONS.md` + `phases/m3-4-latitude/`）+ M6-2 process version（`phases/m6-2-process-version/RESEARCH-NOTES.md`）+ CC BY-SA 资产先例（`Resources/FilmProfiles/` 五件套 + NOTICE）。
> 外部读解纪律：darktable spektrafilm 模块族（`src/iop/spektrafilm.c` 头注释 + `src/common/spektra_sim.h` / `spektra_fetch.h` + `data/kernels/spektrafilm.cl`）= **GPL-3.0 只读**——本文所有引用为读解定位，**代码/表数据零拷贝**；SpektraLab（GPL 代码 + CC BY-SA 资产）同规；Jakob & Hanika 2019 论文 = 公开学术数学面，合法参考。

---

## §1 M8 定位（一句话 + charter-pending 状态）

**M8 = FSIM 光谱升维**：把 M3-3/M3-4 交付的 RGB 密度域染料近似核升维为 darktable
spektrafilm（2026 native 模块，GPL 只读读解）同级的**逐波长光谱材料链**——scene-linear
RGB → CAT 至胶片参考光源 → xy → **光谱上采样**（tc 系数表，自拟合）→ 胶片感光积分
→ 显影（DIR coupler）→ dichroic 放大机配光 → 相纸 → 扫描 CMFs → working RGB + gamut
压缩；经 M6-2 process version 通道迁移（光谱核 = 新 process 臂，密度核冻结 legacy 臂）。

- **状态 = charter-pending**：本文件与四正本预告落账为挂账；正式立项（phase 表 / SC 门 /
  范围红线 / OQ 裁决）随 M7 收口批落账。
- 排队理由（用户裁决背景）：dt 已在生产路径证明该面消费级可达 + 我方 FSIM 资产
  （28 profile 的 81 波长谱面）本就随文件携带、升维后从「不消费」翻为「直接消费面」
  + M6-2 process 机制恰好为「改观感的核换代」备好迁移通道。

## §2 FSIM-01c 精度修正（「光谱不可达」边界的收窄——本 research 的核心交付）

### 2.1 原注记（M3-2 RESEARCH §2 / AGENTS M3-3 增量节 / REQUIREMENTS FSIM-01c）

「CIRAW 解码后 RGB 起步，81 波长光谱重放架构性不可达（光谱信息解码即折叠）……
不可达面：metamerism 级行为、染料光谱交叉吸收的波长依赖细节、滤色头光谱形状效应、
与光谱引擎逐波长一致的渲染输出。」——M3-3/M3-4 的密度域核按此边界落地，正确。

### 2.2 dt spektrafilm 的架构事实（读解正本，模块头注释 + spektra_sim.h）

dt 的链**同样不是场景光谱重放**——链头是**光谱上采样**（metameric reconstruction）：
逐像素把 RGB 色度转成一条确定性的 81 波长光谱（hanatos2025 tc LUT → sigmoid 模型
系数 → 谱重建），再跑完整的逐波长材料前向（感光度积分 / DIR couplers / dichroic
滤光 × 相纸感光 / 观察 CMFs）。即光谱信息**同样**没有从传感器恢复——它由色度
**重建**。

### 2.3 修正后的三分口径（替代原二分「可达/不可达」）

| 面 | 可达性 | 依据 |
|---|---|---|
| ① 场景真实光谱功率分布（true SPD）重放 | **不可达（维持）** | CFA 积分折叠不可逆——原注记正确的部分 |
| ② **重建谱上的逐波长材料链模拟**（上采样谱 × 胶片 × 光源 × 相纸 × CMFs） | **可达** | dt spektrafilm 生产路径已证；81 点谱轴（380-780@5nm）与我方 profile 资产完全一致 |
| ③ metamerism 级保真（相对真实胶片相机捕获） | **不可达（维持）** | 上采样从色度固定选一条确定性 metameric 谱；与相机 SSF 捕获的谱不保证同谱 |

**结论**：FSIM-01c 的「光谱引擎不可达」应收窄为「**场景光谱重放**不可达」；「逐波长
材料链」可达且 dt 已工程化。M8 的对象 = ②。措辞影响（charter 裁决点 OQ-M8-6）：
NOTICE 消费披露行与用户可见措辞「物理流程建模，非光谱重放」在 M8 落地批升格为
「光谱重建材质模拟（逐波长），非场景光谱重放」——NOTICE 是我方文件可改；上游
profile JSON 仍字节原样不动；本 RESEARCH-PRE 不改历史文档原文（勘误行追加惯例）。

### 2.4 资产侧翻面

M3-3-01 KD-3 的消费面裁决「光谱 payload 不进类型面且不可能回漏」（base_density 三点
投影是当时唯一登记的谱面消费）在 M8 语境下自然重开：`data.log_sensitivity`（81×3
感光度）/ `data.channel_density`（81×3 CMY 染料密度）/ `base_density`（81 点橙罩谱）/
`wavelengths`（轴）从「随文件携带」翻为**直接消费面**。CC BY-SA 归属义务面不变
（同文件本就携带，NOTICE 纪律已覆盖）；消费面披露行随 OQ-M8-6 同批修订。

## §3 数学核测绘（hanatos2025 / Jakob-Hanika 公开面 + 我方 clean-room I/O 规格草案）

### 3.1 dt 管路全貌（GPL 只读读解，勿移植）

```
scene-linear work RGB
  → CAT16 至胶片参考光源 → xy → 光谱上采样（hanatos2025 tc LUT）
     × 胶片感光度                                        = 相机曝光（expose）
  → highlight boost / diffusion / halation（线性域，空间）   [调用侧]
  → log exposure → DIR coupler correction（模糊场）→ CMY 胶片密度（develop）
  → grain（密度域，空间）                                  [调用侧]
  → 放大机：dichroic 滤光透过负片 × 相纸感光 × 中灰配平（print_expose）
  → print diffusion filter（可选，空间）
  → 相纸密度曲线（contrast morph 可选）（print_develop）
  → 观察光源透过印品 → CMFs → XYZ → CAT02 → work RGB → OkLCh gamut compression（scan）
```

- dt 定位注记（模块头原文）：「This is a scene-to-display view transform: enable it
  INSTEAD of sigmoid / filmic / agx」——对应我方 = film sub-run 位置语义（grades 后、
  DRT 前），双链正交无冲突。
- 数据包形态（spektra_sim.h / spektra_fetch.h）：pack = `pack.json` +
  `spectra_lut.f32` + `profiles/`，tens of MB；表身份 = `lut_hash`（逐档记账）+
  `pack_hash`（整包）；表 kind 二值 = **irradiance**（谱已按胶片参考光源投影，
  感光度预配平使中性落 1）/ **reflectance**（需按场景白重投影）；上游出货表 =
  `hanatos2025`（`irradiance_xy_tc@0.3.3`），边长 192（读侧上限 `SF_TC_N_MAX`=4096）。
- **GPU 路径关键工程事实**（spektrafilm.cl 头注释 + expose 核读解）：
  1. **每 sim 构建期把「谱重建 × 感光度积分」预折进 tc 表**（「the tc LUT … built
     once per sim」）——运行期 expose = 矩阵 → xy → `tri2quad`（`u=(1−x)²`、
     `v=y/(1−x)` 四边形映射，覆盖**全域色度含光谱轨迹内部**）→ 192×192×3 f32 表
     的 2D Mitchell-cubic 一次 fetch 出 float3 曝光 → ×亮度×EV。**逐像素无 81 波长
     循环**。
  2. 重积分（print_expose / scan）= **运行时构建的 3D 单调 PCHIP 插值表**
     （`use_enlarger_lut` / `use_scanner_lut` 双臂；CPU 侧可逐像素精确、GPU 用表）。
  3. GPU 全 float（CPU 引擎 double），POCL 对 CPU 验证 ~1e-6。
  4. DIR coupler correction 是唯一逐像素链内的空间步（模糊场，host 侧 YVV blur）；
     grain/halation/diffusion 全部留在调用侧。
- 感光度适配两半（模块头「The two halves of the hanatos2025 sensitivity adaptation」）：
  上游表 → 逐胶片适配发生在 per-sim 构建期（表本体跨胶片共享）。

### 3.2 tc LUT 的公开数学底座

- 模型族 = **Jakob & Hanika 2019**《A Low-Dimensional Function Space for Efficient
  Spectral Upsampling》（EGSR 2019）：平滑 sigmoid 谱
  `σ(λ) = c0·(1+exp(c1λ+c2))⁻¹`，逐色度拟合三系数，LUT 按色度索引预计算；官方参考
  实现 mitsuba-renderer/rgb2spec，colour-science `colour.recovery`（BSD）同族实现。
  「tc」= 系数表形态（transition/curvature 族参数）；irradiance kind = 谱按参考光源
  投影后的辐亮度语义。
- hanatos2025 表 = dt 生态（hanatos，dt/vkdt 开发者）2025 自建变体：sigmoidal 上采样
  覆盖**全色度四边形**（tri2quad 域含光谱轨迹内部——比我方若用 sRGB 三角域更广；
  对 Rec2020 working space 的域覆盖是刚需，见 §3.3）。
- **clean-room 合法通道**：论文数学 + BSD 参考方法 → 自拟合。hanatos2025 表本体 =
  GPL 项目侧数据产物，**不当拷贝对象**（OQ-M8-2 推荐 = 自拟合）。

### 3.3 我方 clean-room 输入输出规格草案（charter 期细化为准）

- **输入平面**：working linear Rec2020 float32（film sub-run 现行输入契约不变）。
- **构建期**（per 材料/参数 commit，落现行 `FilmMethodBox` run-scoped GPU payload +
  bake LRU 机制）：
  1. **per-sim tc 表**：canonical 系数表（192×192 tri2quad 域，自拟合）→ 谱重建
     （81 点）× `log_sensitivity` 积分（Float64，sRGB 中性配平核验）→ 192×192×3
     f32（~442KB，texture2d）；构建耗时估 <100ms 级（见 §5 probe ①）。
  2. **印相/扫描表**：dichroic SPD（滤光曲线 × 密度模型）× 相纸 `log_sensitivity`
     × 负片透射 → 印相曝光表；观察 SPD × CMFs 1931 2° → 扫描积分表——构建期
     预折（OQ-M8-3 推荐 3D 表臂）。
  3. 矩阵/常数块：working→XYZ、CAT（至 `info.reference_illuminant`）、CAT02→working、
     OkLab 矩阵族——全公开标准公式。
- **运行期逐像素**（单 sub-run，fused 候选形）：
  ```
  RGB → XYZ → xy → CAT → tri2quad → tc 表 2D cubic fetch（曝光 float3）
    → log10 → 曲线查表（256 点 log-exposure 网格，与现行密度核同轴）
    → [可选 DIR coupler：+ 模糊校正场] → CMY 密度
    → 印相表 fetch → 相纸曲线/反演 → 扫描表 fetch → XYZ
    → CAT02 → working RGB → OkLCh gamut compression →（交 DRT tail）
  ```
- **域语义平移**（charter 期逐条钉）：strength 0 = 直通（现行 delta/log 域强度混
  语义在谱域对应物）；pristine 门（缺 FilmRecord = 零路径）不变；缩略图恒 legacy
  不变；`filmRampPlaneHash` 哨兵按重钉流程登记翻值。

## §4 融合点测绘（与既有 film sub-run 缝的接法）

### 4.1 位置与缝：零改

- 光谱核 = `FilmMethodBox` 的新 payload/kernel；`runTerminalTails` 共享序
  （film → DRT tail → display replay）、`filmTailPolicy(for:)` 3×2 降出矩阵、导出
  递缝（`Job.filmTail` + `$jobFilmTail`）全部零改——换的只是 film 腿内核。
- dt「替代 sigmoid/filmic 启用」语义在我方无对应需求：film 腿启用即接管材料域，
  DRT tail 照常工作（film 在 DRT 前，域正交）——M3-3 已定形。

### 4.2 双核并存 = process 纪律的必然而非选项（M6-2 落地兑现的第一个真实场景）

- 光谱核改观感 = 语义变更 → **bump process**（建议 `process 2` = 光谱臂 current；
  `RenderProcess` 枚举账本开第二 case，doc-comment 即账本）。
- 老 `.lra`（process 0/1）按冻结语义继续走**密度核**渲染——密度核留代码 = 冻结
  legacy 臂（LightCraft V1 冻结同构；dt 侧同构物 = 逐档 `lut_hash`/`pack_hash`
  记账，我方以 process 承载同语义）。
- 文档级 process → film 引擎映射：`process ≤ 1` = 密度核；`process ≥ 2` = 光谱核。
  **零 FilmRecord 新字段即可映射**（process 单源，OQ-M8-1 推荐；可选
  `FilmRecord.engine` 字段 = 按档显式选核——需求出现时再加，避免双真相）。
- 缓存折键：film sub-run seed（`fnv(recordHash ⊕ policyTag ⊕ solvedPackHash ⊕
  upstream)`）折模型 tag 的方式按 M6-2 §3.3「真分叉点折键」惯例——非 legacy 才折
  新 tag 或 tag 内嵌 process 段（charter 期钉折叠序 + 负测）。
- 迁移 UX = M6-2 §6 预留的「Update to Current Process」挂账正主：光谱核上线 =
  第一个真实语义 bump，迁移交互形态（面板按钮/菜单项）在该批落地。

### 4.3 求解 / bake / 面板：同机制换内核

- **FilmSolveCache / 中性包求解**：AUTO 核 (M0,Y0) 求解在光谱域重推导（dichroic
  SPD × 负片谱透射 × 相纸感光积分替代 per-channel 密度增益）；**锚数据不变**
  （`neutral_print_filters.json` 同表 ±10 CC sanity 带继续有效）；缓存键形不变
  （pair ⊕ stats ⊕ tag），modeTag 扩模型段；K 标定（session 操作点，M3-3-02 §3
  机理）在光谱域重标定——「pack 后操作点标定」教训平移。
- **65³ bake 面**：现行 `FilmPrintBake`（印相段 + 反演 + 输出编码）= 密度域印相；
  光谱核印相/扫描表 bake = 同机制家族（per-pair Float64 + LRU + bakeCount 可观测）
  但 builder 重造 + 插值换臂（dt 用单调 PCHIP；我方现行 rtne 四面体 trilinear——
  域结构不同，OQ-M8-3 裁）。**「零新 kernel 红线」在光谱核语境自然重开**：新核 =
  新 kernel 家族，按 M8 解封申报面登记（charter 期列清单）。
- **宽容度面板 / descriptor**：ISO 6846 归约 + 真链 probe 方法论完全平移——probe =
  `PixelPipe.assembleFilmLeg` 产线 factory 换臂（M3-4-01 先例零改原则：film 腿测试
  零改 = 零行为门在换臂后重新对表）；面板数学（直方图原生轴 / 双虚线 / 占比 /
  Fit / typed 拒绝）零改；descriptor 读数随核变（by design，response 列 =
  print reflectance 语义不变）。
- **filmPlacement**（置位 op）：film 腿上游，零改。
- **持久化**：FilmRecord 七字段语义不变；sidecar 零新增（engine 字段不设前提）；
  schema v10 已含 `process` 键——M8 无 schema bump（除非 charter 另立新键）。

### 4.4 一句话结论

**缝零改 + 换 payload + process 双臂**：融合点全部落在 M3-3/M3-4/M6-2 已造好的机器
上；真正的实现面 = 数学核（§3）+ 构建期 bake/solve 重推导 + 冻结 golden 三件套。

## §5 perf 预估（probe 级，不写码；真值 = M8-1 probe 批）

### 5.1 依据

- dt GPU 路径逐像素成本 = 1×2D cubic fetch（16 tap）+ ~2×3D 表 fetch（8 tap）+
  1D 曲线查表 ×3-6 + 矩阵/OkLab cbrt 族——**全链无逐像素 81 波长循环**（积分全部
  预折）。与现行 `film_subrun` fused kernel（1×texture3d 四面体 fetch + 曲线查表 +
  log 域混）**同数量级**，非「81 倍重」。
- 我方预算惯例：100MP 全帧 FULL 渲染延迟容忍域（现管线数百 ms 级）、预览交互
  <16ms、缩略图 legacy 不受扰、导出排队容忍；8G RSS 门机检（AGENTS 资源监控节）。

### 5.2 预估谱（100MP 全帧，Apple Silicon 统一内存）

| 项 | 预估 | 备注 |
|---|---|---|
| 逐像素 ALU+fetch | ≈ 2-4× 现行 film 腿 | fetch 主导；cbrt/pow 吞吐是主要不确定项（native special function 速率） |
| 光谱腿全帧 | ~30-120ms 量级 | 现行腿 ~15-40ms 外推；probe 定真值 |
| 预览（512-1024 长边） | 亚 ms-几 ms | 线性缩放，交互无虞 |
| tc 表构建（per-sim CPU Float64） | <100ms 级 | 192²×81 sigmoid+积分；进构建期非逐帧 |
| 印相/扫描表构建 | 与现行 bake 同量级 | per-pair 一次，LRU 承载 |

### 5.3 内存与空间步（最大风险项）

- DIR coupler 模糊场 = 唯一新增中间面：全幅 float32 RGB @100MP ≈ 1.2GB——**超预算
  形**。候选：①模糊场降采样 1/4-1/8 res（校正场低频，~19-75MB；上采样参与主链）
  ——tile 驱动不变式（film box 不入 tile）可维持；②v1 砍 coupler 档（模型完整性
  让位预算）。**OQ-M8-4 推荐 ①**；probe 批实测 RSS。
- grain/halation/diffusion 不入 M8（现行密度核亦无；上游 `spektra_core` 思路挂账
  不消费）。

### 5.4 probe 设计（M8-01 首任务候选，`LIGHTAMER_PERF_PROBE=1` 门 + L014 fence）

① tc 表构建耗时/数值 sanity（中性配平核验）；② 逐像素 kernel microbench（合成
ramp + 真图 100MP，全帧计时 + 分段 signpost）；③ RSS 峰值（8G 门机检 + 模糊场两
方案对照）；④ 与密度核的 pristine/strength-0 逐位对照基线 + `filmRampPlaneHash`
新哨兵值计算。

## §6 许可边界

- **GPL-3.0 零复制面**：dt spektrafilm 模块族（`spektrafilm.c` / `spektra_sim.*` /
  `spektra_fetch.*` / `spektrafilm.cl` / `spektra_core.*`）+ spektrafilm Python 参考
  仓（andreavolpato/spektrafilm，GPLv3）——只读参考算法思路；代码与表数据零拷贝
  （darktable GPL 只读纪律，M3 族先例同款）。
- **公开数学 / 标准数据可用**：Jakob & Hanika 2019 论文（学术发表数学面）；CIE 1931
  2° CMFs、D 系列光源 SPD 公式、CAT16/CAT02、OkLab 矩阵族 = 公开标准；rgb2spec
  （mitsuba-renderer）与 colour-science `colour.recovery` = BSD 族许可——思想可用，
  我方惯例 = 论文数学独立实现不搬码。
- **CC BY-SA 资产通道（SPEC-02 对象）**：28 profile + `neutral_print_filters.json`
  字节原样纪律延续（NOTICE §1：更新 = fresh verbatim copy + CHANGELOG 新行 +
  MANIFEST 对账，永不原地改）；M8 谱面全消费 = 同文件本就携带，归属义务面不变。
  上游 spektrafilm release 新版（>0.3.2）profile 升级 = 新鲜拷贝流程照走。
- **darktable-spektrafilm 数据仓**（pack 下载源：pack.json + spectra_lut.f32 +
  profiles/ 导出器）：= 数据来源候选。profiles/ 内 = 同款 CC BY-SA JSON；**hanatos2025
  表与常数集（illuminant SPD 集合 / dichroic 滤光曲线）许可待验**（dt 生态产物，
  大概率 GPL 侧）——消费前 charter 期核verify。**推荐路线 = 自拟合 tc 表 + 公开标准
  SPD/CMF 自装配 + dichroic 曲线自近似（公开描述）——零 GPL 数据依赖**；dt pack
  仅作「值域 sanity 带」参照（同 `neutral_print_filters` ±10 带用法）。
- **自建资产归属注记**：自拟合表/自建曲线 = 我方代码资产同族（MIT 仓）；「拟合
  输入 = CC BY-SA profile 数据」的产物是否构成 SA 衍生资产——倾向**非衍生**
  （产物 = 数学拟合系数，非 profile 的改编件），charter 期法务注记登记待裁
  （OQ-M8-2 附则）。

## §7 Open Questions（正式 charter 的裁决点预备，每条带推荐）

- **OQ-M8-1 核拓扑**：推荐 = **process 驱动单源**（`process 2` = 光谱 current 臂 +
  密度核冻结 legacy 臂；`RenderProcess` 账本第二 case），不设 `FilmRecord.engine`
  字段（避免双真相；按档选核需求实证出现再议）。
- **OQ-M8-2 tc 表来源**：推荐 = **自拟合 clean-room**（Jakob-Hanika 数学 + BSD 方法
  参考，fit 到 Rec2020 working space + 各胶片参考光源）；hanatos2025 表 / dt pack
  常数不消费（许可待验且域不合）；自拟合不达标的 fallback（评估上游表许可）不预设。
- **OQ-M8-3 重积分形态**：推荐 = 印相/扫描走**运行时构建 3D 表**（dt 同构；复用我方
  bake 机制家族；插值臂 PCHIP vs rtne 四面体 charter 期裁）；逐像素精确臂不作 v1
  目标（golden 参照仍用 Float64 独立数学复算——M3-3-03 主门形态平移）。
- **OQ-M8-4 DIR coupler 与空间面**：推荐 = v1 **含** coupler correction（模型完整性）
  但模糊场降采样 1/4 res（§5.3 ①）；grain/halation/diffusion 不入 M8（挂账不消费）。
- **OQ-M8-5 范围与阶段切分**：推荐 = **M8-0 charter**（OQ 裁决 + phase 表）→
  **M8-1 数学核 + probe**（SPEC-01/04：自拟合 tc 表 + kernel 探针 + perf/内存真值 +
  coupler 方案裁决数据）→ **M8-2 管线集成**（SPEC-02/03/06：sub-run 缝挂光谱核 +
  solve/bake 重推导 + process bump + 冻结 golden + CC BY-SA 谱面消费 + NOTICE 措辞）
  → **M8-3 面板接线 + golden/收口**（SPEC-05：Film 面板平移 + 宽容度 descriptor 换臂
  + VALIDATION）。预算 L（3-4 plan），charter 期细排；「等其落地」项 = 无（Alcedo
  无光谱面对标，见 OQ-M8-7）。
- **OQ-M8-6 FSIM-01c 措辞修订**：推荐 = M8-2 落地批同批修订 NOTICE 消费披露行 +
  README/help 用户可见措辞升格「光谱重建材质模拟（逐波长），非场景光谱重放」；
  历史文档原文保留（勘误行追加惯例，本文 §2 即正本）。
- **OQ-M8-7 UI 对齐面**：Alcedo 胶片模拟 = LUT 面 + grain 滑杆，无光谱面（M3-2 §10
  已核）——光谱核 UI = 现行 Film 面板平移（材料 picker / Y·M / Solve / 宽容度面板
  数学零改），**无新增 Alcedo 对标项**；dt 的 upsampling 表选择器 / 带宽自适应控件
  推荐 v1 不引入（模型面恒自拟合单表；多表/表选择随上游生态演化再评估）。

## §8 Sources

### 内部正本链

- `phases/m3-2-fsim-research/RESEARCH-NOTES.md`（§1 SpektraLab 读解 / §2 光谱不可达
  原声明 / §3 方案三 / §4 求解草案 / §5 资产三态 / §6 golden 策略）
- `phases/m3-3-fsim/M3-3-0{1,2,3}-DECISIONS.md`（KD-1..7：FilmRecord / 资产五件套 /
  加载器 / FilmMaterialStore / bake 求解器 / K 标定 / sub-run 缝 / golden 四门 /
  确定性门 / Film 面板 / 只读卡）
- `phases/m3-4-latitude/`（M3-4-01：精确锚 / descriptor 运行时 / 宽容度面板 / stats
  投递；M3-4-02 VALIDATION）
- `phases/m6-2-process-version/RESEARCH-NOTES.md`（process 键面 / hash isolation /
  分叉点折键 / RenderProcess 账本 / 迁移 UX 挂账）
- `Resources/FilmProfiles/`（NOTICE / LICENSE / CHANGELOG / MANIFEST.sha256 /
  profiles/ 28 JSON——谱面消费翻面的资产正本）
- AGENTS.md「M3-3/M3-4 架构增量」节（film sub-run 缝 / FilmSolveCache 键控 / 宽容度
  面板约定）

### 外部（GPL 只读读解，零拷贝）

- darktable `src/iop/spektrafilm.c`（模块头注释：全链管路 / 数据包形态 / view
  transform 定位 / GPU 验证精度）
- darktable `src/common/spektra_sim.h`（pack 容器 / 表 kind / SF_NWL=81 /
  SF_NLE=256 / SF_TC_N_MAX / 每 sim 构建期积分预折 / PCHIP 双臂）
- darktable `src/common/spektra_fetch.h`（pack 解析 / lut_hash 身份语义）
- darktable `data/kernels/spektrafilm.cl`（expose 核：tri2quad + 2D cubic fetch /
  stage 分解 / float+1e-6 / 空间步分离）

### Web 公开源

- Jakob & Hanika 2019《A Low-Dimensional Function Space for Efficient Spectral
  Upsampling》EPFL RGL 项目页 + 论文 PDF（jo.dreggn.org/2019_sigmoid.pdf）
- mitsuba-renderer/rgb2spec（官方系数表参考实现）；colour-science `colour.recovery`
  （BSD 族同族方法）
- PIXLS 论坛「Spectral film simulations from scratch」#5（hanatos 2025-02 sigmoidal
  上采样表自述：覆盖全色度、光谱轨迹内部有意义）+「spektrafilm tech discussions」#3
  （vkdt 相机 SSF 系数构建参考）
- darktable user manual spektrafilm 模块页（光谱上采样/带宽自适应选项面）

---

## §9 免责与边界重申

本文 = 预告批底稿：§3.3 规格草案 / §5 预估 / §7 推荐全部为 **charter 期可推翻的
建议面**，非决议；正式立项以 M8-0 charter 五正本为准。dt/spektra 读解若在 charter
期复核发现偏差，以复核为准并在本文追加勘误行（原文不改）。

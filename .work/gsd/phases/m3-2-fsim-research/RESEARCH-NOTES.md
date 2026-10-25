# M3-2 RESEARCH-NOTES — FSIM 两段式胶片模拟设计研究（2026-10-07/08 discuss/research 起草批）

> 配套正本 = 同目录 `M3-2-CONTEXT.md`（D-M3-2-N 决议 + OQ-M3-2-1..7）。上游输入 =
> ROADMAP M3-2 行 + REQUIREMENTS FSIM-01a..d 草案 + `phases/v2-station/V2-PROPOSAL.md`
> FSIM 档案 + `research/SPEKTRALAB-NOTES.md`。
> 参考源码纪律：SpektraLab（`/Volumes/UNITEK/Documents/Development/SpektraLab`，
> 代码 GPL-3.0 **零复制**，只读设计语义与数据 schema；配置/LUT 数据 = CC BY-SA 4.0
> 独立资产）；Alcedo（GPL-3.0 零复制，仅对标差异确认）。
> 本文所有 SpektraLab 引用格式 `file:line` 为读解定位，**非移植清单**。

---

## §1 SpektraLab 设计读解（阶段分离语义）

### 1.1 管线拓扑：四阶段与两层分离

- 阶段链（ARCHITECTURE.md:270 表 + :292-293）：**Pre-Dev**（Latitude / Camera /
  Film Format / **Scene Placement** / Tone Mask，引擎 Layer 1）→ 胶片记录（film
  exposure / development / couplers / grain，缓存负片）→ **印相段**（enlarger 滤色
  光 → 相纸 → scan）→ **Post-Dev**（White Balance / Exposure / Curve / Color
  Balance，app 内 Metal 一画，Layer 2，亚毫秒）。RFC-024:21-35 给出同链的 canonical
  文字版（decoded input → [RFC-023 scene placement] → film → cached negative →
  enlarger spectral projection → [RFC-024 mask] → paper → scan / Layer 2）。
- 两层分离（ARCHITECTURE.md:287-295）：Layer 1 = 材料/引擎域（一次 render ~14ms），
  Layer 2 = scan 上的显示域调整。**对偶到我方**：Layer 1 ≈ 我方胶片段 sub-run；
  Layer 2 ≈ 我方 grade 链 + DRT tail 的既有分工。
- 三白平衡三阶段（ARCHITECTURE.md:281-283）：camera（decode 域 K 氏）/ Post-Dev
  （scan 域）/ **enlarger 滤色包（"what Solve solves"）**——配光是独立第三白平衡，
  不与任何其它阶段共享参数。
- 蒙版阶段归属学（SPEKTRALAB-NOTES.md:15 + RFC-024 中文摘要 :15-19）：影调蒙版
  （RFC-024 Virtual Contrast Mask）属**负片之后、相纸之前**的印放阶段——
  「RFC-023 在曝光时控制光比（胶片前），RFC-024 在印相时控制光比（负片后），
  两者不可互替」。FSIM-03 注记的语义正本。

### 1.2 场景置位（RFC-023 Scene Latitude Mapping）

- 问题起点（RFC-023:15-39）：JPEG 进引擎效果比 RAW 好——相机 JPEG 已内置
  display-referred 肩部压缩；RAW 12-15 stop 无肩直入。结论 = 「JPEG 偶然做的事
  应该被有意地、参数化地、对所有输入一致地做在一个地方」。
- 曲线族（RFC-023:43-58, :638-694 §5.4）：**恒等核 + 双侧 smooth-min 压缩支**，
  `g_m(Δ)=Δ(1+(Δ/H)^m)^(-1/m)`；五参数 = 双膝 K_s/K_h + 双深度 H_s/H_h + 滚降阶
  `m`（默认 2）。性质全部 by construction：单调、恒等核精确、膝点 m 阶接触
  （m≥2 无曲率台阶）、双侧独立、硬渐近线 = 相纸白/黑地板永不越过。
- 参数化即 UX（RFC-023:1182-1234 §9.2）：渲染态不是 K/H，是**双侧 pull-back 滑杆
  （stop 单位）+ m**；K/H 由直方图分位（P99.9/P0.1）与介质边界（descriptor）
  **解出**，永不手打。求解 = 每参数提交一次的 CPU 一维求根（m=1 闭式、m≥2 有界
  二分 + 牛顿，:1207-1217）；**percentile 是 Fit 策略不是渲染参数**（:1178-1180，
  Fit 只写滑杆、影师拥有滑杆，:1235-1266 §9.3）。
- 信号恒线性（RFC-023:709-743 §5.6）：log₂ 只在标量 gain 计算中出现，输出
  `RGB' = k·RGB` 恒 scene-linear；kernel 算 delta `δ(E)=f(E)−E` 使恒等核
  **bit-exact**（:729-743）——关闭曲线时逐位等于现状。这条是「置位零打扰」的
  工程保证，M3-3 kernel 直接同构。
- descriptor 测法（RFC-023:1021-1155 §8）：**ProfileLatitudeDescriptor 用真实管线
  跑中性 ramp 测得，绝不并行实现第二套数学**（:1023-1045——「并行实现 = 会悄悄
  漂移的 guard」）；指标 = ISO 6846 感光测定定义（输出达自身黑白固定距离的 EV，
  :1058-1110），斜率阈值法被否（同 profile 随阈值漂 3-4 stop）。
- 介质宽容度实测参考（:802-811）：portra_400 + portra_endura 端到端 ≈ 8.5 stop
  有效宽容度；我方宽容度面板 FSIM-02 的「胶片容纳范围双虚线」= descriptor 的
  `[useful_shadow_ev, useful_highlight_ev]` 两虚线，读数 = RFC-023 §9.1
  SceneHistogram 的 placed_fractions（引擎实测接口 = engine.cpp:2007
  `hist.set("placed_fractions", ...)`；ARCHITECTURE.md:292-293「Latitude reads
  the scene histogram **after** Scene Placement's curve」）。

### 1.3 印相段与配光求解（printing / spk_solve）

- 滤色包模型（printing.cpp:97-102 + params.hpp:214-215）：减色 dichroic 头
  **两轴调色**——C 恒定其中性值（`c_filter_neutral=0.0`），M/Y 各有
  `*_filter_neutral`（默认 Y=55 / M=65 点）+ 用户 `*_filter_shift`（手动偏移，
  默认 0）。滤色单位 = CC 点（0-100 域）。
- **自动求解的真实形态（本环关键实测）**：`spk_solve(target:"filter_pack")`
  （engine.cpp:2102-2113）= 把 `neutral_print_filters_from_database` 打开后对
  session 参数做 `digest`——**自动配光 = 查 (paper × film) 对的中性滤色包数据表**
  （`resources/neutral_print_filters.json`：TH-KG3 头 × 8 相纸 × 各 film stock，
  值域 [C=0, M≈57-79, Y≈63-79] 点）；**内容自适应部分只有曝光归一**——
  printing.cpp:147-160：mid-gray 探针（0.184 灰过胶片模型得光谱密度）经滤色光照
  → 相纸光谱响应，**三通道几何均值归一**（「归一只动亮度不动滤色包的色」）。
  即 SpektraLab 的「测光自动算滤色组合」= **离线材料对查表 + 在线测光曝光归一**，
  通道色平衡交给中性包 + 用户 Y/M 偏移。
- print LUT（print_lut.hpp:1-13 + print_luts.json 实测）：印相+scan 段 bake 成
  per-paper-stock 的 33³ LUT（索引 print_luts.json 仅元数据：lut_size 33 /
  output_color_space "Display P3" / paired_film / output_cctf_encoding；**payload
  在 `spektrafilm_constants.bin`（9.4MB blob），bake 走 `bake_all_print_luts.py`
  （GPL，不抄）**）。结构上印相段可整体 LUT 化——印证我方「相纸段走烘焙缝」路线。

### 1.4 RFC-024 / 025 / 028 / 030 要点（各一注）

- **RFC-024（虚拟对比蒙版）**：印相域曝光操作、非合成宽宽容相纸（:11-17 产品
  决策）；形态 = 区域 gain map（:440-456）；「负片显影后无法找回已丢信息」
  （:19 注）——FSIM-02 教导语义「EDR 不可找回输入端已丢高光」的印相版同构。
  M3 范围外（FSIM-03 注记即止）。
- **RFC-025（效果强度解耦）**：halation/grain/DIR couplers/glare 各自 strength，
  `1 = 该胶片 as-modelled`，默认 = 引擎默认（零行为变化）；强度语义 =
  `out = in + k·(grained − in)`（密度域混入，:48-52）。M3-3 的胶片效果强度族
  参数面照此语义。
- **RFC-028（去色罩/数字中间片）**：中文摘要 :17-27——橙罩 = 常数 `base_density`
  + 影像变化半（DIR 净化已折进 profile）；去罩 = 逐波长减常数、反转必须用胶片
  **自身中性曲线**（灰阶误差恰 0；逐通道 gamma 法 ±4 stop 内 0.08-0.43 stop 偏色
  ——negadoctor 有偏色滑块的原因）。**对染料近似的直接指导**：负片段 =
  per-channel 密度曲线 + 常数底色偏移 + 小串扰矩阵，通道反转走胶片中性曲线。
- **RFC-030（per-stock 对比）**：DI 把各胶片 γ 归一后 Vision3 族观感趋同（Oklab
  ×100 均值 2.0）；实测 printing-density γ 表（:55-70，Portra ≈0.53-0.58 / Fuji
  X-Tra ≈0.65-0.70）——**胶片个性 = γ 差 + 曲线趾肩形**，RGB 密度域曲线可承载。

### 1.5 资产 schema 实测（引入可行性核心证据）

`engine/resources/profiles/kodak_portra_400.json`（28 配置之一，CC BY-SA 4.0）：

| 键 | 形状 | 我方 RGB 密度域可消费性 |
|---|---|---|
| `metadata.license/copyright/citation` | CC BY-SA 4.0 + 署名条款 | 随文件原样携带即满足归属 |
| `info` | stock/type(negative|positive)/support(film|paper)/stage(filming|printing)/densitometer(status_M)/reference_illuminant 等 13 键 | 配置目录元数据直接可用 |
| `data.wavelengths / log_sensitivity / channel_density / base_density / midscale_neutral_density` | **81 点光谱域** | 光谱不可达（§2）——不消费，随文件携带 |
| `data.log_exposure` | 256 点，−3.0…+4.0（log10） | **直接可用**——密度曲线横轴 |
| `data.density_curves` | **256×3**（per-channel 密度） | **直接可用**——染料近似主数据 |
| `data.density_curves_layers` | 256×3×3（层分解） | 近似可选 |
| `data.edr_tone_map`（相纸侧另有） | tone map 参数 | 待 plan 细读 |

**核心发现**：`density_curves/log_exposure` 是**打印密度域（status M）的 per-channel
特性曲线**——与我方 RGB 密度域染料近似的目标数据**直接同构**，零转化数学。
OQ-V2-10 当时「28 款配置面向 81 波长引擎调校、RGB 域可迁移度未验证」的疑虑，
经本环实测**大幅缓解**：光谱字段不可消费，但密度域字段正是我方要的形状。
（相纸 profile 同 schema，`stage=printing`，同样携带 density_curves。）

> **勘误/措辞同步（2026-10-08，以 M3-3-01-PLAN KD-3 投影裁决为准）**：上表
> 「不消费，随文件携带」行按消费面收窄读作——**光谱重放零消费**（81 波长
> 前向模型不可达，§2 边界不变）；唯 `base_density` 谱数组**经文档化投影**
> 消费为 RGB 常数：`base_R/G/B := base_density(λ≈650/550/450nm)` 三点最近邻
> 采样（橙罩谱形在三原色波长的取样，确定性可入 golden 复算；portra_400
> 实测 0.195/0.602/0.815 量级 = 橙罩物理正确性自证；采样点 None 或越界 =
> typed fail-closed）。资产三态语义（§5 裁决③ c 混合态）不变，未改归属/
> 许可面。原文措辞保留作历史，消费面以本勘误行为准。

> **勘误行（M8-3 勘误追加，2026-10-26；上行与 §2 原文不改）**：M8 光谱核落地后
> 消费面再收窄——81 波长谱数组现为**逐波长材料链正消费**（负片感光 + 相纸响应
> 的逐波长积分；DIR coupler 结构在位出厂中性——profile 集无 coupler 测量数据）；
> §2「光谱不可达」的可达面相应收窄为**场景光谱重放**（场景以色度域 metameric
> 重建进入材料链——「光谱重建材质模拟（逐波长），非场景光谱重放」；密度域
> 消费面保留为 v1 冻结臂）。NOTICE §2 消费披露升格同批；正本 =
> `.work/gsd/phases/m8-fsim-spectral/M8-3-DECISIONS.md`。

---

## §2 光谱不可达声明（正式边界节，M3-2 交付物）

> 落档位置：本节正文即声明文本；M3-3 起由 CONTEXT/AGENTS 引用；用户可见文档
> （README/help）转述采用「物理流程建模，非光谱重放」措辞。

**边界陈述**：Lightamer 的解码链为 CIRAW（Core Image RAW，RGB 域起步）。传感器域
前向模型不可达——光谱重放需要 per-wavelength 数据链（光源光谱 × 染料光谱透射 ×
相纸光谱感光的 81 波长积分），而 CIRAW 解码已把光谱信息折叠进 3 个 RGB 通道
（CFA 光谱积分 + demosaic），任何 RGB 域后处理都无法恢复 per-wavelength 响应。
与「demosaic 算法菜单不可达」（STACK.md Decoder 策略）同一架构性逻辑。

**可行核**（FSIM-01 交付边界）：阶段分离语义（场景置位 → 胶片记录 → 配光 → 相纸
呈现）+ RGB 域染料近似。近似模型 = per-channel 密度特性曲线（影调 S 形/趾肩/γ
个性）+ 常数底色偏移（橙罩常数半）+ 小型通道串扰矩阵（一阶跨通道）+ 滤色
通道增益（配光）+ 相纸密度曲线（印相段）。

**保真面 / 不可达面**（预期管理口径）：
- 可达：胶片影调签名（S 曲线、per-stock γ 差——RFC-030 实测 γ 表 :55-70 即
  RGB 密度域可承载的个性）、一阶通道串扰、整体色偏（橙罩/染料劣化）、
  印相配光流程语义、宽容度/置位教导交互。
- 不可达：metamerism 级行为（同色异谱染色差异）、染料光谱交叉吸收的波长依赖
  细节、滤色头光谱形状效应（RGB 域仅吸收为三通道标量增益）、与光谱引擎逐波长
  一致的渲染输出。

---

## §3 两段式模型落我方架构——三方案对比

链序语义先行：对照 SpektraLab 四阶段与我方 Alcedo 链
（`PipelineDocument`：develop → grades×N → displayTransform，
`LightamerCore/Sources/Graph/PipelineDocument.swift:44-47`），胶片段落位 =
**grades 之后、displayTransform 之前**（grade = scene-referred 置位/预显影域；
胶片+印相 = 材料域；DRT = 显示域）。物理隐喻映射：Develop(RAW) → Grades(置位与
预显影) → [负片 → 放大机配光 → 相纸] → DRT(display encoding)。

### 方案一：独立胶片段节点（新 `NodeKind.film` 段）

- 形态：PipelineDocument 加 `film` 节点（或含四子阶段子卡）插于 grades 与
  displayTransform 之间；胶片段数据活在节点/层上，可蒙版、可多重。
- 收益：阶段一等公民；FSIM-03 印相域蒙版有天然宿主（节点蒙版）；节点图 UI 最直白。
- 代价：`NodeKind` 穷举 switch 全仓破面（文档投影/命令集/面板路由/验证缝——编译期
  安全但面积大）；M2-4 节点图语义（D-M2-4-CONTEXT 系）重开；多重胶片段的物理语义
  （两台放大机串联？）需要额外禁则；history/sidecar 面加层段维度。**M3-3 体量
  暴涨风险最高。**

### 方案二：Grade 件族扩展（胶片 = grade 域新 ops）

- 形态：`filmPlacement` / `filmRecord` / `printPack` 三个新 op 入 GradeCatalog
  （owner 新档或并入 .grade），V50Order add-only 新槽（如 71.x 段）；域切换复用
  ACEScc envelope 先例（`ACESccInModule.swift:123-142` 的「≥1 目录 op 包裹」缝）。
- 收益：**零节点模型改动**；层/蒙版/历史/sidecar/面板 18 目录机器全复用；additive。
- 代价：阶段语义藏在 op 序里（用户可在三 op 之间插 grade 件——需禁则或文档化）；
  材料选择（film×paper 对）是两 op 参数联动，sidecar 上无单一 record；
  「胶片/相纸 = 每张印相一份的材料」语义被降格为「可加蒙版的图层效果」，
  与 enlarger 全图物理不符（蒙版化胶片 = 物理上不存在）。

### 方案三：document 级 FilmRecord + 固定点 sub-run（DrtRecord 同构）【推荐】

- 形态：Core Graph 新 `FilmRecord`（filmStock/paperStock/滤色中性+Y/M 偏移/
  曝光归一模式/效果强度族/strength），**document 级单例**（一台放大机一副底片
  一种相纸 = 每文档一份）。管线：主链顶面 → **film sub-run**（负片段 kernel →
  滤色通道增益 → 印相段 baked LUT）→ 既有 DRT tail。
- 复用面（全部是 M2-6 已造好的机器）：
  - 管线缝 = `TerminalTailPolicy` 体系扩展：DRT tail 的 seed 折叠收
    `upstream: UInt64`（`PixelPipe.swift:1244-1267` `DrtTailAssembly.seed`）——
    film sub-run 输出 hash 作为 upstream 传入，**签名零改，调用点换数**；
    tail 链装配（`DrtTailAssembly.instances` :1276-1310）不受扰。
  - film sub-run 自身 = `DrtTailAssembly` 同款 driver-constructed boxes +
    `runSub` 重放（seed = `fnv(levelHash[top] ⊕ filmRecordHash ⊕ filmPolicyTag)`，
    L013 FNV 折叠序照抄）。
  - 持久化四件套 = M2-6 DRT 持久化逐位同构：per-url carrier（缺键 = pristine，
    默认 record 不入 map 不写 sidecar）→ 写腿 2s debounce → 恢复腿 → document 级
    history item（`HistoryItem.filmRecord` additive，键族 `history_film_*`）；
    `HistoryHash.hash` 尾位折叠扩展同 drtRecord 惯例（无 film item 的档逐位不变）。
  - 面板 = DrtPanelView/DrtPanelModel 先例（读三级投影 + 单 discrete commit 写）。
- 场景置位落位：**置位曲线作主链内 grade 域 op**（新增 `filmPlacement` 单 op，
  RFC-023 语义的恒等核+双侧支曲线，参数 = 双侧 pull-back + m；可蒙版——置位是
  scene-referred 曝光操作，蒙版合法）；FilmRecord 只承载材料/配光。宽容度面板
  （FSIM-02）读主链顶面（= film sub-run 输入平面）直方图 + descriptor 双虚线，
  与「after Scene Placement's curve」读数语义一致（ARCHITECTURE.md:292）。
- 收益：材料语义最忠实（enlarger 全图、无蒙版——与 FSIM-03 注记的物理判断一致）；
  M2-6 全套先例复用 = M3-3 规模最可控；节点图 M2-4 语义**零改动**（UI 可在
  PipelineDocument 投影层加一张只读「Film」卡——投影而非新 NodeKind，M3-3 UI
  细节留 plan）；pristine 直通纪律（缺键 = 逐位现状）同 DRT。
- 代价：新 kernel 2-3 个（负片段/置位曲线，零新 kernel 红线下自研 MSL）；面板/
  history/sidecar 四件套按 DRT 模式新建（机械复制面）；多胶片段不可能（单例）——
  物理上正确，UX 上若用户想对比两种胶片 → 用 M2-8 版本（version swap）而非叠段。

### 对比结论

| 维度 | 一（新节点段） | 二（grade ops） | 三（document record） |
|---|---|---|---|
| 材料物理语义 | 弱（可多段/可蒙版胶片=失真） | 最弱（效果化） | **最忠实（单例/全图）** |
| M2-4 节点模型 | 破面最大 | 零改动 | **零改动（投影卡）** |
| 复用 M2-6 先例 | 部分 | 部分（18 目录） | **全套（DRT 同构）** |
| 蒙版可挂 | 节点蒙版 | 层蒙版 | 置位 op 可蒙版；印相域蒙版留 FSIM-03 载体 |
| M3-3 规模 | L+ | M | **M（机械复制面为主）** |

推荐**方案三**；置位 op（grade 域、可蒙版）为其固定搭档。FSIM-01a 细化草案据此
**修正转正**：「胶片段语义 = document 级 FilmRecord + 主链后固定点 film sub-run +
UI 投影卡」，非「链上新增节点段」。

---

## §4 配光自动求解算法草案（RGB 域简化版）

### 4.1 模型域约定

全链 working linear Rec2020 float32；胶片段内部临时进**密度域**（log10）：

```
置位后场景 RGB(scene-linear)
  → [负片段 kernel]  E_c = log10(clip(RGB_c)) 查 film.density_curves 得 D_c
                      底色偏移 D_c += baseDensity_c（橙罩常数半，RFC-028）
                      串扰 D' = Mxt×D（3×3，一阶）
  → [配光缝]          D''_c = D'_c + filterGain_c(M,Y)   ← 滤色 = 密度域通道增益
  → [印相段 baked LUT] 相纸密度曲线 → 减 Dmin → 胶片中性曲线反转（RFC-028 :
     「反转必须用胶片自身中性曲线，灰阶误差恰 0」）
     → 输出 linear Rec2020（回 working，交 DRT tail）
```

filterGain_c = 滤色包在通道 c 的等效密度：Y 滤色吸蓝、M 滤色吸绿、C 吸红，
RGB 域简化为 `gain = k_y·[0,0,1] + k_m·[0,1,0] + k_c·[1,0,0]`（k = CC 点 × 换算
系数，plan 期标定）。
> **勘误（2026-10-08，以 M3-3-01-PLAN KD-5 checker 回注修正式为准）**：原式
> `k_m·[0,1,1]` 为笔误——dichroic 密度域 M 滤色**只吸绿** = `[0,1,0]`，`[0,1,1]`
> 会同时加蓝密度（等制品红+黄混色）；Y 吸蓝 `[0,0,1]` / C 吸红 `[1,0,0]` 不变。
> 本文 §4.1 散文（「M 滤色吸绿」）本就正确，仅公式侧错；已就地改正。
滤色作为 LUT 前的**逐通道标量增益** → 一个材料 LUT 服务
全部滤色组合（不 per-pack bake）。

### 4.2 求解两段式（SpektraLab 同构 + 我方确定性门）

**离线 bake 期（每 film×paper 对一次，CPU，进 FilmMaterialStore）**：
中性滤色包 (M0, Y0) 求解——mid-gray 场景经负片段得 mid-gray 密度三元组，解
(M0, Y0) 使经配光+印相后输出通道相等（2 元 2 方程，各通道对 M/Y 单调 → 有界
二分/牛顿必收敛）。= SpektraLab `neutral_print_filters.json` 的生成过程自研版
（其 TH-KG3 头实测值域 M0≈57-79 / Y0≈63-79 / C≡0，可作合理性 sanity 带）。

**运行期（每图一次，CPU 统计腿，输出 = FilmRecord 的自动分量）**：
1. 降采样统计（RFC-023 §9.1 SceneHistogram 同构：Y 直方图 128 bins +
   P0.1/P50/P99.9 等分位）——统计腿跑在主链顶面（置位后）。
2. **曝光归一**：mid-gray（P50 或 Y 加权均值）目标落点 = 相纸 mid-density 对应
   EV ↔ 当前落点 EV 之差 → 曝光 gain。= printing.cpp:147-160 几何均值归一的
   RGB 域简化（几何均值 → Y 通道，或保留 RGB 三通道各自归一的亮度不动色版）。
3. **内容自适应通道偏移（可选档，OQ-M3-2-2）**：mid-gray 三通道密度失衡 →
   需要的 (ΔM, ΔY) 修正闭式解（失衡向量在滤色增益基上的最小二乘投影）。
   默认关 = 严格中性包 + 仅曝光归一（SpektraLab 行为）。
4. **手动 Y/M 偏移恒叠加**在自动解上（points 域双滑杆，enlarger `*_filter_shift`
   同款语义）——FSIM-01b 原文钦定，不可裁掉。

**确定性门（FSIM-01b 验收）**：同输入统计 + 同材料对 + 同模式 → 同解。
实现保证 = 统计腿分位数用整数秩（RFC-023:1174-1176 纪律）、求解器为无随机性的
闭式/有界迭代、bake 期与运行期解耦。统计腿结果缓存键 = `fnv(材料对Hash ⊕
统计输入Hash ⊕ 模式tag)`，材料/参数变更重解（printing.hpp:4-6「per-render
重推、不 bake 进渲染」的缓存纪律同构）。

### 4.3 与 M3-1-01 烘焙缝的对接

印相段（相纸曲线 + 反转 + 输出编码）静态 per 材料对 → 经
`Lut3dModule.bakedCompositeTable` 同款复合表烘焙（`Lut3dModule.swift:166-333`：
编码对 + 65³ 复合 bake + LRU 16 + bakeCount 可观测） bake 成 65³ LUT：
input encoding = 材料域标定（密度域查表前置在负片段 kernel 内完成，LUT 输入域
取 working linear 的负片输出——精确域选择 = M3-3 plan 期定，候选
`LutEncodingCatalog` 现行 17 行不加新行：负片段出 working linear，LUT 输入 =
linear_rec2020），output = linear_rec2020 交 DRT。载体 = 新 FilmMaterialStore
（键 = film×paper 对 + version）或复用 LutLibraryStore 独立子目录——M3-3 plan 期
裁，倾向独立 store（材料对身份 ≠ 用户 LUT 库身份，且 CC BY-SA 资产须与 MIT
spectral_film_lut 物理隔离，见 §6）。

---

## §5 资产三态对比与许可分析（OQ-V2-10 裁决面）

> 许可事实（SPEKTRALAB-NOTES.md:5,23-25）：SpektraLab 代码 GPL-3.0（零复制）；
> 胶片/相纸配置与放大 LUT = **CC BY-SA 4.0**（Andrea Volpato spektrafilm，独立于
> 代码许可）；我方现行 spectral_film_lut 40 张 = MIT（M2-5-3，零字节来自 Alcedo/
> SpektraLab）。CC BY-SA 义务：署名（NOTICE/CITATION）+ 相同方式共享（**传染仅及
> 资产本体及其衍生资产**，不及代码）+ 与 MIT 资产不混用（目录/许可双隔离）。

| 态 | 内容 | 收益 | 成本/风险 |
|---|---|---|---|
| **a 自建** | 引擎+schema+28 配置全自造（密度曲线自测/拟合） | 零许可义务；完全可控 | 密度曲线数据自造 = 实测或拟合，质量与真实感差距真实；起步慢，M3-3 golden 与观感风险最大 |
| **b 引入** | SpektraLab 28 profile JSON + 8 print LUT 原样引入 | 28 款实测配置即时可用；density_curves 与我方目标域**直接同构**（§1.5）；print LUT payload 须自烘（仓内 bin 是 GPL 侧产物——**自写 baker 从相纸 profile 重烘**，bake 脚本 GPL 不抄） | NOTICE/CHANGELOG + license 文件随资产；SA：随包分发的**衍生 bake 资产**也须 CC BY-SA；运行时生成不随仓分发的缓存则义务停留在源 JSON；测试 fixture 入仓同受 SA |
| **c 混合【研究倾向】** | 引擎+配置 schema+加载器自建；首批数据 = profile JSON **整文件原样**入库（光谱字段不消费但保留，避免「修改版 CC BY-SA 文件」归属混乱）；质量缺口后续自建平行配置补齐 | 转化成本最低（§1.5 同构发现）；归属最干净（原样文件 = 原许可原文本）；SA 传染面最小且清晰；不锁死自建路 | 需用户裁决接受 CC BY-SA 资产入仓；公开 GitHub 谱系（release 分支）随包携带义务文件 |

**许可操作面（c 态落地清单）**：①资产目录独立（如 `Resources/FilmProfiles/`，
与 `Resources/LUTs/`（MIT）物理隔离）；②`LICENSE`（CC BY-SA 4.0 全文）+
`NOTICE`（Andrea Volpato / spektrafilm 署名 + citation 全文 + 来源与版本）随目录；
③CHANGELOG 行记录引入版本；④测试 fixture 引用同目录文件，不复制改写；
⑤golden 参考基线按 §7 分级， SpektraLab 渲染产物不入仓。

三态对比交 OQ-M3-2-3 用户裁决；本环研究倾向 c（对 OQ-V2-10 当时默认倾向②
「自建起步」的**修正动议**，依据 = §1.5 密度域同构实测）。

---

## §6 golden 策略（染料近似域的对照物，licensing 角度）

1. **主门 = 独立数学复算（M3-1-01 先例）**：曲线族/求解器/串扰矩阵的 golden =
   文档化数学的独立实现复算零误差（M3-1-01 「golden 三件套〔独立数学复算零
   误差〕」同款；曲线数学自定，公开标准部分用公开参考值）。许可零负担，
   确定性可断言。FSIM-01c 基线主形态。
2. **材料数据 fixture = CC BY-SA 源 JSON 引用**（c 态前提）：测试读仓内 profile
   JSON 的 density_curves/log_exposure——文件原样已在仓（义务已随 §5 清单履行），
   测试不新增分发面。b 态未裁前不写此类测试。
3. **SpektraLab 渲染参考图 = 仅本地目测参考，不入仓不 push**：GPL 程序输出图 +
   CC BY-SA 配置的产出物许可归属本身存疑（机械生成物），且本仓有公开 GitHub
   谱系（release 分支）——保守口径：开发期视觉 sanity 用（对照「观感方向」，
   非逐像素门）；如需入库 golden 图，用**自建配置**生成。逐像素 parity 对
   SpektraLab 无意义（光谱域 vs RGB 密度域本就不同输出）——golden 语义 =
   我方模型自身的数学一致性与跨版本稳定性，非对他家输出的逼近。
4. **descriptor/宽容度读数 golden**：中性 ramp 过真实管线测 descriptor
   （RFC-023 §8.1 方法论「probe the shipping pipeline, never reimplement」），
   断言 = ISO 6846 定义距离的单调性与带宽区间（如 portra 端到端 ≈8.5 stop 的
   sanity 带），非他家数值复刻。

---

## §7 FSIM-03 印相域影调蒙版阶段归属研究注记（落档）

- 语义（SpektraLab 实证）：影调/对比蒙版属**负片之后、相纸之前**的印放阶段
  （RFC-024 全文；RFC-023 与 024 的分离 = 「曝光时控光比 vs 印相时控光比，
  不可互替」）——与场景置位蒙版（scene-referred，grade 层）非同一功能，
  与 DRT 后局部调整（display-referred）亦非同一功能。
- 我方落位（方案三下）：印相域局部调整的载体 = **film sub-run 内的 mask plane**
  （document 级 record + 蒙版平面组合，M2-7 蒙版源架构复用）——不是 grade 层
  （域不对），不是 DRT tail（display 域不对）。
- M3 范围：**只落注记不立项**（V2-PROPOSAL.md:29,101）；实现候选挂 M4+
  （届时与 IOP-MASK-06 V2 / MASK-07 蒙版族同站评估）。

---

## §8 M7 spike 设计（RAF 100MP warm 双峰，OQ-V2-2 搭车件）

- 对象与在案事实：RAF 100MP 静态 warm 在 14ms 档与 ~40ms 档两态跳变；ARW 无此
  现象；拖动帧型尾尖峰带 10-52ms（perf.md:22,106 O-1；M2-11-02-DECISIONS.md:55
  §6 D-M2-11-02-6）。疑源三项 = 入口平面 CI 解码腿状态机 / GPU 时钟态 / 内存压力。
  不判缺陷、不设门（在案裁决）。
- spike 方法（零产线 diff，探针走 `LIGHTAMER_PERF_PROBE=1` 门控惯例 + L014 fence
  计时纪律）：①os_signpost 分段计时 decode→入口平面→主链首 box，N 轮 warm 采样；
  ②同轮采 GPU 频率/驻留（IOReport）与内存压力；③判别式 = 双态与哪段计时相关
  （decode 腿双态 → CI/CoreML 状态机；均匀慢 → 时钟/带宽）；④状态变量二分：
  CIContext 复用 vs 重建、前图 RAF/ARW 交错、轮间隔时间。
- 产出：`phases/m2-11-performance/perf.md` O-1 结论行（根因或收窄假说 + 复现
  配方）；spike 证据落 `phases/m3-2-fsim-research/evidence/`。
- 是否本环执行 = OQ-M3-2-6（ROADMAP M3-2 行原文含「spike 顺带」，倾向同批跑）。
- **执行结果（2026-10-08 补批，OQ-M3-2-6 ⑥「spike 同批」兑现）**：已执行并
  结案——根因 = bench 采样窗伪影（3 计时帧落在 fresh decode 后 0-8 帧的
  开图内存增长瞬态带）+ 交互态空闲衰减（帧间空白数百 ms 后 +50-100%，双
  格式共有）两层环境效应；稳态 RAF 14-19ms / ARW 12.3-15.6ms 确定性，
  非管线缺陷；状态变量二分排除 LUT 烘焙 LRU（链无 lut3d）/CI 解码状态机/
  CIContext 内部态/DRT 尾/系统热节流与内存压力。数据正本 =
  `perf.md` §O-1 SPIKE 节；证据包 = `evidence/M3-2-SPIKE-README.md`。

---

## §9 与 M2/M3-1 底座接口清单（复用面/新增面汇总）

**纯复用（零改或签名不变）**：
- `LutEncodingCatalog` 17 行 + `LutTransferMath`（M3-1-01）——胶片 LUT/材料 LUT
  编码对标定域直接消费；
- `Lut3dModule` 复合表烘焙缝（bakedCompositeTable/LRU/bakeCount）——印相段
  LUT 烘焙同款机制；
- `TerminalTailPolicy`/`DrtTailAssembly.seed(upstream:)`——film sub-run 输出作
  upstream，签名零改；
- ACEScc envelope / LayerCompositeSeam——置位 op 若需域包裹，缝机制现成；
- GradeCatalog 五元组 + NodeOwnershipCatalog——`filmPlacement` op 注册行；
- M2-6 持久化四件套模式（carrier/写腿/恢复腿/history item/hash 折叠）；
- M2-7 蒙版源架构（FSIM-03 未来载体）；M2-8 版本 swap（胶片对比 UX）。

**新增面（M3-3 实现量）**：
- Core：`FilmRecord`（+stableHash）+ FilmMaterialStore（材料对 bake 缓存）+
  `HistoryItem.filmRecord`/键族 `history_film_*` + film sub-run 装配；
- IOP：`filmPlacement` op（曲线 kernel）+ 负片段 kernel（密度查表+串扰+滤色增益）
  + 配光求解器（CPU，确定性）；
- App：Film 面板（DrtPanel 同构）+ 节点图投影卡 + Y/M 双滑杆 + 求解按钮（Solve）；
- 资产（OQ 裁后）：`Resources/FilmProfiles/` + NOTICE/LICENSE + 加载器。

**零改动红线核对**：V50Order 现行行零插入（新槽 add-only）；六格式导出矩阵零触；
`defaultFaceDisabledOpNames` 零 diff；既有文档在缺 FilmRecord 键时逐位不变
（pristine 直通，DRT 同款门）。

## §10 Alcedo 差异卖点确认（对标核对）

Alcedo「胶片模拟」实为 **LUT 面**（`LutSettingsPanel.qml:9,34,454-482` 的
filmSimulationCount / "Film simulation" 分类 = LUT 库子类）+ post-process 胶片
颗粒滑杆（`EditorPostProcessPanel.qml:147-301` film_grain strength）。
**无**阶段分离物理模型、**无**配光求解、**无**宽容度/置位教导面——
V2-PROPOSAL.md:50 「Alcedo 无此面 = 差异化卖点」经源码核对成立。

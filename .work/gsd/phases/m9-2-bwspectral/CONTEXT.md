# M9-2 CONTEXT — 光谱延展：黑白族 + 滤色镜 charter + 单 plan 裁决正本（2026-10-27）

> **裁决正本**：OQ-M92-1..8 **全部按 `RESEARCH.md` §6 推荐落定**（research 正本
> 2026-10-27 站批；M6-3/M6-4、M7-2..M7-6、M8、M9-0 charter「OQ 全按推荐」
> auto-advance 制度同款——M9-0 夜间授权令「M9 直接按推荐自动推进」在案，
> D-07-3-T5-1 先例。**晨审可推翻**——推翻 = 用户晨审修订本文件对应 D 条，
> plan 受影响任务面重开）。读解正本 = 同目录 `RESEARCH.md`（§1 上游测绘 /
> §2 数据面双源方案 / §3 我方盘点 file:line / §4 差距矩阵 / §5 golden 真值源 /
> §6 OQ 与风险）；planner 2026-10-27 抽核 ~14 点亲核吻合（见 §亲核登记）。
>
> **站形态**：单 plan 站（M9-2 量级 M、charter ΔN +15..20；对照 M3-3 三 plan /
> M8 四 plan——本站消费面全就绪、纯增量，无核换代无架构迁移，单 plan 五任务
> 足载）。本文件承载 charter 四件（OQ 裁决 / SC 门 / 范围红线 / 编排）+
> plan 层设计钉死（X 条）；执行正本 = 同目录 `M9-2-PLAN.md`。
>
> **编排**：单 plan 串行 T1..T5；**C 档停 = plan 执行+验收闭环后停汇报**
> （AGENTS 暂停机制；M9 站内下一站 M9-3 Upright 无依赖，等 orchestrator 排程）。
> 本 plan 规划期零构建零测试零 commit（重活道归在飞 R6）；执行批一切重活
> 起跑前必过 `Scripts/machine-guard.sh`；排程避让 R6/M9-1 重活窗（机器级单重活制）。

## Phase Goal

把 M8 光谱核的消费面从「28 卷 CC 彩色谱面」延展到**黑白胶片族 + 变反差相纸 +
镜头滤色镜 + per-film granularity 标定**：4 卷 BW profile + Multigrade 级相纸
（厂商发表规格数字化**自建**，非 GPL 复制）落盘即被现有谱链全量接受
（`channel_model:"bw"` M8-1a 已 decode——BW 语义全部由数据涌现，零 kernel 零
引擎分叉）；变反差 grade 档 = `printCC` preset 平移；camera_filter = build 期
CPU 乘法（sensW 窗口段后插 `t[λ]/factor`，绿通道归一保 18% 灰）；granularity
= 推荐强度标定层（grain 算子本体零 diff）。验收形态：构建绿 + 定向 bundle
全绿 + 全套带式对账（M8 终态 ⊕ R6 ⊕ M9-1 ⊕ 本批 +15..20）+ 四门 golden
（中性/阶调/滤色镜零漂移与方向/数字化精度——自建参考数学真值）+ bake 键
正确性负测组（同 pair 不同滤镜/grade 不撞缓存 + absent 档键恒等）+ zh-audit
双 PASS + GUI 走查配方落库。

## 决议（D-M92-1..8 = OQ-M92-1..8 全按推荐，生效值，硬约束，执行中不重开）

### D-M92-1 granularity 标定落位 = BW 资产目录侧独立标定表

- **裁决**：per-film granularity 落 **`Resources/FilmProfilesBW/grain_calibration.json`**
  （stock → 发表 RMS µm + 来源/口径注记 + 推荐强度映射）；GrainModule
  本体零 diff（D-M8-4 空间族挂账不解冻算子——OQ-M9-8 站级裁决「仅标定面」
  的落位形态）。
- 理由一句：grain iop 零 diff 最稳；表随 BW 资产目录走，来源登记与
  MANIFEST 对账单文书链。
- 证据：RESEARCH §4 M9BW-03 表 + §6 OQ-M92-1；`GrainModule.swift:50-75`
  （dt 遗产三滑杆亲核——无 per-film 概念）。
- 晨审推翻点：翻案 = profile metadata 新键（schema 面扩展，不建议）或
  GrainModule 静态表（触碰冻结算子文件，不建议）。

### D-M92-2 granularity 强度语义 = 推荐强度层（零 bump）

- **裁决**：**不动 GrainModule 渲染语义**（strength 保持 dt [0,100] 相对量，
  存量观感零变——process 零 bump 的组成部分）；标定面 = per-film
  **推荐 strength** + 发表 RMS readout（面板给「该胶片发表 RMS + 推荐值」，
  一键应用推荐值 = 一次普通参数编辑，走既有 commit 语义）；量纲桥 =
  标定映射（合成中灰面 net density 1.0 条件下 GrainModule 输出 RMS vs
  strength 曲线 → 反解推荐值，48µm 孔径口径注记随表）。
- 理由一句：strength 量纲重定义触 process 红线（观感变更），推荐层零
  bump零迁移。
- 证据：RESEARCH §4 process 表「granularity 标定 = grain iop 参数面不动 →
  零 bump」+ §6 OQ-M92-2。
- 晨审推翻点：翻案 = strength 语义重定义（触红线 + 全档迁移，不建议）。

### D-M92-3 BW 资产目录 = 独立目录 `Resources/FilmProfilesBW/`

- **裁决**：自建 BW 族落**新目录** `Resources/FilmProfilesBW/`（profiles/
  五 JSON + camera_filters.json + paper_grades.json + grain_calibration.json
  + NOTICE + MANIFEST.sha256）；**不进 `Resources/FilmProfiles/`**（该目录
  = CC BY-SA spektrafilm 包，MANIFEST.sha256 对账 + 逐字节冻结纪律——
  混入自建文件破对账）；NOTICE/MANIFEST 独立，许可注记 =
  "digitized from manufacturer publications, factual data" + 商标注记
  （Kodak/Tri-X/T-Max/Fujifilm/Neopan/Acros/Ilford/HP5/Multigrade =
  各自 owners' trademarks，名字只说数据出处——上游 NOTICE 同款立场）。
- 理由一句：MIT LUT / CC BY-SA FilmProfiles / 自建 BW 三资产物理隔离
  先例（M2-5-3 KD-4 / M3-3-01 KD-2 分账链）。
- 证据：RESEARCH §2.4 + §6 OQ-M92-3；`Resources/FilmProfiles/` 28 卷 +
  四件文书亲核。
- 晨审推翻点：翻案 = FilmProfiles 子目录（破 CC 包 MANIFEST 对账，不建议）。

### D-M92-4 sidecar = schema v12（additive 字段批走 bump，M7-4 先例）

- **裁决**：FilmRecord 两新 optional 字段（`cameraFilter: String?` /
  `paperGrade: String?`）随 **schema v12 单 bump** 落库（`schemaVersionCurrent`
  11→12，单 commit 单 bump 携双键定义；decode `decodeIfPresent` 双向兼容）。
  nil/缺席 = 恒等分支 = 现 solve 行为零漂移。FilmRecord 是值类型整体
  Codable——字段 additive 自动进 record JSON 与 HistoryItem.filmRecord 镜像；
  `stableHash()` 含新字段自动生效（solve 缓存 recordHash 消费自动跟随）。
- **编码裁决附注（MAJ-1，2026-10-27 评审修复——T2 开工前钉死）**：
  `paperGrade: String?` = "00".."5" **verbatim**。上游 paper_grades 表
  7 档 key 含 "00"（y_filter_neutral 199.0）与 "0"（137.9）两个**不同**
  档位，Int 编码无法无歧义表达（0 只能表达其一）；String 与上游表 key
  直映，上游 wire 亦无 grade Int 先例（档 = 表 key 字符串 + m/y 浮点
  对）。三处消费面同此编码：sidecar v12 持久键（本 D）/ D-M92-5
  gradeTag 折 print·scan 槽的折叠值 / UI grade picker 数据源。nil
  语义不变（= 现 solve 零漂移）。
- 理由一句：v8 aiProvenance / v9 filmRecord / v10 process / v11 note——
  persisted-face addition bumps 先例链；v11 内 additive 技术可行但语义
  混（哪批加的键不可考）。
- 证据：RESEARCH §4 sidecar 段 + §6 OQ-M92-4；`LightamerSidecar.swift:250-255`
  bump 注释链亲核；M7-4 note 归属先例（AGENTS 里程碑表）。
- 晨审推翻点：翻案 = v11 内 additive（省 bump 语义混，不建议）。

### D-M92-5 bake 键扩展 = filterTag/gradeTag ⊕ pairHash 折 SpectralPrintBake 槽键（本站最重架构件）

- **裁决**：**R1 正解**——`SpectralPrintBake` 三槽键从裸 `materialPairHash`
  扩为折入变体 tag（policyTag 折叠法先例，DRT policyTag 同构）：
  - **filterTag**（cameraFilter 非 nil/非空才折）折**三槽全量**（tc 槽
    必折——tc_lut 是 sensW 的函数，滤镜改 sensW；print/scan PCHIP 表是
    tc 下游，同折）；
  - **gradeTag**（paperGrade 非 nil 才折；折叠值 = 档 key **String
    verbatim**〔"00".."5"，D-M92-4 编码裁决〕）折 **print/scan 两槽**
    （tc 槽不折——tc_lut 不依赖 printCC/相纸 grade；print/scan 表输入含
    printCC 钉死值）；
  - **absent 恒等负测钉死**：无 filter + 无 grade 档三槽键与 M8 键
    **逐字节恒等**（「非 none 才折」= DRT policyTag 折叠法先例）——
    存量档缓存零 miss 零漂移。
  - 同批 **materialPairHash fold 集对齐消费集**（M8 遗留修正）：
    `FilmMaterialStore.foldProfile` 现折 stock + log_exposure +
    density_curves + base_density + wavelengths——补 `log_sensitivity` +
    `channel_density` + `viewing_illuminant`（三键 = SpectralBuildEngine
    实消费键，grep 实证——真·对齐消费集）+ `midscale_neutral_density`
    （**预折**：引擎当前零消费（grep 实证——仅 FilmProfile decode/
    projected 自身面），非消费集项；理由 = 防未来消费扩面致 fold 漏键
    撞缓存。MIN-1 修正：与 foldProfile doc 注释「fold = 恰好消费集」
    的矛盾以 DECISIONS 分开登记两类理由消解，终清单 DECISIONS 落）
    → 同 stock id 资产更新不再撞缓存。**hash 变更
    无碍**：pairHash 只做缓存键不做持久身份（research R1 注记）——全量
    pair 键一次冷 miss（重算即得同值），非正确性问题，DECISIONS 登记。
- 理由一句：fold 集不含谱面键 + 滤镜/grade 改 build 输出 → 同 pair
  撞缓存出**错误复用**是正确性缺陷，plan 期钉死折叠形态防执行临场发明。
- 证据：RESEARCH §0.5 + §6 OQ-M92-5 + R1；`FilmMaterialStore.swift:109-160`
  fold 集亲核（确不含三谱键）；`FilmPrintBake.swift:346-` 三槽独立 LRU
  亲核。
- 晨审推翻点：翻案 = Parameters 全量序列化键（键膨胀 + 每字段变更全槽
  失效，不建议）。

### D-M92-6 滤色镜 UI 座位 = Film 面板新节（SHOOT 域语义标注）

- **裁决**：Film 面板（`FilmPanelView`/`FilmPanelModel`）增**「镜头滤色镜」
  新节**，picker 9 档（无 + w8/w11/w12/w15/w21/w25/w47/w58）；节头/说明
  caption 标注 SHOOT 域语义（「拍摄时镜头前置——作用于胶片感光，非放大机
  dichroic」——与既有 Y/M 滤色偏移是两回事）。不设独立面板。
- 理由一句：SHOOT 域参数与材料对同宿主（FilmRecord），Film 面板是材料
  操作的稳定心智面。
- 证据：RESEARCH §6 OQ-M92-6 + §3.4 差距表（Film 面板双 picker 现成）。
- 晨审推翻点：翻案 = 独立 picker/面板（IA 膨胀，不建议）。

### D-M92-7 BW stock 分组 = picker 分节（channelModel 消费位）

- **裁决**：film stock picker 按 `channelModel` 分节（彩色 / 黑白两组，
  monochrome 分组位 = StockCatalog 形态对照、零 GPL 复制）；BW 与色片
  行为差异**全部由数据涌现**（三通道同值谱 + 1/3 密度过通用谱链自然
  单通道化）——`channelModel` 唯一 UI 消费 = 分组位，无渲染逻辑分叉。
- 理由一句：28 彩色 + 5 BW 混排难选；分节是 channelModel 的最小诚实
  消费面。
- 证据：RESEARCH §1.1（channel_model 引擎零消费、App 侧消费 =
  StockCatalog 分组位）+ §6 OQ-M92-7；`FilmProfile.swift` channelModel
  decode 亲核在位。
- 晨审推翻点：翻案 = 混排（可用性差，不建议）。

### D-M92-8 滤镜集合 = 8 全上 + w58 数据侧注记

- **裁决**：8 Wratten 全上；w58（绿）在上游 Tri-X 因子验证偏 0.67 档
  （7 中唯一超 0.21 带）——**数据侧注记**入 camera_filters.json
  （`factor_check_note`）与 NOTICE，用户可自见偏差异；不砍。
- 理由一句：8 枚是上游 SHOOT 域全集对照面；砍枚留洞不如注记透明。
- 证据：RESEARCH §1.3 + §6 OQ-M92-8。
- 晨审推翻点：翻案 = 首发 7 枚（数据缺口时 R2 兜底同形，晨审可裁）。

## 设计承接钉死（X-M92-1..6，plan 层硬约束）

### X-M92-1 滤色镜乘法缝（build 期 CPU，两 .metal 零 diff 的根据）

- **插入点** = `SpectralBuildEngine.swift` sensW **窗口段之后、tc 展开循环
  之前**（`:451`/`:453` 邻位——窗口段 `:431-451`，tc 循环 `:453-474`
  亲核）；**形态 = 材料链前置算子（build 输入侧），非 coupler 扩展、
  非 kernel 改动、不上 v50 序新 iop**。数学（hanatos.cpp:165-196 同构）：
  1. `t[λ]` = 81 点透射谱（camera_filters.json 10nm 400-700 → 线性插值
     5nm → <400 线性外推 / >700 持平——上游处理法照抄，事实处理非创意）；
  2. `factor = Σ(sensW_G·t·refSPD) / Σ(sensW_G·refSPD)`——**绿通道整卷
     单 factor**（色片保滤镜偏色；BW 三通道同值 → factor 唯一 → 18% 灰
     曝光不变——滤镜因子给定语义）；sensW = **窗口终态**（window 段后），
     refSPD = film 参考光源（build 既有量）；
  3. `sensW[l][c] *= t[l] / factor`。
- **film leg 是唯一正确座位**（SHOOT 域语义 = 感光输入侧；我方 decode
  段无对应 iop、不该有——滤的是胶片见的光，不是显影后像素）。
- 双 .metal 零 diff 由此结构性成立：滤镜只改 build 期 sensW 输入，
  kernel 消费表（tc_lut/print/scan）形态不变。

### X-M92-2 grade 档 = printCC preset 平移 + printExposure 走 gain 消费层

- `Parameters.printCC`（`SpectralBuildEngine.swift:211` 亲核——nil = 自解
  中性 pack，非 nil = 钉死）= grade 的天然载体：grade 表三元组
  `(m, y, exposure)` 中 **m/y → printCC 钉死值**；**exposure → solve
  gain 消费层**（record 层手动叠加、不入缓存键——exposureEv 同款契约
  〔D-M8-8/X6 先例〕；与既有 exposureEv 叠加序 = grade 增益先、手动
  trim 后，DECISIONS 落终式）。
- paper_grades 表 = **计算件非数据件**：我方 solve 链拟合（grade 00-5 →
  m/y/exposure，中灰同密度目标）+ 四卷 BW 中灰验证（上游 bw_checks
  "the pack is the paper's" 法平移）——不描 7 档曲线，相纸 profile 只
  入三乳剂谱 + 2-3 条代表 grade 特性曲线（R7 处置）。
- grade 档语义：nil = 现 solve 行为（零漂移）；非 nil 档（String
  "00".."5" verbatim——D-M92-4 编码裁决）= preset 钉死 + 增益。

### X-M92-3 数据资产布局与数字化工作流纪律

```
Resources/FilmProfilesBW/
  profiles/  kodak_tri_x_400 / kodak_tmax_100 / fujifilm_neopan_acros_100_ii /
             ilford_hp5_plus_400 / ilford_multigrade_iv_rc（.json ×5）
  camera_filters.json      # 8 Wratten × 81 点 + 双源标记 + w58 注记（T1）
  paper_grades.json        # T2 拟合生成入库（计算件，注记生成法）
  grain_calibration.json   # T4 标定生成入库（含口径注记）
  NOTICE                   # 来源出版物编号 + 商标注记 + factual-data 立场
  MANIFEST.sha256          # 逐文件对账正本
```
- **数字化工具** = `Scripts/bwprofile/`（Python：pdfplumber 矢量路径抽取 +
  600dpi 栅格描点 + 轴仿射 + SHEET/ASSUMED tags 生成 + 透射表转录校验）；
  `uv run python3` 走起（全局 Python 红线），**零新 SPM**（数据工具链
  脚本不进 app）。工具一次建成后续 profile 增量复用。
- **来源登记纪律**：每资产 `metadata.datasource` + NOTICE 来源表（URL +
  出版物编号 + 下载日期 + PDF sha256）；**厂商 PDF 不入仓**（PDF 整体
  受版权保护，采样点/数值是事实——只登记 hash 佐证）；PDF 原件与大图
  证据落 evidence 分仓（M4-0 政策）。
- **假设标注法照抄上游纪律**（行为对照非复制）：每数组键 `SHEET`
  （表上量的）/`ASSUMED`（外推的 + 外推率/锚）进 `metadata.tags`——
  Tri-X 形态参照 RESEARCH §1.1 引文。
- **谱口径逐卷照抄上游事实判断**：Acros II 谱图 = daylight 5400K →
  除黑体谱还原感光度；HP5 谱图 = 钨丝 2850K → taken as drawn（复现
  Ilford 公表日光滤镜因子）。
- **granularity 逐 PDF 独立核对**：四值以我方下载的官方 PDF 数据行为准
  （T-Max 已知出入：上游 0.74=7.4 vs 现行 F-4016 多处引 RMS 8——以
  PDF 为准修正）；上游值只作交叉参考；口径注记（Kodak 整数 RMS 48µm
  扩散密度 1.0 / Ilford 一位小数 / Fuji 按显影液别）随表入册。

### X-M92-4 许可红线：数据自建非 GPL 复制

- **事实数据不受版权保护**（测量事实）：厂商 PDF 曲线采样点、RMS 值、
  Wratten 透射百分比——自建数字化合法，NOTICE 引来源出版物编号即可。
- **禁止**：复制 SpektraLab `resources_product/` 任何数组（GPL 仓产品
  数据；即便 2026-10-20 起 GPL 同许可复制合法，charter 红线选择自建 =
  NOTICE 干净 + 无传染面，同 MIT LUT/CC BY-SA 物理隔离先例）。上游
  `camera_filters.hpp` 81 点表**不得复制**——从 B-3 转录源独立重录
  （karmalimbo B-3 数字化表 + Kodak Wratten 2 官方页**双源交叉**；
  数字同值不可避免——同一物理事实——但录入路径独立；上游表**只读
  对照第三源**，滤镜因子验证法照抄：我方 Tri-X 谱 × 我方透射表算
  factor 对 F-4017 p1 表，基准 = 7 中 6 ≤0.21 档）。
- Wratten 双源缺口处置（R2）：mat.uc.pt 页实测不含 8/11/12/15/21/47/58
  → 双源 = karmalimbo + Kodak 官方；两源都缺某滤镜 → 该滤镜砍掉
  （8→N，UI 列表跟数据走，DECISIONS 登记）。

### X-M92-5 process 零 bump 全站 additive（RESEARCH §4 表生效）

| 变更 | 存量观感 | 判定 |
|---|---|---|
| BW 新 stock（4 卷 + 相纸） | 不可达（新 id） | 零 bump |
| cameraFilter 字段 | 缺席 = 恒等分支 + tag 不折（absent 恒等负测） | v2 内 additive |
| paperGrade 字段 | 缺席 = printCC nil（现行为） | v2 内 additive |
| granularity 标定 | grain iop 参数面不动（推荐强度层） | 零 bump |

**RenderProcess.swift 零 diff**（current=2 不动；v3 继续留给 M9-4
ColorWheels——其 LGG 公式重写 = 真观感变更，两站无冲突）。sidecar
schema v12 bump（D-M92-4）≠ process bump——两条版本线独立（v10 process
键先例）。

### X-M92-6 索引与面板接线形态

- `FilmMaterialStore` 现单目录注入（`init(profilesDirectory:)`，
  `:42` 亲核）→ **additive 多目录形态**（`profilesDirectories: [URL]`
  或并列 init），App 组装点注入双目录（FilmProfiles + FilmProfilesBW），
  测试注入仓内双路径；camera_filters/paper_grades/grain_calibration
  **不进 profile 索引**（非 FilmProfile——独立加载器）。
- `FilmPanelModel` 扩：grade picker 数据源（grade 表——String 档 key
  verbatim，D-M92-4 编码裁决）+ filter picker
  数据源（透射表枚举）+ stock 分节（channelModel 分组）+ granularity
  readout；picker commit 走既有 `recordFilmChange` 单 discrete commit
  语义（D-H1 不涉——非滑杆）。
- film sub-run seed 四项序零改：`fnv(recordHash ⊕ policyTag ⊕
  solvedPackHash ⊕ upstream)`（`FilmTailPolicy.swift:115-142` 亲核）——
  recordHash 含新字段自动生效（尾平面键正确性由 recordHash 保证），
  bake 槽键显式折 tag 是 D-M92-5 面。

## 范围红线（plan 逐条引用；通用红线族参照 M8 CONTEXT 红线 1-16 同款纪律）

1. **数据自建非 GPL 复制**（X-M92-4 全文）：SpektraLab resources_product
   任何数组零拷贝（含 camera_filters.hpp 81 点表）；GPL 上游只读对照；
   自建资产 provenance/NOTICE/MANIFEST 单文书链。
2. **双 .metal 零 diff**：`FilmSubRunKernels.metal`（M3-3 冻结）+
   `SpectralFilmKernels.metal`（M8 收口冻结）——滤镜/grade 全在 build 期
   CPU（X-M92-1 结构性保证）；执行批 `git diff` 两文件零命中机检。
3. **bake 键三槽折入 + 负测必在**（D-M92-5）：同 pair 不同滤镜/不同
   grade 不撞缓存负测 + absent 档键与 M8 逐字节恒等负测——缺任一 =
   收口门拒绝。
4. **process 零 bump**（X-M92-5）：`RenderProcess.swift` 零 diff；
   sidecar v12 bump 仅限 schemaVersion 行 + additive 注释（单 commit）。
5. **封存面 17 件零 diff**（M7-6 原始清单全集——SUMMARY 红线表 #5 亲核；
   AGENTS 速查「15 项」= 不含 IOP Registry/ModuleInstance 的简写，机检
   按 17 件全集跑，MIN-4 勘正）：DrtRecord / TerminalTailPolicy /
   DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf /
   ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·
   WebPEncoder）/ NodeGraphCommand / **sidecar schema（LightamerSidecar——
   例外：v12 单 bump 显式触碰件，D-M92-4；= 封存面登记〔M7-6〕以来
   首例 bump，豁免有据——文件自带 bump 章程 + persisted-face 先例链 +
   本 plan 显式例外申报）** / HistoryStack /
   HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog
   （NodeOwnershipCatalog）/ IOP Registry / ModuleInstance（后两件本站
   零 v50 新 iop、零 Registry 面，被触概率≈0——机检仍全集跑）
   ——除 LightamerSidecar 显式 bump 外全零 diff；
   FIX2③ `LibraryProjectController.swift` 零 diff + `McpServerController.swift`
   零 diff 延续（本站零 Library/MCP 面）。
6. **film 自有面豁免**（M8 先例延续）：`FilmTailPolicy.swift` /
   `FilmPrintBake.swift`（键族扩展正业）/ `SpectralBuildEngine.swift`
   （滤色镜乘法缝正业）/ `FilmMaterialStore.swift`（fold 对齐 + 多目录
   正业）/ `FilmRecord.swift`（两新字段正业）/ `FilmPanelModel·View`
   （picker/readout 正业）——豁免 = 上述件的可控扩展，`PixelPipe.swift`
   仍零 diff（滤色镜/grade 参数透传全在 FilmTailPolicy/Parameters，
   不需要动 film leg 组装）。
7. **xcstrings 尾块纯插入 + zh-audit 双 PASS**；动态键显式 switch 返回
   静态键（V14）；`String.LocalizationValue("prefix_\(x)")` 禁形零命中。
8. **UserDefaults 零新键**（grade/filter/granularity 全为文档级 record
   字段或纯 readout，无偏好面）。
9. **L041 tuist generate 恒末位** + 新测试文件同 commit 入 Project.swift
   对应 bundle 显式数组 + BUNDLE-MAP 登记（E2 纪律）。
10. **机器级单重活 + 排程避让**：起跑前过 `Scripts/machine-guard.sh`；
    规划期零构建零测试（重活道归 R6）；执行批排程避让 R6/M9-1 重活窗；
    `--all` 全套轮 orchestrator 批准制 + 8G 门 + MEMFAIL 机检。
11. **commit 纪律**：每任务独立 commit（Conventional Commits 全英文、
    只 add 相关文件、不 push）；plan 内 commit 草稿零 issue ref；前缀
    `feat(m92)/fix(m92)/test(m92)/docs(m92)`。
12. **CC 资产零触碰**：`Resources/FilmProfiles/` 28 卷 + 四件文书逐字节
    冻结（M3-3 纪律不变）；NOTICE 消费披露行不动（M8-3 已升格，本站
    BW 目录有独立 NOTICE）。

## 测试策略（四门 golden + 负测组 + 数据面对账；L048 比较 space 纪律）

1. **中性门**（BW 数据正确性，结构性的）：五色块 chart（18% 灰/红/绿/
   天蓝/深蓝）过 (BW film, Multigrade) 光谱臂全链 → 输出三通道散
   ≤2e-3（三通道同值谱 + 1/3 密度的结构性验证，不依赖绝对标定）。
2. **阶调门**：grade 00 < 2 < 5 密度跨度单调 + 5 > 1.3×00 + 18% 灰
   displayed density 落 0.55-0.95 带（printCC preset + printExposure
   增益正确性）。
3. **滤色镜门**（零漂移 + 方向）：cameraFilter nil 档输出与 M8 基线
   **逐字节一致**（恒等分支 + absent 键恒等）+ filter 档 18% 灰
   |Δ| < 0.01（factor 归一验证）+ w25/w47 色块方向断言（红滤镜红亮
   天暗蓝暗 / 蓝滤镜反之，阈值 0.05）。
4. **数字化精度门**（数据面真值）：采样曲线 vs 厂商 PDF 控制点回读
   （轴仿射残差 ≤ 读图精度带：矢量 ~1e-3 dex / 栅格 0.01-0.02 dex）+
   特性曲线斜率段 vs sheet 标称 gamma/CI + 滤镜因子交叉（6/7 ≤0.21
   档基准）。
5. **bake 键负测组**（D-M92-5 主门）：同 pair 不同滤镜 tc/print/scan
   三槽全 miss 负测 + 同 pair 不同 grade print/scan miss、tc HIT 断言
   + absent 档三槽键逐字节 = M8 基线 + materialPairHash fold 对齐后
   同 stock 同谱内容恒等/谱变 miss。
6. **数据面对账**：MANIFEST.sha256 全量对账 + schema 接受（BW 落盘即
   decode）+ SHEET/ASSUMED 标注在册断言 + channelModel 分型计数 +
   granularity 四值与 PDF 核对值一致断言 + 透射表双源一致性快照。
7. **sidecar v12**：v11 文档 decode→encode 逐字节零漂移负测 + v12
   双键往返 + 缺席 = 恒等 + recordHash 折新字段生效断言（同 record
   改 grade → seed 变）。
8. **granularity**：标定映射确定性 + 单调 + 推荐 strength 下合成灰面
   RMS 输出与发表值同带（48µm 孔径简化口径注记；带宽 DECISIONS 落）。

## ΔN 分账 + 全套带式对账

| 任务 | ΔN | 构成 | 落点 |
|---|---|---|---|
| T1 数据面 | +3..4 | MANIFEST 对账 / schema+分型 / 标注纪律 / 透射表快照 | Layers |
| T2 谱面消费+相纸 grade | +5..6 | 中性/阶调 golden / grade 表拟合 / sidecar v12 / bake 新 pair / 面板 | IOP·IOPParity·Layers·Library·App |
| T3 滤色镜 | +4..5 | factor 数学 / bake 键负测组 / 零漂移+方向 / typed 拒 / UI | IOP·IOPParity·App |
| T4 granularity | +2..3 | 标定表+映射 / 语义断言 / readout | IOP·IOPParity·App |
| T5 收口 | +1..2 | 端到端冒烟 / 登记 | — |
| **合计** | **+15..20** | charter 带 M（15-20N）命中 | 五 bundle 域 |

**全套对账锚（带式——三者皆在飞/待执行）**：

```
全套预期 = M8 终态 4287/39/0（GOAL-STATE 2026-10-26 亲核）
         ⊕ ΔN_R6（在飞——开工前亲核 R6 SUMMARY 实数）
         ⊕ ΔN_M9-1（待执行——charter 估 +20..28；开工前亲核 M9-1 终态）
         ⊕ ΔN_M9-2 = +15..20（本 plan）
```

skip 面：本批无 probe 族（零 perf probe 新面）；39 基线 skip 漂移随
R6/M9-1 终态亲核合并对账。`--all` 归 orchestrator 批准轮（T5 只跑定向
bundle + 对账表达式申报）。

## 亲核登记（planner 抽核批，2026-10-27；执行以本节为准）

1. `FilmProfile.swift:140-160` 区域：`channelModel`/`densitometer`/
   `viewingIlluminant` decode 在位（M8-1a additive）——BW 落盘即接受
   的根据 ✓。
2. `SpectralBuildEngine.swift`：`build` 入口 `:354` / `filmSens =
   10^logSensitivity` `:374-381` / sensW 窗口段 `:431-451`（erf4 带通 +
   per-channel 归一亲核在位）/ tc 展开循环 `:453-474`（`acc[c] +=
   spectrum(λ)·sensW[l][c]`——滤镜改 sensW 即改全链）/ `Parameters.
   printCC` `:201-211`（nil=solve 注释亲核）/ `illumPrintFor(cc m, y)`
   `:558-572` ✓。
3. `FilmMaterialStore.swift:109-160`：`materialPairHash` fold 集 =
   stock + log_exposure + density_curves + base_density + wavelengths
   ——**确不含** log_sensitivity/channel_density/midscale（R1/D-M92-5
   实锤）✓；`init(profilesDirectory:)` 单目录 `:42` ✓。
4. `FilmPrintBake.swift:346-420`：SpectralPrintBake 三槽（tc 6 / print
   PCHIP 8 / scan PCHIP 8）各槽独立 LRU + bakeCount 可观测，键 =
   materialPair 域 fnv 哈希 ✓。
5. `FilmTailPolicy.swift`：`policyTag(for:)` exhaustive switch `:104-108`
   （.v1/.v2 两臂）/ seed 四项序 `fnv(recordHash ⊕ policyTag ⊕
   solvedPackHash ⊕ upstream)` `:115-142` ✓——recordHash 含新字段自动
   生效，seed 面零改。
6. `FilmRecord.swift:51-90`：七字段（filmStock/paperStock/yFilterShift/
   mFilterShift/contentAdaptiveShift/strength/exposureEv）——无
   cameraFilter/paperGrade（本站两新字段位）✓；stableHash = canonical
   JSON FNV-1a（KD-1 形）✓。
7. `RenderProcess.swift:85-92`：current = 2（M8-2 bump 注释亲核）——
   本站零 diff 目标 ✓。
8. `LightamerSidecar.swift:250-255`：schemaVersionCurrent = 11 + bump
   注释链（v8/v9/v10/v11）——v12 落同链 ✓。
9. `GrainModule.swift:50-76`：Params = scale（dt 域）/ strength [0,100]
   默认 25 / midtonesBias——dt 相对量、无 per-film 概念 ✓（T4 量纲桥
   的必要性实证）。
10. `App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift:85-110`：
    filmStocks/paperStocks picker 数据源 + displayName typed 降级 ✓；
    `FilmPanelView.swift` 同目录在位 ✓。
11. `Resources/FilmProfiles/`：28 卷 + LICENSE/NOTICE/MANIFEST.sha256/
    CHANGELOG 四件套 ✓——BW 独立目录的必要性实证。
12. BUNDLE-MAP 域模式 + E2 登记纪律 + tuist 末位（L041）在册 ✓；
    七 bundle 名 = IOP/IOPParity/Layers/Library/Sessions/Export/App ✓。
13. 基线链：M8 终态 4287/39/0（GOAL-STATE 2026-10-26 续接点亲核）；
    R6 executor 在飞（重活道）；M9-1 待执行（charter M-L 20-28N）——
    带式对账锚成立 ✓。
14. 上游读解锚（RESEARCH §7 表）：BW 三通道同值（Tri-X dump）/ 相纸
    三乳剂分裂 + 盲色截止 ≥560nm / grade→(m,y,exposure) 表 / 滤色镜
    乘法 + 绿通道 factor / ownGrain 四值 / bw_checks 五 check——
    planner 对 RESEARCH §1 引文与 §7 锚点表交叉核对一致 ✓。

## 风险登记（执行批处置绑定）

| # | 风险 | 量级 | 处置 |
|---|---|---|---|
| R1 | bake 键不扩展 → 滤镜/grade 撞缓存错误复用 | 高（正确性） | D-M92-5 必做件 + 负测组（门 5）缺一收口拒 |
| R2 | Wratten 8 滤镜独立源转录（mat.uc.pt 页不含） | 中 | X-M92-4 双源（karmalimbo + Kodak 官方）+ 因子验证；两源缺 → 砍枚（8→N，UI 跟数据走） |
| R3 | 栅格 PDF 描点无现成自动化（Fuji/Ilford 三份） | 中 | 工具脚本一次建成（Scripts/bwprofile）；Acros 5400K 除谱、HP5 2850K 口径照抄上游判断 |
| R4 | granularity 发表值口径差（T-Max 8 vs 7.4） | 低 | 逐 PDF 核对（T1 首任务）+ 口径注记入表；上游值只作交叉参考 |
| R5 | Multigrade IV RC 停产（2023） | 低 | 照上游用 IV RC 2019 官方 sheet（经典暗房语义；MG V 留资产增量） |
| R6 | tc_lut 构建秒级 × 滤镜变体 → tc 槽（LRU 6）压力 | 低-中 | 滤镜档构建按需 + LRU 淘汰（既有机制）；交互预算 = 构建一次后缓存命中；首挂滤镜卡顿登记观察项 |
| R7 | 相纸三乳剂 × 7 档 grade 曲线数字化工作量 | 中 | 谱 + 2-3 条代表曲线入 profile；全 7 档走拟合（X-M92-2 计算件） |
| R8 | golden 真值自建（无上游对照） | 中（如实声明） | 自建参考数学即正本：中性门是结构性的（不依赖绝对标定）；数字化精度 0.01-0.02 dex 对打印观感 = 无 bit 对照对象，登记即可（RESEARCH §5 精度预算） |
| R9 | 数据数字化工作量本身（条目计数） | 中（工期） | 4 卷谱+特性曲线+锚 / 相纸三乳剂谱 / 8×81 透射 / 4 RMS 值 / 工具脚本 ~1-1.5 天（RESEARCH §2.6 表：合计 ~4-5 人机协作日）；栅格卷各 ~1 天为长杆 |

## 晨审推翻点索引（可推翻面速查）

- D-M92-1：独立表 ↔ profile metadata 键 / GrainModule 静态表。
- D-M92-2：推荐强度层 ↔ strength 量纲重定义（触 process 红线）。
- D-M92-3：独立目录 ↔ FilmProfiles 子目录（破 CC 包对账）。
- D-M92-4：v12 bump ↔ v11 内 additive。
- D-M92-5：tag⊕pairHash 折槽键 ↔ Parameters 全量序列化键。
- D-M92-6：Film 面板新节 ↔ 独立面板。
- D-M92-7：picker 分节 ↔ 混排。
- D-M92-8：8 全上+注记 ↔ 首发 7 枚。
- X-M92-2：printExposure 走 gain 消费层 ↔ 折 build 表（曝光语义重标定
  面，不建议）。

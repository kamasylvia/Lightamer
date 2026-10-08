---
phase: m3-3
plan: "M3-3-03"
title: "FSIM golden 与收口批——数学复算主门（fused kernel/印相 LUT bake/置位曲线三面 Float64 独立复算）+ 确定性门 suite（双解 bit-identical + 缓存键折叠 + 跨 ROI 同解端到端）+ Film 面板最小面（DrtPanel 同构：材料对 Picker + Y/M 双滑杆 + 强度 + 求解 readout）+ 节点图只读投影卡 + M3-3 收口（报备终轮 + AGENTS 增量节含光谱不可达注记）"
wave: 3
depends_on: ["M3-3-02"]
autonomous: true
requirements: ["FSIM-01b（确定性门验收面）", "FSIM-01c（golden 门）", "FSIM-01a（UI 投影卡半面）"]
estimated_tests: "+20..28"
test_bundles: [Layers, IOPParity, App]
files_modified:
  - Tests/LightamerTests/FilmGoldenTests.swift            # 新建（IOPP 级，Golden* 域惯例）：fused kernel 逐像素 vs Float64 独立复算 / bake 体素级 / 置位曲线数学
  - Tests/LightamerTests/FilmDeterminismTests.swift       # 新建（LAYERS/Core 级）：双解 bit-identical / 缓存键折叠序 / 跨 ROI 同解端到端 / 统计整数秩
  - App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift   # 新建：@Observable 面板 model（读三级投影 + 单 discrete commit，DrtPanelModel 同构）
  - App/Sources/Lightamer/UI/Shell/FilmPanelView.swift    # 新建：材料对双 Picker + Y/M 双滑杆（D-H1 trio）+ 强度/曝光 + 内容偏移 Toggle + readout
  - App/Sources/Lightamer/State/InspectorState.swift      # 修改：filmPageActive 会话开关（exportPageActive 先例，Inspector 列分支）
  - App/Sources/Lightamer/UI/Shell/Nodes/NodesPanelModel.swift   # 修改：只读 Film 卡投影行（卡列表构建点 additive——预判触点实名，checker 回注 2026-10-08 m5）
  - App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift  # 修改：Film 卡视图 + AX 标签位（预判触点实名；执行期 read_first 5 亲核实位——触点外溢 = C 档回注，禁静默扩面）
  - Resources/Localizable.xcstrings                       # 修改：film_* 键块 append 尾部（既有键字节与顺序零触碰）
  - Tests/LightamerTests/FilmPanelTests.swift             # 新建（APP/App 级）：model 投影/commit 面/滑杆 D-H1/缺键 pristine
  - Tests/LightamerTests/FilmCardTests.swift              # 新建（APP/App 级）：只读卡投影/AX 可达
  - Project.swift                                         # 修改：测试登记（L041 批尾）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：增行登记（E2）
  - AGENTS.md                                             # 修改：「M3-3 架构增量」节（含光谱不可达架构注记 + 确定性门 + 封存面正本）
  - .work/gsd/phases/m3-3-fsim/M3-3-03-SUMMARY.md         # 新建（含 phase 小结节 + M3-3 验收锚状态表）
  - .work/gsd/phases/m3-3-fsim/M3-3-03-DECISIONS.md       # 新建
  - .work/GOAL-STATE.md                                   # 修改：M3-3 phase 终态 + 续接点（→M3-4）
  - .work/TODO.md                                         # 修改：M3-3 清账
  - .work/LESSONS.md                                      # 如踩坑
  - .work/gui-acceptance/m3-3/                            # 新建：走查证据（面板/投影卡/pristine 直通）
---

# Plan M3-3-03 — FSIM golden 与收口批（wave 3）

> **性质**：M3-3 验收批 + 收口。三根柱：①**golden 数学复算主门**（OQ-2-⑤ 裁定
> 形态——文档化数学的独立实现复算， SpektraLab 渲染**仅本地目测不入仓**）；
> ②**确定性门 suite**（FSIM-01b 验收面：同统计+同材料+同模式→同解的端到端
> 机检）；③**Film 面板最小面 + 节点图只读投影卡**（DrtPanel 同构最小面——
> FSIM-02 宽容度/教导面**不在本批**，OQ-2-④ 裁定 M3-4）。收口含 M3-3 phase
> 小结节与报备终轮。
> **SC 数字门（ROADMAP「plan 期定」兑现）**：AC7——全套 `--all` 报备终轮
> **0 fail / 0 MEMFAIL（8G 门机检）** + golden 主门零失败 + 确定性门零失败 +
> pristine 直通（film 未激活行为逐位门）+ 登记三方对表。
> **光谱不可达边界（FSIM-01c 架构注记收口位）**：本批把 01/02 已落的域约定
> 升格为 AGENTS「M3-3 架构增量」正式注记——染料近似 = RGB 密度域（密度曲线 +
> 底色偏移 + 串扰 + 滤色通道增益 + 相纸曲线），**非光谱重放**；用户可见措辞
> 「物理流程建模，非光谱重放」。

## 已定裁决（生效值，硬约束，不得重开）

1. **⑤ golden 形态**：主门 = **独立数学复算零误差/标称容差**（M3-1-01 golden
   三件套先例：公开标准部分用公开参考值，自定曲线部分用文档化公式 Float64
   复算）；**SpektraLab 渲染图不入仓不 push**（仅开发期本地目测对照观感方向，
   证据不落 gui-acceptance）；逐像素 parity 对 SpektraLab 无意义（光谱域 vs
   RGB 密度域本就非对应——golden 语义 = 我方模型的数学一致性与跨版本稳定性）。
2. **② 确定性门**：同输入统计 + 同材料对 + 同模式 → 同解（bit-identical 断言）；
   缓存键 = `fnv(材料对Hash ⊕ 统计Hash ⊕ 模式tag)`（键折叠序钉死——变更任一分量
   → 键必变，负测钉死）；统计整数秩。
3. **① UI 投影面**：节点图 M2-4 语义**零改动**——Film 卡 = PipelineDocument
   投影层**只读卡**（材料对名 + active 状态），非新 NodeKind；Film 面板 = 
   document 级编辑面（DrtPanel 同构）。
4. **④ 面板范围裁界**：材料对选择 + Y/M 双滑杆 + 强度 + 曝光 + 内容偏移 Toggle
   + 求解 readout + 启停——**不含**宽容度教导/直方图/双虚线/descriptor（M3-4 
   FSIM-02）；不含置位参数面板。
   > checker 回注（2026-10-08，m4）：原「filmPlacement 参数经 grade add face
   > 已可达」高估——面板机制 = per-op 手写 provider（无通用面板驱动），02 注册
   > 即止 = filmPlacement 在 M3-4 前为**可加不可编的恒等占位**（add face 可
   > 枚举、参数恒零点恒等直通、无编辑面）——本 plan 一切涉及 filmPlacement 的
   > 措辞以此为准，与 02 KD-5「面板语义」注记互为正本。
5. **pristine 直通**：无 FilmRecord 文档 = 面板呈现 pristine 态 + 渲染链逐位
   现状（02 已钉管线门，本批补 UI 面门）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 golden 数学复算主门（T1，IOPP Golden* 域）

- **三面**：
  > checker 回注（2026-10-08，E5）：门 1 容差锚原写「float32 管线 vs Float64
  > 参考 = 每通道 ≤2e-6 相对（LUT 插值段 ≤1e-5）」——与本仓实测先例矛盾：
  > M3-1-01-ACCEPTANCE §五/DECISIONS §4 已实测裁决「GPU==理想 Float64 ±1e-5
  > 在任何 ~65³ 复合晶格下**数学不可达**」（胶片曲线解码到线性 working 域的
  > 65³ 晶格插值地板 **~8e-3，1e-3..1e-2**——Agfa_Vista_100 全链 0.0087 /
  > Kodak_Vision_320T 0.0068 实测），同类门结构 M3-1-01 §4 已收窄过一次，本
  > plan **预声明同款两级分解**，不再留给执行轮重裁。
  1. **fused kernel 逐像素（两级门）**：受控输入纹理（梯度/中性 ramp/棋盘，
     规模 ≤512²—— 3024 基线 RSS 纪律，禁 100MP 面进 golden）× 2-3 材料对 ×
     Y/M/强度角点 → kernel 输出（L014 fence 读回）。
     - **门 1a（kernel 实现正确性）**：kernel vs **同表 CPU 四面体采样双写**
       （测试文件内独立 sampler——`Lut3dKernelTests.cpuLut3d` 非 bake 自身
       `sampleTable` 的非同源纪律先例）：float 类容差 **~1e-6 相对可达**。
     - **门 1b（烘焙表忠实度）**：烘焙表 vs **理想连续模型独立 Float64 复算**
       （测试文件内独立实现——不复用产线 FilmPrintBake/midGrayDensities 代码
       路径；公式域 = RESEARCH §4.1 文档化模型 + 02 DECISIONS 串扰常量）：容差
       **按 65³ 晶格插值地板标定写死**（先例带 1e-3..1e-2，执行期实测定值 +
       DECISIONS 记依据）——禁用 ±1e-5 端到端锚（数学不可达，M3-1-01 §4 在案）。
     - **比较空间纪律（L048）**：比较一律 **decode 回 linear working 域**（对数
       腿 encode 零点斜率放大 f32 epsilon 750×——对数域逐像素比较是假失败源）；
       Float64 参考常数一律 `Double(Float(x))` 出厂值升维（f32 产线常量直接写
       Double 字面 = 参考失真）。
  2. **印相 LUT bake 体素级**：随机种子固定（LCG 常量种子——确定性）密度域
     体素 → FilmPrintBake vs 独立复算逐体素（**voxel 级 ≤1e-5 保留**——
     Float64 bake vs Float64 复算可达，M3-1-01 KD-6 体素门先例）；负域界/域标定
     一致性断言。
  3. **置位曲线数学**：`g_m` 曲线族 vs 独立复算（m=1 闭式与 m=2 数值解交叉）+
     恒等 bit-exact（delta≡0 逐位）+ 单调 + 硬渐近线不越相纸白黑地板。
- **中性闭合门（求解器×管线）**：mid-gray 场景过「负片段+自动解+印相 LUT」
  全链 → 输出 R≈G≈B（灰阶误差 ≤1e-3——RFC-028「反转走胶片自身中性曲线灰阶
  误差恰 0」的我方域验收形态）；sanity 带（01 交付）在此只作区间复核不重写。
- 材料 fixture = 仓内 CC BY-SA 源 JSON 直接引用（01 已入库，义务已随五件套
  履行，测试不新增分发面——RESEARCH §6-2）。

### KD-2 确定性门 suite（T2，LAYERS/Core 级）

- **双解 bit-identical**：同 (材料对, 统计, 模式) 下 solve×2 + 跨 runSub 重渲
  ×2 → 输出平面 bit-identical（L014 fence + 平面 hash 对比）。
- **缓存键折叠序**：三分量逐一翻转（材料对变/统计变/模式变）→ 键必变；任一
  不变 → 键不变（`fnv(材料对⊕统计⊕模式)` 键控语义钉死）。
- **跨 ROI 同解**（02 KD-2 红线的端到端钉）：同图 FULL vs 两个不同 ROI 窗口
  渲染 → 曝光 gain 同值（film 面无缝）。
- **统计整数秩**：构造已知计数分布 → 分位秩 = 手算整数秩（禁浮点插值路径）。
- **跨版本稳定性哨兵**：固定输入集（中性 ramp + portra_400×portra_endura）的
  film 输出平面 hash 常量化（`FilmGoldenConsts` 测试内常量 + DECISIONS 登记
  「重算入册流程」——模型数学有意变更时按流程重钉，禁静默漂移）。

### KD-3 Film 面板最小面（T3，DrtPanel 同构）

- **FilmPanelModel**（@Observable）：读 = `liveRecord → history 投影
  （effectiveFilmRecord）→ carrier` 三级；写 = `EditorState.recordFilmChange`
  单 discrete commit（DrtPanelModel/DrtPanelView 先例全同构——文件级双写禁令
  无，此处是**新建 twin** 而非复用，DrtPanel 零 diff）。
- **FilmPanelView**：film/paper 双 Picker（FilmMaterialStore 分型清单，显示
  `info.name`，值 = stock id；材料对变更 = 一次 commit + 求解缓存自然失效）；
  Y/M 双滑杆（D-H1 trio：拖动 live 零 item、松手一 commit，CC 点域 0-100）；
  强度/曝光滑杆；内容自适应偏移 Toggle（默认关——生效值②的可视化）；readout
  行（当前自动解 (M0,Y0)/曝光 gain——只读，Solve = 强制重解按钮走缓存失效）；
  pristine 态（无 record）= 「启用胶片模拟」入口态（创建默认 record 即首次
  commit——**默认 record 入 history 后即非 pristine**，与「缺键 = pristine」
  门自洽：启用动作本身 = 编辑）。
- **挂载**：InspectorState `filmPageActive` 会话开关（`exportPageActive` 先例：
  @Observable 会话态非持久、inactive 渲染面逐字节冻结）；Inspector 列顶部分支
  置于 DRT 页邻位。
- zh：`film_*` 键族 append `Localizable.xcstrings` 尾部（历史键字节与顺序零
  触碰）；材料名 = 资产 `info.name` 原文（不翻译，技术专名口径）；`zh-audit 
  --check` 键清单并集对账（静态键 scanner 可见——面板全部走静态键，禁
  `String.LocalizationValue("film_\(x)"` 插值形态——F-2 陷阱禁令）。

### KD-4 节点图只读投影卡（T4）

- PipelineDocument 投影层追加只读 Film 卡（材料对名 + active 态；无编辑面、
  无命令面、无 history 面——**NodeKind 零新增**，卡 = App UI 投影物）；触点
  = `App/Sources/Lightamer/UI/Shell/Nodes/`（执行期 read_first 5 实位亲核：
  卡列表构建点 + AX 标签位；若投影面为 PipelineDocument 驱动的枚举表，则
  additive 一枚投影行）。M2-4 命令集/undo/sidecar 零触碰（测试：卡在场不改变
  NodeGraphCommand 行为面——既有 NodeGraphCommandTests 零改全绿为门）。

### KD-5 M3-3 收口（T5）

- **报备终轮**：全套 `--all`（orchestrator 批准 + 运行监视 + MEMFAIL 8G 机检
  兜底——AGENTS 资源监控节）；贴线 bundle（IOP 7654 / IOPParity 5788）若 
  MEMFAIL 先查重测顺序漂移（±3% 方差，SPIKE 注记）再报。
- **AGENTS「M3-3 架构增量」节**（三 plan 约定正本）：FilmRecord/持久化键族/
  film sub-run 缝位与 seed/FilmSolveCache 键控/filmPlacement 注册行（V50 20.8 +
  E7 19 行）/封存面清单/**光谱不可达架构注记**/thumbnail 恒 legacy/导出
  $jobFilmTail/资产五件套与许可面（CC BY-SA 目录 + SA 传染边界：义务停留源
  JSON 与随包分发面）。
- SUMMARY phase 小结节：M3-3 验收锚（ROADMAP 行）逐条状态表（golden 门/确定性
  门/GUI 走查/SC 门）+ 三 plan 测试增量对账链（基线 **3029** = 3024 + 
  `571c3c0` +5 亲核值——收口终值 = 3029 + 三 plan 登记增量，禁凑数）。
- GOAL-STATE phase 终态 + 续接点 → M3-4（FSIM-02 宽容度面板 + descriptor 运行
  时 + M3 VALIDATION）；TODO 清账；REQUIREMENTS 翻账**不在本批**（M3-4 VALIDATION
  面统一翻，本批只留 SUMMARY 状态表）。

## read_first

1. `.work/gsd/phases/m3-2-fsim-research/RESEARCH-NOTES.md` §6（golden 策略四条
   ——主门形态/SpektraLab 目测纪律/descriptor 断言带）+ §4.1（模型域公式面）
   + `M3-2-CONTEXT.md` 裁决记录（⑤形态措辞）。
2. `Tests/LightamerTests/DrtKernelGoldenTests.swift`（IOPP 15 法——kernel vs 
   Float64 参考的容差标定与受控输入形态）+ `Lut3dEncodingTests.swift`（体素级
   golden + 公开参考值口径）+ `GradeKernelGoldenTests.swift`（受控纹理 + fence
   读回纪律）+ `.work/gsd/phases/m3-1-w1/M3-1-01-DECISIONS.md` §4（**门结构两级
   收窄正本**——「±1e-5 数学不可达」实测裁决与两级分解语义，KD-1 门 1b 的先例
   锚，E5 回注）+ `.work/gsd/phases/m3-1-w1/M3-1-01-ACCEPTANCE.md` §五/§4.4
   （晶格插值地板 ~8e-3 实测值与非门槛放水论证）。
3. `.work/gsd/phases/m3-3-fsim/M3-3-01-PLAN.md` / `M3-3-02-PLAN.md` 全部 KD +
   两批交付的 SUMMARY/DECISIONS（串扰常量/域标定/缓存键实位——golden 复算的
   公式域即此两处登记值）。
4. `App/Sources/Lightamer/UI/Shell/DrtPanelModel.swift` / `DrtPanelView.swift`
   （面板 twin 全形态：三级读/单 commit 写/D-H1/峰值钳制在面板的分工先例）+
   `App/Sources/Lightamer/State/InspectorState.swift`（exportPageActive 分支
   形态）+ `Tests/LightamerTests/DrtPanelModelTests.swift`（9 法断言形态）。
5. `App/Sources/Lightamer/UI/Shell/Nodes/` 目录 + 
   `LightamerCore/Sources/Graph/PipelineDocument.swift`（:44-47 链序——投影卡
   数据源；执行期亲核卡列表构建实位与 AX 位）。
6. `Resources/Localizable.xcstrings`（尾部追加纪律）+ `Scripts/zh-audit.py --check`
   （键清单并集口径）+ `.work/gsd/phases/m2-9-export/M2-9-05-SUMMARY.md` F-2
   （插值键陷阱禁令原文）。
7. `.work/gsd/phases/m3-1-w1/M3-1-VALIDATION.md`（SC 对账形态 + 全套轮记录
   格式）+ AGENTS 资源监控节（报备制/MEMFAIL 处置）+ `.work/LESSONS.md`
   L041/L014/**L048**（GPU golden 比较空间选型——decode 回 linear 域比较 +
   参考常数 `Double(Float(x))` 出厂值升维，KD-1 门 1 比较空间纪律正本，E5
   回注）。

## 纪律（强制）

1. **封存面清单**：`DrtPanelModel.swift` / `DrtPanelView.swift` / `DrtRecord.swift`
   / `TerminalTailPolicy` / `DrtTailAssembly` / `PixelPipe.swift`（02 已落 film
   腿，本批**零 diff**）/ `Lut3dKernels.metal` / `DrtEotf` / `ExportQueueContract`
   / 六格式矩阵 / M2-4 节点命令集（`NodeGraphCommand.swift`）/ sidecar schema
   （v9 已落零触）。
2. **SpektraLab 渲染物不入仓**（本地目测纪律）：gui-acceptance 证据只含本仓
   渲染走查截图（§3.2 截图纪律——视口关键区）；golden 测试零图像资产入库
   （受控输入程序化生成）。
3. **测试登记**（E2/L041）：四新测试文件同 commit 登记（FilmGolden = IOPP；
   FilmDeterminism = LAYERS；FilmPanel/FilmCard = APP）；generate 恒批尾。
4. **既有测试零改**为门：NodeGraphCommandTests / DrtTailTests / 
   GradeCatalogTests（02 已定格 19 行）/ DrtPanelModelTests 等既有族零 diff 
   全绿；任何需改 = 停下上报。
5. **checker 四条**：①真链（golden 走真 GPU 渲染 + fence 读回；确定性门走真
   runSub 双渲）；②登记闭环（三方对表 + 终值 3029+增量 对账链）；③语义断言
   （复算独立性——golden 参考函数不 import 产线 bake/求解代码路径，机检 =
   测试文件内自包含实现）；④边界核对（封存面零命中 + 图像资产零入库 +
   AGENTS 注记三节齐）。

## Tasks

### T1 golden 数学复算主门（KD-1）

- **action**：`FilmGoldenTests`（IOPP）：fused kernel 逐像素**两级门**（1a
  kernel vs 同表 CPU 四面体采样 / 1b 烘焙表 vs 理想模型 Float64 复算——KD-1
  E5 回注）三材料对角点矩阵 / bake 体素级 / 置位曲线三断言族 / 中性闭合门；
  比较一律 decode 回 linear working 域（L048）；容差标定值写死 + DECISIONS
  登记。
- **验收标准**
  - [ ] IOPP 定向轮绿；复算实现测试文件内自包含；零图像资产入库。

### T2 确定性门 suite（KD-2）

- **action**：`FilmDeterminismTests`（LAYERS）：双解 bit-identical / 键折叠序
  四向负测 / 跨 ROI 同解 / 整数秩手算对表 / 平面 hash 哨兵常量。
- **验收标准**
  - [ ] LAYERS 定向轮绿；哨兵常量 + 重钉流程入 DECISIONS。

### T3 Film 面板最小面（KD-3）

- **action**：FilmPanelModel/FilmPanelView 新建 + filmPageActive 分支 + film_*
  键块 + `FilmPanelTests`（三级投影/单 commit/Y-M D-H1/pristine 入口态/键静态
  性）；实机走查（面板挂载/滑杆/材料切换重渲/zh 呈现）落 
  `.work/gui-acceptance/m3-3/`。
- **验收标准**
  - [ ] APP 定向轮绿 + 走查证据落盘；DrtPanel 文件对零 diff；`zh-audit --check`
        键清单并集 PASS。

### T4 节点图只读投影卡（KD-4）

- **action**：投影层 additive Film 卡 + `FilmCardTests`（只读性/AX/既有命令面
  零扰）；实机走查同批落证据。
- **验收标准**
  - [ ] APP 定向轮绿；NodeGraphCommandTests 族零改全绿；M2-4 语义零改动
        （无新 NodeKind——`NodeKind` 枚举零 diff）。

### T5 M3-3 收口（KD-5）

- **action**：报备终轮 + AGENTS 增量节（含光谱不可达注记）+ SUMMARY（phase
  小结节 + 验收锚状态表 + 对账链：3029 + 三 plan 增量）/ DECISIONS / 
  GOAL-STATE 终态与续接点 / TODO 清账。
- **验收标准**
  - [ ] 终轮 `0 fail / 0 MEMFAIL`；终值对账两式互证（登记面 + 运行期 Executed）；
        ROADMAP M3-3 验收锚逐条状态落 SUMMARY；AGENTS 三节齐（架构增量/光谱
        注记/封存面）。

## 验收标准（AC 总表）

| # | AC | 机检方式 |
|---|---|---|
| 1 | golden 主门：kernel 逐像素 + bake 体素级 + 置位曲线 + 中性闭合，四门零失败；复算独立自包含 | T1 测试 |
| 2 | 确定性门：双解 bit-identical + 缓存键四向 + 跨 ROI 同解 + 整数秩 + hash 哨兵 | T2 测试 |
| 3 | Film 面板最小面在场（DrtPanel 同构、D-H1、pristine 入口态、zh 静态键）；DrtPanel 文件对零 diff | T3 测试 + 走查 + diff |
| 4 | 节点图只读 Film 卡（投影层 additive、零新 NodeKind、命令面零扰） | T4 测试 + `NodeKind` 零 diff |
| 5 | SpektraLab 渲染物零入库；gui-acceptance 证据只含本仓走查 | T3/T4 证据目录核 |
| 6 | 登记闭环（E2/L041）+ 封存面零命中 | 三方对表 + diff 机检 |
| 7 | **SC 门**：全套 `--all` 报备终轮 0 fail / 0 MEMFAIL（8G 机检）；终值 = 3029 + 三 plan 登记增量（两式互证）；golden/确定性/pristine 三门在终轮覆盖 | T5 终轮日志 + SUMMARY |

## 风险与边界

- **容差标定循环**：门 1 容差已**预声明两级分解**（KD-1 E5 回注——1a kernel vs
  同表采样 ~1e-6 / 1b 烘焙表 vs 理想模型按晶格地板带标定写死），执行期只做
  「带内定值 + DECISIONS 记依据」；若 1a 实测超 ~1e-6 量级 = kernel 实现疑点
  （非标定问题），停下排查；**禁反向改复算迁就 kernel**（复算是独立真相）；
  比较空间纪律（L048）违式 = 门无效须重跑。
- **hash 哨兵的重钉摩擦**：模型数学有意变更（如串扰常量修订）会翻哨兵——流程
  = DECISIONS 登记变更 → 重算 → 同 commit 重钉（M2-5 adoption 盖章先例口径）；
  无登记的哨兵翻转 = 缺陷。
- **投影卡触点不确定性**：Nodes 投影面实位（枚举表 vs 逐卡视图）执行期才见全
  貌——read_first 5 亲核后若触点形态偏离预估（如需触 `PipelineDocument` Core
  面），停下按 C 档回注 orchestrator，禁静默改 Core 文档模型。
- **报备终轮时间**：七 bundle 全套 ~20 分钟量级 + 监视人力——orchestrator 批准
  窗口对齐；MEMFAIL 贴线处置按 AGENTS 口径（IOP/IOPParity 贴线值在案）。
- **M3-3 ≠ M3 收口**：VALIDATION/REQUIREMENTS 翻账 = M3-4（ROADMAP 行原文）；
  本批 SUMMARY 状态表是 M3-4 翻账输入，非翻账本体。

## 提交约定

- T1 `test(iop): film golden math-recomputation gates`
- T2 `test(core): film determinism gate suite with cache key folding`
- T3 `feat(app): minimal film panel with material pickers and shifts`
- T4 `feat(app): read-only film projection card in node graph`
- T5 `docs(m3-3): close fsim phase with golden gates and ledger`
- 全英文 Conventional Commits；不 push。

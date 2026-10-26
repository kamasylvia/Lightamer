---
phase: M9-2
plan: "v2"
title: "M9-2 执行 plan — 黑白族 + 滤色镜光谱延展（T1 数据面自建：4 BW 卷 + 相纸 + Wratten 双源转录 + granularity 逐 PDF 核对 / T2 谱面消费 + 相纸 grade：printCC preset + sidecar v12 + 中性·阶调 golden / T3 滤色镜：sensW 乘法 + factor 归一 + bake 三槽键折入与负测组 / T4 granularity 标定层 / T5 收口：定向 + 全套带式对账 + zh-audit + 走查配方）"
depends_on: ["M8 全站（光谱核 + 谱面体系）", "M9-0 charter"]
autonomous: true
requirements: ["M9BW-01（BW profile 自建 + MANIFEST 对账 + 中性/阶调 golden）", "M9BW-02（变反差相纸 + 滤色镜：中性链零漂移负测 + 光谱透传 golden）", "M9BW-03（per-film granularity 标定表 + 强度语义断言）"]
success_criteria: "SC 全可机检——T1：MANIFEST.sha256 全量对账 + BW 落盘即 decode（channelModel 分型计数 5/5）+ SHEET/ASSUMED 标注在册断言 + granularity 四值 = PDF 核对值断言 + 透射表双源一致性快照 + Sources 可追溯（NOTICE 来源表逐条 URL+出版物号+sha256）；T2：中性门（五色块过 BW×Multigrade 光谱臂三通道散 ≤2e-3）+ 阶调门（grade 00<2<5 单调 + 5>1.3×00 + 18% 灰 0.55-0.95 带）+ grade 表四卷中灰验证 + sidecar v12（v11 逐字节零漂移负测 + 双键往返 + 缺席恒等）+ bake 新 pair 命中 + gradeTag absent 恒等；T3：滤色镜门（nil 档输出与 M8 基线逐字节一致 + filter 档 18% 灰 |Δ|<0.01 + w25/w47 方向断言）+ bake 键负测组（同 pair 不同滤镜三槽全 miss + 同 pair 不同 grade print/scan miss·tc HIT + absent 档三槽键逐字节 = M8）+ materialPairHash fold 对齐（谱键入 fold）+ typed 非法滤镜拒绝；T4：标定表 round-trip + 映射确定性/单调 + 推荐 strength 语义断言（合成灰面 RMS 与发表值同带）+ GrainModule 零 diff；T5：定向 bundle 全绿 + ΔN 对账（+15..20）+ 全套带式表达式 + zh-audit 双 PASS + 走查配方落库 + 双 .metal/封存面红线机检全零"
estimated_tests: "+15..20（T1 +3..4 / T2 +5..6 / T3 +4..5 / T4 +2..3 / T5 +1..2；越带申报理由）"
test_bundles: [Layers, Library, IOP, IOPParity, App]
baseline: "带式 = M8 终态 4287/39/0（GOAL-STATE 2026-10-26 亲核）⊕ ΔN_R6（在飞）⊕ ΔN_M9-1（待执行，charter 估 +20..28）——本 plan 开工前亲核 GOAL-STATE 与 R6/M9-1 SUMMARY 实数落基线表达式"
expected_all: "全套 = 基线链 + 本批 +15..20（--all 归 orchestrator 批准轮；本 plan 验收 = 构建 + 定向 bundle〔Layers/Library/IOP/IOPParity/App〕+ 对账表达式申报）"
red_lines:
  - "裁决正本 = 同目录 CONTEXT.md（D-M92-1..8 + X-M92-1..6 + 红线 12 条；晨审可推翻）；research 正本 = RESEARCH.md（§1 上游测绘 / §2 数据面 / §3-§4 差距与方案 / §5 golden 真值源 / §6 OQ）。"
  - "数据自建非 GPL 复制（X-M92-4）：SpektraLab resources_product 任何数组零拷贝〔含 camera_filters.hpp 81 点表〕；双源转录 + 上游只读对照；厂商 PDF 不入仓（NOTICE 登记 URL+出版物号+sha256；原件证据落 evidence 分仓）。"
  - "双 .metal 零 diff（红线 2）：FilmSubRunKernels.metal + SpectralFilmKernels.metal——git diff 两文件零命中机检；滤镜/grade 全在 build 期 CPU。"
  - "bake 键三槽折入 + 负测必在（红线 3 / D-M92-5）：filterTag 折三槽 + gradeTag 折 print/scan 槽 + absent 档键与 M8 逐字节恒等——负测组缺任一 = 收口门拒绝。"
  - "process 零 bump（红线 4）：RenderProcess.swift 零 diff；sidecar v12 单 bump 仅 schemaVersion 行 + additive 注释（D-M92-4）。"
  - "封存面 17 件零 diff（红线 5；M7-6 原始清单全集口径——AGENTS 速查「15 项」为不含 IOP Registry/ModuleInstance 的简写，机检按 17 件全集；例外 = LightamerSidecar v12 显式 bump）；FIX2③ LibraryProjectController + McpServerController 零 diff；film 自有面豁免清单（红线 6）；CC 资产 Resources/FilmProfiles/ 逐字节冻结（红线 12）。"
  - "通用族：xcstrings 尾块纯插入 + zh-audit 双 PASS（红线 7）/ UserDefaults 零新键（8）/ tuist 末位 + BUNDLE-MAP 同 commit 登记（9）/ 机器级单重活 + 排程避让 R6·M9-1（10）/ commit 纪律 feat(m92) 前缀（11）。"
files_modified:
  - Scripts/bwprofile/                                                # T1：新建 Python 数字化工具（矢量抽取/栅格描点/轴仿射/tags 生成/透射表转录校验——uv run python3，零新 SPM，不进 app）
  - Resources/FilmProfilesBW/                                         # T1：新建自建资产目录（profiles×5 + camera_filters.json + NOTICE + MANIFEST.sha256）；T2 增 paper_grades.json；T4 增 grain_calibration.json
  - Tests/LightamerTests/BWProfileAssetsTests.swift                   # T1：新建（Layers）——MANIFEST 对账/schema 接受/标注纪律/透射表快照
  - LightamerCore/Sources/Film/FilmMaterialStore.swift                # T2：多目录索引 additive；T3：materialPairHash fold 谱键对齐（:109-160 fold 集扩）
  - LightamerCore/Sources/Film/PaperGradeTable.swift                  # T2：新建——grade→(m,y,exposure) 拟合纯函数 + 四卷中灰验证
  - LightamerCore/Sources/Graph/FilmRecord.swift                      # T2：cameraFilter/paperGrade 两 additive 字段（:51-90 七字段后）
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift             # T2：schemaVersionCurrent 11→12（:255 + bump 注释行）
  - LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift             # T2：paperGrade→printCC preset 消费缝 + grade printExposure 增益消费层；T3：cameraFilter→Parameters 传参缝（seed 四项序 :115-142 零改）
  - App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift              # T2：grade picker 数据源 + stock 分节（channelModel）；T3：filter picker；T4：granularity readout（:85-110 picker 数据源区扩）
  - App/Sources/Lightamer/UI/Shell/FilmPanelView.swift               # T2/T3/T4：grade picker 节 + SHOOT 滤镜节 + readout 行（picker commit 走既有 recordFilmChange）
  - LightamerCore/Sources/Film/CameraFilterTable.swift               # T3：新建——透射表加载/5nm 插值/8+1 枚举 typed 拒绝
  - LightamerCore/Sources/Film/SpectralBuildEngine.swift             # T3：Parameters.cameraFilter + sensW 乘法缝（:451/:453 邻位插入 t/factor——:431-451 窗口段后、:453-474 tc 循环前）
  - LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift              # T3：SpectralPrintBake 三槽键折 filterTag/gradeTag（:346- 键族区）
  - LightamerIOP/Sources/Grain/GrainCalibration.swift                # T4：新建——标定表加载 + stock→推荐 strength 映射纯函数（GrainModule.swift 本体零 diff）
  - Tests/LightamerTests/PaperGradeTableTests.swift                  # T2：新建（IOP）
  - Tests/LightamerTests/BWSpectralGoldenTests.swift                 # T2：新建（IOPParity）——中性门/阶调门/bake 新 pair
  - Tests/LightamerTests/SidecarV12Tests.swift                        # T2：新建（Library——SidecarV10/V11 双连 LIB 同位，MIN-2）——v11 零漂移负测/双键往返/缺席恒等
  - Tests/LightamerTests/FilmPanelBWTests.swift                       # T2：新建（App）——grade picker 模型/分节
  - Tests/LightamerTests/CameraFilterTests.swift                      # T3：新建（IOP）——加载/插值/factor 数学/typed 拒绝
  - Tests/LightamerTests/FilterBakeKeyTests.swift                     # T3：新建（IOPParity)——bake 键负测组/零漂移/方向断言
  - Tests/LightamerTests/GrainCalibrationTests.swift                  # T4：新建（IOP）——表 round-trip/映射确定性单调
  - Tests/LightamerTests/GrainCalibrationSemanticsTests.swift        # T4：新建（IOPParity）——推荐 strength 语义断言
  - Project.swift                                                     # T1-T5 逐任务：新测试文件当批入对应 bundle 显式数组（T1 另含 FilmProfilesBW folderReference）；T5 只做全量核对——tuist generate 恒各批末位（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt        # T1/T5：落域登记
  - .work/gsd/phases/m9-2-bwspectral/M9-2-SUMMARY.md                  # T5：执行摘要
  - .work/gsd/phases/m9-2-bwspectral/M9-2-DECISIONS.md                # T5：裁定记录（grade 曝光叠加序/fold 终清单/标定带宽/双源取值/偏差）
  - Resources/Localizable.xcstrings                                   # T2/T3/T4：新键尾块纯插入（BW 分组/grade/SHOOT 滤镜节/readout 键族）
---

# Plan M9-2 — 光谱延展：黑白族 + 滤色镜（单 plan 五任务）

> **裁决正本** = `CONTEXT.md`（D-M92-1..8 全按 research 推荐 + X-M92-1..6 +
> 红线 12 条；晨审可推翻）；规格正本 = `RESEARCH.md`（§1 上游测绘 / §2 数据面
> 双源方案 / §3 我方盘点 / §4 差距矩阵 / §5 golden 真值源；planner 抽核
> ~14 点亲核吻合——CONTEXT §亲核登记）。
>
> **一句话**：BW = 谱面包新条目（三通道同值数据过通用谱链自然单通道化，
> 零 kernel 零引擎分叉）；grade = printCC preset 平移；滤镜 = build 期
> sensW 乘法（两 .metal 零 diff 结构性成立）；granularity = 推荐强度标定层
> （grain 算子零 diff）。**本站最重架构件 = bake 键三槽折入**（R1 正确性
> 风险，负测组 = 主门）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（OQ 全按推荐已落 CONTEXT）。
> 执行中如触「必须扩面」（kernel 改动 / runTerminalTails 编排骨架 /
> RenderProcess / GrainModule 本体 / v50 新 iop / Resources/FilmProfiles
> CC 包内容）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5（T2 消费 T1 资产；T3 滤镜与 T2 grade
> 键族各随任务负测；T4 独立；T5 收口）。每任务独立 commit；重活起跑前过
> `Scripts/machine-guard.sh`；排程避让 R6/M9-1 重活窗。
>
> **C 档停**：T5 闭环后**停汇报**（plan 执行+验收闭环 = C 档门控位）。
>
> **基线（带式）**：M8 终态 4287/39/0 ⊕ ΔN_R6（在飞）⊕ ΔN_M9-1（待执行）。
> 开工前亲核 GOAL-STATE 与两 SUMMARY 实数落基线表达式；全套对账归
> orchestrator 批准轮，本 plan 验收 = 定向 bundle + 对账表达式申报。

## ΔN 预算表（逐任务，本 plan 分账 +15..20；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 数据面 | +3..4 | MANIFEST 对账 / schema 接受+分型计数 / SHEET·ASSUMED 标注断言 / 透射表双源快照（granularity 四值核对并入资产断言） | Layers（BWProfileAssetsTests） |
| T2 谱面消费+grade | +5..6 | 中性门 / 阶调门 / grade 表拟合+四卷中灰 / sidecar v12 三面 / bake 新 pair / 面板分节+grade picker | IOP·IOPParity·Layers·Library·App |
| T3 滤色镜 | +4..5 | factor 数学+插值+typed 拒 / bake 键负测组（三槽 miss·absent 恒等） / 零漂移+方向 / UI | IOP·IOPParity·App |
| T4 granularity | +2..3 | 标定表+映射确定性单调 / 语义断言（RMS 同带） / readout | IOP·IOPParity·App |
| T5 收口 | +1..2 | 端到端冒烟（BW×grade×filter 组合抽样） / 登记 | IOPParity |
| **合计** | **+15..20** | charter 带 M（15-20N）命中 | 五 bundle 域 |

## 已定裁决（生效值，硬约束，不得重开）

1. **D-M92-5 bake 键**：filterTag 折三槽 / gradeTag 折 print·scan 槽 /
   absent 恒等负测 + materialPairHash fold 谱键对齐——负测组 = T3 主门。
2. **X-M92-1 滤镜乘法**：sensW 窗口段后插 `t[λ]/factor`，绿通道整卷
   factor（保 18% 灰）；film leg 唯一座位；两 .metal 零 diff。
3. **X-M92-2 grade**：m/y → printCC 钉死；exposure → gain 消费层不入键。
   **paperGrade 编码 = `String?`**（"00".."5" verbatim——上游 7 档含
   "00" 与 "0" 两个不同档，Int 歧义；nil = 现 solve。三处消费面同此
   编码：sidecar v12 持久键 / gradeTag 缓存折叠值 / UI picker 数据源。
   裁决附注正本 = CONTEXT D-M92-4——MAJ-1，2026-10-27 评审修复）。
4. **D-M92-4 sidecar v12** 单 bump 携双键（cameraFilter/paperGrade）；
   process 零 bump（RenderProcess 零 diff）。
5. **D-M92-2 granularity 推荐强度层**：GrainModule 本体零 diff；
   strength 语义不动。
6. **数据自建**（X-M92-3/4）：独立目录 + 工具脚本 + 双源转录 +
   逐 PDF 核对；CC 包零触碰；MCP/Library 面零触碰。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m9-2-bwspectral/CONTEXT.md`（D/X 全文 + 红线 12 条 +
  亲核登记 + 测试策略八门）
- `.work/gsd/phases/m9-2-bwspectral/RESEARCH.md`（§1 上游形态 / §2 数据面
  直链与工作流 / §4 差距矩阵 / §5 golden 门 / §7 锚点速查）
- `LightamerCore/Sources/Film/SpectralBuildEngine.swift`（:354 build 入口 /
  :374-381 filmSens / :431-451 sensW 窗口段 / :453-474 tc 循环 /
  :201-211 printCC / :558-572 illumPrintFor）
- `LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift`（:346- 三槽键族）+
  `FilmTailPolicy.swift`（:104-142 policyTag/seed 四项序）+
  `LightamerCore/Sources/Film/FilmMaterialStore.swift`（:42 init /
  :109-160 fold 集）
- `.work/gsd/phases/m8-fsim-spectral/CONTEXT.md`（M8 红线族 + X7 三槽
  bake 机制正本——本站键扩展的宿主语境）
- `.work/gsd/phases/m3-3-fsim/M3-3-01-PLAN.md`（KD-2 资产五件套先例——
  本站数据文书格式对照）+ `Resources/FilmProfiles/NOTICE`（CC 包文书
  形态参照——**只参照不复制内容**）
- AGENTS.md「跨批不变量速查」+「Phase 执行模型」+ M2-9 xcstrings 纪律 +
  `.work/LESSONS.md` L013/L041/L048

---

## T1 — 数据面：BW profile 自建 + Wratten 双源转录 + granularity 逐 PDF 核对

> 零产线 Swift——纯资产 + Python 工具 + 资产断言测试。**来源可追溯 = 验收
> 主面**（NOTICE 来源表 + metadata.datasource + MANIFEST 字节数对账）。

**read_first**：RESEARCH §2 全节（datasheet 直链表 / 数字化工作流 /
granularity 溯源 / 许可红线 / Wratten 双源 / §2.6 工作量表）；CONTEXT
X-M92-3（布局与纪律）+ X-M92-4（许可红线）+ D-M92-8；M3-3-01 KD-2。

- **action**：
  1. **下载五份官方 PDF**（Tri-X F-4017 / T-Max F-4016 / Acros II
     AF3-0258E / HP5+ / Multigrade IV RC——直链表 RESEARCH §2.1）+ 两份
     Wratten 源（karmalimbo B-3 表 + Kodak Wratten 2 官方页）；逐份记
     sha256 → NOTICE 来源表（URL + 出版物编号 + 下载日期 + sha256）。
     **PDF 不入仓**；原件与大图证据落 evidence 分仓（M4-0 政策）。
  2. **Python 工具** `Scripts/bwprofile/`（uv run python3 + pdfplumber）：
     矢量路径抽取（Kodak 两卷——PDF 内嵌矢量图，坐标全精度 + 轴刻度两端
     仿射映射）/ 600dpi 栅格描点（Fuji/Ilford 三份——颜色阈值 + 亚像素
     质心，精度 ~0.01-0.02 dex）/ 谱尾外推（<380 与 >668-780 log-linear
     尾，逐卷 ASSUMED 标签）/ Acros 5400K 除谱还原、HP5 2850K taken as
     drawn（上游口径照抄）/ SHEET·ASSUMED tags 生成。工具输出 = JSON
     profile 骨架（人审后定稿入库）。
  3. **五份 profile 定稿**（schema = spektrafilm 子集，我方 consumer face
     全覆盖——`FilmProfile.swift` decode 零改即接受）：4 BW 卷
     （`channel_model:"bw"` = log_sensitivity 81×3 三通道同值 +
     channel_density 每波长 [1/3,1/3,1/3] 中性银 + densitometer
     diffuse_visual + target_print 相纸 id + 锚〔ISO 速度/base+fog/
     log_exposure 锚——文献式锚形态照 research §2.1〕）+ 相纸
     （三乳剂三通道谱分裂 + ≥560nm 盲色截止全 -10 + base_density=
     Dmin + reference_illuminant TH-KG3 + 2-3 条代表 grade 特性曲线
     ——R7 处置：全 7 档走 T2 拟合）。metadata.tags 逐数组键
     SHEET/ASSUMED + 外推率/锚（上游标注法照抄）。
  4. **camera_filters.json**：8 Wratten × 81 点——**双源独立转录**
     （karmalimbo 10nm 表 + Kodak 官方曲线，交叉取一致值；分歧值
     DECISIONS 登记 + 取官方源）→ 10nm 400-700 → 线性插值 5nm → <400
     线性外推 / >700 持平；每滤镜带 source 双标 + w58 factor_check_note
     （D-M92-8）。**禁止复制上游 camera_filters.hpp 表**；上游值只作
     第三源对照（工具内置对照报告，分歧 >2% 点逐个复核）。
  5. **granularity 逐 PDF 核对**（首任务内完成——research §2.3）：四卷
     RMS 数据行以我方 PDF 为准（T-Max 出入修正预期 7.4→8）；核对结论
     入 DECISIONS（四终值 + 口径注记）；grain_calibration.json 骨架
     （T4 补推荐强度列）。
  6. **NOTICE + MANIFEST.sha256**：NOTICE = factual-data 立场 + 商标
     注记 + 来源表；MANIFEST = 逐文件 sha256（对账正本）。
  7. `Project.swift`：`Resources/FilmProfilesBW` folderReference
     （Resources/LUTs 同款——Tuist 裸目录静默忽略坑）+ 新测试文件登记。
  8. 测试（Layers，BWProfileAssetsTests）：MANIFEST 全量对账（#filePath
     仓根定位）+ BW 落盘即 decode（5/5 channelModel=="bw" 分型——相纸
     同 "bw"？否——相纸 channelModel 缺省 color 或 bw 按实际数据定，
     断言按定稿写死）+ 标注在册（每卷 metadata.tags 含 SHEET 与 ASSUMED
     各 ≥1）+ 透射表形状（8×81 + 值域 [0,1] + 双源标记字段）+
     granularity 四值与 DECISIONS 终值一致断言。
- **验收标准（机检）**：
  - `git diff --stat` 产线面 ⊆ {Project.swift（资源+测试登记）}；
    零 Core/App 源码 diff。
  - MANIFEST 对账测试绿（逐文件 sha256）；NOTICE 来源表覆盖全部 7 份
    源文档（5 PDF + 2 Wratten）——grep 机检 URL+sha256 条目数 ≥7。
  - BW profile 三通道同值断言（log_sensitivity 行内三值逐位相等 ×81）
    + 相纸三乳剂分裂断言（460-540nm 段三通道存在差异 + ≥560nm 全
    ≤ -9）——**来源可追溯 + 结构正确双面**。
  - `Scripts/bwprofile/` 工具可重跑（uv run python3 入口自洽；PDF 本地
    存在时输出与入库 JSON 逐字节一致——工具自检报告落 evidence）。
- **commit**: `feat(m92): add self-digitized bw film family and wratten assets`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（某源不可达 →
  砍滤镜/换镜像源；某卷栅格质量差 → 描点密度调整）= DECISIONS 申报
  （含双源取值分歧表）；**禁复制 SpektraLab 任何数组**；**禁把厂商
  PDF 入仓**；**禁动 Resources/FilmProfiles/ CC 包**。

## T2 — 谱面消费 + 相纸 grade：printCC preset + sidecar v12 + 中性/阶调 golden

> BW 落盘即全链接受的验证面 + 变反差 grade 全链（字段→preset→bake→面板）。
> grade 档语义：nil = 现 solve 行为零漂移；非 nil 档（String "00".."5"
> verbatim——MAJ-1 编码）= preset 钉死 + 增益。

**read_first**：RESEARCH §1.1-§1.2（BW 数据结构 / 相纸配对形态 / wire
机制）+ §5 门 1/2；CONTEXT D-M92-4/X-M92-2/X-M92-6 + 测试策略门 1/2/7；
`FilmMaterialStore.swift`（init/fold）+ `SpectralBuildEngine.swift`
（:201-211 printCC + :558-572 illumPrintFor）+ `FilmTailPolicy.swift`
（Parameters 组装点 + gain 消费层 :441-467 域）+ `LightamerSidecar.swift`
（:250-255 bump 位）+ `FilmPanelModel.swift:85-110`。

- **action**：
  1. `FilmMaterialStore` additive 多目录（`profilesDirectories: [URL]`）；
     App 组装点注入双目录；测试注入仓内双路径（BW 5 项入 filmStocks/
     paperStocks 索引断言——BW 卷自动出现在既有 picker 数据源）。
  2. `FilmRecord` 两 additive 字段：`cameraFilter: String?`（nil/""=无）
     + `paperGrade: String?`（**编码裁决 MAJ-1**："00".."5" verbatim——
     上游 7 档含 "00"/"0" 两不同档，Int 歧义；与上游 paper_grades 表
     key 直映，gradeTag 折叠值/UI picker 数据源同此编码；nil = 现
     solve；decodeIfPresent + init 默认 nil；stableHash 自动含——负测
     断言同 record 改 grade → recordHash 变）。**CodingKeys 同步扩
     （MIN-6 提醒）**：FilmRecord 是手写 `init(from:)`（tolerant
     decode）+ synthesized encode——新 optional 字段不进 CodingKeys
     时编译通过、decode 恒 nil、encode 静默丢键、recordHash 不含
     （一处三静默），CodingKeys/decode/encode 三面须同批扩。
  3. `LightamerSidecar` **v12 单 bump**（schemaVersionCurrent 11→12 +
     bump 注释行；两键经 FilmRecord Codable 自动携带——sidecar 层最小
     diff）；SidecarV12Tests：v11 文档 decode→encode 逐字节零漂移 +
     v12 双键往返 + 缺席 = 恒等（nil 序列化省略语义按 v9 filmRecord
     先例——默认档不入 map 不写 sidecar 的 pristine 纪律延续：两字段
     缺席不触发 record 非默认判定？**注意（MIN-5）**：pristine 判定
     **两处面**同步扩——Core `isFilmRecordDefault`（FilmRecord.swift
     synthesized == 自动覆盖 nil 档）+ App `FilmPanelModel.isPristine`
     （FilmPanelModel.swift:77-83 **手写逐字段判定**——cameraFilter/
     paperGrade 非 nil 档须手扩，否则「仅 grade/filter 设置」的 record
     在 UI 面被误判 pristine）。**SUMMARY 落账登记句（评审 obs 采纳）**：
     sidecar v12 = 封存面登记（M7-6）以来首例 bump——豁免有据（文件
     自带 bump 章程 + persisted-face 先例链 + 本 plan 显式例外申报），
     SUMMARY 摘要节显式登记该事实。
  4. `PaperGradeTable`（新建，纯函数）：grade 00-5 → (m, y, exposure)
     拟合——我方 solve 链（SpectralBuildEngine 印相腿：给定 grade 目标
     密度跨度，解 m/y + 曝光比；拟合于 Tri-X）+ 四卷中灰验证（同表把
     其余三卷中灰打到同密度带——bw_checks check 3 法平移）；生成
     paper_grades.json 入库（计算件注记生成法与拟合锚）。
  5. 消费缝（FilmTailPolicy）：paperGrade 非 nil → `Parameters.printCC`
     钉死 preset（表 m/y 值）+ grade printExposure → solve gain 消费层
     叠加（**不入缓存键**——exposureEv 同款契约；叠加序 = grade 增益
     先、手动 exposureEv 后，DECISIONS 落终式）；nil → 现 solve 行为
     逐字节。seed 四项序零改（recordHash 自动折）。
  6. UI（FilmPanelModel/View）：stock picker 按 channelModel 分节
     （D-M92-7）+ grade picker（无 + "00".."5" 档——**数据源 = String
     档 key verbatim**（MAJ-1 编码），直映 paper_grades 表 key；BW
     相纸激活时可见——非 Multigrade 相纸档列表为空+说明行）；picker
     commit 走既有 `recordFilmChange` 单 discrete commit。xcstrings 新键
     尾块纯插入（分组头/grade 档名〔技术专名 zh=原文〕/picker 标签）。
  7. 测试：BWSpectralGoldenTests（IOPParity）——**中性门**（五色块
     chart 过 (Tri-X, Multigrade) 光谱臂 v2 全链 → 三通道散 ≤2e-3，
     4 卷 ×3 代表 grade 全跑）+ **阶调门**（grade 00<2<5 密度跨度单调
     + 5>1.3×00 + 18% 灰 displayed density 0.55-0.95）+ bake 新 pair
     （BW pair 二次 build HIT + pair 变 miss）；PaperGradeTableTests
     （IOP）——拟合收敛/四卷中灰带/表 round-trip；SidecarV12Tests
     （Library——SidecarV10/V11 双连 LIB 同位，MIN-2）；FilmPanelBWTests
     （App）——分节数据源/grade picker commit/pristine 判定扩。
  8. Project.swift 当批登记（MIN-3，L041/E2）：PaperGradeTableTests 入
     IOP 数组 + BWSpectralGoldenTests 入 IOPParity 数组 + SidecarV12Tests
     入 Library 数组 + FilmPanelBWTests 入 App 数组，BUNDLE-MAP 增行同
     commit；`tuist generate` = 本任务最后一个动作。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 产线 ⊆ {FilmMaterialStore, PaperGradeTable,
    FilmRecord, LightamerSidecar, FilmTailPolicy, FilmPanelModel,
    FilmPanelView, xcstrings}。
  - 中性门 + 阶调门绿（自建参考数学真值——门值即正本，无上游对照，
    风险声明见风险节）；v11 零漂移负测绿。
  - pristine 纪律：无 film record 文档 + 仅默认 record 文档渲染逐字节
    不变（既有 FilmDeterminism 零回归 + 本批负测）。
  - gradeTag absent 档：无 grade 文档 bake 槽键与 T2 前恒等（键折入在
    T3 落地——本任务先钉 absent 语义面断言位，T3 负测组收口）。
- **commit**: `feat(m92): consume bw profiles and add paper grade presets`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（资产仍在库——T1 独立
  成立）；偏差（grade 拟合不收敛 → 二段式/锚放宽；printExposure 叠加序）
  = DECISIONS 申报；**禁触 SpectralBuildEngine build 数学**（printCC 既有
  缝消费——SBE 本任务零 diff 目标）；**禁动 seed 四项序**；**禁在
  LightamerSidecar 之外任何 persisted-face 文件**。

## T3 — 滤色镜：sensW 乘法 + factor 归一 + bake 三槽键折入（主门）

> X-M92-1 乘法缝 + D-M92-5 键族（含 materialPairHash fold 对齐）——
> **缓存正确性负测组 = 本站最重门**：同 pair 不同滤镜/grade 不撞缓存
> + absent 恒等。

**read_first**：RESEARCH §1.3（camera_filter 全读解——hanatos.cpp:
165-196 乘法数学 + wire + 边界）+ §2.5（Wratten 双源）+ §5 门 3/4；
CONTEXT X-M92-1/D-M92-5/D-M92-6 + 测试策略门 3/5；`SpectralBuildEngine.swift`
:420-480（窗口段 + tc 循环——插入点亲核）+ `FilmPrintBake.swift:346-`
（三槽键族）+ `FilmMaterialStore.swift:109-160`（fold 集）+
`FilmTailPolicy.swift`（Parameters 传参缝）。

- **action**：
  1. `CameraFilterTable`（新建）：camera_filters.json 加载 + 10nm→5nm
     插值 + 8+1 枚举（none + w8/w11/w12/w15/w21/w25/w47/w58）+
     typed 非法名拒绝；双源标记透出（w58 注记达 UI caption）。
  2. `SpectralBuildEngine`：`Parameters.cameraFilter: CameraFilter? =
     nil`（additive）+ 乘法缝——sensW 窗口段后、tc 循环前插：
     `factor = Σ(sensW[绿]·t·refSPD) / Σ(sensW[绿]·refSPD)`（绿通道
     整卷单 factor；BW 三通道同值 → factor 唯一）→ `sensW[l][c] *=
     t[l]/factor`。nil = 恒等分支（零乘法路径——absent 语义）。
     **tc_lut/print/scan 表全部随之正确变化——kernel 零触碰**。
  3. `FilmPrintBake` 三槽键折入：tc/print/scan 槽键 = `fnv(pairHash ⊕
     filterTag)`（filterTag = cameraFilter 名，nil 不折）+ print/scan
     槽再折 `gradeTag`（gradeTag = paperGrade **String 档 key verbatim**
     （"00".."5"——MAJ-1 编码），nil 不折）——**absent 恒等**：
     无 filter 无 grade 档三槽键与 M8 逐字节恒等（「非 none 才折」，
     DRT policyTag 先例）。
  4. `FilmMaterialStore.materialPairHash` fold 对齐（M8 遗留修正）：
     fold 集补 `log_sensitivity` + `channel_density` +
     `viewing_illuminant`（**对齐消费集**——SpectralBuildEngine 实
     消费三键，grep 实证在案）+ `midscale_neutral_density`（**预折**：
     引擎当前零消费（grep 实证——仅 FilmProfile decode/projected 自
     身面），非消费集项；理由 = 防未来消费扩面致 fold 漏键撞缓存。
     MIN-1：与 foldProfile doc 注释「fold = 恰好消费集」的表述矛盾
     以 DECISIONS 分开登记两类理由消解，终清单 DECISIONS 落）；全量
     pair 键一次冷 miss（hash 只做缓存键非持久身份——DECISIONS 登记
     该窗口）。
  5. `FilmTailPolicy` 传参缝：FilmRecord.cameraFilter → Parameters.
     cameraFilter（非 nil 才传——nil 恒等）。
  6. UI：Film 面板 SHOOT 新节（D-M92-6）——filter picker 9 档 + 节头
     说明 caption（「拍摄时镜头前置——作用于胶片感光」+ 与 Y/M dichroic
     的区分注记）+ w58 偏差注记行（数据侧 note 透出）；xcstrings 新键
     尾块纯插入（Wratten 编号技术专名 zh=原文 + 色名注记）。
  7. 测试：CameraFilterTests（IOP）——加载/插值正确性（10nm 端点保真）/
     factor 数学（独立复算对拍：手写 Σ 公式 vs 产线 factor）/
     typed 拒绝/双源快照；FilterBakeKeyTests（IOPParity）——**负测组
     主门**：①同 pair 不同滤镜 → tc/print/scan 三槽全 miss（滤镜变
     → 全表变）②同 pair 不同 grade → print/scan miss + **tc HIT**
     （tc_lut 不依赖 grade——分槽正确性）③无 filter 无 grade 档三槽
     键与 M8 基线逐字节恒等 ④fold 对齐后同 stock 同谱恒等 + 谱内容
     变 → miss ⑤**滤色镜零漂移**：cameraFilter nil 档输出与 M8 基线
     逐字节一致（filmRampPlaneHash 既有哨兵族零漂移）⑥filter 档
     18% 灰 |Δ|<0.01（factor 归一）⑦w25/w47 色块方向断言（红滤镜红亮
     天暗蓝暗 / 蓝滤镜反之，阈值 0.05）⑧滤镜因子交叉（我方 Tri-X 谱 ×
     我方透射表算 factor 对 F-4017 p1 表——6/7 ≤0.21 档 + w58 0.67
     档注记核对）。
  8. Project.swift 当批登记（MIN-3，L041/E2）：CameraFilterTests 入
     IOP 数组 + FilterBakeKeyTests 入 IOPParity 数组，BUNDLE-MAP 增行
     同 commit；`tuist generate` = 本任务最后一个动作。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 产线 ⊆ {CameraFilterTable,
    SpectralBuildEngine, FilmPrintBake, FilmMaterialStore, FilmTailPolicy,
    FilmPanelModel, FilmPanelView, xcstrings}。
  - **双 .metal 零 diff 机检**：`git diff FilmSubRunKernels.metal
    SpectralFilmKernels.metal` 零命中。
  - 负测组 ①-⑧ 全绿（缺任一 = 收口门拒绝——CONTEXT 红线 3）。
  - 既有 FilmDeterminismTests 零回归（nil 档逐位恒等主证）。
- **commit**: `feat(m92): add camera filter spectral multiply and bake key folding`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（factor 域选择
  ——窗口终态 sensW；tag 折叠形态）= DECISIONS 申报；**禁把乘法放进
  kernel 或 v50 新 iop**；**禁改 seed 四项序**（bake 槽键独立于 seed，
  两者正确性各归其位）；**禁折 filterTag 进 recordHash 之外再折 seed**
  （seed 已含 recordHash——双折冗余）。

## T4 — granularity 标定：推荐强度层（GrainModule 零 diff）

> OQ-M9-8 站级裁决「仅标定面」的落地：per-film 表 + 量纲桥 + readout；
> grain 算子本体冻结（D-M8-4 空间族挂账不解冻）。

**read_first**：RESEARCH §1.4（ownGrain 语义 + 实测标定方法）+ §2.3
（RMS 溯源）+ §4 M9BW-03 表；CONTEXT D-M92-1/D-M92-2 + 测试策略门 8；
`GrainModule.swift:50-76`（Params 域亲核）；T1 的 grain_calibration.json
骨架 + DECISIONS 四终值。

- **action**：
  1. `GrainCalibration`（新建，LightamerIOP/Sources/Grain/）：表加载
     （stock → published_rms_um + 口径注记 + recommended_strength）+
     推荐映射纯函数（表驱动；未知 stock = nil = 面板不显示推荐行）。
  2. **标定探针**（一次性计算件，测试内承载）：合成中灰面（net
     density 1.0 条件）过 GrainModule kernel → 输出 RMS 估计（48µm
     孔径 = box-filter 模拟 microdensitometer 扫描 → 密度偏差 RMS）→
     扫描 strength 域建曲线 → 反解四卷 recommended_strength 入表。
     探针测试 = LIGHTAMER_PERF_PROBE 门控族（skip-by-default——标定
     是一次性动作，探针法 L014 fence 纪律）；生成值入
     grain_calibration.json（DECISIONS 落曲线与带宽）。
  3. UI：Film 面板 BW stock readout 行（「发表 RMS 17µm · 推荐
     strength N」+ 一键应用——应用 = 一次普通 grain 参数编辑走既有
     commit 语义，零 GrainModule 语义变化）；xcstrings 新键（显式
     静态键，插值走参数化 format）。
  4. 测试：GrainCalibrationTests（IOP）——表 round-trip/映射确定性
     （同输入同输出）/单调（strength↑ → RMS↑ 曲线单调段）/未知 stock
     nil；GrainCalibrationSemanticsTests（IOPParity）——推荐 strength
     下合成灰面 RMS 输出与发表值同带（带宽 DECISIONS 落——口径差异
     ±0.5µm 级容忍 + 简化口径注记）；App readout 测试（FilmPanelBWTests
     扩或新法）。
  5. Project.swift 当批登记（MIN-3，L041/E2）：GrainCalibrationTests 入
     IOP 数组 + GrainCalibrationSemanticsTests 入 IOPParity 数组
     （readout 扩法若新文件则同批入 App 数组），BUNDLE-MAP 增行同
     commit；`tuist generate` = 本任务最后一个动作。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 产线 ⊆ {GrainCalibration, FilmPanelModel,
    FilmPanelView, xcstrings}——**GrainModule.swift 零 diff 机检**。
  - 语义断言绿（推荐值非硬编码——经映射生成断言：表值 = 标定曲线
    反解输出，曲线公开常量）；确定性双跑逐位。
  - process 零 bump 佐证：grain iop 参数面零改（diff 机检）+ 存量
    grain 档渲染零漂移（既有 goldens 零回归）。
- **commit**: `feat(m92): add per-film grain calibration layer`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（RMS 估计口径
  简化 → 带宽放宽）= DECISIONS 申报；**禁动 GrainModule.Params/kernel/
  默认值**；**禁把推荐值写成 GrainModule 静态表**（D-M92-1 落位 = 资产
  目录侧 JSON）；**禁 strength 语义重定义**（D-M92-2）。

## T5 — 收口：定向 + 全套带式对账 + zh-audit + 走查配方

- **action**：
  1. `Project.swift` 九新测试文件全量入对应 bundle 显式数组核对（Layers×1
     = BWProfileAssets；Library×1 = SidecarV12〔V10/V11 同位，MIN-2〕；
     IOP×3 = PaperGradeTable/CameraFilter/GrainCalibration；IOPParity×3
     = BWSpectralGolden/FilterBakeKey/GrainCalibrationSemantics；App×1
     = FilmPanelBW）+ BUNDLE-MAP 增行登记（E2 纪律；**各任务已当批登记
     ——T2/T3/T4 各含登记步骤（MIN-3），本步只做全量核对**）
     + `tuist generate` = 本批最后一个动作（L041）。
  2. 定向全绿：`Scripts/test-direct.sh --bundle Layers` + `--bundle
     Library` + `--bundle IOP` + `--bundle IOPParity` + `--bundle App`；
     ΔN 实数对账（预算 +15..20，越带申报理由）。
  3. 端到端冒烟（IOPParity）：4 BW 卷 × grade{nil,2,5} × filter{nil,
     w25,w47} 组合抽样渲染矩阵（12-24 组——冒烟级非 golden 级）+
     导出递缝冒烟（$jobFilmTail 零改确认——filmTail 跟随文档 record）。
  4. 红线机检族收口：双 .metal 零 diff / 封存面 17 件（M7-6 原始清单
     全集，含 IOP Registry/ModuleInstance——MIN-4；除 sidecar v12）
     零 diff / RenderProcess 零 diff / GrainModule 零 diff /
     LibraryProjectController + McpServerController 零 diff /
     Resources/FilmProfiles CC 包 MANIFEST 对账不破 / UserDefaults
     零新键 grep / `String.LocalizationValue("…\(x)")` 禁形零命中。
  5. `Scripts/zh-audit.py --check` + `--self-test` 双 PASS（新键族 =
     BW 分组/grade/SHOOT 滤镜节/readout——静态键全册 + 动态键显式
     switch 核对）。
  6. 走查配方落库：`.work/gui-acceptance/m9-2/MANIFEST.md`——BW stock
     选择（分节+picker）/ grade 切换（中灰带观感）/ 滤镜切换（SHOOT 节 +
     w25 天空压暗方向）/ granularity readout（BW stock 行 + 一键应用）/
     w58 注记可见性；实机走查归验收批（SC 措辞与 M7-6 先例同款登记）。
  7. SUMMARY（逐任务记账 + ΔN 终账 + 双源取值/fold 终清单/标定带宽
     引用）+ DECISIONS（grade 曝光叠加序终式 / fold 对齐终清单 + 冷 miss
     窗口登记 / granularity 四终值 + 标定带宽 / Wratten 双源分歧表 /
     各偏差）+ GOAL-STATE/TODO 翻账。
  8. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿零回归；Project.swift diff =
  纯数组插入；BUNDLE-MAP 在库；tuist generate 后无生成物入 git；红线
  机检族全零；zh-audit 双 PASS；走查 MANIFEST 在库；SUMMARY/DECISIONS
  在库；全套对账以带式表达式申报（4287 ⊕ ΔN_R6 ⊕ ΔN_M9-1 ⊕ 本批实数
  ——`--all` 归 orchestrator 批准轮）。
- **commit**: `test(m92): register bw spectral suites and close out`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY
  申报理由；禁漏 tuist generate；禁静默吸收 skip 增量。

---

## 风险与回退

- **数据数字化工作量（条目计数，R9/R3）**：4 卷谱曲线（~350-700nm
  对数坐标）+ 特性曲线族（D-76 显影组）+ 锚；相纸三乳剂谱 + 2-3 条
  grade 曲线；透射表 8×81；RMS 4 值；工具脚本 ~1-1.5 天（一次建成）。
  合计 ~4-5 人机协作日（RESEARCH §2.6 表）——**栅格卷（Acros/HP5/
  Multigrade）各 ~1 天为长杆**；矢量卷（Kodak×2）工具化后 ~0.5 天/卷。
  回退：某卷描点质量不达精度门 → 该卷延后（3 卷先上——REQUIREMENTS
  "4+ 卷"下限 4，低于 4 = 停手上报）；相纸 7 档曲线改拟合已内建（R7）。
- **golden 真值自建的风险声明（R8，如实登记）**：本站无上游可对照
  （上游 BW 数据不得复制——GPL 红线 + 自建纪律）——golden 门值 = 自建
  参考数学即正本。缓解：①中性门是**结构性的**（三通道同值数据 +
  1/3 密度的代数必然，不依赖绝对标定——数据错则门红，数据对则门绿，
  判别力保留）②阶调门带（0.55-0.95/1.3×）宽域合理③数字化精度
  0.01-0.02 dex（栅格）对打印观感 = 无 bit 对照对象——**登记即合规**，
  不伪装成 bit 级真值④滤镜因子交叉（6/7 ≤0.21 档）= 唯一有外部
  锚的定量门。若晨审要求上游数值对表（GPL 同许可合法）：需用户翻
  X-M92-4 红线——plan 不预设。
- **bake 键负测必在（R1，主门）**：D-M92-5 三槽折入 + 负测组 ①-⑧ =
  T3 收口门——缺任一 = 收口拒绝（CONTEXT 红线 3）；负测锚 = M8 基线
  键字节（FilmDeterminism 哨兵族）。
- **Wratten 双源缺口（R2）**：mat.uc.pt 页不含 8/11/12/15/21/47/58 →
  karmalimbo + Kodak 官方双源；两源都缺某滤镜 → 砍枚（8→N，UI 跟
  数据走，DECISIONS 登记 + REQUIREMENTS 注记）。
- **tc 槽压力（R6）**：tc LRU 6 × 滤镜变体——滤镜切换首挂构建秒级
  卡顿（交互预算 = 构建一次后缓存命中）；观察项登记（非门）；LRU
  淘汰既有机制零改。
- **T-Max RMS 口径差（R4）**：以我方 PDF 为准修正（T1 首任务）；
  口径注记随表——Kodak 整数/Ilford 一位小数/Fuji 按显影液别。
- **sidecar v12 窗口**：bump 后旧 build 读 v12 档 → tolerant decode
  已在（decodeIfPresent）；回滚窗口中 v12 档在新 build 下正常——
  v12 键缺席语义双向兼容，无 clamp 兜底需求（process 无关）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §4 差距矩阵五行 ↔ T1-T4 逐行；§5 四门
   ↔ T2 门 1/2 + T3 门 3/4 + T1 精度门（滤镜因子交叉归 T3 ⑧）；
   REQUIREMENTS M9BW-01..03 验收形态逐条 ↔ SC。
2. **OQ 兑现核**：D-M92-1..8 ↔ T1（1/3/8）/ T2（4/7）/ T3（5/6）/
   T4（2）；X-M92-1 乘法缝 ↔ T3 插入点 + 两 .metal 零 diff；X-M92-2
   grade ↔ T2 preset + gain 消费层不入键断言。
3. **红线核**：数据自建（T1 grep SpektraLab 数组零命中 + 来源表 ≥7 条）；
   双 .metal 零 diff；封存面 17 件（sidecar v12 显式例外）；process
   零 bump；GrainModule 零 diff；CC 包 MANIFEST 不破；UserDefaults
   零新键；xcstrings 尾块纯插入。
4. **SC 可机检性**：对账全走 sha256/断言/diff 机检（非目测）；负测组
   ①-⑧ 枚举完整；ΔN 对账式非死数；基线带式表达式亲核义务在册。

---

## 评审修复记录（plan v1 → v2，2026-10-27；对应 M9-2-PLAN-REVIEW.md）

- **MAJ-1 paperGrade 编码裁决 → 采 `String?` verbatim**：上游 7 档含
  "00"/"0" 两不同档，Int 歧义（评审 git show origin/main 亲核）。三处
  落点同步：T2 action 2（sidecar v12 持久键 `paperGrade: String?`）/
  T3 action 3（gradeTag 折叠值 = 档 key verbatim）/ T2 action 6（UI
  picker 数据源）；已定裁决节 + CONTEXT D-M92-4 附注（裁决正本）/
  D-M92-5 / X-M92-2 同步。
- **MIN-1 midscale fold 理由修正**：grep 实证 `midscaleNeutralDensity`
  在 SpectralBuildEngine 零消费（仅 FilmProfile decode/projected 自身
  面）——T3 action 4 与 CONTEXT D-M92-5 改两类理由分开：log_sensitivity/
  channel_density/viewing_illuminant = 对齐消费集；midscale = 预折
  （防未来消费扩面），DECISIONS 分开登记。
- **MIN-2 SidecarV12Tests 落域 Layers → Library**：SidecarV10Tests（LIB）
  / SidecarV11Tests（LIB）双连近例（BUNDLE-MAP :733/:739）；M7-4 增行
  记录明文「plan 文『Layers 域』按 V10 同位读解为 LIB 域」——同款漂移
  先例。frontmatter test_bundles/expected_all、ΔN 表、T2 action 7/
  files_modified、T5 action 1/2 六处同步。
- **MIN-3 T2-T4 补 Project.swift 当批登记步骤**：各任务新增末位 action
  （T2 action 8 / T3 action 8 / T4 action 5——数组行 + BUNDLE-MAP 同
  commit + tuist generate 末位，L041/E2）；T5 action 1 改「只做全量
  核对」；files_modified 的 Project.swift 注记同步。
- **MIN-4 封存面计数 15 → 17 件**：M7-6-01-SUMMARY 红线表 #5 原始清单
  = 17 件（含 IOP Registry/ModuleInstance，亲核在案）；AGENTS 速查
  「15 项」为简写口径。frontmatter red_lines / 红线 5 / T5 action 4 /
  Checker 关注点 3 四处改 17 件全集机检 + 口径注。
- **MIN-5 isPristine 双面点名**：T2 action 3 注意事项改「pristine 判定
  两处面同步扩」——Core `isFilmRecordDefault`（synthesized == 自动
  覆盖）+ App `FilmPanelModel.isPristine`（:77-83 手写逐字段，须手扩）。
- **MIN-6 CodingKeys 三重静默提醒**：T2 action 2 显式提醒——FilmRecord
  手写 `init(from:)` + synthesized encode，新字段不进 CodingKeys =
  编译通过 / decode 恒 nil / encode 丢键 / recordHash 不含（一处三
  静默），三面须同批扩。
- **obs 采纳（OBS-1 顺手项）**：T2 action 3 注意事项加 SUMMARY 落账
  登记句——sidecar v12 = 封存面登记（M7-6）以来首例 bump，豁免有据。
- 其余 observations（OBS-2..6）无需 plan 动作：OBS-6（pdfplumber 注入
  形态）按原建议归 T1 执行期 DECISIONS 顺带落。

# M7-6-01 SUMMARY — M7 站收官单 plan 执行摘要（2026-10-17）

> 执行正本 = `M7-6-01-PLAN.md`（HEAD 起点 `beb8937c`）；裁决正本 =
> `M7-6-CONTEXT.md`；偏差申报正本 = `M7-6-01-DECISIONS.md`（§2..§9）。
> 执行链 = `ad003e88..<t6>`（T1..T6 commit-per-task，未 push）。
> C 档第 3 停：本批含站级 `M7-VALIDATION.md`，落盘后呈用户晨审过目。

## Execution Batch Results

| 任务 | commit | 面（细节正本 = DECISIONS 对应节） |
|---|---|---|
| T1 三缺陷 | `ad003e88` | major-1 宿主透传参案（三宿主 + embedded 第七缝 + GUI plain-await 闭包；生产调用恰 3 点）+ minor-1 裸臂两行 + obs-3 快照+条件复检三行 + 5 测试腿（McpHostTests 1 / McpSearchStateToolsetTests 1 / AgentControlCoordinatorTests 3） |
| T2 UQ-A1 | `32b592aa` | drtLayerColorSpace SDR 两段式（legal 8 对 → 导出同款 ICC v4 / 域外回落）+ EditorPreviewColorSpaceTests 3 法（legal 恒等 8 对 / srgbPiecewise 真分段行为 / 域外回落）+ KD-8 偏离消解 |
| T3 UQ-L1 | `bac0ff76` | LightamerSlider readout scrub（DragGesture ≥3pt + LightamerSliderScrubSession 纯函数 + onModifierKeysChanged Shift 通道 + onGeometryChange 行宽）+ D-H1 三回调复用 + LightamerSliderScrubTests 3 法 + xcstrings 恰 +1 键 |
| T4 SKILLS-01 | `4259cfd8` | skills/lightamer-mcp/（SKILL.md 七节 en + errors.md 19 码 + tools.md 机检 378 行）+ SkillsReferenceTests 两门 + makeUnionRegistry internal 恰一行 + README 一句链接 + N2-2 文档句收口 |
| T5 对账批 | 本 commit | 全套 `--all` 对账 + 红线族 11 项亲跑 + zh-audit 双 PASS + MANIFEST（`.work/gui-acceptance/m7-6/MANIFEST.md`）+ SUMMARY/DECISIONS |
| T6 站级收口 | `docs(m7-6)` | `M7-VALIDATION.md`（站级，含 M7-5 §signed 节）+ ROADMAP/REQUIREMENTS/TODO/GOAL-STATE/AGENTS.md 翻账 |

## 测试记账表（ΔN 对账）

| bundle | M7-5 终态 | 本波终态 | Δ | peakRSS（8G 门内） |
|---|---|---|---|---|
| App | 904/4/0 | 917/4/0 | +13 | 2832MB |
| IOP | 687/5/0 | 687/5/0 | 0 | 7649MB（贴线，SPIKE ±3% 方差注记在案） |
| IOPParity | 460/3/0 | 460/3/0 | 0 | 6399MB |
| Layers | 494/5/0 | 494/5/0 | 0 | 816MB |
| Library | 736/4/0 | 736/4/0 | 0 | 623MB |
| Sessions | 284/9/0 | 284/9/0 | 0 | 1224MB |
| Export | 385/5/0 | 385/5/0 | 0 | 4974MB |
| **TOTAL** | **3950/35/0** | **3963/35/0** | **+13** | 全套 2054s exit 0，零 MEMFAIL |

- ΔN 逐任务记账：T1 +5（带 4..6 内；腿②与既有无头恒放行负测同语义 =
  合并让渡申报）+ T2 +3（plan 点估 2——srgbPiecewise 行为腿独立成法，
  带内吸收）+ T3 +3（带 2..4 内）+ T4 +2（带 1..2 内）= **+13**
  （预期点 +13 精确命中，带 3959..3964 内；3950 + 13 = 3963 对账精确）。
- skip 35 构成声明：24 基线 + 11 RAW 供件缺失——第三种来源零（七 bundle
  skip 数与 M7-5 终态逐值一致，零漂移）。

## 红线族 11 项亲跑记录（ beb8937c..HEAD 全波 diff 面）

| # | 项 | 判据 | 结果 |
|---|---|---|---|
| 1 | 零新 SPM | Project.swift dependencies 块零 diff | PASS（仅测试登记 +3 行） |
| 2 | `.metal` 全域零 diff | `git diff --name-only -- "*.metal"` | PASS（空） |
| 3 | McpToolRegistry 面 | 错误码 19 档零触 + writeCallCount 零触 + McpTimeouts 零触 | PASS（文件零 diff；setControlAdmit 装配四点 = DECISIONS §1/§2① 显式申报点） |
| 4 | FIX2③ controller 面 | LibraryProjectController.swift 零 diff 第五波 | PASS（不在 diff 清单） |
| 5 | 封存面 17 件 | DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels.metal/DrtEotf/ExportQueueContract/六格式矩阵/NodeGraphCommand/sidecar schema/HistoryStack/HistoryHash/PipelineDocument/V50Order/GradeCatalog/IOP Registry/ModuleInstance | PASS（零命中；EditorMTKView = T2 受限修改面申报面） |
| 6 | xcstrings 尾块纯插入 | diff = +10/-0 尾块形 | PASS（slider_scrub_hint 一键；历史键零触碰） |
| 7 | UserDefaults 零新键 | diff 无 set/register 新键 | PASS |
| 8 | runModal 禁形 | `grep -rn "\.runModal(" App/Sources` | PASS（零命中） |
| 9 | 插值禁形 | `String.LocalizationValue("...\(...)` 代码形 | PASS（唯一命中 = 既有注释行，非本波 diff） |
| 10 | Project.swift 恰三行 + BUNDLE-MAP 恰三行 + tuist generate 恒末位（L041） | diff 面核 + commit 序列 | PASS（三新测试文件各一批：generate → build → test → commit） |
| 11 | union 32 + 五钉 23 零触 | McpFinalSnapshotTests diff 恰一行 + App 域 union 断言全绿 | PASS（internal 一行 = 持权行使申报点） |

## 其它对账

- zh-audit：`--check` PASS（source keys 1708→1709 恰 +1 / 1957 catalog
  keys / 38 interp keys）+ `--self-test` PASS。
- en 单语机检：`grep -rn "[一-鿿]" skills/` 零命中（exit 1）。
- 走查配方 = `.work/gui-acceptance/m7-6/MANIFEST.md`（UQ-L1 六行 +
  UQ-A1 两行 + major-1 e2e 三行；实机走查归验收批/用户——UQ-L1 验收
  形态 = ROADMAP「交互走查 ✓」以配方就绪 + 机检腿承载，SC 措辞降格
  登记 = T6 VALIDATION §制度偏离③）。

## 偏差清单（正本 = DECISIONS；此处索引）

1. T1 腿②合并让渡（无头恒放行 = 既有负测同语义）；minor-1 测试腿
   等价终形（产线拼写构造 + 源级接线扫描——plan 直调判据与修法结构性
   不一致）。
2. obs-3 复检落点 = `if !alreadyHeldBySelf` 块内（等价性证明在案）；
   测试交错 = PollTriggerBox 串行触发轮（零真 poll 等）。
3. T2 等值腿收敛 = 同实例 + 字节同；srgbPiecewise 行为判别腿（CGColor
   converted 真变换）3 法（点估 2，带内吸收）；KD-8 偏离消解收口。
4. T3 Shift 通道换锚 = onModifierKeysChanged（本 SDK DragGesture.Value
   无 modifiers 成员——编译不可达）；trackWidth = 整行宽；拖离取消让渡
   （MANIFEST A3）。
5. T4 tools.md description 列省略（zh 活文案 vs en 单语门的结构冲突
   裁定——晨审可翻）；生成通道 = 临时脚手架（提交前移除）；零 taste/
   零 Alcedo 自检申报。
6. 制度偏离两件（omp→双 zcode / m7-5 无独立 VALIDATION 载体）→
   T6 VALIDATION §制度偏离登记（非本批新增）。

## Leftovers

- 无新增挂账。承接面翻账归 T6：N2-2 收口 / S-2 维持 / obs-A C12 注记
  一行 / FIX2③ 第五波维持 / union 改动权用讫归还 M8。
- UQ-L1 实机走查（MANIFEST 六行）归验收批/用户。

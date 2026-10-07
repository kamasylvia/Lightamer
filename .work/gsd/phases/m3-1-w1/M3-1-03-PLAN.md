---
phase: m3-1
plan: "M3-1-03"
title: "小件族合并批（wave 3，OQ-7①四任务一 plan 多 commit）——①冲突档选择器 UI 暴露（Export M2 页三档 Picker + enqueueExportM2 消费选择值，引擎零改动，M2-9-VALIDATION 挂账#4 关闭）②peak-ICC 标注说明面（DRT readout HDR 档补行，DrtOutputColorSpace 签名零触碰）③denoise 拖动降档预览语义（OQ-6①自动：拖动态临时旁路 + 状态条 + 松手全质量恰一 commit；NLMeansModule/PixelPipe 零触碰）④V14+V15 zh 清算（标记菜单动态键位显式化 + zh-audit 提取器硬化 + 存量 sweep）+ phase 收口（全套 --all 报备终轮 + AGENTS 增量节）"
wave: 3
depends_on: ["M3-1-02"]
autonomous: true
requirements: []   # 挂账清偿批——无新增 REQUIREMENTS 条目（M2-9-VALIDATION #4 / V14 FINDING-G / V15 / perf.md OQ-7-A V2 语义移交）
estimated_tests: "+5..8"
test_bundles: [App, Export]
files_modified:
  - App/Sources/Lightamer/Export/ExportInspectorView.swift   # 修改：ExportM2PanelModel += collisionPolicy + namingSection 三档 Picker + run face（:282 一带）传选择值
  - App/Sources/Lightamer/Export/ExportPanelView.swift       # 修改（如说明行/readout 有 legacy 面触点——预期零 diff，执行期核；触则本行转正）
  - App/Sources/Lightamer/UI/Inspector/NLMeansPanelView.swift # 修改：LightamerSlider trio onDragBegin/onDragEnd 挂旁路（:32/:41/:54/:63 一带）
  - App/Sources/Lightamer/State/EditorState.swift            # 修改：拖动态 nlmeans 预览旁路标志（live 投影面，零 history）+ 状态条提示位
  - App/Sources/Lightamer/UI/LightamerApp.swift              # 修改：标记菜单两处动态键位（:1490/:1518）改显式 switch 静态键（V14/FINDING-G）
  - Scripts/zh-audit.py                                      # 修改：提取器硬化（continuation 漏提面，V15）
  - Resources/Localizable.xcstrings                          # 修改：新键块 append 尾部（collision 档名 + 降档提示 + 分割线 label 若 02 未清尾）
  - Tests/LightamerTests/ExportCollisionPickerTests.swift    # 新建（App）：model 默认 increment + Picker 写面 + run 传值装配
  - Tests/LightamerTests/NLMeansDragDowngradeTests.swift     # 新建（App）：拖动态旁路不进 params/history + 松手恰一 commit + FULL 桶零变化
  - Tests/LightamerTests/ZhAuditExtractorTests.swift         # 新建（App 或脚本自测面——形态执行期定，见 T4）：硬化负测（continuation 样例可提）
  - Project.swift                                            # 修改：新测试文件登记（L041 generate 批尾）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：增行登记（E2）
  - .work/gsd/phases/m3-1-w1/M3-1-03-SUMMARY.md              # 新建（收口任务，含 phase 小结节）
  - .work/gsd/phases/m3-1-w1/M3-1-03-DECISIONS.md            # 新建（收口任务）
  - .work/TODO.md                                            # 修改：M3-1 条目清账（T5）
  - .work/GOAL-STATE.md                                      # 修改：续接点追加 + phase 终态（T5）
  - .work/LESSONS.md                                         # 如踩坑
  - .work/gui-acceptance/m3-1/                               # 修改：走查证据追加（冲突档 / 降档 / zh 菜单）
---

# Plan M3-1-03 — 小件族合并批 + phase 收口

> **性质**：OQ-7① 裁决 = 四任务面合并 1 plan 多任务串行（Export 页 Picker / Export 页
> 文案 / App 交互层 / 本地化面——零文件交集或同页可同批触碰），一 plan 一验收。**引擎
> 零改动 plan**：`ExportNamer.swift` / `NLMeansModule.swift` / `PixelPipe.swift` /
> `DrtOutputColorSpace.swift` 全部零 diff（红线机检）。本 plan 兼 M3-1 收口（最后
> wave）：全套 `--all` 终轮（**报备制：orchestrator 批准 + 运行中监视 + MEMFAIL 8G
> 机检兜底**——AGENTS 资源监控节）。

## 已定裁决（生效值，硬约束，不得重开）

- **OQ-7①**：小件族合并 1 plan 多任务串行（本 plan 结构即裁决兑现）。
- **OQ-6①**：denoise 拖动降档 = **自动**——拖动中该图 nlmeans 实例临时降档（旁路参数
  不进 params 不进 history）+ 状态条提示「预览降档」+ 松手恢复全质量恰一 commit。
  手动开关（②）与不做（③）不采。
- **冲突档**：引擎零改动纯 UI 暴露——`ExportCollisionPolicy` 三档已交付钉死
  （`ExportNamer.swift:21`），本批只暴露 Picker + 消费选择值；legacy sheet 零触碰；
  既有钉死测试（`testDefaultOverloadEqualsIncrementTier` 族）零改全绿。
- **peak-ICC**：说明面 only——`DrtOutputColorSpace` **签名零触碰**（`M2-9-02-DECISIONS.md:41-45`
  边界正本：peak 有意不进 ICC；渲染消费在 EotfBox record、入队校验在 `ExportVariant.validate`
  peak 闸门；真容器 = UltraHDR ALCE-02 M4）。
- **V14/V15 zh 清算**：修复形态**禁** `String.LocalizationValue("prefix_\(x)")` 新写法
  （F-2 插值键陷阱同族）；M2-7 动态族 52 键式「静态 MISSING + 动态族双清单并集对账」
  方法论沿用。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 冲突档选择器（T1）

- `ExportM2PanelModel`（`ExportInspectorView.swift:584-`）+= 
  `var collisionPolicy: ExportNamer.ExportCollisionPolicy = .increment`（会话态，与
  pattern/metadataOn 同层；**不入 UserDefaults**——M2-9 记忆键族六键外零新增，DECISIONS
  注记「档位会话态」裁定与 Alcedo 对表）。
- `namingSection`（:216-229）= ExportNamingEditor 下方加三档 Picker（Increment 默认 /
  Fail / Replace——键族 `export_collision_increment/fail/replace`，档名技术专名 zh = 
  英文原文 + zh 说明尾注）。
- run face（:282 `enqueueExportM2` 调用）补传 `collisionPolicy: model.collisionPolicy`
  ——`ExportState.enqueueExportM2` 形参（:472 默认 `.increment`）已就位，**App 层透传
  即接入**，队列行为由既有 EXPORT bundle 引擎断言消费面覆盖（零新引擎测试）。
- **挂账#4 关闭判据**：Picker 在场 + 选择值达队列 + 三档行为走查——落 SUMMARY 声明
  （M2-9-VALIDATION 历史行不改写）。

### KD-2 peak-ICC 说明行（T2）

- `drtReadout`（:339-354）在 `record.encodingEotf ∈ {st2084, hlg}` 档追加一行 caption：
  当前 peak nits + 「ICC 嵌入仅含色彩空间与传递函数，峰值亮度不进 ICC；真 HDR 容器
  UltraHDR 规划中」（键 `export_drt_peak_note` 一枚，文案 zh/en 同批；判定 =
  `isHdrEncoding` 既有单源，Core `DrtRecord.isHdrEncoding` 复用禁重写）。
- SDR 档 readout 零变化；`DrtOutputColorSpace` / `ExportICCStrip` 零 diff。

### KD-3 denoise 拖动降档（T3，App 层旁路）

- **机制**：拖动态旁路 = EditorState live 投影面对**被拖 nlmeans 实例**临时置
  `enabled = false`（live 态，零 history——D-H1 trio 的 beginContinuousEdit 窗口内），
  PREVIEW 活渲染即跳过该实例；松手（commitContinuousEdit）恢复 enabled + 落既有的那
  **一次 commit**（LightamerSlider 三件套既有语义，`NLMeansPanelView.swift:14-15` 在案
  「exactly ONE history commit per drag」——本批零新增 commit 面）。
- **落点**：`NLMeansPanelView` 各滑杆 `onDragBegin/onDragEnd` 挂旁路标志（EditorState
  新 face：`setPreviewDenoiseBypass(_ opName: String?, on:)` 一类——**执行期以
  EditorState live 投影实位为准亲核**，read_first 3/4）；状态条提示走既有 toast/status
  通道（「预览降档」提示，拖动窗口内显示）。
- **红线**：`NLMeansModule.swift` / `PixelPipe.swift` 零 diff（旁路 = App 层实例投影，
  非 pipe 桶逻辑、非 kernel、非参数面——CONTEXT D-8 隔离注记）；FULL/THUMBNAIL 桶
  零变化（旁路窗口 = 拖动态，拖动结束即恢复；若拖动窗口内发生 FULL 重渲的并发窗口
  风险 → DECISIONS 登记，M4 coordinator 串行化余量承接）。
- **降档维度裁定**：跳过（enabled=false）而非减趟——decimate 减趟引擎档已证不达
  16.6ms（`perf.md:43-64`），跳过 = 拖动流畅优先的最大档，松手即全质量（OQ-6①
  「拖动态降档（跳过/减趟……plan 期按实测观感定」的兑现裁定，DECISIONS 留观感走查
  复核位）。

### KD-4 zh 清算（T4）

- **V14/FINDING-G**：`LightamerApp.swift:1490/:1518` 两处
  `String.LocalizationValue("metadata_rating_\(stars)")` / `"metadata_color_\(label)"`
  动态键位改**显式 switch 返回静态键**（11 键 `metadata_rating_1..5` /
  `metadata_color_0..5` **已在册且含 zh 值**——planner 2026-10-08 亲核 xcstrings；
  本步 = 形状硬化使 zh-audit 提取器可见可审，非补键）。
- **V15 提取器硬化**：`Scripts/zh-audit.py` continuation 漏提面（:15 已列 form 1b——
  执行期实跑 `--check` 对当前源码全集取 MISSING 输出，对漏提形态逐个补提取规则；
  硬化后新增负测样例锁定）。
- **存量 sweep**：M2-6-3 F1（ProjectWorkspaceFace 4 处 zh 缺口，GOAL-STATE 挂账）+ 
  全仓 `zh-audit --check` 输出清单双对账（静态 MISSING + 动态族并集——01/02 新键块
  并入本轮终核）；补 zh 值 = 键块 append/修订同批。
- **验收门**：`Scripts/zh-audit.py --check` PASS + 标记菜单实机 zh 呈现走查（11 键 +
  clear 两键）。

### KD-5 phase 收口（T5）

- 全套 `--all` 终轮（报备制）→ 终值判定式 = **2962（基线：2961 + `08dd061` +1）+
  三 plan 登记增量**，逐 plan 增量对账链入 SUMMARY phase 小结节（对账以
  BUNDLE-MAP 登记值为准，禁凑数）。
- AGENTS.md「M3-1 架构增量」节（三 plan 约定正本：编码目录/烘焙缝/记忆三层序/sheet
  sizing/旁路面/zh 硬化）+ GOAL-STATE phase 终态 + TODO 清账 + LESSONS。
- M3-1 验收锚（CONTEXT §七）逐条状态表落 SUMMARY（golden / 拖拽 / 挂账#4 / peak-ICC /
  降档 / zh / 全套绿）。

## read_first

1. `.work/gsd/phases/m3-1-w1/M3-1-CONTEXT.md` §四 + 裁决记录 OQ-6/OQ-7 行 + §七验收锚。
2. `.work/gsd/phases/m3-1-w1/RESEARCH-NOTES.md` §二.5/§三.4/§三.5/§三.6——冲突档锚
  （`ExportNamer.swift:21` / M2-9-VALIDATION :59/:124）、denoise 在案事实
  （`perf.md:43-64`）、zh 输入清单。
3. `App/Sources/Lightamer/Export/ExportInspectorView.swift`——model（:584-）/ 命名节
  （:216-229）/ run face（:260-298）/ drtReadout（:339-354）。
4. `App/Sources/Lightamer/UI/Inspector/NLMeansPanelView.swift` + 
  `App/Sources/Lightamer/UI/Inspector/LightamerSlider.swift`——D-H1 trio
  （begin/live-ticks/end）挂点 + `App/Sources/Lightamer/State/EditorState.swift`
  （live 投影 / commitContinuousEdit 实位亲核）。
5. `App/Sources/Lightamer/UI/LightamerApp.swift` :1480-1525——两处动态键位现场。
6. `Scripts/zh-audit.py` 头注 + 三断言口径 + `Resources/Localizable.xcstrings`（zh
  locale、append 尾部纪律——01/02 两批新键为既有前缀）。
7. `.work/gsd/phases/m2-9-export/M2-9-02-DECISIONS.md:41-45`（peak-ICC 边界正本）+
  `.work/gsd/phases/m2-11-performance/perf.md:43-64`（降档在案数字）。

## 纪律（强制）

1. **引擎零改动红线**（`git diff --name-only` 机检零命中）：`ExportNamer.swift` /
   `NLMeansModule.swift` / `PixelPipe.swift` / `DrtOutputColorSpace.swift` /
   `ExportState.swift`（enqueue 形参已就位零改）/ `DrtEotf.swift` / 六格式矩阵编码器 /
   `WebPEncoder` / `PipeCacheKey` / `V50Order` / `ModuleRegistry`。
2. **历史行只追加**：M2-9-VALIDATION 挂账#4 关闭 = SUMMARY 声明，禁改写 M2 phase 历史文档；
   xcstrings 既有键块零触碰（append/新键块尾部）。
3. **测试登记**：新文件同 commit 登记 Project.swift + BUNDLE-MAP（E2）；generate 恒
   批尾（**L041**）；`ZhAuditExtractorTests` 形态若走脚本自测（`test-direct-selftest.sh`
   同款）则零 XCTest 登记——执行期二选一并 DECISIONS 注记。
4. **GUI 走查**：§3.2 截图纪律；证据追加 `.work/gui-acceptance/m3-1/`；GUI 不可达 =
   Manual-Only 登记不阻塞翻账。
5. **全套 `--all` 报备制**：orchestrator 批准后跑，运行中监视 Lightamer 进程资源
   （AGENTS 监控口径），MEMFAIL/压力转红立即 kill——脚本机检兜底在位
   （`RSS_LIMIT_MB=8192`）。
6. **checker 四条**：①真链（走查亲测 + 旁路真链断言）；②登记闭环（E2）；③语义断言
   （三档队列行为复用既有 EXPORT 断言 + 旁路单测可观测）；④边界核对（T5
   `git diff --stat` 对表 + 红线零命中）。

## Tasks

### T1 冲突档选择器（KD-1）

- **action**：model 字段 + namingSection Picker + run face 透传 + zh 键三枚；
  `ExportCollisionPickerTests`（model 默认 `.increment` / Picker 写面 / run 装配传值）。
- **验收标准**
  - [ ] App 定向轮绿；既有 EXPORT bundle 引擎断言零改全绿
        （`testDefaultOverloadEqualsIncrementTier` 族在册）；`ExportNamer.swift` 零 diff。

### T2 peak-ICC 说明行（KD-2）

- **action**：drtReadout HDR 档追加说明行（`isHdrEncoding` 单源判定）+ 键一枚。
- **验收标准**
  - [ ] 走查：HDR 档（EOTF st2084/hlg）行在场含当前 peak 值，SDR 档零变化；
        `DrtOutputColorSpace.swift` 零 diff；键入 zh 账（`--check` 清单并集）。

### T3 denoise 拖动降档（KD-3）

- **action**：EditorState 旁路 face + NLMeansPanelView 三件套挂点 + 状态条提示 +
  `NLMeansDragDowngradeTests`（拖动态旁路 = live 态不进 params/history；history count
  拖动窗口零变；松手恰一 commit 且 enabled 恢复；FULL 桶判定零受扰）。
- **验收标准**
  - [ ] App 定向轮绿；`NLMeansModule.swift`/`PixelPipe.swift` 零 diff；实机拖动观感
        走查（拖动流畅 + 松手全质量恢复 + 提示面）落证据。

### T4 zh 清算（KD-4）

- **action**：两处动态键位 switch 化 + zh-audit 硬化 + F1 四处 sweep + 全仓 `--check`
  清单并集对账（含 01/02 新键）。
- **验收标准**
  - [ ] `Scripts/zh-audit.py --check` PASS；硬化负测在案（continuation/动态键样例
        提取命中）；标记菜单实机 zh 走查（13 键面）。

### T5 收口 + phase 终态（KD-5）

- **action**：全套 `--all` 报备终轮；SUMMARY（phase 小结节 + 测试增量对账链 + CONTEXT
  §七验收锚逐条状态表 + 挂账#4 关闭声明）/ DECISIONS / AGENTS 增量节 / GOAL-STATE /
  TODO 清账；`git diff --stat` 对表。
- **验收标准**
  - [ ] 终轮绿（MEMFAIL 机检在册）；终值 = 2962 + 登记增量（三方对表）；红线域
        `git diff --name-only` 全程零命中。

## 验收标准（AC 总表）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 三档 Picker 在场（Increment 默认）且选择值达队列；引擎/`ExportState` 形参零 diff；既有引擎钉死测试零改全绿 | T1 测试 + diff 核 + EXPORT 定向 |
| 2 | peak-ICC 说明行 HDR 档在场（peak 值 + ICC 语义 + UltraHDR 注记）、SDR 零变化、`DrtOutputColorSpace` 签名零触碰 | T2 走查 + diff 核 |
| 3 | 拖动态 nlmeans 旁路：零 params/零 history/零 pipe-module 触碰；松手恰一 commit 恢复全质量；FULL 桶零变化；状态条提示在场 | T3 测试 + 走查 |
| 4 | V14：两处动态键位显式化（静态键 11 枚已在册含 zh）；V15：提取器硬化负测在案；F1 四处清账 | T4 测试 + `--check` PASS |
| 5 | `zh-audit --check` PASS（三 plan 键块并集终核）+ 标记菜单实机 zh | T4 + 走查 |
| 6 | 全套 `--all` 终轮绿（报备 + MEMFAIL 机检）；终值对账 = 2962 + 登记增量；CONTEXT §七七条锚逐条状态落 SUMMARY | T5 终轮日志 + SUMMARY |
| 7 | 登记闭环（E2/L041）；引擎红线域 `git diff --name-only` 零命中 | 三方对表 |

## 风险与边界

- **旁路并发窗口**：拖动中 FULL 重渲会短暂缺 denoise——拖动窗口极短 + commit 恢复，
  接受并在 DECISIONS 登记；根治（coordinator 串行化）= M4 余量（ToneEqual 修复批同款
  归位，不本批扩）。
- **collision 档位不持久化**：会话态裁定（KD-1）——若走查后用户要跨会话记忆，属新
  挂账非本批（UserDefaults 键登记纪律外零新增）。
- **提取器硬化的回归风险**：zh-audit 是流程工具非产线——硬化负测锁形态，`--check`
  全绿为门；不为此改 xcstrings 既有键块。
- **`ExportPanelView.swift` 触点**：预期零 diff（说明行/readout 全在
  `ExportInspectorView`）；若执行期确需触碰（legacy 面文案同步），按申报行转正并在
  DECISIONS 注记，禁静默扩面。

## 提交约定

- T1 `feat(app): export m2 collision policy picker`
- T2 `feat(app): hdr drt readout peak-icc note line`
- T3 `feat(app): nlmeans drag-time preview bypass with single commit restore`
- T4 `fix(app): explicit rating/color menu keys and zh-audit extractor hardening`
- T5 `docs(m3-1): close out small-item batch and phase ledger`
- 全英文 Conventional Commits；不 push。

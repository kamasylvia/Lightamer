# M2-1 二次验收报告（omp 回溯）— dt 面 feature-flag 禁用

- 验收方：omp 独立二次验收，2026-10-09。零共享上下文：正本四件 + 执行 diff 全部亲读，定向测试亲跑，不采信首验计数。
- 首验正本：`.work/gsd/phases/m2-1-dt-disable/M2-1-ACCEPTANCE.md`（判据 = 10 条 AC）。
- **执行 commits 标识漂移（见分歧点 §1）**：任务书所列 `f5bcfa2/561ca59/f2a3618/902d942` 在当前仓库均 `unknown revision`；按 message + diff 内容亲证定位到同一批逻辑提交 `d734067`（T1）/`9b71843`（T2）/`7babcb0`（T3）/`d3f5744`（T4），下文机检均以此为准。

**结论头：`PASS / 0 error + 1 minor`**

## 抽查点 1：禁用集常量 + gatedRegister 与矩阵对应

- `LightamerIOP/Sources/Registry.swift:39-50`：`defaultFaceDisabledOpNames` 恰 6 项，全部由模块 `opName` 常量构建（`FilmicRGBModule`/`SigmoidModule`/`AgXModule`/`DenoiseProfileModule`/`NLMeansModule`/`BilateralModule`），集合字面量内零字符串字面量；D1/D2 分组注释各标矩阵行号。
- 6 常量字面亲证（`git grep`）：`FilmicRGBModule.swift:197 "filmicrgb"`、`SigmoidModule.swift:382 "sigmoid"`、`AgXModule.swift:178 "agx"`、`DenoiseProfileModule.swift:197 "denoiseprofile"`、`NLMeansModule.swift:80 "nlmeans"`、`BilateralModule.swift:77 "bilateral"`——与 `M2-1-MATRIX.md:17-22` 禁用表逐字一致。
- `gatedRegister` 定义 `Registry.swift:97-106`（`if defaultFace, contains → return`），调用点恰 6 处：`:184` sigmoid（row 2）、`:205` filmicrgb（row 1）、`:214` agx（row 3）、`:327` nlmeans（row 5）、`:341` denoiseprofile（row 4）、`:353` bilateral（row 6）——每处 `matrixVerdict` 注释矩阵行号，与矩阵 6 行一一对应（代码顺序 row 2/1/3/5/4/6，集合相等）。
- 反向机检：`grep "registry.register(opName: (Sigmoid|FilmicRGB|AgX|NLMeans|DenoiseProfile|Bilateral)Module"` 零命中——直接注册面无禁用 6 混入。当前直接注册 45 处 vs M2-1 时 34 处，差量为 M2-5/M3-3 等后加模块（gated 恒 6），非 M2-1 范围。

## 抽查点 2：默认面三面收窄 + env 口双向钉

- 种子面：`Registry.swift:759-760` `if defaultFace { seed.removeAll { … } }` 在 `:762-764` `sorted` 之前——过滤在 sort 前成立。
- 面板面：`App/Sources/Lightamer/State/InspectorState.swift:106-115` `registerDefaultProviders(defaultFace:)` 经 `gated()` 对注册表禁用常量取交集；gated 恰 6 panel（`:123` Sigmoid、`:128` FilmicRGB、`:129` AgX、`:162` NLMeans、`:164` DenoiseProfile、`:166` Bilateral）。T2 diff 亲证 6 处 `register(`→`gated(` 改行。
- 生产组装点：`LightamerApp.swift:982-986` 一处读 `!isFullFaceRequested` 后分发 populate/attach，`:1015` panels，`seedInstances()`（`:2044-2048`）同开关；`PipeCoordinator.swift:968-970` `attach(registry:defaultFace:)` 注入式（D-EXEC-1），消费点 `:1182`、`:1376`。`git grep "editingDefaultInstances()" App/Sources` 零命中，无裸调用残留。
- MCP 面：`McpServerController.swift:231-240` 同源 face（同一 `let defaultFace` 同时 populate registry 与 stamp `seams.defaultFace`）；`EditingToolset.swift:86/116/123` `Seams.defaultFace` 载体、`editingSeed`（`:600-605`）/`defaultRecord` 经 `projectInstances`（`:619-622`）透传、`list_iops` 调用点 `:151` 传 `seams.defaultFace`；`IopCatalog.swift:292-303` `defaultFaceOps()` 对注册表常量过滤 + `catalogJSON(defaultFace:)` 选源（`ops` 数据不动）。
- env 口：`Registry.swift:57-59` `isFullFaceRequested` 一行实现，键名 `LIGHTAMER_FULL_IOP_FACE`（注：任务书抽查点措辞写 `LIGHTAMER_LEGACY`，实为 `LIGHTAMER_FULL_IOP_FACE`；`LIGHTAMER_LEGACY_LIBRARY` 是 M2-2 另一口——任务书笔误，不影响验收对象，按实际口验收）。
- 正反双向钉（`Tests/LightamerTests/DefaultFaceTests.swift`）：populate 面 bare call + explicit false（`:107-123`）；seed KD-2 镜像（`:140-142`）；panel bare 反向 + `full−narrow==6`（`:343-353`）；catalog full-face 反向 18 + `test seams default false`（`:392-398`）。共 8 测试方法（`:76/:88/:107/:130/:163/:290/:331/:364`）。

## 抽查点 3：定向测试 DefaultFaceTests

- 归属：`M2-4-0-BUNDLE-MAP.txt:131` → `IOP 8 DefaultFaceTests.swift`，bundle 名 `IOP`。
- 命令：`caffeinate -dis Scripts/test-direct.sh --bundle IOP 'DefaultFaceTests'`（build-for-testing 产物已存在，直接用；禁跑全套）。
- 结果：`BUNDLE|IOP|8/0/0|peakRSS=195MB|0s|sampling=time` + `TOTAL|8/0/0|0s` + `OK`——**Executed 8 / failed 0**，与首验申报（8 例 0 fail）逐值一致。
- 时效性：`git log d3f5744..HEAD -- Tests/LightamerTests/DefaultFaceTests.swift` 为空——该文件自 M2-1 收口后零改动，本轮跑的即 M2-1 态测试。

## 抽查点 4：git 机检（commits stat + 红线 + 逐字一致）

- 四 commits `--stat` 与首验 §AC10 申报对照（以定位到的实际 SHA）：
  - `d734067`（T1）：`Registry.swift` + `DefaultFaceTests.swift`（新建）——2 文件 ✓
  - `9b71843`（T2）：`InspectorState.swift` + `PipeCoordinator.swift` + `LightamerApp.swift` + `DefaultFaceTests.swift`——4 文件 ✓
  - `7babcb0`（T3）：`McpServerController.swift` + `EditingToolset.swift` + `IopCatalog.swift` + `DefaultFaceTests.swift` + `McpHostTests.swift`（D-EXEC-3 申报偏差，diff 亲证仅 `import LightamerIOP` + 期望元组同源 face）——5 文件 ✓
  - `d3f5744`（T4）：`GOAL-STATE.md` + `LESSONS.md` + `TODO.md` + `M2-1-DECISIONS.md` + `M2-1-MATRIX.md` + `M2-1-SUMMARY.md`——文档 6 件 ✓
- 红线：`git diff --stat 1c34dde..d3f5744 -- LightamerCore/` 输出为空 → **`LightamerCore/` 零改动** ✓。注：range 内夹 5 个中间 `docs(m2)` commits（`dd9745a/d46260b/068d4a5/908d6b3/97c8c1f`），仅碰 `REQUIREMENTS.md`/`ROADMAP.md`/`ALCEDO-FEATURE-MAP.md` 三个 md，不碰代码；M2-1 四 commits 各自 stat 已逐个核对无越界。
- 禁用 6 op 逐字一致：Registry 常量 6 值（抽查点 1 亲证）== 矩阵字面集（`M2-1-MATRIX.md:17-22`）== 测试 `matrixDisabledNames`（`DefaultFaceTests.swift:42-45`，唯一合法字面量处），且 `testDisabledSetMatchesMatrixExactly` 机检绿。

## 与首验分歧点

| # | 级别 | 内容 |
|---|---|---|
| 1 | minor | **执行 commits SHA 与首验记录不符**：首验（及任务书）记 `f5bcfa2/561ca59/f2a3618/902d942`，当前仓库均不存在；实际为 `d734067/9b71843/7babcb0/d3f5744`（message 与 PLAN 提交约定逐字对应，diff 内容亲读确认即 M2-1 执行批；首验时 commits 未 push，后续历史改写致 SHA 漂移）。属标识漂移，代码态/测试态可追溯验证，不影响任何 AC 结论。另 T4 commit body 内自引 `f2a3618`（MATRIX 签注「代码态 f2a3618」）为旧 SHA 残留，同理。 |
| — | note | 首验 minor（`M2-1-MATRIX.md:24` 表标题计数「12+trio」「独有 7+native 2」与实际行数不符）经亲读确认属实；矩阵为已签核正本，本轮不改原文，维持首验处置（留后触时顺手修）。 |

实质分歧（测试红、代码与矩阵不符、文件集越界）：无。

## 会话卫生

- 只读验收：未修改任何源码与既有文档；唯一写入 = 本报告文件。未 push。
- 测试纪律：仅跑定向 `DefaultFaceTests` 1 类（IOP bundle）；未跑全套 `--all`。卫生注记：探查 `test-direct.sh --help` 时该脚本无 `--help` 分支，误触发全量 IOP bundle 一轮（后台任务，300s 超时被杀，仅产出一行 `BUNDLE|IOP|483/1/0` 中间输出后中断）；事后 `ps` 确认无 Lightamer 测试宿主残留，未修改任何源码/文档。纪律计数仍以定向 1 类为准。
- 工作区 `git status` 滞留物（M3-4 回溯队列、`dt-clone-archive/`、gui-acceptance jpg）与 M2-1 无关，未触碰。

OMP-VERDICT: PASS

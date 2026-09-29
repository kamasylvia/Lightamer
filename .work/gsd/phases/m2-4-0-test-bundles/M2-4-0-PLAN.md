---
phase: m2-4
plan: "M2-4-0"
title: "test bundle 拆分——单 LightamerTests（2165 测试/宿主，全套回归 RSS 峰值 3.7-10.4G 破 16G 机器安全线）按域拆 6 个 unit-test target；测试源文件零改动（只动 Project.swift target 归属 + Scripts/test-direct.sh 多 bundle 跑法）；全套回归一条命令 + 每 bundle 峰值 RSS <3G 硬门 + 计数对账 2165/14skip"
wave: 1
depends_on: []
autonomous: true
requirements: [M2-4-0]
files_modified:
  - Project.swift                                                # 修改：单 LightamerTests → 6 个 unit-test target（IOP/Layers/Library/Sessions/Export/App），显式文件清单（BUNDLE-MAP.txt 为归属正本），统一依赖面 {Core,IOP,Lightamer,WebP,MCP} + 同 TestFixtures resources glob；scheme testAction 挂 6 target
  - Scripts/test-direct.sh                                       # 修改：--bundle <name> 选择器 + --all 顺序跑全套（每 bundle 独立宿主进程）+ BUNDLE|<name>|<n>/<skip>/<fail> 计数行 + 峰值 RSS 采样 + 总退出码/时长；保留单 bundle + 类过滤直跑
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 已建（规划期生成）：233 文件 → bundle 归属正本，T1 照此落 Project.swift 数组，T3 复核一致性
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-SUMMARY.md       # 新建（收口任务）
  - AGENTS.md                                                    # 修改（收口任务）：资源监控节过渡条款解除（改记常态化口径）
  - .work/GOAL-STATE.md                                          # 续接点追加（收口任务）
  - .work/TODO.md                                                # 翻账（收口任务）
  - .work/LESSONS.md                                             # 如踩坑
---

# Plan M2-4-0 — test bundle 拆分（单宿主 2165 测试 → 六域 bundle，任一单宿主 <3G）

> **性质**：测试基建 plan——`Tests/LightamerTests/`、`LightamerCore/`、`LightamerIOP/`、`App/`
> **源文件零改动**（零移动、零内容编辑）；只动 `Project.swift`（target 归属）与
> `Scripts/test-direct.sh`（跑法）。动因 = 2026-09-29 AGENTS.md「资源监控」节两次事件
> （10.4G 未响应 / 7.5G 用户强杀）+ 2026-09-30 凌晨全套 756.7s 峰值 3.73G——单 test host
> 2165 测试的内存累积已破 16G 机器安全线，过渡条款（orchestrator 批准 + >8G 即杀）
> 不可长留。**验收硬门：任一 bundle 单宿主运行期峰值 RSS <3G；全套一条命令；计数对账
> 2165/14skip + δ。**
>
> **实测基线（规划期盘点，2026-09-29）**：233 个 test 文件全部平铺于
> `Tests/LightamerTests/`（无子目录）；纯 XCTest（232 文件 import XCTest）；测试方法总数
> grep 实测 = **2165（与运行期基线精确一致）**；跨文件共享符号仅 2 个零测试 helper
> （`Fixtures.swift` 26 文件使用 / `ParityGate.swift` 14 文件使用）——**拆分的全部耦合面
> 就这两位，且都是零测试文件，可安全进多个 target**（各 bundle 独立编译拷贝，无链接
> 冲突、无测试重复）。其余 8 个疑似共享符号（McpJSONSerialization /
> McpLauncherEndpointProbe / RenderCounter / McpEndpointHostFixtures / ProgressRecorder /
> DebounceTestClock / SoftProof 内嵌 Fixtures / ImportProgressRecorder）经逐一 grep 实证
> **全部单文件内聚或同域文件内聚**，无跨 bundle 泄漏。无跨文件测试类继承。

## 已定裁决（不得重开）

- **D1（六域边界 + 零改动迁移）**：按既有域拆 6 个 unit-test target，归属正本 =
  `M2-4-0-BUNDLE-MAP.txt`（规划期逐文件分类 + 计数，总和 2165 已核）：

  | target | 域 | 文件数 | 测试数 |
  |---|---|---:|---:|
  | `LightamerTestsIOP` | Pipe/IOP kernel parity+golden、RAW 解码、HDR 堆栈、LUT kernel、管线基建（PipeCache/MetalContext/MemoryBudget…） | 97 | 765 |
  | `LightamerTestsLibrary` | Library/Sidecar(.lra .lalb)/XMP/EXIF/Import/Presets/StableHash（M2-2/M2-3 检索域） | 43 | 430 |
  | `LightamerTestsApp` | Panel/UI wiring、Editor 腿、Theme/Settings、路由 + MCP host/toolset 全族 | 22 | 267 |
  | `LightamerTestsSessions` | Session/Catalog/Culling/批量套用/对账 diff（Phase 9/16） | 25 | 279 |
  | `LightamerTestsExport` | Export 管线/编码器/WebP/QuickLook/Spotlight + Yiyin 印框水印全族 | 24 | 260 |
  | `LightamerTestsLayers` | Layers/Masks（含 AIMask）/HistoryStack 编辑状态域（Phase 6） | 20 | 164 |
  | （SHARED） | `Fixtures.swift` + `ParityGate.swift`：零测试 helper，列入所有引用它的 target（多 target 编译拷贝） | 2 | 0 |

  **零改动迁移纪律**：测试文件不移动、不编辑（含不建子目录——文件平铺是既成事实，
  用 Project.swift 显式文件清单承载归属，不依赖目录 glob）；不新建任何测试源文件；
  diff 面只有 Project.swift + Scripts/test-direct.sh + 文档。
- **D2（宿主复用结论——单宿主二进制，每 bundle 独立进程）**：test-direct 直启机制与
  多 bundle **兼容**，无需多宿主：`libXCTestBundleInject.dylib` 是宿主 app Frameworks 级
  注入体（与 .xctest 无关）；直启配置 plist 的 `TestBundlePath` + `productModuleName`
  参数化后指向任一 `PlugIns/<name>.xctest`；6 个 bundle 共享同一
  `Lightamer.app/Contents/MacOS/Lightamer` 宿主二进制，**串行各起一个全新进程**——
  进程退出即 Metal/CI/actor 全部状态清零，这正是内存门的结构性保证（比今天单进程
  2165 连跑更干净，不是更脏）。
- **D3（统一依赖面 + 资源 glob）**：6 个 test target 一律
  `dependencies: [Core, IOP, Lightamer, WebP, MCP]` + `resources: ["Resources/TestFixtures/**"]`
  （与现 LightamerTests 完全同构）。理由：62 个测试文件 `@testable import Lightamer`
  （app 层状态）散布所有域（含 McpHost/Editor/Viewport/Paste/CullingPipeline…），按域
  逐 target 裁依赖 = 高风险零收益；TestFixtures 仅 6.2M，×6 复制 ≈ 37MB 磁盘，可忽略；
  WebP/MCP 包产品挂多余 target 只增链接不增行为。bundleId 按
  `com.kamasylvia.lightamer.tests.<域>` 派生（D-05 命名延例）。
- **D4（跑法机制）**：`test-direct.sh` 扩展（脚本签名向后兼容——无参 = 全套 = --all）：
  - `Scripts/test-direct.sh` / `--all`：按 IOP→Layers→Library→Sessions→Export→App 顺序
    各起独立宿主进程跑完 6 bundle；每 bundle 输出一行
    `BUNDLE|<name>|<executed>/<skipped>/<failed>|peakRSS=<MB>|<seconds>`，末行
    `TOTAL|<sum executed>/<sum skipped>/<sum failed>|<total seconds>`；任一 bundle
    fail 或 executed=0（L028 防空转闸门逐 bundle 生效）→ 总退出码非零；峰值 RSS ≥3G
    → 该 bundle 判 FAIL 并列 `MEMFAIL` 标记（硬门机检）。
  - `Scripts/test-direct.sh --bundle IOP ['ClassFilter']`：单 bundle 直跑（定向轮）；
    无 --bundle 的类过滤参数保持现行为兼容（落到默认 bundle 或报错提示，实现自定，
    以不破坏现有调用为界）。
  - RSS 采样 = 宿主 pid 后台 `ps -o rss=` 轮询（1s 间隔）取 max，随 bundle 行输出；
    per-bundle 完整日志 `/tmp/la-direct-tests-<bundle>.log`（沿用 /tmp 即弃惯例）。
- **D5（IOP bundle >3G 预案——预声明拆分线）**：IOP 是最重域（765 测试 ≈ 全套 35%，
  Metal parity/golden kernel 反复跑 + RAW 解码）。若 T3 实测 IOP 单宿主峰值 ≥3G：
  **停，OQ 上报 orchestrator**，预声明拆分线 = 把 `*Parity*|Golden*|ToneEqual*|Lut3d*`
  （kernel 反复执行型）再拆 `LightamerTestsIOPParity`（7 bundle，超出 4-6 指导值——
  <3G 硬门优先于 bundle 数指导，需 orchestrator 批准后执行）。不得未经批准自行加
  bundle，也不得为凑 6 放宽内存门。
- **D6（scheme 与 xcodebuild 面）**：`Lightamer` scheme testAction = 6 unit-test target +
  LightamerUITests（顺序不变式：UITests 永远在最后）；`xcodebuild build-for-testing`
  一次产出全部 `.xctest`（test-direct 前提不变）；定向轮可
  `-only-testing:LightamerTestsIOP` 或走 `--bundle`。`tuist generate` 后
  `xcodebuild build` 与 `build-for-testing` 都必须绿才进 T2。

## 风险与排查（执行者必读）

1. **跨文件符号耦合的编译期暴露**：规划期只实证了显式 helper 符号；若存在规划未捕获
   的跨文件引用（同名 extension/内部类型），表现为**个别 bundle 编译失败**——处置 =
   把被引用的零测试定义文件一并列入该 bundle（只允许零测试 helper 进多 target；含
   测试方法的文件禁重复列入，否则计数翻倍破坏对账）。三秒定位：
   `nm -gU <.xctest>/MacOS/<name> | grep <Symbol>`（L041 同款）。
2. **共享态假设排查（单进程顺序依赖）**：现单进程内隐式顺序依赖（前序测试写
   UserDefaults / 固定路径 /tmp 文件 / 单例态被后序测试消费）拆 bundle 后断裂——表现 =
   某测试单独跑绿、随 bundle 跑红（或反之）。处置原则：先隔离复跑定位（单类过滤），
   确属顺序依赖的测试对**如实上报**（可临时同 bundle 编排缓解 + 登记 M2-4-0-SUMMARY，
   修测试本体超出本 plan 零改动红线，留后续 plan）。已知的良性共享：UserDefaults 同
   宿主 app id 跨 bundle 持久——今天单进程内同样存在，串行 bundle 不比现状差。
3. **tuist generate 面（L041）**：批量改 Project.swift 后 generate 永远是该批最后一个
   动作；generate 幂等秒级。DerivedData 多容器按 xctest 可执行 mtime 取最新（现机制
   保留，6 产物同批构建 mtime 同源，无新风险）。
4. **L028 双读兼容**：`Executed 0 tests` 防空转闸门必须逐 bundle 生效（--all 模式下
   任一 bundle executed=0 即总失败，输出指明哪个 bundle + 其日志路径）。
5. **计数污染**：grep 计数口径 = `^\s*(func test|@Test)`（规划期基线口径）；含
   `override func` 的非测试方法不会误计（XCTest 生命周期方法不叫 test 前缀）。
   BUNDLE-MAP.txt 的静态计数与运行期 Executed 差异只能来自 skip 计入口径（XCTest
   的 Executed 计数**含** skipped），对账公式见 AC-1。
6. **构建时间**：6 test target 链接 &gt; 单 target（全量 build-for-testing 变慢分钟级）；
   定向轮只构建改动域反而更快。可接受，不做构建优化。

## Tasks

### T1 — Project.swift 六 test target 改造（归属正本 = BUNDLE-MAP.txt）
- **read_first**: `Project.swift`；`.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`；
  AGENTS.md「Phase 2 架构增量」「M2-2 架构增量」（bundleId/目录惯例）；L041（generate 时序）。
- **action**:
  1. Project.swift：删单 `LightamerTests` target，按 BUNDLE-MAP.txt 建 6 个
     `.unitTests` target（D1 表 + D3 统一依赖/资源/bundleId；sources = 显式文件路径
     数组，SHARED 两文件列入所有引用它们的 target——引用关系见 BUNDLE-MAP 使用者
     清单：Fixtures → IOP/Layers/Library/Sessions/Export/App 全列（26 使用者跨 5 域 +
     冗余无害）；ParityGate → 仅 IOP）。
  2. scheme `Lightamer` testAction 挂 6 target + UITests（D6）。
  3. `tuist generate`（该批最后动作）→ `caffeinate -dis xcodebuild build-for-testing
     -workspace Lightamer.xcworkspace -scheme Lightamer -destination 'platform=macOS'`
     绿；`ls <DerivedData>/.../PlugIns/` 实证 6 个 `.xctest` 产物。
  4. 编译失败按风险 §1 处置；**禁止**为编译通过改动任何 `Tests/` 源文件。
- **AC**: build-for-testing 绿；6 个 `.xctest` 产物存在；`git diff --stat` 面 =
  {Project.swift} ∪ {风险 §1 允许的零新增文件集为空}（即只有 Project.swift）；
  BUNDLE-MAP 233 文件逐一可归属（audit：数组并集 - SHARED = 231，无遗漏无重复——
  含测试方法文件唯一归属）。
- **commit**: `feat(m2-4-0): split unit tests into six domain test targets`

### T2 — test-direct.sh 多 bundle 跑法
- **read_first**: `Scripts/test-direct.sh` 现正本；L019b（直启配方）；L028（防空转
  双读）；本 plan D4。
- **action**:
  1. bundle 注册表（name → .xctest 相对路径 + productModuleName），config plist 逐
     bundle 生成；宿主二进制/libXCTestBundleInject 解析逻辑不变（D2 单宿主）。
  2. `--bundle <name>` 单跑 + 可选类过滤参数；`--all`（及无参默认）= 六 bundle 串行，
     每 bundle 独立进程 + 独立日志 + BUNDLE 行（D4 格式）+ 峰值 RSS 采样 + 时长；
     末行 TOTAL + 总退出码（fail / executed=0 / RSS≥3G 任一即非零，输出定位到
     bundle）。退出态污染防护沿用现注释口径（RC 仅诊断参考，判据 = Executed/failed 行）。
  3. 向后兼容：现有 `Scripts/test-direct.sh 'StableHashTests'` 类调用形态不破坏
     （映射到全 bundle 扫描或提示 --bundle，二选一，写入脚本头注释）。
  4. 手工冒烟：`--bundle IOP 'StableHashTests'`——不对，StableHash 在 Library 域；
     用 `--bundle Library 'StableHashTests'`（7 tests）+ `--bundle IOP`（765）各一轮。
- **AC**: 单 bundle 轮计数与 `xcodebuild test -only-testing` 历史口径一致（抽查 2 族）；
  `--all` 全绿轮 6 行 BUNDLE + 1 行 TOTAL；人为注入 RSS 门测试（临时阈值 1MB）确认
  MEMFAIL 路径生效后还原。
- **commit**: `feat(m2-4-0): multi-bundle direct-launch runner with per-bundle accounting`

### T3 — 对账 + 内存门 + 时长 + 门控归属验证（本 plan 核心验收）
- **read_first**: GOAL-STATE 资源监控节（基线 2165/14skip/756.7s/峰值 3.73G）；
  AGENTS.md「资源监控」；BUNDLE-MAP.txt。
- **action**:
  1. **AC-1 计数对账**：`--all` 一轮，Σ BUNDLE executed = 2165 + δ_new、Σ skipped =
     14 + δ_new（δ = 拆分批新增/删除条目，逐条如实记 SUMMARY；预期 δ=0——本 plan
     不增删任何测试）。静态复核：BUNDLE-MAP 各域计数 vs 运行期 BUNDLE 行逐域相等
     （允许 skip 口径差，逐域解释）。
  2. **AC-2 内存硬门**：每 bundle peakRSS &lt; 3072MB（脚本已机检）；人工复核 6 行
     数值记 SUMMARY。**IOP ≥3G → 触发 D5 预案，停，OQ 上报**。
  3. **AC-3 总时长**：TOTAL 秒数 ≤ 1135s（= 1.5 × 756.7s 基线）；记录进 SUMMARY。
  4. **AC-4 门控归属审计**：`LA_CATALOG_BENCH*`→Sessions、`LA_LIBRARY_BENCH*`/
     `LA_THUMB_BENCH*`→Library、`LIGHTAMER_MCP`/`LIGHTAMER_FULL_IOP_FACE`→App、
     `LIGHTAMER_RAW_SAMPLES_DIR`→IOP（门体在共享 Fixtures.swift，随宿主 bundle
     生效）——grep 核对每门控的使用文件 ∈ 表内 bundle，BENCH 门默认 skip 形态逐
     bundle 确认（不设 env 跑 --all 即天然覆盖）。
  5. **AC-5 零源改动复核**：`git diff --name-only <起点>..HEAD` ⊆ {Project.swift,
     Scripts/test-direct.sh, .work/gsd/phases/m2-4-0-test-bundles/*, AGENTS.md}——
     `Tests/`、`LightamerCore/`、`LightamerIOP/`、`App/` 零出现。
  6. 发现顺序依赖型失败（风险 §2）→ 按处置原则记录，不修测试本体。
- **AC**: 本节 1-5 全部留痕（命令 + 输出摘要进 SUMMARY）；任一硬门破线 → 停 + OQ，
  不自行绕。
- **commit**: `test(m2-4-0): reconcile 2165-test baseline across six bundles under 3G`

### T4 — 收口（文档 + 台账）
- **action**: AGENTS.md「资源监控」节过渡条款改写为常态化口径（"全套回归经
  test-direct.sh --all 分 6 bundle 跑，单宿主 <3G 硬门由脚本机检"）；CONVENTIONS
  测试约定补一行（新测试文件落域规则：按 BUNDLE-MAP 域模式 + 更新 Project.swift
  对应数组）；GOAL-STATE 续接点 + TODO 翻账 + SUMMARY（含 6 bundle 计数/内存/时长
  实测表）。
- **commit**: `docs(m2-4-0): close out test bundle split with ledgers`

## AC 汇总（机检）

| # | 断言 | 机检方式 |
|---|---|---|
| 1 | 计数对账 2165/14skip + δ（δ 如实记账，预期 0） | `--all` TOTAL 行 + 逐域 BUNDLE 行 vs BUNDLE-MAP 静态计数 |
| 2 | 任一 bundle 单宿主峰值 RSS &lt;3G | 脚本 `ps -o rss=` 采样 max，≥3072MB 即 FAIL（MEMFAIL） |
| 3 | 全套串行总时长 ≤1.5× 基线（≤1135s vs 756.7s） | TOTAL 行秒数 |
| 4 | 门控测试逐 bundle 归属正确（LA_*_BENCH / LIGHTAMER_*） | grep 审计 + 不设 env 全套轮 skip 形态 |
| 5 | 测试源零改动 | `git diff --name-only` 面 ⊆ 白名单（T3-AC-5） |
| 6 | 全套一条命令 | `Scripts/test-direct.sh` 无参即全套，总退出码判green/red |
| 7 | 归属完备无重复 | 数组并集 = 231（+2 SHARED 多列），无遗漏；含测试方法文件唯一 target |

## Open Questions（无硬阻塞）

- 无。直启机制 × 多 bundle 兼容性已按 D2 给出结论；唯一预案（D5 IOP 超门）已预声明
  拆分线并定义上报点，不构成开工阻塞。

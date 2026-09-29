---
phase: m2-4
plan: "M2-4-0"
title: "test bundle 拆分——单 LightamerTests（2165 测试/宿主，全套回归 RSS 峰值 3.7-10.4G 破 16G 机器安全线）按域拆 6 个 unit-test target；测试源文件零改动（唯一豁免 = E1 两个 chain builder 抽出为零测试 SHARED helper，测试方法零增量；其余只动 Project.swift target 归属 + Scripts/test-direct.sh 多 bundle 跑法）；全套回归一条命令 + 每 bundle 峰值 RSS <3G 硬门 + 计数对账 2165/14skip"
wave: 1
depends_on: []
autonomous: true
requirements: [M2-4-0]
files_modified:
  - Project.swift                                                # 修改：单 LightamerTests → 6 个 unit-test target（IOP/Layers/Library/Sessions/Export/App），显式文件清单（BUNDLE-MAP.txt 为归属正本），统一依赖面 {Core,IOP,Lightamer,WebP,MCP} + 同 TestFixtures resources glob；scheme testAction 挂 6 target
  - Scripts/test-direct.sh                                       # 修改：--bundle <name> 选择器 + --all 顺序跑全套（每 bundle 独立宿主进程）+ BUNDLE|<name>|<n>/<skip>/<fail> 计数行 + 峰值 RSS 采样（主判据 /usr/bin/time -l ru_maxrss）+ 总退出码/时长；保留单 bundle + 类过滤直跑
  - Tests/LightamerTests/ChainBuilderHelpers.swift + 30 调用点改写文件  # E1 豁免（checker 2026-09-30 授权，唯一测试源改动例外）：TerminalTrioTests/GeometryGoldenTests 两 chain builder 抽出为零测试 SHARED helper + 49 处限定名调用去前缀，全部非测试方法行，测试方法零增量（对账 2165 不变）；清单见 D1 E1 节
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 已建（规划期生成；E1 回注 +1 SHARED 行）：234 文件（231 域文件 + 3 SHARED）→ bundle 归属正本，T1 照此落 Project.swift 数组，T3 复核一致性
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-SUMMARY.md       # 新建（收口任务）
  - AGENTS.md                                                    # 修改（收口任务）：资源监控节过渡条款解除（改记常态化口径）+ 测试约定处补落域规则一行（E2，与资源监控节同文件）
  - .work/GOAL-STATE.md                                          # 续接点追加（收口任务）
  - .work/TODO.md                                                # 翻账（收口任务）
  - .work/LESSONS.md                                             # 如踩坑
---

# Plan M2-4-0 — test bundle 拆分（单宿主 2165 测试 → 六域 bundle，任一单宿主 <3G）

> **性质**：测试基建 plan——`Tests/LightamerTests/`、`LightamerCore/`、`LightamerIOP/`、`App/`
> **测试源零改动为原则**（零移动、零内容编辑）；只动 `Project.swift`（target 归属）与
> `Scripts/test-direct.sh`（跑法）。**唯一授权的测试源改动豁免（E1，checker 2026-09-30
> 回注）**：把 `TerminalTrioTests.makeCommittedDefaultChain` 与
> `GeometryGoldenTests.makeChainWithCropFlip` 两个跨域 chain builder 抽出为零测试
> SHARED helper（新独立文件 `ChainBuilderHelpers.swift`，方法原样搬移 + 调用点机械
> 改写，测试方法 0 增量、对账 2165 不变）——除该豁免外，`Tests/` 面零改动红线不变。
> 动因 = 2026-09-29 AGENTS.md「资源监控」节两次事件
> （10.4G 未响应 / 7.5G 用户强杀）+ 2026-09-30 凌晨全套 756.7s 峰值 3.73G——单 test host
> 2165 测试的内存累积已破 16G 机器安全线，过渡条款（orchestrator 批准 + >8G 即杀）
> 不可长留。**验收硬门：任一 bundle 单宿主运行期峰值 RSS <3G；全套一条命令；计数对账
> 2165/14skip + δ。**
>
> **实测基线（规划期盘点，2026-09-29；E1 修正 2026-09-30）**：233 个 test 文件全部平铺于
> `Tests/LightamerTests/`（无子目录）；纯 XCTest（232 文件 import XCTest）；测试方法总数
> grep 实测 = **2165（与运行期基线精确一致）**。跨文件共享符号：规划期实证 2 个零测试
> helper（`Fixtures.swift` 26 文件使用 / `ParityGate.swift` 14 文件使用）；**checker 回注
> 补实证第 3 耦合面**——`TerminalTrioTests.makeCommittedDefaultChain`（static，
> TerminalTrioTests.swift:328）被全仓 **30 文件 5 域**调用（grep 实测：IOP 19 / LAYERS 6 /
> APP 2 / LIB 1 / EXPORT 2，共 50 处符号出现 = 1 定义 + 49 处 `TerminalTrioTests.` 限定
> 名调用；checker 报 31 文件系计数口径差，以 grep 复核为准），且
> `GeometryGoldenTests.makeChainWithCropFlip`（internal，GeometryGoldenTests.swift:435）
> 被 `LayerCompositeTests.swift:439` 以 `GeometryGoldenTests()` 直接实例化调用——
> 按域拆分后这两符号必致 4 个 bundle 编译失败，处理 = E1 豁免抽取（见风险 §1）。
> 其余 8 个疑似共享符号（McpJSONSerialization /
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
  | （SHARED） | `Fixtures.swift` + `ParityGate.swift` + `ChainBuilderHelpers.swift`（E1 豁免新增）：零测试 helper，列入所有引用它的 target（多 target 编译拷贝） | 3 | 0 |

  **零改动迁移纪律**：既有 233 个测试文件不移动、不编辑（含不建子目录——文件平铺是既成事实，
  用 Project.swift 显式文件清单承载归属，不依赖目录 glob）；**唯一例外 = E1 豁免**
  （新建 `ChainBuilderHelpers.swift` + 两 builder 定义搬移 + 30 文件调用点机械改写，
  全部为非测试方法行，测试方法计数零增量）；不新建任何其它测试源文件；
  diff 面只有 Project.swift + Scripts/test-direct.sh + 文档 + E1 豁免集。
- **E1 豁免（chain builder 抽取，checker 2026-09-30 授权，唯一测试源改动例外）**：
  - **抽取对象**：`TerminalTrioTests.makeCommittedDefaultChain(registry:outputProfile:)`
    （static，TerminalTrioTests.swift:328）与
    `GeometryGoldenTests.makeChainWithCropFlip(registry:outputProfile:)`（internal 实例
    方法，无 self 依赖，GeometryGoldenTests.swift:435）——方法体**原样搬移**为
    `Tests/LightamerTests/ChainBuilderHelpers.swift` 内的自由函数（`import XCTest`，
    `makeChainWithCropFlip` 内部用到 `XCTUnwrap`）；TerminalTrioTests/GeometryGoldenTests
    两文件内删定义，两文件内既有调用改为无前缀自由函数调用。
  - **调用点机械改写**：全仓 49 处 `TerminalTrioTests.makeCommittedDefaultChain(` 限定
    名调用 → 去前缀（触及 30 文件：IOP 19 / LAYERS 6 / APP 2 / LIB 1 / EXPORT 2）；
    `LayerCompositeTests.swift:439` 的 `GeometryGoldenTests().makeChainWithCropFlip(` →
    直接调用（该文件已在上集内）。**所有改动行均为非测试方法行**——
    `grep -cE '^\s*(func test|@Test)'` 全仓 2165 零增量，对账不受影响。
  - **SHARED 编列**：`ChainBuilderHelpers.swift` 零测试，编入
    **IOP/Layers/Library/Export/App 5 target（最小列，循 ParityGate 先例）**——SESS 无
    调用者（grep 实证），不列；后续 SESS 若出现调用者，风险 §1 编译失败流程会显式
    暴露，届时补列即可。
  - **劣选明示（勿用）**：把 TerminalTrioTests.swift / GeometryGoldenTests.swift 整文件
    列入多 target = 两文件 14+5 个测试方法在各 bundle 重复执行，计数对账 2165 破功——
    禁止。改测试方法本体超红线，同样禁止。
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
  - RSS 采样**主判据 = `/usr/bin/time -l` 包宿主进程**，跑完解析其输出的
    `ru_maxrss`（macOS 单位 bytes，÷1048576 得 MB）——内核记账的精确峰值，无采样间隙，
    随 bundle 行输出 peakRSS；`ps -o rss=` 1s 轮询取 max **降为后备**（仅 time 不可用
    时，输出行标注采样方式）。per-bundle 完整日志 `/tmp/la-direct-tests-<bundle>.log`
    （沿用 /tmp 即弃惯例）。
- **D5（IOP bundle >3G 预案——预声明拆分线）**：IOP 是最重域（765 测试 ≈ 全套 35%，
  Metal parity/golden kernel 反复跑 + RAW 解码）。若 T3 实测 IOP 单宿主峰值 ≥3G：
  **停，OQ 上报 orchestrator**，预声明拆分线 = 把 `*Parity*|Golden*|ToneEqual*|Lut3d*`
  （kernel 反复执行型）再拆 `LightamerTestsIOPParity`（7 bundle，超出 4-6 指导值——
  <3G 硬门优先于 bundle 数指导，需 orchestrator 批准后执行）。不得未经批准自行加
  bundle，也不得为凑 6 放宽内存门。
- **D6（scheme 与 xcodebuild 面）**：`Lightamer` scheme testAction = 6 unit-test target +
  LightamerUITests（顺序不变式：UITests 永远在最后）；`xcodebuild build-for-testing`
  一次产出全部 `.xctest`（test-direct 前提不变）；定向轮一律走 `--bundle`
  （test-direct 直启）。`-only-testing:LightamerTestsIOP` 备选**非本 plan 路径**——
  该形态仅 `xcodebuild test` 语义有效，而 `xcodebuild test` 会经 testmanagerd 触发
  enrollment 弹窗（L019b 弹窗规避正为此绕开它），与直启路线相抵，仅存档不作实现依据。
  `tuist generate` 后
  `xcodebuild build` 与 `build-for-testing` 都必须绿才进 T2。

## 风险与排查（执行者必读）

1. **跨文件符号耦合的编译期暴露**：规划期漏网的跨文件引用已由 checker 回注实证一处
   （`TerminalTrioTests.makeCommittedDefaultChain` 5 域 30 文件 +
   `GeometryGoldenTests.makeChainWithCropFlip` LAYERS 直接实例化）——**已预置处置 =
   E1 豁免**（抽 `ChainBuilderHelpers.swift` 零测试 SHARED helper + 调用点机械改写，
   见 D1；这是唯一授权的测试源改动例外）。若执行期仍出现规划未捕获的其它跨文件引用
   （同名 extension/内部类型），表现为**个别 bundle 编译失败**——处置 = 把被引用的
   零测试定义文件一并列入该 bundle（只允许零测试 helper 进多 target；含测试方法的
   文件禁重复列入，否则计数翻倍破坏对账）；若被引用符号含测试方法体，停 + OQ 上报，
   不得即席扩豁免。三秒定位：
   `nm -gU <.xctest>/MacOS/<name> | grep <Symbol>`（L041 同款）。
2. **共享态假设排查（单进程顺序依赖）**：现单进程内隐式顺序依赖（前序测试写
   UserDefaults / 固定路径 /tmp 文件 / 单例态被后序测试消费）拆 bundle 后断裂——表现 =
   某测试单独跑绿、随 bundle 跑红（或反之）。**在案 flaky 点名（M4，防验收误判）**：
   `LayerE2ERoundTripTests`（LAYERS 域）为 M2-2-2 起在案的**负载型 SIGTRAP flaky**
   （GOAL-STATE 2026-09-30 续接点与 11-04 记录在案：全套负载下偶发 SIGTRAP，隔离复跑
   ×3 绿，非改动面引入）——`--all` 撞上该测试 SIGTRAP 时按在案归因处置（隔离复跑
   定性 + SUMMARY 如实登记留观），**不得误判为拆分引入而回滚拆分**。处置原则：先隔离
   复跑定位（单类过滤），确属顺序依赖的测试对**如实上报**（可临时同 bundle 编排缓解 +
   登记 M2-4-0-SUMMARY，修测试本体超出本 plan 零改动红线，留后续 plan）。已知的良性
   共享：UserDefaults 同宿主 app id 跨 bundle 持久——今天单进程内同样存在，串行
   bundle 不比现状差。
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
  0. **E1 豁免抽取（先于拆分，唯一授权的测试源改动）**：新建
     `Tests/LightamerTests/ChainBuilderHelpers.swift`（零测试，`import XCTest`），把
     `TerminalTrioTests.makeCommittedDefaultChain`（static）与
     `GeometryGoldenTests.makeChainWithCropFlip` 方法体**原样搬移**为自由函数；删两
     文件内定义 + 全仓 49 处 `TerminalTrioTests.` 限定名调用去前缀 +
     `LayerCompositeTests.swift:439` 直接调用改写（30 文件，全部非测试方法行，D1 E1
     节为唯一口径）；完成后 `grep -rcE '^\s*(func test|@Test)' Tests/` 全仓 = 2165
     自证零增量，再进下步。
  1. Project.swift：删单 `LightamerTests` target，按 BUNDLE-MAP.txt 建 6 个
     `.unitTests` target（D1 表 + D3 统一依赖/资源/bundleId；sources = 显式文件路径
     数组，SHARED 三文件列入所有引用它们的 target——引用关系见 BUNDLE-MAP 使用者
     清单：Fixtures → IOP/Layers/Library/Sessions/Export/App 全列（26 使用者跨 5 域 +
     冗余无害）；ParityGate → 仅 IOP；ChainBuilderHelpers → IOP/Layers/Library/Export/
     App 最小列，SESS 无调用者）。
  2. scheme `Lightamer` testAction 挂 6 target + UITests（D6）。
  3. `tuist generate`（该批最后动作）→ `caffeinate -dis xcodebuild build-for-testing
     -workspace Lightamer.xcworkspace -scheme Lightamer -destination 'platform=macOS'`
     绿；`ls <DerivedData>/.../PlugIns/` 实证 6 个 `.xctest` 产物。
  4. 编译失败按风险 §1 处置；**禁止**为编译通过改动任何 `Tests/` 源文件——**唯一
     例外 = 步骤 0 的 E1 豁免集**，越界即停 + OQ。
- **AC**: build-for-testing 绿；6 个 `.xctest` 产物存在；`git diff --name-only` 面 =
  {Project.swift, Tests/LightamerTests/ChainBuilderHelpers.swift} ∪ E1 调用点改写
  30 文件（逐文件对账 D1 E1 清单，改动行均为非测试方法行）；测试方法零增量 =
  `grep -rcE '^\s*(func test|@Test)' Tests/` 合计 2165；BUNDLE-MAP 234 文件
  （231 域文件 + 3 SHARED）逐一可归属（audit：数组并集 - SHARED = 231，无遗漏
  无重复——含测试方法文件唯一归属）。
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
- **AC**: 单 bundle 轮计数与拆分前 LightamerTests 历史计数一致（抽查 2 族，对照既往
  运行记录取值，不重跑 `xcodebuild test`——该形态与 L019b 弹窗规避相抵，见 D6）；
  `--all` 全绿轮 6 行 BUNDLE + 1 行 TOTAL；人为注入 RSS 门测试（临时阈值 1MB）确认
  MEMFAIL 路径生效后还原。
- **commit**: `feat(m2-4-0): multi-bundle direct-launch runner with per-bundle accounting`

### T3 — 对账 + 内存门 + 时长 + 门控归属验证（本 plan 核心验收）
- **read_first**: GOAL-STATE 资源监控节（基线 2165/14skip/756.7s/峰值 3.73G）；
  AGENTS.md「资源监控」；BUNDLE-MAP.txt。
- **action**:
  1. **AC-1 计数对账 + 测试方法零增量**：`--all` 一轮，Σ BUNDLE executed = 2165 + δ_new、
     Σ skipped = 14 + δ_new（δ = 拆分批新增/删除条目，逐条如实记 SUMMARY；预期 δ=0
     ——本 plan 不增删任何测试）。**零增量断言（E1 豁免护栏）**：静态
     `grep -rcE '^\s*(func test|@Test)' Tests/` 合计 = 2165（E1 抽取后复核——豁免只许
     动非测试方法行，此数为硬证据）。静态复核：BUNDLE-MAP 各域计数 vs 运行期
     BUNDLE 行逐域相等（允许 skip 口径差，逐域解释）。
  2. **AC-2 内存硬门**：每 bundle peakRSS &lt; 3072MB（脚本已机检）；人工复核 6 行
     数值记 SUMMARY。**IOP ≥3G → 触发 D5 预案，停，OQ 上报**。
  3. **AC-3 总时长**：TOTAL 秒数 ≤ 1135s（= 1.5 × 756.7s 基线）；记录进 SUMMARY。
  4. **AC-4 门控归属审计（9 变量全清单，门体位置按实位核对）**：
     `LA_CATALOG_BENCH*`→Sessions（CatalogBenchmarkHarness.swift）、
     `LA_PERF07_VOLUME`→Sessions（Perf07MassApplyTests.swift）、
     `LA_LIBRARY_BENCH*`→Library（LibraryBenchmarkHarness.swift）、
     `LA_THUMB_BENCH*`→Library（LibraryGridModelTests.swift）、
     `LA_QL_PERF`→Export（QuickLookPerfProbeTests.swift）、
     `LA_REGEN_YIYIN_GOLDEN`→Export（YiyinWatermarkTests.swift）、
     `LIGHTAMER_MCP`→App（**门体在 APP 测试文件内**：McpLauncherTests /
     McpLauncherSentinelTests / McpFinalSnapshotTests）、
     `LIGHTAMER_FULL_IOP_FACE`→App 使用（McpHostTests.swift；**生产门体在
     LightamerIOP/Sources/Registry.swift** KD-3 opt-in——归属结论不变，审查按实位，
     生产源不在 diff 面内）、`LIGHTAMER_RAW_SAMPLES_DIR`→IOP（门体在共享
     Fixtures.swift，随宿主 bundle 生效）——grep 核对每门控的使用文件 ∈ 表内
     bundle，BENCH/PERF/QL 门默认 skip 形态逐 bundle 确认（不设 env 跑 --all 即
     天然覆盖）。
  5. **AC-5 零源改动复核（E1 豁免集单列对账）**：`git diff --name-only <起点>..HEAD`
     ⊆ {Project.swift, Scripts/test-direct.sh, .work/gsd/phases/m2-4-0-test-bundles/*,
     AGENTS.md, .work/GOAL-STATE.md, .work/TODO.md, .work/LESSONS.md} ∪ **E1 豁免集**
     （`Tests/LightamerTests/ChainBuilderHelpers.swift` 新建 + 30 个调用点改写文件，
     逐文件对账 D1 E1 清单）——`LightamerCore/`、`LightamerIOP/`、`App/` 零出现；
     `Tests/` 出现面 ⊆ E1 豁免集，且改动行均非测试方法行（AC-1 零增量断言兜底）。
  6. 发现顺序依赖型失败（风险 §2）→ 按处置原则记录，不修测试本体。
- **AC**: 本节 1-5 全部留痕（命令 + 输出摘要进 SUMMARY）；任一硬门破线 → 停 + OQ，
  不自行绕。
- **commit**: `test(m2-4-0): reconcile 2165-test baseline across six bundles under 3G`

### T4 — 收口（文档 + 台账）
- **action**: AGENTS.md「资源监控」节过渡条款改写为常态化口径（"全套回归经
  test-direct.sh --all 分 6 bundle 跑，单宿主 <3G 硬门由脚本机检"）；**AGENTS.md 测试
  约定处补一行**（「Swift / macOS 工程约定」节测试条目处：新测试文件落域规则 = 按
  BUNDLE-MAP 域模式 + 更新 Project.swift 对应数组；**落 AGENTS.md 而非 CONVENTIONS.md
  ——全仓无 CONVENTIONS.md，AGENTS.md 注入标记指向不存在文件为已知态，与资源监控
  节同文件且已在白名单内**，E2）；GOAL-STATE 续接点 + TODO 翻账 + SUMMARY（含
  6 bundle 计数/内存/时长实测表）；如踩坑记 `.work/LESSONS.md`。
- **commit**: `docs(m2-4-0): close out test bundle split with ledgers`

## AC 汇总（机检）

| # | 断言 | 机检方式 |
|---|---|---|
| 1 | 计数对账 2165/14skip + δ（δ 如实记账，预期 0）+ 测试方法零增量（E1 豁免护栏） | `--all` TOTAL 行 + 逐域 BUNDLE 行 vs BUNDLE-MAP 静态计数 + `grep -rcE '^\s*(func test\|@Test)' Tests/` 合计 = 2165 |
| 2 | 任一 bundle 单宿主峰值 RSS &lt;3G | 脚本主判据 `/usr/bin/time -l` 的 ru_maxrss（bytes→MB），≥3072MB 即 FAIL（MEMFAIL）；ps 轮询仅后备 |
| 3 | 全套串行总时长 ≤1.5× 基线（≤1135s vs 756.7s） | TOTAL 行秒数 |
| 4 | 门控测试逐 bundle 归属正确（9 变量全清单：LA_CATALOG_BENCH*/LA_PERF07_VOLUME/LA_LIBRARY_BENCH*/LA_THUMB_BENCH*/LA_QL_PERF/LA_REGEN_YIYIN_GOLDEN/LIGHTAMER_MCP/LIGHTAMER_FULL_IOP_FACE/LIGHTAMER_RAW_SAMPLES_DIR，门体位置按实位） | grep 审计（9 变量逐一）+ 不设 env 全套轮 skip 形态 |
| 5 | 测试源零改动（E1 豁免集单列对账） | `git diff --name-only` 面 ⊆ 白名单 ∪ E1 豁免集（T3-AC-5）；`Tests/` 出现 ⊆ E1 豁免集 |
| 6 | 全套一条命令 | `Scripts/test-direct.sh` 无参即全套，总退出码判green/red |
| 7 | 归属完备无重复 | 数组并集 = 231（+3 SHARED 多列），无遗漏；含测试方法文件唯一 target |

## Open Questions（无硬阻塞）

- 无。直启机制 × 多 bundle 兼容性已按 D2 给出结论；唯一预案（D5 IOP 超门）已预声明
  拆分线并定义上报点，不构成开工阻塞。

## Checker 回注记录（2026-09-30）

checker 判 FAIL（2E + 4M），全部回注本 plan（本节为修复清单存档，修订散见上文对应节）：

- **E1 跨 bundle 测试类引用（编译必炸，豁免改窄）**：规划期「跨文件共享符号仅 2 个零
  测试 helper」盘点漏网——`TerminalTrioTests.makeCommittedDefaultChain`（static，
  TerminalTrioTests.swift:328）被 5 域调用、`GeometryGoldenTests.makeChainWithCropFlip`
  （internal，GeometryGoldenTests.swift:435）被 LAYERS 直接实例化调用，按域拆分后 4 个
  bundle 编译失败。**「零改动」对该耦合面不可行**，改为授权窄豁免：两 builder 抽出为
  零测试 SHARED helper（新文件 `ChainBuilderHelpers.swift`，方法原样搬移 + 调用点机械
  改写，全部非测试方法行，测试方法 0 增量、对账 2165 不变）；SHARED 编入
  IOP/Layers/Library/Export/App 5 target（SESS 无调用者，最小列，循 ParityGate 先例）；
  劣选（整文件列 5 target = 测试跑 5 遍破对账）明示禁止。grep 复核实测 = 30 文件
  （IOP 19 / LAYERS 6 / APP 2 / LIB 1 / EXPORT 2）、50 处符号出现（1 定义 + 49 处
  `TerminalTrioTests.` 限定名调用；checker 报 31 文件系计数口径差，以 grep 为准）。
  修订落点：front-matter title/files_modified、引言、D1（表 + 纪律 + E1 节）、风险 §1、
  T1（步骤 0 + AC）、AC-1/AC-5/AC-7。
- **E2 文档落点缺失**：全仓无 CONVENTIONS.md（AGENTS.md 注入标记指向不存在文件，
  已知态）。T4「CONVENTIONS 补一行」改为「AGENTS.md 测试约定处补一行（与资源监控
  节同文件，白名单内）」；front-matter files_modified 确认已含 `AGENTS.md` 与
  `.work/LESSONS.md`（如踩坑）；AC-5 白名单同步补 `.work/GOAL-STATE.md` /
  `.work/TODO.md` / `.work/LESSONS.md`（T4 本就要求写这三处，原白名单漏列）。
- **M1 RSS 采样精度**：主判据改 `/usr/bin/time -l` 包宿主（`ru_maxrss` = 内核记账精确
  峰值，无轮询间隙；macOS 单位 bytes ÷1048576 得 MB），`ps -o rss=` 轮询降为后备
  （仅 time 不可用时，输出行标注）。落点：D4、AC 表 #2。
- **M2 AC-4 门控清单补全**：6 → **9 变量**（补 `LA_PERF07_VOLUME` / `LA_QL_PERF` /
  `LA_REGEN_YIYIN_GOLDEN`）；门体位置按实位改写——`LIGHTAMER_MCP` 门体在 APP 测试
  文件内（McpLauncherTests / McpLauncherSentinelTests / McpFinalSnapshotTests），
  `LIGHTAMER_FULL_IOP_FACE` 测试侧使用在 McpHostTests.swift 而生产门体在
  `LightamerIOP/Sources/Registry.swift`（KD-3 opt-in）——逐 bundle 归属结论不变，
  审查按实位。落点：T3-AC-4、AC 表 #4。
- **M3 `-only-testing` 备选误导**：D6「定向轮可 `-only-testing`」改为标注「仅
  `xcodebuild test` 语义，与 L019b 弹窗规避相抵，非本 plan 路径」；定向轮一律
  `--bundle`。T2-AC 的「`xcodebuild test -only-testing` 历史口径」同步消歧为「对照
  既往运行记录取值，不重跑」。落点：D6、T2-AC。
- **M4 在案 flaky 误判防护**：风险 §2 点名 `LayerE2ERoundTripTests`（LAYERS 域）为
  M2-2-2 起在案负载型 SIGTRAP flaky（隔离复跑 ×3 绿先例在 GOAL-STATE）——`--all`
  撞上时按在案归因处置（隔离复跑定性 + SUMMARY 登记），防验收误判为拆分引入而
  回滚拆分。落点：风险 §2。

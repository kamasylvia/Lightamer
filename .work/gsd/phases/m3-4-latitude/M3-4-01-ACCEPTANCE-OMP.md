# M3-4-01-ACCEPTANCE-OMP — FSIM-02 波 omp 独立二次验收

> 验收方：omp 二次验收（零共享上下文，独立执行四步；2026-10-09）。
> 对象：五提交 `a3a34af` → `383d829` → `9dc64ba` → `2d580d8` → `ad6c560`（HEAD 另有首验 `9f4f692` docs commit）。
> 首验：zcode PASS / 0E+3obs（`M3-4-01-ACCEPTANCE.md`）。本报告 = 独立第二遍，不轻信首验。

## 结论头

**FAIL / 1 error + 0 minor**（error = IOP bundle `testPlacementGainCompressesMonotonically` 红，HEAD 亲跑复现；阻塞）

## 一、定向复跑（fresh build 后亲跑，L055 双保险）

前置：`--help` 误触发真实 IOP bundle 运行（脚本无 help 挡板，`--help` 被当类过滤扫全套）——该轮 IOP 483/1/1 暴露 1 红。后执行 `xcodebuild build-for-testing`（162s，TEST BUILD SUCCEEDED）刷新产物，定向复跑：

| bundle | 首验申报 | omp 亲跑 | peakRSS | 时长 | 判定 |
|---|---|---|---|---|---|
| App | 686/0/0 | **686/0/0** | 2831MB | 353s | ✅ 逐位（含 RSS） |
| IOPParity | 408/3/0 | **408/3/0** | 5998MB | 460s | ✅ 逐位（RSS 5998 vs 首验 5344，+12% 运行方差内，<8G 门） |
| IOP（类过滤 FilmPlacementTests） | 未申报 | **11/0/1** | — | 5s | ❌ 1 红复现 |

- App/IOPParity 两轮 verdict OK（direct launch，no testmanagerd）、末条 Executed 挂 `All tests` 总计段（亲核日志尾两行）、计数逐位。
- 三方对表亲核：`func test` 实数（FilmGoldenTests 16 / FilmLatitudePanelTests 11 / FilmDescriptorTests 7）× Project.swift（:312/:804/:485）× BUNDLE-MAP ✅。
- Layers 未在 omp 任务范围内（任务指定 App + IOPParity），未复跑；首验 Layers 378/3/0 未被推翻但也未被 omp 独立确认。

## 二、数学抽查（Bash + Python 独立实现，第三实现）

RFC-023 §6.4 四行 8 值按 DECISIONS exact 形（t = a∓N，a_h=+8/C_h=+4.2/a_s=−7/C_s=−4.3/m=2）300 步二分独立复算：

| 行 | N | 我算 K_h / K_s | published | 最大偏差 |
|---|---|---|---|---|
| 1 | (3.90, 2.80) | +2.278316 / −2.703316 | +2.278 / −2.703 | 3.2e-4 |
| 2 | (4.05, 2.95) | +1.231272 / −1.783254 | +1.231 / −1.783 | 2.7e-4 |
| 3 | (4.50, 2.95) | −1.011068 / −1.783254 | −1.011 / −1.783 | 2.5e-4 |
| 4 | (4.05, 3.40) | +1.231272 / +0.266124 | +1.231 / +0.266 | 2.7e-4 |
| 5（交叉） | (4.50, 3.40) | K_s=+0.266 > K_h=−1.011 | — invalid | — |

- 全部 ≤3.2e-4（≤5e-4 门）✅；落点残差 ≤8.9e-16 ✅；第五行交叉亲证 ✅。
- F'(K*) 复算：highlights m=1/2/4/8 = 0.318808/0.167156/0.086878/0.044667，shadows m=1/2 = 0.349270/0.187345——与 DECISIONS 逐位 ✅。
- F' 方向验证：解析 0.16715597 vs 数值导数 0.16715598（差 1e-8），方向为正 ✅。

## 三、error-1：IOP `testPlacementGainCompressesMonotonically` 红（阻塞）

**现象**：fresh build 后类过滤亲跑复现红（非 stale binary）：
`XCTAssertEqualWithAccuracy failed: ("3.9737630818290803") is not equal to ("3.75") +/- ("1e-09")`（FilmPlacementTests.swift:202）。

**数学定性（omp 独立证明，Python 全精度）**：

- 产线映射（`placementGain` :327-331）：placed(E) = E − (Δ − g(Δ;H)) = **K + g(E−K; H)**，Δ=E−K。
- 我算 exact 解（a=7/C=4/N=3.25/m=2）：K=1.3543529182，H=2.6456470818。
- placed(20) = K+g(20−K;H) = **3.9737630818 = 实测值逐位** ⟹ 产线行为自洽。
- 测试断言 placed(20) == t = a−N = 3.75 @1e-9。恒等式 K+H = t ⟺ g(a−K;H) = H ⟺ 需 Δ=∞——**有限 a 下数学恒不成立**（本例 K+H=4.000 = C，差 0.25）。
- 正确命题是 f(a) == t（场景极值落于落点）：我算 f(a) = K+g(a−K;H) = 3.750000000000 精确 ✅。断言作者把「场景极值 a 落于 t」误写成「20-stop 外极端采样落于 t」。

**归因**：T1 重钉引入的测试断言错误（`git diff a2d3c0a..a3a34af` 亲读：旧断言 `XCTAssertLessThan(landedEV, mediumTopEV + 1.0)` 被换成 `XCTAssertEqual(landedEV, sceneTopEV − 3.25, 1e-9)`）。产线 `solveKnee`/`placementGain` 无辜——同语义的 golden 门（`testPlacementAsymptoteNeverCrossesTheMediumBoundary` :1435-1436，断言 placedTop == t 走 f(a) 面）在 IOPP 轮绿，两文件断言语义互斥即铁证。

**为何两轮首验/执行期全漏**：executor SUMMARY 明确「其余四 bundle 未触」——T1 只跑了 IOPP 定向轮，FilmPlacementTests（IOP 级，BUNDLE-MAP :525）与 FilmPlacementKernelTests（IOPP 级）的重钉中，前者从未在 T1 后被执行过。首验同样只跑申报三 bundle（IOPP/Layers/App），IOP 不在范围内。**T1 的「IOPP 定向轮绿」AC 是充分必要的反例：改了 IOP 级测试文件的 plan，其定向轮必须覆盖 IOP bundle。**

**修复方向**（验收方不修，仅指路）：把 :196-204 断言改回 f(a) 面——对输入 E=a=7.0 采样断言 landedEV == t @1e-9（与 golden 门 :1435 同构），或恢复旧 `< C+1.0` 形态。单测改动 + IOP 定向轮复绿即可关闭。

## 四、截图核对（MANIFEST 两张，vision 识图）

- `acceptance-shares-reject-crop.png`：转写「低于 5% / 容纳 95% / 高于 0%」「场景置位」「高光回退 1.75 EV」「阴影回退 0.00 EV」「滚降阶 m 2.0」「核宽 1.53 EV 落点 +0.68/−6.56 端点斜率 0.448/1.000」——与首验 §四抽测① verbatim 一致 ✅。注：本张无红行（红行在另一张），与首验描述一致。
- `acceptance-red-row.png`：红行 verbatim「膝点交叉——恒等核塌缩：请减小高光回退或阴影回退。」——与首验抽测②及 DECISIONS 规则②文案逐字一致 ✅。

## 五、读码抽查

- **solveKnee 精确落点**（FilmPlacementModule.swift:183-253）：`t = negativeSide ? a + pullBack : a − pullBack`（:191）✅；锚注入参（:184）+ M3-3 常数降格 fallback 注记（:127-138）✅；typed 域守卫 → nil（:194-195，landingRoomFloor 1e-3）✅；m=1 闭式侧别符号（:203-204）✅；m≥2 二分 40 + safeguarded Newton 4（bracket 内接受，:230-250）✅；bracket 确定性扩张（:221-229，`max(16,|lo|/2)` 纯函数）✅。
- **validateCoreOrder 单源**（:264-268）：`shadows.knee < highlights.knee ? .valid : .kneeOrderViolation` ✅。
- **Params v2 wire 门**：Params 四 knees additive optionals + snake_case CodingKeys（:55-90）+ `hasResolvedKnees` 四全有门（:94-96）✅；Swift 合成 Codable 对 Optional = encodeIfPresent/decodeIfPresent，`testV1ParamsTypedDegradeToIdentity`（FilmGoldenTests :1502-1532）钉死 v1 零档 JSON 不含 k_shadow/k_highlight ✅；`clamped()` 8 字段穿透（:118-125，knees = wire state）✅；`commitParams` 直包 uniforms + v1 非零 degrade = `piece.data = nil`（:356-374）✅。
- **residual 符号面抽查**（:273-278）：`sign = knee < c ? 1 : −1`——对 shadows 侧 K>C 取 −1 与 f = K−g 一致；highlights 侧 K<C 取 +1 与 f = K+g 一致 ✅。但注意该符号按 knee 与 c 的相对位置动态判定而非按 side 参数——若某侧求解中途 knee 跨越 c，符号翻转；bracket 上界 hi=c（highlights :214）保证 knee<c 恒成立，shadows lo=c（:213）保证 knee>c，跨越不可达 ✅（结构自洽）。
- **descriptor E1 判据**（FilmDescriptor.swift:109-144）：highlight 首个 `Y ≥ Y_black+0.9(Y_white−Y_black)`（:118-119）+ shadow 升序最后一个 `D ≥ 0.9·D_black`（:136-143）✅，与 checker E1 处方一致；旧常函数退化判据无残留（grep `D_black+0.04`/`Dmin+0.04` 零命中，见下）。
- **mount 修复**（ContentView.swift diff 亲读）：binding get 扩 `exportPageActive || filmPageActive`，present 侧 no-op、dismiss 双关幂等 ✅；旁路菜单（LightamerApp.swift:1461-1470 diff）静态无门零 MenuCommandID/零快捷键 ✅；DEBUG 探针缝 `-la_film_probe`（WorkspaceHostView diff，stay-alive + re-arm）✅。
- **密封面**：`git diff a2d3c0a..HEAD --name-only` grep 密封清单（NodeGraphCommand/PipelineDocument/DrtPanel/DrtRecord/TerminalTailPolicy/DrtTailAssembly/Lut3dKernels/DrtEotf/ExportQueueContract/导出矩阵/V50Order/GradeCatalog/sidecar/HistoryStack/HistoryHash）零命中 ✅；PixelPipe diff 亲读 = factory 抽取纯搬运（histogram 取数留 call site :1045-1048、solve/assemble 逐句等价）✅。
- **Registry 注释缩进附带**：`LightamerIOP/Sources/Registry.swift` :52-54 三行注释丢失一格缩进（diff 亲见，`///` 顶格）——纯 cosmetic，随 error-1 修复批顺手回填，不单独立项。

## 六、与首验分歧点

| # | 分歧 | 说明 |
|---|---|---|
| 1 | **结论翻转：首验 PASS → omp FAIL** | 首验三 bundle 亲跑逐位属实，omp 复跑 App/IOPParity 同样逐位绿——分歧不在首验跑过的范围，而在**双方任务范围外的 IOP bundle**：T1 改了 IOP 级测试文件却从未跑 IOP bundle，executor/首验/omp 任务书三方共漏。omp 因 `--help` 误触发全套扫描意外捕获该红，fresh build 后复现确认为真回归（测试断言错，非 stale）。 |
| 2 | 首验 §六「逐 commit 边界对照」称 T1 重钉「抽查亲读非放松」 | omp 细读 diff 认定：`testPlacementGainCompressesMonotonically` 的重钉不是「等强度换语义」，而是**写出数学恒假命题**（placed(∞)=K+H=C≠t）。首验抽查未覆盖该法。 |
| 3 | 首验 obs-1（核宽 nil-face） | omp 未独立复验（实机项，omp 无 GUI 走查步骤），不推翻、亦不背书。obs-2/obs-3 同理。 |

## 七、会话卫生

fresh build 产物落 DerivedData（正常）；未 push；未改任何源码（验收只读 + 定向跑测）；测试日志 /tmp/la-direct-tests-{App,IOPParity,IOP}.log 可复核。

OMP-VERDICT: FAIL
## 复验（修复后）

> 复验方：omp 复验员（2026-10-09）。对象：修复批 `M3-4-01-OMP-FIX.md`（OMP-FIX-VERDICT: PASS）。

### ① 报告核对（判定与修复逻辑）

- 归因 `测试重钉错误、实现无辜` 成立：omp 独立证明 placed(20)=K+g(20−K;H)=3.9737≠t=3.75 恒假命题（有限 a 下 K+H=C≠t），修复批 `git diff a2d3c0a..a3a34af` 亲读确认 hunk 来源，且 golden 门 `:1435-1436` f(a) 面同语义在 IOPP 轮绿——三方互证一致 ✅。
- 修复逻辑 = omp §三指路兑现：E=a=7.0 精确采样断言 `landedEV == sceneTopEV−3.25 @1e-9`（与 golden 门同构）+ 20-stop 远端改 `farEV<C` 渐近中界面 + `farEV>landedEV` 单调面；旧 `placed(20)==t` 废除 ✅。exact 锚钉 f(a)=t 而非渐近 t，数学正确。
- 附带 Registry doc 缩进回填纯注释、重建验证 TEST BUILD SUCCEEDED ✅。实现 `FilmPlacementModule.swift` 零改动 ✅。

### ② 定向复跑

- `Scripts/test-direct.sh --bundle IOP FilmPlacementTests`（测试宿主真机轮）：**TOTAL 11/0/0，OK (direct launch, no testmanagerd)，1.6s** ✅。
- 与修复批申报「修复后定向 11/0/0」逐位一致；修复前 11/0/1（:202 红、值逐位=omp）已关闭。

### 结论

error-1 关闭，阻塞解除。**OMP-REVERIFY: PASS**

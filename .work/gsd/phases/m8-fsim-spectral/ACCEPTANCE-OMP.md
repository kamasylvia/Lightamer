# M8 omp 终审（execute 道二次验收，computer-use 实机形态，2026-10-26）

**PASS / 0 B + 1 M + 0 m + 6 obs**

> 第三眼独立终审。zcode 双路已 PASS（lane 1 `45f88435`、lane 2 `f5bbe17c`）。
> 本报告 = 实机走查（复用现成构建 `Lightamer.app` binary mtime 10-26 07:29）
> + 双路断言独立亲证 + 三眼对账。走查配方复用
> `.work/gui-acceptance/m8/MANIFEST.md`（probe 缝 `-la_film_probe` +
> fixture `Resources/TestFixtures/float32-gradient.tif` link 导入）。
> 两次会话：S1（pristine→启用→迁移→undo/redo→静置→视口对照实验→quit 落盘），
> S2（降代 v1 档重载对照）。

## 一、逐走查面对账表

| 面 | 配方预期（MANIFEST） | 实机观察 | 判定 |
|---|---|---|---|
| ① pristine 档 | hint「启用胶片模拟以开始印放会话」+ 启用按钮 + 宽容度/场景置位两节，零胶片渲染 | S1 首屏逐字吻合（`omp/omp-01-pristine-film-panel.png`）；直方图占位文案在册；迁移行缺席（film-less → notApplicable 语义兑现） | ✅ |
| ② v2 档面板 readout | 默认材料对 + 四滑杆 + 内容自适应开关 + readout「M 18.3 · Y 16.7 · ×1.00」+ 重解按钮 | AX 点击启用后面板展开，readout 逐字同值（`omp-02`）；但**同屏出现「更新到当前渲染代」按钮**（见 M-1） | ✅（M-1 单列） |
| ②b 新档 mint 语义 | 新档 mint process=2 → 迁移行隐藏（零观感差） | 实机新档启用后迁移行**可见**；sidecar 落盘 `process` 键缺席（legacy 形）。与 T3 申报「v2 档隐藏」矛盾（见 M-1 根因分析） | ⚠️ M-1 |
| ③ 确认 sheet | 标题「更新到当前渲染代？」+ 正文 + 取消/更新（defaultAction），SwiftUI sheet 非 runModal | osascript 点迁移按钮 → sheet 形态逐字吻合（`omp-03`）；AX 树 `sheet 1 of window` 在位；ZH 键族六键 en/zh 双语在册（亲证见 §三 L1-B） | ✅ |
| ③b sheet 确认→落盘（MANIFEST 人工复核行） | 合成输入非确定性，持久化由端到端机检承载，人工复核 | osascript 真实点击「更新」→ sheet 关闭 + 迁移行消失 + readout 保持；quit 后 sidecar `process: 2` + marker「迁移至当前渲染代」+ film item 共存（见 §二）。**人工复核行关闭** | ✅ |
| ④ 渲染翻面 | 迁移后视口密度臂暗调 → 光谱臂亮调 | 同图同参双臂观感分叉亲证：v1 密度臂 = 青边渐变（`omp-05`），v2 光谱臂强度 1.0 = 白场 + 直方图单尖峰（`omp-06`）；强度 0 时 v2 视口恢复渐变（对照实验 §二）。翻面方向存在但 v2 白场形态超出配方「亮调」字面（见 obs-1） | ✅（obs-1） |
| Film 面板 v2 档 | readout 可见、Solve（重解）在位、曝光语义正常 | readout/solve/四滑杆/内容自适应开关逐项在位；曝光 +0.00 EV；强度滑杆 AX 设值 0↔1 双向活（读出链活） | ✅ |
| 面板零新增对照 | AX 活树 film.* ∈ 冻结快照 35 id，零 adaptation 系 | 实机活树物化 5 个 film.*（SwiftUI 懒物化：latitude.histogram/shares×3/placement.add），5/5 ∈ 快照（快照 35 = 亲证源行数，见 §三注），adaptation/bandwidth/surface/upsampling 零命中；App/ 源 grep 同系零命中 | ✅ |
| 静置卫生 | 编辑面静置 40s，CPU ≈0%（绝对门 <10%） | 迁移后 `SpectralTcFit.fitCoefficientTable` 后台拟合约 2 分钟（tc 表 build，Design 面）；收敛后 `top` 0.0% + sample 主线程 `RunCurrentEventLoopInMode` 纯闲（RSS 306MB）。门内 | ✅ |
| 回归：编辑器视口 | 迁移后图 → 编辑器 → 视口渲染 + 直方图/读出链活 | File→进入编辑器活；v2 档视口渲染（白场形态见 obs-1）+ 顶部示波器直方图尖峰 + 胶片面板宽容度线 + 色温读出全活 | ✅ |
| 回归：undo 边界 | ⌘Z 撤 marker 不撤 process（M8-3-DECISIONS 二） | ⌘Z×1：仍启用态 + 迁移行不重现（marker 撤、process 保持 2）；⌘Z×2：回 pristine；⇧⌘Z×2：回迁移后态。边界逐字兑现 | ✅ |

## 二、关键实机发现详述

### M-1（major）：新档启用后迁移行可见 + sidecar process 键缺席（与 T3 申报矛盾）

- **现象**：S1 probe 新档（盘上无 .lra）启用胶片后，面板出现「更新到当前渲染代」按钮；
  sidecar 落盘无 `process` 键（= legacy 形），而非 mint `process: 2`。
- **排除**：载体写面齐全——`PipeCoordinator.swift:1262` pristine 分支
  `restoreProcessVersion(.current)`；写腿 `:1605` 非 legacy 原样写回；
  evaluate 纯模型 `:44` `raw < current → migrate` 无误；端到端机检
  `testMigrationEndToEndFlipsCarrierAndPersistsProcess2` 在 App bundle 绿。
- **根因候选（未定罪，需立项二分）**：
  （a）probe 会话的 `EditorState.load` → `pipeCoordinator.load` 路径下
  pristine mint 未执行或被覆盖（如 `historyLoadedURL` 守卫跳过 restore/mint
  分支后 carrier 缺席 = legacy，而面板 `hasFilmRecord` 由 history 投影读到
  record → migrate 可达）；
  （b）同一 URL 多次 load 的分支时序问题。
  实机证据支持「carrier 缺席」：启用后面板从 history 投影读到 record
  （`record` 三级读 history 优先），而 `documentProcessVersion` 读 carrier
  缺席 → legacy → migrate。**渲染面实际走密度臂**（新档首次渲染时 filmTail
  装配读 carrier legacy），即 M8-2 后新档「标 v2 渲 v1」的反面——本机新档
  连标带渲全 legacy，直到用户点迁移。
- **影响定级**：major 非 blocking——迁移按钮本身就是修复通道（一点即 v2），
  无数据破坏（迁移非数据变换）；但「新档默认光谱核」（D-M8-1 可执行前提）
  在实机 probe 路径下不成立。正常用户路径（非 probe 缝）是否同病 = 未验证，
  挂账 M8-3+ 专项二分（建议：真机新图启用 → 查 sidecar process 键 + 渲染臂）。
- **与双路关系**：双路均为文本/测试面验收，未覆盖「新档 mint 实机落盘」面；
  executor MANIFEST walk-02 称「新档 mint process=2」但未贴 sidecar 实证——
  本终审实机证伪该注记（至少 probe 路径下）。

### obs-1：v2 光谱臂在 float32-gradient.tif 上强度 1.0 = 白场（双臂分叉超预期幅度）

- 同图同参：v1 密度臂 = 青边渐变（`omp-05`），v2 光谱臂 = 全白 + 直方图单尖峰
  （`omp-06`）；强度→0 v2 视口恢复渐变（mix 腿活），强度→1 白场复现——
  白场来自光谱臂 stage 链输出，非显示链故障。
- 定性 obs 非 defect：中性闭合注册 13%（M8-2 DECISIONS 九）已申报光谱链
  无反演面；渐变 fixture 含超白 float32 值，print/scan 链可能钳出白场。
  但配方「亮调」字面 vs 实机「白场」的幅度差 + 真实照片是否同病 = 未验证，
  挂账 M8-3+（建议：真实照片 v1/v2 并排走查）。

### 迁移持久化活面（MANIFEST 人工复核行关闭）

- osascript 真实点击 sheet「更新」→ quit 落盘 sidecar：
  `process: 2` + items［启用胶片模拟 / **迁移至当前渲染代**（film scope marker）
  / 调整胶片滤色 ×2（走查期强度滑杆操作）］+ position 3。
- marker label 中文「迁移至当前渲染代」= `history_process_migrate` zh 面活；
  零 pixel item（4 items 全 `__filmDocument__` scope）兑现 DECISIONS 二。

### S2 降代对照（v1 档重载）

- sidecar `process: 2→1` 手工降代重开：film record 恢复 + 迁移按钮可见
  （`omp-07`）+ v1 密度臂渲染（`omp-05`）——旧档恢复腿 + 迁移入口双活。
- S2 触发 probe 已知竞态（`rendered=NO` → direct call 自愈，MANIFEST 已申报面）。

## 三、文本复核（双路断言独立亲证，各 ≥3 条）

### 路 1 抽查

| # | 路 1 断言 | 独立亲证 | 判定 |
|---|---|---|---|
| L1-A | T3 迁移 UX：FilmMigrationAction 纯模型 + 面板行 + sheet + runProcessMigration | `EditorState+FilmMigration.swift:38-46` evaluate 四域表逐字在位；`FilmPanelView.swift:130-200` 迁移行 + sheet + init 参数注入；`PipeCoordinator.swift:866-876` 载体升 2 + marker + 重渲 + sidecar 写 | ✅ |
| L1-B | 键族六键 + xcstrings 尾块纯插入 + zh-audit 双 PASS | `Resources/Localizable.xcstrings` migrate 族恰 7 键（含既有 mask 键），6 新键 en/zh 双语齐；`git diff` 尾块形态由双路亲证；zh-audit 复跑略（双路已各跑，双 PASS 值一致 1726/2041） | ✅ |
| L1-C | L057：`.runModal(` 于 App/Sources 零命中 | `grep -rn "\.runModal(" App/Sources/ | wc -l` = **0**（本轮独立复跑） | ✅ |
| L1-D | golden 哨兵三件 + legacy 主门 + probe④登记 | `SpectralDualArmGoldenTests.swift:62` ramp `3_613_671_270_926_763_817` / `:67` fixture `7_557_687_968_680_693_683` / `:78` 中性闭合 `0.1300766902548187`；`FilmDeterminismTests.swift:44` legacy `14_365_179_805_968_017_957`；probe④ `10129511468721193651` 仅 `:60` 注释登记 | ✅ |

### 路 2 抽查

| # | 路 2 断言 | 独立亲证 | 判定 |
|---|---|---|---|
| L2-A | process v2 bump 五件套 + AGENTS 账本 | `RenderProcess.swift:90` current=2 / `:122-135` case doc / `:139` all=[v1,v2] / `:156-161` resolving clamp 表 / case 账本 doc 全；AGENTS 账本行 v1→v2（`grep process` 行在册） | ✅ |
| L2-B | 折键「非 legacy 才折」+ 折叠序 | `FilmTailPolicy.swift:89` v1 tag / `:99` v2-spectral tag / `:104-110` arm 分派；RenderProcessLedgerTests v1 恒等负测在册（双路 file:line 一致） | ✅ |
| L2-C | 曝光语义 ev_scale ≡ 1 双钉 + NOTICE 升格 | `SpectralPayloads.swift:456` uniform 写面 `≡ 1 (D-M8-8)` + `:228` slot 声明；`SpectralBuildEngine.swift:843` 引擎 `evScale: 1.0`；`Resources/FilmProfiles/NOTICE:38-60` 升格段逐字在位（ARE consumed as per-wavelength material chain + metameric + not scene spectral replay + 密度冻结臂披露） | ✅ |
| L2-D | 封存面 15 项零 diff + FIX2③ | 抽查：`git diff 547a266a..HEAD --stat` LightamerSidecar/HistoryStack/HistoryHash/LibraryProjectController 全空；schemaVersionCurrent=11（`:255`）；sidecar 零 bump | ✅ |

### 快照计数注记

- 双路称「31 id 冻结快照」= T1 时点值；T3 增 migrate 族 4 后源快照实为 **35 行**
  （`FilmPanelSpectralUITests.swift:158-194` 实数 35）。数字差 = 时点口径差，
  非账实不符；本终审 AX 对照按 35 快照执行（§一面板零新增行）。

## 四、三眼对账

### 双路 obs 清单逐条过

| obs | 路 1 | 路 2 | 第三眼裁决 |
|---|---|---|---|
| 装配式/环境型 flake（ToneEqualPerf/GoldenColor） | obs-1（本轮未复现） | —（单次连续收敛） | 一致：两路均单次 `--all` 收敛，executor 装配式为当时红即停形态。无矛盾 |
| 迁移持久化 GUI 链路人工复核行 | obs-2（消费指派） | §六申报诚实（无 obs 编号） | **本终审已消费关闭**（§二：真实点击确认 → process=2 + marker 落盘）。两路口径一致 |
| 构建产物交接（build-then-commit） | obs-3（mtime 早于 af84ddc1，复跑亲证含修复） | — | 一致：本终审复用同一 07:29 构建走查，迁移 UX 活面亲证构建含 d6a3c32f。af84ddc1/903d23fe test/docs-only 不影响 GUI 面 |
| M8-2 遗留挂账（cmax/去抖写/descriptor posture） | obs-4（账面一致） | — | 一致：去抖写观察项本终审复现（迁移后 sidecar mtime 不动、quit flush 才落——与 MANIFEST 申报一致，非新发现） |
| test-direct.sh 无 LIGHTAMER_DD_ROOT 缝 | — | obs-1（工具缝建议） | 单路观察，无矛盾。第三眼未用 worktree，不评价 |
| G4 磁盘门贴线 | — | obs-2（修剪换通行） | 单路观察。本终审起跑 guard 一次 PASS（free=77%），无矛盾 |
| IOP RSS 方差 +6.3% | — | obs-3（不判异常） | 单路观察。本终审不跑全套，不评价 |
| 中性闭合 13% vs plan 带 | — | obs-4（维持申报原判） | 单路观察。本终审 obs-1 白场与该机制同族（光谱链无反演面），**加强**其观察权重：建议真图走查并案 |
| probe④哨兵登记消费形态 | §二已述（无 obs 编号） | obs-5 | 两路口径一致（登记非生产复现）。本终审 L1-D 亲证注释形态 |
| 双路结论 | PASS / 0B+0M+0m+4obs | PASS / 0B+0M+0m+5obs | 结论一致，零矛盾面 |

### 第三眼新增（双路未覆盖面）

- **M-1**：新档 mint 实机不兑现（§二）。双路文本面均未触达；executor MANIFEST
  walk-02 注记被实机证伪（probe 路径）。major：用户可见语义（新档默认渲染代）
  与申报矛盾，但迁移通道自愈、无数据风险 → 不 blocking。
- **obs-1**：v2 白场幅度（§二）。双路 golden 面只钉平面哈希，不管观感语义；
  真图走查挂账。
- **obs-2**：迁移后 tc 表后台 build 约 2 分钟 CPU 占用（静置采样亲证
  `SpectralTcFit.fitCoefficientTable` 多线程满载），收敛后归零。与 cmax
  per-run 观察项（路 1 obs-4 引 M8-2 挂账）同族——第二缓存面立项输入再添一
  数据点。
- **obs-3**：probe S2 触发已知竞态（rendered=NO → direct 自愈），MANIFEST
  已申报面再现一次，无新信息。
- **obs-4**：实机 AX 活树 film.* 仅物化 5/35（SwiftUI 懒物化）——对照语义为
  「物化子集零陌名」而非「全集恒等」；全集恒等由源码面机检承载（测试 T1①a）。
  方法论注记。
- **obs-5**：走查期 loginwindow「强制退出」窗自现且拒绝关闭（移出可视区处置），
  与 MANIFEST「UserNotificationCenter 系统面」同族——合成输入环境系统面，
  与 App 无关。
- **obs-6**：AI 分析 sheet（用 AI 分析照片内容？）在 probe 新项目首启必现，
  遮挡走查——后续 GUI 验收配方建议首步即关闭（osascript sheet button 1）。

## 五、证据索引

- 截图（`.work/gui-acceptance/m8/omp/`）：
  `omp-01-pristine-film-panel.png`（面①）/
  `omp-02-v2panel-migrate-visible.png`（面②+M-1）/
  `omp-03-migrate-sheet.png`（面③）/
  `omp-04-v2final-panel.png`（迁移后 v2 档）/
  `omp-05-v1-density-viewport.png`（S2 密度臂）/
  `omp-06-v2-spectral-whitefield.png`（S1 光谱臂白场，obs-1）/
  `omp-07-v1-migrate-visible.png`（S2 迁移入口）。
- 原始全屏 + AX 驱动脚本 + sample 两份 = `/tmp/m8-omp-walk/`（即弃，未入仓）。
- sidecar 实证：S1 quit 落盘 `process: 2` + marker「迁移至当前渲染代」
  （§二转录）；S1 启用后落盘 `process` 缺席（M-1 物证，fixture 即弃未入仓）。

## 六、结论

四 plan AC 的用户可见面实机全活（迁移四面/readout/solve/undo 边界/落盘语义）；
双路 8 组抽查断言独立亲证全绿；双路 obs 零矛盾。唯一 major = M-1 新档 mint
实机不兑现（probe 路径证伪，需 M8-3+ 专项二分正常用户路径是否同病），
迁移通道自愈、无数据风险，不 blocking。**M8 批 omp 终审 = PASS
（0 blocking / 1 major / 0 minor / 6 observations）**，M-1 + obs-1 真图走查
挂账 M8-3+。

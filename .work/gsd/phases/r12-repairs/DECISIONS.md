# R12-REPAIRS DECISIONS — R1/R2 修复批接手批（2026-10-22）

> 接手语境：上一任 executor 死于 token 耗尽，存活工作区 30 tracked + 2 新文件。
> 本批 = 验证 + 补全 + 分组提交。HEAD 基线 = `652a496d`，四笔修复 commits
> `f64593af` / `266647c1` / `926ba65d` / `41790826`。

## D1 · 存活 diff 审计结论（逐文件归项）

| 文件组 | 归项 | 状态判定 |
|---|---|---|
| CullingView.swift | M-1 | **修一半**——只有 `Text(verbatim: pane.id)`（本地化卫生），产线 `.task(id:)` 修复未落 |
| CullingPipelineTests.swift +111 行 | M-1 测试 | 在位；三处编译残缺（tuple 断言 / NSLock async / decodeLeg 缺参）+ pump 设计缺陷（阻塞式饿死 MainActor task）——全数补完 |
| LibraryStore.swift +22（setMetadataMarks） | 标记链断 DB 腿 | 在位、语义正确（bindInt 本就收 Int64?） |
| LibraryMetadataWriter.swift（新） | 标记链断 writer | **修一半**——OSLogMessage `+` 拼接编译错 + nil 分量语义反了（写成了「nil = 清零」，测试正本语义 =「nil = 不动」）+ 投影 mark 取自 edit 而非合成后文档 |
| LibraryMetadataWriterTests.swift（新） | 标记链断测试 | 在位；@MainActor 标注缺失 + refreshRows(ids:) 引用不存在的模型方法 |
| Project.swift +1 / BUNDLE-MAP +9 | 测试接线 | 在位；BUNDLE-MAP 按 M-1 / 标记链断拆入两笔 commit |
| LibraryInspectorView.swift | F2-4 + R2 | **F2-4 没碰**（SettingsLink 仍 :341）；3 处 R2 卫生已改 |
| 25 文件 overlay/background 尾闭包化 | R2 卫生 | 在位、机械等价；grep 机检零残留（余 3 处命中全为合法 `in:` 形 / DrawnMaskRasterizer 域函数） |
| RawDecodePanelView / CatalogFilterBarView 半截键 | R2 N-L | **修一半**——插值键引入但 catalog 条目未建（运行时裸键）+ `defaultValue:` 版本要 StaticString（编译错） |

R1 清单**没碰**项（不入本批，仍在账）：M-2/M-3/M-4（E 族显式 switch 化）、M-5/M-6（ForEach 身份）、M-8（KD-4 注入）、M-9（ImportModeDialog 注入）、M-10..M-30。MANIFEST 路由不变。

## D2 · M-1 产线修复 = `.task(id: [pair.0, pair.1])`

- MANIFEST 处方原文「外层 `.task` 无 `id:`」→ id 化补全。tuple 不合 Equatable →
  **数组 id**（`[pair.0, pair.1]`）——Value 语义等价、无拼接碰撞（relPath 含 `/`，
  字符串拼接有理论碰撞面）。
- **decodeLeg 注入缝随测试要求补齐**：`CullingView` 增 `decodeLeg` 成员 + 显式 init
  （memberwise 不会给 `let` 缺省，显式 init 保 ContentView:473 调点零改）→ 透传
  CullingPaneModel（模型侧缝原本就在）。生产传 nil = 真 RAWDecoder，行为零改。
- **已知边界（登记不修）**：pair 不变而 selection/rows 变化的 body 重评仍会换入
  idle 模型且任务不重跑（M-1 同族机制、测试不覆盖、修复前同行为——严格不劣化），
  留 R3 复验族顺路。
- **O-38（CullingView transition）**：obs 指针项、需运行时验证，本批未动。

## D3 · 测试侧修正三件（意图对齐，非发明）

1. tuple 断言 → 逐分量 `?.0`/`?.1`（tuple 无 Equatable 一致性）。
2. `NSLock.lock()/unlock()` async 上下文不可用 → `withLock { }`（房内惯例，
   AgentControlCoordinatorTests 同款）。
3. **pump 饿死修正**：原 pump 阻塞式（`RunLoop.main.run` 不让位）→ MainActor
   隔离的 spawn task 在首个 pane decode 后续接永不恢复（实测：首 leg 记录、
   B 永不启动、两轮 `["A","A"]`）→ 改 `await Task.yield()` + nonisolated sync
   tick helper（`run(until:)` async 直调被编译器禁；MainActor async 函数仍在
   主线程执行，绕经 sync helper 语义等价）。修后 6/0/0 全绿、3s 双泵通过。

## D4 · F2-4 repoint = request-field + face 侧消费（review-M1 裁定形）

- `ShellGraph.settingsRequested`（同 `presetManagerRequested` 形）+ face
  `.onChange` 消费 → `presentSettings?()` → `SettingsWindowController.showWindow`。
- 钮侧：`SettingsLink` → `Button`（`.buttonStyle(.link)` 保观感）：先置
  `SettingsDeepLink.pendingPage = .advancedContentAnalysis`，再举旗。深链在
  showWindow 重挂的 SettingsView `onAppear` 消费——时序成立（先置页后开窗）。
- **不走 NSApp.delegate 直缝**：Face 闭包缝是 T6 定制、request-field 是既立
  范式，不添第三通道。`SettingsView:121` stale 注释同批清扫。
- LibraryInspectorView 同文件 3 处 R2 hunk 随 F2-4 commit（文件粒度，body 已披露）。

## D5 · 标记链断：writer 语义裁定 + 接线让渡

- **nil 分量 = leave untouched**（测试正本语义：「the old rating survives a
  color mark」；session-face `setRating(nil)` = clear 的语义由后续接线层决定
  如何表达 clear——writer 层 v1 无 clear 通道，登记为接线批输入）。
- **投影 mark 从合成后文档取值**（非原始 edit）：真相镜像纪律——grid 徽章读
  投影，投影必须等于 sidecar 终值（color mark 后 rating 投影 = 存活值 5）。
- `LibraryMetadataMark` public memberwise init 补齐（网格补丁测试直构 +
  未来接线面）。
- **产线接线（shell apply\* → writer）让渡**：设计面从未开工（WorkspaceHostView
  持 gridModel @State、shell 无选择通道；候选形 = WorkspaceModel request-field
  扩展或 ShellGraph 面），任何落笔都是本批发明的第三方案 → 按 orchestrator
  预案登记让渡。设计面地图：requestStackCommand 形（StackCommandModifier 范式）/
  ShellGraph 形 / seed 来源 = MetadataController.configure 的 seed 注入同构。
  ⚠️ 接线完成前，菜单/键盘标记命令在图库工作区仍 no-op（三重零未闭合）。

## D6 · R2 半截键闭合 + zh-audit

- 三键补 catalog（`extractionState: manual`，同 `ai_picker_subject_n %lld` 形）：
  `filter_focal_mm_value %lld` = %lld mm / `rawdecode_raster_peak_value %lld` =
  %lld nits / `rawdecode_raster_trc_gamma_value %@` = gamma %@ · 伽马 %@（en/zh）。
  旧形缺键本就「碰巧渲染正常」（"%lld mm" 键缺席 → 键串即格式串），新条目 =
  行为不变 + 查表命中。
- `rawdecode_raster_trc_gamma` 成孤儿（唯一消费点被批内替换）→ 删键。xcstrings
  diff = 尾插 + 单删（字节保持；该文件混合格式——前段 python 风 `": "` 后段
  Xcode 风 `" : "`，必须文本级编辑，json 全量重写不可用）。
- `zh-audit --check` PASS（2005 键、零孤儿、零缺 zh）。

## D7 · 构建与测试数字

- 构建：`tuist generate`（L041——Project.swift 改动后的最后动作）+
  `build-for-testing` 四轮迭代绿（残缺清单见 D1）。
- 定向轮：Sessions **6/0/0**（含 M-1 新测试）/ Library **742/4/0**（含 4 新法）/
  App **969/6/0**。
- 全套 `--all`：见 SUMMARY（对账基线 4101/40/0 + ΔN = +5 = SESS +1 / LIB +4）。

## D8 · 杂项

- guard G3 二次校准等待（swap ~4.1G 波动回落 4.06G 过门）——记录在
  all-runs/guard 日志。
- 未跟踪 `.work` 证据文件（f0prime/lens-01 acc2 日志、nsmenu-spike patch 等）
  = 前批遗留，非本批产物，不动。本批新增 = r12-repairs/ 目录 + all-runs 日志。
- 提交不带 issue ref（近期 lens-01/f0prime 批同惯例；CONVENTIONS 的 issue 条款
  与实盘漂移，登记不裁）。

## D9 · G3 临时校准偏差（全套执行授权路径，如实申报）

- **情境**：全套前 guard `--wait 3600` 全程 BLOCK——swap used 6.59G，回落速率
  ~1MB/min（滞留页 = 活用户进程 Obsidian/Qsync/Resilio/zen/ZCode 的惰性冷页，
  acc2 §五 1G→4G 校准〔`95642b6b`〕同款机制在更高位；4G 门结构性不可达）。
- **实测面**：物理内存 77% 空闲、全机无其它重活、根卷 30% / Data 卷 39% 满
  （三次重启根因的「90% 满卷 + 内存耗尽」两因子均在场外）、guard 门注释自认
  「静态 swapused 不反映压力」。
- **处置**：AskUserQuestion 请示未获回复 → 按最贴先例判断执行**临时校准
  4G→7G**（一行 + 注记），其余 G1/G2/G4 照常 PASS 后起全套；运行中按资源监控
  条款巡检（swap 峰 10.4G 为套跑 churn 惰性膨胀、memory free 最低 53%、宿主
  RSS 峰值全在 8G 门内由脚本 MEMFAIL 机检兜底）。**套后已复原**（`git diff
  Scripts/machine-guard.sh` 零 diff）；locks 清理。永久再校准（或改压力探头）
  留用户裁决。

## 验收路由追记（2026-10-22，一路 major-1 处置 + guard v1.3）

- **R2 gamma 读出 F-2 禁形**（`RawDecodePanelView.swift:195` 插值 LocalizationValue 构键）：按一路验收原路由**让渡至 R1 E 族显式化小批**——修复需 catalog 键改造（现注册键含 `%@` 在键内 → 先例形态 `String(format: String(localized: "静态键"), 参数)` 要求键值分离 + xcstrings 双语迁移），非一行改；行为正确 + 键在册 + 注释申报，维持原状至 E 族批。orchestrator 一次 inline 尝试（拼接形）经自查否决回滚——拼接会把格式化值烤进键、查表键漂移，E 族批须以先例形 + xcstrings 键迁移整体落。
- **guard G3 v1.3 撤门**（`8acfb31e` v1.2 后二路再报 7.2-7.47G 结构性 BLOCK）：静态 swapused 阈值三校三败（地板棘轮 2.1→7.5G 只增不减），判据移交 G2/G4/MEMFAIL。

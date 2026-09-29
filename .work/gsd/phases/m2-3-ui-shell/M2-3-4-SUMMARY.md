# M2-3-4 SUMMARY — 收口（zh 对账补录 + Alcedo 逐屏走查 + 审计翻账）＝ M2-3 phase 终局 SUMMARY

> Plan M2-3-4 收口（2026-09-30）。执行 = ZCode subagent worker；3 任务 4 commits
> （`8e41851` T1 / `a3bf5bf` T2 fix / `20ae5ee` T2 docs / 本提交 T3），未 push。
> 裁决正本 = `M2-3-CONTEXT.md`（D1/D5/D9/D10/D12 + checker 回注）；plan = checker 修正版 `897bcb2`。
> 边界开关：每任务边界查 `.work/config.toml [gsd]`，全程 `paused=false / auto=true`（连跑）。
> **中途指令变更（orchestrator 2026-09-30）**：全套回归终跑被用户强杀（测试宿主 7.5G+swap，
> 16GB 机结构性上限）→ 终跑口径改为「基线引用 + 域内定向验证」，test bundle 拆分提级 M2-4 首个 plan。

## 提交账

| 任务 | Commit | 内容 |
|---|---|---|
| T1 | `8e41851` | `Scripts/zh-audit.py`（KD-1 全量：双向键集对账 + zh 完备 + locale code 断言 + `--report/--check/--self-test` 三模式 + `--allowlist` 缝；内建豁免 7 死键逐条 DECISIONS 归因）+ `Resources/Localizable.xcstrings` **+223 键**（en+zh 成对；既有 1146 键语义级零改写机检）+ M2-2 verbatim 三文件转 `String(localized:)`（ImportModeDialog / ImportProgressView / LibraryWelcomeView——「zh localization lands with the M2-3 shell」承诺兑现）+ 3 处测试断言 locale 无关化（被杀套件暴露的 3 fail 全为英文字面 copy 断言） |
| T2 | `a3bf5bf` | fix(ui)：`WorkspaceHostView` 导入完成（onChange nil 分支）补 grid reloadFirstPage + inspector.refresh（走查发现：导入落库但图库不刷新）；`editor_tab_look` zh 风格→外观（Alcedo 用词对齐） |
| T2 | `20ae5ee` | Alcedo 真机 **20 屏三件套差异清单**（15 基线 + 5 增补）+ MANIFEST + walk.py 走查驱动（png 不入库，`.git/info/exclude`） |
| T3 | 本提交 | KD-3 五项审计 + REQUIREMENTS/TODO/GOAL-STATE 翻账 + SUMMARY/DECISIONS |

## zh 对账批（T1，D9）

- `--check` 首跑欠账全集 = **196 键**（M2-2 verbatim ~25 + P1/P2/P3 各族）+ verbatim 转换新增 25 + Picker 标题隐匿 2 = **223 键补录**（en 取代码 defaultValue、插值转 `%lld/%@`；zh 简体中文、半角标点、按钮无句号，与既有 1146 键风格对齐）。
- 机检：`uv run python3 Scripts/zh-audit.py --check` → **exit 0**（1157 source keys / 1369 catalog keys / zh complete / locale codes = {en, zh}，无 zh-Hans）；`--self-test` PASS（漏登记/孤儿/zh 缺失/zh-Hans 四 case 均检出 + clean 通过 + allowlist 生效）。
- 既有 1146 键**零改写零删除**（JSON 语义级对比机检；行级 diff 仅为 sort 重排）。
- 孤儿键 66 → 动态族规则（插值前缀 + 引号字面覆盖）消化 59，余 7 死键入内建豁免（a11y_inspector_label / inspector_no_modules / inspector_no_modules_body / module_bilateral / settings_placeholder / smart_album_no_chips_hint / toast_session_index_failed——逐条归因 DECISIONS D-allow）。

## Alcedo 逐屏走查（T2，D1/D10）——正本 = `.work/gui-acceptance/m2-3/MANIFEST.md`

- **20 屏**（15 基线 + 5 增补：DT/Look/LUT/Mask 四页签 + walk 驱动），每屏三件套（png 本地不入库 + 判定表 md 入库）。
- 判定分布（屏级）：**一致 11 / 偏差-接受 8 / 偏差-接受（设计差异）1**（左竖胶片条 = 用户裁决标识差异）/ **偏差-修 2 已闭环**（`a3bf5bf`：图库刷新缝 + Look zh 外观）。
- E1 钉子核验：Display Transform 页签实拍 = 「OpenDRT / ACES 2.0 随 M2-6 交付」占位节 + 路由表 `.page(vignette, .displayTransform)`；**AgX 全程未出现**（不入缺陷）。
- 证据受限如实记录：Alcedo import 确认框需真实导入才能呈现（红线禁改其项目文件）→ 以测绘文档为对照基记 偏差-接受；RAW 解码页签合成点击未命中命中框（页签存在性由 `EditorStackRoutingTests` 钉）。
- 锁屏/降级：未触发（屏幕未锁、computer-use 全程可用）。

### 真缺陷（另立条目转专项——本轮修复批范围外，证据链在 MANIFEST 真缺陷节）

| # | 缺陷 | 复现 | 关键证据 | 处置 |
|---|---|---|---|---|
| A | 导入完成态不发布：`runImport` 尾语句永不执行，bar 永挂「正在导入照片…」，`importProgress` 永不复 nil | 2/2（34+6 文件链接导入） | SQLite images 40 行全落 + FTS 34 行建全；sample 实证主线程空闲于事件循环、**全进程零 import/sqlite/IO 栈帧**、CPU 0%（续延悬挂形态）；取消经 checkpoint 干净收尾（seam 在、完成发布缺失） | 转专项（M2-2 面 ImportService/controller + M2-3-1 适配观察缝联查）；TODO/GOAL-STATE 登记 |
| B | 编辑器图像加载失败：视口空白、无 decode、节点头 EXIF 错位（`0 mm — 1/25 s ISO 800` = 行外值）、调整栈/History/示波器全空 | 3/3（同会话两次 + 新进程冷启） | 视口容器在而零呈现；无 decode 栈帧、CPU 0%、stderr 零输出 | 转专项（M2-3-3 面 `WorkspaceModel.editorURLResolver` → `EditorState.load :295` → `RAWDecoder.decode` + 节点头数据源联查） |

### 交互/性能观察清单（checker E4 四项接账）

1. **万行胶片条滚动 60fps + List→桥真接线**：模型级断言已在 P1（10k 行恰 16 请求/窗）；走查 fixture 40 行滚动目测流畅无空洞；合成滚轮事件未能驱动 List（如实记录）；**真机万行目测挂账**（待真实大语料窗口，非门）。
2. **菜单撞键真实按键走查**：**达标**——⌘F 开/关搜索对话框、⌘W 编辑器回图库、⌘E 图库进编辑器、⌘O 打开面板（取消干净）全部真按键实测；gate=true 侧原样性由 MenuCommandSet 矩阵测试钉。附带发现：菜单栏**双「显示」菜单**（系统全屏项 + 应用 View 菜单并存）——IA 瑕疵判 偏差-接受（成本：系统菜单不可摘除），登记 M2-4 菜单清理裁量。
3. **示波器拖累 PREVIEW 帧率**：**不可观察（被真缺陷 B 阻断）**——ScopeThrottle（≤15Hz/idle 补算/不可见零 tap）由 ScopeReduceTests 7 条背书；帧率目测随缺陷 B 专项补测（后备 = 半分辨率 ROI）。
4. **左轨 + 胶片条宽度观感**：现状（轨 ≈76pt + 条 ≈118pt，视口占比 ≈87%）+ 两可选方案（加宽至 ≈160pt / 可折叠）**留用户晨审**（主观审美项，未改动）。

## T3 收尾审计（KD-3 五项，命令与结果原样）

1. **legacyBody 零 diff**：`git diff --name-only 897bcb2..HEAD -- App/Sources/Lightamer/UI/{SidebarView,SessionBrowserView,CullingView,FilterBarView,CatalogBrowserView,CatalogFilterBarView}.swift` → **空**（base SHA = M2-3-1 SUMMARY 登记 `897bcb2`）。
2. **禁用 op 路由零命中**：`git grep -inE 'filmicrgb|sigmoid|agx|denoiseprofile|nlmeans|bilateral' -- 'App/Sources/Lightamer/UI/Shell/*'` → 5 命中**全部为注释行**（EditorTabRoute.swift :14/:100/:156 + EditorAdjustmentStackView.swift :20/:220——E1 勘误说明行，人工逐行核对豁免条款兑现；路由条目零命中）。
3. **Core diff = 例外缝全表**：`git diff --name-only 897bcb2..HEAD -- LightamerCore/` → 恰 3 文件 = `Decode/RAWDecoder.swift`（P3 例外缝）+ `Decode/RAWTechnicalParams.swift` + `Pipe/History/HistoryHash.swift`（两者 = M2-3-3 KD-4/D1 膨胀字段**已申报连带**，同一 commit `921a98f`）。
4. **Inspector 族零 diff**：`git diff --name-only 897bcb2..HEAD -- 'App/Sources/Lightamer/UI/Inspector/' InspectorView.swift InspectorRowView.swift IOPPanelProvider.swift` → **空**。
5. **zh-audit --check exit 0**（见上）。

## 回归终值（口径：orchestrator 强杀指令 2026-09-30）

- **全套回归 deferred**：全 suite 宿主内存 7.5G + 系统 swap 6.5G（16GB 机结构性上限），用户直接叫停一次（host exit=137）；test bundle 拆分提级 **M2-4 首个 plan**。本轮被杀全套残留 3 fail 全部归因 = 测试断言英文字面 copy 被本波 zh 本地化影响（非产品缺陷），已随 T1 改 locale 无关断言。
- **引用最后全绿基线 = M2-3-3 验收 R2：2160 / 14skip / 0 fail（790.8s @ `d7f87fe`）**。
- **w4 变更面域内验证**：zh-audit `--self-test` PASS + `--check` exit 0；build-for-testing 绿 ×3（T1/fix/走查前）；定向测试 6 类 **55 测试全 0 fail**（BackgroundTaskRegistryTests 9 / LibraryRelinkModelTests 6 / SettingsPagesTests 9 / EditorStackRoutingTests 9 / WorkspaceRoutingTests 11 / RawDecodeOverridesTests 5——覆盖 w4 触碰的全部测试域）。
- skip 基线 14 不变（本波零新增 skip）。

## 边界终审（`897bcb2..HEAD` 代码侧逐文件）

- phase 申报集全量命中；w4 触碰 = T1 7 文件（含 2 测试）+ T2 2 文件 + docs（m2-3 md/walk.py + 本批 ledger）。三笔注记：①`MCP/McpServerController.swift` = orchestrator 豁免件 `{02f727f, 47c356d, 2f8df6b}`（本 plan 未触碰）；②`UI/SettingsView.swift`/`LightamerApp.swift`/`PipeCoordinator.swift`/`EditorState.swift`/`ContentView.swift`/`ThemeTokens.swift`/`SettingsPages.swift`/`AppPreferences.swift` = P1/P2/P3 申报面；③`AGENTS.md` = checker/orchestrator 批（非 executor 触碰）。`.work/gsd/phases/m2-2-library-project/perf.md` = M2-3-2 T5 销账批。
- legacyBody / Inspector 33 面板族 / Library 域 Core 文件零 diff（KD-3 #1/#3/#4 兑现）。

## AC 总表核销（10/10）

| # | AC | 结果 |
|---|---|---|
| 1 | zh 对账四断言 | ✅ `--check` exit 0（1157/1369/zh complete/{en,zh}） |
| 2 | self-test golden | ✅ PASS（四 case 检出 + clean + allowlist） |
| 3 | 屏覆盖 15+ + 胶片条专用词 | ✅ 20 屏；`偏差-接受（设计差异）` 恰 1 行（editor-filmstrip） |
| 4 | 三件套存在 + 判定词封闭 | ✅ 20/20 三件套零 MISSING；sort -u 输出 ∈ 封闭集（UTF-8 collation 合并注记在 MANIFEST） |
| 5 | 偏差-修闭环 | ✅ 2 条 → `a3bf5bf`（git show --stat 可溯）；无未修残留 |
| 6 | 锁屏降级记录 | ✅ 显式「未触发」+ Alcedo 证据受限一处（import 确认框）如实记 |
| 7 | KD-3 五项 | ✅ 五项全绿（上文原样命令） |
| 8 | 全套 0 fail | ✅ 按 orchestrator 强杀口径：基线引用 2160/14/0 @ `d7f87fe` + 域内定向 6 类 55 测试 0 fail；deferred 登记在案（M2-4 首 plan = test bundle 拆分） |
| 9 | 翻账批 | ✅ REQUIREMENTS M2UIW-01..06 P4 锚 + M2DIS-03/04 + M2LIB-05 + TODO M2-3 块 + GOAL-STATE 续接点（同批） |
| 10 | diff 边界 | ✅ 申报集全量（三笔注记见上） |

## Manual-Only / 顺延（M2-4 与专项接账）

- **M2-4 首 plan**：test bundle 拆分（全套回归恢复的前置）。
- **真缺陷专项 ×2**：A 导入完成态不发布；B 编辑器加载失败（含示波器帧率目测随 B 补测）。
- relink Core 写面小 plan（M2-3-2 D2 顺延）；decode overrides 持久化 = M2-4 schema。
- 万行胶片条真机 60fps 目测（真实大语料）；左轨/胶片条宽度观感 = 用户晨审；双「显示」菜单 = M2-4 菜单清理裁量。
- 验收方独立抽查 2-3 屏（MANIFEST 抽查记录位待填；不一致 → 该屏重开）。

## 下一步

M2-3 全 phase（P1..P4）执行+验收+收口完成。C 档第 3 停：phase VALIDATION 前停——verify-work 结论 + 本 SUMMARY + MANIFEST 交用户过目；用户确认后 **M2-4 起航**（节点编辑模型 + test bundle 拆分 + 两真缺陷专项 + relink 写面）。

# M2-3-1 ACCEPTANCE — UI 壳骨架（独立验收报告）

> **PASS / 0 error + 0 minor**（3 条 observation 不计数，见 Findings）
> 独立验收 subagent（2026-09-29）。plan = checker 修正版 `897bcb2`；执行 = 7 commits
> `609662f` → `2329d74` → `909ef3e` → `c659ae7` → `c0a26e5` → `56e582e` → `8a8d0af`（收口）。

## Verdict

11/11 AC 全过、五重点核查全过、8 条偏差全部核实且合理、红线零违反。独立复跑
**2103 / 13 skip / 0 fail（724.3s）** 与执行方声明逐值一致（零 flake，无需隔离归因）。
无验收方修复项。翻账：REQUIREMENTS M2UIW-06 → Delivered（本批同 commit）。

## 复跑（独立）

- 验收方先 fresh `xcodebuild build-for-testing`（HEAD = `8a8d0af`，工作树无代码滞留）
  再 `caffeinate -dis Scripts/test-direct.sh` 全套直启：
  **Executed 2103 tests, with 13 tests skipped and 0 failures (0 unexpected) in 724.317s**。
- = 声明终轮 R2（2103/13/0, 718.0s）逐值一致；skip 13 = 既有基线原样（零新 skip）；
  本轮零挂测试，无 flake 归因事项。

## Commit 边界核查

- 7 commits 逐个 `git show --stat`：T1=2 文件 / T2=5 / T3=4 / T4=2 / T5=2 / T6=6 /
  T7=4 docs——去重后**恰 19 代码文件 + 4 docs = front-matter 申报集全量，零越界**。
  （T6 触 `LibraryThumbnailBridge.swift` +10 行 / 其测试 12 行：两文件均在申报集内，
  内容 = `queuedCountForTesting()` 观测面（D7 竞态根治），边界合规。）
- `git diff --name-only 897bcb2..HEAD -- LightamerCore/` = **空**（Core 零 diff）。
- 工作树滞留物 = `.work/gui-acceptance/*.png|jpg` 与 `.work/{culling-cli,debug-flaky,tmp-public}`
  等历史会话资产，均不在本 plan 申报面、未被 7 commits 携入——非本验收范围。

## 逐 AC 核对（11/11 PASS）

| # | AC | 独立证据（file:line / 命令） | 判定 |
|---|---|---|---|
| 1 | ThemeTokens 七族在册 + 亮暗序；新壳裸 hex 仅 tokens 命中 | `ThemeTokens.swift:62-84` Family 七 case + members 全量；ThemeTokensTests 7/7 绿（复跑覆盖）。机检复跑：`git grep -E '#[0-9A-Fa-f]{6}' -- UI/Shell UI/Library` **零命中**；`(#|0x)` 双拼写全集 = `ThemeTokens.swift`（豁免地，`:29-55`）∪ `LightamerColors.swift`（legacy 冻结并存零 diff，不入新壳机检域——DECISIONS D1 澄清合理）。亮暗序 0x0B0D11 < 0x171B22@0.80 < 0xE7EAF0 实值核实 | ✅ |
| 2 | 双态路由往返无损逐字段；穷举 switch 零 default | `WorkspaceModel.swift:40-96` LibraryPhaseState 六字段（filter/sort/selectedIDs/pageAnchor/scrollPosition/inspectorSelection）+ EditorPhaseState；`openEditor` 快照（`:138-148`）/`closeEditor` 恢复（`:152-155`）；WorkspaceRoutingTests 11/11 绿。机检：`git grep -nE 'default\s*:'` 新壳全集 **零命中**；AppPhase switch 点恰 2（WorkspaceModel:159 / WorkspaceHostView:62，双臂穷举） | ✅ |
| 3 | gate=false = WorkspaceHostView；gate=true = legacyBody 原样；LibraryLegacyGateTests 零改动全绿 | `ContentView.swift` diff 仅 gate=false 内层 9 行（ProjectWorkspaceFace → WorkspaceHostView，`library.project.workspace` marker 经 Host 面保留）；legacyBody 分支**零字节改动**（diff 逐行核实）；`shell.workspace.host` marker = ThemeTokens.Markers 单源（`ThemeTokens.swift:91-96`）；LibraryLegacyGateTests 零 diff、复跑全绿 | ✅ |
| 4 | keyset 分页不重不漏 + NULL 封底 + filter 重置 + 五键白名单 | `LibraryGridModel.swift:116-163` 两段游标（searchPage → searchNullTail，短页切段、尾段手造 anchor `:161-162`、封底 `isExhausted`）；重置 `:169-175`；选择状态机 `:181-218`；白名单透传（scanEpoch typed violation，测试实测）。LibraryGridModelTests 11/11 绿（真 .lalb fixture） | ✅ |
| 5 | 桥双档裁决 + 盘缓存零重产 + LRU + 并发 ≤4 + in-flight 合并 | `LibraryThumbnailBridge.swift`：tier 裁决 `hasEdits == 1 → renderLeg`（`:146-157`，nil = typed miss 不回退档 A）；盘缓存键 `String(id)` + mtime 新鲜度（`:200-216`）；**确定性显式 LRU**（MemoryLRU `:222-268`，access 刷新近用、`orderForTesting` 观测面——非 NSCache，D4）；gate actor 并发闸 + FIFO + prioritize（`:38-80`）；in-flight 合并（`:137-139`）。LibraryThumbnailBridgeTests 10/10 绿 | ✅ |
| 6 | 竖向 List 虚拟化；万行窗外零请求；选中滚动锚 | `FilmstripView.swift:172-210` 竖向 `List`（行高常量 64、`filmstrip.list`/`filmstrip.row.<id>` marker）；FilmstripModel 窗口化（可见 ±4 prefetch、暖集去重、listDisappeared 清窗 `:97-100`）。FilmstripModelTests 6/6 绿：万行挂载恰 16 请求、窗外 9,984 id 不相交、跳窗仅新窗 20、锚随 select | ✅ |
| 7 | MenuCommandSet 矩阵 + Session 四死路由 gate 包裹 | 矩阵测试逐 id 断言 gate×phase 全组合（WorkspaceRoutingTests:217-246）+ 双注册表不相交且并集==全集。**m7 逐 hunk 评审（验收方独立机检）**：LightamerApp diff 26 删除行经空白归一比对 **25 行精确重现于 gate 包裹内（仅缩进 +4）**，唯一例外 = T6 overlay gate 条件并入行（`if legacyLibraryEnabled, let progress = …`，ImportProgressView body 语句零改动）= SUMMARY 声明逐字相符 | ✅ |
| 8 | BackgroundTaskHosting 四态 + 导入腿 + 双呈现同源；controller/dialog/progress 零 diff | 协议 `@MainActor`（BackgroundTaskHosting:52-62，D2）+ registry register/update/finish/cancel/cancelAll（:77-106）；adapter 只读订阅 + 单调钳制 + cancel 透传 `cancelImport()`（ImportTaskAdapter:62-93,118-120）；双呈现 = `BackgroundTaskProjection.descriptors` 单函数（BackgroundTaskBarView:27-41，`tasks.bar`/`tasks.dialog` marker 在册）。BackgroundTaskRegistryTests 9/9 绿。`git diff 897bcb2..HEAD` 对 LibraryProjectController/ImportModeDialog/ImportProgressView = **空** | ✅ |
| 9 | 新 UI 全量 String(localized:)、零裸 Text 字面 | `git grep -n 'Text("' -- UI/Shell Library` **零命中**（动态串走 `Text(String(localized:…))` 重载）；新键 shell_*/filmstrip_*/tasks_*/menu_* 族全带 defaultValue（D9 zh 滞后 P4 补录） | ✅ |
| 10 | 全套回归 0 fail，计数 ≈ 2049 + 25..35 | 独立复跑 **2103/13/0**（= 基线 2049 + 54；超预估部分 = D6 粒度声明，判据「0 fail + AC 机检」满足） | ✅ |
| 11 | diff 边界 == 申报集；Core 零 diff；legacy 树资产零 diff | 见「Commit 边界核查」；SidebarView/SessionBrowserView/CullingView/FilterBarView/CatalogBrowser*/SettingsView/LibraryProjectController/ImportModeDialog/ImportProgressView/LibraryLegacyGateTests/LightamerColors/EditorAreaView 逐文件 diff = 空 | ✅ |

## 五重点核查结论

1. **红线**：`LightamerCore/` 897bcb2..HEAD 零 diff；legacyBody 零触碰（ContentView diff
   仅 gate=false 内层）；LibraryProjectController/ImportModeDialog/ImportProgressView/
   LibraryLegacyGateTests 四文件逐个 diff = 空；裸 hex `(#|0x)` 双拼写全集 = tokens 豁免地
   ∪ legacy 色板（零 diff 存量）——全守住。
2. **胶片条左竖**：`FilmstripView.swift` 竖向 List 实锤（行高 64 常量 + 行内 HStack 布局）；
   `EditorWorkspaceShellView.swift:23-28` 胶片条 slot 居 HStack **首位 = 编辑器左缘**（非
   Alcedo 底部），头注明示用户修订（2026-09-29）为标识性差异。P3 挂接面就绪。
3. **MenuCommandSet 矩阵**：纯函数 gate × phase → id 集（MenuCommandSet:72-79，P1 可见性
   phase 无关由矩阵断言钉死）；Session 死路由 gate=false 移除 / gate=true 原样——m7 独立
   机检 25/26 删行空白归一精确重现（见 AC#7）。⌘E/⌘W/⌘F 回路 + View 三 toggle 在册。
4. **ThumbnailBridge 确定性 LRU**：非 NSCache——60 行显式 LRU（字典 + 近用序数组，容量计
   thumb 数），access 刷新近用（防退化 FIFO）、`orderForTesting` 观测面、LRU 顺序逐断言
   可机检（DECISIONS D4 归因成立：NSCache 驱逐不可观测不可测）。盘缓存权威 + 内存纯加速
   的行为面与 KD-4 意图一致。
5. **8 条偏差合理性**：D1 机检域澄清（plan 字面路径矛盾按 KD-1 意图执行，豁免地唯一性
   不弱化——认可）；D2 协议 @MainActor（snapshot get/set 写入面需隔离，Sendable 蕴含——
   认可）；D3 档 B 注入缝（Library 行无 Session 域索引行，生产腿 P2 接线 + nil typed miss
   有测试钉——认可）；D4 NSCache→显式 LRU（可测性，认可）；D5 T5 片段随 T2 提交（两文件
   均在申报集、commit body 注记、每 commit 可构建——过程偏差已披露，认可）；D6 +54>预估
   （粒度声明，认可）；D7 prioritize 竞态根治（wall-clock sleep → 确定性轮询，观测面
   test-only 命名，隔离 ×3 + 终轮全绿——认可）；D8 全套按域合并 3 轮（纯新增文件零交叉
   + 每任务新增测试定向跑绿 + 3 轮全套覆盖跨域——认可，节时 ~50 分钟风险面已覆盖）。

## Findings / Observations（不计数）

1. **`MenuCommandID.sessionImport` 无菜单消费点**（observation）：KD-6 表列「四死路由」，
   但 M1 基线 LightamerApp 实际只有 session.new/open/close **三个**菜单项（`git show
   897bcb2` 核实，无 session.import 项）；`session.import` id 在 MenuCommandSet 建模 +
   矩阵测试钉拼写，但 LightamerApp 无对应 Button、两 gate 通道均无实体。「gate=true 原样
   字节不变」对它平凡成立（本来就不存在），无功能影响——IA 注册表完备性建模，留 P2/P4
   菜单 IA 走查时如需对齐可删可挂，不构成本 plan 缺陷。
2. **FilmstripModel 双请求路径归并靠桥**（observation）：`FilmstripRowView.task(id:)` 与
   FilmstripModel 窗口化各发一次请求，同 id 经桥 in-flight 合并 + 暖集去重收敛为一次生产
   （AC#6 计数断言在模型级）——语义正确；真机「List→桥」接线兜底核验已按 plan 挂 P4 T2
   清单①（E4 接账），无重复生产风险。
3. **`WorkspaceModel.openEditor` 在 editor 相内带新 id 重入不重快照**（observation）：
   library 快照只在 `phase == .library` 分支落（WorkspaceModel:139-141），editor 相内换图
   不覆盖 preserved 态——往返语义正确（回图库仍恢复进编辑器前的 library 面）；P3 若需
   「编辑器内换图后返回仍保留新选中」由 `updateLibraryState` 面承载，缝已留。

## Manual-Only / 顺延确认（维持执行方登记）

- env=1 真进程 GUI 冒烟（legacy 通道菜单字节同构目测）——沿 M2-2-4 惯例留人工。
- computer-use Alcedo 对照 = P4 统一执行（OQ-10）。
- ⌘F 搜索对话框呈现 / ⌘E 网格双击主入口 / TopBar 完整命令行 = P2 接线；编辑器四区
  slot 填充 = P3；zh 文案补录 = P4 对账批；万行滚动 60fps + 菜单撞键真实按键走查 =
  P4 T2 清单①②（E4 接账）；档 B 首渲产能 = P2 并案。

## 翻账（本验收批）

- REQUIREMENTS `M2UIW-06` → `[x]` + **Delivered 协议+导入腿**（锚 `609662f`..`8a8d0af`，
  验收 = 本报告）；导出腿 M2-9 / AI 腿 M2-10 按协议消费（零预留字段）。
- GOAL-STATE 续接点追加本验收条目（C 档第 2 停汇报就绪）。

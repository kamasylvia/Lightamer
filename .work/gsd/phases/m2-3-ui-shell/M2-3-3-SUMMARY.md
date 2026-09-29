# M2-3-3 SUMMARY — 编辑器面

> **执行身份**：T1-T3 由前任 worker 完成（`46e13fb` 三段布局 / `29553ba` 七页签路由 +
> TAB-MATRIX / `05317d1` 示波器 GPU kernel，基线声明 2130/14skip/0fail）；前任 T4 中断
> （机器重启），**续班 worker 自 T4 在制品接手**：审查 + 4 处编译级修复 + front-matter
> 膨胀字段申报后提交 `921a98f`；T5 `8d556c7`、T6 收口本提交。偏差全案见
> `M2-3-3-DECISIONS.md`（D1-D12）。

## 测试终值

| 轮次 | 执行数 | skip | fail | 秒 | 备注 |
|---|---|---|---|---|---|
| T4 后（`921a98f` 前） | 2151 | 14 | **0** | 700.4 | 2130 基线 + routing9 + scope7 + rawdecode5 |
| **终跑（T5 后）** | **2160** | **14** | **0** | **697.4** | + SettingsPagesTests 9；`Scripts/test-direct.sh` 双读 Executed/failures |

- 增量 = **+30**（AC#11 预估带 25..35 上沿内）；skip 14 = M2-3-2 终态原样
  （LA_THUMB_BENCH MANUAL-ONLY gate 等，零新增 skip）。
- 目标族复跑：`RawDecodeOverridesTests` 5/0fail、`EditorStackRoutingTests` 9/0fail、
  `RAWDecoderTests` 11/0fail（既有 Decode 域零改动）、`SettingsPagesTests` 9/0fail、
  `LibraryLegacyGateTests` 11/0fail（冻结快照零改动）。

## 交付面（按任务）

- **T1（前任 `46e13fb`）**：`EditorToolRailView`（History 真挂 history stack /
  Versions+Nodes 空态，`editor.rail.<name>` marker 族）+ `EditorWorkspaceShellView`
  三段填充（左工具轨 + 左竖胶片条 FilmstripView + 中 EditorAreaView child + 右
  Scope/Stack）+ 顶栏回退接线 `closeEditor()`。**EditorAreaView.swift 零 diff**
  （KD-1 零 diff 包装路径）。
- **T2（前任 `29553ba`）**：`EditorTabRoute`（Alcedo 七页序）+ `EditorTabRoutingTable`
  （`EditorPanelDescriptor` op 常量引用，**33 行恰一次**，动态 populated-registry −
  {TextOverlay} 完备性断言）+ `EditorAdjustmentStackView`（页签条 + InspectorRowView
  宿主形态 + `editor.stack.tab.<name>` marker）+ `EditorNodeHeaderView` + TopBar yiyin
  sheet 入口（`WorkspaceHostView`）+ `M2-3-TAB-MATRIX.md` 落盘（与表同批互校）。
- **T3（前任 `05317d1`）**：`ScopeReduceKernels.metal`（atomic_uint bin 256×4 + 波形
  列散点）+ `ScopeReduce`（双 pass，fence 纪律承 L014/HistogramReduce 先例）+
  `PipeCoordinator` PREVIEW tap（唯一队列路由点，`makeCommandQueue()` 新增代码零
  命中）+ `ScopePanelView`（直方图/波形二选一 + `ScopeThrottle` 状态机：≤15 Hz +
  0.25s idle 补算 + 不可见零 tap，3 条状态机单测）+ `ScopeReduceTests` 7 条
  （三 case 逐 bin parity + 波形 parity + 确定性 + 退化纹理零崩 + 节流两条）。
- **T4（续班 `921a98f`）**：RAW Decode 面板 + decode overrides 缝（checker E2 链路：
  RawDecodePanelView → WorkspaceModel 会话载体 → EditorState.load `:295` 唯一请求链
  → `RAWDecoder.decode` 第二参数 → readback → cache key 漂移 → PREVIEW 重渲）。
  - `RAWTechnicalOverrides`（Optional-nil = identity，`clamped()` 面板域）+
    `resolveDecoderVersion` 纯函数（automatic/forceV8/forceV9 × 探针 × OS，v9 强选
    不支持 = typed 降级 v8 + 面板行内提示）。
  - **膨胀字段规则触发**（D1 申报）：`RAWTechnicalParams` + Optional
    `sharpnessAmount`/`boost`（encodeIfPresent 零漂移）+ `HistoryHash` 两腿 Optional
    fold——front-matter 与纪律 5 同批更新（`921a98f`）。
  - v9 降级提示 = readback `decoderVersionUsed` 对比强选请求（`editor.rawdecode.v9.hint`）。
- **T5（续班 `8d556c7`）**：Settings 十入口导航（KD-5）——`SettingsPage`（十项
  `navigationPages` + Catalogs 门控页 `displayedPages` 两态）+ `SettingsPages.swift`
  （Language&Theme / Default Behavior / Cache / LCR / ACA / Keyboard / About /
  Import Defaults / Displays / MCP / Catalogs 十一视图件）+ `AppPreferences.swift`
  （mask 三选键 + Keyboard keymap 镜像/override 存储/纯冲突检测器）。Displays/MCP/
  Catalogs 三节语句级 verbatim 迁移；`visibleCatalogSectionMarkers` 零 diff。
  - 越界一行（D2 申报）：LightamerApp Settings scene 补 `.environment(pipeCoordinator)`
    （13-2 存量缺失注入，不补 displays 页即 crash）。
- **T6（本提交）**：SUMMARY/DECISIONS/GOAL-STATE 续接点；边界终审见下。

## 例外缝与边界证据

- **diff 边界终审**（`git diff --name-only 46e13fb^..HEAD`，逐文件对 front-matter）：
  申报集全量命中、零计划外文件。两笔注记：①膨胀字段两文件（D1，front-matter 已
  申报）；②`02f727f`（McpServerController）= orchestrator 修复件，按豁免通告剔除
  （D3；本 plan 未触碰）。T5 增补的 LightamerApp.swift 一行 = D2 申报偏差。
- **Core 例外缝**：`RAWDecoder.swift` public 缝纯增量（默认参数编译级零行为变化）；
  decodeRAW 内部 version-selection 重构为 KD-4 授权腿（D4 行为等价论证）。
  `Inspector/` 33 面板 + `InspectorView` + `InspectorRowView` + `IOPPanelProvider` +
  HistogramReduce 既有文件全零 diff（grep 核）。
- **禁用 6 名 grep**：filmicrgb / sigmoid / denoiseprofile / nlmeans / bilateral
  在 `EditorTabRoute.swift` / `EditorAdjustmentStackView.swift` / TAB-MATRIX md
  **零命中**；`agx` 仅命中 E1 勘误注释与 TAB-MATRIX 勘误注记行（路由条目零命中，
  KD-2 确认项）。
- **legacyBody 零 diff**：`ContentView.swift` 不在 plan diff 文件集（legacyBody 树
  资产零触碰）。
- **新 UI 全量 `String(localized:)`**：RawDecodePanelView / SettingsPages /
  SettingsView / AppPreferences 无裸字符串用户面（Keyboard 表命令 id 为技术
  identifier 原文显示）。

## AC 总表核销

| # | AC | 结果 |
|---|---|---|
| 1 | 三段方位 + 左竖胶片条 + 工具轨三态 marker | ✅ EditorStackRoutingTests 9 绿 + `editor.rail.*` marker |
| 2 | EditorAreaView 零迁移 | ✅ 全 plan 零 diff + 既有测试零改动全绿（KD-1 结论入 DECISIONS） |
| 3 | 路由表完备性 + 禁用 6 零命中 + md 对账 | ✅ 恰一次断言绿（动态集）+ grep 证据如上 + TAB-MATRIX 互校 |
| 4 | 33 面板 + Inspector 族零 diff | ✅ 计划 diff 文件集 grep 零命中 |
| 5 | ScopeReduce parity/确定性/单队列/fence | ✅ ScopeReduceTests 7 绿 + `makeCommandQueue` 零命中 |
| 6 | 示波器节流状态机 | ✅ ≤15Hz/idle 补算/不可见零 tap 三断言在 ScopeReduceTests |
| 7 | RAW overrides 四断言 | ✅ RawDecodeOverridesTests 5 绿（含 nil 腿 hash 纪律） |
| 8 | RAWDecoder 唯一 Core 触点仅增量 | ✅ public 缝纯增量（D4 内部重构授权论证入 DECISIONS）；Decode 域测试零改动 |
| 9 | Settings 页集/三选/冲突检测/门控零迁移 | ✅ SettingsPagesTests 9 绿 + LibraryLegacyGateTests 11 零改动 |
| 10 | String(localized:) 全量 + legacyBody 零 diff | ✅ |
| 11 | 全套 0 fail，计数 ≈ 基线+25..35 | ✅ 2160/14skip/0fail（+30，上沿内） |
| 12 | diff 边界 == 申报集 | ✅（两笔注记：D1 申报膨胀字段；D3 豁免件剔除） |

## Manual-Only / 顺延（P4 接账）

- 示波器 PREVIEW 帧率影响观察（后备 = 半分辨率 ROI）；左轨双列宽度观感裁决；
  zh 文案补录（本 plan 新键族）——三项均只登记，详 DECISIONS 性能观察节。
- Decode overrides 持久化 = M2-4（sidecar/项目 schema 承载，KD-4 非目标）。
- Keyboard 活绑重映射 = M2-x（override 存储契约已建，v1 三面展示/检测/恢复）。

## 下一步

M2-3-3 完成（编辑器面落地）。下一步 = **M2-3-4 收口 plan**（P4：菜单 IA 走查 +
Alcedo 对照 + zh 对账 + 性能观察清单核销）。C 档门控：M2-3-3 执行+验收闭环后停，
等 orchestrator 派验收 subagent 并汇报。

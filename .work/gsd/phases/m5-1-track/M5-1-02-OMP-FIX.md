# M5-1-02 OMP-FIX — E-omp1 修复批报告（GUI 面 colormatch 可达性）

> 修复 2026-10-11。对象 = omp 二验 `M5-1-02-ACCEPTANCE-OMP.md` §4.1 E-omp1
> （FAIL / 1 error + 2 minor 的唯一 error）：gate-false 默认编辑器面无 colormatch
> 实例添加入口 → LUT 页追色行永不渲染 → T6+T7 面板/服务不可达。
> **结论：FIXED（实机全链路走通 + App bundle 定向轮全绿）**。

## 1. 缺口归因（三方定位，omp 机制链亲证一致）

| # | 面 | 状态 | 证据 |
|---|---|---|---|
| 1 | 路由行 | **已在**（非缺口） | `EditorTabRoute.swift` LUT 页 `.page(ColormatchModule.opName, .lut)`（T6 已落，`EditorStackRoutingTests` 钉死） |
| 2 | 面板 provider/gating | **已在**（非缺口） | `InspectorState.registerDefaultProviders` 注册 `ColorMatchPanelProvider`；`EditorAdjustmentStackView.selectedPanelBody` 按实例挂面板 |
| 3 | **add 菜单行** | **缺口在此** | `EditorAdjustmentStackView` 全文件无任何 add 入口；`row(for:)`/`pageRows` = 「无实例不渲染行」（M1 chain-list 语义）；唯一 add 菜单在 legacy `InspectorView.moduleList`（`layers.addmodule`），而 gate-false 面 InspectorView 只在 export/film 页激活时挂载（`ContentView.inspector` binding = `exportPageActive \|\| filmPageActive`），standardBody 结构性不可达 |

鸡生蛋闭环（omp 报告机制链成立）：colormatch 行需实例 → 实例需 add 菜单或 Solve
自动 attach → Solve 需面板已渲染 → 面板需实例。`defaultLook` 不含 colormatch →
默认面零 GUI 路径创建首实例。附带确认：`addFaceEntries` base scope（develop-only,
D4 收窄）本就不含 grade-owned 的 colormatch——即使 legacy 菜单可达，base scope
也无此入口；colormatch 的 designed home = **base chain**（`ColorMatchService
.solveAndAttach` 走 `addModuleToBaseChain`，`instanceRecord(opName:)` 读 base）。

## 2. 修复内容（最小补齐，照 grade/LUT add-face 先例同形）

**`App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift`**（唯一产线文件）：

- `pageContent` 的 `.lut` tab 在 `pageRows` 之后渲染 `lutColormatchAddRow`。
- `lutColormatchAddRowGate(instances:layerID:)`（纯函数，机检面）：**base scope
  限定 + 链上无 colormatch 记录**才渲染。base-scope-only 的理由：colormatch 是
  base-resident op（Solve attach 面同缝），layer scope 出现 add 行永远关不了门
  （二次添加 = 重复实例 by construction）。
- `lutColormatchAddRow`：Menu（label = 新键 `editor_stack_add_module`「添加模块」，
  a11y id `editor.stack.lut.addmodule`）→ 单项「追色」（既有键 `module_colormatch`）
  → `EditorState.templateInstance(for:)`（M5-1-01 T5 第 20 行模板厂 case）→
  `addModuleToBaseChain(template:)`（**与 Solve attach 同一缝**）→ 新记录
  `inspectorState.selectPanel`（面板立即挂载——AC#7 的入口步）。
- 零触碰红线面：路由表 / provider 注册 / ColormatchModule / 服务 / DrtRecord /
  Film 域 / `.metal` / 六格式导出矩阵——全部零 diff。

**`Resources/Localizable.xcstrings`**：尾块纯插入 `editor_stack_add_module`
（en "Add Module" / zh "添加模块"）；zh-audit --check PASS（1637 source /
1876 catalog）。注：`Label("key", systemImage:)` 形态 zh-audit scanner 不可见
（同 legacy `layers_add_module` 先例），键以 catalog 承载、运行时查表——动态族
键清单以本报告 + MANIFEST 证据节为准。

**`Tests/LightamerTests/EditorStackRoutingTests.swift`**：+1 法
`testColormatchAddRowGateAndBaseChainAttach`（template 第 20 行 case 在厂 + gate
三态：base 无实例正测 / 实例存在关门 / layer scope 恒 false + attach 落 base 链
幂等门）。`.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` 同批登记
（APP 12→13）+ 顺带勘误 ColorMatchServiceTests 行 6→7（cbd1afa 同类漏：4cc1c52
+1 法未随账，实数 7，grep 互证；仅 per-file 账面，执行总数 725 不受扰）。

## 3. 实机验证（AX + CGEvent 驱动；证据 = `.work/gui-acceptance/m5-1/m5fix-*.png` 9 件）

环境：Debug 构建（含本修复，DerivedData Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi
10:18）直启 + `-la_film_probe` 探针缝（stay-alive；/tmp throwaway 项目
editor-probe-*.lalb，main.ARW 真身 Sony ARW 75MB + ref-warm.ARW 参考）。

| 步 | 实测 | 证据 |
|---|---|---|
| LUT 页 add 行渲染 | `editor.stack.lut.addmodule` AXMenuButton 在位（base scope 无实例态） | m5fix-01（菜单开，「追色」AXMenuItem） |
| 选「追色」 | colormatch 行渲染（`inspector.row.colormatch`）+ 面板四件 AX 全可达（solverPicker/addReference/solve/strength） | m5fix-02 |
| 添加参考图 | NSOpenPanel（PanelPresentation 缝）→ ref-warm.ARW → 权重 1.00 + 移除钮 | m5fix-03/04 |
| 追色 | 历史栏恰一「追色」item；读数节 = 高斯最优传输 + 统计哈希 14288275262918843225 + 支撑域 L ±0.69 a ±0.21 b ±0.19 | m5fix-05/08 |
| 强度拖拽 0→1 | AX slider value 1.0；视口全画面色移（绿黄→红/品红/金，向暖调参考偏移；L1 差分 20.3M）——**拖 strength 动像素** | m5fix-06/09 |
| ⌘Z 一次 | 强度回 0.00（恰一 commit 撤销）；sidecar position 回 solve item | m5fix-07 |
| sidecar 真相 | `main.ARW.lra` schema 9：4 items + colormatch 实例（multiPriority 0、enabled、313B params）持久化 | 正文 §3 |
| zh 呈现 | 添加模块/追色/参考图/强度/求解器三段/读数/统计哈希/支撑域全程 zh 无裸键 | 全部截图 |

MANIFEST 行 1 配方已按实际挂载重写（m-omp1 关闭）+ 证据节追加
（`MANIFEST.md`「OMP-fix 走查证据」节；行 5-8 留验收轮，不在本修复批范围）。

## 4. 回归

```
构建：build-for-testing（默认 DerivedData，含修复）
EditorStackRoutingTests 定向：13/0/0（12 基线 + 1 新法）
App bundle 全量定向轮：725/4/0 | peakRSS=2832MB | 370s | 零 MEMFAIL
  ← 基线 724/4/0（首验/omp 双路对表值）+1 新法，零回归
zh-audit --check：PASS（1637 source / 1876 catalog，+1 新键）
红线：.metal 0 diff；runModal 0；SPM 0 新增；六格式/DRT/Film 域 0 diff（本批只触
EditorAdjustmentStackView + xcstrings + 测试 + 账面四个文件）
```

## 5. 遗留与边界

- LUT 页 lut3d 无实例时的同族 add 缺口（库选择器在面板内、面板需实例）**不在本
  批**——omp FAIL 面仅 colormatch；lut3d 的 add 面挂账不改（既有产品形状）。
- m-omp2（uniform 108B 账面勘误）为文档面，omp 报告已自带更正，本批不重复。
- 走查会话 throwaway 域已清（/tmp editor-probe-* 项目、drive.py 即弃；app 已
  quit，资源监控无异常——GUI 进程峰值 ~1.4G < 3G 触发线）。

# M2-1 SUMMARY — dt 面 feature-flag 禁用（执行收口）

> 执行：executor subagent worker，2026-09-28。Plan/MATRIX 正本见同目录；裁决正本 =
> ROADMAP M2 节 D1/D2/D6（2026-09-27 用户「全按推荐」签核）。本文件只记战果/终值/偏差，
> KD 已决项不重复（执行确认见 `M2-1-DECISIONS.md`）。

## 战果

| 任务 | 内容 | commit |
|---|---|---|
| T1 | 禁用缝正本（`defaultFaceDisabledOpNames` 6 项 / `isFullFaceRequested` env 口 / `populate(defaultFace:)` / `editingDefaultInstances(defaultFace:)`）+ `DefaultFaceTests` 6 测试（含 round-trip 红线钉） | `f5bcfa2` |
| T2 | 生产组装点接线（LightamerApp populate/panels/seed + PipeCoordinator pristine seed）+ `registerDefaultProviders(defaultFace:)` 6 panel gated + panel face 测试 | `561ca59` |
| T3 | MCP 面（`Seams.defaultFace` + `makeEditingSeams` 同源接线 + `editingSeed`/`defaultRecord`/`projectInstances` 透传）+ `IopCatalog.defaultFaceOps()`/`catalogJSON(defaultFace:)`（15/18）+ McpHostTests 期望元组同源 face + catalog/tool face 测试 | `f2a3618` |
| T4 | 矩阵复核签注（MATRIX 尾节）+ SUMMARY/DECISIONS + TODO/GOAL-STATE 翻账 + 本收口提交 | 本提交 |

- **向后兼容红线（KD-4）全钉**：`DefaultFaceTests.testLegacySidecarWithDisabledOpsRoundTripsByteSemantics`
  —— 旧 .lra（global history 含 enabled filmicrgb + 层链含 sigmoid，非默认 params 字节）经
  `degradedForUnknownOps` + `degradedLayerStack`：record count 不变 / paramsData 字节相等 /
  enabled=false / unknownOps == ["filmicrgb"]（层腿 ["sigmoid"]）；真实 `SidecarStore` 写盘 →
  重载全量相等（含 canonical 编码字节相等）；二轮 degrade 幂等。
- **MCP 写面**：upsert 禁用 op = typed `unknownOp`（`makeBox != nil` 寻址缝免费收窄）；
  `remove: true` 对 legacy 实例仍放行（`registered || op.remove` 语义钉）。
- **M2DIS-05 工具面**：工具注册面 19 不变（McpRegistrySnapshotTests 零改动绿）；
  仅 `list_iops` 输出面 18 → 15（恰滤 D1 三条目）。

## 测试终值 vs 基线

- **终轮全套：1889/11skip/0fail（695.7s，exit 0）**；基线 1881/11skip/0fail → **+8**
  （`DefaultFaceTests` 8 个新测试），**既有测试零改动**（对账：McpRegistrySnapshotTests /
  McpEditingToolsetTests 反射守卫 / PanelWiringTests 71 / McpHostTests 18 全绿）。
- 全套执行轨迹（本 plan 内 3 轮完整 + 定向多轮）：
  1. T1 后：1887/11skip/0fail（734.0s）。
  2. T2 首轮：1888/**59 fail**（全部 PanelWiringTests——T2.1 处方的 env 直读撞种子断言，
     修复 = face 注入式，见偏差 #1；55 fail case 修复后定向 71/71 绿）。
  3. T2+T3 组合首轮：1889/**2 fail**（McpHostTests 三形态一致性——期望元组 full face vs
     生产 default face，修复 = 同源 face，见偏差 #2）。
  4. 终轮：**1889/11skip/0fail**（695.7s）。
- **Flake 归因：零 flake**——3 轮全套无在案 flake（GoldenColor 等未出现）；2 fail 均为
  本 plan 改动的确定性撞面（非时序 flake），修复后复跑绿。

## 与 plan 的偏差（全部已实测归因，不推翻任何裁决）

1. **PipeCoordinator face 注入式**（plan T2.1 处方「pristine seed（:675）传
   `defaultFace: !isFullFaceRequested`」env 直读）：env 直读让 coordinator 的**生产路径在
   测试环境中也走 default face**，PanelWiringTests 55 个 case（经 `coordinator.load` 的
   pristine-seed 全量断言，`PanelWiringTests.swift:125` 族）红——与 plan 最高优先 AC
   KD-2「既有测试零改动保持全绿」直接冲突。修复：face 改为组装根注入
   （`attach(registry:defaultFace:)`，LightamerApp 启动 task 与 populate 同一处 env 读）；
   coordinator 落库为属性，默认 false = full face。env 仍是唯一事实源，KD-3 语义不变；
   KD-2 字面兑现（测试零改动）。详见 DECISIONS D-EXEC-1。
2. **McpHostTests 期望元组同源 face**（+`import LightamerIOP`，1 处构造参数）：
   `expectedListIopsText()` 手工构造 full-face seams 作三形态一致性基准，而 HTTP/InMemory/stdio
   三形态全走生产 `makeEditingSeams`（no-env 进程 = default face）→ 18 vs 15 撞。修复 =
   期望元组用同一 face 开关构造（三形态彼此仍互证，一致性断言强度不变）。详见 DECISIONS D-EXEC-3。
3. **任务边界重划（无代码影响）**：T2 的「`editingDefaultInstances()` App/ 生产残留 = 0」
   在 T3 后达成（EditingToolset 两处调用属 plan T3.2 范围）；T2/T3 测试同文件分段提交
   （每任务提交只含本任务测试块）。

## 申报项（代价与边界，用户应知的后果）

- **旧图视觉回退（KD-1 已裁决接受）**：旧 .lra 若启用过 filmic/sigmoid/agx/denoiseprofile/
  nlmeans/bilateral，重定义后打开 = 该 op 降级禁用（enabled=false）+ 一次性 toast
  （「未知模块 … 已停用（数据已保留）」）+ 渲染不再过该模块；**数据零丢失**（字节级测试钉），
  `LIGHTAMER_FULL_IOP_FACE=1` 启动即原样恢复（opt-in 口 = KD-3，无设置 UI，M2-3 后端缝已留）。
- **prewarm/PSO 死代码保留（KD-5）**：禁用 6 模块的 kernel 仍编译、启动仍预热——启动成本微增
  可接受，换 opt-in 零重建；模块源文件/golden 测试/parity harness 照常跑（full face 默认下
  测试面无变化）。
- **Preset seed 验证结论（T2.3，grep 申报）**：生产 preset/批量 apply 种子源**零旁路**——
  ①`PresetController.configure` ← `LightamerApp.seedInstances()`（:597-601）；②批量 paste/batch
  apply ← `seedInstances()`（:1415）；③MCP 元数据种子 ← `seedInstances()`（:956）；④MCP culling
  apply_preset 传 `seed: []`（空种子，无禁用 op 可入）；⑤MCP apply_params pristine 种子 ←
  `EditingToolset.editingSeed(defaultFace: seams.defaultFace)`（T3 接线）。全部经收窄种子流入，
  无需额外接线。
- **内置预设（KD-6）**：执行侧复测 `find` 零 `.lightamer-preset` 资产命中——风险不存在成立。
- **不改 UI 布局**：本 plan UI 面变化仅为「行消失」（面板行/add-module 菜单）；七页签收纳、
  CIRAW NR 的 RAW Decode 页签、设置页开关属 M2-3/M2-5（M2DIS-04 留 M2-3）。

## AC 总表核验（10/10 绿）

| # | AC | 结果 |
|---|---|---|
| 1 | 禁用集恰 6 项与矩阵相等 | ✅ `testDisabledSetMatchesMatrixExactly` |
| 2 | 默认面 registry 不含禁用集；启用集+终端三件套可寻址 | ✅ `testDefaultFaceRegistryExcludesDisabled…` |
| 3 | 默认面种子不含禁用集；v50 sort 保持 | ✅ `testDefaultFaceSeedExcludes…`（count == full−6 双钉） |
| 4 | 旧 sidecar record/paramsData 字节保留 + enabled=false + typed unknownOps + 写读字节相等 | ✅ `testLegacySidecarWithDisabledOpsRoundTrips…` |
| 5 | 预设含禁用 op 不崩/degrade（Payload 直构 + 既有 degrade 面） | ✅ 既有 PresetApplier/SessionBatchApplier 面零回归（终轮 0 fail）+ T1 同机制钉 |
| 6 | UI 默认枚举面不含禁用集 | ✅ `testDefaultFacePanelsExclude…`（panel + 种子双钉） |
| 7 | MCP 默认面：list_iops 无禁用集 / apply_params unknownOp / 工具 19 不变 | ✅ `testMCPDefaultFaceCatalogAndToolFace` + T1 MCP 测试 + 快照零改动绿 |
| 8 | opt-in 恢复 full face（参数正反双向钉） | ✅ populate/seed/panels/catalog 四面 full-face 反向钉 |
| 9 | 全套 0 fail；≈1881+8..12 | ✅ 1889/11skip/0fail（+8） |
| 10 | diff 边界 = 申报文件集；Pipe/Sidecar 生产文件零改动 | ✅ `git diff --stat` 逐任务核对（Sidecar 只读消费，ModuleRegistry.swift 零改动） |

# M2-1 DECISIONS — 执行决策（KD 已决项只记执行确认，不重开）

> 裁决正本 = plan §已定裁决（D1/D2/D6）+ §关键设计决策（KD-1..6）。本文件记执行期新决策
> 与 KD 执行确认。日期 2026-09-28。

## D-EXEC-1 PipeCoordinator face 注入式（T2 偏差，实测归因后裁决）

**决策**：pristine seed 的 face 不在 coordinator 内部 env 直读，改由组装根注入
（`attach(registry:defaultFace:)` 新参 + 私有属性；LightamerApp 启动 task 一处
`!isFullFaceRequested` 读同喂 populate/panels/attach）。

**why**：plan T2.1 处方的 env 直读让生产路径在测试进程内也走 default face（no-env =
`isFullFaceRequested == false` → `defaultFace: true`），`PanelWiringTests` 55 case 经
`coordinator.load` 真生产种子路径断言全量种子（`:125`「pristine seed must include nlmeans」族）
全红——与 plan 最高优先契约 KD-2「既有测试零改动保持全绿」（AC #9 0 fail）直接冲突。
三案对比：(a) 测试 setUp setenv——污染进程全局态且改既有测试文件，违反 KD-2 字面；
(b) 改 PanelWiringTests 断言——同违 KD-2；**(c) face 注入（选定）**——env 仍是唯一事实源
（KD-3 语义不变：`LIGHTAMER_FULL_IOP_FACE=1` 依旧全局恢复 full face），coordinator 默认
false = full face（KD-2 字面兑现），生产组装点（T2.1 的本意「只有生产组装点显式传 face」）
反而更纯粹。**验证**：PanelWiringTests 定向 71/71 绿；终轮全套 1889/11skip/0fail。

## D-EXEC-2 Seams.defaultFace 字段 = MCP face 的载体（T3 设计）

**决策**：`EditingToolset.Seams` 增 `defaultFace: Bool = false` 字段（init 末位默认参数），
`makeEditingSeams` 用与 populate 同一次 `isFullFaceRequested` 读同时喂 registry 与 seams
（「one switch, same source」）；`list_iops` handler 与 `apply_params` 种子经 seams 取 face。

**why**：plan T3.2 预案「若 seams 无法携带布尔，isFullFaceRequested 直读」——seams 能携带
（struct 加字段零破坏，13+ 既有构造点走默认参数 = full face，KD-2 测试面零改动）。env 直读
方案会让测试 seams（无 env）与生产 seams 同值但**不同源**，且 handler 无法对「测试自建
full-face seams」保持 full face（`McpEditingToolsetTests.testListIopsReturnsTheCatalogShape`
断言工具输出 18 ops 将红）。字段化后：生产 = default face、测试自建 = full face，两个 KD 同
时字面成立。

## D-EXEC-3 McpHostTests 期望元组同源 face（T3 连带修复，改既有测试 1 处）

**决策**：`expectedListIopsText()` 的手工 seams 构造追加
`defaultFace: !LightamerIOPRegistry.isFullFaceRequested`（+文件头 `import LightamerIOP`）。

**why**：三形态一致性测试（SC 红线：HTTP/InMemory/stdio 同 kernel 同结果）的期望元组是
手工 full-face 构造，而三形态全走生产 `makeEditingSeams` → no-env 进程生产面 = default
face，18 vs 15 撞（实测 2 fail：`:697`/`:715`）。期望元组与被测形态必须同 face 才是有效
断言；修复后三形态互证强度不变（仍比对真实传输的完整 catalog 文本），face 随 env 双向切换
（=1 时三形态全 18）。**这是本 plan 唯一改动的既有测试**（KD-2 字面破例，机制性耦合而非
行为放宽——偏差登记 SUMMARY §偏差 #2）。

## D-EXEC-4 IopCatalog.defaultFaceOps 用 registry 常量交集（KD-2 纪律延伸）

**决策**：`defaultFaceOps()` = `ops.filter { !defaultFaceDisabledOpNames.contains($0.opName) }`
（App 侧 `import LightamerIOP`），不写字面量集合。

**why**：KD-2「禁字面量防 typo」的同一逻辑适用于 catalog 面——registry 常量是唯一事实源
（DefaultFaceTests 已钉其与矩阵相等），交集恰好滤掉 D1 三条目（sigmoid/agx/filmicrgb；D2
三件本就不在 catalog 的 18 条目内），未来禁用集或 catalog 任何一侧变化自动保持一致。

## KD 执行确认

- **KD-1**（不注册语义）✅ 落地为 `gatedRegister` helper（populate 内 6 处，逐点注释矩阵行号
  与 D1/D2 依据）+ `editingDefaultInstances` 返回前 filter。三消费面全部经 `makeBox == nil`
  免费收窄，零新机制。
- **KD-2**（默认参数 = full face）✅ 全部收窄 API 默认 `false`；生产组装点显式传 face。
  既有测试零改动全绿（唯一破例 D-EXEC-3 属机制耦合，非行为放宽）。
- **KD-3**（env opt-in 口）✅ `isFullFaceRequested` 一行实现于 registry；无设置 UI；
  生产消费点 = LightamerApp 启动 task（一处读，四路分发）+ McpServerController.makeEditingSeams
  （独立进程语境同源读）。
- **KD-4**（round-trip 红线）✅ T1 字节级测试钉死（可读/可写/不崩/数据不丢 + 幂等）。
- **KD-5**（死代码/prewarm 不动）✅ `prewarmFunctionNames` 原样；模块源文件/golden 测试/
  parity harness/NoiseProfileStore/LutLibraryStore 全部未触碰。
- **KD-6**（内置预设零资产）✅ 执行侧复测 `find` 零命中，风险不存在成立。

## D1 DRT method 扩展注记（plan 指定一行）

filmicrgb/sigmoid/agx parity 后评估以 DRT method 扩展身份回归——M2-6 后议题，本 phase 未实现。

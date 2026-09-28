# M2-1 验收报告 — dt 面 feature-flag 禁用

**结论:`PASS / 0 error + 1 minor`**

- 验收方:独立验收 subagent(ZCode),2026-09-28。判据 = `M2-1-PLAN.md`(10 条 AC)+ `M2-1-MATRIX.md`(verdict 正本)。
- 执行方 4 commits:`f5bcfa2`(T1)/`561ca59`(T2)/`f2a3618`(T3)/`902d942`(T4),未 push。
- **独立复跑全套:`Executed 1889 tests, with 11 tests skipped and 0 failures in 735.751s`(exit 0)** — 与执行方声明 1889/11skip/0fail(695.7s)计数严格一致;定向 `DefaultFaceTests` 8/0fail(0.036s)。

## 逐 AC 核对(10/10 绿)

| # | AC | 结果 | 验收证据 |
|---|---|---|---|
| 1 | 禁用集 = {filmicrgb, sigmoid, agx, denoiseprofile, nlmeans, bilateral} 恰 6 项 | ✅ | `Registry.swift:39-50` 由 6 个模块 opName **常量**构建(零字面量);`DefaultFaceTests.testDisabledSetMatchesMatrixExactly` 断言常量 == 矩阵字面集 + count==6 |
| 2 | 默认面 registry 不含禁用集;启用集 + 终端三件套可寻址 | ✅ | `gatedRegister`(:75-84,6 处调用点逐一注释矩阵行号);测试 16 探针含终端三件套 `makeBox != nil`;禁用 6 全 nil |
| 3 | 默认面种子不含禁用集;v50 sort 保持 | ✅ | `editingDefaultInstances(defaultFace:)`(:535,:671-673 filter 在 sort 前);测试钉 count==full−6、dropped==禁用集、sorted 不变式 |
| 4 | 旧 sidecar record/paramsData 字节保留 + enabled=false + typed unknownOps + 写读 round-trip | ✅ | **红线测试真伪核查通过**(见下节)——断言真实钉住 `degradedForUnknownOps`/`degradedLayerStack` 路径,字节级,非测试名游戏 |
| 5 | 预设含禁用 op 不崩/degrade;浏览器不隐藏 | ✅ | 种子源零旁路实证:`LightamerApp.seedInstances()`(:1493-1500)→ PresetController.configure(:597-601)/批量(:1408,:1425)/MCP 元数据(:966)全经收窄种子;既有 PresetApplier 面零回归(全套 0 fail) |
| 6 | UI 默认枚举面不含禁用集 | ✅ | `InspectorState.registerDefaultProviders(defaultFace:)`(:62-67)`gated()` 6 panel(:79/:84/:85/:118/:120/:122);生产 `editingDefaultInstances()` 无参调用 App/ 残留 = **0**(grep 实测) |
| 7 | MCP 默认面:list_iops 无禁用集/apply_params unknownOp/工具 19 不变 | ✅ | `makeEditingSeams`(:230-239)同源 face;`projectInstances` guard `registered || op.remove`(:619-621)typed unknownOp;`IopCatalog.ops.count==18` 守卫零改动 + default-face 15;`McpRegistrySnapshotTests` 零改动绿(全套佐证) |
| 8 | opt-in 恢复 full face(正反双向钉) | ✅ | `isFullFaceRequested`(:57-59)一行 env 口;populate/seed/panels/catalog 四面 full-face 反向钉测试在案(bare call + explicit false 双形态) |
| 9 | 全套回归 0 fail;≈1881+8..12 | ✅ | 独立复跑 **1889/11skip/0fail**(+8 = DefaultFaceTests 8 例,在预估带内) |
| 10 | diff 边界 = 申报文件集;Pipe/Sidecar 生产文件零改动 | ✅ | 4 commits `--stat` 逐一核对:代码面 = Registry/DefaultFaceTests/InspectorState/PipeCoordinator/LightamerApp/McpServerController/EditingToolset/IopCatalog + McpHostTests(D-EXEC-3 申报偏差);**`LightamerCore/` 零改动**;T4 文档 6 件(GOAL-STATE 为 plan T4.4 明示要求) |

## 红线测试真伪(round-trip 专项,任务步骤 3)

`DefaultFaceTests.testLegacySidecarWithDisabledOpsRoundTripsByteSemantics`(:163-281)读码核实:

- **default-face registry 下**构造旧 document(global history 含 **enabled** filmicrgb 非默认 params contrast=1.37 + 层链含 sigmoid contrastSkewness=0.62)。
- `degradedForUnknownOps` 断言:`unknownOp == ["filmicrgb"]`(typed)、record count 不变、`enabled == false`、**paramsData 字节相等**、paramsHash 保留、position 不变。
- `degradedLayerStack` 断言:层 `["sigmoid"]`、整层 enabled=false、chain paramsData 字节相等。
- **真实 `SidecarStore` 写盘 + `flushNow()`** → 磁盘字节 == canonical 编码(`[.prettyPrinted, .sortedKeys]`)→ **重载全量相等** → 红线字段自 RELOADED document 复验 → **二轮 degrade 幂等**。
- 结论:测试真实钉住 degrade 路径的「可读/可写/不崩/数据不丢」,非名义覆盖。

## 偏差核查结论

- **D-EXEC-1(PipeCoordinator face 注入式)——核查通过,论证成立**。实态 = `attach(registry:defaultFace:)` 注入 + 私有属性(默认 false = full face),LightamerApp 组装根一处读四路分发(populate :874 / attach :876 / registerDefaultProviders :882 / seedInstances :1497)。plan 原处方(coordinator 内 env 直读)在 no-env 测试进程中会得 `defaultFace = !false = true`,经 `coordinator.load` 的 PanelWiringTests 全量种子断言族必然全红——与 KD-2「既有测试零改动」直接冲突,归因正确;注入式后 env 仍是唯一事实源(KD-3 语义不变),KD-2 字面兑现。PanelWiringTests 71 例全套佐证绿。
- **D-EXEC-3(McpHostTests 期望元组同源 face)——核查通过,属机制耦合非行为放宽**。diff 实测仅 `import LightamerIOP` + 期望元组构造追加 `defaultFace: !LightamerIOPRegistry.isFullFaceRequested` 1 处;三形态(HTTP/InMemory/stdio)均走生产 `makeEditingSeams`,期望元组必须同 face 才构成有效断言;face 随 env 双向切换(env=1 时三形态全 18),断言强度不减。确为本 plan 唯一被改的既有测试。
- D-EXEC-2(Seams.defaultFace 字段)与 D-EXEC-4(catalog 交集过滤)同核实与声明一致。

## 矩阵复核(任务步骤 5,超抽样全集比对)

- IOP 模块 opName 全集 42 项 − passthrough_spike/dev − testgain(DEBUG) − native 2(skinSmooth/textOverlay)= **38 dt 派生**,与矩阵 38 dt 派生(6 禁 + 10 §10 直接 + 14 灰区 + 8 独有)**逐名集合相等**(comm 比对零差)。
- 6 禁用 = 6 处 `gatedRegister`(逐一注释矩阵行号);32 启用 dt 派生全部直接注册;终端三件套(colorin/colorout/gamma)在 Core `ModuleRegistry.init` 自注册、不经禁用缝(矩阵「永不禁用」成立)。
- 灰区抽验 ≥2 达标:bilat(row 24)/toneequal(row 21)/highpass(row 26)/colorbalancergb(row 27)/velvia(row 32)/monochrome(row 33)全部直接注册 = 启用,verdict 一致。

## Findings

| 级别 | 位置 | 内容 |
|---|---|---|
| minor | `M2-1-MATRIX.md:24`(§10 表标题) | 标题计数「12 + trio」与实际行数 10(rows 7-16)不符;「独有 7 + native 2」实际 8 行(rows 34-41)。头注计数口径(38 dt 派生 + gamma = 39;禁 6/启 33)本身自洽且与代码一致,**verdict 雸清无误**,纯表述瑕疵;矩阵为已签核正本,本次不改原文,留 M2-3 触及时顺手修 |
| note | — | 工作区滞留仅并行会话文件(`.work/gui-acceptance/*.jpg` 等),与 M2-1 无关,未触碰 |

## 翻账清单(本验收批)

- `.work/gsd/REQUIREMENTS.md`:M2DIS-01/02/03/05 翻 `[x]` + **Delivered** 锚点(M2DIS-03 注明半边交付、七页签留 M2-3);M2DIS-04 属 M2-3/M2-5 不动;尾加验收报告指针一行。
- `M2-1-ACCEPTANCE.md`(本文件)落盘。

## 验收测试记录

| 轮次 | 命令 | 结果 |
|---|---|---|
| 全套 | `caffeinate -dis Scripts/test-direct.sh` | Executed 1889 / 11 skipped / 0 failures,735.751s,exit 0 |
| 定向 | `caffeinate -dis Scripts/test-direct.sh 'DefaultFaceTests'` | Executed 8 / 0 failures,0.036s |

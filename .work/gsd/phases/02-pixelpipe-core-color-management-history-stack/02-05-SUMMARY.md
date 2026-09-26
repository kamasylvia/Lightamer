# Plan 02-05 — Summary

**Executed:** 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE

非破坏性核心落地：**`ModuleInstance` 身份元组 + `HistoryStack`（undo/redo/jump）+
`HistoryHash`（FNV-1a 跨进程稳定）+ D-H1 drag-end 三件套 API + `TilingPlan` 脚手架**。
Darktable 身份语义逐条翻译：`(opName, multiPriority)` 去重、UUID 引用锚（NDE-1）、
`effectiveInstances()` = `history.c:1600-1607` 的 `GROUP BY … MAX(num)` 直译、
history hash 仅折叠 enabled 项（Darktable `if (enabled)` 同构）。**EditorState 接管
history + live instance records（D-03b），PipeCoordinator 全部参数变更路径统一为
`historyDidChange()`** —— record → box 按实例 UUID 原位物化，未变参数 uniforms 与缓存
平面原样存活；SC#2 的 undo 腿自此端到端贯通（测试实证：undo 后顶行立即命中，零重算）。
Checkpoint 02-05-01 六项 lock 全部 affirmed（70cc389），CodingKeys 拼写冻结为 02-06
sidecar schema。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 02-05-01 | checkpoint:decision — D-H1..H4 + inline snapshot + 字段拼写六锁 affirmed，记录于 plan | 70cc389 |
| 02-05-02 | `ModuleInstance`（九冻结字段 + typed params 访问 + ParamsCoding/StableHash 派生）| 967a5e9 |
| 02-05-03 | `HistoryStack` + `HistoryItem`（inline snapshot）+ `effectiveInstances()` + `currentValue` | 099a7f6 |
| 02-05-04 | `HistoryHash`（enabled-only 链式折叠）+ PixelPipe `TODO(02-05)` 兑现：`decodeParamsHash(for:)` 提取为 D-H4 共享原子 | 1af9df1 |
| 02-05-05 | EditorState 拥有 history/instances + 唯一变更面；PipeCoordinator `historyDidChange()` 替换 `paramsDidChange()`、D-H1 三件套、undo/redo/jumpToHistory、load 按新 URL 重置 pristine；Core 侧 `ModuleBoxing.apply` + `ModuleRegistry.makeDefaultInstances()` | 43bef80 |
| 02-05-06 | `TilingPlan`/`Tile` 纯几何（D-20 脚手架，unwired）+ PixelPipe 头部 Phase 5 挂接注记 | c731704 |
| 02-05-07 | `HistoryStackTests`（18）+ `TilingPlanTests`（5）+ VALIDATION HIST 行 ✅ | 9e0b7b4 |
| docs | API.md 同步（Core 新 section + App 状态表/touch points）| 6eb2a28 |

## 验证（质量门全过）

- 单测：**106 tests, 0 failures, 3 skips**（83 基线零回归 + 23 新增；skip = 既有 ARW/RAW 样本项）
- 新测试覆盖（plan 验收逐项）：
  - **HIST-01/02**：commit 追加/undo-redo 指针跃迁/commit-after-undo 截断 redo 尾/jump clamp/100 项 uncapped（D-H2）
  - **去重规则**：同 `(opName, multiPriority)` 不同 UUID 取最新；jump 回 位前复活旧 snapshot（inline snapshot 语义）；不同 multiPriority 双留 + v50 排序；disabled 进 effective 不进 hash、翻 enabled 翻 hash
  - **D-H1**：live 上抛 0 条 history / commit 恰 1 条（coordinator 变更序列的 Core 级孪生，见偏差 #1）
  - **HIST-04**：golden 向量 **0x684AEC372467B526**（配方注释在源：decodeSeed 0xDEADBEEFCAFEBABE + colorin 默认 + testgain 1.5 mp0 + testgain 2.0 mp1）；跨测试方法独立重算一致；重排敏感；50.5 顺序冲突簇 tiebreak 确定性；pristine = decode seed
  - **Codable round-trip**：`ModuleInstance`/`HistoryStack`（含 redo 尾、layerScope、item UUID、position=1 中态）JSON 往返全等 —— 02-06 持久化 schema 的守卫
  - **SC#2 undo 腿端到端**：records → `ModuleRegistry.makeBox(opName:instanceID:)` + `apply` 物化 → `RenderPipeline` 缓存计数（run1 全 miss 5 → 编辑 run2 miss 3/hit 1 → undo run3 hit 1/miss 0 —— top-down 短路探测模型，见偏差 #7）；box 原位复用（同对象、UUID 不变）+ apply 字节相同 fast-path
- **grep 守卫**：`grep -rn "Hasher(" LightamerCore/Sources/Pipe/History/` = clean；`grep -n "TilingPlan" PixelPipe.swift` 仅 Phase 5 注记（unwired）
- 每任务 commit 前构建绿（最终 `BUILD SUCCEEDED`）

## 执行过程抓出并修复的缺陷

1. **测试夹具身份冲突**（非产码缺陷）：disabled 实例与 live 实例同 `(op, mp)` 被 dedup 吞掉、
   `ModuleRegistry()` 默认不含 testgain —— 夹具改 multiPriority 1 / 显式 register。
2. **undo-复活语义澄清**：一步 undo 后 `position` 仍同时含两条同身份记录，取最新——需 jump
   到位前才复活旧 snapshot；这正是 Darktable `MAX(num) ≤ history_end` 语义，测试按此修正。
3. **错误类型断言**：optional-only 的 Params（colorin/gamma）对异型 payload 宽容解码不抛错；
   换 REQUIRED 键的 `ColorOutModule.Params` 断言 typed error。

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | D-H1 集成测试以「变更序列孪生 + Core 侧物化/缓存集成」实现，coordinator 本体由构建 + 代码走查验证 | `PipeCoordinator`/`EditorState` 是 App target internal，LightamerTests 仅依赖 Core+IOP，无法 import（02-03/02-04 同先例）；plan 验收原文允许 "or code inspection" |
| 2 | 新增 `ModuleBoxing.apply(_:)` 协议要求 + `ModuleRegistry.makeDefaultInstances()`（超出 plan 产物清单） | 02-05-05 物化路径的必要缝：type-erased box 需 typed decode 才能 re-commit uniforms；pristine 记录种子需与 `makeDefaultChain()` 同源的元数据表。均为既有 public 面的最小扩展，API.md 已同步 |
| 3 | `HistoryHash.decodeParamsHash(for:)` 落在 HistoryHash 内（非独立类型） | 兑现 PixelPipe 内 `TODO(02-05)`（共享 D-H4 decode 原子）；formula bit-identical 平移，缓存行为零变化 |
| 4 | history 只存「编辑」实例；pristine trio 以 `baseInstances` 为基，rebuild = base ∪ effectiveInstances()（历史实例按 `(op, mp)` 顶替 base） | Darktable mandatory-module 语义（终检三件套常驻、历史项顶替其参数）；plan 的「instances seeded pristine」的具体化 |
| 5 | DisplayProfile stableID fold **不入 history 记录**；`historyDidChange` 物化后重新 fold | 环境身份 ≠ 用户编辑（D-COL2 与 history 正交）；记录保持 canonical，fold 只活在 box 上 |
| 6 | 按内存 history 的新 URL 重置放在 coordinator.load（`historyLoadedURL` 追踪） | Phase 2 in-memory 口径；02-06 sidecar restore 在同一 seam 顶替（两处 SEAM 注释已标） |
| 7 | undo 缓存断言为 hit 1 / miss 0（非「上游全 hit」字面） | processRec 探测自顶向下、首个 hit 即短路返回——顶行 hit 即证明整条链零重算；语义与 plan 一致，计数模型按实现校准 |
| 8 | `paramsDidChange()` 物理删除（plan 说 replace） | 无任何调用方（grep 证实）；header 生命周期表更新为 `historyDidChange()` |

## 交接给下游

- **02-06**：`HistoryStack`/`ModuleInstance` CodingKeys = sidecar schema（verbatim 持久化）；
  `HistoryHash.hash(stack:decodeParamsHash:)` + `decodeParamsHash(for:)` = 漂移检测锚；
  coordinator `historyDidChange()` = `scheduleWrite()` 挂点、`load` 的新 URL 重置分支 =
  sidecar restore 挂点（SEAM 注释就位）；未知 op 在 02-06 降级后才进 `editorState.instances`
  （物化层遇未知 op 只 log skip 兜底）
- **Phase 3**：首个滑块模块调 `beginContinuousEdit / setLiveParams / commitContinuousEdit`
  三件套（多实例连续编辑 = 每被触碰实例一条、按 iopOrder 排序提交）；新模块 register +
  （如需默认链）同步 `makeDefaultChain`/`makeDefaultInstances` 双表
- **Phase 5**：`TilingPlan` 即 tile 驱动的几何源（overlap 占位策略待 NLMeans radius/
  wavelet halo 语义顶替；PixelPipe 头部有挂接注记）
- **Phase 6**：`layerScope` 字段 + 具名快照按 D-H2/D-H3 预留位直接落，无 schema 重设计

## 环境注记

- L009 全程生效（USB 卷慢态监控）；新文件后 `tuist generate` × 2（History/Tiling 目录、测试文件）
- xcodebuild `-quiet` 偶发 "exit code 0 but produced no further output" 幻影报错——以完整日志
  `BUILD SUCCEEDED` / 退出码为准（两段式确认，未计入缺陷）

---
phase: 12
plan: "12-4"
title: "预设系统：.lightamer-preset 统一容器（kind: develop|export + SidecarInstanceRecord 同构投影 + ExportRecipe 直挂——Phase 11 移交①兑现）+ paste 同构 apply 三段复用（等价性测试 preset==paste）+ 管理器 CRUD/分类/导入导出 + Inspector 面板/批量 apply + export preset 填充 ExportState + 坏预设 typed 降级"
wave: 3
depends_on: ["12-1"]
autonomous: true
requirements: [PRES-01, PRES-02, PRES-04]
files_modified:
  - LightamerCore/Sources/Presets/LightamerPreset.swift             # 新建：容器值类型（schemaVersion 1 / kind / instances / layerStack 预留位 / exportRecipe）
  - LightamerCore/Sources/Presets/PresetsStore.swift                # 新建：Presets/*.lightamer-preset 存储 + 扫描 + 启动重扫自愈
  - LightamerCore/Sources/Presets/PresetApplier.swift               # 新建：apply = paste 三段同构（load→PastePayload 直构→composeSegment→claimBatchApply→BatchSidecarWriter）
  - App/Sources/Lightamer/UI/PresetManagerWindow.swift              # 新建：管理器独立窗口（CRUD/分类/导入导出）
  - App/Sources/Lightamer/UI/Inspector/PresetPanelView.swift        # 新建：Inspector 预设面板（应用面 + 批量）
  - App/Sources/Lightamer/UI/ContentView.swift                      # 菜单入口 + 面板挂载 + 导入导出 Panel 宿主
  - App/Sources/Lightamer/State/ExportState.swift                   # export preset 填充 exportRecipe（D-11-CONTEXT-3 升级路径）
  - App/Sources/Lightamer/UI/Inspector/IOPPanelProvider.swift       # 面板体系一席注册（如体系要求）
  - Tests/LightamerTests/LightamerPresetTests.swift                 # 新建：容器 golden/降级/L013 投影
  - Tests/LightamerTests/PresetApplierTests.swift                   # 新建：preset==paste 等价性 + partial + live 保护
  - Tests/LightamerTests/PresetsStoreTests.swift                    # 新建：存储 round-trip/自愈/坏预设 typed 降级
  - .planning/phases/12-metadata-presets-lut/12-4-SUMMARY.md
  - .planning/phases/12-metadata-presets-lut/12-4-DECISIONS.md
  - TODO.md                                                         # 12-4 勾选
  - LESSONS.md                                                      # 如踩坑
---

# Plan 12-4 — 预设系统（W3，依赖 12-1 PastePayload 同构面）

> 背景：预设 = **磁盘上的 PastePayload 同构快照**（D-12-CONTEXT-5）——一套 merge/skip 逻辑
> 服务剪贴板与预设两个入口（D-09-CONTEXT-5 skip 集正本零重写）；`ExportRecipe`/
> `ExportVariant` 已 Codable + 零哈希字段（Phase 11 移交①源码级核对：`ExportRecipe.swift:105`
> typealias + 全字段 sizing/scalePercent/format/colorSpace/yiyin/outputTag 无 hash）——直挂
> 零迁移。L013 投影面（RESEARCH §5.1 plan 期定死）：容器持久化字节里 instances 用
> **`SidecarInstanceRecord` 直接复用**（`LightamerSidecar.swift:252` internal，同在 Core
> target 零可见性改动；拼写逐键一致，decimal-String paramsHash 天然满足 one-way 格式锁）。
> apply 段2 用 `claimBatchApply` **原样**（RESEARCH §5.2：预设翻 params，thumb **该** stale
> ——与 12-1 元数据缝相反，两条路径语义对照是本 plan 的核心测试面之一）。

## read_first

1. `.planning/phases/12-metadata-presets-lut/12-RESEARCH.md` §5（容器格式/apply 复用清单/存储管理面）、§7 T7、§8.2（12-4 验收草案）
2. `.planning/phases/12-metadata-presets-lut/12-CONTEXT.md` D-12-CONTEXT-5（统一容器裁决）、继承定案节（D-09-CONTEXT-5 skip 集 / L013 / one-way 格式锁）
3. `LightamerCore/Sources/Pipe/History/PastePayload.swift`（:52 结构 + :128 `filtered(by:)` partial + 头注「Codable 形态：运行时 spelling 仅进程内」——preset 是持久化字节，投影差异即 L013）
4. `LightamerCore/Sources/Session/SessionBatchApplier.swift:65`（`composeSegment` 签名原样：root/relPaths/skipRelPaths/payload/mode/seed/selection/timestamp/label——live 保护/失败降级全继承；**行号以 :65 为准**，RESEARCH :70 为漂移值，checker I-1）
5. `LightamerCore/Sources/Session/SessionIndexStore.swift:916`（`claimBatchApply`——预设 apply 段2 **正主**：翻 params_hash + thumb stale，与 12-1 `claimMetadataApply` 语义对照）+ `BatchSidecarWriter.swift`（段3）
6. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:252`（`SidecarInstanceRecord` internal——容器 instances 投影直接复用）
7. `LightamerCore/Sources/Export/ExportRecipe.swift:105`（`ExportRecipe` typealias + `ExportVariant` Codable 零哈希 + `validate()` 位）
8. `LightamerIOP/Sources/Yiyin/YiyinFontStore.swift`（app 级目录三拆模式：会话注册/typed 错误/启动重扫自愈——PresetsStore 范本）
9. `.planning/phases/11-export-pipeline/11-DISCUSSION-LOG.md` 移交清单第 1 条（recipe 直挂 + `ExportState.defaultVariant` 为预设默认值现成形态）
10. `App/Sources/Lightamer/State/ExportState.swift` + `App/Sources/Lightamer/UI/InspectorView.swift`（面板挂载面）
11. `LESSONS.md` L009/L013/L019b/L020/L025
12. `AGENTS.md`（Phase 执行模型 + 暂停机制）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建；单测 = `Scripts/test-direct.sh '<Class>'`（**判据 = Executed 行 + failures 行，非宿主退出态**；Executed 0 = 失败防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**；零新 SPM 依赖；无 /tmp 产物入工作区；fixture 禁 UNITEK 盘（L009）。
- **one-way 格式锁**：`.lightamer-preset` 自有格式 + schemaVersion 前瞻 + sortedKeys（`LightamerSidecar.swift:7-8` 模式）；reader 容忍 `> 1` 降级；一切 UInt64 哈希 decimal String（L013——instances 走 `SidecarInstanceRecord` 即天然满足）。
- **apply 语义红线**：批量走 9-4 懒渲染语义零新渲染路径；live 保护/失败降级继承 `composeSegment` 既有面；**万张 ≤5s 门（段1+段2）延续 PERF-07**。
- **T3/T4 为 GUI 任务：需解锁控制台（Manual-Only 候补）**。
- RESEARCH 未覆盖细节（分类分组键 UI 形态/批量 apply 的进度反馈形态/预设重名策略）标注**执行期决策**入 `12-4-DECISIONS.md`。

## Tasks

### T1 `.lightamer-preset` 容器 + PresetsStore

- **action**
  1. `LightamerPreset.swift`（新建，Core/Presets）：RESEARCH §5.1 格式 verbatim——`{ schemaVersion = 1, kind: Kind = .develop|.export, name: String, category: String?（自由串，侧栏分组键）, appVersion, createdAt: Date, instances: [SidecarInstanceRecord], layerStack: SidecarLayerStackRecord?（additive 预留位，本 Phase 恒 nil）, exportRecipe: [ExportVariant]?（kind=export 时；develop 恒 nil/省略） }`；sortedKeys + tmp 原子晋升；reader 容忍 `> 1`。
  2. develop `instances` = **PastePayload compose 产物同构**（skip 集已应用：decode 域边界 15.0 / 恒等默认 / 自动检测 verbatim 三规则原样——`PastePayload.instances` 直投影 `SidecarInstanceRecord`，save 路径从剪贴板/当前图有效链取）。
  3. `PresetsStore.swift`（新建）：`~/Library/Application Support/Lightamer/Presets/*.lightamer-preset`；一预设一文件；目录扫描 + 启动重扫自愈（YiyinFontStore 三拆：会话注册/typed 错误/损坏文件跳过）；CRUD = 文件系统原子写；PRES-02 导入/导出 = 文件拷贝零格式转换（NSOpenPanel/SavePanel 宿主在 T3）。
- **证据**：`LightamerPresetTests` + `PresetsStoreTests`——sortedKeys 字节 golden / v1 缺可选字段降级读 / `>1` 容忍 / develop-export 互斥校验（develop 带 exportRecipe → typed 错误）/ 损坏文件跳过自愈 / L013 投影抽查（paramsHash 为 decimal String）。

### T2 PresetApplier：paste 同构 apply + 等价性测试

- **action**
  1. `PresetApplier.swift`（新建，Core/Presets）：RESEARCH §5.2 复用清单 verbatim——`PresetsStore.load` → `PastePayload(sourceImageID: UUID(), sourceURL: nil, instances:（记录→ModuleInstance 还原）, layerStack: nil, copiedAt: 文件时间)` → 段1 `SessionBatchApplier.composeSegment(payload:mode:)`（:70 签名原样）→ 段2 `claimBatchApply`（:916 原样——**翻 params，thumb 该 stale**）→ 段3 `BatchSidecarWriter` + `clearBatchDirty`。
  2. 部分应用（PRES-04 子集）：`payload.filtered(by:)`（:128）+ 既有 partial dialog 消费面复用。
  3. **等价性测试**（RESEARCH §7 T7）：同一 instances 集走 preset-apply 与剪贴板-paste，终态 sidecar 字节 + 索引行**全等 diff**；万张门：批量 apply 段1+段2 ≤5s（PERF-07 fixture 复用）；live 保护（skipRelPaths）/失败降级行为继承断言；坏预设（instances 含 unknown-op）= 既有 unknown-op degrade 面（不特殊处理）。
- **证据**：`PresetApplierTests`——等价性全等 diff / partial 子集语义 / live 保护 / 万张门数字入 `.work/12/perf.md` / thumb stale 正确翻转断言（与 12-1 元数据路径的 thumb 不变形成语义对照）。

### T3 管理器 UI + Inspector 面板 + 批量 apply（GUI，需解锁控制台（Manual-Only 候补））

- **action**
  1. `PresetManagerWindow.swift`（新建）：独立窗口管理器——列表（category 分组）/ 重命名 / 删除 / 分类编辑 / 导入导出（NSOpenPanel/SavePanel 文件拷贝）；「从当前图创建预设…」入口（当前有效链 → skip 集投影 → 命名 + 分类）。
  2. `PresetPanelView.swift`（新建，Inspector 面板体系一席）：develop 预设应用面（列表/双击或按钮 apply/单图与多选批量——PRES-04；批量多选走 grid 选中集 + 同一 `PresetApplier`）；partial 应用对话框复用（T2）。
  3. 菜单入口（`ContentView.swift`）+ 面板挂载；zh catalog 同批（L025）；面板四件套 + 280pt 纪律对齐既有面板体系。
- **证据**：GUI 走查记录（创建/应用/批量/分类/导入导出 round-trip——导出的文件再导入可用）；Manual-Only 未尽项登记；zh 首屏 smoke。

### T4 export preset 填充 ExportState + 坏预设降级（GUI，需解锁控制台（Manual-Only 候补））

- **action**
  1. `ExportState.swift`：kind=export 预设 → 面板读取 `exportRecipe` 填充 `ExportState`（D-11-CONTEXT-3 升级路径字面兑现；`ExportState.defaultVariant` 为「存为预设」默认值形态——移交①现成形态）；面板内联编辑面不变。
  2. load 时 `ExportVariant.validate()`（ExportRecipe.swift:70 附近）跑：坏预设（非法位深/质量越界）→ typed 错误 + 降级（YiyinFontStore 自愈姿态：条目标坏不崩、其余可用）。
  3. **LUT 引用例外文档化**（RESEARCH §5.3/D-6）：LUT iop params 存库内名引用，预设跨机器可用前提 = LUT 库另行拷贝——DECISIONS 注记，不阻塞（12-5 落库）。
- **证据**：`PresetsStoreTests` 扩段（validate 降级向量）；GUI 走查（export 预设保存→面板填充→导出产物与手配一致；坏预设标坏不崩）；Manual-Only 登记。

### T5 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1260/6skip/0fail** + 本 plan 新增，0 fail）；TODO.md 12-4 勾选；`12-4-SUMMARY.md` + `12-4-DECISIONS.md`（投影选型复核[SidecarInstanceRecord 复用]/重名策略/UI 形态/LUT 例外注记）；新教训候选评估入 LESSONS。
- **证据**：测试计数（0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 容器/存储 | golden/降级/`>1` 容忍/自愈/L013 投影 | `Scripts/test-direct.sh 'LightamerPresetTests'` + `Scripts/test-direct.sh 'PresetsStoreTests'` |
| apply 路径 | preset==paste 全等 diff + partial + live 保护 + 万张门 | `Scripts/test-direct.sh 'PresetApplierTests'` |
| export 预设 | validate 降级向量 | `Scripts/test-direct.sh 'PresetsStoreTests'`（validate 段） |
| GUI | 管理器/面板/批量/导入导出走查 + zh | 手动走查记录 + Manual-Only 登记 |
| 回归 | 全 suite 0 fail（基线 1260+新增） | `Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] 容器：schemaVersion 1 one-way 格式锁 + sortedKeys golden + `>1` 容忍 + kind 互斥校验；instances = `SidecarInstanceRecord` 复用（拼写逐键一致，L013 decimal String）；`layerStack` 预留位恒 nil；`ExportRecipe` 直挂零迁移（移交①兑现）
- [ ] apply = paste 同构三段（段2 = `claimBatchApply` 原样，thumb 正确 stale）；**preset-apply 与剪贴板-paste 终态全等**（sidecar 字节 + 索引行）；partial/live 保护/失败降级继承；万张 ≤5s 门数字入 perf.md
- [ ] 存储管理：Presets/ 目录 + 启动重扫自愈 + 导入导出文件拷贝零转换；坏预设 typed 降级不崩（含 export validate 面）
- [ ] GUI：管理器窗口 + Inspector 面板一席 + 批量 apply（PRES-04）+ export preset 填充 ExportState；zh catalog（L025）；Manual-Only 未尽项登记
- [ ] 全 suite 0 fail；每任务独立提交 + 边界查 config 开关；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS 落盘

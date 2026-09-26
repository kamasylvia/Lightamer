# Plan 12-4 — Execution Decisions

**Date:** 2026-09-27
**Executor:** ZCode executor subagent worker（Phase 12 执行模型：执行=本 worker，验收=subagent 另派）
**Scope:** 执行期决策（RESEARCH 未覆盖细节）；plan 期已定死事项不重复。

## D1 — L013 投影选型复核：`SidecarInstanceRecord` 直接复用（非新投影类型）

plan 期定的两个候选（internal 复用 vs 独立同拼写类型）取**直接复用**：容器与 sidecar 同在 Core target，`SidecarInstanceRecord` 自 06-01 T6 起 internal（非 private）即为跨文件复用预留；复用 = 拼写漂移面只有一处（record 的 Keys 注释即「a rename here = a migration」契约），独立第二类型 = 双格式迁移负担零收益。运行时面照 `LightamerSidecar` 先例：文档持有 `public var instances: [ModuleInstance]`，Codable 进出经 record 投影——App 层零 internal 泄漏。测试钉死：golden 行 `"paramsHash" : "1234567890123456789"`（decimal String）+ 与 sidecar 拼写逐键同序。

## D2 — PresetApplier 三段复用形态：整体委托 `SessionBatchApplier.apply`

RESEARCH §5.2 复用清单的三行「原样」以**一次委托**兑现：`SessionBatchApplier.apply` 内部即 段1 `composeSegment`（:65 签名原样）→ 段2 `claimBatchApply`（:916 原样）→ 段3 `BatchSidecarWriter.enqueue`（内含 `clearBatchDirty`）。手抄三段 = 第二份编排逻辑（漂移面），委托 = 剪贴板与预设共享同一条代码路径的字面形态，等价性测试的构造基础。`copiedAt` = 预设文件 mtime（诊断字段，不入合成文档，经测试确认对终态字节零影响）。

## D3 — 等价性测试的「字节全等」口径：recast-UUID 规范化后全等

9-4 语义：`PasteSemantics.paste` 每次调用重铸 payload 记录 UUID（跨图命名空间隔离，by-design 不可注入）——同一 payload 两次 apply 的 sidecar 字节**必然**在 UUID 字段上不同（剪贴板对剪贴板亦然），「逐字节全等」物理不可达。测试钉最强可达口径：索引行逐列全等（HistoryHash 不折 UUID → params_hash 天然相等）+ sidecar 字节在规范化**唯一 by-design 自由度**（实例 UUID / history item id / 每目标 imageID / fixture 提交时间戳）后逐字节全等——labels/timestamps/paramsData/排序/哈希戳/appVersion 任何一处漂移即红。诊断过程实证规范化必要性的两处泄漏（imageID 逐目标、预置项时间戳取构建时刻）均为 fixture 现实而非路径差异。

## D4 — 语义对照双 plan 断言落点

「预设翻 params、thumb 该 stale（12-1 元数据缝相反）」在 `testPresetApplyFlipsThumbAndParamsWhileMetadataPathDoesNot` 内一次跑双路：同一 fixture 库两行分别走 PresetApplier（→ thumb stale + params_hash 翻 + thumb_params_hash 旧绑定保留）与 MetadataService.setRating（→ thumb rendered 保持 + params_hash/thumb_params_hash 双不动 + rating 落）——对照面不靠两个 suite 间接互证。

## D5 — 预设重名策略：文件名 = uuid stem（身份），显示名可重复

「一预设一文件」+ PRES-02 文件拷贝导入的组合推论：身份 = 文件 stem（uuid），显示名 = 文档 `name` 字段——重名允许（列表并列展示，id 恒定）；导入恒铸新 stem（外来文件永不覆盖本地）；rename 只改文档字段不换文件。备选「name 即文件名」被否：导入碰撞需覆盖/改名策略、文件系统非法字符面、跨平台大小写问题三重负担。SmartAlbumStore 同形（uuid stem + name 字段），一致性优先。

## D6 — 分类分组键 UI 形态：自由串 + 「未分类」尾部 + 面板嵌套子菜单

`category` 自由串（RESEARCH 定死），执行期定 UI 形态：管理器 = `Section`（分类名localizedCaseInsensitive 排序，未分类殿后）；Inspector 面板 = 顶层 Menu 内按分类嵌套子菜单（证 12-4-06「Tone ›」）。无分类管理面板（自由串录入 + 编辑即全权），v1 零额外模型。`setCategory` 空/纯空白串归一为 nil（未分类），trim 面在 Core store。

## D7 — 批量 apply 进度反馈形态：继承 9-4 `BatchSidecarWriter` progress（本 plan 不新做 UI）

PRES-04 批量复用 `PresetApplier` → `SessionBatchApplier.apply(progress:)` 缝在；App 接线（PresetController.apply）暂不消费 progress 闭包——v1 反馈面 = 提交后 grid E 徽章/缩略图「进行中→重生成」既有链（走查证 12-4-04 即此链的即时性证据），万张规模对话框式进度 defer（9-4 同款边界，非预设新增缺口）。

## D8 — export preset 的 create/load 校验分工：create 拒空 recipe；load 逐 variant validate

`PresetsStore.create(kind: .export)` 强制 recipe 非空（`.emptyExportRecipe` typed——空导出预设无意义）；`readAndValidate` 对 export kind 逐 variant 跑 `ExportVariant.validate()`（sizing/quality/percent 域），任一失败 = `.invalidExportRecipe` → rescan skip + loadDocument typed。位深×格式非法对由嵌套枚举类型层不可构造（RESEARCH §1.2），运行时向量只剩连续域（quality/percent/dpi）——测试用 quality 1.5 钉死。`ExportState.applyPresetRecipe` 再验一遍（belt to braces：填充面不信任调用方来源，typed 不半填）。

## D9 — 应用入口路由：PresetController 闭包缝（D-03b 无跨态引用）

预设应用的目标路由（grid/culling 选中集 else 当前图）与 live 安装需要 browserModel/editorState/sessionState——控制器零背引，app root 注入四个闭包（targetsProvider = `metadataTargets()` 同源 12-1 路由；liveRelPathsProvider = 当前图 relPath 集；livePaste = 编辑器活体安装（EditorState.installMergePaste/OverwritePaste，ONE ⌘Z）；composeCurrent = ⌘⇧C compose 产物复用）。live 语义与 ⌘⇧V 完全同构：batch 跳过 live 目标（composeSegment 空 → claim 早退，索引零写）→ 交互层安装 → `粘贴调整` label。

## D10 — LUT 引用例外文档化（RESEARCH §5.3/D-6 注记，12-5 落库后复核）

LUT iop（Plan 12-5）params 按裁决存**库内名**引用（`Application Support/Lightamer/LUTs/` 相对名，非原始路径）。`.lightamer-preset` 跨机器可用前提 = LUT 库另行拷贝——预设格式不打包 LUT 字节（D-12-CONTEXT-5/D-6 locked）。缺失引用的行为 = iop 降级恒等 + toast（unknown-op 同款姿态，12-5 实现面）。本 plan 容器层无需任何 LUT 感知代码；Manual-Only F-12-4-3 挂账复核位在 12-5 收口。

## D11 — kind 互斥的严格度：仅钉 plan 向量，export+instances 宽容

strict 集 = plan 钉死向量（develop + exportRecipe 非nil → typed 错）。export kind 携带 instances（理论不应有）**宽容解码不报错**（apply 面由 `kind == .develop` guard 拒绝，字段不消费）——前向兼容姿态：未来版本若给 export 预设加语义（如导出时叠加调整），旧 reader 不丢数据。export + 空 recipe 在 **create** 面 typed 拒绝（无意义预设不入库），但磁盘上出现时 load 宽容（validate 逐 variant 过空集 → 可载入但不进 apply 面）。

## D12 — 面板挂载位：InspectorView 固定底部区（非 IOPPanelProvider 一席）

plan 预留「IOPPanelProvider.swift 一席注册（如体系要求）」——实测体系不要求：`IOPPanelProvider` 按 `opName` dispatch 且绑定 `InspectorEditSession`（D-H1 三件套编辑语义），预设应用不是 iop 编辑（无单实例 params 面），强塞 provider 体系 = 键不存在（opName 无）+ 编辑会话语义错配。落位 = InspectorView 底部固定区（`MetadataInfoSection` 同区先例，12-1 已立「非 iop 面」挂载先例），面板四件套纪律（identifier `presets.panel`/`presets.apply.menu` + a11y label + 高度受限区 + zh 同批）照守。`IOPPanelProvider.swift` 零改动。

## D13 — Manager 窗口形态：独立 `Window` scene + 双入口

「独立窗口管理器」落地 = app 根第二 `Window(id: "preset-manager")` scene（D-03b 状态重注入仅 presetsStore + presetController——create-from-current 走 composeCurrent 闭包，编辑态不需入 scene），入口两处：编辑菜单「预设管理器…」+ ContentView 工具条导入菜单尾项（plan「菜单入口（ContentView.swift）」字面落位）。`openWindow` 环境值驱动，`defaultSize 520×480`。

## D14 — 部分应用入口：面板菜单 `部分应用…` 项（非模态前置选择）

PRES-04 部分应用触发 = 每个预设两个动词（应用 / 部分应用…）；部分路径 = 预载 `loadDocument` → `makePayload` → 复用 09-04 `PastePartialDialog`（合并/覆盖 + InstanceKey 勾选 + 全选/全不选），提交后与全量 apply 同一 `PresetController.apply(selection:)` 路由。管理器右键不设部分应用（避免双面板对话框宿主），面板为唯一部分应用 GUI 入口（Core API 面对任意调用方开放——Phase 14 MCP-09 同源）。

## D15 — 会话 fixture 勘位：图放会话根（`Capture/` 为扫描保留排除目录）

走查首建 fixture 仿 C1 惯例放 `Capture/` 子目录 → 扫描 0 张（`SessionTreeScanner.isExcludedDirectory`：根级 `Capture/Crop/Output` 保留排除，09-01 既有语义）——图移会话根后 3 张全入。非缺陷（09-01 D 记录在案的执行决策），登记为走查环境教训：**Lightamer 会话的浏览集 = 根递归减保留目录，`Capture/` 是「摄入暂存」不是浏览位**。

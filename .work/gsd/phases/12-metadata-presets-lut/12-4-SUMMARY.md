# Plan 12-4 — Summary

**Date:** 2026-09-27
**Status:** Complete（执行申报，待验收）
**Wave:** 3（依赖 12-1 PastePayload 同构面；前置 12-2/12-3 已验收 PASS）
**Requirements:** PRES-01（develop 预设）、PRES-02（导入/导出）、PRES-04（单图/批量应用）

## 交付面

| 任务 | 交付 | Commit | 证据 |
|---|---|---|---|
| T1 | `.lightamer-preset` 容器（one-way 格式锁 schemaVersion 1 + sortedKeys + reader 容忍 `>1` + kind 互斥 typed 校验；instances 复用 `SidecarInstanceRecord` 投影 L013；`layerStack` 恒 nil 预留位；ExportRecipe 直挂零迁移）+ PresetsStore（YiyinFontStore 三拆：会话重扫/typed 错误/自愈跳过标坏不崩；CRUD 原子写 L009；PRES-02 导入导出文件拷贝零转换） | `3195c7e` | LightamerPresetTests 6（line-based sortedKeys 字节 golden + nil-省略锁 + v1 降级读 + >1 容忍 + 互斥 typed + recipe verbatim 挂载零哈希键）+ PresetsStoreTests 11（round-trip 二店重扫/损坏自愈/未来 schema 容忍/互斥 skip 邻居存活/rename+分类持久化/typed 拒绝/导入导出字节全等新 stem/删除盘先册后） |
| T2 | PresetApplier：load → PastePayload 直构 → `SessionBatchApplier.apply` 整体委托（段1 composeSegment / 段2 claimBatchApply / 段3 BatchSidecarWriter+clearBatch 全部 9-4 原样，零新 merge/index/渲染代码）；export preset 进 apply 面 = typed 拒绝 | `f211031` | PresetApplierTests 8：**等价性核心**（preset-apply vs 剪贴板-paste 同预态双目标——索引行逐列相等[HistoryHash 不折 UUID] + sidecar 字节经 recast-UUID 规范化全等）+ 语义对照双 plan 断言（预设翻 params_hash+thumb stale vs 12-1 元数据双不动）+ partial/live 保护/空预设 no-op/export typed/unknown-op verbatim+既有降级面 + **万张门 0.679s**（Debug，≤5s Release 门余量 ~7×）→ `.work/gsd/phases/12-metadata-presets-lut/perf.md` |
| T3 | PresetController（D-03b MetadataController 孪生，闭包缝四件：targets/live-rel/live-paste/compose-current + onWrite）+ PresetManagerWindow（独立窗口 CRUD/分类/导入导出/从当前图创建 + 标坏 footer）+ PresetPanelView（Inspector 一席：分类分组菜单/单图 live/多选批量/部分应用复用 9-4 对话框）+ LightamerApp 双 Window scene/命令/接线 + zh catalog +37 键 | `9d757d8` | GUI 走查 7 证据 `12-4-01..07`（详下节）+ 磁盘断言（创建文件 sortedKeys/测试链实例/paramsHash decimal String；分类编辑 Sunny/Tone 落盘；批量 b/c .lra 新写 E 徽章；删除→导入新 stem 9168AB2E 文档全等；坏文件 footer 标坏不崩） |
| T4 | ExportState.applyPresetRecipe（D-11-CONTEXT-3 升级路径字面兑现——填充=recipe 赋值，面板内联编辑面不变；`defaultVariant` 为存为预设默认值形态；逐 variant 先 validate 再赋值 typed 不半填）+ ExportPanelView 预设行（应用菜单/存为预设 sheet）+ PresetsStoreTests validate 降级向量扩段 | `0b82b0a` | PresetsStoreTests 12（+1：坏 recipe 文件 rescan skip + loadDocument typed `.invalidExportRecipe` + 邻居存活 + 好文件 recipe 过 validate）+ GUI 走查（存为预设捕获面板改值 dpi150 → 菜单填充面板 300→150 可见翻转 → **三次真实导出：预设驱动 vs 手配 150 字节全等（cmp）、手配 300 对照差异**——`导出产物与手配一致` 端到端实证） |
| T5 | 全量回归终轮 + SUMMARY/DECISIONS/TODO/GOAL-STATE/PROGRESS 收尾 | 本提交 | **1390/6skip/0fail**（441.2s） |

## 测试演变

1364/6skip/0fail（12-3 收尾基线）→ **1390/6skip/0fail**（+26：LightamerPresetTests 6 + PresetsStoreTests 12 + PresetApplierTests 8）；终轮 441.2s，0 fail、无 flake。

## AC 逐条自检

- [x] **容器**：schemaVersion 1 one-way 格式锁 + sortedKeys（prettyPrinted+sortedKeys，line-based golden 逐键有序）+ `>1` 容忍（D-S1 姿态）+ kind 互斥 typed（develop+exportRecipe → `.invalidPreset(.developCarriesExportRecipe)`，磁盘文件 rescan skip 实证）；instances = `SidecarInstanceRecord` 复用（拼写逐键一致，L013 decimal String golden 行断言）；`layerStack` 预留位恒 nil（encodeIfPresent 省略形 golden）；`ExportRecipe` 直挂零迁移（Codable round-trip 全等 + 字节零哈希键断言——移交①兑现）。
- [x] **apply = paste 同构三段**：整段委托 `SessionBatchApplier.apply`（composeSegment→claimBatchApply→BatchSidecarWriter/clearBatchDirty 原样，段2 thumb 正确 stale——`testPresetApplyFlipsThumbAndParamsWhileMetadataPathDoesNot` 与 12-1 `claimMetadataApply` 双 plan 对照断言）；**preset-apply 与剪贴板-paste 终态全等**（索引行逐列 + sidecar 字节 recast-UUID 规范化后全等，唯一 by-design 自由度=9-4 每次 paste 重铸 UUID 命名空间）；partial（`filtered(by:)` 子集语义）/live 保护（bytes 零触碰）/失败降级（9-4 原样继承）全测；万张 ≤5s 门 0.679s（Debug 记录值）入 perf.md。
- [x] **存储管理**：Presets/ 目录（app 级）+ 启动重扫自愈（corrupt/future-schema/互斥/坏 recipe 四类 typed 降级进 skippedFiles，标坏不崩永不删除，GUI footer 展示）+ 导入导出文件拷贝零转换（导出字节 == 库内字节 cmp 实证；导入恒新 stem 不覆盖本地）；坏预设 typed 降级不崩（含 export validate 面）。
- [x] **GUI**：管理器窗口（CRUD/分类/导入导出/从当前图创建）+ Inspector 面板一席（分类分组应用菜单）+ 批量 apply（PRES-04，grid 选中集 b+c 双 .lra 落盘实证）+ export preset 填充 ExportState（面板 300→150 可见翻转 + 产物字节等价）+ zh catalog（+42 键，L025 zh 标签）+ Manual-Only 未尽项登记（下节）。
- [x] **收尾**：全 suite 0 fail（1390/6/0）；每任务独立提交 + 边界查 config 开关（T1-T5 各查，`auto=true`/`paused=false`）；不 push；无 /tmp 产物入工作区（走查 fixture 全在 /tmp 与 ~/la-124-session，未混入仓库）；SUMMARY + DECISIONS 落盘。

## GUI 走查记录（控制台解锁，2026-09-26 23:33 – 2026-09-27 00:14；真实 app + `~/la-124-session` + AX/cliclick/剪贴板驱动）

app = DerivedData build-for-testing 产物（T4 后重建二进制；中途 T3 后旧产物先行走查、T4 提交前重建复验）。fixture = 3 张 64px PNG（`a/b/c.png`；a.png 经 `-la_sidecar_probe` 直启宿主种入 testgain 1.5× 编辑链）。会话结构注意：图放会话**根**（根级 `Capture/` 为保留目录被扫描排除——09-01 既有语义）。

1. **12-4-01-editor-preset-panel**：会话打开（3 张·已编辑 1），单图态 Inspector 底部「预设 暂无预设」面板在位（T3 挂载面）
2. **12-4-02-manager-empty-zh**：编辑菜单 →「预设管理器…」开独立窗口；空态 zh 文案 + 工具条（+ 从当前图创建 / 导入）
3. **12-4-03-manager-created-sunny**：从当前图创建 sheet（名称 Sunny）→ 磁盘文件断言：sortedKeys + testgain 实例（probe 编辑链经 skip 集投影——decode 域默认全滤）+ `"paramsHash" : "6481113053740982766"` decimal String
4. **12-4-04-batch-apply-bc**：网格多选 b+c → 管理器右键「应用 Sunny」→ b/c .lra 新写（`history items=1`，label=应用预设）+ E 徽章点亮（onWrite 刷新链）；live 目标零触碰
5. **12-4-05-partial-dialog-reuse**：Inspector 面板「部分应用…」→ 9-4「部分粘贴调整」对话框复用（合并/覆盖 + testgain probe 勾选 + 粘贴）
6. **12-4-06-panel-category-menu**：面板菜单分类分组「Tone ›」子菜单（应用 Sunny / 部分应用…）
7. **12-4-07-bad-preset-skipped-footer**：注入 garbage `.lightamer-preset` 重启 → 管理器 footer「已跳过的坏预设文件（保留在磁盘）： broken.lightamer-preset」，Sunny 照常可用（标坏不崩）
8. **12-4-08-export-preset-fill**：导出面板「存为预设…」捕获面板改值（dpi 150→Web150 文件 dpi:150 断言）；手配回 300 后菜单应用 → **面板 dpi 300→150 可见翻转**；三次真实导出：`la-export-preset150.jpg` == `la-export-hand150.jpg`（cmp 字节全等）、`la-export-hand300.jpg` 差异（对照）

**盘面语义链**：批量走 claim（b=应用预设 batch 提交）+ live 走交互安装（c=粘贴调整 label，batch 对 live 目标零 claim——活体保护 GUI 实证）；live 安装经编辑器 2s throttle 落盘。

### Manual-Only 登记（合成驱动限制，人工确认项）

| # | 项 | 说明 | 覆盖状态 |
|---|---|---|---|
| F-12-4-1 | 管理器重命名 alert 的观感 | 重命名与分类编辑共用同一 alert 机制（分类编辑已走查通过落盘）；重命名单项未重复走查 | 代码面 ✅ / alert 观感待人工 |
| F-12-4-2 | 部分应用「粘贴」提交的全链落盘 | 对话框弹出与复用面已走查（证 05），但未点「粘贴」完成一次 partial 落盘（`filtered(by:)` 子集语义已由 `testPartialApplyAppliesOnlyTheCheckedSubset` 单测钉死） | 服务面 ✅ / 按钮落盘待人工 |
| F-12-4-3 | LUT 引用预设的跨机器行为 | LUT iop（12-5）params 存库内名引用；预设跨机器前提 = LUT 库另行拷贝——D-12-CONTEXT-5/D-6 文档化例外，本 plan 不阻塞（DECISIONS D10 注记） | 文档化 ✅ / 12-5 落库后复核 |

## 偏离与注记

1. **申报文件落位修正**（12-2 D1/D2 先例）：`PresetController.swift`（新，App/State——apply 路由需闭包缝，plan 未申报）；`LightamerApp.swift`（第二 Window scene + 命令 + 接线宿主，plan 未申报）；`InspectorView.swift`（面板挂载位——PresetPanelView 以固定底部落位，非 `IOPPanelProvider` 一席：预设非 iop 无 opName 键，per-op provider 体系不适用，MetadataInfoSection 同区先例）；`ExportPanelView.swift`（T4 填充/存为预设 UI 宿主，plan 未申报）。
2. **PresetApplier 形态**：三段复用以**整体委托 `SessionBatchApplier.apply`** 实现（其内部即 composeSegment→claimBatchApply→writer+clearBatch 原样）——比逐段手抄更强的「原样复用」，零新管线代码。
3. **Core PresetError 增 `.emptyComposition`**（T3）：从当前图创建遇全默认链（skip 集滤空）typed 拒绝，无静默空预设。
4. **走查方法学**：中文 IME 吞 keystroke 路径输入（12-2 D14/12-3 同款）——剪贴板粘贴绕过；`screencapture` 锁屏探针 779KB >200KB（解锁走查前提成立）；万张门为 Debug 记录值（≤5s 门语义 = Release/SSD，PERF-07 口径）。
5. **观察（非缺陷）**：创建 sheet 中 AX `set value` 未触发 SwiftUI 名称绑定的个体现象（分类 alert 的 AX setValue 则正常触发）——人工键入路径不受影响；批处理走查中 b 出现两次「应用预设」提交，脚本驱动双击伪影与产品双触发无法从盘面区分，语义面（每次均为合法单提交、可 ⌘Z）无碍，等价性/批量语义已由单测钉死。

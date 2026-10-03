# M2-9-05 DECISIONS — 收口走查批（wave 4）裁决与对账终稿

> 性质：零源码收口 plan 的裁决底稿。01–04 各 DECISIONS（§1..§12/§1..§10 等）
> 为各波正本，本文件**不复制**其内容，只做：①走查十项裁决终态；②本波新发现
> F/O 台账；③zh 对账；④M2EXP-05 翻账依据；⑤挂账清单终态。晨审可逐条推翻。

## §1 KD-1 十项走查终态（证据 = `.work/gui-acceptance/m2-9/MANIFEST.md` 逐项表）

| # | 项 | 终态 |
|---|---|---|
| 1 | 五节齐备 | ✅ 截图 + AX 树双证（五节序 = Alcedo ExportInspectorPanel 对表） |
| 2 | 尺寸四模式 + 折叠区默认 | ✅ 四模式字段显隐 + Alcedo QML:27-46 首用默认（2048/2048×2048/210×297mm@300）屏上逐值吻合；折叠区 false/0 |
| 3 | 模板编辑器 | ✅ 3 内置 + Custom + typed 红错（unmatchedOpeningBrace）+ 存预设置灰 + live 预览（空 capture 缺省渲染 `-0001`） |
| 4 | 单图 DRT 联动导出元数据 | ✅ Software="Lightamer 0.1.0"（byte-scan）+ ICC=BT.1886 幂臂（Rec709 主色度 + curv 2.398≈2.4）+ 无 GPS IFD + 原尺寸 9504×6336 |
| 5 | 批量 × sequence × 子文件夹 | ✅ edit-01-0001 / img-05-0002 / img-15-0003（0001..0003 递增）落「导出」子目录（OQ-11 默认文案屏上证） |
| 6 | 冲突 FAIL 档 + 失败态 + retry | ⚠️ **FAIL 档 GUI 不可达**（§2 F-2）；失败态红字 + retry 面 ✅（decode 失败触发，AXPress retry → 翻完成） |
| 7 | 四态 + 36 帽 | ✅ 渲染中/Done/Failed 三态屏上证；46 jobs → 36 行 + 「…（还有 10 项）」精确 |
| 8 | yiyin × DRT | ⚠️ 入口 ✅（sheet 开）；**M2 出片 yiyin 恒 false**（04 裁决 M2 页无 yiyin 节）→ 出片判据无 GUI 通道，语义引 M2-9-02 E2E；待人工/晨审 |
| 9 | PQ/HLG 钳位 + ICC | ✅ Rec.2020 切换吸附 ST 2084（联动吸附直证）+ 出片 ICC = 系统 BT.2100 PQ（CICP 9/16）+ [0,1] 钳位 = OQ-8 A |
| 10 | legacy 回切 | ✅ 旧 Sessions 面 + `export.page.*` AX 零命中（页不可达）+ 旧导出路由在（File>导出… + legacy toolbar.export byte-frozen）；旧 sheet 实开需先开会话 → 待人工余项 |

## §2 本波发现台账（新）

- **F-1（error 级，非 M2-9 交付面）**：Import Folder 面板**取消即崩**（SIGSEGV，
  SwiftUI 闭包过度释放；2/2 复现；`.ips` ×2 存档于 ~/Library/Logs/DiagnosticReports/
  `Lightamer-2026-10-03-072103/-072747.ips`）。归属 M2-2/M2-3 时代导入面板，非
  M2-9 交付物 → **另案修复**（独立小修 plan；不进 M2-9 收口零 diff 红线）。
- **F-2（minor，M2-9-04 面）**：导出页格式 Picker 裸键观感（`export_format_jpeg`
  等六键）——`String.LocalizationValue("export_format_\(kind.rawValue)")` 插值
  字面量 → 查表键变 `export_format_%@`（无此键 → 回退渲染插值文本）。
  zh-audit --check PASS 不受影响（静态键在册；查表键动态不可见 = M2-7-3 xcstrings
  动态族教训同族）。**修复 = 一行**（按 kind 显式键，走 `fix(m2-9)` 验收批通道
  ——AGENTS.md Phase 执行模型条款；本 plan 零源码红线不改）。
- **O-1**：NSOpenPanel go-to sheet 合成键击不可达（IME），⌘V 粘贴可达——L032 既录。
- **O-2**：队列「清空」= cancelAllJobs（仅取消非终态），Done 行保留——命名与行为
  心智差，登记不修。
- **O-3**：模板预设 popup 初始锚 = 自定义（pattern 与 Source 内置一致时仍不锚定
  内置名）——锚定按名单不按 pattern 反查；观察项。
- **O-4**：36 帽下排位 >36 的失败行不可见（retry 随行隐藏，仅错误摘要计数）——
  大队列失败处置可达性观察项；与 36 帽裁决（Alcedo QML:47 同构）并存，登记不修。
- **O-5**：应用重启后编辑面 filmstrip 点击不进目标 provider（回落当前图 1 张）；
  同会话内 cmd+click 多选正常。KD-4 目标集=编辑面网格选择语义不变，无 defect。

## §3 04 晨审清单四项 —— 走查侧对表（终裁仍归晨审）

1. 越界三追认：04 验收已全追认；本波走查未产生新反证 → 维持追认建议。
2. 层语义（带层图 M2 面 override 腿 = base 链）：走查 #4 用无层图（edit-01 无
   layerStack），带层图腿无 GUI 新证 → 晨审裁决点维持（立项 Core layer 座位与否）。
3. 目标集 = 编辑面网格选择：走查实证（library 网格多选不入导出腿；filmstrip
   cmd+click 入腿）→ 与 04 裁决一致。
4. add/start 塌缩形态：走查实证单按钮「加入选中（N 张）」直入队即跑 → 与 04
   §8 形态一致。

## §4 zh-audit 对账（T2）

- `uv run python3 Scripts/zh-audit.py --check` → **PASS**（1398 source keys，
  1633 catalog keys，zh complete，locale codes = {en, zh}）。
- 预估 vs 实数：plan 预期「缺口补齐」（04 随手键终核）→ **实际零缺口、
  .xcstrings 零 diff**（04 波键已随手入账生效；本波无新键）。
- 动态族盲区实录：格式 Picker 查表键 `export_format_%@`（F-2）为 scanner 不可见
  动态键的现行案例——**修 F-2 后该键族自然消亡**，无需入册。

## §5 M2EXP-05 翻勾依据（T3 REQUIREMENTS 同批）

- 走查 #1/#5/#6/#7 兑现「真机观感」半边：五节观感 + 队列四态/36 帽/进度/retry
  屏上直证 + 质量四键/落点记忆默认面在案（04 单测）+ yiyin 注入器/topbar 入口在。
- 未竟子面如实挂账：FAIL 冲突档 UI（§2 F-2 同源——档位选择器未暴露）、yiyin
  M2 页节（V2/晨审）、legacy sheet 会话内实开（待人工余项）。**翻勾 = Delivered
  （M2EXP-05 全族），挂账项随注记走**（REQUIREMENTS 终注文本由 T3 同批落）。

## §6 挂账清单（phase 终态）

| 挂账 | 去向 |
|---|---|
| F-1 Import 面板取消即崩 | 独立小修 plan（M2-3 时代面） |
| F-2 格式 Picker 裸键（一行） | `fix(m2-9)` 验收批通道 |
| SidecarV5 卫生缺陷（失败路径不清 71MB 工作拷贝） | 独立小修 plan（M2-8-2 observation③ 延续） |
| L055 test-direct.sh 崩溃假绿解析器修复 | 另案报备 orchestrator（M2-9-03 起挂） |
| 走查观察项 O-2/O-3/O-4 | 挂账观察，不独立立项 |
| yiyin M2 页节 / peak-ICC 标注 / UltraHDR / EXR / 全 recipe 预设 / 细粒度元数据 UI | V2（ALCE-02/03、PRES 交汇等既有挂账延续） |
| legacy sheet 会话内实开走查 | 待人工余项（可选，sheet 面 byte-frozen 且 11-04 已验） |

## §7 机检边界（T3 终核申报）

- 本波 diff 申报集 = `.work/gui-acceptance/m2-9/**`（证据）+ `.work/gsd/phases/
  m2-9-export/M2-9-05-{SUMMARY,DECISIONS}.md` + `.work/gsd/REQUIREMENTS.md` +
  `.work/GOAL-STATE.md` + `.work/TODO.md` + `AGENTS.md`（键册六键 + M2-9 增量节）
  + `.work/LESSONS.md`（如踩坑）。**零第三类源码文件**（.xcstrings 本波零 diff）。
- BUNDLE-MAP 终对账基线 = 2693/16/0（M2-9-04 终态）；本波零新测试 → 终值不变。
- 四前波封存面抽查：ExportPanelView / ContentView legacy 臂 / LightamerApp /
  ExportQueue 引擎体 / legacy 三测试族 `git diff` = 待 T3 终核输出。

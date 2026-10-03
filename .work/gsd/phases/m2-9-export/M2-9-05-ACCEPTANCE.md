# M2-9-05 ACCEPTANCE — 收口走查批（wave 4）+ M2-9 phase 收口

**验收:** M2-9-05 独立验收 subagent（零共享上下文，实测核验不轻信；带 F-2 一行修复授权）
**Date:** 2026-10-03 午后（夜间全自动授权在案；`[gsd]` auto=true / paused=false 全程未动）
**输入:** PLAN × SUMMARY × DECISIONS（§1..§7）× MANIFEST（34 件证据）× M2-9-04-ACCEPTANCE
（基线 2693/16/0）× GOAL-STATE 续接点 × 源码/账本实读 + 机检亲跑 + 实机 GUI 复验
**对象提交链:** `7cedbf4`(T1 走查证据 34 件) → `7ccf4ec`(T2 zh 对账 + DECISIONS) →
`a40f1c4`(T3 五账同批 + SUMMARY)；**验收批追加** `afb1f88`(F-2 fix，授权通道) + 本报告 docs commit
**复跑基线树:** `afb1f88`（含 F-2 修复；build-for-testing 重建后跑）

## 结论

# PASS / 0 error + 1 minor(已修) + 3 observation

Plan 八条 AC 全部独立复核通过；全套独立复跑**单轮干净绿 `TOTAL|2693/16/0|923s EXIT=0`**
（七 bundle 逐值零漂移 = M2-9-04 终态精确对表；peakRSS 最大 IOP 6541MB < 8G 门，
零 MEMFAIL）。**零源码 diff 红线成立**：worker 三提交（2ab4f3a..a40f1c4）非
`.work/`/AGENTS.md 文件数 = **0**（亲跑）；封存面八处抽查全零行。**F-2 已修**（本验收批
`afb1f88`，常量键构造一行 + L058 注释；实机复验格式 Picker 六项全本地化，截图 ×2 落盘）。
F-1 维持另案（`.ips` 崩溃签名亲验）。判据偏差两项定性为**裁决内合理现状**（observation，
非 error——见 §五）。

## 一、全套独立复跑（单轮干净）

`caffeinate -dis Scripts/test-direct.sh --all`（含 F-2 修复树；对账基线 = M2-9-04 终态）：

| Bundle | 基线（04 终态） | 本轮 | Δ | peakRSS | 判定 |
|---|---|---|---|---|---|
| IOP | 467/1/0 | 467/1/0 | 0 | 6541MB | 零漂移 ✓ |
| IOPParity | 362/3/0 | 362/3/0 | 0 | 5998MB | ✓ |
| Layers | 298/3/0 | 298/3/0 | 0 | 1050MB | ✓ |
| Library | 437/4/0 | 437/4/0 | 0 | 310MB | ✓ |
| Sessions | 279/4/0 | 279/4/0 | 0 | 1363MB | ✓ |
| Export（红线门） | 338/1/0 | **338/1/0** | **0** | 5461MB | **零漂移 ✓** |
| App | 512/0/0 | 512/0/0 | 0 | 1313MB | ✓ |
| **TOTAL** | **2693/16/0** | **2693/16/0** | **0** | — | **精确对账** ✓ |

- 923s 单轮干净；EXIT=0；零 MEMFAIL（8G 门全过，最大 IOP 6541MB）。
- 本波零新测试（front-matter `estimated_new_tests: 0`），终值 = 对账链终值 2693。
- 对账链：2577（M2-8 终）→ 2611 → 2634 → 2662 → 2693（04）→ **2693（05 终跑，零增量）**。

## 二、三提交边界 + 零源码红线（亲跑）

| commit | 申报 | 实测 `--stat` | 判定 |
|---|---|---|---|
| `7cedbf4` T1 | 走查证据（MANIFEST + 截图/AX/元数据 dump） | 恰 **34 文件**（+108，全落 `.work/gui-acceptance/m2-9/`） | ✓ |
| `7ccf4ec` T2 | zh 对账（零缺口）+ DECISIONS 终稿 | 恰 **1 文件**（DECISIONS +91）——`.xcstrings` 零 diff = 预估偏差如实登记（04 波键已生效，无可补） | ✓ |
| `a40f1c4` T3 | 五账同批 + SUMMARY | 恰 **6 文件**（GOAL-STATE/LESSONS/TODO/REQUIREMENTS/AGENTS/SUMMARY，+127/−3） | ✓ |

- **零源码红线**：`git diff --name-only 2ab4f3a..a40f1c4` 非 `.work/`/AGENTS.md 文件数 = **0**；
  工作树源码面 `git diff HEAD -- '*.swift' '*.metal' '*.xcstrings'` = 空。
- **封存面抽查（8 处全零行）**：`ExportPanelView.swift` / `LightamerApp.swift` /
  `ExportQueueContract.swift` / `WebPEncoder.swift` / `ExportQuantizer.swift` /
  legacy 三测试族（RendererE2E/PhaseE2E/NamerTests）。
- 验收批例外 = `afb1f88`（F-2 一行修复，`fix(M2-9-05)` 授权通道——plan 风险节与
  AGENTS.md Phase 执行模型条款钦定；红线语义只约束 worker 三提交，fix 以独立提交隔离）。

## 三、F-1 / F-2 处置

### F-1（error，Import Folder 取消即崩）——维持另案，证据亲验

- `.ips` ×2 存档亲核（`~/Library/Logs/DiagnosticReports/Lightamer-2026-10-03-072103.ips`
  / `-072747.ips`）：termination = SIGNAL 11（Segmentation fault）+ EXC_BAD_ACCESS，
  栈含 `swift_release_dealloc` 帧——与申报「SwiftUI 闭包过度释放」签名一致。
- 归属 M2-2/M2-3 时代导入面板，非 M2-9 交付面；本波不修（零 diff 红线），独立小修 plan
  挂账维持（DECISIONS §6）。

### F-2（minor，格式 Picker 裸键）——已修 + 实机复验（`afb1f88`）

- **根因亲核**：`ExportInspectorView.swift:366`（修复前）
  `String(localized: String.LocalizationValue("export_format_\(kind.rawValue)"))`——
  插值字面量使查表键 = `export_format_%@`（catalog 无此键 → 静默回退渲染插值文本 =
  `export_format_jpeg` 裸键观感）。走查截图 `m2-9-07-queue-section-visible-top.png`
  格式行亲见裸键（修复前态直接物证）。
- **修复**：常量键构造一行——`String.LocalizationValue("export_format_" + kind.rawValue)`
  （先拼完整 String 再包装；与同文件 sizing picker `String.LocalizationValue(mode.labelKey)`
  现行正确形态同构）+ L058 机制注释。
- **实机复验**（Debug 重建 + m29walk 项目实走）：编辑器 → topbar 导出 → Export 页
  `export.page.format` AX **Value = "JPEG"**；展开菜单六项 **JPEG/PNG/TIFF/HEIC/AVIF/WebP
  全本地化**（JPEG 勾选）。
- **证据落盘**：`.work/gui-acceptance/m2-9/m2-9-05-f2-format-picker-fixed.png`（展开菜单
  全景）+ `m2-9-05-f2-format-menu-closeup.png`（特写）。
- **静态对账**：六静态键本就在册（`export_format_jpeg`..`webp`，zh/en 双语）→ 修复后
  `zh-audit --check` 亲跑 PASS（1398/1633，zh complete，{en,zh}）；xcstrings 零 diff 维持。

## 四、走查证据抽查（MANIFEST 十项抽 6 项深核）

| 项 | 抽查方式 | 判定 |
|---|---|---|
| #1 五节齐备 | AX tree dump 亲读（五节 header + 11 token chips + DRT readout 全在） | ✓ |
| #2 四模式 + 折叠区 | 打印尺寸截图亲读（210/297/单位 mm/300 DPI）+ 边界框/长边（另两张截图域）+ 高级折叠展开态（允许放大未勾 + 最大边 0） | ✓ |
| #3 模板红错 + live 预览 | 红错截图亲读（`{source` → 红字「模板无效——导出已禁用。 unmatchedOpeningBrace」+ 存预设置灰）+ 预览 `edit-01.jpg-0001` 两截图亲见 | ✓ |
| #4 DRT 联动出片 | 元数据 dump 亲读：9504×6336 / Software byte-scan FOUND @120（"Lightamer 0.1.0"）/ ICC = Rec709 主色度 + D50 wtpt + chad + curv γ2.398（BT.1886 幂臂）/ GPS 仅熵流噪声命中（无 IFD）——判据全过 | ✓ |
| #5 批量 sequence | listing 亲读：`edit-01-0001 / img-05-0002 / img-15-0003` 递增落「导出」子目录 | ✓ |
| #6 失败态 + retry | 失败截图亲读（红字「⚠️ 1 项失败」+ 失败行 + 重试按钮）+ retry 后 AX json 亲读（`export.queue.row_state` ×4 全「完成」） | ✓ |
| #7 36 帽 | AX json 亲读：`row_state` 恰 36 条 + 46/46 进度截图亲见；实现面 `ExportQueueFaceView.previewCap=36` + `export.queue.more` + 键「…（还有 %lld 项）」在册 | ✓（more 汇总字符串无直接屏幕工件——O-1） |
| #9 PQ 臂 | ICC dump 亲读：desc = "Rec. ITU-R BT.2100 PQ" + CICP 9/16（BT.2020/BT.2100 PQ）+ LUT A2B0/B2A0 + EXIF Software 在——OQ-8 A 判据过 | ✓ |
| #10 legacy 回切 | legacy 面截图亲读（旧 Sessions「选择文件夹以创建会话」面）；File 菜单旧「导出…」项在本验收实机 AX dump 亲见（legacy 路由保留） | ✓ |

## 五、翻账复核 + 判据偏差定性

- **M2EXP-05 翻勾**：REQUIREMENTS `[ ]`→`[x]` + Delivered 终注（走查观感半边 + 挂账
  三项随注记）——diff 亲核；01..04 四行（04 验收批已翻）注记义务逐条在（01 模型域
  1...100000/1...2400 超集域 / 02 XMP packet 默认不嵌 / 03 三档 Increment 默认 / 04
  尾平面 float32 + EXR/UltraHDR V2）→ **AC3 五条注记义务全数在案**。
- **AGENTS.md**：M2-9 增量节（载体面/递缝三件套/座位事实/模板边界/尺寸单源/DrtOutputColorSpace）
  + 键册六键 grep 各 1 命中（AC4 ✓）。
- **GOAL-STATE**：wave-4 续接点行入账（含 F-1/F-2/观察项/下一步门控）；**TODO**：M2-9
  行 `[x]` + 里程碑行更新（AC5 ✓）。
- **OQ 生效值对表**（CONTEXT :230 逐条）：走查证据覆盖 OQ-1/3/7/8/10/11/12 屏上或
  dump 直证，OQ-2/4/5/6/9 由单测 + 装配断言承载——无与裁决冲突项。
- **判据偏差两项定性 = observation（裁决内合理现状，非 error）**：
  1. **FAIL 冲突档 GUI 不可达**：OQ-5 裁决 = 三档并存「Increment 默认 + FAIL/REPLACE
     显式档」——引擎/模型三档已交付且单测钉死；M2 页固定 `.increment` 是「默认档」
     的 UI 呈现，档位选择器暴露从未单独立裁决，走查如实挂账（REQUIREMENTS 注记
     「随 F-2 通道或另案」处置去向明确）。
  2. **yiyin M2 出片恒 false**：04 验收 §八既裁「M2 页无 yiyin 节——Alcedo 对标面无
     此项」（`makeVariant()` 恒 false）；走查 #8 尊重裁决改登记入口实证 + 语义引
     M2-9-02 E2E——非本波违背，属裁决面延续（V2 页面节挂账在案）。

## 六、observation 清单（3 项，均不阻塞）

- **O-1**：#7 的「…（还有 10 项）」精确字符串无直接屏幕工件（`m2-9-07-*.json` 只采
  `row_state` ×36 元素；46=36+10 算术 + 46/46 进度截图 + previewCap/previewSlice 单测 +
  catalog 键在册构成旁证链）。证据完备性注记，非缺陷主张——状态层映射面由穷举单测钉。
- **O-2**：MANIFEST #5「shift 不生效见观察 O-3」交叉引用错位（O-3 = 模板预设锚定；
  shift 范围多选未注册为独立观察项）。文档措辞 slip，不影响任何判据。
- **O-3**：SUMMARY phase 小结节以「交接节」形态落盘（五 plan 逐 plan 战果未复刻成表，
  对账链增量隐含于 2577→2693 链；挂账清单正本在 DECISIONS §6 + TODO M2-9 行）——
  实质信息齐备（SUMMARY 头部已声明 DECISIONS 为对账底稿），形态与 plan KD-3 措辞
  有偏差，登记不补。

## 七、AC 逐条（8/8）

| # | AC | 独立核验 | 判定 |
|---|---|---|---|
| 1 | 走查十项状态落 SUMMARY/MANIFEST + 零当场修复 | MANIFEST 逐项三态表 + SUMMARY §任务逐条；T1..T3 零源码（§二亲跑） | ✓ |
| 2 | zh-audit PASS；xcstrings 面 | 亲跑 PASS（1398/1633/{en,zh}）；零缺口 → 零 diff（预估偏差如实登记） | ✓ |
| 3 | M2EXP-01..05 勾选 + 五条注记义务 | 五行 `[x]` + 注记关键词逐条 grep 命中（§五） | ✓ |
| 4 | AGENTS.md 增量节 + 六键入册 | 节 1 命中 + 六键各 1 命中 | ✓ |
| 5 | GOAL-STATE 续接点 + C 档终态；TODO 清账 | 续接点行 + C 档门控链在文；TODO M2-9 `[x]` | ✓ |
| 6 | SUMMARY phase 小结 + 挂账 + 对账链 | 对账链 2577→2693 + 挂账清单（DECISIONS §6 七行）+ 交接节（形态偏差 = O-3） | ✓ |
| 7 | 全套 0 fail = 终态计数 | `TOTAL|2693/16/0|923s EXIT=0` 单轮干净（§一） | ✓ |
| 8 | diff 边界 = 申报集，零第三类源码 | 三提交 41 文件全 `.work/`+AGENTS.md（§二）；`afb1f88` = 授权 fix 例外 | ✓ |

## 八、M2-9 phase VALIDATION 输入就绪状态（C 档第 3 停前置）

**就绪**。输入清单核点：

- 五 plan SUMMARY/DECISIONS 齐（01..05）+ 四 ACCEPTANCE（01/02/03/04 PASS）+ 本报告（05 PASS）。
- 测试对账链终值 **2693/16/0**（2577→2611→2634→2662→2693→2693，逐 plan 有验收复跑背书）。
- REQUIREMENTS M2EXP-01..05 全 Delivered（注记义务五条全落）。
- 挂账清单终态（DECISIONS §6）：F-1 另案 / SidecarV5 卫生小修 / L055 脚本修复 /
  冲突档 UI 缺口 / yiyin M2 节 + peak-ICC + UltraHDR + EXR + 全 recipe 预设 = V2 /
  legacy sheet 实开 = 待人工可选 / O-2..O-4 观察项。
- 本验收批新账：F-2 已修（`afb1f88`）——VALIDATION 汇总时应记「走查 minor 一件，
  验收批闭环」。

## 九、下一步（交接 orchestrator）

C 档第 2 停 = M2-9-05 plan 闭环汇报（本报告为输入）→ 用户确认 → **M2-9 phase
VALIDATION 签核**（C 档第 3 停；verify-work 输入 = §八清单）→ **M2-10（AI 图库）**
research 起步。F-1 Import 面板崩溃 + SidecarV5 卫生缺陷 = 独立小修 plan 候选，与
M2-10 排期由 orchestrator 裁。

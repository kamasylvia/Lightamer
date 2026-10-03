# M2-9-05 SUMMARY — 收口走查批（wave 4）+ M2-9 phase 小结

**Status:** COMPLETE（2026-10-03；执行 = ZCode subagent worker，夜间全自动授权在案，
`[gsd]` `paused=false / auto=true` 全程未动——每任务边界复查）
**提交链:** T1 `docs(m2-9): walkthrough evidence records`（本批证据 + MANIFEST）→
T2 `chore(m2-9): zh catalog reconciliation`（对账零缺口，DECISIONS 终稿）→
T3 `docs(m2-9): phase summary and requirements ledger`（翻账五账 + phase 小结）。
**不 push。**
**对账底稿:** 同目录 `M2-9-05-DECISIONS.md`（走查终态 §1 / 发现台账 §2 / 晨审
四项对表 §3 / zh 对账 §4 / M2EXP-05 翻勾依据 §5 / 挂账清单 §6 / 机检边界 §7）。
**走查证据:** `.work/gui-acceptance/m2-9/`（MANIFEST.md 逐项表 + 截图 ×20 + AX
dump ×4 + 元数据 dump ×2）。

## 数字对账表

| 项 | 基线（M2-9-04 终态） | 本波终态 | Δ |
|---|---|---|---|
| 全套 | **2693/16/0**（七 bundle = 467/362/298/437/279/338/512） | **`TOTAL|2693/16/0|968s EXIT=0`**（七 bundle = 467/1/0 + 362/3/0 + 298/3/0 + 437/4/0 + 279/4/0 + 338/1/0 + 512/0/0，逐值零漂移；peakRSS 最大 IOP 7601MB < 8G 门，零 MEMFAIL；L055 对策②崩溃签名 grep = 0 命中） | 0（零新测试，plan front-matter `estimated_new_tests: 0`） |
| BUNDLE-MAP | M2-9-04 九行（9/11/11 等） | 零改动（本波无新测试文件） | — |

- 零源码 diff 红线：`.xcstrings` 本波**零 diff**（zh-audit --check 开局即 PASS，
  无缺口可补）；`git diff --stat` 申报集 = 证据目录 + 账本 md（T3 终核输出在案）。
- zh 对账：`--check` PASS（1398 source keys / 1633 catalog keys / zh complete /
  locale {en, zh}）；plan 预估「缺口补齐」→ 实际零缺口（04 波键已随手入账生效）。

## 任务逐条（commit × 验收）

| 任务 | commit | 交付 | AC 覆盖 |
|---|---|---|---|
| T1 | docs(m2-9): walkthrough evidence records | KD-1 十项真机走查（证据 20+ 件 + MANIFEST 逐项表）：五节观感 AX+截图 / 四模式+折叠区默认 / 模板三内置+红错+live 预览 / 单图 DRT 联动出片（Software="Lightamer 0.1.0" byte-scan + ICC BT.1886 幂臂 + 无 GPS）/ 批量 sequence 0001..0003 落子目录 / 失败态红字+retry（corrupt 源触发，AXPress 翻完成）/ 46 jobs→36 行+「…（还有 10 项）」精确帽 / yiyin sheet 入口 / PQ 臂（Rec.2020 吸附 ST 2084 + 出片 ICC=系统 BT.2100 PQ CICP 9/16 + [0,1] 钳位）/ legacy 回切双向（`export.page.*` 零命中）。零当场修复（走查纪律） | AC1 |
| T2 | chore(m2-9): zh catalog reconciliation | zh-audit `--check` PASS（输出贴 §4）+ `.xcstrings` 零 diff + DECISIONS 终稿（01-04 底稿不复制、只做终态合并；F/O 台账 + 晨审四项对表） | AC2 |
| T3 | docs(m2-9): phase summary and requirements ledger | REQUIREMENTS M2EXP-05 翻勾 Delivered（走查终注）+ GOAL-STATE 续接点 + C 档终态 + TODO M2-9 行 + AGENTS.md M2-9 增量节 + **键册六键**（export.lastDirectory/四质量键/namingTemplates）+ 本 SUMMARY（phase 小结节）+ 全套终跑 + `git diff --stat` 逐文件终核 | AC3..8 |

## 红线机检（AC8，T3 亲跑输出）

- `git diff --stat`（基线 `2ab4f3a`..工作树）逐文件对表 = 申报集（`.work/gui-acceptance/m2-9/**` +
  五账 md + 本 SUMMARY/DECISIONS），**零第三类源码文件**。
- 四前波封存面抽查（零 diff 亲核）：`ExportPanelView.swift` / `LightamerApp.swift` /
  `ExportQueueContract.swift` / `WebPEncoder.swift` / `ExportQuantizer.swift` /
  legacy 三测试族（RendererE2E/PhaseE2E/NamerTests）/ `ExportQueueTests` /
  `ExportNamingTemplateStoreTests` / `LibraryLegacyGateTests`。
- BUNDLE-MAP 终对账：基线 2693/16/0（M2-9-04 终态）——本波零新测试，终值对表。

## 走查发现（全部入 DECISIONS §2，逐条有据）

1. **F-1（error，非 M2-9 面）**：Import Folder 面板取消即崩（SIGSEGV 2/2，`.ips`
   ×2 存档）——M2-3 时代导入面，另案修复。
2. **F-2（minor，M2-9-04 面）**：格式 Picker 裸键（`String.LocalizationValue`
   插值字面量 → 查表键 `export_format_%@` 不存在 → 回退裸键观感；zh-audit 静态
   PASS 不冲突）——一行修复走 `fix(m2-9)` 验收批通道。
3. **O-2/O-3/O-4**：清空=cancel 语义 / 预设锚不反查 pattern / 36 帽下隐藏失败行
   ——登记不修。
4. KD-1 判据偏差三项如实登记：FAIL 档 GUI 不可达（无档位选择器）、yiyin 出片
   M2 恒 false（04 裁决面）、legacy sheet 会话内实开（待人工可选）。

## 交接（M2-9 phase VALIDATION 输入清单 = C 档第 3 停前置）

- 五 plan SUMMARY/DECISIONS + 四 ACCEPTANCE（01/02/03/04 PASS）+ 本走查批
  （MANIFEST + DECISIONS）+ 测试对账链（2577 → 2611 → 2634 → 2662 → **2693** →
  本波终跑 **2693/16/0**（968s，单轮干净，EXIT=0，零漂移零新测试））。
- 走查新账：F-1 另案 / F-2 fix 通道 / 观察项 O-2..O-4 / M2EXP-05 挂账注记
  （冲突档 UI、yiyin M2 节、legacy sheet 实开）。
- M2-10 依赖面交接：导出管线消费面已备（ExportVariant 载体 + TaskLocal 递缝
  三件套范式 + resolveExportResolution/DrtOutputColorSpace 单源）——AI 图库
  phase 的导出汇入点按 AGENTS.md「M2-9 架构增量节」约定正本消费。

## LESSONS

- **L057 候选**：macOS 27 NSOpenPanel/NSSavePanel 的 runModal 取消路径在
  SwiftUI 宿主内可 SIGSEGV（F-1，闭包过度释放；`.ips` 两份）——任何「面板
  取消」路径需要 GUI 走查覆盖（单测盖不住 runModal 的模态返回路径）。
- **L058 候选**：`String(localized: String.LocalizationValue("a_\(x)"))` 的插值
  字面量 = 查表键 `a_%@`（非拼接结果）——catalog 无 `a_%@` 时静默回退渲染插值
  文本，裸键观感；zh-audit 静态扫描对查表键不可见。动态查表键一律先落常量
  再 `String.LocalizationValue(constant)`。

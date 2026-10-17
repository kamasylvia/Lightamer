---
phase: M7 站（Agent 互操作与壳专项——五 phase + 站收官）
slug: m7-station-close
status: validated
nyquist_compliant: true
created: 2026-10-17
validated: 2026-10-17
batch_form: station-closeout（M7-6-01 六任务 + 站级五 phase 收口矩阵）
---

# Milestone 7 站级 Validation（五 phase 收口矩阵 + SC 翻账 + 制度偏离登记 + M7-5 签核）

> **用户晨审过目待定（C 档第 3 停）**：本文档 = 站内 auto-advance 链的
> 产出（夜间全自动授权先例 D-07-3-T5-1；晨审可推翻——推翻 = 翻账重开，
> 对应 phase 面重开）。签核语义 = `status: validated` 为站内判定，用户
> 晨审确认后方为最终签核。

## 1. 站终验全套轮（SC 数字门判定式兑现）

```
TOTAL|3963/35/0|  2054s  exit 0  零 MEMFAIL  七 bundle 全 8G 门内
IOP 687/5/0 (7649MB 贴线) · IOPParity 460/3/0 (6399MB) · Layers 494/5/0 (816MB)
Library 736/4/0 (623MB) · Sessions 284/9/0 (1224MB) · Export 385/5/0 (4974MB)
App 917/4/0 (2832MB)
```

- 对账链：3860（M7-1 定罪批基线）→ 3877（M7-2 +17）→ 3905（M7-3 +28）
  → 3925（M7-4 +20）→ 3950（M7-5 +25）→ **3963（M7-6 +13）精确**。
- skip 35 构成 = 24 基线 + 11 RAW 供件缺失；七 bundle skip 与 M7-5 终态
  逐值一致（零漂移，第三种来源零）。
- 本波全套轮 = orchestrator 预批在案（plan 期）；运行监视 + MEMFAIL
  机检兜底，无需人工干预。

## 2. 五 phase 收口矩阵

| phase | 收口正本 | 判定 |
|---|---|---|
| M7-0 立项 | charter 五正本落账（ROADMAP :104；无 VALIDATION 形态——验收 = 五正本一致 ✓） | ✅ |
| M7-1 D-6 壳专项 | `phases/m7-1-shell/M7-1-VALIDATION.md`（status: validated + nyquist true——定罪批：D-6 终局定性 + upstream-only 缓解 + 零产线 ΔN=0） | ✅ |
| M7-2 MCP O1 | `phases/m7-2-mcp-o1/M7-2-VALIDATION.md`（validated——双路 PASS / 0 error + 2 minor；三路全套同值 3877） | ✅ |
| M7-3 MCP O2+O3 | `phases/m7-3-mcp-o2o3/M7-3-VALIDATION.md`（validated——双路 PASS / 0 error；3905） | ✅ |
| M7-4 MCP O4 + UQ-A2 | `phases/m7-4-mcp-o4/M7-4-VALIDATION.md`（validated——双路 PASS / 0 error + 3 minor；3925；S1 修复实证 + UQ-A2 TOCTOU 负测） | ✅ |
| M7-5 TURN-01..04 | **无独立 VALIDATION.md（载体偏差 = 制度事实，见 §5②）**——收口载体 = `M7-5-01-ACCEPTANCE.md` + `M7-5-01-ACCEPTANCE-2ND.md`（双路独立验收 PASS）+ `M7-5-SUMMARY.md`（相位级收口摘要） | ✅（签核语义见 §M7-5 signed 节） |
| M7-6 站收官 | `phases/m7-6-station-close/M7-6-01-SUMMARY.md` + `M7-6-01-DECISIONS.md` + 本文档 | ✅ |

## 3. 红线族复检记录（11 项，正本 = `M7-6-01-SUMMARY.md` §红线族表）

逐条亲跑 PASS（`beb8937c..HEAD` 全波 diff 面 + T5 commit `eba261e3`
body 记录）：①零新 SPM ②`.metal` 全域零 diff ③McpToolRegistry 面
（错误码 19 档零触 + writeCallCount 零触——setControlAdmit 装配四点 =
DECISIONS §2① 显式申报点）④FIX2③ LibraryProjectController 零 diff
第五波维持 ⑤封存面 17 件零 diff（EditorMTKView = UQ-A1 受限修改面
申报面）⑥xcstrings 尾块纯插入 +10/-0 ⑦UserDefaults 零新键 ⑧runModal
禁形零命中 ⑨插值禁形代码零命中 ⑩Project.swift 恰三行 + BUNDLE-MAP
恰三行 + tuist generate 恒末位（L041）⑪union 32 基线 + 五钉 23 零触
（McpFinalSnapshotTests 恰一行 private→internal = M7-5 移交改动权的
持权行使申报点）。

## 4. SC 表翻账（ROADMAP §Milestone 7 SC 门判定式）

| 判定式 | 判定 | 证据 |
|---|---|---|
| skill 仓机检 reference 生成 ✓ | **✓** | `SkillsReferenceTests` 两门绿（tools.md 活注册表渲染逐字节 + errors.md 19 码名断言）——注册表演进漂移随全套即红 |
| UQ-A1 解码等值测试 ✓ | **✓** | `EditorPreviewColorSpaceTests.testLegalSDRPairsPreviewSharesTheExportICCInstance`（8 对 preview === export 同实例 + ICC bytes 逐字节同）+ srgbPiecewise 真分段行为腿 + 域外回落负腿 |
| UQ-L1 交互走查 ✓ | **✓（走查配方就绪——实机走查归验收批）** | `.work/gui-acceptance/m7-6/MANIFEST.md` 六交互行 + 机检腿（LightamerSliderScrubTests 3 法：travel 映射族 / Shift 族 / begin-end 配对）。措辞降格登记见 §5③ |
| SC 数字门 = 站终验全套轮判定式兑现 | **✓** | §1 对账行（3963/35/0 exit 0 零 MEMFAIL） |

REQUIREMENTS 翻账联动：SKILLS-01 / UQ-A1 / UQ-L1 → Delivered（M7-6
commit 指针 `32b592aa`/`bac0ff76`/`4259cfd8`）。

## 5. 制度偏离登记（三件，站级汇总）

1. **omp→双 zcode 验收路由**：plan 预设验收含 omp 路；实际 = 双 zcode
   独立眼替代（M6-2..M6-5、M7-2..M7-4 同款先例，`M7-2-VALIDATION.md`
   §特殊事项 2 正本句）——晨审可裁。M7-5 双路验收同制。
2. **m7-5 无独立 VALIDATION 载体**：M7-1..M7-4 各 phase 一份 VALIDATION；
   M7-5 收口载体 = 双 ACCEPTANCE + SUMMARY（OQ-M7-6-8 裁定：补写 =
   事后追认失真，双 ACCEPTANCE 已是更重载体）。本站级文档 §M7-5 节
   承载其签核语义。
3. **UQ-L1 SC 措辞降格**：ROADMAP :110 验收形态原文「UQ-L1 交互走查 ✓」
   vs 本表「走查配方就绪 ✓（实机走查归验收批）」——M7-5 TURN-02
   「配方就绪归验收批」先例同款（MANIFEST 配方 + 机检腿在库，实机
   走查行面归验收批/用户执行）。站级 VALIDATION 以 `status: validated`
   签核时，该措辞差在此显式登记，晨审对账不再出现未解释降格。

## 6. M7-5 signed 节（前置条件 = T1 三缺陷修复后执法语义完整）

M7-5 交付（TURN-01..04）在本站级文档给 **signed** 语义。前置条件链
（M7-5-SUMMARY §Leftovers 1/2/3/6 路由兑现）：

- **major-1（setControlAdmit 生产接线零调用）→ 已修**（`ad003e88`）：
  宿主透传参案（OQ-M7-6-7 (a)）——13 个 requiresControl 工具的 typed
  拒面（controlNotHeld/controlRevokedByUser）在真宿主首次真实执法
  （真宿主 controlNotHeld 腿绿 = M7-5 第二路 e2e 实锤「落 handler
  internalError」的翻转面亲证）；embedded 经 box→startHTTPHost 单点
  装配；无头臂字节零 diff（恒放行 = D-M7-5 正确语义维持）。
- **minor-1（裸臂 agent=null 镜像谎报）→ 已修**（同 commit）：裸
  stdio/http 臂 `get_state.control.agent` = always-held 常量诚实面
  （非 null 腿绿）。
- **obs-3（acquire 复检硬化）→ 已修**（同 commit）：入口快照 + 循环
  退出后条件复检——Stop-in-final-window 不再静默吞（controlRevokedByUser）
  、并发异 holder 不再双持（controlBusy）；resume 主语义负腿绿
  （review B1 病灶拦截腿）。
- **执法语义完整性判定**：三修复 + 5 腿全绿（App 917/4/0 含）+ 全套
  3963/35/0 零 MEMFAIL——M7-5 的 turn-taking 四条 TURN 在 GUI 臂
  有了完整的门语义 + 活动卡 + Stop/resume + 无头恒持有，验收形态四条
  （双端 fixture 机检 / 活动卡走查配方 / Stop→resume 活动连续 / 无头
  恒持有负测）全部 PASS 或配方就绪归走查批。**M7-5 = signed（本站级
  载体，晨审确认后终局）。**

## 7. 挂账清算面（M7 站单一清单终态）

| 挂账 | 处置 |
|---|---|
| N2-2（get_state project 字段不对称文档句，M7-2 路由） | **收口**——SKILL.md §7 如实句（headless 携 heldByOther，GUI 臂仅 path/readOnly）；DECISIONS §8 |
| S-2（strerror 重整，让渡 Export 波） | **维持**（M7-5 让渡延续；触 Export 编码腿时随批） |
| obs-A C12（禁编辑面 AXEnabled 恒读 true） | **制度注记一行**（OQ-M7-6-10：零代码——行为门为准〔osascript 实测 commands `.disabled(gate)` 行为生效〕，AXEnabled 恒真 = 框架忠实度已知面，不产码） |
| FIX2③（LibraryProjectController 零 diff） | **第五波维持**（本波亲证；下一触 controller 面的波继续核） |
| union 快照改动权 | **用讫归还 M8**（本波唯一 diff = internal 一行持权行使；M8 若触快照面 = 显式改 + 串行禁并行注记移交下一波） |
| UQ-L1 实机走查（MANIFEST 六行） | 归验收批/用户（SC 措辞降格已登记 §5③） |
| UQ-L2（软打样） | 维持挂面不入波（立项时验收形态直接取用） |

## 8. 留痕

- 执行链 = `ad003e88`（T1）→ `32b592aa`（T2）→ `bac0ff76`（T3）→
  `4259cfd8`（T4）→ `eba261e3`（T5）→ 本 commit（T6），未 push。
- 执行正本 = `phases/m7-6-station-close/M7-6-01-{SUMMARY,DECISIONS}.md`；
  裁决正本 = `M7-6-CONTEXT.md`（D-M7-6-1..10）；规格正本 =
  `RESEARCH.md`；plan = `M7-6-01-PLAN.md`。
- 走查配方 = `.work/gui-acceptance/m7-6/MANIFEST.md`（工作树 untracked
  副本——政策 B 惯例）。
- zh-audit 双 PASS（source keys 1708→1709）+ en 单语机检零 CJK 命中。

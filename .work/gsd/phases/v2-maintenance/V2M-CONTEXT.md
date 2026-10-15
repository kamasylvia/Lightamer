# CONTEXT — V2/Maintenance 修复批 + 清算批（OQ 裁决落正本 + 批次治理正本）

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。本档 = planner 批产物：
> RESEARCH（`phases/v2-maintenance/RESEARCH.md`，2026-10-16 HEAD `5e87bbe8`
> 亲核定稿）的 OQ-VM-1..5 全部按推荐 A 裁决落正本 + 销账注记 + 两波 plan
> 治理正本。执行批（omp 或 ZCode executor）接手 `V2M-01-PLAN.md` →
> `V2M-02-PLAN.md` 串行推进。
>
> **裁决依据**：OQ-VM-1..5 五问全部采纳 RESEARCH §五推荐 A（夜间授权链 =
> 「按推荐」先例，M2/M3/M6 立项批同款；晨审可逐项推翻，推翻即 plan 修订重报）。

---

## 一、OQ-VM 裁决（全按推荐 A）

### OQ-VM-1 波次切分 = A（两波、同 research 治理）

- **波 1「缺陷修复批」= `V2M-01-PLAN.md`**：D-1 → D-2 → D-3 → D-4/D-5 顺带 →
  收口全套对账。
- **波 2「清算批」= `V2M-02-PLAN.md`**：V17 zh-audit 门扩展 + Manual-Only
  GUI 批余行 + PATCH-LIVEPLANE / RELEASE-DIRECT-INJECT 顺带候选 +
  EXPORT-PRESET-01 波尾 + （D-5 若波 1 未清则并此）。
- 执行**串行**：波 1 全套验收闭环 → 波 2 源码面开工。唯一并行口 =
  OQ-VM-5（GUI 走查行提前口，见下）。
- 不合一波（验收门混杂）、不三波（GUI 批独立即空转）——RESEARCH §四理由
  全文adopted。

### OQ-VM-2 D-2 修法路线 = A（修复批内先侦查 bisect，假说收敛前不预设修法）

- V2M-01 T2 验收标准写成三段：**bisect 裁定（RESEARCH §3.4 配方）+ 修法
  落地 + 回归钉**——修法形态留执行批按实测定，DECISIONS 申报。
- H-Aa 坐实 → automatic 收紧 / 受影响机身 v8 白名单 / 解码后通道健全性门
  三选**再裁**（仍由执行批按 bisect 实测证据裁，DECISIONS 记选择理由）；
  H-Ab / H-B 翻正则分别按 profile 臂 / sidecar 持久态路线修。
- 修法若需触 `.metal`（如健全性门 kernel 化）→ **先停手修订本 plan 申报**，
  禁静默破「`.metal` 零 diff」共同红线。

### OQ-VM-3 V2 S 件顺带范围 = A（两 S 件列波 2 顺带候选）

- PATCH-LIVEPLANE（V2-PROPOSAL §七.9）+ RELEASE-DIRECT-INJECT（§七.2）列入
  V2M-02 顺带候选，**入批与否随波 2 容量定**（执行批开工时盘点余量，容量
  不足则原样留 V2 挂账，登记不销账）。
- SESSION-LEGACY-READONLY 不入（推荐 A 明文不扩）。

### OQ-VM-4 EXPORT-PRESET-01 = A（入清算波尾）

- 入 V2M-02 波尾任务（S-M、UI 加层面、`export.*` 键族基座在位、独立性好；
  Alcedo 对标 charter 下真实 UI 面）。评估正本 =
  `research/ALCEDO-PARITY-2026-10.md` + REQUIREMENTS :401 行。

### OQ-VM-5 GUI 走查批时机 = A（D-1+D-2 验收闭环后即排）

- Manual-Only 余行走查批挂 V2M-02 T2；**提前口**：V2M-01 的 T1（D-1）+ T2
  （D-2）定向验收闭环后即可开跑走查行（走查不占源码面，与波 1 收口/波 2
  其余任务并行度高）。供件（自然样张 / 真无人像照片 / layer B 资产 / HDR
  屏 / 连拍素材 / UltraHDR 样张）由用户/orchestrator 备料；供件缺席行如实
  记 Blocked 保持，**不硬造判定**。
- 通道 = AX + CGEvent + screencapture harness（`gui-acceptance/m6-closeout/
  MANIFEST.md` 执行批注记先例：AXPress 可靠 / CGEvent 键盘路径判死 /
  多选清选不可靠——交互设计一律走 AXPress/setValue）。

---

## 二、N-1 销账勘误（正本注记）

**N-1（McpLauncher 三插值键）已清偿——从待办队列剔除。**

- M6-6 T2 rider `d63cf79c` 提前清偿；`%lld` 变体三条亲证在册
  （xcstrings:32369 / :32386 / :32403）；调用面
  `McpLauncherPanelView.swift:225/242/246` 无恙。
- 登记时点说明：M6-5 VALIDATION 挂账 #2 登记早于 M6-6 执行，「提前清偿偏差
  登记 VALIDATION §四.2」在案。**历史行（M6-5 VALIDATION 等）不改写，本节
  即勘误注记正本**（RESEARCH §B 同文）。
- 波 2 V17 任务的 Text 族活体扫描中 McpLauncherPanelView 三键应全部
  PRESENT——若首跑报 ABSENT 即勘误有误，停下上报（双保险机检）。

## 三、六项销账记录（RESEARCH §E 亲核结论，此处落账面正本）

| # | 项 | 状态 | 证据锚 |
|---|---|---|---|
| 1 | M6-1② 孤儿 fixture | **已根治销账**（M6-5 T1 `c749ee00` restore+undo 双写腿 temp 化；轮毕复扫零命中） | `M6-5-01-SUMMARY.md` T1 节 |
| 2 | M6-2#2 SessionBatchApplier 字段丢弃 | **已清偿销账**（M6-5 T2 `bd81f859` 12 字段全带 + 4 回归法） | 同上 T2 节 + `M6-2-VALIDATION.md` 补记行 |
| 3 | M6-3#2 行序方向性断言 | **已清偿销账**（M6-5 T4 `76729922`） | `M6-5-01-SUMMARY.md` T4 节 |
| 4 | M6-3#4 门③载体分叉 API 注记 | **已清偿销账**（M6-5 T5 `c651bb51`） | 同上 T5 节 |
| 5 | M6-4⑥ M6-1 四项核查 | **已履行销账**（转 M6-5 完毕） | `M6-4-VALIDATION.md` 挂账 #6 + M6-5 收口 |
| 6 | M6-5#1 minor-1 勘误正本 + M6-5#6 3843 核销声明 | **已落账销账**（闭环项） | `M6-5-01-DECISIONS.md` + VALIDATION |

其余 open 项归宿不变（RESEARCH §D/§E 正本）：Manual-Only 行 → V2M-02 T2；
legacy 只读回退 → V2 #4；PROCESS-WIRING → V2 #5（触发条件档）；EXIF 注入器
→ V2 #6；栈顶顶替/计数口径 → V2 #7；SAM CoreML → V2 #8；livePlane 残差 →
V2 #9（PATCH-LIVEPLANE，波 2 顺带候选）；charter 留置 A9/A12/A16/A19/A20
原位不动。

---

## 四、批次治理正本

- **基线**：全套 `--all` = **3848/24/0**（M6-5 T9 确认轮，三路亲跑同值）。
  两波 expected_all 均为对账式：`3848 + ΔN（执行时逐任务如实记账）`；
  **全套轮批准制 + 8G 门 + MEMFAIL 机检 + 运行中保持监视**（AGENTS 资源
  监控节；贴线 bundle 连续 MEMFAIL 先查重测顺序漂移）。
- **共同红线**（两 plan 同文执行，收口核对）：零新 SPM；UserDefaults 新键
  须 AGENTS 登记（EXPORT-PRESET-01 是本批唯一预设新键候选）；`.metal`
  零 diff（D-2 侦查裁定需要时先修订 plan 申报）；xcstrings 只许尾块纯
  插入 + `zh-audit --check` PASS 对账；`\.runModal(` App/Sources 零命中；
  `String.LocalizationValue("prefix_\(x)` 插值禁形零命中；封存面零触
  （DrtRecord / sidecar schema / V50Order / 六格式导出矩阵 / GradeCatalog /
  HistoryStack / Registry 等 AGENTS 各「架构增量」节清单）。
- **复现与探针纪律**：D-2 侦查探针 /tmp 即弃（M2-7 进程内真链探针方法论
  先例）；被杀进程 `$TMPDIR` 残留清扫（L077）；transcript 落
  `evidence/`（gui-acceptance 为 local-only gitignored 域，零 commit）。
- **缺陷走查证据域**：`.work/gui-acceptance/v2m/`（local-only）——GUI 复走
  截图 / AX transcript / bisect 目测证据落此，MANIFEST 记指针。
- **翻账义务**：每波收口 = SUMMARY + DECISIONS + AGENTS「V2-Maintenance
  架构增量」节（登记键族/门形态/终值）+ TODO 条目 + GOAL-STATE 续接点；
  ROADMAP 行翻账留 VALIDATION 批。
- **暂停开关**：`.work/config.toml [gsd]` 现 `auto=true / paused=false`
  （开工前复查）。

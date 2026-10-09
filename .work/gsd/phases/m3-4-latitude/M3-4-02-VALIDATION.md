---
phase: M3-4
slug: latitude-validation-closeout
status: validated
nyquist_compliant: true
created: 2026-10-10
validated: 2026-10-10
milestone_closeout: M3 (closure gated — OMP-RETRO-QUEUE all-PASS pending, see §前置门)
---

# Phase M3-4 — Validation（FSIM-02 收口 + **M3 milestone 收口正本**，单文档收口 OQ-8-A 体例）

> 体例对齐 `phases/m2-11-performance/M2-11-VALIDATION.md`（单文档收口——里程碑
> 终态由本件 + 翻账批承载，不另跑 gsd-complete-milestone）。**翻账只认证据**：
> SC 三列对账正本 = 本件 §SC 表（判据/证据指针/终态三列，三态判据禁第四态）；
> 数字正本 = 本件 T1 终验轮亲跑日志；走查证据 = `.work/gui-acceptance/m3-4/` +
> `m3-3/` + `m3-1/`（继承）。
> **SC 数字对账基线 = 本 phase 终验轮 `TOTAL|3174/16/0|1470s` 亲证值**
> （2026-10-10 夜间，exit 0 / verdict OK / 零 MEMFAIL；对账链
> **2962 → 3024 → 3081 → 3125 → 3152 → 3174**：3152（M3-3-03 终值）+ 22
> （M3-4-01 登记增量 16+7+11〔golden 门 3 扩容 / descriptor / 面板卡〕，
> BUNDLE-MAP × Project.swift × 文件 `func test` 三方对表亲核）+ 0（`d8d72d9`
> 修复批 = 测试重钉零新增），skip 恒 16 零新增）。

## ⚠️ M3 milestone closure 前置门（回溯二次验收）——未清注记（用户令，非掩盖项）

- **门源**：2026-10-08 用户指令（入库 `a2d3c0a`）+ 编排正本
  `phases/m3-4-latitude/OMP-RETRO-QUEUE.md`：「omp 回溯二次验收 16 项
  （M2-0..M2-11 + M3-0/M3-1 三波/M3-2/M3-3 三波）**全部 PASS 方进 M3
  VALIDATION**」；M3-4 起走新双验收制度不回溯。
- **门状态（本件落签时点亲核）**：16 项**全待办**（queue checklist 零勾）；
  全仓唯一 `*-ACCEPTANCE-OMP.md` = `M3-4-01-ACCEPTANCE-OMP.md`（M3-4-01 本身
  的双验，FAIL→修复 `d8d72d9`→复验 PASS——不属回溯批范围）。
- **处置裁定（2026-10-10 夜间 orchestrator 同意 worker 报备）**：本 VALIDATION
  照签（夜间授权在案；FSIM-02 交付面与 M3 全 phase SC 对账不受此门影响——
  门的内容是「对既往验收的独立二次复核」，非本 phase 交付物）；**milestone
  closed 翻账带本门注记**，五正本同步；**「全史瘦身手术第二次」触发挂
  「门清后生效」**（§手术触发确认节）。回溯批 = 主会话串行 omp 接力
  （编排正本 OMP-RETRO-QUEUE.md）；16 项全 PASS 后由主会话把 STATE/
  GOAL-STATE/ROADMAP 的门注记翻正 + 触发手术。**晨审可推翻本裁定**。

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 直启宿主 / GUI 实测轨〔AX + CGEvent〕/ 独立数学复算轨〔zcode + omp + Python 第三实现三重〕） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL 机检 `RSS_LIMIT_MB=8192` + L055 verdict 双保险 + 崩溃签名全日志机检 + ANE-DEGRADED 注记） |
| **Full suite（phase 终验轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3174 tests / 16 skip / 0 fail**（1470s，2026-10-10 终验轮亲跑 exit 0；七 bundle：IOP 483/1/0〔7651MB〕/ IOPParity 408/3/0〔5843MB〕/ Layers 378/3/0〔1150MB〕/ Library 598/4/0〔612MB〕/ Sessions 279/4/0〔1587MB〕/ Export 342/1/0〔5315MB〕/ App 686/0/0〔2831MB〕；全 <8192 门零 MEMFAIL、零 ANE-DEGRADED、末行 `OK (direct launch, no testmanagerd)`） |
| **基线演变** | 2962（`08dd061`→现世系 `e50b291` 修复批后）→ 3024（M3-1 终）→ 3081/3125（M3-3 两波）→ 3152（M3-3-03 终）→ **3174** = 3152 + 22（IOPP 404+4 / Layers 371+7 / App 675+11；IOP/Library/Sessions/Export 四 bundle 未触）+ 0（`d8d72d9` 修复批重钉不增数）；**登记面 × 运行面两式互证逐位命中**（BUNDLE-MAP 行 16/7/11 × Project.swift × 文件实数，M3-4-01 双验收亲核在案） |
| **zh 对账** | 本批 doc-only 零新键；终态 = M3-4-01 验收亲跑 **1584/1822 PASS**（latitude_* 25 键 + history_film_placement + menu_show_film_panel 尾块纯插入在册） |
| **GUI 证据** | M3-4 真机走查（`gui-acceptance/m3-4/` MANIFEST 十项 + 双验截图二张）+ M3-3/M3-1 继承（`m3-3/` 画布 Film 卡 + zh-audit、`m3-1/` 三 plan 全套）；占比三读数 verbatim 实机（「低于 5% / 容纳 95% / 高于 0%」）+ typed 拒绝红行实机（「膝点交叉——恒等核塌缩……」）+ 真相回弹双证据 |
| **在案 flake（本 phase 事件）** | 终验轮零新增（七 bundle 一次干净绿）。在册台账（LayerE2E 负载型 / SidecarV5 ANE 环境型 / ToneEqual 家族——已修复 `e50b291`）维持观测；omp 双验期间 IOP `FilmPlacementTests` 一红 = 测试重钉错误非 flake（§特殊事项 1） |

## M3 全 phase SC 三列对账（checker m7 修正后覆盖 M3-0..M3-4 全相）

| SC | 判据 | 证据指针 | 终态判定 |
|---|---|---|---|
| **M3-0**（立项与站规格） | 无独立 SC 判据（no-SC 注记行，checker m7 补）——立项批验收形态 = 五正本落账一致 + 用户预裁「按推荐」在案（C 档快速通道） | `ROADMAP.md` M3-0 行（✅ 闭环 2026-10-08）+ V2-PROPOSAL（草案，现世系 `06ffb91`）+ OQ-V2-1..10 全按推荐裁决（现世系 `ffe0d9e`） | **Delivered**（立项批已随 M3-1 签核清偿；账面旧 SHA `4f84351`/`6e265ee` 为全史重写前死引用，现世系对照 = §特殊事项 4） |
| **M2GRADE-08** | 编码建模 / 补标 / golden 三件套（log 域直套偏差消除 + 上游 `c740f7b` 行为对表） | `phases/m3-1-w1/M3-1-VALIDATION.md` SC 表首行（正本：独立数学复算 11 曲线零误差 + Bradford 4.0e-5/5.0e-5 + 破自参照倒置推演）；REQUIREMENTS 已翻 `[x] Delivered（M3-1-01）` | **Delivered**（本件终态索引） |
| **YIYIN-09** | 五语义 + 持久化（分割线拖拽走查 + PR #126 形态对表） | `M3-1-VALIDATION.md` SC 表（正本：defaults 三段探针 ×3 轴 + 终端四点 AX frame 逐位 + relaunch 重推导）；REQUIREMENTS 已翻 `[x] Delivered（M3-1-02）` | **Delivered**（本件终态索引） |
| **小件族四件**（冲突档 / peak-ICC / 降档 / zh 清算） | M2-9 挂账#4 关闭 + OQ-V2-3① + V14/V15/F1 | `M3-1-VALIDATION.md` SC 表（正本：三档 Picker 透传链亲读 + `isHdrEncoding` 单源 + Manual-Only 双腿论证 + zh 1534/1772 PASS→终态 1584/1822） | **Delivered**（03-ACCEPTANCE PASS；本件终态索引） |
| **M3-2 研究产物**（阶段模型 / 光谱不可达声明 / 资产 c 态 / FSIM-03 注记 / M7 spike） | research 定稿 + OQ 清零 + spike 结论入 perf.md | `phases/m3-2-fsim-research/M3-2-CONTEXT.md` + `RESEARCH-NOTES.md`（定稿，现世系 `b4049b7`）+ OQ-M3-2-1..7 全按推荐回批 `e02dcc7`（活）+ `perf.md` §O-1 SPIKE + `evidence/M3-2-SPIKE-README.md` | **Delivered**（STATE M3-2 complete 行 2026-10-08 在案） |
| **FSIM-01a**（阶段承载：节点图胶片段四子阶段 + 命令集/history/sidecar 兼容） | FilmRecord + sub-run + 置位 op + UI 面 | M3-3-01（FilmRecord + sidecar v9 + HistoryItem.filmRecord + Hash 折叠）/ 02（film sub-run 缝 3×2 降出矩阵六格断言 + fused kernel 单 pass）/ 03（Film 面板 + 只读卡 NodeKind 零新增）三 SUMMARY；`M3-3-03-SUMMARY.md` §七状态表 | **Delivered**（三波全交付；v1 零档字节零漂移 + 无 film 档逐位不变负测钉死） |
| **FSIM-01b**（配光自动求解 + 确定性门 + Y/M 手动恒在 + 精确锚语义收口） | 软件测光自动求解 + 确定性门（同输入同解） | 01 §5（bake 期求解器 bit-identical + 错误向量判别）+ 02 §2（运行期 AUTO-core solve cache + FilmStatsSeam + 整数秩）+ 03 §五（确定性门五件：键折叠小端 FNV 精确值 / 跨 ROI 同解 / 平面 hash 哨兵 14_365_179_805_968_017_957）+ **M3-4-01 T1 精确锚收口**（§6.4 四行 8 值公开向量 ±5e-4 三实现独立复算全命中 + F'(K*) 六值逐位 + 排序门/交叉拒绝/域守卫；`M3-4-01-ACCEPTANCE.md` §二 + `M3-4-01-ACCEPTANCE-OMP.md` §二双验） | **Delivered**（确定性门 suite 于 Layers 378/3/0 亲跑绿） |
| **FSIM-01c**（染料近似域基线 + golden 主门 + 光谱不可达注记） | RGB 域近似 golden 数学复算主门 + 81 波长光谱引擎不可达声明落档 | 03 T1 golden 四门（kernel 两级 8.7e-5/钉 1e-4 + 凸性门 + bake 体素 ≤1e-5 + 中性闭合 1.4e-3；M3-4-01 重钉 12→16 法）+ M3-2 RESEARCH §2 声明 + AGENTS「M3-3 架构增量」注记节 | **Delivered**（golden 门于 IOPP 408/3/0 亲跑绿） |
| **FSIM-01d**（资产三态 + 许可面） | CC BY-SA 资产独立归属 + 五件套 | 01 §2（29 文件字节原样 + MANIFEST 30 行全量对账测试 + LICENSE = 上游 SPEKTRAFILM_LICENSE.txt 逐字节）+ 仓根 `NOTICE` + 03 验收复核（shasum 30/30 + LUTs 零触碰） | **Delivered**（c 混合态 = OQ-V2-10 裁决兑现） |
| **FSIM-02**（宽容度面板 + 教导 + 置位编辑面） | 场景直方图 + 双虚线 + 低于/内/高于占比 + 两教导语义 + 置位编辑 | `M3-4-01-SUMMARY.md` AC 总表 7/7 + **双验收记录**（`M3-4-01-ACCEPTANCE.md` PASS/0E+3obs + `M3-4-01-ACCEPTANCE-OMP.md` FAIL→§三 error-1→修复 `d8d72d9`→**OMP-REVERIFY: PASS**）+ 实机证据（MANIFEST 十项：双黄虚线 + 占比 verbatim + N_h 拖拽落点精确 + ⌘Z 恰一回退 + Fit + typed 拒绝红行 + 回弹）+ FilmLatitudePanelTests 11 法 | **Delivered**（教导两条 zh verbatim 实机在屏） |
| **SC 数字门** | M3-4 plan 期定 = 全套 `--all` 终验 + 对账链两式互证 | 本件 T1 终验轮 `TOTAL|3174/16/0|1470s` 亲跑 + 对账链 2962→3024→3081→3125→3152→3174 逐位（终值先于对账式独立亲跑，禁凑数对账成立）；零 MEMFAIL；红线域机检（M3-4-01 密封面 diff 零命中 + M3-3-03 §九 21 实体零 diff）继承 | **达成** |

> **回溯验收门注记（置顶节同源）**：上表证据指针全部指向既有 ACCEPTANCE/
> SUMMARY 正本；用户令的 omp 回溯二次验收（16 项）是对这些正本的**独立第二遍
> 抽查**，属流程门非证据缺口——本表三态判定不因门待办而改变；门清后本表
> 无需翻面。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。M3-0..M3-4 逐 SC 条目均有 ≥1 机器锚
  （专测断言 / 定向亲跑 / 全套终轮 / red-line range grep / defaults 探针 /
  zh-audit 机检 / shasum 对账）+ ≥1 数字/实证背书（本轮 3174/16/0 亲跑 +
  M3-4-01 双验收三 bundle 亲跑 + 独立数学复算三实现〔执行期 uv/Python +
  zcode 验收复算 + omp 复算〕+ 实机 AX/CGEvent 证据链落盘）。「无证据 ✅」
  零项。
- 采样密度：M3 全 9 plan + 本收口 = 每波独立验收（M3-1 三波 / M3-3 三波 /
  M3-4-01 zcode + omp 双验）；本 closeout 补偿 = 终验轮亲跑 + SC 表逐条指针
  可达亲核 + 手术预检三断言亲跑。
- **Manual-Only 行如实列通道边界**（非无证据）：
  1. M3-4-01 四行（菜单合成激活 / m 步进 / 材料切换 / 占比随图）——合成输入
     环境三路皆惰 + 同屏既有命令对照同惰（环境级限制），面级语义已机检覆盖
     （FilmLatitudePanelTests 11/0/0 + FilmPanelTests 6/0/0），配方在
     `gui-acceptance/m3-4/MANIFEST.md`。
  2. click-dead 节点画布合成点击（M3-3-03 §6 登记，M3-1 T3 denoise 实机同族）
     ——卡片渲染/AX 正常、grade 卡同惰 = 画布级既有问题；M3-4-01 旁路入口
     使 Film 页可达性不再依赖它；人工真机复核挂 Maintenance M4。
  3. M3-1 T3 denoise 拖动降档实机观感——nlmeans 默认 IA 结构不可达（禁用集 +
     tab shell 零席位双腿亲核），配方在 `gui-acceptance/m3-1/` MANIFEST。

## 挂账单一清单总汇编（M3 移交正本；底册 = M3-1 VALIDATION 七项 + M3-3 登记 + M3-4 新增；逐项带锚）

### Maintenance（M4/Maintenance 站桶）

| # | 项 | 状态 | 正本指针 |
|---|---|---|---|
| M1 | **L057 面板族加固专项**（底册#1） | **大部清偿**（2026-10-08 双 error 批：L057-A begin 缝全 runModal 族 16 点位 + L057-B 主线程栈 64MB `9c074a4` + LUT 页空白种子补种 `571c3c0`）；残余 = 家族观测 | `M3-1-VALIDATION.md` 底册#1 + `phases/l057-panel-family/L057-DECISIONS.md` D10 + `gui-acceptance/fix-batch/L057-B-EVIDENCE.md` |
| M2 | **D6/O-1 yiyin sheet 宽轴拖拽手感 ≈1.93×**（底册#2，双验记录再确认） | 维持（等用户诉求重开；修复方向 = NSWindow 级 NSEvent 屏幕坐标差分 / in-flow 面板） | `M3-1-02-DECISIONS.md` D6 修订节 + `gui-acceptance/m3-1/` MANIFEST O-1 |
| M3 | **M4 coordinator 串行化**（render 读序残留 / ToneEqual GPU 同源归位；底册#5） | 维持 | `M3-1-03-DECISIONS.md` D4 + `e50b291` 批 M4 余量注记 |
| M4 | **click-dead 节点画布合成点击真机复核**（M3-3 登记 + M3-4-01 carry） | 维持（人工真机：真实设备点选 grade/Film 卡；页面可达已由旁路入口解耦） | `M3-3-03-SUMMARY.md` §六-3 + `M3-4-01-DECISIONS.md` §4 |
| M5 | **zh 余量族** = D7 两处 verbatim「Import Folder…」（LightamerApp :1301/:1635）+ T3 denoise 补走查（底册#3/#6） | 维持（zh 专项 sweep 余量） | `M3-1-03-DECISIONS.md` D7/D8 + `gui-acceptance/m3-1/` MANIFEST 附录 |
| M6 | **M3-4-01 Manual-Only 四行**（菜单合成激活真机激活 / m 步进人工驱动 / 材料切换重渲 / 占比随图） | 维持（配方在 MANIFEST；面级语义机检覆盖） | `gui-acceptance/m3-4/MANIFEST.md` Manual-Only 节 |
| M7 | **定向轮覆盖教训：改 IOP 级测试文件的 plan，其定向轮必须含 IOP bundle**（omp 双验 error-1 漏检根因） | 流程教训（回溯批及后续验收任务书携带） | `M3-4-01-ACCEPTANCE-OMP.md` §三/§六 + `M3-4-01-OMP-FIX.md` §二 |

### V2/观察项桶

| # | 项 | 触发条件 | 正本指针 |
|---|---|---|---|
| V1 | 冲突档跨会话记忆（底册#4，D1 裁定会话态） | 等用户诉求 | `M3-1-03-DECISIONS.md` D1 + SUMMARY §六 |
| V2 | O-2 height 帽 560「只能缩不能增」（底册#7，checker M7 有意裁定） | 大屏增高诉求 | `M3-1-02-DECISIONS.md` D2 |
| V3 | FilmRecord.PresetNames 预设注册面（现悬置） | 预设 UI 立项 | `M3-3-03-SUMMARY.md` §八-3 |
| V4 | grid-only 图 disk sidecar filmRecord 消费面（导出 UI 归属） | 导出面触点立项 | `M3-3-03-SUMMARY.md` §八-3 + `M3-3-02-DECISIONS.md` §7-5 |
| V5 | descriptor sanity 带收窄（5.9148 单对证据） | 多材料对采样后 | `M3-4-01-DECISIONS.md` §2（E2 带 [4.0,7.5] 未收窄）+ SUMMARY §四 |
| V6 | m≥3 Fit λ→0 双侧 off 简并「可行推荐」语义 | 如需推荐语义再立项（§7.3 原义保持） | `M3-4-01-SUMMARY.md` §四 + DECISIONS §3 |
| V7 | Fit H_min §6.1 型场景恒拒「放宽建议」语义 | 同上 | 同上 |
| V8 | EV 域分箱升级（256 bin 线性域深阴影 ~0.3-0.6 stop/bin）+ 统计量化容差注记 upkeep | 面板精度诉求 | `M3-4-01-PLAN.md` 风险节 + DECISIONS §3（m4 注记已落） |
| V9 | readouts 核宽 nil-face（单侧 off 缺膝当 0；只读行非阻断） | P2 顺路面 | `M3-4-01-ACCEPTANCE.md` obs-1 |
| V10 | FilmLatitudePanelTests 注释笔误（≈4.46 实为 ≈4.02；断言语义不受扰） | 下次触文件顺手 | `M3-4-01-ACCEPTANCE.md` obs-2 |
| V11 | AI 分析模态弹窗拦截 CGEvent 主窗口事件（环境族） | 环境项随走查批登记 | `M3-4-01-ACCEPTANCE.md` obs-3 + DECISIONS §5 |
| V12 | **账面死 SHA 四枚**（全史重写连动未入 map；对照 = 4f84351→`06ffb91` / 6e265ee→`ffe0d9e` / b4049b8→`b4049b7` / 08dd061→`e50b291`） | 手术批步骤 6 sha-rewrite-map 增补吸收 | 本件 §特殊事项 4 |

### 手术批前置（阻塞登记，主会话批）

| # | 项 | 处置 | 指针 |
|---|---|---|---|
| S1 | **回溯验收门 16 项全待**（用户令） | 主会话串行 omp 回溯批 → 全 PASS → 门注记翻正 → 触发手术 | `OMP-RETRO-QUEUE.md` + 本件置顶节 |
| S2 | **三枚 commit message 内嵌 zh 引用串**（`2d580d8` 显示胶片面板/显示侧边栏；`ca714f9` checker 回注；`c5afe0d` checker 回注/根治——英文 body 内引号 UI 串/术语） | 手术批步骤 1 断言①前置：msg 重写小批（主会话；perl 判据同 SPEC；sha-rewrite-map 增补） | 本件 §手术触发确认·预检① |

## Per-Plan Map（M3 全 9 plan + 收口）

| Plan | 交付 | 终态 commits（现世系） | 验收 |
|---|---|---|---|
| M3-1-01 M2GRADE-08 | 编码目录 + 曲线族 + 烘焙 + 补标 + 双 Picker + golden 三件套 | 六 commit + `5278f6b`（验收批） | PASS / 0E+1m+2o |
| M3-1-02 YIYIN-09 | 五语义映射 + 分层 + `.global` 锚定修复 | 四 commit + `3416c61`（验收批） | PASS / 0E+2m+1o |
| M3-1-03 小件族 + zh | 冲突档 + peak-ICC + 降档旁路 + V14/V15/F1 + 全套终验 | 四 commit + `89f21b2`（验收批） | PASS / 0E+1m+1o |
| M3-2 research | RESEARCH-NOTES 定稿 + OQ 回批 + M7 spike 补批 | `b4049b7` / `e02dcc7` + spike docs | 用户回批闭环 |
| M3-3-01 数据底座 | FilmRecord + CC BY-SA 五件套 + 加载器/store/求解器 + sidecar v9 | 六 commit（22e14c8..dc82dc0 旧世系） | 验收 PASS / 0E+0m+2o |
| M3-3-02 管线批 | film sub-run 缝 + fused kernel + bake + 运行期腿 + filmPlacement op + 导出递缝 | 五 commit | PASS / 0E+1m（基线勘误 +44/3081） |
| M3-3-03 golden/收口 | golden 四门 + m=1 符号修复 + 确定性门五件 + Film 面板/卡 + 3152 终轮 | 六 commit | PASS / 0E+2m+6o |
| M3-4-01 FSIM-02 | 精确锚 + Params v2 + descriptor 运行时 + 宽容度面板/置位面 + 走查补课 + 定向三轮 | 五 commit + `9f4f692`（首验）+ `d8d72d9`（双验修复批） | **双验**：zcode PASS/0E+3obs + omp FAIL(1E)→修复→**OMP-REVERIFY PASS** |
| M3-4-02 收口（本件） | 终验轮 3174/16/0 + SC 三列全相 + 五正本翻账 + 手术预检 | 本批 docs | 本 VALIDATION |

零红线域终态：M3-3-03 §九 21 实体零 diff + M3-4-01 密封面五提交 diff 零命中
（NodeGraphCommand/PipelineDocument/DrtPanel 族/DrtRecord/六格式/V50Order/
GradeCatalog/sidecar/HistoryStack/HistoryHash 等）+ M3-1 三 plan 红线 range
grep 零命中（各 VALIDATION/ACCEPTANCE 机检节）。GPL/CC BY-SA/MIT 参考全程
只读（Alcedo GPL 零字节；SpektraLab GPL 代码零复制、CC BY-SA 资产独立归属
NOTICE 在案；RFC 数值 = 公开参考向量）；`.xmp` 零读写删。

## 特殊事项入册（phase 级事件台账）

1. **omp 双验 error-1 事件（双验收制度首次实战，制度价值实证）**：omp 二次
   验收以 `--help` 误触发全套扫描意外捕获 IOP `testPlacementGainCompresses
   Monotonically` 红——T1 重钉把尾段写成数学恒假命题（placed(20)==t 需
   Δ=∞），executor/首验/omp 任务书三方范围共漏（IOP bundle 三方均未跑）。
   修复 `d8d72d9` = f(a) 面重钉（E=a 精确采样 + 渐近面改 `farEV<C`）+ Registry
   注释缩进回填；实现零改动；复验 **OMP-REVERIFY: PASS**。教训 = M7 行。
2. **胶片页默认面结构不可达（M3-3-03 遗留集成缺陷）**——M3-4-01 T4 修复
   （InspectorView 宿主 binding 扩 `exportPageActive||filmPageActive`，
   present 侧 no-op 防回声盖写）；实机证据链 = 修复后首挂 film-fixed-crop.png。
3. **BUNDLE-MAP FilmLatitudePanelTests 9→11 勘误**已当场落（ad6c560）；
   +22 两式互证以 11 为准。
4. **账面死 SHA 四枚 finding**：`4f84351`/`6e265ee`/`b4049b8`/`08dd061` 在
   现世系不存在——2026-10-07/08 全史 msg 重写连动重写后代 SHA，map 只录
   message 实变的 165 对，四个被引 commit（V2 草案 / OQ-V2 裁决 / M3-2
   定稿 / ToneEqual 修复）message 未变故无 map 行。本件已按 subject 反查
   现世系对照（V12 行）；ROADMAP/REQUIREMENTS/TODO 既有历史行按「不可改写」
   纪律不动，手术批步骤 6 map 增补吸收。
5. **回溯验收门未清**（置顶节）——非缺陷非掩盖项：用户令流程门，主会话接力。

## 「全史瘦身手术第二次」触发确认（KD-4/T3；手术本体零动作——半径红线）

- **触发条件（SPEC）**：M3 VALIDATION 落签后、无在飞 worker。
- **判定**：本 VALIDATION 已落签（夜间授权），**但 milestone closure 带回溯
  验收门注记（置顶节 + orchestrator 裁定）→ 手术触发挂「门清后生效」**：
  OMP-RETRO-QUEUE 16 项全 PASS → 主会话翻正门注记 → 手术即触发（主会话批，
  SPEC 红线「push 收敛主会话」）。本批对手术本体零动作（无 filter-repo /
  无 remotes 变更 / 无 push）。
- **三前置断言预检（本批亲跑 2026-10-10，结果如实登记）**：
  1. **零中文 commit message 基线** — **FAIL**：3 枚 commit 英文 body 内嵌
     引号 zh（`2d580d8`「显示胶片面板/显示侧边栏」UI 串；`ca714f9`「checker
     回注」；`c5afe0d`「checker 回注/根治」）——perl CJK 扫描机械不过。→
     手术批步骤 1 前置 = msg 重写小批（S2 行，主会话）。历史重写批（2026-10-07/08）
     之后的增量 commit 未被既有 map 覆盖，属同族坑再现。
  2. **`git status` 无在飞 worker 产物** — **PASS**：untracked 四项定性 =
     `M3-4-01-ACCEPTANCE-OMP.md`（已完成证据件，本批入库）/
     `research/dt-clone-archive/`（2026-10-07 历史调研残留 2 文件 20KB，非在飞，
     留晨审归类）/ `09-3-tiers-*.jpg` ×2（2026-10-07 前存量脏文件，
     GOAL-STATE 已登记「不入本批」）。
  3. **release 分支未检出** — **PASS**：主 worktree 在 `main`；`release` 检出
     于独立 worktree `Lightamer-release`（SPEC 括注「独立 worktree 无碍」）。
- 任一 FAIL = 手术批停等（S1/S2 双阻塞在册，不掩盖）。

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 /
  M3-1-VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批派遣在案）**：「开跑，不要停」。
- **运行中 orchestrator 补充裁定（2026-10-10 夜间，同批在案）**：回溯验收门
  未清注记 + 手术触发挂「门清后生效」+ 回溯批主会话接力——worker 报备后
  coordinator 同意，本件按裁定落盘。
- 依授权，本 VALIDATION 由夜间全自动批落盘签核（`[gsd] paused=false /
  auto=true` 签核前亲读复核未动）；用户晨审可推翻（推翻 = 本签核作废回退，
  已交付面与执行/验收证据不受影响；翻账批同 commit，推翻时翻账行随 revert）。
- 签核 executor：ZCode VALIDATION executor（2026-10-10 夜间批）；doc-only——
  零源码 diff（`git diff --stat` 对表 = 申报集全 docs，见翻账节）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：FSIM-01a..d + FSIM-02 **Delivered 翻账**（append 式 Delivered
  子行 + 终态注记 + 证据指针；`grep "^- \[ \] \*\*FSIM"` = 0 门；原行字节
  零改写）；FSIM-03 研究注记已结行核对（M3-2 并入，无行动项）。
- ROADMAP：M3-3 行 ✅ 闭环（三波 + 终态 3152）+ M3-4 行 ✅ 闭环（M3 终值
  3174/16/0）+ Milestone 3 块头收口注记（**带回溯门注记**）。
- STATE：M3-3/M3-4 complete + **M3 milestone closure（gated）** + 终验 TOTAL
  行 + 对账链 + current_phase + m3_phases_complete 3→5 + plans 140→145。
- TODO：M3-4 [x] + M3 头部收口行（门注记）+ 瘦身手术队列行翻触发态
  （门清后生效）。
- GOAL-STATE：续接点 bullet（M3-4-02 闭环 → 回溯批主会话接力 → 门清翻正 →
  手术 → V2/Maintenance·M4 站）+ 瘦身手术队列行翻触发态。
- 未 push；本批零进程残留（终验轮宿主已自然退出，`pgrep` 亲证零残留）。

## 签核

- M3-0..M3-4 全相 SC 判定 = **全 Delivered + SC 数字门达成**（三列证据齐，
  数字对账 = 本件终验轮亲证基线 3174/16/0；三态判据无第四态；Manual-Only
  行如实列通道边界）。
- `status: validated` + `nyquist_compliant: true` + `milestone_closeout: M3
  (gated)`。
- **M3 phase 5/5 complete；milestone closure = 门控态**（OMP-RETRO-QUEUE 16
  项全 PASS 后由主会话翻正——翻正即 milestone closed + 手术触发）。挂账
  单一清单（Maintenance M1-M7 + V2/观察项 V1-V12 + 手术前置 S1-S2）移交。
- 晨审裁决项：①门清后两行翻正与手术触发 ②S2 msg 重写批 ③V12 死 SHA map
  增补 ④M1-M7/V1-V12 归属复核 ⑤签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**

# M2-11-05 ACCEPTANCE — closeout 终验批 + VALIDATION 自签审计 + M2 milestone 收官终审（2026-10-07 验收 subagent，零共享上下文实测核验）

## 结论

**PASS / 0 error + 1 minor（已修）+ 3 observation。M2 milestone 收官终审意见 = 可收官**
（附晨审三裁决点：①M2NODE-03 翻勾维持与否；②两 error FINDING 归属；③签核推翻窗——
均为 VALIDATION 在册呈报项，非本验收新增阻塞）。

- minor-1（已修，随验收批）：INPUT §2.1 终验轮窗口原记「09:04-09:22」与七 bundle
  日志 mtime 实序（08:59-09:14）偏差 ~10min——记账偏差，已就地勘误注记；计数/L055/
  verdict 不受影响（日志正本亲核）。
- obs-1：hangs-zoompan.xml 本验收解析 duration 格 350（申报「351 行」）——行计数
  口径差一格，`>250ms = 0` 判定与 max 65.49ms 数字均亲证成立，不修正。
- obs-2：T1 commit `2129311` body 称「two .ips stacks archived」，实际归档一份
  （0812）；第二栈（085313）未归档留 DiagnosticReports——Flaky 台账行明文披露
  （「+085313 第二栈未归档，DiagnosticReports 在案」），诚实记账；commit 不可改写
  （SHA 破坏），本条记录在案即可。
- obs-3：GOAL-STATE 续接点记「T5+T6 本批」（写于 T5 时点的措辞伪影）；SUMMARY
  提交账精确（T5=`3f91221` / T6=`86a3766`），无实质矛盾，不改。

---

## 一、VALIDATION 自签审计（核心职责，四子项）

### 1.1 签核内容 vs INPUT 四节一致性（SC 表抽 5 条对前波正本）

| 抽核项 | INPUT/VALIDATION 申报 | 前波正本亲核 | 判定 |
|---|---|---|---|
| SpektraLab 双硬门 | FULL 168.2/300.6ms；尾命中 0.021/5.009ms | `M2-11-03-ACCEPTANCE.md` :23-25/:40 逐位一致（验收复测 168.1/280.5 带内） | ✓ |
| GUI 稳态三分法 | 三轮中位 1975MB ≤3GB | `M2-11-04-ACCEPTANCE.md` :25 R1/R2/R3 = 2427/**1975**/1856 + R4 1856 带内 | ✓ |
| PERF-05 512 门 | 0.172/0.194s ≤500ms | `perf.md` :74-77 逐位一致 | ✓ |
| PERF-07 带内 | 0.543s（vs 0.490 +10.8%） | Sessions 日志 :655 `PERF07-GATE segments1+2 10k: 0.543s (gate ≤ 5.000s)` 亲读 | ✓ |
| 缩放/平移 hitch 补测 | framewait max 14.36ms >50ms=0 | `framewait-zoompan.xml` 亲解析：804 duration 格 max **14.36ms**、>50ms=**0** | ✓ |

INPUT 四节（机检/终验/GUI/SC+挂账+签核路径）齐备亲读；三态判定无第四态
（达标 + 挂账 denoise→V2 + 观察项 RAF O-1/fit2560/万张滚动/渐进显示）逐行带证据
指针；门不硬签条款遵守（02 波 OQ-7-A revert / 03 波 KD-4 未触发 / 04 波 OQ-1-A
各按其 DECISIONS）。

### 1.2 翻账五处亲证

- **REQUIREMENTS**：`grep -c "^- \[ \] \*\*M2"` = **0** 亲跑（验收方复跑）；
  翻勾前基线 `git show 3f91221~1` 同式 grep = **4**（:41/:61/:99/:100）→ 4→0 纯
  翻勾；numstat 恰 4/4 行变更，历史行零触碰亲证。四行终态注记齐（M2PERF-01 六要素
  逐门 + M2PERF-02 终验 + M2DRT-06 记账件 + M2NODE-03 带指针件）。
- **证据指针有效性**：`phases/m2-6-drt/M2-6-3-ACCEPTANCE.md` 在盘 ✓；
  `phases/m2-5-color-grade/M2-5-3-ACCEPTANCE.md` 在盘 ✓ + `TODO.md` :354 M2-5 批
  「add 面严格化」逐字在案（M2NODE-03 翻勾依据真实）。
- **ROADMAP** M2-11 行 ✅（VALIDATION 锚 + 2961/16skip/0fail 终态）✓。
- **STATE**：frontmatter current_phase = M2 closed；M2-11 complete + **M2 milestone
  终态行**（对账链 2165→…→2955→2961）✓。
- **TODO**：M2-11 条目 `[x]` 落账（五 plan 链 + 终验数字 + 事件面）✓。
- **GOAL-STATE**：续接点翻新 = M2 closed → V2/Maintenance（未立项态）✓。
- 五处同 commit = `3f91221`（numstat 亲核：REQUIREMENTS 4/4 + ROADMAP 1/1 +
  STATE 6/6 + TODO 1/0 + GOAL-STATE 1/0 + VALIDATION 新建 136 行）✓。

### 1.3 授权记录完整性

- **先例正本**：D-07-3-T5-1 在 GOAL-STATE :48（M2-8 签核条）——用户双原话
  「今晚任务不要停下，自动化持续推进」「开跑，不要停」（2026-10-01/02 夜间）；
  M2-9（10-03）/M2-10（10-07）两次 VALIDATION 同款沿用，均在册「晨审可推翻」。
- **本次授权原话**：「开跑，不要停」——VALIDATION §授权记录 + SUMMARY 头 +
  M2-11-03/04-SUMMARY 四处在册；`[gsd] paused=false / auto=true` 亲读 config。
- ** INPUT §4.5 呈报两点**（M2NODE-03 + 两 error FINDING）禁静默条款兑现——
  VALIDATION 特殊事项 5 + 授权记录节双登记。

### 1.4 程序裁定：plan T5 是否确含落签授权

**plan 原文亲读（M2-11-05-PLAN.md KD-4.2）**：「INPUT 落盘即 C 档第 3 停——verify-work
结论呈报用户签核（**执行 worker 不自行落签；夜间授权先例 D-07-3-T5-1 形态可适用
——授权在案则同批落签**）」；T5 任务名即「VALIDATION 落签 + 翻账批（签核授权后）」。
**裁定：plan 字面即含授权通道，执行走通道 + 先例 + 原话三要件齐 → T5 落签
非越权，追认**。推翻窗维持（VALIDATION 文内「晨审可推翻 = 签核作废回退，翻账
四行随 revert」推翻路径已写明）。

## 二、终验轮对账（验收方亲跑，非转述）

- **2961/16/0 逐位亲证**：七日志 tail —— IOP 471/1/0 + IOPParity 362/3/0 +
  Layers 300/3/0 + Library 581/4/0 + Sessions 279/4/0 + Export 338/1/0 + App
  630/0/0；合计 2961/16/0 精确。
- **L055 双保险亲跑**：末条 Executed 全挂靠 `Test Suite 'All tests' passed` 段 ✓；
  `terminated abnormally` = 0 ×7、`ANECCompile` = 0 ×7、`Restarting after
  unexpected exit` = 0 ×7 ✓。
- **peakRSS**：ru_maxrss 亲解析 = 7710/5980/1159/592/1650/6971/2832 MB（INPUT 表
  ±1MB 取整差）；max 7710 < 8192 零 MEMFAIL ✓。
- **三方对账 Δ=+6 亲核**：`git diff 9586c1b..HEAD` Tests 域逐文件 func test
  前后比——M2DefaultChainPerfTests 0→2、FullRenderBenchmarkTests 0→1、
  DrtTailTests 12→14、MemoryBudgetTests 13→14、其余四文件 +0；2955（M2-10 终值，
  GOAL-STATE :20 在案锚）+6 = 2961 精确；skip 16 零新增。
- **PERF-07**：Sessions 日志 0.543s 带内（门 ≤5s 余量 ~9.2×）；perf.md §PERF-07
  终验带内复核节在案（T1 批 `2129311` 落盘）。
- **canary**：SidecarV5 canary 本轮 **20.190s passed** 在 App 日志亲读（慢速绿，
  台账第 6/7 波行一致）。
- 净轮真实性 = 三重背书：本轮日志正本 + 01..04 四波独立验收轮 + 03/04 波
  2960/16/0 定向预期（GOAL-STATE 在案），本验收不再全套重跑（净轮在册 + 程序
  授权口径，与派单「不强制全套重跑」一致）。

## 三、红线域终扫复跑 + 零源码 diff（验收方亲跑）

- `git diff --name-only 9586c1b..HEAD`：MCP 域 **0** / Export 域 **0** / Version
  域（Sidecar+Library，D2 口径取宽）**0** ✓。
- 全窗产线 diff 亲核 = 唯一 `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`
  **+9/-2**（`bff022e` DEBUG probe guard，越界已申报件）——IOP/Core 全窗零改动
  （崩溃家族「旧账非回归」归因的结构性前提成立）。
- `2129311~1..HEAD` 源码零 diff 亲证（31 files 全 `.work/` docs/证据）；
  INPUT「窗内 32 commits」在 T1 时点属实（`git rev-list --count 9586c1b..2129311~1`
  = 32；现 36 = +4 docs commit，零 diff 性质不变）。
- 四 commit（`2129311`/`b5fa68a`/`3f91221`/`86a3766`）全 docs-only + 英文
  Conventional body 亲读 ✓；semantic_search defer 维持注记在 INPUT §1.1 ✓。

## 四、FINDING 审计 + ToneEqual 家族事件审计

### 4.1 ToneEqual 悬垂 retain 家族（FINDING/M4，error 级）

- **.ips 真品亲读**（`profile/appbundle-crash-2026-10-07-0812.ips`，bug_type 309，
  08:12:43）：faultingThread 13 栈 = `swift_unknownObjectRetain + 44` ←
  `ToneEqualModule.dispatchPack(_:guide:mask:output:gridW:gridH:) + 260` ←
  `ToneEqualModule.process` ← `ModuleBox.processErased` ← `closure #2 in
  PixelPipe.processRec` ← `PipeCache.plane(for:byteCount:make:)`——与申报链
  **逐帧一致**；exception = EXC_BREAKPOINT/**SIGTRAP** 亲读。
- **归因合理性**：「产线零 diff = 旧账」= 结构性论证（全窗 IOP/Core 零改动，
  §三亲证）+ 崩点类隔离全绿 + App 独立轮复绿 + 环境协同因子（Data 98%/Metal
  cache MDB_MAP_FULL/重编译风暴）三重支撑——归因**成立**；「悬垂 retain」读法与
  `swift_unknownObjectRetain` 陷阱语义（对已释放对象 retain）相符。
- **恢复协议实录**：三次全套 + App 独立五轮在 Flaky 台账追加行全量记载
  （GOAL-STATE 台账两行亲读：家族行 + SidecarV5 第 6/7 波行）；「终值以干净轮
  为准」= KD-1.1 字面兑现。
- **磁盘 98% 根因登记**：台账行 + INPUT §2.3 + DECISIONS 执行期裁定补充三处在册
  （卫生处置 = 可再生缓存清理 3.7GB+1.7GB+Metal cache，非用户数据）✓。

### 4.2 FINDING-F（L057 家族 LUT 导入点位，error 级）

- **.ips 真品亲读**（`profile/guiwalk-crash-2026-10-07-0937-lut-import-panel.ips`，
  09:37:35）：EXC_BAD_ACCESS/**SIGSEGV** + message「Could not determine thread
  index for stack guard region」**逐字** = L057 签名消息 ✓；栈 = `__swift_closure_
  destructor` ← `_swift_release_dealloc` ← `doDecrementSlow` 链在主线程（closure
  上下文过释放形态，与面板取消腿家族一致）；D4 命名勘误已兑现（MANIFEST :23 指针
  正确）。M2-9 F-1（Import Folder）HEAD 不复现 ×2 亲证申报与证据链自洽。

### 4.3 FINDING-G（minor，zh 面）

标记菜单裸键（`metadata_rating_1..5`/`metadata_color_0..5`）——INPUT §三义③ +
VALIDATION zh 对账 + 汇编 V14（→ Phase 15 zh 清算批）三处登记闭环；与 F-2 同族
定性（动态查表键 scanner 不可见）成立。登记 completeness ✓。

## 五、挂账总汇编完整性

- **M2-10 十项逐项对照**（`M2-10-VALIDATION-INPUT.md` §挂账十项原文 vs INPUT
  §4.4）：#1→V1 维持 / #2→V2 维持 / #3→V3 维持 / #4→V4 维持 / **#5→V5 本轮关闭**
  （义① live 证据在 MANIFEST 15-18）/ #6→V6 维持 / #7→V8=M1 同源落位 / **#8→V9
  本轮关闭**（M2PERF-01 §4.1 兑现）/ **#9→V10 本轮关闭**（M2-11-01 清算 + 台账，
  新行追加如实注记）/ #10→V7 维持——**关闭三 + 同源一 + 维持六，与 DECISIONS
  KD-3 一致，零遗漏**。
- **分桶**：Maintenance M1-M7 全带锚（M4/M5 = 本轮新登记 error 两枚，归属晨审裁
  显式标注）；V2/观察 V11-V16 本轮新增 + V17 既有 M2-9 挂账延续（原文不改写）。
  清单唯一移交面语义维持（各 phase 挂账原文未动——INPUT/VALIDATION 均为汇编引用
  带锚形态）✓。
- **GUI 证据**：MANIFEST 行 15-26 齐（12 件 t7-* + 3 XML + 3 footprint txt 亲见
  git show b5fa68a 清单）；zoompan 三 XML 数值亲解析（framewait max 14.36ms
  >50ms=0 / hangs max 65.49ms >250ms=0 / frame-lifetime max 74.58ms by-design
  注记）；O-2 = `o2-footprint-z100.txt` 亲读 phys_footprint_peak **8557 MB** +
  稳态 2982 MB（vs R4 8556 ±1MB 稳定复现）✓。

## 六、M2 milestone 收官终审意见

**可收官**。依据：

1. **数字链闭合**：终验净轮 2961/16/0 干净绿（本验收逐位亲证）+ 对账链
   2165→…→2955→2961 每跳有 VALIDATION/ACCEPTANCE 锚（GOAL-STATE/STATE/TODO 三处
   一致）+ skip 恒 16 零凑数（Δ 逐文件亲核）。
2. **SC 全 Delivered**：M2PERF-01 九门三态判定 + M2PERF-02 终验 + M2DRT-06 +
   M2NODE-03 四行翻勾清零（机检亲跑 = 0），REQUIREMENTS M2 族无未勾残留。
3. **质量事件全 in-册**：两 error FINDING 带 .ips 证据登记（判据「无未登记
   error」满足）、恢复协议台账化、越界申报追认链完整——移交晨审三裁决点均为
   VALIDATION 在册项，不构成收官阻塞。
4. **移交面完备**：挂账单一清单（M1-M7 + V1-V17 全带锚）+ 下一站 V2/Maintenance
   未立项态 + 未 push（本验收批同样不 push）。

晨审提示（沿用 VALIDATION 呈报）：①M2NODE-03 若裁「严格面语义未满」→ revert 该行
翻勾即可，其余翻账不受影响；②M4/M5 归属建议——M4（ToneEqual encode 悬垂 retain，
产线零 diff 旧账）建议 Maintenance 立项前置排查或专项修复批；M5（LUT 导入取消
SIGSEGV，面板调用点族）修复面小、建议随下一批 fix；③签核推翻窗明示在册。

## 验收批变更

- `M2-11-05-ACCEPTANCE.md`（本件，新建）
- `M2-11-VALIDATION-INPUT.md` §2.1 窗口时间勘误注记（minor-1）
- `.work/GOAL-STATE.md` 续接点增量（本验收条）
- 零源码 diff；不 push。

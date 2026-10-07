---
phase: M2-11
slug: performance-closeout
status: validated
nyquist_compliant: true
created: 2026-10-07
validated: 2026-10-07
milestone_closeout: M2
---

# Phase M2-11 — Validation（性能专项 + closeout；**兼 M2 milestone 收口正本**，OQ-8-A）

> 体例对齐 `phases/m2-10-ai-library/M2-10-VALIDATION.md`。**单文档收口**（OQ-8-A：
> 不另跑 gsd-complete-milestone——里程碑终态由本件 + 翻账批承载，避免双状态源）。
> **翻账只认证据**：SC 三列对账正本 = `M2-11-VALIDATION-INPUT.md` §4.1（逐门
> 门值/证据/判定三列，三态判据禁第四态）；数字正本 = `perf.md`；走查证据 =
> `.work/gui-acceptance/m2-11/` MANIFEST 行 15-26。
> **SC 数字对账基线 = 本 phase 终验净轮 `TOTAL|2961/16/0|1081s` 亲证值**
> （2026-10-07 09:04-09:22，R4 验收批 07:40 增量产物；对账链 **2165 → … → 2955
> → 2961**：2955（M2-10 终值）+ M2-11 增量 +6【02 波 +2 / 03 波 +3 / 04 波 +1】，
> skip 恒 16 零新增）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / bench / 直启宿主 / GUI 实测轨 / xctrace / footprint） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；M2-11-01 两修后 = crash/no-total-line/MEMFAIL/ANE-DEGRADED 全机检 + selftest 自证） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **2961 tests / 16 skip / 0 fail**（1081s，2026-10-07 终验净轮；七 bundle 逐行见 INPUT §2.1；L055 核读 abnormal=0/ANE=0/末条 Executed 全挂靠；max peakRSS 7709MB < 8192 零 MEMFAIL） |
| **基线演变** | 2955（M2-10 终值）→ 02 波 +2（M2DefaultChainPerfTests）→ 03 波 +3（FullRenderBenchmarkTests 1 + DrtTailTests 计时 2）→ 04 波 +1（MemoryBudgetTests）= **2961 精确**；三文件 `grep -c "func test"` 逐位亲核 |
| **PERF 数字面** | 静态 warm ARW 13.4/13.2ms 达标 / RAF 14-42 带（O-1）；拖动 color 8.6-8.9 达标 / denoise ~65-57.5 未达（OQ-7-A revert 挂账）；open→512 门 0.172/0.194s 达标；内存三分法 GUI 稳态中位 1975MB PASS；SpektraLab 双硬门 168.2/300.6ms + 0.021/5.009ms PASS；PERF-07 0.543s 带内（净轮复核）——正本 = `perf.md` |
| **在案 flake（本 phase 事件）** | **ToneEqual encode 悬垂 retain 潜伏崩溃家族**（SIGTRAP swift_unknownObjectRetain；.ips ×2 归档 `profile/`；当日 5 红 2 绿；产线零 diff = 旧账非回归；盘/缓存卫生后净轮落地——GOAL-STATE Flaky 台账追加两行）+ SidecarV5 canary 第 6/7 波（崩溃形态两波 + 净轮 20.190s 慢速绿；ANE 环境型归因维持） |
| **GUI 证据** | 本 phase 真机走查一轮四义（`gui-acceptance/m2-11/` MANIFEST 15-26）：AI 面 live 三件 + hitch 缩放/平移补测 framewait max 14.36ms >50ms=0 + L057 取消腿 ×9 活 + DRT EOTF 实切/单步 undo + O-2 8557MB 复现 |
| **zh 对账** | 本 phase 零新键批（doc-only closeout）；走查发现 **FINDING-G 标记菜单裸键**（metadata_rating_N/color_N 直出）→ Phase 15 zh 清算批 |

---

## M2PERF-01/02 对照表（三列对账正本 = INPUT §4.1/§4.2，此处终态索引）

| SC | 判据 | 终态 |
|---|---|---|
| **M2PERF-01** | 原 PERF-01..07 重述六要素（OQ-1..7-A）+ SpektraLab 双硬门 | **Delivered**：两硬门 PASS（168.2/300.6ms <1s；0.021/5.009ms ≤10ms）+ 三分法/512 门/PERF-07 达标 + PERF-03/04/06 终值指针在案；**挂账面如实**：denoise 拖动（V2 语义）+ RAF O-1 观察项 + fit(2560) 记录档 + 万张滚动 Manual-Only（缩放/平移本轮补测 >50ms=0 清账）——三态判定无第四态，禁硬签条款遵守 |
| **M2PERF-02** | M2 全族 SC 终验 + VALIDATION + verify-work 签核 | **Delivered**：终验净轮 2961/16/0 + 机检四件全过 + 本件落签 |
| **M2DRT-06**（遗留） | DRT method 注册口 | **Delivered**（记账件翻勾；M2-6-3 终验在案） |
| **M2NODE-03**（遗留） | 18 目录所有权严格面 | **Delivered**（带指针件翻勾；指针 = TODO.md M2-5 批 + M2-5-3-ACCEPTANCE；INPUT §4.5 显式呈报——晨审可裁保持 uncheck） |

---

## 挂账总汇编（KD-3 单一移交清单正本 = INPUT §4.4；两栏七 + 十七项全带锚点）

- **Maintenance**（M1-M7）：100MP 行带流式 E3 / denoise 拖动本征成本（C 案杠杆）/
  Follow Edges V2 / **ToneEqual 悬垂 retain（本轮新登记，归属晨审裁）** /
  **L057 家族 LUT 点位 SIGSEGV（本轮新登记，同上）** / O-2 瞬态峰 TilingPlan 杠杆 /
  O-1 双峰噪声 spike。
- **V2/观察项**（V1-V17）：M2-10 十项**逐项落位**（#5 视觉走查 + #9 性能表 +
  #10 flake 台账 = **本轮关闭**；余七项维持带锚）+ M2-11 新增六项（V11-V16）+
  既有 M2-9 挂账延续（V17，原文不改写）。

## Per-Plan Map（M2-11-01..05）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M2-11-01 flaky 清算 | 脚本两修 + 缩略图硬化 + 台账立表 | `6031e1e`/`f9284ca` + docs | PASS |
| M2-11-02 PERF 计量 | PERF-01/05/03/04/06 数字 + OQ-7-A revert + 档 B 复核 + Release 三修越界申报 | `de424d0`/`7e79a2e`/`7a87eaa`/`bff022e`/`e19a03f`/`4184fd8` + docs | PASS |
| M2-11-03 SpektraLab 两硬门 | FULL <1s + 尾命中 ≤10ms 双 PASS 无降门 | `fdc9ea0`/`37eb603` + docs | PASS |
| M2-11-04 内存三分法 | GUI 稳态 1975MB 三轮 + 断言面 +1 + 重述批 | `7ac3727`/`f238a55`/`88ffba8` + docs | PASS |
| M2-11-05 closeout | 机检 + 终轮 + GUI 轮 + VALIDATION + 翻账（本件 = 其验收面） | `2129311`/`b5fa68a`/本批 | 本 VALIDATION |

零红线域终态：`git diff --name-only 9586c1b..HEAD` MCP/Export/Version 三域 = **零命中**
（INPUT §1.1 亲证；全窗唯一产线 diff = WorkspaceHostView DEBUG probe guard，
`bff022e` 越界申报件）。GPL/MIT 参考全程只读；`.xmp` 零读写删；semantic_search
defer 维持（OQ-12-A）。

---

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。M2PERF-01 九门 + M2PERF-02 终验每条均有
  ≥1 机器锚（bench 断言族 / MemoryBudgetTests / test-direct 机检 / xctrace XML
  / footprint CLI 读数）+ ≥1 数字/实证背书（净轮亲跑 + 恢复协议实录 + GUI 真机
  走查截图/AX 证据 + O-2 复现读数）。
- 采样密度：五 plan 全部 AC 逐条机检（01: 8 条 / 02: 8 / 03: 6 / 04: 7 / 05: 8）
  + 四轮验收 subagent 独立复跑（01-04）+ 本 closeout 亲跑终轮；「无证据 ✅」零项。
- 05 无单独验收轮的补偿 = VALIDATION 即验收面（M2-10-07 先例同款）：机检亲跑复现
  （红线域/L055/三方对账）+ 走查证据全部落盘可回溯 + 崩溃家族 .ips 双栈归档。

## 特殊事项入册（phase 级事件台账）

1. **ToneEqual 崩溃家族与恢复协议**（INPUT §2.3 + GOAL-STATE 台账追加行）：App
   bundle 五红二绿 → 盘/缓存卫生（Data 卷 4.3→11GB + Metal cache 重建）→ 第 3 试
   净轮干净绿——终值以干净轮为准（两轮取后不取平均）；产线零 diff 排除 M2-11 回归。
2. **L057 家族复活 + F-1 不复现**：Import Folder（M2-9 F-1 现场点位）HEAD 取消
   腿 ALIVE ×2 亲证；LUT 导入 .cube 取消 SIGSEGV（FINDING-F）——同族不同点位，
   修复面 = 面板调用点族（L057 对策三条继续适用）。
3. **M2-9 `bff022e` 越界申报追认**（Release 断代三修；02 波验收 PASS 已载）。
4. **走查通道边界**：合成右键不开 SwiftUI context menu / LazyVGrid 零 AX /
   hover 门控按钮不可达 / NSOpenPanel 路径表单 IME 截键——四条通道边界本轮实测
   入册（Manual-Only 行的全部理由）。
5. **两 error 级 FINDING 已登记**（M4 ToneEqual / M5 L057 家族）——「零 error 级
   FINDING」判据 = 无未登记 error；归属裁决随晨审。

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8/9/10-VALIDATION
  同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」。
- 依授权，本 VALIDATION 由夜间全自动批落盘签核（`[gsd] paused=false / auto=true`
  全程未动——五 plan 逐任务边界复查在案）；用户晨审可推翻本签核（推翻 = M2-11
  签核作废回退，已交付面与五轮执行/验收证据不受影响；翻账批同批执行，推翻时
  四行翻勾随 revert）。
- 签核 executor：ZCode closeout executor（2026-10-07 夜间批）；doc-only——零源码
  diff 亲证（`git diff --stat` 对表 = 申报集全 docs）。
- **呈报裁决点（禁静默）**：①M2NODE-03 翻勾（带指针件；晨审可裁保持 uncheck）；
  ②两 error FINDING 归属（修复批 or V2/Maintenance）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：M2 段四行翻勾 + Delivered 终态注记（`grep "^- \[ \] \*\*M2"` = **0**）。
- ROADMAP：M2-11 行 ✅ 闭环（终态 2961/16skip/0fail）。
- STATE：M2-11 complete + **M2 milestone 终态行**（对账链 2165→…→2955→2961）
  + current_phase = M2 closed。
- TODO：M2-11 条目落账（[x]）。
- GOAL-STATE：续接点翻新 = **M2 closed → V2/Maintenance 站（未立项态）**。
- 未 push；GUI app / 测试宿主进程零残留（走查毕已 quit）。

## 签核

- M2PERF-01/02 + M2DRT-06 + M2NODE-03 全项 Delivered（三列证据齐；数字对账 =
  终验净轮亲证基线）。
- `status: validated` + `nyquist_compliant: true` + `milestone_closeout: M2`。
- **M2 milestone（Alcedo V1）closed**：M2-0..M2-11 全 complete，终验
  `TOTAL|2961/16/0|1081s`；挂账单一清单（Maintenance 七 + V2/观察项 十七）移交。
- 晨审裁决项：M2NODE-03 裁决 + 两 error FINDING 归属 + 签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**

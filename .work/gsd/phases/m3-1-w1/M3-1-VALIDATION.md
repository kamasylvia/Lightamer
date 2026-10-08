---
phase: M3-1
slug: w1-lead-batch
status: validated
nyquist_compliant: true
created: 2026-10-08
validated: 2026-10-08
---

# Phase M3-1 — Validation（W1 前置批：M2GRADE-08 + YIYIN-09 + 小件族）

> 体例对齐 `phases/m2-11-performance/M2-11-VALIDATION.md`（C 档第 3 停签核正本格式）。
> **翻账只认证据**：SC 三列对账证据正本 = 三 plan ACCEPTANCE（M3-1-01/02/03），
> 走查证据 = `.work/gui-acceptance/m3-1/` MANIFEST（含 M3-1-03 附录 + 五证据图），
> 数字正本 = 各 SUMMARY 测试数字节 + `M3-1-03-ACCEPTANCE.md` §一。
> **SC 数字对账基线 = M3-1-03 验收终轮 `TOTAL|3024/16/0|1113s` 亲证值**
> （2026-10-08，验收 subagent 独立复跑 exit 0 零 MEMFAIL；对账链
> **2962 → 2999 → 3013 → 3024**：2962（M2-11 终值 2961 + `08dd061` +1）+ 37（01）
> + 14（02）+ 11（03），skip 恒 16 零新增；登记面起算 3013 + 11 = 3024 两式互证）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 直启宿主 / GUI 实测轨〔AX + CGEvent〕/ 独立数学复算轨） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL 机检 `RSS_LIMIT_MB=8192` + L055 双保险 + 崩溃签名全日志机检） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3024 tests / 16 skip / 0 fail**（1113s，M3-1-03 验收终轮亲跑；七 bundle：IOP 471/1/0〔7594MB〕/ IOPParity 389/3/0 / Layers 300/3/0 / Library 587/4/0 / Sessions 279/4/0 / Export 338/1/0 / App 660/0/0，全 <8192 门零 MEMFAIL） |
| **基线演变** | 2962（`08dd061` 修复批后）→ 01 +37（IOPP 24 + Golden 2 + LIB 6 + APP 5）→ 02 +14（YiyinSheetSizingTests）→ 03 +11（Picker 5 + Bypass 6）= **3024 精确**；`grep -c "func test"` 三方对表（BUNDLE-MAP × Project.swift × 源文件）逐位亲核 |
| **zh 对账** | 1510/1760（起算）→ **1534 source / 1772 catalog PASS**（终态；+24 静态键 = 提取器 1c 硬化 surfaced 的 continuation 形态族，+12 catalog 键 = collision 4 + peak note 1 + nlmeans toast 1 + project_face 4 + search 占位 2）；`--self-test` PASS（负测两样例） |
| **GUI 证据** | 三 plan 真机走查（`gui-acceptance/m3-1/` MANIFEST）：01 方向探针 + 补标观感走查；02 五语义六探针（defaults 三段探针 ×3 轴 / 终端四点 AX frame / relaunch 重推导 / 容器跟随 150×206 / 读数四态 verbatim）；03 五项（F1 zh 屏上实证 / 冲突档三档菜单 + 选择翻转 / peak-ICC 双态 / 标记菜单 13 键 zh / T3 Manual-Only） |
| **在案 flake（本 phase 事件）** | 零新增。01 验收中段 shell spawn 通道故障（`spawn /bin/zsh ENOENT`，环境故障非仓库问题）——两补录槽处置见「特殊事项入册」 |

---

## SC 对照表（三列证据，正本 = 三 plan ACCEPTANCE）

| SC | 判据 | 终态 |
|---|---|---|
| **M2GRADE-08** | 编码建模 / 补标 / golden 三件套（ROADMAP 验收形态：log 域直套偏差消除 golden 对照 + 上游 `c740f7b` 行为对表） | **Delivered**（`REQUIREMENTS.md` 已翻 `[x] Delivered（M3-1-01）`）：①**编码建模**——目录 17 条（scene 11 + display 6，表驱动加行 = 加 case）+ 传递曲线 Float64 正逆族（10 camera log + sRGB 新写，PQ/HLG/BT.1886/γ2.2 经 DrtEotfMath 复用）+ gamut Bradford 自算 + Params additive 编码对（hash 零漂移专测逐字节）+ 宿主复合表重烘焙（零新 kernel，LRU 16 + bakeCount + stateLock）+ 面板双 Picker。证据 = 01-ACCEPTANCE AC 8/8 + **独立数学复算：11 曲线 vs colour-science 0.4.7 全零误差 + Bradford↔BT.2087 公表 4.0e-5/5.0e-5**（申报 ≤2e-4 成立）。②**补标**——内置 40 张 adoption 盖章 `{arri_logc4_awg4, rec709_bt1886}` + 库内记忆三层序 + 记住 Toggle（40/40 逐条断言；新选档观感变化 = 修偏差非回归交付注记在案）。③**golden 三件套**——voxel 级烘焙门 ≤1e-5 + 方向探针三件（恒等表闭式独立推导，**破自参照倒置推演实测偏差 1302 → 探针必红**）+ 忠实渲染门 ±1.5/1024（门结构收窄 = 实测修正非降门，验收裁定成立）。上游对表偏离（快路径 HasUnitDomain 移除 / M5 ①②③）= OQ-1① 用户硬值推论 + DECISIONS 登记态，验收两收窄均裁定成立 |
| **YIYIN-09** | 五语义 + 持久化（ROADMAP 验收形态：分割线拖拽走查 + PR #126 形态对表） | **Delivered**（`REQUIREMENTS.md` 已翻 `[x] Delivered（M3-1-02）`）：**五语义**①双重钳制（px 界 120-720/160-560 原值 ∩ 比例域 0.15-0.75/0.35-0.92 两域交，终端四点 AX frame 逐位）②松手才落盘（quantize3；defaults 三段探针 ×3 轴 = 拖中零写、松手恰一写逐值精确）③拖动零 history 零 pipe 零落盘（结构断言 + 实机拖拽全程响应）④容器跟随（onGeometryChange 测 host 域递入；1504→1000 → 150×206 逐位）⑤实时读数 verbatim（四态与 frame 逐字一致）。**持久化**——两键 `yiyin.sheet.widthRatio/heightRatio` 注入式 defaults（typed 容错域外 = 缺席）+ relaunch 重推导亲证（542 = 0.36×1504 / 614 = round(0.408×1504)）+ 首用键缺席 = 420×560 逐位零观感。形态对表 = 方案 A①映射声明（D7：语义移植非像素移植）。height 帽 560「只能缩不能增」= checker M7 有意裁定（走查 GUI 直证） |
| **小件族**（四件） | 冲突档 / peak-ICC / 降档 / zh 清算 | **Delivered**（03-ACCEPTANCE PASS）：①**冲突档选择器**——三档 Picker（Increment 默认 = 历史行为逐位）+ `makeRunAssembly` 纯缝 → `enqueueExportM2(collisionPolicy:)` 既有形参 → `ExportNamer.resolve` 既有引擎；透传链全读码亲核 + 逐档装配测试亲跑 + 三档菜单走查翻转；**M2-9-VALIDATION 挂账#4 关闭三判据全落**（Picker 在场 / 选择值达队列 / 三档行为走查；历史行未改写）。②**peak-ICC 说明行**——drtReadout HDR 档 caption（`isHdrEncoding` Core 单源亲核 DrtRecord.swift:456）；SDR 零变化 + `DrtOutputColorSpace`/`ExportICCStrip` 签名面零触碰（红线机检）；双态截图目检。③**denoise 拖动降档**（OQ-6① 兑现）——EditorState 旁路三防线（实例身份键控 + 先验 enabled 记忆 + commit 自愈 + 重建清扫 + upsert 强制）+ 旁路永不进 liveEdited/params/history（checker M6）+ 松手恰一 commit；六测逐条亲跑 + 读码；**实机 = Manual-Only 登记成立**（不可达双腿亲核：Registry.swift:48 禁用集 + EditorTabRoute 零席位；plan 纪律 4 条款；补走查配方在 MANIFEST）。④**zh 清算**（V14/V15/F1）——标记菜单动态键位 switch 化 13 键 zh + 提取器 1c 硬化（`--self-test` 负测）+ **硬化首轮即抓两枚真缺口** `search_{exif,clip}_placeholder` 同批入账 + F1 四键清账（M2-3-4 挂账销账）；`--check` 1534/1772 PASS 亲复现 + 菜单 13 键 zh 截图 |
| **SC 数字门** | M3-1 plan 期定 | **达成**：全套 `--all` 终验轮 3024/16/0 = 判定式 2962+37+14+11 逐位命中（禁凑数对账成立——终值先于对账式独立亲跑）；MEMFAIL 全程零；三 plan 红线域机检零命中（各 SUMMARY 机检节 + 03 验收 range grep `0241a1c..HEAD` 亲跑零命中：ExportNamer/NLMeansModule/PixelPipe/DrtOutputColorSpace/ExportState/DrtEotf/六格式/WebPEncoder/PipeCacheKey/V50Order/ModuleRegistry/ExportICCStrip/Lut3dKernels.metal/legacyBody/EditorState） |

---

## Per-Plan Map（M3-1-01..03）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M3-1-01 M2GRADE-08 编码建模 | 编码目录 + 曲线族 + 烘焙 + 补标 + 双 Picker + golden 三件套 | `e274cc0`/`4f48d04`/`a1e7d56`/`9ab0193`/`5c6291c`/`74e14a4`（docs）+ `5278f6b`（验收批代提交） | **PASS / 0 error + 1 minor + 2 observation**（独立数学复算零误差级；IOPParity 全量 389/3/0 亲跑逐位） |
| M3-1-02 YIYIN-09 sheet 拖拽 | 五语义映射 + 纯数学/值类型/模型分层 + `.global` 锚定修复 | `73c8764`/`3fd6ff0`/`43153e0`/`10abb8b`（收口）+ `3416c61`（验收批） | **PASS / 0 error + 2 minor + 1 observation**（实机六探针复测；D6 机制修订入册） |
| M3-1-03 小件族 + zh 清算 + phase 收口 | 冲突档 + peak-ICC + 降档旁路 + V14/V15/F1 + 全套终验 | `7a800a5`/`158a468`/`c5afe0d`/`d4ae750`/`184d1aa` + `89f21b2`（验收批） | **PASS / 0 error + 1 minor + 1 observation**（全套 3024/16/0 独立复跑 + 定向亲跑 + §四终态意见：**同意签核**） |

零红线域终态：三 plan 各 SUMMARY 机检节 + 03 验收 range grep 全零命中（SC 表末行）。
GPL/MIT 参考全程只读（01 数学源 = 公开标准 + colour-science BSD-3 数学事实，Alcedo
零字节零数值；02 = yiyin fork MIT 语义移植零成段移植）；`.xmp` 零读写删。

---

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。三 plan 全部 AC 逐条机检（01: 8 条 / 02: 6 条 /
  03: 7 条）且每条均有 ≥1 机器锚（专测断言 / 定向亲跑 / 红线 range grep / defaults
  三段探针 / zh-audit 机检）+ ≥1 实证背书（三轮验收 subagent 独立亲跑——含全套
  3024/16/0 终轮独立复跑、独立数学复算〔colour-science / BT.2087 / 倒置推演〕、
  实机 AX/CGEvent 六探针、GUI 走查截图/AX 证据落盘）。
- 采样密度：三波验收全部零共享上下文独立执行，「无证据 ✅」零项；数字对账链
  四点（2962→2999→3013→3024）全对表且终值独立亲跑先于对账式。
- 唯一 Manual-Only 行（T3 denoise 实机观感）非无证据：不可达论证双腿亲核（禁用集 +
  tab shell 零席位）+ 补偿覆盖三层（状态层六测 + 挂点编译期 + D-H1 既有语义）+
  补走查配方落盘 MANIFEST——按 plan 纪律 4 兜底条款登记，不构成 nyquist 缺口。

## 特殊事项入册（phase 级事件台账）

1. **M3-1-01 验收 shell 故障两补录槽追认**：槽①（Library 587/4/0 / App 635/0/0 两
   bundle 亲跑）已由 M3-1-03 全套终验轮实质清偿——Library 587/4/0 逐位一致、App 660
   含 635 基线 + 后续增量，两族测试全绿在终轮内亲跑；**径行追认**（晨审可另令补跑）。
   槽②（晶格地板实测脚本 `/tmp/m31_lattice_floor.py`）未执行——脚本属 /tmp 即弃区
   已不存；该值不承载判定（01-ACCEPTANCE §4.4 结构论证独立成立：65³ 复合晶格插值
   地板属表驱动烘焙物理属性，Alcedo 自家同尺寸同地板），记 observation 不阻塞。
2. **两处 plan 字面实测收窄均验收裁定成立**（01 §2 快路径 HasUnitDomain 移除 =
   OQ-1① 用户硬值推论 + 首轮 5 红证据链；01 §4 门结构 = voxel 1e-5 门原样保留 +
   探针原样交付，被收窄的端到端字面数学不可达）——晨审可推翻（推翻代价已注记
   DECISIONS）。
3. **D6 机制修订（02 验收批）**：`.global` 在 sheet 子窗口内 = sheet 窗口锚定而非
   屏幕锚定，宽轴有效增益 ≈1.93×——执行批「终端精确」系钳制端点探针盲区；验收批
   非钳制定标探针（+100pt→+193pt）即此补。五语义不受扰，代码处置维持 O-1 挂账。
4. **F-1 扩围登记（非本批面，范围认定审计完成）**：New Project 面板取消即崩 =
   L057 家族新实例（.ips 同签名亲读）；全仓 runModal 族排查无第 N 处遗漏——修复批
   立项范围 = `M3-1-02-ACCEPTANCE.md` §三全集（含 SettingsPages ×3 勘正 +
   FileOpenHelper 死代码清理 + `Task {}` 非充分免疫实证）。
5. **两枚 zh 真缺口为硬化意外战果**（D6：catalog 从未在册 = 运行时 en 回退的真
   缺失）——提取器硬化价值实证，同批入账销账。

## 挂账总汇编（单一移交清单；全部有主、有指针、有触发条件）

| # | 挂账 | 归属 / 触发 | 正本指针 |
|---|---|---|---|
| 1 | **L057 面板族加固专项**（在飞，队列行在案）——取消即崩家族；`Task {}` 非充分免疫；范围 = 02-ACCEPTANCE §三全集 | 下一波专项（M3-1-03 已落地可派） | GOAL-STATE 队列行 + `M3-1-02-ACCEPTANCE.md` §三 |
| 2 | **D6/O-1 yiyin sheet 宽轴拖拽手感**——`.global` = sheet 窗口锚定，宽轴增益 ≈1.93×（非 1:1）；五语义不受扰 | 用户报手感差 → OQ 重开；修复方向 = NSWindow 级 NSEvent 屏幕坐标差分（真 clientX 等效）或 in-flow 面板 | `M3-1-02-DECISIONS.md` D6 修订节 + MANIFEST O-1 |
| 3 | **denoise T3 实机观感走查 = Manual-Only**——nlmeans 默认 IA 结构不可达 | legacy 修复批 / zh sweep 余量顺路（补走查配方在 MANIFEST 附录） | `M3-1-03-DECISIONS.md` D8 + MANIFEST |
| 4 | **冲突档跨会话记忆**——D1 裁定会话态（Export 页视图寿命，关页复位 Increment） | 等用户诉求；新挂账 = 键登记纪律外零新增，不得顺手加键 | `M3-1-03-DECISIONS.md` D1 + SUMMARY §六 |
| 5 | **M4 coordinator 串行化**——拖动窗并发 FULL 缺 denoise（已登记风险）+ ToneEqual GPU 读序残留同源归位 | M4 Maintenance 专项 | `M3-1-03-DECISIONS.md` D4 + 08dd061 批 M4 余量 |
| 6 | **D7 两处 verbatim「Import Folder…」**（LightamerApp :1301 / :1635）登记不修 | zh 专项 sweep 余量（M2-3-4 先例） | `M3-1-03-DECISIONS.md` D7 |
| 7 | **O-2 height 帽 560**「只能缩不能增」= checker M7 有意裁定 | 大屏增高诉求出现 → 新挂账重开 | `M3-1-02-DECISIONS.md` D2 |

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8/9/10/11-VALIDATION
  同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「今晚不停」「开跑，不要停」。
- 依授权，本 VALIDATION 由夜间全自动批落盘签核（`[gsd] paused=false / auto=true`
  签核前亲读复核未动）；用户晨审可推翻本签核（推翻 = M3-1 签核作废回退，已交付面
  与三轮执行/验收证据不受影响；翻账批同批执行，推翻时翻账行随 revert）。
- 签核 executor：ZCode VALIDATION executor（2026-10-08 夜间批）；doc-only——零源码
  diff（本批 `git status` 亲证 = 五账本文件，产线码零触碰；SC 数字不重跑全套，用
  03 验收终轮亲证值 3024/16/0|1113s）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：无本批新翻账——M2GRADE-08 / YIYIN-09 已于各 plan 收口批翻
  `[x] Delivered` 终态注记（本签核准读复核在位）。
- ROADMAP：M3-1 行 ✅ 闭环（终态 3024/16skip/0fail）。
- STATE：M3-0 complete（立项交付闭环）+ **M3-1 complete**（VALIDATION signed
  2026-10-08，终态 3024/16skip/0fail）+ **M3-2 标 next**；m3_phases_complete 0→2。
- TODO：M3-1 条目落账（[x]）。
- GOAL-STATE：续接点追加 = **M3-1 closed → L057 面板族加固专项（在飞另行登记）→
  M3-2 FSIM research**（C 档第 1 停：research 定稿后停，用户过目裁决点再 plan）。
- 未 push；GUI app / 测试宿主进程零残留（验收批已还原；本批零进程启动）。

## 签核

- M2GRADE-08 + YIYIN-09 + 小件族四件 + SC 数字门全项 Delivered（三列证据齐；数字
  对账 = 03 验收终轮亲证基线 3024/16/0）。
- `status: validated` + `nyquist_compliant: true`。
- **M3-1（W1 前置批）closed**：三 plan 全验收 PASS（0 error 累计；minor 4 枚均验收
  批当轮修复在案），FSIM-01 软前置交付物（编码目录 + 曲线函数族 + 三层序记忆）就位
  待 M3-3 消费；挂账单一清单七项（上表）移交。
- 晨审裁决项：签核推翻窗（原话授权在案）+ 补录槽②追认复核 + 两处实测收窄推翻通道
  （01 §2/§4，代价已注记）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**

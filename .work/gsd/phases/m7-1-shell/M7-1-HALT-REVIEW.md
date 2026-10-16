# M7-1 停手批独立复核（M7-1-HALT-REVIEW，2026-10-16 夜）

> 复核人 = 零共享上下文独立 subagent；输入 = SUMMARY/DECISIONS（D-M7-1-01-1..5）
> + t1-scratch-matrix/MATRIX.md + FIX2-01-DECISIONS.md（D-FIX2-1）+ 双路
> ACCEPTANCE 遮挡节；方法 = 读档 + 读码 + **亲跑三实验**（Exp-1/2/3，本机
> 自采 sample/ps；探针 /tmp 即弃）。HEAD = `5323df67`（复核期间零产线
> diff——C1 scratch 涂改后 `git checkout --` 回退 + HEAD 二进制重建亲核）。
>
> **结论头：三问全部裁定，证伪从「重测级」升级为「证据级」——FIX2 全部
> 饿死读数（C1/C2 + E1/E2/E3）均落遮挡/发射静默窗伪象，E 系三连饿死运行
> 更是从未进入编辑器面（transcript `phase=library` 全程）；今日协议下
> C1-EXACT 与 HEAD 逐行为同构（活），编辑器面 reveal 无点击 ≤1s 复燃。
> D-6 建议裁定 = upstream-only 为主 + 遮挡止损 doc 一行补记 + 窗拆挂账
> 条件改写为「E 系硬化复测复活」。停手批处置（零 commit、回退、上报）
> 正确，维持。**

---

## §1 Q1 矩阵方法学复核

### 1.1 遮挡门控有效性：六形态逐行核

| 行 | 形 | frontmost 证据 | CPU series | 样本存档 | 残留遮态？ |
|---|---|---|---|---|---|
| 1 | flag-off = HEAD 座位 | launch.txt（18:49:16 启动 → 18:49:57 frontmost-then-read，41s 沉降） | 10×1s 27.7-31.9% | **无自有 sample**（符号仅注「family present」无数字） | 无 |
| 2 | case-B 重组 | MATRIX 在册，per-arm 文件**不在 file map**（簿记缺口） | 28.5% 中位 | **无自有文件**（数字 5/4/4/103 无载体） | 无 |
| 3 | A+B 重组 | t1-idle-flag-on/launch.txt「frontmost=true」+ 可见面截图 | 34.9% 中位 | sample-6s + symbol-counts（pid 49139 对上） | 无 |
| 4 | C1-EXACT | c1-cpu-recheck.txt（pid 50951，19:03:52；样本头 launch 19:03:43） | 27.8-43.7% | c1-sample-6s.txt | 无 |
| 5 | C2-EXACT | 同批协议 | 29.05% 中位 | c2-sample-6s.txt | 无 |
| 6 | research 基线 | research §0 配方（当日 16:1x） | 30-34% | m71-editor-sample-head.txt（编辑器面）+ §0.2 | 无 |

- 首对 flag-on/off 读数（遮态 0.0%）被协议**自己抓出并作废** = 门控自证有效；保留行无残留遮态窗口。
- 缺口：row 1/2 的符号判读无独立存档（row 1 依赖 row 3-5 同族外推；row 2 数字悬空）。复核以 Exp-1（HEAD，mm 总量 204）补上 row 1 缺口；row 2 影响低（与 row 3 同批同族）。

### 1.2 符号判读语义：记录格式低估活性量级（重要勘误建议）

per-arm `symbol-counts.txt` 与 `m71-six-symbols.txt` 记录的是 sample call
graph **最大单支计数**，非符号总量。复核以 awk 跨行求和重提：

| 样本 | 记录值（mm/um/pv/mangled） | **总量重提**（mm / UpdateStack / beginTransaction） |
|---|---|---|
| c1-sample-6s（行 4） | 6/4/3/126 | **198 / 537 / 1228** |
| c2-sample-6s（行 5） | 3/2/4/115 | **143 / 569 / 1261** |
| reshaped-A+B（行 3） | 4/5/3/108 | **(同文件) 198 / 547 / 1306**（flag-on sample 同源） |

结论：停手批「环活」判定**成立**（总量与 FIX2 活态同带，见 §2.1 对照表），
但记录格式会把后续读者引向「tick 级」误读——FIX2 第二路验收「C1 饿死样本
makeMainMenu/updateMainMenu 合计 7 hits（环态样本为数百）」正是同一陷阱：
7 = grep 行数级，数百 = 计数总和，**跨量纲比较**。同一陷阱再走一步就会把
停手批行 4（单支 6/4/3）误判为与 FIX2 饿死样本同形。

### 1.3 C1/C2 同构性与证伪强度分级

- FIX2 原 scratch diff 已不在 git 面（执行批回退）；语料原在 /tmp（第一路
  ACCEPTANCE minor #2 判「重启即失」——**复核时 /tmp/fix2t1 仍在**，c1-sample.txt
  等未回填件幸存，见 §2）。可比对面 = D-FIX2-1 文字描述：「摘 .inspector（C1）/
  摘双 safeAreaInset（C2）于空载/图库面」。
- 停手批 C1-EXACT/C2-EXACT 与描述吻合；复核另做**第三次独立复涂**（同描述：
  ContentView gate=false 臂 `.inspector(...)` 块移除，insets 原样）亲测仍活（§2.2 Exp-2）。
- **分级**：对「按描述的 C1/C2 形今日不饿死」= **高**（两个独立复现 + 复核第
  三次）；对「FIX2 原 scratch 字节级相同」= **中**（不可验证，但描述形复涂
  已足证伪——原字节若不同，差异只能比描述形**更轻**才可能救回饿死论，而
  §2.1 显示 FIX2 自留样本里 C2 形自己就是活态满速环，无此空间）。
- PTY 捕获：属 research §0.3 transcript 配方（L077 族）；停手批矩阵未跑
  transcript，plan 判据（transcript 零行 + 环符号 ≤1）被置换为 CPU+符号且
  未重推导。置换结果侥幸正确（活/死在 CPU 轴完全分离：死 = 0.0%，活 =
  26-36%），但「环符号 ≤1」阈值与 FIX2 饿死样本自身读数不兼容（见 §1.2/
  §2.1）——若 FIX2 饿死为真，其自身样本也过不了「≤1」。判据置换应在
  DECISIONS 补记理由。

## §2 Q2 遮挡伪象假说检验

### 2.1 FIX2 时代证据链还原（/tmp/fix2t1 幸存使逐件还原成为可能）

**C1/C2 transcript 双相结构**（sceneBody 10s 桶直方图，五轮同构）：

| transcript | pid | 发射 | 静默 | 复燃 | 平均速率（掩盖双相） |
|---|---|---|---|---|---|
| c1 | 32243 | 2 tick | 0-50s | 50-80s（600/10s 桶 = 60/s） | 10.7/s |
| c1b | 32436 | 2 | 0-70s | 70-98s | 15.0/s |
| c1c | 32654 | 2 | —（320s 长窗，未做桶分解） | 均值 4.0/s 为长窗摊薄 | 4.0/s |
| c2 | 33591 | 2 | 0-60s | 60-75s | 9.4/s |
| c2b | 33812 | 2 | 0-90s | 90-112s | 7.0/s |
| c2c | 34093 | 2 | 0-55s | 55-70s | 15.2/s |
| c2d | 34237 | 2 | **15 行即止（发射初窗捕获）** | 未及 | — |

- 「饿死」读数（ps 10×1s、sceneBody 2/25s）**全部落在静默相内**。FIX2 执行批
  配方零 frontmost 步（FIX2-01-PLAN.md 无 frontmost/遮挡字样——grep 亲核）；
  裸直启未激活 → 窗遮挡 → 环被可见性门控压 0。
- **FIX2 自留样本内在矛盾**（关键对照）：

| 样本（时刻，pid） | mm 总量 | UpdateStack | beginTransaction | 判读 |
|---|---|---|---|---|
| idle-sample.txt（09:23，29437） | 0 | 0 | 0 | **遮态静默**（观察 #1 原始形态，早于正式识别） |
| idle2/t1-idle-face-sample（09:25，29742） | 93 | 388 | 884 | 活态（同面 2 分钟后） |
| c1-sample.txt（09:37:30，32243 = c1 轮 t+66s） | 62 | 204 | 480 | **复燃上升沿**（非「残底噪」） |
| c2-sample.txt（09:44，33591 = c2 轮 t+71s） | 91 | 251 | 568 | 复燃后 |
| **c2-long-sample.txt（09:46:20，34093 = c2c 轮 t+54s）** | **263** | **789** | **1850** | **恰逢 c2c 复燃沿 = 满速环**（被记作「28% AppKit 残底噪」的样本实为活态环） |
| rearm-sample（10:36，44415） | 295 | 1884 | 2854 | 活态环心 |
| b2-sample（09:30，31003） | 86 | 291 | 636 | 活态（B2 形不饿死） |

  D-FIX2-1 第 5 条「C1 形 churn 死后 ~28% AppKit 侧低频底噪（c1-sample/
  c2-sample）」的样本档案**本身就是 SwiftUI 图活动样本**——AppKit UpdateCycle/
  layoutIfNeeded 支路与环支路共存于同一份活态样本。
- **E 系证据链断裂（新发现，决定性）**：e-strip/e-area/e-right transcript
  **全程 `phase=library`**（各 10 个 menuCmds 探针零 editor；各 12s、2 tick）——
  三次「编辑器面摘段饿死」运行 **AX 腿未生效，从未进入编辑器面**；其
  0.0-0.1% 读数 = 图库面 × 遮态静默窗双重伪象。对照组 e-base 8810 个
  `phase=editor` 探针在案（AX 腿在活态轮正常）。D-FIX2-1「编辑器面三段任摘
  → 环饿死（0.0-0.1%，E1/E2/E3 三向复核）」的证据本体无效。
- 归因裁定：D-M7-1-01-1 候选 #1（遮挡伪象）**成立并升级**——不止 C1/C2
  「CPU 归零恰是遮态签名」，而是全部饿死读数轮（C1×3 + C2×4 + E×3 共十轮
  transcript）均落静默窗/错面；候选 #2（环境漂移）、#3（产线 commit 重燃）
  无需动用。

### 2.2 今日协议重跑（复核亲跑；Exp-1/2/3）

环境：macOS 27.0.1 (26A434)；二进制 = 停手批 DerivedData（glcjhggt…）T5 后
HEAD 等价构建（5323df67 仅 docs）；协议 = `caffeinate -dis` 包裹 + 裸直启 +
System Events `visible=false`（遮）/ `frontmost true`（显，无点击）+ 1s 步
ps %cpu + `sample <pid> 6 -file`；日志与截图 = /tmp/m71-review/（即弃，关键
数值全部内联于本文）。

**Exp-1（HEAD 空载面）**：遮态（启动即隐）0.0% ×12 → sample 全零符号
（mm/UpdateStack/beginTransaction = 0/0/0）→ 25s/45s/70s 复测仍 0.0%（85s+
静默，不自发复燃）→ `frontmost`（无点击）**≤1s 点燃**（0.0 → 30.9）→ 30%
带自持 45s → 跨相（含未生效遮挡相）连续自持 ≥110s → 稳态样本 mm 204 /
UpdateStack 696 / beginTransaction 1557 = 满速环。

**Exp-2（C1-EXACT 复涂 + 增量构建）**：遮态 0.0% ×85s（样本全零）→ reveal
≤1s（29.8）→ 30-36% 自持 45s → hide 15s（12.4→1.5→0.0%，全程 0.0%）→
reveal ≤1s（29.3）→ 自持至收尾（28.3%）→ 稳态样本 mm 202 / UpdateStack 578。
**与 HEAD 逐行为同构——停手批证伪独立确认。**

**Exp-3（编辑器面，probe 缝项目 + AX 腿 en-US，`-la_editor_probe
/tmp/fix2acc-import`）**：进编辑器成功（Open Recent item 1 =
editor-probe-276EB0DB…）；基线 spin 78.7-90.3%（与 FIX2 42-53%、第二路
82-87%、research 82-86% 同带偏上）；hide → 2s 内 0.0%（88.1→5.4→0.0），
18s 保持；**reveal（frontmost，无点击）≤1s 复燃**（0.0 → 80.1）→ 78-86%
自持 45s+（收尾 86.5%）；复燃后样本 mm 274 / UpdateStack 4334 /
sizeThatFits 49663 = 满速编辑器环。

**对「解遮后一次点击恢复」假说的裁定**：**点击非必需**——reveal（激活/
置前）本身即点火事件，两形三面（HEAD 空载 / C1 空载 / 编辑器面）延迟一致
≤1s。FIX2 第二路「重新显示后 4s 内不复燃（仍 0.0%）+ 点击复燃」= 观察窗
（4s）短于实际点火延迟的测量伪象（或该轮特异延迟），**不构成与今日环活的
矛盾**；「环被点击重置一次而非饿死」的替代解释不成立（无需任何交互重置）。
附带：环自持性在 FIX2 时代已有分钟级在案（b2b transcript 401s @59/s），
自持无争议；编辑器面遮挡同样压 0 = 遮挡止损对 spin 亦有效（§3②）。

## §3 Q3 策略影响裁定材料

前提修正：「环若真不可饿死」应表述为——**环的树形饿死已无任何在案有效
证据**（原五组证据全 dissolved + 今日三独立复现均活）。环的真实行为模型 =
**可见性门控开关**（遮 0% / 显+激活 ≤1s 点火 / 显期间自持）× **振幅随面重**
（图库 ~30% / 编辑器 80-100% / legacy 面 0.1%（开菜单态 41.5%，第一路 #4））。

### ①窗拆（SHELL-02 重评）

- **RESEARCH 论断复核**：§2.1.4「NSApp.mainMenu 全 app 共享——菜单环不随窗
  拆分消失；环燃料面原样」与框架事实一致（样本环心 = appGraphDidChange →
  makeMainMenu → updateMainMenu → invalidateProperties → prependValue，作
  用在 app 级主菜单与 per-window preferences 桥上，无窗拓扑项）。**预判：
  窗拆后编辑器窗仍在环内、树仍重（三段内容原地）→ spin 不消失（维持
  80-100% 带或同带内波动）；主窗图库面轻树在环内但振幅低。**窗拆唯一理论
  杠杆 =「把段移出主窗树」（生产版摘段）依赖 E 系饿死——E 系证据已无效。
- **实验设计（便宜先行，两步）**：
  1. **E 系硬化协议复测**（半日级，前置必做）：同 C1 复涂法逐段摘
     （filmstrip/viewport/rightPane）+ probe 项目 + AX 腿 + frontmost +
     reveal 后 60s 观测 + 样本总量 + **transcript `phase=editor` 机检断言**
     （E 系教训）。判读：任一形 reveal 后 0% 持续 ≥60s = 树形杠杆复活 →
     窗拆重评；全部 ≥80% = 窗拆饿死性终证死亡。
  2. 若 1 复活：SHELL-02 scratch（编辑器段独立窗）同协议 + 编辑器窗 CPU
     硬门 <10% + RESEARCH §3 已列多窗生命周期走查。
- **量级**：L（2-3 plan 波次，RESEARCH §2.3 在案）。**预期收益**（仅当杠杆
  复活）：编辑器 spin 80-100% → <10%——唯一 app 侧根治杠杆；若杠杆死亡：
  窗拆只剩 IA 偏好收益（偏离 Alcedo 单窗对标，RESEARCH §2.3 已记代价）。
- **证据缺口**：E 系硬化复测（本复核判定原证据无效后升为必做前置）；
  窗拆 scratch 采数（停手批按 E-1 乙案跳过，前提已变）。

### ②遮挡 workaround 常态化

- **事实面（今日实测）**：遮挡 = 0% 对两形三面成立（空载 HEAD/C1 + 编辑器
  spin）；**⌘H 手动即可达 = 零代码既有行为**；自动遮挡宏/启动默认最小化 =
  甜味剂（XS 级：NSApp.hide 一行 + 配置项）。
- **可接受度**：对「后台空烧」（app 挂后台 30% / 编辑器挂后台 80-100%）=
  有效止损且用户现即可手动；对「使用中 spin」（用户正盯着编辑器）= 无效
  （遮挡即不可用）。启动默认最小化与照片编辑器工作流冲突，不建议；自动
  idle-hide 属锦上添花，收益被 ⌘H 全覆盖，不建议立项。
- **建议行使面（一行级）**：把「遮挡即断环（CPU 归零）+ 置前即复燃（≤1s，
  无需点击）」写入用户可及文档（FIX2 第二路 §5.3 指出「遮挡止损未写入任何
  用户可及文档」；本复核把语义从「一次点击恢复」勘正为「置前即恢复」）。
- **量级**：XS（doc 一行；代码 0）。**预期收益**：降级期止损语义落账。
  **证据缺口**：无（Exp-3 亲测闭合）。

### ③upstream-only

- **现状**：FB 稿在案（`research/APPLE-FB-D6-DRAFT.md`，勘误两处随批落稿，
  D-M7-1-01-5）；案号待用户提交回填（槽 = SUMMARY 呈报件 3）。
- **量级**：M（用户手动提交 + 27.x 追踪）。**预期收益**：根修（唯一不受
  树形证伪影响的路径）；树形域证伪后成为**默认主路径**。
- **建议随提交补强的数据点**（可选，强化稿面）：①遮挡门控确定性复现
  （遮 0% / 置前 ≤1s 复燃，两形三面）②树形证伪（C1/C2 三独立复现均活）
  ③跨日稳定编辑器 spin 配方（repro.sh 形，82-100% 三路在案）= Apple 可
  复现配方；**E 系证据无效一事不入 FB**（内部分卷）。
- **证据缺口**：Apple ETA 不可控；降级期内 D-6 表型（编辑器 spin）持续。

## §4 对停手批台账的勘误/补强建议（移交 orchestrator）

1. **证据记录格式**：sample 符号一律记**总量**（跨行求和），禁最大单支；
   「N hits」表述必须区分 grep 行数 vs 计数总和（第二路「7 hits」教训，
   LESSONS 候选）。
2. **静默窗纪律升级**：遮挡门控（frontmost 先行）之外补**读数带验证**——
   可见窗语境下 CPU 读数 ≈ 0.0% 即伪象哨兵（活态带 26-36%/80-100% 完全
   分离，0.0% 只该在遮态出现）；读数后即时对带复核。
3. **编辑器面探针配方机检**：涉编辑器面的 AX 腿探针必须断言
   `phase=editor`（transcript phase 字段）后再采数——E 系教训。
4. **判据置换补记**：plan 判据（transcript 零行 + 环符号 ≤1）被 CPU+符号
   置换的理由应补入 DECISIONS（置换正确但当时未论证；「≤1」阈值与 FIX2
   饿死样本自身读数不兼容）。
5. **/tmp/fix2t1 回填**：B/C/E 原始语料至今幸存（第一路 ACCEPTANCE minor #2
   的「重启即失」未发生）——回填窗口仍在，orchestrator 裁量。
6. **呈报件 2 批注维持**：case A 座移 AX 桥不可测结论（D-M7-1-01-2）与本次
   证伪独立，留档不变。

## §5 复核留痕

- Exp-1/2/3 日志 = /tmp/m71-review/{exp1,exp2,exp3}.log + 四份 sample
  + 两张截图（即弃域；数值已内联本文）。
- C1 复涂 = ContentView.swift gate=false 臂 `.inspector` 块移除（一次性），
  已 `git checkout --` 回退 + HEAD 二进制重建（BUILD SUCCEEDED）；复核期间
  tracked modified = 0 亲核；probe 缝本轮生成 editor-probe-276EB0DB….lalb
  （与既有 probe 轮同类痕迹）。
- 本文件 = doc-only commit；不 push。

# FIX2-01 修订版 CHECKER（独立反向核，2026-10-13）

> checker 身份：fixer 后独立目标反向核（同 worker 两段，checker 段以修订后
> plan 为目标重新对源，不复用 fixer 段结论）。输入 = 修订版
> `FIX2-01-PLAN.md`（commit `dafcec88`）+ `FIX2-CONTEXT.md` +
> `FIX2-01-PLAN-REVIEW.md` + 三正本（`V2M-VALIDATION.md` §挂账② /
> `gui-acceptance/v2m/MANIFEST.md` / `gui-acceptance/m6-closeout/MANIFEST.md`）
> + 判据原文（`gui-acceptance/m6-4/MANIFEST.md` M-3/M-4）+ 代码面 HEAD
> 抽验。**本文所有 file:line 均本次实读/实跑，非转述 fixer 段。**
>
> **结论头：PASS / 放行——0 再修项 + 2 minor 残留（容忍放行，附处置）+
> 3 条执行注记**。修订版达成性、核心修订自洽、SC→任务映射全过；
> 残留均为证据引用级/文档 supersession 级，不阻断派发。

---

## 一、Goal-backward 达成性（修订版能否达成挂账目标）

### 1.1 D-6 三铁条（修订后可达性）

- 铁条 (1) 编辑器面 CPU<10%：机检通道 = `ps`/`sample` 在案（修前 82-99%
  对照锚），**编辑器面硬门 = SC 主判据**已钉（T1 action 4 (1)）；
  **10-30% 区间裁定路径闭合**：未达标 → 判别探针二轮迭代义务 → 二轮后
  仍 ≥10% 且 spin 已消失 → DECISIONS 申报 + 上报 orchestrator 定夺；
  spin 仍现 → H2 行使门槛（原语义不变）。无 M-8 型「中间态无裁定」残留。
- 铁条 (2) 编辑器可用：filmstrip 换图 + 视口出图 + 右栏 mount 三步 +
  **启动即按走查点**（不等首次 phase 翻转）——该点同时是 M-2 priming
  腿的行为验证面（不达标 = 漏挂载发布腿），判定机械（命令可用与否）。
- 铁条 (3) 空载面：**记录口径**（SC 与 action 4 (3) 两处已同读——M-8
  对齐核验通过：SC「空载无项目面同口径复测记录（记录口径不设独立硬门；
  >10% 同触发二轮迭代义务）」↔ action 4 (3)「记录口径，不设独立硬门
  （M-8 全篇对齐）」逐句互证，无第二处残留旧「一并记录」歧义措辞
  （grep 实跑 = 0 命中）。
- 证据面 FIX2-D6-01..03 指针在位。**达成性 PASS**。

### 1.2 D-7 完成态（修订后可达性）

- 机制面：合流非阻塞形 + 保序钉（T2 action 1 两钉）——handler 内零
  await 钉直击 `emit` 处 `await progressHandler?`（ImportService.swift
  :737 本次实读确认）的阻塞路径；doc comment 陷阱正本
  （LibraryProjectController.swift:369-383 本次实读：「the handler hands
  the snapshot to a detached MainActor task and returns immediately」）
  与钉语义互证。
- 断言面：四语义含**双载体终态穿透**（controller nil 直写 :416 +
  ImportService `.completed`/`.cancelled` 快照 :56-60/:359-361 本次实读
  确认两载体均在）；Checker #3 已同步扩为「终态穿透 + 非阻塞形」双打回
  条款。
- 机检面：T2 action 3 N≥3 轮 images 行数 + 完成态发布 + 静置 CPU 记录
  （T1 修后应 <10%——SC「完成后 CPU 静置回落」为结果性表述，action 为
  记录 + 期望注记，两者非门语义冲突，核验通过）。**达成性 PASS**。

### 1.3 D-8 核销（修订后可达性）

- T3 零码翻案链完好（配方三步 + MANIFEST 配方节 + DECISIONS 登记 +
  AC「本任务 git diff --stat 仅 docs」）；**N-1 证据缺口自愈条款在位**
  （T3 action 2 后注记块）：probe-8/14/16 引用缺口 → 复走重产 + probe-8
  补采或注明缺失原因，闭环。**达成性 PASS**。

### 1.4 T5 四波全清单（三源对表终核）

对表三正本（`V2M-VALIDATION.md` :117-123 挂账② / `v2m/MANIFEST.md`
:43-65 wave-2 终表 / `m6-closeout/MANIFEST.md` 总队列 42 行）逐行核：

| 正本义务/行集 | 修订版落位 | 判定 |
|---|---|---|
| E2-1 四行：T1-02 / D3-01 / D4-01 / D5-01 | W1 / W2 / W2 / W2 | ✓ 全在 |
| 挂账② 硬义务 03/05/08 + 06/07 复走 | W1（03/05/06/07）+ W2（08） | ✓ 全在 |
| 挂账②「余 Blocked-Channel 行随通道恢复复走」 | v2m 终表 Blocked-Channel 全集 = {03/05/08 复查, 06, 07, 16-19, **32/33**, 34-38, 40} → W1/W2/W4 波次全覆盖 | ✓ **32/33 已入 W2 尾（M-4 闭环，第六漏行消除）** |
| D-4 复验 + 快照上移预案 | W2，机械触发条款原文保留 | ✓ |
| Blocked-Env：26 / 39 / 24/25/27-31 | 不入波 + 供件/硬件理由 | ✓ |
| **10 / 12 / 14（本次新查）** | 不入波 + 逐行排除理由（10 = Registered-obs 无判据样张未制备；12 = Executed 1/3 由 W2 D3-01 复走覆盖；14 = 简形 sheet 零档位控件与通道无关——三行定性本次对 m6-closeout :28-:32 原表逐行核实无误） | ✓ 静默排除清零 |
| 32/33 判据原文指针 | `m6-4/MANIFEST.md` :30-31 M-3（无人像 typed toast）/ M-4（羽化三档 ±100 三档 + reset）本次实读确认存在且可执行 | ✓ |

**行集无缺行、无双计、无定性漂移。四波全清单 PASS。**

### 1.5 SC→任务映射缺口扫描

SC 五段（T1..T5）逐短语对任务 action：T1 五要素（transcript 定罪/断环/
编辑器面门/空载记录/三铁条+启动即按/零回归）→ action 1/2/4/3+AC 全有
产出点；T2 三要素 → action 1（单测）/ action 3（N 轮机检 + CPU）；T3
三要素 → action 1-3；T4 两要素 → action 1-2；T5 波次行集（含新增
32/33）→ W1-W4。**零缺口**。ΔN 带 +0..4 = +0..2 + +0..2 + 0 上下界精确
闭合（修订未触）；skip 35 口径未触。**映射 PASS**。

---

## 二、核心修订自洽（三组重点）

### 2.1 M-2 双腿与探针裁断的衔接

- 衔接逻辑核验：双腿形（挂载 priming + phase 重发布）在**两种裁断结果下
  均成立**——探针读「同引用重写触发下游失效」= 否（框架有去重）→ H1-b
  非罪魁，双腿无害、Equatable 载体可选；= 是（无去重）→ 双腿把写频降到
  O(挂载+phase 翻转) 直接消环，**Equatable 载体在无去重世界无效**（同值
  重写照旧失效）——plan 文「Equatable 载体备案路线仅在探针裁断…成立后才
  可选，否则双腿形为准」正是此语义，方向正确。
- 时序自洽：裁断在 action 1（探针）、选形在 action 2（修法）——读数先于
  选形，顺序无倒挂。
- 启动即按走查点（action 4）与双腿的 priming 腿互为验证（行为面 ↔ 实现
  面），AC 已收录裁断读数为交付物。**自洽 PASS**。

### 2.2 M-4 行集终表三源对表

见 §1.4 终表——V2M-VALIDATION 挂账② / v2m wave-2 终表 /
m6-closeout 总队列三源逐行对齐，32/33 入 W2 尾 + 10/12/14 注记排除
（「排除理由或纳入」二选一已行使「纳入 32/33 + 注记 10/12/14」组合，
不许双缺条款满足）。**自洽 PASS**。

### 2.3 M-6 时序与「直到全量修复完成」兑现结构

- 用户指令 = 「直到全量修复完成，再执行新特性立项」。兑现结构 = T5 内嵌
  于本 plan（本 plan 内闭环）+ T5 末台账 commit 才翻「修复批 II closed →
  新特性立项待用户定向」。T4 中间态「代码面收口，T5 走查复走批执行中」
  不提前宣告完成——**指令语义由 T5 末终态承载，中间态只服务中断续接**
  （会话在 T4/T5 间或 T5 中断，续接会话读「T5 执行中」正确续走 T5，
  而非误判全量完成）。
- 时序面核验：T4 action 3（台账）在 action 2（--all）之后，写「T5 执行
  中」时 T5 确为紧邻下一步（停等点条款：唯一外部依赖 = --all 批准，批准
  后 T5 直通）；T5 收口行明确「含返工分支收口之后才落」——返工臂
  （SessionBrowserView contingency）不产生账实倒挂。**自洽 PASS**。

---

## 三、独立猎残（checker 自产，非 review 转述）

| # | 级别 | 发现 | 处置 |
|---|---|---|---|
| R-1 | minor（自愈型，容忍放行） | T3 read_first 仍写「probe-16..20 证据（fix2-probe/）」——该目录本次实勘仅 5 png（probe-0/10/11/18/20）+ 2 sample，probe-16/17/19 现不存在。T3 action 1 走查正要重产此批证据 + T3 的 N-1 注记块已声明缺口自愈，引用随复走自闭合 | 执行批知悉：read_first 时若 probe-16..20 缺席为**预期态**（复走前），勿判供件缺失 |
| R-2 | minor（supersession 级，容忍放行） | `FIX2-CONTEXT.md` §四编排表 W2 行仍写「merge 动作经项目面 import 供件」且 W1..W4 无 32/33——与修订版 plan 的 M-5 勘误块 / M-4 行集**不一致**。CONTEXT 为 research 产物，plan 为可执行契约，修订按 review 修法只落 plan 侧（本次维持不动 CONTEXT，避免改写侦查正本） | 执行批以 **plan 为准**（M-5 勘误块 + T5 行集）；CONTEXT §四相应行视为被取代 |
| R-3 | 注记（cosmetic） | T5 内「W2 前置通道勘误」bullet 位于 W2 与 W3 bullet 之间——前置声明排在所闸波次之后，阅读顺序稍绕；内容无歧义（「W2 前置 = T1 + W1 + T3 legacy 配方」显式主语） | 不修；执行批按内容读 |
| R-4 | 注记（已核无误） | 修订版新增锚点抽验全过：SessionBrowserView merge 面 :161-207 菜单 + :282/:307/:343 三 sheet + :446 MergeDialogCount 实读命中；ContentView :439 挂载点确认在 legacyBody（:248 起）内；WorkspaceModel 非 Equatable（:103-104 `@Observable final class` 无 Equatable）实读命中；LightamerApp :490 `var body: some Scene` 实读命中（M-7 前提成立） | — |
| R-5 | 注记（已核无误） | front-matter 完整性：修订后 YAML 解析通过（14 keys / files_modified 12 / red_lines 8；red_lines 插值 regex 行 `\"`/`\\` 转义合法，解码文本 = 预期 regex 形） | — |

---

## 四、复核方法

1. 修订版 plan 全文重读（非 diff 视角），逐 M 对照 review 修法原文核
   「钉是否落位、语义是否等价、有无过修」：M-1..M-8 全部落位且无过修
   （任务序/波次编排/批次治理/ΔN 带/skip 口径逐项未动，grep 实跑旧措辞
   零残留）。
2. 三正本对表：`V2M-VALIDATION.md` :113-123（挂账①②）/
   `v2m/MANIFEST.md` :43-65 / `m6-closeout/MANIFEST.md` 全表 + 判据原文
   `m6-4/MANIFEST.md` :30-31 实读。
3. 代码锚抽验：WorkspaceModel / WorkspaceHostView（:170/:220-222/
   :309-332）/ LibraryProjectController（:369-383/:384-391/:416）/
   ImportService（:56-60/:178/:359-361/:737）/ LightamerApp（:461-472/
   :490/:1618-1640）/ ContentView（:205-222/:248/:439）/
   SessionBrowserView（:161-207/:282/:307/:343/:446）。
4. 证据目录实勘：`v2m/fix2-probe/` 文件清单（R-1 依据）。
5. front-matter YAML 解析器实跑（R-5 依据）。

## 结论

**PASS / 放行**——修订版可作为 FIX2-01 执行正本派发。残留 R-1/R-2 为
自愈型/supersession 型，随执行批自然闭合，不构成再修项。

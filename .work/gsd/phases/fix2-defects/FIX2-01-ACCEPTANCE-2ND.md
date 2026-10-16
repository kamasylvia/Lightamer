# FIX2-01 ACCEPTANCE-2ND — 修复批 II 第二路独立验收（2026-10-16）

> 验收身份：zcode 第二路独立验收 subagent（零共享上下文；夜间全自动授权在案，
> 先例 D-07-3-T5-1）。输入 = 修订版 plan（`dafcec88`+`029f84bc`）+ CONTEXT +
> CHECKER + SUMMARY + DECISIONS + 第一路 ACCEPTANCE + 执行链
> `da99ea2f..2427670e`（4 commits）+ 证据域 `gui-acceptance/v2m/fix2-probe/`。
> **本文所有读数均为本路亲跑/亲采/亲读，非转述执行方与第一路。**
> 本路证据 = `fix2-probe/acc2-*` 十一件（local-only）。

---

## 结论头

**PASS（代码面 T2/T3/T4/T5 全部追认）+ T1 BLOCKED 判定追认（D-6 三铁条
未过成立，三选一上报维持）+ 0 error 产物缺陷 + D-FIX2-4 翻案三腿独立坐实
（「per-file insert 静默失败」证伪二次确认）+ 2 minor 自产 + 2 分歧记录。**

- 全套独立复跑 **`TOTAL|3860/35/0|`（2059s，exit 0，七 bundle 全绿零
  MEMFAIL）** = 申报值逐位闭合（3857 + ΔN 3 精确；skip 35 = 24 基线 +
  11 RAW 供件漂移口径维持；七 bundle RSS 全部 8G 门内，峰值 IOPParity
  7597MB）。
- T2 合流 + watchdog 修法代码面四面亲审成立；本路自备供件独立导入轮
  **3/3 完成态**（6/6 行 + 逐行 loaded/rendered）；「零行间歇」经 DB 法证
  16 包全量亲查 + 行为级重开实验，确认**行恒落库、失效面 = grid 刷新迟到**。
- T3 零码翻案核销追认；T5 四波 MANIFEST 三源对表 14 行错开抽验零缺行
  零双计；Blocked 族证据图亲读成立；红线族 9 项亲跑全 PASS。
- D-6：环签名本路自采 sample 两段坐实（makeMainMenu↔updateMainMenu↔
  invalidateProperties↔updatePreferences + prependValue 无去重 +
  getTypeByMangledName 热帧）+ 编辑器面 CPU 82-100%（硬门 <10% 远未达）
  + `@self`-only 决定性读数 transcript 亲扫复现（@self ×29938 精确）——
  **BLOCKED 判定与「修法不可落地」裁定追认**。
- 本路验收意见 = 三选一中的 **①接受降级 + gate=false 壳减树/窗口内容拆分
  专项立项**（与第一路同判）；本路新数据点使 workaround 从「遮挡止损」
  升级为「遮挡断环 + 点击恢复」，同时记录点击表型输入路径分歧。

---

## 一、全套独立复跑（对账）

新鲜 `xcodebuild build-for-testing`（TEST BUILD SUCCEEDED）后
`caffeinate -dis Scripts/test-direct.sh --all`（后台单实例，运行期间仅做
轻量文档审计，零内存压力干扰）：

| bundle | 本路亲跑 | 执行方申报 | 第一路 | 本路 RSS |
|---|---|---|---|---|
| IOP | 687/5/0 | 687/5/0 | 687/5/0 | 7189MB |
| IOPParity | 460/3/0 | 460/3/0 | 460/3/0 | 7597MB |
| Layers | 494/5/0 | 494/5/0 | 494/5/0 | 807MB |
| Library | 729/4/0 | 729/4/0 | 729/4/0 | 622MB |
| Sessions | 284/9/0 | 284/9/0 | 284/9/0 | 1666MB |
| Export | 379/5/0 | 379/5/0 | 379/5/0 | 6393MB |
| App | 827/4/0 | 827/4/0 | 827/4/0 | 2832MB |
| **TOTAL** | **3860/35/0 \| 2059s** | 3860/35/0 \| 2070s | 3860/35/0 \| 2079s | 零 MEMFAIL |

- 三轮互证逐位一致（执行批 / 第一路 / 本路）；对账链 3857 + 3（T2
  `ImportProgressCoalescingTests`）= 3860 精确；skip 35 无第三种来源。
- build-for-testing 新鲜度 = 本路重建（批后 HEAD `a35a734e`——**批外
  docs-only 新 commit 在案**（Alcedo 调研 docs，`git show --stat` 零产线
  文件），不触本批红线窗）；L055 假绿签名零现（七 bundle verdict 全 ok，
  脚本 exit 0；crash / no-total-line 签名零出现）。
- 本路 RSS 峰值 7597MB（IOPParity）在 8G 门内；±3% 方差注记下与执行批
  8112MB 同域（SPIKE 注记口径）。

## 二、红线族亲跑（029f84bc..2427670e 批窗）

1. `.metal` 全域零 diff ✓ 2. `LightamerIOP/` 零 diff ✓ 3.
`LightamerSidecar.swift` 零 diff ✓ 4. 封存面九件零 diff ✓（grep
DrtRecord/GradeCatalog/Registry/HistoryStack/V50Order/ExportFormatSpec/
ImageIOEncoders/WebPEncoder/ExportQueueContract 于批窗 name-only = 空）
5. `\.runModal(` App/Sources **全域零命中** ✓ 6. LocalizationValue 插值
禁形 regex 恰 1 命中 = `LightamerApp.swift:2069` doc comment（`///` 行，
豁免锚亲读）✓；`ExportInspectorView:534` 亲读 = `"export_format_" +
kind.rawValue` **拼接形非插形**，合法 ✓ 7. UserDefaults 批内代码 diff
新增行 = 0 ✓ 8. xcstrings 零 diff ✓ 9. Project.swift 恰 T2 测试一行 +
BUNDLE-MAP 恰一行（`APP 3 ImportProgressCoalescingTests.swift`，tuist
generate 末位随批）✓。
批窗 `git diff --stat` = 9 文件（4 code + 5 docs），T1/T3 零产线 diff
申报成立。**红线族全 PASS。**

## 三、T2 D-7 修法深审（`da99ea2f` 独立亲读）

- **非阻塞形（M-1①）**：`submit` = 锁内单槽 stash + 一次性 fire-and-forget
  调度即返回，**零 await**；100ms 睡眠在 drain Task 内不在 handler 内；
  service handler 闭包 `{ [weak coalescer] in coalescer?.submit($0) }`
  同步形——doc comment Defect A（actor↔main 互等）保持切断 ✓。
- **保序钉（M-1②）**：投递恒 `@MainActor`（drainWindow/flushTerminal 双
  @MainActor）+ `windowDrainArmed` 单飞守卫 + 单槽 latest-wins；adapter
  单调钳维持（第一路亲读，本路未重复）✓。
- **终态恒穿透（双载体）**：`.completed/.cancelled` bypass 窗口且单槽
  supersede 在途 interim ✓；controller `importProgress = nil` 直写 tail
  （:459）零改动 ✓。测试判别力亲读：TestClock 手拨钟 + leading/窗内合流/
  尾沿不丢/终态 bypass-supersede（含「窗缘后 superseded interim 不复活」
  负断言）+ 纯函数缝三臂——四语义覆盖成立 ✓。
- **watchdog**：`os Logger .info`（com.kamasylvia.lightamer /
  import-watchdog）tail 前一行，零行为变更 ✓（`.info` 级 = 第一路
  「`log stream` 缺 `--level info` 致失聪」注记与代码面自洽）。
- **N≥3 轮导入亲跑（本路自备供件 `/tmp/fix2acc2-import` 6 TIFF，
  lane2-*.tif 全新文件名，生产链探针缝 `-la_editor_probe`）**：**3 轮 =
  3/3 完成态**（6/6 行 + 逐行 loaded/rendered；acc2-round{1,2,3}.log）。
  ≥AC N≥3 满足；间歇在本路窗口未复现（跨三路：执行批 8/11、第一路 2/3、
  本路 3/3——间歇真实性由执行批 3 FAIL 轮日志逐轮亲核支撑，见 §四）。
- **窄边界评估（本路自产，2 minor 级，不阻断）**：
  1. **throw 路径 stale-interim**（第一路发现，本路代码面独立复核成立）：
     `importFolder` 中途 throw 无终态 emit；armed drain Task 强捕获
     coalescer（:102 属性清位不灭活已调度 Task），若在 ：459 nil 之后苏醒
     即回写陈旧 interim → :405 `guard importProgress == nil` 拒绝后续
     导入（重启自愈）。常规完成/取消路径被终态 supersede 封死 ✓。
  2. **flushTerminal-vs-tail 理论竞态**（本路新登记）：terminal submit
     先于 `importFolder` 返回调度 flush Task，主 actor 无契约 FIFO——
     若 runImport tail（:459 nil）先于 flushTerminal 执行，`importProgress`
     终态 = `.completed` 非 nil → nil 消费面（WorkspaceHostView :309-332
     task finish + grid reloadFirstPage）不触发 + :405 guard 同样阻塞后续
     导入。enqueue 时序实践上偏向 flush 先行，概率极低、重启自愈，**minor
     登记**。两边界同根修法：tail 处对 coalescer 做 `cancelAndClear()`
     （锁内清 pending + 置代际/取消位，armed drain 与待发 flush 一并封死）
     ——建议下批触此文件时顺手行使。

## 四、D-FIX2-4 翻案复核（三腿独立坐实 + 新数据点）

第一路翻案（「insert 静默失败」→「grid 刷新迟到，行恒落库」）**独立复核
成立，置信度高**：

1. **DB 法证腿（16 包全量亲查，`sqlite3 -readonly` 防 checkpoint 副作用）**：
   15/16 包 `images=6`；唯一 `images=0` = `869ED347`（09:51，T1 时代，异轮
   语境）——与第一路「唯一真零行 DB = 869ED347」精确吻合。执行批 FAIL 三轮
   `B58CAA6A`(11:22,r1) / `8F4D1DC5`(11:24,r3) / `AE849F33`(11:30,r9) 全部
   images=6（8F4D1DC5 mtime 13:46 = 第一路读取时 checkpoint 亲证；WAL=0）。
   第一路自产 FAIL 轮 `A8AC64C8`（13:43）主文件 4096B + **WAL 626KB 未
   checkpoint，read-through-WAL = 6 行**——行在探针 10s 等窗期间已落库
   （WAL 态）的铁证。
2. **行为级腿（本路新产）**：`A8AC64C8` 经 Open Recent 于全新会话重开 →
   网格 **6 张照片全部可见**（「共 6 张照片」+ 图库概览 6 总数；
   `acc2-a8ac-reopen-grid.png`）——「零行」表型在 fresh reload 下消失，
   失效面锁定在 import 完成时的 grid 刷新时机（nil 终态触发的
   `reloadFirstPage` 被 churn/饥饿延迟 >10s），非 insert 路径。
3. **逐轮日志腿**：t2-r*.log 12 件亲核 = 8 PASS（loads=6）+ 3 FAIL
   （r1/r3/r9）——「8/11」申报数字精确吻合，FAIL 轮号与 DB 法证映射一致。

**勘误标签落点建议（移交项，当前未应用）**：TODO D-7 行 / AGENTS ④ /
MANIFEST T2 指针节 + W3 Registered 行 / DECISIONS D-FIX2-4 / GOAL-STATE
移交句——六处「per-file insert 静默失败」表述统一勘误为「**grid 页刷新
迟到（行恒落库，WAL 在案；fresh reload 自愈）**」，独立待研立项以本节
三腿法证为起点。一行级 docs 顺手修。

## 五、D-6 探针定罪独立复核 + 三条新观察 + 表态

### 5.1 定罪复核（全部亲读/亲采）

- **环签名（本路自采 sample ×2 段，3s 各）**：`makeMainMenu(6)/
  updateMainMenu(4)/invalidateProperties(39)/requestUpdate(18)/
  updatePreferences(11)/graphDidChange(14)/appGraphDidChange(7)/
  prependValue(17)/keyboardShortcut(43)/swift_getTypeByMangledName(118)`
  全链在位（`acc2-d6-editor-sample.txt`）；第二段（功能态复燃后）同签名
  （`acc2-d6-editor-sample2.txt`）。**环身份独立坐实。**
- **`@self`-only 决定性读数**：`t1-editor-spin-transcript.log` 亲扫 =
  WorkspaceHostView `@self` ×29938（与第一路逐位同值）+ phase/projectURL
  各 1 次挂载变更，**零稳态属性变更**——「无 app 写点」定罪独立复核成立。
- **threshold 面**：`t1-menu-loop-sample.txt` 全链符号亲 greps 在案
  （getTypeByMangledName 147 / keyboardShortcut 54 / prependValue 21 与
  第一路读数同值）；`t1-c1-inspector-off-sample.txt` makeMainMenu/updateMainMenu
  合计 7 hits（环态样本为数百）——C1 摘 `.inspector` 饿死叙事与样本一致。
  E 系读数维持 DECISIONS 文字记录口径（第一路已注记 evidence 文件仅
  C1/C2 在案，本路同判，不重复扣分）。
- **编辑器面 CPU（本路亲测）**：重开项目 → 进入编辑器 = **82-87%**
  （10×1s ps 窗，frontmost）；交互后功能态 = **98-100%**。硬门 <10%
  两阶远未达——**三铁条未过、BLOCKED 判定追认**。gate=false 空载面 =
  23-31%（可见窗）= 壳族固有病第三路坐实。
- **修法不可落地追认**：`@self`-only = 无写点可断；C1 备案实测（摘
  `.inspector` 编辑器面环照转 + 点击死截图亲读）换不来 spin 消失——
  备案不行使正确。结构性偏差行使（停手上报、零产线 diff、不硬造判定）
  **合规**。

### 5.2 本路新数据点（入专项卷）

1. **遮挡断环 + 不复燃（新）**：编辑器 spin 态（85% CPU）窗口 hide →
   **CPU 6×1s 全 0.0%**；重新显示后 **4s 内不复燃（仍 0.0%）**——比
   第一路「遮挡态 churn 归零」更强的形态：遮挡不仅压低 churn，**杀死
   spin 环且解除遮挡后不自动重启**（display-cycle 耦合断环；环需新交互
   再点火）。`acc2-d6-editor-broken.png` = 解遮后断环态（空态卡仍在、
   CPU 0%）。
2. **遮挡循环后点击恢复（新，N=1 循环 2/2 点击）**：断环态下 filmstrip
   点击（cliclick 真实鼠标）acc2/acc3 **两连击全部响应**——选中 ring 翻转
   + 视口出图 + 右栏 mount（`acc2-d6-click-after-occlude.png`）+ churn
   复燃 98-100% 同签名。**「坏态」经一次选择即自愈为「功能态-with-churn」**。
3. **点击表型输入路径分歧（分歧记录）**：本路 **3/3 点击全响应**（含
   1 次无遮挡直接点击：fresh 重开 → 进入编辑器后 6s 直接点 acc2 =
   立即出图，`acc2-d6b-aleg-click-no-occlusion.png`）vs 执行批 probe-11
   「AX row 点击零响应」+ t1-filmstrip-click-dead.png 占位变体。分歧源
   假说 = **AXPress 合成路径 vs 真实鼠标 CGEvent 路径**（m6 harness 教训
   「键盘 CGEvent 不进 app」同族的输入通道差异），或间歇表型（与导入
   零行同级的概率性）。**不影响 T1 判定**：CPU 硬门（SC 主判据）82-100%
   远超 <10%，BLOCKED 与 CPU 无关点击表型；但「filmstrip 点击零响应」
   在后续专项走查中应**双输入路径对照复测**（AXPress + cliclick）再定
   表型边界。
4. **legacy 菜单点火分歧（分歧记录）**：空 legacy 面（无会话）File 菜单
   挂开态实测 **0.0%**（5×1s；`acc2-legacy-menu-open.png` 菜单确实开着，
   inert-disabled 项可见）vs 第一路 41.5%（其 legacy 面曾带 d2-session
   带图会话）。点火条件疑与「菜单环 × 面内容复杂度」相关，非无条件——
   第一路观察维持其记录口径，本路数据点收窄其适用域。

### 5.3 三选一表态

**同第一路：①接受降级 + gate=false 壳减树/窗口内容拆分专项立项。**

- ③（回退 macOS 27）与 Lock-early 决策冲突，不建议。
- ②（research 复审）并入专项第一步（五读数已决定性）。
- **workaround 完备性（本路裁决：现账面不完备，需一行级补记）**：
  「遮挡止损」**未写入任何用户可及文档**（TODO D-6 行无 workaround 句，
  第一路 §5.3 仅为建议未落地）。且本路 §5.2.1/5.2.2 数据使该 workaround
  从「止损」升级为「**遮挡即断环（CPU 归零）+ 一次点击即恢复编辑**」——
  降级期用户侧可操作性比第一路估计更强。建议专项立项批同批把 workaround
  句补入 TODO D-6 挂账行（无需代码）。C 档用户裁决点不变。

## 六、T5 走查四波 MANIFEST 三源对表（错开抽验 14 行）

对表三正本（V2M-VALIDATION §挂账①② + v2m/MANIFEST「FIX2-01 T5」节 +
m6-closeout MANIFEST 总队列 42 行）错开抽验：

| # | 抽验行 | 正本状态 | FIX2 终态落位 | 判定 |
|---|---|---|---|---|
| 1 | M6C-03/05（追色 solve） | Blocked-Defect(D-1) | W1 Blocked-Channel | ✓ |
| 2 | M6C-06/07（数值/before-after） | Blocked-Defect/Manual | W1 Blocked-Channel | ✓ |
| 3 | M6C-08（关图重开恢复） | Blocked-Defect | W2 Blocked-Channel | ✓ |
| 4 | M6C-32/33（无人像 toast/羽化三档） | Blocked-Manual | W2 尾 Blocked-Channel（判据原文 m6-4 M-3/M-4 在案） | ✓ |
| 5 | M6C-16..19（pano） | Blocked-Manual | W4 Blocked-Channel | ✓ |
| 6 | M6C-34..38（栈面） | Blocked-Manual | W4 Blocked-Channel | ✓ |
| 7 | M6C-40（guided filter） | Blocked-Manual | W4 Blocked-Channel | ✓ |
| 8 | M6C-24/25（HDR 屏） | Blocked-Manual(HDR) | 排除（硬件） | ✓ |
| 9 | M6C-26（UltraHDR 样张） | Blocked-Manual | 排除（供件） | ✓ |
| 10 | M6C-27..31/39 | Blocked-Env | 排除（供件族） | ✓ |
| 11 | M6C-10（Registered-obs） | Registered-obs | 排除+理由注记 | ✓ |
| 12 | M6C-12（filmstrip 1/3） | Executed 1/3 | 排除+理由注记（D3-01 覆盖） | ✓ |
| 13 | M6C-14（deghost 三档） | Blocked-Env | 排除+理由注记（UI 通道缺席与通道修复无关） | ✓ |
| 14 | E2-1 四行 T1-02/D3-01/D4-01/D5-01 | 挂账②硬义务 | W1/W2 全在 | ✓ |

**行集完备、零缺行、零双计、排除注记逐行在案（M-4/M-5 配套钉兑现）。**

- **Blocked 族证据图亲读**：`t5-w2-multiselect-cmdflag-dead.png`（两次
  cmd+click 后仅 A.ARW 单格 ring = REPLACE 非 toggle-add，判据面成立）✓ /
  `t5-w3-panel-tmp-unsearchable.png`（Spotlight 搜 srctiff 空转零结果）✓ /
  `t1-filmstrip-click-dead.png`（D-6 占位变体 + 空态卡 + No Image
  Selected）✓。
- **T3 证据图亲读**：`t3-legacy-step2-editor.png` = legacy 面 Single 模式
  带图渲染（夜景灯笼图）+ 右栏调整栈 mount（Temperature/Tint 6504K/1.000
  + 模块列表）+ Ready——T3 三步证据真实 ✓。
- **「快照上移」返工不触发**追认：D4-01 对话框从未呈现（多选通道死）≠
  复验见 0；返工 contingency 面 SessionBrowserView.swift 零 diff ✓。
- **「零行以代码面证据替代屏面判据销账」声明复核成立**：唯一 Executed
  两行（T3 配方三步 / D-7 生产链完成态）均有屏面/运行证据；W3 面板腿
  如实 Blocked 未混记 ✓。
- **W3 D-7 = 生产链口径 Executed 追认**：`-la_editor_probe` 走
  `controller.runImport` 产线路（代码面亲读确认），8/11 逐轮亲核精确。

## 七、偏差四项 + 第一路 4 minor 裁决

**偏差四项（全部追认）**：

1. **T1 结构性偏差（修法不可落地 → BLOCKED 上报）**：合规追认（§5.1）。
2. **导入零行间歇新观察**：观察成立 + 登记合规；**机理标签错误经本路
   三腿法证二次确认**（§四）；勘误未应用 = 移交项（非阻断）。
3. **NLMeans flake（首轮窗外 crash 1 例）**：追认——本路亲读
   `/tmp/fix2t1/t4-all.log`（IOP crash verdict + peak 5090MB + ↳ 签名行）+
   `t4-iop-rerun.log`（隔离重跑 687/5/0）+ `t4-all2.log`（全套绿逐值）+
   本路独立全套轮 IOP 687/5/0 = 四轮互证；flake 台账延续先例。
4. **watchdog 日志失聪**：接受（代码面 `.info` 级与「缺 `--level info`
   不入流」假说自洽；本路未重跑 stream 验证，留给 D-7 族开工时一行验证）。

**第一路 4 minor**：

1. **D-FIX2-4 勘误**：三腿坐实（§四）；**待应用**（六处落点清单已列）。
2. **t2-r*.log 回填**：12 件（t2-round1 + t2-r1..r10 + watchdog-stream2）
   亲点在案 ✓，指针闭合。`/tmp/fix2t1` B/C/E 系探针语料**本路实测仍在**
   （未重启）——回填窗口仍开，建议随勘误同批执行（易失警告第三次）。
3. **探针缝 terminate 挂起**：本路 **3/3 复现**（每轮 PASS 后 NSApp.terminate
   均挂起需 kill；遮挡态下 terminate 不可靠）——minor 成立，建议缝内补
   `exit(0)` 兜底。
4. **遮挡门控**：方向证实 + 强度升级（§5.2.1）；菜单点火分歧如实记录
   （§5.2.4）。

## 八、台账时序与产物面

- M-6 时序钉：T4 commit（e46ca566）GOAL-STATE 续接点 = 「修复批 II 代码面
  收口，T5 走查复走批执行中」非 closed ✓；T5 commit（2427670e）方追加
  「修复批 II closed → 新特性立项待用户定向」，历史行追加不改写 ✓。
- TODO 三行翻账口径亲核：D-6 open（三选一待裁）/ D-7 fixed（W3 收口注记）/
  D-8 **翻案核销（非「已修复」）** ✓；AGENTS FIX2 行在位 ✓（含探针定罪
  范式 + 合流范式 + 翻案核销 + 新观察 + 红线终态五段）。
- commit 链 = `da99ea2f`（T2 产线+测试）+ `4ee0ccd6`（T2/T3 裁定 docs）+
  `e46ca566`（T4 对账+台账）+ `2427670e`（T5 收口）；**未 push** ✓。
- 批外新 HEAD `a35a734e`（Alcedo CLI/AI 调研 docs，另一会话产物）不触
  本批窗（本路红线机检双窗 029f84bc..HEAD 与 ..2427670e 均 PASS，零产线
  文件涉入）。
- 本路产物：本文件 + 证据域 acc2-* 十一件（3 轮日志 + 2 sample + 4 截图
  + 1 legacy 菜单截图 + 1 全套日志）。零产线 diff；未 push。

## 九、移交决策项（orchestrator，与第一路合并后呈报）

1. **D-6 三选一**：两路同判 **①接受降级 + gate=false 壳减树/窗口内容
   拆分专项立项**；专项卷带上：第一路 §四.4 三条 + 本路 §5.2 四条
   （遮挡断环/点击恢复/输入路径分歧/菜单点火适用域）+ 精确定性措辞
   （「macOS 27 SwiftUI 菜单/焦点更新机制在特定树形（重树 + .inspector
   分栏宿主 + 三段内容）下不收敛」）。
2. **D-FIX2-4 勘误应用**（一行级 docs，六处落点 §四）+ **workaround 句
   补入 TODO D-6 行**（§5.3）+ **/tmp/fix2t1 B/C/E 系回填**（同批；
   现仍存活第三次警告）。
3. **T2 窄边界两枚**（§三）：throw-path stale-interim（第一路）+
   flushTerminal-vs-tail 理论竞态（本路）——同根修法 `cancelAndClear()`
   建议下批触 LibraryProjectController 时行使。
4. **点击表型双路径复测**（§5.2.3）：专项走查对 filmstrip 用 AXPress 与
   cliclick 双输入通道对照，定「点击零响应」表型边界（AXPress 伪象 vs
   间歇真死）。
5. **探针缝 exit(0) 兜底**（第一路 minor-3，本路 3/3 复现）——下批触
   WorkspaceHostView DEBUG 缝时顺手。
6. 双重验收（dual_acceptance）：两路 zcode 验收 PASS 收口后，按制度串行
   呼叫 omp 二次验收（computer-use 单实例约束）。

---

> 验收人：FIX2-01 第二路独立验收 subagent（zcode，2026-10-16）。
> 亲跑清单：全套 --all ×1（2059s）/ 独立导入轮 ×3（自备供件）/ D-6 复现
> ×2 会话 + 自采 sample ×2 + 遮挡/点击 A/B 实验 ×1 组 / legacy 面 + 菜单
> 开态 ×1 / gate=false 空载面 ×1 / 红线族机检 ×9 项 / DB 法证 16 包全量
> / t2-r*.log 12 件逐轮 + t4 三件 flake 链 + transcript/sample 亲读 ×5
> / 三源对表错开抽验 14 行 / 证据图亲读 ×6。

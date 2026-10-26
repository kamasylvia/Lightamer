# R6 修复批 — omp 复核（execute 道二次验收，computer-use 实机，2026-10-27）

**FAIL / 1 B + 0 M + 1 m + 3 obs**

> 第二眼独立复核。复核对象 = R6 四 fix（`363e4387` T1 导入零行 /
> `95729b14` DRT / `f77d3488` film / `eba66447` raw）与 zcode 验收报告
> `R6-ACCEPTANCE.md`（PASS/0B+0M+0m+2obs）。本场 = 重建构建实机（binary
> mtime 10-27 02:57，四 fix in-HEAD 自证）+ T1 复走 15 轮 + 压力腿 + T3
> 三链 + 大导入回归 + zcode 对账。**结论与 zcode 分叉**：T1 修法缝内逻辑
> 闭合但病灶未除（18 独立轮 5 败 28%），判 blocking。

## 一、逐面判定表

| 面 | 配方预期 | 实机观察 | 判定 |
|---|---|---|---|
| ① T1a 导入复走（zcode 配方） | 5/5 到达 0.54-0.66s | 5 轮 4/5（round5 零行复活）；扩样 10 轮 3 败；**15 轮 4 败**（到达轮 0.33-0.66s，绿轮与 zcode 数据吻合） | ❌ B（§二） |
| ② T1b 压力腿（双并发导入） | 无复活/无零行 | 双实例并发双绿 16/16（stressA/B 零 FAIL） | ✅ |
| ③ T3-film 链 | 启用→关→重进存活 | 启用 readout「M 18.3·Y 16.7·×1.00」+ 双 picker（C200/相纸）→ 返回图库（Film 面板共存）→ 双击重进 → readout/双 picker 逐字存活（`omp6-05..08`） | ✅ |
| ④ T3-raw 链 | 改值→关→重进保持 | ARW 真档 RAW 页降噪「强度」System Events 设 0.50 → 关 → 重进 → **0.50 保持**（`omp6-10..11`；修复前 reseed 读空归零） | ✅ |
| ⑤ T3-DRT 链 | 设 DRT→关→重进仍在 | **链不可达**：显示变换页 DRT 面板双实例不渲染（vignette 独占，上下滚动穷尽，`omp6-09`） | ❌ m（§三） |
| ⑥ 回归：大导入 N=20 | 完成态照常发布 | 3 轮 2/3（20 行 0.63-0.73s 到达）+ 1 零行（DB 20/20，T1 同族）；绿轮证 invalidate 未破坏正常发布 | ✅（零行归 B） |
| ⑦ 对账 obs-1/obs-2 | 各评一句 | obs-1 认同（§四）；obs-2 属实（9224188f..HEAD 四笔纯 .work/，亲核） | ✅ |

## 二、B-1：T1 零行修复后 28% 复活（blocking）

- **数据**：独立计时轮 18 轮（T1a 15 + 大导入 3）**5 败**；失败轮表型与
  R5-2/obs-4 逐字同源（DB 恒落库 16/16 或 20/20、grid 永零行、主线程 idle
  事件循环采栈、`"FAIL: grid rows never arrived"`）。
- **失败活体取证**（stay-alive 实例 82437/83381 双活体）：
  - oslog watchdog 行在位（run tail 到达，nil 已写）+ AI 行存在（tail 已过
    nil 写）+ 导入行残留「正在导入照片…」+ 对话框 detail「**导入完成**」+
    ProgressIndicator val=1 → **terminal 交付到达 adapter，nil-finish 分支未
    执行**（`omp6-01/02` + AX 树 + 截图三证）。
  - 导入行取消钮 AXPress err=0 后行消失、grid 仍零行 → registry 面活，
    grid 发布独立丢失。
- **修法缝评估**：`invalidate()` 三面锁语义 + run tail 调用序亲核**逻辑闭合**
  （nil 恒终写者——机制面判别 2 法 sabotage 乙确定性真红亦佐证）；本轮失败 =
  **缝外第二病灶**：nil 已写但 `ImportProgressModifier` else 分支未跑（onChange
  nil 丢失或等价形态）。R6 归因（复活竞态）覆盖病灶之一，非全部。
- **对 zcode 5/5 的解释**：零行是概率性调度竞态（28%/轮下 5 连绿概率约
  19%）——zcode 5/5 系小样本幸存，非修复实证。本轮 15 轮 4 败在低载期复现，
  与 obs-4 低载 2/5 基线同量级。
- **路由**：T1 不得签核；后续批需对 nil-finish 丢失链（onChange 观察/合并语义
  或未知复活者）立项诊断。本报告证据（活体 AX/截图/watchdog 行）即输入。

## 三、m-1：DRT 面板不渲染（minor，T3-DRT 实机链 blocker）

- **现象**：显示变换页双实例（84202/85940）DRT 面板缺席——vignette 独占整页
  （上下滚动穷尽），AX 树无 DRT 控件（`drt.method.picker`/方法/编码/峰值全缺），
  无错误日志；RAW 页 specialContent 同实例活（输入色彩/传递曲线/峰值），通道
  非整死。
- **窗口**：最后活证 = M2-11（10-07）/M6-3（10-14 经面板 Peak 操作）；10-17
  AR-01 把 DrtPanelView 改 onAppear lazy-build 后**无实机活证**——疑该重构回归
  或 probe 态专属，未定（黑盒不可达，需源码断点/日志缝）。
- **T3-DRT 降级判**：修法与 film/raw 同构（删 drop 三行 + doc，源码面 zcode
  已亲核）+ 单测改写覆盖 + 本轮 film/raw 双实机 → 修法本身不疑；实机链因本
  缺陷未达，记 minor 不扩 blocking（DRT 面板属既有面，非 R6 引入）。

## 四、zcode 报告对账

| 条 | zcode 申报 | 第三眼裁决 |
|---|---|---|
| obs-1（生产缝法 sabotage 甲假绿） | 申报边界如此设计，机制腿承担判别 | **认同**：本轮 B-1 反向佐证——生产缝法在修复「在位」下仍可红（实机 28%），其非判别腿定位正确；机制 2 法的确定性交错是唯一真判别，sabotage 乙真红成立 |
| obs-2（并行账本两笔） | 纯 .work/ 零产品面，结论不受影响 | **属实**：亲核 9224188f..HEAD = 四笔（含验收报告自身），`--name-only` 非 .work/ 为空；本轮构建 = HEAD 含四 fix，源码层一致 |
| 5/5 全绿 | 修复后零失败 | **推翻**：本轮同配方 15 轮 4 败 + 同族表型活体取证；5/5 = 小样本幸存（§二） |
| 反自取消结论 | 判别力成立、无自取消 | **维持**：sabotage 乙真红的机制腿判别力不受 B-1 影响（缝内逻辑闭合）；B-1 是缝外第二病灶，非自取消 |

## 五、观察项（obs，本轮新增 3）

- **obs-1（tab 条 AX 索引随 film 列漂移）**：无 film 列时 tab 条 = 子索引
  /30-36 七连；film 列在位时 = /20-26 七连（RAW=/25，显示变换=/23）。走查
  驱动应按「inspector.row 区邻接 + 七连特征」动态定位，非硬编码索引。
- **obs-2（System Events 深 AX 补盲）**：自研 swift AX 遍历（depth 10）漏
  Form 深层 slider，System Events `entire contents` 可见且可写（raw 强度设
  0.50 落定；CG 拖/点双死）。后续面板写入配方：System Events 设值优先。
- **obs-3（菜单 AXPress 闭合态假成功）**：「显示胶片面板」press err=0 但页未现
  （m7-6 登记的 closed-menu artifact 同族）；「返回图库」同通道有效。菜单驱动
  后必须 AX/截图双验挂载，不可信 err=0 单证。

## 六、证据索引

- 截图（本目录 `omp-evidence/`）：`omp6-01-fail-window.png`（失败活体全屏：
  零行 + 导入条残留）/ `omp6-02-fail-dialog-complete.png`（对话框「导入完成」）/
  `omp6-03-editor-tone.png`（编辑器 Tone 页）/ `omp6-04-raw-page-alive.png`
  （tif 只读面）/ `omp6-05-film-pristine.png`（film 启用前）/
  `omp6-06-film-enabled.png`（启用 readout）/
  `omp6-07-library-film-coexist.png`（图库+Film 共存）/
  `omp6-08-film-survived-reentry.png`（film 重进存活）/
  `omp6-09-drt-panel-absent.png`（DRT 缺席）/ `omp6-10-raw-nr-050.png`
  （0.50 落定）/ `omp6-11-raw-survived-050.png`（raw 重进保持）。
- 日志（/tmp 即弃域，轮值转录在案）：`/tmp/r6-omp-gui/round{1..5}.log`
  （4/5）/ `/tmp/r6-omp-gui2/round{6..15}.log`（7/10）/ `/tmp/r6-omp-stay/`
  （活体 AX 树 fail-ax/fail2-ax-dialog、采栈 fail-sample.txt、T3 链 AX 全套）。
- 构建：binary mtime 10-27 02:57，四 fix `merge-base --is-ancestor` in-HEAD
  全过；monitor 全程零 RSS-KILL（`RSS-MONITOR start` 单行）。

## 七、卫生

- 每轮实例 SIGTERM/kill 清零（ps 复核 0 实例）；`library.recentProjects`
  探针污染整键删除（键不存在复核）；monitor 用后停（pgrep 空）；
  /tmp fixture（r6-omp-t3/raw/big）即弃，round log 按惯例留存；tracked 零
  diff（本报告 + omp-evidence 为唯一新增 untracked）。
- guard 说明：`--wait` 被自身 omp 命令行文本误判 G1（任务书含匹配串），
  改手动三门实质通过（G2 73% / G4 28GB / 真重活零 / GUI 零）后推进——guard
  G1 口径建议排除自身进程族（obs 口径，不入计数）。

## 八、结论

T3 film/raw 双链实机存活（R6 修法同构三件中两件落地）；T1 修法缝内闭合但
**第二病灶致 28% 复活**，zcode 5/5 系小样本幸存，T1 不得签核；DRT 实机链被
既有面板渲染缺陷阻断（minor）。**R6 批 omp 复核 = FAIL（1 blocking + 0
major + 1 minor + 3 observations）**。B-1 输入与 m-1 输入均已就绪，后续批
可直接立项。

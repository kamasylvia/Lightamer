# M2-3-4 ACCEPTANCE — 收口（zh 对账补录 + Alcedo 逐屏走查 + 审计翻账）＝ M2-3 phase 终局验收（独立验收报告）

> **PASS / 0 error + 2 minor**（F1 zh verbatim 缺口、F2 计数笔误；3 条 info 级
> observation 不计数，见 Findings。另 2 项走查期真缺陷 A/B 已由 executor 如实转专项，
> 不计入本 plan 缺陷——根因文件均不在本 plan 申报集。）
> 独立验收 subagent（2026-09-30）。plan = checker 修正版 `897bcb2`（含 E4 接账节 +
> E1 勘误钉）；执行 = 4 commits：T1 `8e41851`（zh-audit.py + 223 键 + verbatim 三文件
> 转换 + 测试断言 locale 无关化）→ T2 fix `a3bf5bf`（图库刷新缝 + Look zh 外观）→
> T2 docs `20ae5ee`（20 屏三件套 + MANIFEST + walk.py）→ T3 `934dd19`（五项审计 +
> 翻账 + SUMMARY/DECISIONS）。终跑口径 = orchestrator 强杀指令（2026-09-30）：
> 引用基线 2160/14skip/0fail @ `d7f87fe` + w4 域内定向验证。

## Verdict

10/10 AC 全过（逐条独立复验，见下表）；五重点核查全过；KD-3 五项审计本批亲跑全绿；
D10 独立抽查 3 屏 3/3 与 executor 判定一致（无重开屏）；强杀口径收尾诚实（deferred
显式登记非缺口掩盖，域内验证可独立复现——本批已复现 zh-audit 双模式 + 6 族定向）。
2 项 minor 均不阻塞：F1 = 验收独立走查新发现的 zh verbatim 缺口（新债务挂 M2-4），
F2 = SUMMARY 计数笔误（本批已原子修正）。

## 逐 AC 核验（10/10）

| # | AC | 验收核验 | 结果 |
|---|---|---|---|
| 1 | zh 对账四断言 | `uv run python3 Scripts/zh-audit.py --check` 亲跑 exit 0（1157 source / 1369 catalog / zh complete / {en,zh}）；语义级 JSON 对比独立机检：old=1146 → new=1369，added=223 / removed=0 / **modified=0**（既有键零改写实锤）；zh-Hans 全文 0 命中 | ✅ |
| 2 | self-test golden | `--self-test` 亲跑 exit 0（missing/orphan/zh-missing/zh-Hans 四 case 检出 + clean + allowlist） | ✅ |
| 3 | 屏覆盖 15+ + 胶片条专用词 | 20 屏 = 15 基线逐一在 MANIFEST + 5 增补；`editor-filmstrip.md` 判定列含且仅含 1 行「偏差-接受（设计差异）」（全库唯一）；屏级分布 一致 11/偏差-接受 8/设计差异 1 机检核对 | ✅ |
| 4 | 三件套存在 + 判定词封闭 | 存在性命令亲跑零输出（`__pycache__` 残留致初跑 1 条 MISSING，本批清除后复跑零输出——F3 info）；判定列提取：LC_ALL=C 分布 = 一致 51 / 偏差-接受 22（含 1 设计差异）/ 表头 20，与 MANIFEST 声明逐值一致；无 LC_ALL=C 时 collation 合并现象与 MANIFEST 注记吻合；两口径 sort -u 输出均 ∈ 封闭集 | ✅ |
| 5 | 偏差-修闭环 | MANIFEST 2 条 → 均 `a3bf5bf`（git show --stat 可溯：WorkspaceHostView.swift +10 / xcstrings 单值）；无未修残留；Look 页复验截图实拍「外观」已渲染（识图确认） | ✅ |
| 6 | 锁屏降级记录 | MANIFEST 显式「未触发」+ Alcedo 证据受限一处（import 确认框，红线禁改其项目）如实记 | ✅ |
| 7 | KD-3 五项 | 本批亲跑：#1 legacyBody 6 文件零 diff；#2 禁用 op 5 命中逐行核对全为 `//` 注释行（EditorTabRoute :14/:100/:156 + EditorAdjustmentStackView :20/:220，E1 勘误说明）；#3 Core diff 恰 3 文件 = RAWDecoder.swift + RAWTechnicalParams.swift + HistoryHash.swift（后两者同一 commit `921a98f` 落，KD-4 申报连带核实）；#4 Inspector 族零 diff；#5 zh-check exit 0 | ✅ |
| 8 | 全套 0 fail | 强杀口径：deferred 登记三处同口径（SUMMARY/DECISIONS D-orch-1/GOAL-STATE：7.5G+swap 用户叫停 exit=137、test bundle 拆分提级 M2-4 首 plan）；引用基线 2160/14/0 @ `d7f87fe`（M2-3-3 验收 R2）；域内定向 6 族本批独立复跑 **49 tests / 0 fail**（9+6+9+9+11+5） | ✅（口径内核销） |
| 9 | 翻账批 | REQUIREMENTS 核对：M2UIW-01..06 均带 P4 走查 Delivered 锚（判定分布 + `a3bf5bf` + 真缺陷转专项指针）；M2UIW-05 = 设置页族 T5 锚 + LCR/ACA「arrives with M2-10」诚实空态 + zh 补录 Delivered（+223 键机检 exit 0）；M2DIS-03 终注 + P4 走查一致；M2DIS-04 Delivered（NR 四滑杆 + decoder version）；M2LIB-05 P4 走查 Delivered；M2LIB-07④ Import Defaults 注记在；TODO M2-3 块 + M2-4 队列（含缺陷 A/B/relink 写面/双显示菜单）+ GOAL-STATE 续接点同批——单一状态源无漂移 | ✅ |
| 10 | diff 边界 | 4 commits 逐 commit `git show --stat` 核对：T1 7 文件（含 2 测试）/ T2 fix 2 文件 / T2 docs 22 文件（md+walk.py；png 按 orchestrator 红线留本地，`.git/info/exclude` 有登记——申报集注记形态，非越界）/ T3 5 文件；无申报外代码文件 | ✅ |

## 五重点核查结论

1. **缺陷 A/B 证据链真实性：扎实**。A = 2/2 复现（34+6 文件链接导入）+ 量化落库
   （images 40 行全落/FTS 34 行）+ sample 方法论正确（主线程空闲于事件循环、全进程零
   import/sqlite/IO 栈帧、CPU 0% = 续延悬挂形态，非 IO/计算停滞）+ 取消路径可干净收尾
   佐证 seam 在而完成发布缺失；原始 sample 留 /tmp 即弃（家目录纪律内），文本摘要
   SUMMARY/MANIFEST 双落。代码级佐证：`a3bf5bf` diff 证明 adapter finish 只挂在
   onChange nil 分支——nil 不发布则 bar 永挂，与 A 症状同构自洽。B = 3/3 复现（含冷启）
   + EXIF 错值具体化（行 1 DSC09991 节点头显示 DSC00012 值）+ look 页复验截图同框佐证
   （空白视口 + `0 mm — 1/25 s ISO 800` + 图库缩略图正常渲染 = 缺陷定位于编辑器加载链
   而非缩略图管线）。A/B 登记三处齐（MANIFEST 真缺陷节 + TODO M2-4 队列 + GOAL-STATE）。
2. **a3bf5bf 修复评语**：修的是「刷新缝」（onChange nil 分支缺 grid reloadFirstPage +
   inspector.refresh），**不是缺陷 A 根因本身**——根因（runImport 尾语句永不执行）转
   M2-2 域专项，分工正确。修复根因诊断对（nil 分支是唯一完成发布点，refresh 缺失即
   「落库但图库空」的成因）；复验诚实注明「定向复验走取消路径触发 nil，全链复验受
   缺陷 A 阻断」——不夸大修复效力，登记形态合规。
3. **zh 223 键**：`--check`/`--self-test` 亲跑 exit 0；语义级对比 added=223/removed=0/
   modified=0；抽 12 键对照代码调用点（EditorTabRoute/ImportModeDialog/ImportProgressView/
   LibraryProjectController/SettingsPages/EDRControlView）语义全部忠实，术语与需求原文
   一致（「记住我的选择」= M2LIB-07④、「卷相对路径」= ImageLinker kind1 语义）；风格
   合规（按钮无句号、半角标点、技术标识符不译）。
4. **观察清单四项**：记录完整且诚实——①部分达成 + 万行真机目测挂账（合成滚轮不驱动
   List 如实记）；②达标（⌘F/⌘W/⌘E/⌘O 真按键实测）+ 附带双「显示」菜单 IA 瑕疵判
   偏差-接受（成本）；③不可观察（被 B 阻断）不伪结论；④现状 + 两方案留用户晨审。
   登记形态合规（观察项非门）。
5. **强杀口径诚实性**：三处同口径显式 deferred 登记（非沉默缺口）；被杀全套暴露的
   3 fail 归因 = 测试断言英文字面 copy 被 zh 本地化影响（D-t1-3，非产品缺陷）且修复
   （locale 无关断言）已入 T1 并经本批 6 族复跑背书；基线引用注明代际（M2-3-3 R2）。

## Findings

- **F1（minor，验收新发现，挂 M2-4）**：默认面 `ProjectWorkspaceFace`
  （`App/Sources/Lightamer/UI/ContentView.swift:660-697`）4 处 `Text(verbatim:)` 用户
  可见文案（"Lightamer" 品牌词除外："No project open." / "Create or open a project to
  organize your library." / "Project open. Import a folder to fill this project." /
  "Import Folder…"）zh 缺口——该文件头注释自承诺「The complete two-workspace shell +
  zh copy = M2-3」，T1 verbatim 转换范围（D-t1-2 三文件）未含本面。zh-audit 按 KD-1
  设计排除 verbatim 故机检不报；zh 机器实拍英文空态为证（抽查 spot1 同轮主窗截图）。
  不越界修理由：ContentView 受 KD-3 #1 文件级零 diff 审计约束 + 修复需重建与复走查
  （超验收批 ≤20 行权限语义）。处置：挂 M2-4 队列（与两真缺陷专项同批裁量）。
- **F2（minor，本批已修）**：SUMMARY/T3 commit message「定向 6 类 **55** 测试」与自列
  枚举（9+6+9+9+11+5=49）不符；本批独立复跑实测 49/0fail，SUMMARY 已原子修正为 49
  （commit message 不改史）。T1 commit message 同笔误，随史保留、以本报告为准。
- **F3（info，本批已清）**：walk.py 运行残留 `.work/gui-acceptance/m2-3/__pycache__/`
  使 AC#4 存在性命令输出 1 条 MISSING（非屏目录）；已清除，复跑零输出。
- **F4（info）**：editor-viewport / editor-filmstrip / editor-scopes 三屏共享同一
  Alcedo 截图文件（同窗多区合理复用，md 判定表各自独立）；不影响判定有效性。
- **F5（info）**：工作区存量滞留物（`.work/gui-acceptance/09-3-tiers-*.jpg` 两处
  modified + 根目录 `IMG_3061-3.ARW` 等 untracked）均在 4 commits 之外，非本 plan
  触碰；未纳入本验收提交。

## D10 独立抽查（本批执行，MANIFEST 抽查位已填）

3/3 屏与 executor 判定一致：library-welcome（Alcedo 实拍与 executor 截图逐像素级一致）、
settings-about（十入口 zh + 版本/MIT/GPL 致谢归因如实）、settings-language-theme
（跟随系统/深色 v1 固定）。证据三件存 `.work/gui-acceptance/m2-3/spot*-acc.png`
（本地，git 排除）。Alcedo 零污染（仅导航观察，未开项目未改设置，退出未存会话态）。

## M2-3 phase 小结（P1..P4 全闭环）

- **4 plans 全 PASS**：M2-3-1（壳骨架，验收 PASS）→ M2-3-2（图库面，验收 PASS）→
  M2-3-3（编辑器面，验收 PASS / 0 error + 1 minor）→ M2-3-4（收口，本报告
  PASS / 0 error + 2 minor）。
- **测试**：phase 内 2049 → 2160（+111：P1 +54 / P2 +27 / P3 +30；skip 13→14 =
  bench MANUAL-ONLY 门控）；M2 里程碑宽口径 1889（M2-1 末）→ 2160。P4 终跑按强杀
  口径以基线引用 + 域内定向收束，全套恢复 = M2-4 首 plan（test bundle 拆分）。
- **Manual-Only 汇总**：真实 C1 目录导入复跑（M2-2-2 起）；万行胶片条真机 60fps 目测
  （待真实大语料）；示波器 PREVIEW 帧率目测（随缺陷 B 专项）；左轨/胶片条宽度观感
  （用户晨审，方案 a/b/c 已列）；D10 抽查 3 屏（本批已完成销账）。
- **遗留挂账（M2-4 队列，TODO 同步）**：test bundle 拆分（首 plan）；真缺陷 A
  （导入完成态不发布，M2-2 域）；真缺陷 B（编辑器加载失败 + EXIF 错位，M2-3-3 域）；
  relink Core 写面小 plan；双「显示」菜单 IA 裁量；F1 zh verbatim 缺口；decode
  overrides 持久化（M2-4 schema）；catalog 7 死键修剪（D-allow 待办）。
- **C 档第 3 停就绪**：phase VALIDATION（verify-work）材料齐——本报告 + SUMMARY +
  MANIFEST 交用户过目，确认后 M2-4 起航。

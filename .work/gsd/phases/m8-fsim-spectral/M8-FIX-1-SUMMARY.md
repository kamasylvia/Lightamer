# M8-FIX-1-SUMMARY — omp 终审 M-1 修复批收口摘要（2026-10-26）

> 缺陷正本 = `ACCEPTANCE-OMP.md` §二 M-1；诊断与裁决正本 =
> `M8-FIX-1-DECISIONS.md`（本文只记账 + 对账，不重复裁定正文）。
> 基线 HEAD = `c0f1e5a1`；全套基线 4286/46/0（M8-3 三轮）。

## 逐任务记账

| 任务 | commit | 产物 | 测试增量 |
|---|---|---|---|
| T1 根因二分 | `73421ef9`（账本） | 诊断构建五处插桩即弃 + 复现 A/B 双轮实证 + DECISIONS 诊断节 | 0 |
| T2 修复 | `7422401a` | `WorkspaceModel.closeEditor` 免除 process 载体 drop（`dropSessionProcessVersions` 删除）+ 契约注释修订 | 0（随 T3） |
| T3 回归 | `7422401a` | ProcessVersionCarrierTests #7 改写（close 保留 + legacy 判别腿）+ #9 新增（M-1 疾病链端到端，生产缝） | **+1** |
| T3 账本 | `73421ef9` | AGENTS 架构索引 process 不变量行扩注 + ARCHIVE M6-2 App 面勘误行（追加式） | 0 |
| T4 全套 | 本 commit | DECISIONS T4 对账节 + 本 SUMMARY | 0 |
| **合计** | | | **+1** ∈ 任务书带 [+3..+8] 外——下缘修正申报见下 |

## T1 结论速览（详证 = DECISIONS 一）

- **omp 双候选均证伪**：①probe mint 未执行——干净路径插桩实证
  `restoreProcessVersion v=2` 正常落地（probe 与正常路径同构，同一
  `PipeCoordinator.load` pristine 分支）；②carrier 缺席读腿——读腿按契约
  行事，缺席本身是被制造的。
- **真根因**：`closeEditor()` 的 `dropSessionProcessVersions()`（M6-2-01
  注册的关图丢弃）在无 sidecar 新档上丢弃 mint 的唯一副本，而同图重开零
  载入腿（`historyLoadedURL`/`loadedImageURL` 双守卫）+ process 无 history
  re-sync 源 → 关图后任意首次提交（omp = Film 面板启用）写入 legacy 形
  sidecar + 迁移行可见 + 密度臂渲染。omp 三项物证逐项吻合，omp-01/02
  「图库面 + Film 面板」布局由复现 B 截图逐像素同构佐证。
- **正常用户路径同病判定：同病**（⌘W/返回图库 → 图库态面板启用 = 疾病链；
  omp 挂账问题已回答）。

## T2 修复面（缝位）

- `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift`：closeEditor 删除
  process drop 调用 + 函数本体删除 + `processVersions`/`closeEditor` doc
  注释登记偏离与动机。备选否决（读腿回落 current / commit 时 re-mint /
  close 强制写盘）与安全性审计（老档零误判 / 零新写腿 OQ-5 / sidecar
  schema 零触 / 陈旧条目惰性）= DECISIONS 二。
- 迁移 UX 四面（面板行/确认 sheet/渲染翻面/undo 边界）零触——写腿、
  FilmMigrationAction、FilmPanelView、HistoryStack 全零 diff。

## T3 回归清单

- `testCloseKeepsTheCarrierAndReopensStayIdempotent`（#7 改写）：close 保留
  + 同会话重开读保留值 + 新装配重开文件恢复 + legacy 档跨 close 恒缺席
  （OQ-1 延伸腿）。
- `testEnableAfterCloseWithoutReloadKeepsTheMintedGeneration`（#9 新增，
  M-1 疾病链反转，透过 `FilmPanelModel.enableFilm` 生产缝）：①
  documentProcess == current ②migrationAction == alreadyCurrent（行隐藏）
  ③flush 后 sidecar 同时含 filmRecord + process:2（omp 物证反转）④v1 孪生
  仍 migrate（判别力腿）。
- 定向轮：App bundle **1015/6/0**（650s，peakRSS 1419MB）。
- **ΔN = +1**：任务书带 [+3..+8] 估算的是多腿拆法形态；本批疾病链回归按
  FilmPanelSpectralUITests 端到端先例以单法承载四面断言（+1），#7 改写为
  既有法语义移动（零增量）——越带下缘申报如上，非漏账。

## T4 全套对账（详表 = DECISIONS 五）

`Scripts/test-direct.sh --all` 单轮 **TOTAL 4287/39/0**（4097s；guard
--monitor 21600 伴跑零 RSS-KILL；机器级单重活纪律全程）。对照申报带：

- **4287 = 4286 + ΔN(1)** ✓；
- **39 = 46 − U(7)** ✓——U = 样本供件恢复（orchestrator commit
  `0a21136c`）后首次真实执行的 Fixtures 门法七法（Sessions +5 /
  Layers +1 / Export +1，skip→executed 内部换位），**全数通过零失败**
  （「既有潜在失败」分支空，无需路由）；
- 计数语义勘误：executed 元含 skip（XCTest summary 行口径），故激活法
  表观 pass 持平——对账带意向（分子 +ΔN / 分母 −U）达成，实测形貌
  记 DECISIONS 五；
- 六 bundle 对照 M8-3 三轮：IOP/IOPParity/Library 三者逐值同（IOPParity
  529/11/0 = golden 三件套 + legacy 主门在册全绿）；App +1 = 本批 ΔN。

## 红线机检

- 封存面 15 项 + FIX2③：`git diff c0f1e5a1..HEAD` 逐项零 diff ✓（本批
  产线面 = WorkspaceModel.swift 单文件）。
- 哨兵：filmRampPlaneHash 主门 + 光谱三件套 + 老档零漂移负测 =
  IOPParity 全绿承载 ✓；probe④ 登记面零触。
- sidecar schema（v11）/ HistoryStack / HistoryHash / V50Order /
  GradeCatalog 零 diff ✓；零 sidecar 新键 / 零 UserDefaults 新键 /
  零 xcstrings 触碰 ✓（本批无用户可见新串）。
- 迁移 UX 零回归：runProcessMigration/写腿/evaluate 面零 diff ✓；零自动
  迁移纪律维持（OQ-5——close 保留是「不丢」非新写腿）✓。
- 语义铁律：「新档 = current」由 mint 值真实存活达成，非键缺席裸判；
  老档（legacy 缺席 / v1 stored）判定键不受扰（#7 legacy 腿 + #9 判别腿
  双钉）✓。
- commit 纪律：`fix(m8)` 产线+测试一提、`docs(m8)` 账本一提，零 issue
  ref（内部账本/测试面），只 add 相关文件 ✓；不 push ✓。
- 机器纪律：全程 guard --wait 前置 + 起跑 ps 清零验证（Lightamer/xctest
  = 0）+ 全套伴跑 monitor + 收工 kill ✓；诊断轮自出 GUI 实例 kill -9
  自清（自出 PID）✓。

## 遗留与移交

- **姐妹缺口（M8-3+ 挂账）**：film/DRT/rawOverrides 三载体关图丢弃 ×
  同图重开零载入——已启用胶片的图 close→reopen 后渲染门静默失效至下次
  film commit（面板 history 读腿掩盖观感）；process 修复先例（drop 豁免）
  与 re-sync 腿两案候选，独立批裁决（DECISIONS 1.6）。
- **obs-1（v2 白场幅度）**：本批未触（归走查裁量，原账不变）。
- **omp M-1 复核面移交**：修复后 probe 缝复走（enable 前后 migration 行
  隐藏 + sidecar process:2 落盘）= 验收路输入；accept 面本批不做
  （执行纪律约定）。

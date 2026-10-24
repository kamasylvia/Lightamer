# R13(R4)修复批综合验收(重派轮)

> 2026-10-24。对象 = `d2bcaf06`(流一 Link os_log + 双模回归,fixes #2)/ `b0690452`(流二 F-2
> 全族 46 处显式形,fixes #3)/ `acd3074b`(docs);HEAD = `93a97ed6`(SOP 硬化,验收轮前在位)。
> 前任验收死于 12GB 事件整机重启,报告未落盘;本轮为重派全量重验(非续写)。
> 纪律执行:guard v1.3 `--wait` 三过(heavy=0 free=44/35/59%)+ **v1.4 `--monitor` 伴跑全程**
> (零 RSS-KILL 触发)+ 起跑前 ps 验证 GUI 清零 + nohup + 只杀自出 PID + 主树零改动。
> 证据 = `evidence/acceptance/`(all-r13-acc.log / app-rerun.log / app-hang-run1.log /
> app-host18180-sample.txt / link-regression.log / render-harness.swift / s2.diff / xc.diff)。

## 结论

**PASS / 0 blocking + 0 major + 2 minor + 4 obs。**双流判定均成立,全套数字 4206/41/0 精确
复现,无 blocking 级缺陷。App bundle 宿主在复跑第 1 轮 hang(AI worker 测试族环境敏感,
非本批触及面),杀自出树后单 bundle 重跑绿——如实登记为 obs,不降级结论。

## 一、流一 Link 归因审(清单第 1 项)——「环境型一次性表型」定性成立,附 1 obs

**证据链逐项亲核(全部实测):**
- **代码面无删行路径**:`removeImage(id:)` / `removeImage(_:from:)` 生产调用点 = 0
  (仅 LibraryStore.swift:335/409 定义 + 6 处测试引用);迁移面 additive 不在本批 diff。
- **AI-ask 互斥**:`LibraryProjectController.swift:441`(`outcome.imported > 0` 才填
  `newImageIDs`)+ `:466`(`guard !newImageIDs.isEmpty else { return }`)——omp 报告的
  「AI ask 出现过」与「零行」在代码面确不可同真,推理链成立。
- **omp 原报告**(LUMEN-CULLING-ACCEPTANCE-OMP.md §七 major-1):Link×4 零行、Copy 8/8
  同源、静默表型(无 alert/watchdog/lastError),其自列首要嫌疑 = typed 吞错——与修复
  对象一致。
- **实证双复现**:probe log(`evidence/gui-probe-link-import.log`)8/8 行 + 8/8 loaded/
  rendered;回归双测试本轮**亲跑**(Library bundle `ImportServiceTests` 13/0/0,两新测试
  逐名 passed,`evidence/acceptance/link-regression.log`)。
- **修复落点**:`ImportService.swift` 逐文件 catch 加 os_log error(mode+path+error,
  category `import`,privacy .public)——吞错腿的复发从此必有 Console 痕迹;oslog 语句
  位于 per-file catch 内,`plan.mode`/`item.source.path` 作用域亲证。

**定性审结论:**「环境型一次性」在「未定位根因」意义上是诚实标签(DECISIONS §1 残余不
确定性如实申报,复发路径有书面升级缝),证据链强度足以支撑「不作行为修改 + 观测性补洞 +
回归钉死」的处置。os_log 观测腿**足以兜住吞错腿**的复发检测;但 **guard 腿(§obs-3)
仍无观测**——复发若走 `runImport` 入口静默 return,Core 侧依旧零日志,只能靠「新日志
缺席 + watchdog 行缺席」反向指向。可接受(红线约束下的申报偏差),不阻断。

## 二、流二 F-2 全族抽验(清单第 2 项)——全绿

- **46 处全读**(超 ≥6 抽样要求,逐 hunk):46 处删除行含插值 = **46 精确**;全部为
  格式串带参形(含 4 个双参/三参键:export_targets_header、toast_import_partial、
  tasks_analysis_detail、library_hint_burst_index、skin_toast_yaw、tier_detail),
  **零「有限枚举形」站点**——主张成立(负清单 V14 显式 switch 形于
  LightamerShell:1592 亲证为合法形,未误转)。
- **转换形键值分离 + 键在册**:37 个唯一键(46 处去重)**全部**在 catalog 在册且
  specifier 与值一致(多参键用位置参数 `%1$lld/%2$lld`,arity 匹配);37 键在**预提交
  catalog**(b0690452^)全部已在——**「键值零迁移」亲证**。
- **残留机检**:全仓(App+Core)插值禁形扫 = **0 残留**;余 18 处全为「静态键+拼接」
  合法形(负清单在案:AIMaskEditing/MaskRefineCoordinator/DepthMaskService/
  AIDownloadPrompt/PresetManagerWindow/PresetPanelView/MaskToolbarView 等)。
- **mcp_launcher_launch_failed 真 bug 亲验**(渲染级,`render-harness.swift`):
  旧形 `String(localized: "mcp_launcher_launch_failed \(reason)")` → 运行时键
  `…failed %@` 查表 MISS → **渲染裸键串**(复现 bug);新形指向裸键(值 = 「启动失败：%@」)
  → 渲染 `Launch failed: port 8765 in use`。**转换前后行为差实锤**,r12「零运行时裸键」
  对该键的误判(DECISIONS §4)定性正确。
- **xcstrings 三孤儿删除亲核**:diff = 51 行纯删除、三个整块(edr_headroom_label /
  settings_displays_overridden / softproof_active_label);六值(en+zh×3)与 `%@` 孪生
  **逐字节相等**(脚本断言 bv==tv 全 True);键数 2038→2035(Δ=3),其余 2032 键零触碰;
  三裸键当前 `False in keys`、孪生 `%@` 键在位。

## 三、全套独立复跑(清单第 3 项)——4206/41/0 精确复现,附 App hang obs

第 1 轮(--all,guard 门 + monitor 伴跑,15:37 起)六 bundle 全绿后 **App 宿主 hang**:
`AIWorkerClientTests.testTimeoutKillFoldsToWorkerCrashedAndRespawns` 起跑后 ≥8 分钟
零日志增长;`sample` 实锤卡点 = `AIWorkerClient.killChild`(AIWorkerClient.swift:569)
SIGKILL 后 `waitUntilExit()` 永久阻塞 mach_msg,3 个 `--ai-worker` 子进程在场。杀自出树
(suite/host/workers,§8 自出 PID)后**单 bundle 重跑** = **1007/6/0 · 453s 绿**(卡点
测试本轮通过)。合并向量:

| bundle | 本轮(run1 / App=重跑) | executor 申报 all-r1 | 判定 |
|---|---|---|---|
| IOP | 771/5/0 · 5808MB | 771/5/0 · 4777MB | ✓ 计数逐值中 |
| IOPParity | 478/6/0 · 5425MB | 478/6/0 · 3338MB | ✓ |
| Layers | 502/6/0 · 679MB | 502/6/0 · 802MB | ✓ |
| Library | **778**/4/0 · 774MB | 778/4/0 · 980MB | ✓(+2 = r13 新测试,lumen 基线 776) |
| Sessions | 285/9/0 · 1105MB | 285/9/0 · 1168MB | ✓ |
| Export | 385/5/0 · 4655MB | 385/5/0 · 3707MB | ✓ |
| App | 1007/6/0 · 1243MB(453s 重跑) | 1007/6/0 · 2581MB | ✓ |
| **TOTAL** | **4206/41/0** | 4206/41/0 · 2226s | ✓ 精确 |

- 对账:基线 4204/41/0(88bdb9fb 收口轮,LUMEN-BC-ACCEPTANCE §四亲证)+ ΔN **2**
  (Library +2)= **4206 精确**;skip 向量 5+6+6+4+9+5+6 = 41 逐值一致;峰值 RSS 全在
  8G 门内,零 MEMFAIL,monitor 零 RSS-KILL。

## 四、回归面(清单第 4 项)——全绿

- **FIX2③**:`git diff 88bdb9fb..HEAD -- LibraryProjectController.swift` = 空(零 diff);
  `runImport` guard(:404-405,静默 `else { return }`)原样在位,未观测化(申报偏差
  DECISIONS §2 一致)。
- **封存面**:`git diff 88bdb9fb..HEAD` 对 16 个封存面名(DrtRecord/TerminalTailPolicy/
  DrtTailAssembly/PixelPipe/Lut3dKernels.metal/DrtEotf/ExportQueueContract/
  ExportFormatSpec/ImageIOEncoders/WebPEncoder/NodeGraphCommand/HistoryStack/
  HistoryHash/PipelineDocument/V50Order/NodeOwnershipCatalog)glob = **零命中**。
- **zh-audit 双 PASS 复跑**:`--check` PASS(1720 source / 2035 catalog / 10 interp keys
  variant-PRESENT + spec-matched,specifier 深检零失配——与申报逐字同值);`--self-test`
  PASS(V17 golden 八例)。
- **E 族显式形等价性抽验 3 处**(bundle 级渲染 harness,新旧形同 key 同参对渲染):
  `filter_chip_rating`(Rating ≥ 4)/ `focus_stack_dialog_title`(Focus-stack 3 sources)/
  `settings_lcr_size_mb`(88 MB)——**三处逐字节相等**(EQUIV-OK ×3);另 4 键多参替换
  正确(skin_toast_yaw/export_targets_header/toast_import_partial/tier_detail)。
  harness locale = en(zh 强制本 OS 未生效,同 executor §5 申报;zh 侧由目录 dump
  字节级核验背书)。

## 五、GitHub issues #2/#3(清单第 5 项)——一致

- #2(Link 导入零行):标题/body 与实际处置一致(不可复现结论、双实证、os_log 修复、
  +2 回归、AI-tail 前置链);`d2bcaf06` message 末 `fixes #2` 预埋。
- #3(F-2 家族转换):标题「46 sites」与实际一致;body 的 mcp bug 叙述、三孤儿删除、
  zh-audit 双 PASS 均与实物相符;`b0690452` 末 `fixes #3` 预埋。
- 两 commits 当前**本地未推**(origin/main behind 537,推送为编排事件)——issues OPEN
  态正确,关闭动作随 push 到默认分支触发,机制无偏差。

## 六、分级清单

**minor(2):**
1. **台账「21 文件」口径失准**:`b0690452` 实触 **18 个 Swift 文件**(+xcstrings=19),
   SUMMARY/DECISIONS 写「46 处 / 21 文件」。46 处精确;21 ≈ r12 花名册「16 文件」+ 5 个
   新文件的事前并集,非实际 diff 文件数(r12 花名册自身「16 文件」对 14 个列名亦有内差)。
   修复 = 随下批 docs 批把「21」勘误为「18」(行为零影响)。
2. **流一 guard 腿观测缺口维持开放**(承接 DECISIONS §2 申报):`runImport` 入口静默
   return 路径在 FIX2③ 冻结下无日志;若复发走此腿,仍是零诊断通道。非本批能解
   (须显式解冻),登记为已知敞口,升级缝书面在案。

**obs(4):**
1. **App bundle AI-worker 测试族环境敏感(三态:绿/崩/hang)**:同一 HEAD 三轮全套,
   executor 433s 绿 → 前任宿主异常退出(exit=143)→ 本轮 hang(`killChild` 的
   `waitUntilExit()` 死等,sample 在案)。R13 对 AIWorker* 零 diff(机检 0 文件),
   非回归;重跑即绿。建议:给 `testTimeoutKillFoldsToWorkerCrashedAndRespawns` 类
   NSFoundationTask waitUntilExit 路径加有界等待(後续批),并纳入 MEMFAIL 之外的
   「App 宿主超时」机检话题。
2. **前任验收轮残留实证**:`all-runs/acc-r13-all.log` = 前任全套第 1 轮,App 宿主异常
   退出被 parse 判 crash(L055 机制正常工作,计数置零),TOTAL|3199/35/0| 不可信行已在
   案;其死因(12GB 进程)与本轮 hang 非同机制(本轮峰值 1.6GB,monitor 在位无 RSS 风险)。
   文件保留作历史证据,不删。
3. **流一归因的两读张力**:omp 报告将 guard 列入「已排除」(importProgress==nil 串行
   单跑),DECISIONS §1.4-a 又将其列为残余嫌疑 a(「无 watchdog 日志与此吻合」)。两者
   对 omp 会话内 guard 状态的判定相反,真值不可考(omp 会话不复存在);不影响「环境型」
   定性(两条残余嫌疑均已如实登记),登记备查。
4. **渲染抽验通道**:验收采用 bundle 级渲染 harness(与产线同形
   `String(format: String(localized:bundle:))`)+ en 表读数;zh 渲染面由目录字节级
   dump + zh-audit zh-completeness 双背书,与 executor §5 降级申报同口径(2 处 GUI zh
   实读 + 8 键 bundle 机读 → 本轮 3+4 键 bundle 机读,覆盖 ≥3 键要求)。

## 七、验收清单对照

| # | 清单项 | 结果 |
|---|---|---|
| 1 | 流一 Link 归因审 + 回归双测试亲跑 | ✓(§一;13/0/0 含两新测试逐名 passed) |
| 2 | F-2 抽验(≥6×2 / mcp 亲验 / xcstrings 亲核) | ✓(§二;46 处全读超抽样,37 键全验) |
| 3 | 全套独立复跑 + 向量对照 | ✓(§三;4206/41/0 精确;App hang→单 bundle 重跑绿) |
| 4 | 回归面(FIX2③/封存/zh-audit/等价性) | ✓(§四;零 diff + 双 PASS + 等价 3 处) |
| 5 | issues #2/#3 一致性 | ✓(§五) |

## 八、还原与卫生

- 主树 tracked 零 diff(`git status --porcelain` 仅 .work 产物与既有 untracked)。
- 进程终态:Lightamer/xctest/test-direct/machine-guard 全清零(两 monitor 随轮停止)。
- /tmp/r13-acc 工作副本保留 harness 与采样,证据正本已入 `evidence/acceptance/`。
- 本文件不入 git(验收轮产物,待 orchestrator 决定随批或留档)。

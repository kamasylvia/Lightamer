# LUMEN-A-ACCEPTANCE-2ND — plan A(LUMEN-A)第二路独立验收·补验轮

> 验收轮:2026-10-24 00:20–01:50,验收人 = zcode 独立验收 lane 2(补验轮)。
> 对象 = 一路 major-1 聚焦修复 `dcc1c030`+`c7bc2b9b` 本体 + 一路 4 minors 复核 + 全套独立复跑。
> 零源码改动;主树 HEAD `c7bc2b9b` 全程只读(git status 亲证;报告与 evidence 落 .work 不 commit)。

## PASS / 0 blocking + 0 major + 4 minor + 9 obs

**判定:PASS(修复闭环确认,LUMEN-B 可起跑)**。major-1 徽章事件链修复三缝语义攻击全过:
单一 actor 实例端到端成立、产线 setAnalysis 写点恰一、身份钉测试亲跑绿、修复前红证
复核实锤、nil=inert 与 reopen 路真机双轮亲证(徽章 live 渲染 + 跨重启初始 reload 渲染)。
全套独立复跑 **TOTAL|4144/40/0|** 与对账向量逐位命中(4112 基线 + Library +28〔含 fix +1〕
+ App +4),七 bundle 零 fail 零 MEMFAIL。一路 4 minors 全数复核确认、原样携带,无新增
blocking/major。**对账口径勘误(记 obs-8/9)**:派单申报「主树 HEAD = 2b2246cb」实为链基
(ancestor),真实 HEAD = `c7bc2b9b` = 修复批 tip = 验收对象本体,状态正确;申报
「TOTAL|4112/40/0|」为 r12 基线简写,批后真值 = 4144(数学见 §四),逐位对账无分歧。

---

## 一、badge 修复语义攻击(验收清单第 1 项,最高优先)——全过

**三缝亲读(现场态源码,非仅 diff)**:

| 缝 | 位置 | 亲读判定 |
|---|---|---|
| ① service 注入 | `LibraryAnalysisService.init` 增 `libraryStore: LibraryStore? = nil`,`self.libraryStore = libraryStore ?? LibraryStore(store: store)`;`persistAndTick` 改 `try? await libraryStore.setAnalysis(product)`(`:288`) | ✅ 每行新建形态根除。**自建兜底语义正确**:nil = 每 SERVICE 一份(非每行一份),headless/test 面事件链同样自洽;`public private(set)` 防外改 |
| ② wiring 转经 | `LibraryAnalysisWiring.analysisEvents()` = `guard let service else { return nil }; return await service.libraryStore.analysisEvents()`;装配点 `libraryStore: LibraryStore(store: store)` 建一份注入(`:137`) | ✅ 消费方订阅的 THE SAME actor 实例 = persist hop yield 进的表。wiring 的 `projectStore(for:)` guard 保证与 projectController 共享同一 ProjectFileStore(写腿与读腿同源) |
| ③ 视图订阅 | `WorkspaceHostView` badge 循环删 ad-hoc `LibraryStore(store:)`,改 `guard let events = await wiring.analysisEvents() else { return }; for await _ in events { await reloadCullingBadges(queries) }` | ✅ onTermination → `removeAnalysisContinuation`(`LibraryStore.swift:1296-1300`)——task 取消/项目切换续表清理,无 zombie continuation 泄漏 |

**产线写点全量 grep**:`.setAnalysis(` 全仓恰一(`LibraryAnalysisService.swift:288`,注入
实例);其余 `LibraryStore(store:)` 散建点(AIAnalysisRegistry/EditorWorkspaceShellView/
SearchStateToolset/ImportService/WorkspaceHostView 其余三处)零 setAnalysis 调用——**无第二
破链点**。

**身份钉测试亲跑**:`testAnalysisEventReachesSubscriberThroughWalkPersist` 独立复跑
**PASS(0.282s,套件 5/0/0)**;`===` 身份断言在案(注入实例 vs `service.libraryStore`,
per-row 新建形态先死在钉上);事件到达断言(`received.value`)+ 产物落库断言双实。日志 =
`evidence/lumena/acceptance2/acc2-idpin-detail.log`。

**修复前红证复核**:`fix-red-run.log`(2026-10-23 23:40,先于 fix commit 00:08)——
同测试**红在事件到达断言(`:250`,"the analysis event must reach the subscriber's store
instance"),5/0/1**;行已 stamp 前置过 = §八「数据在、事件丢」表型精确复现。红轮形态
(无注入参数)下身份钉尚不存在、钉属修复后守卫属性——红/绿时序与断言位置自洽,非事后
补造。

**nil = 分析面 inert 边界**:①无项目启动 = 欢迎面(「尚未打开项目。」),零 crash 零
泄漏(wheel 1 首启亲测);②gate off / teardown → service nil → `analysisEvents()` nil →
badge 循环 `guard let events else { return }` 干净退出,初始 reload 独立成立;③wiring
`?? LibraryProjectController()` 兜底 = 生产死代码(生产路径 `libraryProjects` 为
LightamerShell `let` 非可空、同实例贯穿,陈旧 wiring 攻不可达)。

**首刷顺序覆盖亲证(§11 声明的语义攻击)**:`service.start()` = spawn 即返
(`Task(priority: .utility)`,不 await walk)→ 时序 = projectChanged(起趟)→ 首刷
reloadCullingBadges → 订阅。[**起趟, 首刷**] 窗内落库行由首刷覆盖 ✅(声明成立);[
**首刷, 订阅**] 微窗(两次 actor 跳,µs–ms 级)yield 无 continuation = 事件丢 → 见
obs-6(理论缺口,自愈性覆盖)。GUI wheel 1 live 路实证整链。

## 二、真机行为复验(验收清单第 3 项;AX 驱动 + 定窗截屏,证据 =
`evidence/lumena/acceptance2/`)

自建 BADGECHK2 工程(修复轮 createproj 同款:ProjectFileStore+LibrarySchema+SQLiteHandle+
SingleWriterLock+LibraryError 自洽闭包裸 SQL 插行;fixture = 3 棋盘连拍相邻 ts + 1 棋盘
独立 + 2 纯色,同机三元组 AccCam/AccOne/SER-Y;`PRAGMA user_version`=6 + 七列 presence
建库即验):

- ✅ **wheel 1(live)**:无项目首启(nil=inert 面)→ AX 开项目 → 分析趟完成 →
  **同会话徽章渲染**:「连拍 1/3 ★」「连拍 2/3」「连拍 3/3」+「可能模糊」×2 + 独立
  清晰行零徽章(`acc2-grid-mid.png`/`acc2-taskbar.png`)。**二进制含修复由此实证**
  (pre-fix 形态 live 徽章恒不出 = 一路 §八表型)。SQL 核:6 行 `analysis_version=1`,
  sharpness 95.068(棋盘)/0.0(纯色,strong-empty 谱系),signature 256B,serial
  COALESCE 保 SER-Y——与一路 §七及修复轮 §11 数值逐位同谱系。
- ✅ **wheel 2(reopen = 一路 §八断点二余量)**:⌘Q → 重启 → 重开同项目 → 徽章自
  **初始 reload 独立渲染**(该轮零事件:行已 stamp,walk no-op)——`acc2-reopen-mid.png`。
  断点二实证关闭;§11 归因(「live 与 reopen 同用一条 reload 缝」)成立。
- ✅ **智能相册四案真机**(ACCTEST 前缀 JSON 注入 `~/Library/Application
  Support/Lightamer/SmartAlbums/`,验后删除还原):sharpness≥50 → 计数 4,点击应用网格
  「共 4 张照片」+ 连拍×3 保留(两轮复现);faces eq 0 → 计数 6,单击应用「共 6 张」
  chips=1;eyesClosed eq 0 → 计数 6,单击应用「共 6 张」chips=1;hasBurst eq 1 →
  **列表计数缺席 + 单击 typed 拒**(evaluate 抛 `cullingFieldNotSQLQueryable` →
  `smartAlbumsUnavailable=true` → 无臂、无 crash、网格不动)——m-11 designed 降级面,
  非缺陷;UI 粗糙度见 obs-7。SQL 直比/NULL 语义由 FilterCullingFieldsTests 集成面覆盖
  (全套 Library 775 绿背书)。
- ✅ **Settings 行**:默认行为 → 「照片分析」节 + 「后台分析照片」toggle(默认 ON,
  AX value=1)+ 说明文案(「…空闲时为图库计算清晰度、闭眼与连拍提示。导出与 AI 任务
  始终优先。」)渲染可达(`acc2-settings-toggle.png`)。

## 三、一路 4 minors 复核(验收清单第 2 项)——全数确认,原样携带

- **minor-1(SubSec ÷1000)**:现状 `ExifSearchIndexer.swift:183`
  `subsecMilliseconds / 1000.0` 硬编码三位数假设;变量名 `subsecMilliseconds` 同铸假设。
  SDK 头(`CGImageProperties.h:566-576`)仅「The fraction of seconds」**不定位数**;EXIF
  规范 = 任意位小数串。**失败谱系比一路表述更锐**:3 位(实践相机主流)正确;2 位
  「25」=0.25s → /1000 = 0.025s(10x 错);6 位微秒形「250000」=0.25s → /1000 =
  **+250s 偏移**(爆炸性)。影响面 = capture_date 亚秒精度 + 连拍副本排除 ±1e-3 判定。
  建议:按 `pow(10, -(digits))` 缩放或按位数控幅。
- **minor-2(hasBurst 死拼写)**:`FilterSQL.swift:545` `case .hasBurst: "burst_annotated"`
  原样;`:273` guard 先决永不可达。防御值建议改 typed throw,维持。
- **minor-3(MainActor 全量重算)**:`reloadCullingBadges` 在 View(MainActor),每事件
  全表 `burstRows()` + 同步 annotate O(n)——万张库首扫 O(n²) 主线程面,原样。修复轮
  零触碰(与 §五面复核一致)。
- **minor-4(任务条不回收)**:teardown 才 `registry.finish`;walk 自然完成无回收缝。
  **本轮视觉坐实**:wheel 1 截图中徽章已渲染(=趟毕)而左下「照片分析」条仍在屏
  (`acc2-taskbar.png`)。Plan B 任务面打磨项,维持。

## 四、全套独立复跑(验收清单第 4 项)——逐位命中

guard PASS 后锁 + `nohup caffeinate -dis Scripts/test-direct.sh --all`(PID 41191,
2254s,全程监视;消费修复轮 23:43 build-for-testing 容器——GUI live 徽章实证二进制含
修复,未重建):

| bundle | 二路实测 | R3 基线(4112) | 判定 |
|---|---|---|---|
| IOP | 753/5/0 · 5577MB · 454s | 753/5/0 | ✓ 逐值 |
| IOPParity | 478/6/0 · 4334MB · 741s | 478/6/0 | ✓ 逐值 |
| Layers | 494/5/0 · 817MB · 147s | 494/5/0 | ✓ 逐值 |
| **Library** | **775/4/0** · 749MB · 173s | 747/4/0 | ✓ = 747+27(A)+1(fix);申报 775 命中 |
| Sessions | 285/9/0 · 1053MB · 70s | 285/9/0 | ✓ 逐值 |
| Export | 385/5/0 · 3473MB · 212s | 385/5/0 | ✓ 逐值 |
| **App** | **974/6/0** · 2776MB · 457s | 970/6/0 | ✓ = 970+4(A);申报 974 命中 |
| **TOTAL** | **4144/40/0** | 4112/40/0 | ✓ = 4112+28+4 逐位对账;skip 40 恒等(Library skip 4 不变) |

零 fail 零 MEMFAIL(峰 IOP 5577MB,8G 门内);日志 =
`evidence/lumena/acceptance2/acc2-all.log`。**对账**:plan 评审带 A 终态 4124..4127
(+12..15 预算)——实测 4144 越带(+32 总账),越带甄别一路 §三已全清(31 法全深读,
SC 子句/评审强制全可溯,无虚胖)+ fix +1;本轮按 per-bundle 向量与「Library 775/App 974
新基线」申报逐位复核,账实一致。

## 五、回归面(验收清单第 5 项)——全过

- **schema v6 迁移回归**:V6Tests 三法(fresh 36-pin / 真 v5 fixture migrate 零漂移+
  快照 / 幂等+半程)在 Library 775 内全绿;另以自建工具独立验证 fresh-create v6
  (user_version=6 + 七列 presence)真机开库跑通分析趟(§二)。
- **FIX2③**:McpServerController 零 diff(`dcc1c030^..dcc1c030` MCP 域 0 行)。
- **封存面**:修复批全 diff = 5 文件(4 代码 + 1 DECISIONS,`git diff e853cacf..HEAD
  --stat` 亲证);Sidecar 域/PixelPipe/Lut3dKernels.metal/DrtRecord/TerminalTailPolicy/
  ExportQueueContract/StackClustering 逐 pathspec diff 零行;CullingToolset/近亲零触。
  修复改动面 = 申报四文件,无越界。
- **zh-audit 双 PASS**:`--check` PASS(1697 source / 2016 catalog / 41 interp,与一路
  同值)+ `--self-test` PASS(V17 golden 八例)。
- **L013/UserDefaults**:修复批零新增 defaults 键(`library.analysis.enabled` 域内缺席
  = 默认 ON 原态保持;recentProjects 验后还原,见 §七)。

## 六、obs 清单(本轮新增 + 携带)

- **obs-6(新)**:[首刷, 订阅] 微窗事件丢失——AsyncStream 无预挂 continuation 时
  yield 即弃;窗宽 = SELECT+订阅两次 actor 跳(µs–ms),首行分析落库时长大数个量级,
  实践不可达;且任一后续事件的全量 reload 自愈。修复 commit 注释「covers the window
  between walk start and subscription」对 [首刷,订阅) 段略有夸大——不构成缺陷,登记
  备 Plan B 打磨(如订阅先行或尾刷一遍)。
- **obs-7(新)**:智能相册 hasBurst 单击的 typed 拒走 `smartAlbumsUnavailable=true`
  全节隐藏(任一相册 evaluate 错误即隐整列,下次成功 toggle 恢复)——安全(无 crash/
  无数据风险/无臂污染)但 UX 粗糙;Plan B 相册面顺路评估「单相册降级不隐全节」。
- **obs-8(新,口径勘误)**:派单申报「主树 HEAD = 2b2246cb」= 链基(ancestor,7 commits
  之前);真实 HEAD = `c7bc2b9b` = 修复批 tip——正是验收对象,状态正确非漂移。
- **obs-9(新,口径勘误)**:派单申报「TOTAL|4112/40/0|」为 r12 基线简写;批后真值 =
  **4144**(4112+28+4,逐位对账见 §四)。二路实测与数学期望一致,无分歧。
- **obs-10(新,知会)**:验收期间 `library.recentProjects` 出现非本验收来源的混染写入
  (Widget.lalb×2,ro-face 测试 fixture 路径;用户会话活跃窗口内他方写入)——已按修复
  轮 §11 正本还原 ACCPROJ×3;提请 orchestrator 知会(并行会话同域 defaults 写入互踩
  风险)。
- 携带(一路,复核后维持):obs-1(SUMMARY 构成账 30 vs 31 stale)/obs-2(常量复读
  哨兵)/obs-3(sharpness 单案集成)/obs-4(TIFF SubSec dump 即弃)/obs-5(`ANAYLSIS`
  注释拼写)/一行注记:rowGroups Swift 非稳定排序(obs-6 一路编号)/issue ref 缺席备案。
  (编号自本轮起顺延,一路原 obs-1..7 不改写。)

## 七、还原确认

- 主树零改动:HEAD `c7bc2b9b` 不动;生产路径 git status 空(仅既有 .work untracked);
  本报告 + evidence 落 .work 不 commit。
- 进程零残留:app 已退;caffeinate/test-direct 自出进程清零(pgrep 复核)。
- 产物清理:`/tmp/lumena-acc2/`(fixture 工程 + 截图已归档 evidence)删除;
  `/tmp/lumena2-*.log` 移交 evidence 后删除;SmartAlbums 目录 ACCTEST 四 JSON 删除
  (还原为用户原单一 UUID.json);`library.recentProjects` 还原 ACCPROJ×3;
  `library.analysis.enabled` 键保持缺席原态。
- 机器纪律:全程 machine-guard 前置(两次 PASS);GUI 轮与测试轮严格串行;零 kill
  他方进程(§8)。

## 八、分歧清单(vs 一路)

| 项 | 一路 | 二路 | 判定 |
|---|---|---|---|
| major-1 徽章事件链 | 断裂(代码+GUI 双坐实) | 修复闭环:三缝语义攻击过 + 身份钉亲跑绿 + 红证实锤 + live/reopen 双轮真机渲染 | **关闭**(dcc1c030+c7bc2b9b) |
| 断点二(reopen 不出) | 疑似第二未定位环节 | §11 归因成立:同断点一覆盖;wheel 2 实证初始 reload 独立渲染 | **关闭**(无需独立改动) |
| minor-1..4 | 在案 | 全数确认现状,原样携带;minor-1 失败谱系锐化(+250s 级) | 维持 |
| 全套数字 | 未跑(批准制) | 4144/40/0 逐位命中对账向量 | 补齐闭环 |
| App bundle | fix 轮未跑(编译由 build-for-testing 验证) | 974/6/0 全绿(含 WorkspaceHostView/Wiring 改动编译+装配测试) | 补齐闭环 |

**结论**:修复本体质量成立(单一 actor 端到端,无过度设计,测试守卫到位),一路 7 obs
无翻案,新增 5 obs 全部为口径/打磨级。LUMEN-A 执行+验收双路闭环,**LUMEN-B 可起跑**。

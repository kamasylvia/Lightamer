# M7-3-01 SUMMARY — MCP O2 反馈回路 + O3 项目与版本(执行批)

> 执行窗:2026-10-17 夜间批(夜间全自动授权先例 D-07-3-T5-1;晨审可推翻)。
> Plan 正本 = `M7-3-01-PLAN.md`(修订版,CHECKER 放行);裁定正本 =
> `M7-3-CONTEXT.md`(D-M7-3-1..10)。执行 HEAD 起点 `2e530f8e`,基线
> **3877/35/0**。**ACCEPTANCE 不写**(orchestrator 派验收 subagent)。

## 总账

- **执行链**:`c6019122`(T1 顺路件六项)→ `cf49c046`(T2 pristineOnly+region)
  → `3ef68910`(T3 compare 双臂+list_luts+xcstrings)→ `bb6026f1`(T4
  ProjectToolset+运行时缝)→ `286530d2`(T5 测试批 union 23→27+四域 golden)
  → T6 docs commit(本批收尾)。
- **全套 `--all` 终值 = `TOTAL|3905/35/0|` exit 0 / 0 MEMFAIL**(3877+ΔN 28
  对账精确闭合;七 bundle 8G 门内:峰 IOPParity 7786MB;IOP 687/5/0〔7538MB〕
  / IOPParity 460/3/0〔7786MB〕/ Layers 494/5/0〔808MB〕/ Library 731/4/0
  〔622MB〕/ Sessions 284/9/0〔1628MB〕/ Export 381/5/0〔6337MB〕/ App
  868/4/0〔2832MB〕)。**skip 35 = 基线零漂移**(构成 = 既有 env 门:
  LIGHTAMER_PERF_PROBE / LA_QL_PERF 门探针族 + RAW fixture 缺失 skip,零静默
  吸收——Export 五 skip 逐条点名 = Mertens probe / Pano probe ×2 / QL perf /
  Yiyin RAW fixture 缺失)。
- **ΔN = +28 逐任务记账**(预估带 +12..20,**越上沿 +8——如实申报**):
  | 任务 | 新测试 | bundle | ΔN |
  |---|---|---|---|
  | T1 | F-AC-1 两法(FilterSQL library 域快照 + keywords eq 臂)+ F-AC-2 真值断言法 + N2-3 nil 载体负测法 + N2-4 requestFailed 臂〔嵌既有法零新法〕 | Library +2 / App +2 | +4 |
  | T2 | pristineOnly 恒等负测两法 | Export +2 | +2 |
  | T5 | McpProjectToolsetTests 17 法 + McpEditingToolsetTests additive 5 法(region golden/region rejections/compare 双臂/region 双臂/list_luts golden) | App +22 | +22 |
  | 合计 | | | **+28** |
- 三验收形态(ROADMAP §M7-3):①compare/region golden ✓(T5 McpEditingToolsetTests
  四法,含 M2 两边界腿 x+w==1.0 精确 + 亚像素 invalidParams 携归一化值)
  ②project 工具与单写者锁仲裁 fixture ✓(McpProjectToolsetTests in-process 双
  store flock 形:held→typed projectReadOnly 携真 pid/释放自然恢复/自持切换
  checkpoint 腿/H2 锚随盒腿/M1 http 不 arm 腿/GUI 差分谓词两腿〔stub face〕)
  ③快照族零意外 diff ✓(union 27 全点位显式改 + editing 层两层同批 + union 外
  五计数钉显式改 + 残漏 grep 零命中 + culling/searchstate 工具面零 diff)。

## 逐任务速览

- **T1(c6019122)**:F-AC-1 = `testLibraryDomainSnapshots()`(六断言钉现字节:
  `+i.` 前缀 + `(1=1)` baseline + 四子句物化列形)+ `testLibraryKeywordsExactSnapshot()`
  第二法;F-AC-2 = `makeHeadlessSearchState` 加 `projectWriteProbe` 默认参 +
  :374 传既有 probe + get_state.control.lock 双臂真值断言;N2-1 = pristine
  payload 12→13 键(truncated:false)+ golden 断言同 commit;N2-3 = fulltext
  闭包 typed `notSessionMember` 抛 + nil 载体负测(直调 closure);N2-4 =
  requestFailed 臂(F-3 四案闭合);⑥ = DECISIONS 承接句。定向 Library
  731/4/0 + App 846/4/0。
- **T2(cf49c046)**:Core 唯一新触点 = `renderedPlane` 签名尾部 `pristineOnly:
  Bool = false` + :236 条件化(恰两处,grep token 计 2);两负测 = 缺省 ≡ 显式
  false byte-equal + true ≡ 无 sidecar 副本缺省渲染 byte-equal(EXPORT 定向绿
  381/5/0)。region = 归一化 0..1 {x,y,w,h} schema + decode/校验(w≤0∨h≤0 →
  invalidParams;越界 → roiOutOfBounds 既有码)+ round+clamp 裁剪 + 交后零面积
  invalidParams 携归一化值。全消费方 9 调用点/5 文件零 diff(git diff 面核)。
- **T3(3ef68910)**:compare enum none|root 默认 root;双臂 = 同一 boundedWait
  30s 单窗两遍 renderedPlane(pristine 臂 pristineOnly:true,不共享 decode);
  内容序 [current, root, text] + summary JSON;compare:none = 旧行为逐字节;
  list_luts 注册 editing 域(readOnlyHint + McpTimeouts.list 包裹 +
  LutLibraryStore.shared 直读 + description lutName 寻址键句;libraryGroups
  零命中);xcstrings = render_preview 原位值改(en defaultValue + zh 同批)+
  list_luts 尾块纯插入。
- **T4(bb6026f1)**:ProjectToolset.swift 新建(McpProjectContext 全 provider
  optional + ProjectOpenOutcome 四字段无 photo_count + name=url stem 派生 +
  三工具:open/create requiresWriter:true 先检后开/list_versions 只读
  sidecar 单源 version-reference 投影零命中 includeItems historyItemCap 500
  保新端);makeRegistry 第四参缺省 nil;四宿主缝 + EmbeddedState.project 第五缝;
  current-project 盒(锁保护 store/url/readOnly 三元)替换启动捕获静态载体
  ——liveState per-call 盒读(盒空 = bare-context null 面逐字节)+ **:194
  library projectDirectory 锚改盒读**(H2);no-project stdio/http 双臂换盒读
  closure 形(裸 `McpSearchStateContext()` controller 内零命中);生产调用点
  五处全传 project provider;EOF watcher 抽取 `armStdioEOFReleaseOnce(mode:)`
  (once guard + mode==.stdio 内部自守卫;恰两调用点 = 启动 + parkRuntimeStore);
  GUI 臂 = library/sessionPair 闭包变量提共享 + held 目标 probeLockAvailable
  预检 + before/after pendingConflict 差分;**controller 文件零 diff**;
  McpToolRegistry.swift 零 diff(错误码零新增);xcstrings 三新键尾块。
- **T5(286530d2)**:union 23→27 全点位显式改(计数 ×4:assertSnapshot 计数/
  :274 白名单 27/:421 SC7 directTools/组合代数 :246;descriptionKeys +4;
  makeUnionRegistry + SC7 传 project fixture;F-AC-4 :210 非易碎形;all23→all27;
  测试名 Union23→Union27;头注/message 同批)+ editing 层两层同批(render_preview
  行 + list_luts 行 + :194 计数钉 20→21)+ union 外五钉(McpHostTests :243/:696
  + McpLauncherTests :200 + McpSearchStateToolsetTests :270,20→21 message 同批)
  + McpProjectToolsetTests 新文件 17 法 + McpEditingToolsetTests additive 5 法
  + Project.swift 恰一行 + BUNDLE-MAP 恰一行 + tuist generate 恒末位。
  **App 868/4/0 全绿(红窗 T2..T5 闭合)**。

## 中间红窗处置

T2 起 render_preview schema 字节变 → union/editing 两层快照红至 T5;每任务
gate = 构建绿 + 非 App 定向绿(T1 双域/T2 EXPORT/T3-T4 构建+grep),T2-T4
零快照改动(禁提前改快照纪律兑现),T5 一批显式改收口,App bundle 红窗闭合
868/4/0。T6 三域定向轮绿 + 全套对账闭合。

## 三验收形态判定指针

1. compare/region golden → `McpEditingToolsetTests.swift`
   testRenderPreviewRegionGoldenPixelFrame / testRenderPreviewRegionRejections /
   testRenderPreviewCompareRootDualArm / testRenderPreviewRegionAppliesToBothArms。
2. 锁仲裁 fixture → `McpProjectToolsetTests.swift` testHeldTargetIsTypedProjectReadOnly
   / testReleaseThenOpenRecovers / testSelfSwitchClosesThenOpensWithAnchorFollowing /
   testCreateRefusalsAreTypedInvalidParams / testProjectAnnotationsWriterGateExecutable /
   testHttpModeRuntimeOpenArmsNothing / testGuiProvider 两腿。
3. 快照族零意外 diff → `McpFinalSnapshotTests.swift`(27 verbatim)+
   残漏 grep(`count, 20` / `count == 20` / `all23` MCP 测试面零命中;
   McpLauncherSentinelTests 2000-buffer 与 SidecarV10「11 reads」注释为
   checker 清白旁证非工具计数)。

## 红线族机检(T6,全部 PASS)

零新 SPM(Project.swift dependencies 零 diff)/ `.metal` 全域零 diff /
McpToolRegistry.swift 零 diff(封闭表 + McpTimeouts)/ controller 文件零 diff /
封存面零触(vs 基线 217999a5 产线触面恰六申报文件:EditingToolset /
McpServerController / ProjectToolset 新建 / SearchStateToolset / LightamerApp /
QuickLookRenderer)/ xcstrings 累计 = 恰 1 删除行(render_preview 原位改)+
4 新键尾块 / UserDefaults 零新键 / runModal 零命中 / LocalizationValue 插值
禁形零命中(:2294 命中为 M3-1 既有文档注释 describing 反模式,非本批 diff)/
V50Order/GradeCatalog 零触 / Project.swift 恰一行 + BUNDLE-MAP 恰一行 /
zh-audit `--check` PASS(1695 source keys)+ `--self-test` PASS。

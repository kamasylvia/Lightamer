# M7-3-01 ACCEPTANCE — 第一路独立验收（subagent，2026-10-17 夜间批）

> **结论头:PASS / 0 error + 3 minor（S1/O1/O2,均为非阻断独立发现——S1 为
> 先前 M6-1 潜伏缺陷,本波红线内忠实保留,不属本 plan 违例）。**
> 验收方式 = 不轻信执行方报告,逐条实测:全套独立复跑 + 三判据亲跑 +
> 真端到端抽测 + 红线族全亲跑。执行链 `c6019122..7694e7b1`(6 commits),
> 基线 `217999a5`。

## 一、全套独立复跑(本验收自起,非转抄)

`caffeinate -dis Scripts/test-direct.sh --all`(04:25 起,2044s,exit 0):

```
BUNDLE|IOP|687/5/0|peakRSS=7594MB
BUNDLE|IOPParity|460/3/0|peakRSS=6986MB
BUNDLE|Layers|494/5/0|peakRSS=807MB
BUNDLE|Library|731/4/0|peakRSS=623MB
BUNDLE|Sessions|284/9/0|peakRSS=1626MB
BUNDLE|Export|381/5/0|peakRSS=6094MB
BUNDLE|App|868/4/0|peakRSS=2832MB
TOTAL|3905/35/0|2044s
```

- **对账闭合**:3877+ΔN 28 = 3905;skip 5+3+5+4+9+5+4 = 35;七 bundle
  逐 bundle 与执行者申报同值;峰 RSS 全 <8G 门(最大 7594MB),0 MEMFAIL。
- **L055 机检**:七 bundle 日志 `terminated abnormally|Restarting after
  unexpected exit` 零命中;各 bundle 末条 Executed = `Test Suite 'All
  tests'` 总计行(App: started 04:53:23 / passed 04:59:27)。
- **skip 35 构成亲点**:全为既有 env 门族(LA_QL_PERF /
  LIGHTAMER_PERF_PROBE 探针族、Catalog/Library benchmark harness、
  ColorChecker ARW/RealRAW fixture、Vision face)——零 M7-3 相关 skip,
  零静默吸收。
- **新测试亲点(我的轮日志)**:McpProjectToolsetTests 17 法全 passed;
  `testFinalSnapshotUnion27Verbatim` passed;EXPORT bundle
  `testRenderedPlaneDefaultMatchesExplicitFalseByteEqual` +
  `testRenderedPlanePristineOnlyMatchesNoSidecarCopyByteEqual` 两法全 passed。
- **build-for-testing 新鲜度**:xctest 二进制 03:26:23-30 构建(晚于 T4
  commit 02:59;McpServerController.swift 终版 03:26:10 早于产物);
  T6 commit `7694e7b1` = docs-only(亲验 6 文件全 .work/AGENTS 面);
  McpFinalSnapshotTests.swift mtime 03:35 晚于产物 → 用二进制内嵌串亲证
  终版在产物内:`strings` 命中 "the final count is 27"/"no 28th tool",
  "the final count is 23"/"no 24th tool" 零命中 + McpProjectToolsetTests
  marker 串命中;我的复跑结果与执行者逐 bundle 同值 = 双重佐证。
  工作树 = HEAD 干净(仅 3 个无关 untracked 文档件)。

## 二、T2 pristineOnly 深审(最重项)——PASS

1. **Core 触点恰两处(亲核全 diff)**:`QuickLookRenderer.swift` 全 diff
   = 恰两 hunks(签名尾部 `pristineOnly: Bool = false` :226 + :243
   `pristineOnly ? nil : readDocument`);函数其余逐行零触;
   `grep -c pristineOnly` 该文件 = 2。
2. **9 调用点/5 文件零 diff(亲核)**:QL pane 内部 :123/:171(原文件零
   diff 覆盖)/ McpRenderParityTests :221/:262/:543 + McpMatchColorParity
   Tests :158(两文件全 diff = 0)/ QuickLookRendererTests :206/:227
   (文件 diff 纯尾部 additive,既有调用零改)/ MCP body EditingToolset
   (T3 申报内改形 :1020/:1042 双臂,逐 hunk 核对无申报外形)。
3. **三判据亲跑**:两负测在位且我的 EXPORT 轮亲证 passed——
   ①缺省 ≡ 显式 `pristineOnly:false` byte-equal(带 sidecar fixture,
   非链真的会红)②`pristineOnly:true` ≡ 同图无 sidecar 副本缺省渲染
   byte-equal(`plane.data` 全量比对)。
4. **region round+clamp 边界(亲测)**:实现面
   `croppingPixelRect` = round → 平面 bounds clamp → 交后 w/h<1 →
   invalidParams 携归一化值(不落 cropping-nil → renderFailed 静默面,
   detailCrop 先例只作 bail-out);golden 亲跑(我的 App 轮 passed)——
   x+w==1.0 精确臂 800×600 全帧不缩;亚像素 0.0005 臂 → invalidParams
   且 message 携 "0.0005";越界两臂 typed 拒(invalidParams /
   roiOutOfBounds);schema 恰 +region 属性(0..1 四 double)。

## 三、T4 四域深审——PASS

- **current-project 盒**:`HeadlessProjectBox`(NSLock 保护
  store/url/readOnly 三元;set/current/takeStore);liveState/semantic/
  fulltext/library 四 seam 全 per-call 盒读;盒空 = bare-context null 面
  (`testBoxEmptyGetStateIsTheBareContextNullFace` 亲跑过)。
- **H2 :194 锚随盒**:library seam `projectDirectory` =
  `box.url.deletingLastPathComponent()`(启动捕获退役);executable
  judgment = `testSelfSwitchClosesThenOpensWithAnchorFollowing`(A→B 后
  get_state 与解析锚同指 B)。**进程级实证(端到端第 6 步)**:A 持
  seeded row → open B → `list_versions(1)` = "id 1 is not a row of the
  open library"——锚确随盒,亲证。
- **EOF watcher 双保险**:`armStdioEOFReleaseOnce(mode:)` 恰两调用点
  (:321 parkRuntimeStore / :552 启动);once guard(eofArmLock +
  eofArmDone)+ 内部 `mode == .stdio` 自守卫(M1)在位;
  `testHttpModeRuntimeOpenArmsNothing` 亲跑过(http open 后
  eofArmDone 恒 false)。**S1 见 §六——真实 HUP 面为先前潜伏缺陷**。
- **GUI 臂**:held 目标 `probeLockAvailable` 预检在 openProject 之前
  (held → typed projectReadOnly,不掀当前项目)+ before/after 差分三
  clause(beforeConflict==nil ∧ afterConflict!=nil ∧ store 引用未变);
  两腿 stub fixture 亲跑过;`lalb.lock` 形与 controller :190-191/
  LightamerApp :1323-1324 先例同形亲核。
- **零 diff 亲核**:`LibraryProjectController.swift` 全 diff = 0;
  `McpToolRegistry.swift` 全 diff = 0(错误码 16 档封闭表 +
  McpTimeouts 双零);裸 `McpSearchStateContext()` controller 内零命中
  (H3);生产调用点五处(stdio/http/no-project 两臂 + 仲裁三宿主)全传
  project provider;`requiresWriter: true` 恰两处 + list_versions
  readOnlyHint;`version_ref` ProjectToolset 零命中(双真相禁令);
  EmbeddedState.project 第五缝在位(off→on toggle 不静默缺席)。
- **真端到端抽测(独立脚本,stdio 起 server)**:
  ①initialize(2025-11-25)→ tools/list = **27**(六关键工具在位)
  ②`project_create` 实调 → 四键 summary{path,name,readOnly,
  heldByOther},无 photo_count(D-M7-3-6)③get_state 即时反映 ④
  sqlite 种一行 + Media 文件 → `list_versions(1)` = pristine 诚实面
  `{image,activeVersionID:null,versions:[]}` ⑤`render_preview` = typed
  notSessionMember(无头臂无 session 的诚实臂;真实渲染体由进程内
  Metal golden 覆盖——render_preview 是 session 域工具,无头 stdio
  进程级只可达 typed 臂)⑥A→B 自持切换(见上 H2)。
  全部 ①-⑥ PASS。

## 四、T5 union 对账——PASS

- **27 全点位**:render_preview schema 行(region+compare)+ list_luts
  行 + projectTools 三行(descriptors() 名序)+ all23→all27(定义 +
  引用)+ 计数 ×4(:209 段/:246 段/:274 段/:421 段——行号微漂移内容
  亲核)+ 组合代数四集合并 + disjoint +3 + descriptionKeys +4 +
  makeUnionRegistry 与 SC7 传 fixture + F-AC-4 注释非易碎形 + 测试名
  Union23→Union27 + 头注/message 同批——全部亲核在位。
- **五计数钉 20→21**:McpRegistrySnapshotTests :203-204 /
  McpSearchStateToolsetTests :274-275 / McpHostTests :243+:697(:718
  memory 臂 = `memoryTools == httpTools` 等值断言无独立硬码亲核)/
  McpLauncherTests :200——全带 message 同批。
- **残漏 grep 亲跑**:`count, 20`(仅命中 SentinelTests `count, 2000`
  buffer 断言 = checker 申报的清白旁证)/ `count == 20` / `all23`
  全仓零命中。
- **两层同批**:editing 层(render_preview 行 + list_luts 行 6→7 +
  :29 docstring "all 27")与 union 层同 commit;assertSnapshot 不比
  description(亲核——占位符 "snapshot"/"list" 合法);culling 层零
  diff;searchstate 工具面零 diff(:270 计数负测显式改例外,负测语义
  保持)。
- **红窗纪律**:cf49c046/3ef68910/bb6026f1 三 commit 零快照文件触碰
  (亲核)——禁提前改快照兑现,显式改集中 T5。

## 五、偏差 1-8 + §3 执行期新增逐项裁决

| # | 项 | 裁决 |
|---|---|---|
| 2.1 | http 无 EOF 腿(H3③) | **认**——guard 在位 + 偏离句落 DECISIONS;前提面受限见 S1/O2 |
| 2.2 | EOF arm 恰两调用点(启动+parkRuntimeStore) | **认**——grep 恰两处,open/create 经共享尾计数与 plan 字面吻合 |
| 2.3 | 两臂先关后开差异句(H4②) | **认**——代码+测试双证(headless close-then-open 盒清空诚实态;GUI held 预检+差分;promoteRecent 不对称申报) |
| 2.4 | 寻址单源抽取(M3) | **认**——纯抽取零语义变;MatchColorToolset 零 diff(禁顺手动兑现) |
| 2.5 | library projectDirectory 锚退役(H2) | **认**——盒读锚 + golden 腿 + 端到端进程级亲证 |
| 2.6 | region round+clamp 两边界 golden(M2) | **认**——实现与 golden 终值亲核(800×600 全帧/0.0005 携值) |
| 2.7 | pristine 键数 12→13(L1) | **认**——亲点恰 13 键 |
| 2.8 | ⑥ cursor 承接句 | **认**——DECISIONS §2.8 在位 |
| 3.1 | 盒终形 + semantic/fulltext 同批盒读 | **认**——plan「library/fulltext/liveState/probe 全接线」的一致延伸,additive |
| 3.2 | makeHeadlessSearchState 签名演化 | **认**——盒驱死后旧参误导;T1 调用点同批改,构建绿门维持;F-AC-2 语义原样 |
| 3.3 | Box/eofArmDone internal 化 + 测试序复位 | **认**——进程全局态的测试序独立性要求;复位点亲核(盒空测试/Held 腿/CheckBeforeOpen/fulltext 负测);字母序推演无冲突(Http 复位后 Release/SelfSwitch 重臂自证) |
| 3.4 | dup2 /dev/null 防自噬 | **认**——setUpWithError 先于每法,套件内所有 arm 见 /dev/null(poll 永不 HUP);仲裁真 HUP 面由跨进程纪律承载;注:S1 使该网当前 moot,但属正确防御性卫生(poll 若修复仍必要) |
| 3.5 | StubProjectController(H4③ 腿) | **认**(带 O1)——controller 零 diff 红线下唯一可测形态;谓词同形复制有漂移残留风险,见 O1 |
| 3.6 | suite 级 @MainActor | **认**——Swift 6 region isolation 下 test-case self 跨 actor 发送的编译要求;registry/provider 调用不敏感 |
| 3.7 | list_versions includeItems items 形 | **认**——get_history 投影减 params 面,合理 |

**ΔN +28 构成亲核(超带 +8 正当性)**:T1 = Library +2(FilterSQL 两法)
+ App +2(F-AC-2 真值断言 + N2-3 负测;N2-4 嵌既有法零新/N2-1 同批零新)
/ T2 = Export +2 / T5 = App +22(McpProjectToolsetTests 17 + editing
additive 5:region golden/rejections/compare 双臂/region 双臂/list_luts
golden)= **+28** ✓。带 +12..20 为 research §0.5 预估,plan 明文「预估带
……越带如实申报」;超带构成 = 评审修订批显式增腿(H2 锚腿/H4③ 两腿/M1
门控腿——CHECKER 门 5 亲核在 plan 文)+ SC 强制腿(域快照 verbatim/注解
executable/白名单负测/盒空负测/仲裁 fixture 每腿一法)。构成逐条可追溯
SC/评审处方,无凑数测试。**裁决:正当,如实申报兑现。**

**红线族(全亲跑 PASS)**:零新 SPM(Project.swift 恰一行测试登记)
/ `.metal` 全域零 diff / 封存面 17 件零 diff(Registry 命中为测试文件
误匹配,真身 IOP Registry/ModuleInstance 零触)/ McpToolRegistry.swift
零 diff / McpTimeouts 零 diff / controller 零 diff / xcstrings = 恰 1
删除行(render_preview 原位改)+ 4 新键 JSON 序恰列文件末四位(尾块纯
插入)/ UserDefaults 零新键(diff 仅两处既有键读)/ runModal App/Sources
零命中 / LocalizationValue 插值禁形零命中(:2294 = M3-1 既有文档注释)
/ BUNDLE-MAP 恰一行 / zh-audit `--check` PASS(1695 source keys)+
`--self-test` PASS。

## 六、独立发现(非阻断)

- **S1(显著;先前 M6-1 潜伏缺陷,非本波违例)**:stdio EOF watcher 的
  `poll(fd: STDIN_FILENO, events: 0)` 在 macOS 对管道**永不因写端关闭
  醒来**——本验收以同形最小 C 探针亲测:events=0 + 唯一写者关闭后
  ≥12s 不醒(sample 亲证卡 `McpServerController.swift:398` poll);
  同形改 `events: POLLIN` 则 0.38s 醒,revents = POLLIN|POLLHUP(0x11)。
  后果 = 「agent 断连 → checkpoint 优雅释放」面(M6-1 KD-4 / OQ-7 /
  D-M7-3-7)实际惰性,真实释放 = 进程退出 kernel 地板(plan 语言本身
  允许的底);DECISIONS H3③「checkpoint 优雅面仅 stdio」高估 stdio
  侧实际工作面(→ O2)。**先前性亲证**:基线 `217999a5` :355 原体
  同形 `events: 0`——M7-3 红线「启动路径行为逐字节不变」被忠实兑现,
  抽取未引入新缺陷;且全测试面从未真跑 HUP(McpProjectArbitrationTests
  全部 `child.terminate()`=SIGTERM,「真实 HUP→checkpoint→exit 由仲裁
  测试承载」的 DECISIONS 句不准确)。**处置建议**:报 orchestrator 立
  M7-4/独立 fix 批;修法方向(需独立裁决,勿顺手修):poll 改 POLLIN
  请求 + 醒后按 `revents & POLLHUP` 分流(HUP → close+exit;POLLIN →
  清位续 poll——不消费字节,保「watches HUP without stealing bytes」
  原意图;http 臂 M1 自守卫语义不变),修复批需 e2e 真断连回归用例
  (本验收脚本可复用)。本波验收按「行为逐字节 = 基线」判 **PASS**。
- **O1(minor)**:GUI 差分谓词测试 = LightamerApp 生产闭包的**同形
  复制**(§3.5 申报形)——生产闭包本身只有编译+装配覆盖,复制体与
  原体存在漂移残留风险。后续可考虑把谓词逻辑抽 App target 内可测
  helper(单源)消二份。
- **O2(minor)**:DECISIONS H3③ 与 SUMMARY 的「checkpoint 优雅面仅
  stdio」措辞在 S1 修复前高估 stdio 优雅面;S1 修复批同批校订。
- **O3(info)**:plan/申报内行号若干处微漂移(:194→:203、:270→:274、
  :696→:697)——内容逐点亲核吻合,零行动。

## 七、commit 清单(执行链 `c6019122..7694e7b1`,未 push)

| commit | 内容 | 验收核 |
|---|---|---|
| `c6019122` | fix(m7-3) T1 顺路件六项 | 恰四文件;F-AC-1 两法/F-AC-2 默认参透传/N2-1 13 键+golden 同 commit/N2-3 typed 抛+负测/N2-4 requestFailed 臂 |
| `cf49c046` | feat(m7-3) T2 pristineOnly+region | Core 恰两处;9 调用点零 diff;两负测;region 校验链 |
| `3ef68910` | feat(m7-3) T3 compare 双臂+list_luts | schema +region+compare;双臂不共享 decode;[current,root,text];list_luts 只读投影;xcstrings 原位改+尾块 |
| `bb6026f1` | feat(m7-3) T4 ProjectToolset+运行时缝 | 四域/盒/锚/EOF 双保险/五调用点/EmbeddedState 第五缝;controller+registry 零 diff |
| `286530d2` | test(m7-3) T5 union 23→27 | 全点位+五钉+两 golden 层+新文件 17 法+登记两行 |
| `7694e7b1` | docs(m7-3) T6 收口翻账 | docs-only 亲验(6 文件) |

## 八、验收形态(ROADMAP §M7-3 三条)

1. **compare/region golden ✓**——T5 四法 + T2 两负测(我的轮亲跑过;
   两边界腿 M2 兑现)。
2. **project 工具与单写者锁仲裁 fixture ✓**——in-process 双 store
   真 flock held 形(携真 pid)+ 释放恢复 + 自持切换 + create 三拒 +
   writer gate executable + 盒空 null 面 + M1 http 不 arm + H4③ 两腿
   stub fixture;另加进程级端到端抽测(create/open/switch/pristine
   投影)亲证。
3. **快照族零意外 diff ✓**——union/editing 两层显式改全点位 + 五钉 +
   残漏 grep 零命中 + culling/searchstate 工具面零 diff + T2-T4 红窗
   纪律亲核。

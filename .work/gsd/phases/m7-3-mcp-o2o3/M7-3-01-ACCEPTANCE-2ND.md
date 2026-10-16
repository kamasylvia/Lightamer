# M7-3-01 ACCEPTANCE-2ND — 第二路独立验收（subagent，零共享上下文，2026-10-17 夜间批）

> **结论头：PASS / 0 error + 4 minor/info 级独立发现**
> （S2 新显著发现〔非阻断〕+ S3 正臂覆盖缺口〔minor〕+ O1 确认 + O2 确认；
> S1 成立且三层独立复现，归因 M6-1 潜伏非本波违例——同第一路，无分歧）。
> 验收方式 = 不轻信第一路与执行方：全套独立复跑（自建 build-for-testing）
> + 五面独立审计（错开切入）+ 真产线二进制 E2E 三轮 + S1 独立探针复现
> + 红线族亲跑。执行链 `c6019122..7694e7b1`（6 commits），基线 `217999a5`。
> **未 push**（工作树 = HEAD + 3 个无关 untracked 文档件）。

## 〇、验收过程事故自我申报（非产物缺陷）

第一轮全套（05:29 起）在 IOPParity 中段（05:37:50，FilmGoldenTests.
testBakeDomainBoundsMatchDocumentedCalibration）被判 crash——**根因 = 本验收
自己在清理 E2E 探针残留进程时 `kill -9 80377` 误杀了测试宿主**（SIGKILL 签名
`time: command terminated abnormally`；log 留证 `/tmp/m73_accept2_all.log` +
`/tmp/la-direct-tests-IOPParity.log`）。违反了 M2-7-3「进程清理先核 parentage」
教训（先杀后查）。处置 = 按 M2-7-3 先例留证后**干净重跑**，第二轮零进程干预，
逐 bundle 闭合同值（见下）。此事故独立佐证该教训的纪律价值。

## 一、全套独立复跑（本验收自建产物，非转抄）

`caffeinate -dis xcodebuild build-for-testing`（**自建新鲜产物**，二进制
05:29 晚于 T6 commit 7694e7b1 04:23——工作树 = HEAD，免第一路的 mtime/strings
间接证明）→ `caffeinate -dis Scripts/test-direct.sh --all`（第二轮，2129s，
exit 0，**脚本 EXIT=0**）：

```
BUNDLE|IOP|687/5/0|peakRSS=7642MB|425s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=7008MB|792s|sampling=time
BUNDLE|Layers|494/5/0|peakRSS=808MB|183s|sampling=time
BUNDLE|Library|731/4/0|peakRSS=623MB|79s|sampling=time
BUNDLE|Sessions|284/9/0|peakRSS=1628MB|63s|sampling=time
BUNDLE|Export|381/5/0|peakRSS=6268MB|197s|sampling=time
BUNDLE|App|868/4/0|peakRSS=2832MB|390s|sampling=time
TOTAL|3905/35/0|2129s
OK (direct launch, no testmanagerd)
```

- **对账闭合（亲算）**：687+460+494+731+284+381+868 = 3905；skip 5+3+5+4+9+5+4
  = 35；failed 全 0；3877 + ΔN 28 = 3905 精确闭合；**与执行者申报、第一路
  亲跑三方逐 bundle 同值**（RSS 在 ±3% 同族方差带内：IOP 7594→7642 /
  IOPParity 6986→7008 / Export 6094→6268）。
- **8G 门 + MEMFAIL**：峰 RSS 最大 7642MB < 8192，七 bundle 0 MEMFAIL。
- **L055 机检（我的七份 log 亲跑）**：`terminated abnormally|Restarting
  after unexpected exit` 全零命中；每 bundle 恰 1 个 `Test Suite 'All tests'
  passed` 末条挂靠；末条 Executed 行逐 bundle 与 BUNDLE 行同值。
- **skip 35 构成亲点（我的 log）**：App 4 = Depth 探针/金家族 env 门 ×4、
  Export 5 = Mertens probe / Pano probe ×2 / QL perf / Yiyin RAW fixture
  缺失——零 M7-3 相关 skip，零静默吸收。
- **新测试亲点（我的轮日志 grep）**：McpProjectToolsetTests 18 行全 passed
  （17 法 + suite 行）/ 0 failed；`testFinalSnapshotUnion27Verbatim`、
  `testRenderPreviewCompareRootDualArm`、`testListLutsGoldenSeededProjection`、
  `testSelfSwitchClosesThenOpensWithAnchorFollowing`、
  `testHttpModeRuntimeOpenArmsNothing`、两 GUI 腿、Export 两 pristineOnly
  负测——全 passed（我的轮，亲证非转抄）。

## 二、五面审计（错开第一路切入）

### 面 1：T2 render_preview —— PASS
1. **Core 触点恰两处（全 diff 亲核）**：`QuickLookRenderer.swift` 恰两
   hunks——签名尾部 `pristineOnly: Bool = false`（:226）+ :243 条件化
   `pristineOnly ? nil : readDocument`；`git diff 2e530f8e..7694e7b1
   --name-only -- LightamerCore/Sources LightamerIOP/Sources` = **恰此一文件**
   （封存面 + 单写者锁 + Core 全域零触的最强形态亲证）。
2. **两负测实质亲核**：byte-equal 走 `plane.data` 全量比对且 sidecar fixture
   真参与（非链真的恒等负测会红）；真值断言在我的 Export 轮亲跑 passed。
3. **region 校验链亲核**：decode（非 object / 缺键 / w≤h≤0 → invalidParams；
   越界/负坐标 → roiOutOfBounds）→ `croppingPixelRect` = round → bounds
   clamp → 交后 w/h<1 → invalidParams 携归一化值（0.0005 臂 message 亲测含
   值）；golden 手算帧（400×150 / x+w==1.0 → 800×600 全帧）在我的 App 轮
   亲跑 passed。
4. **compare 双臂（T3）亲核**：双臂同一 boundedWait 闭包两遍 renderedPlane
   （pristine 臂 `pristineOnly: true`，各自 decode——红线「不共享 decode」
   兑现）；内容序 [current, root, text] + summary JSON 尾；compare:none =
   单图面；golden 三断言（序 / root 臂 ≡ 无 sidecar 渲染 byte-equal /
   显式 ≡ 缺省）亲跑 passed。
5. **进程级 E2E（我的独立轮）**：真实 stdio server（真 app 二进制
   `--mcp-stdio`）→ tools/list 27 含 render_preview → 无头臂调用 =
   typed `notSessionMember`（session 域工具在无 session 宿主的诚实臂，与
   第一路观察一致；真渲染面由进程内真 Metal golden 覆盖 = 我的全套轮）。

### 面 2：T4 —— PASS
- **盒/锚/EOF 双保险**：`HeadlessProjectBox`（NSLock 三元 + takeStore pop）
  / library seam `projectDirectory = box.url.deletingLastPathComponent()`
  （H2）/ `armStdioEOFReleaseOnce` 恰两调用点（grep 亲证 :321 parkRuntimeStore
  + :552 启动）+ `mode == .stdio` 自守卫（M1）+ once guard。
- **GUI 臂**：`probeLockAvailable` 预检在 openProject 之前（held → typed
  projectReadOnly 不掀当前项目）+ before/after 差分三 clause；LightamerApp
  生产闭包 diff 逐 hunk 亲核同形。
- **零 diff 亲核**：`McpToolRegistry.swift` 链内 diff = 0 行；
  `LibraryProjectController.swift` = 0 文件；`SingleWriterLock.swift` = 0
  （probeLockAvailable/holderSummary 皆既有 Core 面）；裸
  `McpSearchStateContext()` controller 内零命中（H3）；生产 `project:`
  provider 五调用点（:445/:457/:567/:582/:600）+ GUI 第六处全传。
- **进程级 E2E 三轮（我的独立轮，真 app 二进制）**：①tools/list = **27**
  ②`project_create` → 四键 summary {path,name,readOnly,heldByOther}、
  **photo_count 缺席**（D-M7-3-6）③`get_state` 即时反映盒真值（path/readOnly/
  hostMode=stdio）④M1 臂 http 不 arm（in-process 亲跑）+ EOF once（见 S1）。
  自持切换锚随盒（A→B）由 in-process golden 腿亲跑覆盖。

### 面 3：T5 快照面 —— PASS
- **27 全点位亲核**：render_preview schema 行（region+compare）+ list_luts
  行 + projectTools 三行 + `all27` 定义/引用 + 计数 ×4（:249-250 message
  "the final count is 27" / :299 / :327 "no 28th tool" / :479 SC7）+
  descriptionKeys +4 + 四域并 + disjoint +3。
- **残漏 grep 独立跑**：`count, 20`（MCP 面）/ `count == 20` / `all23`
  零命中；SentinelTests `count, 2000` = buffer 断言清白旁证。
- **五计数钉 20→21 亲点**：McpRegistrySnapshotTests :203 / McpSearchState
  ToolsetTests :274 / McpHostTests :243+:697 / McpLauncherTests :200，
  message 同批。
- **锁仲裁 fixture 实质亲核**：held 腿真 flock（第二 store 真持有 + 携真
  `pid=\(getpid())`）+ 盒空断言 / 释放恢复 / 自持切换（get_state A→B +
  H2 锚随盒断言 + eofArmDone 翻转）/ create 四拒 + happy 腿 / writer gate
  executable（open/create serverReadOnly + list_versions 穿门）/ 盒空 null
  面 / 白名单负测——17 法全有可机检断言，我的轮全绿。
- **list_versions golden 族亲核**：byte-equal 投影（sortedKeys 序）+
  includeItems + 500 帽保新端 + 双地址臂（OQ-8 同闭包变量赋两 context 的
  fixture 形亲核——`makeVersionRegistries` 同一 `librarySeam` 赋两 registry）。

### 面 4：偏差 1-8 + 执行期新增七项 —— 全认（逐项独立复核）
| # | 项 | 第二路裁决 | 亲核面 |
|---|---|---|---|
| 2.1 | http 无 EOF 腿 | 认 | :391-394 guard mode==.stdio 亲核 |
| 2.2 | EOF arm 恰两调用点 | 认 | grep 恰两处 |
| 2.3 | 两臂先关后开差异 | 认 | headlessRuntimeOpen close-then-open + GUI 预检差分代码面 |
| 2.4 | 寻址单源抽取（M3） | 认 | resolveImageURL seam 化形 + MatchColorToolset 链内零 diff（diff stat 空）|
| 2.5 | :194 锚退役（H2） | 认 | 盒读 + golden 腿我的轮亲跑 |
| 2.6 | region round+clamp（M2） | 认 | 实现面 + 两边界 golden 亲跑 |
| 2.7 | pristine 12→13（L1） | 认 | :840 truncated 亲点恰 13 键 |
| 2.8 | ⑥ cursor 承接句 | 认 | DECISIONS §2.8 在位 |
| 3.1 | 盒终形 + semantic/fulltext 同批盒读 | 认 | 「全接线」一致延伸，additive |
| 3.2 | makeHeadlessSearchState 签名演化 | 认 | T1 调用点同批改形（T1 测试现调新形亲核）|
| 3.3 | Box/eofArmDone internal + 测试序复位 | 认 | 三处 `headlessProjectBox.set(.init())` 复位亲点 |
| 3.4 | dup2 /dev/null 防自噬 | 认 | setUpWithError :50-52 亲核；S1 使真 HUP 面 moot 但防御性卫生正确 |
| 3.5 | StubProjectController | 认（O1 确认）| controller 零 diff 红线下唯一可测形；漂移残留风险真实 |
| 3.6 | suite 级 @MainActor | 认 | Swift 6 region isolation 编译要求 |
| 3.7 | includeItems items 形 | 认 | get_history 投影减 params 面 |

### 面 5：S1 独立表态 —— **成立，三层独立复现，无分歧**
1. **最小探针独立复现**（自写 C probe + pipe/fork/exec harness，非转抄
   第一路脚本）：`events: 0` 形（产线形）唯一写者关闭后 **20s 不醒**
   （强杀收场）；同形改 `events: POLLIN` → **2.001s 醒，revents = 0x11**
   （POLLIN|POLLHUP）。与第一路（≥12s 卡死 / 0.38s / 0x11）同判。
2. **真产线二进制复现**：真 app `--mcp-stdio` + runtime `project_create`
   （arm EOF watcher）→ 关闭 stdin（断连面）→ **12s+ 进程不退出**，
   `sample` 亲证卡 `static McpServerController.armStdioEOFReleaseOnce(mode:)`
   的 poll（McpServerController.swift:398）。
3. **归因亲核**：基线 `217999a5` :355 原体同形 `events: 0` 亲读；`git log
   -S "events: 0"` 引入 commit = **`1f981f9b`（M6-1 headless arbitration
   批）**——M7-3 抽取忠实保留字节，非本波引入。✓ 第一路结论全部可复现。
4. **M7-4 修复批建议形态**（表态）：poll 改 `POLLIN` 请求 + 醒后按
   `revents & POLLHUP` 分流（HUP → close+exit；纯 POLLIN → 清位续 poll
   不消费字节）——本验收的探针/harness/e2edrv 脚本（`/tmp/m73_probe/`）
   可直接改造为 e2e 真断连回归用例（真二进制 + 真 EOF + 活性断言，
   12s 窗）。

## 三、红线族（全亲跑 PASS）

零新 SPM（Project.swift 链内 diff 恰一行测试登记）/ `.metal` 链内零 diff /
McpToolRegistry.swift 零 diff / McpTimeouts 零 diff / controller 面（链内
352 行 diff = 申报文件本体；registry/library controller/SingleWriterLock
零触）/ 封存面亲证（Core+IOP 链内恰 QuickLookRenderer.swift 一文件）/
xcstrings = 恰 1 删除内容行（render_preview zh 原位改）+ 4 新键（list_luts/
project_open/project_create/list_versions）/ UserDefaults 零新键（diff 内
零命中）/ `runModal(` 链内新增零命中 / `LocalizationValue("...\( 插值禁形
零命中 / zh-audit `--check` PASS（1695 source keys）+ `--self-test` PASS
（本验收亲跑）。

## 四、独立发现（本波非阻断；报 orchestrator 处置）

- **S2（显著；本波新工具面，plan 级盲区非实现偏离）**：**`list_luts` 进程级
  首调 50.2s 才回复**（声明窗口 `McpTimeouts.list` = 10s）。亲测：真
  stdio server 冷进程首调 `list_luts` → 应答 50.2s 后才落盘（e2edrv3 计时；
  sample 栈亲证线程在 `LutLibraryStore.shared` 首次 dispatch_once →
  `rescan()` → `CubeLutParser.parse` 纯 CPU 解析内置 40 LUTs——非死锁，
  是长解析）。机制：`withTimeout` 的 v1「stuck body blocks」形（任务组
  scope 退出 await loser）无法救援不响应取消的 CPU 型 body——10s 超时错误
  在 race 里永远赢不了，应答被 body 时长决定。测试面从未暴露
  （`testListLutsGoldenSeededProjection` 用 `replaceShared` 塞小 store，
  不触默认根全库解析）；GUI 臂有 UI 预热，**stdio agent 臂独吃冷成本**。
  实现 = plan T3 字面处方照办（「McpTimeouts.list 包裹 + LutLibraryStore.
  shared 直读」均 plan 处方），故判 plan 盲区。**处置建议**：报
  orchestrator 入 M7-4（宿主启动后台预热 shared store / 解析协作化挂起 /
  description 明示首调代价——三选一需裁决，勿顺手修）。客户端短超时
  （常见 30-60s）会误杀此调用，agent 实测体验劣化真实存在。
- **S3（minor；新）**：GUI 差分谓词的**正臂无可执行判定**——两腿 stub 均
  `heldTargets: []`（leg1 走预检拦截、leg2 走 stale 不触发）；
  `before==nil ∧ after!=nil ∧ store 未变 → typed projectReadOnly` 的正臂
  仅在 probe-passed-但-openProject-published-conflict 的窄竞态窗口可达，
  当前零测试覆盖（`heldTargets` 非空调用点全仓零命中亲证）。生产面该
  clause 是防御网（预检已拦确定性 held），不阻断；建议 M7-4 顺路补一腿
  （`heldTargets` 非空 stub 腿即可，零生产代码）。
- **O1 确认（第一路已报）**：GUI 谓词同形复制漂移风险——亲核成立（复制体
  `afterStore == beforeStore` 值比对 vs 生产 `===` 引用比对的差异已在
  stub 形内诚实注记）。
- **O2 确认（第一路已报）**：S1 复现后「checkpoint 优雅面仅 stdio」措辞
  高估实况（stdio 侧 watcher 实际惰性）——M7-4 修复批同批校订。

## 五、分歧

**无实质分歧。** 第一路 PASS 判定 + S1 归因 + O1/O2 全部独立复现确认；
S2/S3 为第一路未覆盖的角度（进程级冷延迟量化 / diff 正臂覆盖审计），
非矛盾发现。

## 六、commit 清单（执行链 `c6019122..7694e7b1`，未 push）

| commit | 内容 | 第二路核 |
|---|---|---|
| `c6019122` | fix(m7-3) T1 顺路件六项 | 恰四文件；F-AC-1 两法在 FilterSQLTests :97/:158 亲点 |
| `cf49c046` | feat(m7-3) T2 pristineOnly+region | Core 恰两处；两负测实质亲核 |
| `3ef68910` | feat(m7-3) T3 compare 双臂+list_luts | 双臂不共享 decode；[current,root,text]；summary JSON |
| `bb6026f1` | feat(m7-3) T4 ProjectToolset+运行时缝 | 盒/锚/EOF/五调用点/EmbeddedState 第五缝；controller+registry 零 diff |
| `286530d2` | test(m7-3) T5 union 23→27 | 全点位+五钉+17+5 新法；登记两行 |
| `7694e7b1` | docs(m7-3) T6 收口翻账 | docs-only（6 文件全 .work/AGENTS 面） |

## 七、验收形态（ROADMAP §M7-3 三条，第二路独立判定）

1. **compare/region golden ✓**——T5 四法 + T2 两负测（我的轮亲跑全绿）。
2. **project 工具与单写者锁仲裁 fixture ✓**——in-process 真 flock 形 17 法
   全绿（我的轮）+ 进程级 E2E（tools/list 27 / project_create 四键 /
   get_state 即时反映 / EOF 断连行为）亲证。
3. **快照族零意外 diff ✓**——27 全点位 + 五钉 + 残漏 grep 零命中（独立跑）
   + 封存面链内零触亲证。

**S1 表态**：成立（M6-1 潜伏，非本波违例；三层复现无分歧）→ 报
orchestrator 立 M7-4 修复批。**S2 表态**：本波新面显著发现（plan 盲区）→
一并报 M7-4 处置。

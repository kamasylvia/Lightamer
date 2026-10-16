# M7-3-01 DECISIONS — 执行批裁定记录

> 裁定正本 = `M7-3-CONTEXT.md`(D-M7-3-1..10 全按 RESEARCH §7,本批不重开)。
> 本文件记录执行级落定形态 + 偏离申报 + 顺路件收口申报。配套 =
> `M7-3-01-SUMMARY.md`(总账/ΔN/红线族)。

## §1 快照显式改申报(union 全点位清单——本波持权行使)

`McpFinalSnapshotTests.swift` 显式改全点位(commit `286530d2`):

1. render_preview schema 行(region+compare 两属性)——与 editing 域层
   `McpRegistrySnapshotTests.swift` render_preview 行 **consciously change
   together**(M5-1-03 形)。
2. list_luts 行加入 editingTools(6→7)。
3. `projectTools` 新静态数组三行(list_versions/project_create/project_open
   ——descriptors() 名序)。
4. `all23` 属性名 → `all27`(:184-186 定义 + :207 引用同批)。
5. 计数断言 ×4:testFinalSnapshotUnion27Verbatim 计数(:209 段)+ 组合代数
   :246 段(count 27 + 三集合并 → 四集并 + disjoint +3)+ 白名单负测 :274
   (23→27 + "no 28th tool" message)+ SC7 directTools :421(23→27)。
6. `makeUnionRegistry` 传 `project: McpProjectContext()`(all-nil fixture;
   不传则 27 永不可达)+ SC7 `startHTTPHost` 传同 fixture。
7. F-AC-4 注释(:210 段)非易碎形改写("exactly 9 destructive tools — the §A
   write face + match_color; the remainder are read-only or non-destructive
   state-changing (project_open/project_create)")——grep "11 read" MCP 测试面
   零命中。
8. 测试名 testFinalSnapshotUnion23Verbatim → Union27。
9. 过时计数注释/message 同批:文件头注(:15/:22 段「all20 → all23」「THE
   UNION (23)」→ 27 面叙述;「all23」token 本身改写为「the 23-set」使残漏
   grep 零命中)+ :209 段断言 message + McpRegistrySnapshotTests :30 docstring
   ("asserts all 20" → 27)+ :16/:178 注记。

**union 外五处计数钉显式改(H1)**:`McpRegistrySnapshotTests` :194 段(editing+
culling 无 searchState 闭合面 20→21 + message)、`McpSearchStateToolsetTests`
:270 段(同形,负测语义保持)、`McpHostTests` :243/:696(:718 memory 臂断言
≡ httpTools 无独立硬码随行绿)、`McpLauncherTests` :200——全部 20→21 +
message 同批。**残漏 grep**:`count, 20` / `count == 20` / `all23` 在
Tests/LightamerTests/Mcp* 零命中(McpLauncherSentinelTests :171/:175 的
2000-buffer 断言与 SidecarV10Tests「schemaVersion 11 reads」注释为 checker
§四.2 清白旁证,非工具计数)。

advisory 清扫(CHECKER §四.3 清单内零成本件):McpHostTests :216/:466/:668、
McpSearchStateToolsetTests :15(:262 已随计数钉 docstring 同批)、
McpRegistrySnapshotTests :16/:178、McpFinalSnapshotTests :196 段——同批顺路。
清单外两件(McpRenderParityTests :564 / McpProjectReadOnlyErrorTests :18)按
CHECKER 裁定本波不触。

## §2 偏离申报族(plan 修订批预案兑现 + 执行期形态)

1. **http 无 EOF 腿偏离句(H3③)**:http 运行时开项目 = 进程退出 kernel
   地板,checkpoint 优雅面仅 stdio——armStdioEOFReleaseOnce 内部
   `mode == .stdio` 自守卫(M1 双保险)+ 启动路径既有 `if mode == .stdio`
   门(抽函数后由函数内 guard 承担)。http 臂从不 arm。
2. **EOF arm 调用点数**:plan 写「恰两调用点(启动 + 运行时 open 成功后)」
   ——实际落形 = 启动路径 + `parkRuntimeStore`(open 与 create 共享的单一
   park 尾,内含 arm)= 恰两处。OQ-7 的 open/create 双腿经共享尾实现,
   计数与 plan 字面吻合。
3. **两臂先关后开差异句(H4②)**:headless = 先关后开(close checkpoint 内置;
   失败中间态 = 盒清空诚实态,`closeCurrentHeadlessProject` + open 失败不回填
   ——agent 重试);GUI = held 目标 probeLockAvailable 预检(openProject 之前
   ——held 不触 openProject 不动当前项目)+ before/after pendingConflict 差分
   (before==nil ∧ after!=nil ∧ store 未变化 → typed projectReadOnly;stale
   conflict 反向误报由 before==nil clause 消)。promoteRecent 随 controller
   既有语义 = GUI 臂入 recent / 无头臂天然不入(D-M7-3-9 不对称,controller
   文件零 diff)。
4. **寻址单源抽取申报(M3)**:`SearchStateToolset.resolveImageURL` 抽
   internal 共享 helper(`(image, libraryProvider, sessionPairProvider)` 签名)
   ——行为零变纯抽取;**match_color provider 禁顺手动**(锚病在案,M7-4 路由)
   ——git diff 面核 MatchColorToolset 零触。
5. **library projectDirectory 锚退役申报(H2)**:makeHeadlessSearchState
   library seam 的锚从启动捕获 `projectURL.deletingLastPathComponent()` 改盒读
   `box.url.deletingLastPathComponent()`——A→B 运行时切换后 PathKind 0 解析锚
   随盒(fix `20997721` 同族第二实例关闭)。executable judgment =
   McpProjectToolsetTests.testSelfSwitchClosesThenOpensWithAnchorFollowing
   (get_state.project.path 与 library seam projectDirectory 同指 B)。
6. **region round+clamp 与两边界 golden 终值(M2)**:px/py/pw/ph = 归一化值 ×
   平面尺寸 `.rounded()`(schoolbook)→ 平面 bounds clamp;交后 w/h <1 →
   invalidParams 携归一化值。golden 实测:x+w==1.0 精确臂 800×600 全帧不缩
   (round 恰好归位);亚像素 0.0005 臂 → round(0.4)=0 → invalidParams 且
   message 携 "0.0005"。
7. **pristine 键数 12→13 勘误注记(L1)**:plan 前写「十三键→十四键」系 grep
   口径误计,亲点 12 键(image/position/itemCount/items/versions/
   activeVersionID/note/keywords/rating/flag/colorLabel/author),加
   truncated = 13——与正常面等形。
8. **⑥ cursor 边界承接句**:库重排后旧 cursor 可能跳行/漏行,不引入版本戳
   ——边界口径维持 M7-2-01 DECISIONS §4;list_versions/project 族无 cursor
   面,零新增边界。
9. **F-AC-1 收口申报段**:快照补(`testLibraryDomainSnapshots` 六断言 +
   `testLibraryKeywordsExactSnapshot` 第二法——keywords 四子句在 library 域
   为物化列形故按 plan 条款补第二法)+ 本段 = F-AC-1「二选一收口」两路兑现。
   断言钉现字节(sessionKeywordsCondition 复用形:`+i.` 前缀 + `(1=1)`
   baseline),零新 SQL 面。

## §3 执行期新增裁定(plan 未预设、执行中落定,均 additive)

1. **current-project 盒终形**:`HeadlessProjectBox`(锁保护
   `{store, url, readOnly}` 三元;`set/current/takeStore` 三面)替换
   `headlessProjectStore` 静态变量。**liveState 启动捕获退役范围 = plan 申报
   的 liveState + :194 锚 + 顺带 semanticStore/fulltext 两 seam 同批盒读**
   (plan 要求 no-project 双臂「library/fulltext/liveState/probe 全接线」
   ——语义 seam 不随盒则运行时 open 后 CLIP/fulltext 腿仍指旧载体;盒读 =
   同缝一致性)。read-only open 失败臂的 seeding 形 = store nil + url/readOnly
   仍播(liveState 项目面保持今日仲裁结果形状,库 seam 诚实 nil)。
2. **makeHeadlessSearchState 签名演化**:`(projectURL:isWriter:mode:)` →
   `(mode:projectWriteProbe:)`——盒驱死后 projectURL/isWriter 参数误导
   (盒持真值);T1 两测试调用点同批改形(T4 commit 内,构建绿门要求)。
   F-AC-2 的 probe 透传语义原样延续。
3. **HeadlessProjectBox 与 eofArmDone internal 化**:box class/静态实例与
   EOF once-guard 旗标从 private 提 internal——进程全局态的执行面要求:
   box 敏感测试序前复位(格序依测试字母序,McpProjectToolsetTests 的
   Create/Release/SelfSwitch 腿 park 后残值会污染后继盒空断言与 T1 的
   fulltext nil 载体负测——三处测试前置 `headlessProjectBox.set(.init())`
   复位 + McpSearchStateToolsetTests fulltext 负测同批复位);eofArmDone
   internal 供 M1 http-arm-absence 腿观测(测试前复位旗标保序独立)。
4. **McpProjectToolsetTests 测试进程 stdin 安全化**:stdio 运行时 open 腿在
   测试进程 arm 真 EOF watcher——setUpWithError 将 STDIN_FILENO dup2 到
   /dev/null(watcher poll 永不 HUP,suite 不自噬);真实 HUP→checkpoint→exit
   语义由 McpProjectArbitrationTests 跨进程启动路径纪律承载(本波零 diff)。
   M1 腿的 stdio 正臂可观测面 = eofArmDone 翻转断言(SelfSwitch 腿)+ http
   负臂 = 恒 false(Http 腿);HUP 触发 e2e 不在本波重做(既有 A/B 序列覆盖)。
5. **StubProjectController(H4③ 腿)**:GUI provider 谓词测试用 stub face
   (@MainActor + @unchecked Sendable;openProject 对 held 目标 publishConflict
   不 throw 的 controller 真形)。谓词逻辑 = LightamerApp 装配闭包同形复制
   (held 预检在 openProject 之前 + 差分三 clause);LightamerApp 生产闭包由
   App bundle 其余面(编译 + 快照 + 装配路径测试)覆盖——controller 文件
   零 diff 红线下的可测形态。
6. **suite 级 @MainActor**:McpProjectToolsetTests 整类 @MainActor(Swift 6
   region isolation 下 test-case self 跨 actor 发送的编译要求;registry/
   provider 调用不敏感)。toolError helper `@Sendable` body + 尾部正常完成
   fail 分支(compiler 全路径 return/throw 要求)。
7. **list_versions 的 includeItems items 形**:与 get_history item 投影同构
   (id/label/timestamp/kind/layerScope;不含 params face——includeParams 是
   get_history 专属参数,list_versions v1 不带 params)。

## §4 顺路件六项收口申报(M7-2 挂账单一清单)

①F-AC-1 ✓(§2.9 两法 + 本段)②F-AC-2 ✓(T1 + T4 同缝,盒读改形后 probe
仍透传)③N2-1 ✓(12→13 键 + golden 同 commit)④N2-3 ✓(typed 抛 + nil
载体负测——负测形态 = 直调 context.fulltext closure,进程全局盒前置复位)
⑤N2-4 ✓(F-3 四案闭合)⑥cursor 承接句 ✓(§2.8)。附 F-AC-4 ✓(§1.7)。
**FIX2③ 不承载**(controller 零 diff 门兑现——本波零触 LibraryProjectController,
维持 M7-4 挂账)。match_color provider 锚病维持 M7-4(零触)。CLIP 10s 贴线
待实测维持。

## §5 窄投影/键形终值

- list_versions 投影键序(编码序):image / activeVersionID / versions[];
  per-version:id / name / createdAt / updatedAt / active / position /
  itemCount / truncated / [items?](includeItems 时;items 元素 = id/label/
  timestamp/kind/layerScope)。**version-reference 投影零消费**(token 在
  ProjectToolset.swift 零命中——描述文案以「the library's version-reference
  projection」表述,代码与注释同)。
- list_luts 出参键形:libraryRoot(store.lutsDirectory.path)/ total / luts[]
  {key(根相对 POSIX = resolvedRelativePath), name, hash, is1D, size,
  title?, subdirectory?, rememberedEncodings?{input, output}}。
- project_open/create 出参四键:path / name / readOnly / heldByOther
  (photo_count 缺席 = schema 自描述诚实面;D-M7-3-6)。
- xcstrings 五动作:4 新键尾块纯插入(list_luts/project_open/project_create/
  list_versions,zh-only 形)+ render_preview 原位值改(恰 1 删除行——累计
  diff 面核)。UserDefaults 零新键。

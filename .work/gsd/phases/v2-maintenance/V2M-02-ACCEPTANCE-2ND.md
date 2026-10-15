# V2M-02 ACCEPTANCE-2ND(波 2 清算批——第二路独立验收,2026-10-16)

> 验收方:第二路独立验收 subagent(零共享上下文,不轻信第一路与执行方,逐条亲测;夜间全自动授权链)。
> 对象:执行链 `2ba1d1fe..08f9ebc4`(5 commits),基线 = 波 1 终值 3851/35/0,HEAD = `08f9ebc4`。
> **结论:PASS / 0 error + 0 minor(+2 验收自产注记 N5/N6,均非缺陷)**。全套独立复跑
> **3857/35/0 exit 0 亲证闭合**(新鲜 build 后七 bundle 逐位与申报一致,App bundle 本轮全绿
> ——第一路窗外 crash 未复现);五面深审全部成立;红线族两波合并全零;D-6 **严格独立复现
> 成立**(6 图项目重开态空态卡 + AG spin 栈亲采,与波 1 D-1 修法隔离性亲证);D-4 裁决
> **追认成立**;偏差四项 + 第一路 4 注记全部追认;执行方与第一路报告无虚报。不 push(按派发令)。

## 一、全套独立复跑(本路亲跑,新鲜构建,非转抄)

`caffeinate -dis xcodebuild build-for-testing`(TEST BUILD SUCCEEDED,exit 0)→
`caffeinate -dis Scripts/test-direct.sh --all` →

```
BUNDLE|IOP|687/5/0|peakRSS=7278MB|414s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=8108MB|833s|sampling=time
BUNDLE|Layers|494/5/0|peakRSS=807MB|160s|sampling=time
BUNDLE|Library|729/4/0|peakRSS=621MB|78s|sampling=time
BUNDLE|Sessions|284/9/0|peakRSS=1664MB|62s|sampling=time
BUNDLE|Export|379/5/0|peakRSS=6472MB|201s|sampling=time
BUNDLE|App|824/4/0|peakRSS=2832MB|369s|sampling=time
TOTAL|3857/35/0|2117s
OK (direct launch, no testmanagerd)
```

- **对账**:段和 687+460+494+729+284+379+824 = **3857** = 3851(波 1 终值)+ ΔN₂ 6
  **精确**;skip 35 = 波 1 同值;**0 fail / 0 MEMFAIL / 七 bundle 全 8G 门内**
  (IOPParity 8108MB 居历史带 7242..8111 上沿带内;IOP 7278 / Export 6472)。包装链
  CHAIN_EXIT=0 亲验。**与执行方申报及第一路合并亲证三方逐位闭合**。
- **第一路条件性全套轮注记的复现率观察**:第一路全套轮 App 宿主在窗外既有测试
  `ProcessVersionCarrierTests` 内异常退出(L055 crash 签名,单独重跑绿)。**本路全套轮
  App bundle 全绿 824/4/0,crash 未复现**——本路亲验 App log 零 `terminated abnormally`
  签名 + 末条 Executed 824 挂靠 All tests 总段(本批 +6 新法含 mid-flight 8.8s 真跑全部
  executed)。三轮全集(执行方/第一路/本路)1 次复现 = **复现率 1/3,环境型 flake 归因
  (M2-7-3 先例族)得到加强**,维持「条件性注记,非缺陷」判定。
- ΔN₂ 分解亲证:App 824 = 818+2(T3)+4(T5);其余六 bundle 逐值与波 1 终值相同。

## 二、T1 V17 门面独立审计——成立(+1 独立发现 N5)

- **spec 正则修复形边界(独立 fixture,四边界亲测)**:自建 source+catalog fixture 跑
  `--report`——①**`%@` 混排多参**:`mix_multi`〔String,Int〕vs 变体 `mix_multi %@ %lld`
  → **绿**(SPEC_RE `%(?:@|[a-zA-Z]+)` 对 `@` 显式位在混排序列下解析正确);②**位置参数
  变体键名**:`pos_arg` vs `pos_arg %1$lld` → **MISMATCH 红**(门把 `%1$lld` 解析为空
  spec → expected 不中 → 红)。**失败方向 = 假红非假绿**(未来若真出现位置参数键名,
  门拦下要求人工复核,不静默放行)——安全方向;活树亲查零此类键名(在册 5 处 `%1$@`
  全在 value 文本非变体键名);③**derivable 真错配**:`deriv_mismatch`(Int32)vs `%@`
  → 红(全 Int 族映射端到端再证);④**成员链豁免**:`cfg.name` → EXEMPT 不判。
- **golden 八例独立跑**:`--self-test` PASS(exit 0);活树 `--check` PASS(1688 source /
  1936 catalog / 38 interp 全 variant-PRESENT + spec-matched)本路亲跑。
- **EXEMPT 判定面(豁免过宽评估)**:活树 EXEMPT = **31** site(亲跑报告模式);三多参
  活体(`session_counts` / `settings_catalogs_rebuild_progress` 双调用点 /
  `toast_import_partial`)+ McpLauncher 三键全部 EXEMPT(成员链实参)——**N4 亲证**,
  逐参有序比对的活体 derivable 覆盖 = 0,位置洞防护由 golden g5 合成例 + 本路独立
  fixture 承担。EXEMPT 是 plan 明文「禁误报」设计行为,非放水;如实记录。
- **独立发现 N5(断言面外盲区,观察项非缺陷)**:`String(localized: "K",
  defaultValue: "…\(x)…")` 形态(静态键 + 插值 defaultValue)+ catalog 值带位置占位
  (`%1$@`)——V17 断言 5/6 只覆盖**插值字面键**(`"K \(x)"` 调用形态),此形态的 spec
  错配(参数类型过表 format)不在门内。活树 5 键在册(`session_lock_held` /
  `mcp_connect_guidance_stderr(_noendpoint)` / `mcp_error_project_read_only` /
  `project_read_only_dialog_message`);调用点已**手动 stringify 规避 crash**
  (McpServerController.swift:354-356 注记「%@ requires String arguments…stringify
  explicitly」亲读)——现状无活跃缺陷面;V17 缺口正本(RESEARCH §一.B)未列此形态,
  属后续批可选扩展,登记备查。
- 活体清偿键 / D-5 绿例 / C-3 预言:第一路 §二 全部亲证结论**独立复核一致**
  (`catalog_session_remove_confirm_body` :32420 尾块 + SidebarView 零 diff;
  `toast_hdr_merge_done` derivable 绿;McpLauncher 三键 EXEMPT 非绿、断言 5 层过)。

## 三、T3 PATCH-LIVEPLANE 面——成立(+1 独立注记 N6)

- **任务书指定:armed 双写窗口亲核——窗口不存在**。stamp 写点唯一(AIMaskEditing.swift
  :263-267,`releaseIfIdentityChanged(armed)` + `patchImageURL = armed`),位于 arm gate
  (:255 `guard live==armed ∧ selected==layerID else return ref`)**之后**;gate 前零
  stamp 写点亲读;gate→stamp 之间纯同步段(全函数 MainActor isolated,Swift 6 下无
  await 介于其间)——用户 select 无法插入。「armed 捕获后 select 再变」的窗口内 stamp
  旧值不可能发生:gate 拒(不 stamp)或同步通过(stamp 与 live 一致)。
- **两 eager 释放点触发序**:`LayerEditingState.select`(异值判断,同步释放)+ 
  `EditorAreaView.onChange(of: loadedImageURL)`(view update 时点释放)——两释放点与
  arm gate 相互独立(gate 读 EditorState 状态本身,不依赖 onChange 已跑);释放与 gate
  构成双保险,无双写窗口。`releaseLivePatchState` 释放面 = livePlane/patches/patchState/
  debounceTask 亲读;stamp 有意不清——`releaseIfIdentityChanged` 以旧 stamp 与新 live
  比对触发释放,清与不清两形态均安全(亲核)。
- **patch fire 段亲读**:runPatchRefine 函数头 fire seam(`releaseIfIdentityChanged(live)`
  → guard hasSeed/livePlane)在任何 await 前——切图后 face 已释放则 pass 直接丢弃;
  在飞 segmentPatch await 中切图 → eager release 清 face → 返回后 patches 从空数组
  重建、commitRasterMask(patchRebake: true)不进 stamp 段,mask 腿走 commitLayerEdit
  stack guard(:838 `layerStack.adjustmentLayers.contains(id)` 亲读——切图后旧 layer
  不在新栈 → no-op)。
- **独立注记 N6(孤儿 bake 文件缝,观察项非缺陷)**:上述「在飞切图」竞态下,composed
  (A 图)plane 会烘至 **B 图的 masksDirectory**(anchor 在 commitRasterMask 内重读
  live=B),commitLayerEdit no-op 后该 mask 文件成为无人引用的孤儿文件。非正确性问题
  (历史/栈/session 零污染),且严格优于修复前形态(修复前同一竞态**额外**污染 stamp);
  缺口正本 E5 未列此面,登记备查(修复批如触该文件可顺带收口)。
- **两新测试判别力亲证**:`testLayerSelectReleasesHeldPatchFace`(无 eager 释放则第一
  断言红;同值 re-select 保 face 防过度释放)+ `testMidFlightImageSwitchLeavesNoSessionFace`
  (6000² 放宽 bake 窗 = decodeWidth/Height 产线既有缝的测试专用取值,零注入缝;无
  gate 则 patchImageURL 非 nil 红、mask 落新图则 history==0 红)——判别力真实。

## 四、T5 EXPORT-PRESET-01 面——成立

- **持久化面**:JSON = `[ExportPreset]`(id/name/variant/namingPattern/isBuiltIn)
  synthesized Codable,无版本字段——**与 NamingTemplateStore 先例同构亲证**
  (ExportNamingTemplates.swift:64 同款 `try? decode → 降级`);坏 JSON → 空库
  (测试④亲读);encode 失败写空 Data 与 load 自洽(值类型 encode 实际不可达);
  stored built-in 过滤(测试①tampered 注入亲读)。字段演化代价 = 整库降空(非 crash)
  ——两家族(NamingTemplate/ExportPreset)共享的已知策略,低价值数据域可接受,如实记录。
- **apply 语义(epoch 对齐性)**:`applyPreset → ExportPresetProjector.project(纯函数,
  defaultFace 为底)→ applyFace(全字段替换)`——apply 不触 history/epoch(导出面板态
  = 会话 UI 态,非文档编辑面,OVERWRITE-paste 的 epoch 机制不适用亦不需要,无冲突);
  **M-5 pin 双成立**:编译期(face 结构不含 collisionPolicy/gainMapHDR)+ 运行期
  (applyFace :873-901 无此二字段写点亲读;测试②先设 `.fail`+gainMap=true 后断言
  原值亲读)。capture/project 对称亲读(round-trip 无损;`maximumEdgePixels ?? 0` 与
  defaultFace 0 一致;shortEdge/percent 超集形态 degrade 到 .original 合理)。
- **round-trip 四法 + store 面**:测试①-④逐法亲读,判别力真实(测试③悬挂模板回落
  builtIns[0].pattern 且有效腿照落;坏 variant 整 face 回 defaultFace 禁半落地)。

## 五、T4 RELEASE-DIRECT-INJECT 抽验——成立

`Scripts/make-release-direct-launchable.sh`(110 行)亲读:零产线 diff 形态、Release
ad-hoc 构建参数与 make-dmg.sh 签名形状一致、embed PackageProduct frameworks + 全量
重签 + 直启探针(pid 存活 + 主窗计数)+ 探针毕自起实例静默 kill——与 D-V2M2-4
「防御脚本 + 回摆自愈」定位一致;第一路 probe transcript 硬证据(webp 静态内联 +
PROBE PASS)在案不再重跑(本路不重建 Release,余量盘点定案「当前债形态已消」由
脚本逻辑与 transcript 双证)。

## 六、D-6 登记面——严格独立复现成立(error 级候选定级独立表态:成立)

本路独立执行复现配方(osascript AX 菜单通道,零特殊 harness——**配方可执行性亲证**):

1. 直启 Debug Lightamer.app(新鲜进程 pid 88259)→ 文件 > Open Recent Project >
   **Untitled.lalb(6 图项目)** → 文件 > 进入编辑器。
2. **症状复现(截图 `/tmp/v2m02-2nd/d6-2nd-untitled-editor.png`,本路识图亲证)**:
   filmstrip 6 图带缩略图(A/B/C 真实缩略 + bracket×3)+ 视口中央 legacy Session
   空态卡「选择文件夹以创建会话」+ 右栏「未选择图像」——**带图状态与空态卡不一致态,
   与执行批 diag-a-editor.png 同款**(本路亲读两图对照)。先以 V2M02.lalb(images=0,
   D-7 产物)走一遍,空态卡出现但 filmstrip 空——改用 6 图项目后**严格复现**(排除
   「空项目空态卡合理」解释)。
3. **CPU spin 亲采**:进入编辑器后 CPU 83.2% 持续(elapsed 1:49;低于执行批 99.9%,
   本会话有其它前台负载属正常方差);`sample <pid> 3` 亲采——主线程 **1233/1233 全帧**
   在 `NSHostingView.beginTransaction → ViewGraphRootValueUpdater.updateGraph →
   GraphHost.flushTransactions → AG::Subgraph::update → AG::Graph::UpdateStack::update`
   (AttributeGraph update 循环)——**与执行批 t2-spin.sample.txt 同族同链**(MANIFEST
   记述的 SystemSplitView formCurrentItems 路径同为 AG update 循环族),零 app 帧亲验。
4. **AX 恶化佐证**:spin 态下 osascript AX 树深钻 AppleEvent 失败(-10000)——与执行批
   「filmstrip 24 步循环全部零响应」同面(执行批 pyobjc 24 步证据在案,不再重复)。
5. **与波 1 D-1 修法隔离性(独立复核)**:波 1 D-1 修法触 ColorMatchPanelModel params
   面(两波验收多路封闭);D-6 栈全在 SwiftUI AttributeGraph/布局面——互不相交亲证;
   对照组(波 1 同会话新建路径 walk-8-editor.png 健康)在案,非 GUI 环境全局劣化。
- **定级表态**:error 级候选成立——用户常规工作流(重开项目)编辑器完全不可用 +
  主线程 spin(电量/交互双影响)+ 机检证据硬 + 隔离性亲证 + 复现配方可执行。登记不修
  纪律合规。**处置建议(供修复批)**:sample 栈指向 AttributeGraph update 循环,
  m6-closeout D-1 layout churn 同族——修复批可从「重开项目态的 view graph 循环更新
  源」切入(与执行批 MANIFEST 指向一致)。

## 七、D-4 裁决独立表态——追认成立

- 代码面亲证:`SessionBrowserView.swift:165-170`(targets.count ≥ 2 门 +
  `hdrMergeDialog = MergeDialogCount(count:)`)+ :279-282(`.sheet(item:)`——title
  count 在 item 值内,payload 形态注释亲读)——波 1 修法链在位无反证。
- 语义分析:「走查批复验仍见 0 张」的触发前提 = merge 对话框**实际呈现**;本批 D-6/D-7/D-8
  三通道阻断下对话框从未呈现——触发条件未被行使,「通道不可达 ≠ 复验见 0」区分逻辑
  成立。四 V2M 行 Blocked-Channel 保持 = **义务延续非销账**(D-6 修复后走查批复走)。
  追认。

## 八、偏差四项 + 第一路 4 注记独立表态(全部追认)

| # | 项 | 本路独立表态 |
|---|---|---|
| 偏差 1 | T5 实触 `ExportPresetStore.swift` 新文件(ExportState 零 diff) | 合规——diff 亲证 ExportState 零触、新文件 308 行;plan files_modified 预测不全,DECISIONS 已申报 |
| 偏差 2 | ΔN₂ = +6 = 带上界 | 合规——本路全套亲跑 App 824 = 818+2+4 亲证 |
| 偏差 3 | T2 可达行集缩水为零(通道变体) | 合规——MANIFEST 逐行终态亲读,通道证据(d3_cycle/截图)在案;D-6 本路严格复现反证「不硬造判定」裁定正确 |
| 偏差 4 | T2 harness menu 通道改良 | 合规——本路 osascript 菜单通道亲跑可达(项目重开/进入编辑器全通),正向偏差佐证 |
| N1 | T3 文件落位偏差(EditorState→AIMaskEditing/EditorAreaView)未申报 | 追认注记级——EditorState 零 diff 亲证;eager 释放挂 view onChange 是合理形态选择,修复语义与 E5 正本对齐;DECISIONS 偏差表确无此项(T5 同类有申报),申报面小缺口成立 |
| N2 | EXEMPT 计数口径 30→31 | 追认——本路清偿后亲跑 = 31,与第一路实测一致 |
| N3 | 幻红分诊面无 transcript | 追认——`evidence/v2m-02-t1/` 仅终形分诊(v17-first-run-triage.txt 亲读:1 ABSENT + 0 MISMATCH + EXEMPT 30 + FAIL 1,与申报一致);`%@` bug 期红面确无独立留证;过程证据缺口注记级 |
| N4 | 位置洞防护活体覆盖落空 | 追认——三多参活体全 EXEMPT 本路亲证;设计行为非放水 |

## 九、红线族两波合并抽验(本路亲跑,`git diff 7b252db1..08f9ebc4`)

- 全部 `*.metal` 零 diff ✓;`LightamerIOP/` 全域零 diff ✓;`LightamerSidecar.swift`
  零 diff ✓;封存面(ExportFormatSpec/ImageIOEncoders/WebPEncoder/ExportQueueContract/
  DrtRecord/GradeCatalog/History)**全零 diff** ✓。
- `Project.swift` 全窗 = 恰一行(`ExportPresetTests.swift` 登记;dependencies 块零
  diff、零新 SPM)✓;BUNDLE-MAP 恰 APP 4 行登记 ✓(AIMaskPatchFlowTests 波 1 已在册,
  T3 只加法不触清单)。
- `*.xcstrings` 全窗 **136+/0-** 纯插入(T1 17 行 + T5 119 行)✓;`zh-audit --check`
  (V17 新门)PASS + `--self-test` PASS 本路亲跑 ✓。
- UserDefaults:唯一新键 `export.presets`(storageKey 唯一拼写 :227 + 唯一 set 点
  :306;两波窗 diff 内 defaults.set 唯一命中 = preset store)✓;AGENTS 登记(V17 门 /
  PATCH-LIVEPLANE / EXPORT-PRESET-01 / RELEASE-DIRECT-INJECT / 全套终值五节)亲读在位 ✓。
- `\.runModal(` App/Sources 零命中 ✓;`String.LocalizationValue("` 插值禁形唯一命中 =
  LightamerApp.swift:2069 **doc comment** 注记字面(豁免锚,与申报一致)✓。
- 工作树 untracked 全 `.work/` 文档域(含两路 ACCEPTANCE local-only 惯例)✓;构建
  `caffeinate -dis` 包裹、单测走 test-direct ✓;T2 走查批零 commit 零源码 diff ✓。

## 十、commit 清单(5 commits,执行链 `2ba1d1fe..08f9ebc4` 亲验)

| commit | 内容 | 本路判定 |
|---|---|---|
| `2ba1d1fe` | T1 V17 门扩展 + 活体清偿 | 成立(§二,含独立 fixture 四边界) |
| `4914619c` | T3 PATCH-LIVEPLANE | 成立(§三,双写窗口不存在亲证 + 判别力亲证) |
| `4ca893cb` | T4 RELEASE-DIRECT-INJECT | 成立(§五) |
| `de786663` | T5 EXPORT-PRESET-01 | 成立(§四) |
| `08f9ebc4` | T6 收口文档 | 与全套亲跑实测逐位一致 |

## 十一、结论

**PASS / 0 error + 0 minor(+2 验收自产注记 N5/N6)**。全套独立复跑 3857/35/0 exit 0
三方逐位闭合(App 窗外 crash 三轮 1 次复现,环境型归因加强);V17 门四边界独立 fixture
亲证(位置参数键名 = 假红安全方向)+ 独立发现 N5(`String(localized:defaultValue:)`
+ 位置占位形态为断言面外盲区,现状零活跃缺陷面);T3 armed 双写窗口不存在亲证 + N6
孤儿 bake 文件缝观察项;T5 持久化/apply/round-trip 全链成立;**D-6 严格独立复现成立**
(6 图项目空态卡不一致态 + AG spin 栈 1233/1233 亲采 + AX 恶化佐证,error 级定级独立
表态成立,复现配方可执行性亲证);D-4 裁决追认成立;偏差四项 + 第一路 4 注记全部追认;
红线族两波合并全零;执行方与第一路报告无虚报。**放行**:账面翻新(TODO/GOAL-STATE)
交闭环批统一执行;D-6/D-7/D-8 转修复批入口;波 1 屏面证据四项义务延续至 D-6 修复后
走查批。证据(截图/sample/fixture/log)在 `/tmp/v2m02-2nd/`(即弃域,关键判定已转录
本报告)。不 push(按派发令)。

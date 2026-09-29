# M2-3-FIXES-SUMMARY — 缺陷 A/B 修复专项(2026-09-30)

> 执行 = ZCode 调试修复 worker(方法:先复现再修 / 根因修复 / 修复带回归)。
> 缺陷档案 = `.work/gui-acceptance/m2-3/MANIFEST.md` 真缺陷 A/B 节。
> 修复 commit:`cba3456`(fix import)+ `5b3c62e`(fix editor)。未 push。

## 缺陷 A(M2-2 域)— 导入完成态永不发布

### 根因
`LibraryProjectController.runImport` 的 progressHandler 写成
`await MainActor.run { self?.importProgress = snapshot }`——**每次进度发射都同步阻塞
ImportService actor,直到主线程 drain 该 hop**(actor↔主线程相互等待的结构性依赖)。
完成发布链上任何一次 main-executor job 丢失唤醒,actor 即永挂于该 await:
`importFolder` 永不返回 → 尾语句(`importProgress = nil`)永不执行 → bar 永挂。
与走查证据逐项吻合:零 import 栈帧、0% CPU(挂起 Task 无栈帧)、DB 行全落+FTS 建全
(actor 自主推进的部分全完成)、**取消点击可干净收尾(主线程事件活跃时 hop 被 drain,
actor 踢活)**。

### 复现记录(诚实账)
- 单测(XCTest)环境:**不复现**(4 种形态:直接 MainActor 驱动 / GUI 启动期探针 /
  两段式非空项目二次导入 / 12s 安静期空闲 run loop,全部 PASS)——悬挂是环境形态
  (空闲 run loop 的 main-executor 唤醒丢失),XCTest 的主线程驱动不触发。
- GUI 级探针 `-la_import_probe <sourceFolder>`(DEBUG,LightamerApp):真 NSApp
  事件循环内走生产 createProject + runImport,报完成发布 PASS/FAIL。修复前后均 PASS
  (同上,环境性不复现)——探针保留为 GUI 级回归工具。
- 根因定性证据 = 走查 sample(续延悬挂形态)+ 取消可踢活的观察 + 机制分析;修复 =
  结构性切断该依赖,任何 hop 丢失形态都不再影响完成发布。

### 修复(cba3456)
handler 改 fire-and-forget:`Task { @MainActor in self?.importProgress = snapshot }`——
actor 循环与完成发布永不等主线程 drain;main queue FIFO 保持快照顺序(ImportTaskAdapter
的 monotonic clamp 仍在,双保险)。**Core `ImportService.emit` 零改动**(无 Core 越界)。

### 回归
`ImportCompletionRegressionTests`(App 层,单测可 import):
1. `testRunImportPublishesCompletion` — GUI 同构 MainActor 驱动全链,断言完成发布
   (importProgress==nil + 无 error + 6 行落库)。
2. `testFireAndForgetHandlerPreservesSnapshotOrder` — 64 快照经 fire-and-forget 投递
   顺序保持。

## 缺陷 B(M2-3-3 域)— 编辑器加载图片失败(视口空白)

### 根因
**渲染腿钥匙上的鸡生蛋死锁。** 编辑器 GUI 链
(`EditorWorkspaceShellView.loadCurrentImage`)把 `pipeCoordinator.detectionMetal()`
传入 `EditorState.load` 的 metal 参数,而 `PipeCoordinator.metal` **只在
`pipeCoordinator.load()` 内部赋值**——首次编辑器加载恒读到 nil,`EditorState.load` 的
`if let metal` 静默跳过整条渲染腿(metal nil = 无 GPU 合法形态,按设计不报错)。
context 只能经「永远不会发生的那次调用」到达 → decode 成功、视口永久空白。
与走查证据吻合:无 decode 呈现(无 displayTexture)、节点头 EXIF 正常读取(数据源是
行不是渲染)、调整栈/示波器空(伴生)、图库缩略图正常(缩略图腿不经此链)。
**直连探针(`-la_sidecar_probe`,显式传根 metalContext)一直能渲染**——缺陷只在 GUI 链
首次加载暴露,M2-3-3 单测/构建走查级验收未覆盖。

### 复现与定位(GUI 级探针 `-la_editor_probe <sourceFolder>`,DEBUG,WorkspaceHostView)
代码级等价「双击行」:createProject → runImport(link) → 等库面 →
`openCurrent + workspace.openEditor(imageID:)`(onOpen 闭包原样)→ 逐行观测
loaded/rendered。修复前:**全部可解码行 loaded=yes rendered=NO**(decode 成功、
displayTexture 30s 不来);`PipeCoordinator.load` 入口插桩(保留,info 级)证实
load 从未被进入。

### 修复(5b3c62e)
- `PipeCoordinator.attach(metal:)` 新面:组合根启动时注入**同一个** app 级
  MetalContext(单 context / 单 command queue 纪律 D-L031 保持);`detectionMetal()`
  在任何 load 前即非 nil。`load()` 内的赋值保留(同实例刷新)。
- LightamerApp 装配点:editorState.attach 相邻处 `pipeCoordinator.attach(metal: metalContext)`。

### 回归
`EditorMetalLegRegressionTests`(3 条):
1. `testDetectionMetalIsNilBeforeAttachment` — 缺陷形态钉为文档。
2. `testAttachMetalMakesDetectionFaceNonNil` — attach 面返回同实例。
3. `testEditorChainRenderLegRunsThroughDetectionFace` — **GUI 链精确取值流**
   (metal 经 detectionMetal() 解析,不经测试持有引用):渲染腿必须推 displayTexture。
   修复前该取值流读 nil,此测试红;修复后绿。

### GUI 级验证(修复后)
`-la_editor_probe`:DSC00012.ARW / DSC09991.ARW(真实 Sony ARW,.lra 恢复路径)
**loaded=yes rendered=yes**;corrupt.ARW typed decode error(预期降级)。
管道日志:`pipe load entered → sidecar restore → rendering preview bucket=1840 →
renderPreview returned` 全链贯通。

## 验证汇总

| 面 | 结果 |
|---|---|
| 回归测试(新增 2 类) | 5/5 绿(Import 2 + EditorMetalLeg 3) |
| 受影响域定向轮(10 族) | 69/69 绿(ImportService 10 / BackgroundTaskRegistry 9 / BeforeAfter 5 / PipeCache 10 / EDRViewport 5 / CropOverlay 7 / EditorMetalLeg 3 / ImportCompletion 2 / WorkspaceRouting 11 / ScopeReduce 7) |
| GUI 探针终验(HEAD) | import probe PASS×2(两段式);editor probe 两真实 ARW rendered=yes |
| **全套基线(orchestrator 批准后跑)** | **2165 / 14skip / 0 fail(756.7s)EXIT=0** = 既有基线 2160 + 新增回归 5,精确吻合;全程 RSS 监视 >8G 即杀口径,峰值 3.73G / free ≥72%,零杀 |

### 全套 flake 记录(在案域,非本改动面)

第 1 轮全套于 `LayerE2ERoundTripTests.testRealRAWRoundTripThroughHistoryAndSidecar`
启动即宿主 SIGTRAP(exit 133,1739 case 后)——**M2-2-2 SUMMARY 在案同测试同形态**
(「第 1 轮启动即 SIGTRAP(host exit 133)…GOAL-STATE 在案『相邻域负载型 flaky 留观
Phase 15』」),隔离复跑 ×3 全绿(2.26s 级稳定),第 2 轮全套 0 fail 入账。该测试不经
Library 域,与本批两修复无涉(attach(metal:) 为 opt-in 新 API,runImport handler 不在
其调用链)。

## 工具登记(DEBUG-only,随修复入库)

- `-la_import_probe <sourceFolder>`(LightamerApp):GUI 形态导入完成发布探针
  (两段式:二次导入进非空项目;12s 安静期;stderr + oslog 双通道)。
- `-la_editor_probe <sourceFolder>`(WorkspaceHostView):GUI 链编辑器加载探针
  (逐行 loaded/rendered + 直调 pipeCoordinator.load 的分叉诊断)。
- `PipeCoordinator.load` 入口/关键步 info 日志(4 行/load,诊断价值保留)。

## 边界与登记

- Core 零改动(缺陷 A 的 `withWriteBatch` internal 先例未触及,无需登记 Core 越界)。
- `legacyBody` 零 diff(全部改动在 gate=false 面 + Core 无涉)。
- 走查 MANIFEST 的「节点头 EXIF 错位(行 1 显示 DSC00012 值)」经探针复核为**行序认知差**:
  rows[0](id=1)= DSC00012,其 EXIF(focal=0, 1/20s, ISO 800)与节点头显示值一致——
  元数据源未错位;走查记录以「行 1 = DSC09991」为预期,实为排序面(keyset id 序)。
  渲染腿修复后 EXIF 头与加载图严格同源(currentRow 同一行 id)。
- 未 push(任务书红线)。

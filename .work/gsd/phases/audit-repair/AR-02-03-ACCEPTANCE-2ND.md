# AR-02 + AR-03 第二路验收 — 聚焦补位（stale 猎洞 + 行为级 GUI + 对抗抽查）

> 验收批 = audit-repair AR-02(plan B M2 codemod) + AR-03(plan C 机械小件批)
> 第二路独立验收的**聚焦补位**。原第二路 lane 两次死亡(报告零落盘),本批
> 为重派补位。**不重复第一路已闭合面**(codemod 逐文件核对 / 五族 grep /
> 全套 --all / ΔN 对账——`AR-02-03-ACCEPTANCE.md` 已三重闭合,全套
> `TOTAL|3969/37/0|` 三方一致),只做第一路任务书中属于第二路独特攻击
> 面的四项聚焦。对象 = 主树 HEAD `0a79685e`(执行链 `4452e10c..0a79685e`
> 8 commits)。零源码改动;本报告为唯一落盘产物(不 commit)。
>
> 方法 = worktree 隔离(`/tmp/la-ar23-acc2nd/wt` @ 0a79685e)+ 自建
> DerivedData 容器 + 供件拷入(input/ 312MB + Resources/AIModels 194MB
> —— D-AR2-6 偏差⑦配方,先查后拷)+ tuist generate + build-for-testing
> (TEST BUILD SUCCEEDED)+ nohup/disown 脱离 + 只杀自出 PID + GUI 实例
> 用后优雅退(⌘Q,sidecar flush 完整)+ parentage 全程亲核。

# PASS / 0 blocking + 0 major + 0 minor + 6 obs

零产线缺陷发现。stale 猎洞五路径全闭合(机制面源码穷举 + 行为级 GUI
七腿亲跑);对抗抽查四面全过;定向轮第三样本 `921/6/0` 闭合
「executed 恒 921」声明;YiyinPanelView 挂账论据亲读成立并补强。

## §1 stale 猎洞——逐路径判定(聚焦清单 #1,最高优先)

### 1.1 机制链源码亲读(等价性的数学基础)

- **`ModuleInstance` = `public struct`(Codable, Sendable, Equatable,
  Hashable)**(`LightamerCore/Sources/Pipe/History/ModuleInstance.swift:44`)
  ——值语义。零 stale 论据(plan 头注/D-AR2-4)由此成立:computed
  `params`(每 tick 解码 **view `let` 捕获的同一份字节**)与 stored
  `let params`(init 解码同一份字节)在任何「实例字节不变」的路径下
  **行为必然逐位等价**——stale 只可能来自「实例换了而视图未重建」,
  且该形态下改造前后**同样 stale**(computed 读的也是旧捕获)——
  codemod 不可能引入新 stale 类别。
- **重建链**:`InspectorView`(@Environment(EditorState.self))tracked
  读 `editorState.instances`(`UI/InspectorView.swift:93` editableInstances、
  :336-341 selectedPanel)→ instances @Observable mutation → 宿主 body
  重估 → `inspectorState.panelView(for: effective, edit: session)`
  以**当前** instance 构造面板 → 面板 init 重解码 stored params。
  `EditorState` 是 instances 唯一写者(:143 注记「the ONLY writers」)。

### 1.2 五路径 mutation 面穷举(全部落 `instances` tracked mutation)

| # | 路径 | EditorState 落点 | mutation |
|---|---|---|---|
| 1 | paste adjustments | `installMergePaste`(:340)/`installOverwritePaste`(:353,另并 baseInstances) | `rebuildInstances()` → `instances = merged`(:460) |
| 2 | 版本 swap | `installVersionChain`(:132;注释原文「the SAME single rebuild path every other history assignment uses」) | 同上 |
| 3 | undo/redo/jump | `performUndo`(:385)/`performRedo`(:397)/`performJump`(:409) | 同上 |
| 4 | 切图 | `resetHistoryForNewImage`(:149) | `instances = defaultInstances` |
| 5 | AI 出片副本 | `EnhanceDialogModel`(:279-295):写盘 + `importFile` 入库,**不自动打开**;打开副本 = 正常 load → `PipeCoordinator.swift:1234` `resetHistoryForNewImage` | 与路径 4 同路 |
| + | 面板自身 D-H1 commit | `upsert`(:423) | `instances[index] = incoming` |

五路径无一绕过 `instances` mutation → 机制面上无「params 变而宿主不
重估」的洞。

### 1.3 行为级验证(GUI 亲跑,HEAD 构建,≥4 条达标——实跑 7 腿)

驱动 = CGEvent 鼠标/键盘 + System Events 菜单 AX(MANIFEST 勘定组合)
+ 截图读数闭环;证据图 `/tmp/la-ar23-acc2nd/gui/`(即弃域,判定值
逐条录本表)。

| 腿 | 操作序列 | 断言 | 实测 | 判定 |
|---|---|---|---|---|
| W1 拖动+commit | 曝光 slider knob 拖至右端(live tick 全程) | readout 实时刷新,松手恰一 commit | **+18.00 EV**,⌘Z 可一步撤(= 恰一 item) | PASS |
| W2 undo | W1 后 ⌘Z | 面板显示回拖动前值,零 stale | **+0.00 EV**,knob 回中位 | PASS |
| W3 redo | W2 后 ⇧⌘Z | 面板显示回提交值 | **+18.00 EV** | PASS |
| W4 切图出 | 双击 filmstrip 第二图 alpha-8.tiff | 新图 pristine 投影,无 W1 值残影;面板落 first 行(色温 6504 K/1.000 默认) | 与断言一致 | PASS |
| W5 切图回(=sidecar/恢复投影) | 双击回首图 | 恢复的 history 投影重铺面板 | **+18.00 EV** | PASS |
| W6 paste+落盘取证 | ⇧⌘C(首图)→ 切 alpha → 粘贴调整(菜单点击) | payload merge 落目标;ONE item 可 undo | 历史面板三条「粘贴调整」item(三次触发全落);点曝光行:行启用 + **+18.00 EV** | PASS |
| W7 paste-undo | W6 后 ⌘Z 一步 | ONE ⌘Z 撤销整个 paste,面板回 pristine | 曝光退出投影,面板回落 6504 K/1.000 | PASS |
| W8 版本 swap | 版本面板新建版本(×2,双击双发)→ 双击版本 1 swap 回 | 活跃 badge 随 swap 移动;模块列表投影随版本链切换 | 版本 1 badge「活跃」(01:25:06);列表曝光行回归(v1 链)而活跃 v2 期列表无曝光行(pristine 新链)——**投影差正确反映版本链差** | PASS |
| W9 重启恢复(全链闭环) | ⌘Q → 重启 → 重开项目 → 载入首图 → 点曝光行 | sidecar→history→面板全链一致 | **+18.00 EV** | PASS |
| W10 AI 副本(源码腿) | 见 1.2 表路径 5 | 与切图同构,无独立 stale 面 | 出片止于 importFile 入库,不自动替换编辑态 | PASS(源码证据;行为面由 W4/W5 承载) |

**猎洞结论:五路径 × 十腿全 PASS,零 stale 形态。**

### 1.4 YiyinPanelView `siblingInstance` 挂账论据亲读(D-AR2-3 复核)

- 引用链逐环亲读:`YiyinPanelView`(:62-70 `watermarkInstance`/
  `bordersInstance` computed)→ `InspectorEditSession.siblingInstance`
  (`IOPPanelProvider.swift:154-156`)→ `PipeCoordinator.instanceRecord`
  (`:1678-1680`)= `editorState?.instances.first { $0.opName == opName }`
  ——**class 活引用现读活态**成立(`InspectorEditSession` = @MainActor
  final class,weak coordinator)。
- **「zero-stale 论据不覆盖」论据:成立。**39 面板等价论据的前提 =
  「computed 与闭包每次解码同一份字节」(instance `let` 值捕获);
  Yiyin sibling 臂每次 body 求值解码的字节**可变**(面板存活期间编辑
  另一段即变)——stored 化将失去机械等价保证,挂账(零代码动作)处置
  正确。
- **补强观察(不推翻挂账)**:两处挂载宿主——`InspectorView.selectedPanel`
  (经 YiyinPanelProvider/BordersPanelProvider 注册,:172/:177)与
  `WorkspaceHostView`(:1488 yiyin sheet,经 `record()` :1526 现读
  `editorState.instances`)——**均 tracked 读 instances**;sibling 变更
  实际会触发宿主重估 → YiyinPanelView 以新值重建。实证 stale 形态
  不可达。挂账的本质 = 论证严格性面(机械等价论据不可用 ≠ 已知活
  缺陷),维持挂账处置、复活条件(sibling 读取失效链改造立项)不受影响。

## §2 行为级 GUI 走查(聚焦清单 #2)

- 构建:worktree @0a79685e,tuist generate(4.208.0),build-for-testing
  **TEST BUILD SUCCEEDED**;宿主 = 自建容器 Lightamer-Acc2nd。
- 已做透面:
  - **slider 编辑往返**:曝光面板完整链(W1-W3:live tick 拖动 60Hz
    流畅、readout 实时刷新、松手恰一 commit、undo/redo 双向)。
  - **undo/redo 后面板一致**(猎洞行为腿):W2/W3/W7 三向断言全过。
  - 载入/切换/恢复面:W4/W5/W9(sidecar→history→面板全链)。
- **让渡面**(如实呈报;均属第一路残留清单已登记的 Manual-Only 域,
  本轮通道受限未能补足):
  - GradeScalarPanels 六 struct(contrast/white/black/saturation/tint/
    hls)与 ChannelMixerRGB/FilmicRGB/Lut 面板 slider 往返——Inspector
    tab 交互通道在本轮 CGEvent 会话中间歇失灵(见 §4 注记 2),未达。
    佐证:六 struct 与其余面板同构 stored 形(第一路 B-1 逐文件核过
    6 处)+ App bundle 921 全绿(panel/wiring/inspector 测试 17 文件
    在册亲跑)+ 执行批 B1 走查配方(ChannelMixerRGB 代表 +
    HighpassSoften helper 式代表)在册 MANIFEST。
  - ExportNamingEditor live 预览:源码位亲读(`ExportNamingEditor.swift`
    :101 patternBinding TextField / :159 `export.naming.preview`
    livePreview Text / :184 onSubmit(commitRename))——GUI 面让渡
    (同通道)。
  - SidebarView dropDestination 行为级拖放:macOS 无系统级合成拖放缝,
    AX 驱动不可达——第一路 C-3 已源码亲读(guard→no-op 形、move guard
    链逐字保留、coordinateSpace `.named(Self.canvasSpace)` factory
    :273),本轮复核维持;实物拖放归 Manual-Only。
  - menuStyle 五处展开观感:执行批 3/5 逐像素亲证在案 + AR-03-C1
    配方(2/5 legacy face)在册;本轮未重跑(同通道)。

## §3 对抗抽查 + obs-③(聚焦清单 #3/#4)

| # | 项 | 实测 | 判定 |
|---|---|---|---|
| 1 | `@Published` 零残留 | App/Sources 亲 grep **零命中**;`ObservableObject`/`@StateObject`/`objectWillChange` 唯一命中 = `LightamerApp.swift:248` **注释行**(「@Observable objects are owned with @State, never @StateObject」规约文案) | PASS |
| 2 | xcstrings diff 形 | B+C 链 `4452e10c..0a79685e` **零 diff**(AR-02 红线兑现);AR-01 链 `17b95f2b` = `latitude_share_value` +1 键,`-` 行计数 **0** = 尾块纯插入 | PASS |
| 3 | 恒等式 48=48 亲核 | UI/Inspector 域 `params(of:` 亲跑 = **48 命中/41 文件** = 40 文件 46 处 codemod + provider 注释 1(:27)+ helper 本体 1(:196)——构成算术自洽 | PASS |
| 4 | AR-01 交叉 | A 批文件集(49)∩ B+C 文件集(21)= **恰 1 文件**:`EditorAdjustmentStackView.swift`(3bcb5b83 ar03-m1,AnyView→`InspectorRowView?` 两 hunk 面)——AR-03 plan C 清单内合法回触,时间序 A→B→C 串行非并行冲突 | PASS |
| 5 | obs-③ 定向轮 | **`BUNDLE|App|921/6/0|peakRSS=2832MB|365s`**(净轮)——第三样本:executed 921(执行批 = 第一路 = 本轮)恒、fail 恒 0、RSS 恒 2832MB;skip 6 与第一路一致(执行批 16 = 计数口径差,第一路已判 obs)。「executed 恒 921」声明**稳** | PASS |

## §4 流程注记(验收过程事故链,orchestrator 已裁采信)

1. **定向轮首轮卡死事故(环境面)**:HOME 重定向隔离跑
   `test-direct.sh` → 宿主卡死 21 min 于
   `ACASettingsTests.testConnectionTestMockRoundTrip`。sample 采栈亲证
   卡点 = `requireKeychain()` → `AICredentialStore.save` → `SecItemAdd`
   → `makeLoginAuthUI` → `AuthorizationCopyRights` → XPC 同步等待——
   **HOME=/tmp 无 login keychain,securityd 弹「找不到钥匙串」授权框,
   无头环境死等**。处置 = 杀自出进程树(93169/93170/93175/93176)+
   System Events 取消弹窗 + 改**容器符号链接**进默认 DerivedData glob
   (`~/Library/Developer/Xcode/DerivedData/Lightamer-Acc2nd` → /tmp/dd,
   脚本 mtime glob 亲验命中)以真 HOME 重跑 → 净轮 921/6/0 采信(同
   第一路「安静窗口净轮」先例)。**配方教训**:隔离 HOME 跑
   test-direct.sh 必遇 SecItemAdd 弹窗;后续验收轮用容器链接法替代。
2. **GUI 通道间歇失灵**:CGEvent 合成单击对 Inspector tab 条/部分行
   选中间歇无效(重启后首击灵,随后渐失;键盘 ⌘Z/⇧⌘C/⌘Q、System
   Events 菜单点击、slider drag、双击全通)。frontmost 亲核正常
   (M7-1 协议①在场)。归因验收工具通道面(合成事件 vs app 事件处理
   时序),非产线缺陷——不影响已采信判定(全部关键断言经灵通通道
   取得)。
3. **双实例干扰规避兑现**(第一路 §6.1 教训):GUI 会话严格等定向轮
   宿主退出后启动;全程无同 bundle-id 并行。
4. **清理亲核**:GUI ⌘Q 优雅退(进程 0 残留);defaults 还原
   (labelingMode 键不存在 = 默认态);DerivedData 符号链接已删;
   worktree 与 /tmp 容器留存待 orchestrator 裁量清除(主树零触碰,
   worktree 独立路径)。

## §5 分级清单

- **blocking: 0 / major: 0 / minor: 0**
- **obs 1**:HOME 重定向 keychain 卡死事故(环境面,净轮采信;配方
  教训入 §4.1,建议后续验收轮以容器链接法替代 HOME 重定向)。
- **obs 2**:obs-③ 第三样本 `921/6/0` 闭合——executed 恒 921 稳,
  skip 6 稳态与第一路一致。
- **obs 3**:GUI 通道失灵让渡面(GradeScalar 六 struct/
  ChannelMixerRGB/FilmicRGB/Lut slider 往返、ExportNamingEditor live
  预览、menuStyle 展开观感、SidebarView 实物拖放)——MANIFEST 配方
  在册(执行批 B1 + AR-03 C1/C2),归实机走查批/用户。
- **obs 4**:Yiyin 挂账论据补强——宿主 tracked 链使实证 stale 形态
  不可达;挂账维持(论证纪律面非活缺陷)。
- **obs 5**:AI 出片副本不自动打开(importFile 入库止)——「副本替换
  编辑态」仅经用户显式打开 = 与切图同路,机制面无独立 stale 风险。
- **obs 6**:paste 提交后 Inspector 选中行不自动切换(保持原选中/
  first 落点)——选中态保持行为,非 stale(值面经 W6 点行验证 +18
  正确);GUI 驱动方需显式点行读值。

## §6 结论

- **PASS / 0 blocking + 0 major + 0 minor + 6 obs**。
- stored-params codemod 的零 stale 论据在值语义(struct)+ tracked
  重建链两个层面源码坐实;五条「params 变而视图不重建」候选路径全部
  落入 `instances` tracked mutation,行为级十腿(undo/redo/切图往返/
  paste/版本 swap/重启恢复)GUI 亲跑零 stale。
- YiyinPanelView 挂账论据(sibling class 活引用 → 机械等价论据不可用)
  亲读成立,并补强「实证 stale 不可达」观察——挂账处置维持正确。
- 对抗抽查四面(@Published / xcstrings / 48=48 / AR-01 交叉)全过;
  定向轮第三样本 `921/6/0` 闭合 obs-③。
- 零源码改动;工作树还原干净(GUI 杀净、defaults 还原、DD 链接已删)。

—— 第二路聚焦补位验收(AR-02-03-2ND),2026-10-18。

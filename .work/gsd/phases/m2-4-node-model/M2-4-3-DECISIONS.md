# M2-4-3-DECISIONS — 执行期裁定与 KD 执行确认（plan M2-4-3）

> 执行批：2026-09-30。全部为机械随动或语义澄清，无行为越界；晨审可推翻
> （各条附翻转代价）。plan 正本 = 同目录 `M2-4-3-PLAN.md`（checker 修正版
> `c94aa3c`）。

## KD 执行确认

- **KD-1（命中测试/拖拽几何）按 plan 落地**：`ZStack { Canvas 连线层(仅画线,
  `.allowsHitTesting(false)`); 卡片层(真 SwiftUI 视图, `.position` 布局) }`，
  零手写 hit-test；几何正本 = `NodeCanvasGeometry` 纯函数（App 文件零 UI
  依赖，单测直调）；常量集中文件头（cardWidth 196 / cardHeight 64 /
  endpointHeight 44 / verticalSpacing 18 / 上下 inset 16）。
- **KD-2（模型三分）按 plan 落地**：投影订阅 + 选中写 `selectedLayerID`
  （仲裁点单源）+ 命令路由（`EditorState.apply` 薄转发）；模型唯一自有状态 =
  `selectedNodeID` 高亮；mix = live/commit 腿（`applyLiveLayer` 零 history +
  `commitLayerEdit` 恰一条 `history_graph_mix`），`SetMix` 命令仍经
  `NodeGraphCommand` 保留，数学等价锚 = M2-4-1 AC2（mix 0 ≡ bypass 像素级）。
- **KD-3（卡信息面/交互表）按 plan 落地**：三类卡 + 菜单四项 + 删除拦截
  （locked 卡 action 集为空 = 无 Delete 项）+ 锁形点击 toast
  （`node_lock_develop`/`node_lock_drt`）；穷举纪律双钉（视图 switch 与
  `availableActions` 均零 default）。
- **KD-4（收口三件）按 plan 落地**：zh-audit exit 0；REQUIREMENTS 仅翻
  M2NODE 族；`M2-4-ACCEPTANCE.md` phase 级汇总表落盘。

## 执行期裁定（D-M2-4-3-1..8）

### D-M2-4-3-1 document = computed 投影（替代 plan 草图的 stored + 手动重建）

KD-2 草图 `private(set) var document: PipelineDocument?` 注记「stack 变更时
重建」。实现取 computed 属性直读被观测的 `editorState.layerStack`：视图 body
经 `model.document` 读取即注册 Observation 依赖，stack 变更自动重推导——
「每次重建」语义满足得更强（per-read 纯派生，零 staleness 结构性成立，零手动
同步点），消费面（`model.document`）与草图一致。与 M2-4-1 PipelineDocument
「纯派生零存储」纪律同构。
**翻转代价**：改 stored + onChange 钩子，一行属性 + 一处钩子；行为等价。

### D-M2-4-3-2 insertionIndex 边界集 = 相邻 grade 中点 + 末卡-DRT 中点

T1 首版只有 grade 内部中点，末段（最后一张卡以下）无法解析到
`grades.count`（阈值矩阵测试当场红）。终版边界集 = N 条：N-1 条相邻 grade
中点 + 1 条末 grade-DRT 端点中点——线性链恒以 DRT 端点收尾，拖出下界自然
钳到顶位。随附语义钉死：**拖在卡上 = 该卡自身槽位**（自己拖到自己 = no-op
位置，`reconnectGrade` 拒发由视图短路）。测试矩阵（2/3 grade + 0/1 grade
退化面）随裁定同批改写。
**翻转代价**：一行边界 append + 测试矩阵两行——但「末段不可达顶位」是缺陷
非选项，本裁定不预期翻转。

### D-M2-4-3-3 Fit 按钮 v1 语义 = scroll 重置到链头

D-M2-4-CONTEXT-5 裁「Fit 恒定」+ v1 无自由缩放（Deferred）——恒定 auto-fit
下 Fit 按钮无 zoom 态可复位。落地语义 = 重申 fit（ScrollViewReader 滚回链头
锚点 + 0.15s 动画），marker `editor.nodes.fit`，M2NODE-06「Fit」字面交付。
**翻转代价**：自由缩放激活时改绑 zoom 态复位，一处 Button action。

### D-M2-4-3-4 BENCH 测试提前随 T1 落盘（plan 排在 T2）

30 节点 layout 计时测试与几何断言同文件同 commit（T1）落盘——文件级归属与
plan 一致（NodeCanvasGeometryTests），仅任务时点提前；plan T2 AC「BENCH|
行落 SUMMARY」满足时点不变（SUMMARY 本批记录 0.0081 ms/round）。
**翻转代价**：无（时点记录问题）。

### D-M2-4-3-5 AC3 渲染几何机检 = preference 读回（真实 layout 系统测量）

plan 给了「预览快照断言或 marker 几何读回」双选。落地 =
`NodeCardFramesKey` PreferenceKey：每卡 `.background(GeometryReader)` 在
canvas 命名空间上报帧（`.position` 之前挂，解析时折叠 position 变换）；
测试把**真面板**（真 EditorState/LayerEditingState 实例）装进 NSHostingView，
pump runloop 收 preference，逐卡帧与 `NodeCanvasGeometry.layout` 断言相等
（accuracy 0.01）。这是**经真实 SwiftUI layout 系统的测量**——渲染帧 =
纯函数 layout 的因果链被端到端钉死，非源码镜像自证。生产成本 ≈ 0（无观察者
的 preference 不参与 reduce）；未来 overlay 功能可复用同面。
**翻转代价**：改截图比对 = 维护成本高企；不预期翻转。

### D-M2-4-3-6 锁定三件套泛化签名 + 选中面在 trio 之外（M2-7 复用接口）

`.nodeLocked(_ locked: Bool, hint: @escaping () -> Void) -> some View`——
零节点语义；三件套 = `NodeLockedBadge`（marker `editor.nodes.locked`）+
内容 hit-test 拦截（locked 时内部控件全死）+ badge 点击 hint 回调。
**语义冻结（M2-7 首组锁按此消费）**：可见锁形标记 / 交互禁用 / 提示回调
三合一；签名演化 = additive 参数（plan 风险节预案）。**选中/navigation
在 trio 之外挂接**（contentShape + onTapGesture 后置）——锁定卡可导航不可
编辑（D-M2-4-CONTEXT-7：develop 点选 = 全局链），编辑类手势（拖/菜单/滑杆）
或被 trio 拦截或被 action 集清空结构性排除。
**翻转代价**：M2-7 需要锁定卡可编辑内部子集时，加 `intercept:` 参数收窄
allowsHitTesting 域；语义三件不变。

### D-M2-4-3-7 报备计数笔误勘误（22/2239 → 实际 23/2240）

全套终跑报备口径按「T1 一次建齐 20 例」申报 22 新增；实际 T2 渲染读回
+1、T3 补组 +2 均并入既有两文件，累计 = 23（NodeCanvasGeometryTests 9 +
NodesPanelModelTests 14）。实跑 TOTAL|2240/14/0 精确对账；BUNDLE-MAP 几何行
内计数 8→9 勘误 + 注记随收口 commit（登记纪律 = 行值与文件终值一致）。
**翻转代价**：无（记录勘误）。

### D-M2-4-3-8 PipelineLinkageTests 断言 KEY 化（M2-4-2 验收 finding③ 联动）

zh catalog 补 `editor_node_develop`/`editor_node_drt` zh 值的同批，把
`displayTitle` develop/drt 分支两处英文字面量断言改为同式
`String(localized:)` KEY 对照（与 M2-4-2 D-2 既有 nil 分支写法同构）——
任意 locale 下与渲染同解析，比字面量更强。改动 = LAYERS bundle 测试文件
两处断言 + 注释。
**翻转代价**：zh 宿主跑测时字面量断言会红——本裁定是 finding③ 钦定的
必改项，不预期翻转。

## 执行期观察（不属本 plan diff 面）

- **mix 滑杆 Slider 在 64pt 卡内的 controlSize(.mini)**：手感（拖拽响应/
  与卡拖动手势的并行识别）= Manual-Only 走查项，挂 ACCEPTANCE 观察清单；
  不达标调 `minimumDistance` 常数或滑杆 controlSize（几何纯函数参数，非
  选型问题）。
- **锁定 toast 4s 自动清窗与连续 hint**：`EditorState.presentToast` 重入
  重置计时（既有语义），面板侧未做去抖——连点锁 badge 只会刷新文案，无
  堆积风险；记录备查。

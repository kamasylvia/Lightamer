# Plan 06-05 决策记录

## D-06-05-C0-1: GeometryPointMapper.stableHash 的 liquify 网格折带有界采样

- **裁决**：mapper 稳定哈希对 `.liquify(DisplacementField)` 段折叠 **维度/origin/maxMagnitude + ≤256 cell 的定步长采样**，不逐 cell 哈希。
- **理由**：逐 cell 折叠每次 composite 对百万级网格（2560×1707 ≈ 4.4M cell × 8B）做 FNV 会吃掉帧预算；任何 liquify 参数变化都会移动数千 cell，步长采样 + maxMagnitude 的碰撞概率在「不同参数状态」粒度上可忽略。
- **Reversibility**: reversible——发现真实碰撞案例后可换全量哈希（API 不变）。

## D-06-05-C0-2: HistoryHash 层锚点补折 mask（格式窗口期收紧）

- **裁决**：层感知 drift 锚点在 identity/props/chain 之外补折 `MaskSpec.stableHash()`。
- **理由**：06-01 锚点漏 mask 内容——mask 篡改/编辑不触发 drift。现在收紧的窗口依据：**尚无任何生产文档携带层栈**（coordinator 的层持久化是本轮 06-05 才接通），锚点公式无兼容包袱；一旦有真实用户文档，此公式即冻结。
- **Reversibility**: irreversible after first user document ships——本轮为最后窗口。

## D-06-05-T1-1: mask chip 快照策略 = 矢量示意图（GPU 低清快照延后）

- **裁决**：层行 mask chip 用 Canvas 矢量示意图（brush 折线/椭圆轮廓/渐变带/path 轮廓；parametric/raster 显示字形；空 = 暗框），不做蒙版平面 GPU 读回缩略。
- **理由**：① 零 GPU 读回 = 零 L014 fence 负担、笔画实时更新无异步调度；② chip 的信息目的是「这层有没有蒙版 + 大致形状」，矢量示意完全覆盖；③ GPU 快照需要每笔画结束触发光栅化 + 读回 + 下采样管线（约一天工作量 + 异步生命周期），收益仅是像素级保真。
- **Reversibility**: reversible——后续可换真快照，chip 视图单点替换。

## D-06-05-T1-2: mergeDown 落 base 的 commit 形态 = 结构项 + 逐记录 N 项（dt 形态）

- **裁决**：合并到下层调整层 = 恰 1 个 stackSnapshot 结构项（验收「每类恰 1 commit」钉此情形）；**最底层调整层并入 base** = 1 结构项 + 每条并入记录各 1 个 layerScope=nil 项（N+1）。
- **理由**：全局实例集的投影规则（effectiveInstances）只认 layerScope=nil 的 snapshot 项——并入全局的记录必须各占一项才能在 undo/redo 中正确重建（dt 同形态：apply 历史逐项入栈）。把 N 条记录塞进一个 item 需要 HistoryItem/侧车加字段（违背冻结前缀最小变更原则）。
- **Reversibility**: reversible——若后续要求严格 1 commit，加 additive optional 字段即可迁移。

## D-06-05-T1-3: 层内几何豁免面 = 驱动拒绝集 ∪ {crop, enlargecanvas, liquify}（UI 隐藏）

- **裁决**：层模块列表/添加菜单隐藏 lens(13)/ashift(15)/flip(16)/clipping(17) 之外再加 crop(24.5)、enlargecanvas(16.5)、liquify(18.0)。驱动 fatalError 拒绝集维持 06-1 原集不变（13/15/16/17）。
- **理由**：三者的 `modifyROIOut` 都会改变层输出 ROI，破坏「层子 run 终 ROI == 合成窗口」的跨层不变量（composite precondition 直接触发）——UI 隐藏是唯一安全的层；驱动拒绝集扩大属 6-7 签核轮的数据面决策（D-06-01-T4-1 的遗留问题就此回答：**应入集**，随 6-7 收口）。
- **Reversibility**: reversible（v2 泛化论证后放开）。

## D-06-05-T2-1: 层参数编辑走 InspectorEditSession 的 layerScope 注入（24 面板零改动兑现）

- **裁决**：面板不感知 scope——`InspectorView` 构造 `InspectorEditSession(coordinator:layerScope:)`，session 内部把 D-H1 三件套路由到 `setLiveParams(_:layerID:)`/`commitContinuousEdit(label:layerScope:)`；结构型层操作（增删/重排/属性/mask）走 EditorState 独立 API。
- **理由**：scope 是会话级路由概念不是面板概念；注入点在面板工厂的调用侧，24 个既有面板签名零改动（本轮全量回归 764/0fail 实证）。
- **Reversibility**: reversible。

## D-06-05-T3-1: 视口手势仲裁 = LayerEditingState 单点 if/else-if 链

- **裁决**：`viewportRoute(liquifyPanelSelected:)` 返回 maskEditing > liquify > crop 三态，EditorAreaView 依此挂载唯一 overlay；06-6 的「液化面板选中即拥有视口」规则收编为机器的中间分支。
- **理由**：互斥不变量（同时恰一 overlay）由穷举分支结构保证，单测可钉（LayerUIWiringTests.testEditingStateMutexRoutes）；避免 06-6 的散点布尔（liquifyActive）继续生长。
- **Reversibility**: reversible（新工具 = 新分支/新优先级）。

## D-06-05-T3-2: 蒙版手势 = form 在 press 时即以真实 UUID 入 mask（live 腿按 id 突变）

- **裁决**：press 即把新 form append 进层 mask（真实 UUID），后续 tick 按 id 突变（`mutateForm`）；drag end 恰一次结构提交；**无变化的纯点按不产生 history item**（dirty 门）。
- **理由**：草稿影子状态（draft + 提交时合入）会让「live 渲染」与「最终 form id」分叉（group 项引用 formID），press-即安装让 maskVersion 哈希驱动整条 06-3 增量链路零特例。
- **Reversibility**: reversible。

## D-06-05-T5-1: FULL 政策 benchmark 结论 = 维持「冷层不缓存」（fullColdLayer）

- **裁决**：**维持 fullColdLayer，不回退 fullCacheAll**（D-06-CONTEXT-8 的回退决策点就此关闭）。
- **数据**（Debug 口径，×3-5 修 Release；`.work/06/perf.md` 同账）：
  - 10 层稳态拖动（2560 PREVIEW，层 K tick/帧）：**median 15.6–16.4ms < 16.6ms 60fps 预算**（Debug 已达标，Release 更快）——交互不落 FULL 路径。
  - FULL fit（无窗）cold=16-17ms vs window cold=4-5ms：窗口化 ~4× 收益。
  - 窗口化账本：coldLayer 166.7MB vs cacheAll 280MB（+68%，合成小图下差距已显著）。
  - cacheAll 的 0ms 帧只在「全工作集存活」时出现；100MP FULL = 1.63GB/层 × N，5 层 8.2GB 必破 D-C2 4GB 预算 → enforcement 反向抖动驱逐，等效劣化回冷层。
- **Reversibility**: reversible（策略常量；benchmark 脚本常驻 `LayerDragPerfTests`，未来复测一处跑全）。

## D-06-05-T6-1: 侧车层记录写「live 有效链」+ 读「document 记录 ⊕ history items」重建

- **裁决**：写出侧 document 的层链 = live 栈的当前链（结构快照 ⊕ layerScope 项合并后的有效态）；读入侧 install document 记录为 live 栈 + history（含 layerScope 项）原样恢复，undo/redo 由 rebuildLayerStack 重推导。
- **理由**：rebuild-from-history 不变量在双轨（结构 snapshot + 参数项）模型下要求「写时冻结有效态、读时按位置重投影」；live 链恰是有效态，零额外投影。
- **Reversibility**: reversible（侧车拼写不变，语义只在读写两端）。

## 遗留（非阻塞）

- **GUI-17**：显示蒙版 toggle（circle.dashed）在部分会话不可见（AX 与渲染同时缺失，构建含修复仍复现一次）——overlay 请求路径已由 row-tap 驱动验证；人工复验挂 FINDINGS Manual-Only。
- **cmd-drag 调 brush size**（C1 手势）viewport 层未实现——参数环面板可调，等效能力；挂账 6-7 前补。
- gradient 两端手柄/ellipse/path 手柄的细粒度手感：数据腿 + kernel 已由单测钉住，viewport 手势待人工复验（FINDINGS Manual-Only）。

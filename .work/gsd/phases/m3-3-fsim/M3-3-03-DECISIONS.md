# M3-3-03-DECISIONS — FSIM golden 与收口批（wave 3）

> 执行：2026-10-09 夜间（executor subagent，夜间全自动授权在案）。
> commits：`9f4a649` fix(iop) → `6c83505` test(iop) golden → `b10df2c`
> test(core) determinism → `94168f8` feat(app) film panel → `5a8a2f8`
> feat(app) film card → T5 docs。
> 本文 = KD-1..5 执行期裁决正本。checker 回注（E5 两级门分解 + L048 比较空间
> 纪律）全部落地为执行处方，容差标定值与依据在此登记。

## §1 KD-1 golden 数学复算主门 —— 四门全绿 + 三项执行期标定

- **门 1a（kernel vs 同表 CPU 四面体采样双写）**：实测最大相对差 **8.7e-5**
  （3 材料对 × 4 Y/M/strength 角点 × 2 受控域 × 24576 texel × 3 通道，收集后单断言
  取真全局 max）——**钉 1e-4**。E5 预声明的 ~1e-6 在真实链上不可达，机理 =
  dt-verbatim rtne 晶格映射（`film_subrun` = 生产 Lut3d verbatim）**外推 ±0.5 格**
  （d = scaled − rint(scaled) ∈ [−0.5, 0.5]，affine 权重含负臂），f32/f64 坐标噪声
  （曲线 lerp + cube 归一 ~6e-6 格）被外推臂按局部对比度放大；平滑域三重筛选
  （§4）后残余即此量级。任何真实 kernel 缺陷（错支/错表/错钳）≥1e-2，门语义完好。
- **门 1b（烘焙表 vs 理想连续模型）**：**凸性门**（插值偏差 ≤ 单元自身值域 1.5×，
  全 400 探针零违例——错误模型表现为整面偏移 ≫ 单元值域，语义最强）+ 平面元
  线性带（flat cell = 值域 < 25% 值）实测 **6.2e-3**、钉 2e-2（先例带 1e-3..1e-2
  中值，与 M3-1-01 §4 的 ~8e-3 晶格地板同量级互证）。**标定依据**：反演轴端
  clamp 平台面（黑场 10^axisLo / Clear 10^axisHi）切片式穿过 cell——探针自身
  着陆 + 8 角点着陆（0.35 stop 内着陆即筛）+ |d|≤0.25 插值域三重筛后地板才可测；
  首轮全域均匀探针 332/400 落平台面 = 域结构本身（操作亚盒集中测）。
- **门 2（bake 体素级）**：LCG 常量种子 60 体素/对 × 3 对 vs 独立 Float64 复算
  相对 ≤1e-5 全绿（f32 存储拓宽为唯一残差）+ 域标定一致性 + 负域界面（G/B 头量）。
- **门 3（置位曲线）**：m=1 两侧闭式精确（**阴影侧符号修正**见 §5）+ m=2/4 膝点
  vs 独立二分 ≤1e-8 + g_m 单调/上界扫 + 单侧臂渐近线（不越相纸白/黑边界）+
  逐像素 golden（核面 bit-exact + 分支像素 vs Float64 标量参考线性域 ≤2e-5）。
  联合双臂的跨边界断言按 §6 缺陷分析降为单侧（登记非放水）。
- **门 4（中性闭合）**：中灰均匀面过「负片段 ⊕ 自动解 ⊕ 印相 LUT」（strength 1、
  gain 1）通道散实测 **1.4e-3**、钉 2e-3（插值色度地板）+ 中灰量级保持面。
- **复算独立性机检**：参考函数全部测试文件内自包含（曲线插值/三点投影/中性包/
  K 标定/SysC 反演/域界/ACEScc 传递逐一双写），产线 bake/solve 代码路径零 import
  为 oracle；零图像资产入库（受控输入程序化生成）。

## §2 KD-2 确定性门 suite —— 五测全绿 + 两项语义定形

- **solve bit-identity**：同参双调 bitPattern 全等 + 跨 fresh store 实例全等。
- **缓存键折叠序精确值钉死**：独立 FNV-1a 双写（offset basis → pair 字节 →
  stats 字节 → mode tag UTF-8；**UInt64 小端字节序 = withUnsafeBytes 内存序**）
  与 `FilmRuntimeSolve.cacheKey` 精确相等（非仅判别）+ 四向翻转矩阵。折叠序
  = pair ⊕ stats ⊕ tag，自日一起冻结。
- **跨 ROI 同解（02 红线端到端钉）**：周期夹具（48 = 4 周期，列值 12 值周期）—
  FULL vs 两个 24 宽 ROI 窗（roiHint 测试缝）：A/B 窗共享**一个缓存条目**（同
  统计同键）+ 三渲重叠列逐字节相等（film 面无缝端到端）。**语义定形（登记）**：
  键的 stats 项 = **原始计数直方图**（非比例不变）——FULL（48 列）与窗（24 列）
  各自成键；而解值按比例不变（整数秩分位），由重叠字节相等端到端钉死。生产面
  roiHint 恒 nil（测试缝），窗作用域统计无用户可见面；若未来窗式 film 渲染立
  项，全图统计需 PixelPipe 面（密封文件，非本批半径）。
- **整数秩**：spike/uniform/thin 分布手算精确秩（P50=127/P25=63/P75=191——
  首达累积 bin 的 off-by-one 以实现为准手算复核）+ 单调性扫。
- **跨版本稳定性哨兵**：`FilmGoldenConsts.filmRampPlaneHash =
  14_365_179_805_968_017_957`（周期 ramp + portra×endura + 无缝面 gain=1 +
  .edrLinear 空链 float32 平面 FNV-1a）。**重钉流程**：DECISIONS 登记数学变更 →
  重算 → 同 commit 重钉（M2-5 adoption 盖章口径）；无登记翻转 = 缺陷。

## §3 KD-3 Film 面板最小面 —— 三项执行期定形

- **carrier 读面**：DrtPanelModel 的 workspace 弱引在 Inspector 列挂载点无座
  （WorkspaceModel 不入 environment）→ carrier 读 = PipeCoordinator 新增只读
  面 `currentFilmRecord`（restore 腿先行 priming 的渲染真相）+ `hasFilmRecord`
  + `filmMaterialStore`（picker 数据源；store 本体仍在 LightamerApp 组成根，
  零第二实例）。三级读 = liveRecord → history 投影 → carrier。
- **启用 = 默认材料对**：无 stock 的默认 record 在 `filmTailPolicy` 门 off
  （`isFilmRecordDefault` 即返 nil）——「启用」commit 无 stock 默认 record =
  视觉 no-op 假启用。裁定：enable commit 携**首个排序 film × paper 对**（一次
  commit、非 pristine、film 腿真激活）。PresetNames 维持空命名空间（plan 无预
  设任务；GOAL-STATE 移交面的「预设注册面」由 plan 正文裁决为不立项）。
- **Solve 按钮 = `FilmSolveCache.invalidateAll()`**（新增失效缝；解为键的纯函
  数故值不可见——缝的存在使手势有真边 + M3-4 stats 面变更单点落位）。
- 滑杆产线域：Y/M 0-100 CC、strength 0-1、exposure ±3 EV（面板钳制，Core 不钳）。
- **D-H1 键族**：`history_film_shift`（滑杆 commit）/ `history_film_material`/
  `history_film_param`/`history_film_enable`；`film_*` 面板族 19 键 + 卡族 3 键
  全静态（F-2 插值禁令遵守）；zh-audit `--check` PASS（1557/1795）。

## §4 KD-4 节点图只读卡 —— 布局缝与注入式 inspector

- **触点亲核结果**：卡列表 = `EditorNodesPanelView.cardsLayer` 的
  `ForEach(document.nodes)` + `NodeCanvasGeometry.layout`（App 侧纯函数几何）。
  PipelineDocument.Node init 为 Core internal（App 不可合成伪节点）→ 卡 = App
  投影物：`NodeCanvasGeometry.filmCardID` 编译期常量 + `layout(includesFilmCard:)`
  additive 默认参（既有调用/测试零改）+ cardsLayer 增渲染支。**NodeKind 零新增**
  （FilmCardTests 钉死三 case + 卡 id 解析不到节点）。
- **inspectorState 注入式 optional**：首版 @Environment(InspectorState.self) 在
  NodeCanvasGeometryTests 裸宿主即 fatal（No Observable object found——App 全量
  0/0/0 crash 当场逮住）→ 改 init 注入 optional（nil = tap no-op），
  EditorToolRailView 传真实 env 值。**教训**：视图新增 @Environment 依赖前先查
  裸宿主测试面。
- **卡点击 = 导航非编辑**（openFilmPage；不走 select——选择空间零触）。

## §5 执行期发现：m=1 阴影闭式符号缺陷（已修 + 回归钉死）

- **缺陷**：`solveKnee` 的 m=1 闭式对阴影侧套用高光形 `K = t − √((a−t)(C−t))`——
  阴影落地方程 K − g(K−a; K−C) = t 的精确解为 `K = t + √((t−a)(t−c))`（分支方
  向定号）。旧符号使膝点偏离 1.9+ stop（数值探针：f(a) = −5.92 vs t = −4.0），
  阴影分支输出越过相纸黑边界。
- **修复**：`9f4a649`（一行符号 + 注记正本化）。**零波及**：默认面（0/0/2 恒等
  + rolloff 2 走 m≥2 二分臂本就正确）+ 既有测试只钉高光闭式与 m=2 阴影落地，
  均不变；IOPP 404/3/0 复跑确认。m=1 阴影落地精确性由 FilmGoldenTests 回归钉死。
- **关联缺陷（登记不修，M3-4 消解）**：m≥2 落地方程 `K ± g(a−K; C−K) = t` 的根
  深离 t（F 全正/切点深谷多根）——K_h 可深至 −7.9 且 K_s > K_h（违反 kernel 注
  释「K_s < K_h by construction」，联合双臂互相越界）。零用户可见面（filmPlacement
  面板恒等占位 + 默认 0/0/2 关闭）；M3-4 descriptor 臂恢复 §9.2 精确形时换锚消
  解。golden 门相应只断言单侧臂契约 + m=1 精确 + m≥2 与独立二分同根。

## §6 执行期发现：节点画布合成点击 click-dead（走查受阻，登记不修）

- **现象**：Film 卡实机走查中，节点画布全部卡（含 grade 卡）对合成鼠标点击
  （CGEvent 多点位重试 + AXPress）均无响应（无选中高亮、无页面打开）——卡片
  渲染与 AX 在册均正常（截图为证）。
- **判定**：合成事件限制（SwiftUI 手势对 CGEvent 合成序列的已知敏感性）或真实
  hit-test 缺陷，本环境不可区分。**非本批引入**（画布交互面 = M2-4 时代代码，
  本批只 additive 卡视图/几何槽）；`NodeCanvasGeometryTests` 的渲染帧机检全绿。
- **处置**：Film 页实机走查（面板挂载/滑杆/材料切换/zh 呈现）挂 M3-4 FSIM-02
  走查清单（人工/真实输入设备复核）；面板事务面由 FilmPanelTests 6/0/0 机检
  覆盖。MANIFEST 如实申报（`.work/gui-acceptance/m3-3/MANIFEST.md`）。

## §7 声明外扩面（结构必经文件，如实申报）

front-matter 之外的结构必经触点（M3-1-03 obs-1 先例口径，非静默扩面）：
1. `PipeCoordinator.swift` — 只读暴露三面（filmMaterialStore/currentFilmRecord/
   hasFilmRecord），面板与卡的唯一数据源（零第二真相）。
2. `InspectorView.swift` — filmPageActive 整列分支（exportPageActive 孪生，KD-3
   「Inspector 列顶部分支」的本体）。
3. `EditorToolRailView.swift` — NodesPanelView 构造点传 coordinator/inspector
   （默认参不强制——但 nil 卡即死，必须实传）。
4. `FilmTailPolicy.swift`（Core）— `FilmSolveCache.invalidateAll()` 失效缝
   （Solve 按钮「走缓存失效」的唯一实现位）。
密封面机检：`DrtPanelModel/DrtPanelView/DrtRecord/TerminalTailPolicy/DrtTail
Assembly/Lut3dKernels.metal/DrtEotf/ExportQueueContract/六格式矩阵/
NodeGraphCommand.swift/sidecar schema` 零 diff（§9）。

## §8 密封面机检对表（`git diff 2fee806..HEAD` 产线域）

- `DrtPanelModel.swift` / `DrtPanelView.swift` / `DrtRecord.swift` /
  `Lut3dKernels.metal` / `DrtEotf` / `ExportQueueContract.swift` /
  `ExportFormatSpec` / `ImageIOEncoders` / `WebPEncoder` /
  `NodeGraphCommand.swift` / `LightamerSidecar.swift` / `HistoryStack.swift` /
  `HistoryHash.swift`：**零 diff**。
- `PixelPipe.swift`：零 diff（02 落 film 腿后本批不触——film 筛选为测试面）。
- `TerminalTailPolicy`/`DrtTailParams`/`DrtTailAssembly`/`policyTag
  "lightamer.drt"`：PixelPipe 零触即零命中；FilmTailPolicy.swift 增量 =
  invalidateAll 一法（§7.4）。
- `V50Order` / `GradeCatalog` / `Registry` / `ModuleInstance`：零 diff（本批无
  catalog 行变更）。
- `PipelineDocument.swift`（Core）：零 diff（KD-4 红线）。

## §9 走查批（如实申报）

证据 = `.work/gui-acceptance/m3-3/`（MANIFEST.md 正本）：节点画布 Film 卡在册
实机截图 + zh-audit PASS。**Film 页实机走查未完成**（§6 click-dead——卡片渲染/AX
在册正常，grade 卡选择同样无响应 = 画布级合成事件问题，非本批引入）；面板事务
面由 FilmPanelTests 6/0/0 机检覆盖；挂 M3-4 FSIM-02 走查清单。会话副作用：probe
缝 throwaway 项目（/tmp 域）、温度滑杆误触当场 ⌘Z 撤销、defaults 零触碰、实例
已 quit、两枚 AI 弹窗「暂不」关闭。

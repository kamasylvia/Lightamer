---
phase: m2-7
plan: "M2-7-1"
title: "数据与内核——Radial 双羽化 additive（Alcedo 线性带公式 + 旧档 border 回落零漂移，M2MASK-01）+ LinearGradient 映射换算钉（M2MASK-02）+ mask 级属性内核（item feather + 应用序 feather→invert→opacity→clamp + facade 扩展含嵌套寻址，M2MASK-04）+ sidecar 载体（deletionProtected/contentRevision capture/restore，D-M2-4-1-3 兑现）+ contentRevision 写点终表（提交腿五处，checker E3/E5）+ 校验原语 + D-M2-4-2-5 stroke 腿 sibling 修复同批（M2MASK-07/03）+ Follow Edges Metal kernel 新件（边缘图派生缓存 + 切向流线 walker + 熔断 fallback，M2MASK-05）"
wave: 1
depends_on: ["M2-6"]
autonomous: true
requirements: [M2MASK-01, M2MASK-02, M2MASK-03, M2MASK-04, M2MASK-05, M2MASK-07]
files_modified:
  - LightamerCore/Sources/Layers/Masks/MaskSpec.swift            # 修改（全 additive）：EllipseForm 增 innerFeather/outerFeather（Float?）；MaskGroupItem 增 feather（Float?）；MaskSpec 增 contentRevision（Int?，nil=0）+ 单一 bump 助手；访问面扩展 setItemFeather/setItemInverted/setItemOpacity + 嵌套 child 递归寻址 + resolvedOuterFeather mode-aware 读约定（checker E7）
  - LightamerCore/Sources/Metal/MaskRasterKernels.metal          # 修改：ellipse 增 Alcedo 线性带腿（uniform 旗标分流；既有 border 二次羽化腿逐字节保留）
  - LightamerCore/Sources/Layers/Masks/DrawnMaskRasterizer.swift # 修改：uniforms 打包增 form2 槽（innerFeather/outerFeather/modeFlag/pad，nil 零值传旧腿）
  - LightamerCore/Sources/Layers/Masks/MaskCombiner.swift        # 修改：drawnGroupPlane 条目级 feather 腿（reduce 前 blur，feather>0.1 门）——应用序 = feather→invert→opacity→clamp 钉死；既有五式公式/enabled 过滤零 diff
  - LightamerCore/Sources/Layers/Masks/FollowEdges.swift         # 新建：FollowEdgesParams + 切向流线 walker（纯 Swift 可单测）+ 边缘图请求类型；输出 = BrushStroke 点链（复用既有 stamping，rasterizer 零改）
  - LightamerCore/Sources/Metal/MaskEdgeKernels.metal            # 新建：mask_edge_map（亮度 Sobel 幅值 + 阈值边缘图；单 PSO 零 function constant 先例）
  - LightamerCore/Sources/Layers/Masks/MaskGradientDefaults.swift # 新建：compression_default 常量单源（KD-2 显式落点文件，checker E4——Core glob 免登记）
  - LightamerCore/Sources/Pipe/PipeCacheKey.swift                # 修改（checker E4/E2 申报）：edgeMapPosition = **-4** 常量 + edgeMapKey 静态键函数 + layerTier 一行 additive 分支（edgeMap → .maskPlane 档）——additive 例外详见纪律 5
  - LightamerCore/Sources/Sidecar/SidecarLayerStack.swift        # 修改：SidecarMaskSpec 增 deletionProtected/contentRevision capture/restore 各一行（D-M2-4-1-3 正解原文）
  - App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift       # 修改（D-M2-4-2-5 同批 + checker E5）：appendForm/mutateForm 改 `var spec = layer.mask ?? MaskSpec(); spec.drawn = drawn` 保 sibling payload（parametric/raster/deletionProtected/contentRevision 不再丢失）+ bump 重挂提交腿（endInteraction 提交前恰一次；live 腿零 bump）
  - App/Sources/Lightamer/State/AIMaskEditing.swift              # 修改：install 提交前 revision bump + install 前 expectedRevision 校验原语消费（失配 = 拒装 + 既有 typed error 面）
  - App/Sources/Lightamer/State/LayerEditingState.swift          # 修改：MaskCommand fill/duplicateAndInvert 提交值 revision bump（checker E3 终表；duplicate/resetEdits/clear 零 bump）+ 防御性校验 pin
  - Project.swift                                                # 修改：新建测试文件登记对应 bundle sources 显式清单（bundle 无 glob，漏登 = 文件不进构建；checker E2）
  - Tests/LightamerTests/MaskFeatherAlignTests.swift             # 新建（**LightamerTestsLayers**，Core 级 kernel golden）：双羽化两腿 CPU float64 参考 parity + nil 旧档逐位零漂移 + 回落次序 + gradient 换算对照
  - Tests/LightamerTests/MaskItemSemanticsTests.swift            # 扩展（既有文件）：setItemFeather/Inverted/Opacity + 嵌套 child 寻址 + revision bump 助手
  - Tests/LightamerTests/MaskRevisionTests.swift                 # 新建（**LightamerTestsApp**，App 级——写点经 overlay/AI/命令实态）：写点终表 bump（提交腿五处 + 三命令零 delta）+ 校验原语 + AI install 失配拒装
  - Tests/LightamerTests/FollowEdgesTests.swift                  # 新建（**LightamerTestsLayers**，Core 级）：合成边缘场 walker golden（直边/转角/噪声）+ 熔断降级路径
  - Tests/LightamerTests/SidecarV5Tests.swift                    # 扩展：deletionProtected/contentRevision 双向 capture/restore 断言翻面（既有「缺口钉」断言改真）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 修改（checker E4）：三新测试文件登记行（纪律 6 实路径申报）
  - .work/gsd/phases/m2-7-masks/M2-7-1-SUMMARY.md                # 新建（收口任务）
  - .work/gsd/phases/m2-7-masks/M2-7-1-DECISIONS.md              # 新建（收口任务）
  - .work/GOAL-STATE.md                                          # 续接点追加（收口任务）
  - .work/LESSONS.md                                             # 如踩坑
---

# Plan M2-7-1 — 数据与内核（双羽化 + 参数映射 + mask 级属性 + sidecar 载体 + revision/乐观并发 + Follow Edges）

> **性质**：数据与内核 plan——`MaskSpec` 全 additive 扩展、raster/combine kernel 缺口腿、
> sidecar 载体补缺、revision/乐观并发数据面、Follow Edges 新件。UI 面零触碰（面板/手柄/
> 设置 = P2 地盘；本 plan 只落 P2 消费的 Core facade 与内核语义）。规格锚点 =
> D-M2-7-CONTEXT-1..12（全部按推荐 A 生效，不得重开）+ `research/ALCEDO-FEATURE-MAP.md`
> §4 + REQUIREMENTS M2MASK-01/02/03/04/05/07。
>
> **本 plan 是 P2/P3 的缝正本**：双羽化公式与回落次序（P2 手柄交互的语义底）、
> mask 级属性 facade（P2 面板读写门）、`contentRevision` 写点终表与校验原语（P2 接线的
> 数据面）、Follow Edges walker（P3 质量验证的对象）——语义在此定死，后续只消费不重开。
>
> **两条挂账本 plan 兑现**（M2-4 DECISIONS 钦定同批复核）：D-M2-4-1-3
> （`SidecarMaskSpec` 缺 `deletionProtected` 文件载体）+ D-M2-4-2-5（overlay
> `appendForm/mutateForm` 以 `MaskSpec(drawn:)` 重建丢 sibling payload）。

## 已定裁决（不得重开）

- **D-M2-7-CONTEXT-1（OQ-1 A）**：Radial/LinearGradient 走**映射复用 + 真缺口
  additive**——`EllipseForm` 全字段映射，唯一真缺口 inner/outer 双羽化 =
  `EllipseForm` 增 `innerFeather/outerFeather: Float?`（nil = 回落既有单 `border`）；
  Linear gradient：anchor↔origin、rotationDegrees↔normal 角度、compression↔
  transition_distance（换算式本 plan 钉）；curvature/sigmoidal 为超集收「高级」。
- **D-M2-7-CONTEXT-2（OQ-2 A）**：Phase 6 stamping brush 为数据正本；Alcedo
  `brush_stroke.cpp` 9 文件仅交互参考。M2MASK-03 对齐落点收敛到 revision/乐观并发
  （本 plan T5）+ mask 级属性（T3/T4）。
- **D-M2-7-CONTEXT-4（OQ-4 A）**：Follow Edges = 自研 Metal edge-aware kernel——
  per-image 边缘图一次预计算入缓存 + 笔刷 stamp 沿边缘切向流线追踪；复杂度熔断条款 =
  降级「边缘吸附」+ 完整流线挂账 V2（如实登记）。
- **D-M2-7-CONTEXT-9（OQ-9 A）**：`MaskSpec` additive `contentRevision: Int?`
  （nil=0）+ 每内容写点单调 +1 + 异步生产者 seam 乐观校验 + **D-M2-4-2-5 同批修**。
  revision 是并发防护计数非缓存键（`stableHash` 仍是失效正解）。
  **写点枚举勘误（checker E3/E5，勘误注记见 CONTEXT）**：OQ-9 原文「stroke
  append/form mutate/AI 烤贝/clear-fill 逐写点 +1」收窄为「bump 只挂 history
  提交腿五处」（append/mutate = live 腿零 bump；duplicate/resetEdits/clear 无
  bump 载体）——以本 plan KD-3 终表为准。
- **D-M2-7-CONTEXT-10（OQ-10 A）**：`SidecarMaskSpec` 补 `deletionProtected`
  capture/restore 各一行 + SidecarV5Tests 双向断言（D-M2-4-1-3 挂账正解原文）。
- **D-M2-7-CONTEXT-11（OQ-11 A）**：既有 stamping 0.744ms/千枚 golden 不动；新增
  预算项 = Follow Edges 边缘图（per-image 一次预计算随缓存失效）；观察项（手柄拖动
  实时性等）挂 P3 走查。
- **D-M2-7-CONTEXT-12（OQ-12 A）**：新 UI 键随手 `String(localized:)`，zh 滞后允许，
  P3 收口对账（本 plan 内核面预计 <5 键）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 Radial 双羽化 = 双公式腿 additive，nil 旧档逐位零漂移

**Alcedo 参考公式**（`alcedo_studio/src/edit/mask/grade_mask_coverage.cpp:150-153`
实测，GPL 只读参考）：

```
rho   = sqrt(rx² + ry²)                     // 归一化椭圆半径（边缘 = 1）
inner = max(0, 1 - inner_feather)
outer = 1 + max(0, outer_feather)
value = 1 - clamp((rho - inner) / max(outer - inner, ε), 0, 1)   // 线性带
```

- **腿分流（checker E7 钉死读约定）**：`MaskRasterKernels.metal` ellipse 段增 mode
  旗标（uniform form2.z）——**谓词 = 双 nil → 既有腿逐字节保留**（
  `f = clamp((k−e)/border), value = f²`，outer = radius·(1+border)）；**任一非 nil →
  Alcedo 线性带腿**（腿内 `innerFeather nil→0`、`outerFeather nil→0` 补缺后求值；
  腿内 0 = 显式值非缺省——**双 0 显式 = Alcedo 腿硬边输出，不回落旧腿**）。
  **回落次序（CONTEXT OQ-1 悬决回填）**：双值任一非 nil 即接管，`border` 届时忽略；
  双 nil → 旧 border 语义。读约定单源（**mode-aware**，checker E7）：facade
  `resolvedOuterFeather = outerFeather ?? (innerFeather != nil ? 0 : border)`——
  Alcedo 腿活跃时缺 outer 补 0、旧腿时回落 border（P2 面板显示面消费同一表达式，
  禁止第二实现；「`outerFeather ?? border`」非 mode-aware 旧表述作废）。
- **零漂移机理**：新字段 synthesized encodeIfPresent——nil 时 canonical JSON 缺席，
  `stableHash()` 字节与 v4/v5 档逐位相同（SidecarV5Tests 既有 nil 零漂移断言族
  机械扩展一行）。**旧档渲染零漂移由 golden 钉**：同一 EllipseForm（无新字段）在
  改造前后 plane 逐位相等（既有 06-03 analytic golden 复跑即证）。
- **uniform 布局**：`MaskRasterUniforms` 增 `form2: SIMDFloat4`（innerFeather,
  outerFeather, modeFlag, pad）——additive 槽尾追加，既有 form0/form1 偏移不动；
  DrawnMaskRasterizer 打包处 nil → (0,0,0,0) 走旧腿。
- **精度门**：两腿各配 CPU float64 参考（Swift 参考实现入测试文件，06-03/06-04
  golden 先例），GPU vs 参考 ≤1e-6（解析门族既有带）；线性带腿另钉 Alcedo
  coverage 公式的三个采样锚点（inner 带内 = 1、带中点 = 0.5±1e-6、outer 带外 = 0）。

### KD-2 LinearGradient = 零新字段映射，换算式 plan 期钉死

- **字段映射全表**（CONTEXT 发现 4 已清点，本 plan golden 钉）：
  | Alcedo | Lightamer 既有 | 关系 |
  |---|---|---|
  | origin 0.5/0.5 | `anchor: MaskPoint` | 直映射（归一化同空间） |
  | normal (0,1) | `rotationDegrees`（dt 符号约定 deg2rad(−rotation)） | normal 角 = atan2(nx, ny)；rotation 0 ⇔ normal (0,1)——**执行时以 golden 采样对验证符号** |
  | transition_distance 0.2 | `compression`（≥0.001，profile 宽度） | **换算式 = P1 悬决回填**：读 `MaskRasterKernels.metal` gradient 段 profile 式 + Alcedo `grade_mask_coverage.cpp` Linear 覆盖式，导出 `compression_default` 使过渡带宽等价 Alcedo 0.2 参考空间；golden 两档（0.2 档 + 1.0 档）采样对照钉 |
  | start 1 → end 0 | dt 渐变固定方向 | 既有语义内含（anchor 侧 1 → 远端 0），golden 锚点验证 |
  | —（Alcedo 无） | `curvature`/`state(.sigmoidal)` | 超集，P2 UI 收「高级」折叠；本 plan 只保数据面不动 |
- **交付物**：零 schema 改动；`MaskFeatherAlignTests` gradient 组 = 换算式 golden
  （Alcedo 默认参数档 ⇔ 我方 compression_default 档 plane 采样逐点 ≤1e-6）+
  换算式推导过程入 DECISIONS（含两侧公式行号引证）。P2 面板默认值消费
  `MaskGradientDefaults.compressionDefault`（本 plan 落 Core 常量单源）。

### KD-3 mask 级属性内核 = item feather 腿 + 应用序钉死 + facade 补齐

- **应用序（M2MASK-04 钦定 = feather→invert→opacity→clamp）现状核查结论**：
  invert→opacity→clamp 已在 combine reduce 条目内核成立（`MaskCombiner`
  `max(0, opacity·(±1 − s))` 语义 + `max(0, min(1, opacity))` 钳制）；
  **缺的是 mask 级（item 级）feather**——`MaskGroupItem` 增 `feather: Float?`
  （nil = 无附加羽化），执行点 = `drawnGroupPlane` 内、reduce 装配前对条目平面
  跑既有 Deriche `blur(sigma:)`（门 = feather > 0.1，dt blend.c:306 阈值同款）。
  表单羽化（ellipse border/path border/brush hardness）已在 rasterizer 内嵌 =
  「source feather」第一段；item feather 为第二段；两者都先于 invert。
  **本条序以一个非空转探针测试钉死**（06-04「序 pin 非空转探针」先例：调换两腿
  顺序输出必变的构造）。
- **facade 扩展（M2-4-2 访问面同款纪律：值语义、miss 静默 no-op、无第二存储）**：
  `setItemFeather`/`setItemInverted`/`setItemOpacity` 三 setter + **嵌套 child
  递归寻址补齐**（M2-4-2 明文归本 phase）——`mutateTopLevelItem` 升级为深度优先
  递归 walk（child 链逐层搜 formID，首中即改；重复 id = 首中，头注文档化）。
  `maskItems` 读面保持 top-level 平铺不变（嵌套树的展示形态归 P2 面板投影，
  本 plan 只保证 setter 可达嵌套）。
- **MaskSpec 增 `contentRevision: Int?`（nil=0）+ 单一 bump 助手**：
  `public mutating func bumpContentRevision()`（nil→1，否则 +1，不回绕检测
  precondition）。**写点终表（CONTEXT OQ-9 悬决回填；checker E3 收窄——执行时
  复核 M2-4-2 DECISIONS 的 8 触点审计表后逐点落实，对照表入 DECISIONS）。
  bump 载体成立五处**：
  ① overlay 提交腿（`endInteraction` 提交前恰一次——append/mutate live 腿零
  bump，重挂语义见 KD-5/checker E5）② AI bake install（`AIMaskEditing`）提交前
  ③ `MaskCommand.fill`（mask 替换腿 = 内容整体重写）④
  `MaskCommand.duplicateAndInvert`（invert 变体 = 内容写）⑤ P2 面板 item 属性写
  （经 T3 setter——setter 本身不 bump，调用方 bump，见 KD-5 分工）。
  **无 bump 载体三命令（checker E3 裁决，理由入 DECISIONS）**：
  - `duplicate`：复制 = 内容搬运非内容写（新 spec = 源快照逐字节、revision 原值
    随迁；新 form 无在途异步生产者，bump 无防护收益）。
  - `resetEdits`：恢复基线 = 内容回退（revision 随恢复值回落基线态；穿越写防护
    由快照恢复语义承担——下述语义注记）。
  - `clear`：清空后 drawn 为空、无 form 可作异步生产目标——失配判据退化为
    form 存在性（mutate 型天然拒绝），revision 数值无判读意义。
  语义注记：undo/redo 快照恢复会把 revision 带回旧值——这是**期望行为**（恢复后
  在途写按旧 expected 校验失败 = 正确拒绝穿越写）；「单调」域 = 单一线性 history
  段内，头注写明。

### KD-4 sidecar 载体 = SidecarMaskSpec capture/restore 各一行，测试翻面

- `SidecarMaskSpec` 增 `deletionProtected: Bool?` + `contentRevision: Int?`
  两 Optional 字段（decodeIfPresent/encodeIfPresent synthesized 缺席式）；
  `init(_ spec: MaskSpec)` capture 与 `var spec: MaskSpec` restore 各补一行
  （D-M2-4-1-3 挂账正解原文，M2-4-1 落的 runtime/snapshot 拼写不动）。
- **SidecarV5Tests 翻面（checker M1 收窄）**：翻面仅 **`:204` 一条**——
  `testV5RoundTripCarriesAllNewFields` 内的缺口钉 `XCTAssertNil(
  mask.deletionProtected, "…lands with M2MASK-04")` 改**双向真断言**（setup 增
  `contentRevision = 7`（`:176` 的 `deletionProtected = true` setup 行随用）→
  capture→JSON→restore 逐值复原断言）。**`:111/:119/:164` 为保留的零漂移族
  不动**（`:111` nil 断言 / `:119` canonical bytes 无键断言——
  `testNilNewMaskFieldsKeepCanonicalBytesAndStableHash`；`:164` v4 档解码 nil
  断言——`testV4DocumentDecodesWithNilNewFields`）；`:135` hash 参与断言既有
  不动。version 注释节补 v5 字段清单两行（`SidecarLayerStack.swift` 头部格式
  注释块同步）。
- hash-isolation 判定：`contentRevision` **随 mask 域自然折叠**（经
  `stableHash()`——它变即缓存该失效，正确语义）；**不单独申报**进/出
  `HistoryHash`（无新判定代码，06-05 hardening 既有语义）。

### KD-5 乐观并发 = 校验原语 Core 单源 + 失配路径按生产者分派

- **校验原语（Core 纯函数，P2 接线的唯一门）**：
  ```swift
  public extension MaskSpec {
      /// Optimistic-concurrency gate (D-M2-7-CONTEXT-9): true = the
      /// caller's snapshot is current and the write may proceed.
      /// nil folds to 0 both sides (pre-M2-7 documents).
      public static func matchesExpected(
          _ expected: Int?, in current: MaskSpec
      ) -> Bool { (expected ?? 0) == (current.contentRevision ?? 0) }
  }
  ```
- **bump 腿重挂（checker E5 裁决，P2 KD-6 消费同口径）**：bump 只挂
  **history 提交腿**，live 腿零 bump——
  ① overlay：`endInteraction` 提交前 bump 恰一次（`dirty` 门既有，no-op tap
  零 bump）；`appendForm`/`mutateForm`（四形态 update* 全部经它）是 **LIVE 腿**
  （MaskOverlayHost 既有「zero history」注释），revision 数值在 live 腿恒不变；
  ② AI：install 提交前 bump；③ 命令：`fill`/`duplicateAndInvert` 提交值写入时
  bump（写点终表见 KD-3）。
  **校验次序钉死 = 提交点先校验后 bump**：`matchesExpected(expected, current)`
  相等 → bump 恰一次 → commit；失配 → 分派表（下表）。**正常笔画 = 相等路径
  恰 +1、不走重放**（MaskRevisionTests 断言钉——T5）。
  **快照时点钉（P2 消费口径，checker E5）**：expectedRevision 快照取 press 段
  写毕后的现值——常规笔画 press 段 `appendForm` 走 live 腿零 bump（快照 = N）；
  press 即「append+commit」型交互（Follow Edges tap-commit、path 节点 tap-add
  既有先例）其 bump 随 press 段提交先落，同交互后续快照取 **post-bump** 值——
  防自致失配误走重放。
- **失败路径分派表（KD 必答：重放 vs 拒绝；生产者列 = history 提交腿，checker
  E5 口径）**——单写者 @MainActor 下唯一真异步生产者 = AI bake（async Task 落点
  可与用户编辑交错）；overlay 提交腿为同步但**同表钉死**（防 undo/面板写在笔画
  中途穿插）：
  | 生产者（提交腿） | 失配动作 |
  |---|---|
  | overlay 提交腿·追加型（笔画/新 form） | **重放**：重读 live spec 重装 drawn payload（保留新 form），bump 后提交——追加型操作可无损重放 |
  | overlay 提交腿·改写型（既有 form mutate） | **拒绝**：丢弃本次变更 + 重读 live + toast（form 已不存在 = 目标消失，静默结束该 grab） |
  | AI bake install | **拒装**：typed error 沿 07 既有错误面浮出，不静默覆盖、不自动重烤（重烤决策归用户） |
  | MaskCommand（fill/duplicateAndInvert） | 单写者同步腿失配在 @MainActor 上不可达——仍走原语（防御性 pin），失配 = assert 域（debug 停、release 走拒绝+toast） |
- **D-M2-4-2-5 同批修（本 plan 兑现）**：`appendForm/mutateForm` 改
  `var spec = layer.mask ?? MaskSpec(); spec.drawn = drawn; layer.mask = spec`
  ——parametric/raster/deletionProtected/contentRevision 四 sibling 不再丢。
  修复的回归测试 = **先建带 parametric+raster+锁的层 → overlay 画一笔 → 断言
  四字段存活**（修复前该测试红，修复后绿——E4 先例「能揭穿原缺陷」口径）。
  expectedRevision 提交接线归 P2（本 plan 只落数据面 + AI/命令侧 bump/校验，
  overlay 腿的 grab→commit 快照参数在 P2 随手柄任务一并接）。

### KD-6 Follow Edges = 边缘图派生缓存 + CPU 流线 walker + 既有 stamping 复用

- **算法结构（D-M2-7-CONTEXT-4 A 落地）**：
  1. **边缘图预计算**：新 kernel `mask_edge_map`（`MaskEdgeKernels.metal`）——
     输入 = 该层 below 复合平面的亮度（采样 r 分量或 luma 加权，plan 钉 luma
     加权 0.2126/0.7152/0.0722），Sobel 幅值 → r32Float 边缘强度图 + 阈值前
     归一化；**派生缓存** = PipeCache 新 position 槽（`edgeMapPosition = -4`，
     常量名单源 PipeCacheKey；**checker E2 勘误：原拟 `-3` 撞
     `retouchPosition = -3`**——PipeCacheKey.swift:79 已被 06-07 retouch
     stroke-leg 输出槽占用，保留段位表 = composite -1 / mask -2 / retouch -3 /
     **edge map -4**；CONTEXT Specific Ideas 并无 -3 数值钉，「-3 惯例」为 plan
     起草误引，勘误注记见 CONTEXT）；键 = imageID ⊕ pipeType ⊕
     upstreamHash ⊕ roi ⊕ 算法版本常量——**随 decode（imageID）与下方复合
     内容（upstreamHash）失效，不挂 layer、不进 sidecar**（CONTEXT Specific
     Ideas 原文）；跨 grade 共享同前缀 below 平面的边缘图（键含前缀身份自然
     去重），**不是「每 grade 每次 render 重算」**。
     **tier 归类决策（checker E2，理由入 DECISIONS）**：`layerTier` 增一行
     additive 分支（`position == edgeMapPosition → .maskPlane`）——边缘图 =
     一次 Sobel pass 可重建、成本与 mask 栅格同量级，归「最便宜重建族最后逐出」
     的 maskPlane 档；不加新 tier（预算表零膨胀）。若缺此分支，-4 会按
     layerTier 既有 default 落 `.layerChainOutput`（最贵逐出档）——语义错误，
     故该分支属纪律 5 申报例外的一部分。
  2. **切向流线 walker（CPU 纯 Swift，`FollowEdges.swift`）**：输入 = 边缘图
     CPU 读回（**stroke 局部窗口**：seed 包围盒 + margin，工作分辨率长边 ≤512
     下采样——读回走 L014 fence 纪律）；从 seed 出发沿局部边缘切向（梯度旋转
     90°）双步进，每步梯度幅值加权方向修正（follow strength 参数）+ 对比阈值
     门（低于阈值即停），单侧方向参数选 ± 切向；输出 = 归一化 `MaskPoint` 链 →
     打包为 `BrushStroke`（radius/hardness/density/opacity 沿用当前笔刷参数）。
     **rasterizer/combine 零改动**——Follow Edges 的产出就是一支普通 brush
     form（appendForm 走既有腿），edge-aware 性全部在输入点链的生成。
  3. **参数面**：宽度（=brush radius 透传）、边缘对比阈值、跟随强度、单侧方向
     （±）——四参数落 `FollowEdgesParams`（Core struct，P2 UI 消费）。
- **复杂度熔断（OQ-4-C 条款，本 plan 预埋 + P3 实测裁决）**：walker 单 seed
  压测（合成边缘场 + 真实样张读回）超预算（P3 走查口径：交互延迟可感劣化）
  → 降级路径 = seed 吸附最近强边缘 + 直线 stamps（`FollowEdgesMode.snap`
  枚举分支），完整流线挂账 V2 如实登记。**枚举现在就分 `.streamline`/
  `.snap` 两 case**——熔断 = UI 默认值翻转 + walker 不删，非代码删除。
- **失败降级**：边缘图不可得（窗口越界/缓存逐出）→ walker 返回空链 →
  appendForm 不发生 + 状态条提示（P2 面）——不静默不出笔。

### KD-7 性能预算（D-M2-7-CONTEXT-11 A 落地）

- **不动**：stamping 0.744ms/千枚 golden、combine 五式 parity、既有 analytic
  golden 全保留复跑。
- **新增预算项**：① 边缘图（per imageID+upstream 态一次预计算，成本 = 一次
  Sobel pass，O(窗口像素)；缓存命中后零成本）② item feather blur（feather>0.1
  才发生，Deriche 既有成本量级）。
- **观察项（挂 P3）**：双羽化手柄拖动实时性、缩略图 pass 成本（P2 交付物）。
- 双羽化 Alcedo 腿为分支表达式级差异，不构成可测性能回归面——不设专项 bench。

## read_first

1. `.work/gsd/phases/m2-7-masks/M2-7-CONTEXT.md`——裁决正本（D1..D12 + 发现
   1..8 + Ruling 节）。
2. `LightamerCore/Sources/Layers/Masks/MaskSpec.swift`——四形态/MaskGroupItem/
   访问面 facade 实态（`:205-377`）+ `stableHash()` encodeIfPresent 语义。
3. `LightamerCore/Sources/Layers/Masks/MaskCombiner.swift`——`drawnGroupPlane`
   （enabled 过滤 `:417`、reduce 装配 `:423-433`）+ `postProcess` 门阈值 + gopacity
   契约（`:196-199`）。
4. `LightamerCore/Sources/Metal/MaskRasterKernels.metal`——ellipse 二次羽化腿
   （`:30-45,144-168`）+ gradient profile 段（KD-2 换算式推导输入）+ uniform 布局。
5. `App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift:383-406`——
   appendForm/mutateForm（D-5 缺口实态）+ endInteraction 恰 1 commit 契约。
6. `LightamerCore/Sources/Sidecar/SidecarLayerStack.swift:33-72`——
   SidecarMaskSpec capture/restore 实态 + `Tests/LightamerTests/SidecarV5Tests.swift`
   缺口钉断言行。
7. `/Volumes/UNITEK/Documents/Development/AlcedoStudio/alcedo_studio/src/edit/mask/
   grade_mask_coverage.cpp:140-160`——Radial/Linear 覆盖式参考（GPL 只读，公式
   不复制入库——只作数值参考锚）+ `src/edit/graph/color_grade_node_model.cpp:
   296-301,383-392`（revision/expected_revision 语义参考）。
8. `App/Sources/Lightamer/State/AIMaskEditing.swift` + `App/Sources/Lightamer/
   State/LayerEditingState.swift:80-89,267-323`——AI install seam 与五命令写点
   （bump 终表 = fill/duplicateAndInvert 两命令，checker E3）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符
   祈使句、body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；
   git add 用 `.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；不加 `-derivedDataPath`；新建
   .swift/.metal 文件后同 commit `tuist generate`（T1/T2/T5/T6 建文件批末
   generate 一次；T2 含 MaskGradientDefaults.swift 新建——checker E4 落点）；Core sources 为 glob（Metal 免登记），测试 bundle 无 glob
   （见纪律 6）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed
   计数行 + failures 行双读（L028）。**回归基线 = 2464/16skip/0fail**（M2-6-3
   终轮：IOP 467/1、IOPParity 362/3、Layers 268/3、Library 430/4、Sessions 279/4、
   Export 260/1、App 398/0）；每任务全套 suite 绿。**全套跑法 =
   `Scripts/test-direct.sh --all`（七 bundle）——报备制：跑前必须向 orchestrator
   SendMessage 报备**；RSS ≥8G = MEMFAIL 机检内置，触发即记 E3 不自行重试超两次；
   在案 flake（GoldenColor 族 L018 类）隔离复跑 ×3 归因入 SUMMARY。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`MaskCombiner` 既有五式公式/kernel 公式与 `enabled` 过滤腿零语义
   改动（本 plan 只 additive 条目 feather 腿）；`DrawnMaskRasterizer` 既有 stamping
   路径与 golden 不动；`PipeCacheKey`/`PixelPipe`/`LayerCompositeDriver` 零 diff
   （边缘图例外 = checker E2 申报的 additive 三件：`edgeMapPosition = -4` 常量 +
   `edgeMapKey` 新静态键函数 + `layerTier` 一行 additive 分支
   `edgeMapPosition → .maskPlane`——**仍禁触碰既有键函数与既有 tier 分支行**）；
   AI 生成参数不持久红线不触碰；Alcedo/darktable GPL 源只读（公式数值参考，
   代码不入库）。
6. **测试登记纪律（checker E2）**：新建测试文件**同 commit** 登记两处——
   ① `Project.swift` 对应 bundle sources 显式清单；② `.work/gsd/phases/
   m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` 增行（`<bundle>\t<test-method-count>
   \t<file>`）。归属：MaskFeatherAlignTests/FollowEdgesTests = **LightamerTestsLayers**
   （Core kernel/walker，MetalContext 直用）；MaskRevisionTests = **LightamerTestsApp**
   （overlay/AI/命令 App 实态）；SidecarV5Tests/MaskItemSemanticsTests = 既有文件
   扩展免登记。
7. **收口核对（checker M 级）**：T7 `git diff --stat` 与 front-matter
   files_modified 逐文件核对，越界 = 违约；枚举新 case（FollowEdgesMode 等）
   switch 穷举零 default（`git grep -n "default:" -- <新枚举所在文件>` 口径：
   模式限 `default:`、文件限新枚举文件）。

## Tasks

### T1 Radial 双羽化 additive（数据 + kernel + golden）

- **read_first**：上列 1/2/4/7。
- **action**
  1. `MaskSpec.swift`：`EllipseForm` 增 `innerFeather: Float?`/`outerFeather:
     Float?`（init 缺省 nil，既有调用点零改动——编译器证）+ facade 读约定
     `resolvedOuterFeather`（mode-aware：`outerFeather ?? (innerFeather != nil
     ? 0 : border)`，checker E7 单源）。
  2. `DrawnMaskRasterizer.swift`：uniforms 增 form2 槽打包（KD-1）。
  3. `MaskRasterKernels.metal`：ellipse 段双腿分流（KD-1 Alcedo 线性带式逐字）。
  4. 新建 `Tests/LightamerTests/MaskFeatherAlignTests.swift`（KD-1 测试面）：
     双腿 float64 参考 parity ≤1e-6 + 三采样锚点（1/0.5/0）+ **nil 旧档逐位
     零漂移**（同 form 无新字段改造前后 plane 逐位相等——复用既有 golden fixture）
     + 回落次序矩阵（双 nil→旧腿；inner 单设→Alcedo 腿 inner 补 0；outer 单设
     同理；**双 0 显式→Alcedo 腿硬边输出、不回落旧腿**——checker E7 补格）+ 谓词
     边界（mode 旗标与 nil 性一致——双 nil 恒走旧腿）。
  5. `tuist generate` + 测试登记两处（纪律 6）。
- **验收标准**
  - [ ] 双腿 parity/锚点/零漂移/回落矩阵断言全绿；既有 06-03 analytic golden
        全绿零改动。
  - [ ] 测试登记：Project.swift（Layers sources）+ BUNDLE-MAP 行在册。
  - [ ] 全套回归 `0 fail`（基线 2464 + 新增）。

### T2 LinearGradient 映射换算钉（零 schema golden）

- **read_first**：上列 4/7（gradient profile 段 + Alcedo Linear 覆盖式）。
- **action**
  1. 读两侧公式导出换算式（KD-2）：`compression_default` 常量落 Core
     （`MaskGradientDefaults`，含文档注释推导引证行号）。
  2. `MaskFeatherAlignTests` gradient 组：Alcedo 默认档（origin 0.5/0.5、normal
     (0,1)、transition 0.2、start 1→end 0）vs 我方（anchor 同、rotation 0、
     compression_default）plane 采样逐点 ≤1e-6 + 方向符号锚（normal (0,1) ⇔
     rotation 0；normal (1,0) ⇔ rotation −90 档采样）+ start/end 方向锚。
  3. 换算式推导 + 两侧公式行号引证入 `M2-7-1-DECISIONS.md` 草稿段（T7 收口
     并盘）。
- **验收标准**
  - [ ] 换算 golden 两档（0.2 档 + 1.0 档）+ 方向/起止锚断言全绿。
  - [ ] 零 schema 改动（`git diff --stat` 证：本任务不触 MaskSpec.swift）。
  - [ ] 全套回归 `0 fail`。

### T3 mask 级属性内核（item feather + 应用序 + facade 补齐）

- **read_first**：上列 2/3。
- **action**
  1. `MaskSpec.swift`：`MaskGroupItem` 增 `feather: Float?`；facade 增
     `setItemFeather`/`setItemInverted`/`setItemOpacity`；`mutateTopLevelItem`
     升级深度优先递归 walk（KD-3，头注文档化首中语义）。
  2. `MaskCombiner.swift`：`drawnGroupPlane` 条目 feather 腿（reduce 前 blur，
     >0.1 门；KD-3）。
  3. `MaskItemSemanticsTests` 扩展：三 setter 正/miss 静默 + **嵌套 child 寻址**
     （两层 child 链设值命中）+ **应用序非空转探针**（feather 与 invert 调换
     输出必变的构造钉序）+ feather 门阈值边界（0.1 不触发/0.11 触发）。
- **验收标准**
  - [ ] facade 全绿 + 嵌套寻址绿 + 序探针绿 + 门边界绿。
  - [ ] `drawnGroupPlane` diff 仅 feather 腿（enabled 过滤/reduce 装配逐行不动
        ——diff 评审 m7）。
  - [ ] 全套回归 `0 fail`。

### T4 sidecar 载体（deletionProtected + contentRevision capture/restore）

- **read_first**：上列 2/6。
- **action**
  1. `MaskSpec.swift`：增 `contentRevision: Int?` + `bumpContentRevision()`
     （KD-3/KD-4）。
  2. `SidecarLayerStack.swift`：`SidecarMaskSpec` 增两字段 + capture/restore
     各一行 + 头部格式注释块同步（KD-4）。
  3. `SidecarV5Tests` 扩展：`:204` 缺口钉断言翻面为双向 capture/restore 真断言
     （KD-4/checker M1）+ nil 档字节零漂移保留断言全绿复核。
- **验收标准**
  - [ ] 双向 round-trip 断言绿；nil 零漂移两断言（stableHash 字节 parity +
        driftDetected 同值）保持绿。
  - [ ] 既有 Sidecar 族测试零改动全绿。
  - [ ] 全套回归 `0 fail`。

### T5 contentRevision 写点终表 + D-5 同批修 + 校验原语（M2MASK-07/03）

- **read_first**：上列 5/8 + `.work/gsd/phases/m2-4-node-model/M2-4-2-DECISIONS.md`
  （8 触点审计表 + D-M2-4-2-5 原文）。
- **action**
  1. `MaskOverlayHost.swift`：`appendForm`/`mutateForm` 改 sibling 保真构造
     （KD-5）+ **bump 重挂提交腿**（checker E5：`endInteraction` 提交前恰一次；
     append/mutate live 腿零 bump——live 腿 revision 数值恒不变）。
  2. `AIMaskEditing.swift`：install 腿提交前 bump + install 前
     `matchesExpected` 校验（失配 = 拒装 typed error，KD-5 分派表）。
  3. `LayerEditingState.swift`：`fill`/`duplicateAndInvert` 两命令提交值 bump
     （KD-3 终表；duplicate/resetEdits/clear **零 bump**——无 bump 载体裁决）
     + 防御性校验 pin。
  4. 新建 `Tests/LightamerTests/MaskRevisionTests.swift`：写点终表逐点断言
     （**正常笔画 = 相等路径恰 +1、不走重放**——press→appendForm→live ticks
     mutateForm→endInteraction 全程模拟：revision 恰 N→N+1、commit 恰 1、
     live tick 间 revision 不变，checker E5 口径 / AI install +1 / fill 与
     duplicateAndInvert 各 +1 / duplicate/resetEdits/clear 零 delta）+ AI 失配
     拒装 + **D-5 揭穿测试**（带 parametric+raster+锁的层画一笔后四 sibling
     存活——修复前红）+ undo 后穿越写被拒（快照恢复旧 revision → 在途 expected
     失配路径）。
  5. 测试登记两处（纪律 6，App bundle）。
- **验收标准**
  - [ ] 写点终表断言全绿（五处 bump + 三命令零 delta）；正常笔画恰 +1 不走
        重放断言绿；D-5 揭穿测试绿；AI 拒装路径绿。
  - [ ] overlay 腿 expectedRevision **参数面不引入**（P2 接线，diff 评审核）；
        live 腿零 bump（代码评审：appendForm/mutateForm 无 bump 调用）。
  - [ ] `matchesExpected` 单源（`git grep -n "contentRevision ?? 0" App/Sources
        LightamerCore/Sources` 仅 MaskSpec.swift 一处实现）。
  - [ ] 全套回归 `0 fail`。

### T6 Follow Edges 内核新件（edge map + walker + 熔断预埋）

- **read_first**：上列 4/7 + `LightamerCore/Sources/Pipe/PipeCacheKey.swift`
  （position 槽惯例）+ `LightamerCore/Sources/Layers/Masks/DrawnMaskRasterizer.swift`
  （stamping 入口——walker 产出衔接面）。
- **action**
  1. 新建 `MaskEdgeKernels.metal`：`mask_edge_map`（KD-6 Sobel luma 幅值，单
     PSO 零 function constant）。
  2. `PipeCacheKey.swift`：新 position 常量 `-4`（edgeMapPosition；**-3 已被
     retouch 占用**——checker E2 勘误，见 KD-6①）+ 静态键函数
     （imageID/pipeType/upstreamHash/roi/算法版本）+ `layerTier` 一行 additive
     分支（edgeMap → `.maskPlane`，KD-6① tier 归类）——additive 三件，既有键
     函数与既有 tier 分支零 diff。
  3. 新建 `FollowEdges.swift`：`FollowEdgesParams`（四参数 + mode 枚举
     `.streamline`/`.snap`）+ walker（CPU 纯 Swift：边缘图读回结构体入 →
     `[MaskPoint]` 链出，读回走 L014 fence）+ 空 edge 图降级（返回空链语义）。
  4. 新建 `Tests/LightamerTests/FollowEdgesTests.swift`：合成边缘场三景（直边/
     直角/噪声退化）walker golden（点链贴边距 ≤ 容差带）+ `.snap` 降级分支 +
     空图空链 + walker 纯函数性（同输入两次运行逐点相等）。
  5. `tuist generate` + 测试登记两处（纪律 6，Layers bundle）。
- **验收标准**
  - [ ] 三景 golden + 降级/空链/纯函数性断言全绿。
  - [ ] `FollowEdgesMode` switch 穷举零 default（grep 口径见纪律 7）。
  - [ ] 既有 PipeCacheKey 键函数零 diff（`git diff` 评审核：仅 additive 段）。
  - [ ] 全套回归 `0 fail`。

### T7 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前向 orchestrator SendMessage 报备；
     计数/秒数/bundle 峰值入 SUMMARY）。
  2. 落盘 `M2-7-1-SUMMARY.md`（测试数变化/KD 确认/写点终表/换算式终式）+
     `M2-7-1-DECISIONS.md`（KD-1..7 执行确认 + 偏差归因 + revision 写点复核
     表对照 M2-4-2 审计表 + **无 bump 载体三命令理由**（checker E3：duplicate
     内容搬运/resetEdits 内容回退/clear 无生产目标）+ **edgeMapPosition tier
     归类决策**（checker E2：`-4 → .maskPlane` 档理由 = 一次 Sobel pass 可
     重建成本量级；retouch -3 段位实证））。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-7-1 完成 + 下一步 = M2-7-2）；
     LESSONS 如踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 7）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 双羽化双腿 parity ≤1e-6 + 三锚点 + nil 旧档 plane 逐位零漂移 + 回落矩阵（含双 0 显式格，checker E7） | MaskFeatherAlignTests |
| 2 | gradient 换算 golden 两档 + 方向/起止锚 ≤1e-6；compression_default Core 单源 | MaskFeatherAlignTests + `git grep` |
| 3 | item feather 腿 + 应用序非空转探针（feather→invert→opacity→clamp）+ 门阈值边界 | MaskItemSemanticsTests 扩展 |
| 4 | facade 三 setter + 嵌套 child 递归寻址 + miss 静默 no-op | MaskItemSemanticsTests |
| 5 | sidecar：deletionProtected/contentRevision 双向 capture/restore + nil 零漂移保持 | SidecarV5Tests 翻面断言 |
| 6 | 写点 bump 终表（checker E3：overlay 提交腿/AI install/fill/duplicateAndInvert/面板写五处；duplicate/resetEdits/clear 零 delta）+ 正常笔画恰 +1 不走重放（checker E5）+ AI 失配拒装 + undo 穿越写被拒 | MaskRevisionTests |
| 7 | D-5 揭穿测试：带三 payload 层画一笔后 sibling 全存活 | MaskRevisionTests（修复前红口径） |
| 8 | Follow Edges：三景 golden + snap 降级 + 空图空链 + 纯函数性；Mode 穷举零 default | FollowEdgesTests + `git grep` |
| 9 | 边缘图缓存键 additive（`edgeMapPosition = -4` + tier 分支，既有键函数/既有 tier 行零 diff）；stamping golden/五式 parity 复跑全绿 | `git diff` 评审 + 既有 suite |
| 10 | 全套回归 0 fail，计数 ≈ 2464 + 28..36 | test-direct.sh --all BUNDLE 行双读 |
| 11 | diff 边界 == 申报文件集 | `git diff --stat` 逐文件核对 |
| 12 | 新测试文件登记闭环（checker E2）：三新文件在 Project.swift 对应 bundle + BUNDLE-MAP 行 | `git grep -n "MaskFeatherAlignTests.swift\|MaskRevisionTests.swift\|FollowEdgesTests.swift" Project.swift` + BUNDLE-MAP grep 同命中 |

## 风险与边界

- **双羽化语义分歧**：Alcedo 线性带 vs 我方既有二次羽化并存（双腿分流）——同一
  层两种视觉过渡形态共存是**设计意图**（旧档保真优先）；若走查裁决须统一，属
  P3 后调整（改默认 + 迁移腿），本 plan 不预做。
- **换算式推导失败**（compression 与 transition_distance 非纯倒数）：KD-2 golden
  两档钉不出 ≤1e-6 → 记 DECISIONS 偏差（等价带宽判据放宽到可视等价 + 采样门
  5e-3），映射语义不破——字段语义族已同（profile 宽度），只对齐默认值档位。
- **Follow Edges 边缘图成本**（任务书风险条目①）：回答 = **非每 grade 每次
  render**——键含 upstreamHash 随下方复合内容失效，同前缀跨 grade 共享、同
  层连续笔画全命中；未中才一次 Sobel pass（O(窗口像素)，与 stamping 同量级）。
  P3 观察项兜底：若实测预计算挤占交互预算，窗口下采样分辨率（≤512）再降档。
- **revision 与既有异步腿相互作用**（任务书风险条目③）：Phase 6 既有
  applyLiveLayer/endInteraction 契约（笔画结束恰 1 commit、dirty 门）不动——
  bump 挂 history 提交腿（endInteraction 提交前恰一次，checker E5；live tick
  零 bump）、校验原语在 P2 才接 overlay 提交腿；本 plan AI/命令侧先落，
  回归由「恰 1 commit」既有测试族把守。undo 恢复旧 revision 的穿越写拒绝语义
  由 MaskRevisionTests 钉（KD-5）。
- **SidecarV5Tests 翻面误伤**：缺口钉断言与真断言混行——翻面仅 `:204` 一条
  （checker M1），`:111/:119/:164` 零漂移族**保留不动**；diff 评审逐行核。
- **递归 walk 与重复 formID**：构造上不产生（forms 平面数组 id 唯一），防御性
  首中语义头注化；若未来引入共享 form 引用（Alcedo 式），语义重裁归后 phase。

## 提交约定

- T1 `feat(core): radial dual feather additive with legacy zero drift`
- T2 `feat(core): linear gradient alcedo mapping constants and goldens`
- T3 `feat(core): mask item feather and application order pin`
- T4 `feat(core): sidecar mask capture of lock and content revision`
- T5 `fix(app): preserve mask sibling payloads in overlay legs`
- T6 `feat(core): follow edges walker with edge map cache key`
- T7 `docs(m2-7): close out plan 1 mask data and kernel core`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-10-01）

checker 判 FAIL（7E+9M）后本 plan 修订项（hint 逐条落实；勘误正本 = CONTEXT
勘误注记节）：

- **E2**：`edgeMapPosition` -3 → **-4**（`retouchPosition = -3` 实占实证
  `PipeCacheKey.swift:79`）；tier 归类决策（→ `.maskPlane` 档 + `layerTier`
  一行 additive 分支）入 KD-6① + T6 action 2 + T7 DECISIONS 清单 + 纪律 5 例外
  扩述 + front-matter 补申报 `PipeCacheKey.swift`；CONTEXT 勘误-2 同步（源头错 =
  Specific Ideas「-3 惯例」引用失实）。
- **E3**：写点全表收窄为**终表五处 bump 载体**（overlay 提交腿/AI install/
  fill/duplicateAndInvert/面板写）+ duplicate/resetEdits/clear **无 bump 载体**
  三命令裁决（理由入 KD-3 + T7 DECISIONS 清单）；AC6 措辞同步。
- **E4**：front-matter 补申报 `PipeCacheKey.swift`、
  `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（实路径）、
  `MaskGradientDefaults.swift`（KD-2 显式落点新文件）。
- **E5**：bump 重挂 **history 提交腿**（KD-5 新增小节：endInteraction 提交前恰
  一次 / AI install 提交前 / 命令提交值；live tick 零 bump）+ 快照时点钉
  （press 段写毕后现值；press 即 append+commit 型交互取 post-bump 值）+
  分派表生产者列改提交腿口径 + T5 action/AC 重写（「overlay 一笔 +1」→「正常
  笔画 = 相等路径恰 +1、不走重放」全程模拟断言）。与 P2 KD-6 跨 plan 同口径。
- **E7**：KD-1 谓词钉死 = 双 nil→旧腿、任一非 nil→Alcedo 腿（腿内 nil→0 补缺，
  腿内 0 = 显式值）；删「或全 0」；facade 读约定改 **mode-aware**
  `outerFeather ?? (innerFeather != nil ? 0 : border)`；回落矩阵补「双 0 显式」
  格（T1 action 4 + AC1）。
- **M1**：SidecarV5Tests 翻面行收窄 = `:204` 一条（`testV5RoundTripCarriesAllNewFields`
  缺口钉断言）；`:111/:119/:164` 为保留的零漂移族不动（KD-4 + T4 + 风险节同步）。
- **M2/M3/M6-M9**：留执行期 DECISIONS（checker 口径）。

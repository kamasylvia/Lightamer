# M2-7-1 DECISIONS — 执行期签注（checker 口径；晨审可推翻）

> Plan M2-7-1（P1 数据与内核）执行批（2026-10-01，夜间授权连跑）。KD-1..7 全部按
> plan 落地；本文件记录执行期裁定、checker E2/E3/E5/E7 落实形态、M 级留档项与偏差。
> 正本锚点 = `M2-7-1-PLAN.md`（checker 修正版 7b88bbb）+ `M2-7-CONTEXT.md`
> Ruling/勘误注记节。

## 一、KD-1 Radial 双羽化（执行确认 + checker E7 落实）

- 谓词按 E7 钉死：`EllipseForm.hasDualFeather`（任一非 nil）→ uniform form2.z
  modeFlag 1 → Alcedo 线性带腿（`grade_mask_coverage.cpp:150-153` 逐字：rho =
  sqrt(q)，inner = max(0, 1−innerF)，outer = 1+max(0, outerF)，value =
  1 − clamp((rho−inner)/max(outer−inner, ε))）；双 nil → modeFlag 0 → 旧二次腿
  逐字节（0 fail 的 DrawnMaskRasterTests 8/0/0 复跑 = 06-03 goldens 零改动即证）。
  腿内 nil→0 折叠（打包处 `?? 0`），**双 0 显式 = Alcedo 腿硬边**（测试钉）。
- facade 读约定单源 = `resolvedOuterFeather`（mode-aware：
  `outerFeather ?? (innerFeather != nil ? 0 : border)`），P2 面板禁第二实现。
- **M2 签注（零漂移口径）**：AC1 的「nil 旧档 plane 逐位零漂移」由两件合成证——
  ①06-03 analytic goldens（含 border/rotation 变体）零改动复跑全绿；②新测试
  `testDualNilRoutesToLegacyLegZeroDrift` 对旧腿 float64 参考 ≤5e-6 parity（
  旋转羽化带 gate 沿 06-03 先例 5e-6，实测 1.13e-6）+ 对「Alcedo-zeros 误路由」
  差距 >0.1 的反证。位级 byte-equal 在测试内不可复现（pre-change kernel 不可
  同时在场的物理限制），以上两件 + kernel diff 评审（旧分支逐 token 未动）为
  执行期等效判据。

## 二、KD-2 LinearGradient 换算式终式（checker E4 落点 + 两处偏差）

**换算式（推导行号引证）**：

- dt 侧（`MaskRasterKernels.metal` gradient 段 ← dt gradient.c:1176-1232）：
  `y0 = (sin v·px − cos v·py − yoff)·hwscale`，hwscale = 1/√(wd²+ht²)（**半对角
  单位**）；linear value = 0.5 + 0.5·y0/compression；value-1 方向 =
  −(sin rot, cos rot)。
- Alcedo 侧（`grade_mask_coverage.cpp:155-158` Linear 分支）：d = (n−origin)·n̂
  （**矩形归一单位**，nx=px/wd、ny=py/ht）；t = clamp(d/τ + 0.5)；value =
  start + (end−start)·t = 1−t；value-1 方向 = −n̂。
- 方向映射：−(sin rot, cos rot) = −n̂ ⟹ **rotation = atan2(nx, ny)**（方形窗）。
- 带宽映射（方形窗 wd=ht=s，halfDiag = s√2；normal (0,1) 时 y0 = −d/√2）：
  0.5 + y0/(2c) = 0.5 − d/τ ⟹ 2√2·c = τ ⟹ **compression = τ/(2·√2)**。
  τ=0.2 → c ≈ 0.0707107（`MaskGradientDefaults.compressionDefault`，Core 常量
  单源，P2 面板消费）；τ=1.0 档同式（scale 线性验证）。

**偏差-1（方向符号锚：plan 草稿「normal (1,0) ⇔ rotation −90」被 golden 否）**：
推导与平面采样 golden 一致裁决为 **+90**（`testGradientDirectionSignAnchors`：
normal (1,0) → rotation +90 时左饱和 1、右饱和 0，逐点 ≤1e-6）。plan 映射表内
公式 `atan2(nx, ny)`（给 (1,0) → +90）与「−90」示例文字自相矛盾，执行以公式为
权威——plan 明文「执行时以 golden 采样对验证符号」即此案。
**偏差-2（T2 goldens 随 T1 commit 落盘）**：MaskFeatherAlignTests 单文件承载
T1/T2 两组 golden，T1 commit（d6de037）已含 T2 gradient 测试；T2 commit（
3ab8aad）落 `MaskGradientDefaults.swift` + 测试改挂常量单源。理由 = 纪律 2
「建文件批末 generate 一次」的分批选择，拆两 commit 需同文件两轮 generate 零收益。
**_aspect 注记**：换算式在方形窗逐点精确；非方窗下 dt compression 的半对角单位
与 Alcedo 矩形单位的各向异性使等价带宽随 aspect 漂移——P2 面板默认值语义不受
影响（profile 宽度族同域），非方窗精映射若需要归 P2 DECISIONS。

## 三、KD-3 item feather + 应用序（探针机制注记，checker M 级留档）

- `MaskGroupItem.feather: Float?`；`drawnGroupPlane` 条目腿：reduce 装配前
  `blur(sigma: feather)`（门 = feather > 0.1，dt blend.c:306 同款）；enabled
  过滤 / 五式 / reduce 装配零 diff（diff 逐行核过，仅 `let plane`→`var plane` +
  feather 腿 7 行）。
- **M3 签注（应用序探针机制）**：plan 机制建议「feather 与 invert 调换输出必
  变」在线性代数下**不可达**——Deriche blur 线性、invert 仿射、opacity 线性
  缩放，三者对单条目数学交换（含 float 语义下仅 ulp 级差）。探针按「非空转」
  实质重设计：①双条目构造（feathered A + 硬 difference B）钉 **feather 先于
  combine**（feather-after-combine 回归在 B 切口内泄漏 ~0.3，正确序恒 0——
  `testApplicationOrderFeatherBeforeCombineProbe`）；②inverted+feathered 轮廓
  锚（核心 0 / 远场 1 / 软环）钉 invert 消费羽化后轮廓；③门阈值 0.1/0.11
  （位同 / 位异）。三件全绿。

## 四、KD-4 sidecar 载体（checker M1 落实）

- `SidecarMaskSpec` + `deletionProtected`/`contentRevision` 两 Optional，
  capture/restore 各一行；头部 Spelling 注释 + SidecarMaskSpec 文档注释同步。
- **翻面范围 = M1 收窄口径**：仅 `testV5RoundTripCarriesAllNewFields` 的缺口钉
  断言翻为双向真断言（setup 增 `contentRevision = 7`，既有 `deletionProtected
  = true` 行随用）；`:111/:119/:164` 零漂移族零 touch（diff 评审核过）；
  `:135` hash 参与断言不动。SidecarV5Tests 11/0/0（10 既有 + 1 新原语测试）。
- hash-isolation：contentRevision 随 mask 域经 `stableHash()` 自然折叠，不单独
  申报进/出 HistoryHash（零新判定代码，06-05 hardening 既有语义）。

## 五、KD-5 乐观并发（checker E5 落实 + 四项执行期裁定）

- **裁定-1（MaskOverlayRecord 抽取）**：plan 断言「press→appendForm→live
  ticks→endInteraction 全程模拟」要求 overlay 腿可测——MaskOverlayHost 是
  @Environment 视图（测试构造即 fatal）。处置 = 记录管道（appendForm/mutateForm/
  endInteraction + dirty）抽取为同文件 `@MainActor struct MaskOverlayRecord`，
  View 持 @State 委托；手势/几何零动。MaskRevisionTests 直驱该类型走真路径。
  属申报文件内的结构重组，非越界。
- **裁定-2（endInteraction dirty 复位微修）**：原实现 `dirty=false` 在 guard
  之后（有脏但无 live layer 时 dirty 残留 → 下次交互幽灵提交）；抽取版
  `defer { dirty = false }` 恒复位。正常流不可观测（笔画存在 ⇒ 选层存在），
  幽灵提交路径被消除，记为顺手正确性修复。
- **裁定-3（fill 前向携带 +1）**：KD-3 ③「fill = 内容整体重写」的实现取
  「revision 前向携带」（新空 spec 继承旧值再 bump：3→4；nil→1）而非「新纪元
  归 1」。理由 = 「每内容写点单调 +1」语义（KD-3）+ 陈旧在途写防护（fill 归 1
  会让更早 epoch 的 expected=1 陈旧写复活）。clear 无载体与此自洽（记录消失，
  无 form 生产目标，失配判据退化为 form 存在性）。
- **裁定-4（AI gate 时点 + 错误面）**：校验点在 **bake await 之后、slot 写之前**
  （读共享 layer 引用的现值——用户编辑落在 bake 窗口内即命中拒绝；gate 前置
  会漏检 await 期间的穿插写）。失配 = 既有 `AIMaskError.invalidInput`（07 错误
  面复用；`AIMaskTypes.swift` 非 plan 申报文件，**不加新 case**——单源纪律的
  文件集投影）。拒绝不回滚已 bake PNG（孤儿文件无害，D-07-CONTEXT-5 同名覆盖
  语义下未来 install 重写）。equal 路径 bump 恰一次；快照语义（press 段写毕后
  现值 / press 即提交型取 post-bump）为 P2 接线口径，本 plan 参数面仅 AI 侧
  `expectedRevision: Int? = nil`（overlay 腿参数面未引入，diff 评审核）。
- 写点终表逐点断言全绿（MaskRevisionTests 6/0/0）：正常笔画恰 +1 不重放、
  AI +1/拒装、fill +1 前向、duplicateAndInvert +1（源 3 不动）、duplicate
  原值随迁、resetEdits/clear 零 delta、undo 恢复旧 revision 后在途写被拒。

## 六、写点终表对照 M2-4-2 审计表（checker E3 收窄后终态）

| 写点 | M2-4-2 审计定性 | M2-7-1 终态 |
|---|---|---|
| `MaskOverlayHost` appendForm/mutateForm（live 腿） | 合法（内容生产） | **sibling 保真修（D-5）+ 零 bump**（E5：live 恒不变） |
| `MaskOverlayHost` endInteraction（提交腿） | —（commit 通道） | **bump 恰一次，提交前**（E5；dirty 门 no-op 零 bump） |
| `AIMaskEditing` install | 合法（内容生产） | **gate（失配拒装）+ bump 恰一次** |
| `MaskCommand.fill` | deletionProtected 拦截面 | **前向携带 +1**；拦截腿不变 |
| `MaskCommand.duplicateAndInvert` | 合法（内容变换） | **提交值 +1**；防御 assert pin |
| `MaskCommand.duplicate` | 合法（结构） | **零 bump**（内容搬运，revision 原值随迁） |
| `MaskCommand.resetEdits` | —（chain 域） | **零 bump**（mask 保留原值；chain 回退非 mask 内容写） |
| `MaskCommand.clear` | deletionProtected 拦截面 | **零 bump**（无 bump 载体——记录消失，无生产目标） |
| AdjustmentLayer init / snapshot / sidecar decode | 合法（构造/恢复） | 不 bump（恢复路径；undo 携回旧值 = 期望行为，穿越写被 gate 拒） |
| P2 面板 item 属性写（setter ⑤） | —（未落地） | **setter 不 bump、调用方 bump**（KD-5 分工；T3 setter 头注钉死） |

## 七、无 bump 载体三命令裁决（checker E3，理由归档）

1. **duplicate**：复制 = 内容**搬运**非内容写——新层 mask = 源快照逐字节、
   revision 原值随迁；新 form 无在途异步生产者，bump 无防护收益，反而破坏
   「拷贝即快照」语义。
2. **resetEdits**：恢复基线 = **chain 域内容回退**——mask 记录本身保留原值
   （实现核验：该命令只写 `copy.chain = []`，mask 不动），无 mask 内容写点；
   穿越写防护由 undo 快照恢复语义承担（恢复后 gate 按旧值拒绝，测试钉）。
3. **clear**：清空后 drawn 为空、**无 form 可作异步生产目标**——失配判据退化
   为 form 存在性（mutate 型天然拒绝），revision 数值无判读意义；与 fill 的
   区别 = fill 留下**记录**（raster-only 生产者仍可落），clear 连记录一并移除。

## 八、KD-6 Follow Edges（checker E2 落实 + 三项执行期签注）

- **edgeMapPosition = -4 tier 归类（E2 正解）**：`retouchPosition = -3` 实占
  实证（`PipeCacheKey.swift:79`，06-07 stroke-leg 输出槽）。`layerTier` 一行
  additive 分支 `-4 → .maskPlane` 理由 = 一次 Sobel pass 可重建（与 mask 栅格
  同量级），归「最便宜重建族最后逐出」档；缺此分支 -4 落 `.layerChainOutput`
  （最贵逐出档）语义错误。**additive 第四件声明**：`edgeMapNamespaceID`（固定
  UUID）——edgeMapKey 需要一个非 base-sentinel 的 layerID 承载「不挂 layer」
  语义且让 tier 分支可达（base sentinel 会在 tier 首行短路返 nil）；它是键
  函数的实现细节非新 API 面。
- **签注-1（walker 采样设计）**：幅度图脊线上自采样梯度为零（crest 处横向
  梯度对称抵消）——walker 取 **lookahead 侧翼采样**（当前点 + heading·step
  处的梯度，回落 ±1 环最强读数，再回落纯动量），初始朝向 = 种子 ±1 环最强
  梯度的垂直向。直边/转角/噪声三景 golden + 纯函数性（两次运行逐点相等）全绿。
- **签注-2（snapTarget 阈值门）**：吸附目标必须 ≥ edgeThreshold（首版 >0 门
  在亚阈值纹波场误吸附——测试揭穿后修正）；streamline 种子吸附与 .snap 共用
  同一门（8px / 12px 半径）。
- **签注-3（corner 场景参数）**：转角完成度对 followStrength 敏感（动量过强
  切角、stop gate 像素取整放大）——golden 用 λ=0.25/step 1.0 显式参数（walker
  默认 0.5/1.5 保留；P3 走查实测裁决熔断与默认值）。
- 复杂度熔断预埋 = `FollowEdgesMode` 双 case 现在分立（`.streamline`/`.snap`
  dispatch 穷举零 default，纪律 7 grep = 0 命中）；熔断 = P3 翻 UI 默认值，
  walker 不删。

## 九、KD-7 性能预算（确认）

stamping 0.744ms/千枚 golden、五式 parity、06-03/06-04 analytic goldens 全
保留复跑绿；新增预算项 = 边缘图（per imageID+upstream 一次 Sobel，缓存命中后
零成本）+ item feather blur（>0.1 门才发生）；双羽化 Alcedo 腿 = 分支表达式级
差异无专项 bench（plan 原文）；手柄拖动/缩略图 = P3 观察项挂账。

## 十、测试与文件对账

- 新增测试 = **29**（--all 对账精确：2464 基线 → 2493）：MaskFeatherAlignTests
  9【LAYERS】+ FollowEdgesTests 8【LAYERS】+ MaskRevisionTests 6【APP】+
  SidecarV5Tests +1（APP 扩展）+ MaskItemSemanticsTests +5（APP 扩展：2 facade
  + 3 combiner 探针）。bundle 对账：LAYERS 268→285（+17）、APP 398→410（+12）、
  其余五 bundle 逐值持平（IOP 467/1、IOPParity 362/3、Library 430/4、Sessions
  279/4、Export 260/1）；skip 16 持平。AC10 的估区间 28..36 为 plan 起草估计，
  实际 29 落于区间内。
- 登记闭环（AC12）：Project.swift 两 bundle 显式清单 + BUNDLE-MAP 三行 + 增行
  记录注释，grep 双命中。
- `matchesExpected` 单源（AC6）：`git grep "contentRevision ?? 0"` =
  MaskSpec.swift 3 处（bump 折叠 / 文档注释 / 原语行），App/Sources 零命中
  （T7 批消除 AI 错误消息里的同拼写插值）。
- 红线核：`MaskCombiner` 五式/enabled 过滤零语义改动；`DrawnMaskRasterizer`
  stamping 路径与 golden 不动（form2 打包 additive）；`AIMaskEditing` 生成参数
  不持久红线未触；Alcedo/darktable GPL 源只读（公式数值参考，零拷贝入库）；
  `AIMaskEditing.swift` 本 plan 实际 diff = install 腿 gate+bump（**CONTEXT/派发
  红线「零 diff」按 plan front-matter 申报为准**——front-matter 明列该文件修改，
  派发红线指「生成参数/生成面」不动，已按 front-matter 执行并在此声明口径）。

## 十一、偏差清单（晨审可推翻）

1. T2 goldens 随 T1 commit（§二 偏差-2）。
2. 方向锚 +90（§二 偏差-1，golden 裁决）。
3. MaskOverlayRecord 抽取 + endInteraction defer 微修（§五 裁定-1/2）。
4. fill 前向携带 +1（§五 裁定-3）。
5. AI gate 后置 bake + invalidInput 复用（§五 裁定-4）。
6. edgeMapNamespaceID additive 第四件（§八）。
7. AC1「逐位零漂移」以 goldens 复跑 + 反证测试等效承载（§一 M2 签注）。
8. 应用序探针机制重设计（§三 M3 签注）。

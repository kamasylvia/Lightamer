# M2-7-1 SUMMARY — 数据与内核 plan 执行收口

> 执行 worker（2026-10-01，夜间授权连跑）。plan 正本 =
> `M2-7-1-PLAN.md`（checker 修正版 7b88bbb）；签注正本 =
> `M2-7-1-DECISIONS.md`（KD 确认 + 写点终表对照 + 偏差清单）。
> **全套回归终跑（coordinator 批准报备制）= `TOTAL|2493/16/0|873s EXIT=0`**
> （基线 2464/16skip/0fail + 29 精确；MEMFAIL 零触发，峰值 IOP 6936MB < 8G）。

## 交付面（六执行提交 + 收口批）

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `d6de037` | Radial 双羽化 additive：`EllipseForm.innerFeather/outerFeather: Float?`（init 缺省 nil，既有调用点零改动）+ `hasDualFeather`/`resolvedOuterFeather`（E7 mode-aware 单源）+ uniforms form2 尾槽（modeFlag = nil 性纯函数）+ MSL Alcedo 线性带腿（`grade_mask_coverage.cpp:150-153` 逐字）+ MaskFeatherAlignTests 9 法【LAYERS，登记 Project.swift + BUNDLE-MAP】 |
| T2 | `3ab8aad` | `MaskGradientDefaults.compressionDefault = τ/(2√2)` Core 常量单源（推导行号引证入文件头 + DECISIONS §二）+ gradient 换算 goldens（goldens 随 T1 commit，偏差-2）+ 方向锚 **+90 裁决**（偏差-1，golden 否决 plan 草稿 −90） |
| T3 | `1a038a5` | `MaskGroupItem.feather: Float?` + `drawnGroupPlane` 条目 feather 腿（reduce 前 Deriche blur，>0.1 门）+ facade `setItemFeather/setItemInverted/setItemOpacity` + `mutateItem` 深度优先递归 walk（首中头注化）+ 应用序探针三件（双条目切口/inverted 轮廓锚/门阈值） |
| T4 | `7231c14` | `MaskSpec.contentRevision: Int?` + `bumpContentRevision()` + `matchesExpected` 原语（单源）+ `SidecarMaskSpec` deletionProtected/contentRevision capture/restore 各一行（D-M2-4-1-3 兑现）+ SidecarV5Tests `:204` 翻面（M1 口径）+ revision 原语测试 |
| T5 | `768d5e3` | D-M2-4-2-5 同批修：`MaskOverlayRecord` 抽取（appendForm/mutateForm sibling 保真构造；live 腿零 bump）+ endInteraction 提交前 bump 恰一次 + AI install gate（`expectedRevision` 失配拒装 `AIMaskError.invalidInput`）+ `fill` 前向携带 +1 / `duplicateAndInvert` +1（duplicate/resetEdits/clear 零 delta，E3 裁决）+ MaskRevisionTests 6 法【APP，登记两处】 |
| T6 | `066423f` | `MaskEdgeKernels.metal`（luma Sobel 幅值，阈值前归一 ÷4√2，单 PSO 零 function constant）+ `PipeCacheKey` additive 三件（`edgeMapPosition = -4`【E2 勘误：-3 实占】+ `edgeMapKey` + `layerTier` 一行 `.maskPlane` 分支）+ `FollowEdges.swift`（四参数 + 双 mode 熔断预埋 + lookahead 侧翼采样 walker + 空图空链降级 + L014 fence 读回 ≤512 守卫）+ FollowEdgesTests 8 法【LAYERS，登记两处】 |
| T7 | 本批 | SUMMARY/DECISIONS/GOAL-STATE 续接点 + AC6 grep 口径修（AI 错误消息去 `?? 0` 拼写，行为零变） |

## 测试数字 vs 基线

| 轮 | 结果 |
|---|---|
| 基线（M2-6-3 终轮） | 2464/16skip/0fail（IOP 467/1、IOPParity 362/3、Layers 268/3、Library 430/4、Sessions 279/4、Export 260/1、App 398/0） |
| 定向域全量轮（Layers / App） | Layers **285/3/0**（+17）；App **410/0/0**（+12） |
| **全套 `--all` 终跑（批准）** | **`TOTAL|2493/16/0|873s EXIT=0`**——IOP 467/1、IOPParity 362/3、Layers 285/3、Library 430/4、Sessions 279/4、Export 260/1、App 410/0；skip 16 持平；**+29 = 9+8+6+1+5 精确对账**（AC10 估区间 28..36 内）；MEMFAIL 零触发（峰值 IOP 6936MB / Export 6796MB < 8G） |

每任务边界 suite（摘）：MaskFeatherAlignTests 9/0/0、FollowEdgesTests 8/0/0、
MaskRevisionTests 6/0/0、MaskItemSemanticsTests 7/0/0、MaskItemCombinerSemanticsTests
7/0/0、SidecarV5Tests 11/0/0、MaskCommandTests 11/0/0、LayerUIWiringTests 19/0/0、
PanelWiringTests 71/0/0、DrawnMaskRasterTests 8/0/0、MaskCombineTests 8/0/0、
PipeCacheTests 10/0/0、LayerCacheTests 10/0/0。在案 flake（GoldenColor 族 L018 类）
零触发。

## AC 总表机检（12/12）

| # | AC | 结果 |
|---|---|---|
| 1 | 双羽化 parity ≤1e-6 + 三锚点 + nil 零漂移 + 回落矩阵（含双 0 显式） | ✅（旋转带 gate 5e-6 沿 06-03 先例；逐位口径的等效承载见 DECISIONS §一） |
| 2 | gradient 两档 + 方向/起止锚 ≤1e-6；compression_default 单源 | ✅（`git grep compressionDefault` 单文件单常量） |
| 3 | item feather 腿 + 序探针 + 门边界 | ✅（探针机制重设计见 DECISIONS §三） |
| 4 | facade 三 setter + 嵌套寻址 + miss 静默 | ✅ |
| 5 | sidecar 双向 capture/restore + nil 零漂移保持 | ✅（`:111/:119/:164` 未动） |
| 6 | 写点终表（五 bump + 三零 delta）+ 恰 +1 不重放 + AI 拒装 + undo 穿越拒 | ✅（MaskRevisionTests；`matchesExpected` 单源 grep = MaskSpec.swift 3 处、App 零命中） |
| 7 | D-5 揭穿测试 | ✅（四 sibling 存活断言；修复前红由构造等价论证——DECISIONS §五裁定-1） |
| 8 | Follow Edges 三景 + snap + 空图 + 纯函数性；Mode 穷举零 default | ✅（`git grep "default:" -- FollowEdges.swift` = 0） |
| 9 | edgeMap 缓存键 additive + 既有键/tier 零 diff + stamping/五式复跑绿 | ✅（diff 评审：仅 additive 段 + position 文档注释一行） |
| 10 | 全套 0 fail，计数 ≈ 2464+28..36 | ✅ **2493/16/0**（+29 在区间内） |
| 11 | diff 边界 == 申报文件集 | ✅（`git diff 7b88bbb..HEAD --stat` 逐文件对 front-matter：全申报内；执行期新增申报外 diff = 无【`AIMaskEditing.swift` 在 front-matter 申报内】） |
| 12 | 三新测试文件登记闭环 | ✅（Project.swift grep 3 命中 + BUNDLE-MAP 3 行 + 增行记录注释） |

## KD 确认（摘要；签注全文在 DECISIONS）

- **KD-1** 双腿分流 + E7 谓词落实；零漂移 = goldens 复跑 + 反证测试（§一）。
- **KD-2** 换算式终式 **compression = τ/(2·√2)**、**rotation = atan2(nx, ny)**
  （+90 锚 golden 裁决）；aspect 注记挂 P2（§二）。
- **KD-3** feather 腿 additive；应用序 = feather→invert→opacity→clamp 结构钉死
  + 非空转探针（§三）。
- **KD-4** sidecar 双字段 + M1 翻面口径（§四）。
- **KD-5** bump 只挂 history 提交腿五处；live 零 bump；校验次序 = 先校验后
  bump；快照时点 = press 段写毕后现值（P2 接线口径）；分派表 AI/命令侧落地
  （§五 四裁定）。
- **KD-6** `-4 → .maskPlane` tier 归类 + walker 设计签注（§八）。
- **KD-7** 预算项确认（§九）。

## 写点终表（checker E3/E5 终态；对照表全文 DECISIONS §六）

bump 五处 = overlay endInteraction（提交前恰一次）/ AI install / `fill`（前向
携带）/ `duplicateAndInvert` / P2 面板写（setter 不 bump、调用方 bump——P2 落）。
零 delta 三命令 = duplicate（内容搬运）/ resetEdits（chain 域回退，mask 不动）/
clear（无生产目标）。undo 恢复旧 revision = 期望行为（穿越写被 gate 拒，测试钉）。

## 偏差与挂账

- 偏差 8 项入 DECISIONS §十一（T2 goldens 分批 / +90 方向锚 / MaskOverlayRecord
  抽取 + defer 微修 / fill 前向携带 / AI gate 后置 + invalidInput 复用 /
  edgeMapNamespaceID 第四件 / 逐位零漂移等效承载 / 序探针机制重设计）。
- 挂账（非本 plan 范围）：P2 接 overlay expectedRevision 快照参数与重放/拒绝
  分派、Follow Edges UI 面、P3 走查观察项（双羽化手柄实时性 / walker 单 seed
  压测熔断裁决 / walker 默认参数实测）。
- REQUIREMENTS M2MASK-01/02/03/04/05/07 翻账**留验收批**（派发指令第 7 条）。

## 红线核

`MaskCombiner` 五式公式/enabled 过滤零语义改动（diff 仅 `let→var` + feather 腿
7 行）；`DrawnMaskRasterizer` stamping 路径与 golden 不动（form2 打包 additive）；
`PipeCacheKey` 既有键函数与既有 tier 分支行零 diff（仅 additive 段 + position
字段文档注释一行）；`AIMaskEditing` AI 生成参数不持久红线未触（本 plan diff =
install 腿 gate+bump，front-matter 申报内）；Alcedo/darktable GPL 源只读零拷贝；
未 push。

# M9-1 CHECKER — plan v2 修复终验（goal-backward，2026-10-25）

> **结论档位：放行**（7/7 处置全真落 / goal-backward 三 AC 全兑现 / 0 退回项 / 1 非阻断观察）
> 评审对象 = `M9-1-PLAN.md` v2 + `CONTEXT.md`（修复后）；对照 = `M9-1-PLAN-REVIEW.md`
> （PASS-with-notes，0 blocking / 2 major / 5 minor）。
> 亲核锚点 **16 组全命中零错锚**（见 §三）；纯读评：零 commit、零构建、未启 computer-use。

---

## 一、逐条核验表（M-1/M-2/m-1..5 处置真伪）

| 条 | 档位 | v2 落点（plan 文本核） | 源锚亲核（fixer 声称的修法落点） | 判定 |
|---|---|---|---|---|
| **M-1** `.candidate` allCases 消费面泄漏 | major | T3 action 3「样式 picker 白名单」子条在位：`userSelectableCases` 静态白名单（三现役 case）+ `panelMenuCases` 同款先例锚 + `MaskToolbarView.swift:144` 改消费白名单 + xcstrings 显式**不加** `mask_overlay_style_candidate` 键 + 「`ForEach(allCases)` 非穷举 switch 无编译期保障——收口靠白名单断言 + grep 三项机检，非任何『编译期收口』措辞」纠偏句；T3 验收三项机检（ForEach 消费白名单恰一处 + 测试断言可选集不含 candidate + xcstrings 键零在册）；T3 测试族 picker 白名单断言；front-matter SC/files_modified/read_first/Checker 节四处同步；CONTEXT D-M9A-3 同步改写（「编译期收口」错误措辞源头已正） | `LayerEditingState.swift:109-111` = `MaskCommand.panelMenuCases` 白名单真实在位，:104-108 注释原句「every menu consumer reads this list, never `allCases`, so a future command case cannot silently leak into the menu」逐字命中（M-1 先例引用非虚构）；`LayerEditingState.swift:69-76` MaskOverlayStyle 恰三 case + labelKey 动态拼 `mask_overlay_style_\(rawValue)` :75（裸键陷阱语境真实）；`MaskToolbarView.swift:144` `ForEach(MaskOverlayStyle.allCases, id: \.rawValue)` 现役消费面精确命中（改写点真实存在） | **真落** |
| **M-2** 候选 coverage 传值缝结构低估 | major | T3 action 3 传值缝子条整体重写：「不复用 spec 组装腿」判据句（session 候选未 bake 无 layer.mask spec → `applyMaskOverlayIfRequested` spec 组装 + caller 门结构性不适用）+ **二选一显式预案**（① request 形态扩展——:227-230 元组 additive 候选纹理位 + caller 候选分支 bypass payload guard + 合成腿跳过 spec 组装直染 / ② 候选专用合成臂——独立 request 变体旁路 spec 组装走同一 render 尾插入点 :2434-2452）+ execute 期定 DECISIONS 记选定形态 + Core PixelPipe 零触碰护栏；read_first 补 `:227-230,:264-300,:2434-2452` 锚（review 修法要求的「点名 spec 组装前提」达成）；风险节「候选通道渲染缝（M-2 扩）」结构性缝面；T3 回滚节偏差清单补传值缝选定形态；front-matter SC/files_modified 同步；Checker 节「非 spec 组装腿复用」核面；CONTEXT D-M9A-3 + 复用件清单行同步 | `PipeCoordinator.swift:264-272` 函数签名真实；:282 `unwrap(layer.mask, "mask overlay: no mask")` 逐字命中；:289-292 `DrawnMaskRasterizer.planeIfDrawn` / :298-307 `MaskCombiner.effectivePlane` spec 组装双腿精确；caller 门 `layer.mask?.hasAnyPayload == true` 精确在 :2434-2441（:2446 调用点）——「候选 plane 无 spec 则两门皆不可过」的结构判据实锚成立，二选一预案与结构现实吻合 | **真落** |
| **m-1** Expand CPU/GPU 偏离未申报 | minor | T2 action 5 申报句在位：「Expand = CPU vImage 显式偏离 REQUIREMENTS M9AIM-03 与 ROADMAP M9-1 行的『GPU 算子』字样（零新 kernel 红线优先，D-M9A-9；GPU 化留 seam），DECISIONS 收口登记」+ GPU seam 注记；Checker 节 D-M9A-9 核面加「CPU 偏离 GPU 字样申报」 | REQUIREMENTS :737 M9AIM-03 正文「GPU Feather/Expand……GPU 算子」字样实锚（偏离对象真实存在；验收形态本身无 GPU 判据——review 已确认不构成 AC 违反，申报即闭环） | **真落** |
| **m-2** ΔN 构成与带偏紧 | minor | 带 +20..27 → **+20..29** 四处同步（front-matter estimated_tests / expected_all / 头部基线句 / T5 action 3）；ΔN 预算表 T2 +5..7→+5..9（构成列按 action 6 细目重写：Morphology 五面 + FeatherPx 四面 ≈9）、T3 +6..8→+6..9（Path 三面 + Iterative 六族 ≈9）；表后**越带申报注在位**（上限 29 越 charter +20..28 至多 +1；golden 五面各承载独立红线论证 + AI-06 断言一一对应 + 一法多断言可回落 + 收口按实数落 SUMMARY） | 算术自洽性：下界直和 5+5+6+4+0=**20** ✓；上界直和 6+9+9+6+0=**30** vs 申报带上界 **29** 差 1——见 §四观察项 O-1（非阻断） | **真落**（附 O-1） |
| **m-3** M9AIM-02 承载映射未显式 | minor | T5 action 5 承载映射句在位：验收形态（合成事件→AX 驱动真视口 tap→蒙版更新→coverage 消长 + 交互不改参数真相）↔ 三层链 = T3 状态机级单测（机检）+ 走查项②③（AXPress 配方）+ omp computer-use 二次验收；SUMMARY 对账行按此映射落、验收轮逐段核销不落空 | —（plan 文本核充分；三层链各腿在 T3 验收/CONTEXT 编排节实在位） | **真落** |
| **m-4** re-entry 与注释意图相抵 | minor | T4 action 2「意图变更注释同步」子句在位：注释改写为「自动联动仍禁；用户显式 re-entry 走 .segment/.subject/.person 三源路由」+ DECISIONS 记设计意图变更（防联动语义保留、路由面扩源——「显式 open ≠ 自动 seed」语义可分论证完整）；re-entry 判据锚精确化 `LayerEditingState.swift:284-290`（`== .segment` :287）；T4 验收 grep 补「must never seed 措辞零残留」 | `AIMaskEditing.swift:36-43` 注释真实在位（depth :36-38「stays disjoint」同款 + person :41-43「a person re-bake must never seed a segment session — `armSegmentSession` keys on `.segment` only」逐字）；`LayerEditingState.swift:284-290` `armSegmentSession` + :287 `AIMaskSource.source(ofFileName: fileName) == .segment` 精确——被推翻注释与被扩展判据双实锚，改写义务非虚构 | **真落** |
| **m-5** 行号漂移 + grep 口径 | minor | ① `commitRasterMask` :157→**:158**（T4 read_first）✓；② 主体蒙版入口 :353→**:353-363**（注释 :353 / 按钮 :363——T1 action 1）✓；③ AdjustmentTransfer mask 腿 :193-195 v2 声称「实测复核无漂移」+ 精确化注 :194 ✓；④ T3 验收 `scribbleNotSupported` 口径明确化：硬清零面 = throw 点 + 测试断言在册；error case/注释去留 = DECISIONS 记（throw 点清零后 case 若成死代码则删除）+ 风险节同步 ✓ | ① :158 函数声明精确；② :353 注释「主体蒙版 — layer A one-tap」/ :363 `generateSubjectMask(invert: false)` 按钮 action 精确；③ :193 `if var mask` / :194 `mask.contentRevision = nil` / :195 `layer.mask = mask` 三行逐字（v2 判定「无漂移」正确，review 附录计数偏差所致）；④ 全仓 grep 恰 **5 处**命中与 plan 所列逐字吻合：throw `AIMaskService.swift:386` / 注释 `AIMaskTypes.swift:70` / case 定义 `AIMaskTypes.swift:151` / 断言 `AIMaskSemanticTests.swift:293` / 注释 `LayerEditingState.swift:684` | **真落**（四子项全中） |

**小结**：7/7 处置真落，无假修复、无措辞空转；v2 修复记录表（plan 尾节）与实际 plan/CONTEXT 文本一致。

## 二、Goal-backward：M9AIM-01..03 在 v2 T 序的兑现核

| AC（REQUIREMENTS :735-737 原文亲核） | v2 承载链 | 判定 |
|---|---|---|
| **M9AIM-01**「三件经 M6-4 分割基建落位 + Background 恒等负测 + Sky 槽 disabled 断言」 | T1 action 1 四 icon（Subject 现役腿复用 :353-363 / Background invert 位 / People InstancePicker+unionSelection / Sky disabled）+ 测试①（invert 位 + 与 Subject 共腿断言）②（AX id + `.disabled` 态 + 点击零动作）③（union max-fold）④⑤；服务面零差距（person 族 :480/:588 review 已亲核） | **兑现** |
| **M9AIM-02**「合成事件→AX 驱动真视口 tap→蒙版更新→coverage 消长 + 交互不改参数真相（AI-06）」 | 三层链完整：T3 状态机级单测（debounce 300ms 合并/候选保留/通道消失）+ T3 验收「候选态全程 sidecar/history 零写入」AI-06 机检断言 + T5 走查②③ AXPress 配方 + omp computer-use 二次验收（CONTEXT 编排节）+ **m-3 承载映射句显式登记**（SUMMARY/MANIFEST 对账行） | **兑现**（v2 较 v1 强化） |
| **M9AIM-03**「会话三命令端到端 + paste 排除负测 + Feather/Expand golden（对称半径/边界行为）」 | T4 四族测试（cancel 丢弃零 bake / re-entry 三源路由 / paste 正负测 + 手绘不排 + 跳过名单 / undo 边界恰 1 条）+ T2 golden 五面（八角距离对称 = 形态学各向对称 / 逐字节 vImage 对拍 / erode 反演边界 / 恒等 / 量化单调）+ GPU→CPU 偏离申报（m-1；验收形态无 GPU 判据不构成 AC 违反） | **兑现** |

**修复未引入缺腿**：M-1/M-2 修法均为 additive 预案/白名单补面，v1→v2 只见增补与锚点精确化，T1-T5 主体 action/验收标准零删改；front-matter depends_on（R6 让位）与 STATE「near = R6 修复批」现势一致。

## 三、亲核锚点清单（16 组，全命中零错锚）

| # | 锚点 | 用途 | 实测 |
|---|---|---|---|
| 1 | `LayerEditingState.swift:109-111` + 注释 :104-108 | M-1 白名单先例 | ✓ 逐字（含 "cannot silently leak" 原句） |
| 2 | `LayerEditingState.swift:69-76` | M-1 枚举/labelKey 语境 | ✓（labelKey :75 动态拼） |
| 3 | `MaskToolbarView.swift:144` | M-1 现役消费面/改写点 | ✓（`ForEach(MaskOverlayStyle.allCases)`） |
| 4 | `PipeCoordinator.swift:227-230` | M-2 预案① request 形态 | ✓（元组 :227） |
| 5 | `PipeCoordinator.swift:264-272` | M-2 函数签名 | ✓ |
| 6 | `PipeCoordinator.swift:282` | M-2 unwrap 门 | ✓ 逐字 |
| 7 | `PipeCoordinator.swift:289-292` | M-2 DrawnMaskRasterizer | ✓ |
| 8 | `PipeCoordinator.swift:298-307` | M-2 effectivePlane | ✓ |
| 9 | `PipeCoordinator.swift:2434-2441`（+ :2446 调用） | M-2 caller payload 门 | ✓（`hasAnyPayload == true` :2441） |
| 10 | `AIMaskEditing.swift:36-43` | m-4 被推翻注释 | ✓（person :41-43 / depth :36-38） |
| 11 | `LayerEditingState.swift:284-290`（:287） | m-4 被扩展判据 | ✓（`== .segment` :287） |
| 12 | `AIMaskEditing.swift:158` | m-5① | ✓ |
| 13 | `MaskToolbarView.swift:353-363` | m-5② | ✓（注释 :353 / 按钮 :363） |
| 14 | `AdjustmentTransfer.swift:193-195` | m-5③ | ✓ 三行逐字（无漂移判定正确） |
| 15 | `scribbleNotSupported` 全仓 grep | m-5④ | ✓ 恰 5 处与 plan 口径逐字吻合 |
| 16 | REQUIREMENTS :735-737 + STATE current_phase | goal-backward / R6 前提 | ✓（M9AIM 三行原文；STATE near = R6 在飞） |

## 四、观察项（非阻断，1 项）

- **O-1 ΔN 分账上界直和与申报带上界差 1**：分账带宽 T1 +5..6 / T2 +5..9 / T3 +6..9 / T4 +4..6 上界直和 = 30，申报带 +20..29 上界 = 29。成因 = v2 上调 T2/T3 后总带未取直和（v1 带 20..27 恰为直和）。带为预计区间非硬顶、构成明细「合计 27-29」按 T1/T4 不取满上界口径、「一法多断言可压」+ 收口轮按实数对账 + 越带理由落 SUMMARY 兜底在位——**不改放行判定**；收口轮若实数落 30（越 charter +2），SUMMARY 申报即可，无需 plan 期改文。

## 五、放行判定

**放行**——executor 可启动（前置 = R6 修复批收口 + guard 让位，front-matter depends_on 在位）。

- M-1/M-2 两条 major 修法落点全部实锚亲核在位，plan/CONTEXT 双侧同步完整；
- m-1..5 五条 minor 全落（含 m-5 四子项逐字核）；
- goal-backward：M9AIM-01..03 三 AC 承载链完整，修复零缺腿；
- ΔN 带四处一致、越带申报句在位（O-1 为算术口径观察，收口轮消化）；
- 残项：**0**（O-1 不构成残项，登记收口轮留意）。

> Checker 本批零 commit、零构建；本文件 = 唯一产出，orchestrator 收割。

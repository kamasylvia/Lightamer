# M9-4 修复终验（checker，2026-10-25）

> 对象 = `M9-4-PLAN.md`（v2）+ `CONTEXT.md` 对照 `M9-4-PLAN-REVIEW.md`
> （PASS-with-notes：1M+4m+2obs）。零 commit、零构建、纯读评。
> 方法 = 逐条核真落（fixer 声称落点全部代码/账本亲核）+ Goal-backward
> + ΔN 自洽。**亲核 25 锚**（代码 15 + 账本/前站 6 + 文档交叉 4）。

## 档位结论

**放行**（error 0 / 残项 2——均台账级，不阻断执行）

评审 1M+4m 修复全部落真且与代码事实吻合；两 obs 处置正确（一不处置
有据、一「无需改文」结论正确但补注声称与事实有出入，见残项 2）。
Goal-backward 零缺腿；ΔN 带与终带算术自洽且前站带/基线全部亲证。

## 逐条核真

### M-1① D-M9SP-8 断言改写 — 落实（亲核 3 锚）

- **代码事实**：`PipeCoordinator.swift:2506-2515` 亲核——注释明文
  「M8-3 T3 … THUMBNAIL stays legacy (the M3-3 thumbnail gate twin —
  the grid consumes display-ready SDR planes and the thumbnail
  cache-key space never moves)」+ `guard resolution != .thumbnail …
  return .legacy`。评审断言的「M8-3 T3 显式 process 层设计决定」定性
  与代码逐字吻合。
- **CONTEXT v2**（D-M9SP-8 第四段 :186-199 + THUMBNAIL 专段 :200-210）：
  已改写为「M8-3 显式设计决定的修订（非补漏）」+ M8-3 注释同批修订
  + DECISIONS 单独申报条目（区别于 9 点补漏性质）——**旧误引句
  （tail-policy 先例/勿混）全查零残留**。
- **红线 4 同步**（plan :18 + CONTEXT 红线面）：「.legacy 缺省腿属
  bug」保留 ✓、guard 定性改「设计修订」✓；**X3 引用同步**
  （:308-312 清单正本双指 D-M9SP-8 第四段 + plan T2 Action 3③）✓。

### M-1② 未穿清单显式化 — 落实（亲核 8 锚 + 全仓完备性 grep）

- **全仓完备性亲证**：`rg "RenderPipeline\.(process|processComposite)\("`
  App/Sources + LightamerCore/Sources = **恰 16 处调用语句**，与 plan
  分类 **4 已穿 + 9 未穿 + 3 豁免 = 16** 一一对应，零遗漏零多余。
- **未穿 9 点逐点亲核均 `.legacy` 缺省**（参数尾无 renderProcess）：
  QuickLookRenderer `:287/:296`、PipeCoordinator `:2001`（eyedropper，
  参数止 :2009）/`:2073`（followEdgesSurface 子 run，参数止 :2081）/
  `:2161`（filmic auto，止 :2169）/`:2607/:2626`（EDR override 双路，
  止 :2635）、ColorMatchService `:205/:214`。fixer 补的 `:2073`
  亲核属实（评审 8 点外真实第 9 点）。
- **已穿正资产亲证**：主渲染双路 = `:2521`（processComposite）/
  `:2543`（process），`renderProcess: migratedProcess` 落 :2540/:2553；
  EXPORT 主腿 = ExportRenderer `:542/:556` 调用、`renderProcess:
  documentProcess` 落 **:550/:562**——fixer 勘正行号（评审引
  :555/:570）**逐字精确**。
- **机检面 grep 串有效**：`RenderPipeline.process` 是真实 API 族名
  （PC :103 注释即用此称），一网打尽成立。

### M-1③ 超线预告 — 落实（4 处同款）

plan 裁定权归属钉（:63-68「穿线超线预告」）+ 红线 4 末句 + T2
Action 3③ 末段 + CONTEXT D-M9SP-8 末段（:218-222）——四处一致：
预期触「超 10 行」属计划内申报（预授权 + DECISIONS 记实数与逐点
清单），其余四类扩面照旧硬停。执行者误判面已封。

### m-1 键数 4→5 — 落实（亲核 2 锚 + 5 处同步全查）

- **事实亲证**：xcstrings `panel_film_migrate_*` 现役恰 **5 键**
  （title/body/button/cancel/**confirm** 逐键在册）；`panel_process_
  migrate_*` 现有键 **0**（新键族无撞）。
- **五处同步全在**：frontmatter xcstrings 行（:37，含 confirm 勘正
  注）/ T2 Action 5③（:263-265）/ T2 验收机检（:285「5 键含
  confirm」）/ T5 Action 4（:381，15-17→**16-18**）/ CONTEXT
  D-M9SP-7③（:148-150）。修复记录声称五处，实查五处齐。

### m-2 T3 引用笔误 — 落实

T3 Action 2（:310-312）已改「id 拼写照上游 c740f7b……X5 十 case
列表为正本」+ 笔误注记（勘误③ = 迁移通道泛化面；id 拼写属 X5/勘误④
面）——与评审 m-2 原文表述逐字对齐。

### m-3 豁免面登记 — 落实（亲核 3 锚）

- **代码事实**：SessionThumbnailRenderer `:22` 注释明文「Phase 8
  contract (禁改): the leg branches processComposite/process …」+
  `:35`「THROWAWAY per-run cache」+ 调用点 `:42/:59`；CullingView
  `:227` 调用 + `:229` `makeDefaultChain()`。豁免依据（禁改契约 +
  无 process 载体 / pristine 默认链）全部属实。
- **登记面**：T2 Action 3③ 豁免专段（:240-245，含 m-3 引标）+ 红线 4
  「豁免面禁穿」+ frontmatter DECISIONS 行（:49）+ CONTEXT D-M9SP-8
  豁免段（:211-217）。机械套红线撞禁改契约的误改面已封。

### m-4 GradeCatalog 措辞 — 落实（亲核 1 锚）

- **事实亲证**：`NodeOwnershipCatalog.swift:297-306` defaultLook 恰
  三条（Exposure/Contrast/Saturation），**无 colorWheels 条目**。
- **三处措辞同步**：plan 风险节 4（:428-432）+ CONTEXT H-SP4
  （:362）+ CONTEXT 红线 5（:415-416）均改「天然零改」并保留停手
  护栏（identityJSON 消费面逼改 = 停手上报）。

### 两 obs 处置

- **obs ΔN 上沿超 ROADMAP**：不处置——评审自注「非本 plan 义务」，
  前站实数落后对账面已有红线 12 覆盖。处置正确。
- **obs ParamsCoding 路径**：结论「无需改文」正确（plan read_first
  带文件名，执行可定位）；但修复记录声称「修复批在 CONTEXT 抽核域
  补注路径」——实查 CONTEXT :83 仍只写 `ParamsCoding.swift:22-28`
  无路径，**补注未实际发生**。台账措辞出入，登记残项 2。

## Goal-backward — M9SM-01/02 零缺腿

（REQUIREMENTS :743-744 原文亲核比对）

| REQUIREMENTS 要求 | plan 承接 | 判 |
|---|---|---|
| M9SM-01 LGG 分离 + Offset 新轴 | T1 kernel 四轮（Offset→Lift→Gamma→Gain，X1 公式逐条） | ✓ |
| process v3 双臂 + M6-2 五件套 | T2 Action 1（case/all/current :90/switch 补腿/AGENTS 账本）+ Action 2 冻结双臂 | ✓ |
| 新公式 golden vs 上游数值锚 | T1 解析锚套件移植（ΔEV≈1/分离比 ≥4×/中性 1e-6/往返 1e-4，tolerance 注释引上游行） | ✓ |
| v2 旧档逐位零漂移负测 | 冻结臂 golden 原样主门（红线 2）+ 缓存键 legacy/v1/v2 恒等负测② + `Params()` 编码 hash 钉死（H-SP2） | ✓ |
| M9SM-02 LUT 表扩（「+24」→ OQ-3 修正 10 行+7 曲线+6 gamut，修正已申报） | T3 全件 + golden + add-only 断言 | ✓ |
| Filmstrip stars/编辑态磁贴 | T4 Action 1（stars + 双态 accent edge/selectedRing 核验，D-M9SP-5） | ✓ |
| Show in Finder | T4 Action 2 三门 + AX id | ✓ |
| XPan ratio 三行 | T4 Action 3（65:24 / 2.75:1 / 6:17 + dn + bits 双向） | ✓ |
| 验收形态：逐件定向 + zh-audit PASS | T5 Action 2/4（定向 IOP+APP + zh-audit 双 PASS） | ✓ |

**零缺腿**——M9SM-01 五要素、M9SM-02 四件 + 验收形态全部有承接有验收。

## ΔN 自洽 — 通过（亲核 5 锚）

- **本批构成**：T1 +4..5 / T2 +3..4 / T3 +2..3 / T4 +2..3 / T5 0 →
  下沿 4+3+2+2+0 = **11**、上沿 5+4+3+3+0 = **15** ✓；下沿越 charter
  10 已申报理由（缓存负测三件不可并法）。
- **基线亲证**：R6-SUMMARY:55「全套终值 = **4292/35/0**」在册。
- **前站带亲证**：M9-1 plan estimated_tests **+20..29** / M9-2
  **+15..20** / M9-3 **+14..19**——三 plan 逐一直读吻合；三前站
  SUMMARY 均无（与评审观察一致，plan「开工前亲核实数落基线表达式」
  纪律在位，红线 12 + baseline/expected_all 双字段承载）。
- **终带算术**：4292+(20+15+14+11)=**4352** ✓；4292+(29+20+19+15)
  =**4375** ✓。与 plan expected_all / CONTEXT 红线 12 / ΔN 预算表
  合计行三处同值。

## 残项登记（2，均不阻断）

1. **files_modified 缺两文件行**（台账完备性）：未穿 9 点中 4 点落在
   `LightamerCore/Sources/Export/QuickLookRenderer.swift` 与
   `App/Sources/Lightamer/State/ColorMatchService.swift`，二者必被
   T2 穿线批触改，但 frontmatter files_modified 未列（PipeCoordinator
   行只登记自身五点）。**缓解**：落点正本在 T2 Action 3③ 显式清单 +
   机检 grep 一网打尽 + 豁免面反面登记，执行者以 Action 3③ 为准即
   无漏。建议 execute 期随手补两行，不构成退回理由。
2. **修复记录 obs-ParamsCoding 行补注声称与事实不符**：声称「CONTEXT
   抽核域补注 = LightamerCore/Sources/Foundation/」，实查 CONTEXT :83
   无路径补注。该行同载「无需改文」结论且结论正确（真实路径存在、
   read_first 文件名可定位），执行零影响——仅修复记录台账措辞出入，
   登记在案即可。

## 放行判定

**放行**。1M+4m 全部修复落真且经代码/账本亲核吻合（含 fixer 声称的
两处亲核增量 :2073 / CullingView :227 均属实）；Goal-backward 零缺腿；
ΔN +11..15 与终带 4352..4375 全链自洽。两残项均台账级（一处 execute
期顺手补、一处仅记录），不影响执行正确性。可进执行（T1 起，C 档门控
照 plan）。

## 抽核锚点清单（25）

| # | 锚 | 结果 |
|---|---|---|
| 1 | PC :2506-2515 thumbnail guard + M8-3 注释原文 | ✓ |
| 2 | PC :2521/:2543 主双路 + :2540/:2553 migratedProcess | ✓ |
| 3 | PC :2001-2009 eyedropper 缺省 | ✓ |
| 4 | PC :2073-2081 followEdges 缺省（fixer 补点属实） | ✓ |
| 5 | PC :2161-2169 filmic 缺省 | ✓ |
| 6 | PC :2607-2635 EDR 双路缺省 | ✓ |
| 7 | QuickLookRenderer :287/:296 缺省 | ✓ |
| 8 | ColorMatchService :205/:214 缺省 | ✓ |
| 9 | ExportRenderer :542/:550 + :556/:562 已穿（勘正行号精确） | ✓ |
| 10 | 全仓 RenderPipeline 调用 16 处 = 4+9+3 恰覆盖 | ✓ |
| 11 | SessionThumbnailRenderer :22/:35/:42/:59 禁改契约 | ✓ |
| 12 | CullingView :227/:229 makeDefaultChain | ✓ |
| 13 | NodeOwnershipCatalog :297-306 defaultLook 三条无 colorWheels | ✓ |
| 14 | xcstrings panel_film_migrate 恰 5 键（confirm 在册） | ✓ |
| 15 | xcstrings panel_process_migrate 现有键 0 | ✓ |
| 16 | R6-SUMMARY:55 4292/35/0 | ✓ |
| 17 | M9-1 plan +20..29 | ✓ |
| 18 | M9-2 plan +15..20 | ✓ |
| 19 | M9-3 plan +14..19 | ✓ |
| 20 | 三前站无 SUMMARY（实数落纪律前提成立） | ✓ |
| 21 | REQUIREMENTS :743-744 M9SM-01/02 原文 | ✓ |
| 22 | CONTEXT D-M9SP-8 三段（穿线/THUMBNAIL/豁免/超线）v2 文本 | ✓ |
| 23 | CONTEXT 红线 4·5 / H-SP4 / X3 / D-M9SP-7③ 交叉同步 | ✓ |
| 24 | plan 红线 4 / 裁定权钉 / T2 3③ / T2 5③ / T2 验收 / T5 4 / 风险 4 / T3 2 修复落点 | ✓ |
| 25 | CONTEXT :83 ParamsCoding 无路径注（残项 2 反证） | 出入 → 残项 2 |

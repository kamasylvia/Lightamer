# Plan 09-05 — 执行决策（DECISIONS）

> 签核 plan（不写功能代码）。本文件记录签核执行期的授权路径与计量通道决策。
> 体例同 07-3 / 09-04 DECISIONS。

## D-09-05-T1-1: C 档第 3 停执行记录（终签核授权路径）

**决策**：plan 纪律「VALIDATION 产出后停等用户确认才翻账（T3）」的停等授权已由用户
显式给出——2026-09-26 用户指令「**继续全自动推进 lightamer,下一项:09-05 签核**」=
终签核授权；同时 `.work/config.toml [gsd]` 已由用户侧恢复 `auto = true / paused = false`
（本会话每任务边界复核通过）。先例 = D-07-3-T5-1「续班 executor 指令 = 终签核授权，
签核结论以 VALIDATION frontmatter 为准，用户终验留 verify-work 轮」。

**落账**：`09-VALIDATION.md` status: validated + nyquist_compliant: true；T3 翻账
（REQUIREMENTS Delivered ×9 + TODO/GOAL-STATE 收口）照常执行并在 SUMMARY 对应
AC 项注记授权路径；用户终验 = Phase 9 verify-work 轮（VALIDATION Manual-Only 10 行
随该轮一并走查）。

Reversibility：高（签核结论可被 verify-work 推翻重开；Manual-Only 行为正式挂账）。

## D-09-05-T1-2: PERF-07 复核通道 = clean Release 构建 + 直启注入布局固化

**决策**：9-4 验收必办项⑤「门数字以最终代码再复核」的复核通道按以下固化流程执行：

1. **必须 clean 构建**：增量 Release 构建（`-derivedDataPath build` 复用 9-4 产物目录）
   实测产出 host 与 `LightamerCore.framework` 不一致对——host 二进制引用现行
   `SidecarStore.init(destination:debounce:clock:)` 符号而框架为旧签名，注入后 dyld
   `Symbol not found` 静默死链；且该症状与「注入路径错误/签名错误」表象难以区分
   （裸启正常、注入即死、零输出零 crash report）。`rm -rf` Release 产物后 clean
   重建即自愈。**终账门数字只认 clean 构建**（0.490s）。
2. **注入布局三件套**（clean 构建下）：①clean 构建已自动内嵌 `LightamerTests.xctest`
   入 `Lightamer.app/Contents/PlugIns/`（Debug 同形——9-4 时代的 `build/Release` 顶层
   独立 xctest 形态不再出现）；②`libXCTestBundleInject.dylib` 取自 Debug app
   Frameworks 拷入 Release app；③XCTest 依赖闭包以符号链补入 app Frameworks
   （XCTest/XCTestCore/XCUIAutomation/XCTAutomationSupport.framework +
   libXCTestSwiftSupport.dylib → Xcode platform 目录），此后 `DYLD_INSERT_LIBRARIES`
   之外的 DYLD_* 路径变量可全部省略。
3. **重签照旧**（D-09-04-D9 惯例延续）：`codesign --force --deep --sign "Lightamer Dev"`
   + entitlements；实测 `get-task-allow` 单 entitlement 与 cs.* 双 entitlement 两种
   形态均可注入（差异不在签名）。
4. **判定口径**：门数字三轮对账（0.419 / 0.435 / 0.490）同量级即视为稳定；本轮
   0.490s ≪ 5s 门，不触发「不达标停下报告」条款。

**教训**：perf 计量通道的「一次性环境处置」必须落成可复现配方（本轮即因 9-4 仅记录
签名半边、布局半边缺失，排障耗时约 40 分钟）；已补记 `.work/09/perf.md` 终值节。
Reversibility：高（纯计量通道，工程零改动）。

## D-09-05-T3-1: 翻账注记口径（REQUIREMENTS 九项 + PERF-07）

**决策**：REQUIREMENTS 翻账按 Phase 7 体例（checkbox 翻转 + 缩进 Delivered 注记行，
原文不改写），三条必附注记落位：

- **SESS-06**：culling v1 = 2 图 cap（D-09-CONTEXT-6），4 图扩展位与同步缩放挂后
  ——SC#4 判定不受影响（「多图并排」语义 2 图已满足，ROADMAP 措辞「multi-image」
  的下限口径由 CONTEXT 裁决背书）。
- **SESS-05**：孤儿处置 = 「移除（带确认）/ 忽略（meta KV 持久化）」两动作，永不
  硬失败——对应 REQUIREMENTS 行 edge case 措辞的完整兑现。
- **HIST-05**：跨图 undo 组（批级撤销）defer v2（per-image commit 可退）+ skip 集
  边界 `< ashift 15.0`（D-09-04-D1 公式修正）+ pristine 目标铸造 doc 自洽
  （imageID 新铸 + 0/0 stamp + driftDetected 按文件自身重算不误报——9-4 验收注记⑥
  在 VALIDATION Per-Requirement Annotations 落位）。
- **PERF-07**：勾选附终值注记（0.490s Release/SSD）；**PERF-06 不勾**，行内追加
  「工作基线已落账 + 60fps 门本体 Phase 15 清算」注记（plan T3.1 口径）。

Reversibility：高（文档层）。

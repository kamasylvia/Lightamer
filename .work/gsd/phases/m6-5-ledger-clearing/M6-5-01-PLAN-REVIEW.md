# M6-5-01 PLAN 评审（独立 zcode 路，2026-10-16）

> 评审身份：独立 plan 评审（替代 omp 路），零共享上下文。
> 输入 = `M6-5-01-PLAN.md` + `M6-5-CONTEXT.md` + 七份挂账正本（M5-1
> VALIDATION/FILM-LEG-FIX §4、M5-2、M5-3、M6-1、M6-2、M6-3、M6-4
> VALIDATION 挂账节）+ 代码锚点 HEAD 亲验。
> 结论头：**PASS' / 3 error + 4 minor——须修后放行**（error 全部是
> 「按 plan 原文执行会批内卡死或交付半修」级，修法均明确、量级不变）。

---

## E-1（error）T1 修一半：第二 repo 路径写腿 `testUndoToTopKeepsRasterDrtCarrier` 漏网

**证据链（HEAD 亲验，全链闭合）**：

1. `Tests/LightamerTests/RasterEditFaceTests.swift:202-222`——
   `testUndoToTopKeepsRasterDrtCarrier` 经 `loadRaster("srgb-matrix-8.tif")`
   （:205，**repo fixture 路径**）后 ：209 `recordDrtChange` + :213 `undo()`，
   **零入口前清、零 defer 清扫**。
2. 写腿接线：`EditorState.recordDrtChange`（EditorState.swift:285）→
   `notifyDrtChange` → `PipeCoordinator.drtRecordDidChange`（:612-618，
   `scheduleSidecarWrite()`）；`undo()`（:1848-1855）**也**
   `scheduleSidecarWrite()`（"position moved — persist it too"）。
   `load()`（:1161）对每次新 URL 挂
   `SidecarStore(destination: sidecarURL(for: repo fixture))`——写目的地
   就是 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`。
3. 时序：该测试仅睡 ~100ms 即返回；SidecarStore 2s debounce 写在**测试
   返回后**落地（Task 持 store 强引用，进程存活即触发）。
   `makeSidecarDocument()`（:1458）无 pristine 抑制（只 guard
   decoded/editorState/imageID）——undo 到顶照写（M6-2 VALIDATION :60
   在册排除项「undo 到顶后写腿仍写 carrier 值」直证）。
4. 旁证：现树孤儿在盘（`Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`
   untracked，mtime = 最近全套轮窗口）；`7bc6365`（M5-1 修 Export 写方 +
   restore 读方前清）之后孤儿仍五度全套轮再生——restore 法 flush 后无
   再调度写、其 defer 应确定性胜出，**plan 对 M5-1 误宣告的归因
   （「defer 清扫输给迟到 write-behind」落在 restore 法自身）是错位的；
   真残写源 = undo 法的 post-test debounce 写**。

**对 plan 的冲击**：T1 只 temp 化 restore 法后，undo 法继续在 repo 路径
产孤儿。T1 定向轮的「轮毕 find 零命中」可能**假阴**（undo 法按字母序
最后执行，定向宿主可能在 2s debounce 前退出，写永不落地）；T9 `--all`
轮 App bundle 后续测试使进程存活越 2s → 复扫必命中 → **批卡死在 T9**。

**修法**：T1 action 扩为两法同改——restore 法 + undo 法都走
`tempFixtureCopy`（undo 法断言全在 carrier 面，与文件无关，换 tmp 副本
零语义影响）；`loadRaster` 加 URL 形参或加 `loadRaster(at:)` 孪生。
验收与复扫条款不变（已覆盖）。风险节「回退预案 = 保持 repo 路径写」
同步作废（与根治目标矛盾）。

## E-2（error）T2 字段清单不全：同一既有档臂还静默丢 5 个元数据字段

**证据（HEAD 亲验）**：

1. `LightamerSidecar` 文档全字段面（:250-377）逐字段对表
   SessionBatchApplier 既有档臂提升面（:113-118 六项）+ 构造点
   （:149-163 九参）——**除七 additive 字段外，`rating`(:293) /
   `flag`(:297) / `colorLabel`(:300) / `keywords`(:306) / `note`(:309)
   五个 optional 元数据字段同样被丢弃**（构造点不传 = decode 出 nil）。
2. 产线确有写腿持久化它们：`LightamerCore/Sources/Session/MetadataService.swift`
   :85/:95/:104/:122/:145——setRating/setFlag/setColorLabel/setKeywords/
   appendNote 全部 decode → mutate 字段 → write `.lra`。带 rating/
   keywords/note 的目标图过 batch apply（Copy Adjustments）= **库内组织
   元数据静默清除**，与七字段同族「数据保真缺陷」（M6-2 挂账 #2 原文
   定性）。
3. 根因：plan 七字段清单 = M6-2 挂账 #2 原文照抄，而挂账原文本身就漏列
   ——字段名锚「LightamerSidecar.swift:317-365」行区间天然排除
   :293-309 元数据族。**M6-2 挂账与 plan 双层未做全字段面对照。**

**修法（二选一，DECISIONS 记录，禁静默半修）**：
- (a) 携带面扩为 **12 字段**（七 additive + 五元数据；语义同为「携带
  目标档自有文档级状态，paste 只动调整结构」），测试断言 12 全带；
- (b) typed 范围外裁定：元数据族另立挂账（转 V2 或后续 fix batch），
  CONTEXT §1 C2 现状核查与 M6-2 挂账对表同批补记，T2 测试显式断言
  现状边界。
推荐 (a)——量级仍 S-M（+5 捕获行 +5 构造参 + 测试断言扩面），且一次
清干净避免第三批再开同族挂账。

## E-3（error）T6 门基线预期错误：`String(localized: "…\(` 在册合法形态现树 27 处命中

**证据（HEAD 实跑）**：

1. plan T6 的 grep（`String\(localized: "[^"]*\\`）在
   App/LightamerCore/LightamerIOP 三 Sources 实测 **27 命中**
   （BeforeAfterState :46 / ExportQueueFaceView :109/:128/:168 /
   ExportPanelView :346 / SettingsPages :526/:1191 / ACASettingsModel
   :219 等）。
2. 抽验目录：`beforeafter_compare_step %lld` /
   `export_face_add_selected %lld` / `export_targets_header %lld %lld` /
   `settings_lcr_dim_semantic %lld` 全部 **PRESENT** 于
   `Resources/Localizable.xcstrings`（1923 键）——
   `String(localized: "静态键 \(数值)")` 是 xcstrings **格式键合法惯例**
   （构建期提取为占位符键、zh-audit V15 form 1c 在册），**不属于**
   M2-9 F-2 禁形（F-2 = 动态查表键 `String.LocalizationValue("prefix_\(x)")`
   运行时回退裸键）。CONTEXT F1/M6-4 N-3 的「候选」措辞被 plan 硬化成
   「禁形 + 零命中基线」，定性滑步。
3. 「预期零命中基线」与 red_lines「T6 新门零命中基线」按现树**不可满足**
   ——按 T6 处置协议逐条「改显式 switch 静态键」= 大改 27 处在册合法
   用法（破坏提取键、远超 S 量级、六格式键全动）；「登记豁免」27 处 =
   门变噪音且 grep 形态无豁免机制。
4. **真缺陷确有 ≥1 活体**：SettingsPages.swift:1191
   `String(localized: "settings_displays_overridden \($0)")`（$0 = String
   路径 → 提取键 `settings_displays_overridden %@`）——目录只有**静态键
   `settings_displays_overridden`，无占位符变体** → 运行时回退裸键
   （F-2 家族活体，overrides 副标题显示原始键文本）。

**修法（T6 重刻，三选一）**：
- (a) 门升级为脚本化：提取插值键字面量前缀 + 占位符形态 → 目录
  PRESENT/ABSENT 判定（zh-audit 提取器扩展形态，V15 先例同族）——门
  语义 = 「ABSENT 键零命中」，合法格式键天然豁免；
- (b) 保留 grep 门但分诊协议改写：命中预期 ~27、按「目录占位符变体
  PRESENT = 合法格式键（豁免类）／ABSENT = 真缺陷逐修」分诊，
  red_lines 零命中条同步改「ABSENT 键零命中」；
- (c) 活体缺陷 `settings_displays_overridden` 至少顺带清偿（改显式
  `String(localized: "settings_displays_overridden")` + 路径拼 Text 后段，
  或目录补 %@ 变体键）——无论门形态如何选择，此缺陷不入账即违背本批
  「挂账清算」宗旨。

## M-1（minor）T2/T1 bundle 归域错：`--bundle LIB` 非法 token，且 SessionBatchApplierTests 在 Sessions

- `Scripts/test-direct.sh:165`：`BUNDLES=(IOP IOPParity Layers Library
  Sessions Export App)`——**`LIB` 不是合法 `--bundle` 值**（:191 error
  exit）。BUNDLE-MAP 标签 LIB→Library、SESS→Sessions 是映射标签非
  token。
- `SessionBatchApplierTests.swift` 归 **SESS/Sessions**（BUNDLE-MAP :400
  + `Project.swift:671` `LightamerTestsSessions` :694 成员亲验）——T2
  验收命令应为 `--bundle Sessions SessionBatchApplierTests`。
- front-matter `test_bundles: [APP, LIB]` 应为 **[APP, Sessions, Export]**
  （T1=APP ✓；T2=Sessions；T4=EXPORT 域漏列——ExportGainMapTests =
  EXPORT，BUNDLE-MAP :737）。

## M-2（minor）T4 法数滑差：ExportGainMapTests HEAD 已 25 法非 24

- `grep -c "func test"` = **25**（CONTEXT D2 记「24 法亲点」= 计数漂移，
  `c077784a` 容器 golden/reimport 批后未复核）。T4 +1 后 = **26**。
  AC「25 法 = 24+1」应订正「26 法 = 25+1」。本批以账面精确为纲
  （M6-3 minor-1 同源滑差先例），执行前订正，防 T9 对账自扰。

## M-3（minor）T3 范围缺口：算术伴文 + 全仓另有两处 19-tool 残留

- `McpServerController.swift:15` 与 :448-449 的「19-tool」均带
  「(5 editing + 14 culling)」伴文算术（5+14=19）——只改 19-tool→20-tool
  会产出「the closed 20-tool set exactly (5 editing + 14 culling)」内部
  矛盾句。需同步 **5 editing → 6 editing**（match_color 属 editing 族）。
- 全仓 grep 另有两处 19-tool 注释：`McpRenderParityTests.swift:564` +
  `DefaultFaceTests.swift:361`——同族陈旧（19-tool closed set 已被
  match_color 破），T3 顺带（仍纯注释零行为）或 DECISIONS 显式登记
  范围外，禁留新陈旧账。
- T3 验收 grep 未覆盖伴文算术——建议补 `grep -n "5 editing" ... 零命中`。

## M-4（minor）T8「逐字一致」AC 与供给措辞不符

- M6-2 `M6-2-01-DECISIONS.md` §6（:68-76）触发条款原文 =「**首个真实
  分叉批**的接线件挂账」+ 四件套①②③④（含「分叉 iop 在 `process` 内
  消费 `RenderProcess.resolving(piece.renderProcess)`」完整形）。
- CONTEXT §5/5 与 plan T8 写「首个真实 iop 语义 bump 批」——同文对象
  实为 **M6-2 VALIDATION 挂账 #1**（「首个真实 iop 语义分叉/bump 批」）
  而非 DECISIONS §6。执行者按 §5 措辞落盘即违反 plan 自己的「与
  DECISIONS §6 逐字一致」AC。
- 修法：AC 放宽为「与 M6-2 VALIDATION 挂账 #1 同文、DECISIONS §6
  四件套语义逐条镜像」，或登记文本改抄 §6 原句。二选一，执行前定。

## A-1（放行面复核结论——逐维度）

1. **销账 6 项证据全部可复核**：A2 `7bc6365f` 在库 + 五轮全套绿
   （3631/3689/3725/3759/3841 逐值对上 VALIDATION 正本）；A5 同上五轮
   （M5-3 3631 exit 0 亲读）；A7 `5ff6ff48` + `ColormatchModule.swift:84-103`
   NSLock holder 亲读 + `ColormatchResolverBox.shared =` 全仓 0 赋值点 +
   ColormatchResolverBoxTests 4 法在位；B4 `908526fe` + M6-1 挂账 #4
   原裁「观察项，无动作」；C4 M6-2 挂账 #4 留痕在案；D3 M6-3 挂账 #3
   原裁零动作；E6 M6-4 挂账 #6 读账履行。**销账链成立。**
2. **转 V2 九项对表**：A11/A15/A18/B3/C1/D1/E1/E4/E5 ↔ 各 VALIDATION
   挂账原文逐项语义一致（E5 两残差、E1 D-06 双件、D1 禁自建 APP1 +
   C 路同批条款齐全）；V2-PROPOSAL 既有章节一..六，追加「七、」编号
   正确；触发条件档体例一致。C1 措辞见 M-4。
3. **--all 口径**：3841（M6-4 实测）+ 2（修批 `984e0256`/`b49215bb`）+
   3（T2+2/T4+1）= 3846 算术 ✓；带 3840..3844 与 M6-4 VALIDATION :282
   申报一致；ΔN=0 异常停手上报条款在册 ✓；孤儿复扫验收 T1+T9 双点
   在册 ✓（M5-1 教训的「扫对窗口」半边已被吸收——但根因定位错位见 E-1）。
4. **T1 helper 锚**：DepthMaskEditingTests.swift:270-281 helper +
   :22-32 setUp/tearDown UUID 目录生命周期亲读 ✓ verbatim 可搬；
   RasterEditFaceTests 7 法 ✓（AC 准确）。
5. **其余写腿全树扫描**：DepthMaskEditingTests / AIMaskPatchFlowTests
   已 tempFixtureCopy ✓；FilmCoordinatorTests tmp URL + defer ✓；
   RasterRoundTripTests :95/:224 只读 decode 源、:294-300 已 tmp 化 ✓；
   NLMeans / ProjectReadOnly 无 repo-fixture 写面。App bundle 的 repo
   路径写腿全集 = restore + undo 两法（E-1 修后归零）。
6. **T5 锚点亲证**：ExportRecipe.swift 门③注释 :158-166 + peak guard
   :176-186（`drtOutput` 载体）+ ExportRenderer.swift:519
   （`drtTail!.record.peakLuminance`）——两锚准确，注记语义与 M6-3
   挂账 #4 一致，纯注释不越界 ✓。
7. **任务边界**：T1-T9 编号与内容对表 ✓；T7 不入 git（gui-acceptance
   gitignored，L073 口径）✓；T9 五正本翻账分工带执行时指令 ✓；
   red_lines 族（IOP/.metal/sidecar schema/Pipe/Project.swift
   dependencies/xcstrings/runModal/LocalizationValue）与批面匹配 ✓；
   `.work/config.toml [gsd]` auto=true / paused=false——流水线开，
   无暂停阻断 ✓。
8. **T4 断言设计**（非 uniform 面 + 非对称 base + flip 反置负测预案）
   逻辑成立：垂直 flip 在均匀面上不可检，非均匀是必要前提——预案二选一
   机制健全 ✓。

## 总评

**须修后放行**。骨架（六清偿 + 汇编 + 登记 + 确认轮、销账/V2 证据链、
红线族、算术口径）成立且证据可复核；但 E-1（T1 漏第二写腿——不修则
T9 必卡）、E-2（T2 七字段非全集——不裁则 C2 半修销不掉）、E-3（T6 零
命中基线被现树 27 命中证伪——不重刻则 red_line 不可满足）三条必须先
修订 plan 再派执行；M-1..M-4 顺手同批订正（bundle token / 法数 / 算术
伴文 / 逐字 AC 对表）。修订量级不改变批的 S-M 定性与任务序。

# M9-4 验收报告 — 双路 zcode 独立验收第一路（2026-10-29）

> 对象 = 九 commits `358523ce..83006dcb`（refs #14），基线 `7f089c9d`
> （M9-3 收口）。方法 = AC 逐条独立核对（file:line）+ 产品面 diff 逐文件
> 审 + 封存面 17 件机检 + 例外恰形核 + 全套独立复跑 + 反自取消双探针
> （主树掏空还原法）。executor 终报不轻信——全部关键断言实测复验。
> 正本 = `M9-4-SUMMARY.md` + `M9-4-DECISIONS.md` + PLAN v2 + CONTEXT；
> AC 源 = REQUIREMENTS M9SM-01..02。

## 结论

**PASS / 0 error + 3 minor + 3 obs**（B 级零；全套独立复跑 = 本路终值见
下节；双探针双真红后还原干净）。

- M9SM-01（ColorWheels v3 主件）：验收形态三件全数落真——新公式
  golden vs 上游数值锚（IOPParity 11 法 + IOP 转换 6 法逐法读验）、
  v2 旧档逐位零漂移负测（GradeKernelGoldenTests 两法零 diff 亲证 +
  冻结体 md5 同值 + 全套原样跑绿）、v3 bump 五件套全在位。
- M9SM-02（尾件四件）：LUT 10+7+6（add-only 钉死——X5 分组前缀恒等
  正解，曲线常数上游对拍抽查 3 条全中 + P3 peakNits 48）、Filmstrip
  stars、Show in Finder 三门、XPan 三行全落；zh-audit 双 PASS 本路
  复跑通过。

## 全套独立复跑（本路终值）

- 前置：guard G4 初判 BLOCK（Data 卷 24757MB<25GB）——**未走越门**：
  清可再生面（Lightamer DerivedData 容器 1.4G +
  SDKExplicitPrecompiledModules 257M）后全量重建，GUARD PASS
  （26331MB，free 79%）；同链 GUI/测试宿主 ps 清零验证 CLEAN；
  `machine-guard.sh --monitor 21600 &` 伴跑全程；caffeinate -dis。
- 本路终值：

```
BUNDLE|IOP       |813/1/0|peakRSS=7323MB| 960s|sampling=time
BUNDLE|IOPParity |565/10/0|peakRSS=6376MB|1636s|sampling=time
BUNDLE|Layers    |528/5/0 |peakRSS=1181MB| 460s|sampling=time
BUNDLE|Library   |785/4/0 |peakRSS= 751MB| 171s|sampling=time
BUNDLE|Sessions  |285/4/0 |peakRSS=1592MB|  60s|sampling=time
BUNDLE|Export    |385/4/0 |peakRSS=5398MB| 198s|sampling=time
BUNDLE|App       |1065/6/0|peakRSS=2832MB| 589s|sampling=time
TOTAL|4426/34/0|4074s   EXIT=0
```

- 七 bundle 分值与 executor 第四轮终值轮**逐位一致**（分值全同；
  peakRSS 本路 IOP 7323 / Sessions 1592 / Export 5398 略高——同族方差，
  全部 <8G 运行门，MEMFAIL 机检零触发）；时长 4074s vs executor
  4016s 同量级。

- 对账：executed = 4391（M9-3 基线亲核）⊕ +35 = **4426 精确**；
  skip 34 持平；fail 0。ΔN +35 构成 = BUNDLE-MAP 六行（IOP 6 + IOPP
  11+4 + IOP 6 + APP 4 + APP 4）与七 bundle 分值逐位复核。

## AC 逐条核对（file:line 实证）

### M9SM-01 ColorWheels LGG+Offset 主件

| AC 面 | 落点 | 本路核验 |
|---|---|---|
| 新公式 golden vs 上游数值锚 | `Tests/LightamerTests/ColorWheelsToneWheelGoldenTests.swift`（11 法） | identity 双 shape 逐位（accuracy 0，:152-175）；kernel-vs-referenceV3 参数点族四轮各一 + combined + 超域采样（t∉(0,1) 边界 + clamp/max 早退，:179-228，OQ-4 落实）；上游解析锚 6 法（ΔEV 每轮 +1 档表 :253-282 / Lift-Gain 分离比 ≥4× :286-295 / 中性 −10..+10EV 全影调 ≤1e-6 :299-310 / disc 零均值+strength·r :313-319 / disc↔stops 往返 1e-4 :323-335 / 越界截单位圆 :338-342）；ACEScc 常数与 Cat02WBMath 互验 :347-357 |
| v2 旧档逐位零漂移负测 | `Tests/LightamerTests/GradeKernelGoldenTests.swift` | **git diff 零**亲证（identity + 4 参数点两法原样）；缺省 piece `.legacy` → resolving `.v1` 冻结臂 |
| v3 bump 五件套 | `RenderProcess.swift` | case v3 账本 doc-comment :139-156 + all 尾插 :159 + current 2→3 :90-92 + processVersion switch 补腿 :185 + AGENTS.md:416 账本行 + 新旧 golden 三件套（上两行） |
| params 甲红线（offset additive + 判别子） | `ColorWheelsModule.swift` | `Params.offset: ColorWheelControl?` synthesized encodeIfPresent（:191-217 diff）；`isIdentityV3` 缺席→v1 判定/在场→四轮零基（:484-499）；`effectiveToneWheelParams` 渲染预解与面板投影单源（:501-508）；首编辑物化 = `ColorWheelsPanelView.v3Params`（:104-107）+ `v3Write` 每 tick 以投影为基 |
| 字节零漂 hash 钉死 | `ColorWheelsToneWheelGoldenTests.swift:365-384` | `Params()` 编码无 `"offset"` 键结构断言 + `pinnedDefaultParamsHash = 11640277816793824460`（与 SUMMARY 申报同值）；round-trip 双向 + 旧 JSON 无键 tolerant decode :388-410 |
| frozen 16-float 打包逐字节不动 | `ColorWheelsModule.swift` commitParams | 打包段零 diff（本路 diff 审亲证）；v3 镜像另路（`mirrorLock` NSLock + `paramsMirror` + `toneWheelMemo` 键=paramsHash，:253-256/:268-276 diff） |
| PipeCache 折键 resolved-arm | `ModuleBox.swift`/`IOPModule.swift`/`PixelPipe.swift` | 协议要求 + extension default nil（全模块零改）+ ModuleBox 转发；`prepareChain` enabled 分支折一处（:958-975，恰一 hunk）；ColorWheelsModule.processForkHash = resolved==.v3 才折 `StableHash.hash("lightamer.colorwheels.v3")` 否则 nil |
| 负测三件硬门 | `ProcessForkCacheKeyTests.swift` | ①同 params 字节 v1 vs v3 链不等 + 手工折叠交叉验证 :85-110；②legacy/v1/v2 与折前逐位恒等 + fork nil 三臂 :114-129；③v3 臂 params 变更链翻转 + fork tag hash 钉死 905990834909371860 :133-149。生产 `PixelPipe.chain` 与测试 `foldChain` 组合体同构亲证（同 withUnsafeBytes+StableHash.combine） |
| 迁移 UX 泛化四面 | `EditorState+FilmMigration.swift`/`PipeCoordinator.swift`/`FilmPanelView.swift`/`IOPPanelProvider.swift` | gate 二源（`hasFilmRecord \|\| hasColorWheelsEdits`，evaluate :46-49 + coordinator `hasColorWheelsEdits()` 读 isIdentityV3）；marker 二形（film VERBATIM / `commitProcessMigrationMarker(colorWheels:label:)` 普通 commit 零 params diff，EditorState:374-386 + runProcessMigration :966-990）；copy 中性化 5 键（`panel_process_migrate_{title,body,button,cancel,confirm}` 尾插 + `panel_film_migrate` 引用归零〔唯一命中=注释〕+ allowlist zh-audit.py:144-148）；双面板挂点（`ProcessMigrationInputs` 参数化 + Film :50 + ColorWheels :84-88 单行单动作） |
| 渲染入口穿线 9 点 + thumbnail 修订 | `PipeCoordinator.swift`/`QuickLookRenderer.swift`/`ColorMatchService.swift`/`MatchColorToolset.swift` | 9 点全穿：eyedropper :2135 / followEdgesSurface :2310 / filmic auto :2398 / EDR override 双路 :2898+:2910 / QuickLook 双路 :288+:297（document?.process 盘上真相）/ ColorMatchService 双路 :214+:247；THUMBNAIL guard 删特例全 resolution 穿 doc 值 + M8-3 注释改写新叙事（:2774-2790 diff，M-1① 申报一致）；豁免两件未穿（SessionThumbnailRenderer/CullingView 零 diff 亲证）；ColorMatchDocument carrier 缺省 nil（pre-M9-4 构造点零改）+ MCP target 腿 `sidecar?.process` 连带在册 |

### M9SM-02 尾件四件

| AC 面 | 落点 | 本路核验 |
|---|---|---|
| LUT encodings 表扩 | `LutEncodingCatalog.swift`/`LutTransferMath.swift`/`LutEncodingExpansionTests.swift`（6 法） | enum 10 case + all 表 27 行（scene 分组尾插 7 + display 尾插 3，linearRec2020 相对位不动 :18）+ gamuts 6 键 + 7 曲线 Float64 正逆双落笔；**add-only 钉死** = 分组前缀恒等（scene 前 10 + working 行位 17 + display 旧序 18..23 + 9 旧 gamut spot 值，`testOldRowsPrefixStable` :192-219——X5 分组尾插正解，plan Action 3「全表前缀」字面与 X5 内部矛盾，执行取 X5）；曲线常数上游对拍抽查（flog2/log3g10/clog2 k/logOffset/linSlope/linOffset 与 `git show c740f7b:…color_encoding_math.h` :210/:228/:236 逐值同）；peakNits 逐行照上游（P3 行 48，测试 :142）；6 gamut primaries/white 逐值对拍在册 |
| Filmstrip stars + 双态 | `FilmstripView.swift` | `FilmstripModel.ratingStars` 纯函数缝 + 行 UI（rating 直读——勘误①，nil 不渲染）+ AX id `filmstrip.row.rating.<id>`；isCurrent Circle/isSelected 色双态保留 |
| Show in Finder 三门 | `LibraryGridView.swift`/`FilmstripView.swift`/`NSMenuBridge.swift` | grid contextMenu + filmstrip contextMenu + Image 菜单（AI 项同区，menu 尾 separator 后）三门全落；存在性检查前置 + `activateFileViewerSelecting`（reveal 先例形，L057 无涉）；三 AX id 在册 |
| XPan 三行 | `CropOverlayHost.swift`/`CropPanelView.swift` | 3 case 尾插（rawValue "65:24"/"2.75:1"/"6:17"）+ dn 臂 (65,24)/(11,4)/(17,6) + picker 3 行 + ratio bits 双向映射（N/D 整数对入现 Int 存储，零 schema）；旧 7 档 dn 回归在册（SmallPoolUITests:48-53） |
| zh-audit 双 PASS | `Scripts/zh-audit.py` | 本路复跑 `--check` PASS（1770 source/2100 catalog）+ `--self-test` PASS；xcstrings 尾块纯插入（git diff 零删除行）亲证 |

## 封存面与例外恰形

- **封存面 17 件零 diff 机检全过**：DrtRecord / TerminalTailPolicy /
  DrtTailAssembly / Lut3dKernels.metal / DrtEotf / ExportQueueContract /
  六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/
  NodeGraphCommand / LightamerSidecar / HistoryStack / HistoryHash /
  PipelineDocument / V50Order / NodeOwnershipCatalog（GradeCatalog）/
  Registry / ModuleInstance / NodeGraphCommand——git diff 空输出逐件亲证。
- **例外恰形**：PixelPipe.swift **恰 2 hunks** 逐 hunk 对照申报——
  ①`prepareChain` 折一处（计划内豁免本体，注释即 D-M9SP-8 条款）+
  ②`assembleFilmLeg` `case .v2` → `case .v2, .v3` 编译器补腿（film 腿
  语义零变化，注释在册）——与 DECISIONS §3 申报恰形一致；`FilmTailPolicy.policyTag`
  同款补腿（该文件不在封存清单，申报一致）；ColorWheels.metal 纯
  append（git diff 零删除行）+ 现行 `grade_color_wheels` 函数体 md5
  **8943b9a434132c48f62b66d490c7664a** 与基线 `7f089c9d` 同值亲证（=
  申报值 8943b9a4）。

## 反自取消双探针（主树掏空还原法）

- **探针①（折键掏空）**：`ColorWheelsModule.processForkHash` 改恒
  `nil` → 增量重建 → `--bundle IOPParity 'ProcessForkCacheKeyTests'`
  → **TOTAL 4/0/2 真红**（负测①同 params 双臂键不等 + ③fork tag 钉死
  两法 fail；②legacy/v1/v2 恒等法在恒 nil 下仍绿——数学自洽，掏空后
  三臂本就零折）。
- **探针②（v3 公式改错）**：`ColorWheels.metal` gamma 段
  `precise::pow(t, p)` → `precise::pow(t, p * 1.01f)` → 重建 →
  `--bundle IOPParity 'ColorWheelsToneWheelGoldenTests'` → **TOTAL
  11/0/1 真红**（`testV3KernelMatchesReferenceParameterPoints` 参数点族
  562 断言失败；identity 法绿 = 中性早退分支不触 pow 路径，探针信号
  诊断面干净——红恰好圈定被改的公式路径）。
- **还原**：两探针备份还原（`git status` tracked 零残留亲证）→ 重建 →
  三类定向复跑全 OK（ProcessForkCacheKeyTests /
  ColorWheelsToneWheelGoldenTests / ColorWheelsLegacyConvertTests）。

## 执行期偏差质询

| 项 | 质询结论 |
|---|---|
| v3 scalar branch 形（§4） | **成立**。终版 kernel = per-channel scalar branch 直译 + 中性早退显式分支，与 CPU `applyToneWheels` 逐句同构；vector select 五探针轮失败史如实登记（证据未入册见 obs）。scalar 形对 parity 义务是保守正确选择，性能属后续优化面 |
| 字面钉四折跑教训 | **登记完备**。四笔修复各随轮 commit（`c095f1eb`/`d45e0fdd`/`1d24bce1`/`043e4a30`），SUMMARY 跑史逐轮对得上；L0xx-k 教训（bump/扩表的字面钉面 grep 不可穷尽，应随 bump 任务清单跑 `current.rawValue, 2\|all, \[.v1, .v2\]\|count, 17`）入 SUMMARY+DECISIONS §10 |
| 拟合残差实测 vs plan 粗化 | **申报诚实**。常见域实测 0.0308 vs plan 转写 ≤0.03（超字面 0.0008，断言带 0.035 且上游锚 0.05 容差双层在册）；极端域实测 0.143 vs plan ≈0.12（带 0.145 + hard cap 0.15 双层）；测试注释明写「the research "≤0.03" line is the same research 粗化」——非隐瞒，符合「升号近似」文案如实声明的 H-SP3 纪律 |

## 发现清单（B/M/m/obs）

### Minor（3）

- **m-acc1** DECISIONS §7 申报句「editing 守卫扩 = …（后者 = 通用
  isEditingContinuous D-H1 窗——**轮盘拖拽**/stops 滑杆全走）」与代码
  事实不符：`TrackballView`（`ColorWheelsPanelView.swift:420`）无
  onDragBegin 回调，轮盘拖拽的 live tick 走 `setLiveParams` 在
  `isEditingContinuous == false` 下**只 preview 不进窗**（
  `PipeCoordinator.setLiveParams` defensive 分支亲核）——v1 legacy 面
  同形（既有行为，非本批回归；stops/luminance 滑杆有 onDragBegin 确进
  窗）。影响 = 轮盘拖拽中迁移行的 editingInFlight 守卫不触发（v1 时代
  同样不触发，行为对称零回归）；属**申报措辞不精确**，非代码缺陷。
- **m-acc2** LUT add-only 申报词「旧 17 行 + 9 gamut **前缀恒等**」
  不精确：实际 all 表 = scene 分组尾插（新 7 行插在 appleLog 后），
  旧 17 行**非全表前缀**（linearRec2020 位 11→18）。实现符合 plan X5
  正解（「行序按上游 scene/display 分组尾插 + linearRec2020 位置不动」
  ——X5 与 plan Action 3「all 前缀 == 旧 17 行序列」字面**内部矛盾**，
  执行取 X5 且测试钉法正确：`testOldRowsPrefixStable` 钉 scene 前 10
  恒等 + working 位 17 + display 旧序 18..23 + 旧 gamut spot 值）；
  仅 SUMMARY/申报的「前缀恒等」一词应读作「分组前缀恒等」。
- **m-acc3** Finder 三门的 2 法弱断言：`testFinderDoorsAccessibilityRegistration`
  实质 = 自写字符串集 Set 自等（tautology，未从源码/AX 树读任何面）；
  `testFinderExistenceGuardSemantics` = Foundation FileManager 行为
  自证（非产品代码断言）。真 AX 树可达归走查配方（DECISIONS §11 有
  登记、MANIFEST §Finder 在册承接）——但 SUMMARY T4 机检「AX 三 id
  注册断言 ✓」措辞偏乐观，且 ΔN +35 越带申报中此 2 法断言力近零
  （越带主力法——负测三件/golden 参数点族/解析锚 6 法/五态表——
  断言力实足，越带结论不翻）。

### Obs（3）

- **obs-acc1** 负测三件跑在测试内 `foldChain` 镜像（与生产
  `PixelPipe.chain` 组合体同构已亲证）——镜像↔生产同步靠「verbatim
  mirror」注释纪律，未来 prepareChain 折叠序漂移（如 fork 先于
  params）测试不红。plan D-M9SP-8 本就指定「PipeHash.upstream 纯函数域
  表驱动」，属 plan 指定域的承接性质，非执行缺陷。
- **obs-acc2** DECISIONS §4 vector select 五探针轮证据未入册（临时
  alpha 写值轮已还原；M7-1 探针协议硬化先例要求探针留痕——教训已入
  §12 候选，留痕纪律待 LESSONS 批一并落）。
- **obs-acc3** `toneWheelUniformsBuffer` 在 `mirrorLock` 锁内
  makeBuffer + `MTLCreateSystemDefaultDevice()` fallback（首帧/缺
  device 时锁内分配一次性成本；申报「uniformsBuffer 同款纪律」的申辩
  可接受，无并发正确性问题——NSLock 读写互斥面完整）。

## G4 门与机器纪律

- guard G4 初判 BLOCK（24757MB<25GB）——本路**未行使任务书预设的越门
  路径**：清可再生面 1.66G 后 GUARD PASS（26331MB / free 79%），全量
  重建后复跑，全程 monitor 伴跑（MEMFAIL 机检同链生效）。
- 起跑前 GUI/测试宿主 ps 清零验证 CLEAN；测试宿主与 GUI 实例 parentage
  未触碰（本路无进程清理动作）。

## 验收界限

- AX 树走查（stars 行可达/Finder 三门 AXPress/四轮拖拽走查/升号观感
  并排）归 `gui-acceptance/m9-4/MANIFEST.md` 走查批（DECISIONS §11
  登记的分家）；本路验收 = 测试面 + 源码面 + 机检面。
- phase VALIDATION 与 M9 站收口另批（C 档停维持）。

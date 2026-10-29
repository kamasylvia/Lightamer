# M9-4 DECISIONS — 小件池执行期裁定记录(2026-10-29)

> 正本 = PLAN.md v2 + CONTEXT.md(D-M9SP-1..9 + X1..X6 + hazards + 红线 15 条
> + 转写勘误四条);本文件只记 **execute 期新裁定与偏差申报**。晨审可推翻。

## §1 穿线核验清单结论(D-M9SP-8 第四段 / T2 Action 3③ 的 execute 终态)

- **已穿正资产核验零工作量**:coordinator 主渲染双路(`renderCurrentChain`
  传 `migratedProcess`)+ EXPORT 主腿(`ExportRenderer` 的
  `documentProcess`,语句行 :550/:562)——亲核在位。
- **未穿 9 点全穿**(实际行号较 planner 漂移,逐点终态):
  1. `PipeCoordinator` eyedropper pickColor 线性链(实际 :2082 域)
  2. `PipeCoordinator` followEdgesSurface 层子 run(实际 :2255 域)
  3. `PipeCoordinator` sampleLinearNormMinMax(filmic auto 采样,实际 :2343 域)
  4./5. `PipeCoordinator` EDR/before-after override renderPreview(override)
     双路(实际 :2843/:2854 域)
  6./7. `ColorMatchService` extractStats 双路(processComposite + process)
  8./9. `QuickLookRenderer` 双路(:287/:296 域)
  - 穿线通道:coordinator 侧走既有 `documentProcessVersion`(nil →
    `.legacy`);ColorMatchDocument 增 `renderProcess`(缺省 nil——pre-M9-4
    构造点零改,headless/pristine = `.legacy` 即正确值);QuickLook 走
    `document?.process`(盘上 sidecar 真相)。
- **实际行数**:9 点 ×2 行(renderProcess 参数行)+ guard 修订块
  (~7 行)+ 注释改写 ~9 行 + ColorMatchDocument carrier ~8 行 ≈ 35 行——
  **触「穿线修正超 10 行」停手线**,按 plan 裁定权归属钉的**计划内预告**
  放行(M-1③):plan 已预授权该缝穿线,本条即 DECISIONS 逐点清单登记,
  不作方案失败论。
- **豁免面(m-3)判断登记**:
  - `SessionThumbnailRenderer`(:42/:59)——文件头 Phase 8 契约(禁改)+
    legacy session 库无 process 载体可读,机械套「一切渲染腿」会撞契约,
    **未穿,维持禁改**。
  - `CullingView`(:227)——pristine 默认链(`makeDefaultChain()` + 每次
    新 UUID + throwaway cache),无 doc stored process 可穿,**未穿**。

## §2 M8-3 thumbnail guard 设计修订(M-1①,单独条目)

- **修订对象**:`PipeCoordinator` 主渲染双路的 `migratedProcess` 闭包——
  M8-3 T3 的显式 process 层设计决定(`guard resolution != .thumbnail …
  return .legacy`,注释明文「the thumbnail cache-key space never moves」)。
- **修订内容**:删 thumbnail 特例,thumbnail 腿同穿 doc stored 值;
  M8-3 时代注释("THUMBNAIL stays legacy…never moves"段)同批改写为新
  叙事(M9-4 版注释在位)。
- **修订理由**:M8-3 时唯一 fork(film tail)在 thumbnail 腿恒 nil,grid
  与编辑器天然一致;M9-4 的 v3 fork 渲染在**链内**(colorWheels 是普通
  box),thumbnail 不穿 = 图库/胶条与主视图不同臂——用户可见撕裂。
  cache-key 空间问题由折键的 resolved-arm 收窄形消解:legacy/v1/v2
  thumbnail 键字节恒等(零折),只有 v3 文档进入新键空间。
- **修订性质**:设计决定修订(非补漏),区别于 §1 的 9 点补漏清单。

## §3 封存面例外申报终态(红线 5「恰两处」的偏差申报)

- **PixelPipe.swift 实际 2 hunks**(plan 预告恰 1):
  1. `prepareChain` 折一处(例外本体,逐 hunk 申报豁免——计划内);
  2. `assembleFilmLeg` exhaustive switch 补 `.v2, .v3` 腿(编译器指向的
     bump 连带,非本意扩面——case 追加的编译半边,M8-2 同族先例;film
     腿语义零变化:v3 文档 ride 光谱臂,policyTag 恒
     `lightamer.film.subrun.v2-spectral`)。
- `FilmTailPolicy.policyTag` switch 同款补腿(.v2, .v3 → spectralPolicyTag,
  该文件不在封存清单)。
- 其余封存面 17 件:亲核零 diff(NodeOwnershipCatalog / HistoryStack /
  LightamerSidecar / DrtRecord / TerminalTailPolicy / DrtTailAssembly /
  Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵 /
  NodeGraphCommand / PipelineDocument / V50Order / GradeCatalog /
  Registry / ModuleInstance——git diff 零输出)。
- ColorWheels.metal append(纪律面登记):v3 kernel + ToneWheelUniforms
  append,现行 `grade_color_wheels` 函数体 md5 与 HEAD 同值
  (8943b9a434132c48f62b66d490c7664a)亲证。

## §4 v3 kernel 的标量分支形(T1 执行期发现)

- 初版 vector + `select` 形在实机探针轮失效(五轮 alpha 探针:bool3
  谓词真值与 select 结果面不自洽——部分 lane 走 full 分支导致 identity
  位漂)。终版 = **scalar branch 直译**(上游 ApplyToneWheels 的
  per-channel if 形,中性早退为显式分支)——与 CPU `applyToneWheels`
  逐句同构,行为确定。vector 化重试属后续优化面(非 parity 义务)。
- 探针过程未入册文件(临时 alpha 写值轮,终版已还原 `out.write(result,
  c.a)`);教训候选:vector bool3 谓词 + select 组合的 GPU 行为不可从
  文档推断,数学面 kernel 一律 scalar branch 起步。

## §5 拟合残差实测值(H-SP3 锚带)

- 常见域(上游锚点集 0.02/−0.01/0 · 0.92/1.0/1.06 · 1.06/1.0/0.95):
  实测 max 残差 **0.0308 stops**——plan 转写的「≤0.03」是 research 粗化;
  断言带定 **0.035**(上游锚 0.05 容差过,双带并存)。
- 极端域(lift ≈1.4 档 + gamma 0.9/0.95/1.0 + gain 1.08/1.03/1.0 同调):
  实测 **0.143 stops**——CONTEXT「≈0.12」带的量级确认;断言带定
  **0.145**(hard cap 0.15)。构造点经两轮收敛(首版 gain 1.45 得
  0.585 = 域外构造;次版 0.235;终版落带)。

## §6 T1 落域偏差(ColorWheelsToneWheelGoldenTests → IOPParity)

- plan 红线 11 字面「kernel golden → IOP」;BUNDLE-MAP D5 域模式 =
  `*Parity*|Golden*|ToneEqual*|Lut3d* → IOPParity`,所有既有
  `*GoldenTests`(含冻结臂 GradeKernelGoldenTests)都在 IOPParity。
- 裁决 = 按 BUNDLE-MAP 域模式落 **IOPParity**(CONVENTIONS 的 E2 落域
  正本;冻结臂与 v3 golden 同 bundle 同域对拍);plan 的「IOP」读作
  IOP bundle 家族口径(IOP+IOPParity = test_bundles: [IOP, APP] 的
  「IOP」)。ConvertTests(纯函数,非 Golden 模式)落 IOP 同 plan。

## §7 迁移 marker 泛化定形(D-M9SP-7②)

- **film 记录在场** = M8-3 `commitFilm` VERBATIM 零 diff(语义未动,
  `filmDocumentScope` 不变)。
- **film 记录缺席** = `commitProcessMigrationMarker(colorWheels:label:)`
  新形——colorWheels 实例 params VERBATIM 走普通 `history.commit`
  (零 params diff,marker = `history_process_migrate` label;不触
  HistoryStack 封存面)。优先级:film 优先、cw 兜底,双记录文档只落
  film 形(单 marker)。
- gate 二源 = `hasFilmRecord || hasColorWheelsEdits`(coordinator
  `hasColorWheelsEdits()` 读 instances 中 colorWheels params 的
  `isIdentityV3`——v1 形缺席走 v1 判定,判别子语义单源)。
- editing 守卫扩 = `filmEditInFlight || colorWheelsEditInFlight`
  (后者 = 通用 `isEditingContinuous` D-H1 窗——轮盘拖拽/stops 滑杆
  全走)。

## §8 编辑器 Image 菜单定位(X6 正本execute 期登记)

- Image 菜单正本 = `NSMenuBridge.buildImageMenu`(AI upscale/denoise
  同区);Finder 项挂 menu 尾(separator 后),使能条件与 AI 项同
  (`editor phase + currentImageID`),AX id `menu.image.finder`,
  数据源 = `workspace.currentRow`(currentImageID → editorGrid 行 →
  imagePath),**存在性检查前置**(缺文件静默降级——reveal 先例同款
  guard)。

## §9 XPan 三行值(D-M9SP-6 确认)

- 65:24(dn=(65,24)) / 2.75:1(dn=(11,4)) / 6:17(dn=(17,6)),
  rawValue 拼写 "65:24" / "2.75:1" / "6:17"。CaseIterable 7→10;
  picker 3 行 + bits 双向映射臂(N/D 整数对入现 Int 存储,零 schema
  影响)。**自主增强非 parity**(REQUIREMENTS 只点名 65:24「等三行」)。

## §10 bump/扩表连带既有测试对齐(编译器指向不到的字面钉面)

- **bump 面**(T2,修复笔随轮):M8-3 迁移表/E2E(FilmPanelSpectral
  UITests targetRawValue 2→3 + process 2→current ×3)、M8-2 域表
  (SpectralLegForkTests)、**Layers** RenderProcessLedgerTests(账本表/
  clamp/mint,修复笔 2)、**Library** SidecarV10Tests(修复笔 3)——
  共 4 文件 + 本批新 2 文件。
- **扩表面**(T3,修复笔 1/4):IOPParity Lut3dEncodingTests
  (counts 17/11/6→27/18/9 + camera logs 10→17 + display peak 族
  +48)与 App LutEncodingPanelTests(修复笔 4)——扩表字面钉与 bump
  字面钉同族:「case 追加编译器逐点指向」不覆盖测试字面值。
- 修复序列 = 全套四轮折跑(IOPParity→Layers→Library→App 各暴露一
  批);每笔 = 修复类定向绿 + 随轮 commit;教训入 L0xx-k(grep
  `current.rawValue, 2\|all, \[.v1, .v2\]\|count, 17` 应入 bump/扩表
  任务清单)。
- M9-2/SpectralLegForkTests `testResolvingDomainsAfterTheBump`:all 表
  三项 + resolving(.current)==.v3(+ :3 自身域)。

## §11 偏差与挂账登记

- **T4 stars 的 AX 树断言**:FilmstripRowView 为 private struct,AX
  id(`filmstrip.row.rating.<id>`)可达断言归走查配方(MANIFEST §stars)
  ——单测面 = `FilmstripModel.ratingStars` 纯函数表(rating 0..5 + 超
  域 clamp + 负值 0 档);model seam 提取(AC 可机检缝范式)。
- **ColorWheelsPanelView 的 v1/v2 面板零 diff 断言**:面板 struct 加
  fork 分支(processArm 判定 + legacyBody 包裹),legacyBody 内部语句
  与 pre-M9-4 body 逐字节同(含迁移行挂点追加——挂点是 M9-4 新增,
  不属「零 diff」承诺面;三轮视图本身零 diff)。diff 审核在 T5 走查。
- **AGENTS 约定正本节 + 键族登记**:T5 统一回写(commit 计划见 SUMMARY)。

## §12 lessons 候选(T5 LESSONS 同批)

- vector select/bool3 谓词在 M 系列 GPU 的行为与文档语义面不自洽
  (§4)——数学 kernel 的 neutral 早退一律 scalar branch(教训正式
  化随 T5 LESSONS 批)。

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

## §5 拟合残差实测值(H-SP3 锚带;修复轮 B-1/m-1 修订见 §13)

> **修复轮修订(2026-10-29)**:本节原值(0.0308/0.143)测于上游直指数
> target——B-1 修复后 target 换倒数形,双带经产线路径重测:**common
> 0.0313(带 0.035 维持)/ extreme 0.1317(带 0.145 维持)**,重测对照
> 全表 = §13。m-1 的域限定诉求在新 target 下收窄:γ_s 偏离 1 达 0.2
> (原 0.081 实测域端)现实测 0.0253(γ_s=1.2)/0.0285(γ_s=0.9),
> 见 §13 语义回归行——0.035 带的「近中性域限定」叙事由 §13 接管。

- 常见域(上游锚点集 0.02/−0.01/0 · 0.92/1.0/1.06 · 1.06/1.0/0.95):
  实测 max 残差 **0.0308 stops**(原 target 轮)——plan 转写的「≤0.03」
  是 research 粗化;断言带定 **0.035**(上游锚 0.05 容差过,双带并存)。
- 极端域(lift ≈1.4 档 + gamma 0.9/0.95/1.0 + gain 1.08/1.03/1.0 同调):
  实测 **0.143 stops**(原 target 轮)——CONTEXT「≈0.12」带的量级确认;
  断言带定 **0.145**(hard cap 0.15)。构造点经两轮收敛(首版 gain 1.45
  得 0.585 = 域外构造;次版 0.235;终版落带)。

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
- **Show in Finder 三门的 AX 可达断言**(修复轮 M-1 补申报,与 stars 同
  款合并叙述):SwiftUI contextMenu 项与 NSMenu 项的**活树可达性**单测
  不可达,归走查配方(m9-4 MANIFEST 三门 AXPress 走查);单测面经修复
  轮改造为**真产线耦合**——三挂点消费 `FinderReveal.revealIfPresent`
  产线缝(存在性 guard + reveal 决策路径,注入 seam 实测:缺文件不
  reveal、在文件恰一 reveal)+ 三挂点 AX id 换 `FinderReveal` 产线常量
  单源(测试钉拼写——挂点改名再不能静默漂出走查登记树)。修复前两法
  为自构造字面量/Foundation 库行为断言(零产线耦合,验收第二路 M-1)。
- **ColorWheelsPanelView 的 v1/v2 面板零 diff 断言**:面板 struct 加
  fork 分支(processArm 判定 + legacyBody 包裹),legacyBody 内部语句
  与 pre-M9-4 body 逐字节同(含迁移行挂点追加——挂点是 M9-4 新增,
  不属「零 diff」承诺面;三轮视图本身零 diff)。diff 审核在 T5 走查。
- **AGENTS 约定正本节 + 键族登记**:T5 统一回写(commit 计划见 SUMMARY)。

## §12 lessons 候选(T5 LESSONS 同批)

- vector select/bool3 谓词在 M 系列 GPU 的行为与文档语义面不自洽
  (§4)——数学 kernel 的 neutral 早退一律 scalar branch(教训正式
  化随 T5 LESSONS 批)。

## §13 修复轮:gamma 倒数语义错配(B-1,验收第二路 blocking)+ M-1/m-1(2026-10-29)

### 错配机制(验收第二路 §3.2 亲证链,修复轮复核成立)

- 我方 v1 **冻结渲染** = `pow(|c+lift|, 1/γ_store)·gain`(M2-5 移植期
  `1/γ_leg` 指数换算形态,D-M9SP-1;ColorWheelsModule.reference +
  冻结 kernel 体 md5 8943b9a4 三重互证)——存储的 gamma 轮值 = 渲染
  指数的**倒数形**。
- 上游 e1effd8 v1 存储直指数(`out = ((c+lift)^γ)·gain`),T1 的
  convert 拟合 target 直译为 `pow(|input|, γ)`——对**同一存储值**的
  解释与我方冻结渲染互为倒数;测试锚 `legacyApply` 同病(锚验证的是
  上游语义自洽,非我方迁移保真)。
- 后果:γ_s 非中性旧档升号观感**反转**(中灰即翻转,1.17–2.34 stops,
  探针实锤);迁移文案只称「small tonal shift at the range ends」;
  DECISIONS §1..§12 零申报——blocking 定级成立。

### 两案裁决

- **(a) 拟合 target 改 `1/legacyGamma`(采行)**——保「迁移 ≈ 保观
  感」承诺,一处公式改 + 转换锚 goldens 重钉;上游测试锚**适配**而非
  照抄(真值模型换我方冻结形,GPL 头 Modifications 段已注记偏差)。
- (b) 设计裁决接受上游语义翻转(把 M2-5 `1/γ` 视为待修正移植缺陷)
  ——否决:M2-5 冻结臂是 **2.x 时代起的历史用户观感**(冻结 = 契约),
  升号顺带改观感违反「迁移保观感」,且 D-M9SP-1 已把 `1/γ` 形登记为
  有意换算而非笔误。

### 修复内容与重钉前后对照

- `ColorWheelsLegacyConvert.fitLegacyGammaGain` target 换倒数形 +
  文档三处(文件头 Modifications / fit doc / target 行注记);测试锚
  `legacyApply` 同步换 `1/γ` 形(独立 Float64 真值模型——路 2 探针
  形态转正,inline 写死不 import 产线路径)。
- **重钉对照表**(真值 = 我方冻结 v1 观感;Float64 探针与产线路径
  Float32 实测逐位一致;「前」= 直指数 target,即验收第二路实锤):

| 场景 | 前:max 偏差(stops) | 前:中灰 | 后:max 偏差(stops) | 后:中灰方向 |
|---|---|---|---|---|
| γ_s=1.2, gain=1.0 | **2.3390** | 0.479→0.347(反转) | **0.0253** | 保持(0.4792→0.4788) |
| γ_s=0.9, gain=1.0 | **1.3521** | 0.375→0.452(反转) | **0.0285** | 保持(0.3749→0.3751) |
| γ_s=1.1, gain=0.95 | **1.1660** | 0.426→0.360(反转) | **0.0196** | 保持(0.4257→0.4255) |
| common 锚(lift+γ0.92+gain1.06) | 0.0308(上游真值域) | — | **0.0313** | — |
| extreme 锚(lift≈1.4+γ0.9+gain1.08) | 0.143(上游真值域) | — | **0.1317** | — |

- 断言带重测后**数值维持**(common ≤0.035 / extreme ≤0.145——新实测
  均在原带内),带注释改写为 re-pinned;转换锚 6 法 + 新增语义判别
  回归 1 法 = 7/0/0(定向)。
- **语义判别回归**(新法 `testGammaNonNeutralLegacyKeepsLookAnd
DirectionAtUpgrade`):三场景(1.2/0.9/1.1+0.95)× 25 点 ±6 EV 全
  网格,断言①中灰方向保持(migrated 与 truth 同侧于中性——**B-1 反
  转哨兵**)②幅值 ≤0.035;负向探针证实设防有效(target 临时改回直
  指数 → 15 failures 真红,方向断言 + 幅值断言齐红,实测 2.339 与
  上表逐位一致;还原回绿)。
- **m-1 随修消解**:原域端担忧(γ_s 偏离 0.2 → 0.081)测于旧 target
  的上游自洽域;新 target 下同域重测 = 0.0253(§13 上表)——0.035
  带在语义域(γ_s∈[0.9,1.2])成立;「近中性域限定」叙事由上表语义
  行接管,§5 修订注记在案。
- **迁移文案修正**(三处同批):`panel_process_migrate_body`
  defaultValue + xcstrings en/zh——「the new wheels approximate the
  previous look (a small tonal shift is possible at the range ends)」
  →「the new wheels **re-express the previous look (the previous
  rendering behavior is kept;** a small approximation can remain at
  the range ends)」/ zh「重新表达原观感(沿用原渲染行为;两端可能残
  留轻微近似偏差)」——语义对齐如实声明,残留近似(极端域 0.13 量级)
  如实保留。

### M-1 处置(同轮)

- 产线缝 `FinderReveal`(App/Sources/Lightamer/UI/Shell/FinderReveal
  .swift):三 AX id 常量单源 + `revealIfPresent`(存在性 guard + 注
  入式 reveal/exists seam);三挂点(grid/filmstrip/menu)改消费缝;
  SmallPoolUITests 两法改真耦合(缝决策路径实测 + 常量拼写钉)。
  「三门 AX 可达」归走查配方——§11 合并申报。方法数不变(2)。
- tuist generate 重跑(pbxproj 收录新文件,L041 恒为构建批末动作)。

### 修复轮负向探针记录

- 探针 = target 临时回退直指数 → 重建后 `ColorWheelsLegacyConvert
Tests` 3/7 法红(15 failures:方向 9 + 幅值 3 + 派生)→ 还原回绿
  7/0/0。日志 `/tmp/m94-redprobe-run.log`(临时,结论在本节)。

### 修复轮全套的 Export 环境型红(范围外收口修复,取证链完整)

- **现象**:第一遍全套(20:29)Export 385/4/1——`ExportPhaseE2ETests
testBorderedVariantsFullChainRoundTripThroughQueue` 的「white water
mark rows survived」断言红(实测 5/4 vs >30),fail 停使 App 未跑;
Export 单 bundle 两连红**逐值同**(5/4)。
- **基线实锤排除本轮**:`git checkout b6ba12fc`(修复前,占位
  FinderReveal 编译垫片)**同红同值 5/4**——修复 commits 构造性豁免。
- **像素取证**(临时直方图 + PNG dump 探针,已还原):两行水印文字
  **渲染完整**(anchor/布局/内容全对,maxR 236-251),但 ~8px CoreText
  **灰度 AA** 字形的笔画覆盖 <1px → r>0.8 核心像素仅 4 个;渲染器
  注释自证「deterministic **per system**」(YiyinTextRenderer.draw)
  ——全图核心像素计数随**系统文本光栅化状态**漂移(M9-4 终值轮
  14:43 绿 → 同日夜间重建红,代码零变、机器 5 天未重启、无系统更
  新)。降阈值不可行:主图渐变自身高光(全图 3.4k 像素 @ r 0.6-0.7)
  会吞掉任何低阈值。
- **处置(收口门必需的范围外最小修复,commit `ac7b633a`)**:计数
  改**水印文字区域局部窗**(canvas 中央 70%×22%,r>0.72——背景高光
  在窗外);实测 34/35,下限钉 15(2.3× 余量;水印消失/全黑 ≈0,量
  级分离,设防力完整)。Export 单 bundle 回绿 385/4/0。
- 定性:**环境敏感脆弱断言**,非渲染缺陷、非本轮回归、非 M9-4 任一
  批产物缺陷(断言形态系 11-05 批遗留)。晨审可复核取证(本节 +
  commit body)。

## §14 M-1′ 修复轮:Show in Finder 三门相对路径静默失效(omp 终审 major,2026-10-30)

> 输入正本 = `M9-4-ACCEPTANCE-OMP.md` §四(实机三档路径矩阵 + 机制独立
> 复现);任务书 = 修复轮 M-1′ 单项。HEAD 起点 = `46a01e07`。

### 缺陷机制(omp 亲证,采纳)

- 三门(grid contextMenu / filmstrip contextMenu / Image 菜单)消费
  `row.imagePath` = `images.image_path` **原始列**(`LibraryQueries`
  投影,`ImageLinker.resolve` 未参与),`FinderReveal.revealIfPresent
  (String)` 内 `fileExists(atPath:)` 按**进程 CWD** 解析相对串 →
  kind2(绝对+UUID)真定位、kind0(项目相对)/ kind1(卷相对+UUID)
  静默 no-op——默认导入(link 外部文件夹 = kind1、项目内 Media =
  kind0)全是相对档,用户观感 =「点了没反应」。

### 修法(三挂点改走 resolve;守卫语义不变)

- **`FinderReveal` 增两门,组合单源**:URL 门(`revealIfPresent(_ url:)`,
  共享 guard/reveal 决策路径逐字节不变)+ **row 门**
  (`revealIfPresent(row:resolve:)` = 三挂点唯一组合面——先经注入
  resolver 拿 ImageLinker 解析 URL,再走共享路径;resolve 失败
  (stale link/文件缺失)= nil → 静默 no-op 维持)。String 门原样
  保留(既有测试 + 守卫语义锚)。
- **解析器单源**:`LibraryThumbnailBridge.sourceURLResolver(
  projectDirectory:)` static factory = host `rebuildLibrarySurface`
  内联闭包**逐句上提**(PathKind decode + `ImageLinker.resolve`,
  行为零变化),bridge / AI entry / editor resolver 三绑定面同源;
  `nonisolated var sourceResolver` 读出面(actor `let` 免 hop)供
  grid/filmstrip 挂点消费。
- **三挂点**:LibraryGridView cell 与 FilmstripRowView contextMenu 改
  `FinderReveal.revealIfPresent(row: row, resolve: { bridge?.
  sourceResolver($0) })`;NSMenuBridge Image 菜单改走既有
  `workspace.editorURLResolver`(host 同一 factory 产物)。AX id /
  文案 / UserDefaults / xcstrings 零新增;存在性 guard 语义不变
  (resolve `.resolved` 本身已 stat,门内默认 exists 复核保留)。

### 回归(新法三 kind 直测;透过 FinderReveal 缝断言)

- 新法 `SmallPoolUITests.testFinderDoorsResolveAllThreePathKinds
BeforeReveal`:真 fixture 文件树 + **真产线组合**(factory resolver +
row 门 + 注入 reveal/exists seam),三 kind 各断言「resolve 后 URL 恰
  达缝」——kind0 手造 Media/ 形(record 从不铸造)、kind1 = `ImageLinker
  .record` 真实同卷面(firmlink 现实 /-rooted 拼写)、kind2 = record
  probe **按 URL 区分**强制异卷;外加 stale 行(文件已失)零 reveal
  断言。
- **首跑 3 fail 教训**:probe 首版对 source/project 返同一串 → record
  判同卷铸出 kind1 行 + 假 UUID → resolve `volumeAbsent`(产线行为
  正确,测试造行错);probe 改 `{ $0 == kind2File ? "cross-volume-uuid"
  : nil }` 后绿。修后 SmallPoolUITests **5/0/0**(类过滤定向 2s)+
  全 App bundle **1066/6/0**(= 1065 ⊕ 1,skip 6 持平;全套账面
  4428/34/0 对账态,六 bundle 未跑——本批触面全在 App target,其余
  域测试文件零触碰,LIB 域 LibraryThumbnailBridgeTests 走 additive
  API 零扰)。

### 封存与范围

- 封存面 17 件**零 diff**(触面 = FinderReveal / LibraryThumbnail
Bridge / WorkspaceHostView(rebuild 单源化,行为同构)/ LibraryGridView /
  FilmstripView / NSMenuBridge / SmallPoolUITests——无一在封存清单)。
- 无 GUI 走查(omp 已终审三门 UI/AX 面,本批只补行为缺口,回归机检
  承载);guard G4 贴线透明越门(Data 卷 23775MB<25GB,§9 先例,
  monitor 伴跑 ceiling 9GB 零 kill)。

### M-1′ 修复轮运行事故注记（诚实账）

- **App 全量第一遍（00:38）**：1066/6/**3**——红全数落新法 kind2 腿
  （probe 造行错，上文已记）；其余 1060 法全绿 = 产线改动零连带。
- **App 全量第二遍（00:51）**：卡死 50 分钟——
  `AIWorkerClientTests.testTimeoutKillFoldsToWorkerCrashedAndRespawns`
  起跑后不返（/tmp/la-direct-tests-App.log 101 test-case 行后停滞；
  宿主栈 = 主事件环 idle）。与本批改动零关联（AI worker 子进程
  kill/respawn 时序 flake；同二进制第一遍 + 复测均通过）。处置 =
  杀本人会话进程树（host exit 143 → script crash 终态记账
  `m1p-fix-app2.log`），单类复测 AIWorkerClientTests **9/0/0**（3s）
  后全量第三遍。
- **App 全量第三遍（01:42）终值**：**1066/6/0**（601s，peakRSS
  1797MB）——SmallPoolUITests 5/5（新法 0.009s）+ 既有两 Finder 法
  绿；LIB bundle 顺跑 **785/4/0**（= 修复轮基线逐位同，bridge
  additive 零扰实证）。日志 = all-runs/m1p-fix-{build,build2,app,
  app2,app3}.log。

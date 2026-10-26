# M9-4 PLAN 独立评审（2026-10-25）

> 评审对象 = `M9-4-PLAN.md`（v1）+ `CONTEXT.md`（D-M9SP-1..9/X1..X6/hazards/红线 15/勘误四）。
> 依据正本 = RESEARCH.md / REQUIREMENTS M9SM-01..02 / ROADMAP §M9 / AGENTS 跨批不变量
> / M8-3 迁移通道现役面 / M6-2+M8-2 process bump 先例 / PixelPipe 现行键形
> / Alcedo `e1effd8`·`c740f7b` git 对象。零 commit、零构建、纯读评。
> 抽核 = **43 锚**（代码 27 + 上游 git 对象 6 + 制度/账本 6 + UI 4），命中明细见 §抽核表。

## 档位结论

**PASS-with-notes**（error 0 / major 1 / minor 4）

核心设计全部核实正确：折键 resolved-arm 形、params 甲形态+判别子/镜像两补强、
冻结臂锚定我方字节、上游 e1effd8 数学逐条精确吻合（含 `max(0.5+K/R, 0.05)` 的
cpp 侧 `kMinGammaBase` 下限）、c740f7b 十行 id + peakNits 48 逐值对上、终带算术
正确、勘误四条全部亲证成立。唯一 major = 渲染入口穿线面的**事实断言与代码不符
+ 核验清单不完备**（方向正确、护栏在，修表述与清单即可，不动设计）。

## 分级清单

### Major

- **M-1 渲染入口穿线：CONTEXT 断言与代码不符 + T2 核验清单漏点名未穿腿**
  （`CONTEXT.md` D-M9SP-8 第四段 / `M9-4-PLAN.md` 红线 4 + T2 Action 3③）
  1. D-M9SP-8 称「『thumbnail 恒 legacy』先例只关 tail policy 非 process——勿混」
     ——实核 `PipeCoordinator.swift:2510-2515`：`migratedProcess` 的
     `guard resolution != .thumbnail … return .legacy` 是 **process 穿线层的显式
     thumbnail guard**（M8-3 T3 设计，注释明文「THUMBNAIL stays legacy … the
     thumbnail cache-key space never moves」）。不是 tail-policy 先例、更不是
     「.legacy 缺省腿漏穿」。改穿 doc 值 = **修订 M8-3 显式设计决定**（连带其
     「thumbnail cache-key space never moves」注释需同批修订），应登记 DECISIONS
     为「M8-3 guard 修订」而非补漏；红线 4「.legacy 缺省腿属 bug」的措辞同改。
  2. 未穿腿清单不全：plan 点名「缩略图/EXPORT/子 run」。实核 EXPORT 主腿**已穿**
     （`ExportRenderer.swift:555/:570` `renderProcess: documentProcess`——正资产，
     核验零工作量）；但**未穿腿**还有 `QuickLookRenderer.swift:287/:296`、
     `PipeCoordinator.swift:2001`（eyedropper 线性链）/`:2161`（filmic auto 采样）
     /`:2607/:2626`（EDR display override）、`ColorMatchService.swift:205/:214`
     （colormatch 提取）——共 8 处调用点全部 `.legacy` 缺省，v3 文档下吸管读数/
     自动黑白键/EDR 预览/QuickLook/colormatch 与主视图不同臂。机检面
     `grep -rn "RenderPipeline.process" App/Sources LightamerCore/Sources/Export`
     即可一网打尽，应入 T2 Action 3③ 显式清单。
  3. 上述修正（8 调用点 ×1-3 行 + thumbnail guard + M8-3 注释同步）大概率触
     「超 10 行停手上报」——预期管理应写明「本缝预期触线、停手上报属计划内」，
     避免执行者误判为方案失败。
  缓解已在 plan：红线 4「一切渲染腿」字面涵盖、「超 10 行停手上报」护栏、
  T5 走查第三项双保险——故 major 不阻断，修订表述与清单后执行。

### Minor

- **m-1 键计数：`panel_process_migrate_*` 计 4 键，实需 5**。film 族现役 5 键
  （title/body/button/cancel/**confirm**，xcstrings 亲核）；迁移行保留 confirm
  sheet（红线 10 明文 L057 sheet 形），confirm 键必然随 copy 中性化——T2
  Action 5③ 与 T5 键数对账（15-17）各 +1。zh-audit --check 会兜底抓 MISSING。
- **m-2 引用笔误：T3 Action 2「id 拼写勘误③对上游」**——勘误③是 M8-3 迁移
  通道泛化面；id 拼写对上游属 X5/勘误④（peakNits）面。X5 列表本身正确
  （十 id 与 `c740f7b` 亲核逐一对上），执行以 X5 为准即可。
- **m-3 SessionThumbnailRenderer 豁免未登记**：该腿带「Phase 8 contract（禁改）」
  注释（`SessionThumbnailRenderer.swift:22`）且属 legacy session 面——.legacy
  即正确值（legacy 库无 process 载体），**无需也不应改**；建议 DECISIONS 登记
  豁免判断，防执行者机械套「一切渲染腿」撞禁改契约。
- **m-4 GradeCatalog 论证空转（无害）**：RESEARCH §2 称 defaultLook 有
  colorWheels identityJSON——实核 `NodeOwnershipCatalog.swift:297` defaultLook
  仅 exposure/contrast/saturation 三条，**无 colorWheels 条目**；plan「identityJSON
  零改」结论仍成立（无条目 = 天然零改），仅论证措辞（「v1 形 pristine 单源」）
  无实体对象。风险节 4 的停手护栏足以接住任何意外。

### 观察（不入计数）

- M9 全里程碑 ΔN 上沿（20+15+14+11 至 29+20+19+15 = 60..83）超 ROADMAP §M9
  预期 +55..75 上沿 8——前站实数落后收口对账面提示，非本 plan 义务。
- `ParamsCoding.swift` 实际路径 = `LightamerCore/Sources/Foundation/`（CONTEXT
  只写文件名未写路径，:22-28 域亲核吻合）。

## 六维度逐项

### 1. 目标回溯 — 通过

- M9SM-01 全兑现：LGG+Offset 新 kernel（T1）+ process v3 双臂五件套（T2）+
  golden vs 上游数值锚（解析锚套件移植，tolerance 注释引上游行）+ v2 旧档
  逐位零漂移负测（冻结臂 golden 原样 + 缓存键恒等负测②）。
  「v2 档读入单公式转换」措辞 = 升号后 v3 臂读入转换（RESEARCH OQ-7 已释），
  与「旧号冻结零漂移」自洽。
- M9SM-02 全兑现：LUT 10+7+6（OQ-3 修正已申报且 REQUIREMENTS「+24」原文在册
  :744）/ stars / Finder 三门 / XPan 三行；验收形态（定向 + zh-audit）落在 T4/T5。
- golden 三面判别力完备：上游数值锚（独立于我方实现的第三方真值）⊕ 冻结臂
  零漂（现行 golden 零改即门 + md5 机检）⊕ 字节零漂 hash 钉死（H-SP2）——
  三面互不倚赖，任一破各有独立信号。

### 2. 坐标真实性 — 通过（43 锚抽核，41 命中 / 2 出入归入 M-1）

见 §抽核表。重点：上游 e1effd8 数学（四公式/±6EV/R=12/`kMinGammaBase=0.05`
cpp :18,:65/`kDiscMaxStops=1.0`·`kMasterMaxStops=2.0` model.hpp:38-40/
ToneWheelKernelParams 14 float/中性早退 cpp :268/FitLegacyGammaGain 25 采样·
1e-4 step·3×3 消元·20 迭代·1e-9 收敛 test 级全参数）与我方 X1/X2 **逐参数
精确吻合**；test.cpp 265 行 + 分离比 4×（:91-92）+ 往返 1e-4（:120-121）+
中性 1e-6（:96-101）锚值全在。

### 3. 红线完备 — 通过（M-1 表述修订 + m-1 键数后完备）

- v3 五件套完整（case/all/current :90/processVersion switch :167-172 补腿/
  AGENTS 账本行——账本正本 `AGENTS.md:405` 亲核在册）。
- **PipeCache 折键设计正确**：`PipeCacheKey.upstreamHash`（:48-55 亲核）= FNV-1a
  chain over paramsHash，**确无 process 段**——「必查缝」坐实；折落 run 级
  prepareChain（:946-976 亲核，levelHash 构造在域内；实例属性 `renderProcess`
  :194 在 prepareChain 可达，签名零改）；resolved-arm 收窄形（v1/v2/legacy →
  nil 零折）与 M8-2 policyTag 先例（`RenderProcess.swift:130-133` 注记亲核）
  同构；负测三件 = 硬门在 T2 验收机检。
- 封存面例外恰两处申报诚实（prepareChain 一 hunk + ColorWheels.metal append
  ——后者本非清单内、登记为纪律面）；IOPiece :76-88 stamp 注释明文预留缝
  （「a future fork point folds the process at ITS cache key」亲核）兑现合法。
- 新 kernel 唯一申报面 ✓；xcstrings 尾插/V14 禁形/UserDefaults 零新键 ✓
  （本批确无设置面）。

### 4. 可执行性 — 通过

- T 序（数学面先行→接线→表扩→UI→收口）依赖正确；T1 明确「不带 fork 接线」
  边界清晰。
- ΔN +11..15 构成逐任务列账；下沿 11>charter 10 已申报理由（负测三件不可并法）。
- 终带算术亲证：4292+20+15+14+11=**4352** / 4292+29+20+19+15=**4375** ✓；
  前站 plan ΔN 带（M9-1 v2 +20..29 / M9-2 v2 +15..20 / M9-3 v2 +14..19）逐一
  亲核吻合；三前站尚无 SUMMARY——plan「开工前亲核实数落」处理正确。
- offset 判别子四件自洽：encodeIfPresent 字节零漂（ParamsCoding sortedKeys
  :18-27 亲核）⊕ 首编辑物化 quad（undo/jump 回旧 item = 回缺席 shape，判别随
  paramsData 自带）⊕ frozen 16-float 不动 ⊕ params 镜像缓存（module 实例级
  per-box 隔离 + NSLock + memo 键 paramsHash；不同 renderProcess 共 memo 无害
  ——convert 结果只依赖 params）。golden 冻结主门自洽：`IOPiece()` 缺省
  .legacy → resolving = .v1 冻结臂，现行两法（:508-555 亲核）零改即过。

### 5. OQ 采纳 — 通过

七条全按 research 推荐 + 晨审推翻点索引齐备；planner 两补强均结构性必需
（判别子防双语义同名键互撞；镜像缓存解决 frozen 打包不携带 offset 的 v3
保真读取）论证扎实；OQ-7 泛化工作量经勘误③显式列面（gate 二源/marker 二形/
copy 中性化/双面板挂点）——亲核 M8-3 现役 gate 确为 film 专属
（`runProcessMigration` :858 guard `hasFilmRecord` 亲核），泛化是真实工作量、
申报诚实。

### 6. 转写勘误四条 — 全部亲证成立

① rating 已通（`LibraryQueries.swift:112` 亲核 + `FilmstripRowView :271`
直消费 `LibraryImageRow` + `LibraryGridModel :222` 确为分页锚 `keyValue:
.int(nil)`）✓；② 工作区 stale（HEAD=6024386 亲核，`git show e1effd8:…`
对象可读）✓；③ gate film 专属 ✓；④ peakNits（`c740f7b` p3d65/p3dci 均
48.0f 亲核）✓。

## 抽核表（43 锚）

| # | 锚 | 结果 |
|---|---|---|
| 1 | RenderProcess.swift:90 current=2 bump 位 | ✓ |
| 2 | RenderProcess.swift:108-172 枚举/账本/processVersion switch | ✓ |
| 3 | RenderProcess.swift:130-133 M8-2 折键先例注记 | ✓ |
| 4 | ColorWheels.metal:39-48 `1.0f/gammaLegX` 形态 | ✓ |
| 5 | ColorWheels.metal 现行 kernel 50 行整（append 面） | ✓ |
| 6 | PipeCacheKey.swift:48-55 upstreamHash paramsHash 链无 process 段 | ✓ |
| 7 | PixelPipe.swift:940-976 prepareChain + levelHash | ✓ |
| 8 | PixelPipe.swift:995-1002 forwardWalk stamp | ✓ |
| 9 | PixelPipe.swift:194 renderProcess 实例属性（prepareChain 可达） | ✓ |
| 10 | PixelPipe.swift:2209/:2276 两入口形参缺省 .legacy | ✓ |
| 11 | IOPiece.swift:76-88 stamp 注释预留缝 | ✓ |
| 12 | ModuleBox.swift ModuleBoxing 协议（default nil 可加） | ✓ |
| 13 | ColorWheelsModule Params :192-206 三轮/strengthRange :100 | ✓ |
| 14 | ColorWheelsModule isIdentity :221-234（v1 形） | ✓ |
| 15 | GradeKernelGoldenTests :508-555 colorWheels 两法 | ✓ |
| 16 | PipeCoordinator :858-875 runProcessMigration gate film 专属（勘误③） | ✓ |
| 17 | PipeCoordinator :2510/:2540/:2553 主渲染双路已穿 | ✓（带 thumbnail guard → M-1.1） |
| 18 | ExportRenderer :555/:570 EXPORT 已穿 documentProcess | ✓（正资产，plan 预设核验） |
| 19 | QuickLookRenderer :287/:296 未穿 | 出入 → M-1.2 |
| 20 | PipeCoordinator :2001/:2161/:2607/:2626 + ColorMatchService :205/:214 未穿 | 出入 → M-1.2 |
| 21 | EditorState+FilmMigration :40-76 evaluate gate | ✓ |
| 22 | WorkspaceModel.swift:405 setProcessVersion | ✓ |
| 23 | ParamsCoding.swift:18-27 sortedKeys | ✓ |
| 24 | FilmPanelView :130+ ProcessMigrationRow + panel_film_migrate 5 键在册 | ✓（→ m-1 键数） |
| 25 | LutEncodingCatalog 17 case + all 17 行（:195-249）+ 9 gamut | ✓ |
| 26 | LutTransferMath 17 曲线 case（尾插面） | ✓ |
| 27 | sgamut3/cinema_gamut/rec2020/display_p3 既有（10 行缺口成立） | ✓ |
| 28 | LibraryQueries.swift:112 rating: Int64?（勘误①） | ✓ |
| 29 | LibraryGridModel.swift:222 分页锚（勘误①后半） | ✓ |
| 30 | FilmstripView :271 row: LibraryImageRow + caption 区 | ✓ |
| 31 | LibraryGridView :562-565 ratingBadge 先例 | ✓ |
| 32 | CropOverlayHost :25-40 七档 + dn d≥n | ✓ |
| 33 | CropPanelView :34+ picker（36-149 域） | ✓ |
| 34 | PostExportActions :171-175 revealInFinder | ✓ |
| 35 | ColorWheelsPanelView 三轮 Section 现状 | ✓ |
| 36 | NSMenuBridge :555 menu_image + AI 同区（T4 第三门锚） | ✓ |
| 37 | 上游 e1effd8 hpp 四公式/±6EV/R=12/ToneWheelKernelParams/ConvertLegacy | ✓ |
| 38 | 上游 cpp kMinGammaBase=0.05/中性早退/25·1e-4·20·1e-9 拟合参数 | ✓ |
| 39 | 上游 model.hpp kDiscMaxStops=1.0/kMasterMaxStops=2.0/payload 四轮 | ✓ |
| 40 | 上游 test.cpp 265 行/4×分离/1e-4 往返/1e-6 中性 | ✓ |
| 41 | c740f7b 十行 id 拼写 + peakNits 48（勘误④） | ✓ |
| 42 | Alcedo 工作区 HEAD=6024386 stale（勘误②） | ✓ |
| 43 | R6-SUMMARY 4292/35/0 + M9-1/2/3 ΔN 带 + 终带 4352..4375 算术 | ✓ |

（另核：NodeOwnershipCatalog defaultLook 无 colorWheels 条目 → m-4；
REQUIREMENTS :743-744 / ROADMAP §M9 站 4 表行 / AGENTS.md:405 账本 / xcstrings
新键 0 在册——均吻合。）

## 结语

Plan 质量高于本仓近期均值：上游数学逐参数精确、折键/判别子两处高风险设计
论证自洽、账目算术零误、勘误四条全部可复现。M-1 属「亲核声明过强 + 清单
粒度不足」——修订 CONTEXT D-M9SP-8 第四段表述、T2 Action 3③ 显式列出 8 个
未穿调用点与 M8-3 guard 修订性质、m-1 键数 +1 后，即可放行执行。

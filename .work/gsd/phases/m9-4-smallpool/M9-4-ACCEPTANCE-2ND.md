# M9-4 双路验收 — 第二路(盲评独立第二眼,2026-10-29)

> 验收对象 = 九 commits `358523ce..83006dcb`(refs #14);正本 = PLAN v2 +
> CONTEXT(D-M9SP-1..9/X1..X6/红线 15)+ SUMMARY/DECISIONS §1..§12;AC 源 =
> REQUIREMENTS M9SM-01..02。独立性纪律:未读 `M9-4-ACCEPTANCE.md` 与
> acc1-* 日志。第二路特色 = **迁移语义与 v3 行为正确性深审**。

## 结论头

**PASS with 1 blocking(1 B + 1 M + 1 m + 4 obs)**——机检面(封存面 17 件
零 diff / 例外恰形 / 五件套 / 折键链 / 键族 / 越带构成)全过;三 bundle
定向与 SUMMARY 终值轮逐位同值;双探针真红还原。但**迁移语义核心面存在
1 项 blocking 级缺陷(B-1:gamma 倒数语义错配)**——v1 时代 gamma 轮
非中性的旧档升号后观感反转(数值实锤 1.17-2.34 stops,中灰即翻转),
测试锚与迁移文案均未覆盖,DECISIONS 无申报。建议回注修复轮。

---

## 一、AC 独立核对(M9SM-01/02,file:line 亲证)

- **M9SM-01**(ColorWheels LGG+Offset + process v3 双臂):
  - 新 kernel `grade_color_wheels_v3` = 全批唯一新增 kernel(git diff
    `+kernel void` 全批恰 1 命中);`ToneWheelUniforms` 14 float 布局与
    `ToneWheelKernelParams.bufferFloats` 镜像一致(ColorWheelsModule.swift
    :418-432 ↔ ColorWheels.metal :69-79)。
  - 四公式 + 常数(kToneBlackEv=−6/kToneWhiteEv=+6/R=12/CE_ACESCC_B=17.52/
    MIDDLE_GREY=0.4135884)与上游 `e1effd8` hpp/.cpp 逐值对上(tone 轴/
    Offset→Lift→Gamma→Gain 序/gammaExponent 公式)。
  - 旧档零漂负测:`Params()` 编码 hash 11640277816793824460 钉死 +
    「无 `"offset"` 键」结构断言 + 旧 JSON tolerant decode→nil
    (ColorWheelsToneWheelGoldenTests:365-409)。
  - v3 bump 五件套:case v3 账本 doc-comment(RenderProcess.swift:139-152)
    + all 尾插(:153)+ current 2→3(:87-92)+ processVersion switch 补腿
    (:183-185)+ AGENTS process 账本 v3 行 + M9-4 约定正本节(diff 亲核)。
- **M9SM-02**(尾件):LUT 10 行 + 7 曲线 + 6 gamut(id 拼写照上游 c740f7b
  十 case 逐一对照;**peakNits 逐行照上游亲核**——scene 行 0/P3 两行 48/
  rec2020_bt1886 100,勘误④ 兑现)+ Filmstrip stars(ratingStars 表驱动
  0..5+超域 clamp+负值 0 档)+ Show in Finder 三门(产线三 AX id 注册 +
  前置存在性 guard + `activateFileViewerSelecting` :174 先例形,亲核
  LibraryGridView:209-220/FilmstripView:350-362/NSMenuBridge:571-582)+
  XPan 三行(dn=(65,24)/(11,4)/(17,6)+ rawValue 拼写 + CaseIterable 7→10
  + 旧 7 档 add-only 钉)。

## 二、封存面与例外恰形

- **17 件零 diff 亲证**(git diff 逐文件零输出):DrtRecord/TerminalTail
  Policy/DrtTailAssembly(后两者载体 = PixelPipe.swift,属例外面)/Lut3d
  Kernels.metal/DrtEotf/ExportQueueContract/六格式导出矩阵三件/NodeGraph
  Command/LightamerSidecar(v11 保持)/HistoryStack/HistoryHash/Pipeline
  Document/V50Order/NodeOwnershipCatalog(GradeCatalog)/Registry/Module
  Instance。
- **例外恰形**:
  - PixelPipe.swift **恰 2 hunks**:①prepareChain 折一处(:958-976 域,
    计划内豁免本体);②assembleFilmLeg `.v2`→`.v2, .v3` switch 补腿 +
    注释(bump 连带,DECISIONS §3 申报,M8-2 同族)。
  - ColorWheels.metal **纯 append 亲证**(旧文件 = 新文件字节前缀,
    cmp 逐字节);冻结 `grade_color_wheels` 函数体 **md5 8943b9a4** 与
    DECISIONS §3 申报值同值。
  - FilmTailPolicy.policyTag switch 补腿(该文件不在封存清单,§3 申报)。

## 三、迁移语义深审(主职责一)

### 3.1 offset 判别子全链推演(除 B-1 外全部闭合)

- 判别子单源:`effectiveToneWheelParams`(offset 缺席→convert,在场含
  全零→直读)恰两消费点——渲染预解 `resolveToneWheelKernelParams` 与 v3
  面板 `v3Params` 投影。
- **无双重转换窗口**:物化前 = convert(P)→解析;物化后(offset 在场
  = P')= 直读 P'→解析——同一 P' 进同一解析,逐位一致;物化仅经 v3 面板
  首 edit commit(全 quad、offset 显式在场),undo 回缺席 shape → 渲染期
  转换恢复。链路闭合。
- params 字节零漂(H-SP2):encodeIfPresent 结构断言 + hash 常量钉死 +
  round-trip 三面在册。
- params 镜像(D-M9SP-2 补强②):NSLock 读写 + memo 键 = piece.paramsHash,
  与 uniformsBuffer 同款 box 归属纪律;hash 回退时 memo 命中同字节 buffer,
  无害。
- isIdentityV3 判别子:offset 缺席走 v1 isIdentity(v1 中性 = convert 后
  零 quad,转换锚 testNeutralLegacyConvertsToNeutralQuad 钉死)——gate 面
  「v1 中性不给迁移行」语义正确。
- 迁移 UX 泛化四面全兑现:①gate 二源(`hasFilmRecord || hasColorWheels
  Edits`,evaluate 的 `hasColorWheelsEdits` default false 保 M8-3 调用形
  编译零改);②marker 二形(film item VERBATIM 零 diff 优先 / cw params
  verbatim 普通 commit 兜底,双记录文档单 marker);③copy 中性化 5 键
  (title/body/button/cancel/confirm;`panel_film_migrate_*` 留册引用
  归零——App/Sources 唯一命中为注释,allowlist 入 zh-audit);④双面板
  挂点(`ProcessMigrationInputs` 参数化,Film + ColorWheels 同行同动作)。
  undo/redo 边界:cw marker = 零 params diff 普通 item,undo 穿过无视觉
  变化,与 M8-3 film marker 同语义。
- thumbnail guard 修订(M8-3 设计决定修订):guard 删除 + M8-3「cache-key
  never moves」注释同批改写为新叙事(diff 亲核)+ DECISIONS §2 单独申报
  ✓;修订后的 v3 档缩略图与主视图同臂(主渲染双路 migratedProcess 闭包
  删特例后 thumbnail 腿直穿 doc stored 值,`renderPreview` 全 resolution
  走同一闭包——代码路径证据;AX 树走查归 MANIFEST)。豁免面两件
  (SessionThumbnailRenderer Phase 8 契约/CullingView pristine 链)未穿 ✓。

### 3.2 B-1(gamma 倒数语义错配——blocking)

**事实链**(全部亲证):
1. 我方 v1 冻结渲染 = `pow(|c+lift|, 1/γ_store)·gain`——ColorWheels.metal
   冻结体(`1.0f / gammaLegX`)+ `ColorWheelsModule.reference`(:355)+
   冻结 golden gammaPoint(1.2,0.9,1.1)三重互证;这是 D-M9SP-1 登记
   的「M2-5 移植期 `1/γ_leg` 指数换算形态」,冻结 = 我方历史观感。
2. 我方 v1 面板写入 = `gamma.colorOffset = (1,1,1) − delta`(面板
   deriveColorOffset,gamma inverted 注记)——存储值语义 = 渲染指数的
   倒数形。
3. **convert 拟合 target = `pow(|input|, legacyGamma)·gain`(直指数)**
   ——上游 `e1effd8` ConvertLegacyColorWheel 直译(上游 v1 存储 = 直指数,
   「Version 1 applied out = ((c+lift)^gamma)·gain」),对同一存储值的
   解释与我方 v1 渲染**互为倒数**。
4. **测试锚同病**:`ColorWheelsLegacyConvertTests.legacyApply`(:26)用
   直指数——转换锚 golden 验证的是「上游 v1 语义」的自洽,不是我方冻结
   语义的迁移保真。
5. **数值实锤**(独立 Float64 模型探针,复现产线数学,`/tmp/m94_probe_
   gamma_semantics.swift`, swiftc 直编):
   - 以「上游 v1 语义」为真值(转换锚自洽域):残差 0.017-0.081 stops
     ——拟合本身正常;
   - 以「我方冻结 v1 观感」为真值(= 真实用户迁移场景):
     - γ_s=1.2,gain=1.0:**max 偏差 2.339 stops**,中灰 0.479→0.347
       (变暗,方向反转);
     - γ_s=0.9:**1.352 stops**,中灰反向变亮;
     - γ_s=1.1+gain 0.95:**1.166 stops**,中灰反向变暗。
6. 影响面:lift 维精确(offset 直转)、gain 维同形(两侧均直乘)、中性
   档短路无损——**仅 gamma 非中性旧档中招**,但 gamma 是三轮常用轮,
   非中性旧档常见。迁移文案只声明「a small tonal shift is possible at
   the range ends」,与「中灰即翻转、幅值 1-2.3 stops」严重不符;
   DECISIONS §1..§12 无此申报。

**定级 blocking**:用户可见行为缺陷 + 无申报 + 文案误导。修复方向二选一:
(a)拟合 target 改用 `1/legacyGamma`(匹配我方冻结语义)——一处公式改 +
   转换锚 goldens 重钉 + DECISIONS 补申报(推荐,保「迁移 ≈ 保观感」
   承诺);(b)设计裁决「接受上游语义翻转」(把 M2-5 的 1/γ 视为待修正
   移植缺陷,升号 = 顺带修正)——须 DECISIONS 明示 + 文案如实改写。
现行 = 两者皆非(行为翻转 + 无申报),故 blocking。

## 四、PipeCache fork 语义推演(主职责二)

- **折键全链闭合**:run 级 `PixelPipe.renderProcess`(:194,入口 :2221/
  :2288 传参)→ `prepareChain` 恰一处折(`processForkHash(renderProcess)`
  在 params 项之后、per-box,levelHash 链式 running)→ `PipeCacheKey.
  upstreamHash`(:48-55 链语义)——colorWheels 位及其一切下游位键翻转,
  上游位键不变。子 run 同穿:tailPipe/filmPipe/replayPipe :1131/:1254/
  :1498 继承 run process;layer sub-run 走同一 prepareChain。
- **IOPPiece stamp 预留缝兑现**:forwardWalk :1005-1010 每 piece stamp
  `state.renderProcess` → `ColorWheelsModule.process` exhaustive switch
  读 piece.renderProcess(`.v1/.v2` 冻结 dispatch 逐字节/`.v3` 走镜像
  memo buffer)——零新线程面 ✓。
- **同图 v2→v3 迁移一致性推演**:params 字节不变 → box.paramsHash 不变
  → 升号只翻 run 级 renderProcess → 折键后 cw 位及下游 miss 重渲、上游
  位键恒等命中正确平面(两臂同字节);同一次 run 内 prepareChain 单次
  求值,无内部错配窗口。v1/v2/legacy 零折(resolved-arm discriminator)
  = 旧档缓存键字节恒等。
- **三负测**(ProcessForkCacheKeyTests):①同 params v1 vs v3 键不等
  (含 fork 项手工线程复算对拍);②legacy/v1/v2 与无折链逐位恒等 +
  三臂 processForkHash 均 nil;③v3 内 params 翻转折不吞 + fork tag hash
  905990834909371860 钉死。覆盖面合格。
- **obs-1(断言域缺口)**:三负测全在「手写 foldChain 镜像」纯函数域
  (文件头自认 mirror),无「真 PixelPipe v2 渲染→升号→v3 重渲→断言
  平面异 + 缓存 miss」集成级负测;该面挂 gui-acceptance 人工走查
  (SUMMARY 走查第三项)。镜像与产线折语句漂移风险低(3 行)但在。

## 五、定向测试(第二路亲跑)

| bundle | executed/skip/fail | peakRSS | 对照 SUMMARY 终值轮 |
|---|---|---|---|
| IOPParity(v3 golden/折键/ProcessFork/LUT 扩) | **565/10/0** | 6073MB | 565/10/0 逐位同 ✓ |
| IOP(ColorWheels/GrainCalibration/LUT 族) | **813/1/0** | 7673MB | 813/1/0 逐位同 ✓ |
| App(FilmPanel 迁移面/gate/尾件) | **1065/6/0** | 2832MB | 1065/6/0 逐位同 ✓ |

- build-for-testing 先行(TEST BUILD SUCCEEDED);GUI 实例 ps 清零同链
  内联验证 ✓;guard **G4 BLOCK(Data 卷 23980MB<25GB)→ 按三批 §9 先例
  透明越门 + `--monitor` v1.4 伴跑全程(ceiling 9GB,零告警,峰值
  7673MB)**——追记如仪(obs-4)。
- 两探针域还原后回绿(ConvertTests 6/0/0 + GateTests 4/0/0),主树对
  HEAD 零 diff(`git diff` 空)。

## 六、反自取消补充探针(主树掏空还原法)

- **探针① offset 判别子掏空**(`effectiveToneWheelParams` 去 convert 腿)
  → 重建后 `ProcessMigrationGateTests.testPanelForkReadProjection`
  **真红**(:139 XCTAssertNotNil failed + :143 fatal unwrap——「首编辑
  物化 offset」断言设防)→ 还原回绿。附观察(obs-2):转换锚 6 法对该
  掏空**不红**(parity 直喂 convert 输出不经 effective)且 kernel-vs-ref
  亦不红(kernel 与 ref 双侧同源同变)——判别子缝的设防面单点化为
  gate 投影一法;职责分工可接受,记录备查。流程注记:首轮探针未重建
  产物跑了旧二进制(假绿),重建后复测才真红——探针纪律 = 改源必重建。
- **探针② ConvertLegacy 拟合扰动**(target 指数 ×1.05)→ 重建后转换锚
  **4/6 红** → 还原回绿。转换锚对拟合扰动设防 ✓。
- 探针脚本与数值:`/tmp/m94_probe_gamma_semantics.swift`(B-1 实锤,
  见 §3.2)。

## 七、越带 +35 构成独立清点

- 六新测试文件法数亲数:`ColorWheelsToneWheelGoldenTests` 11 +
  `ColorWheelsLegacyConvertTests` 6 + `ProcessForkCacheKeyTests` 4 +
  `ProcessMigrationGateTests` 4 + `LutEncodingExpansionTests` 6 +
  `SmallPoolUITests` 4 = **35**,与 SUMMARY 构成表(IOPParity 11+4/IOP
  6+6/App 4+4)精确吻合;八既有对齐文件(bump/扩表字面钉)法数清点
  与「只改值不增减法数」声明一致。越带非凑数——每法对应验收形态清单
  (转换锚双带/解析锚 9 法/折键三件+账本/gate 五态/marker 双形/fork
  投影/stars 全表/XPan 全臂),与 M9-2 越带同形,申报成立。
- 基线链对账:4391(任务书)⊕ 35 = 4426 与全套终值自洽(executed Δ
  精确闭合);skip 34 持平零新增族。

## 八、T3/T4 抽核与键族

- LUT add-only:enum/曲线/gamut/行全尾插;10 行 id 拼写与上游 c740f7b
  逐条对照 ✓;7 曲线 Float64 双落笔(encode/decode);既有 17 行 + 9
  gamut 前缀恒等断言在册(Lut3dEncodingTests 对齐后 27/18/9)。
- 解析锚数值同源:ΔEV 表/分离比 ≥4×/中性 ≤1e-6/disc 往返 1e-4/截单位圆
  与上游 test.cpp 断言值逐点同;超域采样(black±外/t 边界)在册
  (v3SampleField :115-119)——OQ-4 兑现。
- 键族 18 键 xcstrings 亲数在册(panel_wheels 4 + tooltip 4 + panel_
  process_migrate 5 + action_show_in_finder + menu_image_finder +
  panel_crop_aspect 3);UserDefaults 零新键 ✓。
- NOTICE T(Alcedo GPL e1effd8)+ U(OCIO 2.5.1 BSD)条目在册 ✓。

## 九、发现清单(B/M/m/obs 逐条)

| 级 | 条目 | 摘要 | 消解建议 |
|---|---|---|---|
| **B-1** | gamma 倒数语义错配 | convert target 用上游直指数,我方 v1 冻结 = 1/γ;gamma 非中性旧档升号观感反转(实测 1.17-2.34 stops,中灰翻转);测试锚 legacyApply 同病;文案只称 small tonal shift;DECISIONS 零申报 | 拟合 target 改 1/legacyGamma + goldens 重钉 + 申报(推荐);或设计裁决接受翻转 + 文案如实改写 |
| **M-1** | Finder 两法断言力虚置 | testFinderDoorsAccessibilityRegistration 断言自构造字面量数组(Set.count==3)、testFinderExistenceGuardSemantics 断言 Foundation 库行为——均与产线零耦合;plan T4 字面「三门 AX 可达 + typed degrade 入 SmallPoolUITests」未兑现;DECISIONS §11 只申报 stars 未申报 Finder(产线三门实装本身亲核无缺陷) | 补产线符号耦合断言(AX id 常量对产线源/注入 reveal 闭包的可测缝)或补申报 |
| **m-1** | 拟合残差带覆盖面 | 断言带 0.035 锚在近中性锚点集;γ_s 偏离 1 达 0.2 时实测 0.081(独立探针 A2),真实 v1 域 γ_s∈[0.9,1.1] 端部超带叙事;DECISIONS §5 只锚两构造域 | 随 B-1 修复重钉;或扩带申报(按域端) |
| **obs-1** | 折键负测镜像域 | 三负测在手写 foldChain 镜像域,无真 PixelPipe 升号缓存 miss 集成负测(挂人工走查);镜像漂移风险低但在 | 后续补集成级负测(非本批义务) |
| **obs-2** | 判别子设防单点化 | 探针①显示判别子缝唯一设防 = gate 投影一法(kernel-vs-ref/转换锚双侧同源不设防) | 职责分工记录;可在 golden 增「convert 腿显式」断言 |
| **obs-3** | plan 外文件 6 处 | IOPPanelProvider(+29 读通道/挂点)/FilmPanelModel/EditorState(cw marker)/IOPModule(processForkHash default 落位)/MatchColorToolset(ColorMatchDocument 构造点)/IOPPiece——均 T2 连带合理落位漂移;FilmTailPolicy 已申报;另 m9-3 omp-evidence/monitor.log 1 行混入 T5 commit | 登记备查,无需动作 |
| **obs-4** | G4 越门 | Data 卷 23980MB<25GB BLOCK → 按三批 §9 先例透明越门 + monitor 伴跑零告警(峰值 7673MB) | 追记如仪(本报告即) |

## 十、正向确认摘要(不重复正文)

封存面 17 件零 diff;例外恰形(PixelPipe 2h/metal 纯 append/冻结体 md5
8943b9a4 亲证);五件套全;判别子链/镜像/折键/穿线/迁移 UX 四面/
thumbnail 修订+豁免全兑现;三 bundle 逐位同值;越带 35 法精确吻合;
peakNits/解析锚/超域/键族/NOTICE 全对;双探针真红还原零残留。

## 附:第二路运行证据

- 定向:build-for-testing ×4(基线 + 探针① + 探针② + 还原验证);
  IOPParity 1641s / IOP 944s / App 605s;monitor `/tmp/m94_acc2_monitor.log`
  (start 17:59:23,零告警)。
- 探针:App crash 日志 `/tmp/la-direct-tests-App.log`(:139/:143 真红);
  数值探针 `/tmp/m94_probe_gamma_semantics.swift` + 输出(Scenario A/B
  全表见 §3.2)。
- 主树终态:`git diff` 空(还原亲证);报告 + 本文件 = 唯一产出。

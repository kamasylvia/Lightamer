# LENS-01 DECISIONS — plan L1 裁定记录

> 正本 = CONTEXT.md(D-LENS-1..8 / X1..X4);本文件只记执行期裁定与偏差申报。

## D-L1-1 decodeParamsHash 覆盖面核验结论(T1,X2 边界)= **已覆盖**

`RAWTechnicalOverrides` 全部 setter legs 落 `RAWTechnicalParams`,`HistoryHash.decodeParamsHash`(HistoryHash.swift:148-175)逐字段显式折叠:

| override | rawTech 载体 | 折叠面 |
|---|---|---|
| noiseReductionAmount | noiseReductionAmount | 恒折 |
| luminanceNoiseReduction | optional | 设才折 |
| colorNoiseReduction | optional | 设才折 |
| sharpness | sharpnessAmount(optional) | 设才折 |
| boost | optional | 设才折 |
| decoderVersion | decoderVersionUsed.rawValue | 恒折(渲染真相——request 与结果同 v8 时语义等价,折结果正确) |

结论:**v1.x 的 `vendorLensCorrection` override 落地时按 L013 规则扩字段列表即可**(optional nil 不折,旧档 hash 零漂移),本批零改。证据行号:RAWDecoder.swift:36-60(overrides struct)/ HistoryHash.swift:148-175。

## D-L1-2 ImageIO 写侧丢弃 0xA405(T1 fixture 形态)

CGImageDestination 对 TIFF/JPEG 的 EXIF dict 写入**不序列化** `FocalLenIn35mmFilm`(0xA405;2026-10-21 探针实证,LensMake/LensModel/FocalLength 正常)。ExifLensFieldsTests 的 fixture 改为**手织最小 TIFF 字节**(II 头 + IFD0 十 entry + Exif IFD 0xA405/0xA433/0xA434 + 4×4 RGB8 strip),ImageIO 读侧正常拾取。该织器骨架供 T2 探针测试复用。无产线影响(读侧行为既有且被钉住)。

## D-L1-3 T2 构造点拓扑(review M6 执行形)

plan 预写行号 `:236/:358/:121/:138`,实际提交后 = `RAWDecoder.swift:236/:361`(T2 自身插入 isDNGUTI helper 使 decodeRaster 构造点 +3)+ `RasterDecoder.swift:121/:139`(embeddedGeometry 注释行 +1)。「各腿恰一处」按实际拓扑兑现:RAW 腿一处条件分支(`isDNGUTI(uti) && probe → .detected`,否则 `.unknown`,含 DNG 无 tag 桶);退役 decodeRaster 与 RasterDecoder 两腿恒 `.notApplicable`。

**DNG 无 opcode tag 落 `.unknown` 非 `.notApplicable`/`.detected`**:plan 措辞「任一 tag 存在 = detected;非 DNG = unknown」未明 DNG-without-tag 桶——执行取 unknown(缺席 tag 不能证明无校正,与 X1 保守语义一致;风险节「探针假阳性保守方向无害」同理)。

## D-L1-4 探针入口双缝(review m10)

`probe(url:)`(FileHandle seek 式有界读,产线面)+ `probe(data:)`(窗口语义:引用越窗 = 缺席 = false → 调用方落 unknown 安全向)。walk 深度帽 1(IFD0→SubIFD),entry 帽 4096,SubIFD 数帽 8;opcode payload 零读取(存在性语义)。

## D-L1-5 阈值常量与 `?? 1.0` 兜底分布(T3)

`autoApplyThreshold = 60` 恰一处声明(LensfunMatch.swift:111)。`params.imageCrop ?? 1.0` 兜底出现两处——`matchCommitted`(match gate 输入面)与 `resolveCommitted`(resolve crop/NS·HW 折算面)——同一 X4 优先链穷尽后的兜底语义在两个消费点的投影,非双真相(链源头 = reloadDefaults 单点 bake)。plan grep「恰一处」按「兜底语义单源」兑现,特此申报。

## D-L1-6 歧义判定语义(T3)

同分多候选 = **不同 entry 同最高分**;同 entry 多 model 变体(model 数组)不算歧义(lensfun 单 entry 多语言/别名变体)。40 分档无同分拒绝面(40 本身已被阈值摘除,歧义判定只作用于 ≥60 段)。

## D-L1-7 LensMatchOutcome public 形态(T5 App 可达面)

App 面板消费 outcome → `LensMatchedProfile`(public:maker/model/cropFactor + internal entryIndex)替代 LensEntry 关联值(App 不可见 internal LensEntry)。resolveCommitted 经 internal index 在同一 stamp 内回取 entry。`matchHardened` 的 100/60/40+5 打分本体零改(红线)。

## D-L1-8 memo 键面(T4,review M4 落地形)

键 = FNV-1a("lightamer.lensfun.memo.v1" ⊕ cameraMaker ⊕ cameraModel ⊕ lensKey ⊕ imageCrop bits ⊕ focal bits);aperture/distance 不折(resolve-only);width/height 结构性缺席(值 = 匹配结果非系数)。值 = `(matched(entryIndex)/ambiguous/noLens/missingFocal)`;LRU 32;install/uninstall 换 stamp 清表;打分在锁外、读写表在锁内。memo 结果不写 params(持久化 = LENS-04 T1 域)。

## D-L1-9 旧键复用终形(T5)

`panel_lens_embedded_note` 保留 = **未判定(nil)文案**(zh/en 值零触碰);`panel_lens_no_exif` 保留 = idle 面。新增七键:`panel_lens_embedded_detected/unknown/notapplicable` + `panel_lens_match_matched/ambiguous/nolens/nodatabase`。

## D-L1-10 parity fixture 硬化适配(T3 回归面)

LensParityTests `testUnifiedExitMatchesManual` 的两 fixture params 补 `imageCrop = 1.534`——硬化后 nil→1.0 兜底撞 0.96 crop gate(1.0/1.534=0.652)→ blit identity。此即 plan 风险节预告的「阈值收紧匹配率回落」在测试 fixture 上的显形:fixture 相机本就是 1.534-crop 机身,补 crop = 语义正确化,非放宽门。

## 偏差清单

- ΔN +36 越带(+13..18)——SUMMARY 申报(表驱动密度,非膨胀)。
- plan 预写行号漂移(D-L1-3)——拓扑等价兑现。
- 其余零偏差。

## 修复批(B-1 + M-1 + 顺手 minor;2026-10-20,验收 `LENS-01-ACCEPTANCE.md` 1 blocking + 1 major + 4 minor)

### F-1(B-1)`isNeutral` 语义扩展 = 「手动滑杆中性 **且** 无激活 lensfun 校正」

- 机理:旧谓词只看手动滑杆存储;本批三条主写入路径(auto-apply / browser 选型 / 快照 bake)全不写滑杆 → 零滑杆 lensfun 文档在 `process()`/`modifyROIIn`/`pointMapSegment` 三门恒 identity blit——「选型即校正」在渲染面静默 no-op;既有测试全绿为自消结构(直调 resolveUniforms / 手工抄滑杆 / `_ = (via, man)` 丢弃)。
- 终式(LensModule.isNeutral):`enabled == false` 臂保持最前;手动七系数全零后,`source == .lensfun` 时 **snapshot ≠ nil ∨ `LensfunStore.resolveCommitted` 可解析命中 → 非中性**;resolve miss = 中性(数据缺席降级保持静默 identity,免逐帧 warning 刷屏;resolve nil-ness 与尺寸无关——match + target-refusal + DB 在场三因子,探针尺寸任意)。`.off`/`.manual` 语义不变(红线 12 默认中性不受扰;真手动全零 + 无选型 = identity blit 短路不回归)。
- 配套:
  - `pointMapSegment` 加零系数守卫——零滑杆 lensfun 文档保持 1:1 蒙版映射(B-1 不下放到 mask 面;lensfun-warp 蒙版映射 = 已登记后续面);手动 TCA/vignette-only 档由零系数段改回 nil(同为恒等,语义更诚实)。
  - 新 golden `testPureLensfunZeroSliderDocRendersThroughProcessGate`(LensParityTests):真 pipe(process 面)零滑杆 lensfun 渲染 ≠ 输入(行为级证明)+ 与同系数手动门逐字节恒等(poly3-only profile 落手动可拼子集);`testLensfunResolveMissKeepsSilentIdentityFace` 钉 miss 面渲染级恒等;`testNeutralPredicateReadsActivatedLensfun`(LensPerCorrectionTests)六臂 truth table(命中/快照零 DB/miss/.off/.manual/enabled-off)。
  - 自消结构消解:`testUnifiedExitMatchesManual` 的 `_ = (via, man)` 丢弃改为真断言(lensfun 门渲染 ≠ 输入);`testLensResolvedTCAUnionWidensROI`(ROINegotiationTests)改双臂可比形——子窗 roiHint(全帧 clamp 会重吞 union 增量)+ 强 TCA(vr=1.06)+ 中性 verbatim 锚臂,双臂为可证计算面,严格加宽断言替代 verbatim==verbatim 假绿带。

### F-2(M-1)fisheye-from-equirect 双侧重转录 = Alcedo 真等距式

- 旧臂(Swift `LensProjection.fromEquirect(.fisheye)` 与 Metal `projFromERect kFisheye`)= 立体式 ksp 公式,与自家 stereographic 臂逐字相同(Alcedo `ApplyProjectionERectStereographic` 误标 `ApplyProjectionERectFishEye`);defish 主用例径向误差 y=1.0rad 时 +9.3%。golden CPU twin 同笔转录同错同源自消。
- 终式 = Alcedo `ApplyProjectionERectFishEye`(lens_calib.metal :219-238)逐式重转录:theta 反射骨架 + `theta2 = atan2(hypot(vx,vy), s·cos x)` + 输出 = theta2·单位向量(等距:盘半径=极角),Swift Double / Metal float 双侧;归属注释与 Portions Copyright 头保持。
- 配套 golden(独立真相,非同源 twin):`testFisheyeFromEquirectIsEquidistantNotStereographic`(轴上 r(θ)=θ 含 y=1.0;离轴球面恒等式半径+方向;stereographic 轴上 2·tan(θ/2) 对照,两臂互异)+ `testFisheyeProjectionRoundTripIdentity`(equirect→fisheye→equirect 往返恒等,双向网格含 y=1.0 边界,门 1e-9;stereographic 对自身往返沿带对照)。既有 kernel-vs-CPU-twin 对表四法不变(双侧同批重转录后继续钉 kernel==CPU;链路 = 往返恒等钉 CPU 公式真,twin 钉 kernel==CPU → kernel 真)。

### F-3(minor 三件)

- m-1:`LensKernels.metal` 头注释 SCALE 段随 D-L3-3 求值序修订(×1/scale 施于中心相对输出坐标、先于投影折;L2「映射后偏移」面退役注记)——plan T1 action 2 漏改补齐。
- m-2:`Project.swift` 补 `.folderReference(path: "Resources/Licenses")`(plan L3 T5 明文第二条;bundle 级归属面齐全)。
- m-3:BUNDLE-MAP lens 族八行计数同步(LensParity 7→9、LensPerCorrection 6→7、LensProjectionGolden 7→9 为本批新增;LensAutoCrop 6→7、LensScaleGolden 3→4、LensDefaultNeutral 2→3、LensProfileBrowser 8→7、LensfunDistribution 7→6 为验收 m-3 存量 stale)。
- m-4(LENS-02 T5/T6 单 commit)不涉产线,验收已判「登记备查」,本批不动。

### F-4 process version 裁决(修复批)

见 `LENS-04-DECISIONS.md` 裁决表第 9 行:**不 bump**(缺陷修复律 + 改动面自 04-04 以来从未生效过——identity blit / 误标公式无任何已交付观感可冻结;渲染前修复,无存量文档承载旧行为)。

## B-2 接线修复批(2026-10-20,验收二 `LENS-01-ACCEPTANCE-2ND.md` 1 blocking;commit `fix(lens-01): wire reloadDefaults into production seams — B-2`)

### B-2 三缝接线 = reloadDefaults 进入产线(死路考古 + 接线落点)

- **死路考古(二路确证,本批复核)**:`IOPModule.reloadDefaults` 自 Phase 02 引入以来全仓零生产调用点(仅 17 处测试;`git log -S ".reloadDefaults(image" --all -- App LightamerCore` 零命中)→ Lensfun 四条产线路径全死:①auto-apply(LENS-02 T2,`lensfun.autoApply` 键 + 硬守卫 + 注入式 reader 全就位但运行时无人读)②browser 选型(EXIF 字段唯一生产写入点 = reloadDefaults,镜头实例恒静态默认 → `matchCommitted` guard focal > 0 恒 miss → identity +「无镜头信息」)③系数快照 bake(D-L4-1 option A 同步 bake 内嵌 reloadDefaults,无可达调用者)④detected 确认门(embeddedGeometry 恒 nil,确认永不触发)。
- **应然调用缝(逐缝对照 plan 原文)**:缝① = **EXIF 解析完成 + auto-apply 开**(LENS-02 T2:reloadDefaults 是 defaults 缝;生效域硬守卫在函数内——autoApply 键 + `embeddedGeometry == .notApplicable` 唯一 + lensKey 非空;EXIF 快照字段无条件随行 = D6 设计「resolve inputs baked here so params stay self-describing」)→ 落点 **pristine 载入 seed**(`PipeCoordinator.load` 无 sidecar 分支,`LensDefaultsWiring.injectedLensSeed(into:image:)`,:1243);缝② = **browser 选型确认**(LENS-02 T4 Apply 退役改确认制,确认动作/直选同一 commitSelection 缝)→ 落点 `LensPanelView.commitSelection` → `LensDefaultsWiring.committedSelection(base:candidate:image:)`(:588 起);缝③ = **快照 bake**(RESEARCH「auto-apply 同步 bake」句 + D-L4-1 option A:bake 语义 = reloadDefaults 内同步 bake,同一 commit 翻 source)→ 随缝①②到达产线,零新代码。守卫单源:调用点不复述三态互斥(reloadDefaults 内部硬守卫即单源);幂等(重复调用同值)。
- **装配纯函数范式(makeRunAssembly 先例)**:两缝装配逻辑提为 `App/Sources/Lightamer/State/LensDefaultsWiring.swift` 纯函数,coordinator/panel 只留 I/O 壳——状态层机检缝,视图/协调器不承载装配逻辑。缝②附修:选型 bake 换 **rematch 面**(fresh bake per selection;miss 清陈旧快照——修复前 bake-miss 沿用旧快照的静默不一致随写入路径变活而成为真缺陷,随缝修复)。
- **范围让渡(不接线面,登记)**:①**restore 分支不折**(sidecar 恢复文档持久 params verbatim——「affects NEW images only」per-image params 规则;遗留文档经缝② browser 选型时由 exifRefreshed 现折 EXIF,选型可达);②`SidecarSeedTopUp` 补种记录保持 identity/neutral 契约(零像素语义面,折 EXIF 会改 paramsData 字节);③`LightamerShell.seedInstances`(粘贴/预设合成基座)与 MCP `EditingToolset.editingSeed` 非图像载入面,不折(agent 通道可显式传 lens params);④层链加模块 template 静态默认(lens 恒在载入 seed,加面仅重加场景,缝②可达)。

### 反死路回归(消洋葱;LensDefaultsWiringTests,APP bundle,8 法)

- **测试全走真产线缝**:缝①②经 `LensDefaultsWiring`(产线调用的同一函数,装配纯函数范式)+ 缝级硬守卫三态表 + E2E **真 `PipeCoordinator.load` 链**(EditorMetalLegRegressionTests 合成梯度先例)断言 editorState 实携 lens record 的 source/focal/resolve 三点。m-5 golden = resolveUniforms 手动臂投影折(`sourceProj` uniform 携 decodeLenient enum raw,rectilinear=1/fisheye=2/equirectangular=4 三点断言)。
- **红绿双腿(两腿齐)**:
  - 腿 A 运行时红:探针法——stash 产线三笔(PipeCoordinator/LensPanelView/LensModule)+ 仅既有 API 的 E2E 探针(可编译于修复前树)→ **三断言全红**(`off ≠ lensfun` / `nil ≠ 16` / resolve nil;`fix-batch/b2-red-green/red-run-prefix-tree.log`);恢复后同探针类 **8/8 绿**(`green-run-newclass.log`)。两缝纯函数测试在修复前树 = 编译红(API 不存在,如实申报)。
  - 腿 B 源级机检:`grep -rn "LensDefaultsWiring\." App/Sources` = 恰 2 产线调用点(PipeCoordinator:1243 + LensPanelView:591);`grep -rn "\.reloadDefaults(image" App LightamerCore LightamerIOP`(排除注释)= 恰 2 生产调用(LensDefaultsWiring.swift:55/:88);本批 commit 后 `git log -S ".reloadDefaults(image" -- App` 首次落产线 commit。

### m-5 手动门投影折叠(修复,≤10 行)

`resolveUniforms` 手动臂(LensModule.swift:702-717)补 `targetProjectionRaw/sourceProjectionRaw` 装配(4 行)——与面板 `resolvedScalePreview` 手动臂(:482-485)对齐,消「同文档 readout 折叠 / 渲染不折」分叉(B-1 同族静默 no-op,combo = 手动系数 + 投影选型)。nil raws(默认档)decodeLenient = rectilinear 恒等,历史字节零漂移;golden = `testManualArmFoldsProjectionRaws`(三 slot 断言)。

### o-B 让渡(登记,不本批)

matched + 非 rectilinear entry + target 未设 = resolveCommitted 保守拒 → 渲染 identity,readout 仍「匹配到配置」无「需选 target 投影」提示(LENS-03 T1 既定保守拒设计;xcstrings 无此文案键)。让渡理由:文案属 UX 补全(新 xcstrings 键 + 状态机新面),与本批「接线修复」正交;挂后续 UX 轮。

### 复验数字(定向 + 全套)

- 定向:IOP **753/5/0**(峰 5800MB)+ IOPParity **478/6/0**(4966MB)+ App **969/6/0**(2832MB)——前两 bundle 逐值 = 二路验收基线;App 969 = 基线 961 + 8 新测试精确;skip 零漂移;峰全 <8G 门。
- 全套:`--all` 一轮 **`TOTAL|4101/40/0|`** exit 0 零 MEMFAIL(峰 IOP 7680MB 门内)= 4093(二路基线)+ 8 新测试精确;skip 40 零漂移;七 bundle:IOP 753/5/0 + IOPParity 478/6/0 + Layers 494/5/0 + Library 738/4/0 + Sessions 284/9/0 + Export 385/5/0 + App 969/6/0,前六逐值 = 二路基线。
- 守卫偏差申报(D-L4-4 同形):`machine-guard.sh --wait 1800` 满窗 G3 swap ~4.1GB 恒静(冷页残留零衰减);G2 可用内存 83% + G1 零并发重活亲核,`/usr/bin/time` ru_maxrss MEMFAIL 机检兜底在岗,定向轮峰 5800MB / 全套轮峰 7680MB 均 < 8G 门,放行正当。

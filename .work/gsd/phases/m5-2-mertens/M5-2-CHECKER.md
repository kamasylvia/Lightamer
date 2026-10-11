# M5-2 CHECKER — Mertens 曝光融合 plan 集（M5-2-01 + M5-2-02）从严审查

> Checker = zcode subagent（从严口径）。审查对象 = `M5-2-01-PLAN.md` /
> `M5-2-02-PLAN.md`，规格正本 `RESEARCH-NOTES.md`，裁决正本 `M5-2-CONTEXT.md`
> 裁决记录（2026-10-11 用户回批）。源码锚全部亲核（非转述）；Lumen
> `lumen/merge.py` 315 行对照亲读。日期 = 2026-10-09（checker 派发批）。

# PASS / 0 error + 5 minor

5 处 minor 均为规格完备性/账面口径级，**不阻断派发**；处方随条，建议执行批
随手修并落各自 DECISIONS。逐维审查如下。

## 一、裁决一致性（七项生效值 → AC 对表）——PASS

| 生效值 | 落点 | 判定 |
|---|---|---|
| OQ-1 = A 自实现 + MIT 注记 + OpenCV 零入仓 | 01 KD-1/KD-3 + AC1（`git grep -i opencv` 门 + dependencies 零 diff + 零新 `.metal`） | ✅ |
| OQ-2 = A display [0,1] 32f + M4-1 链 + kind 域判别 | 02 KD-2（sRGB tag 修正形）+ T2 两域判别钉 + AC1 | ✅（修正有据，见 §三） |
| OQ-3 = A deghost 四态默认 medium 无面板 | 01 KD-4（nil→medium 腿层语义）+ 02 KD-5（sheet 零档位控件）+ AC2 | ✅ |
| OQ-4 = A 互为选项 + `_mertens` 分账 | 01 KD-4 defaultTag `"mertens"` + 02 KD-5 两菜单项/Robertson02 原样/零择优 | ✅ |
| OQ-5 = A 免 EV（extent+N 硬门，aperture/ISO warning） | 01 KD-6 `mertensVerdicts` 零拒绝面 + 严格版对照负测 + 02 AC3 消费面 | ✅ |
| OQ-6 = A sRGB piecewise + 层数自适应 + halo 流式 + 8G 机检 | 01 KD-1/KD-2 + 02 KD-1/KD-6（ru_maxrss 门） | ✅ |
| OQ-7 = A 六门 | G1/G2/G3/G5 = 01 T4/T5；G4/G6 = 02 T4/T5；VALIDATION 全表 | ✅ |

- `dual_acceptance = true`（`.work/config.toml [gsd]` 亲核）→ 两 plan T5 均
  落「zcode PASS → 串行 omp 二次验收，严禁并发」+ ACCEPTANCE 落盘。✅
- `paused = false` / `auto = true` 亲核，无门控冲突。✅

## 二、算法实现——PASS（2 minor）

亲核 `lumen/merge.py` 逐段对照：

- **档表** `{'low':(.20,2),'medium':(.12,5),'high':(.065,9)}`（:122）与 01
  KD-3 逐值一致；σ1.2 模糊 / 33 点分位 2..98% / 抽样 `ceil(max/1000)` /
  可用门 (0.015, 0.985) 双帧开区间 / 膨胀 `radius×max(dim)/1800` / 羽化，
  全部吻合（:123-138）。✅
- **置换语义**（:141-169）：静止格 `motion<0.01`、逐通道 129 点分位 LUT、
  `prepared = original·(1−α) + LUT(ref)·α`——**融合前 in-pass**；02 KD-1 ⑥
  把置换放在条带融合之前（refStrip 已在手），顺序正确，merge.py:153-155
  注释明言的「融合后贴参考 = 亮矩形」风险被结构性消解。✅
- **三因子权重**：C=|Laplacian(gray)| / S=std(RGB) / E=∏exp(−(I−0.5)²/2σ²)、
  σ=0.2、wc=ws=we=1.0（merge.py:167 `createMergeMertens(1.,1.,1.)` 锚）✅。
- **G3③ 修正数学验算**：E(1.0)=exp(−0.25/0.08)=exp(−3.125)≈0.0439>0 ✅
  「零化→压制（占比门 ≤5%）」修正成立（另见观察项 O3）。
- **金字塔**：reduce/expand 复用 `FocusStackMerge`（binomial [1,4,6,4,1]/16 +
  linear 2×，DC-consistent telescoping exact——08-3 T2 验收面亲核）；
  `reduce`/`expand`/`gaussianPyramid`/`laplacianPyramid` 均 internal static，
  同模块直调访问级已足，无需提升。✅
- **层数自适应** `clamp(1+floor(log2(minEdge/32)),1,12)` 真值表逐行验算：
  32→1 / 64→2 / 256→4 / 512→5 / 1024→6 / 8642→9 全对。✅
- **halo 公式** `max(32, 2^L)`：感受野 2^L−2（FocusStackMerge 头注
  「≈30 rows @5 层」同式亲核）≤ halo；L=5→32 精确命中 `defaultHaloRows=32`
  既有常数。✅

### minor-1（01 KD-3）：Lumen `static.sum()<64` 兜底分支遗漏

01 KD-3 声明「置换语义（merge.py:141-169 原样移植）」，但 merge.py:146
`if static.sum()<64: static=np.ones_like(...)` 的**全格兜底**未进移植清单。
全帧运动极端场景下静止采样集为空 → 129 点分位在空集上求值 = 未定义/退化。
**处方**：01 KD-3 增补一行兜底语义（静止格不足 64 → 全格视作静止），02
KD-1 LUT 预计算段同句引用；执行批随手落 DECISIONS。

### minor-2（01 T4 G3①）：双帧恒等的前置条件未写明

G3①「同帧 ×2 → 输出 == 输入（带 ≤1e-6，预期逐位）」仅在**权重场非恒零**
处成立：W = C·S·E 在 flat 区（C→0）或灰像素（S=0）真零，双源同零处融合
输出走 ε 守卫 = 0 而非输入值。合成 fixture 若取灰度 ramp（R=G=B，S≡0）
将全帧失配、golden 大红。**处方**：T4 补 fixture 条款——恒等靶面保证处处
S>0 且局部有对比度（如 RGB 三通道错相 ramp）；或断言限缩到权重为正像素。
顺带把两个未钉常数写进 T1 注记（gray 系数 = Rec709 luma 与 merge.py
`cv2.COLOR_RGB2GRAY` 对齐；std = population 口径与 OpenCV 对齐）。

## 三、域语义——PASS

- **KD-1 依赖图修正成立（亲核证实）**：`LutEncodingCatalog.swift` 确在
  `LightamerIOP/Sources/Lut3d/`；`Project.swift` :10 头注 + :144
  `.target(name: "LightamerCore")` 证实 IOP → Core 单向——Core 侧 `Stack/`
  反向 import 禁止，research §3.3 ②「LutEncodingCatalog 现成」的依赖方向
  确实不成立。`DrtEotf.srgbPiecewiseEncode/Decode`（`LightamerCore/Sources/
  Pipe/Drt/DrtEotf.swift` :172-182，文件内注记 M4-1-01 KD-8，golden 经
  `DrtEotfTests` 在册）为正确接缝；编码函数自带 [0,1] clamp（:180），KD-1
  显式 clamp 约定冗余但无害。✅
- **KD-2（02）sRGB tag 修正成立（亲核证实）**：`RasterColorDescription.resolve`
  ② 规则（:225-236）= 无 ICC float32 → scene-linear Rec.2020（origin
  `tiffNoIccFloatLinear`）——research §3.4「无 ICC → sRGB 判定」对 float32
  确实不成立，草案若落盘 = display 值被判 scene-linear 的域误判。sRGB tag
  路径：① named-space `kCGColorSpaceSRGB`（:267-271）→ displayReferred +
  srgbPiecewise；Primé 规则（:254-258）只对 `transfer == .linear` 触发，
  sRGB 不命中 → M4-1 display 腿 linearize → sceneLinear。**OQ-2「零新机制
  + kind 域判别」在修正形下完整保持**，两域判别互证（Robertson02
  linear-ICC 对照 Primé → sceneLinear）设计成立。✅
- 金字塔全程在 sRGB 编码域（权重语义 [0,1] 中心 0.5），与 OQ-6 生效值及
  Mertens display-referred 本体一致；deghost 亦在编码域后（02 KD-1 ②→③
  序），与 Lumen display 域前提（merge.py:1）同构。✅

## 四、编译/结构——PASS

- **四处穷举 switch 落点亲核**（新 case 编译期全破，逐处补臂方案成立）：
  `provenanceKind`（:255-263）/ `stepTotal`（:548-557）/ `defaultTag`
  （:561-569）/ `runProductionMerge`（:827-841）。✅
- **MergeParams additive**：init（:313-325）尾部追加双 optional，既有 11 参
  调用点零改动；synthesized Codable 对 optional = encodeIfPresent（Swift
  语义事实），旧档零漂移 + 专测钉死方案成立。✅
- **ProvenanceReplay**：Kind（:37-43）raw 值镜像纪律 + 独立算法名/版本常量
  位（:141-144 邻域）✅。
- **免 EV 与 refactor 分界正确（亲核证实）**：`precheckStack` aperture 严格
  （:235-251 reject 分支）与 OQ-5 相抵——02 KD-3 只抽 MTB 段为
  `runMTBAlignment` helper、不复用预检段的分界论证正确；`runStackPrecheckAnd-
  Alignment` :1106-1162 行号锚精确；「既有测试零 diff 为证」的行为保持
  红线 + 回退备选（Mertens 持私有副本）在册。✅
- **landStackProduct additive 双参**（:1382-1386 尾部追加缺省 nil）：既有
  flat-zero EV / nil layerStack 路径字节零漂移；`exposureRatioVerified`
  全 true 已是 :1424 既有形——OQ-5 占位确为零新代码。✅
- **writeFloatTIFF additive colorSpace**（:149-151 加参缺省
  `WorkingSpace.colorSpace`）：生产调用点 2（runHDRLeg :1006 /
  landStackProduct :1396）+ 测试多点，全部零漂移。✅
- **stub→真腿交接**：01 落 dispatch 臂 + typed stub（M4-1-01「路由不切」
  同形），02 只换腿体零二次编辑；01 T2 的「合成腿 done==total」用注入腿
  测试缝、stub typed 失败用生产腿——两测试不矛盾。✅

## 五、红线——PASS

- Robertson02 逐字节不动（`runHDRLeg` 函数体零 diff 截屏 + G5 复验双保险）；
  ExportQueue 队列/取消/进度/落地骨架零改（唯一例外 refactor 在
  StackMergeService 内部）；六格式导出矩阵 / sidecar schema / JPEG-PNG-RAW
  零回退——两 plan 纪律节 + 零 diff 自证清单全覆盖。✅
- 零新 SPM（Project.swift 仅登记测试数组，dependencies 块零 diff）+ 零新
  `.metal`（Stack 域现状零 .metal 亲核）。✅
- L072 temp 域 / L014 fence / L041 tuist generate 恒末位 / L057 runModal
  禁入（现状 `grep -rn "\.runModal(" App/Sources` = 0 命中亲核，T3 负测
  维持）/ V14 静态键 + xcstrings 尾块纯插入——全挂在册。✅
- 100MP probe 双保险：env 门 `LIGHTAMER_PERF_PROBE=1` + 批准制 + MEMFAIL
  即 kill；`Scripts/test-direct.sh` `RSS_LIMIT_MB=8192` 机检亲核在册；
  probe 落 EXPORT 的贴线 rationale（IOP 7654MB）成立。✅

## 六、测试对账——PASS（3 minor）

- **基线勘误链已写入**：01 基线段记 3477/21/0 = M5-1-VALIDATION 终验亲证值
  （:23 `TOTAL|3477/21/0|`、:38 七 bundle 逐行、:39 对账链三处亲核），
  派发指令 3335/16/0 陈值已显式勘误。✅
- **估数**：+42..52 / +22..30 = +64..82，与派发口径一致。✅
- **bundle 分账核对（BUNDLE-MAP 域模式亲核）**：01 四文件 =
  MertensFusionGoldenTests（*Golden* → IOPP）/ MertensFusionTests ·
  MertensMergeKindTests · MertensLegTests（IOP，与 HDRMergeMathTests /
  StackMergeServiceTests 同位）/ MertensProvenanceTests（LIB，与
  ProvenanceV4Tests 同位）；02 四文件 = MertensLegTests ·
  MertensRasterDomainTests（IOP，decode 家族同位）/ MertensMergeUITests
  （APP）/ MertensFusionPerfProbeTests（EXPORT，probe 先例 + rationale
  注记随行）。✅

### minor-3（01 基线段）：勘误链算术笔误

基线段写「M4-3 **+31** 与 M5-1 +110」——正本 = **+32**（M5-1-VALIDATION
:39 + GOAL-STATE：3335 + 32 + 38 + 47 + 1 + 24 = 3477 逐位闭合；3335+31+110
= 3476 差 1）。头值 3477/21/0 无误，仅叙事数字。**处方**：一字改 32。

### minor-4（01 T1）：「真值表 KD-2 八行」行数不符

KD-2 实列 **6 行**（32/64/256/512/1024/8642）。**处方**：T1 改「六行」，
或补齐至 8 行（如 12 帽上界、65536→12）并在 KD-2 注明。

### minor-5（02 front-matter）：test_bundles 含 Library 无对应落域文件

02 四新测试文件落域 = IOP×2 / APP / EXPORT，无 LIB 文件。**处方**：删
Library，或注记「Library = G5 复验定向轮口径」（01 的 LIB 行有
MertensProvenanceTests 支撑，02 无）。

## 七、goal-backward——PASS

- IOP-HDR-06 交付定义（免 CRF 快速第二模式 + 多档 deghosting + 与
  Robertson02 互为选项）由两 plan 合计全覆盖；六门全落位（G1-G3/G5 = 01，
  G4/G6 = 02，VALIDATION 六门全表）；GOAL-STATE 续接点链证实 M5-2 为
  M5-1 closed 后下一站、M5-3 PANO 划界清楚（SIFT/ECC 不入本 phase）；
  VALIDATION = C 档第 3 停；AGENTS 架构增量节 + GOAL-STATE/TODO 翻账均在
  files_modified。✅
- 双波验收编排符合 config `dual_acceptance = true`（串行 omp，结论落
  ACCEPTANCE）。✅

## 观察项（不计级，供执行批参考）

- **O1（01 KD-8 挂账范围）**：decode N 超步为**全 kind 共性**——亲核
  execute 循环 :709 逐源 stepper + markTerminal :761 settle，HDR 声明
  `(2+deGhost)N+3` 实际 `(3+deGhost)N+3` 同样超 N；挂账现只点「08-3 stack
  族」。可放宽一句「五 kind 共性（decode N 未入声明式）」，不改不修的裁定。
- **O2（既有 Project.swift 重复行）**：`LightamerTestsApp` sources 数组既有
  重复登记——RasterEditFaceTests.swift（:835/:837）、RasterHdrViewportTests.swift
  （:836/:838/:839）；先于本 plan 存在、当前 tuist 容忍（3477 全绿在案）。
  两 plan 均要编辑 Project.swift + `tuist generate`（L041），若 generate 报
  duplicate 可顺路去重（以 BUNDLE-MAP 单行登记为准），不属本 plan 缺陷。
- **O3（G3③ 注记因子不全）**：修正依据只引 E 单因子；完整权重 C·S·E 下
  flat 过曝块 S=0 → 权重真零，占比门 ≤5% 以更强方式成立。数学结论不变，
  DECISIONS 落字时两因子并写即可。

## 亲核锚清单（本报告事实基础）

- `LightamerCore/Sources/Stack/StackMergeService.swift`（全文 1586 行——
  MergeKind :247-264 / MergeParams :268-338 / stepTotal :540-557 /
  defaultTag :561-569 / enqueue N≥2 guard :506 / execute decode bump :709 /
  settle bump :761 / dispatch :827-841 / runHDRLeg :849-1077 /
  runStackPrecheckAndAlignment :1106-1162 / focus leg :1167-1265 /
  aggregate leg :1270-1377 / landStackProduct :1382-1454 / StagedSet
  :1459-1586）
- `LightamerCore/Sources/Stack/FocusStackMerge.swift`（全文——defaultHaloRows
  :47 / weightEpsilon :50 / reduce/expand :133-213 / 感受野头注 :20-22 /
  fuseStrip :262-365）
- `LightamerCore/Sources/Stack/ExifPrecheck.swift`（全文——precheck 严格面
  / precheckStack aperture :235-251 / ΔEV 组成式 :148-153）
- `LightamerCore/Sources/Stack/ProvenanceReplay.swift`（Kind :37-43 / 常量
  :141-144 / provenanceHash 排除面 :194-220）
- `LightamerCore/Sources/Stack/BandStreamer.swift`（writeFloatTIFF :149-232 /
  WorkingSpace tag :181）
- `LightamerCore/Sources/Pipe/Drt/DrtEotf.swift`（srgbPiecewise :169-182）
- `LightamerCore/Sources/Decode/RasterColorDescription.swift`（resolve
  :203-247 / ② 规则 :225-236 / Primé :254-258 / named-space sRGB :267-271）
- `Project.swift`（:10/:96-104 packages / :143-144 IOP→Core / 六测试 target
  显式清单）
- `App/Sources/Lightamer/UI/SessionBrowserView.swift`（onHDRMerge :55 /
  gate :151-153 / dialog :321）；`SessionCoordinator.swift`（:127/:131）；
  `LightamerApp.swift`（:883-928 三段形）
- `Scripts/test-direct.sh`（RSS_LIMIT_MB=8192 :70 / MEMFAIL :139）
- `/Volumes/UNITEK/Documents/Development/lumen-raw/lumen/merge.py`（全文 315
  行——:39-43 / :120-138 / :141-169 / :157-165 / :167 / :293-315）
- `.work/config.toml [gsd]`（dual_acceptance/paused/auto）；
  `.work/gsd/phases/m5-1-track/M5-1-VALIDATION.md`（:23/:27/:38/:39 基线）；
  `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（域模式）；
  `.work/GOAL-STATE.md`（M5 续接点链）

## 结论

**PASS / 0 error + 5 minor**。两 plan 规格与七项生效值、源码现状、Lumen
MIT 正本三方对表闭合；file:line 锚全部亲核无虚指；五处 minor 均为账面/前置
条款级，处方随条、不阻断派发（建议 01/02 各自执行批 T5 DECISIONS 随手
吸收，或 orchestrator 派发前一笔勘误）。

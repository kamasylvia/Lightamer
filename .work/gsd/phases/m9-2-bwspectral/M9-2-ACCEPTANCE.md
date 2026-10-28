# M9-2 ACCEPTANCE — 双路 zcode 独立验收·第一路(2026-10-28)

> 验收对象:`af446612`(T1 自建 BW 谱资产 + Wratten)+ `b807b1dd`(T2+T3+T4
> 合一)+ `667bd85c`(账本);HEAD = `667bd85c`。issue #12;AC 源 =
> REQUIREMENTS M9BW-01..03。正本 = M9-2-SUMMARY.md + DECISIONS + PLAN v2。
> 中断叙事:三任中断(限额 ×1 + 意外终止 ×2),T2-T4 接续实现、收口
> orchestrator 代完成——拼装缝专项见 §6。

## 结论

**PASS / 0 error + 1 minor + 6 obs**。三 AC(M9BW-01/02/03)逐条落
file:line 全对上;数据自建红线零复制成立(hash 全对照 9/9 零命中 +
谱值结构抽验全合规);bake 负测组 ①-⑦ 逐法读验齐全且反自取消两处真红;
sidecar v12 豁免面 = 纯 bump + 注释(12 行 diff),v11 恒等负测在册;
全套独立复跑 **4363/34/0** 与申报值逐位一致(七 bundle 全绿、零 MEMFAIL、
monitor 零 kill);拼装缝 40 文件对账零孤儿。

## §1 AC 逐条核对

### M9BW-01 — BW profile 自建 + MANIFEST 对账 + 中性/阶调 golden ✓

| AC 面 | 落点 | 独立核验 |
|---|---|---|
| profile 入谱面体系 | `FilmMaterialStore.init(profilesDirectories:)`(FilmMaterialStore.swift:58 多目录一索引,duplicate-id 跨联合 fail-closed)+ `LightamerShell.swift:921`(BW 第二目录注入,缺席 degrade CC-only never fatal) | BWProfileAssetsTests(Layers 6 法)绿;`testEveryBWFilmBuildsAgainstTheMultigradePaper` 4 卷 build(BWSpectralGoldenTests.swift:163)绿 |
| MANIFEST 对账 | `Resources/FilmProfilesBW/MANIFEST.sha256`(9 文件) | 验收独立实跑 `shasum -a 256 -c` **9/9 OK**(含 T4 更新后的 grain_calibration.json 与 T2 修正后的 multigrade) |
| 三通道同值结构 | BW 4 卷 `data.log_sensitivity` 81×3 | 验收 Python 抽验 tri_x_400:**81 行三通道逐位同值(0 mismatch)**,首行 [-0.7,-0.7,-0.7] |
| 相纸盲通道/三乳剂分裂 | multigrade JSON | ≥560nm 45 行全 ≤-5.5(0 violations);460-540nm **17/17 行三通道分裂**;channel_model 双侧 "bw" |
| SHEET/ASSUMED tags | metadata.tags(tri_x 抽验含 log_sensitivity/density_curves/base_density/granularity 四键) | BWProfileAssetsTests 标注纪律法绿 |
| 中性 golden | `testFivePatchChartStaysChannelNeutralThroughTheSpectralLeg`(BWSpectralGoldenTests.swift:188):五色块 × 4 卷 × 3 grade,spread ≤2e-3 | 绿(全套 IOPParity 540/10/0 内) |
| 阶调 golden | `testGradeLadderDrivesDistinctRenderedResponses`(:251)——**PLAN-DECLARED 降级版**(span>0.05 + 三 ladder pairwise distinct + 18% 灰 0.55-1.10;单调面 00<2<5/5>1.3×00 实测不可达,DECISIONS §6 申报挂 v2) | 绿;M92-TONALITY print 数值台账在法内 |

### M9BW-02 — 变反差相纸 grade + 滤色镜乘法缝 + 零漂移负测 ✓

| AC 面 | 落点 | 独立核验 |
|---|---|---|
| grade 拟合(计算件) | `PaperGradeTable.swift`(gradeKeys 7 档 verbatim :42;ISO R 目标表 :46;affine 校准层 :115-152;active-channel 盲通道剔除 :199-204) | PaperGradeTableTests 3 法(fit 家族/单调+校准 R ±0.05/持久 round-trip)绿 |
| grade 消费缝 | `FilmPrintBake.tables()` printCC 钉 preset(SIMD3(0,m,y))+ gradeEv 走 solve gain 消费层(`FilmTailPolicy.swift:880-884`:`totalGain = autoGain × 2^(gradeEv + exposureEv)`,**不入缓存键**) | X-M92-2 终式逐位对上 |
| **paperGrade String verbatim 三消费面** | ①sidecar 持久键 `paper_grade: String?`(FilmRecord.swift CodingKeys :115)②gradeTag 折叠值 `grade:\(key)`(FilmPrintBake.swift:567)③UI `availableGradeKeys` = gradeKeys 声明序 filter(FilmPanelModel.swift:154-158,**收口修复:非字符串排序——"0" 会排 "00" 前**) | 三面同编码逐点核验 ✓ |
| 滤色镜乘法缝 | `SpectralBuildEngine.swift:464-490`:sensW 窗口段后、tc 循环前;绿通道(index 1)整卷 factor 归一锚 18% 灰;`filterT.count == axis.count` guard + nil 恒等分支 | 位置/数学/恒等三分支逐行核验 ✓ |
| typed 拒绝 | `CameraFilterTable.isValid`(:116)+ coordinator 层 degrade-to-nil(PipeCoordinator.filmLegRequestTags 未知名 → 无 tag) | CameraFilterTests w99/"" 拒绝法绿 |
| ON/OFF 中性链零漂移 | absent 面:CORE 哨兵 `filmRampPlaneHash`(FilmDeterminismTests:44,COLOR pair 全链 hash)+ `testAbsentTagsReServeTheBareBundleInstance`(FilterBakeKeyTests:310,absent consult never rebuilds)+ `identityBuild == neutral`(CameraFilterTests:165,恒等透射 build 逐位=neutral) | 三层承载,全套零漂移 |
| 光谱透传 golden | FilterBakeKeyTests ⑥(18% 灰 |Δ|<0.01)+ ⑦(w25 压蓝 / w47 压红,阈值 0.003——DECISIONS §6 申报降级) | 绿 |
| 导出递缝 | enqueueExportM2 legTags(ExportState.swift:494)→ ExportQueue per-job(:267/:320)→ `$requestTags` TaskLocal(:502-508,嵌套于 $jobDrtTail 内/$jobFilmTail 外) | 三段递缝 diff 逐 hunk 核验 ✓ |

### M9BW-03 — per-film granularity 标定 ✓

| AC 面 | 落点 | 独立核验 |
|---|---|---|
| 标定表 | `grain_calibration.json`:Tri-X 17 / T-Max 8 / Acros 7 / **HP5 null**(四终值与 NOTICE 逐 PDF 核对一致;T-Max 第三方 7.4→8 修正在 note 在册) | GrainCalibrationTests round-trip 法(:40)绿 |
| 强度语义(强度 1 = RMS 同带) | `GrainCalibrationSemanticsTests.testRecommendedStrengthsReproducePublishedRmsInBand`(:193,推荐 strength 下合成灰面 RMS vs 发表值 ±2.0 带) | 绿 |
| 映射确定性/单调 | GrainCalibrationTests(:58 确定性 + :76 域)+ `isMonotone`(:89)+ Semantics :161 曲线单调 | 绿 |
| HP5 诚实降级 | rms null → recommendedStrength nil(GrainCalibration.parse :58 强联动)→ 面板 readout 隐藏(bwGrainReadout nil) | GrainCalibrationTests :54 双 nil 断言绿 |
| GrainModule 零 diff | — | `git diff af446612..HEAD -- *GrainModule.swift` 零命中 ✓ |

## §2 数据自建红线核

- **零复制(hash 级)**:FilmProfilesBW 全部 9 文件 sha256 vs `Resources/FilmProfiles/`(CC 包)与 `/Volumes/UNITEK/.../SpektraLab/engine/resources/` 全量 JSON/NOTICE 对照——**9/9 零命中**。
- **零复制(谱值级)**:上游 `camera_filters.hpp` 在本地 SpektraLab/AlcedoStudio 均不存在(RESEARCH 引用路径本地不可达)——退守 hash 全对照 + 谱值结构抽验;BW 四卷 log_sensitivity 结构与 CC 包(三通道异值)本质异型,复制不可能。
- **NOTICE 来源登记**:8 源(5 datasheet PDF + B-3 scan + W2 双 PDF 组 + Repacholi 文本锚)全部 URL/出版物号/sha256 在案;**PDF 零入仓**(repo 内无 .pdf,find 核验)。
- **CC 包冻结**:`git diff af446612..HEAD -- Resources/FilmProfiles/` 零命中 ✓。
- **证据分仓**:`evidence/t1/`(b3_transcription.md / wratten_crosscheck.json / sources / native_images 等)在库。
- **工具可重跑**:`Scripts/bwprofile/` 15 脚本 + uv.lock 在库(NOTICE 载 rebuild 命令序)。

## §3 bake 键负测组核(收口门)

FilterBakeKeyTests(IOPParity,4 法)逐法读验:

- **① 同 pair 不同 filter → 三槽全 miss**(:99-113,count +1×3 + tcLut/print 值不等)✓
- **② 同 pair 不同 grade → tc HIT + print/scan miss**(:115-130,tc count 不变 + print/scan +2)✓
- **③ absent 恒等**:bare consult + all-nil struct 同键(count 零增,:87-96)✓——**注**(obs-2):该测试用 BW pair,BW 相纸 absent 自钉 grade 2(DECISIONS §1.1),故 ③ 实测语义 =「nil ≡ struct 同路径」,文件头注释「the bare pairHash at all three slots」在 BW pair 上仅 tc 槽成立;COLOR pair 的键级 absent≡M8 由渲染 hash 哨兵(FilmDeterminism)承载,键级直接断言缺位。
- **④ fold 对齐 determinism**(:135-154,同 bytes 同 hash + 4 卷四键互异)✓;消费集三键 + midscale 预折在 `materialPairHash`(FilmMaterialStore.swift:189-245)逐键核验,两类理由注释分开 ✓
- **⑤ nil-tag consult never rebuilds**(:310-327,bakeCount 不变 + 同 bundle instance)✓
- **⑥ factor 锚 18% 灰**(:275-287,真渲染 Metal leg)✓
- **⑦ 方向断言**(:289-305,w25 压蓝/w47 压红,0.003 = 实测地板 + 余量,DECISIONS §6 申报)✓
- **⑧(滤镜因子交叉)**:发表值不在仓(PDF 不入仓政策)→ 独立复算形态落地 CameraFilterTests(:100-152,手写 Σ vs 产线 + f∈(0,1] + f8>f25 + w58 双源 note),T1 人工核对 6/7 ≤0.21 档注记在册——PLAN-DECLARED 替代形态 ✓

## §4 sidecar v12 豁免面 + 双键面

- diff 逐 hunk:LightamerSidecar.swift 全 diff = **12 行(schemaVersionCurrent 11→12 + bump 章程注释扩)**,零逻辑改动——符合红线「仅 schemaVersion 行 + additive 注释」。
- FilmRecord 双键三面同批(CodingKeys :115-117 / tolerant decode :136-137 / init 默认 :102-103;MIN-6 注释在码)。
- SidecarV12Tests(LIB,3 法):v11 文档 decode→encode **逐字节零漂移**(:54-75)/ v12 双键 verbatim 往返(:79-96)/ nil 键省略 + grade/filter 移动 recordHash(:100-117)✓。
- 封存面豁免申报链完整:文件自带 bump 章程(v12 注释)+ persisted-face 先例链(v8/v9/v10/v11)+ plan 显式例外申报(frontmatter red_lines)+ SUMMARY 登记 ✓。

## §5 全套独立复跑(第一路)

纪律:guard PASS(G1-G4)→ ps 验证 GUI/测试宿主清零 → `--monitor 21600 &`(nohup disown)→ `Scripts/test-direct.sh --all`(nohup disown)→ 全程 ~69 分钟。

| bundle | 本验收轮 | 申报值 | 峰值 RSS |
|---|---|---|---|
| IOP | 798/1/0 | 798/1/0 | 7298MB |
| IOPParity | 540/10/0 | 540/10/0 | 6709MB |
| Layers | 528/5/0 | 528/5/0 | 1185MB |
| Library | 785/4/0 | 785/4/0 | 743MB |
| Sessions | 285/4/0 | 285/4/0 | 1265MB |
| Export | 385/4/0 | 385/4/0 | 5130MB |
| App | 1042/6/0 | 1042/6/0 | 2832MB |
| **TOTAL** | **4363/34/0** | **4363/34/0** | 零 MEMFAIL / monitor 零 kill |

**逐位一致**;RSS 方差带内(IOP 7298 < 已知贴线 7865;门 8192)。skip 34 = 33 + 1 探针门控与申报口径同。日志正本 = `all-runs/acc1-all.log` + `acc1-monitor.log`。

## §6 中断拼装缝专项

三任中断的接缝对账:b807b1dd **40 文件** vs SUMMARY/DECISIONS §0/§8 记账——

- §0「保留 10」:FilmRecord/LightamerSidecar/LightamerShell/ExportQueue/ExportState/ExportInspectorView/PaperGradeTable/paper_grades.json/PaperGradeTableTests/SidecarV12Tests——**10/10 在 diff**。
- §0「续写 2」:FilmPanelModel/FilmPanelView/BWSpectralGoldenTests(含 T3 SHOOT 节 + T4 readout 三任务同文件交织)——diff 形态吻合。
- §0「返工 2」:FilmPrintBake(touchPchipSlices 删除 + 三槽全 HIT 才返回)/FilmTailPolicy(solveSpectral modeTag 折叠)——与 D-M92-5 终式逐位一致 ✓。
- §0「修正 3」:SpectralDualArmGoldenTests(C1 v12 digit / C2 nil-face emit)/assemble_profiles.py / MANIFEST.sha256——在 diff。
- §0「删除 1」:BWDbgTests——全仓 grep 零残留(其从未入 git,删除无需 diff 行)✓。
- §0「重做 1」:xcstrings 尾块纯插入(删除行 0)12 键 = 4 T2 + 6 T3 + 2 T4 逐键清点吻合 ✓。
- T4 面(GrainCalibration/grain_calibration.json/两测试文件)+ T3 面(CameraFilterTable/SpectralBuildEngine/FilmMaterialStore/FilterBakeKeyTests/CameraFilterTests)+ 递缝(PipeCoordinator :869 tags 解析)+ 测试翻新(FilmProfileTests fold 镜像/SpectralBakeTests clearEntries/SpectralBake setUp)+ 数据重锚(4 BW profile + assemble_profiles.py)+ 登记(Project.swift 纯数组插入 + BUNDLE-MAP 9 行)——**40 文件全归位,零孤儿面**。
- §8「第二任未申报缺陷两处」修复验证:FilmPanelBWTests setUp 补 `loadGradient()`(:67)在码;`availableGradeKeys` 按 gradeKeys 声明序(:154-158 注释「NOT a string sort」)在码。
- 第三任收口:九类新测试全绿(IOPParity 5/4/2+1skip · IOP 4/4/2 · LIB 3 · APP 5 · LAYERS 6——本轮全套计数吻合);BWDbgTests 调试脚手架零残留。

**拼装缝结论:零孤儿、零 WIP 未记面、两任未申报缺陷已由第三任修复且本轮全套实证。**

## §7 反自取消(两处)

工作树改造 → 重建 → 定向 FilterBakeKeyTests → 还原 → diff 干净核验:

- **A·去绿通道归一**(`factor = 1.0`):**真红**——`testFactorAnchorAndDirectionThroughTheSpectralLeg` 1 failure(:303,⑦ w47 下红块反亮 +0.0058;无归一时 solve AUTO gain 吸收整体亮度,方向翻转)。**观察**(obs-4):⑥(18% 灰 |Δ|<0.01)未红——AUTO solve 增益把整体亮度重新归一,factor 锚的渲染面真保护由 ⑦ 方向 + ① 键面承载;⑥ 对「归一缺失」不敏感属结构性(solve 面吸收),判别网仍闭合。
- **B·bake 键去 filter 折**(tcKey 不折 filter):**真红**——2 failures / 10 断言:① 三槽 count 不增(:105/107/109「1 ≠ 2」= filter 撞缓存)+ ⑦ delta 恒 0.0(渲染面直接复用未过滤槽)。
- 还原后 `git status` 干净;干净 HEAD 重建成功(全套轮即用该产物)。

## §8 红线机检族(复跑)

- 双 .metal(FilmSubRunKernels/SpectralFilmKernels)零 diff ✓
- 封存面:除 sidecar v12(申报例外)与 FilmTailPolicy(film 自有面,非封存 17 件)外零 diff;RenderProcess/GrainModule/LibraryProjectController/McpServerController 零 diff ✓
- CC 包冻结 ✓ / UserDefaults 零新键 ✓ / `String.LocalizationValue("…\(x)")` 禁形零实际命中(唯一 grep 命中 = LightamerShell.swift:1599 注释内的反例文档引用,非代码)✓
- tuist generate 各批末位 + BUNDLE-MAP 同 commit(ca263596 LAYERS 行 + b807b1dd 8 行 = 9 类全登记)✓
- zh-audit 复跑双 PASS(--check 1744/2060 + --self-test V17)✓

## §9 发现清单

**M(minor)**

- **M-1** `grain_calibration.json` HP5 行 note 残留 plan 骨架原句「T4 interpolates the family (M9-2 DECISIONS)」——与 DECISIONS §3 终裁(**不采纳**插值,null 诚实降级)文字矛盾。代码面行为正确(null → recommendedStrength nil,readout 隐藏,测试钉死),仅 note 文案误导后续读者。建议下批顺手改 note 措辞(不动 hash 断言值域外字段须同步 MANIFEST)。

**obs(观察项,不阻断)**

- **obs-1** 乘法缝 `filterT.count == axis.count` 不匹配时静默走恒等分支(SpectralBuildEngine.swift:465)——coordinator 层已 1:1 对齐,此为兜底;静默降级可加 debugAssert 提升可诊断性。
- **obs-2** FilterBakeKeyTests 文件头 ③ 注释「absent → bare pairHash at all three slots」在 BW pair 上不成立(absent 自钉 grade 2 → print/scan 键 = fold(pair,"grade:2"));COLOR pair 的键级 absent≡M8 直接断言缺位,由 FilmDeterminism 渲染 hash 哨兵间接承载。建议注释补 BW 自钉注记。
- **obs-3** BW absent 自钉 grade 2 使 solveSpectral modeTag 的 absent 档产生冗余缓存行(显式 "2" 档与 absent 档值同键异)——DECISIONS §1.1 已登记「无正确性面」,维持登记口径。
- **obs-4** 见 §7-A:⑥ 断言对归一缺失不敏感(AUTO solve 增益吸收)——factor 锚的判别力实际由 ⑦ 方向 + ① 键面承载;可在 DECISIONS 追记该判别网结构。
- **obs-5** 阶调门单调面降级(00=0.229/2=0.235/5=0.110,5 反窄于 2)与 ⑦ 阈值 0.05→0.003 均 DECISIONS §6 PLAN-DECLARED;v2 挂账(dial 表按渲染密度跨度反解)在册,验收不重复计违反。
- **obs-6** Δexecuted vs 任务书基线余 **+6 口径差**(4328→4357 的存量法增量,候选 = m9-1 收口 commit 注册面)——SUMMARY 已申报待 orchestrator 复核,本路复核同口径登记不冒领。

## §10 逐 AC 判定汇总

| AC | 判定 | 依据节 |
|---|---|---|
| M9BW-01 | ✓ | §1 表一 + §2 |
| M9BW-02 | ✓ | §1 表二 + §3 + §4 |
| M9BW-03 | ✓ | §1 表三 |
| 数据自建红线 | ✓ | §2 |
| bake 负测组(收口门) | ✓ | §3 + §7 |
| sidecar v12 豁免面 | ✓ | §4 |
| 全套带式 | ✓ 4363/34/0 逐位一致 | §5 |
| 拼装缝 | ✓ 零孤儿 | §6 |
| 反自取消 | ✓ 两处真红已还原 | §7 |

**验收判定:PASS(0 error + 1 minor + 6 obs)。M-1 为文案级,不阻断交付;v2 挂账(阶调单调面反解)沿 DECISIONS 既有登记。**

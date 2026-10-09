# M4-1-01-ACCEPTANCE-OMP — omp 独立二次验收记录（dual_acceptance 第二路）

> 验收对象 = M4-1-01（TIFF 开发分支底座批，11 commits `80c96c2..4346dbe`，基线
> `71f8f8d`；验收时 HEAD = `1220581`，含 zcode 验收 commit，本路零代码触碰）。
> 与 zcode 首验零共享上下文：亲跑 + 亲读 + 上游/Alcedo 正本对表，不轻信首验结论。
> 验收日期 = 2026-10-10 凌晨（亲跑三 bundle 全量 + 两 suite 定向过滤）。
> 首验文件 = `M4-1-01-ACCEPTANCE.md`（zcode 路 PASS / 0E+0M+3obs）；本文件为 omp 路独立报告。

## 结论

**omp 路：PASS / 0 error + 1 minor + 3 observation（minor 与 obs 全部登记，02 批顺路处置，不阻塞）。**

---

## §一 定向复跑（亲跑，不采信首验数字）

`caffeinate -dis Scripts/test-direct.sh --bundle <域>`，零 MEMFAIL，exit 0：

| bundle | omp 亲跑 | 首验亲跑 | 申报 | 判定 |
|---|---|---|---|---|
| IOPParity | **427/3/0**（453s，peak 6001MB） | 427/3/0（450s，6002MB） | 427/3/0 | ✅ 逐位命中 |
| Layers | **394/3/0**（147s，peak 1153MB） | 394/3/0（150s，1183MB） | 394/3/0 | ✅ 逐位命中 |
| IOP（加跑） | **544/1/0**（158s，peak 7729MB） | 544/1/0（142s，7280MB） | 544/1/0 | ✅ 计数命中；RSS 见 omp-obs-3 |
| IOPP 定向过滤 `RasterKernelParityTests` | **3/0/0**（26s） | — | — | ✅ |
| Export 定向过滤 `ExportDrtColorSpaceSrgbTests` | **5/0/0** | — | — | ✅ |

- 失败行三 bundle亲核 `failed (` 零命中；skip 数 3/3/1 与申报一致。
- 新 suite 运行期 Executed 亲核（`Test Suite passed` 行）：IOP 侧 28+20+13、
  `RasterDefaultRecordTests` 14、`DrtEotfTests` 15（基线 13，+2 在册）、
  `Aces2InverseTests` 8；IOPP 日志被过滤轮覆盖前已取 print 行（见 §三）。
- zh-audit `--check` 亲跑复现：**PASS 1585 source / 1823 catalog**（`drt_eotf_srgb_piecewise`
  在册，`Resources/Localizable.xcstrings:30608`）。

## §二 数学抽查（uv/Python 独立实现，不复用 Swift 代码）

1. **sRGB 分段（M3-1-01 LutTransferMath 同源）**：独立复算
   `decode(0.5)=0.21404114048223255`、`encode(0.5)=0.7353569830524495`，
   与 `RasterIccSemanticsTests` / `DrtEotfTests` / `Lut3dEncodingTests:237`
   三处钉死值**逐位一致**；roundtrip 残差 0 / 1.1e-16；膝点连续。
2. **PQ relative + HLG display**：PQ `pq_rel(0.25)=0.0005154176009833007`、
   `pq_rel(0.5)=0.009224570899406526` 逐位命中；HLG 初算用 10 位 ARIB 常数差
   6.2e-10，改用 Swift 侧截断常数 `hlgC=0.55991073`（`DrtEotf.swift:98`）后
   `hlg(0.75)=0.2031521453536661` **diff=0.0 逐位命中**——钉死值与产线常数口径一致，无误。
3. **32F fixture 位深保真**（tifffile 直读，不走被测代码）：
   `srgb-matrix-32f.tif` / `no-icc-float32.tif` / `linear-icc-float32.tif` 均为
   float32 64×64×3；`no-icc-float32` max=2.0（HDR 探针输入）；row0 探针
   0/1(2)/0.18(0.36)/0.5(1.0) 与 `testFloat32Fidelity` 断言一致。

## §三 上游/交叉正本对表 + print 行亲证

- **上游 CTL**（`raw.githubusercontent.com/ampas/aces-core/069b0bc3…` 亲拉，1702 行）：
  `tonemap_and_compress_inv` :544-560 逐字含注释「Applies the inverse tonescale,
  then uncompresses M」且调用序 = J_to_Y → tonescale_inv → Y_to_J →
  chroma_compress_inv；`outputTransform_inv` :1690-1700 stage 序；
  `gamut_compress_inv` :890-917 双 guard；M 归零 guard 实际行 :752-755
  （首验引 :742-747 为调用表达式区，同一 guard，无实质分歧）；
  `ref_luminance=100`（:61）；`chroma_compress_inv` 的 `bool invert` 形参在
  :492-532 体内**零消费**（vestigial，Swift 去参无损——首验结论复核成立）。
- **E3 落笔序**：Swift `tonemapAndCompressInv`（:115-121）与 kernel
  `riTonemapAndCompressInv`（:245-248）均与上游同序；文件头 stage 图 :46-54 同序。
- **Alcedo**（本地源码亲核）：`drt_node_model.hpp:46` `SrgbPiecewise = 7`；
  `editor_panel_projection.cpp:169` `"srgb_piecewise"`；D3（plan :1319）
  「float TIFF with a linear ICC curve or no ICC, are scene-linear」；
  canonicalization 1e-4（:253-254）；「A2B0 with no matrix-shaper tags」（:257-259）。
- **亲跑 print 行**（自家 IOPP 全量轮日志，非首验转述）：
  fwd-first worst `4.440892098500626e-15`；display-first total=10985 /
  artifactClass=1 / outOfClampDomain=57 / worstInDomain=`0.0038412827070091193`
  @rec2020@100（首验 3.8412827e-3 一致，门 4e-3 内）；
  RASTERPARITY 六行（worst 0.2639/0.0205/0.0134/0.0107/0.1075/8.66e-8、
  p999 6.50e-4/5.44e-4/4.41e-4/4.73e-4/4.85e-3、**近黑全 0**）与首验表逐位一致；
  定向过滤轮复跑逐位复现（确定性）。
- **SRGBICC**（自家 Export 过滤轮）：decode 方向 @256 采样 maxDev `7.605890171418395e-6`
 （首验「7.6e-6 幸存」成立）；TRC 三 tag form=`curv` count=1024（L053 守住）；
  raw entry @0.5 差 4.45e-4（半 knot 偏移，测试内注记准确）。

## §四 读码抽查（路由红线 / 四通 / E1 / derive）

1. **路由零翻转**：`testProductionDecodeRoutingStillCIPath` 体亲读
  （`rasterColor==nil ∧ rasterNative==nil ∧ ciImage!=nil`）；
   `git diff 71f8f8d..HEAD -- RAWDecoder.swift` = `contentDedupeID` 可见性一行，
   `decodeRaster` 体零触。红线机检亲跑：`Aces2Kernels.metal` / `LightamerIOP/` /
   `Sidecar/` / `Pipe/History/` / `Library/` **全零命中**；`Aces2Reference.swift`
   = 9 行纯头注（`git show d3a0268` 亲核，算法体零触）。
2. **srgbPiecewise 四通**：serde `"srgb_piecewise"`（:79）+ `kernelIndex` 7（:56）+
   MSL case 7 双向（:141-144/:167-170，常数体 :111-119 与 Swift 逐式同形）+
   `legalEOTFs` 两行（:454-455，顺序 = KD-9 fallback 链）+
   `isHdrEncoding` 显式 false 臂（:466）+ 导出六臂（rec709/p3d65 curv 表，
   其余四空间 typed illegal）+ App 两件（`eotfName` :271 新键；
   `drtLayerColorSpace` SDR 幂组 γ2.2 近似 :749-760；
   `hdrDrawable` 布尔链补位 :808-809 + 负测 `testSrgbPiecewiseRecordIsNotHdrDrawable`）。
   GPU 面：`testGPUAgainstFloat64AcrossAllSeven` 走 `allCases`（encode 全覆盖），
   亲跑日志 `ALARM-CHECK [srgb_piecewise encode] max=1.51e-7 p99.9=1.39e-7`
   （门 1e-5/5e-5 内大余量）。
3. **E1 半边**：`applyPriméRule`（:254-259，`isFloat ∧ transfer==.linear ∧
   displayReferred → sceneLinear`）落点 = named 快路径（:211）+ 字节解析（:218）
   **双覆盖**；fixture 测试断言 reason 逐字 + rec2020 primaries + 白点 2e-3。
   受害链引注复核：`BandStreamer.swift:24-28`（linear-Rec2020 TAGGED float32 落盘）
   + `StackMergeService.swift:815`（经 `RAWDecoder().decode` 回流）亲证在册。
4. **derive 联合规则**：scene-linear HDR 分支优先（:98-107）+ encoding 表（:115-133）
   + eotf 表（:137-179，linear 特例 :143-154 含 rec2020 回落）+ TRC legality 复核
   （:186-215）；14 法逐行 `assertJointRule` + `stableHash` 零漂移负测在册。
   逐 commit 边界 11 个亲核：全部落在 front-matter ∪ SUMMARY 申报外扩三件内，
   无第六件；commit message 与 plan 约定逐字同（全英文 Conventional）。
5. **证据目录核对**（替代 computer-use：本批纯底座批，无 GUI 走查面、无截图产物，
   计划内无此交付）：`evidence/m4-1-01/acceptance/testrun.log` 四行与首验 §一逐位一致
   （`build.log` 空文件）；`MANIFEST.txt` 21 tif 名 vs 在盘 comm 空差；
   生成器幂等重跑后 `git status Tests/Fixtures/TiffRaster/` 全净（亲证）。

## §五 minor + observation（omp 路新增，首验未登记）

- **omp-minor-1（plan-代码字面不一致，行为合理，缺 DECISIONS 登记）**：
  ② 号默认 plan/RESEARCH（:222）/代码注释（:20/:67/:226）/reason 字面（:234）/
  测试名（`…DefaultsToSceneLinearRec709`）五处写 **Rec.709**，实际落地
  `primariesXY = rec2020Primaries`（:229），且 T1 测试（:308）/fixture 测试
  （:183）/derive HDR 分支消费（`nearestLimitingSpace → rec2020 → (rec2020, st2084)`，
  DRT-HDR 视口臂激活依赖此）全部按 rec2020 走。机制面自洽（无 ICC 文件色域未知，
  limiting 取最大包络 rec2020 比 rec709 保守；改回 sRGB 会把 HDR 分支 limiting
  收窄到 rec709）。裁定：代码行为正确，错的是字面；02 批补 DECISIONS 登记并订正
  五处字面为 Rec.2020（或晨审裁定改行为——需同步改三处测试与 HDR 分支预期，默认不建议）。
- **omp-obs-1（台账瑕疵，无机检面）**：BUNDLE-MAP 本批登记数五处失准——
  `RasterColorDescriptionTests` 14 vs 实际 28、`RasterIccSemanticsTests` 18 vs 20、
  `RasterDecodeLegTests` 16 vs 13、`Aces2InverseTests` 6 vs 8、
  `RasterDefaultRecordTests` 15 vs 14（`grep func test` + 落地 commit 字节亲核；
  同文件既有行语义 = 文件终态 method 数，`RAW03Tests` 8=8 亲证）。
  登记数不参与任何机检（分账以运行期 Executed 为准），02 批顺路订正
  （另有 T9 漏同步 `DrtEotfTests` 12→15、`DrtViewportTests` 6→7）。
- **omp-obs-2（whitespace 级无关触碰）**：T9 commit（`7f7f000`）顺手剥除了
  `ExportDrtChainTests.swift` 行尾 `.swift` 后缀（基线 `71f8f8d:397` 带后缀；
  与本批零语义关系）。02 批顺路恢复后缀（或全文件统一无后缀风格二选一）。
- **omp-obs-3（资源方差观察）**：IOP 峰值 RSS 轮间方差 6%（首验 7280MB vs omp 亲跑
  7729MB），超出 SPIKE 注记 ±3%，距 8G 门仍有 463MB 余量，零 MEMFAIL。
  可能因子 = 本机当时残留进程/系统负载；记观察，02 全套轮若贴线再查。

## §六 与首验分歧点

1. **结论口径**：首验 PASS / 0E+0M+3obs；omp 独立复核 **PASS / 0E+1M+3obs**。
   唯一分歧 = omp-minor-1（首验 §四.1 亲读了 `applyPriméRule` 落点但未核对
   ② 臂 primaries 常量与 plan 字面的冲突）。不影响 PASS（行为正确 + 测试钉死 +
   路由未翻转 + 生产零影响）。
2. **首验三 obs 复核**：obs-1（`colorSpaceName:nil` 恒传，产线命名快路径不可达）
   同意（`RasterDecoder.swift:119/:135` 亲证）；obs-2（T7 提前带 T8 测试文件）同意，
   补充：T8 commit message 明写 "replaces the placeholder" 且 T7 登记了
   BUNDLE-MAP placeholder 行（"T8 placeholder — count updated in T8"），属有记录的
   相邻序，非暗渡；obs-3（3.9e-3 进位口径）同意，精确值 `0.0038412827070091193`
   omp 亲跑逐位复现。
3. **落盘形态**：首验 §十二预期「在本文件追加」omp 结论；实际按 orchestrator 任务指令
   落独立文件（本文件），首验文件零改动。无冲突。
4. **上游行号注记**：M 归零 guard 实际行 :752-755（首验引 :742-747 为调用表达式区，
   同一 guard）；`chroma_compress_inv` vestigial 形参结论复核成立。无实质分歧。

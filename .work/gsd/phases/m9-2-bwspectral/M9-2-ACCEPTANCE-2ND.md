# M9-2 ACCEPTANCE（第二路·盲评独立验收）

> 验收对象：`af446612`（T1 数据资产）+ `b807b1dd`（T2+T3+T4 合一，refs #12）+ `667bd85c`（收口账本）。
> 独立性：全程未读 `M9-2-ACCEPTANCE.md`（路 1）与 `all-runs/acc1-*`。
> 本路特色 = 数学正确性深审（Python 独立复算 repo 数据对拍代码/账面）+ 反自取消探针（独立切口）。
> 日期：2026-10-28。执行：第二路 zcode（本报告单 commit，免关联，不 push）。

## 结论

**PASS / 0 error + 1 major + 1 minor + 3 obs**

三 AC 独立核对全过、封存面 17 件机检全过（唯一申报豁免 sidecar v12 成立）、定向测试 9 类
24 executed + 1 skip 全绿（与账面逐值一致）、两发反自取消探针均真红（非自取消）、拼装缝
40 文件逐一对账归位。数学深审三面（滤色镜乘法缝 / 相纸 grade 拟合 / granularity 标定）
独立复算全部对拍成功；发现一处**资产注记失实（M）**与一处**登记曲线不自洽（m）**，
均不影响本批 AC 判定，修复建议挂 orchestrator 裁决。

---

## 1. AC 独立核对（M9BW-01/02/03，file:line）

### M9BW-01 黑白胶片族光谱 profile 自建 ✓

| 验收腿 | 独立证据 |
|---|---|
| profile 入谱面体系 | `LightamerCore/Sources/Film/FilmMaterialStore.swift:62-99` 多目录一索引（`profilesDirectories: [URL]`，CC+BW 联合，duplicate-id 跨联合 fail-closed）+ `App/Sources/Lightamer/UI/Shell/LightamerShell.swift` 双目录组装 + `bw` channel_model 经既有 `FilmProfile` tolerant face 消费（`Tests/LightamerTests/BWProfileAssetsTests.swift:105` 五卷 decode 断言） |
| MANIFEST 对账 | `BWProfileAssetsTests.swift:56` `testManifestReconcilesEveryAssetFile`（sha256 全量对账，全绿） |
| 中性/阶调 golden | `Tests/LightamerTests/BWSpectralGoldenTests.swift:188`（五色块 × 4 卷 × 3 grade 三通道散 ≤2e-3）+ `:251`（span > 0.05 + 三档 ladder 两两互异 + 18% 灰 0.55-1.10 带，PLAN-DECLARED 降级如实落码，见 §6 本文） |

### M9BW-02 变反差相纸 + 镜头滤色镜 ✓

| 验收腿 | 独立证据 |
|---|---|
| Multigrade 变反差相纸对 | `LightamerCore/Sources/Film/PaperGradeTable.swift:93-152`（ISO R 目标仿射校准拟合 + 二分）+ `paper_grades.json` 持久记录 + `PaperGradeTableTests.swift:111` round-trip 钉；消费缝 = `LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift:633-641`（grade preset 钉 `parameters.printCC`）+ BW 相纸 absent 自钉 "2" 档（`FilmPrintBake.swift:545-556`，DECISIONS §1.1 一致） |
| camera_filter 黄/红/绿 SHOOT 域 | `LightamerCore/Sources/Film/CameraFilterTable.swift`（81 点加载/typed 拒绝/双源 note）+ `App/Sources/Lightamer/State/PipeCoordinator.swift`（`:872-905` name→透射解析，未知名 degrade 无滤镜，engine 零文件 IO）+ 面板 SHOOT 节 9 档 |
| 滤色镜 ON/OFF 中性链零漂移负测 | `Tests/LightamerTests/FilterBakeKeyTests.swift:280-287`（⑥ 18% 灰 w25/w47 ON vs OFF \|Δluma\| < 0.01，真渲染）+ `CameraFilterTests.swift:100-166`（恒等透射 bit-equal + 独立复算对拍引擎） |
| 光谱透传 golden | `CameraFilterTests.swift` 方向门（⑦ w25 压蓝 / w47 压红，阈值 0.003 = DECISIONS §6 申报实测地板）+ `BWSpectralGoldenTests.swift:339` grade-seam 键断言（tc HIT bit 恒等 + print/scan miss） |

### M9BW-03 per-film granularity 标定 ✓

| 验收腿 | 独立证据 |
|---|---|
| per-film 标定表 | `LightamerIOP/Sources/Grain/GrainCalibration.swift`（表 + 纯映射 `:72-76` + 单调前提 `:89-101`）+ `grain_calibration.json`（Tri-X 17 / T-Max 8 / Acros 7 / HP5 null 诚实降级） |
| 强度语义断言 | `Tests/LightamerTests/GrainCalibrationSemanticsTests.swift:193-213`（推荐 strength 经产线 kernel 复测 RMS 落发表值 ±2.0 带，本轮实跑绿 0.745s） |
| 发表值对照（本文独立加验） | 四值从 evidence vendor PDF 逐页提取实证：Tri-X = F-4017 p6 "17 (fine)"（HC-110 Dil B）✓；**T-Max = F-4016 p8 IMAGE STRUCTURE 表 "8"（D-76）——第三方 7.4 修正有据** ✓；Acros = AF3-0258E p3 "DIFFUSE RMS GRANULARITY VALUE：7" ✓；HP5 = hp5.pdf 全文零 RMS/granularity 字样，null 成立 ✓ |

## 2. 封存面 17 件零 diff 机检（基线 `d4f71039` → `667bd85c`，本文独立机检）

机检式：`git diff` 逐文件；文件级零 diff 直接过，类型级封存面看 hunk 归属。

| 封存件 | 结果 |
|---|---|
| DrtRecord / DrtTailAssembly / DrtEotf / PixelPipe / Lut3dKernels.metal / DrtEotf…（15 文件级零 diff：DrtRecord·DrtTailAssembly·PixelPipe·Lut3dKernels.metal·DrtEotf·ExportQueueContract·ExportFormatSpec·ImageIOEncoders·WebPEncoder·NodeGraphCommand·HistoryStack·HistoryHash·PipelineDocument·V50Order·NodeOwnershipCatalog/Registry/ModuleInstance） | ✓ 零 diff |
| TerminalTailPolicy（宿主 `FilmTailPolicy.swift` 有 2 hunk） | ✓ 两 hunk 均在 `FilmRuntimeSolve`（solve 面 M9-2 合法改动）；`TerminalTailPolicy` 类型体零 diff |
| LightamerSidecar | ✓ **唯一申报豁免**（v12 单 bump，+24 行 = CodingKeys/digit/注释；plan 显式申报 + SUMMARY 登记） |
| ExportQueue.swift（+46） | ✓ 封存件是 `ExportQueueContract.swift`（零 diff）；ExportQueue 本体改动 = legTags TaskLocal 递缝（`nil = legacy` additive 默认参，`$jobFilmTail` 先例同形，M3-3 E1 三编辑点族） |
| 双 .metal（FilmSubRunKernels/SpectralFilmKernels）/ GrainModule / RenderProcess / LibraryProjectController / McpServerController | ✓ 零 diff |
| Resources/FilmProfiles CC 包 | ✓ 全程零触碰（diff 文件清单仅 FilmProfilesBW） |
| UserDefaults | ✓ 全 diff 零命中 |
| xcstrings | ✓ 恰 12 新键、单 hunk（:34261 尾部）、0 删除行 = 纯尾插（4 T2 + 6 T3 + 2 T4 与 DECISIONS 键族登记一致） |
| `String.LocalizationValue("…\(x)")` 禁形 | ✓ 全 diff 零命中 |

## 3. 数学正确性深审（本路主职责，Python 独立复算）

### 3.1 滤色镜 SpectralBuildEngine 乘法缝 ✓（一处资产注记失实 → §6 M-1）

乘法缝 = `LightamerCore/Sources/Film/SpectralBuildEngine.swift:476-490`：绿通道整卷归一
`factor = Σ sensW_G·t·refSPD / Σ sensW_G·refSPD`，三通道同乘 `t[λ]/factor`。

- **独立复算对拍**（Python 直读 repo 数据：`camera_filters.json` × Tri-X `log_sensitivity` ×
  SpectralConstantsData D55，绿通道 index 1）：f8 = **0.459276**、f25 = **0.126232** ——
  与 DECISIONS §6 登记值（0.459 / 0.126）逐位一致；八滤镜全表见下。
- **18% 灰锚语义**：代数恒等 `Σ S_G·(t/factor)·SPD = Σ S_G·SPD` 数值验证 rel.dev = **0.0**
  （w25/w58/w8 三镜皆 0）；恒等透射 t≡c → factor ≡ c、max|scale−1| ≤ 1.1e-16（float 位级，
  与 CameraFilterTests「identity → bit-equal」互证）。BW 卷通道相等 ⇒ factor 跨通道唯一
  （ΔR = ΔB = 0.0，注记声称成立，实证）。
- **深浅单调**：w8 0.4593 > w12 0.4121 > w15 0.3585 > w21 0.2698 > w25 0.1262；w47 0.1623 >
  w58 0.1091 ✓；因子域 (0,1] ✓；谱质心漂移方向物理正确（无镜 502nm → w8 563nm → w25 615nm）。
- **发表 factor 对照（本文加验，超出 executor 自证面）**：从 evidence vendor PDF
  `f4017_trix.pdf` p1 提取 Daylight Filter Factor 表（No.8=2× / No.11=4× / No.12=2.5× /
  No.15=2.5× / No.25=8× / No.47=6× / No.58=6×），与生产语义复算逐档（stops 差）：
  **8: Δ0.12 ✓ · 11: Δ0.89 ✗ · 12: Δ0.04 ✓ · 15: Δ0.16 ✓ · 25: Δ0.01 ✓ · 47: Δ0.04 ✓ ·
  58: Δ0.61 ≈ 申报 0.67 ✓** → 独立复算 = **5/7 ≤0.21 stop**，与 shipped
  `factor_check_note`（"6/7 within 0.21"）不符：**w11 是未申报的第二个离群档**
  （发表 4× vs 曲线积分 2.16×）。w11 为 B-3 单源 vintage 曲线（深红台地 90.6% 平直段
  可疑，见 §6 M-1）。判定语义面：生产缝是 TTL「过镜测灰」锚（发表 factor 不进语义），
  灰块输出正确性不受影响；失实的是资产注记本身。

### 3.2 相纸 grade 拟合残差 ✓

按 `PaperGradeTable.swift` 模型逐行 Python 重实现（dichroic 表 + TH-KG3 + 活跃通道选择 +
混合特征线 + ISO 桥式反演 + 48 轮二分），对 `ilford_multigrade_iv_rc.json` 独立 refit：

| key | shipped dial | 本文 refit | \|Δdial\| | 校准目标 R | R@shipped | 残差 | ISO 等效@shipped | ISO 目标 |
|---|---|---|---|---|---|---|---|---|
| 00 | 200.000000 | 200.000000 | 7.8e-12 | 173.9816 | 173.9816 | 0.0e+00 | 180.000 | 180 |
| 0 | 68.085014 | 68.085131 | 1.2e-04 | 171.1465 | 171.1464 | -8.6e-06 | 160.000 | 160 |
| 1 | 21.461208 | 21.461214 | 5.9e-06 | 166.8937 | 166.8937 | -7.5e-07 | 130.000 | 130 |
| 2 | 0（neutral） | — | — | — | 164.0586 | — | 110 | 110 |
| 3 | 33.504931 | 33.504938 | 7.2e-06 | 158.5945 | 158.5945 | +1.3e-06 | 90.000 | 90 |
| 4 | 89.829382 | 89.829432 | 5.0e-05 | 150.3985 | 150.3985 | +5.8e-06 | 60.000 | 60 |
| 5 | 200.000000 | 200.000000 | 7.1e-13 | 144.9344 | 144.9344 | +2.3e-13 | 40.000 | 40 |

- dial 逐档复现（max Δ 1.2e-04，二分精度界内）；拟合残差 max **8.6e-06**（R = log10×100
  刻度，即 8.6e-8 log10 曝光——数值噪声级）；ISO 等效 @shipped 与 datasheet 目标
  （180/160/130/110/90/60/40）**逐档精确命中**。
- **单调性**：黄拨 0→200 严格升（164.06→173.98）、品拨 0→200 严格降（164.06→144.93），
  双族扫描零逆序。
- 已申报限制复核：模型 ISO-R 带宽窄（scaleY 0.142 / scaleM 0.273）、00/5 端点钉二分上界
  200 = DECISIONS §6「端点饱和」与「阶调门降级 + v2 挂账」申报一致；非隐性问题。

### 3.3 granularity 标定 ✓（一处登记曲线不自洽 → §6 m-1）

- **单调性**：shipped 表 (7,10.713) < (8,12.205) < (17,25.638) 严格递增，
  `GrainCalibration.isMonotone` 前提成立（独立数值核）。
- **发表值**：四卷全数从 publisher PDF 独立提取证实（见 §1 M9BW-03 行）；**T-Max 8 vs
  第三方 7.4 的修正经 F-4016 p8 IMAGE STRUCTURE 表实证为正确取向**（publisher 原文 8，
  D-76，48µm，net diffuse 1.00）。
- **推荐值反解不自洽（m-1）**：JSON note/DECISIONS §3 登记探针曲线
  `boxRMS ≈ 0.662×strength + 0.62`，以其反解得 24.74 / 11.15 / 9.64，**非** shipped
  25.638 / 12.205 / 10.713；shipped 三值自身严格共线、反解出实测曲线 ≈
  `boxRMS = 0.670×strength − 0.18`（1000× 刻度，斜率近、截距反号——注记系数无法复现
  shipped 值）。探针 stdout（M92-GRAIN-PROBE 行）未存档 evidence，登记曲线不可复核。
  兜底语义：runtime 语义门（±2.0 带）独立复测推荐值成立（本轮绿），差异 0.9 strength
  单位 ≈ 0.6 RMS 单位在带内——**无用户可见错误，属登记面失真**。

## 4. 定向测试（本文实跑；guard + build-for-testing 先行，干净 DerivedData 全量重建）

`Scripts/machine-guard.sh` PASS（G4 首轮 BLOCK 24.3G<25G，按 DECISIONS §9 同类配方清
本项目 DerivedData + Lightamer/swiftpm 缓存后过门；zen/playwright 他工具缓存未动）；
`machine-guard.sh --monitor 21600` 伴跑；GUI 实例 ps 验证清零后起跑。

| bundle | 类 | 结果 |
|---|---|---|
| IOPParity | FilterBakeKeyTests | 4/0/0（284s） |
| IOPParity | BWSpectralGoldenTests | 5/0/0（302s） |
| IOPParity | GrainCalibrationSemanticsTests | 2/1/0（语义门 0.745s；1 skip = PERF_PROBE 探针门，既知形态） |
| Library | SidecarV12Tests | 3/0/0 |
| IOP | PaperGradeTableTests | 4/0/0 |
| IOP | CameraFilterTests | 4/0/0（263s，含多次谱 build） |
| IOP | GrainCalibrationTests | 2/0/0 |

合计 24 executed / 1 skip / 0 fail —— 与第三任定向快核（IOPParity 5/4/2+1skip、IOP 4/4/2、
Library 3）逐值一致；BUNDLE-MAP 法数（6/4/4/2/3/5/4/2/5）经 `grep -c "func test"` 实测
逐一复核一致（第三任的 5→4 / 3→4 修正属实）。全套 4363/34/0 复跑归路 1，本文未重复。

## 5. 反自取消探针（本文独立切口，两发，已全部还原复绿）

### 探针 1：paperGrade verbatim 整数化（"00"→"0"）

变异点 = `PaperGradeTable.gradeKeys` 首档 `"00"` → `"0"`（verbatim 七档梯破坏）。三腿真红：

1. IOP `PaperGradeTableTests` → **crash**（`PaperGradeTableTests.swift:71` `table["00"]!`
   nil 解包，host exit=133，L055 置零判据生效）；
2. IOPParity `BWSpectralGoldenTests` → `:315` FAIL（grades 00/2 rendered ladders
   **0/41 steps differ**——grade seam 整体惰性化）；
3. App `FilmPanelBWTests` → `:124`+`:126` FAIL（picker 首档 "0" ≠ "00"，00/0 两个不同档的
   verbatim 断言红）。

结论：gradeTag 消费面（面板/渲染缝/拟合）对 verbatim 梯的守护**非自取消**。（v12 字节面
`SidecarV12Tests` 不红——其钉 wire format 与梯无关，属面内分工，非漏防。）

### 探针 2：多目录 duplicate-id guard 掏空

变异点 = `FilmMaterialStore.init` `guard index[stock] == nil else { throw
duplicateStockId }` → 静默覆写。结果：Layers `FilmProfileTests.testDuplicateAndMissingStockIdsAreTypedRejected`
→ `:770` FAIL（`XCTAssertThrowsError failed: did not throw an error`）——fail-closed
guard 有真红靶，**非自取消**（负测经单目录便捷 init 走同一条多目录循环，联合 guard 代码路径被覆盖）。

### 还原

两变异还原后 `git status` 干净；重建复跑 `PaperGradeTableTests` 4/0/0 +
`FilmProfileTests` 21/0/0（含 duplicate 负测）确认基线恢复。

## 6. Findings（B/M/m/obs 逐条）

**B（blocking）：无。**

- **M-1｜w11 发表 factor 偏差未申报（资产注记失实）**：`camera_filters.json` w58 条目的
  `factor_check_note` 称 "6/7 filters within 0.21 stop"；本文以生产语义（film-sens × D55，
  绿通道）对 F-4017 p1 发表表独立复算得 **5/7**（w11 Δ0.89 stop：发表 4× vs 曲线 2.16×），
  w11 深红台地 90.6% 平直段（B-3 单源）疑数据/注记双失真。生产正确性不受影响（TTL 锚
  语义不消费发表 factor；18% 灰锚数值恒等），但 shipped 资产注记与可复核事实不符。
  **建议**：修正 note（如实登记 5/7 + w11 离群）并复核 w11 曲线源（W2 退役、B-3 单源是
  唯一在册源——或降级注记为「发表 factor 未验证」）。

- **m-1｜granularity 探针曲线登记不自洽**：note 曲线 `0.662×s + 0.62` 反解 ≠ shipped
  推荐值（隐含实测 ≈ `0.670×s − 0.18`）；probe stdout 未存档。runtime ±2.0 语义门为
  operative guard 且独立复测绿。**建议**：存档一次 M92-GRAIN-PROBE 输出或修正 note 系数。

- **obs-1**：T5 收口节 ΔN 分解「新文件 27 法」与 ΔN 表（29 法，含 GrainCalibrationSemantics
  2 法）小账不平；executed +35 / skip +1 主账不受扰。
- **obs-2**：`SpectralBuildEngine` 乘法缝对 `cameraFilter.count != axis.count` 静默走恒等
  分支（`:476-477`）——生产路径不可达（coordinator 层 `alignedTransmission` 恒同轴），
  typed gate 在装配点（DECISIONS §2 设计如此）；引擎缝自身无 typed 拒绝，留档备查。
- **obs-3**：DECISIONS §6 span 台账「00=0.229 / 2=0.235」与 HEAD 实测漂移：本文
  M92-TONALITY 输出 00=0.22863 / **2=0.22863（与 00 恒等）** / 5=0.11044、midD 0.850/0.850/1.009
  （带内 ✓）——00/2 span 恒等是「端点饱和」申报的实测形态（门内合法：span>0.05 + ladder
  两两互异均绿）；§6 的 2=0.235 值疑为返工前状态，v2 refit 挂账 inputs 以 HEAD 实测为准。

## 7. 拼装缝独立核（40 文件对账）

`b807b1dd` 恰 40 文件，逐一对账 SUMMARY/DECISIONS 记账面**零未记面、零记而无物**：
保留 10（FilmRecord/LightamerSidecar/LightamerShell/ExportQueue/ExportState/
ExportInspectorView/PaperGradeTable.swift/paper_grades.json/PaperGradeTableTests/
SidecarV12Tests）+ 续写 2（FilmPanelModel/View、BWSpectralGoldenTests）+ 返工 2
（FilmPrintBake 三槽键终式 `tcKey=fold(pair,filter?) / psKey=fold(tcKey,grade?)` +
全三槽 HIT 门 = `:527-600` 与 D-M92-5 逐字一致；FilmTailPolicy solve modeTag + X-M92-2
gradeEv gain 消费层）+ 修正 3（SpectralDualArm C1 v12/C2 nil-face emit、
assemble_profiles.py、MANIFEST.sha256）+ 删除 1（BWDbgTests 仅存于在制品，未入 commit，
Project.swift 行随之）+ 重做 1（xcstrings 12 键尾插）+ T3 新（CameraFilterTable/
CameraFilterTests/FilterBakeKeyTests）+ T4 新（GrainCalibration + 两测试文件）+
PipeCoordinator 装配点 + FilmMaterialStore 双目录 + T1 资产五卷/NOTICE/filters/grain/
Scripts 工具链/BWProfileAssetsTests/Project.swift + BUNDLE-MAP。三任中断拼装的两处
收口修复（FilmPanelBWTests setUp gradient load、availableGradeKeys 声明序 filter）在位
（`FilmPanelModel.swift:134-147` 注记与代码一致）。T5 收口批 `75e7e1d5` =
FilmPanelSpectralUITests 冻结清单 +3 id（`:75e7e1d5` diff 归属核实）。

## 8. 环境事件（透明登记）

- G4 首轮 BLOCK（Data 卷 24.3G < 25G）→ 清本项目 DerivedData（2.2G，顺带获得干净重建）+
  Lightamer/swiftpm 缓存 → 27.0G PASS；zen/playwright 他工具缓存按 DECISIONS §7 纪律未动。
- 会话继承死代理 env（10809 无 daemon）致首轮 build-for-testing 的 SPM 拉取失败
  （AGENTS §6 死代理形态）→ `px --up` 一条龙起代理后重建成功；任务收尾 `px --stop`。
- guard 全程 PASS；monitor 看门狗伴跑定向轮全程，零触发；测试宿主峰值 RSS ≤ 275MB。

## 9. 本报告产物

- 报告：`.work/gsd/phases/m9-2-bwspectral/M9-2-ACCEPTANCE-2ND.md`（本文件，单 commit 免关联）。
- 工作区收尾态：探针两变异已还原，`git status` 无残留（未跟踪的本报告文件除外）。

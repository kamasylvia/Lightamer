# M3-1-ACCEPTANCE-PI — W1 前置批回溯二次验收（PI 路独立，零共享上下文）

> 验收员：PI 路回溯二次验收员（omp+pi 双路并发批，授权在案）。日期：2026-10-10。
> HEAD：`f2969d24`（main）。方法一句话：正本三 ACCEPTANCE 亲读 + 上一轮 OMP 报告抽查点提炼、≥4 项独立机检重验（file:line 读码 / git show·diff 机检 / grep·wc 计数 / zh-audit self-test 亲跑），逐项独立取证不照抄。

## 结论头

**PASS / 0 error + 0 minor**（+ 2 observation，均「后演进，不记账」类，见分歧项节）

- M3-1-01（LUT 编码维）/ 02（yiyin sheet 拖拽）/ 03（小件族 + zh 清算）三 plan 抽查面全部独立复核成立。
- 测试未复跑（默认不跑纪律）：build/Debug 测试产物 mtime = 09-16（陈旧，不反映 HEAD），复跑需全量重建超 8 分钟预算且非必要——ACCEPTANCE 已记录终值（02 定向 14/0/0、App 全量 649/0/0；03 全套 `--all` 3024/16/0 双轮互证）采信，另以 grep 计数 vs BUNDLE-MAP vs 专测在场三方机检替代复核。

## 逐抽查点证据（对上一轮 OMP 报告抽查清单的独立重验，8 项 ≥ 4 达标）

### 1. LUT 编码维：目录 17 行（SC-1）

- `LightamerIOP/Sources/Lut3d/LutEncodingCatalog.swift:32-50`：`LutEncodingId` 亲数 17 case——scene 11（acescc/acescct/arriLogC4AWG4/arriLogC3AWG3/sonySLog3/canonCLog3/fujiFLog/panasonicVLog/nikonNLog/appleLog/linearRec2020）+ display 6（rec709BT1886/rec709SRGB/rec709Gamma22/displayP3SRGB/rec2100PQ1000/rec2100HLG1000）✓。
- `Tests/LightamerTests/Lut3dEncodingTests.swift:25-40` `testCatalogRowCounts` 显式断言 17/11/6 + 10 camera log + linear 唯一行 ✓。
- `LutTransferMath.swift:123-127`：`logC4A=(pow(2,18)−16)/117.45` 等 ARRI A0042 **派生式**非硬抄字面 ✓（独立读码，与 OMP 同判）。方向探针三测在场 `Lut3dEncodingTests.swift:545/:566/:589`（与 OMP 所引行号逐位同值，零漂移）✓。

### 2. LUT 专测族在场性 + 计数三方对表（SC-1/SC-5 数字门）

- `grep -c "func test"` 亲跑：Lut3dEncodingTests **24** / Lut3dGoldenImageTests **7** / LutLibraryStoreTests **16** / LutEncodingPanelTests **5** / YiyinSheetSizingTests **14** / ExportCollisionPickerTests **5** / NLMeansDragDowngradeTests **6**。
- BUNDLE-MAP（`M2-4-0-BUNDLE-MAP.txt`）对应行亲读：`:100 IOPP 24` / `:104 IOPP 7` / `:206 APP 5` / `:343 LIB 16` / `:534 APP 14` / `:540 APP 5` / `:541 APP 6`——**七行逐位一致** ✓。对账式 2962+37+14+11=3024 算术精确 ✓。
- hash 零漂移/烘焙三态/verbatim 三专测在场：`testParamsEncodingZeroDrift:435`、`testBakeCountThreeStatesAndLRU:637`、`testNonUnitDomainDefaultPairStaysVerbatim:713` ✓。

### 3. 补标 40/40 adoption 盖章（SC-2）

- `LutLibraryStore.swift:182-183`：`builtInRememberedPair = RememberedEncodings(input: .arriLogC4AWG4, output: .rec709BT1886)`——`{arri_logc4_awg4, rec709_bt1886}` 盖章对单源在案 ✓；`:327` adoption 路径盖章 + `:298-302` 注释（re-adoption 重建整行重盖）。
- `LutLibraryStoreTests.swift:214` `testBuiltInAdoptionStampsRememberedPair`（BuiltIn 行盖章 + 非 BuiltIn 行 nil 断言）在场 ✓。

### 4. yiyin sheet 拖拽：钳制数学 + 两键（SC-3）

- `App/Sources/Lightamer/Yiyin/YiyinSheetSizing.swift:55-70`：`clampWidth/Height` = `lo=max(pxMin, container×ratioMin)`、`hi=min(pxMax, container×ratioMax)`、`min(max(px,lo),hi)` 双域交亲读 ✓；`:94-96` `quantize3 = (ratio*1000).rounded()/1000` ✓；`defaultWidth=420/defaultHeight=560` 首用锚（:42-44）✓。
- `App/Sources/Lightamer/State/YiyinSheetMetrics.swift:15-16`：`yiyin.sheet.widthRatio/heightRatio` 两键注入式 defaults，body 零直读（头注 :6-10 明示）✓。

### 5. denoise 拖动降档旁路三道防线（SC-5）

- `App/Sources/Lightamer/State/EditorState.swift:239` `previewDenoiseBypass: [UUID: Bool]`（实例身份键控，注释明示 layer-embedded 不连带）；`:249-263` arm 记先验 enabled / disarm verbatim 复原；`:217` `recordChange` 内 `removeValue(forKey: snapshot.id)` **commit 自愈**；`:267-270` `clearPreviewDenoiseBypass` 调用点亲核 = `:153 resetHistoryForNewImage` + `:449 rebuildInstances` **双清扫**；`:429-432` upsert 强制压 `enabled=false` ✓。三防线 + upsert 四面独立读码成立，旁路字段无任何 params/history/liveEdited 写入路径 ✓。
- Manual-Only 双腿：`LightamerIOP/Sources/Registry.swift:48` `NLMeansModule.opName` ∈ `defaultFaceDisabledOpNames`（:39-49 集合亲读）✓；`EditorTabRoute.swift` `grep -c -i nlmeans` = **0**（tab shell 零席位）✓。

### 6. 冲突档选择器透传链（SC-4）

- `ExportInspectorView.swift:230` Picker 三 tag 绑 `ExportNamer.ExportCollisionPolicy` ✓；`:630` `collisionPolicy = .increment` 会话态默认 ✓；`:846 makeRunAssembly` 纯缝 → `:832/:875` 入 `RunAssembly` → `:295` 消费 → `ExportState.swift:492` 既有形参（默认 .increment）→ `:541` `queue.enqueue(collisionPolicy:)`——**逐跳闭合** ✓。
- 行号漂移注记：OMP 引 `ExportState :472/:514`，现 = `:492/:541`——M3-3 起追加 `filmTails` additive 形参所致，**后演进，不记账**。

### 7. peak-ICC 单源（SC-5 附带）

- `LightamerCore/Sources/Graph/DrtRecord.swift:463` `public func isHdrEncoding` Core 自由函数单源在场 ✓（OMP 引 :456，M4-1 `srgbPiecewise` 等后演进插入致 +7 行，不记账）。

### 8. git 机检（SHA 谱系 + 三个对象 commit + 红线）

- **SHA 现状**：OMP 报告所引全部 SHA（`502494d/73c8764/7a800a5/0241a1c` 及首验 01 六 SHA）当前树**均不可解析**（`git cat-file -t` fatal 亲证）。归因亲证：`.work/gsd/research/sha-rewrite-map-2026-10-10-pathstrip-commit-map.txt`（1270 行 old→new 映射表）亲读——`73c8764…→a3903461`（:566）、`502494d…→0d0ea07b`（:411）、`7a800a5…→78432f8d`（:596）、`0241a1c…→f3ecc8e5`（:11）。即 2026-10-10 pathstrip history 手术发生于 OMP 报告（10-09）**之后**——后演进，不记账；实质经新 SHA 全部独立复核成立。
- 复核①（换锚后逐位重验 OMP §五两抽检）：`git show --numstat 0d0ea07b` = `118 0 LutPanelView.swift`（面板纯增量零删除逐位 ✓）；`git show --name-only a3903461` = BUNDLE-MAP + YiyinSheetMetrics + YiyinSheetSizing + Project.swift + YiyinSheetSizingTests（5 文件，与 OMP 报 02-T1 集合一致 ✓）；`git show --name-only 78432f8d` = BUNDLE-MAP + ExportInspectorView + Project.swift + xcstrings + ExportCollisionPickerTests（5 文件一致 ✓）。
- 复核②红线：`git diff --name-only 78432f8d~1..d907a304`（= OMP 引 7a800a5~1..d4ae750 的现谱系等价区间，d907a304 = 03 验收收口 commit）对红线 13 名 grep = **零命中**（exit 1 亲证）✓。

### 9. zh 提取器硬化 + 键族（SC-4/V15 面）

- `python3 Scripts/zh-audit.py --self-test` 亲跑 = **SELF-TEST PASS（exit 0）** ✓；V15 行对状态机 `PENDING_LOCALIZED_RE/LEAD_LITERAL_RE` 在档 `Scripts/zh-audit.py:120-121`（消费 :214/:233）✓。
- 键族抽查：`export_collision_{label,increment,fail,replace}` / `export_drt_peak_note` / `panel_nlmeans_preview_downgrade` / `project_face_import_folder` / `search_{exif,clip}_placeholder` 九键 `grep -c` Localizable.xcstrings 各 = 1 全在册 ✓；AGENTS.md `:348`「M3-1 架构增量」节在位，与代码实况逐条相符（本验收读码印证）。

## 分歧项（与上一轮 M3-1-ACCEPTANCE-OMP.md 的判定差异）

**实质分歧：无**——其五个 SC 抽查点 + 数字门 + git 两抽检 + zh 面，本路独立取证全部成立，无一误判。两 observation 级差异（均后演进，不记账）：

- **obs-P1（OMP §五/obs-1 的时效性注记）**：OMP 报告称「02/03 的九个首验 SHA 在树内全部有效」在其时点（10-09）为真，但 2026-10-10 pathstrip history 手术后其本报告所引全部 SHA（含其亲手验证过的 `502494d/73c8764/7a800a5`）已不可解析——其 obs-1 只预言了 01 六 SHA 失效，未预见后续手术；映射正本（pathstrip-commit-map）在案可查，实质已由本路经新 SHA 逐位重验，故仅记时效性观察，不动摇其当时判定。
- **obs-P2（行号漂移清单，供后续验收防误读）**：`ExportState.swift :472/:514→:492/:541`（M3-3 filmTails）、`DrtRecord.swift :456→:463`（M4-1 srgbPiecewise 等）、BUNDLE-MAP `:101→:104`（后续 phase 增行）——引用需换锚，语义面零分歧。

## 会话卫生

- 只读验收遵守：零源码/文档修改（唯一写入 = 本报告文件）；未创建/改动 OMP 路任何文件（含 M3-1-ACCEPTANCE-OMP-R2.md）；未跑 `--all`；未启动 GUI 实例；未触 defaults/临时项目；zh-audit self-test 为秒级只读脚本。测试产物陈旧（09-16）如实申报并以机检替代，未伪造任何「亲跑」终值。

PI-VERDICT: PASS

# M5-3-03 ACCEPTANCE — 全景 UI 与收口批（wave 3）独立验收记录

> **双重验收制度**（config `dual_acceptance = true`）：本文件 = 两路结论正本。
> **第一路 = zcode 独立验收（本文件 §一..§十，2026-10-13 晨）：PASS / 0 error + 1 minor（验收批当场更正，本 commit 同批）+ 3 观察（零动作）**。
> 第二路 = omp 二次验收（orchestrator **串行**派遣，严禁并发；结论落 §十一）。

---

## 一、亲跑对表（全套 `--all` 独立复跑，exit 0，TOTAL 逐位闭合）

| bundle | 本轮（亲跑） | 申报 | 对表 | peak RSS | MEMFAIL |
|---|---|---|---|---|---|
| IOP | **684/1/0**（455s） | 684/1/0 | ✓ 逐位 | 7084MB | 0 |
| IOPParity | **456/3/0**（770s） | 456/3/0 | ✓ 逐位 | 6982MB | 0 |
| Layers | **466/4/0**（166s） | 466/4/0 | ✓ 逐位 | 1177MB | 0 |
| Library | **636/4/0**（78s） | 636/4/0 | ✓ 逐位 | 617MB | 0 |
| Sessions | **279/4/0**（70s） | 279/4/0 | ✓ 逐位 | 1626MB | 0 |
| Export | **353/4/0**（199s） | 353/4/0 | ✓ 逐位 | 6161MB | 0 |
| App | **757/4/0**（366s） | 757/4/0 | ✓ 逐位 | 2832MB | 0 |
| **TOTAL** | **3631/24/0**（2104s） | 3631/24/0 | **✓ 精确** | — | — |

- 亲跑命令：`caffeinate -dis Scripts/test-direct.sh --all`（直启宿主，尾行 `OK (direct launch, no testmanagerd)` 亲见）；七 bundle 和 = 684+456+466+636+279+353+757 = **3631** ✓、skip 和 1+3+4+4+4+4+4 = **24** ✓（手加复核）。
- **构建新鲜度亲证**：产品二进制 mtime 06:42:32-35（T2 `2d57bc37` 代码态 build，06:50 commit 前）；`git diff 2d57bc37..HEAD -- '*.swift' '*.metal' Project.swift Resources/` = 空（其后三 commit 纯 docs/.work）——产品即 HEAD 代码态，零重建必要。
- **对账链闭合亲证**：3539（M5-2 基线）+ 43（01）+ 44（02 实测净增）+ 5（本批 App 752→757）= **3631** ✓。
- **skip 24 身份逐个亲验**（七 bundle log skipped 行逐条读，零静默跳过）：21 = M5-1 时代在册（SkinRegion Vision 环境 / GoldenColor ARW×2 fixture / LutRecursion 手动探针 / AIMask×2 模型资产 / ColorMatchBake 时间门 / GradeEnvelope 探针 / LibBench×2 + LibGrid 观察行 / CatalogBench×3 / Perf07 record-only / QuickLook 探针 / Depth×4〔3 资产缺席 + 1 延迟探针〕）+ 1 = `MertensFusionPerfProbeTests`（LIGHTAMER_PERF_PROBE 门）+ **2 = `PanoFusionPerfProbeTests`（testPanoFusion200MPBudgetProbe + testPanoFusionFootprintDiagnostic，同 env 门亲读）**。注：VALIDATION 所记子分类「12 env + 6 资产 + 3 fixture」与我方复点 13/5/3 有 ±1 归类差（总额 21 不变，观察 o-3）。
- **PanoMergeUITests 5 法亲跑**：App log 五 `Test Case ... passed` 行逐条亲读（seam nil 门 / 参数映射+defaultTag / 三前缀正反+透传 / 消费面替换+不漏英文 / sibling mertens 共存）——**5/5 passed**。

## 二、UI 审计（本波灵魂，读码亲证）

- **菜单第三项**：`SessionBrowserView.swift` merge 组三项并存（hdr_merge → hdr_mertens → **pano**），`browser_menu_pano` 静态键；gate = `targets.count >= 2, onPano != nil`（多选 + nil 隐藏，onHDRMertens 同形）；**Divider 链逻辑同构**（pano 项仅在前两项全 nil 时补分隔线——与 mertens 项「前项 nil 才补」的链式语义一致）；取消按钮复用既有 `alert_cancel`（zh=取消 亲验）。
- **简形 sheet（OQ-7 零控件）**：`.sheet(isPresented: $showPanoDialog)` 四件 = title/body/取消/开始，**零档位控件**；正文单键 `pano_dialog_body` 承载四生效值（同视点 / 重叠约 30% 以上 / 画布上限 2 亿像素超限自动等比缩小 / 恒自动裁去无效边缘）——OQ-4/5/7 文案落点亲读在键值。L057 runModal 族构造性豁免（SwiftUI .sheet 非 NSOpenPanel）。
- **seam 链四段**：①`SessionBrowserView.onPano` optional seam（nil = 隐藏）②`ContentView` 装配点第四段 `onPano: { relPaths in Task { await sessionCoordinator.panoMergeHandler?(relPaths) } }`（mertens 段同位 :464——checker minor-1 处方兑现 + plan front-matter 补登记亲见 diff）③`SessionCoordinator.panoMergeHandler`（mertensMergeHandler :131 孪生同形）④`LightamerApp` 接线 `enqueue(kind: .pano, sources:, params: MergeParams(deGhost: false, tag: nil), sessionRoot:)` + `toast_pano_queued`——**deGhost false 显式形**（pano 腿不消费，注释言明）+ **tag nil → `defaultTag(.pano)` = "pano"`_pano` 分账**（`StackMergeService.defaultTag`亲读第七臂）。
- **既有项零回退**：T1 全仓 diff 223+/0-；SessionBrowserView 49+/0-（菜单前两项与 focus/stack 字节不动亲证）。

## 三、typed 三态 zh 映射审计（KD-3，读码 + 测试亲跑）

- **单源契约**：Core `PanoMatch.FailurePrefix`（public，三常量带 ": " 尾）——App 侧 `PanoFailureCopy.failureKey(for:)` 纯函数前缀表直接消费该常量，**零第二词汇源**。
- **V14 纪律亲证**：`failureMessage(for:)` 消费面 = **显式 switch 返回静态键**（三臂 + default 透传），零 `String.LocalizationValue(运行时串)` 查表形态；failureHook 挂载 = `mergeService.setFailureHook` 既有 toast 通道（`toast_hdr_merge_failed` 包装保留，插值参数由原文换映射值——T2 唯一删除行即此正当改线）。
- **样板头剥离机理亲证**：canonical 前缀自带 ": " 尾 → detail 从 prefix `upperBound` 起取 → 前缀前的一切（含 AppError `Invalid setting: ` 头）自然剥除；空 detail = 裸文案——`testPanoFailureMessagePassthroughAndSubstitution` 三臂（透传恒等 / detail 保留且英文短语不漏 / 裸形态）+ 本轮亲跑绿。
- **非前缀透传不变式**：`failureKey` nil → `failureMessage` 原样返回——既有错误面零变化，负测十案例（含空串）亲跑绿。

## 四、zh 键族审计（KD-4）

- **8 键尾块纯插入亲证**：T1 diff = 136 insertions / **0 deletions**；插入位 = `toast_hdr_mertens_queued` 之后（尾块）；八键（browser_menu_pano / pano_dialog_title / pano_dialog_body / pano_dialog_start / toast_pano_queued / pano_error_alignment / pano_error_disconnected / pano_error_canvas）en+zh 双语全 translated，**零裸键**。
- **zh-audit --check 亲跑**：`PASS (1651 source keys, 1890 catalog keys, zh complete)`——与申报逐字同；三 error 键 T1 边界 ORPHAN → T2 消费点闭合（MISSING 全程 0）亲证。

## 五、G4 审计（KD-5：OpenCV 结构对照 evidence）

- **evidence 三件读核**：`opencv_structural_probe.py`（探针正本）+ `probe-output.txt`（原始输出）+ `report.md`（七段对表报告；**非门值声明卷首显式**——无数值断言、不进 CI）。
- **活体复跑亲证**：本验收以同脚本独立复跑（`uv run --with opencv-python-headless`，opencv 5.0.0）——输出与 `probe-output.txt` **逐位一致**（Stitcher 门值 1.0/0.6/0.1/−1；组件 getter ABSENT 五行；conf **2.9624** / inliers **213** / BA focals **2553.6053945992862 / 2553.5033822363143** / features 269/272 / wave 2 rotations）——「Lumen 腿 OpenCV 段活体实跑」申报属实且可复现。
- **七段对表判定核**：段序一一对应（特征→匹配/边门→估计→BA→波→投影/帽→增益→融合/裁切）；段 2/3/4/5 门值族同源（Lowe 0.3 / conf>.6 ∧ inliers≥10 / HORIZ / 200MP）；段 6/7 两处结构分叉（逐通道 GainCompensator vs scalar min-norm；multiband+GraphCut vs 512 tile 几何羽化带+恒 inner_crop 直方图栈）= **CONTEXT 裁决记录在案的有意 Lumen 形采纳**（OQ 全 A 回批 2026-10-16 亲读）——零意外缺口判定成立。
- **源码树零 opencv 亲跑**：`grep -rni "opencv|cv2"` 于 LightamerCore/ LightamerIOP/ App/ Tests/ = **26 命中全为头注归属/语义注记**（含 `docV2` 变量名大小写误命中），零代码零依赖零 `.metal`。
- **政策 B 合规**：`git check-ignore` 亲证 evidence/ 与 gui-acceptance/ 双路径 gitignored（.gitignore:79/80）+ `git log --all` 零跟踪历史——仓外运行、产物只落 evidence、主仓零 opencv 痕迹三申报全成立。

## 六、G5 红线机检审计（KD-6：十一项逐项亲跑复核）

| # | 项 | 亲跑结果 | 判定 |
|---|---|---|---|
| 1 | 红线路径零 diff（LightamerIOP/ + LightamerCore/ + `*.metal`，base 60aad61） | 0 行 | ✓ |
| 2 | 腿体/FloatTIFFWriter/ProvenanceReplay 字节零 | StackMergeService/BandStreamer/ProvenanceReplay 各 0 行 | ✓ |
| 3 | dependencies 块零 diff | Project.swift 唯一 diff = PanoMergeUITests 登记单行 | ✓ |
| 4 | hardened 禁系统随机源（含 `\.random(`） | pano face + StackMergeService/BandStreamer grep 0 命中 | ✓ |
| 5 | runModal 门（App/Sources） | 0 命中 | ✓ |
| 6 | LocalizationValue 插值前缀禁形 | 插值形态唯一命中 = :1921 文档注释（禁形示范本体）；另见观察 o-1 | ✓ |
| 7 | sidecar schemaVersion 零触 | Sidecar/ ⊂ §1 全域 0 行 | ✓ |
| 8 | xcstrings 纯插入 | 136/0 亲数 | ✓ |
| 9 | SessionBrowserView 既有项 0 deletions | T1 diff 0 删除行 | ✓ |
| 10 | zh-audit --check PASS | 1651/1890 亲跑复现 | ✓ |
| 11 | 六 kind 零回归证人 | IOP 684/1/0 亲跑（含 PanoMergeKindTests 7 法全绿——`testStepTotalPanoThreeNPlusSixAndExistingSnapshots` 六 kind 快照钉 + `testPanoKindRawValueAndCaseCount` 七 case 计数）+ 全套拼表第四面 | ✓ |

**十一项全绿亲证**（transcript `g5-redline-checks.txt` 与我方复跑逐项一致）。

## 七、G6 审计（KD-7：走查 MANIFEST）

- `.work/gui-acceptance/m5-3/MANIFEST.md` 五行配方逐行读核：①三重叠样张合一（菜单三项并存 + sheet 四值 + 产物落格）②crop 观感（无效边缘裁净）③`_pano` 分账落盘名 + provenance details ④typed 失败 toast（无重叠 → disconnected zh 文案、**canonical 英文短语不漏出**断言——与本验收 §三机理一致）⑤产物重导入编辑链（M4-1 sRGB readout）。
- **fixture 来源注记在卷首**（同视点扫幅样张，RAW bracket 不适用；无实拍时合成 TIFF 序列替代——Lumen diagnostics 先例引用）；**Manual-Only 依据引用在卷首**（M3-4 先例措辞）。
- **VALIDATION「走查证据待回填」形态正确**：G6 行 ⏳ + 签核前置如实登记——执行移交 orchestrator/用户，配方完备可执行。

## 八、逐 commit 边界审计（四提交对照 front-matter）

| commit | 内容 | 边界判定 |
|---|---|---|
| `fe3fc5f` T1 | SessionBrowserView/SessionCoordinator/ContentView/LightamerApp/xcstrings + plan front-matter 补登记（6 文件 223+/0-） | ✓ 全在 front-matter 清单内；ContentView = minor-1 处方原形；Conventional 全英文 subject+body |
| `2d57bc37` T2 | LightamerApp 映射面 + PanoMergeUITests + Project.swift 单行 + BUNDLE-MAP APP 增行（4 文件 337+/1-） | ✓ 唯一删除 = toast 消费点正当改线；BUNDLE-MAP +7 = 注释块+数据行；tuist generate 恒末位（pbxproj 06:41 < 二进制 06:42 < commit 06:50 亲证时间链） |
| （T3 零 commit） | G4 evidence 三件 = 政策 B 磁盘产物 | ✓ check-ignore 亲证（§五）；申报如实 |
| `6699da3e` T4 | 仅 `g5-redline-checks.txt`（48+） | ✓ transcript = phase 根 tracked 账本（perf.md 同位先例）；MANIFEST 磁盘产物不入仓 = 政策 B 一致 |
| `570768f9` T5 | SUMMARY/DECISIONS/VALIDATION/AGENTS M5-3 节/GOAL-STATE/TODO + all-run log（7 文件 353+） | ✓ 收口面完备；VALIDATION drafted = C 档第 3 门正确形态；ACCEPTANCE 未创建 = 验收波产物申报属实 |

- **CHECKER 五 minor 采纳分账核验**：①minor-1 ContentView → T1 兑现 ✓；②minor-2 预览灰度双缝 → 01/02 已落（01-SUMMARY 在案）✓；③「+32」→ **CHECKER/plan 全文零命中亲证**（grep 复跑）→ 转写残迹判定成立，对账链以实测 bundle 和为锚 ✓；④尺寸表 6 行非 8 → 01-SUMMARY :20 亲见 ✓；⑤02 test_bundles 口径 → BUNDLE-MAP「M5-3-02 增行记录」块亲见 ✓。五项分账准确。

## 九、minor 与观察（本验收发现）

- **m-1（minor，验收批当场更正）**：`M5-3-VALIDATION.md` SC 行法数锚「88 法 + MergeUI 5 = 93 法」与 grep 实数不符——十文件集（9 + MergeKind）现盘实数 = **85** 法（Gain 13 / Leg 12 实数即 02-ACCEPTANCE m-a 已勘的 BUNDLE-MAP 错记口径；88/93 为其陈旧算术）。更正为「85 法 + MergeUI 5 = 90 法」并注记来源（本 commit 同批）。**非门值**——bundle 计数（684 等）与 TOTAL 3631 为真账，已逐位亲证。
- **o-1（观察，零动作）**：`ExportInspectorView.swift:392` `String.LocalizationValue("export_format_" + kind.rawValue)` 运行时拼接键形态——**M2-9-05 既有修复形**（`0c928a15`），本批零触碰（base..HEAD 该文件 0 行 diff），不在本批 V15 禁形（插值前缀字面量）范围；登记供 V15 词汇全景视图参考。
- **o-2（观察，零动作）**：`PanoMergeUITests.testSiblingMertensSeamCoexistsBesidePano` 的 mertens 桩 bump = 4N+2（先例 MertensMergeUITests = 3N+2 恰 duty）——超步 N 步无害（progress 仅显示面，`.done` 由腿返回与服务流决定，本轮亲跑绿）；纯 cosmetic。
- **o-3（观察，零动作）**：skip 24 子分类「12 env + 6 资产 + 3 fixture」与我方复点 13/5/3 有 ±1 归类差（总额 21 + 1 Mertens + 2 Pano = 24 恒等式亲验成立；归类边界属描述性粒度）。

## 十、结论（第一路 = zcode 独立验收）

**PASS / 0 error + 1 minor（已当场更正）+ 3 观察**。

- 全套 `--all` 独立复跑 **TOTAL 3631/24/0 exit 0** 逐位闭合、零 MEMFAIL（峰值 7084/6982/6161MB 全 8G 门内）、零 crash；skip 24 身份逐个亲验零静默。
- UI/typed 映射/zh 键族/G4/G5/G6/commit 边界七面审计全绿（§二..§八）；四提交边界干净、政策 B 合规、checker 五项采纳分账准确。
- M5-3-03 申报与实物**零实质偏差**；发现的 1 minor 为收口文档锚数字精度（已更正），3 观察均零动作。

## 十一、第二路 = omp 二次验收（待 orchestrator 串行派遣）

- （待填——**严禁与 zcode 路并发**；可选含 omp 实机 G6 五行走查取证回填，M5-2 G6 行 2/5 先例。）
- 结论：＿＿＿（PASS / FAIL + 证据指针；FAIL 回注修复批后重走验收。）

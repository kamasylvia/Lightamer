---
phase: M6-3
slug: ultrahdr
status: validated
nyquist_compliant: true
created: 2026-10-14
validated: 2026-10-14
---

# Phase M6-3 — Validation（ALCE-03 UltraHDR gain map JPEG 导出：CI `.hdrImage` 全服务路 + validate 六门 + DRT 尾 EOTF-box 前线性级 capture）

> 体例对齐 `phases/m6-2-process-version/M6-2-VALIDATION.md`（正本链上溯
> `phases/m2-11-performance/M2-11-VALIDATION.md`）。**双重验收（config
> `dual_acceptance = true`）落终态后成文**：第一路 zcode 独立 subagent 验收
> PASS / 0 error + 1 minor + 3 观察项（minor = 账面滑差，3 处修复清单交闭环
> 批）→ omp 制度路**配额阻塞**由**第二支零共享上下文 zcode 独立验收眼替代**
>（与 M6-2 先例同款登记，晨审可裁）→ 第二眼 PASS / 0 error + 1 minor（同源
> 补全——第一路清单 3 处扩为 **7 位点逐行清单**）+ 4 观察项，正本 =
> `M6-3-01-ACCEPTANCE-2ND.md`。两路各自自建 build-for-testing 并独立全套
> `--all` 亲跑同值——零实质分歧，dual_acceptance 意图满足。
> **翻账只认证据**：SC 生效值对账正本 = 两路 ACCEPTANCE + SUMMARY + DECISIONS
> 四份亲跑/亲读记录 + CONTEXT 裁决（OQ-M6-3-1..6 全 A 夜间授权批 + 增补
> D-M6-3-7）；charter 验收形态三件（ROADMAP M6-3 行）= spike 结论落档 ✓
>（`RESEARCH.md` 三臂实测——ImageIO 两键死路证毕，**CI `.hdrImage` 全服务路
> 原生容器字节达标**，charter「原生路容器字节达标即收」兑现）+ 导出链集成 ✓
>（集成点按 research 结论演进 = `encodeStage` gain-map 臂 + 新文件
> `ExportGainMapEncoder`；`ImageIOEncoders` JPEG 腿 additive 原案随两键死路
> 退役——**六格式矩阵零改动红线维持**，`ExportFormatSpec` 类型面零 diff）+
> DRT-HDR/EDR 源图端到端 ✓（DRT 尾 EOTF-box 前线性级 capture → ISO 21496-1
> 容器 → M4-1 raster 链重导入降级正确；st2084/hlg 编码 base 由增补裁决
> D-M6-3-7 typed 拒 = E4 物理约束「gain 比率必须对线性光取」的 base 侧投影，
> 演进注记见特殊事项 §2）。
> **SC 数字对账基线 = 全套 `--all` 终验 `TOTAL|3759/24/0|` 两路独立亲跑同值**
>（第一路 2106s / 第二路 2130s，均 exit 0 零 MEMFAIL 零 crash；对账链
> **3725 + 34 = 3759** 精确闭合：ExportGainMapTests 25 法（EXPORT）+
> ExportGainMapPanelTests 9 法（APP），即 Export **353+25=378** / App
> **801+9=810**；skip 段和 1+3+4+4+4+4+4 = 24 = TOTAL 24 机械一致）。执行方
> 申报 3756 为账面滑差（minor-1，+22/31 → 实测 25/34）——3759 ∈ plan 预期带
> 3753..3759 顶沿，测试与代码缺口为零，两眼接力 7 位点闭环批原位改数清偿。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（**ExportGainMapTests 25 法** Core 面：validate 六门负测〔jpeg/drtOutput/peak 202-203 边界+NaN/HDR-encoding st2084+hlg 双臂/yiyin+无旗标负控〕+ capture 两态 + queue box 泄漏双路终态箱空 + 容器四法〔MPF payload 形字节扫 / ISO 21496 URN / 尾图 / tmp 零残渣〕+ aux 双法〔'L008' fourcc + BytesPerRow==width + 尺寸==基面〕+ rewrap 双断言 + 后处理三门 + fail-loud 落盘零残 + 基面保真 ±1 LSB S1 漂移伞 + gain 语义 band〔E4 反证形〕+ reimport raster 链；**ExportGainMapPanelTests 9 法** App 面：五维门拆 5 + 复位 + 装配/兜底 + enqueue + 默认关） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/crash 签名/no-total-line 机检全挂靠，L055 双保险） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3759 tests / 24 skip / 0 fail**（两路独立亲跑：第一路 **2106s**〔自建 build-for-testing〕/ 第二路 **2130s**〔自跑构建〕，exit 0；七 bundle 逐行：IOP **686/1/0**〔peakRSS 7716/6827MB〕/ IOPParity **460/3/0**〔7251/6525MB〕/ Layers **474/4/0** / Library **671/4/0** / Sessions **280/4/0** / Export **378/4/0**〔5717/5997MB〕/ App **810/4/0**〔2832MB〕；峰值全 <8G 运行门，零 MEMFAIL 零 crash，L055 双保险两路亲证） |
| **基线演变** | 3725（M6-2 终值）→ worker 批 +34（ExportGainMapTests 25 + ExportGainMapPanelTests 9）= **3759 精确**；两路各自 build+run 同值互证；执行方申报 3756 = 账面滑差（minor-1，闭环批清偿） |
| **SC 数字面** | 定向对表精确：Export **353→378**（+25）/ App **801→810**（+9）；IOP/IOPParity/Layers/Library/Sessions 五段逐值零漂移；BUNDLE-MAP 两新行中 APP 行 9 正确、EXPORT 行 minor-1（22→25，行注记「T4 +3 后共 25」本已自证 25——闭环批修 7 位点） |
| **在案发现（本 phase 事件）** | **minor-1（第一路发现，第二眼补全，闭环批清偿）**：申报链「+22 新法 → 合计 31 → 全套预期 3756」为同源记账滑差——实测 `grep -c "func test"` = 25 + 9 = 34、全套 3759；**测试与代码缺口为零**（两路独立亲跑同值，3759 ∈ plan 带 3753..3759 顶沿）；第一路 3 处清单 + 第二眼 7 位点逐行清单（BUNDLE-MAP :723 + SUMMARY :23/:28/:29/:32/:64 + DECISIONS :73 双值），本批原位改数清偿；**观察项分账**：挂账表五项（§挂账总汇编）+ 登记级三则（§特殊事项 §6） |
| **GUI 证据** | M2 页 checkbox 面由 **ExportGainMapPanelTests 9 法机检承载**（五维门 + UI↔validate 子集对表两路亲核 + 复位三入口闭）；跨生态目检（Preview/Photos/Chrome/Android/LightCraft 互读）= **Manual-Only**，配方 = `.work/gui-acceptance/m6-3/MANIFEST.md`（可选行，不可达不阻断收口） |
| **zh 对账** | 5 新键尾块纯插入（85 插入 0 删除，历史键零触碰）；zh-audit `--check` **PASS 1666/1905**（第二眼亲跑）；UserDefaults 零新增 |

---

## SC 生效值对照（`M6-3-CONTEXT.md` 裁决记录 2026-10-13 夜间授权批全 A + 评审增补 D-M6-3-7 → 落点终态）

| # | 生效值（OQ 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **HDR 面取平面点 = DRT 尾 EOTF-box 前线性级**（OQ-1①，禁独立 EDR 链）：单一 record 单源，两臂同链只差终级；spike E4 反证——PQ/HLG 编码码值直喂 gain 语义非物理，必须喂线性光 | T1 `53a74582` | **Delivered**：`PixelPipe.linearGainCapture` 窄缝 9 hunk（PixelPipe 7 + LayerCompositeDriver 2，两路逐 hunk 亲核超清单触点零）；capture 单点 = processRec uncached 臂 EotfBox 位（:1595，export 恒冷缓存走 uncached 臂；cached 臂不可达申报属实）；`EotfBox` 全仓唯一构造点 = 尾段 assembly `:1791`（主链/editor 视口零触发面）；wrapper 判定 `box is ModuleBox<EotfBox>` 精确无假阳（TailOrderedBox 直 conform `ModuleBoxing` 非 ModuleBox 子类 + post-only filter + eotf 裸加入链——偏差①，机械必要）；capture 面 = EOTF-box 输入平面（entry plane，sizing 在 entry 施加——48×32 亲证）+ 尾平面 working float32 语义链（`tailFormatFloatOverride` 同位）+ E4 线性光喂入三层证（capture 点结构排除 + 门⑤ + gain 语义 band：SDR 线性解码值 ×2^k → GainMapMax≈2±0.5，3.2167 事故自证 CI 先解码基面） |
| 2 | **EXIF = metadata 路 probe 先行 → 失败降级 v1 无 EXIF**（OQ-2①→②，禁自建 APP1 注入器——段级注入移动文件内绝对偏移与 MPF 副图偏移互斥） | T2 `caa4113b` | **Delivered（降级落位）**：probe **两路独立复现**（各自 /tmp 即弃 swiftc 探针亲写亲跑）——`CGImageMetadataSetValueWithPath` 对 `{TIFF}/Software` 返 **false**；第一路追枪加强：`exif:Software`（XMP 命名空间）虽可 SetValue 但 rewrap 后仅落非标准 XMP 属性——APP1 `Exif\0\0` 段缺席、`{Exif}`/`{TIFF}` 读回双 ABSENT——「v1 无 EXIF」裁决成立且加强；**存活座位 = `xmp:CreatorTool`**（序列化落盘亲证 + doc comment 固化）；失败臂容器/aux/XMP 全存活双测（`testGainMapArmSkipsTheICCStrip` + rewrap 双断言）；六格式矩阵唯一 additive 档偏离登记（OQ-2 预授权）；EXIF 注入器 → 挂账 #1 |
| 3 | **`hdrgm` 兼容档位 = primary XMP 补 `hdrgm:Version` 接受**（OQ-3①；老 Android/Chrome 副图内嵌 hdrgm XMP 非硬需求）→ **LightCraft 移植臂（C 路）降兜底封存** | T2 `caa4113b` | **Delivered**：`hdrgm:Version` 字节扫 + rewrap 后 aux 读回 PRESENT + MPF 存活（F5 门双断言法）；`.none` 档无 XMP 但容器仍 UltraHDR；**C 路零代码零 NOTICE**（`git diff | grep -icE "lightcraft\|NOTICE"` = 0 两路亲跑）——激活条件 = 老生态裁硬需求时（挂账随 D-M6-3-3 封存注记）；rewrap 用 `CGImageDestinationCopyImageSource`（首实现 AddImageFromSource 重编码主图丢 MPF——偏差②，探针实测 1268B vs 15723B，修正归位） |
| 4 | **gain map 通道 = 单通道亮度 'L008'**（OQ-4；`hdrGainMapAsRGB` 不开——RGB 档读回侧 Data 键被 reader 扣留） | T2 `caa4113b` | **Delivered**：aux 读回 PixelFormat fourcc == "L008"（bigEndian 解码比对）+ BytesPerRow == width + data.count == W×H 三断言 + 尺寸==基面；`hdrGainMapAsRGB` 全仓零代码命中（唯一 grep 命中 = 测试 doc comment 陈述其未启用，语义即「不开」）；aux 描述字典纯字符串键（SDK 无对应 CFString 常量——探针定案，偏差⑥） |
| 5 | **M2 页 UI 位 = SDR 导出节 checkbox**（OQ-5①；可用门 = drtOutput≠nil ∧ .jpeg ∧ peak≥203〔headroom=peak/203≥1〕；不可用态文案）+ 联动复位（C-2：页内 setter + run-face 复核兜底） | T3 `e1ef7396` | **Delivered**：五维门 9 法全绿（jpeg/peak 202-203 边界/HDR-encoding/embedICC-off/noRecord + 复位 + 装配/enqueue/默认关）；**UI↔validate 子集对表两路亲核无残口**（format↔① / noRecord↔②〔enqueue 强制联动 `drtOutput = drtRecord` 下等价〕/ peak↔③〔`sdrReferenceWhite` 203 单源 + NaN 比较语义等价〕/ embedICC↔④ / encoding↔⑤〔`isHdrEncoding` Core 单源〕/ 门⑥ yiyin = validate-only〔makeVariant 恒不设 yiyin 结构性不可达〕）；复位三入口闭 = embedICC setter + format setter（页内）+ run-face 复核（`makeRunAssembly` 复位先于 `makeVariant`，`gainMapAutoReset` 携带 blocked 维度 + V14 静态键 toast）；默认 record peak=100 → checkbox 默认灰 + 诚实文案（§5 UX 注记） |
| 6 | **不加新 tag**（OQ-6①；容器本就是超集 JPEG，同池冲突递增语义正确） | T3/T4 | **Delivered**：formatName 恒 "jpeg"（`ExportFormatSpec` 类型面零 diff；本批 diff grep `outputTag\|formatName` 仅命中门①错误文案引用）；Namer 既有测试原样绿（Export 378 全绿含之） |
| 7 | **validate 第五门：`gainMapHDR ∧ encodingEotf ∈ {st2084, hlg}` typed 拒**（增补裁决 D-M6-3-7——UltraHDR 语义要求 base = SDR rendition；PQ/HLG 编码 base 是 E4 禁止形态的 base 侧投影；planner 权限外收窄由 orchestrator 裁准）+ **第六门 `gainMapHDR ∧ yiyin`**（同批随录——borders/watermark 在 EotfBox 后回放致 capture 面与出口位图尺寸分叉） | T1 `53a74582` | **Delivered**：validate 门⑤ st2084+hlg 双臂负测 + UI `.encoding` 维同步 + 负测各一（validate/panel）；`isHdrEncoding` Core 单源（DrtRecord.swift:463）双消费（validate / UI :799）；门⑥ yiyin + 无旗标负控；双锁尺寸分叉防护 = validate 门⑥ + **encoder 内第二道硬守卫**（`encode` 尺寸 guard typed 拒——defense-in-depth，直接 Request 绕过 validate 仍 fail-loud，第二眼独立点名的第二防线） |
| — | **AC7 零回归门** | T4 `c077784a` + 两路机检 | **Delivered**：九文件文件级零 diff（ImageIOEncoders/WebPEncoder/ExportEncoder/ExportQueueContract/ExportChainBuilder/XMPWriter/XMPContainerInjector/ExportNamer/ExportQuantizer）+ ExportState 零 diff + ExportFormatSpec 面零 diff + ExportICCStrip 本体零 diff（`ExportEncoder.swift` 文件级）+ `.metal` 全仓零 diff + dependencies 块零 diff（零新 SPM）；`Project.swift` diff = 恰两行测试登记；xcstrings 85 插入 0 删除纯插入 + 5 新键全入册；runModal / LocalizationValue 插值禁形 / UserDefaults / `hdrGainMapAsRGB` grep 零命中；`PixelPipe`+`LayerCompositeDriver` diff 恰 = 9 hunk（7+2）；**非 gain-map 负测**（无 MPF + strip 照跑 + XMP 照缺零 diff）+ 既有套件原样绿（七段基线逐值零漂移） |
| — | **AC8 SC 数字门** | 两路终验批 | **Delivered**：Export +25 / App +9 定向逐值精确（34 ∈ plan `estimated_tests "+28..34"` 顶沿）；全套 **3759/24/0** = 3725+34 精确闭合，两路独立 build+run 同值（2106s/2130s），exit 0 零 MEMFAIL 零 crash；skip 段和 1+3+4+4+4+4+4 = 24 = TOTAL 24 机械一致；L055 双保险两路亲证 |

## 双重验收记录（dual_acceptance 链，第二眼正本 = ACCEPTANCE-2ND）

| 路 | 结论 | 证据要点 | 分歧与处置 |
|---|---|---|---|
| **第一路 zcode 独立验收**（2026-10-14，真独立 subagent 零共享上下文） | **PASS / 0 error + 1 minor + 3 观察项** | 全套 `--all` 自建亲跑 **3759/24/0**（2106s）exit 0 + AC1..8 逐条 fresh evidence + 9-hunk 逐 hunk 亲核 + DECISIONS 10 项偏差全 ACCEPT（零应 REJECT）+ EXIF probe 独立复现并追枪（exif:Software XMP 座位不可读回）+ 红线机检族亲跑全绿 | **minor-1**：申报账面 +22/31/3756 滑差（实测 25/34/3759）——3 处修复清单交验收后闭环批；观察项 = headroom 载体分叉残余（obs1→挂账 #4）/ primaryXMP 静默 nil 臂（obs2→登记级）/ GOAL-STATE 日期混用（obs3→登记级，前序遗留） |
| **第二路（实际执行）：zcode 第二独立眼**（零共享上下文；doc 题注 2026-10-15，落盘 2026-10-14） | **PASS / 0 error + 1 minor（同源补全）+ 4 观察项** | 自跑 build-for-testing + 全套 `--all` **3759/24/0**（2130s）与第一路逐值一致（互为复核）+ 六面独立审计自选切入（容器面 25 法亲数与三法非永真逐法亲读 / 渲染缝面 9-hunk 亲核 + 尺寸色彩行序三一致性论证 / 编码腿面 L009 三事实 + 同队 CIContext + 203 单源三消费点 / UI 面五维⊆六门逐维对表 + 单值贯穿亲证 / EXIF 降级面 probe 独立写 / 偏差面 10 项独立复核全 ACCEPT）+ **独立发现零新 error** | **minor-1 补全（非翻案）**：第一路清单 3 处只覆盖 7 个同源位点中的 3 个——`grep` 全量扫描扩为 **7 位点逐行清单**（BUNDLE-MAP :723 / SUMMARY :23/:28/:29/:32/:64 / DECISIONS :73 双值），闭环批逐行原位改数清偿；观察项 = HDR/base 行序方向性断言缺失（obs1→挂账 #2）/ gain map 臂不带 DPI（obs2→挂账 #3 登记）/ moveItem 晋升语义 vs plain 路原子写（obs3→登记级，保守失败方向可取）/ 继承第一路三 obs（均复核成立维持观察级） |
| **omp 制度路（原第二制度位）** | **配额阻塞登记（非 FAIL），未执行** | 制度位由第二支零共享上下文 zcode 独立眼替代（与 M6-2 先例同款——omp 串行配额硬顶家族）；登记晨审可裁 | 不重试（lane_retry 语义）；如需可后补 omp 复核路，默认不需要——双 zcode 独立眼意图已满足 |

两路终态：**零未清偿 error、零 open minor**（minor-1 同源滑差两眼接力 7 位点
闭环批原位改数清偿）；两路独立全套复跑同值互证（3759/24/0 逐值一致）——
零实质分歧，dual_acceptance 意图（≥2 路零共享上下文独立验收 PASS）满足。

## Per-Plan Map（M6-3-01 单 plan 全量批）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M6-3-01 | T1 `ExportVariant` additive `gainMapHDR` + validate 六门（非 jpeg / drtOutput 缺席 / peak<203 / embedICC=false / HDR-encoding EOTF / yiyin 全 typed 拒）+ `PixelPipe.linearGainCapture` 窄缝（KD-2 9 hunk）+ `ExportRenderer` capture 装配（owned-copy blit 同队 FIFO）+ `ExportQueue.ExportGainMapPlaneBox` 交接（stash/consume+clear/finish/finishCancelled/retry 幂等——ExportQueueContract 零 diff 的 queue 级载体）；T2 `ExportGainMapEncoder.encode`（CI `writeJPEGRepresentation(.hdrImage)` 全服务写 + 同目录 tmp 晋升 L009 + CopyImageSource XMP rewrap + 203 单源三消费点）+ `encodeStage` gain-map 臂（registry 旁路 + M4 fail-loud guard + strip/XMP 双旁路——MPF 绝对偏移雷结构性消解）+ queue encodeLeg consume；T3 M2 页 checkbox（五维可用门 + 三态不可用文案 + embedICC 复用 hint）+ 联动复位 + `makeVariant` S4 落点 + 5 键 xcstrings 尾块纯插入；T4 尾 3 golden（基面保真 S1 漂移伞 / gain 语义 band / reimport raster 链）+ 零 diff 机检族 + 9 hunk 对照；T5 收口（SUMMARY/DECISIONS/MANIFEST） | worker 五提交 `53a74582..04b2b0a8`（T1 `53a74582` / T2 `caa4113b` / T3 `e1ef7396` / T4 `c077784a` / T5 `04b2b0a8` docs）+ 验收批本批（VALIDATION 成文 + 两份 ACCEPTANCE 入库 + minor-1 7 位点修数）；未 push | 双路 PASS / 0 error + 0 minor open（minor-1 账面滑差闭环批清偿） |

零红线域终态（两路亲跑，`55eb8f3c..HEAD`）：九文件 + ExportState + ExportICCStrip
本体 + `ExportFormatSpec` 类型面 = **0 diff**（六格式矩阵零改动红线）；全部
`*.metal` = **0 diff**（gain 计算全在 CI 黑盒内）；`ExportQueueContract` = **0
diff**（HDR 面交接走 queue 级载体，M2-9-02 KD-4 递缝范式同族）；`Project.swift`
= 恰 2 行测试登记（dependencies 块零 diff，零新 SPM）；`*.xcstrings` = 5 键尾块
纯插入（85/0）；`\.runModal(` App/Sources = **0**；LocalizationValue 插值禁形 =
**0**；UserDefaults = **0** 新增；LightCraft/NOTICE = **0 命中**（C 路封存零代码
移植）；零新渲染链（独立 EDR 链零存在——`git diff --diff-filter=A` 亲列 = 仅
ExportGainMapEncoder + 两测试文件）。CI 全服务路定式沉淀（`.hdrImage` +
CopyImageSource rewrap——**AddImageFromSource 丢 MPF 的雷**）与 203 单源三消费点
见 AGENTS「M6-3 架构增量」节。

---

## 挂账总汇编（M6-3 单一移交清单，五项）

1. **EXIF v1 无 EXIF → v2/EXIF APP1 注入器批**（DECISIONS §1 + 两路 probe 双证，
   by-design 降级预授权非缺陷）：gain map 档无 EXIF round-trip（六格式矩阵唯一
   additive 档偏离）；Software 签名存活座位 = `xmp:CreatorTool`（XMP，
   非 EXIF APP1）。**触发 = 用户/生态对 EXIF 元数据提出硬需求时**立项注入器批——
   注意禁自建 APP1 注入器裁决在案（段级注入移动文件内绝对偏移，与 MPF 副图偏移
   互斥），届时须与 LightCraft C 路（零代码封存中）同批评估路线。
2. **HDR/base 行序方向性断言**（第二眼 obs-1）→ **M6-5 清算批候选**：encoder 的
   `.oriented(.downMirrored)` 是增益空间对齐的唯一承载，现有测试面（uniform
   band 法 + base-only 保真法 + 尺寸双法）均不抓垂直 flip——防护现状 = 与出口腿
   同约定（L029 三先例同形，代码审查可锚），flip 属观察性残余非在案缺陷；建议
   后续批补一条非 uniform HDR 面 + 非对称 base 的方向性断言（可选行）。
3. **gain map 臂不带 DPI 元数据**（第二眼 obs-2）：plain 路经 `ExportEncodeRequest.dpi`
   写分辨率，gain map 臂走 CI writeJPEGRepresentation（无 DPI 选项）——产物缺
   resolution 元数据（72 缺省观感）。UltraHDR 生态通例、无用户可见面（预览/打印
   以像素为准），**登记即可，零动作**。
4. **门③载体分叉残余**（第一路 obs1）：render 侧 headroom 取 `drtTail.record.
   peakLuminance`（装配点），validate 门③查 `variant.drtOutput.peakLuminance`——
   M2 页双写同源零分歧；直接构造 Request 可组出「drtOutput peak 合格 + drtTail
   record peak 低」→ headroom<1 超纲产物（M4 fail-loud guard 只兜 plane 缺席）。
   与 M4「载体 API 级独立」框架自洽，**全 UI 路不可达**（第二眼单值贯穿亲证），
   纯 public-API 鲁棒性观察 → **API 消费者文档注记**。
5. **Manual-Only 跨生态目检**（Preview/Photos/Chrome/Android 13+/LightCraft 互读）：
   配方 = `.work/gui-acceptance/m6-3/MANIFEST.md`（六行配方 + 半自动 sips 自检 +
   走查记录节）；**可选行，不可达不阻断收口**——全部机检面已入 `ExportGainMapTests`，
   headless 不可达面仅剩人驱渲染观感。

另有三则**登记级观察**不占挂账（两路在案，零动作或顺目）：①moveItem 晋升语义
vs plain 路原子写（第二眼 obs3——namer 冲突解析使正常流等价，外部同名竞争下
gain map 臂保守失败不覆盖外来文件，方向可取）；②`primaryXMP` 静默 nil 臂（第一
路 obs2——fresh mutable metadata 注册失败为运行时不可达面，fail-safe 不
fail-loud）；③GOAL-STATE 前序批次日期混用（第一路 obs3——2026-10-14/10-16 并存
于 M6 站早期条目，前序遗留账面非本批引入；**历史行不改写**，本批登记顺目）。

**批内已清偿**不占挂账：minor-1（申报账面 +22/31/3756 → 实测 25/34/3759 同源
滑差——第一路 3 处清单 + 第二眼 7 位点补全，本批逐行原位改数；MANIFEST 无滑差，
两份 ACCEPTANCE 数字自洽）。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。六项 OQ 生效值 + D-M6-3-7 + AC7/AC8 每条
  均有 ≥1 机器锚（ExportGainMapTests 25 法〔六门负测 + capture 两态 + 容器四法 +
  aux 双法 + rewrap 双断言 + 后处理三门 + fail-loud + 基面保真 ±1 LSB + gain
  band + reimport〕/ ExportGainMapPanelTests 9 法〔五维门 + 复位 + 装配 + enqueue〕）
  + ≥1 实证背书（两路独立全套 3759 同值 + 对账链 3725+34 精确 + EXIF probe 两路
  独立复现 + 9-hunk 两路逐 hunk + 10 项偏差两路全 ACCEPT + BUNDLE-MAP grep 实测
  25 法亲数 + 203 单源三消费点亲核 + LightCraft/NOTICE 零命中亲跑）。
- 采样密度：单 plan 全 AC 逐条机检（34 新测 + 既有面零回归双保险：五段基线逐值
  + 九文件零 diff 机检族）+ **两路零共享上下文独立验收**（各自自建 build +
  各自全套 `--all` 亲跑，第二眼证据 HEAD `04b2b0a8` 亲跑/亲读重取不复述第一路）
  + checker FAIL 先审后放（plan 评审 2E+4M+4A 回注 → 修订版 E1/E2 门 +
  M1-M4 修复 + S1-S4，checker 放行 C-1..C-5——`9015a608`→`56ea8461`→
  `01dc6e52` 三步链在案）；「无证据 ✅」零项。
- 数字对账：两路互证（3759/24/0 两轮独立亲跑逐值一致 + 段级 skip 和 = TOTAL
  机械一致 + 对账式 3725+34 = 3759 精确 + Export/App 增量 25/9 与文件 grep
  亲数一致）。

## 特殊事项入册（phase 级事件台账）

1. **omp 制度路配额阻塞 → 双 zcode 独立眼替代**：原制度第二路（omp 串行）因
   配额硬顶阻塞（M6-2 同款 429 家族），第二路意图由第二支零共享上下文 zcode
   独立验收眼兑现（PASS，全套独立亲跑同值）——**dual_acceptance 意图满足、
   制度字面偏离**（omp 未参与本 phase 验收），登记晨审可裁。
2. **charter 集成点演进（research 驱动的合法演进，非越权）**：charter 原文
   「spike 先行 = ImageIO 原生路 + 集成 `ImageIOEncoders` JPEG 腿 additive」——
   research 三臂实测证 ImageIO 两键死路（aux 手挂七形态全拒 / destination 键族
   静默忽略+count=2 拒）→ **可行原生路 = CI `.hdrImage` 全服务路**（CI 即 Apple
   原生框架，charter「原生路容器字节达标即收」兑现）；集成点演进 = `encodeStage`
   gain-map 臂 + 新文件 `ExportGainMapEncoder`，**六格式矩阵零改动红线维持**
   （`ExportFormatSpec`/五编码器/registry/quantizer 全零 diff 机检在案）；
   LightCraft C 路降兜底封存（零代码零 NOTICE）。演进正本 = `RESEARCH.md` +
   `M6-3-CONTEXT.md`（夜间授权批裁决落签）。
3. **minor-1 账面滑差两眼接力闭环**：执行方申报 +22/31/3756（定向轮记账）vs
   实测 25/34/3759——**滑差性质 = 账面非测试缺口**（3759 ∈ plan 预期带顶沿，
   两路独立亲跑同值）；第一路清单 3 处 + 第二眼 `grep` 全量扫描补全 7 位点
   （第一路 4 处遗漏同源同性质零代码面），本批逐行原位改数。教训与 M6-2 minor-1
   同族：申报数字应以 `grep -c "func test"` 机检为准，不应心算累计。
4. **EXIF 座位事实分账**（对 L054 的适用边界注记）：L054「EXIF Software 唯一
   可序列化座位 = `{TIFF}` dict」是 **ImageIO 编码路**事实；gain map 档走 CI
   编码路，`{TIFF}/…` 属性路径语法被 `CGImageMetadataSetValueWithPath` 拒
   （两路 probe 双证）——L054 事实不适用于本档，Software 存活座位 = XMP
   `xmp:CreatorTool`。两座位事实并存，后续 EXIF 批引 L054 时须分路对账。
5. **D-M6-3-7 增补裁决的权限注记**：validate 第五门是对 OQ-5 生效值可用门集的
   **planner 权限外收窄**（三条件→四维），由评审 M3 回注、orchestrator 夜间
   授权批裁准（CONTEXT 增补节在案）；晨审推翻路径 = 撤门三处回退
   （validate/UI 谓词与文案/负测）+ DECISIONS 语义豁免显式登记。
6. **登记级观察三则**（见挂账节末——moveItem 晋升语义 / primaryXMP 静默 nil /
   GOAL-STATE 日期混用前序遗留）：均零代码面零用户可见面，不立账不阻断。

## 授权记录（C 档第 3 停 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 +
  M3/M4/M5/M6-1/M6-2 全系 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」（research/plan/执行 +
  双重验收编排 + 终验 + 本 VALIDATION 同一授权链）。
- 依授权，本 VALIDATION 由 VALIDATION 成文 executor 落盘签核（`.work/config.toml
  [gsd] paused=false / auto=true` 全程未动，dual_acceptance=true 在册）；用户晨审
  可推翻本签核（推翻 = M6-3 签核作废回退，已交付面与两路执行/验收证据不受
  影响；翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode VALIDATION executor（2026-10-14 晚批）；**doc-only——
  零源码 diff**（`git status` 对表 = 本批全 docs；工作树既有 untracked 四件
  属兄弟批/孤儿 fixture〔M4-1 #6〕，本批零触碰）。
- **呈报裁决点（禁静默）**：①EXIF APP1 注入器批时机（挂账 #1，默认 = 出现真实
  EXIF 硬需求时与 C 路评估同批）；②行序方向性断言归属（挂账 #2——M6-5 清算批
  候选 or 独立小批）；③Manual-Only 跨生态目检安排（挂账 #5 可选行，默认不安排
  不阻断）；④门③载体分叉 API 注记落点（挂账 #4——doc 注记 or encoder 头注）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：ALCE-03 翻 **Delivered（validated）**——CI `.hdrImage` 全服务路
  终态 + 六门 + EXIF 降级注记 + C 路封存注记。
- ROADMAP：M6-3 行 ✅ 闭环（终态 3759/24skip/0fail；双路结论 + charter 演进
  注记）；头部 Milestone 6 行追加 M6-3 closed。
- STATE：M6-3 complete + current_phase 翻新 = next M6-4；m6_phases_complete 4；
  M6 Ledger 4/7。
- TODO：M6-3 条目落账（[x]）+ M6 头部翻新（M6-3 ✅ 闭环，下一步 = M6-4）。
- GOAL-STATE：续接点翻新 = **M6-3 closed → M6-4（图库 stacks + auto-stack + AI
  分割蒙版原生 spike）**。
- minor-1：7 位点原位改数随本批 VALIDATION commit；未 push；测试宿主/GUI 进程
  零残留（两路验收批各自清场申报在案）。

## 签核

- 六项 OQ 生效值 + D-M6-3-7 + AC7 + AC8 全项 **Delivered**（三列证据齐；数字
  对账 = 两路独立亲证基线 3759/24/0，对账链 3725+34 精确闭合；双重验收零实质
  分歧）。
- `status: validated` + `nyquist_compliant: true`。
- **M6-3（ALCE-03 UltraHDR gain map JPEG 导出）closed**：单 plan 全量批双路
  独立验收 PASS / 0 error + 0 minor open（minor-1 账面滑差批内清偿），终验
  `TOTAL|3759/24/0|`（两路 2106s/2130s 独立亲跑同值）；挂账单一清单五项
  （EXIF v2 注入器批 / 行序方向性断言 → M6-5 候选 / DPI 登记零动作 / 门③载体
  分叉 API 注记 / Manual-Only 跨生态目检可选行）+ 登记级观察三则，移交 M6-5
  清算批与晨审。
- 晨审裁决项：四项呈报裁决点（见授权记录）+ 签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**

---
phase: M2-9
slug: export
status: validated
nyquist_compliant: true
created: 2026-10-03
validated: 2026-10-03
---

# Phase M2-9 — Validation（导出选项 Alcedo 化：SC#1-5 三列证据 + Per-Plan Map + 晨审裁决项汇总 + 授权记录）

> 体例对齐 `phases/m2-8-versions/M2-8-VALIDATION.md`（frontmatter / Checklist）。
> **翻账只认证据**：SC 表逐条「SC 原文 + 证据指针（测试名 + 数字 + commit SHA +
> ACCEPTANCE 节）+ 判定」；无证据 ✅ = 违规。**SC 数字对账基线 = M2-9-05 验收
> 终轮全套独立复跑 `TOTAL|2693/16/0|923s EXIT=0`**（含 F-2 修复树 `afb1f88`，
> build-for-testing 重建；`M2-9-05-ACCEPTANCE.md` §一；peakRSS 最大 IOP 6541MB
> < 8192MB 门，零 MEMFAIL）。对账链：**2577（M2-8 终）→ 2611 → 2634 → 2662 →
> 2693 → 2693（05 收口零新测试）**，逐 plan 有独立验收复跑背书。
> 本 phase **零 error 级 FINDING**（五轮验收全 PASS / 0 error；走查 F-1 属
> M2-3 时代面另案、F-2 minor 已修闭环）——签核 = 带挂账清单 + 晨审裁决项照常放行。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 真链装配 / 直启宿主 / 真机 AX+cliclick 走查） |
| **Quick run** | `Scripts/test-direct.sh`（L019b 直启；`--bundle`/`--all`） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **2693 tests / 16 skip / 0 fail**（923s，2026-10-03 午后 M2-9-05 验收批独立复跑，EXIT=0；含 F-2 修复树；MEMFAIL 零，峰值 IOP 6541MB < 8192 门） |
| **基线演变** | M2-8 末 2577 → M2-9-01 +34（**2611**：Settings 6 + Template 11 + Collision 5 + MetadataPolicy 4 + Recipe 2 + Store 6）→ M2-9-02 +23（**2634**：DrtOutputColorSpace 10 + DrtChain 5 + DrtTailE2E 8）→ M2-9-03 +28（**2662**：NamingE2E 11 + EncoderMetadata 8 + IccEmbed 8 + XMPMatrix 1）→ M2-9-04 +31（**2693**：InspectorFace 9 + MemoryKeys 11 + Assembly 11）→ M2-9-05 +0（收口走查零源码，2693 持平）；skip 恒 16 |
| **在案 flake** | SidecarV5Tests 环境型瞬态（04 验收轮复发：Data 卷 96% 满反噬 ANE/decode 腿，两种形态；清 sidecarv5 残留 ×84≈6G 后单 bundle 绿 + 全套终跑绿；M2-5-3/M2-8-2 前案同族——卫生缺陷本体挂账#2）；L055 test-direct.sh 崩溃假绿解析器（03 起挂，脚本修复另案报备） |
| **GUI 证据** | `.work/gui-acceptance/m2-9/`（MANIFEST 逐项表 + 截图 ×20 + AX dump ×4 + 元数据 dump ×2 + F-2 修复复验截图 ×2） |
| **zh 对账** | `zh-audit --check` **PASS**（1398 source keys / 1633 catalog keys / zh complete / locale {en, zh}；05 验收亲跑） |

---

## SC#1-5 对照表（ROADMAP §M2-9 行契约 = REQUIREMENTS M2EXP-01..05，三列证据）

| SC | 判据（SC 原文） | 证据指针（测试名 + 数字 + commit SHA + ACCEPTANCE 节） | 判定 |
|---|---|---|---|
| **SC#1** | **尺寸四模式——Original/Long Edge/Bounds W×H/Print（in-cm-mm+DPI）+ allow_upscale + maximum_edge_pixels**（M2EXP-01） | **模型+数学半边**：`6835bd2` `OutputMode` 四模式 + `bounds(w:h:)`/`physical(width:height:unit:dpi:)` + `ExportPhysicalUnit` + `allowUpscale`/`maximumEdgePixels` + `resolveExportResolution` 单源数学（Alcedo cpp:31-80/287-325 同构自写；golden 手算六法全真——含 **DPI 宽度比修正锚 300×2/3=200**、physical DPI≤0 typed 失败；`M2-9-01-ACCEPTANCE.md` §三.1）；YiyinExportSettingsTests +6 / ExportRecipeTests 增向量；全套 **2611/16/0**（01 验收 §一三轮全记录）。**renderer DPI 接线半边**：`cfbe385` renderStage sizing 腿直切 `resolveExportResolution` + `StageOutput.dpi = result.dpi`；golden `testCappedPhysicalExportLandsCorrectedDPI`（2000×1333 + DPI 元数据 200 经 `kCGImagePropertyDPIWidth` readback；legacy 三模式逐值零漂移论证 cap=0 直通 + clamp no-op）（`M2-9-03-ACCEPTANCE.md` §五.1）。**面板 UI 半边**：`ec69483`/`572df73` 四模式字段按模式显隐 + 高级折叠区（allowUpscale=false / maxEdge=0，OQ-12 A）+ 模型域越界红字禁入（`canRun` 门，不静默钳）；`ExportMemoryKeysTests.makeSizing` 四模式映射 + `testPanelModelDefaultsMatchAlcedo`（2048/210×297@300 首用默认，`M2-9-04-ACCEPTANCE.md` §七 AC2）。**走查**：#2 四模式 + 折叠区默认屏上逐值（210/297/mm/300 DPI + 打印尺寸截图，`m2-9` MANIFEST #2） | ✅ |
| **SC#2** | **元数据策略档位——默认剥离 location/设备序列号/编辑历史；EXIF 写入本 app 版本号**（M2EXP-02） | **模型半边**：`3b90709` `ExportMetadataPolicy` mode{standard,none}+6 bool（STANDARD = exif/xmp/iptc 真 + location/serials/editingHistory 固定剥离假；Alcedo hpp 字段清单对表）+ `ExportVariant` 手写 `init(from:)` 容错 decode（旧 payload 字面锚双侧）；ExportMetadataPolicyTests 4（01 验收 §三.5）。**消费半边**：`6a7515a` `ImageIOEncodeCore.mountMetadata` 单点装配腿（五 encoder 换调用点；**编码核心面零 hunk = E1 案 A**，`M2-9-03-ACCEPTANCE.md` §三逐 hunk）+ OQ-6 剥离（BodySerialNumber 精确 + Exif-dict GPS 前缀 + `{GPS}` 构造性缺席；NONE 短路）+ EXIF Software **{TIFF} dict 座位**（D-5 原文 Exif 座位全容器被弃——ObjC 探针链 `M2-9-03-DECISIONS.md` §1；JPEG readback 不回显走 byte-scan）+ `mountXMP` policy gate（`.skippedByPolicy` 五臂穷举；默认档 packet 不嵌 = OQ-6 有意行为变更，XMPExportMatrixTests 白名单改造 6/0 + `testDefaultPolicyKeepsPacketUnmounted`）；ExportEncoderMetadataTests 8（03 验收 §五.3/.4）。**App 传值载体**：`c97924e` `exifSoftwareString(version:)` + `currentExifSoftware` 经 `enqueueExportM2` → `$jobExifSoftware` TaskLocal（03 钦定递缝，引擎体零 hunk）；`ExportAssemblyTests` 真链捕获 encode 腿逐 job 载体值（04 验收 §五.3）。**走查**：#4 单图出片 byte-scan **Software="Lightamer 0.1.0" FOUND @120** + ICC BT.1886 幂臂 + **无 GPS IFD**（元数据 dump 亲读，MANIFEST #4） | ✅（Software 座位 = {TIFF} dict 非 D-5 原文 Exif 座位——平台实测探针链在案，REQUIREMENTS 注记已落） |
| **SC#3** | **文件名模板——字段 12 种+补零序号+冲突 FAIL/REPLACE+子文件夹**（M2EXP-03） | **引擎+模型半边**：`e2a37f3` `ExportFileNameTemplate` 11 token+literal（12 面）parse/render 分离 + `{{}}` 转义 + typed 五错误 + sequence 零计数位宽 + shutter `1-500` 形态 + sanitize 200 帽 + fallback "image"（Alcedo cpp:136-197 逐形态对表，01 验收 §三.3）；ExportFileNameTemplateTests 11。`3b90709` `ExportCollisionPolicy` 三档（increment 默认 = 既有 `-1/-2` 行为**逐字节**——重载对形态，`testDefaultOverloadEqualsIncrementTier` 双面同 URL 钉；`.fail` typed `BaseNameOccupiedError`；`.replace` 永不落 `-N`）+ `ba379ac` `NamingTemplateStore` 三内置（QML:35-52 **逐字节**对表）+ CRUD + 损坏降级；ExportCollisionPolicyTests 5 + ExportNamerTests **零 diff 全绿** + ExportNamingTemplateStoreTests 6（01 验收 §三.5/.6）。**renderer 接线半边**：`cfbe385` step 9 逐 job 模板求值（decoded.capture 8 字段 + 盘上 rating〔override 模式同读〕+ sequence）+ 冲突三档消费（FAIL=typed 拒绝零写盘，queue 级经既有 finish 映射 `.encodeFailed(String)`——Contract 零 diff 不扩面）+ 子文件夹消费（渲染前 typed 创建，`landingDirectory` 单源 join）+ `$jobNamingCarrier` TaskLocal 递缝（sequence 入队盖章批内序）；ExportNamingE2ETests 11（`testFailPolicyFailsQueueJobWithoutWriting` 断言 1 done + 1 failed + 单产物落盘）（03 验收 §五.5）。**面板 UI 半边**：`ec69483` `ExportNamingEditor`（预设下拉 3 内置+用户+Custom / 11 token 尾追 / typed parse 红错+raw message / live 预览四断言 / 存 sheet+改名 inline+删〔内置不可删〕；手改 pattern→Custom 掉锚；无效模板→`canRun` 禁用）。**走查**：#3 模板红错（`{source` → unmatchedOpeningBrace + 存预设置灰）+ live 预览 `edit-01.jpg-0001` 屏上亲见；#5 批量 sequence `edit-01-0001 / img-05-0002 / img-15-0003` 落「导出」子目录（MANIFEST #3/#5） | ✅（注记：M2 页冲突档固定 `.increment` = 默认档 UI 呈现——引擎/模型三档单测+E2E 钉死，档位选择器缺口挂账#4；OQ-5 裁决口径内，05 验收 §五定性 observation） |
| **SC#4** | **输出 ICC = 本图 DRT 编码强制联动（space/EOTF/peak nits 入队前已解析）；格式矩阵保留原 6 格式（EXR/UltraHDR = V2 ALCE-02/03）**（M2EXP-04） | **渲染链半边**：`e87b25e` `DrtOutputColorSpace`（space×eotf 穷举无 default——`grep "default:"` = 0，42 组合全域测试 accept-set==legalEOTFs；legalEOTFs==映射==Alcedo cpp:76-118 **三方逐行镜像**；macOS 27 CalibratedRGB 平台缺陷 → SDR 幂臂自建 ICC v4 字节，**锚值第一性重算逐位一致**——rec709 rXYZ `[28576,14581,912]` 与 Alcedo `rec709_bt1886.icc` 原码逐位、p3_d60 九值同样逐位；`para` fn=0 ColorSync 误解析 → 全走 curv；HDR 三臂系统名 ITUR_2100_PQ/HLG + DisplayP3_PQ）`M2-9-02-ACCEPTANCE.md` §四.1；`48a7136` `exportDrtChain`（records verbatim + `drtEncoding` 载体）+ `Request.drtTail`/`jobDrtTail` TaskLocal 队列递缝（**像素 parity maxDiff==0** + profile 名恒等双断言实证）+ `enqueue(drtTails:)`；`ef3a70b` `tailFormatFloatOverride` 四处缝（导出尾平面恒 float32，quantizer 拥有钳位与位深 = OQ-8-A；display 零漂移门 DrtTailTests 12 + AIMaskPlaneFormatTests 3 零改全绿）；`4ceee3b` yiyin×DRT E2E（HDR record 下 band=post-EOTF 纯白 vs 内容 PQ 码可分辨——borders/watermark EOTF 后红线导出腿实证）；`testHDRDrtExportClampsToUnitRangeThroughTIFFFloat32`（[0,1] 钳四断言）；全套 **2634/16/0**（02 验收 §一/§四）。**元数据腿/OMIT 半边**：`fe338d7` `ExportICCStrip` post-encode 剥离（JPEG APP2 marker walk / PNG iCCP / TIFF tag 34675 原位压缩 + **孤儿 payload 按 entry 定界清零**；HEIC/AVIF/WebP typed `.skippedUnsupportedFormat`；完整性 = `stripped == strip(embedded)` 确定性断言 + SOS 后熵流 verbatim）+ `embedICC` encodeStage/render/queue 全消费 + `ExportVariant.validate` drtOutput peak 闸门（finite 正数 typed 拒绝五坏值 + nil 不触发）；ExportIccEmbedTests 8（03 验收 §五.2）。**装配半边**：`c97924e` `enqueueExportM2` OQ-7 强制联动（`assembled.drtOutput = drtRecord` + 每图 `DrtTailParams(record:postOpNames: NodeOwnershipCatalog.drtPostOpNames)`——PipeCoordinator :660 同法 verbatim）+ 装配级 peak 闸门兜底（04 验收 §五.3）。**走查**：#4 出片 ICC = BT.1886 幂臂（Rec709 主色度 + curv γ2.398）+ #9 PQ 臂（Rec.2020 切换**吸附 ST 2084 联动直证** + 出片 ICC = 系统 "Rec. ITU-R BT.2100 PQ" CICP 9/16 + [0,1] 钳位）（MANIFEST #4/#9）。**6 格式矩阵**：六格式 Picker 全本地化（F-2 修复后实机复验六项，截图 ×2）+ 编码器矩阵零改动红线（`WebPEncoder.swift` 02/03/04 三波机检零 diff；`ImageIOEncoders` 编码核心面零 hunk） | ✅（EXR/UltraHDR = V2 既有挂账维持，REQUIREMENTS 注记已落） |
| **SC#5** | **导出队列 UI（检查器内、四态、质量跨会话记忆）；yiyin 印框/水印终步保留适配**（M2EXP-05） | **队列 UI 半边**：`ec69483`/`572df73`/`c97924e` 检查器 Export 页（OQ-1 A：`exportPageActive` 会话开关挂 Inspector 列 + File>Export 菜单复用 `\.exportPanelRequest` focused 键 + topbar 按钮；legacy sheet 冻结——`ExportPanelView.swift` 全波 **0 行 diff**，`LightamerApp.swift` 零 diff，剥离门 `openExportPage` 恰 3 调用点全 M2 面）+ `ExportQueueFaceView` 四态映射（pending→Queued / rendering+encoding→Exporting / done→Done / failed+cancelled→Failed 取消归败档——穷举 switch 测试钉）+ 36 行帽 + `…(N more)` + 进度 + 失败红字摘要 + per-job retry/cancel；ExportInspectorFaceTests 9 + ExportMemoryKeysTests 11 + ExportAssemblyTests 11（App **512/0/0** = 9+11+11 逐类亲数）（04 验收 §三/§五/§七）。**质量跨会话记忆**：四键登记拼写常量 + `object as? Double` typed 读（**0.0 真记忆**——`testQualityZeroIsARealMemoryNotAnUnsetKey` 抓 presence-check 假记忆后修正）+ mount/切格式载入 + run/离页写回（04 验收 §五.2）。**yiyin 适配**：注入器保留（`ExportYiyinInjector` 零 diff）+ topbar yiyin sheet 入口（走查 #8 入口实证）+ yiyin×DRT E2E 语义承载（02 T4）。**走查十项终态**（`m2-9` MANIFEST 逐项 + `M2-9-05-DECISIONS.md` §1）：五节观感（AX 树+截图双证）/ 四模式+折叠区默认 / 模板三内置+红错+live 预览 / DRT 联动出片元数据 / 批量 sequence 落子目录 / 失败红字+retry（AXPress 翻完成）/ 46 jobs→36 行+「…（还有 10 项）」精确帽 / yiyin 入口 / PQ 臂 / legacy 回切双向（`export.page.*` AX 零命中）；全套 **2693/16/0** 终跑零漂移（05 验收 §一）。**翻账**：M2EXP-05 Delivered 终注已落（走查批 `M2-9-05-DECISIONS.md` §5） | ✅（注记：yiyin M2 出片恒 false = 04 裁决面延续〔M2 页无 yiyin 节——Alcedo 对标面无此项，语义 E2E 承载，V2 页面节挂账〕；legacy sheet 会话内实开 = 待人工可选余项） |

---

## 晨审裁决项汇总（执行/验收批已判，用户晨审可逐条推翻）

| # | 项 | 内容与执行/验收判定 | 推翻路径（如晨审不认） |
|---|---|---|---|
| 1 | **越界三追认**（M2-9-04） | ①Core 载体两面（`ExportQueue`+`ExportRenderer`：`$jobExifSoftware` TaskLocal + per-image `instancesOverrides`）——03 交接节**钦定缝**原文亲核 + 引擎体零 hunk 亲验 + Export bundle 338/1/0 两轮零漂移实证 + 索引载体为批序保序唯一路径；②`WorkspaceHostView`——KD-1 topbar 正主 + KD-4 provider 必要腿（32 行最小面）；③`ToastFaceTests` 环境随动——**真因修复**（最小宿主少注入新 env = 挂载即 trap，生产码/断言零改）。04 验收 §四全追认；05 走查无新反证 → **维持追认建议** | revert 对应 hunk（`c97924e` 内载体面）——注意 ①为 03 钦定接缝、③不修则 App bundle 全量必崩 |
| 2 | **层语义边界**（04 §3 / 晨审 §12.2 双挂点） | 带层图 M2 面 override 腿 = **base 链像素**（`layerRecord = nil`，blame `fb5b044` 11-03 起 renderer step-3 现行语义——非本波引入实证；批量其余图恒盘上真相含层）。04 验收定性「诚实申报的既有边界」；05 走查 #4 用无层图 → 无 GUI 新证 → **立项 Core layer 座位与否 = plan 级决策，裁决点维持** | 晨审判层语义必须进 M2 面 → Core override 面加 layer 座位另立 plan（本 phase「纯 App 波」红线内未动 Core 渲染面） |
| 3 | **MCP export_image opt-in XMP**（03 `d2e80d2` 越界 fix） | OQ-6 默认收窄（mountXMP 三 bool 合取）波及 MCP 互操作契约——`McpEditingToolsetTests.testExportImageLandsInOutputWithXMPAndPathNote` **零修改**字节断言钉 packet（`ns.adobe.com/xap/1.0/`），不 opt-in 必红（执行波跑 1 实证）；修复 = 单调用点显式 `ExportMetadataPolicy(editingHistory: true)`，GUI 导出面收窄照旧。03 验收 §四判「成立且必要，改动面最小」 | revert `d2e80d2` → 契约测试必红（= 用户升级点：OQ-6 收窄是否应波及 MCP 互操作面由用户终裁） |
| 4 | **目标集 = 编辑面网格选择**（04 §5） | 页入口在 editor topBar/菜单 → provider = 编辑面网格选择（filmstrip/grid 同一选择状态机；library 阶段多选不进导出腿）。05 走查实证一致 → **维持**；O-5（应用重启后 filmstrip 点击不进 provider 回落单图；同会话 cmd+click 正常）登记观察 | 如需 library 网格多选直入导出 → 另立 plan 扩 provider |
| 5 | **add/start 塌缩形态**（04 §8） | Alcedo 两段式「Add to queue → StartExport」塌缩为单 enqueue（引擎即入即泵，并发 1 红线不动——「无新状态、无队列引擎感知」裁决的直接推论）。05 走查实证单按钮「加入选中（N 张）」直入队即跑 → **维持** | 晨审判需两段式 → App 层改造（引擎面不动） |
| 6 | **FAIL 冲突档 UI 不可达** | OQ-5 裁决 = 三档并存「Increment 默认 + FAIL/REPLACE 显式档」——引擎/模型三档已交付且单测+E2E 钉死；M2 页固定 `.increment` 是默认档的 UI 呈现，档位选择器暴露从未单独立裁决。05 验收 §五定性 observation（裁决内合理现状）；挂账#4 | 晨审判选择器必须暴露 → 随 `fix(m2-9)` 通道或另案小修 |
| 7 | **yiyin M2 出片恒 false**（04 裁决面） | 04 验收 §八既裁「M2 页无 yiyin 节——Alcedo 对标面无此项」（`makeVariant()` 恒 false）；走查 #8 尊重裁决改登记入口实证 + 语义引 M2-9-02 E2E。**V2 页面节挂账**维持 | 晨审判 yiyin 节进 M2 页 → V2 提前立项 |
| 8 | **01 波越界 fix 族**（`3a1ecb8` + 验收批 `8e810a0`） | 活体夹具（gitignored `input/RAW/DSC00012.ARW.lra` 带层漂移）暴露「带层 sidecar 必炸未注册 IOP metallib 的测试」潜伏缺陷——四处测试位测试侧注册修复（QuickLookRenderer + McpRenderParity ×3），夹具原样、无产品码。01 验收 §四闭环 | revert → fail 态回归（属既有环境问题非本波引入）；O-2 观察项：再爆同签名优先排查该 sidecar layerStack |

---

## Per-Plan Map（M2-9-01..05 + 验收批）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M2-9-01 数据模型与纯函数面 | `OutputMode` 四模式 + `resolveExportResolution` 单源数学 + `ExportFileNameTemplate` 模板引擎 + `ExportCollisionPolicy` 三档 + `ExportMetadataPolicy` + `ExportVariant` 三载体 + `NamingTemplateStore` | `6835bd2`/`3a1ecb8`（越界 fix）/`e2a37f3`/`3b90709`/`ba379ac`/`f302011`（收口）+ `8e810a0`（验收批 parity 注册 ×3） | PASS / 0E + 1m 已修 + 2o（2611/16/0；`M2-9-01-ACCEPTANCE.md`） |
| M2-9-02 ICC=DRT 强制联动渲染链 | `DrtOutputColorSpace`（自建 ICC v4）+ `exportDrtChain` + `Request.drtTail`/`jobDrtTail` TaskLocal 递缝 + `tailFormatFloatOverride` 四处缝 + yiyin×DRT E2E | `e87b25e`/`951d85c`（mluc 修复）/`48a7136`/`ef3a70b`/`4ceee3b`/`8dcc32d`（收口） | PASS / 0E + 1m 已修 + 2o（2634/16/0；`M2-9-02-ACCEPTANCE.md`） |
| M2-9-03 命名/元数据/ICC 消费接线 | step 9 命名腿 + E6 sizing 切换 + `mountMetadata` 装配腿 + OQ-6 剥离 + {TIFF} Software 座位 + `ExportICCStrip` OMIT + peak 闸门 | `cfbe385`/`6a7515a`/`fe338d7`/`d2e80d2`（越界 fix：MCP opt-in）/`262f98e`（收口） | PASS / 0E + 1m 已修 + 2o（2662/16/0；`M2-9-03-ACCEPTANCE.md`） |
| M2-9-04 检查器 Export 页 + App 装配点 | 五节 UI + `ExportNamingEditor` + 质量四键 + `ExportQueueFaceView` 四态/36 帽 + `enqueueExportM2` + Core 载体两面 + WorkspaceHostView topbar | `ec69483`/`572df73`/`c97924e`/`8cbcfbb`（收口） | PASS / 0E + 1m 已处置 + 3o（2693/16/0；越界三追认；`M2-9-04-ACCEPTANCE.md`） |
| M2-9-05 收口走查批（wave 4） | KD-1 十项真机走查（证据 34 件 + MANIFEST）+ zh-audit PASS 零缺口 + M2EXP-05 翻勾 + 五账同批 + phase 小结 | `7cedbf4`/`7ccf4ec`/`a40f1c4` + `afb1f88`（验收批 F-2 fix）+ `e77def8`（验收报告） | PASS / 0E + 1m 已修 + 3o（2693/16/0 零漂移零新测试；`M2-9-05-ACCEPTANCE.md`） |

零源码红线终态：05 验收亲跑 `git diff --name-only 2ab4f3a..a40f1c4` 非 `.work/`/AGENTS.md 文件数 = **0**；四前波封存面八处抽查全零行（`ExportPanelView`/`LightamerApp`/`ExportQueueContract`/`WebPEncoder`/`ExportQuantizer`/legacy 三测试族）。验收批 fix 例外两件均授权通道隔离提交（`8e810a0` fix(m2-9-01) / `afb1f88` fix(M2-9-05)），红线语义只约束 worker 提交。

---

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。SC#1-5 每条均有 ≥1 机器锚（本 phase 新增测试
  **+116 法**：01 波 34 + 02 波 23 + 03 波 28 + 04 波 31——BUNDLE-MAP 逐行登记且
  经 02/03 两波 M-1 勘误后行值 = 文件 `func test` 终态逐值对表）+ ≥1 数字/走查
  实证（全套 2693/16/0 五轮独立验收复跑 + `m2-9` 走查 34 件证据）。
- 覆盖密度与前序已签核 phase（M2-8-VALIDATION 同款）对齐：数学面 golden 手算
  （resolveExportResolution 六法 / E6 DPI 修正 readback / ICC 锚值第一性重算逐位）、
  语义面真链装配（ExportAssemblyTests 真链捕获 + queue E2E 像素 parity maxDiff==0）、
  UI 面真机走查（AX + 截图 + 元数据 dump 在案）、行为面正反双向（typed 拒绝五坏值 /
  剥离确定性断言 / 契约测试负腿）、平台面第一性实证（CalibratedRGB 死亡 probe 链 +
  para fn=0 误解析对照矩阵）。
- 采样率对变更面不成欠账：五 plan 全部 AC 逐条机检（9+8+8+9+8 = **42 条**）+
  五验收 subagent 零共享上下文独立复跑；每轮全套对账基线精确（+34/+23/+28/+31/+0
  逐波对上）；无「无证据 ✅」项。
- zh 对账收口：`zh-audit --check` PASS（1398/1633/{en,zh}）+ F-2 动态查表键族
  修复后消亡——静态扫描盲区以 L058 教训沉淀。

---

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（C 档第 3 停夜间
  授权先例，M2-8-VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（用户两条显式指令，M2-8 签核批在案沿用至夜间全自动批）**：
  1. 「今晚任务不要停下，自动化持续推进」（今晚不停）
  2. 「开跑，不要停」
- 依上述授权，本 VALIDATION 由夜间全自动批落盘签核（`[gsd] paused=false /
  auto=true` 全程未动——五 plan 执行/验收逐任务边界复查在案）；用户晨审可推翻
  本签核（推翻 = M2-9 签核作废回退，已交付面与五轮验收证据不受影响）。

---

## 挂账清单（Deferred + 观察项，交接修复批与 M2-10）

**独立小修 plan 候选（排期 orchestrator 裁）**：
1. **F-1 Import Folder 面板取消即崩**（error 级，非 M2-9 交付面——M2-2/M2-3 时代
   导入面板；SIGSEGV 2/2 复现，`.ips` ×2 存档亲验：`swift_release_dealloc` 帧 =
   SwiftUI 闭包过度释放签名）。**修复批在飞，另行登记**（独立登记跟踪，不在本
   VALIDATION 闭环内）。
2. **SidecarV5 卫生缺陷**（测试失败路径不清工作拷贝——04 验收轮清残留 ×84≈6G
   实证复发条件 = Data 卷满反噬 ANE/decode 腿；M2-8-2 observation③ 延续）——
   teardown residue sweep 或 setUp 清同名前缀，独立小修。
3. **L055 test-direct.sh 崩溃假绿解析器**（宿主中途 crash 取末条类 suite 行当
   bundle 计数；03 起挂）——脚本修复另案报备 orchestrator。
4. **冲突档选择器 UI 缺口**（`enqueueExportM2` 固定 `.increment`；引擎三档已交付）
   ——随 `fix(m2-9)` 通道或另案（晨审裁决项#6）。

**V2 面（既有挂账延续，REQUIREMENTS 注记在案）**：yiyin M2 页节 / peak-ICC 标注 /
UltraHDR（ALCE-03）/ EXR（ALCE-02）/ 全 recipe 预设 / 细粒度元数据 UI。

**待人工可选**：legacy sheet 会话内实开走查（sheet byte-frozen 且 11-04 已验）。

**观察项（登记不修）**：O-1（#7「…（还有 10 项）」精确字符串旁证链齐，无直接屏幕
工件）/ O-2（队列「清空」= cancelAllJobs 语义，Done 行保留）/ O-3（模板预设锚按
名单不按 pattern 反查）/ O-4（36 帽下排位 >36 失败行不可见，retry 随行隐藏）/
O-5（重启后 filmstrip 点击不进目标 provider 回落单图）/ 04 O-2（质量测试名
non-finite 措辞差——plist 不可达面，isFinite 在位）/ 02 O-1（enqueue 等长
precondition 崩溃面——编程契约）/ 02 O-2（自建 profile 导出 golden 永不钉文件
字节，L053③ 口径）/ 01 O-2（活体夹具漂移反复现环境风险）。hunk 记账类勘误
（02 M-1 / 03 O-1 / 04 O-1）正本各在验收报告，不另立账。

**LESSONS 沉淀终态**：L053（macOS 27 自建 ICC 三坑）/ L054（ImageIO 写入面 ≠
readback 面）/ L055（test-direct.sh 崩溃假绿）/ L057（NSOpenPanel 取消 SIGSEGV）/
L058（LocalizationValue 插值字面量查表键）已入册；L056 候选（SwiftUI
`@Environment` 少注入挂载即 trap——全仓 grep 测试挂载点随动纪律）登记于
`M2-9-04-SUMMARY.md`，随批补沉淀。

---

## 翻账与移交

- REQUIREMENTS **M2EXP-01..05 全 Delivered 终态复核通过**（五条注记义务全落：
  01 我方超集域 1...100000/1...2400 / 02 XMP packet 默认不嵌 + {TIFF} 座位 /
  03 三档 Increment 默认 / 04 尾平面 float32 + EXR/UltraHDR V2 / 05 冲突档 UI +
  yiyin M2 节 + legacy sheet 实开）——本批零改动（前波翻账已终态）。
- STATE.md：M2-9 翻 complete（2693/16/0）+ M2-10 标 next（本批）。
- ROADMAP §M2-9 行状态同步 ✅（本批）。
- GOAL-STATE 续接点增量：M2-9 closed → **修复批候选排期**（F-1 / SidecarV5 卫生 /
  L055 脚本 / 冲突档选择器，orchestrator 裁）→ **M2-10（AI 图库）research 起步**
  （M2-10-01）。
- M2-10 依赖面交接（`M2-9-05-SUMMARY.md` 交接节）：导出管线消费面已备——
  `ExportVariant` 载体 + TaskLocal 递缝三件套范式（`jobDrtTail`/`jobNamingCarrier`/
  `$jobExifSoftware`）+ `resolveExportResolution`/`DrtOutputColorSpace` 单源——
  AI 出片（M2AI-09）的导出汇入点按 AGENTS.md「M2-9 架构增量节」约定正本消费。
- 未 push；GPL 参考零接触（Alcedo/darktable 只读对表）；`.xmp` 零读写删。

## 签核

- SC#1-5 全项 ✅（三列证据齐；SC 数字对账 = 05 验收终轮 2693/16/0 亲证基线）。
- `status: validated` + `nyquist_compliant: true`。
- 零 error 级 FINDING（五轮验收全 PASS / 0 error；F-2 minor 验收批 `afb1f88`
  闭环——「走查 minor 一件，验收批闭环」）；挂账四小修候选 + V2 面 + 观察项
  随 M2-10 交接。
- 晨审裁决项八条入册（§晨审裁决项汇总），逐条带推翻路径。
- **C 档第 3 停 = 夜间授权先例（D-07-3-T5-1 + 用户「今晚不停」「开跑，不要停」
  两条原话）落签，晨审可推翻。**

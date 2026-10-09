# M2-9-ACCEPTANCE-OMP — 导出 Alcedo 化回溯二次验收（phase 粒度）

**验收:** omp 独立二次验收（零共享上下文，不轻信首验，一切亲测）
**Date:** 2026-10-09
**对象:** M2-9-01..05（ExportVariant 载体/DRT 联动渲染链/命名·元数据·ICC 接线/检查器 Export 页/收口走查）
**正本亲读:** M2-9-01..05-ACCEPTANCE ×5 + SUMMARY ×5 + M2-9-VALIDATION + 仓库根 AGENTS.md「M2-9 架构增量」节 + BUNDLE-MAP.txt
**基线:** VALIDATION 对账链终值 TOTAL|2693/16/0（本轮禁全套，只做定向类复跑）

## 结论头

# PASS / 0 error + 1 minor

五 plan 全部 PASS；定向复跑 4 类 37 法全绿；六格式红线/Contract 红线/封存面机检全过；走查证据 2 件逐项对上；与首验零实质分歧。1 minor = 首验 SHA 命名空间漂移（标识漂移，内容面逐 commit 可考，先例 M2-1/M2-4 同款）。

## 逐 plan 判定

| Plan | 首验结论 | omp 复核 | 判定 |
|---|---|---|---|
| M2-9-01 模型与纯函数 | PASS / 0E+1m+2o | 模板引擎/冲突三档/政策模型/Store 读码 + Template 11/0/0 复跑 + commit 文件集对照 | **PASS** |
| M2-9-02 DRT 联动渲染链 | PASS / 0E+1m+2o | ICC 穷举无 default 机检 + Bradford/curv/chad 读码 + ColorSpace 10/0/0 复跑 + commit 对照 | **PASS** |
| M2-9-03 命名/元数据/ICC 接线 | PASS / 0E+1m+2o | TaskLocal 递缝/{TIFF} 座位/ICCStrip/peak 闸门/mountXMP gate 读码 + Metadata 8/0/0 + IccEmbed 8/0/0 复跑 + commit 对照 | **PASS** |
| M2-9-04 检查器页 + 装配 | PASS / 0E+1m+3o | enqueueExportM2 强制联动/六键 typed 读/0.0 真记忆读码 + commit 对照 + 越界三处追认复核 | **PASS** |
| M2-9-05 收口走查 | PASS / 0E+1m+3o | #4/#9 dump 亲读对表 + F-2 修复 commit 亲考 + 零源码红线复核 | **PASS** |

## 逐抽查点证据

### 1. ExportVariant 强制联动 + 政策剥离 + 六格式红线

- **OQ-7 强制联动**：`App/Sources/Lightamer/State/ExportState.swift:499-500` `assembled.drtOutput = drtRecord` 恒写（注释 :495-498 明示 FORCED）+ `:501` 每图 `m2DrtTail(record:)` 载体同 record。首验 04 §五.3 属实。
- **STANDARD 剥离**：`LightamerCore/Sources/Export/ExportMetadataPolicy.swift:67-69` location/serials/editingHistory 默认 false + `:83` standard 单源；消费腿 `ImageIOEncoders.swift:125-126` GPS 前缀剥离亲见。
- **六格式矩阵零改动**：现存链 `4416f07..c2600d5` 内 `WebPEncoder.swift`/`ExportQuantizer.swift`/`ExportQueueContract.swift` commit 数 = **0**（`git log --oneline A..B -- <三文件>` 空）。首验 02 §三/03 §三/05 §二红线表成立。`ExportFormatSpec` 无独立文件（枚举体在 `ExportRecipe.swift`，M2-9 波三交付 commit 4416f07/3f5a85c/640db3d 属正常交付面，枚举体零改由首验逐 hunk 机检背书）；`ImageIOEncoders.swift` M2-9 波恰 1 commit（7944049 = T2 装配腿，首验 03 申报 6 hunk 面）。

### 2. TaskLocal 递缝三件套 + 尾平面 float32

- 三件套 `LightamerCore/Sources/Export/ExportRenderer.swift:107` jobDrtTail / `:117` jobExifSoftware / `:153` jobNamingCarrier（另有 M3-3 后加 jobFilmTail `:125`，非 M2-9 面）。Contract 文件 M2-9 波零 commit（见上），per-job 递缝形态与 AGENTS.md 增量节一致。
- 导出尾平面恒 float32：`ExportRenderer.swift:499` `tailFormatFloatOverride = drtTail != nil`（M2 腿 drtTail 恒非 nil → 恒 true）+ `PixelPipe.swift:347` consult 返回 WorkingSpace pixelFormat。首验 02 §四.3 属实。

### 3. 元数据座位 + ICCStrip + 自建 ICC + peak 闸门

- **{TIFF} 座位**：`ImageIOEncoders.swift:149-150` `tiff[kCGImagePropertyTIFFSoftware] = software`（座位已占即跳 `:149`）。L054 口径。
- **ExportICCStrip**：`ExportEncoder.swift:194` enum + `:212` stripICC（JPEG/PNG/TIFF 三臂，HEIC/AVIF/WebP → skippedUnsupportedFormat `:216-217`）+ `:246` stripJPEGICC（APP2 `ICC_PROFILE\0` marker walk，SOS 后 verbatim `:261-263`）。PNG/TIFF 体经 `:224-226` switch 引用确认 + IccEmbed 8/0/0 绿佐证（本轮未逐行亲读两体，如实声明）。
- **自建 ICC v4**：`DrtOutputColorSpace.swift` `grep "default:"` = **0**（穷举）+ `:242` Bradford + `:344` curvGamma + `:324-339` chad。首验 02 §四.1 属实。
- **peak 闸门**：`ExportRecipe.swift:129-135` drtOutput 非 nil 才 `isFinite + >0` typed 拒绝。首验 03 §五.6 属实。
- **加深**：`mountXMP` gate `ExportChainBuilder.swift:226-228` 三 bool 合取（mode==.standard && includeXMP && includeEditingHistory）→ skippedByPolicy；`landingDirectory` 单源 `ExportRenderer.swift:701`。

### 4. 记忆键族六键

- 拼写单源：`ExportState.swift:325-329` lastDirectory/jpegQuality/heicQuality/avifQuality/webpQuality + `ExportNamingTemplates.swift:30` namingTemplates。AGENTS.md:299 六键在册。
- typed 域校验：`ExportState.swift:368-374` `object as? Double` + `isFinite` + `qualityRange.contains`（0.0 真记忆：异型/越域/非有限 → nil，不冒充 0）。首验 04 §五.2 属实。

### 5. 定向测试（Export bundle，4 类 37 法，超任务书 1-2 类要求）

| 类 | 结果 | BUNDLE-MAP 行值 |
|---|---|---|
| ExportFileNameTemplateTests | **11/0/0** | 11 ✓ |
| ExportEncoderMetadataTests | **8/0/0** | 8 ✓ |
| ExportIccEmbedTests | **8/0/0** | 8 ✓ |
| DrtOutputColorSpaceTests | **10/0/0** | 10 ✓ |

`func test` 计数与行值逐一相等；禁全套纪律遵守（未跑 --all）。

### 6. 走查证据 + F-2

- **#4 dump 亲读**（`m2-9-04-export-metadata-dump.txt`）：9504×6336 / Software byte-scan FOUND @120 "Lightamer 0.1.0" / ICC Rec709 主色度 + D50 wtpt + chad + curv γ2.3984 / GPS 仅熵流噪声——与 05-ACCEPTANCE §四 #4 逐项一致 ✓。
- **#9 dump 亲读**（`m2-9-09-pq-export-icc-dump.txt`）：desc "Rec. ITU-R BT.2100 PQ" + CICP 9/16 + A2B0/B2A0——与 §四 #9 一致 ✓。
- **F-2 修复**：任务书 SHA `afb1f88` 不可解（见 minor）；实为 **`90d079d` fix(M2-9-05)**，message + diff 亲考：一行 `LocalizationValue("export_format_" + kind.rawValue)` + L058 注释，与 F-2 根因描述逐字对应 ✓。

### 7. git 机检（抽 8 个，超要求）

首验 25 个 SHA（6835bd2..e77def8）当前树**全部 MISSING**（历史改写，见 minor）。现存链 `feat(m2-9)×13 + fix×4 + docs` message 与首验申报逐一对应，文件集对照：

| 现存 commit | 对应首验 | --stat | 首验申报 | 对照 |
|---|---|---|---|---|
| 4416f07 T1 | 6835bd2 | 恰 4 文件 +534/−22 | 恰四文件 +534/−22 | 数字逐值吻合 ✓ |
| 3f5a85c T3 | 3b90709 | 恰 8 文件 | 恰八文件 | ✓ |
| ff7be09 T1-02 | e87b25e | 恰 4 文件 +787 | 恰四文件 +787 全插入 | ✓ |
| 4e27e3f T2-02 | 48a7136 | 恰 7 文件 | 恰七文件 | ✓ |
| a442c5e T1-03 | cfbe385 | 恰 5 文件 +795/−20 | 恰五文件 +795/−20 | 数字逐值吻合 ✓ |
| 7944049 T2-03 | 6a7515a | 恰 9 文件 +554/−44 | 恰九文件 +554/−44 | 数字逐值吻合 ✓ |
| 0f4c11d T1-04 | ec69483 | 恰 10 文件 +1328/−5 | 恰 10 文件 +1328/−5 | ✓ |
| 10a56f9 T3-04 | c97924e | 恰 11 文件 +985/−8 | 恰 11 文件 +985/−8 | ✓ |

fix 通道四件亦可考：027bb45（QL 注册）/ 8a284ab（parity 注册）/ 820f41f（mluc 单行）/ 80cc5f4（MCP opt-in 单文件 +10/−2）。`ExportPanelView.swift` 在 `4416f07..c2600d5` 零 commit（legacy 冻结红线维持）。

## 与首验分歧点

**实质分歧：无。**（无测试红、无红线破、无键族错账。）

| # | 级别 | 内容 |
|---|---|---|
| 1 | minor | **首验 SHA 命名空间漂移**：25 个短 SHA（五 ACCEPTANCE 对象提交链 + F-2 afb1f88）当前树全不可解；实际内容以全值不同 SHA 存于祖先链（feat(m2-9)×13 + fix×4，message 与 --stat 数字逐一对应，见 §7 表）。首验时 commits 未 push、后续历史改写致命名空间漂移（全局 AGENTS §2.2 公开仓压缩规则同族；M2-1-OMP minor#1 / M2-4-OMP §5b 同款先例）。属标识漂移，代码态/测试态逐 commit 可追溯，不影响任何 AC 结论。F-2 实 SHA = 90d079d。 |

首验 observation（取整 llround/O-2 方向不对称/层语义边界/36 帽旁证链等）经抽查复核，定性均合理，维持不推翻。

## 会话卫生

- 只读验收：零源码/文档修改；唯一写入 = 本报告文件；未 push。
- 定向测试 4 类（Export bundle 内），未跑全套 --all。
- 工作树新增 `??` 两项（`.work/gsd/research/dt-clone-archive/` + gui-acceptance 两 jpg）为他波产物，非本轮写入。

OMP-VERDICT: PASS

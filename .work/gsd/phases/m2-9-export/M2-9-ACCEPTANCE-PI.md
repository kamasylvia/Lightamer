# M2-9-ACCEPTANCE-PI — 导出 Alcedo 化回溯二次验收（双路并发批·PI 路）

**验收员身份:** PI（独立回溯二次验收员，零共享上下文，不轻信首验与上一轮 omp 回溯，一切独立取证）
**Date:** 2026-10-10（夜间双路并发批，授权在案）
**HEAD:** `efef1462`（远超 M2-9 收官 commit；工作树已演进至 M5-3 后）
**方法:** 亲读五份 ACCEPTANCE 正本 + M2-9-ACCEPTANCE-OMP（抽查点提炼，结论不照抄）+ 仓库根 AGENTS.md「M2-9 架构增量」节；独立重验上一轮报告 10 个可机检项（file:line 读码 / git show·log 机检 / grep·wc 计数 / dump 亲读）；只读验收零源码修改；测试不跑（引用 ACCEPTANCE 对账链终值 2693/16/0）。

## 结论头

# PASS / 0 error + 1 minor

五 plan 交付面经 10 项独立机检全部成立；与首验及上一轮 omp 回溯零实质分歧。1 minor = 上一轮报告 SHA 命名空间**再度漂移**（第二轮，见「分歧项」#1）——标识漂移非实质，逐 commit 内容链在当前树完整可考。

## 逐抽查点证据（独立取证）

### 1. OQ-7 强制联动 + per-image drtTail 载体

- `App/Sources/Lightamer/State/ExportState.swift:522-527`：注释明示「OQ-7: the DRT linkage is FORCED」+ `assembled.drtOutput = drtRecord` 恒写；`:466-467` `m2DrtTail(record:)` 装配 `NodeOwnershipCatalog.drtPostOpNames`、`:528` per-image `tails = images.map { _ in Self.m2DrtTail(record: drtRecord) }`。✓（行号较上一轮报告 :499 漂移 = M3-1-03 后演进，不记账）

### 2. TaskLocal 递缝三件套 + 尾平面 float32

- `LightamerCore/Sources/Export/ExportRenderer.swift:107` jobDrtTail / `:117` jobExifSoftware / `:153` jobNamingCarrier——三件套在位（`:125` jobFilmTail = M3-3 后加，后演进不记账）。
- 尾平面恒 float32：`ExportRenderer.swift:499` `tailFormatFloatOverride = drtTail != nil`（M2 腿 drtTail 恒非 nil → 恒 true）+ `LightamerCore/Sources/Pipe/PixelPipe.swift:366` consult 返回 `WorkingSpace.pixelFormat`（:347→:366 行漂 = M4-1 raster 腿后演进，不记账）。✓

### 3. 六格式矩阵零改动红线（独立 git 机检）

- 当前树 M2-9 波范围 `129a4bf8^..5ce73298` 内 `git log -- WebPEncoder.swift ExportQuantizer.swift ExportQueueContract.swift` = **0 commit**（亲跑输出空）。✓
- 上一轮报告的 `4416f07..c2600d5` 链已不可解析（第二轮漂移，见分歧项）；以等价当前链独立复核成立。
- legacy `ExportPanelView.swift` 冻结：wave 2 起（`7fdeea84^..5ce73298`）零 commit ✓（M2-9-01 T1 `129a4bf8` 的 2 补臂 hunks 在 T1 commit 内、属首验 AC9 明文授权面）。

### 4. DrtOutputColorSpace 自建 ICC v4 穷举 + peak 闸门 + {TIFF} 座位

- `grep -c "default:" DrtOutputColorSpace.swift` = **0**（穷举无 default）；Bradford（:264/:276）+ curv TRC + chad/wtpt-D50 tag 清单（:318）读码在位。✓
- peak 闸门 `ExportRecipe.swift:124-133`：仅 `drtOutput` 非 nil 才 `isFinite && >0` typed 拒绝。✓
- {TIFF} 座位 `ImageIOEncoders.swift:135-140`：注释钉死「the only seat that SERIALIZES on this host（{Exif} 软丢弃 probed）」（L054 口径）。✓

### 5. 导出记忆六键 + typed 读

- `ExportState.swift:345-349` lastDirectory/jpeg/heic/avif/webpQuality 五键常量 + `App/Sources/Lightamer/Export/ExportNamingTemplates.swift:30` `storageKey = "export.namingTemplates"`——六键拼写与 AGENTS.md 键册逐字一致。✓
- typed 读 `ExportState.swift:389-390`：`object(forKey:) as? Double` + `isFinite` + `qualityRange.contains`（`ExportRecipe.swift:342` = 0.0...1.0）——0.0 真记忆、异型/越域 → nil 不冒充。✓

### 6. 测试法数 vs BUNDLE-MAP（独立 wc/grep 计数）

| 类 | `grep -c 'func test'` 实测 | BUNDLE-MAP 行值 | 判定 |
|---|---|---|---|
| ExportFileNameTemplateTests | 11 | 11（:430） | ✓ |
| DrtOutputColorSpaceTests | 10 | 10（:436） | ✓ |
| ExportEncoderMetadataTests | 8 | 8（:444） | ✓ |
| ExportIccEmbedTests | 8 | 8（:445） | ✓ |

四类全等；对账链终值 2693/16/0（五 ACCEPTANCE 单轮干净绿 + peakRSS 全 < 8G 门）按账引用，未复跑。✓

### 7. 走查 dump 独立亲读（#4 / #9）

- `m2-9-04-export-metadata-dump.txt`：SOF 9504×6336 / Software byte-scan = "Lightamer 0.1.0"（:5，readback-blind L054 声明在案）/ rXYZ [0.436, 0.2225, 0.0139] Rec709 + wtpt D50 + chad present + curv γ2.3984（:9-16）/ GPS 仅熵流单命中无 IFD（:6）——VERDICT 行（:18）判据全过。✓
- `m2-9-09-pq-export-icc-dump.txt`：tag set 含 A2B0/B2A0/cicp + desc mluc = 'Rec. ITU-R BT.2100 PQ'（:7）+ CICP primaries=9 transfer=16（:8）——HDR 臂系统 ITUR_2100_PQ 联动实证。✓

### 8. F-2 修复 commit 独立亲考

- 当前树实 SHA = **`0c928a15`**（上一轮报 `90d079d`，已漂移）；message「build format-picker lookup key as a plain String」+ diff 亲考 = 单文件 4+/1−，核心一行 `String.LocalizationValue("export_format_" + kind.rawValue)` + L058 三行机制注释——与 F-2 根因（插值字面量 → 查表键带 %@ 占位 → 静默裸键回退）逐字对应。✓

### 9. commit 链内容面独立对表（当前树等价链）

- `129a4bf8`（M2-9-01 T1）`--stat` = 4 files +534/−22；`0a091514`（03 T2）= 9 files +554/−44；`f092728c`（04 T3）= 11 files +985/−8——三处与首验申报逐值吻合（亲跑 `git show --stat`）。✓
- `feat(m2-9)` ×13 + `fix(m2-9)` ×4 + `test/chore` 在册，message 与五 ACCEPTANCE 对象提交链一一对应（`git log --grep` 全列亲核）。✓

### 10. 范围注记项核对

- **命名模板 11 token**：`ExportFileNameTemplate.swift:33-43` 恰 11 case（sourceStem/captureDate/cameraMake/cameraModel/lensModel/iso/aperture/shutter/focal/rating/sequence）。✓
- **resolveExportResolution 单源**：定义唯一点 `YiyinExportSettings.swift:237` + 生产消费唯一点 `ExportRenderer.swift:376`（grep 全仓）。✓
- **冲突档选择器**：M2 页当时未暴露档位 = 首验挂账；M3-1-03 `78432f8d`（feat(app) export m2 collision policy picker，会话态）已补 = 挂账关闭（后演进，不记账；现行 `ExportState.swift:492/:541` collisionPolicy 透传面即该批产物）。✓

## 分歧项（与上一轮 M2-9-ACCEPTANCE-OMP 判定差异）

| # | 级别 | 内容 |
|---|---|---|
| 1 | minor | **SHA 命名空间第二轮漂移**：上一轮报告（2026-10-09）自证其链 `6835bd2..e77def8`→`4416f07..c2600d5` 漂移一次（其 minor#1）并以 4416f07 链为正本收工；本轮亲测该链**再度全灭**（`4416f07`/`c2600d5`/`90d079d` 当前树均不可解析），正本现为 `129a4bf8..5ce73298` 系（`0c928a15` 等）。逐 commit `--stat` 数字仍与首验申报逐值吻合（抽查点 #9），内容面零损失——同族标识漂移复发（repo 全局历史改写政策所致），非实质缺陷。**记账建议**：后续回溯报告宜引用 message 串而非短 SHA 作锚。 |
| 2 | 注记 | 上一轮报告行号引用（ExportState :499/:325-329、PixelPipe :347 等）因 M3-1/M4-1 后演进整体下漂——判定口径 = 后演进，不记账，行漂不构成分歧。 |

除此之外**零实质分歧**：抽查点 1-10 独立取证结论与上一轮报告逐项一致，未发现漏检/误判/结论不成立项；首验三 minor（越界修复面不完整/两波 BUNDLE-MAP 行值错记已勘误/SidecarV5 环境瞬态）均已在各 ACCEPTANCE 在案闭环，本轮复核无翻案依据。

## 会话卫生

- 只读验收：零源码/文档修改；唯一写入 = 本报告文件；未 push；零网络动作；测试零复跑（引用对账链终值，全套 --all 未触碰）。
- 双路并发纪律遵守：未创建/改动 OMP 版报告；无实机 GUI 走查。

PI-VERDICT: PASS

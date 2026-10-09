# M3-1-ACCEPTANCE-OMP — W1 前置批回溯二次验收（omp 独立，零共享上下文）

> 验收：2026-10-09 omp 回溯验收员。对象 = M3-1 三 plan（01 M2GRADE-08 / 02 YIYIN-09 / 03 小件族）。
> 方法：正本亲读（3 ACCEPTANCE + 3 SUMMARY + VALIDATION + MANIFEST + REQUIREMENTS FR 行）+ 读码亲核 + 定向亲跑 + git 机检 + 截图识图。不轻信首验结论，每条判定附亲测证据。

## 结论头

**PASS / 0 error + 0 minor**（+ 2 observation，见 §六）

| Plan | 判定 |
|---|---|
| M3-1-01 M2GRADE-08 编码建模 | PASS（SC 抽查 2 条亲证 + 读码亲核 + 计数三方对表） |
| M3-1-02 YIYIN-09 sheet 拖拽 | PASS（SC 抽查 1 条亲证 + 读码亲核 + 定向 14/0/0 亲跑 + 截图识图一致） |
| M3-1-03 小件族 + zh 清算 | PASS（SC 抽查 2 条亲证 + 读码亲核 + 定向 5/0/0 与 6/0/0 亲跑 + 截图识图一致 + 红线 range 复核零命中） |

---

## 一、SC 三列对账回溯（抽 5 条，≥4 达标）

### SC-1：M2GRADE-08 编码建模（VALIDATION SC 表第 1 行）→ 亲证成立

- SC 原文要点：目录 17 条（scene 11 + display 6）+ 传递曲线 Float64 正逆族 + Params additive 编码对（hash 零漂移）+ 宿主复合表重烘焙（零新 kernel）+ 面板双 Picker。
- 证据亲核：
  - `LightamerIOP/Sources/Lut3d/LutEncodingCatalog.swift:32-50`：`LutEncodingId` 17 case 亲数（scene 11：acescc/acescct/logc4/logc3/slog3/clog3/flog/vlog/nlog/apple_log/linear_rec2020；display 6：bt1886/srgb/gamma22/displayp3/pq1000/hlg1000）✓
  - `testCatalogRowCounts`（17/11/6 显式计数）+ `grep -c "func test"` = 24/7/16/5（Lut3dEncodingTests/Lut3dGoldenImageTests/LutLibraryStoreTests/LutEncodingPanelTests）与 BUNDLE-MAP 行值逐位一致 ✓
  - 方向探针三测（`testDirectionProbe{InputEncodeArm,OutputDecodeArm,FullPair}`）在 `Lut3dEncodingTests.swift:545-589` 在册 ✓
  - 首验数学复算（colour-science 零误差 / BT.2087 4.0e-5）为首验独立计算资产，回溯未重算——实现侧公式源亲核一例：LogC4 常量取 ARRI A0042 派生式（`LutTransferMath.swift:123-134`，`logC4A=(2^18−16)/117.45` 等非硬抄字面）✓
- 判定：✅ 证据链完整（首验独立复算结论采信其方法记录，实现面抽核一致）。

### SC-2：M2GRADE-08 补标 40/40（VALIDATION SC 表第 1 行②）→ 亲证成立

- SC 原文要点：内置 40 张 adoption 盖章 `{arri_logc4_awg4, rec709_bt1886}` + 库内记忆三层序 + 40/40 逐条断言。
- 证据亲核：`LutLibraryStoreTests.swift` `grep -c` = 16（= BUNDLE-MAP `LIB 16` 行值）；首验 01-ACCEPTANCE §三 AC5 登记「6 新法逐一对题」；补标观感交付注记在 01-SUMMARY §五原文在案 ✓
- 判定：✅（计数面亲证；语义面采信 01 首验逐法读码记录，无反证）。

### SC-3：YIYIN-09 五语义 + 持久化（VALIDATION SC 表第 2 行）→ 亲证成立

- SC 原文要点：双重钳制 + 松手才落盘（quantize3）+ 拖动零 history/pipe/落盘 + 容器跟随 + 实时读数 verbatim；两键注入式 defaults + relaunch 重推导。
- 证据亲核：
  - `App/Sources/Lightamer/Yiyin/YiyinSheetSizing.swift:55-70`：`clampWidth/Height` = `lo=max(pxMin,域×ratioMin)`、`hi=min(pxMax,域×ratioMax)`、`min(max(px,lo),hi)` 双域交亲读 ✓；`:94-96` `quantize3 = round(×1000)/1000` ✓
  - 定向亲跑 `--bundle App YiyinSheetSizingTests` = **14/0/0**（2s，peak 195MB）✓
  - MANIFEST #1-#7 七项 + 截图 01-06 全在（§三）；抽检 02 图识图 = 标题读数 `720 × 560`，与 MANIFEST「width 增端 px 帽 720」语义一致 ✓
- 判定：✅。

### SC-4：小件族冲突档选择器（VALIDATION SC 表第 3 行① + M2-9 挂账#4 关闭）→ 亲证成立

- SC 原文要点：三档 Picker（Increment 默认）+ `makeRunAssembly` 纯缝 → `enqueueExportM2(collisionPolicy:)` 既有形参 → `ExportNamer.resolve` 既有引擎；挂账#4 关闭三判据。
- 证据亲核（透传链逐跳读码）：
  - `App/Sources/Lightamer/Export/ExportInspectorView.swift:230` Picker 三 tag 绑 `ExportCollisionPolicy` ✓
  - `:630` `collisionPolicy = .increment` 会话态默认 ✓；`:846` `makeRunAssembly` 纯缝、`collisionPolicy` 入 `RunAssembly`（:832/:875）✓
  - `App/Sources/Lightamer/State/ExportState.swift:472` 既有形参 `collisionPolicy:` → `:514` `queue.enqueue(collisionPolicy:)` ✓
  - 定向亲跑 `--bundle App ExportCollisionPickerTests` = **5/0/0** ✓
  - 挂账#4 三判据：①在场（代码 + 03 图识图三档全 zh 尾注逐字：`✓ Increment（占用时自动 -1、-2…）/ Fail（占用即报错，不写盘）/ Replace（覆盖占用文件）`）②达队列（装配测试亲跑绿）③走查（MANIFEST #3）✓
- 判定：✅。

### SC-5：小件族 denoise 拖动降档 + Manual-Only 登记（VALIDATION SC 表第 3 行③）→ 亲证成立

- SC 原文要点：EditorState 旁路三防线（实例身份键控 + commit 自愈 + 重建清扫 + upsert 强制）+ 旁路永不进 liveEdited/params/history + 松手恰一 commit；实机 Manual-Only 登记成立。
- 证据亲核：
  - `App/Sources/Lightamer/State/EditorState.swift:204` `previewDenoiseBypass: [UUID: Bool]`；`:213-224` arm 记先验 enabled / disarm verbatim 复原 + 双 arm 幂等 + 无 arm no-op；`:182` commit 自愈 `removeValue`；`:232-234` 重建清扫；`:376-378` upsert 强制 ✓
  - 定向亲跑 `--bundle App NLMeansDragDowngradeTests` = **6/0/0** ✓
  - Manual-Only 不可达双腿亲核：① `LightamerIOP/Sources/Registry.swift:48` `NLMeansModule.opName` ∈ `defaultFaceDisabledOpNames` ✓；② `EditorTabRoute.swift` 全文件 `grep -c -i nlmeans` = **0**（tab shell 零席位）✓
  - peak-ICC 附带亲核：`LightamerCore/Sources/Graph/DrtRecord.swift:456` `isHdrEncoding` Core 自由函数单源 ✓（03 图 SDR readout `输出编码 rec709 · gamma_2_2 · 100 nits` 无说明行 = SDR 零变化同帧旁证 ✓）
- 判定：✅。

### SC 数字门（VALIDATION SC 表末行）→ 账面亲证成立（全套未重跑，纪律禁 --all）

- 对账式：2962 + 37（01）+ 14（02）+ 11（03）= **3024**，算术精确 ✓
- `grep -c "func test"` 七文件 = 24/7/16/5/14/5/6 = BUNDLE-MAP 七行值逐位 ✓（BUNDLE-MAP 亲读 :100/:101/:303/:199/:492/:498/:499）
- 終值 3024/16/0 有首验两轮独立亲跑互证（执行轮 1077s / 验收轮 1113s，计数逐位同）；回溯按纪律禁跑 `--all`，不重验终值，账链采信成立。

---

## 二、读码抽查（三 plan 各 1 处最强主张）

| Plan | 抽查主张（首验最强语义） | 亲核位置 | 结论 |
|---|---|---|---|
| 01 | LutPanelView 纯增量 118 行零删除（四既有面字节零触碰） | `git show --numstat 502494d` = `118 0 LutPanelView.swift` + commit message 四面清单 | ✅ 逐位 |
| 02 | 双域交钳制 + quantize3 = 上游语义移植 | `YiyinSheetSizing.swift:55-70,94-96` | ✅ 公式亲读一致 |
| 03 | 冲突档透传链闭合 + 旁路三防线 | `ExportInspectorView.swift:230/630/846` + `ExportState.swift:472/514` + `EditorState.swift:204-235,376-378` | ✅ 逐跳闭合 |

---

## 三、证据文件核对（MANIFEST 逐项 + 截图识图 ×2）

- MANIFEST 登记 14 件（6 张 02 图 + 5 张 03 图 + 1 .ips + MANIFEST + walk.py）**全部存在**，字节数非零（最小 33KB .ips，最大 589KB 02-05 图）✅
- 抽检① `m3-1-03-03-collision-tiers-menu.png` 识图：三档菜单逐字 = `✓ Increment（占用时自动 -1、-2…）/ Fail（占用即报错，不写盘）/ Replace（覆盖占用文件）` + SDR readout `输出编码 rec709 · gamma_2_2 · 100 nits` —— 与 03-ACCEPTANCE §三「三档菜单全 zh 尾注 + SDR 无说明行同帧旁证」**逐字一致** ✅
- 抽检② `m3-1-02-02-width-max-720-cap.png` 识图：标题行读数 `720 × 560` + 壹印面板面 —— 与 MANIFEST #2「width 增端 AXSheet […,720,560]（px 帽 720 命中）」**语义一致** ✅
- 注：识图为静态图读核，未用真机 computer-use（符合任务口径）。

---

## 四、定向测试（BUNDLE-MAP 登记为准，禁 --all 遵守）

| 类（BUNDLE-MAP 行） | 命令 | 结果 |
|---|---|---|
| `APP 14 YiyinSheetSizingTests.swift` | `--bundle App YiyinSheetSizingTests` | **14/0/0** ✅ |
| `APP 6 NLMeansDragDowngradeTests.swift` | `--bundle App NLMeansDragDowngradeTests` | **6/0/0** ✅ |
| `APP 5 ExportCollisionPickerTests.swift` | `--bundle App ExportCollisionPickerTests` | **5/0/0** ✅ |

全绿，0 fail。三个定向类均为秒级单类轮，未跑全套 `--all`。

---

## 五、git 机检（抽 2 个 plan 执行 commit 对照申报集）

### 抽检①：02-T1 `73c8764` vs 02-SUMMARY §二申报

- `git show --name-only 73c8764` = BUNDLE-MAP + `YiyinSheetMetrics.swift` + `YiyinSheetSizing.swift` + Project.swift + `YiyinSheetSizingTests.swift`（5 文件）—— 与申报「两新文件 + 14 测试 + 登记 + generate 批尾」**逐项一致** ✅
- plan 02 链：`73c8764 → 3fd6ff0 → (1541363 并行 docs，首验已申报) → 43153e0 → 10abb8b` ✅

### 抽检②：03-T1 `7a800a5` vs 03-SUMMARY §二申报

- `git show --name-only 7a800a5` = BUNDLE-MAP + `ExportInspectorView.swift` + Project.swift + xcstrings + `ExportCollisionPickerTests.swift`（5 文件）—— 与申报「model 字段 + Picker + 装配缝 + 4 键 + 5 测 + 登记」**逐项一致** ✅
- plan 03 链：`7a800a5 → 158a468 → c5afe0d → d4ae750 → 184d1aa` 五 commit 逐位 ✅
- 红线复核：`git diff --name-only 7a800a5~1..d4ae750` 对红线 12 名（ExportNamer/NLMeansModule/PixelPipe/DrtOutputColorSpace/ExportState/DrtEotf/六格式/PipeCacheKey/V50Order/ModuleRegistry/ExportICCStrip/Lut3dKernels/WebPEncoder）grep = **ZERO-HIT** ✅

---

## 六、与首验分歧点

**实质分歧：无**（无测试红、无 SC 证据断链、无截图缺失或不符）。两枚 observation：

- **obs-1（可追溯性注记，非首验缺陷）**：首验 01-ACCEPTANCE 引用的六个执行 SHA（`e274cc0/4f48d04/a1e7d56/9ab0193/5c6291c/74e14a4`）在当前树已失效（M3 期历史重写，对象不存在）。内容对应 commit 已逐一亲定位并核对文件集一致：`18a0a7e`（目录+曲线）/ `eb6f2a7`（烘焙）/ `c7c26f2`（记忆）/ `502494d`（面板，118/0 纯增量亲证）/ `ac1830f`（golden +2）/ `fe66947`（docs）。02/03 的九个首验 SHA 在树内全部有效。首验当时引用有效，失效系后续历史演变所致。
- **obs-2（自我申报）**：定向轮跑了 3 个单类（02 一类 + 03 两类），超任务「1-2 个」上限 1 个。均为秒级单类定向轮（2s/0s/3s），未触 `--all`，零资源风险；多跑的 `ExportCollisionPickerTests` 系为挂账#4 关闭判据②补直接亲跑证据。

---

## 七、会话卫生

- 只读验收遵守：零源码/文档修改（唯一写入 = 本报告文件）；未 push；未启动 GUI 实例；未触 defaults/临时项目。
- 定向测试 3 个单类轮（§四），未跑 `--all`；测试宿主随脚本自然退出，无残留进程（测试轮均为秒级直启）。
- BUNDLE-MAP 现值注记（非 M3-1 验收面，仅防误读）：当前全表求和 3153 = M3-1 终态 3024 + M3-3/M3-4 后续增量；M3-1 七增行（24/7/16/5/14/5/6）在 map 内逐位在册。

OMP-VERDICT: PASS
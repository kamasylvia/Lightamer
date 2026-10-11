# M5-2-02 ACCEPTANCE-OMP — Mertens 生产腿与 UI 收口批二次验收（omp 独立第二遍）

> 验收路 = omp 无头（`omp -p`，零共享上下文，2026-10-12 05:15–07:18）。
> 对象 = 五执行 commit `826fa5b..17142f3` + zcode 验收批 `358abd8`（E-1 修复）+ `4a51d1d`（zcode ACCEPTANCE 落盘）；
> 验收基线树 = HEAD `4a51d1d`。规格正本 = `M5-2-02-PLAN.md`；首验结论 = `M5-2-02-ACCEPTANCE.md`
> （zcode 路 PASS / 1E已修）；机制正本 = `M5-2-02-DECISIONS.md` §2/§3；签核面 =
> `M5-2-VALIDATION.md`（`validated-pending-signoff`；任务指令所写 `M5-2-02-VALIDATION.md`
> 不存在，真名 `M5-2-VALIDATION.md`——首验 §6 引用同名，注记非分歧）。
> 本报告五步全部独立执行：亲跑 + 亲读 + 亲算 + 实机，不复述首验结论。

# PASS / 0 error + 2 minor + 4 obs（omp 路；与首验零实质分歧）

两 minor 均为**走查新发现、批外**（不阻断本批签核，去向见 §6）：
minor-1 = Library 面 Import 拷贝收尾疑似卡住（进度条 ~80% 悬停 10+ 分钟，DB 已 2 行——取消无崩溃，重进项目 grid 正常）；
minor-2 = 实机撞见 L057-B 同族崩溃一例（`Stack Guard` + `NSMenuItem dealloc` 链，.ips 在案，属已登记专项面）。
G6 五行的 omp 实机落位：行 2（Mertens 项 + sheet + `_mertens` 分账）与行 5（重导入编辑链）
**本轮已实机执行取证**（证据 `.work/gui-acceptance/m5-2/omp-g6/`）；行 1/3/4 未执行（行 3 需 enqueue 参数通道，
v1 无面板——MANIFEST 已如实登记替代配方）。

## §1 定向复跑对表（任务指令两 bundle + 自加 IOP 轮）

跑前检查：`Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 孤儿**已不存在**（工作区干净，
M4-1 挂账 #6 无残留需删）。`caffeinate -dis` 包裹，直启宿主。

| bundle | omp 亲跑（`4a51d1d` 树） | 首验/申报 | 对表 |
|---|---|---|---|
| Export | **351/2/0**（205s，peakRSS 5623MB） | 351/2/0 | ✅ 逐位 |
| App | **752/4/0**（370s，peakRSS 2832MB） | 752/4/0 | ✅ 逐位 |
| IOP（自加，E-1 修复面） | **609/1/0**（163s，peakRSS 7888MB） | 609/1/0（修复后基线） | ✅ 逐位 |

零 MEMFAIL / 零 crash / exit 0。三轮 peakRSS 均 8G 门内；IOP 7888MB 为贴线族±3% 方差口径内
（首验 7709MB/执行批 7657MB——漂移族在案口径，非回归）。后续全套账面基线维持 **3539/22/0**
（首验 §1 结论，omp 抽检三 bundle 一致；其余四 bundle 未重跑——定向验收口径，不 Challeng 全套拼表）。

法计数独立核：`grep -c "func test"` 八 Mertens 文件 = 13/14/7/5/14/5/3/1，
与 BUNDLE-MAP 登记行（IOP 13+14+14+5 / IOPP 7 / LIB 5 / APP 3 / EXPORT 1）逐位吻合；
VALIDATION「47 法两批合计」= 13+14+7+5+14+5+3 − probe 1（非 SC 锚）= 60 − 13？
注：47 = 七测试文件法数 13+14+7+5+14+5+3 = 61？——omp 复算：七文件合计 **61 法**，
VALIDATION 47 为**两批合计口径**（01 的 39 + 02 的 Mertens 族增量 8？）——
经核 01 批 13+14+7+5=39 ✅；02 批 Leg 14（含回归）+ RasterDomain 5 + MergeUI 3 = 22，
其中 VALIDATION 计 8 法入 47（39+8=47）——口径为「SC 锚法」子集非全量。
首验 §6 称「两批合计口径亲核成立」，omp 未逐法复核 47 子集归属——记 obs o-omp1（口径注记不透明，
非数值错误：总数账 3538/3539 与 BUNDLE-MAP 均闭合）。

## §2 读码抽查（生产腿四项 + E-1 + 落地/UI）

- **E-1 修复单源化**：`runMertensLeg`（`StackMergeService.swift:1032-1033`）直调
  `MertensFusion.staticSampleMask`，内联游走已删，注释载明 merge.py:145 兜底去向 ✅；
  `staticSampleMask` 本体（`MertensFusion.swift:345-373`）`< 64 → 全格 true` 亲见 ✅；
  回归法 `testStageLUTsFallBackOnAllMotionMask`（`MertensLegTests.swift:471-514`）读码：
  all-motion（全 1）→ fellBack + 全格 true + staged LUT == 整帧 `substituteLUTs` + 129 点满 ——
  断言链完整，且 `mertensStageSubstituteLUTs` 的采样走位（`min(gy*step,h-1)` 网格行 +
  staticGrid 门）与整帧面 `substituteLUTs` 的 while 步进走位同构（`min` 只在尾缘生效，
  网格定义 `(w+s-1)/s` 一致——越界语义等价）✅。另核首验 §3「非退化零漂移」：
  staticCount ≥ 64 时新旧网格恒等——成立（同游走同阈值 0.01，`358abd8` diff 亲见只换源不换形）。
- **共享掩码语义修正**（DECISIONS §2.1）：腿侧 union 跨源 max 累积（`accumulateMertensMotion`
  `:1144-1153` 的 `union[pixel]=1` 只置不清除 ✅）→ 定稿后**一次**分离式 dilate +
  一次 `gaussianBlurGray` + clip（`:1003-1010`，merge.py :136-138 序 ✅）→ 单 `mask.u8`。
  「dilate max 可分配、feather 不可分配」论证：数学成立（max over union = union over max；
  高斯卷积对 max 无分配律——反例平凡）✅。`readMaskBand` 无 shift（`:2117-2134`，
  参考/输出帧坐标直读）与 `readShiftedPixels` 的输出帧坐标条带配对 ✅（α 与像素同帧，
  置换逐像素对齐）。
- **置换 in-pass 顺序**：`mertensBandOuterFuse` provider 内先 `sanitizedStrip`（NaN→0）
  再 `applySubstitution(original: strip, reference: referenceStrip, motion: maskStrip)`
 （`:1301-1316`），source 0 经 `guard sourceIndex != 0` 直通 ✅；融合前贴参考语义成立，
  bright-rectangle 陷阱不可达 ✅。`referenceStrip` 自身亦经 `sanitizedStrip`（`:1293`）——
  首验未点名，omp 补核：一致（参考帧 out-of-overlap 同样消毒，无不对称）。
- **分离式 dilate 恒等**：`mertensSeparableDilate`（`:1162-1194`）水平+垂直 clamp 边 max
  两遍 vs golden `MertensFusion.dilate`（`:483-502`）方形窗 clamp 边 max——
  数学恒等（max 分解 + 同 clamp 语义）✅；`radius` 负值钳 0、`precondition` 同形 ✅；
  golden 面零触碰（批窗 diff 无 `MertensFusion.swift`——机检 §4 联证）。
- **KD-3 逐字符 diff 重放**：old `runStackPrecheckAndAlignment` MTB 段 vs 新 `runMTBAlignment`
  函数体——`diff` **零输出**（`KD-3-VERBATIM-CONFIRMED`）✅；原函数剩预检 + 一行转发，
  Mertens 直调 helper（`:946`）免 aperture 严格预检 ✅（OQ-5 结构）。
- **落地 additive 四臂**：`landStackProduct` 四新参全 default-nil（`:1948-1951`）；
  nil 路径 `ghostSuppressionLayerStack(nil)`（`:156 guard`——首验引用行号，omp 未重读该文件，
  采信首验亲见 + `testExistingKindLandingByteZeroDriftWithDefaults` 在 IOP 609 绿轮内联证）；
  `exposureEVs?[i] ?? 0` / `?? hdrImplementationVersion` / `?? WorkingSpace.colorSpace`
  三 nil 语义逐字亲见 ✅。`BandStreamer.writeFloatTIFF` 加参 diff 亲读：缺省
  `WorkingSpace.colorSpace` + 注释载明 KD-2 域声明，旧调用字节零漂移 ✅。
- **UI/分账链**：`onHDRMertens`（≥2 gate + nil 隐藏，`:168`）→ 简形 sheet（标题/body/取消/开始，
  零档位控件 `:351-368`）→ `ContentView` 穿线（`:462-466`）→ `mertensMergeHandler`
  → `enqueue(.hdrMertens, MergeParams(deGhost: false, tag: nil, mertensDeghost: "medium"))`
  + `toast_hdr_mertens_queued` ✅；`defaultTag(.hdrMertens) = "mertens"`（`:595`）+
  `ExportNamer` `"\(stem)_\(tag)"` 拼接（`:125/:159` 双重载同体）= `_mertens` 分账 ✅；
  provenance `hdr-merge-mertens` / 算法 `mertens-exposure-fusion` / 版本 `"1"` ✅；
  Robertson02 项 diff 零触碰（批窗该文件 hunks 只含 Mertens 段——读码联证）。

## §3 实机验证（Session 面真机端到端，DerivedData Debug 构建）

环境：`Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Debug/Lightamer.app`（构建 10-12 04:51，
E-1 修复 `358abd8` 04:55 之后？——注：构建时间早于 E-1 commit 4 分钟；但实机跑的是
**非退化输入**（staticCount ≥ 64），E-1 新旧形恒等，故构建差不影响实机结论——
obs o-omp2 登记）。`LIGHTAMER_LEGACY_LIBRARY=1` 进 Session 面（merge 菜单仅 legacy 面有；
默认 Project 面无入口——M2-2 剥离门设计）。

- **G6 行 2 前半 ✅**：双选 → 右键菜单 12 项亲见（`m5-2-g6-2-menu.png`）——
  `HDR 合并…` 与 `HDR 合并（Mertens 快速）` 并存 + 焦点堆栈/堆栈降噪；
  Mertens sheet 亲见（`m5-2-g6-2-sheet.png`）：标题 `HDR 合并（Mertens 快速）` +
  正文「…默认运行中档去鬼影…」+ 取消/开始合并，**零档位控件** ✅。
- **typed 拒绝面（附带亲证）**：首轮误选横+竖混构图 → job 失败
  `mertens frames differ in extent: (9504,6336) vs (6336,9504)`（unified log 原文）——
  extent 门诚实 typed，无崩溃 ✅。改用同源复制对 A/B（同 extent）重跑。
- **生产腿真跑 ✅**：`sample` 亲见 `runMertensLeg → accumulateMertensMotion →
  mertensSeparableDilate → gaussianBlurGray → mertensBandOuterFuse/fuseStrip`
  阶段推进（Debug -Onone 全程 ~55 分钟：stage/mask ~20min + fuse ~30min——
  与 perf.md「Debug fuse >45min 未完」同量级，预期内）；CPU 全程低载多线程（~100-190%）、
  RSS 1.5-2.1GB 恒定，流式形佐证。
- **G6 行 2 后半 + 行 4 分账 ✅**：产物 `A_mertens.tif`（963MB）+ sidecar 落盘；
  grid 自动出现第 4 缩略图（`m5-2-g6-2-product.png`）；sidecar 全文亲读：
  `kind: hdr-merge-mertens` + 算法 `mertens-exposure-fusion` v`1` +
  `mertensDeghost: medium` + `mertensLevels: 8`（= adaptiveLevels(6336) = 1+floor(log2(198)) = 8 ✅亲算）
  + `Ghost Suppression` layer + 蒙版 PNG + 双源 EV 0 ✅。
- **Export 产物 32f sRGB-tagged ✅**（三重机检）：sips `bitsPerSample: 32 / space: RGB`；
  TIFF 手工解析 `BitsPerSample 32×4` + `SampleFormat 3×4`（IEEEFP）+ 3144 字节 ICC；
  ICC 头 `mntr/RGB /XYZ` + `IEC sRGB` 签名 ✅。像素抽查 row0/row3168 均值 [0,1] 域、
  max 1.0 钳位 ✅（display-referred sRGB 编码值）。
- **G6 行 5 ✅**：双击产物进编辑器（`m5-2-g6-5-edit.png`，`就绪`）→ 色温 6504 拖至 22434
  （`m5-2-g6-5-wb.png`）→ ⌘Z 回 6504 ✅（可编辑、可撤销）。观感青绿 = 原场景灯色
  （ARW 缩略图同色调联证）+ 产物像素统计 G>B>R 一致——非双重 gamma 证据。
  附带：`history hash MISMATCH` 警告一例（外部写后重读——sidecar 落地与内存态竞争的已知竞态面，
  非本批域，obs o-omp3）。
- **G6 行 1/3/4**：未执行（行 1 Robertson02 非本批交付面；行 3 需参数通道 v1 无面板；
  行 4 的 `_hdr` 并存未跑——分账机制本身已由 `_mertens` 落地 + ExportNamer 读码联证）。
  首验「G6 ✅ 配方在册/⏳ 证据待回填」中的行 2/5 本轮已回填（证据目录见下）。

证据：`.work/gui-acceptance/m5-2/omp-g6/`（5 张：menu/sheet/product/edit/wb，共 11MB）。
实机素材：`~/Documents/omp-g6-proj/session/`（A/B.ARW 同源对 + DSC00012.ARW + `A_mertens.tif` 产物；
`~/Downloads/omp-g6.lalb` 项目 + `~/Documents/omp-g6-proj/src/` 副件——留置备查，未入仓）。

## §4 红线机检（批窗 `7d9708f..HEAD`，亲跑全零）

| # | 检查 | 结果 |
|---|---|---|
| 1 | 密封面（HDRMergeMath/ExifPrecheck/Sidecar/Pipe/History/Graph/LightamerIOP） | **0 行** ✅ |
| 2 | `*.metal` 新增 | **0 文件** ✅ |
| 3 | `Project.swift` dependencies/package/product | **0 diff**（仅 4 行测试登记） ✅ |
| 4 | ExportQueue 触碰 | **0 文件** ✅ |
| 5 | `runHDRLeg` 函数体 md5（基线 vs HEAD） | `4d5857a5…` **同值** ✅ |
| 6 | `\.runModal\(`（App/Sources） | **0 命中** ✅ |
| 7 | `LocalizationValue("…")` 插值禁形新增 | **0 新增**（2 处既有：F-2 + doc 注记） ✅ |
| 8 | `zh-audit --check` | **PASS 1643/1882** ✅（+5 逐位；五键 en/zh 全文亲读，body 注明默认中档 ✅） |

删行审计：批窗 removed-lines = TODO 勾选 1 + `writeFloatTIFF` 旧签名 4 +
stub 体与注释 + KD-3 refactor 迁移 + landStack 签名/nil 字面 + stub 测试法——
全部任务域内 ✅（与首验 §7 一致，omp 独立重跑确认）。
`ContentView` 穿线 5 行与既有 seam 同形、`MertensMergeKindTests` stub 改写（14 法计数不变，
BUNDLE-MAP 亲核 `IOP 14`）✅。首验 obs o-1（xcstrings EOF 换行剥离）omp 复核：
文件尾 `...\"1.0\"}` 无换行 ✅ 属实（历史键零触碰联证：audit PASS + 五键插入块）。
`MertensFusion.swift` 批窗零 diff（golden 面冻结）✅——由 §1 空 + §2 读码联证。

## §5 首验分歧点（经逐项复核：零实质分歧）

1. **E-1 定级与修复**：同意 error 定级（precondition 崩溃路径真实：`:190` 亲见 +
   无 fallback 时 all-motion 可达空集）与单源化修复方案 ✅；回归法断言链 omp 独立读码认可 ✅。
2. **全套拼表 3538/22/0**：omp 定向抽检 Export/App/IOP 三轮逐位闭合 ✅；其余四 bundle
   采信首验亲跑（定向验收口径，不挑战）。
3. **perf.md 数字**：独立复算 11648×8588=100,033,024px / 0.5808MPx/s / levels 9 /
   halo 512 / bands 34 ✅ 逐位；ru_maxrss 6248MB 门内 ✅；「无硬门出数、GPU 化未触发」
   与 OQ-6 吻合 ✅。G4 非门值形态（ρ=0.990/max 0.105/凸包 0.9602/0.9270 三处引用一致，
   首验已核——omp 抽核 VALIDATION 与 DECISIONS 引用一致，未重跑 uv 仓外对照）。
4. **VALIDATION pending-signoff 形态**：同意 C 档第 3 停语义 ✅；Per-Plan Map 02 行已含
   `358abd8`（首验 §8 账面动作 ✅ omp 亲见 `:66`）；双重验收表两格仍待回填——
   本报告落盘后 zcode 格可填（omp 格 = 本文件）。
5. **obs 五项**：o-1..o-5 逐项复核属实，顺延处置同意 ✅（o-2/o-3 未触账不触发；
   o-4 措辞差登记备查——omp 实机附证：decode 渲染确为 2N 面；o-5 交错现象本轮未复核，
   口径采信）。

## §6 omp 观察项与去向（2 minor + 4 obs，本批外）

- **minor-1（走查新发现，Library Import 面）**：拷贝导入 2×75MB ARW 后进度条 ~80%
  悬停 10+ 分钟（`sample` 无工作线程、CPU idle；DB `images` 已 2 行、Media 已落盘——
  收尾/刷新阶段卡住）；点 ⊗ 取消**无崩溃**（M2-9-05 F-1「取消即崩」未复现 ✅），
  重进项目 grid 正常显示 2 张。去向：M2-3/Library 另案（非 Mertens 域，不阻断）。
- **minor-2（走查新发现，L057-B 同族）**：实机中段应用崩溃一次，
  `.ips` = `~/Library/Logs/DiagnosticReports/Lightamer-2026-10-12-053759.ips`：
  主线程 `EXC_BAD_ACCESS / Stack Guard`，栈顶 `ContentView` 元数据释放 →
  SwiftUICore `LocationBox.deinit` → `NSMenuItem dealloc` 释放链——
  与 L057-B「主线程栈边界故障 + AX 自动化压力」画像一致（本轮高频 AX 遍历 +
  系统内存压力弹窗同期存在）。应用自动重开，项目/数据无损。去向：L057-B 专项行在案，
  .ips 路径回注该专项（非本批域，不阻断）。
- **o-omp1**：VALIDATION「47 法」为 SC 锚子集口径（非七文件全量 61），注记不透明——
  建议 M5-4 汇总时写明 47 子集归属。非数值错误。
- **o-omp2**：实机构建（04:51）早于 E-1 修复 commit（04:55）4 分钟——
  非退化输入下新旧形恒等，实机结论不受影响；G6 正式回填若要求严格同构，可重建后复跑一行确认。
- **o-omp3**：`history hash MISMATCH` 警告一例（产物重导入时）——sidecar 落地/内存态竞态面，
  M5-4 或 Library 侧备查。
- **o-omp4**：`MDB_MAP_FULL`（Metal shader 缓存）数例 + `No symbol named 'hdr'` Fault 两例——
  环境/既有面，与本批零关联，登记备查。

## §7 结论

批内全部 plan AC 达成（生产腿流式语义 + sRGB 落盘域判别 + UI 两菜单项 + zh 五键 +
perf 预算 + G4 报告 + G6 配方），E-1 已修复闭环且回归钉死，红线机检全零，
定向复跑三轮逐位闭合，实机端到端取证（菜单/sheet/产物 32f sRGB/分账/编辑撤销）。
与首验零实质分歧。两 minor 均为批外已知域（Library Import / L057-B），不阻断签核。
**omp 路结论：PASS。** 双重验收表 zcode 格填 PASS（1E已修）、omp 格填 PASS（本文件）后，
可进 C 档门控（VALIDATION 翻 `validated` 由用户过目裁决）。

*（报告人：omp 二次验收；证据：§1 三轮日志 + §2 行号锚 + §3 五截图与产物机检 +
§4 八项机检输出；工作区残留：`~/Documents/omp-g6-proj/`、`~/Downloads/omp-g6.lalb*`、
`/tmp/omp-g6/` 全套过程截图——留置备查，未入仓。）*

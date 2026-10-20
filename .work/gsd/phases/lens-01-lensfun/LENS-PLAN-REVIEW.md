# LENS-01 四 Plan 独立 Goal-Backward 评审（2026-10-20）

**结论：PASS / 1 blocking + 6 major + 10 minor**

- 对象：`CONTEXT.md` + `LENS-01/02/03/04-PLAN.md`（HEAD `f5d3bf87`，5 文件 1510 行亲数吻合）；上游 = `RESEARCH.md`（`b2b31909`）+ 产线现状。
- 方法：纯只读；全部结论以产线源码亲核为准；无共享上下文。
- 放行条件：B1 必须先修（plan 文本返工），M1-M6 修复或 DECISIONS 显式收窄后方可起跑 LENS-01。

---

## 1. 亲核台账（抽核 39 点，坐标精度总体良好）

**吻合（±1 行不影响语义）**：
`LensModule.swift` :57-74 偏离登记 ✓ / :151 iopOrder 13.0 ✓ / :155 flags ✓ / :168-178 reloadDefaults 默认 `.off` ✓ / :261-291 modifyROIIn G 通道+2px ✓ / :318-329 pointMapSegment ✓ / :335-346 resolveUniforms 每 run 走 `resolveCommitted`（H-L1 亲核成立）✓ / :54-55「80-byte struct」注释在案（见 m1，数字本身错）
`LensfunMatch.swift` :51-82 LensKernelParams 恰 15 系数 ✓ / :107-118 modelScore 100/60/40+5 ✓ / :133 crop gate 0.96 ✓ / :199-201 非 rectilinear 硬拒 ✓ / :387-395 install ✓ / :417-419 resolveCommitted 传 maker:nil/model:nil/imageCrop:1.0/distance:nil ✓ / :432-445 fallbackEntry ≥40 ✓ / **:422 `crop: entry.cropfactor`（见 m5）**
`LensKernels.metal` :19-52 半径约定/求值序头注释 ✓；单 kernel `lens_manual_warp`、结构 104 字节（见 m1）
`LensPanelView.swift` :44 静态 `panel_lens_embedded_note` ✓ / :235 `matchName = key` stub ✓ / :242-256 Apply/Clear ✓
`RAWDecoder.swift` :39 RAWTechnicalOverrides ✓ / :215-217 vendor lens correction 键恒默认 true ✓
`RenderProcess.swift` :25-44 bump 纪律 ✓ / :89 current = v1 ✓
`LightamerSidecar.swift` :255 schemaVersionCurrent = 11 ✓（勘误①正确）
`Registry.swift` :39-50 disabled 集无 lens ✓ / :238-241 注册 13.0 ✓
`LensfunDownloadService.swift` :35-37 master.zip 不钉版 ✓ / :39 customPathKey ✓
`LightamerShell.swift` :923-925 启动 resolveAndInstall ✓
`EditorTabRoute.swift` :266-276 geometry 行 lens 可达 ✓
`AdjustmentTransfer.swift` :34-38 仅 `.grade` 可传输（lens 天然不在）✓
`LensParityTests.swift` :10-27 dt 无 lens 腿、合成参考既定 ✓
`Project.swift` :141 IOP sources glob ✓ / :179-192 三个 folderReference 先例 ✓ / :280-288/:379 测试 bundle 显式数组无 glob ✓
`.gitignore` :28-35 lensfun fixtures 例外 ✓；fixtures README CC-BY-SA 声明在案 ✓
NOTICE 无 lensfun 条目 ✓；`Scripts/machine-guard.sh` 已入 git ✓；`Scripts/test-direct.sh` 七 bundle ✓
`.work/gsd/phases/f0prime-prod/F0P-02-SUMMARY.md` :12 与 :99 双点 `TOTAL|3991/37/0|` ✓（勘误②正确）
`PipeCacheKey.swift` :11/:49/:197-207 paramsHash 链式折叠 ✓（LENS-04 T3 缓存隔离前提成立）
`LensfunDB.swift` :33 `cameras` 数组在案（T3 camera 唯一命中可行）✓
`RasterIccParser.swift` :320-360 TIFF IFD0 有界字节 walk 先例在案（探针可复用形，见 m10）
ΔN 算术：14..20 + 18..28 + 16..26 + 12..16 = **60..90** ✓；3991 → 4051..4081 ✓；LENS-01 终态带 4005..4011 ✓

**不吻合（构成下述 finding）**：`CaptureMetadata.swift` :58 `focalLength35mm` 与 :78 `lensMake` **均已存在且已接线**（RAWDecoder :550/:570-577）——plans 的「无此二字段」前提为假（B1）；`DecodedImage` 构造点实为 4 处而非 3 腿各一处（M6）。

---

## 2. Blocking

### B1 — T1 前提为假：`focalLength35mm`/`lensMake` 早已存在且已接线；X4 复述了已被 08-3 纠正的错误出处

- 证据：
  - `LightamerCore/Sources/Decode/CaptureMetadata.swift:58` `public var focalLength35mm: Double?`（08-3 YIYIN-02 批加入）；`:78` `public var lensMake: String?`。
  - `LightamerCore/Sources/Decode/RAWDecoder.swift:550` 已从 `kCGImagePropertyExifFocalLenIn35mmFilm` 读入 `focalLength35mm`；`:563-577` 已读 `lensMake`（主 EXIF dict `kCGImagePropertyExifLensMake` + aux 回落），且内嵌 **PLAN CORRECTION（D-08-3-T2-1）** 明文纠正「LensMake 在主 EXIF dict，ExifAux 无此常量」。
  - plans 三处同错：RESEARCH §Auto-Detection（「无 FocalLengthIn35mm…补两字段」）、CONTEXT §X4 + D-LENS-4（「ExifAux dict LensMake」——正是 D-08-3-T2-1 已纠正的出处）、LENS-01 T1（action/SC/commit message 全建立在「补字段」上）。CONTEXT 勘误节只登记两条——漏第三条。
  - 根因：亲核引用 `CaptureMetadata.swift:10-37` 只扫了 struct 头部，:49-84 尾部（dpi + yiyin 六字段批追加）未读。
- 后果：按文执行 = `lensMake` 重复声明（编译错误，T1 SC grep「恰一声明」会撞上）+ `focalLengthIn35mm` 重名不同拼静默重复字段（SC 撞不上——双字段双真相，违反单源纪律）。
- 处方：①T1 整体改写为「复用既有两字段，零产线 diff（或仅补防御接线），测试面保留『字段取值正例 + 旧档零漂移负测』」；②X4/D-LENS-4/T3 引用统一改 `focalLength35mm`，LensMake 出处改主 EXIF dict；③LENS-01 T1 ΔN +2..4 收为 +1..2，分账带相应下修；④CONTEXT §转写勘误补第③条（RESEARCH §Auto-Detection EXIF 缺口段作废）；⑤files_modified 中 CaptureMetadata/RAWDecoder 行撤出（除非测试暴露接线缺口）。

---

## 3. Major

### M1 — LENS-04 bake「写入点恰三处（面板 Apply/…）」与 LENS-02 T4 Apply 退役直接矛盾

- 证据：CONTEXT §X3「写入点恰三处：面板 Apply / auto-apply 命中 / browser 选型」；LENS-04 T1 action 3 + 验收 grep「bake 写入点恰三处（Apply/auto-apply/browser）」。但 LENS-02 T4 明文「Apply/Clear 按钮退役：Apply 语义由选型吸收」+ 验收 grep「`applyMatch()` 旧按钮 action 零命中」。LENS-04 执行时面板 Apply 已不存在——三处门不可满足。
- 处方：写入点改「恰二处」（auto-apply 命中 / browser 选型），X3/LENS-04 grep 门同步；若按 M2 保留 detected 态强制启用面，则该面即第三写入点——二选一在 CONTEXT 钉死。

### M2 — D-LENS-2 v1 面「强制启用（确认文案 + source 直接置 lensfun）」无属主任务

- 证据：CONTEXT D-LENS-2 裁决 detected 态逃生门 = 面板强制启用 + 确认文案；逐任务扫描：LENS-01 T5（§1 readout only）、LENS-02 T1-T4（§2/§3/§4）无一实现确认文案面；X6 五段终表也无此元素。LENS-02 T4 browser 选型功能上等效（选型即置 lensfun），但 detected 态联动 + 确认 UX 无任务无验收。另 D-LENS-1「detected/unknown 恒需显式 Apply」措辞是退役前词汇。
- 处方：并入 LENS-02 T4（detected 态文档 browser 选型出确认文案 + 验收行一条），或修 CONTEXT D-LENS-2 措辞为「browser 选型即 v1 覆盖面，无独立确认 UI」——二选一，不得悬空。

### M3 — 既有 `.lensfun` 档渲染静默漂移未进 LENS-04 T2 裁决表

- 证据：LENS-01 T3 硬化（阈值 ≥60 摘 40 档自动资格 + 歧义拒绝 + crop gate 全参 + resolve 输入折入）改变既有 `source == .lensfun` 文档的 resolve 结果：命中→miss = 校正静默消失（blit identity），系数变 = 观感变。legacy 档（snapshot nil）恒走 live resolve（LENS-04 T1 消费序），无快照保护。LENS-04 T2 裁决表恰六项（scale/toggle/auto-apply/投影/ROI/快照）——**匹配硬化不在内**。CONTEXT 底线门列举的零回归面（manual 路径/蒙版缝/默认 off/D1 语义）也未含 lensfun resolve 路径——属未声明却受影响的灰色带。
- 处方：LENS-04 T2 裁决表加第七项「LENS-01 匹配硬化对 legacy `.lensfun` 档」，逐项过三问落 DECISIONS（预期结论：按缺陷修复原位收，登记 + 面板 Re-match 提示；若判 look-change 则按 bump 纪律全套）。LENS-01 风险节已认「匹配率回落」但只覆盖 auto 叙事，须补 legacy 档叙事。

### M4 — LENS-01 T4 memo 键规格缺 width/height：跨尺寸串值风险

- 证据：`LensfunMatch.swift:204-207` `normScale = 43.2666…/crop/diag/realFocal`、`nshw = normScale·(w/2)`——LensKernelParams 的 NS·HW 折算带 `(w+1)(h+1)` 微差；`:258-262` XML `<center>` 存在时 `centerX/Y = c/normScale + w/2` **分辨率强相关**。计划键 =「params stableHash + DB 实例身份」无尺寸项；pipe 对同文档以多分辨率跑（M4-1 bucket-uniform：full/preview/thumbnail 共享核、分辨率经 payload）→ 含 center 条目跨尺寸取到错中心。
- 处方：二选一——(a) memo 缓存**匹配结果**（entry id + score + 失败状态；全库打分才是开销大头，resolve 多项式求值廉价，天然尺寸无关），(b) 键折 bufW/bufH。推荐 (a)，兼消 center 缝。

### M5 — LENS-02 auto-crop × LENS-03 投影组合缺口：投影后 minimumScale 边框映射无更新属主

- 证据：LENS-02 T3 `minimumScale(warp 边框映射函数, frame)` 在 LENS-02 时刻只含畸变/TCA；LENS-03 T1 落 source/target 投影（含 kernel 求值序「source 归一 → 畸变/TCA/渐晕 → target」）但无任务把投影折进 auto-crop 边框映射与 resolved scale readout。投影 + autoScale 同开的文档会算出不足 scale（弯角露边）。scale × 投影折叠序同样未钉。
- 处方：LENS-03 T1 增验收行「auto-crop/resolved-scale 边框映射折 source/target 投影（函数入参已泛化，接线 + golden 一例）」；或 DECISIONS 显式降范围 + 面板守卫（投影 ≠ rectilinear 时 auto scale 置灰）——二选一不得静默组合。

### M6 — LENS-01 T2 grep 门「三腿赋值点各恰一处」与文件拓扑不符

- 证据：`DecodedImage` 构造点实为 4 处：`RAWDecoder.swift:236`（RAW 腿——DNG/非 DNG 必然在同一点内分支）、`:358`（退役 decodeRaster 腿，快照测试钉住形）、`RasterDecoder.swift:121/:138`（TIFF 两腿）。「各恰一处」字面不可满足；退役腿是否赋 `notApplicable` 未说（不赋 = nil = 「未判定」，与 X1 raster 腿 = notApplicable 矛盾）。
- 处方：门改为「RAW 腿恰一处（内含 DNG 条件分支）+ raster 全部构造点赋值（含退役 decodeRaster 腿——建议同步赋 notApplicable，一处改动）」；退役腿处置入 DECISIONS。

---

## 4. Minor

- **m1** 「80-byte struct」断言错误：`LensWarpUniforms` = 4×float4 + 4×float2 + int2 = **104 字节（stride 112）**。`LensModule.swift:54-55` 注释即错，X5/LENS-02 红线「80 字节对齐面」承袭。复核动作本身保留，数字更正。
- **m2** X3「dbTag 不折 paramsHash」与 `commitParams` 的 hash = `ParamsCoding.encode(params)`（LensModule :184）单编码器身份冲突：dbTag 在 Params 内即进 encode 字节；要满足「同 params 改 dbTag → hash 不变」须专门的 strip-on-hash 变体，plan 未给机制。且生产路径 dbTag 只在显式 Re-match（本身即新 commit）时变——该断言实际空转。处方：降格为文档性说明，或钉死 strip-on-hash + 说明动机。
- **m3** LENS-03 T3 测试落域自相矛盾：`LensfunDataDistribution`/`LensfunDownloadService` 是 App Session 域类型，`LensfunDistributionTests` 却标 IOP bundle——IOP 测试 target 不可 import App 模块。处方：SHA/优先序纯面显式落 Core/IOP（文件落点同步 files_modified），或测试改 App bundle；BUNDLE-MAP 同步。
- **m4** 登记面缺位：四 plan files_modified 均无 `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` 行（新 17 测试文件将成 array-union 审计孤儿）；LENS-02 T5 要求改 AGENTS.md 键族节但 files_modified 无 AGENTS.md 行。各 plan T6 补两登记行。
- **m5** resolve 的 crop 实参语义未钉死：现役 `LensfunMatch.swift:422` 传 `crop: entry.cropfactor`（镜头校准 crop），而 `resolve` 语义（:193 注释自述）需**相机** cropfactor（NS·HW NormScale）。「全参化」若只改 `match()` 实参不改此处，跨 crop 组合系数折算仍错。T3 SC 增一条「resolve crop 实参 = 相机 imageCrop」回归。
- **m6** scale 折叠点未钉死：畸变前缩 ru（改变畸变强度）vs 畸变后缩采样偏移（纯视场收窄）观感不同；「采样坐标 ×1/scale」字面倾向后者但未明示，且与投影复合序同题（并入 M5 处方）。X5 加一句「scale 施于映射后采样偏移」+ golden 钉死。
- **m7** 并行波「触碰面不相交」表述不实：LENS-03 与 LENS-04 files_modified 相交于 `LensPanelView.swift`、`Localizable.xcstrings`、`Project.swift`（数组 + 各自 tuist generate 末位）。单重活串行机下安全，但 CONTEXT 编排总纲与 LENS-03 头的「不相交」应更正为「串行交错 + 相交文件清单」，防 checker 误判可并行起跑。
- **m8** 对表 golden 独立性 observation：dt 无 lens 腿（不跑 dt ✓）；projection/scale golden = Alcedo 源转录 CPU 参考 + kernel 同源对表——同笔转录系统性误读会自消，真独立对账只有 LENS-04 T4 RawLab 抽查（非 CI）。T4 的「延后供件」降级路径不得用于静默跳过（plan 已有此禁 ✓，评审确认维持）。
- **m9** perf probe 门值未在 plan 层给带值（锚 = 04-04/ashift 实测、DECISIONS 登记）——可接受；执行批登记时同时给绝对 ms 与相对倍率，避免「同阶」事后解释。
- **m10** 探针读法未钉：LENS-01 T2 签名 `(data: Data) -> Bool` 引导全文件读入（DNG 可达 10^8 字节级）；opcode tags 可在 IFD0 或 SubIFD（ProRAW 多帧）。处方：read_first 加一句「seek 式有界读（`RasterIccParser.tiffEmbeddedICCData` :320-360 先例），禁全文件 Data 读」；签名可改 `(url: URL)` 或 Data 语义注明可分片。

---

## 5. 评审清单逐项回答

1. **目标覆盖**：FEAT-DEV-07 五锚逐项有属主——enable→L2T1、scale→L2T3、projection→L3T1、profile database→L3T3/T4、auto-detection→L1T2/T3/T5 + L2T2/T4；互斥三态（detected/unknown/notApplicable）+ auto 恒关 opt-in（`lensfun.autoApply` 默认 false，生效域 = notApplicable 硬守卫）+ 覆盖逃生门（**功能闭环，UX 面缺口 = M2**）——三态机表驱动可测、CIRAW 无查询 API 的架构性约束下「存在性探测 + 保守默认」设计闭环成立（空 opcode list 假阳性例已入 T2 测试面）。覆盖判定：**锚全闭合，经 M1/M2/M3 修补后无悬空裁决**。
2. **坐标抽查**：39 点台账见 §1——坐标纪律总体优秀（±1 行级），两处结构性失实（B1/M6）均源于「引用行段未覆盖追加尾段」与「构造点拓扑未数全」。
3. **路线 A 收口特殊风险**：`resolveCommitted` 调用点全仓 grep 仅 `LensModule.swift:339` 一处（测试零调用）——若走「params 加字段、签名不变」形态则零签名破坏面（推荐形态）；既有 parity（`LensParityTests`/`LensfunDBTests`）在 T3/T4 验收门显式零回归 ✓；真正的收口回归面 = 既有 `.lensfun` 档 live resolve 行为变化——**M3**（裁决缺口）。
4. **互斥探测**：可行——`DNGOpcodeProbe` 有同模块先例（`RasterIccParser` TIFF IFD0 有界字节 walk :320-360），SubIFD walk 为增量；厂商 RAW unknown = 常量赋值零难点；`DecodedImage` additive 有 rasterColor/rasterNative 同形先例（init 默认 nil，构造点 4 处——M6 门面修正即可）；读法性能注意 = m10。
5. **系数快照**：骑 paramsData 不触 sidecar schema 可行（Params 已 Codable 骑 history item；`LightamerSidecar` 封存零 diff 与勘误① v11 自洽）；「写入点恰三处」主张亲核 = **与 LENS-02 退役矛盾（M1）**；snapshot nil 恒等路径设计完备（消费序双臂 + uninstall-DB 恒等断言 = H-L2 机检正门 ✓）；dbTag/hash 张力 = m2。
6. **ΔN 与测试策略**：算术精确（60..90 → 4051..4081 ✓，B1 修正后 L1 分账微调）；dt 同源 golden 操作化 = **不跑 dt**（本地 dt 无 lens 腿既定结论维持），projection/scale = gen_fixtures.py 合成参考扩节 + Alcedo GPL 源逐式转录 CPU 参考（对表数值入 DECISIONS、门 1e-5、禁放宽）+ RawLab 无头抽查独立对账（非 CI）——操作化成立，独立性边界见 m8；100MP perf 门值 = m9。
7. **编排**：01→02→03 串行 + 04 依赖 02、T1/T3/T4 可与 03 并行、T2 串行垫底、T5 --all 收口——执行序「T1→T3→T4→〔03 闭环〕→T2→T5→T6」自洽；「并行垫底」措辞与执行序一致；瑕疵 = m7（相交文件清单失实）+ M5（并行波内 03 改语义、04 并行段已建的 auto-crop 需回头接线——交叉点应在 04 T2 前收口）。
8. **红线与勘误**：15 条红线齐备且四 plan 逐条引用 ✓；勘误两条处理正确（v10→v11 亲核 :255 ✓；基线 3991/37/0 双点亲核 ✓）——漏第三条勘误（B1 的 CaptureMetadata 段）；OQ-LENS-1..8 与 plan 映射逐条吻合（D-1→L2T2 / D-2→X2 parked / D-3→L4T1 / D-4→L1T3 / D-5→L2T3 / D-6→L3T3 / D-7→L2T1 / D-8→L3T1），唯 D-2 的 v1 面悬空（M2）。

---

## 6. 放行条件汇总

1. B1 修复（CONTEXT 勘误③ + X4/T1 改写 + ΔN 微调）——**先于一切执行**。
2. M1/M2 二选一钉死 bake 写入点与 detected 覆盖面终形；M3 裁决表加第七项；M4 memo 键改匹配结果缓存；M5 投影×auto-crop 属主落 L3T1 或降范围守卫；M6 T2 grep 门按真实拓扑改写。
3. minors 按 §4 处方随各 plan 执行批顺路处理，不阻塞起跑（m2/m5/m6 建议在对应 plan 开工前落入 CONTEXT 措辞，避免执行中二次偏差申报）。

（评审完；本文件为唯一产出，零源码触碰。）

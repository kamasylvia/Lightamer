# M2-6「DRT」回溯二次验收（omp 独立二次验收）

> 验收：omp 二次验收员，2026-10-09。零共享上下文——不轻信首验结论，正本材料全部亲读、六抽查点全部亲测。
> 对象 = M2-6 3 plans：M2-6-1（OpenDRT 核，`7c2d5de`..`1865f34`，收口 `1580f08`，验收 `4beb632`）/ M2-6-2（ACES 2.0，`17a16d6`..`3c5ff8a`，收口 `313c0b8`，验收 `f0556e4`）/ M2-6-3（面板+HDR 视口+Post 迁移，`5e7d676`..`b6e1f38`，收口 `979ea15`，验收 `77de936`）。M2-6 全程范围 `7c2d5de^..979ea15` 共 22 commits。
> 正本：`M2-6-1/2/3-ACCEPTANCE.md` + 各 SUMMARY + 仓库根 AGENTS.md「M2-6 架构增量」节（全部亲读）。

**结论头：PASS / 0 error + 1 minor**

## 一、逐 plan 判定

| plan | 交付 | 判定 |
|---|---|---|
| M2-6-1 | DrtRecord schema / EOTF 七函数 + kernel / Float64 参考 + kernel golden / 预设三件套 + NOTICE / sidecar v6 / TerminalTailPolicy + 尾段装配 | ✅ PASS。DrtRecord 对表 Alcedo hpp/cpp 逐键吻合（§二.1）；尾段序锁与格式面亲读吻合（§二.2）；首验 0E+3m（F1 记账勘误已修、F2 flake 注记、F3 仿算未落盘）无新增。 |
| M2-6-2 | CAM16 / 限色七表 + RGC / ODT 参考 / aces2 kernel + method 分派 / Apache-2.0 署名链 | ✅ PASS。许可链亲验完整（NOTICE 两条目 + Apache 文本 + 四文件头注，§二.4）；`isRenderImplemented` 交付态双 true + 分派穷举无 default（§二.2 末）；首验 0E+0m 维持。 |
| M2-6-3 | 持久化四件 / 面板 / EOTF 吸附 / HDR 视口 / Post 四件迁移 / zh + 收口 | ✅ PASS。持久化四件 + HistoryHash 末位折叠亲读吻合（§二.3）；HDR 终式 + follow gate 亲读吻合（§二.3）；Post 槽 74.1+ 与 E5 键折叠亲读吻合（§二.2）；首验 0E+0m 维持。 |

## 二、逐抽查点证据

### 1. DrtRecord 读码 + Alcedo 对表 ✅

- 53 detailed 浮点：`LightamerCore/Sources/Graph/DrtRecord.swift:215-269` CodingKeys 机检 `case` 数 = **53**；`init` 默认值（:159-213）与 Alcedo `drt_node_model.hpp:60-112` 逐行核——抽 8 键全符：`tn_con=1.66`（hpp:60 ↔ :160/:216）、`tn_hcon_st=4.0`（:66 ↔ :166/:222）、`cwp_lm=0.25`（:69 ↔ :169/:225）、`pt_lml_g=0.0`（:75 ↔ :175/:231）、`ptm_high=-0.8`（:86 ↔ :186/:242）、`brlp_r=-1.25`（:96 ↔ :196/:252）、`hc_r_rng=0.3`（:100 ↔ :200/:256）、`hs_y_rng=1.0`（:112 ↔ :212/:268）。键序 = hpp 声明序 verbatim。
- 12 顶层：`DrtRecord.swift:386-400` CodingKeys = method + 11 snake_case（encoding_space/encoding_eotf/limiting_space/peak_luminance/look_preset/tonescale_preset/creative_white/creative_white_limit/display_grey_luminance/hdr_grey_boost/hdr_purity）+ parameters，共 13 case；扣除嵌套组 `parameters` = **12 顶层**，与 hpp `DrtPayload:116-128` 字段一一对应（顺序一致）。默认值 `init`（:370-384）与 hpp:116-127 逐值一致。
- rawValue 终式：`DrtRecord.swift:36-77` 与 Alcedo `drt_node_model.cpp:25-74` 对表——`aces_2_0`/:39 ↔ cpp:26、`open_drt`/:41 ↔ cpp:26、`p3_d65`/:49 ↔ cpp:38、`gamma_2_6`/:69 ↔ cpp:64、`gamma_2_2`/:74 ↔ cpp:73、`gamma_1_8`/:76 ↔ cpp:68、`linear`/`st2084`/`hlg`/`bt1886` 全符。**超出 hpp 域的 6/7 值枚举**（p3d60/p3d60/xyz/pro_photo/adobe_rgb）在 :19-25 有 m4 显式偏离声明（自创拼写、禁称 hpp 源），诚实。
- 注意（非缺陷）：当前 Alcedo 主干 hpp 已增 `SrgbPiecewise`（hpp:46）与 `diffusion_strength`（hpp:130）——均为 M2-6 定稿（2026-10-01）之后的上游增量（本地仓已更新至 v0.3.1+主干 f1fae5d），不属本 phase 对表范围；我方 EOTF 七值 = M2-6 定稿时上游域，无漏。
- 单源：`legalEOTFs`（:445-452）、`isHdrEncoding`（:456-461）、`isDrtRecordDefault`（:466-468）定义唯一；全仓 grep 引用点均为**调用**（App：`DrtPanelModel.swift:85,208`、`WorkspaceModel.swift:268`、`ExportInspectorView.swift:368`、`PipeCoordinator.swift:1435`；Core：`PixelPipe.swift:1532`），零第二实现。
- stableHash：`DrtRecord.swift:426-435` = `JSONEncoder[.sortedKeys]` → `StableHash.hash(data)`；`StableHash`（`LightamerCore/Sources/Foundation/StableHash.swift:20-56`）= FNV-1a 64（offset `0xcbf29ce484222325`），与申报一致。

### 2. TerminalTailPolicy 三臂 + 尾段次序 + 平面格式 ✅

- 三臂：`LightamerCore/Sources/Pipe/PixelPipe.swift:1483-1495` = `.sdrGamma` / `.edrLinear` / `.drt(DrtTailParams)`，穷举无 default 纪律注释在册（:1479-1482）。
- 次序：`DrtTailAssembly.instances`（:1590-1615）= `[method 74.0] + post（TailOrderedBox 74.0+0.1×i，即 74.1+）+ [eotf 75.0] + residents（borders 76/watermark 77 过滤重放）`；method/eotf 序值 `DrtMethodBox.iopOrder=74.0`（:1701）、`EotfBox.iopOrder=75.0`（:1799）；borders/watermark 76/77（`V50Order.swift:225-226`）。与申报 `[74 → 74.1+ → 75 → 76 → 77]` 一致。序锁测试：`DrtTailTests.swift:340 testTailAssemblyOrderIsMethodEotfBordersWatermark`（含 `orders[2]==76.0` :350）+ `DrtPostMigrationTests.swift:152 testAssemblyInsertsPostSlotsBetweenMethodAndEotf` + `:185 testEmptyPostAssemblyAndSeedMatchTheP1Face`（空集 P1 位等）。
- E5 键折叠：`DrtTailAssembly.seed`（:1553-1577）= `recordHash ⊕ policyTag ⊕ post 集身份（非空才折、sorted order-insensitive）⊕ upstream`；注释（:1554-1562）明言参数值经尾段 sub-run 自身 levelHash 链——与 M2-6-3 首验 §二③记载的「与 plan 字母等价偏离、已申报」一致。
- 平面格式：`tailPixelFormat`（:327-368）——`.drt` 尾腿：EOTF 起显示格式（`DrtTailDisplay.format` :1530-1540：HDR→16F、linear→float32、余→bgra8）、EOTF 前恒 float32（:348-353）；主链顶面回 float32、P1 显示格式分支退休（:355-361，D9）。与 AGENTS.md「尾平面格式」节逐字吻合。
- pristine：`PipeCoordinator.terminalTailPolicy`（`App/Sources/Lightamer/State/PipeCoordinator.swift:656-670`）非 pristine → `.drt`，余 → `.edrLinear`/`.sdrGamma`；注释（:651-652）明言「pristine = 无 DRT 段」。
- P2 翻面：`isRenderImplemented`（`OpenDrtReference.swift:690-694`）双 `return true`；`DrtMethodBox` 两分派 switch（`PixelPipe.swift:1723-1728,1751-1764`）穷举 `.opendrt/.aces20` 无 default。

### 3. 持久化四件 + HistoryHash + HDR 视口 ✅

- ①carrier：`WorkspaceModel.drtRecords` per-url（`WorkspaceModel.swift:249`），默认 record 不入 map（:267-271 经 `isDrtRecordDefault` 判定）。
- ②写腿：`updateDrtRecord`（`PipeCoordinator.swift:577-585`）= 非当前图跳过 + `scheduleSidecarWrite()`（2s 节流既有通道）。
- ③restore 腿：`restoreDrtRecordLeg`（:598-608）= nil 零动作 / history 失配 error 日志且 field wins / 同 session 跳过 / 异值回注——三态分级在册。
- ④run 传点：`terminalTailPolicy(for:)`（:656-670），thumbnail 恒 legacy（`resolution != .thumbnail` 双分支）。
- HistoryHash：`HistoryStack.swift:548-583` 5 参式 = 3 参层感知哈希 + `drtRecord.stableHash()` 末位折入（:571-575）+ film（M3-3 后加位，默认 nil 零影响）；无 drt item 档原样返回（`guard let` 语义 + 注释 :553-555）。`commitDrt`（:265-289）+ `drtDocumentScope`（:362）+ `effectiveDrtRecord`（:515-524）在位。
- HDR 视口：`followGateActive`（`EditorMTKView.swift:431-432`）= `!edrActive && !drtTailActive`，draw 唯一调用点（:529-532）；colorspace 终式 `drtLayerColorSpace`（:732-794）= rec2020→`itur_2100_PQ/HLG`（:738-739）、p3d65→`displayP3_PQ/HLG`（:741-742）、linear→`extendedLinearSRGB`（:748）、SDR 幂→ calibrated RGB（:749-793）；SDK 无 extendedITUR_2100 修正注释（:719-721）。`drtSurfaceSpec`（:798-804）+ `DrtSurfaceSpec`（:710-713）在位。

### 4. 许可红线 ✅

- 仓根 `NOTICE`（4901B）：条目 1 = jedypod/open-display-transform v1.1.0（GPLv3，独立实现声明 + 数值事实转录边界 + 六引用文件清单 + Alcedo schema 只读注记）；条目 2 = aces-core v2.0 main `069b0bc3…`（2026-09-01，Apache-2.0，移植函数清单 + 四移植文件清单 + v1.3 RGC/AMPAS-BSD 段 + Alcedo hpp 只读交叉验证注记）。
- `third_party_licenses/aces-core-LICENSE-Apache-2.0.txt` 在位（11356B）。
- 四移植文件头注全带 `Portions Copyright Contributors to the ACES Project; Apache-2.0; see NOTICE`：`Cam16.swift:20-22`、`Aces2Limiting.swift:17-18`、`Aces2Reference.swift:11-12`、`Aces2Kernels.metal:9-10`。OpenDRT 三文件 jedypod/GPL 只读注记在位（`DrtPresets.swift:8`、`OpenDrtReference.swift:11-14`、`OpenDrtKernels.metal:24-25`）。

### 5. 定向测试 ✅（2 类，0 fail）

- `Scripts/test-direct.sh --bundle Layers DrtRecordTests` → **17/0/0**（4s，peakRSS 191MB）。
- `Scripts/test-direct.sh --bundle Layers DrtTailTests` → **14/0/0**（1s，peakRSS 499MB）。
- 计数说明：BUNDLE-MAP 登记 `DrtRecordTests=17` / `DrtTailTests=14`（`M2-4-0-BUNDLE-MAP.txt:293,296`），与本轮实测精确一致。M2-6 首验口径 `DrtTailTests=12` 系 plan 收口时计数，其后 `d6b8d9c test(layers): tail hit rerender timing gate` 追加 2 法（`git log -- Tests/.../DrtTailTests.swift` 亲证）——后加合法增量，非分歧。禁全套 `--all` 纪律遵守（仅上述两类定向）。

### 6. git 机检 ✅

- 抽 commit 1：`7c2d5de feat(core): drt record schema with eotf linkage`（M2-6-1 T1）= 4 文件（BUNDLE-MAP 行 + `DrtRecord.swift` 468 行新 + Project.swift 行 + `DrtRecordTests.swift` 327 行新），与 SUMMARY T1 申报一致。
- 抽 commit 2：`b6e1f38 feat(iop): migrate post four after display transform`（M2-6-3 T5）= 8 文件（BUNDLE-MAP + PipeCoordinator 8 行 + EditorTabRoute 22 行 + PixelPipe 177 行 + Project.swift + xcstrings −17 + DrtPostMigrationTests 349 行新 + EditorStackRoutingTests 翻面 13 行），与 SUMMARY T5 申报（含 E4 先例翻面）一致。
- `defaultFaceDisabledOpNames` 零 diff：`LightamerIOP/Sources/Registry.swift:39-50` = filic/sigmoid/agx（D1）+ denoise 三件（D2）在位；`git log 7c2d5de^..979ea15 -- Registry.swift NodeOwnershipCatalog.swift` = **零命中**；`git diff 7c2d5de^..979ea15 --stat -- LightamerIOP/` = **空**——M2-6 全程（22 commits）注册面零触碰，filmic/sigmoid/agx 原地保留。

## 三、Findings（0 error + 1 minor）

- **O1（minor，注记）**：M2-6-1 首验 F3（st2084 升带 numpy float32 仿算佐证未落独立文件）延续——本二次验收未重做仿算（读码确认 DECISIONS §D2/§D4 数学论证在册 + 首验已独立复现同机制同量级）。建议后续 phase 若触 EOTF 容差再补归档；不阻塞本 phase 结论。

## 四、与首验分歧点

- 无实质分歧。三份 ACCEPTANCE 的结论（M2-6-1 PASS 0E+3m / M2-6-2 PASS 0E+0m / M2-6-3 PASS 0E+0m）、测试计数口径（含 F1 勘误后 2402 基线）、偏差签注（E5 等价偏离、m4 超域声明、tsprst11 陷阱、D9 格式退休）经本轮独立亲测全部成立。

## 五、会话卫生

- 只读验收：除本报告文件外零写入；`git status` 无本会话新增修改（仅前序遗留 untracked 走查产物与 research 归档目录）；未 push；未跑 `--all`。

OMP-VERDICT: PASS

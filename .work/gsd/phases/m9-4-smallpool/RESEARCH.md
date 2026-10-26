---
phase: M9-4
station: smallpool（M9 收尾站）
status: drafted
date: 2026-10-25
charter: ROADMAP §M9 + REQUIREMENTS M9SM-01..02
upstream-anchor: AlcedoStudio origin/main `e1effd8`（ColorWheels v2）+ `7ccb0ec`（Filmstrip tiles）+ `c740f7b`（color encoding catalog）
---

# M9-4 小件池 RESEARCH

## 0. 调研范围与结论速览

| 件 | 结论 |
|---|---|
| ColorWheels LGG+Offset（M9SM-01 主件） | 上游 v2 = 归一化影调域 LGG + 加性 Offset 轮；我方现行 = 上游 v1 公式 verbatim（全像 ACEScc 直乘）→ **真 parity gap**；迁移 = process v3 bump + 冻结/新双臂 + Update-to-Current 单公式转换（§2-§3） |
| LUT encodings（M9SM-02） | 上游 catalog 26 行 vs 我方 17 行 → 实缺 **10 编码行**（连带 7 传递曲线 + 6 gamut）；REQUIREMENTS「+24」= 全部新表行粗算口径（10+7+6=23≈24），非 24 条编码（§4.1，OQ-3） |
| Filmstrip stars/编辑态磁贴（M9SM-02） | 我方磁贴已有 selected ring + 当前图 accent edge；缺 stars 行（rating 列在 Core 已投影、App 行模型未带）+ editing/selected 双态分档（§4.2） |
| Show in Finder（M9SM-02） | 导出产物 reveal 已有（PostExportActions）；**原图（图库/编辑器）菜单/上下文 reveal 无**——加行半天级（§4.3） |
| XPan ratio 预设（M9SM-02） | 我方 CropAspectPreset 7 档；上游 12 档**无 65:24**——本件是自主增强非 parity，三行具体值待 OQ-6（§4.4） |

---

## 1. 上游 ColorWheels v2 全测绘（`e1effd8`，2026-10-18）

### 1.1 问题陈述（上游 issue #445，设计正本 = `docs/roadmap/alcedo_studio/edit/color_wheel_tonal_lgg_plan.md`）

v1 公式 `((c+lift)^gamma)·gain` 直接作用在 **ACEScc 编码值**上。ACEScc 非 0=黑/1=白 归一化信号，三操作的不动点全落在可见域外，实测后果：三轮在 −3EV..+2EV 内几乎都是**整体平移**（Lift ≈ Exposure 同数学），Lift 力度 ≈ 其它两轮的 **2.7 倍**，strength 被 clamp 成固定值——「Lift/Gamma/Gain」名义分离、实际不分。

### 1.2 v2 数学形态（正本 `color_wheel_tone.hpp/.cpp`）

**影调坐标**（ACEScc 上以中灰为 0EV）：

```
ev = (c − CE_ACESCC_MIDDLE_GREY) × CE_ACESCC_B
t  = (ev − kToneBlackEv) / (kToneWhiteEv − kToneBlackEv)
常量 kToneBlackEv = −6, kToneWhiteEv = +6（R = 12 档，中灰恰 t = 0.5）
```

**四轮逐通道公式**（K = 该通道档数 = `color_offset[ch] + luminance_offset`；执行序 **Offset → Lift → Gamma → Gain**）：

| 轮 | 公式 | 不动点 | 标定点（满幅 = K 档） |
|---|---|---|---|
| Offset | `ev' = ev + K`（ACEScc 增量 `K/B`，先加） | 无 | 所有影调 |
| Lift | `t' = t + (K/R)·clamp(1−t, 0, 1)` | t ≥ 1 | t ≤ 0（−6EV 及以下） |
| Gamma | `t' = t^p`，`p = ln(max(0.5 + K/R, 0.05)) / ln(0.5)`；仅 0 < t < 1 | t ≤ 0、t ≥ 1 | t = 0.5（中灰恰移 K 档） |
| Gain | `t' = t + (K/R)·max(t, 0)` | t ≤ 0 | t = 1（+6EV，以上线性延续） |

CPU 预解（`ResolveToneWheelKernelParams`）每通道下发：offset_acescc / lift K/R / gamma 指数 p / gain K/R + tone_black_acescc + tone_range_acescc（14 float）；kernel 只做 `ApplyToneWheel` 查表级运算（三后端 primary_grade.metal/.cl/.cu 同步改）。**中性早退**：lift=0 ∧ p=1 ∧ gain=0 时仅加 offset（逐位精确）。

**分离性实测**（上游 plan 表，每轮 +1 档）：Lift 在 −6/0/+6EV = 1.00/0.50/0.00 档；Gamma = 0.00/1.00/0.00（−4EV 峰 1.11）；Gain = 0.00/0.50/1.00——真分离。

**值域/单位换挡**：全部值改**档（stops）**；`kDiscMaxStops = 1.0`（盘满幅 = 主导通道约 +0.82 档）、`kMasterMaxStops = 2.0`（Master ±2 档）——替换 v1 的 strength∈[0,0.1] / luma±1。四轮**同一组常量**，v1 的 gamma 符号翻转折除。

**盘映射**：`DiscToChannelStops(x,y,strength)` = 零均值色相单位向量 × strength×r（v1 `DiscToCdlDelta` 同构，去 clamp、strength 语义改档）；`ChannelStopsToDisc` 反演（拟合迁移与 UI 回填用）。四轮 color_offset/luminance_offset **中性值全 0**（v1 的 gamma/gain 中性 (1,1,1) 废除）。

### 1.3 Payload/持久化

- `ColorWheelPayload` 增第四 `ColorWheelControl offset` + `optional<nlohmann::json> version_one_json`（读入的 v1 JSON 原样保存）。
- `ToJson`：未编辑（version_one_json 在）→ **原样写回 v1 字节**（root id 与 history before/after 是 JSON 哈希/逐字节比较，未编辑旧工程必须序列化同字节）；任一轮值变 → 清除、写 `"version": 2` 四轮。
- `LoadJson`：无 `version` 键 = v1 → 立即转换；`version: 2` = 新档；其它版本 throw。
- `IsIdentity` 改为四轮全中性（`IsNeutral`：color_offset==0 ∧ luma==0，disc/strength 不参与——与我方 M2-5 照抄版同形但 gamma/gain 基准从 (1,1,1) 变 0）。

### 1.4 v1→v2 转换（`ConvertLegacyColorWheel`，读入单公式转换）

- **旧 lift → 新 offset：精确转换**，`K = (color_offset[ch] + luminance_offset) × CE_ACESCC_B`（v1 lift 是 ACEScc 加法 = 全影调同移，正是新 Offset 的定义）。
- **旧 gamma/gain → 新 lift/gamma/gain：最小二乘拟合**（`FitLegacyGammaGain`）：每通道在 −6..+6EV 取 25 采样点，以旧公式（含旧 lift）输出为目标，Gauss-Newton（数值雅可比 step 1e-4，法方程 3×3 高斯消元，≤20 迭代，收敛 <1e-9）拟合三个 K。误差：常见值 ≤0.03 档；旧 lift ≈1.4 档且同调 gamma 时两端可达 ≈0.12 档（新 Gamma 在 ±6EV 不起作用，结构性残差）。
- 拟合 K 拆均值（→luminance_offset）+ 零均值部分（→color_offset + 反演 disc 截单位圆）；**不截断**，渲染即拟合结果。
- 触发时机：旧工程 LoadJson 即转换渲染（观感≈旧、非逐位），存储字节保持 v1 直到用户动轮。

### 1.5 UI/面板

Look 面板四轮改名 **Shadows / Midtones / Highlights / Offset**（保留英文副标题）+ tooltip；catalog `*_master` 属性改档（`editor_parameter_catalog.cpp` 65 行改）；trackball 模型（`editor_cdl_trackball_model.cpp` −349/+重写）去 gamma 翻转。

### 1.6 数值锚（GPL 同许可可对照）

上游 `tests/edit/graph/color_wheel_tone_test.cpp`（265 行）提供解析锚：每轮 +1 档在目标影调恰 ΔEV=1（tolerance 级）、Lift/Gain 分离比 ≥4×、四轮中性全影调 ≤1e-6、disc↔stops 往返 1e-4、越界截单位圆、v2 JSON schema round-trip。可作我方 golden 对照源（GPL-3.0 同许可复制纪律：保留版权头 + NOTICE）。

---

## 2. 我方现行实现与差距（逐参数）

现行 = **上游 v1 公式 verbatim 移植**（M2-5-1 T6 批），三处正本：

| 面 | 我方现状 | file:line | vs 上游 v2 |
|---|---|---|---|
| Params | `ColorWheelControl {disc, strength, colorOffset, luminanceOffset}` ×3（lift/gamma/gain）；中性 lift=0 / gamma=(1,1,1) / gain=(1,1,1) | `LightamerIOP/Sources/ColorWheels/ColorWheelsModule.swift:23-206` | 缺 `offset` 第四轮；中性值域全 0 |
| kernel | `sign(c)·\|c+lift.color+lift.luma\|^(1/max(γ.color+γ.luma,1e-4))·gain.color` 直接作用 ACEScc texel | `LightamerIOP/Sources/ColorWheels/ColorWheels.metal:39-48` | 整体换 `ApplyToneWheel`（§1.2 四公式）；**注意**：我方指数是 `1/γ_leg`，上游 v1 metal 是 `γ_leg` 直作指数（M2-5 移植时的 catalog 侧语义换算）——见 OQ-1 |
| CPU reference | 同公式 Float64 镜 | `ColorWheelsModule.swift:305-325` | 换 `ApplyToneWheels` CPU 参考式 |
| 打包 | 16 float：flag + 三轮 color/luma（disc/strength 不进像素） | `ColorWheelsModule.swift:250-279` | 换 14 float 新布局（offset3/lift3/gamma3/gain3/black/range——CPU 预解） |
| 盘推导 | `DiscToCdlDelta` + UpdateDerived（gamma 臂 `1−delta` 翻转、strength clamp 0...0.1、luma ±1） | `ColorWheelsModule.swift:100-189` | 换 `DiscToChannelStops`（零 clamp、strength=1.0 档、四轮统一无翻转）；range 常量改 1.0/±2.0 |
| isIdentity | lift 全零 ∧ gamma/gain colorOffset==(1,1,1)（照抄 v1） | `ColorWheelsModule.swift:221-234` | 四轮全中性（0 基） |
| 面板 | 三轮 Section（lift/gamma/gain）+ strength 滑杆 + luma 滑杆 + reset | `App/Sources/Lightamer/UI/Inspector/ColorWheelsPanelView.swift` | 四轮（+Offset Section）、命名 Shadows/Midtones/Highlights/Offset、值域换档 |
| golden | identity 逐位 + 4 参数点 vs Float64 reference | `Tests/LightamerTests/GradeKernelGoldenTests.swift:508-555` | reference 换新公式重钉 + v3 双臂新增（§3.4） |
| zh 键 | `panel_wheels_{lift,gamma,gain,strength,luminance,reset}` 族在册 | xcstrings | +offset 节 + 四轮新名/tooltip 键（尾块纯插入） |

**其余涉面盘点**（v2 改动的全仓波及面，我方对应物）：
- `Registry.swift` 注册行 / `V50Order.swift` 41.0 槽——**零改**（同 op 同槽，只有语义变 → 正是 process bump 的教科书场景）。
- `GradeCatalog`（NodeOwnershipCatalog）defaultLook 的 colorWheels identityJSON——中性值域变（gamma/gain 从 (1,1,1) 变 0 基）则 identityJSON 单源要改（**注意 V50Order/GradeCatalog 在 M7-6 封存面清单**——identityJSON 属目录数据非 schema，改值不改面，plan 期核封存边界）。
- `AdjustmentTransferTests` / `GradeParamsCodingTests` / `EditorStackRoutingTests` / `CatalogAddFaceTests` 凡持 colorWheels params 字面量的测试——随 params 形变同批更新。

---

## 3. process v3 迁移形态（M9SM-01 主裁决面）

### 3.1 号位与冲突面（确认独占）

- `RenderProcessVersion.current = 2`（`LightamerCore/Sources/Pipe/RenderProcess.swift:90`，M8-2 film 光谱核占用）；`RenderProcess.all = [.v1, .v2]`。
- **M9-2 已声明零 bump**（BW = 新 stock id 存量不可达；`.work/gsd/phases/m9-2-bwspectral/RESEARCH.md:39`）、**M9-3 零 schema**（upright 骑既有 crop params）——**v3 归本站独占，无竞态**。

### 3.2 bump 五件套（M6-2 制度，照单）

① `RenderProcess` 追加 `case v3`（doc-comment = 账本：ColorWheels LGG+Offset 代际）② `all` 尾插 `.v3` ③ `current` 2→3（`RenderProcess.swift:90`）④ AGENTS.md「process 账本」行 ⑤ 新旧 golden 三件套（§3.4）。

### 3.3 双臂 + 转换挂点（建议形态，OQ-7 落地）

**渲染臂分叉点** = `ColorWheelsModule.process`（或其 params 预解处）按 `RenderProcess.resolving(...)` exhaustive switch：`.v1/.v2` = 冻结臂（现行 kernel 公式逐字节保留，v2 档含 v1/legacy 观感零漂移）；`.v3` = 新 `ApplyToneWheel`。同 film v2 先例（`PixelPipe.assembleFilmLeg` fork 同构）。

**params 形变**（第四轮 offset + 中性 0 基）与 modversion 的关系两选一（OQ-2）：
- **甲（推荐）**：`Params.offset` 以 additive optional/宽容 decode 进 struct（DrtRecord/FilmRecord tolerant-decode 先例），colorOffset 中性基准**不改存量键义**——v3 臂读入时把 v1 语义值经**单公式转换**（移植 §1.4 `ConvertLegacyColorWheel`：lift→offset 精确 + gamma/gain 拟合）现算为新参数。**零 modversion bump、零 sidecar schema 改、旧档字节零改写**；转换发生在渲染预解层（memo 化），不落盘。
- 乙：modversion bump + Update 动作时 params 字节转换落盘——多一条持久化迁移缝，收益仅「新档 params 可读性好」，代价 = HistoryHash/paramsData 兼容面全动。不推荐。

**迁移 UX**：复用 M8-3「Update to Current Process」通道（`WorkspaceModel.setProcessVersion`，`App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift:405`——唯一运行时写脸，零自动迁移 OQ-5 纪律不变）。v2 档用户显式升号后：新臂对存量 params 走同一单公式转换渲染（与甲形态同缝——即升号前后观感从「冻结 v1」变「拟合 v2≈旧观感」，拟合残差 ≤0.03 档〔常见值〕如实入 tooltip/发版注记）。**与上游差异**：上游 LoadJson 即换观感（非逐位）；我方冻结臂保逐位、升号后才近似——我方 process 纪律更严，此偏离为有意（M9SM-01「旧号冻结零漂移」原文即此意）。

### 3.4 golden 重钉清单（凡 colorWheels 涉面）

1. **冻结臂 golden**：现行 4 参数点 golden（`GradeKernelGoldenTests.swift:527`）**原样保留**改跑 v1/v2 臂 + 新增「v2 档零漂移」负测（同 params 两臂切换只有 v1 臂逐位不变断言）。
2. **新臂 golden**：①CPU reference 重写为 `ApplyToneWheels`（Float64 镜）+ kernel vs reference 常规 golden；②解析锚套件（上游 test 移植，GPL 数值对照）：每轮 +1 档目标影调 ΔEV=1 / 分离比 ≥4× / 中性全影调 ≤1e-6 / 档数学 disc↔stops 往返；③转换锚：`ConvertLegacyColorWheel` 拟合误差 ≤0.03 档（常见参数域）+ lift→offset 精确性。
3. **identity 逐位**：四轮中性 → blit 逐位（新中性早退路径）。
4. **缓存折键**：`PipeCacheKey` 若折 colorWheels paramsHash——params 未变（甲形态零 params 字节变）则键零漂；**渲染臂分叉不进缓存键**（v2 档 paramsHash 不变 + 臂由 process 定 → 若同一 params 在 v2/v3 档缓存混用会错配！→ **fork 点缓存折键「非 legacy 折 resolved arm」**（film v2 的 policyTag 先例，`RenderProcess.swift` KD-6 契约）——plan 必核 `PipeCacheKey` colorWheels 平面键是否含 process 段，不含则补折，这是**必查缝**）。

### 3.5 面板/键面

- 四轮 Section + 命名换档（`ColorWheelsPanelView` 重排）；strength 滑杆域 0...0.1→0...1（kDiscMaxStops）、luma ±1→±2（kMasterMaxStops）；新增 offset Section。
- zh 键：`panel_wheels_offset` + `panel_wheels_{shadows,midtones,highlights}`（或保留 lift/gamma/gain 键 + 副标题新键——plan 定；技术专名照 V14 惯例显式 switch 静态键）+ tooltip 键族；xcstrings 尾块纯插入。
- Master/stops 单位换算提示（catalog `*_master` 同步——我方 InspectorState 若有 colorWheels master 键则同批）。

---

## 4. 尾件四件

### 4.1 LUT encodings 表扩（M9SM-02；「+24」口径修正 OQ-3）

上游正本 = `alcedo_studio/src/color/color_encoding_catalog.cpp`（commit `c740f7b`，单 commit 全量引入）：**26 encodings + 22 gamuts**。我方 = `LightamerIOP/Sources/Lut3d/LutEncodingCatalog.swift:195-247`（17 行 + 9 gamut）。

**编码行缺口 10 条**（逐行，id 照上游拼写）：

| # | 上游 id | 内容 | 需新曲线 | 需新 gamut |
|---|---|---|---|---|
| 1 | `sony_slog3_sgamut3cine` | Sony S-Log3 / S-Gamut3.Cine | —（slog3 已有） | sgamut3cine |
| 2 | `fujifilm_flog2_fgamut` | F-Log2 / F-Gamut | flog2 | —（rec2020） |
| 3 | `canon_clog2_cinemagamut` | Canon Log 2 / Cinema Gamut | clog2 | —（cinema_gamut 已有） |
| 4 | `red_log3g10_rwg` | RED Log3G10 / REDWideGamutRGB | log3g10 | redwidegamutrgb |
| 5 | `blackmagic_film_gen5_bmdwg` | BMD Film Gen5 / BMWG Gen5 | bmdFilmGen5 | bmdwg_gen5 |
| 6 | `davinci_intermediate_dwg` | DaVinci Intermediate / DWG | davinciIntermediate | davinci_wide_gamut |
| 7 | `dji_dlog_dgamut` | DJI D-Log / D-Gamut | dlog | dgamut |
| 8 | `p3d65_gamma26` | P3-D65 Gamma 2.6 | gamma26 | —（display_p3 已有） |
| 9 | `p3dci_gamma26` | P3-DCI Gamma 2.6 | gamma26（共用） | p3dci |
| 10 | `rec2020_bt1886` | Rec.2020 BT.1886 | —（bt1886 已有） | — |

（我方独有 `linearRec2020` working 行上游无——保留不动。）合计 = **10 编码行 + 7 新传递曲线（flog2/clog2/log3g10/bmdGen5/davinciIntermediate/dlog/gamma26）+ 6 新 gamut** = 23 条新表行 ≈ REQUIREMENTS「+24」的计数口径（写作时粗算）。**成本**：表驱动加行本身机械（catalog 是纯数据表 + Float64 正逆曲线对）；成本主体 = 7 条曲线的 Float64 正逆函数移植 + 每条往返/单调 golden 单测（M3-1 批的传递曲线族先例同款）。上游矩阵构造注明 OCIO 2.5.1 port（BSD-3）——曲线常数从上游表直取（GPL-3.0 同许可 + OCIO BSD 注记随 NOTICE）。约 1.5-2 天。

### 4.2 Filmstrip stars / 编辑态磁贴（M9SM-02；上游 `7ccb0ec`，#442）

上游磁贴形态（`EditorFilmstripThumbnailCard.qml`）：双态 = **editing**（编辑器开图，bone well + ink frame 最强态）与 **selected**（共享 Library 选择，浅灰 well）；图下固定两行 caption = 上行星右对齐 + 文件名下行；dock 高 168px。rating 数据 = Library rating。

我方现状：`App/Sources/Lightamer/UI/Shell/FilmstripView.swift`（M2-3 壳 + M7-AR-7 id 记账 + R12 pair 索引）——行 = 缩略图 + 文件名（`:267-293`）+ selected ring（`:314`）+ 当前图 accent edge（`:178` 注记）；**无 stars 行**；editing/selected 双态未分档（accent edge 承担了 editing 语义、selectedRing 承担 selected——形态已有但按上游口径核视觉分档即可，成本低）。

数据缝：rating 在 Core 已投影（`LibraryImageRow.rating: Int64?`，`LightamerCore/Sources/Library/LibraryQueries.swift:112`；schema 列 `LibrarySchema.swift:188`），**App 侧 `LibraryGridModel` 行结构未带 rating**（构造点 `LibraryGridModel.swift:222` 等三处 keyValue 投影无 rating）——加字段 + FilmstripView 行 UI 加 stars 行 + 编辑态视觉分档。约 1 天（含 zh 键 + AX id + 定向测试）。

### 4.3 Show in Finder（M9SM-02）

- 已有：**导出产物** reveal = `App/Sources/Lightamer/Export/PostExportActions.swift:174`（`NSWorkspace.shared.activateFileViewerSelecting`）。
- 缺：**原图** reveal——图库 grid 行 / CullingView / Filmstrip 行 / 编辑器 Image 菜单的「Show in Finder」菜单项 + contextMenu。形态 = `NSWorkspace.shared.activateFileViewerSelecting([url])` 现成先例同款调用（注意 L057：非 runModal 面，无面板纪律问题）。加行半天（含 zh 键 `action_show_in_finder` + AX id）。

### 4.4 XPan 类 ratio 预设（M9SM-02）

我方 `CropAspectPreset` 7 档（free/original/1:1/4:3/3:2/16:9/16:10，`App/Sources/Lightamer/UI/Overlay/CropOverlayHost.swift:25`）；picker + 双向 ratio bits 映射在 `CropPanelView.swift:36-149`。上游 12 档**电影向**（2.35:1/1.9 IMAX/1.85 DCI/2.2 70mm/1.43 IMAX 70mm/2.76 Panavision…，`editor_support/modules/geometry.cpp:15-31`）——**无 65:24**，本件是**自主增强非 parity**。加行成本 = 枚举 case ×3 + picker 行 + ratioN/D 双向映射臂 + zh 键（65:24 = ratioN 65/ratioD 24，整数对现有 Int 存储零 schema 影响）。**三行具体值 OQ-6**（REQUIREMENTS 只点名 65:24「等三行」；候选：65:24 XPan、2.75:1? Ultra Panavision 70、6:17? 中画幅宽幅——需用户/REQUIREMENTS 作者定）。

---

## 5. 差距矩阵 + 方案骨架（M9SM-01/02 逐条）

| 条目 | 现状 | 动作 | 复用/新建 | 关键缝（file:line） |
|---|---|---|---|---|
| M9SM-01 新公式 kernel | v1 verbatim | 写 `ApplyToneWheel` kernel 臂 | 新 kernel 分支（同文件加）+ 上游公式移植（GPL 保留头） | `ColorWheels.metal:28-50`；上游 `color_wheel_tone.cpp` |
| M9SM-01 CPU 预解 | 打包 color/luma 直通 | `ResolveToneWheelKernelParams` 移植（14 float 布局） | 新建（ColorWheelsModule 内静态函数） | `ColorWheelsModule.swift:250-279` |
| M9SM-01 Params+offset | 三轮 | additive 第四轮 + tolerant decode | 复用 DrtRecord 宽容 decode 先例 | `ColorWheelsModule.swift:192-206` |
| M9SM-01 v1→v2 转换 | 无 | `convertLegacyColorWheels`（lift→offset 精确 + LGG 拟合 Gauss-Newton） | 新建（上游 `FitLegacyGammaGain` 移植，纯函数可单测） | 新文件 `ColorWheels/Sources` 侧或 Module 内 |
| M9SM-01 process v3 | current=2 | 五件套 + 双臂 fork | 复用 film v2 fork 先例 + M8-3 Update 通道 | `RenderProcess.swift:90,108-172`；`WorkspaceModel.swift:405` |
| M9SM-01 缓存折键 | paramsHash 无 process 段 | fork 平面键折 resolved arm（非 legacy 才折） | 复用 KD-6 契约 | `PipeCacheKey`（plan 必查缝） |
| M9SM-01 golden | v1 4 点 | 冻结臂保留 + 新臂三套（kernel-vs-ref / 解析锚 / 转换锚） | 上游 `color_wheel_tone_test.cpp` 数值对照 | `GradeKernelGoldenTests.swift:508-555` |
| M9SM-01 面板四轮 | 三轮 | 四 Section + 档域 + 新名 | ColorWheelsPanelView 重排 | `ColorWheelsPanelView.swift` |
| M9SM-02 LUT +10 行 | 17 行 | 表扩 + 7 曲线 + 6 gamut + golden | 表驱动先例 | `LutEncodingCatalog.swift:195-247` |
| M9SM-02 Filmstrip stars | 行无 stars | GridModel 行 +rating 字段 + 行 UI stars + 双态分档 | Core 投影已在 | `FilmstripView.swift:267-320`；`LibraryGridModel.swift:222`；`LibraryQueries.swift:112` |
| M9SM-02 Show in Finder | 仅导出产物 | 图库/Filmstrip/编辑器菜单 + contextMenu | PostExportActions 先例 | `PostExportActions.swift:174` |
| M9SM-02 XPan ratio | 7 档 | +3 case + 映射臂 + zh 键 | 现有 picker 双向映射 | `CropOverlayHost.swift:25`；`CropPanelView.swift:36-149` |

## 6. 风险

1. **缓存键错配（最高风险）**：colorWheels 平面若在 PipeCache 键内无 process 判别，v2/v3 档同 params 值（甲形态 params 字节不变）会共用缓存平面 → 冻结臂观感污染新臂（或反之）。plan 必须机检 `PipeCacheKey` 的 colorWheels 涉面并按 KD-6「非 legacy 才折」补折（film v2 policyTag 同款）。
2. **v1 冻结臂基准**：我方 kernel 指数形态（`1/γ_leg`）与上游 v1（`γ_leg` 直指数）有移植期换算差异（M2-5 决策）——冻结臂锚定**我方现行 golden 字节**而非上游 v1 数值（OQ-1 确认后写死）。
3. **拟合转换的观感近似**：升号后旧档 colorWheels 观感 = 拟合近似（常见 ≤0.03 档、极端 ≈0.12 档残差）——非逐位。须在 Update 确认文案如实声明（M8-3 通道已有文案面，扩一句）。
4. **GradeCatalog/封存面**：identityJSON 中性值若动即触 M7-6 封存面清单（GradeCatalog 在册）——plan 期裁决「数据行值变 vs 面零 diff」边界并在 DECISIONS 登记（先例：LUT 内置集 seeder 数据行替换未算破面）。
5. **modversion 误用**：params shape 语义变化若走 modversion bump（乙形态）则 HistoryHash 全动——本站推荐甲形态避免；若 plan 翻乙，须按 M6-2 ORTHOGONALITY 注记双轨登记。
6. **LUT 曲线精度**：7 条新曲线的 Float64 正逆对若从 OCIO/厂白皮书转录，须逐条 golden（往返误差 + 单调 + 端点），防手抄常数错（上游表常数可直取对照）。

## 7. Open Questions

- **OQ-1**：v1 冻结臂基准确认——锚定我方现行 kernel/golden 字节（含 `1/γ_leg` 换算形态），不再回溯对齐上游 v1 数值？（建议：是，冻结=我方历史观感）
- **OQ-2**：params 形态——甲（additive offset + 渲染层现算转换，零 modversion/零 sidecar 改）vs 乙（modversion bump + 落盘转换）？（建议甲）
- **OQ-3**：LUT「+24 条」口径修正——实缺 = 10 编码行 + 7 曲线 + 6 gamut（=23 新表行）；确认按此范围交付（编码行 10 是用户可见缺口）？
- **OQ-4**：t 域外行为核验——ACEScc 段 texel 可为负/超编码域（−0.358..1.468 之外 extrapolation），新公式 t ∉ (0,1) 早退路径的像素覆盖面需 golden 覆盖（v3 新臂测试矩阵加超域采样点）？
- **OQ-5**：Filmstrip editing/selected 双态——我方 accent edge + selectedRing 现有视觉是否够格视为已对齐上游双态，还是按上游 bone well/ink frame 视觉规范重做分档？
- **OQ-6**：XPan 三行具体比例值（65:24 确认 + 另两行候选待用户定；上游无此档，自主增强）。
- **OQ-7**（承 REQUIREMENTS 编号）：迁移 UX 复用 M8-3「Update to Current Process」通道 + 升号即切拟合观感——确认不复刻上游「LoadJson 即转换渲染」（我方冻结纪律更严）？

## 8. 证据索引

- 上游 commit：`e1effd8`（ColorWheels v2 全 diff + `color_wheel_tonal_lgg_plan.md` 设计正本 + `color_wheel_tone_test.cpp` 数值锚）；`7ccb0ec`（Filmstrip tiles）；`c740f7b`（encoding catalog）。
- 我方正本：`ColorWheelsModule.swift` / `ColorWheels.metal` / `ColorWheelsPanelView.swift` / `RenderProcess.swift` / `WorkspaceModel.swift:380-412` / `LutEncodingCatalog.swift` / `FilmstripView.swift` / `LibraryQueries.swift:95-146` / `CropOverlayHost.swift:25` / `CropPanelView.swift:36-149` / `PostExportActions.swift:174` / `GradeKernelGoldenTests.swift:508-555`。
- 制度先例：film v2 fork（`RenderProcess.swift:124-135` 账本）、M8-3 Update 通道（`WorkspaceModel.swift:398-412`）、M9-2 零 bump 声明（`m9-2-bwspectral/RESEARCH.md:39`）。

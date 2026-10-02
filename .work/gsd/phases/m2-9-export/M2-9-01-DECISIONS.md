# M2-9-01 DECISIONS — 收口底稿

> Plan 正本 = 同目录 `M2-9-01-PLAN.md`（checker 回注修正版，E4/E9/m1/m2 已
> 回注）。执行 = ZCode subagent worker（2026-10-02 夜间，`[gsd] paused=false /
> auto=true`）。本文落 plan 期预埋裁决点的执行注记 + 执行期新增裁决。
> 提交链：`6835bd2`(T1) → `3a1ecb8`(边界修复) → `e2a37f3`(T2) → `3b90709`(T3)
> → `ba379ac`(T4)。

## 1. KD-5 穷举 switch 影响面清单（执行期 grep + 编译仲裁，checker E4 五处确认）

`OutputMode` 加 `bounds`/`physical` 两 case 的 production 穷举面全集（每臂
落点 = commit 内注释）：

| # | 位置 | 处置 | commit |
|---|---|---|---|
| ① | `YiyinExportSettings.validate` | 本 plan 改写（四模式域） | `6835bd2` |
| ② | `YiyinExportSettings.targetSize` → `resolveExportResolution` dispatch | 本 plan 改写（KD-1 单源） | `6835bd2` |
| ③ | `ExportRecipe.derivedTag` | 补臂：`bounds` → `"WxH"`（如 `2048x1536`）、`physical` → 格式名 fallback（与 original 同法）——planner 预裁（KD-5#2） | `6835bd2` |
| ④ | `ExportPanelView` :435-436（mode→SizingKind 映射）+ :698-701（`(SizingKind, OutputMode)` 二元组）| 仅编译性补臂（不可达——legacy 面无 setter 路径构造新 case），legacy 行为字节冻结；除此之外该文件零 diff（逐 hunk 机检 = 2 hunks 全为补臂） | `6835bd2` |
| ⑤ | `MCP/Tools/EditingToolset.swift:329-336` | 三元式构造，非穷举 switch，不炸——无需处理（checker E4 预判确认） | — |

grep 复核（`case .longEdge|.shortEdge|.bounds|.physical`，production 全仓）：
其余命中 = ④ 的同文件 `ExportPanelViewSizingKind` 自有枚举 switch（:448/:497/:737，
不受影响）与 `if case` 条件式（非穷举）。无 `default:` 息事新增。

**执行偏差 D8（编译序强制）**：plan 把 ③ 的补臂动作挂在 T3、但 T1 加 case 当
轮 ③④ 即编译炸——每任务独立提交必须可构建，故 ③④ 的补臂随 T1 commit 落地
（T3 只交付其测试向量，如 plan 原排）。front-matter 无越界（③④ 所在文件均已
登记）。

## 2. 尺寸域差异对照（我方超集 vs Alcedo 字面域，DECISIONS 差异表）

| 域 | Alcedo | Lightamer（本 plan 落地） | 备注 |
|---|---|---|---|
| 像素目标（longEdge/shortEdge/bounds 双轴） | UI 256..16384（longEdge）/1..100000（bounds，QML:840,873） | `1...100_000`（`maxTargetPixels`，D-08-3-T3-1 域保留） | 我方域为准（plan 已裁） |
| DPI | QML 1..10000 | `1...2400`（`dpiRange` 既有旋钮面保留） | 我方域为准 |
| 物理尺寸双轴 | 0.01..100000 双精度（QML:916） | `physicalSizeRange = 0.01...100_000.0`（同域落地） | 同构 |
| `maximumEdgePixels` | 0 = 关（int，无显式域） | ≥ 0（0 = 关；负数 validate 抛 typed） | 执行定：负 cap 无意义；正上限不设（cap 是限制不是目标，超 maxTargetPixels 无害不触发） |
| 源尺寸非正 | typed 失败（"Source pixel dimensions must be positive"） | **钳 `max(w,1)`**（既有 `targetSize` 面——历史向量行为） | **偏差 D2**：我方源面历史语义是钳不是炸，保持之；typed 失败保留给 physical DPI 缺失（D-M2-9-CONTEXT-6 正主） |
| DPI 修正取整 | Double dpi 原样乘比例 | Int dpi × 比例 → `.rounded()` 取整 | golden 钉 300×(1200/1800)=200 精确；非整比例存在 ±0.5dpi 取整带（Int 载体固有） |

## 3. shutter 渲染对照结论（plan AC4 对照义务，OQ-4 修正案）

Alcedo `PartText` SHUTTER_SPEED（cpp:155-158）：`shutter_numerator_/denominator_`
双 int 直拼 `"\(num)-\(den)"`，任一 ≤ 0 → 空串。我方上下文载体是
`shutterSeconds: Double?`（RESEARCH §2.5 CaptureMetadata 同源），执行补
**Double→有理数推导**（Alcedo 无此层——它上游存的就是 EXIF 有理数）：

- `seconds ≤ 0 / non-finite / nil` → 空串（同 Alcedo 空形态）；
- `seconds ≥ 1` → `"<round(seconds)>-1"`（EXIF ≥1s 惯例 `n/1`）；
- `seconds < 1` → `"1-<round(1/seconds)>"`（相机惯例 1/N；1/500 → `1-500`、
  1/60 → `1-60`）。

形态面与 Alcedo 逐形态一致：分子-分母、`-` 连接符（`/` 文件名非法）、空值空串。
推导层为本 plan 自有（**偏差 D3**，测试 `testRenderFieldSemantics` 逐值钉）。

## 4. date 实参 typed 拒绝（OQ-4 错误集第 5 项；Alcedo 直通 vs 我方拒绝）

Alcedo `FormatCaptureDate` 对未知字符**直通**（token 替换后原样保留）。plan
错误集明列「date 实参非法 token」= typed 解析错——执行落地为**字母表白名单**
：`{y,M,d,H,m,s}` 六 token 字母 + 文件名安全分隔符 `{空格,-,_,.}`（**`:` 排除**
——文件名非法字符，时间分隔符用 `.`）。超集字符即
`.invalidDateArgument`，面板可指名禁用 startExport（Alcedo QML:64 同构心智）。
**偏差 D4**：比 Alcedo 严，per plan 错误集原文。

## 5. ExportVariant 新字段 init 默认值注记（KD-2）

- `colorSpace` 参数补默认 `.sRGB`（additive）——**语义**：DRT 联动档
  （`drtOutput != nil`）下该值被忽略（legacy 五空间菜单的兼容载体）；
  legacy 面（`drtOutput == nil`）下 `.sRGB` 本就是面板默认，无行为面。
- `drtOutput: DrtRecord? = nil`：nil = legacy 五空间路径（既有测试/legacy sheet
  字节冻结锚）；非 nil = DRT 强制联动（M2 UI 恒设；消费在 M2-9-02）。
- `metadataPolicy: ExportMetadataPolicy = .standard`（类型默认即 STANDARD 剥离
  三项）、`embedICC: Bool = true`（Alcedo ExportIccPolicy EMBED 默认）。
- 手写 `init(from:)`：三新字段全 `decodeIfPresent` + 默认——synthesized 会炸
  旧 payload（E2 纪律：旧 JSON 字面锚测试两侧落地——Settings 侧
  `testLegacyPayloadDecodeCompatibility`、Recipe 侧
  `testVariantLegacyPayloadDecodeCompatibility`，字面 = 旧 synthesized 发射
  逐键形状，nil optional **不发射键**经探针实测钉入注释）。

## 6. ExportNamer 冲突三档落点与形态（T3 执行裁决 D6）

- `ExportCollisionPolicy` 落 `ExportNamer.swift` 嵌套（单源）。
- **重载对而非默认参数**：`destinationURL(4 参)` 非 throwing = 历史默认
  increment 面（内部委托非 throwing 私有 `incrementDestination`）；5 参
  throwing 面 = 全三档。若走「默认参数 + throws」，三个既有调用点
  （ExportRenderer:357 / StackMergeService:1000,1390）强制加 `try`——两文件
  均不在本 plan front-matter（ExportRenderer 归 M2-9-03），边界纪律禁止。
  语义与 plan 原文等价：「默认 .increment = 现行为逐字节」由非 throwing 面
  承载，`ExportNamerTests` 零修改全绿 + `testDefaultOverloadEqualsIncrementTier`
  双面同 URL 钉死。
- `.fail` typed = `BaseNameOccupiedError`（携带基名）；大小写不敏感占用比对
  （D7）全档保留；fail/replace **永不**落入 `-N` 递增。

## 7. 元数据模型字段计数注记（OQ-6 "7 bool"）

Alcedo hpp:54-62 正本 = mode(2 值) + **6 bool**（exif/xmp/iptc/location/
serials/editing_history）。本 plan 逐字段照抄（`ExportMetadataPolicyTests`
全量断言）；CONTEXT 的「7 bool」口语计数 = mode+6（7 个字段），模型面以
hpp 字段清单为准，无第八字段。

## 8. 边界外小修复申报（fix commit `3a1ecb8`，phase 模型「验收方直接修」形态）

**发现链**：T1 后 Export bundle 首跑 1 fail
（`QuickLookRendererTests.testPreviewPlaneParityByteIdenticalSharedDecode`
：`functionNotFound("compositeLayer")`）。

归因（三步实测）：① stash 本波改动 → 干净树复跑同 fail（非本波回归）；
② 删 Debug Products 全量重编（L034 处方）→ 仍 fail（非混合代际）；③ 根因 =
**未跟踪活体夹具漂移**：`input/RAW/DSC00012.ARW.lra`（gitignored、GUI 会话
随手重写）于 **2026-10-02 00:52**（M2-8-3 基线跑之后）被走查会话写入
layerStack=1 + 37 instances——parity 腿自此进 LayerCompositeDriver →
`compositeLayer` kernel 查找 → 该测试从未注册 IOP metallib（潜伏缺陷：任何带
层 sidecar 必炸此测试）。

修复 = 测试侧一行注册（`registerDefaultLibrary(in: PassthroughKernel.
metalBundle)`，全体 pipe 测试同款显式注册），夹具**保持原样**（活体工件非本
波可 curate；曾试剥 layerStack 验证归因，因 historyHash 漂移破坏 probe b、
已从备份还原）。修复后 10/0/0（60s：真 RAW 解码 + 全复合渲染）。
front-matter 越界申报：`Tests/LightamerTests/QuickLookRendererTests.swift`
不在 files_modified，以 fix() 单独提交、SUMMARY 登记，晨审可推翻。

## 9. 测试计数对账（plan 预估 +45 vs 实数 +34）

| 任务 | 新测试方法 | 文件 |
|---|---|---|
| T1 | 6 | YiyinExportSettingsTests（append-only 追加） |
| T2 | 11 | ExportFileNameTemplateTests（新） |
| T3 | 5 + 4 + 2 | ExportCollisionPolicyTests（新）/ ExportMetadataPolicyTests（新）/ ExportRecipeTests（append-only 追加） |
| T4 | 6 | ExportNamingTemplateStoreTests（新，App bundle） |
| **合计** | **34** | （预估 45 的 -11：模板引擎错误集/渲染锚合并进复合测试方法，断言数远超方法数） |

## 10. 零行为红线机检记录（T5 收口核对）

- `git diff 180c39e..HEAD -- ExportNamerTests` = **空**（真零 diff）；
  ExportRecipeTests/YiyinExportSettingsTests diff 无 `-` 行（append-only，
  checker E9 拆分口径）。
- `ExportFormatSpec`/`ExportColorSpace` 枚举体：ExportRecipe.swift 全部 diff
  = 3 hunks（ExportVariant 字段+init+decode、derivedTag 补臂），两枚举体内
  **零 hunk**（AC9 ✓）。
- `ExportPanelView.swift` diff = 2 hunks 全为编译性补臂（AC9 ✓）。
- 既有向量零漂移：targetSize 三模式向量 / effectiveSizing 向量 / ExportNamer
  全套 / ExportQueue 契约随 bundle 全绿逐值保绿（Export 288/1/0、App 481/0/0，
  skip 同基线）。

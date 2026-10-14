# M6-3-01 ACCEPTANCE — 第一路独立验收（2026-10-14，zcode subagent）

> **结论：PASS / 0 error + 1 minor + 3 observations**（minor = 账面滑差非测试缺口，
> 修复清单交验收后闭环批，见 §五.1）。
> 性质 = 双重验收第一路（dual_acceptance=true，夜间全自动授权批）；不轻信执行方
> 报告——全套独立复跑 + 逐 AC 机检亲跑 + 9-hunk 逐 hunk 亲核 + EXIF probe 独立
> 复现。验收树 = HEAD `04b2b0a8`（验收方自建 build-for-testing 后跑批，零源码
> commit；本文档为本批唯一新增产物）。omp 第二路按 plan T5 串行待派（严禁并发）。

## 一、全套独立复跑（AC#8 亲证数字）

`caffeinate -dis Scripts/test-direct.sh --all`（验收方自跑 build-for-testing 于
HEAD，产物与 `c077784a` 代码态同源——T5 为 docs-only）：

```
BUNDLE|IOP|686/1/0|peakRSS=7716MB|435s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=7251MB|762s|sampling=time
BUNDLE|Layers|474/4/0|peakRSS=1172MB|165s|sampling=time
BUNDLE|Library|671/4/0|peakRSS=620MB|80s|sampling=time
BUNDLE|Sessions|280/4/0|peakRSS=1301MB|70s|sampling=time
BUNDLE|Export|378/4/0|peakRSS=5717MB|208s|sampling=time
BUNDLE|App|810/4/0|peakRSS=2832MB|386s|sampling=time
TOTAL|3759/24/0|2106s
OK (direct launch, no testmanagerd)
```

- exit 0；七段零 MEMFAIL 零 crash；峰值全 <8G 运行门（IOP 7716MB 在历史带
  7167..7975 内，±3% 方差口径）；L055 双保险亲跑——七段末条 Executed 全挂靠
  `Test Suite 'All tests' passed`，崩溃签名七段零命中。
- **对账**：七 bundle executed 逐值与执行申报一致（Export 378 = 基线 353+25 ✓ /
  App 810 = 801+9 ✓ / IOP·IOPParity·Layers·Library·Sessions 五段零漂移 ✓）。
  skip 段和 1+3+4+4+4+4+4 = 24 = TOTAL 24 机械一致。
- **TOTAL = 3759/24/0 ≠ 申报 3756**：申报链「+22 新法 → 合计 31 → 3756」为记账
  滑差（实测 `grep -c "func test"` = ExportGainMapTests **25** 法 + PanelTests
  **9** 法 = 34；3725+34 = 3759）。3759 ∈ plan 预期带 3753..3759（顶沿），SC 带
  内，**非测试缺口**——minor-1 登记，见 §五.1。

## 二、逐 AC 核验表（八条）

| # | AC | 判定 | 亲证证据（全部本验收轮亲跑/亲读，非转抄） |
|---|---|---|---|
| 1 | OQ-1① capture 点 = DRT 尾 EOTF-box 前线性级 + 门⑤门⑥ | ✅ | capture 单点 = `PixelPipe.swift:1630`（processRec uncached 臂，hunk 7）；`EotfBox` 全仓唯一构造点亲证 = `:1791`（`DrtTailAssembly.instances`，以 `ModuleBox(module:)` 包装）；`PipeCache()` 每 renderStage 局部新建（`ExportRenderer.swift:497`）→ export 恒冷缓存恒走 uncached 臂，cached 臂不可达申报属实；独立 EDR 链零存在（本批新文件仅 ExportGainMapEncoder + 两测试文件，`git diff --diff-filter=A` 亲列）；门⑤（st2084+hlg 双臂）与门⑥（yiyin + 无旗标负控）负测各一在册（`ExportGainMapTests` :161/:177）；E4 线性光喂入三层证 = capture 点结构排除 + 门⑤ + gain 语义 band 法（SDR 线性解码值 ×2^k → GainMapMax≈k ±0.5 带，:881） |
| 2 | OQ-2② EXIF probe 双态 | ✅ | **probe 独立复现**：验收方 /tmp 即弃 swiftc 探针亲跑——`CGImageMetadataSetValueWithPath(meta, nil, "{TIFF}/Software")` 返 **false**（与 DECISIONS §1 逐字一致）；`xmp:CreatorTool` / `hdrgm:Version` 返 true。**追枪加强**：`exif:Software`（XMP exif 命名空间）虽可 SetValue，但 rewrap 后仅落非标准 XMP 属性——APP1 `Exif\0\0` 段缺席、`{Exif}`/`{TIFF}` 读回双 ABSENT、`tiff:Software` 干脆不序列化——「v1 无 EXIF」降级裁决**成立且加强**。失败臂容器/aux/XMP 全存活测试在册（`testGainMapArmSkipsTheICCStrip` + `testRewrapSurvivesAndPolicyNoneStaysUltraHDR` 双断言） |
| 3 | OQ-3③ hdrgm:Version + F5 门 + C 路封存 | ✅ | `hdrgm:Version` 字节扫 + rewrap 后 aux 读回 PRESENT + MPF 存活（:611 双断言法亲读）；`.none` 档无 XMP 但容器仍 UltraHDR（同法）；LightCraft C 路零代码零 NOTICE——`git diff | grep -icE "lightcraft|NOTICE"` = 0 亲跑 |
| 4 | OQ-4④ 单通道 'L008' | ✅ | aux 读回 PixelFormat fourcc == "L008"（bigEndian 解码比对）+ BytesPerRow == width + data.count == W×H（:572 三断言）；`hdrGainMapAsRGB` 全仓零代码命中（唯一命中 = 测试 doc comment 陈述其未启用，语义即「不开」） |
| 5 | OQ-5⑤ UI 位 | ✅ | 五维门 9 法全绿（jpeg/peak 202-203 边界/HDR-encoding/embedICC-off/noRecord + 复位 + 装配/enqueue/默认关）；三态不可用文案 + embedICC 复用 hint（C-3 不新增键）；**UI↔validate 子集对表亲核**：format↔① / noRecord↔②（enqueue 强制联动 `drtOutput = drtRecord` 下等价）/ peak↔③（同 `sdrReferenceWhite` 单源 + NaN 比较语义等价）/ embedICC↔④ / encoding↔⑤（同 `isHdrEncoding` Core 单源）/ 门⑥ yiyin = validate-only（makeVariant 恒不设 yiyin）——逐门无「UI 可用但 validate 拒」残口；复位三入口闭 = embedICC setter + format setter（页内）+ run-face 复核（`makeRunAssembly` :1036 复位先于 `makeVariant()` :1047，`gainMapAutoReset` 携带维度 + V14 静态键 toast） |
| 6 | OQ-6⑥ 无新 tag | ✅ | 本批 diff 新增行 grep `outputTag|formatName` 仅命中门①错误文案引用（非新 tag 面）；formatName 恒 "jpeg"（ExportFormatSpec 类型面零 diff）；Namer 既有测试原样绿（Export 378 全绿含之） |
| 7 | 零回归门 | ✅ | **九文件文件级零 diff 亲跑零命中**（ImageIOEncoders/WebPEncoder/ExportEncoder/ExportQueueContract/ExportChainBuilder/XMPWriter/XMPContainerInjector/ExportNamer/ExportQuantizer）+ ExportState 零命中 + `.metal` 零命中 + Project.swift 仅两行测试登记（dependencies 块零 diff）+ ExportRecipe diff 恰 = additive 字段/init/decode/六门（ExportFormatSpec 面零触，ExportICCStrip 本体随 ExportEncoder.swift 零 diff）；**9-hunk 逐 hunk 吻合**（§三）；xcstrings 85 插入 0 删除 = 尾块纯插入 + 5 新键全入册（zh-audit `--check` PASS 1666/1905）；runModal/LocalizationValue 插值禁形/UserDefaults 零命中；非 gain-map 负测（`testNonGainMapPostProcessingRunsAsBefore`：无 MPF + strip 照跑 + XMP 照缺）+ 既有套件原样绿（七段基线逐值） |
| 8 | SC 数字门 | ✅（带内） | 34 新法 ∈ +28..34；全套 3759 ∈ 3753..3759；per-bundle 逐值精确（§一）；**申报账面 +22/31/3756 滑差 = minor-1（§五.1）** |

## 三、9-hunk 红线亲核（KD-2 清单逐 hunk）

`git diff 55eb8f3c..HEAD` 亲核，PixelPipe.swift 恰 7 hunk + LayerCompositeDriver.swift
恰 2 hunk，与 DECISIONS §2 表逐行吻合，超清单触点 = 零：

| # | hunk | 对应清单项 | 亲核注记 |
|---|---|---|---|
| 1 | PixelPipe `@@ -154` | 属性声明 | `linearGainCapture` 尾缝同位（`tailFormatFloatOverride` 旁），缺省 nil |
| 2 | PixelPipe `@@ -1098` | runDrtTailLeg tailPipe 继承 | flat 直跑与 composite terminal 尾 sub-run 共用 |
| 3 | PixelPipe `@@ -1595` | processRec EotfBox 位回调 | `box is ModuleBox<EotfBox>` 判定（偏差①，机械必要——§四.1） |
| 4 | PixelPipe `@@ -2080` | process additive 缺省参数 | 同位 :2115 |
| 5 | PixelPipe `@@ -2093` | process 内赋值 | 同位 :2135 |
| 6 | PixelPipe `@@ -2142` | processComposite additive 缺省参数 | 同位 :2186 |
| 7 | PixelPipe `@@ -2154` | processComposite 传递进 driver | 同位 :2199 |
| 8 | LayerCompositeDriver `@@ -204` | composite additive 缺省参数 | 尾缝同位 |
| 9 | LayerCompositeDriver `@@ -568` | terminalPipe 赋值 | composite 导出（layered 常态）capture 活性承载，缺省 nil 零触 |

结构附加亲证：EotfBox 唯一构造点 :1791（主链/editor 视口零触发面成立）；
TailOrderedBox 直接 conform `ModuleBoxing`（非 ModuleBox 子类）→
`is ModuleBox<EotfBox>` 无假阳；post-four replay 仅包 borders/watermark
（:1792-1795 filter）→ EotfBox 恒不被 TailOrderedBox 包裹。

## 四、DECISIONS 10 项偏差逐项裁决

| # | 偏差 | 裁决 | 依据 |
|---|---|---|---|
| ① | 捕获判定 `box is ModuleBox<EotfBox>`（plan 原文 `box is EotfBox`） | **ACCEPT，非越权** | pieces 持 `any ModuleBoxing`（Piece.box :55），EotfBox 以 `ModuleBox(module:)` 入链（:1791）——裸类型判定恒假（死代码）；wrapper 判定精确无假阳（§三）。plan 文本失实，修正属机械必要 |
| ② | rewrap 用 `CGImageDestinationCopyImageSource`（plan KD-4 原文即此） | **ACCEPT（回归 plan）** | 首实现 AddImageFromSource 丢 MPF 为 executor 自误，修正归位；F5 spike 原文即 CopyImageSource；测试钉 MPF/aux 存活 |
| ③ | MPF 字节扫 payload 形 `"MPF\0MM\0*"` | **ACCEPT** | 段长 2 字节隔在 FF E2 与 payload 之间，marker+payload 拼接模式结构性不命中；同一断言的更准确实现 |
| ④ | box 常驻 actor 属性（plan「测试注入腿时为 nil」读解） | **ACCEPT** | 语义等价（注入腿不 stash = 箱空 = 零行为）；清路径无条件化 + `gainMapBoxForTesting` 探针面（`inFlightCountForTesting` 同位先例）；泄漏负测（failed + gate-cancelled 双路箱空）实测通过 |
| ⑤ | CIContext 建在 capture 同队列 | **ACCEPT（强形态）** | 同队 FIFO 消跨队竞态；无 CPU 读回断言维持（L014 免除前提不变）；SDK 面存在 |
| ⑥ | aux 描述字典纯字符串键 | **ACCEPT** | SDK 无 CFString 常量（探针定案）；测试按字符串键断言亲读吻合 |
| ⑦ | App 面 9 法 vs plan「8 法」 | **ACCEPT（SC 带内）** | 五维拆 5 + 复位 + 装配/兜底 + enqueue + 默认关 = 9；34 ∈ +28..34；BUNDLE-MAP APP 行 9 正确（EXPORT 行 22 错——minor-1） |
| ⑧ | 容器组 4 法保持 plan 口径 | **ACCEPT** | 25 法与 KD-7 一致（此条与 §3.7「31 实值」并存 = DECISIONS 内部不一致，随 minor-1 一并修） |
| ⑨ | run-face 复核在 `makeRunAssembly` 内 + `gainMapAutoReset` 携带 | **ACCEPT（恰为 C-2 处方）** | model 纯装配缝复位 + 视图 toast；V14 合规（显式 switch 返回静态键 + 显式 `String.LocalizationValue(key)` 包装，非插值形） |
| ⑩ | capture 测试 sizing 显式 longEdge 48 | **ACCEPT** | 测试内实现细节；断言对齐 entry-plane 语义（48×32 亲证） |

**总评**：十项全为 plan 文本/实现细节层的申报修正，零结构性越权；无需
orchestrator 追认项。偏差①③⑥⑤ 附带机制证据充分（构造点/fourcc/SDK 探针/队列
语义），DECISIONS 登记与代码实态一致。

## 五、独立发现（执行方与 checker 均未报）

### minor-1（账面滑差，测试缺口为零；修复交验收后闭环批）

- **BUNDLE-MAP 行 `EXPORT 22 ExportGainMapTests.swift` 与文件实测 25 法不符**
  （同行自注「T4 +3 后共 25」与行值 22 自相矛盾；APP 行 9 正确）。
- **SUMMARY AC#8「+22 / 合计 31 / 全套预期 3756」为同源滑差**——实值 25/34/3759
  （3759 仍在 plan 带 3753..3759 顶沿；per-bundle executed 值全部精确）。
- **DECISIONS 内部不一致**：§3.8「总数 25 与 KD-7 一致」vs §3.7「31 实值」。
- **闭环批修复清单**（三处，原位改数）：BUNDLE-MAP EXPORT 行 22→25；SUMMARY
  任务序表「+22」→「+25」+ AC#8「31/3756」→「34/3759」；DECISIONS §3.7「31 实值」
  →「34 实值」。零代码零测试面。

### 观察（不阻断，不立账）

1. **headroom 与 validate 门③ 的载体分叉残余**：render 侧 headroom 取
   `drtTail.record.peakLuminance`（ExportRenderer 装配点），门③查
   `variant.drtOutput.peakLuminance`——M2 页双写同源零分歧；直接构造 Request 可
   组出「drtOutput peak 合格 + drtTail record peak 低」→ headroom < 1 的超纲产物
   （M4 fail-loud guard 只兜 plane 缺席，不兜 headroom<1）。与 M4「载体 API 级
   独立」框架自洽，全 UI 路不可达，纯 public-API 鲁棒性观察。
2. **`primaryXMP` 静默 nil 臂**：hdrgm 命名空间注册/setValue 失败 → 返 nil → 整个
   rewrap（含 sidecar 五字段）静默跳过（容器仍 UltraHDR，fail-safe 不 fail-loud）。
   fresh mutable metadata 上注册失败为运行时不可达面，立观察不立缺陷。
3. **GOAL-STATE 既有条目日期混用**（2026-10-14/10-16 并存于 M6 站早期条目）——
   前序批次遗留账面，非本批引入，提请闭环批顺目。

## 六、T5 产物与翻账状态核对

- SUMMARY/DECISIONS/MANIFEST（gui-acceptance）/BUNDLE-MAP 两新行/Project.swift
  登记/xcstrings 5 键全部在位；MANIFEST 为 local-only（gui-acceptance ignore
  政策，与既往 phase 一致，commit body 显式申报）。
- **翻账挂验收后闭环批**（SUMMARY 挂账申报 + T5 commit body 显式声明）：AGENTS.md
  M6-3 架构增量节 / ROADMAP M6-3 行 ✅ / REQUIREMENTS ALCE-03 终态 / GOAL-STATE
  续接点 / TODO M6-3 条——执行边界内（plan front-matter 虽列 T5，executor 以
  「验收后闭环批统一翻账」申报，验收 PASS 后闭环批一并执行 + 顺手清 minor-1）。

## 七、验收程序完备性自述

- 全套复跑：验收方自跑 build-for-testing（HEAD `04b2b0a8`，增量判定测试产物与
  `c077784a` 同源）→ `--all` 2106s exit 0——**非转抄执行方数字**。
- 机检族全部亲跑：九文件/ExportState/.metal/dependencies 零 diff、9-hunk 逐
  hunk、xcstrings 纯插入、5 键入册（zh-audit PASS）、runModal/LocalizationValue/
  UserDefaults/hdrGainMapAsRGB grep、LightCraft/NOTICE 零命中。
- 测试体亲读：六门负测（含 202/203/NaN 边界与无旗标负控）、capture 两态、box
  泄漏双路、容器四法、aux 双法、rewrap 双断言、后处理三门 + fail-loud（含落盘
  零残断言）、质量旋钮方向带、tmp 无残渣、基面保真 ±1 LSB S1 伞、gain band
  （含 3.2167 事故自证 CI 先解码基面）、reimport raster 链；Panel 9 法全读。
- EXIF probe：双向独立复现 + 追枪（exif:Software XMP 座位不可读回验证）。
- 资源纪律：全套运行期间零并行测试宿主（定向轮未另起，避免 GPU/内存争用
  MEMFAIL 假阳）；无进程清理动作。
- 不 push（L070）；未派 omp（第二路串行待 orchestrator/闭环批）。

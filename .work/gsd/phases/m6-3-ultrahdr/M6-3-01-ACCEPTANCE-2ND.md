# M6-3-01 ACCEPTANCE-2ND — 第二路独立验收（2026-10-15，zcode subagent 第二独立眼）

> **结论：PASS / 0 error + 1 minor + 4 observations**
> （minor = 第一路 minor-1 同源账面滑差的**修复清单补全**——第一路清单三处只覆盖
> 7 个同源位点中的 3 个，本路补全为 7 位点逐行清单，见 §三；零代码零测试面。
> 无新增 error，无与第一路的实质分歧。）
> 性质 = 双重验收第二路（dual_acceptance=true；零共享上下文、独立视角，替代 omp
> 路制度位——omp 制度位以本独立批替代有 M6-2 先例）。不轻信第一路结论——全套
> 独立复跑（自建 build-for-testing）+ 六面独立审计自选切入 + EXIF probe 独立
> 亲写亲跑 + 9-hunk 亲核。验收树 = HEAD `04b2b0a8`（零源码 commit；本文档为本批
> 唯一新增产物）。

## 一、全套独立复跑（AC#8 亲证，第二路独立数字）

`caffeinate -dis xcodebuild build-for-testing …`（本路自跑构建）→
`caffeinate -dis Scripts/test-direct.sh --all`（全程单宿主串行，零并行测试宿主）：

```
BUNDLE|IOP|686/1/0|peakRSS=6827MB|442s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=6525MB|769s|sampling=time
BUNDLE|Layers|474/4/0|peakRSS=1174MB|169s|sampling=time
BUNDLE|Library|671/4/0|peakRSS=619MB|79s|sampling=time
BUNDLE|Sessions|280/4/0|peakRSS=1626MB|72s|sampling=time
BUNDLE|Export|378/4/0|peakRSS=5997MB|206s|sampling=time
BUNDLE|App|810/4/0|peakRSS=2832MB|393s|sampling=time
TOTAL|3759/24/0|2130s
OK (direct launch, no testmanagerd)
```

- exit 0；七段零 MEMFAIL 零 crash；峰值全 <8G 运行门（IOP 6827 / IOPParity
  6525 均在历史带下方，方差口径内）；L055 双保险由脚本 verdict 门承载亲证
  （`parse_bundle_log` 的 no-total-line 门 + crash 签名门 = verdict ok 的前置
  条件，exit 0 = 七段全过；stdout 崩溃签名 grep 零命中）。
- **逐值对账**：IOP/IOPParity/Layers/Library/Sessions 五段与 M6-2 基线逐值一致
  （零漂移）；Export 378 = 353+**25** ✓；App 810 = 801+**9** ✓；skip 段和
  1+3+4+4+4+4+4 = 24 = TOTAL 24 机械一致。
- **TOTAL = 3759/24/0 与第一路独立亲跑同值**（3725 基线 + 34 新法 = 3759 精确；
  两路各自 build+run，互为复核）——执行方申报的 3756 为账面滑差（minor-1），
  实测数字 3759 ∈ plan 预期带 3753..3759（顶沿）。
- 孤儿 fixture `srgb-matrix-8.tif.lra` 跑前删除、跑后**复活**——M4-1 挂账 #6
  在案行为（M6-2 挂账③延续），非本批引入，随闭环批清单处理。

## 二、独立六面审计（与第一路同深度、不同切入面）

### 2.1 容器面（golden 测试本体亲读，25 法亲数）

- **25 法亲数确认**（`grep -c "func test"` = 25）——BUNDLE-MAP 行值 22 错、
  行注记「T4 +3 后共 25」对（自相矛盾 = minor-1 实锤）。
- **golden 三法断言非永真**逐法亲读：
  - 基面保真（`testBasePlaneFidelityMatchesPlainJPEGEncoder`）：同一 rgba8
    平面过 `ExportGainMapEncoder.encode` 与纯 `JPEGEncoder`，解码后 **5 采样
    点 × 4 通道 ±1 LSB** 逐点比对——真实像素比对，CI 重写基面即红；S1 漂移伞
    预登记在 doc comment（黑盒跨实现相等的防假红形态合规）。
  - gain 语义 band（`testGainSemanticBandProvesLinearLightFeed`）：uniform
    SDR 128 平面 + HDR = **线性解码值**×2² → GainMapMin==Max≈2±0.5——E4 反证
    形态正确（fixture 特意填线性解码值而非 sRGB 编码值，DECISIONS §4 的
    3.2167 事故自证 CI 先解码基面）。
  - reimport（`testReimportThroughTheRasterChainDecodesTheBase`）：产物过
    `RAWDecoder().decode`（M4-1 raster 链）48×32 extent 断言——SDR base 解出
    = 正确降级。
- **四件容器结构断言在册**：MPF APP2（payload 形 `"MPF\0MM\0*"` 字节扫——偏差
  ③的更准确实现）/ ISO 21496 URN / 尾图（SOI≥2 ∧ EOI≥2 ∧ 文件尾=EOI）/
  tmp 零残渣（L009）。**aux 双法**：'L008' fourcc bigEndian + BytesPerRow==
  width + data.count==W×H；尺寸==基面（48×32）。**rewrap 双断言法**（hdrgm:
  Version + Software 签名 + aux 存活 + MPF 存活；.none 臂无 XMP 但容器仍
  UltraHDR）。**后处理三门**（strip 跳过 = profile 在位 + MPF 在位；mountXMP
  跳过 = `<x:xmpmeta` 恰 1；非 gain-map 负测零 diff）+ **fail-loud 负测**
  （armed 无 plane → typed 拒 + 落盘零残）。
- 质量旋钮（方向带 ≥ 非字节等值）+ 晋升后可解码（48×32）两法在册。

### 2.2 渲染缝面（9-hunk 亲核 + 尺寸/行序双一致性论证）

- **9-hunk 全文 diff 亲读**：PixelPipe 恰 7（:154 属性/:1098 tailPipe 继承/
  :1595 processRec EotfBox 位回调/:2080+:2093 process 双 hunk/:2142+:2154
  processComposite 双 hunk）+ LayerCompositeDriver 恰 2（:204 参数/:568
  terminalPipe 赋值）——与 DECISIONS §2 表逐行吻合，超清单触点零。
- **偏差①承重声明独立证实**：`TailOrderedBox` 直 conform `ModuleBoxing`
  （PixelPipe.swift:1821，**非 ModuleBox 子类**——`box is ModuleBox<EotfBox>`
  对 wrapper 恒假，无假阳）；TailOrderedBox 仅包 post 候选（:1809 filter
  `postOpNames.contains`），EotfBox 裸加入链（:1811 `[method]+post+[eotf]+
  replayed`）——EotfBox 恒不被包裹，捕获判定精确且唯一。
- **capture 面与出口 base 面一致性**：
  - **分辨率**：capture = EOTF-box 输入平面 = entry plane（sizing 在 entry
    施加，`longEdge 48` → 48×32 亲证于 capture 测试）；出口 base = 同 entry
    经尾段量化（yiyin off 无画布扩展）→ 同尺寸。**尺寸分叉机理被双锁封死**：
    validate 门⑥（yiyin typed 拒——E1）+ **encoder 内第二道硬守卫**
    （`ExportGainMapEncoder.encode` :108 `guard hdrPlane.width == plane.width`
    typed 拒）——第二道防线直接 Request 绕过 validate 时仍 fail-loud（本路
    独立点名的 defense-in-depth，第一路未展开）；容器级 aux 尺寸==基面双法
    钉死（`testAuxReadbackDimensionsMatchTheBasePlane`）。
  - **色彩**：capture 面 = 尾段 EOTF-box 前线性级（M2-6 增量正本「EOTF 之前的
    尾平面恒 working float32 display-referred 线性」+ `tailFormatFloatOverride
    = drtTail != nil` :508）→ encoder 以 `WorkingSpace.colorSpace`（linear
    Rec2020）包 CIImage（:135-137）——语义链闭合。
  - **行序对齐证据链**：`CIImage(mtlTexture:)` bottom-up 读 + `.oriented(
    .downMirrored)` 修正 = **L029 家族三先例同款**（CIContextPool :501/:582/
    :696，11-02 host finding 注记正本）——encoder 与出口腿同约定，基面
    （出口腿修正后位图，首行=顶）与 HDR CIImage（downMirrored 后首行=顶）行
    对齐。独立性注记：**该对齐无专项测试钉**（uniform band 与 base-only
    fidelity 均不抓垂直 flip）——见 §四 obs-1。
- **同队排序**：capture blit 提交于 routed queue（renderStage 全程
  `$routesToExportQueue.withValue(true)`，:528/:541）；blit 先于 EotfBox 及
  后续 pass 入队 → 同队 FIFO 保证 copy 读到 pre-EOTF 态；encode 腿 CIContext
  建在同一 queue（:145-147）→ CI 读排序在 blit 后。跨队竞态面结构性消除
  （偏差⑤强形态亲读成立）。

### 2.3 编码腿面（三事实 + 双旁路 fail-loud 亲核）

- **L009 tmp 晋升三事实**：①`ciTmp`/`rewrapTmp` 均为
  `destination.appendingPathExtension(...)` = **同目录同卷**；②`defer`
  removeItem 双清扫（rewrap 失败/抛错路径残渣零留）；③`moveItem` 原子晋升
  （:199）。测试钉「无残渣」（`.tmp` 过滤）+ fail-loud 负测「落盘零残」双保险。
- **同队 CIContext**：`CIContext(mtlCommandQueue: hdrPlane.commandQueue,
  options: [.cacheIntermediates: false])`——queue 载体随 capture 固化
  （`routesToExportQueue ? exportCommandQueue : commandQueue`），与出口腿
  `exportPool`（:559 exportCommandQueue）同 queue。
- **203 单源三消费点亲核**：validate 门③（ExportRecipe.swift :194 引
  `sdrReferenceWhite`）/ UI 门（ExportInspectorView.swift :796 同常量）/
  headroom 计算（`headroom(peakLuminance:)` :76-78）——三处全走
  `ExportGainMapEncoder.sdrReferenceWhite` 单拼写，零双源。
- **strip/XMP 双旁路 fail-loud**：encodeStage 臂首行 guard（:672-679）typed
  拒 + 产物路径显式 return（:693）——stripICC/mountXMP 结构性不可达；负测
  （非 gain-map 臂照旧）+ 双旁路正测（profile 在位/单 XMP 包）在册。
  `primaryXMP` rewrap 的 `guard copied else throw`（:186）= rewrap 失败
  fail-loud。
- **queue box 交接**：stash（render 腿 :682-684，key=snapshot.seq）/
  consume+clear（encode 腿 :709-711，gain-map 才取）/ clear（finish :586-589 /
  finishCancelled :618-621 / retry :389-391 幂等）+ 常驻箱（零行为=注入腿不
  stash）+ `gainMapBoxForTesting` 泄漏探针 + 双路终态箱空测试（failed +
  gate-cancelled）亲读。

### 2.4 UI 面（五维 ⊆ 六门逐维对表 + 取数同源亲核）

| validate 门 | UI 维 | 同源性亲证 | 判定 |
|---|---|---|---|
| ① format == .jpeg | `formatKind == .jpeg`（:793） | `makeVariant → makeFormat()` 同一 formatKind | ✅ |
| ② drtOutput != nil | `effectiveRecord != nil`（.noRecord :795） | enqueue :526-528 强制 `drtOutput = drtRecord`（非 nil）——UI noRecord 拦旗标 ≡ 门② 不可达 | ✅ |
| ③ peak ≥ 203 finite | `peak >= sdrReferenceWhite`（:796） | 同常量单源；**NaN 语义等价**（`NaN >= 203` = false → blocked，与 validate `isFinite` 拒等价）；202/203 边界双测 | ✅ |
| ⑤ !isHdrEncoding | `!isHdrEncoding(record.encodingEotf)`（:799） | `isHdrEncoding` Core 单源（DrtRecord.swift:463）双消费（validate :194 / UI :799）；取数源同一条 | ✅ |
| ④ embedICC | `embedICC`（:794，C-3 第五维） | 同一 model 字段 → makeVariant 携带 | ✅ |
| ⑥ yiyin | 无 UI 面（validate-only） | `makeVariant`（:968-975）恒不设 yiyin → M2 页结构性不可达 | ✅ |

- **门⑤取数源与门③载体分叉残余可达性**：`currentEffectiveRecord`（:498-500）
  ≡ `makeRunAssembly(effectiveDrtRecord:)`（runExport :279 传同一
  `editorState.history.effectiveDrtRecord()`）≡ `enqueueExportM2(drtRecord:)`
  （:299 同一 assembly 值）——**单值贯穿**，UI 门/validate 门③⑤/render
  headroom 三处读同一 record 实例；载体分叉残余仅存于 direct-Request
  public API 面（第一路 obs1，本路复核成立且确认全 UI 路不可达）。
- **复位三入口**：embedICC setter（:371-378）/ format setter（:486-495）/
  run-face 复核（makeRunAssembly :1036-1042 复位先于 makeVariant :1047，
  `gainMapAutoReset` 携带维度 + V14 静态键 toast :286-291）——DRT 面板改
  peak/encoding 的非页内变化由第三入口闭死。负测（embedICC off 复位 + format
  维复位 + run-face 复位双态）亲读全非永真。

### 2.5 EXIF 降级面（probe 独立复现 + 座位实测）

- **本路独立 swiftc 探针**（/tmp 即弃，独立写非转抄）：`{TIFF}/Software` →
  **false**；`exif:Software` / `tiff:Software`（XMP 命名空间）→ true（仅落
  XMP 属性，非 EXIF APP1 座位）；`xmp:CreatorTool` / `hdrgm:Version` → true
  且序列化实测 PRESENT。与 DECISIONS §1 逐字一致——EXIF APP1 的唯一座位
  （{TIFF} dict 路径）被 `CGImageMetadataSetValueWithPath` 拒，**「v1 无
  EXIF」降级裁决成立**（OQ-2② 预授权）。
- `xmp:CreatorTool` 座位产物实测 = rewrap 测试字节扫
  `"Lightamer 0.4.0-gainmap-probe"` 落盘亲证（第一路追枪 exif:Software 不可
  读回与本路 probe 的 XMP-namespace-only 机制结论互洽）。

### 2.6 偏差面（DECISIONS 10 项独立复核——全 ACCEPT，无应 REJECT）

| # | 偏差 | 本路独立证据 | 裁决 |
|---|---|---|---|
| ① | `box is ModuleBox<EotfBox>` | TailOrderedBox :1821 直 conform ModuleBoxing 非 ModuleBox 子类 + wrapper 仅包 post 候选 :1809 + eotf 裸加 :1811——判定精确无假阳，plan 原文为死代码 | ACCEPT |
| ② | CopyImageSource | 代码 :183 + :165-169 注记（AddImageFromSource 重编码丢 MPF 1268B vs 15723B）+ rewrap 测试 MPF/aux 存活双断言 | ACCEPT |
| ③ | MPF payload 形字节扫 | 测试 :483-489 注记 + 段长 2 字节隔断机制亲读 | ACCEPT |
| ④ | box 常驻 actor 属性 | diff 注记「ALWAYS present … unconditional」:156-161 亲读；注入腿不 stash = 箱空零行为语义等价 | ACCEPT |
| ⑤ | CIContext 建在 capture 同队列 | :145-147 + capture :362-364 routed queue 选择 + renderStage withValue(true) 全程包裹——同队 FIFO 强形态 | ACCEPT |
| ⑥ | aux 字典纯字符串键 | 测试 :571 注记 + 本路 SDK 面无对应 CFString 常量（与探针结论一致） | ACCEPT |
| ⑦ | App 9 法 vs plan 8 | 9 法亲数 + BUNDLE-MAP APP 行 9 正确 | ACCEPT |
| ⑧ | 容器组 4 法 | MPF/ISO/尾图/tmp 亲数 = 4 | ACCEPT |
| ⑨ | run-face 复核在 makeRunAssembly + gainMapAutoReset | :1036-1053 + :286-291 亲读；V14 显式 switch 静态键合规 | ACCEPT |
| ⑩ | capture 测试 longEdge 48 | :298-300 + 48×32 断言亲读；entry-plane 语义 | ACCEPT |

十项均 plan 文本/实现细节层申报修正，零结构性越权，与第一路裁决一致（独立
到达）。

## 三、minor-1 复核：第一路修复清单**不完整**（本路补全为 7 位点）

第一路清单（ACCEPTANCE §五.1）=「三处：BUNDLE-MAP EXPORT 行；SUMMARY 任务序
表 +22 + AC#8 31/3756；DECISIONS §3.7 31 实值」。本路 `grep` 全量扫描同源数
字（22/31/3756），实际滑差位点 **7 处**——第一路清单覆盖其中 3 处，漏 4 处
（同源、同性质、零代码面）：

| # | 文件:行 | 现值 | 应值 | 第一路清单 |
|---|---|---|---|---|
| 1 | BUNDLE-MAP.txt :723 `EXPORT	22	ExportGainMapTests.swift` | 22 | 25（行注记 :722 已自证 25） | ✅ 已列 |
| 2 | SUMMARY :23 任务序表 `**+22**（ExportGainMapTests）` | +22 | +25 | ✅ 已列 |
| 3 | SUMMARY :28 `新法合计 **31**` | 31 | 34 | ❌ 漏 |
| 4 | SUMMARY :29 `3725 + 31 = **3756/24/0**` | 31/3756 | 34/3759 | ❌ 漏 |
| 5 | SUMMARY :32 批准申请 `预期 3756/24/0` | 3756 | 3759 | ❌ 漏 |
| 6 | SUMMARY :64 AC#8 `Export +22 / App +9（31 ∈ …）；全套预期 3756` | +22/31/3756 | +25/34/3759 | ✅ 已列 |
| 7 | DECISIONS :73 `（31 实值），全套预期 3756 ∈ 3753..3759` | 31/3756 | 34/3759 | ⚠️ 半列（只点名 31，同行 3756 未点名） |

**补全后闭环批修复清单 = 上表 7 位点逐行原位改数**（#1 行值改、#7 双值改）。
MANIFEST 无滑差（grep 零命中）；两份 ACCEPTANCE 数字自洽。级别维持 minor
（账面滑差，测试与代码缺口为零——TOTAL 3759 两路独立亲跑同值）。

## 四、独立发现（两路此前均未报）

1. **obs：HDR 面与 base 面的行序对齐无专项测试钉**。encoder 的
   `.oriented(.downMirrored)`（:137）是增益空间对齐的唯一承载；现有测试面
   （uniform band 法 + base-only 保真法 + 尺寸双法）均不抓垂直 flip——若该
   修饰符回归性丢失，全套仍绿而产物 gain map 空间镜像（高光相对基面错位）。
   防护现状 = 与出口腿同约定（L029 三先例同形，代码审查可锚）。**不阻断**
   （本批产物经 band 法证明比率语义正确、经 reimport/aux 证明结构正确；flip
   属观察性残余）；建议后续批补一条非 uniform HDR 面 + 非对称 base 的方向性
   断言（可选）。
2. **obs：gain map 臂不带 DPI 元数据**。plain 路经 `ExportEncodeRequest.dpi`
   写分辨率（cap 修正值达产物）；gain map 臂走 CI writeJPEGRepresentation
   （无 DPI 选项），产物缺 resolution 元数据（72 缺省观感）。UltraHDR 生态
   通例、无用户可见面（预览/打印以像素为准），登记即可，无需动作。
3. **obs：晋升语义差异**——gain map 臂 `moveItem`（目标已存在 = typed 失败）
   vs plain 路 ImageIO 原子写（截断覆盖）。namer 冲突解析使两路正常流等价；
   外部同名竞争下 gain map 臂保守失败（不覆盖外来文件），方向可取。登记即可。
4. **继承确认**：第一路 obs1（headroom 载体分叉残余，public-API 面）/
   obs2（primaryXMP 静默 nil 臂，运行时不可达）/ obs3（GOAL-STATE 前序日期
   混用）本路独立复核均成立，维持观察级。

## 五、翻账与产物状态核对

- SUMMARY/DECISIONS/BUNDLE-MAP 两行/Project.swift 两行登记/xcstrings 5 键
  （85 插入 0 删除 = 尾块纯插入；zh-audit `--check` **PASS 1666/1905** 本路
  亲跑）/MANIFEST（local-only 政策）全部在位。
- **翻账四处未翻**（ROADMAP M6-3 行 / REQUIREMENTS ALCE-03 终态 / TODO M6-3
  条 / GOAL-STATE 续接点）——与执行方「验收后闭环批统一翻账」申报一致，两路
  共同门控（第一路 §六 + 本路亲查四文件现状）；闭环批翻账时**顺带清 minor-1
  7 位点**。
- 零 diff 红线本路全量亲跑：九文件 + ExportState + `LightamerCore/Sources/
  Metal/` 全目录 + dependencies 块零 diff；`hdrGainMapAsRGB` 全仓唯一命中 =
  测试 doc comment（语义即「不开」）；runModal / LocalizationValue 插值禁形
  零命中；UserDefaults 零新增。

## 六、验收程序完备性自述

- 全套复跑：本路自跑 build-for-testing + `--all`（2130s exit 0）——**非转抄**
  执行方/第一路数字；运行期零并行测试宿主、零进程清理动作。
- 机检族全部本路亲跑（命令与命中见 §五/§二）；EXIF probe 本路独立写编译运行。
- 测试本体亲读：ExportGainMapTests 25 法全文 + PanelTests 9 法核心段 +
  encoder/renderer/queue/inspector 四面产线代码亲读（关键断言逐条对到行号）。
- 与第一路分歧点：**仅 minor-1 修复清单完备性一处**（本路 7 位点 vs 第一路
  3 处——同源补全非翻案）；六面审计结论、10 项偏差裁决、PASS 判定均独立
  一致。
- 不 push（L070）；未派 omp（本批即制度位替代批）。

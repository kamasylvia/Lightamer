# M2-9-03 DECISIONS — 命名/元数据/ICC 消费接线（wave 2b）底稿

> 执行期（2026-10-03 夜间）执行 = ZCode subagent worker；`[gsd]`
> `paused=false / auto=true` 全程未动（每任务边界复查 3 次：T1/T2/T3 前）。
> 提交链：`cfbe385`(T1 命名腿) → `6a7515a`(T2 元数据腿) → `fe338d7`(T3 ICC+闸门)。
> 本文件是 SUMMARY 的对账底稿：探针证据 / 边界裁定 / case 清单逐条在此。

## §1 EXIF Software 座位探针（KD-4 落seat 证据链）

plan/CONTEXT D-5 原文「properties 路径 `kCGImagePropertyExifDictionary`」在
本 host **不可达**——ObjC 探针（2026-10-03，/tmp probe2–probe7）实测：

1. `{Exif}["Software"]` 键在**全部六容器**被 ImageIO 静默丢弃（readback 无、
   文件字节无）——Software 是 EXIF 0x0131（IFD0 tag），不属于 Exif IFD 面。
2. `{TIFF}["Software"]`（TIFF dict Software tag）是**唯一可序列化座位**：
   - JPEG：写入 EXIF APP1 IFD0（文件字节实证 `strings` 命中）；但
     **properties readback 永不回显 `{TIFF}`**（reader 面局限，probe4 H
     字节 Y / readback nil 同证）→ 测试断言走 byte-scan。
   - TIFF 容器：tag 0x0131，readback `{TIFF}.Software` 可回显（既有
     editorSignature golden 同座位）。
   - HEIC/AVIF：写入容器元数据，readback 可回显（probe3 G）。
   - PNG：ride host 的 **XMP CreatorTool bridge packet**（iTXt 字节含
     `xmp:CreatorTool`）——mountXMP 注入自持 packet 时 bridge packet 被替换
     （该态 Software 消失）；默认档（gate 关）bridge 存活，字符串在文件。
   - WebP：libwebp v1 无 mux 面（既有文档化边界）→ 本波 Software 不可达
     （WebPEncoder 整文件零 diff 红线）。
3. **座位共享裁定**：TIFF 容器上 editorSignature（预留面）与 exifSoftware
   同 tag——`mountMetadata` 见座位已占即跳过，editorSignature 胜（「两字段
   独立」实现为「一 tag 一写者、预留面优先」）；JPEG 上 editorSignature 本
   无座位（既有实现只进 TIFF encoder），Software 座位归 exifSoftware。
4. **JPEG 裸 Software dict 陷阱**：`{TIFF}[Software]` 单键 dict 被 JPEG
   writer 整体丢弃（probe6 组 1/2/3/4 vs probe4 H 组——round-trip {Exif}
   dict 同批在场时才序列化；产品真实形状恒有 round-trip dict 或空 Exif
   host trio）。测试用富 EXIF 源钉该形状。

## §2 剥离键清单实测（OQ-6，KD-3「以源 RAW 实测键集定清单」）

Sony ARW 活体夹具（`input/RAW/DSC00012.ARW`）ImageIO 属性面探针：

- `{Exif}` dict 38 键：**无 BodySerialNumber、无任何 GPS 键、无 MakerNote**
  ——serial 族在本 host 的 RAW 通路 ride MakerNote，ImageIO 不 surfacing 进
  round-trip dict（plan 预判「MakerNote 本就不在 round-trip 白名单」实测
  证实）。`{GPS}` dict 对该 body 为 nil；`{IPTC}` 仅 StarRating。
- 源 `{TIFF}` dict 含 Software/Make/Model/DateTime 等——encoder 从不挂载源
  TIFF dict（只有 Exif dict round-trip），故源 Software/Make 不泄漏。

**实现清单**（`ImageIOEncodeCore` 常量表，测试逐键钉）：
- serial 族 = `kCGImagePropertyExifBodySerialNumber`（0xa431，EXIF 标准位）
  精确匹配。
- location 族 = `{GPS}` dictionary 整体（**构造性缺席**——encoder 只挂
  Exif dict，GPS dict 是 properties 顶层 sibling，从不进 AddImage）+ Exif
  dict 内 `GPS` 前缀键防御性剥离（`hasPrefix("GPS")`，实测键集为空、防
  厂商旁路）。
- 边界：MakerNote 整体不在 round-trip 面（实测），无剥离动作；v1 不做
  MakerNote 白名单细目。

## §3 `.skippedByPolicy` 穷举面（checker 回注 L 系纪律）

`ExportChainBuilder.XMPMountOutcome` 新臂 `skippedByPolicy`；五臂全列：
`attached / skippedNoFields / skippedUnsupportedFormat / skippedByPolicy /
failed(String)`。消费面审计：Core 内 mountXMP 消费 = encodeStage 的
`if case .failed`（非穷举 switch，编译无破）；测试消费 = 等值断言（穷举
switch 零处）→ 无需补臂的既有 switch 存在。gate = **三 bool 合取**：
`mode == .standard && includeXMP && includeEditingHistory` 才挂载（KD-3
的 editingHistory 门 + 已定裁决 OQ-6 的「xmp bool gate packet」两句话
同时成立；DECISIONS §4 记 iptc 边界）。

## §4 exif/xmp/iptc 三 bool 的 v1 消费边界

- `includeExif`：gate round-trip（false = 无 Exif dict 挂载，Software 照写
  ——Software 是 STANDARD 档面非 round-trip 面）。
- `includeXMP`：gate packet（§3 合取）。
- `includeIPTC`：**no-op**——encoder 从不挂载 `{IPTC}` dict（host 无写入
  通路），v1 无 IPTC 单独剥离细目；iptc:false 不 gate EXIF round-trip
  （测试钉）。记录为 v1 边界，UI 说明归 04。

## §5 命名面与 Alcedo 差异注记（KD-1 差异表）

- **tag 并存**：Alcedo 单 recipe 世界（一次一格式，模板名即终名）；本实现
  多 variant 批共模板 → `outputTag` 拼接面在模板路径**保留**（单 variant
  tag=nil = 纯模板名；多 variant 不互覆）。测试钉两态。
- **sequence 盖章**：OQ-4「批内图像序 1 起、同图多 variant 共享」——enqueue
  按图像索引盖章（`sequence = imageIndex + 1`），载体自带的 sequence 值在
  queue 面不被消费（单真相 = queue 批序）；直接渲染面（Request.naming）
  由调用方给 sequence（04 装配或测试）。
- **FAIL 档队列面错误包装**：renderer 抛 typed `BaseNameOccupiedError`；
  queue `finish` 的既有映射（非 AppError → `.encodeFailed(String)`）包装之
  （Contract 零 diff 红线，不扩 AppError 面）——job failed 语义不变，类型
  细节进 message（测试断言 message 含名）。
- **sanitize 双层**：模板渲染 stem 经 `ExportFileNameTemplate.sanitizedStem`
  （Windows 保守）后进 `ExportNamer.destinationURL` 再过 APFS-lenient
  sanitize（对已洁净 stem 恒等）——两层共存按 01 KD-3 口径。

## §6 队列递缝 = `$jobNamingCarrier` TaskLocal（Contract 冻结续用 02 模式）

`ExportQueueContract` 整文件零 diff → `ExportJobContext` 不能加字段。命名
三元组（naming/collisionPolicy/subfolder）per-batch 入队、per-job 投递：

- `ExportJob` 增三字段（actor-private，不入 snapshot）；`enqueue` 增三
  默认参（`naming`/`collisionPolicy`/`subfolder`，batch-wide）。
- `execute` 构造 `ExportRenderer.ExportNamingCarrier` 经
  `$jobNamingCarrier.withValue` 包 render leg（与 `$jobDrtTail` 同位嵌套，
  detached task 无 TaskLocal 继承的既证缝）；**pump/cancel/retry/generation
  零触碰**（git diff 引擎体零 hunk）。
- 占用枚举：`occupiedNamesProvider(ExportRenderer.landingDirectory(base:,
  subfolder:))` —— join 单源与 renderer 落地面同一纯函数，枚举天然命中
  拼接目录（KD-1 OQ-11）。
- 优先级：Request 显式字段 > carrier（`??` 链；queue 面从不设 Request
  naming，实际无歧义）。

## §7 E6 sizing 腿切换 = 字节零漂移论证（AC 逐值同）

`renderStage` 步骤 2 由 `effectiveSizing.targetSize(...)` 切为直接调
`resolveExportResolution`：

- **像素零漂移**：01 交付的 `targetSize()` 本身已委托 resolve（success 面
  逐值同）；`StageOutput` 尺寸面不变。
- **failure 面收紧**：`targetSize` 失败回落源尺寸（never-worse 契约）；
  新 guard 改 typed throw。可达性论证——resolve 的失败输入（physical
  DPI ≤ 0 / box 维度非正）全被 `variant.validate()` → `sizing.validate()`
  前置 typed 拒绝（physicalSizeRange 0.01 下限 + dpiRange 1 下限）→
  guard 在 validate 后**不可达**，纯防御臂（DECISIONS 申报）。
- **DPI 面（E6 正主）**：`StageOutput.dpi = result.dpi`（修正后值）；
  legacy 三模式（original/longEdge/shortEdge + percent fold）cap=0 →
  `applyMaximumEdgeLimit` 直通 → `result.dpi == clampedDpi ==
  effectiveSizing.dpi`（validate 保证 1...2400，clamp no-op）→ 逐值同。
  Golden：physical 10in×20/3in@300dpi 源 3072×2048 + cap 2000 → 产物
  2000×1333、DPI 元数据 200（300×2000/3000 宽比修正）。

## §8 ICC OMIT 面 host facts（E1 案 A 的可观察面）

1. **sRGB 已知空间零嵌入**：JPEG/PNG writer 对 `kCGColorSpaceSRGB` 目标
   **不写任何 profile payload**（JPEG 只 JFIF marker、PNG 用 sRGB chunk，
   probe8/9）——OMIT 在 sRGB JPEG/PNG 上无可剥对象（typed `.failed("no ICC
   payload")` 降解，产物天然 untagged-by-inference）。可观察 OMIT 测试走
   **AdobeRGB** 目标（真 payload：JPEG APP2 / PNG iCCP）。
2. **profileName inference**：untagged JPEG/TIFF readback 回落
   "sRGB IEC61966-2.1"（JFIF/TIFF 面推断）；PNG untagged 才真 nil。断言
   相应取「嵌入 profile 名消失 + payload 字节缺席」面。
3. **像素完整性 = 剥离确定性**：跨 ICC 上下文的 color-managed decode 不可
   比对（同文件带/不带 profile 解码出不同 device 值）——最强完整性断言 =
   `strippedBytes == strip(embeddedBytes)`（剥离纯函数确定性）+ JPEG SOS
   后熵流逐字节相等 + PNG IDAT 不动。
4. **TIFF 原位压缩**：entry table 原地左移（文件长度不变 → 表后所有外部
   offset 有效）、vacated 尾槽 + 旧 next-IFD 位清零、**profile payload
   block 按 entry (type,count) 定界清零**（孤儿数据不留盘）；IFD 链逐段
   处理。产物仍可解码、其余 entry（EXIF round-trip）照常走查（测试钉）。
5. **不可达档**：HEIC/AVIF ICC ride 容器元数据盒（不做容器级剥离）、WebP
   永不嵌入（no-mux）→ typed `.skippedUnsupportedFormat`，产物保持 EMBED
   （HEIC/AVIF profileName 断言在）。

## §9 XMPExportMatrixTests 白名单 case 清单（checker E2 逐条）

| case | 改造前 | 改造后 |
|---|---|---|
| testSixFormatMatrixPositiveAndReverseAnchors | 默认参（旧语义=挂载） | `policy: editingHistoryMounted`（= `ExportMetadataPolicy(editingHistory: true)`，6 个 encode 调用点显式参） |
| testRejectFlagMapsToRatingMinusOne | 默认参 | 同上（2 调用点） |
| testEmptySidecarSkipsAndNoFieldProductHasNoPacket | mountXMP 默认参 → skippedNoFields | encode+mountXMP 均显式 editingHistoryMounted → skippedNoFields **不变**；**新增**默认参 mountXMP → skippedByPolicy 断言 |
| testInjectionFailureDegradesWithoutBlocking | mountXMP 默认参 → .failed / .skippedUnsupportedFormat | 2 调用点显式 editingHistoryMounted → 面**逐值不变** |
| testFullRenderChainLandsXMP | variant 默认 policy | variant `metadataPolicy: editingHistoryMounted`（GPU 全链 packet 挂载不变） |
| **testDefaultPolicyKeepsPacketUnmounted（新增）** | — | 默认档 packet 缺席（JPEG byte-scan + PNG hostRating nil）+ skippedByPolicy + `.none` 档同断言 |

净增 1 方法（5→6）；改造后全绿（Library bundle 6/0/0——该类属
LightamerTestsLibrary，BUNDLE-MAP 310 行既有登记，本波无新登记行）。

## §10 测试增量对账（vs front-matter 预估 21）

| 文件 | 方法数 | bundle |
|---|---|---|
| ExportNamingE2ETests（新） | 11 | EXPORT |
| ExportEncoderMetadataTests（新） | 8 | EXPORT |
| ExportIccEmbedTests（新） | 8 | EXPORT |
| XMPExportMatrixTests（白名单改造） | +1（净） | LIBRARY |
| **合计** | **28**（预估 21，+7） | +27 EXPORT / +1 LIBRARY |

偏差说明：复合方法组织（01 口径）+ E1 案 A 的座位/探针面要求逐容器钉
（JPEG bytes / TIFF readback / HEIC readback / PNG bridge / sRGB
no-payload 各占 1 方法）；E6 golden + queue 递缝 + 三档冲突（renderer 级
与 queue 级分开钉）按 AC 展开为独立方法。

## §11 边界申报

- **越界文件：一处（收尾轮 fix `d2e80d2`，晨审可推翻——01 波 3a1ecb8
  先例）**：`App/Sources/Lightamer/MCP/Tools/EditingToolset.swift`——OQ-6
  默认收窄波及 MCP export_image 工具（其互操作契约钉 packet：工具集行为
  规格「export lands in Output WITH XMP」+ 挂载自 14-2 起 ride
  encodeStage）；全套跑 1 抓出 McpEditingToolsetTests 红 → 工具调用点
  显式 `ExportMetadataPolicy(editingHistory: true)` opt-in（产品语义 =
  MCP 互操作面保契约；GUI 面 OQ-6 收窄照旧，装配归 04）。测试零改动
  （契约测试保真）。除此之外波内 diff 恰 12 文件 == front-matter
  files_modified 清单（6 Core 源 + 3 新测试 + 1 白名单测试 + Project.swift
  + BUNDLE-MAP）。
- 红线机检（git diff 840eecf..HEAD）：`WebPEncoder.swift` /
  `ExportQuantizer.swift` / `ExportQueueContract.swift` /
  `ExportRendererE2ETests.swift` / `ExportPhaseE2ETests.swift` /
  `ExportNamerTests.swift` **零 diff**；`ImageIOEncoders.swift` 恰 6 hunk
  （1 additive 装配腿 + 5 调用点换写；makeCGImage 签名/writeAtomically/
  质量-DPI 映射零 hunk）；`ExportQueue.swift` 7 hunk 全载体（引擎体零
  hunk）；`ExportChainBuilder.swift` 2 minus 行均为注释行替换（gate 纯
  additive）；`ExportRecipe.swift` minus 1 行 = validate 注释行（枚举体
  零 diff）。
- `mountXMP` 默认参语义变更有意行为变更（OQ-6 用户裁决，风险节口径）——
  XMPExportMatrixTests 显式传参改造 + 新默认档断言双锚，回退 = 用户升级点
  （未触发，改造面在预算内）。
- exifSoftware 的 App 载体（`Lightamer <CFBundleShortVersionString>`）=
  04 装配面：queue 路径暂无载体（Contract 冻结 + variant 无此字段——
  front-matter 不许加），04 需经 enqueue 增参 + carrier/variant 面接入
  （SUMMARY 交接）。

## §12 运行记录

- 定向轮：T1 ExportNamingE2ETests 11/0/0；T2 ExportEncoderMetadataTests
  8/0/0（EXIF 座位三轮迭代——裸 Software dict 陷阱、host trio 面断言修
  正）；T3 ExportIccEmbedTests 8/0/0（sRGB 零嵌入 / profileName 推断 /
  TIFF 孤儿清零三轮探针迭代）；XMPExportMatrixTests 6/0/0（Library）。
- Export bundle：322/1/0（T1）→ 330/1/0（T2）→ **338/1/0**（T3）。
- 全套 `--all` 终跑（跑 2，干净轮）：**`TOTAL|2662/16/0|900s EXIT=0`**，
  七 bundle 逐行 = IOP 467/1/0 + IOPParity 362/3/0 + Layers 298/3/0 +
  Library 437/4/0 + Sessions 279/4/0 + Export 338/1/0 + App 481/0/0
  （六未触 bundle 零漂移；Library +1 matrix / Export +27 本波增量）。
- 全套跑 1（收尾轮）两事件（均闭环，详见 SUMMARY 偏差 §8）：① App host
  于 HistoryRowJumpTests 中途 crash（瞬态，隔离复跑 ×2 零复现；假绿计数
  缺陷记 LESSONS L055）；② McpEditingToolsetTests 红 = OQ-6 波及 MCP
  互操作面 → 越界 fix `d2e80d2`（§11）。

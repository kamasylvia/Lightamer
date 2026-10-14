# M6-3-01 DECISIONS — 执行期裁决与偏差登记（2026-10-13/14 夜间批）

> 性质 = executor 执行期就地处置记录（plan 小偏差按纪律入档；结构性偏差 =
> 零——无停手项）。裁决正本 = `M6-3-CONTEXT.md`；plan = `M6-3-01-PLAN.md`
> 修订版。

## §1 EXIF probe 双态登记（OQ-2② 落位）

**结论 = probe 失败 → v1 gain map 档无 EXIF。**

- 执行期探针（T2，独立 swiftc 脚本即弃 /tmp，同 F5 缝形态）：
  `CGImageMetadataSetValueWithPath(meta, nil, "{TIFF}/Software", …)` **返回
  false**（路径被拒——`{TIFF}/…` 属性路径语法不是 CGImageMetadata 的合法
  tag path），且重写后 `kCGImagePropertyTIFFDictionary` 读回无 Software 键。
- 处置 = 编码器不设该座位（代码中无死尝试）；Software 签名的存活座位 =
  **`xmp:CreatorTool`**（F5 亲证序列化），探针结论已固化在
  `ExportGainMapEncoder.primaryXMP` doc comment。
- 后果对账：gain map 档无 EXIF round-trip（六格式矩阵唯一 additive 档偏离，
  OQ-2 裁决预授权）；EXIF Software 的 `{TIFF}` 座位事实（L054）不适用于本
  档——分账登记。
- 测试面：`testGainMapArmSkipsTheICCStrip`（profile 在位 = 容器全活）+
  rewrap 双断言法（hdrgm/Software/M aux/MPF 全存活）= 「probe 失败形态下
  产物容器/aux/XMP 全存活且无 EXIF」的降级负测（AC#2 失败臂）。

## §2 PixelPipe + LayerCompositeDriver 解封申报（KD-2 9 hunk 逐 hunk 对照）

`git diff 55eb8f3c..c077784a` hunk-header 审计：

| # | 文件:hunk | 对应清单项 |
|---|---|---|
| 1 | PixelPipe.swift `@@ -154` | hunk 1 属性声明（tailFormatFloatOverride 同位） |
| 2 | PixelPipe.swift `@@ -1098` | hunk 6 runDrtTailLeg tailPipe 继承 |
| 3 | PixelPipe.swift `@@ -1595` | hunk 7 processRec uncached 腿 EotfBox 位回调（唯一捕获点） |
| 4 | PixelPipe.swift `@@ -2080` | hunk 2 process additive 缺省参数 |
| 5 | PixelPipe.swift `@@ -2093` | hunk 3 process 内赋值 |
| 6 | PixelPipe.swift `@@ -2142` | hunk 4 processComposite additive 缺省参数 |
| 7 | PixelPipe.swift `@@ -2154` | hunk 5 processComposite 传递进 driver |
| 8 | LayerCompositeDriver.swift `@@ -204` | hunk 8 composite additive 缺省参数 |
| 9 | LayerCompositeDriver.swift `@@ -568` | hunk 9 terminalPipe 赋值（composite 导出 capture 活性承载） |

恰 9/9，超清单触点 = 零。FULL 缓存臂未加判定（export 无缓存腿恒走 uncached
臂单处；editor 视口恒 nil capture——plan 缓存臂「至多 +1 处」授权未行使）。
`.metal` 零 diff 维持。

## §3 执行期偏差清单（plan 小偏差就地处置，晨审可推翻）

1. **捕获判定改 `box is ModuleBox<EotfBox>`**（plan 原文 `box is EotfBox`）：
   pieces 持有的运行时类型是包装类 `ModuleBox<EotfBox>`，裸类型判定恒假——
   T1 首轮测试抓出（capture 未触发）；wrapper 对 EotfBox 恒非
   TailOrderedBox（post-four 只包 Post-four 集），判定精确。commit T1 body
   已记。
2. **rewrap 换 `CGImageDestinationCopyImageSource`**（T2 首实现为
   `AddImageFromSource`）：执行期探针实测 AddImageFromSource **重编码主图并
   丢弃 MPF 副图**（产物 1268B vs 原件 15723B）；CopyImageSource 保容器逐字
   段存活（aux 3072B / MPF / isoURN / hdrgm 全在，ImageIO 重写段移位后的
   内部偏移）。F5 spike 原文即 CopyImageSource——首实现误用 API，修正归位。
3. **MPF 字节扫模式改 payload 形**（`"MPF\0MM\0*"`）：段长字节隔在 FF E2 与
   payload 之间，marker+payload 拼接模式永不命中（探针 dump 定案）；测试
   helper 注记在案。
4. **box 为常驻 actor 属性**（plan「测试注入腿时为 nil」读解 = 空箱）：注入
   腿永不 stash → 箱恒空 = 零行为，与 plan 意图一致；常驻使 actor 清理路径
   无条件化 + 泄漏探针可观测（`gainMapBoxForTesting`，inFlightCountForTesting
   同位）。plan 内 KD-3 括注与泄漏负测「注入失败」措辞的张力由此读解消解。
5. **CI 上下文走 `CIContext(mtlCommandQueue: captureQueue)`**：plan KD-2 断言
   「GPU→GPU 同设备无 L014 fence 需求」——本实现取更强形态：CI 上下文建在
   capture blit 的同一条路由队列上，同队 FIFO 排序消除跨队竞态（无 CPU 读回
   断言维持）。SDK 探针证实 `CIContext(mtlCommandQueue:options:)` 在案。
6. **aux 描述字典键 = 纯字符串**（"PixelFormat"/"Width"/"Height"/
   "BytesPerRow"）：SDK 无对应 CFString 常量（头文件 grep 定案）；测试按字符
   串键断言，'L008' 以 bigEndian fourcc 解码比对。
7. **App 面测试 9 法 vs plan「8 法」**：五维门拆 5 法（plan 文本也按维度
   分列）+ 复位 + 装配/兜底 + enqueue + 默认关 = 9；SC 带 +28..34 内
   （34 实值），全套预期 3759 ∈ 3753..3759。BUNDLE-MAP 行已按终态登记。
8. **容器组 4 法保持 plan 口径**（MPF 与 ISO 分列两法）：T2 首轮曾并档为 3
   法，对账发现即拆回——总数 25 与 KD-7 一致。
9. **run-face 复核在 `makeRunAssembly` 内复位 + `RunAssembly.gainMapAutoReset`
   携带 blocked 维度**（C-2 落点）：model 层纯装配缝内复位（视图只 toast）；
   toast 文案复用对应维度的 unavailable 键（plan 5 键清单不扩，V14 显式
   switch 返回静态键 + 显式 `String.LocalizationValue(key)` 包装）。
10. **capture 测试 sizing 显式 longEdge 48**：gainVariant 缺省 original 时
    capture 面 = 全幅（96×64）——非缺陷，断言对齐 entry-plane 语义。

## §4 band 容差与 CI 黑盒漂移注记（含 S1 漂移伞）

- **gain 语义 band**：uniform 平面 HDR = 线性解码基值 × 2^k → GainMapMin ==
  GainMapMax ≈ k；本批实测 **2.0 ± 0.02 量级**（容差带 0.5 极宽裕）。首轮
  探针曾测 3.2167 = log2(encoded128×4 / linear0.216) 精确值——fixture 填了
  sRGB 编码值所致，修正后即归位；该事故**顺带证明 CI 确实先解码基面再取比率**
  （E4 物理约束的运行时反证）。
- **S1 基面保真漂移伞（预案启用情况 = 未触发，band 已预登记）**：基面保真法
  的断言形态 = 五采样点 × 四通道 **逐点 ±1 LSB band**（两黑盒编码器 CI 内部
  JPEG vs ImageIO JPEGEncoder 的跨实现相等仅本 host 单次亲证；macOS 升级
  任一编码器重调只应消耗 band 而非假红）。首跑逐点 delta = 0/1 LSB 内通过。
- **gold 钉法纪律**：全套无字节级全量断言（容器 = 结构 marker 扫 + aux 字典
  读回 + XMP 字节扫命名空间键；checker 关注点 6 口径）。

## §5 headroom<203 默认禁用 UX 注记

默认 record peak = 100 → checkbox **默认灰** + 「将 DRT Peak 提升至 203 nits
以上以启用（低于 SDR 参考白无 HDR 余量）」文案。诚实语义：SDR 参考白下无 HDR
余量，gain map 档不可达不是缺陷态。与 OQ-5 生效值文案一致；用户预期管理 =
「UltraHDR 是 DRT Peak 拉高后的选项」。

## §6 box fresh-seq + actor 清理语义（M1——plan 假事实作废确认）

plan 原文「token 复用 = 覆盖写」为假事实（retry = `seqCounter += 1` fresh
seq，旧 key 永不被覆盖）已在 plan 修订版作废；本批按 M1 修订语义落地：
stash（render 腿，key = snapshot.seq）/ consume+clear（encode 腿一次取）/
clear（finish / finishCancelled / retry 入队前——幂等）；generation 换代经
gate ① → finishCancelled 汇入。泄漏负测 = failed + cancelled 双路终态箱空
（4×4 proxy 面，计数断言）。

## §7 encoding 门⑤ 裁决增补引用

validate 第五门（st2084/hlg 拒）= CONTEXT「裁决增补」节 D-M6-3-7（评审 M3
回注，orchestrator 夜间授权批裁准）；本批按生效值落地三处：validate 门 +
UI 五维门 `.encoding` 维 + 负测（validate/panel 各一）。晨审推翻路径 =
plan 风险节三处回退 + 本文豁免登记（当前无豁免）。

## §8 待供件清单

无（无源待核标注零项；中文标注仅本文档裁决引用，均有源）。

# Phase 8: HDR/Stacking & Effects iops - Context

**Gathered:** 2026-09-27
**Status:** Draft for planning — 12 项 OQ 全按推荐自动裁决〔晨审追认〕（D-08-CONTEXT-1..12，追认清单表见 decisions 末）；Phase 7 移交清单（AI mask 消费端四面对位）+ Phase 12 移交清单五条（HDR 域 LUT 精度条目消费）已逐条对位。输入偏差注记见 08-DISCUSSION-LOG「输入偏差」节。

<domain>
## Phase Boundary

本 Phase 交付两大能力线 + 一个显示能力：**多源合并/堆栈簇**（HDR merge、focus stacking、average/median 堆栈降噪 —— IOP-HDR-01/02/03）、**32-bit float HDR 管线收口与 EDR 显示**（IOP-HDR-04/05）、**创意效果 iop 簇**（vignette/grain/bloom/dehaze/text overlay —— IOP-FX-01..05）。10 项需求。核心架构事实：

1. **合并/堆栈是文档级服务，不是 in-pipe iop**（D-08-CONTEXT-1/11）——既有 pixelpipe 的一切身份机制（`PipeCacheKey`、history stack、`paramsHash`、四管线生命周期 `PipeResolution.swift:10-27`）都是 **per-image 单文档**语义；多源合并没有「N 输入的 iop 实例」能挂进去的缝（实例参数 Codable 进 sidecar 意味着 N 个绝对路径进 history hash——缓存键/可移植性双输）。正确形状 = **独立的合并服务**（读 N 源 → 对齐 → 加权合并 → 落一个新文档 + provenance sidecar），合并产物从那一刻起就是普通单文档，走既有全链（IOP-HDR-04 的字面语义「合并后可继续在 linear Rec2020 中调整」由此免费成立）。
2. **32-bit float HDR 管线大半是既有现状的验证，不是新架构**（D-08-CONTEXT-4）——working space = float32 RGBA linear Rec2020 全链（Phase 2 定案，`PipeResolution.swift` 四管线表 + `WorkingSpace.swift`）；32-bit float TIFF/EXR **读**已由 RAW-03 交付（`LightamerCore/Sources/Decode/RAWDecoder.swift:158-161`，bpp=32/96 float32 RGB TIFF + bpp=32/128 float32 RGBA EXR 保深直通）；32-bit float TIFF **写**已由 Phase 11 交付（EXP-01）；scene-referred tone mapping（filmicrgb/sigmoid，Phase 3）本来就处理 >1.0 值域。**本 Phase 不新发明「HDR 管线」——合并产物进常规管线 + EDR 显示开关就是 HDR-04/05 的全部新面。**
3. **EDR 是显示腿 opt-in 开关，永不进 export 链与 history**（D-08-CONTEXT-12）——viewport 现状 `.bgra8Unorm`（`App/Sources/Lightamer/UI/EditorMTKView.swift:20-21` 注释明确「`.rgba16Float` reserved for the Phase 8 EDR viewport」）；EDR 路径 = `CAMetalLayer.wantsExtendedDynamicRangeContent` + headroom 查询（`NSScreen.maximumExtendedDynamicRangeColorComponentValue`）+ extendedLinear 色彩空间（13-2 已交付 `LinearVariantCache` + extendedLinearSRGB workalike 单例）；SDR 显示腿（filmicrgb/sigmoid → gamma/colorout 终端三件套）**逐字节不变**。HDR 导出深度（HEIC gain map / AVIF 10/12-bit PQ/HLG）defer——ROADMAP §Phase 8 Notes 原文「full HDR export can lean on Phase 11」。
4. **V50Order 槽位已预留，效果簇是零迁移接入**——`LightamerCore/Sources/Foundation/V50Order.swift:48`（hazeremoval 14.0）、`:147`（bloom 61.0）、`:151`（grain 65.0）、`:161`（vignette 68.0）四槽在表；text overlay 是唯一需新槽位的 iop（非 dt 行，skinSmooth 66.5 先例——07-DISCUSSION-LOG 终节「非 dt 行纪律：只增不改、V50OrderTests strip-to-93 零移动钉常驻」）。yiyin borders 76.0 / watermark 77.0 终端尾窗（`V50Order.swift:171-172`，Phase 8-yiyin 执行序交付）不动。
5. **Phase 7 移交的 mask/层栈面是 ghost 抑制与效果蒙版化的现成消费端**（07-DISCUSSION-LOG.md:93-100）——①`RasterMaskRef`（raster 通道唯一入口）原文点名「Phase 8 HDR merge/focus stack 若需蒙版限定（如 ghosting 抑制区），直接消费此形态」；②层栈 API 面（`LayerStack` mutation + `MaskSpec` 三 payload ⊗ `MaskCombiner.effectivePlane` 装配）让效果 iop（vignette/bloom/text overlay）天然可挂层蒙版，零新机制；③缓存零新类（maskPlane/blendTriple 前缀键 + enforceBudget 五档）。
6. **dt 移植参考全部在库**：`src/iop/vignette.c`（1105 行，参数面 :57-72，OpenCL 腿 `:851` 走 `data/kernels/extended.cl:308` vignette kernel）、`src/iop/grain.c`（558 行，CPU-only，`noise_generator.h`；scale 参数即「~ISO of the film」语义 `:542-543`）、`src/iop/bloom.c`（399 行，threshold→blur→screen 三段 `:135-180`；`data/kernels/bloom.cl:22-38` bloom_threshold）、`src/iop/hazeremoval.c`（979 行，暗通道先验；`data/kernels/hazeremoval.cl:22-163` box_min/max_x/y + transision_map + dehaze 四 kernel）、`src/iop/watermark.c`（1561 行，text/SVG 参数结构参考）。**HDR merge / focus stacking / 堆栈降噪在 darktable 无对应 iop**（dt 生态走外部 hdrmerge/enfuse 工具）——这三项以算法文献为移植正本（Robertson02 / MTB / enfuse 式金字塔融合），golden 用合成 fixture 数值断言而非 dt 交叉对照。
7. **多文件编排入口 = Phase 9 Session 面既有能力**——grid 多选（SessionBrowserView）+ `SessionTreeScanner.isExcludedDirectory` 排除语义（13-3 验收实锚）+ `.lra` sidecar 同目录惯例 + one-way 格式锁（schemaVersion 前瞻 + UInt64String decimal String，CONVENTIONS Phase 2 增量）。合并产物落位与浏览可见性规则是 research 头号 P0（RQ-08-3）。

**Phase 8 不做**：

- **HDR 导出深度（HEIC gain map / AVIF PQ/HLG 10/12-bit）**——Phase 11 增强位（ROADMAP Notes 原文）；本 Phase 只交付 EDR 预览（IOP-HDR-05 SC#3 字面）
- **Mertens exposure fusion 输出模式**——输出非线性融合图，与 scene-referred 文档语义不合（D-08-CONTEXT-1 理由节）；v1.1 可选输出模式候补
- **深度学习 focus stacking / 深度图估计、AI ghost 去除自训模型**——v2；pluggable 升级缝保留（D-08-CONTEXT-2 Reversibility）
- **光流对齐 refine（亚像素/大位移）**——v2；v1 对齐 = MTB + EXIF 焦距/光圈一致性预检
- **EXR 写出**——零新 SPM 依赖红线（ImageIO 不写 EXR）；合并产物落 32-bit float TIFF（native `CGImageDestination`，EXP-01 既有能力）
- **全景拼接/panorama**——不在需求集（IOP-HDR 无此项）
- **HDR→SDR 新 tone mapping 算法**——用既有 filmicrgb/sigmoid（Phase 3）；dt `globaltonemap.c`/`tonemap.cc` 不移植
- **tonemap 23.0 / clahe 71.0 / overlay 16.7 等 v50 legacy 槽位模块**——表内占位非本 Phase 需求（REQUIREMENTS 无对应条目）
- **跨会话堆栈编排 UI / 自动 bracket 分组**——v1 = 用户在 grid 多选手动成组（同一会话内）；跨会话/自动分组 defer
</domain>

<decisions>
## Implementation Decisions

> 12 项 = discuss 起草识别的 OQ，全部按推荐项自动裁决〔晨审追认〕。晨间任一推翻 → 回注 planner 重开受影响面（推翻代价见追认清单表）。

### D-08-CONTEXT-1: HDR merge = 线性域加权合并（Robertson02 族）+ MTB 对齐 + 共识权 ghost mask；Mertens 否决为主路径
- **裁决**：①**合并数学 = 线性域真 HDR 合成**：对已线性化的 RAW bracket（同机同 ISO/光圈，ΔEV 来自快门——解码后即物理线性，无响应曲线估计需求，与 JPEG bracket 场景本质不同），逐像素按「曝光差高斯权 + 噪声帽权」加权平均，输出 float32 linear Rec2020（Robertson02 族，hdrmerge/OpenCV `createMergeRobertson` 同算法族）；**Mertens exposure fusion（多分辨率分解融合）否决为主路径**——其输出是已融合的非线性显示图，不是可继续调整的线性 HDR 文档，与 IOP-HDR-04「合并后可继续在 linear Rec2020 中调整」字面冲突。②**对齐 = MTB（median threshold bitmap，Ward）**：整数阈值位图 + 位移搜索（含小角度倾转），GPU 友好、对曝光差天然鲁棒；EXIF 焦距/光圈一致性预检前置；光流 refine 不进 v1。③**de-ghosting = 共识权偏离位图**：对每像素偏离合并共识超阈值的源打 ghost mask（位图 + 形态学膨胀），v1 自动生成 + **用户可编辑**——自动 mask 落 `RasterMaskRef` 形态（Phase 7 移交①原义消费），用户编辑走 Phase 6 蒙版面。
- **理由**：真 HDR 输出是 SC#1 字面（「aligned, de-ghosted **32-bit float HDR** image」）；线性域加权是唯一产出物理值域的合并族；MTB 是 hdrmerge/Luminance 的实证主流（手持 ±2-3EV bracket 覆盖面足够，光流是数量级更贵的 v2 面）；ghost mask 消费 `RasterMaskRef` 是 Phase 7 移交清单的**点名兑现**（零新机制）。
- **Reversibility**: 权重函数参数化（σ/帽宽可调）；Mertens 可作可选输出模式后补（服务接口按「N 源 → 1 float32 文档」抽象，融合模式只是末段替换）；光流 refine 可插件进对齐段。

### D-08-CONTEXT-2: focus stacking = 修改 Laplacian 焦点度量 + 多尺度金字塔融合；深度学习深度图否决
- **裁决**：①**焦点度量 = modified Laplacian（SML 族）**逐像素清晰度图（每源一张 focus measure map）；②**融合 = enfuse 式 quality-weighted 拉普拉斯金字塔**（soft 权重过渡，无硬深度边界——回避深度图 inpaint 的全部复杂度）；③对齐复用 D-08-CONTEXT-1 的 MTB 底座（对焦轨微位移场景）；④深度学习深度图（Zerene/PicNoMore 类）v2，pluggable 缝留。
- **理由**：SC#2 只要求「clean combined output with correct alignment」——金字塔融合是该验收的最低复杂度实证路线（enfuse 十余年野外验证）；深度图路线需要深度估计 + 边界修复两个新算法域，v1 收益/成本倒挂。
- **Reversibility**: 度量算子可换（SML/tenengrad 枚举）；金字塔层数参数化；深度图路线日后可作第二融合后端插入同一服务接口。

### D-08-CONTEXT-3: 堆栈降噪 = average（默认）/ median / sigma-clipped robust 平均三模式；时域降噪同算子族
- **裁决**：①默认 **average**（线性域数学最正——N 张降噪 √N 倍、物理期望不变）；②**median** 模式（离群鲁棒，运动场景）；③**sigma-clipped robust 平均**（星野/长曝光场景，dt `denoiseprofile` 生态外的主流堆栈降噪模式）；④三种模式 = 同一合并服务的权重/聚合算子变体（与 HDR merge 共享对齐段与服务骨架，只换末段）；时域降噪不另立模块（视频域概念，堆栈降噪已覆盖其静态等价物）。
- **理由**：IOP-HDR-03 字面就是「average/median」双模式 + robust 变体是同类需求的标准第三腿；共享骨架 = 08-3 plan 的实现经济学（对齐段零重写）。
- **Reversibility**: 聚合算子枚举 additive；第四种模式（如时域 OdB）纯增列。

### D-08-CONTEXT-4: IOP-HDR-04 = 零新管线架构；验证矩阵 + 缓存预算复核 + HDR 域 LUT 精度消费
- **裁决**：①**不新建任何管线变体**——float32 RGBA linear Rec2020 全链是 Phase 2 既有（事实 2），合并产物按普通文档进四管线生命周期；②HDR-04 的交付物 = **验证矩阵**：合并文档 → exposure/filmicrgb/sigmoid/toneequal 全链数值 parity（HDR stack torture 图已在 Phase 2 golden harness 门内——ROADMAP:60）+ preview 管线 float32 平面内存预算实测（2560px float32 ~70MB/平面已在 `PipeResolution.swift` 注记，enforceBudget 五档零改前提下复核）；③**消费 Phase 12 移交④/遗留#4**：LUT rgba32Float 升格预案（rgba16Float 1e-3 相对容差先例）在 HDR 域 LUT 场景的适用性结论写入本 Phase RESEARCH（HDR 文档 + `.cube` DOMAIN remap 的精度口径一次钉死）。
- **理由**：把「HDR pipeline 支持」当新工程做是对 Phase 2 架构的重复建设；验证矩阵才是该需求的实际缺口（合并文档从未流经全链）；LUT 精度分叉是 12-5 明文移交的消费义务。
- **Reversibility**: 验证矩阵是测试资产（纯增）；若预算实测超限，enforceBudget 阈值注入缝已就位（Phase 2 交付）。

### D-08-CONTEXT-5: vignette = dt 参数面 verbatim 移植（槽位 68.0 已预留）
- **裁决**：①参数面 = `vignette.c:57-72` 全表：`x/y`（中心，±1.0）、`scale`（fall-off start，% 最大边）、`falloff_scale`（fall-off radius）、`brightness`（±1.0 亮度衰减强度）、`saturation`（±1.0 饱和衰减强度）、`whratio`（宽高比）、`shape`（形状幂）、`unbound`（裁剪语义）、`autoratio`；②数学 = `vignette.c` process（:694 起）+ `extended.cl:308` vignette kernel 逐段移植为单一 Metal kernel（径向 falloff 一次算完，无多 pass 依赖）；③dithering 参数不移植（dt 三态 dither 是 8-bit 输出域补丁；本管线 float32 全链 + dither 75.0 既有终端模块承担同职责）；④槽位 = `V50Order.swift:161` 68.0 既有（< terminalTailFloor 70.0 → 可挂层蒙版）。
- **理由**：dt 对标是项目 LOCKED 目标；68.0 槽位预留使接入 = 注册 + kernel，零表迁移；dither 移植是重复建设（管线深度不同）。
- **Reversibility**: 参数 additive；dithering 三态日后可补（kernel 参数化）。

### D-08-CONTEXT-6: grain = dt 参数面（scale≈ISO 语义）+ 确定性随机种子（L013 纪律）
- **裁决**：①参数面 = `grain.c` 三滑杆：`scale`（coarseness——dt 语义即「~ISO of the film」，`:542-543` tooltip 明文；**不另设 ISO 感度参数**，ISO 维度已内嵌于 scale 语义）、`strength`、`midtones_bias`；②噪声 = 确定性**白噪声 Luma 域**注入：seed = `StableHash(instance params ⊕ image stable id)`（FNV-1a 64，L013 纪律）——同输入同参数逐字节可重现，这是 golden 测试与 PipeCacheKey 缓存键的**双重前提**；dt 的 CPU `noise_generator.h` 谱形（:312 「scaled to stay just inside [-1,1]」）为移植正本；③dt 无 OpenCL 腿（grain.c process_cl = 0），Metal kernel 为自研直译；④槽位 = `V50Order.swift:151` 65.0 既有。
- **理由**：随机 iop 不确定性 = 缓存键失效 + golden 不可冻结——确定性种子不是风格选择而是管线契约；scale≈ISO 合一避免双滑杆语义重叠（dt 实证面）。
- **Reversibility**: seed 派生公式可调（版本化进参数）；谱形可扩（gaussian/poisson 枚举）。

### D-08-CONTEXT-7: bloom = dt 三段结构 verbatim（threshold → blur → screen blend）+ scene-referred 阈值适配
- **裁决**：①结构 = `bloom.c:135-180` 三段直译：亮度阈值提取（`bloom.cl:22-38` bloom_threshold）→ 大核 Gaussian（`gaussian.cl` 族惯例，多 pass 或降采样级联——RQ-08-9 定）→ **screen blend** 回原图（dt 同款线性友好混合）；②**阈值域适配**：dt threshold（0-100，显示域习惯值 90）映射为线性域 luminance 阈值（scene-referred 管线里线性亮度阈值才是物理语义——RQ-08-9 给换算曲线与默认值实测）；③ brilliance/radius 参数面照 `bloom.c`；④槽位 = `V50Order.swift:147` 61.0 既有。
- **理由**：三段结构是 SC#4「match references」的移植正本；screen blend 在线性域数学上良定义（1-(1-a)(1-b)），无需域翻译；multi-scale（unsharp 式多半径叠加）是 v2 候补非 v1 需求。
- **Reversibility**: 阈值映射曲线参数化；blur 实现可换（MPS 与手写 kernel 择优，STACK.md「MPS selective use」条款）。

### D-08-CONTEXT-8: dehaze = dt hazeremoval 移植（暗通道先验 + box 滤波族）；CLAHE 否决
- **裁决**：①算法 = **暗通道先验**（He 算法族）——`hazeremoval.cl:22-163` 四 kernel 全表直译：`box_min_x/y` + `box_max_x/y`（暗通道/亮通道 box 滤波近似）→ `transision_map`（透射率图）→ `dehaze`（大气光 + 透射率还原）；参数面照 `hazeremoval.c`（strength/distance 族）；②**CLAHE 否决**（对比度增强的局部直方图均衡，无大气散射物理模型——除雾语义不合；v50 表 `clahe` 71.0 是 legacy 占位非本需求）；③槽位 = `V50Order.swift:48` 14.0 既有（dt 同位，scene-referred 前段——除雾在几何/色彩校正前生效的管线序语义照 dt）。
- **理由**：kernel 移植表逐文件对应（CONVENTIONS「`.cl` → Metal 移植」纪律的标准场景）；14.0 槽位在表 = 零迁移；物理模型除雾是「match references」的唯一正解。
- **Reversibility**: strength 参数化；引导滤波精化（guided filter 替代 box）可后补升级。

### D-08-CONTEXT-9: IOP-FX-05 text overlay = 独立轻量 iop（新非 dt 槽位 <70.0）；yiyin watermark 77.0 不动——ROADMAP「order 77」为编写期冲突
- **裁决**：①**IOP-FX-05 = 新 text overlay iop**：单段/多行文本（CoreText 渲染 → 纹理 → 合成），参数面 = 内容/字体（复用 YiyinFontStore 字体管理面）/字号/颜色/位置/旋转/不透明度/描边阴影，能力边界 = 挂层蒙版可局部化；②槽位 = **新非 dt 行**（skinSmooth 66.5 先例：只增不改 + strip-to-93 钉），候选 66.x 段——**必须 < 70.0**（`LayerCompositeDriver.terminalTailFloor=70.0`，非终端段才有层蒙版资格，这是与 yiyin 终端水印的本质分工）；③**yiyin `WatermarkModule`（77.0，终端段）零改动**——它是「最终出图水印」（模板引擎/EXIF 字段/品牌归一化，Phase 8-yiyin 三 plan 交付）；text overlay 是「编辑期文字层」（需求原文「作为 iop 层，独立于 yiyin 面板的最终出图水印」）；④**ROADMAP SC#4「watermark iop (order 77)」与 Phase 10 yiyin「watermark at order 77」是 ROADMAP 编写期冲突**（yiyin 定序前写的）——按 IOP-FX-05 需求原文（REQUIREMENTS:140 黑体「独立于」）裁决 77.0 归 yiyin，text overlay 走新槽位。**此项晨审特别过目**：若用户裁定 FX-05 由 yiyin watermark 已交付（零新代码），则 SC#4 相应改写且蒙版能力缺口登记接受。
- **理由**：需求原文双重锁定（「iop 层」+「独立于 yiyin」）；<70.0 槽位是「iop 层」语义的技术必要条件（终端段蒙版不可达——Phase 8-yiyin splitTerminal 语义）；YiyinFontStore/YiyinTextRenderer 复用让增量可控。
- **Reversibility**: 槽位 additive；若晨审改判「FX-05 = yiyin 已交付」，删除本 iop 需求零回退成本（模块未建）。

### D-08-CONTEXT-10: 波次分解建议 = 5 plans / 3 waves（W1/W2 双 plan 并行；08-1 为堆栈簇依赖根）
- **裁决**（给 planner 的依赖序基线）：**08-1**（堆栈/合并服务底座 + HDR merge：多源文档服务 + MTB 对齐 + Robertson 加权 + ghost mask + 文档落位/provenance + HDR-04 验证矩阵——IOP-HDR-01/04，堆栈簇依赖根）∥ **08-2**（创意效果簇 A：vignette + grain + bloom——FX-01/02/03，独立 GPU 腿）→ **08-3**（focus stacking + average/median stacking：复用 08-1 对齐/服务骨架换聚合段——IOP-HDR-02/03）∥ **08-4**（EDR 显示输出：rgba16Float 视图腿 + headroom + SDR 不变断言——IOP-HDR-05，独立显示腿）→ **08-5**（dehaze + text overlay + 收口签核：FX-04/05 + HDR-04 LUT 精度结论 + 全 Phase 验证）。
- **理由**：08-1 与 08-2 无依赖（堆栈簇 vs 效果簇正交）；08-3 依赖 08-1 骨架；08-4 独立显示腿可并行；08-5 收尾吸收两波验收回注余量 + 签核义务（C 档第 3 停）。
- **Reversibility**: plan 边界可并/拆；刚性 = 08-1 先行（08-3 前置）、08-5 收口含签核。

### D-08-CONTEXT-11: 合并产物 = 会话内新文档（32-bit float TIFF）+ provenance sidecar；源文件永不可变
- **裁决**：①合并/堆栈产物 = **新文档文件**（32-bit float TIFF，native `CGImageDestination`——EXP-01 既有写面；文件名带后缀模式如 `<base>_hdr.tif`）+ **同目录 `.lra` sidecar**，sidecar 记 provenance（additive 新字段：源文件引用集 + 算法 kind/参数 + 源稳定哈希集，one-way 格式锁 + UInt64String 纪律照抄）；②产物**进浏览集**（grid 可见可继续编辑——SC#1「continue through the normal edit pipeline」的字面前提），落位目录与 `SessionTreeScanner.isExcludedDirectory` 排除语义的精确对位（会话根 vs 保留子目录的可见性差异，D-09-CONTEXT-2）= research P0（RQ-08-3）；③**源文件永不可变**（CONVENTIONS 非破坏性红线）——合并服务对源只读；重复合并 = 生成新文档不覆盖（幂等性防抖 RQ-08-3）；④合并运行形态 = 后台 Task（非交互管线），取消/进度面接 Phase 11 队列惯例（独立 MTLCommandQueue 低优先级先例）。
- **理由**：文档级产物 + provenance 是 C1/Lr HDR 合并的既有用户预期；float TIFF 是零新依赖下的唯一保真载体（EXR 写出被依赖红线封死）；provenance 入 sidecar 让「合并图」可溯源可重建（删产物后从源重跑同参合并）。
- **Reversibility**: sidecar 字段 additive；落位目录可迁（产物是普通文件，mv 即迁）；provenance 格式升级走 schemaVersion。

### D-08-CONTEXT-12: IOP-HDR-05 EDR = 显示腿 opt-in 开关（rgba16Float + headroom + extendedLinear）；SDR 腿逐字节不变；HDR 导出 defer
- **裁决**：①**开关形态 = viewport 级 HDR 预览 toggle**（非文档参数、不进 history/sidecar/export——与 soft proof 的显示腿 runtime override 同位语义，13-2 SoftProofStage 先例）：开启时 `EditorMTKView` 切 `.rgba16Float`（`EditorMTKView.swift:20-21` 预留位兑现）+ `wantsExtendedDynamicRangeContent = true` + 显示色彩空间切 extendedLinear 系（13-2 `LinearVariantCache`/extendedLinearSRGB workalike 既有面），终端段 gamma/SDR 钳制旁路；关闭时与今日输出**逐字节一致**（回归断言形状）；②headroom 语义 = `NSScreen.maximumExtendedDynamicRangeColorComponentValue` 查询 + >1.0 值域直通（「headroom above 1.0 treated correctly — not as a different color space」SC#3 原文）；XDR/外接 HDR 双实测进 Manual-Only；③**HDR 导出深度（HEIC gain map / AVIF PQ/HLG）defer Phase 11 增强**（ROADMAP Notes 原文授权）；④COLOR-4 风险主战场：EDR 下的色域/亮度标定结论入 research（与 13-2 色彩批的 F-12-5-2 dt-GUI 参考环境同源）。
- **理由**：显示腿开关是 EDR 预览的行业标准形态（WWDC21/10161 + WWDC22/10114 惯例）；「SDR 逐字节不变」是把 COLOR-4 回归面钉死的最小断言；导出 defer 有 ROADMAP 明文，避免本 Phase 吞 Phase 11 增量。
- **Reversibility**: toggle 独立实现件（视图层）；导出增强日后接 EXP 面不动本 Phase 代码。
</decisions>

### 继承定案（非 OQ，上游已论证、下游不得重开）

- **float32 RGBA linear Rec2020 working space 全链不动**（Phase 2 定案；`PipeResolution.swift` 四管线表）——合并产物与效果 iop 都是常规管线公民，无「HDR 管线分支」。
- **one-way 格式锁 + UInt64String**（CONVENTIONS Phase 2 增量）——provenance sidecar 与一切入盘哈希沿用；`paramsData` base64 惯例不变。
- **StableHash（FNV-1a 64）持久化身份纪律**（L013）——grain seed、provenance 源哈希、ghost mask `maskHash` 全走此纪律；Swift `Hasher` 禁入跨进程身份。
- **GPU 读回纪律**（L014）——合并/堆栈服务的对齐位图/焦点度量读回一律 fence（`drain()` 模式）；07 AI 基建 `AIMaskInput` fence 先例。
- **零新 SPM 依赖**——EXR 写出不做（ImageIO 不写）；blur/box 滤波自研 kernel 或 MPS 择优（STACK.md「MPS selective use」）；CoreText/Core Image 原生面优先。
- **golden-image 纪律**（CONVENTIONS 测试条款）——效果 iop 对照 dt 参考输出；合并/堆栈用合成 fixture 数值 golden（dt 无对应模块，文献算法以解析已知值断言）；HDR stack torture 图全链 gating（ROADMAP:60 既有）。
- **非破坏性 + 源永不可变**（CONVENTIONS）——合并服务对源文件只读；一切产物是新文件。
- **`.xmp` 红线不动**（09/12 两轮澄清后的口径）——合并产物 sidecar 是 `.lra`；不写任何 `.xmp`。
- **V50Order 非 dt 行纪律**（07 移交原文）——text overlay 新行只增不改；`V50OrderTests` strip-to-93 零移动钉常驻。
- **执行纪律**——`.work/config.toml [gsd]`（auto/paused，:77-78）每任务边界检查；C 档门控三点停（research 定稿停 / 每 plan 闭环停 / 签核前停）；单测走 `Scripts/test-direct.sh`。

### 验证与红线（全 plan 写死，执行期不得放宽）

- **合并/堆栈数值 golden**：合成 bracket fixture（已知响应/已知位移/已知鬼影）→ 对齐位移断言精确命中 + 合并结果解析已知值容差断言；禁「看起来对」断言（L020 内容级）。
- **效果 iop golden**：vignette/grain/bloom/dehaze 各自 dt 参考交叉（CPU float64 双写正本先例，12-5 遗留#5 口径）；grain 同 seed 逐字节确定性 + 同参数跨运行逐字节断言。
- **SDR 不变断言**：EDR toggle off == 既有显示输出逐字节；EDR on 永不进 export/history/sidecar 三断言（soft proof 四断言先例形状）。
- **provenance 专项**：sidecar additive 字段 round-trip + 源哈希漂移检测（源文件被改后 provenance 标脏）+ 删产物重合并幂等。
- **L014/L010/L025/面板四件套**：同 09/12-CONTEXT 全套；新面板 D-H1 三件套 + zh catalog 同批（L025）。
- **回归纪律**：每任务全套 suite 绿（现基线 **1636/10skip/0fail**，13-3 验收后）；每任务边界查 `.work/config.toml [gsd]`。
- **性能预算**：100MP 合并/堆栈全程秒表入 perf.md（非交互操作，预算 research 定，RQ-08-12）；效果 iop 预览管线 60fps 预算不回退（既有 perf 基线）。

### Open Questions 晨审追认清单（12 项全按推荐自动裁决）

| OQ | 裁决一句 | 关键理由 | 推翻代价 | Reversibility |
|---|---|---|---|---|
| 1 HDR merge 算法 | Robertson 线性加权 + MTB 对齐 + 共识 ghost mask；Mertens 否决主路径 | SC#1 字面要真 float32 HDR；MTB 是实证主流 | Mertens 主路径 = 输出非线性图，HDR-04 语义崩塌；光流 = 数量级成本 | 权重参数化；Mertens 可后补输出模式 |
| 2 focus stacking | SML 度量 + 金字塔融合；DL 深度图 v2 | SC#2 最低复杂度实证路线；enfuse 野外验证 | DL 深度图 = 新算法域 + 模型训练，违背原生约束 | 度量/融合后端可插拔 |
| 3 堆栈降噪 | average 默认 + median + sigma-clipped 三模式同骨架 | IOP-HDR-03 字面；对齐段共享 | 单模式 = 需求缺口；分实现 = 三倍成本 | 算子枚举 additive |
| 4 HDR-04 | 零新管线；验证矩阵 + 缓存预算 + LUT 精度消费 | Phase 2 架构现状即 HDR 管线 | 新管线分支 = 重复建设 + 双维护 | 测试资产纯增 |
| 5 vignette | dt 参数面 verbatim；68.0 既有槽位；dither 不移植 | dt 对标 LOCKED；槽位零迁移 | 改参数面 = 断 dt 对标 + 参考失锚 | 参数 additive |
| 6 grain | dt 三滑杆（scale≈ISO 合一）+ 确定性种子（L013） | 随机不确定 = 缓存/golden 双崩 | 非确定性 grain = 缓存键失效 + golden 不可冻结 | seed 公式版本化 |
| 7 bloom | 三段 verbatim + 线性域阈值适配；screen blend | 移植正本明确；线性域数学良定义 | multi-scale = v2 面提前吞 | 阈值曲线/blur 可换 |
| 8 dehaze | 暗通道先验移植（14.0 槽位）；CLAHE 否决 | 物理模型是除雾正解；kernel 表全对应 | CLAHE = 语义错位 + 参考失锚 | 引导滤波可后补 |
| 9 FX-05 边界 | text overlay 新槽 <70.0（可蒙版）；yiyin 77.0 不动；ROADMAP 77 冲突按需求原文裁 | 需求黑体「独立于」；层蒙版是本质分工 | 判 yiyin 已交付 = 蒙版能力缺口登记 + SC#4 改写 | 未建则零回退成本 |
| 10 波次 | 5 plans / 3 waves；08-1 堆栈簇根 ∥ 08-2 效果簇 | 正交簇并行；cap 内 | 串行拉长日历 | plan 边界可调 |
| 11 产物落位 | float32 TIFF 新文档 + provenance sidecar；源只读；落位 research P0 | 零依赖唯一保真载体；C1/Lr 用户预期 | in-pipe 多源 iop = 身份/缓存/history 三崩 | 落位可迁；字段 additive |
| 12 EDR | 显示腿 opt-in toggle；SDR 逐字节不变；导出 defer Phase 11 | SC#3 字面 + soft proof 先例形状；ROADMAP 明文授权 | EDR 进 export = 吞 Phase 11 增量 + COLOR-4 面翻倍 | toggle 独立件可拆 |

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/ROADMAP.md` §Phase 8（:135-147——SC#1-4 + Notes：RAW-03 float 读已备 / COLOR-4 双屏实测 / HDR 导出 lean on Phase 11）+ :60（HDR stack torture 图 golden harness 既有）+ :26（Phase 表）
- `.planning/REQUIREMENTS.md` IOP-HDR-01..05（:128-132）/ IOP-FX-01..05（:136-140）/ RAW-03（:25）+ Traceability :373-382
- `.planning/phases/07-ai-modules/07-DISCUSSION-LOG.md:93-140`——**Phase 8 移交清单**（①RasterMaskRef/层栈 API/缓存面 = ghost mask 与效果蒙版化消费端；②skinSmooth 66.5 非 dt 行纪律；③遗留对表）
- `.planning/phases/12-metadata-presets-lut/12-DISCUSSION-LOG.md:48-101`——Phase 12 移交五条（本 Phase 消费其④/遗留#4：LUT float16/32 精度 HDR 域结论入 RQ-08-13）
- `.planning/phases/13-system-integration-distribution/13-DISCUSSION-LOG.md`——13 discuss 风险七条（BPC/extendedLinearSRGB/LinearVariantCache 为 D-08-CONTEXT-12 底座；**Phase 13 移交五条不存在**——13-4 移至最后，偏差注记见 08-DISCUSSION-LOG）
- `LightamerCore/Sources/Pipe/PipeResolution.swift:10-27`（四管线生命周期）+ `LightamerCore/Sources/Decode/RAWDecoder.swift:158-161`（RAW-03 float 读）+ `LightamerCore/Sources/Foundation/V50Order.swift:48/:147/:151/:161/:166-173`（槽位面）+ `App/Sources/Lightamer/UI/EditorMTKView.swift:20-21/:295/:336-339`（EDR 预留位 + D-COL2 显示色彩空间挂接）
- Darktable 移植正本：`src/iop/vignette.c`（:57-72 参数 / :694 process / :851 process_cl）+ `data/kernels/extended.cl:308`（vignette kernel）；`src/iop/grain.c`（:312 噪声谱 / :542-543 ISO 语义）；`src/iop/bloom.c`（:47 threshold / :135-180 三段）+ `data/kernels/bloom.cl:22-38`；`src/iop/hazeremoval.c`（979 行）+ `data/kernels/hazeremoval.cl:22-163`（box_min/max + transision_map + dehaze）；`src/iop/watermark.c`（1561 行，FX-05 参数结构参考）
- `.planning/phases/08-yiyin-border-watermark/`（执行序 08 = ROADMAP §Phase 10 yiyin，STATE 完成账在案）——borders 76.0/watermark 77.0 终端尾窗语义 + splitTerminal 契约，本 Phase FX-05 分工的上游事实；目录与本 Phase（`08-hdr-stacking-effects/`）零冲突
- `.planning/phases/09-session-management/09-CONTEXT.md`（D-09-CONTEXT-2 浏览集排除语义 + SESS-07 真身纪律）+ 13-3 验收锚（`SessionTreeScanner.isExcludedDirectory`）——RQ-08-3 落位对位正本
</canonical_refs>

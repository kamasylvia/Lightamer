# Phase 4 Research: Geometry, Lens & Detail iops

**Researched:** 2026-09-20
**Confidence 汇总：** Darktable 模式映射 = High（crop/flip/rotatepixels/ashift/sharpen/highpass/bilat/lens 源码逐行核过）；ROI 协商 Swift 设计 = High（processRec/PipeCacheKey/ModuleBoxing 现码逐行核过）；Lensfun XML = High（本机 Homebrew lensfun 0.3.4 数据库实测解析）但 C 侧插值语义 = Med；Vision API = High（文档核对，符号约定需 spike）；Detail 模块 golden 路线 = Med（受 L017 dt-cli float 导出缺陷约束，多处走合成参考路线）。

---

## Summary

Phase 4 = 8 个需求（IOP-GEO-01..04 + IOP-DETAIL-01..04），架构验收核心是 **ROI 协商端到端**（ROADMAP SC#4 / D-G5）。核心结论：

1. **ROI 协商是 processRec 的一次结构性改造，不是新模块**。Darktable 用两趟：前向 `dt_dev_pixelpipe_get_dimensions`（pixelpipe_hb.c:3368-3405，逐模块 `modify_roi_out` 链算 buf_in/buf_out）+ 后向递归内 `modify_roi_in`（pixelpipe_hb.c:2085）。Lightamer 的 `IOPModule.modifyROIOut/In` 钩子、`PipeCacheKey.roi` 字段、`ModuleBoxing` erased 转发模式**全部已就位**，缺的只是：① `run()` 里一段前向 ROI 预计算；② `processRec` 里把「identity assert」换成真协商；③ `ModuleBoxing` 补 `modifyROIOutErased/InErased` 两个 erased 方法；④ 输入平面构建器支持带 x/y 偏移的子域渲染。**不改缓存键结构**——roi 已在 key 里。
2. **crop 的正解就是 dt 的正解**：fraction 参数（cx/cy/cw/ch ∈ [0,1]，分辨率无关）+ modifyROIOut 前向收缩 + process 为窗口拷贝。「不实际裁切内存」（D-G2）的正确读法 = **不需要先做全幅 buffer 再拷出窗口**——ROI 协商让 crop 之后的平面按裁切尺寸原生分配（比 dt 还省）；不是「buffer 保持全幅」。
3. **rotate 映射要换参照物**：dt 的 `rotatepixels`（11.0）是 raw 域 45° 旋转模块，位于 demosaic(8.0) 之后但仍是传感器域语义，**Lightamer 管线（CIRAW 已显影输出）不适用**。任意角度旋转/透视的正确参照是 `ashift`（15.0）：单应矩阵前向角点求 AABB（modify_roi_out）+ 逆向角点求输入 AABB（modify_roi_in）+ bilinear warp kernel。Vision `VNDetectHorizonRequest`（angle → 旋转参量）与本机 4 点单应替换其 LSD 自研检测。
4. **镜头校正三层（D-G1）可落地**：(a) CIRAW 内嵌已实证直通（零代码，文档化防双补）；(b) 手动滑块 = 一个融合 kernel（逐通道径向 backward warp + vignette 乘法），默认中性时 ROI/缓存完全中性；(c) Lensfun XML：**本机实测全库仅 4.2MB**（CONTEXT 估 ~30MB 偏大），55 个 xml、schema 平坦（`lensdatabase → lens → calibration → distortion/tca/vignetting`），Foundation `XMLParser` 足够；distortion 模型 poly3(875)/ptlens(4697)/poly5(5)，tca poly3(3265)/linear(6)，vignetting pa(23759)。XML 参数喂给 (b) 的同一 Metal warp。
5. **Detail 四件全部有 Phase 3 底座**：sharpen = GaussianBlur(Deriche IIR) + 软阈值混合 kernel（dt sharpen.c/sharpen.cl 逐式）；local contrast = 03-05 EIGF/guided 大半径分解 + 细节增强（D-G3）；highpass/soften = GaussianBlur 变体（highpass 是 Lab 域反相高通，soften 是 Orton 效果 RGB 线性域——两者域不同，dt 源码定位清楚）；equalizer = 多频段分解 + CorrectionLUT 模式（dt eaw 6 带 edge-aware wavelet，atrous.cl）。
6. **Golden 最大风险是 L017**：dt-cli float 导出对空间变化图像损坏（Plan 03-02 已证）。几何模块（rotate/lens warp）与 sharpen 恰是空间变化算子 → **dt-cli EXR parity 不可作为主轨**，须走 L017 路线①（float64 公式合成参考 + dt 侧 uniform 探针 + 参数采纳实证）。crop/flip 例外（纯索引拷贝，语义零自由度，可直接 dt-cli）。
7. **v50 槽位全部现成**（V50Order.swift 已含 93 条全表）：lens 13.0 / ashift 15.0 / flip 16.0 / crop 24.5 / equalizer 27.0 / highpass 34.0 / sharpen 35.0 / bilat 54.0 / soften 66.0。硬约束：flip(16.0) 必须先于 crop(24.5)（iop_order.c:810-812「crop GUI broken if flip is done on top」）；crop 24.5 排在「最后一个需要扩大 roi_in 的模块」（toneequal 24.0）之后——ROI 协商语义就是这两条注释的机制化。

**给 planner 的切分建议**（Open Questions 前详述）：ROI 协商协议改造必须单独成 plan 且最先做，8 个模块全部消费它；UI overlay 依赖 crop 模块先落。

---

## Implementation Approaches

### 1. ROI 协商端到端（D-G5，架构验收核心）

#### 1.1 现状（代码核过）

- 钩子已定义、默认恒等：`IOPModule.modifyROIOut(_:input:piece:)` / `modifyROIIn(output:input:piece:)`（`LightamerCore/Sources/Pipe/IOPModule.swift:71-76`）。
- `processRec` **完全忽略**两个钩子：递归直传 `roiOut`，并用 assert 钉死恒等不变量——`PixelPipe.swift:549-553` 与 `:586-590`（"pass-through-era ROI identity violated"）。这正是 02-RESEARCH Risk #7 预留的 Phase 4 改造点。
- `PipeCacheKey.roi` 已在键内（`PipeCacheKey.swift:37`），key 由 `roiOut` 构造（`PixelPipe.swift:520-526`）；`levelHash` 只折 enabled 件的 paramsHash，**与 ROI 无关**——ROI 变化天然走 roi 字段失效，params 变化走 upstreamHash 失效，两轴正交。
- `ModuleBoxing` erased 模式已成型（`processErased`/`tileHaloErased`，`ModuleBox.swift:61-74`），补两个 erased 转发是机械活。
- `blit(from:sourceOrigin:size:to:destinationOrigin:)`（`PixelPipe.swift:308-329`）已可复用为 crop 的窗口拷贝。

#### 1.2 Darktable 两趟协议（源码核过）

- **前向**（`pixelpipe_hb.c:3368-3405` `dt_dev_pixelpipe_get_dimensions`）：从入口 ROI 起，按 v50 序遍历，禁用件直通（:3378-3384），启用件 `module->modify_roi_out(module, piece, &roi_out, &roi_in)` 后 `roi_in = roi_out`，逐件盖 `piece->buf_in/buf_out`。这一趟产出**每件的最大平面几何**与管线最终输出尺寸。
- **后向**（`pixelpipe_hb.c:2085-2096`，递归体）：每级 `module->modify_roi_in(module, piece, roi_out, &roi_in)` → 盖 `piece->processed_roi_in/out` → 以 `roi_in` 递归上游。dt 明示约定（各 iop process 注释）：process 收到的输入区域**可能与请求的不同**（框架 clamp 后），模块尽力填充。
- crop 实例（`crop.c:517-560` modify_roi_out / `:576-592` modify_roi_in / `:594-608` process=`dt_iop_copy_image_roi`，`imagebuf.c:188-223` 逐行 memcpy）：fraction→px、min 4px、导出管线才做比例对齐（:533-560，Phase 11 注记）。
- lens 实例（`lens.cc:1697-1790` `_modify_roi_in_lf`）：把 roi_out 四边框点经 modifier **逆变换**，取 6 组坐标（RGB 三通道各自）的 AABB + 插值边距——这就是「warp 类模块按需外扩」的参考实现。
- sharpen **不覆盖** modify_roi_in——dt 靠 tiling 框架的 border 处理（IOP_FLAGS_ALLOW_TILING）。Lightamer 的 D-G5「后向扩展」是自己的语义（无 per-module mask 蒙版栈），由 modifyROIIn 声明 halo 外扩实现，与 03-05 `tileHalo`（4·radius+65 推导）同源。

#### 1.3 Swift 设计

```swift
// ── ModuleBoxing 增补（ModuleBox.swift，机械转发）──
public protocol ModuleBoxing {
    // 既有 processErased / tileHaloErased …
    func modifyROIOutErased(_ roi: inout ROI, input: ROI, piece: IOPiece)
    func modifyROIInErased(output roi: ROI, input: inout ROI, piece: IOPiece)
}

// ── PixelPipe.run 增补：前向 ROI 预计算（dt get_dimensions 直译）──
internal var levelROI: [ROI] = []      // 每件的 OUTPUT roi（= dt buf_out）
internal var bufInROI:  [ROI] = []     // 每件的 buf_in（warp 类模块的全图基准）

// run() 内、processRec 之前：
//   var roiWalk = roi  // 入口 ROI（scale-at-entry，现 :386-403 已算好）
//   for (i, piece) in pieces.enumerated() {
//       bufInROI[i] = roiWalk
//       var out = roiWalk
//       if piece.box.enabled { piece.box.modifyROIOutErased(&out, input: roiWalk, piece: &pieces[i].state) }
//       levelROI[i] = out;  roiWalk = out
//   }
//   // dscIn 盖章从「统一 pieceGeometry」改为 per-level：
//   pieces[i].state.dscIn = IOPBufferDesc(width: bufInROI[i].width, height: bufInROI[i].height)
//   //（toneequal 24.0 < crop 24.5 → 其全图半径语义不受影响；tile 驱动约束「TILE 不得改 dscIn」不变）

// ── processRec 改造（PixelPipe.swift:470-615）──
//   入参不变（position, roiOut, metal）；roiOut 即「本件输出应产生的 ROI」。
//   miss closure 内：
//     var roiIn = roiOut
//     box.modifyROIInErased(output: roiOut, input: &roiIn, piece: &pieces[position].state)
//     let upstream = try await processRec(position: position - 1, roiOut: roiIn, metal: metal)
//     assert(upstream.texture.width == roiIn.width && upstream.texture.height == roiIn.height,
//            "negotiated ROI identity violated")   // 替换 :549-553/:586-590 的恒等 assert
//   disabled 直通分支（:509-515）保持 roiOut 直传（dt :3378-3384 同语义）。
```

**缓存正确性论证**：位置 p 的 key = (imageID, pipeType, position+1, levelHash[p], **roiOut@p**)。crop 参数变化 → levelHash ≥ crop 全翻（params 轴失效）；裁切窗口变化即 params 变化；入口 scale 变化（窗口跨档）→ 全链 roi 字段变化（ROI 轴失效）。「上游 hash 变化自动失效下游」性质不破坏，因为 key 里 roi 与 upstreamHash 同时在。

**输入平面（position 0）子域渲染**：crop 后向传导到 base case 时 `roiOut` 带偏移——`renderToTexture` 需新增带 ROI 变体：`ciImage.cropped(to: CGRect(x·s, y·s, w·s, h·s))` + 按 roiOut 尺寸 transform 渲染（`PixelPipe.swift:496-501` 现只按 longEdge 全幅）。收益：decode 腿少渲 + 输入平面缓存按窗口记字节。CI 是 lazy 的，crop 子域预期直接省 demosaic 后的重采样量（是否省 demosaic 本身属 CIRAW 内部，Phase 1 spike-b 上界可接受，不做承诺）。

**sharpen 后向扩展的具体值**：`modifyROIIn` 外扩 `ceil(3σ)`（可见能量 99.7%）起步，用 GaussianBlurTests 的脉冲包络校准；文档注明与 03-05 tileHalo（4r+65，IIR 跑道 14.5σ）的差异——ROI 外扩面向「不取全图」的架构验收，tileHalo 面向「分块==整幅 <1e-6」，两个常数服务两个精度门。⚠ D-G5 的「内存断言（sharpen 只按需外扩不取全图）」需要一个**子窗口调用者**来观察——`RenderPipeline.process` 目前没有「对最终输出请求子 ROI」的入参，补一个 `roiHint: ROI? = nil`（nil=全幅）即可，测试用它断言上游平面尺寸 = 输出窗口 + halo ≪ 全图。

**crop 拖动时的缓存行为（gotcha）**：拖动中每次 roi 变化 → ≤crop 全部位置键变（上游内容虽是逐点算子，但 ROI 窗口不同即不同 key）→ 全链 miss。dt 同样如此（它靠模块便宜硬扛）。**推荐 UI 层规避**：裁切编辑期间以「crop 临时 disabled」live 渲染（§8），整幅平面全程缓存命中，commit 才渲染裁切后的窗口一次——与 C1/Lr 的「编辑时全图 + 暗膜」交互一致，且 60fps 无虞。

Confidence：**High**。改造面集中在 `PixelPipe.run/processRec` + `ModuleBoxing` + `renderToTexture` 变体，有 PipeCacheTests 全链语义测试网可先行加固（先加 ROI 变体用例再动 processRec）。

---

### 2. crop + rotate + flip（IOP-GEO-01/02/04）

#### 2.1 crop（IOP-GEO-01，槽位 24.5）

- **Params**（dt `crop.c:61-69` 直译，fraction 语义分辨率无关、多分辨率天然成立）：
  ```swift
  public struct CropParams: Codable, Hashable, Sendable {
      public var left: Float    // cx ∈ [0, 0.99]（dt MIN_CROP_SIZE=0.01，crop.c:44）
      public var top: Float     // cy
      public var right: Float   // cw
      public var bottom: Float  // ch
      public var ratioN: Int    // -1 = free（dt 默认）
      public var ratioD: Int    // -1 = free；(n,d) ∈ 预设表 + original
  }
  ```
- **modifyROIOut** = crop.c:517-531 直译（`x=max(0,int(w·cx))`，`width=max(4,int(w·(cw−cx)))`）；**modifyROIIn** = :576-592 直译（偏移回加 + clamp 到 bufIn）；**process** = 同尺寸窗口拷贝（roiIn==roiOut 尺寸）→ 复用 `PixelPipe.blit`（L008：blit encoder 显式 endEncoding 已合规）。不 blit 直接复用上游纹理不可行——FULL ping-pong scratch 会复用该平面，缓存语义要求独立产物。
- **导出精确对齐**（crop.c:533-560 的 ratio aligner/奇偶收缩）：Phase 11 EXP-03 的事，Params 位保留，本阶段不实现（注释标注）。

#### 2.2 rotate / perspective（IOP-GEO-02，槽位 15.0「ashift」语义）

- **参照物勘误**：dt `rotatepixels`（11.0）的 modify_roi_out 全是 raw 域 45° 旋转数学（rotatepixels.c:191-231，Pythagoras 内接矩形 + `piece->iscale`），前置假设是「demosaic 之后、传感器像素网格上」——Lightamer 输入是 CIRAW 已显影域，**不移植 rotatepixels，参照 ashift**（15.0）。11.0 槽位留空。
- **几何**：单一 3×3 单应。纯旋转 = 特例（绕中心旋转 + 中心平移）；透视 = 4 点单应（§3）。dt 的 `_homography()`（ashift.c:1142 起 forward / :1213 起 inverse 调用）把 (rotation, lensshift_v/h, shear, f_length_kb, orthocorr, aspect) 合成为矩阵并内嵌裁切角 (cl/cr/ct/cb)。Lightamer 简化：
  ```swift
  public struct AshiftParams: Codable, Hashable, Sendable {
      public var rotation: Float      // 度，±45（dt ROTATION_RANGE_SOFT）
      public var lensShiftV: Float = 0
      public var lensShiftH: Float = 0
      public var shear: Float = 0
      public var fLength: Float = 28  // 透视模式焦距基准
      public var cropFactor: Float = 1.0
      // 内嵌裁切（dt cl/cr/ct/cb 同构，默认 0/1 全幅）
      public var cl: Float = 0; public var cr: Float = 1
      public var ct: Float = 0; public var cb: Float = 1
  }
  ```
  CPU（Double）合成 3×3（commitParams 时算好 → uniforms buffer，ExposureModule 模式）；kernel 收逆矩阵 per-output-pixel backward 采样（bilinear），出界写 `(0,0,0,0)`（线性 Rec2020 黑 + alpha 0）。旋转非零时输出 AABB 变大（黑角）——**不自动内切**，让用户用 crop 收（模块可组合，符合 Lightamer 模型；dt 的内嵌裁切位保留作为快捷方式）。
- **modifyROIOut**（ashift.c:1142-1207 模式）：4 角 forward 变换 → AABB × 裁切系数 → floor；`width/height < 4` 时 dt 直接 `piece->enabled=FALSE`（:1195-1204）——Lightamer 对应「参数病态 → 记日志 + 本件按恒等渲染」，不 crash。
- **modifyROIIn**（ashift.c:1213-1289 模式）：4 角 inverse 变换 → AABB + 2×插值边距 → clamp 到 bufIn。
- **EXIF 方向**：`flip` 的 reloadDefaults 从 DecodedImage 元数据（RAW-06 已读）种默认 orientation——90° 步进由 flip 承担（§2.3），ashift 只管微调/透视，与 dt 分工一致。
- **自动水平检测**：`VNDetectHorizonRequest`（macOS 10.13+，macOS 27 可用）→ `VNHorizonObservation.angle`（弧度）→ `rotation = -angle`（**符号待 spike**：Vision 的 transform 在 CG 图像坐标（y 向下），与管线 uv 约定差一个翻转，一次性探针测试钉死）。输入图：PREVIEW 平面 `getBytes` → `CGImage`（fence 先行——L014），或 `decoded.ciImage` 缩渲后构造；选后者避免读回管线平面（零管线状态污染）。按钮在 rotate 面板，结果写 Params 走 D-H1 commit。

#### 2.3 flip / orientation（IOP-GEO-04，槽位 16.0）

- dt flip（flip.c:283-400）：orientation 位（H/V 镜像 + 90° 步进含 XY 交换）；modify_roi_out 在 90° 时交换 W/H（flip.c:299-313）；OpenCL kernel `flip`（basic.cl，索引重排）。Lightamer：一个 `flip_apply` Metal kernel（orientation uniform：恒等/水平/垂直/转置/反对置…8 态枚举，与 dt ORIENTATION_SWAP_XY 位语义对齐）；modifyROIOut 交换 W/H；modifyROIIn 逆变换角点。**纯索引映射、零采样**——parity 可达 <1e-6。
- **顺序硬约束**：flip(16.0) < crop(24.5)（dt iop_order.c:810-812 明注「crop GUI broken if flip is done on top」）——默认链自然满足，planner 勿调序。

#### 2.4 比例锁数据模型与 UI（联动 §8）

- 预设表：free(-1,-1) / original(w,h) / 1:1 / 4:3 / 3:2 / 16:9 / 16:10（dt aspect_list 同集）。锁比拖角时以**短边贴比例、长边从动**，rect 收敛 clamp 在 [0,1]² 内；original 比例从 `bufInROI` 的 w/h 读（crop 看到的上游几何）。
- crop Params 是 fraction → 旋转/裁切后的图中再次裁切，语义仍是「相对当前上游」——与 dt 一致，无级联歧义。

---

### 3. Perspective correction（IOP-GEO-02 的透视半边）

- **4 点单应求解**：4 组 (src↔dst) 对应 → DLT 8×8 线性方程 → h₃₃=1 归一；CPU Double 高斯消元 ~40 行（无依赖）。dt 的做法复杂得多（ashift_nmsimplex.c Nelder-Mead 拟合旋转/lensshift/剪切参数 + LSD 线段检测）——**不移植**，直接以 4 点单应为一等参数。
- **参数形态二选一**（planner 拍板，倾向 a）：
  - (a) dt 风格参数面（rotation/lensshift/shear 滑块，§2.2 Params 已含）+ 自动检测填充 4 点 → 反解参数；
  - (b) 直接暴露 4 角手柄（归一化 8 个坐标进 Params）。(b) 交互面大（hit-test + 实时单应预览循环），建议 Phase 4 以 (a) + Vision `VNDetectRectanglesRequest` 自动检测落地，**4 角手柄 defer**（CONTEXT deferred 已列 perspective 自动检测按需评估，方向一致）。
- **Vision 检测**：`VNDetectRectanglesRequest`（macOS 10.13+）——`minimumConfidence`、`quadratureTolerance`（默认 30°）、`maximumObservations`；`VNRectangleObservation` 给 4 个归一化角点（topLeft/topRight/bottomLeft/bottomRight）。用户点「自动」→ 检测 → 取最高 confidence → 写 Params → 一次 commit。失败（无矩形）toast 不动参数。
- **kernel 复用**：透视与旋转同一条 warp kernel（逆单应 uniform + bilinear）——一个 `ashift_warp` kernel 覆盖 IOP-GEO-02 全部几何。

---

### 4. Lens correction（IOP-GEO-03，D-G1 三层）

#### 4a. CIRAW 内嵌直通（零代码，文档化）

Phase 1 已实证 CIRAW 对支持的镜头自动应用 DNG OpcodeList/厂商 opcode 校正（STACK.md 能力表「CIRAW applies embedded lens-correcting metadata」）。模块文档与面板必须写明：**解码数据已含内嵌校正**；手动层默认关闭/中性，避免对已校正镜头双重校正（dt 用 lensfun 的 mods_done 检测防重——Lightamer 无 C 库，用「默认 off + UI 提示」替代，记录为已知取舍）。

#### 4b. 手动滑块（Metal warp，默认中性）

单一融合 kernel（`lens_manual_warp`）：

- **畸变**：径向模型，归一化半径 r（约定：r=1 于半宽？半对角？——**必须与 Lensfun 归一化对齐**，实现期对照 lensfun `modifier.elaborate` 源钉死，此处标注 Med）：`rd = ru·(1 + k1·ru² + k2·ru⁴)`，backward 采样。
- **横向 CA**：逐通道半径缩放——R 在 `r·(1+tcaR)` 采样、B 在 `r·(1+tcaB)`、G 原位（lensfun TCA linear 模型语义；poly3 是其二阶推广，(b) 层只做 linear，(c) 层解析 poly3）。
- **渐晕**：`I' = I·(1 + k1·r² + k2·r⁴ + k3·r⁶)` 前向乘法（lensfun pa 模型）；dt 在几何重采样**之前**对输入施加 vignette（lens.cc:1194-1206）——Lightamer 融合 kernel 内先乘后查样，顺序一致。
- **ROI**：k 全 0 → 恒等（缓存零扰动）；非零 → 前向变换 4 边框点取 AABB + 边距（lens.cc:1697-1790 模式）。槽位 13.0（V50Order 已有，含 dt 注释「cacorrectrgb 13.5 在 lens 后以防 lensfun 重新引入 CA」——(b) 层同位置受益）。

#### 4c. Lensfun XML 只读（Phase 4 后半）

- **数据源实测**（本机 2026-09-20）：Homebrew lensfun 0.3.4 数据在 `/opt/homebrew/share/lensfun/version_1/`——**55 个 xml 共 4.2MB**（CONTEXT 的「~30MB」为全量历史估计，实测小一个量级；「小体积子集内置」其实整库都够小）。
- **Schema**（实测样本核过）：`<lensdatabase version="1">` → `<mount>(name,compat)` / `<camera>(maker,model,mount,cropfactor)` / `<lens>(maker,model,mount,cropfactor,center?,calibration?)`；calibration 子元素：
  - `<distortion model="poly3|poly5|ptlens" focal="16" a=".." b=".." c=".."/>`（poly3 用 k1；ptlens 用 a,b,c；实测计数 875/5/4697）
  - `<tca model="poly3|linear" focal br vr bb vb/>`（3265 poly3 + 6 linear）
  - `<vignetting model="pa" focal aperture distance k1 k2 k3/>`（23759 条，(focal,aperture,distance) 三维网格，须插值）
- **解析**：Foundation `XMLParser` 足够——结构平坦两层、全属性驱动、无命名空间/混合内容。模型：`LensfunDB`（惰性按文件加载 → `[LensEntry]`，Codable 快照缓存可后置）。
- **匹配**：EXIF maker/model/lens（RAW-06 已读）→ 归一化（lowercase、去品牌前缀、去 "f/" 焦距段）→ 等值/包含匹配 + cropfactor 近似校验。lensfun C 有一套多别名/模糊匹配（`<model>` 可多个），v1 从简，**匹配 miss 率在 Phase 4 测试里落账**。
- **焦距选择**：定焦直取；变焦取最近 focal 条目起步（条目间插值后置）；vignette 三维插值（focal/aperture/distance 各维线性 + 端点 clamp）须自实现（~50 行），**精确语义对照 lensfun C `lfModifier` 插值**（实现期读 lensfun GitHub 源，Med）。
- **分发**：不入 git（D-G1）；选项 = 用户自备路径 / 内置精简子集 / 首跑下载整库（4.2MB 可接受，落 Application Support）。倾向首跑下载 + 设置里可指路径（planner 拍板，见 Open Questions）。
- **统一出口**：XML 解析出的参数归一到 (b) 层的内部模型（径向多项式 + TCA 缩放 + vignette k1k2k3），喂**同一个** `lens_manual_warp` kernel——D-G1 的字面要求，kernel 只认归一化 uniform。

---

### 5. Detail 模块（IOP-DETAIL-01..04）

#### 5a. sharpen（USM，槽位 35.0）

- dt 语义（源码核过）：**Lab 域、仅 L 通道**。radius → `rad = MIN(MAXR, ceil(radius·scale/iscale))`，`σ² = (1/2.5²)·(radius·scale/iscale)²`（sharpen.c:126-180）；混合（sharpen.cl `sharpen_mix`:145-160）：
  `delta = L − blurL; out = L + amount·copysign(max(0, |delta| − threshold), delta)`（软阈值 USM）。
- Lightamer：`GaussianBlur.blur`（Deriche IIR，与 dt gaussian.c 逐式同源）+ 一个 `sharpen_mix` kernel。**域决策**：dt 在 Lab 上做 → 推荐**经 LabRoundTrip 取 L**（`LightamerIOP/Sources/Common/LabRoundTrip.swift` 已有 Rec2020↔Lab 全套，Float 版 `rec2020ToLabF/labToRec2020F` kernel 侧可用），色度通道直通——这是 dt parity 可达的前提；纯线性 Y 版本留作 Phase 8+ 语义升级（Open Question）。σ 与 radius 换算沿用 dt（radius/2.5）。
- Params（dt v? 三元组）：`amount ∈ [0,4]`（默认 2.0？dt init_presets 钉 2.0/0.5/0.5 为 preset，模块默认 0——以 dt 默认中性为准，golden 用钉参）。

#### 5b. local contrast（clarity，D-G3：EIGF 复用；dt 参照 bilat 54.0）

- dt 的 local contrast = `bilat`（54.0，bilat.c:49-58）：两模式 bilateral grid / local laplacian；参数 sigma_s（空间）/sigma_r（域）/detail(−1..4, 默认 0.25)/midtone；`sigma_s` 按 `iscale/roi.scale` 补偿（bilat.c:341-344）。
- **D-G3 拍板复用 03-05 EIGF/guided**——实现：luma（Lab L 或线性 Y，与 sharpen 同决策）→ EIGF/guided 大半径表面模糊为 base 层（toneequal 的 ds 下采样 + 迭代路径直接可抄）→ `out = luma + detail·(luma − base)`（difference-of-luma 增强族；或 log 域比值族，实现期按视觉评估钉一个）。**不新写双边滤波**（决策已锁）。
- **parity 后果必须写进 plan**：guided 分解与 dt bilateral/local-laplacian 数学不同 → **dt-cli 参考不可用**（L017 路线①）：合成 float64 公式参考 + uniform 探针（detail=0 → 恒等精确门）+ 轨 B 中性。这不是缺陷，是 D-G3 的必然代价。
- ROI：`modifyROIIn` 按 base 半径外扩（同 §1 halo 语义）；tileHalo 复用 03-05 公式。

#### 5c. highpass / soften（IOP-DETAIL-03；槽位 34.0 / 66.0）

- **highpass**（dt 34.0，Lab 域——highpass.c:120-265 + highpass.cl）：`invert(100−L) → h/v blur → mix: o.x = 50 + (0.5a + 0.5b − 50)·contrast_scale，a/b 归零`。效果是浮雕灰度预览辅助。Lightamer：LabRoundTrip L + GaussianBlur + 一个 mix kernel；参数仅 `contrast/center/radius`（dt highpass 三参）。dt 是 display-referred Lab 语义——golden 合成参考按同一语义复刻。
- **soften**（dt 66.0，**RGB 线性域**——soften.c:96-105 default_colorspace RGB，Orton effect）：blur(size) 后按 amount 混合 + saturation/brightness。直接 port：GaussianBlur + mix kernel，无 Lab 纠缠，dt-cli uniform 平场 parity 可能可达（Orton 对平场 = 平场，探针固定点）。

#### 5d. equalizer / detail enhancement（IOP-DETAIL-04；槽位 27.0）

- dt `equalizer`（27.0）= contrast equalizer：**edge-aware wavelet** 6 带（equalizer_eaw.h `dt_iop_equalizer_wtf` + atrous.cl `eaw_decompose/eaw_synthesize/eaw_addbuffers`），Lab 3 通道各挂 6 点曲线。
- D-G4 拍板「多频段分解复用 CorrectionLUT 模式」：GaussianBlur 半倍频程金字塔（σ 递倍，5-6 带）→ 每带差分 → 每带增益（用户滑块/曲线 → **带增益 LUT**，CorrectionLUT 的 band→LUT→apply 架构同构）→ 重组。edge-aware 权重（eaw 的 gweight）v1 可省（纯高斯带已覆盖 detail enhancement 主场景），文档记录与 dt eaw 的偏差——或者作为 stretch goal 接入 03-05 的 EIGF 权重。
- golden：合成 float64 参考（带分解+增益逐式复刻）+ detail 全零恒等门 + 轨 B。

---

### 6. v50 槽位与管线/缓存互动

| 模块 | 槽位（V50Order 现表） | ROI 行为 | 与 Layer/PipeCacheKey 互动 |
|---|---|---|---|
| lens | 13.0 | 中性恒等；激活时 in-AABB 外扩 | roi 进 key；vignette-only 不改几何 |
| ashift | 15.0 | out 变大（黑角 AABB）；in 逆变换 AABB | 旋转后 crop(24.5) 在新几何上裁 |
| flip | 16.0 | 90° 时交换 W/H | 必须先于 crop（iop_order.c:810-812） |
| crop | 24.5 | **out 前向收缩**；in 偏移回取 | 下游平面按窗口尺寸分配（省内存） |
| equalizer | 27.0 | halo 外扩（大半径） | toneequal 24.0 之后，同 tile 驱动 |
| highpass | 34.0 | 小半径外扩 | — |
| sharpen | 35.0 | 小半径外扩（D-G5 主证） | — |
| bilat(ours: local contrast) | 54.0 | 大半径外扩 | 在 colorin(28.0)/sigmoid(45.3) 后——v50 注释「improve clarity after tonemapping」 |
| soften | 66.0 | blur 半径外扩 | 创意段 |

- **PipeCacheKey 不动**：roi 已在键内；crop 窗口不单独进 key（它通过该位置 roi 与 levelHash 的 params 折叠自然表达）。
- **enabled 开关**：levelHash 只折 enabled 件（PixelPipe.swift:371-378）——crop disable/enable 自动整链失效正确。
- **多分辨率**：crop/ashift 全部 fraction/相对语义 → PREVIEW 档位梯子（D-C3）、THUMBNAIL 360、FULL scale1.0 自动一致；裁切窗口跨档缩放无需模块感知。
- **FULL 内存**：crop 后 FULL 中间平面变小（利好）；ashift 旋转 AABB 变大（1.55GB@100MP 的系数略涨，量级不变，MemoryBudgetTests 门覆盖）。
- **新模块注册**：Registry.swift 填充 + `prewarmFunctionNames`（Registry.swift:89）补新 kernel + `editingDefaultInstances` 以**中性/禁用**进链（缓存中性——exposure 0EV 同款约定）。

**⚠ 遗留设计债（本阶段顺手还）**：`RenderPipeline.process` 无子 ROI 入参（§1 的 roiHint）；`viewportUV` 的 aspect-fit 数学在 PipeCoordinator 与 EditorMTKView 各有一份（aspectFitUniforms）——crop overlay 需要第三处使用，抽一个公共 fit 工具（放 App 层即可，Core 不依赖 UI）。

---

### 7. Golden parity 策略（几何模块专项）

**L017 约束重申**：本机 dt-cli float 导出对空间变化图像损坏（EXR 逐通道错排 / PFM 相位涂抹），空间均匀平场正确。几何/锐化模块几乎全是空间变化算子 → 分流：

| 模块 | 轨 A（dt-cli） | 合成参考（L017 路线①） | 轨 B（ColorSync 双判据） |
|---|---|---|---|
| crop | ✅ 可直接 dt-cli EXR（纯窗口拷贝零自由度；仍先跑平场 probe 确认本机 dt-cli 状态） | 兜底：窗口索引公式参考 | ✅ |
| flip | ✅ 同上（索引映射） | 同上 | ✅ |
| ashift（rotate/perspective） | ❌（bilinear warp 空间变化；uniform 探针仅证「平场旋转=平场(黑角除外)」+ 参数采纳实证） | ✅ float64 逆单应 + bilinear 逐式复刻（无 dt-cli 依赖，确定性） | ✅ |
| lens 手动 | ❌ 同上（uniform 探针：k=0 恒等、vignette 平场衰减公式点检） | ✅ 径向 warp + vignette 公式参考 | ✅ |
| lens XML | —（参数解析本身单测对照 XML 样本） | 解析→归一化参数的 golden（固定 xml 子集钉参数） | — |
| sharpen | ⚠ Lab 域空间变化 → dt-cli 不可靠 | ✅ float64 复刻（LabRoundTrip 参考递归 + dt_gauss_coeffs 已在 gen_fixtures）+ 平场恒等探针（delta=0 → USM 恒等） | ✅ |
| local contrast | ❌（D-G3 语义本就不等于 dt bilat） | ✅ 公式参考 + detail=0 精确恒等门 | ✅ |
| highpass/soften/equalizer | soften 平场可能可达；其余合成 | ✅ 逐式复刻 + 全零参数恒等门 | ✅ |

- **fixture 增补**（现有 18 RAW + 74 个合成 EXR 之外）：① 水平/垂直梯度 ramp EXR（warp 模块的合成参考输入——注意这是喂给**我们自己的管线**做 parity，不是喂 dt-cli，无 L017 风险）；② 棋盘格 EXR（warp 采样/走样可见性人工判据）；③ 已知角度水平线合成图（Vision 自动检测回归，PNG 即可，Vision 吃 CGImage）；④ 一条真实斜地平线 RAW（18 张里若有建筑/海平面优先）。
- **ROI 验收 harness（SC#4）**：
  1. 树内断言：`[crop(50%), testGain, colorout, gamma]` 链 run 后 `PipeCacheKey(position≤crop).roi` == 全幅、`> crop` == 窗口尺寸；input 平面纹理宽高 == 窗口。
  2. 外扩断言：`[sharpen(r)]` 链 + `roiHint` 子窗口 → 上游平面 == 窗口+2·ceil(3σ)（< 全图），数值断言 + 字节记账。
  3. 禁用穿越：crop disabled → 全链 roi 恒等（dt `_skip_piece_on_tags` 直通回归）。
  4. 缓存语义回归：拖动 crop rect N 次 → N 组新键且旧键保留（回拖命中，D-C3 精神）；ParityGate 双闸照走。
- **Vision 探针测试**：合成图角度 θ ∈ {−8°, 0°, +5°} → 检测角与真值差 < 0.2°；矩形检测在合成梯形上 4 角还原误差 < 0.5%。

---

### 8. UI overlay 手柄（IOP-GEO-01 SC#1 + D-G6）

- **层级**：`EditorAreaView` 的 ZStack 中、EditorMTKView 之上叠 SwiftUI `CropOverlayView`（新文件），吃三样输入：显示纹理的 fitted rect（公共 fit 工具，§6 遗留债）、当前 `CropParams`（经 EditorState 的 instance 记录）、模式枚举（none/crop/rotate）。
- **交互路由（D-H1 三件套严格复用）**：
  - 手势开始 → `PipeCoordinator.beginContinuousEdit()`
  - 拖动 tick → 归一化 rect 换算 → `setLiveParams(ModuleInstance(crop, **enabled=false**))`（裁切编辑期间全图渲染 + overlay 画暗膜——§1 缓存行为规避，60fps 靠整幅平面缓存命中）
  - 手势结束 → `commitContinuousEdit(label:)`（恰好一条 history item，params 含 enabled=true 的最终 rect）
  - 角落把手 hit-test 抄 dt `_grab_region_t`（crop.c:71-88 的 16 态位枚举：4 角/4 边/中心/全选）；比例锁（§2.4）；三分/黄金网格线 overlay。
  - 旋转模式：旋转手柄（图外四角圆弧）+ 角度滑块 + 网格 + 「自动水平」按钮（Vision，§2.2）→ 同一 D-H1 通道。
- **面板（D-T6 框架扩展）**：`CropPanelView`（比例下拉 + 数字微调 + 重置）、`AshiftPanelView`（角度滑块 ±45 + 透视滑块组 + 自动检测按钮 + 网格开关）、`LensPanelView`（三段：内嵌状态说明 / 手动三滑块组 / Lensfun 匹配状态 + 应用按钮）、`SharpenPanelView` / `LocalContrastPanelView` / `HighpassSoftenPanelView` / `EqualizerPanelView`（6 带滑块起步，曲线 Canvas 为 stretch——ToneEqualPanelView 的 Canvas 已可抄）。
- **XCUITest**：把手/按钮全部 `.accessibilityIdentifier`（L010：容器不加 label）；overlay 手势最小断言 = 拖角后 commit 恰 1 条 history + viewport 纹理尺寸变化（经 logs/signpost）。
- String Catalog zh/en 同批（ToneEqualPanelView 33 keys 的规模参照）。

---

## Validation Architecture

1. **顺序**：Plan A（ROI 协商协议改造 + PipeCacheTests ROI 用例加固）全绿后，模块 plan 才动工——所有 8 个模块消费协议。
2. **双轨 golden**：轨 A dt-cli 仅 crop/flip（+soften 平场尝试）；其余合成 float64 参考（gen_fixtures.py 增 geometry/detail 节，模式照 toneequal T5：公式逐式复刻、float32 网格点对齐、参数采纳实证不适用时以「公式同源 + uniform 探针 + 恒等门」三件套替代 dt 侧证据）。ParityGate 双闸容差：索引类 <1e-6、warp 类 <1e-5（bilinear 逐式应达）、IIR 混合类 <1e-4（与 03-04/03-05 门一致）。
3. **轨 B**：全部模块插链后 ColorSync 中性度 + 交叉一致性（D-COL1 双判据）不回归——crop/flip 是窗口语义，轨 B 意义在「暗角/黑角不破坏中性」。
4. **ROI 端到端 harness**（§7 的 4 条断言）作为 SC#4 验收门，进 `PipeCacheTests`/新 `ROINegotiationTests`。
5. **性能**：PERF-5 承接（03-05 记录 Debug warm median 63.4ms > 16.6ms 预算，03-06-T7 正式门）。Phase 4 链长 +9 模块——新模块逐个记录单帧增量；warp/blur 模块全部 `dispatch2DTexture` 单 pass 或 3-pass，增量预期每模块 2-6ms@2560px（Debug），标注 03-06 优化杠杆（Release/PSO 预热/批合并）为共同解。
6. **内存**：MemoryBudgetTests 扩展：crop 后 FULL 平面记账下降、ashift AABB 上升有界、sharpen 外扩 < 全图。

## Risks & Gotchas

1. **processRec 改造是 Phase 2 以来最大回归面**：递归 + 缓存 + tile 驱动三者在同一函数。先加 ROI 用例再动实现；`executeTiled` 的 readRect blit 假设「输入平面 == roiOut 尺寸」（PixelPipe.swift:278-282）在协商后要对齐 roiIn 尺寸——tile 内的 ROI 语义必须显式处理（tile 驱动发生在单个模块执行内部，输入平面尺寸=协商 roiIn，readRect 相对该平面，不与协商冲突，但 assert 要改）。
2. **D-G2 措辞歧义**（「不实际裁切内存」）：按 §1 读法实现（协商收缩、无全幅拷贝）。**非 DECISION REVIEW**——D-G5 的验收断言（「下游模块看到的纹理尺寸=裁切尺寸」）与该读法一致，字面自洽。
3. **dt 的 Lab 域模块**（sharpen/highpass/equalizer）：不经 LabRoundTrip 直接线性 RGB 实现会让 golden 与 dt 语义分叉——parity 路线已定（Lab L），planner 勿图省事。
4. **L017 dt-cli float 导出缺陷**直接约束本阶段：几何/锐化 golden 主轨 = 合成参考；任何「dt-cli EXR 对比」新 case 首用前必须先过平场+变化图像双重 probe（L017 对策原文）。
5. **Lensfun 语义自实现**（模型公式、归一化半径约定、vignette 三维插值）：C 源不在本机（Homebrew 只有二进制+数据）——实现期读 lensfun GitHub 源码定稿；置信 Med，误差表现为校正量小偏差而非崩溃，可接受。
6. **Vision 符号/坐标约定**：horizon angle 的符号、rectangle 角点在 y-flip 下的顺序——一次性探针测试钉死，勿凭文档猜。
7. **crop 拖动全链 miss**（§1 gotcha）：UI 层用「live disabled」规避；若 planner 选择「live 裁切预览」则接受每 tick 全链重渲（PREVIEW 档可扛但与 PERF-5 叠加），二选一写进 plan。
8. **flip 必须先于 crop**（dt iop_order.c:810-812）：默认链顺序勿动。
9. **L008/L014/L018 全适用**：新 kernel 的 endEncoding 顺序；Vision 读回前 fence；任何新 blur 变体禁 read_write 纹理累积与 in-place 行 pass（GaussianBlur 的 buffer 双平面模式照抄）；`.storageModeShared`（L018 缺陷 3）。
10. **ashift 黑角 alpha=0**：float 管线 alpha 通道首次承载语义（此前全 1）——gamma/display 尾巴与 blit 是否透传 alpha 需要一次检查（`.bgra8Unorm` 输出 alpha=0 区域显示为黑，可接受；但 ColorSync 腿的 premultiply 语义要验证——FOUND-02 已声明 premultiplied-alpha，OK，测试钉住）。
11. **sidecar 兼容**：9 个新 op 进 `instances`——未知 op 透传降级机制（02-06）已有，旧 app 读新 sidecar 安全；Params schema 全部 Codable+Hashable，`ParamsCoding.encode`（sortedKeys）进哈希（L013 红线）。

## Open Questions for Planning

1. **rotate/perspective 的模块身份**：单一 `ashift` op（一个实例，面板两个区块）vs `ashift`+`crop` 组合默认链。倾向单一 ashift + 内嵌裁切位默认全幅；planner 定。
2. **sharpen/local contrast 的 luma 域**：Lab L（dt parity、display-referred 语义）vs 线性 Y（scene-referred 纯度、与管线域一致）。推荐 Lab L（golden 可达 + dt 视觉对齐），Phase 8+ 再议线性化；需 planner 认可「intentional divergence 记录」。
3. **local contrast 合成 golden 的接受度**：D-G3 的必然代价（无 dt-cli 参考）——planner 确认验收口径 = 公式参考 + detail=0 恒等门 + 视觉抽检。
4. **Lensfun 数据分发**：首跑整库下载（4.2MB，GitHub lensfun/lensfun-data）vs 用户自备路径 vs 内置子集。倾向「首跑下载 + 设置可指路径」，涉及网络权限与失败降级（miss → 手动层照常）。
5. **透视交互范围**：滑块组 + Vision 自动检测（推荐）vs 完整 4 角手柄。后者建议 defer 到 Phase 6（ liquify 的顶点交互基建可复用）。
6. **`RenderPipeline.process` 的 `roiHint` 参数形状**：本阶段为测试/探针用（SC#4 内存断言）；是否同批暴露 FULL zoom-ROI 给 UI（Phase 4 zoom 交互），还是仅测试面。
7. **crop 编辑的 live 语义**：「live disabled + 暗膜」（推荐，缓存友好）vs「live 裁切预览」（所见即所得但每 tick 全链 miss）。影响 §8 overlay 实现，plan 拍板。
8. **equalizer 的 edge-aware 权重**：v1 纯高斯带（推荐）vs 接入 EIGF 权重对齐 dt eaw。影响 golden 公式与工作量，推荐 v1 从简并记录偏差。

## Sources

### Darktable（本地源码，file:line 均已核，tree 与 Phase 2/3 同）

- `src/develop/pixelpipe_hb.c:3368-3405` — `dt_dev_pixelpipe_get_dimensions` 前向 ROI 趟（modify_roi_out 链 + buf_in/buf_out 盖章 + 禁用直通）
- `src/develop/pixelpipe_hb.c:2085-2096` — 递归体后向 `modify_roi_in` + processed_roi 盖章
- `src/common/imagebuf.c:188-223` — `dt_iop_copy_image_roi`（crop/flip 的窗口拷贝原语；注：ROI 几何辅助在本树位于 imagebuf.c/imageop.h，无独立 imageop_geometry.c）
- `src/iop/crop.c:44,61-69,71-88,517-560,576-592,594-608` — fraction params、MIN_CROP_SIZE、grab 枚举、modify_roi_out/in、process
- `src/iop/ashift.c:272-290,1142-1207,1213-1289,3569+` — params（rotation/lensshift/shear/f_length/cl..cb）、homography forward/inverse ROI、CL 腿与 isflipped 检测
- `src/iop/rotatepixels.c:191-231` — raw 域 45° 旋转 ROI（不移植的对照证据）
- `src/iop/flip.c:283-400` — orientation 位、W/H 交换、`flip` kernel（basic.cl）
- `src/iop/lens.cc:80-151,1160-1210,1697-1790` — 修正旗标/TCA 手调参数、vignette 前置施加、inverse-transform ROI AABB
- `src/iop/sharpen.c:55-100,126-180` + `data/kernels/sharpen.cl:145-160` — USM 三参、radius/σ 换算、软阈值 mix
- `src/iop/highpass.c` + `data/kernels/highpass.cl` — Lab 反相高通三 kernel（invert/hblur/vblur/mix）
- `src/iop/bilat.c:40-58,329-355` — local contrast 双模式 params 与 process
- `src/iop/soften.c:50-110` — Orton effect（RGB 线性域）
- `src/iop/equalizer.c:40-80` + `src/iop/equalizer_eaw.h` + `data/kernels/atrous.cl:31-95` — eaw 6 带分解/重组
- `src/iop/clahe.c:80-120` — CLAHE luminance（D-G3 不采用的对照）
- `src/common/iop_order.c:810-812` — flip/ashift 先于 crop/clipping 的 GUI 约束

### Lightamer 代码（现码，file:line 核过）

- `LightamerCore/Sources/Pipe/PixelPipe.swift:340-615` — run/processRec/levelHash/blit/executeTiled（ROI 改造面）
- `LightamerCore/Sources/Pipe/PipeCacheKey.swift:15-38`、`Pipe/ROI.swift`、`Pipe/IOPiece.swift`、`Pipe/ModuleBox.swift:61-75,84-216`、`Pipe/IOPModule.swift:37-119`
- `LightamerCore/Sources/Foundation/V50Order.swift`（93 条全表 + 注释约束）
- `LightamerIOP/Sources/Common/GaussianBlur.swift`（Deriche IIR + buffer 双平面纪律）、`Common/LabRoundTrip.swift`、`Common/HistogramReduce.swift`
- `LightamerIOP/Sources/ToneEqual/CorrectionLUT.swift` + `ToneEqualModule.swift`（EIGF/guided/ds 路径 = local contrast/equalizer 复用面）
- `LightamerIOP/Sources/Exposure/ExposureModule.swift`（模块文件对/commit/uniforms 模式样板）、`Sources/Registry.swift:89`
- `App/Sources/Lightamer/State/PipeCoordinator.swift`（D-H1 三件套/viewportUV/renderPreview）、`App/Sources/Lightamer/UI/EditorMTKView.swift`（aspectFitUniforms/blit）、`UI/Inspector/ToneEqualPanelView.swift`（面板样板）
- `Tests/LightamerTests/ParityGate.swift`、`Fixtures.swift`、`input/golden/fixtures/`（74 个合成 EXR）

### Lensfun（本机实测 2026-09-20）

- `/opt/homebrew/share/lensfun/version_1/`（55 xml / 4.2MB；schema 与模型分布实测：distortion poly3×875 + ptlens×4697 + poly5×5；tca poly3×3265 + linear×6；vignetting pa×23759）
- Homebrew lensfun 0.3.4（二进制 + 数据；C 源实现期读 GitHub lensfun/lensfun `modifier.elaborate` / `modifier.cpp`）

### Apple 文档

- `VNDetectHorizonRequest` / `VNHorizonObservation`（angle/transform，macOS 10.13+）— developer.apple.com/documentation/vision/vndetecthorizonrequest
- `VNDetectRectanglesRequest` / `VNRectangleObservation`（4 归一化角点；minimumConfidence/quadratureTolerance/maximumObservations，macOS 10.13+）
- Metal：`MTLBlitCommandEncoder.copy`（crop 窗口拷贝）、bilinear 采样约定

### 项目文档

- `.planning/phases/04-geometry-lens-detail-iops/04-CONTEXT.md`（D-G1..G6）
- `.planning/ROADMAP.md` §Phase 4（SC#1..4；风险 CIRAW-3、METAL-6/7、PERF-5）
- `.planning/phases/02-pixelpipe-core-color-management-history-stack/02-RESEARCH.md`（Risk #7 预留、缓存键语义）
- `.planning/phases/03-tone-filmic-iops/03-05-SUMMARY.md`（EIGF/CorrectionLUT/TilingPlan halo 公式/PERF-5 数据）
- `LESSONS.md` L005/L008/L010/L013/L014/L017/L018；`AGENTS.md`（Conventions：golden-image 测试硬约定、60fps 预算）

---
*Phase 4 Research — 2026-09-20。产物仅本文件；未提交 git。*

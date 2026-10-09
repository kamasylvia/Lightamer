# M4-1 CHECKER — TIFF 栅格开发链双 plan 从严审查

> Checker subagent（2026-10-10）。审查对象 = 同目录 `M4-1-01-PLAN.md` + `M4-1-02-PLAN.md`，
> 对照 `M4-1-CONTEXT.md`（裁决记录）+ `RESEARCH-NOTES.md` + 仓库源码亲核 + 上游 aces-core
> v2.0（SHA `069b0bc3`，`Lib.Academy.OutputTransform.ctl` 亲验）+ Alcedo
> `raster_image_input_plan.md`（GPL 只读，1339 行亲读关键节）。所有 file:line 为
> 2026-10-10 HEAD 亲证。

# FAIL / 6 error + 4 minor

两 plan 的裁决一致性、波分解、测试对账、红线意识总体扎实（详见 §三），但存在 6 项
error 级缺陷：1 项数学规格错误、2 项语义规则缺口（其中一项与自身红线相撞）、1 项
映射表不可行、1 项 canonicalization 缺失致自身 AC 不可实现、1 项波及面申报不全含
静默语义缺陷。全部可在 plan 内修复，不动摇裁决与架构骨架。

---

## 一、裁决一致性（审查维度 1）——PASS

七项生效值逐条对 AC（`M4-1-CONTEXT.md` 裁决记录 2026-10-10 亲读）：

| # | 生效值 | plan 承载 | AC 落点 | 判定 |
|---|---|---|---|---|
| 1 | raster 默认 DRT = Alcedo D2 同形 + `DrtEotf.srgbPiecewise` | 01 KD-8/KD-9 + 02 KD-2 | 01-AC1 / 02-AC4 | ✓ |
| 2 | 新 TIFF 开发分支（limiting = 源 primaries） | 01 KD-3/KD-5/KD-6 | 01-AC2 | ✓ |
| 3 | 逆变换 = aces-core 移植 + RGC 逆不移植 + raster RGC 恒关 | 01 KD-3/KD-9 | 01-AC3 | ✓ |
| 4 | HDR 旗标 = TRC ∨ float 探针；DRT-HDR 既有臂；徽标 defer | 01 KD-9 + 02 KD-5 | 01-AC4 / 02-AC5 | ✓ |
| 5 | 选择器默认双开 + `library.import.categories` 新键 + rawExtensions 正交 | 02 KD-4 | 02-AC1 | ✓ |
| 6 | TIFF 整体切新分支 + 旧臂退役保留 + JPEG/PNG 零回退 | 02 KD-1/KD-3 | 02-AC2 | ✓ |
| 7 | import 三模式零特例 + excludedType 分账 | 02 T6 | 02-AC3 | ✓ |

- **RGC 恒关 = render-side 政策的晨审可翻点声明：合规**。KD-9 明示「晨审可翻点：
  若要求 per-record RGC 位则升级为 additive `rgcOn: Bool?`（stableHash nil 零漂移钉死）」，
  且给出了当前裁定的理由链（DrtRecord 零新字段/零持久化/零 hash 面；Alcedo D2 同形）。
  `params(space:peak:rgcOn:)` 运行时开关亲证在册（Aces2Reference.swift:1064，paramsCache
  键含 rgc 位 :1043-1062），只改调用点传入值的技术可行性成立。
- 逆变换移植对象亲验：**`outputTransform_inv` 在上游 SHA `069b0bc3` 在册**
  （`Lib.Academy.OutputTransform.ctl` 文件尾，紧随 `outputTransform_fwd`；同文件含
  `chroma_compress_inv` / `gamut_compress_inv` / `init_TSParams` 全族）。M2-6-2 预留
  注记亲证（Aces2Reference.swift:20 + M2-6-2-DECISIONS.md:30）。
- `srgb_piecewise` 拼写与 GPU ordinal 亲证：Alcedo `drt_node_model.hpp:46`
  `SrgbPiecewise = 7` + `color_utils.hpp:255` 序列化拼写 `"srgb_piecewise"`——plan KD-8
  的 rawValue 选择正确（E1 中 ordinal 7 须列入补臂清单）。
- baseline 3174/16/0 与七 bundle 分账亲证（GOAL-STATE M3-4-02 续接点 + M3-4-01-SUMMARY
  :83/:115：3152+22=3174；IOP 483 / IOPP 408 / Layers 378 / Library 598 / Sessions 279 /
  Export 342 / App 686）——plan 01 基线声明逐位一致。

## 二、error 清单（逐条带处方）

### E1【语义规则缺口·自撞红线】scene-linear 判定缺 linear-ICC float32 半边——IOPP 逐位基线红线被自身路由翻转击穿

- **亲证**：Alcedo D3 原文（raster_image_input_plan.md:1319）：「OpenEXR, and float TIFF
  with **a linear ICC curve or no ICC**, are **scene-linear**: they get a matrix only and
  no inverse DRT.」（:178/:239 同义复述）。plan 01 KD-1 解析序只收了无 ICC 半边
  （「②无 ICC 且 float32 → scene-linear Rec.709 默认」），**linear ICC + float32 →
  sceneLinear 整支缺失**；KD-2 fixture 矩阵特形亦只有「无 ICC float32」。
- **在库受害链（三重）**：
  1. `BandStreamer.swift:24-28`：stack merge 产品 = 「linear-Rec2020 TAGGED float32
     TIFF……round-trips the working space through RAWDecoder.decodeRaster」——
     StackMergeService.swift:1006/:1396 落盘。02 T1 分流翻转后这些产品经 `decode()`
     走新腿，按 plan 现行规则（有 ICC → displayReferred）会对 scene-linear 工作平面
     施加 ACES 逆 ODT → 双重变换损坏 stack 产品。
  2. `HDRPipelineMatrixTests.swift:55`（IOPP bundle，BUNDLE-MAP:94）自述「rides the
     same raster decode leg a merged product rides」，:92-95 用
     `BandStreamer.writeFloatTIFF` 写 torture 源后 `RAWDecoder().decode(url)`，:800
     `decode(product)` 真链跑 merge 产品——02 翻转后即坏。plan 02 红线「IOP/IOPParity
     逐位基线」与自身 T1 直接相撞。
  3. Alcedo 对齐面：我方 stack/float 产品语义与 Alcedo float-TIFF 消费同构，收窄规则
     即行为分叉。
- **与 SC#1 无冲突**：我方导出链 `DrtOutputColorSpace` 亲证 `.linear` 在全部六空间均
  `throw illegal`（DrtOutputColorSpace.swift:72/:83/:92/:101/:112/:121）——**导出链
  从不产出 linear-ICC 文件**，SC#1 的 32F 行恒携 gamma/piecewise TRC ICC → displayReferred
  → 逆→forward 像素带测试不受此规则影响。补 D3 半边零代价。
- **处方**：plan 01 KD-1 解析序补「①′ 内嵌 ICC 且 TRC==linear 且 float32 →
  referral=sceneLinear（矩阵分支，primaries/白点照取自 ICC；origin 建议新 case 或
  复用 `iccMatrixShaper` + defaultReason 记 D3 规则）」；KD-2 矩阵特形补
  「linear-ICC float32（scene-linear 判定）」fixture；KD-9/T10 补该支映射负测；
  02 T7 红线自证增列 HDRPipelineMatrixTests 逐位基线；SC#1 明写 32F 行走 display 分支
  （gamma ICC）不经矩阵支。plan 02 风险节「路由切换的隐 consumers」补齐
  BandStreamer/StackMergeService 产品消费面（现有 T1 grep `decodeRaster` 调用点方向
  反了——该 grep 只能找到直调者，找不到**产品经 decode() 回流**的消费者）。

### E2【波及面普查缺失】路由翻转的 decode() 消费面普查任务缺失——.tif 测试舰队无处置规则

- **亲证**：`Tests/LightamerTests/` 内 27 个测试文件使用 `.tif/.tiff` 字面量。其中
  **synthetic DecodedImage 载体面安全**（亲核：EditorMetalLegRegressionTests:119/
  DrtViewportTests:237/FilmCoordinatorTests:86 等自造 `DecodedImage`，.tif 仅为 URL
  载体；翻转后 `rasterColor == nil` → seed 跳过 → pristine 逐字节不变）；但
  **真实 decode() 驱动面**至少含 HDRPipelineMatrixTests（见 E1）、ImportServiceTests、
  ImportFilterTests（tif 拒绝断言翻转，见 M3）、ImportDropTests。
- plan 02 风险节只扫了「QuickLook/Spotlight 直调 decodeRaster」（grep 亲证 decodeRaster
  无第二调用点，该项为空集）与「tif 拒绝断言翻转」两类，**没有 decode() 真链消费面
  的普查任务与处置规则**（fixture 换容器 vs golden 重钉 + DECISIONS 逐条登记）。
  T7 全套轮才暴露 = 波内失控点。
- **处方**：plan 02 T1 增验收项「decode() 真链消费面普查清单入 DECISIONS」（按
  `grep -l 'decode(' Tests` × `.tif` 交集逐文件定性：synthetic 载体 = 安全判据
  `rasterColor == nil`；真 decode 面 = 逐个处置）；ImportServiceTests 的 tif 运输面
  在 T5/T6 一并翻转登记。

### E3【数学规格错误】逆变换 stage 图 [i4'] 箭头序与上游 `tonemap_and_compress_inv` 相反

- **亲证**（上游 CTL 逐行，SHA `069b0bc3`）：`tonemap_and_compress_inv` 执行序 =
  `luminance = J_to_Y(JMh_tc[0])` → `linear = tonescale_inv(luminance/ref)` →
  `J = Y_to_J(linear*ref)` → `JMh = chroma_compress_inv(JMh_tc, J, p, true)`；文件内
  注释自述「Applies the **inverse tonescale, then uncompresses M**」。数据依赖是硬的：
  `chroma_compress_inv` 需要 tonescale_inv 恢复出的**原始 J** 作为输入。
- plan 01 KD-3 stage 图写「`[i4'] chroma_compress_inv → tonescale_inv`」——按箭头序
  读 = 先 chroma 后 tonescale，**依赖倒挂**。且 T4 验收标准「文件头 stage 图与 KD-3
  一致」会把错误序**固化进 Aces2InverseReference.swift 头注**（共享词汇表正本）。
  RESEARCH §3.3 的「[4']逆 chroma compress + 逆 tonescale」为无序并列表述，plan 转
  写成有序图时引入了方向错误。
- **处方**：KD-3 改为 `[i4'] tonescale_inv → chroma_compress_inv（以恢复的 J 解 M）`；
  T4 头注照改；顺带在 DECISIONS 记「图序 = 数据依赖序，非 forward 组合序」防止执行期
  再混淆。

### E4【映射表不可行/越集】KD-9 derive 三处与 `DrtEncodingSpace`/`legalEOTFs` 实况冲突

- **亲证**：`DrtEncodingSpace` = {rec709, p3d65, p3d60, p3dci, xyz, rec2020}（DrtRecord.swift:46-57）
  ——**无 adobeRGB / proPhoto case**；`legalEOTFs`（DrtRecord.swift:445-452）：gamma18
  与 linear 不出现在任何集合（:441-443 注记自述），gamma26 仅 p3d60/p3dci/xyz 合法，
  bt1886 仅 rec709。
- KD-9 三处缺陷：
  1. 「`encodingSpace` 与 primaries 同族映射（**同上表** + xyz 例外）」——上表含
     AdobeRGB→adobeRGB、ProPhoto→proPhoto，对 encodingSpace 是**编译不可能**（无此
     case）；adobeRGB/proPhoto 只对 limitingSpace 成立（DrtLimitingSpace:80-92 亲证七值）。
  2. `encodingEotf` 最近邻映射可产出**集外值**：gamma 1.8 源 → `.gamma18`（任何 space
     非法）；gamma 2.6 源 + encodingSpace=rec709 → `.gamma26`（rec709 非法）；linear
     TRC display 面 → `.linear`（任何 space 非法）——直接违反同 plan KD-8/T9 誓保的
     「accept-set==legalEOTFs==Alcedo cpp 三方镜像」不变式，首次面板交互即被 snap 改写，
     derive 的「开图所见 ≈ 源」承诺静默失效。
  3. displayReferred + linear transfer（LUT-ICC 支）derive `linear→linear` 同越集，
     且无合法近邻可落（rec2020 的合法集 = [st2084, hlg] 全 HDR——错标 SDR 文档为 HDR）。
- **处方**：KD-9 改**联合规则**（space × eotf 联合落在 legalEOTFs 接受集内，M3-4
  `validateCoreOrder` 联合规则单源先例）：①encodingSpace 表独立列出（AdobeRGB/ProPhoto →
  rec2020 或 rec709 编码 + limitingSpace 保留源域，二表分离）；②每 space 定义合法
  fallback 链（如 rec709: srgbPiecewise > gamma22 > bt1886；miss 记 defaultReason）；
  ③displayReferred+linear 特例显式裁（建议 srgbPiecewise + reason，或扩 legal 集——
  后者动三方镜像须用户裁）；④T10 负测逐行钉「derive 结果 ∈ legalEOTFs(space)」。

### E5【canonicalization 缺失→自身 AC 不可实现】sRGB/gamma 采样曲线 canonicalization 缺失

- **亲证**：KD-1 canonicalization 只列「ICC 采样曲线逐点对 **ST 2084 / 1000-nit HLG**
  公式，全部 2e-4 内 → st2084/hlg」；而 KD-8/T9 自己的验收 = 「srgbPiecewise ICC 导出 →
  重导入描述 **canonicalize 回 srgbPiecewise**」。T9 落地后导出链写的是**自建 v4 profile
  的 curv 采样表**（KD-8 明令非 para）——重导入解析得 `iccSampled`，无 sRGB 规则就
  **回不到 `srgbPiecewise`**，T9 的 EXPORT round-trip AC 按现行 KD-1 规则集不可实现。
- Alcedo 有此规则亲证（raster_image_input_plan.md:253-254）：「Curves within **1e-4**
  of **sRGB or a pure gamma** are canonicalized to the analytic form.」——即 PQ/HLG
  canonicalization 之外还有 sRGB/纯 gamma 两支，plan 漏抄。
- **处方**：KD-1 canonicalization 补两支：采样曲线对 sRGB 分段公式（门值建议与 Alcedo
  同 1e-4，或自定但须 > fixture 扰动距离，见 minor M4）与对纯 gamma 单值（拟合幂 γ，
  落 `gamma(Double)`）；T3 golden 补正负测；T9 的 EXPORT round-trip 依赖链即闭合。

### E6【波及面申报不全 + 静默语义缺陷】srgbPiecewise 编译/行为面清单不全；两条零 diff 声明为假

- **亲证**（全仓穷举 switch 枚举，`case .gamma18` 全域 grep 补多值行式）——additive
  case 落地时编译破出的面共 **13 处**：
  - `DrtEotf.swift` ×4：kernelIndex :47-57（GPU ordinal，**须补 7**——Alcedo hpp:46
    `SrgbPiecewise = 7` 亲证，MSL 契约面）、powerExponent :62-70、`DrtEotfMath.encode`
    :187-206、`DrtEotfMath.decode` :213-232；
  - `DrtRecord.swift` ×2：`isHdrEncoding` :456-461（**须显式补 `.srgbPiecewise → false`**
    ——KD-8 未列名）、`legalEOTFs` :445-452（已列）；
  - `DrtEotfKernels.metal` ×2：drtEotfEncode :112 / drtEotfDecode :134 + 常数探针
    （已列）；
  - `DrtOutputColorSpace.swift` ×6：:72/:83/:92/:101/:112/:121 六个空间臂组（已列）；
  - **App 层 ×2（plan 零提及）**：
    - `App/Sources/Lightamer/UI/Shell/DrtPanelView.swift:266-277` `eotfName(_:)` 穷举
      switch——M3-3 封存面清单在册成员，**编译必破**，且需新增显示名 → **新 xcstrings 键
      一枚 + zh-audit 入册**；
    - `App/Sources/Lightamer/UI/EditorMTKView.swift:729-749` `drtLayerColorSpace(_:)`
      外层穷举 switch——编译必破；`.srgbPiecewise` 落哪臂（SDR 幂组 + gamma 三元组近似，
      抑或 `CGColorSpace(name: .sRGB)`）是 plan 未裁的**视口行为决策**；
    - `App/Sources/Lightamer/UI/EditorMTKView.swift:801-803` `drtSurfaceSpec` 的
      `hdrDrawable` 布尔链（`!= .gamma26 && != .bt1886 && != .gamma22 && != .gamma18`）
      ——**非 switch，编译器不兜底**：不补则 `.srgbPiecewise`（SDR）被静默判为
      `hdrDrawable = true`。
- 由上，plan 01 两条声明为假：①KD-8「本批唯一生产可见变化……**panel/model 代码零
  diff**」——DrtPanelView/EditorMTKView 必 diff；②T11「readout 面本 plan 无 UI——
  **预期零新键**」——eotfName 键必增。files_modified 亦漏列 DrtPanelView.swift 与
  EditorMTKView.swift（M3-1-03 验收 obs-1 教训「路由缝/扫批类结构必经文件入申报集」
  的复发）；M3-3 封存面解封申报漏 DrtRecord（虽在 files_modified）与上述两个 App 文件。
- **处方**：KD-8 清单补齐四件（kernelIndex ordinal 7 / isHdrEncoding / DrtPanelView
  eotfName + 新键 / EditorMTKView 两处），并显式裁 drtLayerColorSpace 的 srgbPiecewise
  臂（推荐：`CGColorSpace(name: .genericRGB)` 不可取——建议 SDR 幂组 gamma 2.2 近似 +
  DECISIONS 记近似偏差，或按 IEC 公式自建 calibrated 表外注）；drtSurfaceSpec 布尔链
  补 `&& record.encodingEotf != .srgbPiecewise` 并加负测；files_modified 补三文件；
  T11 预期改「+1 键（eotfName）」，zh-audit 对表随之。

## 三、minor 清单

- **M1**：`dual_acceptance = true`（.work/config.toml:80-84，2026-10-09 生效）的编排
  缺位——两 plan 均无 omp 二次验收落点，front-matter 无 `-ACCEPTANCE.md` 产物（对照
  M2-8-3/M3-1-03 先例）。处方：两 plan 各补 ACCEPTANCE 记录文件与「zcode PASS 后串行
  omp 二次验收、结论落 ACCEPTANCE、FAIL 回注修复批」工序行（严禁并发为 config 硬约束）。
- **M2**：锚点勘误两处——①plan 02 front-matter 与 read_first 5 写
  `App/Sources/Lightamer/State/WorkspaceModel.swift`，真身 =
  `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift`（drtRecords carrier :249-277
  行号正确；find 亲证 State/ 下无此文件）；②plan 02 KD-3「`load(image:)` 分派点」——
  PixelPipe 无此函数名，真身 = `run(image:)`（:686，:714 写 decodedImage）+ 输入平面
  装配腿 `renderInputPlane`（:628-664，行号锚正确）；分派点应落在 renderInputPlane
  三条 return 之前。files_modified 路径是 commit 边界契约，须改。
- **M3**：「tif 旧被拒→今被受」翻转断言 plan 只令「逐条列名」未列——亲证现存翻转面
  **恰一处**：`ImportFilterTests.swift:79-87`
  `testNoExtensionAndNonWhitelistedFormatsRejected`（`photo.tif → .extensionNotWhitelisted`
  断言，双开缺省下必翻）。处方：plan 02 KD-4 直接列名该测试与新预期（`.tif` 移出循环
  或改判 accepted），并注明 tiff 双扩展变体无第二断言面。
- **M4**：LUT-ICC 两处未钉死——①逆分支：RESEARCH §3.2.4「逆腿只跑**矩阵分支语义**的逆」
  与该节自记 `{displayReferred, linear}` 矛盾（Alcedo :257-259 亲证 LUT-ICC 转换后 =
  display-referred + Linear transfer，走 **display 逆腿**、linearize 恒等）；plan KD-5
  的描述字段隐含 display 分支但 kernel 入口选择规则未写死。处方：KD-5/KD-6 补一句
  「`origin == iccLutConverted` 平面走 `raster_input_display`、TRC=linear 恒等」，并在
  DECISIONS 勘正 RESEARCH §3.2.4 措辞；②判别式：KD-1 未定「A2B0 与 matrix-shaper 并存
  时谁优先」（Alcedo D4 = 「A2B0 **with no** matrix-shaper tags」→ matrix-shaper 优先），
  RasterIccParser 须照抄此优先级 + 双 tag 并存 fixture 一枚。

## 四、亲核锚清单（全部属实）

`RAWDecoder.decode` :118-141 / `decodeRaster` :316-334（多页取 0、32F 保真注记 :299-315、
`decodeRaster` 全仓唯一调用点 = decode() 本体）/ `utiForFile` :401；`DrtEotf` 七值枚举
（DrtRecord.swift:62-77）/ `legalEOTFs` :445 / `isHdrEncoding` :456 / 默认 record :368-381；
`Aces2Reference.swift` 头注 NOT-ported 预留 :20 / stage 图 :24-54 / `TSParams` :90+ /
`tonescaleFwd/Inv` :144/:151 / `params(space:peak:rgcOn:)` :1064（rgc 入键 :1055-1062）/
`runPixel` :1090；`ap0ToRec2020` = Cam16.swift:182（`rec2020ToAP0.inverted()`）；
`DecodedImage` additive 落点（init 全字段显式，optional 双字段可无痕插入）；
`PixelPipe.inputPlaneDedupeKey` :231-246 / `renderInputPlane` :628-664 / `run` :686；
`ImportFilter` 三序 :71-91 / `ImportDefaults` 三键 :126-208 / `LibrarySchema.defaultRawExtensions`
:235-241（无 tif/tiff 亲证）/ `ImportProgress` :55-75（additive Int 可无痕插入）；
`DrtOutputColorSpace` SDR 幂臂 curv 注记 :300-356（L053 para 坑在案）/ 六空间臂组
:60-126 / accept-set==legalEOTFs 不变式测试在册（DrtOutputColorSpaceTests:54-70）；
`TIFFEncoder` ImageIOEncoders.swift:231-273（float32/压缩/TIFFSoftware 签名）；CIContextPool
working space :144-152；WorkspaceModel carrier :238-278；PipeCoordinator updateDrtRecord
:577 / drtEditSeed :713-716；EditorState mint 面 :434-440/:508-518；`LutTransferMath
.srgbEncodeChannel/.srgbDecodeChannel` :320/:328（IOPP 交叉锚可行）；`Scripts/gen-float-fixtures.py`
在册；NOTICE §2 aces-core 条目在册。上游：aces-core v2.0 CTL 亲验（outputTransform_fwd/_inv、
chroma_compress_inv、gamut_compress_inv、tonemap_and_compress_inv、init_TSParams 全在册）；
Alcedo raster_image_input_plan.md D1-D7/§4.2/§5.3/§5.4/§9.3/§12 亲读。

## 五、观察项（不计数）

- **O1**：checker 任务书指认「SpektraLab 仓：栅格输入设计文档」为笔误——栅格输入设计
  正本在 **Alcedo** 仓（`raster_image_input_plan.md` 亲读在案）；SpektraLab 仓内无此文档
  （find 亲证）。RESEARCH/plan 引用（Alcedo 路径）正确，非 plan 缺陷。
- **O2**：synthetic DecodedImage 测试面（EditorMetalLeg/DrtViewport/FilmCoordinator 等
  .tif URL 载体）经亲核**不受路由翻转影响**（rasterColor=nil → seed 跳过 → pristine）——
  E2 普查任务应将此定性为安全判据写明，避免执行期误伤扩大。
- **O3**：`DisplayProfile.swift` 已有 ICC tag walk + per-profile 缓存，KD-1 选择
  RasterIccParser 自持（零触碰）——理由（display/文件域 fallback 链语义不同）成立，
  接受；执行期若两处 tag-walk 漂移可在 DECISIONS 记共用低层 helper 的后续机会。
- **O4**：KD-2「扰动一位有效数字」的扰动-门距未量化——对首数 0.8 级表值一位扰动
  ≈1e-3 相对差 > 2e-4 门 ✓；执行期 T2 验收应实测最小扰动距写入 DECISIONS（并入 E5
  的门值统一裁）。

## 六、结论

**FAIL / 6 error + 4 minor**。六项 error 全部为 plan 内可修复（无一项动摇 OQ 裁决、
波分解或架构红线骨架）；修复后本 checker 无需全量重审，按项复核即可（E1/E2 重审
02 风险节与 T1/T7、E3 重审 KD-3 与 T4、E4/E5 重审 KD-1/KD-9 与 T3/T10、E6 重审
KD-8/T9/files_modified）。修复批处方已逐条给出，供 planner 回注。

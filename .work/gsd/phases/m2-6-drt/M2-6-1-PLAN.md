---
phase: m2-6
plan: "M2-6-1"
title: "OpenDRT 核（wave 1）——DrtRecord schema 单文件（DrtMethod/DrtEotf/DrtEncodingSpace/DrtLimitingSpace 四枚举 + 12 顶层字段 + 53 detailed 参数 + legalEOTFs 联动表 + IsHdrEncoding 纯函数）+ EOTF 编码核七函数（ST2084/HLG/BT.1886/G2.6/G2.2/G1.8/Linear，Swift Float64 + Metal 双落笔）+ OpenDRT Float64 参考实现（dctl 走读转录，算法结构图头注）+ OpenDRT Metal kernel（53 参数 MTLBuffer 单 PSO）+ 预设三件套具名快照（Look 7 + Tonescale 全枚举 + Creative White 6，数值事实转录 + NOTICE 署名）+ sidecar v5→v6 additive + drtTail 尾段策略枚举与管线装配（edrDisplayLeg 收敛 + colorout/gamma 终端对降级）"
wave: 1
depends_on: ["M2-5"]
autonomous: true
requirements: [M2DRT-02, M2DRT-04, M2DRT-06]
files_modified:
  - LightamerCore/Sources/Graph/DrtRecord.swift            # 新建：DrtMethod/DrtEotf/DrtEncodingSpace/DrtLimitingSpace 枚举 + DrtRecord（12 顶层字段）+ OpenDrtDetailedParams（53 Float）+ legalEOTFs(for:) + isHdrEncoding(_:) + stableHash——「联动/HDR 判定知识单文件承载」（CONTEXT Specific Ideas 钦定；OQ-2-A/OQ-5-A/OQ-6-A 落点）
  - LightamerCore/Sources/Pipe/Drt/DrtEotf.swift            # 新建：七 EOTF Swift Float64 编码核（encode/decode 对 + 规范常数单源）
  - LightamerCore/Sources/Pipe/Drt/DrtEotfKernels.metal     # 新建：七 EOTF Metal 公共函数库（kernel 与测试共用同一份常数）
  - LightamerCore/Sources/Pipe/Drt/OpenDrtReference.swift   # 新建：OpenDRT Float64 参考实现（KD-3 阶段序 = 算法结构唯一正本；GPL 源只读，代码零复制）
  - LightamerCore/Sources/Pipe/Drt/OpenDrtKernels.metal     # 新建：OpenDRT per-pixel compute kernel（53+12 参数 MTLBuffer 单 PSO，OQ-10-A）
  - LightamerCore/Sources/Pipe/Drt/DrtPresets.swift         # 新建：预设三件套具名快照（look 7 + tonescale 全枚举 + creative white 6 → OpenDrtDetailedParams 映射表；custom = 派生判定非持久化）
  - LightamerCore/Sources/Pipe/PixelPipe.swift              # 修改：TerminalTailPolicy 尾段策略枚举（edrDisplayLeg 收敛为派生）+ drt 尾段装配（KD-7 半径红线：diff 越界 = 违约）
  - LightamerCore/Sources/Pipe/LayerCompositeDriver.swift   # 修改（本 phase 允许触碰面）：composite 入参增 terminalTail 透传（与既有 edrDisplayLeg 参数同位同半径）
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift    # 修改：schemaVersionCurrent 5→6 + document 级 `displayTransform: DrtRecord?` additive 字段（decodeIfPresent + encodeIfPresent，v5 档字节零漂移）
  - NOTICE                                                  # 新建（仓根）：jedypod/open-display-transform v1.1.0 (GPLv3) provenance 署名——算法思路参考 + 数值表转录，零代码复制（OQ-1-A）；aces-core 条目占位（M2-6-2 补）
  - Project.swift                                           # 修改：新测试文件登记（bundle 无 glob 豁免——checker E2 纪律；新源文件目录 tuist generate 覆盖）
  - Tests/LightamerTests/DrtRecordTests.swift               # 新建（LAYERS，Core 级——PipelineDocumentTests 同位）：枚举/默认值/联动表全枚举/HDR 判定/stableHash/Codable round-trip
  - Tests/LightamerTests/DrtEotfTests.swift                 # 新建（LAYERS）：七 EOTF Float64 规范锚点 + 往返 + GPU 对齐
  - Tests/LightamerTests/DrtKernelGoldenTests.swift         # 新建（IOPP，Golden* glob 惯例）：OpenDRT 阶段函数单测 + kernel GPU vs Float64 参考 golden（探针输入）
  - Tests/LightamerTests/DrtPresetsTests.swift              # 新建（LAYERS）：预设快照完备性 + 默认值断言 + custom 判定
  - Tests/LightamerTests/DrtTailTests.swift                 # 新建（LAYERS，LayerCompositeTests 同位）：尾段策略枚举三态 + 非 drt 路径逐字节不变 + SDR/HDR 平面格式 + 键稳定
  - Tests/LightamerTests/DrtSidecarTests.swift              # 新建（APP，SidecarV5Tests 同位——undo/redo 载入链实例化 EditorState）：v6 additive 双向 + v5 档字节零漂移 + 未来版本容忍
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：六个新测试文件增行（登记纪律②，同 commit）
  - .work/gsd/phases/m2-6-drt/M2-6-1-SUMMARY.md             # 新建（收口任务）
  - .work/gsd/phases/m2-6-drt/M2-6-1-DECISIONS.md           # 新建（收口任务）
  - .work/GOAL-STATE.md                                     # 续接点追加（收口任务）
  - .work/LESSONS.md                                        # 如踩坑
---

# Plan M2-6-1 — OpenDRT 核（DrtRecord schema + EOTF 编码核 + Float64 参考 + Metal kernel + 预设三件套 + sidecar v6 + drtTail 装配）

> **性质**：算法/管线 plan——App 层零改动（面板/持久化接线/HDR 视口归 P3/M2-6-3，ACES 2.0 method
> 归 P2/M2-6-2）。六块交付：①**DrtRecord 单文件 schema**（OQ-2-A/OQ-5-A/OQ-6-A 落盘：四枚举 +
> 12 顶层字段 + 53 detailed 参数 + `legalEOTFs` 联动表 + `isHdrEncoding` 纯函数 + stableHash）；
> ②**EOTF 编码核七函数**（M2DRT-04 编码腿地基 + M2-9 导出复用缝）；③**OpenDRT Float64 参考实现**
> （OQ-11-A：dctl 只读走读转录，算法结构图头注 = 全 phase 数学正本）；④**OpenDRT Metal kernel**
> （OQ-10-A：参数 buffer 化单 PSO）；⑤**预设三件套具名快照**（OQ-1-A：数值事实转录 + NOTICE）；
> ⑥**sidecar v5→v6 additive + drtTail 尾段装配**（OQ-2-A/OQ-8-A：`TerminalTailPolicy` 收敛 +
> colorout/gamma 终端对降级，非 drt 路径逐字节不变）。规格锚点 = D-M2-6-CONTEXT-1..12
> （不得重开）+ FEATURE-MAP §5 + REQUIREMENTS M2DRT-02/04/06。
>
> **执行期精读悬决点**（CONTEXT「夜间授权预案」预告的 plan 期回填项中属本 plan 的三件，全部在
> T1-T5 内核读钉死、DECISIONS 签注）：①预设数值转录许可边界（OQ-1 附注——夜间授权已按 A 生效，
> 执行期只做 NOTICE 落笔与数值抽检记录，不再重开）；②预设枚举真值清单（tonescale 15 项系
> REQUIREMENTS 计数，以 dctl `DEFINE_UI_PARAMS` 枚举清单为准——差异勘误注记入 DECISIONS，不改
> REQUIREMENTS 原文）；③EOTF 规范常数终式（BT.1886 黑位参数/HLG OOTF 参考环境光取值——以
> ITU-R 规范 + dctl `eotf_pq`/`eotf_hlg`（:453/:476）数值抽检对照钉死）。**语义忠实 > 数学家
> 自洽**：dctl 实现为唯一对照源，公式照思路重写，GPL 代码零复制入库。

## 已定裁决（不得重开）

- **D-M2-6-CONTEXT-1（OQ-1 A）**：OpenDRT = 独立实现（GPLv3 上游只读算法参考）+ 预设数值表
  转录 + NOTICE 署名；零代码拷贝（M2GRADE-07/darktable 先例）。
- **D-M2-6-CONTEXT-2（OQ-2 A）**：sidecar v5→v6 additive，document 级 `displayTransform`
  record；全字段 decodeIfPresent；hash 判定 = set-fields-move（进渲染哈希，非 rawOverrides 式
  hash-isolation）；预设 = 具名快照；custom = 派生展示值不持久化。
- **D-M2-6-CONTEXT-5（OQ-5 A）**：`legalEOTFs(for:)` Core 单源纯函数 + 切换吸附（吸附 UI 行为
  P3）；模型层 EOTF 枚举全 7 值，UI 暴露合法子集。
- **D-M2-6-CONTEXT-6（OQ-6 A）**：`isHdrEncoding` 纯函数（∈{ST2084, HLG}）；DRT 激活文档上
  colorout/gamma 终端对降级（edrDisplayLeg「尾段 demote」同缝）；SDR = DRT 尾段产 8bit 显示
  平面；HDR = 编码值直写 16F 平面（视口 colorSpace 切换归 P3）。
- **D-M2-6-CONTEXT-8（OQ-8 A）**：DRT = composite 后文档级终端段，非 v50 iop；v50 表零新增槽；
  渲染序 C_N → DRT → Post 四件（P3 填充）→ EOTF 编码 → 显示/导出。
- **D-M2-6-CONTEXT-10（OQ-10 A）**：53 参数 MTLBuffer 传入（非 function constant）→ 参数拖动
  零 PSO 重编译，单 kernel 单 PSO 常驻；PREVIEW 桶 2560 帽不变；不做分段编译/降参预览。
- **D-M2-6-CONTEXT-11（OQ-11 A）**：自建 Swift Float64 参考实现 + dctl 走读交叉验证 + 确定性
  合成探针；GPL 管线渲染参考图不入库。
- **D-M2-6-CONTEXT-12（OQ-12 A）**：`DrtMethod` 枚举 = aces20/opendrt 两 case（aces20 的渲染
  臂本 plan 落显式 stub，P2 填充）；filmic/sigmoid/agx **不入枚举**（v1 零注册——注册口 = 枚举
  rawValue 空间 + method 分派 switch 穷举形状 + 注记）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 DrtRecord 单文件 schema = 联动/HDR 判定知识单源

```swift
// LightamerCore/Sources/Graph/DrtRecord.swift（与 PipelineDocument 同目录，OQ-2-A）
public enum DrtMethod: String, Codable, Sendable, CaseIterable {
    case aces20      // 渲染臂本 plan = 显式 stub（KD-6），P2 填充
    case opendrt     // 默认
}
public enum DrtEotf: String, Codable, Sendable, CaseIterable {
    case linear, st2084, hlg, gamma26, bt1886, gamma22, gamma18   // 模型层全 7 值
}
public enum DrtEncodingSpace: String, Codable, Sendable, CaseIterable {
    case rec709, p3d65, p3d60, p3dci, xyz, rec2020                // 六选
}
public enum DrtLimitingSpace: String, Codable, Sendable, CaseIterable {
    case rec709, rec2020, p3d65, p3d60, p3dci, proPhoto, adobeRGB // ACES 专属七选
}
public struct OpenDrtDetailedParams: Codable, Hashable, Sendable {
    // 53 个 Float 字段，命名与 JSON key 照抄 drt_node_model.hpp:45-98 spelling
    // tn 系 9 + cwp_lm 1 + rs 系 3 + pt_lml 系 4 + pt_lmh 系 3 + ptl 系 3
    // + ptm 系 6 + brl 系 6 + brlp 系 4 + hc 系 2 + hs 系 12 = 53
}
public struct DrtRecord: Codable, Hashable, Sendable {
    // 12 顶层字段照抄 DrtPayload（drt_node_model.hpp:101-113）：
    // method/encodingSpace/encodingEotf/limitingSpace/peakLuminance
    // lookPreset/tonescalePreset/creativeWhite
    // creativeWhiteLimit(0.25)/displayGreyLuminance(10)/hdrGreyBoost(0.13)/hdrPurity(0.5)
    // + parameters: OpenDrtDetailedParams（嵌套单对象，editor-owned 参数组整体序列化）
    public init()   // 默认 = OpenDRT / Rec709 / Gamma22 / peak 100 / standard /
                    // use_look_preset / use_look_preset（hpp 默认逐字段）
    public func stableHash() -> UInt64   // StableHash(FNV-1a) over canonical JSON
                                         // 字节（sortedKeys，L013 纪律）
}
public func legalEOTFs(for space: DrtEncodingSpace) -> [DrtEotf]
//   rec709 → [.bt1886, .gamma22]; p3d65 → [.gamma22, .st2084];
//   p3d60/p3dci/xyz → [.gamma26]; rec2020 → [.st2084, .hlg]（FEATURE-MAP §5 联动表逐行）
public func isHdrEncoding(_ eotf: DrtEotf) -> Bool   // ∈ {.st2084, .hlg}
public func isDrtRecordDefault(_ r: DrtRecord) -> Bool  // == DrtRecord()（pristine 判定）
```

- **JSON key 纪律**：顶层与 53 参数的 JSON spelling 照抄 Alcedo hpp（`encoding_space`/
  `peak_luminance`/`tn_con`/`ptm_high_rng`…snake_case）——与 sidecar 既有「参数 JSON key 照抄
  Alcedo spelling」惯例一致（M2-5-1 KD-6 同款）； CodingKeys 全显式，禁 Swift 自动 camelCase
  转换。rawValue 字符串终值（method/空间/EOTF 的序列化形态）执行期核读 `drt_node_model.cpp`
  ToJson 钉死、DECISIONS 签注（工作假设 = hpp 枚举名 snake_case 直译）。
- **一致性维持答案（KD 必答）**：本 plan **不改任何加载/校验路径**——DrtRecord 是纯数据面，
  decode 面只有 sidecar v6 additive（KD-5）；PipelineDocument/LayerStack/NodeGraphCommand
  零触碰（图拓扑零改动，CONTEXT 事实基线③）。`displayTransformNodeID` 消费零变化。
- **联动表完备性机检**：`DrtRecordTests` 全枚举断言——六空间 × legalEOTFs 逐空间比对字面表 +
  每 space 的合法 EOTF 非空 + `isHdrEncoding` 七值逐个断言（st2084/hlg true，其余 false）。
  「模型层 7 值 vs UI 合法子集」的差（linear/gamma18 全空间非法）由表自然表达——不存在
  「legalEOTFs 返回空」的空间。

### KD-2 EOTF 编码核七函数 = Swift Float64 + Metal 公共库双落笔

- 七函数：`linear`（恒等）/ `st2084`（PQ，ITU-R BT.2100：`E' = (c1 + c2·Y^m1) / (1 + c3·Y^m1)`
  的 1/n 幂形，Y = 线性值 × peak nits / 10000）/ `hlg`（BT.2100 reference OOTF + 逆 OETF，
  1000-nit 参考 peak——OOTF 环境光项执行期按规范 Table 5 简化式钉死、DECISIONS 签注）/
  `gamma26`/`gamma22`/`gamma18`（纯幂）/ `bt1886`（ITU-R BT.1886：gamma 2.4 + 黑位 lift 项，
  Lb 执行期按规范 + dctl 数值抽检钉死）。
- **双落笔纪律**：Swift（`DrtEotf.swift`，Float64）与 Metal（`DrtEotfKernels.metal`，float）
  是**同一份推导两个落笔**——常数逐个对齐（测试逐常数断言），头注「EOTF 常数唯一源在
  DrtEotf.swift，Metal 侧禁另立常数」。decode = 精确逆（测试逐函数往返断言）。
- **规范锚点（机检）**：PQ 100 nits → 码值 ≈ 0.5081、PQ 1000 nits ≈ 0.7520、PQ 10000 nits
  = 1.0（BT.2100 表值，容差 ≤1e-4——表值本身 4 位）；gamma22(0.5) = 2^(-1/2)；bt1886 黑位
  锚点执行期随终式钉。HLG 0.75 信号 → 场景 ≈ 0.264（reference OOTF 表值）。
- **peak 语义（KD 必答）**：`peakLuminance` 只进 PQ/HLG 两函数的亮度归一（SDR gamma 族
  peak 无效——测试断言 gamma 族输出与 peak 参数无关）；peak ∈ [100, 1000]，越界钳制在
  DrtRecord 构造/validation 缝（P3 面板消费，Core 层纯函数不钳——记录入注）。

### KD-3 OpenDRT Float64 参考实现 = 算法结构唯一正本（dctl 走读转录）

`OpenDrtReference.swift` 头注 = **算法结构图**（执行期按 `OpenDRT.dctl:737` `transform()` 主
体逐段转录，以下为走读预勘的阶段骨架——**执行期以 dctl 为准修订头注，DECISIONS 签注终版**）：

```
[0] 输入线性化（v1 恒 linear working，in_oetf 菜单不暴露——CONTEXT 衔界面）
[1] 输入 gamut → P3-D65 render gamut（in_to_xyz → matrix_xyz_to_p3d65；v1 输入恒
    working linear Rec2020，不露 dctl 15 种 in_gamut——CONTEXT OQ-3 附注）
[2] Render space 去饱和（rs_sa/rs_rw/rs_bw 权重 sat_L lerp——色体积比率控制）
[3] Offset（tn_off）+ tonescale norm（tsn，display_grey_luminance 锚）
[4] RGB ratios（rgb / tsn）
[5] 色相角常量表（ha_rgb / ha_cmy）
[6] Pre Brilliance（brl 系 6，gauss 窗）
[7] Contrast Low（tn_lcon/tn_lcon_w）→ [8] Contrast High（tn_hcon 系 3）
[9] Hyperbolic compression（per-channel tonescale：tn_con/tn_sh/tn_toe，
    compress_hyperbolic_power + compress_toe_quadratic，dctl :503/:508）
[10] Hue contrast（hc 系 2，g/b 随强度缩放）→ [11] Hue Shift RGB（hs_r/g/b + rng，
     随强度）→ [12] Hue Shift CMY（hs_c/m/y + rng，逆强度）
[13] Purity Limit Low（ptl 系 3，softplus）→ [14] Purity tone maps（pt_lml 系 4 +
     pt_lmh 系 3 + ptm_low/high 系 6，gauss 窗）→ [15] lerp to peak achromatic（ptf）
[16] Inverse render space（[2] 的逆式）
[17] display_gamut_whitepoint（CAT 白点矩阵 D93/D75/D65/D60/D55/D50 + cwp_lm 混合，
     dctl :593——creative white 落点）
[18] Post Brilliance（brlp 系 4）→ [19] Purity Compress Low（softplus 二次）
[20] Final tonescale adjustments（crv overlay）→ [21] RGB ratios 复原（× tsn）
[22] 输出 = display-referred encoding space 原色线性（EOTF 编码独立在 EotfBox，KD-4）
外围：HDR 灰轨（hdr_grey_boost/hdr_purity，100→1000 nits pt_cmp lerp，dctl :481 注）+
     peak luminance（tn_Lp limiting）+ display_grey_luminance
```

- **纪律**：每阶段函数独立命名（`refTonescale`/`refPurityCompress`/…前缀 Float64 纯函数），
  测试注释列 `OpenDRT.dctl:<行号>` 对照；发现 dctl 实现与本推导冲突时**以 dctl 为准**同批改
  参考与 kernel（M2-5-1 风险节同款立场）。测试注释/参考实现注释允许引用 dctl 行号（事实性
  引用），**禁止**复制 dctl 代码文本（GPL）。
- **阶段函数单测（T3）**：`compress_hyperbolic_power`/`compress_toe_quadratic`/`softplus`/
  `contrast_high` 等 primitive 对 dctl 内嵌 desmos 锚点 + 数值抽检点断言（容差 KD-8）；
  tonescale 全域单调性（1000 点 ramp 输入序保持）；端点有界无 NaN（0/1e-6/1/1e6/负值钳制）。

### KD-4 OpenDRT Metal kernel + 尾段 EOTF 分离

- **kernel 形态**：单 compute kernel per-pixel 无邻域；参数 = `DrtUniforms` struct 经
  `MTLBuffer` 传入（53 detailed + 12 顶层 + 常量表索引），**零 function constant**（OQ-10-A：
  拖动零重编译）；输出 = display-referred **encoding space 原色线性** float32 平面。
- **EOTF 独立段**：DRT kernel 与 EOTF 编码**不内联合一**——尾段装配为 `[DrtMethodBox] →
  [EotfBox]` 两枚 driver 直构 box（ACEScc envelope 先例，M2-5-1 KD-2：零 registry、零
  sidecar、不出现在 add 面）。分离理由：①EOTF 七函数独立可测（M2-9 导出腿同核复用，OQ-7-A
  「给定 DrtRecord + 像素 → 编码后平面」的纯函数缝）；②ACES 2.0 method（P2）共享同一
  EotfBox——method 差异只在 DrtMethodBox 一段。
- **Post 四件插槽（P3 锚）**：尾段装配函数内留显式注释锚 `// Post-four slot (M2-6-3 T5)`
  ——本 plan 插槽恒空，**不**落任何四件逻辑。
- **golden（T4）**：确定性合成探针输入三件套（①linear ramp 0..4 步进 1024 点；②色卡网格
  8×8 饱和度×色相；③极饱和探针（RGB 原色/二次色 × 0.01..100 亮度对数扫））× 参数点
  （default / arriba / umbra / HDR 点 rec2020+st2084+1000nits）vs Float64 参考；
  PREVIEW（2560 帽）与 FULL（探针小图）双路径各跑一遍（OQ-10 风险面），两路径 golden 同容差。
- **identity 面**：DRT 无恒等参数点（tone mapping 天然非恒等）——`isDrtRecordDefault` 是
  **持久化 pristine 判定**非渲染恒等（测试断言二者语义分离：default 参数渲染输出 ≠ 输入）。

### KD-5 sidecar v6 additive = v5 惯例逐条照抄

- `schemaVersionCurrent` 5→6；`CodingKeys` 增 `displayTransform`；decode
  `decodeIfPresent(DrtRecord.self)`（v5 档与 FUTURE 版容忍分支同 :323 先例）；encode
  `encodeIfPresent`（nil = pristine 保持 key ABSENT——rawOverrides v5 先例，**v5 档字节零
  漂移**测试钉死）。
- **hash 判定 = set-fields-move（KD 必答）**：DrtRecord 影响渲染 → 进 drift 判定链
  （**非** rawOverrides 式 hash-isolation，OQ-2-A 字面）。机制分工：本 plan 落字段 + 双向
  Codable 测试；historyHash 折叠的实现载体 = HistoryItem 新 additive 快照字段（P3 T1 落——
  DRT 编辑必经 history item，届时 history 投影把末位 drt item 的 DrtRecord.stableHash 折进
  historyHash，drift 判定自然覆盖）。**本 plan 不动 HistoryStack**（零触红线）。
- **头注同批**：`LightamerSidecar.swift` v5 文档注释块续写 v6 段（照 v2/v3/v4/v5 段式样）。

### KD-6 drtTail 尾段策略枚举 + 管线装配（TerminalTailPolicy）

```swift
// PixelPipe.swift 内（收敛 OQ-6-A 的「尾段 demote」缝 + CONTEXT Specific Ideas 悬决点⑤）
public enum TerminalTailPolicy: Sendable, Equatable {
    case sdrGamma                       // 现默认：colorout → gamma（sRGB TRC 8bit）
    case edrLinear                      // 现 edrDisplayLeg：gamma 降级，float colorout 平面
    case drt(DrtTailParams)             // M2-6 新：colorout+gamma 双降级，尾段接管
}
public struct DrtTailParams: Sendable, Equatable {
    public let record: DrtRecord
    public let recordHash: UInt64       // stableHash 预算好传入（键折叠单源）
}
```

- **收敛方式（半径红线）**：`edrDisplayLeg` 存储属性改为**派生计算属性**
  （`terminalTail == .edrLinear`），两处既有判定点（`PixelPipe.swift:655`/`:873` gamma skip
  条件）**引用与语义零改**——EDR 既有测试（EDRViewportTests 等）全绿零改动 = 收敛无回归的
  活体证明。调用面：`process`/`processComposite` 的 `edrDisplayLeg: Bool` 参数换
  `terminalTail: TerminalTailPolicy = .sdrGamma`（默认值 = 现行为；**调用点穷举**——App
  PipeCoordinator 传点 + 测试传点逐个改，`git grep edrDisplayLeg` 零残留为 AC 机检）。
- **drt 尾段装配（run 内，顶位置渲染后）**：①colorout+gamma 入 skip 集（同 EDR gamma 降级
  模式——禁用判定在 pass 装配处，非运行时跳跑）；②尾段 box 链 `[DrtMethodBox] → [EotfBox]`
  driver 直构（KD-4）在顶位置输出平面上续跑；③输出平面格式按 `isHdrEncoding` +
  EOTF 族：SDR（bt1886/gamma26/gamma22/gamma18）= `.bgra8Unorm` 显示平面（gamma 尾段先例：
  软件编码 + drawable 非 _srgb 变体）；HDR（st2084/hlg）= `.rgba16Float`（EDR 先例，16F
  drawable 直写）；linear = float32（编码空间线性原色，视口走 EDR 线性腿先例）。
- **缓存键（KD 必答——`PipeCacheKey.swift` 零 diff 红线）**：尾平面键 = 顶位置+1 的既有键
  结构，`upstreamHash = levelHash[top] ⊕ recordHash ⊕ tailPolicyHash`（policy 折叠进
  upstreamHash，无新 key 字段）；EOTF 切换 → recordHash 不变但 policy 变 → 尾平面重算而
  colorout 前全 HIT（与 gamma 先例「显示变更只重跑 colorout+gamma 段」同型）；EDR 开关
  （.sdrGamma ↔ .edrLinear）零失效语义不变（既有注释 :135-146 断言语义由测试保持）。
  EXPORT 不缓存红线不动（11-03）。
- **零行为差门（AC 硬条）**：`terminalTail == .sdrGamma` 时全管线输出**逐字节**等于改造前
  （DrtTailTests 以既有 fixture 栈断言——非 drt 文档/env 回切路径行为不变，OQ-6-A 字面）。

### KD-7 预设三件套 = 数值事实转录 + NOTICE

- `DrtPresets.swift`：
  - `DrtLookPreset`：standard/arriba/sylvan/colorful/aery/dystopic/umbra 七具名（+ custom
    派生态）→ 各自 `OpenDrtDetailedParams` 全 53 值（dctl `:791-828` 各 look 分支数值表
    逐字段转录——**数值事实**，OQ-1-A 许可边界内）。
  - `DrtTonescalePreset`：枚举清单执行期从 dctl `DEFINE_UI_PARAMS(_tonescale_preset,…)`
    枚举转录（REQUIREMENTS 记 15 项；实际枚举以 dctl 为准，差异勘误注记 DECISIONS）——每项
    → tn 系参数覆盖表（use_look_preset = 不覆盖，随 look）。
  - `DrtCreativeWhite`：useLookPreset/d93/d75/d65/d60/d55/d50（dctl `_cwp` 七值——6 具名
    白 + use_look_preset，FEATURE-MAP「6」按具名白计数）。
  - `applyPreset(record:look:tonescale:white:) -> DrtRecord`：一次原子应用（P3 面板消费，
    本 plan 落纯函数 + 测试）。
  - `isCustomLook(record:) -> Bool`：当前 53 参数不匹配任何内置快照 → custom（派生展示值，
    不持久化额外字段——OQ-2-A）。
- **NOTICE（仓根新建）**：jedypod/open-display-transform v1.1.0（GPLv3）——算法思路只读
  参考 + 预设数值表转录，未复制代码；Lightamer 本体保持 MIT。aces-core 条目 P2 补（本 plan
  占位注释）。
- **数值抽检（不做进测试断言）**：Alcedo `tests/resources/expected_parameters/drt/*.bin`
  （GPL 资产，只读不入库）参数 dump 与转录表执行期一次性 Float 位级对照（如
  `metal_opendrt_arriba_p3d65_gamma22_expected_params.bin`），结果（一致/偏差清单）记
  DECISIONS——**测试断言只用我们自己的表**（CI 环境无 Alcedo 仓，GPL 数据不进断言路径）。

### KD-8 容差谱（checker 教训③：AC 机检逐条含 IEEE 容差）

| 层级 | 容差 | 说明 |
|---|---|---|
| Float64 纯函数（EOTF 规范锚点/CAT 矩阵/阶段 primitive） | ≤1e-6 | Swift Float64 对 Float64 |
| 规范表值锚点（BT.2100 PQ/HLG） | ≤1e-4 | 表值本身 4-5 位有效 |
| GPU kernel vs Float64 参考 | absolute ≤1e-5，p99.9 达标 + max ≤5e-5 硬顶报警行 | float32 纹理量化 + ~40 阶段级联（M2-5-1 KD-8 分级同款） |
| IEEE 语义 | -0/+0 视相等；NaN/Inf 恒 fail | 全 AC 口径 |

- **容差谱升级评估点（风险显式化）**：per-pixel 大算子级联在 float32 下的系统性偏差可能超
  1e-5——T4 golden 实测若 p99.9 超标，按**值域分级**调整（低值段 relative 容差 / 高值段
  absolute），**逐参数点 DECISIONS 签注终谱 + 上界来源分析**，禁静默全局面放宽、禁逐测试
  随手调数（checker 教训①：穷举触点——放宽必须点名每条被改断言）。

## read_first

1. `.work/gsd/phases/m2-6-drt/M2-6-CONTEXT.md`——裁决正本（D1..D12 + 三条事实基线 +
   Reusable Assets 表 + Integration Points）。
2. `LightamerCore/Sources/Graph/PipelineDocument.swift:30-145`——displayTransformNodeID
   端点语义（本 plan 零触碰，消费面认知）。
3. `LightamerCore/Sources/Pipe/PixelPipe.swift:115-146,640-680,860-880,1069-1092`——
   edrDisplayLeg 语义/两处 gamma skip 判定/process 签名（KD-6 收敛点）。
4. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:86-145,280-400`——v5 additive
   惯例正本（v6 逐条照抄：decodeIfPresent/encodeIfPresent/未来版本容忍/头注段式）。
5. `LightamerCore/Sources/Pipe/Terminal/GammaModule.swift` + `ColorOutModule.swift`——现
   终端对语义（SDR 8bit 软编码 + drawable colorSpace 匹配先例——DRT SDR 尾段继承）。
6. Alcedo 参考源（只读，代码零复制）：`alcedo_studio/src/config/DRTs/OpenDRT.dctl`
   （:43-200 参数定义 / :301-735 数学函数 / :737-1211 transform 主体）+
   `src/include/edit/graph/drt_node_model.hpp`（:31-85 参数模型 / :99-113 payload 默认）
   + `tests/resources/expected_parameters/drt/*.bin`（数值抽检用，不入库）。
7. `Tests/LightamerTests/`（LayerCompositeTests / EDRViewportTests 先例任一）+
   `Scripts/test-direct.sh` 头注——测试落点与跑法。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；git add 用
   `.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；不加 `-derivedDataPath`；新建目录/文件后
   同 commit 内跑 `tuist generate`。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行双读（L028）。**回归基线 = 2327/16skip/0fail**；每任务全套 suite 绿。
   **全套跑法 = `Scripts/test-direct.sh --all`（七 bundle）**；跑前必须向 orchestrator
   报备；RSS ≥8G = MEMFAIL 机检内置，触发即记 E3 不自行重试超两次。在案 flake 隔离复跑 ×3
   归因入 SUMMARY。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`PipeCacheKey.swift`/`PipelineDocument.swift`/`LayerStack.swift`/
   `MaskSpec.swift`/`LibrarySchema.swift`/`HistoryStack.swift`/`NodeOwnershipCatalog.swift`
   /`Registry.swift`/`V50Order.swift` **零 diff**（DRT 非 iop——注册面/v50 面/所有权面全
   不触）；`PixelPipe.swift` 改动半径 = TerminalTailPolicy 枚举 + drt 尾段装配 + 头注
   （blend 公式/retouch leg/base sub-run/composite 段零改动——diff 越界 = 违约）；
   `LayerCompositeDriver.swift` 改动半径 = terminalTail 参数透传（与既有 edrDisplayLeg
   参数同位）；`EditorTabRoute.swift`/App 层全目录零触（P3 面）。GPL 参考只读（dctl 代码
   与 expected bins 不入库）。
6. **测试登记纪律（checker E2）**：新建测试文件**同 commit** 登记两处——①`Project.swift`
   对应 bundle sources 显式清单；②`.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`
   增行（`<bundle>\t<method-count>\t<file>`）。归属：DrtRecordTests/DrtEotfTests/
   DrtPresetsTests/DrtTailTests = **LAYERS**（Core 级，LayerCompositeTests/PipelineDocumentTests
   同位）；DrtKernelGoldenTests = **IOPP**（Golden* glob 惯例）；DrtSidecarTests = **APP**
   （SidecarV5Tests 同位——undo/redo 载入链实例化 EditorState）。运行期总数基线相应上移
   （对账以 BUNDLE 行为准）。
7. **收口核对（checker 教训②前置）**：T8 `git diff --stat` 与 front-matter files_modified
   逐文件核对，越界 = 违约。
8. **枚举穷举纪律**：`DrtMethod`/`DrtEotf`/`DrtEncodingSpace`/`DrtLimitingSpace`/`
   TerminalTailPolicy` 上的一切 switch **无 default 臂**（新增 case 编译期爆漏臂——
   M2DRT-06 注册口形状的机检面）；本 plan 新增的每处 switch 在测试中加穷举断言
   （CaseIterable 全域驱动）。

## Tasks

### T1 DrtRecord schema 单文件 + 联动表 + HDR 判定

- **read_first**：上列 1/2/6（hpp :31-113）。
- **action**
  1. 新建 `LightamerCore/Sources/Graph/DrtRecord.swift`：KD-1 全量（四枚举 + 53 参数结构 +
     DrtRecord + legalEOTFs + isHdrEncoding + isDrtRecordDefault + stableHash；JSON key
     照抄 hpp spelling；rawValue 终式核读 hpp ToJson 钉死、DECISIONS 签注）。
  2. 新建 `Tests/LightamerTests/DrtRecordTests.swift`：枚举 CaseIterable 计数断言（2/7/6/7）+
     默认值逐字段断言（hpp :46-98/:101-113 逐字段）+ 联动表全枚举（六空间逐空间比对字面表 +
     「每空间合法集非空」+ linear/gamma18 全空间非法）+ isHdrEncoding 七值逐个 + Codable
     round-trip（canonical sortedKeys 字节稳定两次编码逐字节相等——L013）+ stableHash 稳定
     （同值同 hash / 换一字段换 hash）+ 53 字段编码后 JSON key 集合 = hpp 字段名集合逐个断言。
  3. 测试登记两处（纪律 6）。
- **验收标准**
  - [ ] 上述断言全绿；JSON key 集合与 hpp :45-98 + :101-113 逐字段一致（机检）。
  - [ ] 全套回归 `0 fail`（基线 2327 + 新增）。

### T2 EOTF 编码核七函数（Float64 + Metal 双落笔）

- **read_first**：上列 5/6（dctl :453-500 eotf_hlg/eotf_pq 数值抽检对照）/7。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/DrtEotf.swift` + `DrtEotfKernels.metal`：KD-2
     全量（七函数 encode/decode 双落笔 + 常数单源头注）。
  2. 新建 `Tests/LightamerTests/DrtEotfTests.swift`：规范锚点（PQ 100/1000/10000 nits、
     HLG 0.75、gamma22(0.5)、bt1886 终式锚点）+ 逐函数往返（≤1e-6）+ GPU vs Float64
     （≤1e-5 p99.9 + max 5e-5 报警行）+ peak 无效性断言（gamma 族输出与 peak 无关）+
     线性段/暗端 NaN 无 + IEEE -0/+0 口径。
  3. 测试登记两处。
- **验收标准**
  - [ ] 规范锚点 ≤1e-4 全绿；往返 ≤1e-6 全绿；GPU 对齐全绿；常数终式（BT.1886 黑位/HLG
        OOTF 简化式）入 DECISIONS。
  - [ ] 全套回归 `0 fail`。

### T3 OpenDRT Float64 参考实现

- **read_first**：上列 6（dctl :301-735 函数库 + :737-1211 transform 主体）。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/OpenDrtReference.swift`：KD-3 全量（阶段函数族
     Float64 + 算法结构图头注 + `refOpenDRT(record:linearRGB:peak:)` 总入口——DrtRecord +
     输入线性 RGB → 输出 encoding space 线性 RGB）。
  2. `Tests/LightamerTests/DrtKernelGoldenTests.swift`（本任务先建文件，T4 续用）：阶段
     primitive 单测（hyperbolic/toe/softplus/contrast 族对 dctl 锚点）+ tonescale 全域
     单调性 + 端点有界无 NaN + 总入口 default 参数点数值锚（执行期从参考实现自身输出取锚，
     注释注明「锚 = 参考实现自洽基线，kernel 对齐目标」）。
  3. 测试登记两处（文件归属 IOPP）。
- **验收标准**
  - [ ] primitive 锚点/单调性/有界性全绿；结构图头注阶段序与 dctl transform 逐段对应
        （code review 项，SUMMARY 引 dctl 行号清单）。
  - [ ] 全套回归 `0 fail`。

### T4 OpenDRT Metal kernel + golden

- **read_first**：上列 3/6/7。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/OpenDrtKernels.metal`：KD-4 全量（单 kernel +
     DrtUniforms buffer + 阶段序照参考实现头注阶段号）。
  2. golden（`DrtKernelGoldenTests.swift` 续）：KD-4 探针三件套 × 参数四点 vs Float64
     参考（KD-8 容差谱）+ PREVIEW/FULL 双路径各一遍 + 位精确确定性断言（同 PSO 同输入两次
     运行逐字节相等）+ aces20 臂 stub 断言（KD-6/T5——`fatalError` 语义以测试锁定 P2 替换面）。
  3. 若 p99.9 超 1e-5：按 KD-8 升级评估点流程处置（值域分级 + DECISIONS 逐断言签注）。
  4. `tuist generate`（新目录一次覆盖 T2-T4）。
- **验收标准**
  - [ ] golden 全绿（或 DECISIONS 签注的分级容差终谱全绿）；确定性断言绿；报警行（max 值）
        记入 SUMMARY。
  - [ ] 全套回归 `0 fail`。

### T5 预设三件套 + NOTICE

- **read_first**：上列 6（dctl :43-200 参数/枚举定义 + :791-828 look 分支）。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/DrtPresets.swift`：KD-7 全量（look 七具名快照 +
     tonescale 枚举真值清单 + creative white 七项 + applyPreset 纯函数 + isCustomLook）。
  2. 仓根新建 `NOTICE`：jedypod provenance 署名（KD-7 文本要点）。
  3. 新建 `Tests/LightamerTests/DrtPresetsTests.swift`：七 look 快照完备（53 字段逐字段
     非 nil/默认值 spot 断言 standard = DrtRecord().parameters）+ applyPreset 原子性
     （应用后 record 与快照逐字段相等）+ isCustomLook（改一字段 → true；复原 → false）+
     tonescale 枚举计数断言（真值清单，勘误差异 DECISIONS 记）+ creative white 七项。
  4. 数值抽检（KD-7）：Alcedo expected bins 对照，结果记 DECISIONS（非测试）。
  5. 测试登记两处。
- **验收标准**
  - [ ] 预设断言全绿；NOTICE 在册；抽检结论入 DECISIONS（含 tonescale 枚举勘误若有）。
  - [ ] 全套回归 `0 fail`。

### T6 sidecar v6 additive

- **read_first**：上列 4。
- **action**
  1. `LightamerSidecar.swift`：KD-5 全量（schemaVersionCurrent 6 + CodingKeys + decode/
     encode + 头注 v6 段续写）。
  2. 新建 `Tests/LightamerTests/DrtSidecarTests.swift`（APP bundle）：v6 round-trip
     （displayTransform 非 nil 档写读一致）+ **v5 档字节零漂移**（无 DRT 编辑的文档编码
     字节与 v5 写出逐字节相等）+ v5 档读取 displayTransform == nil + 未来版本（schema
     99）容忍降级 + displayTransform 变更进渲染哈希的**前置面**测试（record.stableHash
     与 decodeParamsHash/instance hash 无耦合——set-fields-move 判定的 P3 载体占位注记）。
  3. 测试登记两处。
- **验收标准**
  - [ ] v6 双向 + 零漂移 + 容忍全绿；`LightamerSidecar.swift` diff 仅 additive（逐 hunk 核）。
  - [ ] 全套回归 `0 fail`。

### T7 drtTail 尾段策略枚举 + 管线装配

- **read_first**：上列 3/5/7。
- **action**
  1. `PixelPipe.swift`：KD-6 全量（TerminalTailPolicy + edrDisplayLeg 派生化 + 调用点
     穷举改传 + drt 尾段装配 `[DrtMethodBox] → [EotfBox]` + colorout/gamma skip + 平面
     格式三态 + 缓存键折叠）。`LayerCompositeDriver.swift`：terminalTail 参数透传。
  2. 新建 `Tests/LightamerTests/DrtTailTests.swift`（LAYERS）：**零行为差门**（.sdrGamma
     时既有 fixture 栈输出逐字节不变）+ EDR 路径等价（.edrLinear 与改造前 edrDisplayLeg
     true 语义一致——EDR 既有测试全绿佐证）+ drt 尾段 SDR 8bit 平面格式断言 + HDR 16F
     断言 + linear float32 断言 + gamma/colorout skip（drt 激活时二位不进 pieces 求值）+
     键稳定（同 record 二次运行 HIT）+ EOTF 切换失效面（record 换 eotf → 尾平面 MISS 而
     colorout 前全 HIT）+ PREVIEW/FULL 双路径烟测 + method switch 穷举断言（aces20 stub
     触发、opendrt 正常——无 default 臂机检）。
  3. `git grep -n "edrDisplayLeg"` 审计：残留仅允许派生属性定义/头注（调用点穷举 AC）。
  4. 测试登记两处。
- **验收标准**
  - [ ] 上述断言全绿；`PixelPipe.swift` diff 逐 hunk 核（半径红线）；`PipeCacheKey.swift`
        零 diff；edrDisplayLeg 残留审计过。
  - [ ] 全套回归 `0 fail`。

### T8 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前向 orchestrator 报备；计数/秒数/bundle 峰值入
     SUMMARY）。
  2. 落盘 `M2-6-1-SUMMARY.md`（测试数变化/容差实配值与报警行/kernel PSO 编译耗时观察/
     EOTF 常数终式引用）+ `M2-6-1-DECISIONS.md`（执行期精读悬决点终式签注：rawValue 终式/
     BT.1886 黑位与 HLG OOTF 简化式/tonescale 枚举勘误/容差谱终版与分级依据/数值抽检结论）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-6-1 完成 + 下一步 = M2-6-2）；LESSONS 如踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 7）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | DrtRecord schema：四枚举计数 2/7/6/7；53 参数 + 12 顶层字段 JSON key 集合与 hpp 逐字段一致；默认值逐字段=hpp；Codable canonical 字节稳定；stableHash 稳定/敏感 | DrtRecordTests |
| 2 | 联动表：六空间 legalEOTFs 逐空间=字面表（rec709→bt1886,gamma22 / p3d65→gamma22,st2084 / p3d60,p3dci,xyz→gamma26 / rec2020→st2084,hlg）；isHdrEncoding={st2084,hlg} 精确 | DrtRecordTests |
| 3 | EOTF 七函数：规范锚点 ≤1e-4；往返 ≤1e-6；GPU vs Float64 absolute ≤1e-5 p99.9 + max ≤5e-5 报警行；gamma 族 peak 无效；-0/+0 视相等、NaN/Inf 恒 fail | DrtEotfTests |
| 4 | OpenDRT 参考：阶段 primitive 对 dctl 锚点 ≤1e-6；tonescale 单调；端点有界无 NaN；结构图头注阶段序与 dctl transform 对应（SUMMARY 行号清单） | DrtKernelGoldenTests + SUMMARY |
| 5 | OpenDRT kernel golden：探针三件套 × 参数四点 ≤1e-5 p99.9（或 DECISIONS 签注分级终谱）；位精确确定性（同输入两次逐字节相等）；PREVIEW/FULL 双路径同容差 | DrtKernelGoldenTests |
| 6 | 预设三件套：七 look 快照完备 + applyPreset 原子（逐字段相等）+ isCustomLook 派生语义 + tonescale 真值清单 + creative white 七项；NOTICE 署名在册；抽检结论入 DECISIONS | DrtPresetsTests + `git grep` NOTICE |
| 7 | sidecar v6：schemaVersionCurrent==6；round-trip 一致；**v5 档编码字节零漂移**；v5 档读 nil；schema 99 容忍；diff 仅 additive | DrtSidecarTests + `git diff` 逐 hunk |
| 8 | drtTail：.sdrGamma 零行为差（fixture 栈逐字节不变）；.edrLinear 等价（EDR 既有测试零改动全绿）；SDR 8bit/HDR 16F/linear float32 三态格式；colorout+gamma skip；键稳定 + EOTF 切换尾平面 MISS 而 colorout 前全 HIT；PREVIEW/FULL 烟测 | DrtTailTests + 既有 EDR 测试 |
| 9 | method 注册口形状：DrtMethod switch 穷举无 default（编译+CaseIterable 机检）；aces20 = 显式 stub（测试锁定，P2 替换面）；filmic/sigmoid/agx 零注册（`git grep` Registry 无新增） | DrtTailTests + grep |
| 10 | `PipeCacheKey.swift`/`PipelineDocument.swift`/`LayerStack.swift`/`HistoryStack.swift`/`NodeOwnershipCatalog.swift`/`Registry.swift`/`V50Order.swift` 零 diff；`edrDisplayLeg` 调用点穷举清零（残留仅派生属性/头注） | `git diff --name-only` + `git grep` |
| 11 | 全套回归 0 fail，计数 ≈ 2327 + 50..65 | test-direct.sh --all TOTAL 行双读 |
| 12 | diff 边界 == 申报文件集；测试登记闭环（六文件 × Project.swift + BUNDLE-MAP 双命中） | `git diff --stat` + `git grep` |

## 风险与边界

- **dctl 转录保真度（无 golden 锚的交叉验证法）**：OpenDRT 无上游可自动化参考渲染图（GPL +
  外部渲染环境）——三重缓解：①预设数值表对照 Alcedo expected bins（KD-7 抽检）；②阶段
  primitive 对 dctl 内嵌 desmos/规范锚点数值抽检（T3）；③测试注释列 dctl 行号可人工复核。
  残余风险 = 阶段拼接顺序/条件分支转录错——走读时逐段编号复核 + SUMMARY 阶段对照清单兜底。
- **Float64 参考 vs GPU 浮点容差谱**：~22 阶段级联在 float32 的系统性漂移可能超 1e-5——
  KD-8 升级评估点流程（值域分级 + 逐断言签注），禁静默放宽；若级联放大至 1e-3 量级 =
  实现结构性错误信号（回查阶段序），非容差问题。
- **PSO 编译时间（53 参数单 PSO）**：OpenDRT kernel 体量大（22 阶段内联）——首编译耗时
  观察行入 SUMMARY；参数 buffer 化保证**拖动零重编译**（OQ-10-A），首编译一次性成本可接受；
  若 >2s 记 E3 观察（预热面 = PSO 缓存常驻，既有 prewarm 机制后续 plan 评估，本 plan 不做）。
- **PREVIEW 与 FULL 双路径**：同一 kernel 同 PSO，分桶只影响平面尺寸——golden 双路径同
  容差断言兜底；PREVIEW 2560 帽语义零改（OQ-10-C 禁降参预览）。
- **EOTF 切换的失效面**：无 LUT 缓存（直算 per-pixel）——切换代价 = 尾平面重算一次
  （colorout 前全 HIT，KD-6 键折叠设计）；测试钉死该失效局部性（AC#8），防未来实现引入
  全链失效回归。
- **edrDisplayLeg 收敛的隐性消费点**：调用点穷举（AC#10 grep 审计）防漏改——App 传点在
  PipeCoordinator（EDR 开关语义 P3 才动，本 plan 仅参数形态替换、传值语义等价）。
- **基线上移**：2327 为起算基线；本 plan 预计 +50..65（六测试文件），后续 plan 以
  BUNDLE-MAP 行对账。

## 提交约定

- T1 `feat(core): drt record schema with eotf linkage`
- T2 `feat(core): eotf encode kernels for display transform`
- T3 `feat(core): opendrt float64 reference implementation`
- T4 `feat(core): opendrt metal kernel with golden probes`
- T5 `feat(core): opendrt preset snapshots with provenance notice`
- T6 `feat(sidecar): schema v6 display transform record`
- T7 `feat(pipe): drt tail segment with terminal tail policy`
- T8 `docs(m2-6): close out plan 1 opendrt core`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

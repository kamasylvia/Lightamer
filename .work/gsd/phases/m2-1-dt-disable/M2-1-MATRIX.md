# M2-1 启用/禁用矩阵（39 dt 派生 iop 逐模块 verdict）

> **事实基础**：`research/ALCEDO-FEATURE-MAP.md` §9（dt 独有对照）/ §10（映射建议）+ 代码实测
> （`LightamerIOP/Sources/Registry.swift` populate 注册表 / `App/Sources/Lightamer/State/InspectorState.swift`
> registerDefaultProviders / `App/Sources/Lightamer/MCP/Tools/IopCatalog.swift` ops 表）。
> **裁决依据**：ROADMAP M2 节 D1/D2/D5/D6（2026-09-27 用户签核全按推荐）。
> **计数校验**：`LightamerIOPRegistry.populate` 实注册 40 模块 = 38 dt 派生 + 2 Lightamer-native
> （skinsmooth/textoverlay）；39 = 38 IOP dt 派生 + `gamma`（Core 终端三件套之一，永不禁用）。
> **结论**：**禁用 6 / 启用 33 / 其中灰区保留 14**（全部灰区按 D6 保留启用，无一改判禁用）。
> 本矩阵是 plan 的 deliverable 正本；代码侧机器可读孪生 =
> `LightamerIOPRegistry.defaultFaceDisabledOpNames`（T1 落地，必须与本表禁用集逐字相等——测试钉）。

## 禁用集（6，opName 实测）

| # | 模块 | opName | verdict | 依据 | 理由 |
|---|---|---|---|---|---|
| 1 | FilmicRGB | `filmicrgb` | **禁用** | D1 | tone mapping 职能整体移终端 DRT（ACES 2.0/OpenDRT，M2-6）；parity 后评估以「DRT method 扩展」身份回归（本 plan 仅留注记不实现） |
| 2 | Sigmoid | `sigmoid` | **禁用** | D1 | 同上（D1 三件套） |
| 3 | AgX | `agx` | **禁用** | D1 | 同上（D1 三件套） |
| 4 | DenoiseProfile | `denoiseprofile` | **禁用** | D2 | Alcedo 零降噪（§9 封闭目录 18 项无 NR）；降噪由 RAW 9 解码层承担（CIRAW NR 参数族属 M2-3/M2-5 的 RAW Decode 页签，本 plan 不做 UI） |
| 5 | NLMeans | `nlmeans` | **禁用** | D2 | 同上（D2 三件套） |
| 6 | Bilateral | `bilateral` | **禁用** | D2 | 同上（D2 三件套；surface blur 降噪腿。ROADMAP D2 句尾「bilateral/highpass 收进 Detail 分组」指 UI 收纳意向，与「v1 禁用」主句冲突时以签核主句 + 本任务书为准 = 禁用；若 M2-3 Detail 分组需要局部平滑增强，届时以新模块身份重评，不回切本矩阵） |

## 启用集——Alcedo 有直接对应物（12 + trio，无争议）

| # | 模块 | opName | verdict | 依据 | Alcedo 对应物（§10） |
|---|---|---|---|---|---|
| 7 | Exposure | `exposure` | 启用 | §10 | Exposure（`exposure_ev` ±16） |
| 8 | Temperature | `temperature` | 启用 | §10 | CAT02 White Balance / Develop 相机 WB（Grade 级语义属 M2-5） |
| 9 | ToneCurve | `tonecurve` | 启用 | §10 | Curve（单位方形点列） |
| 10 | Crop | `crop` | 启用 | §10 | Geometry crop（xywh/rotation/aspect） |
| 11 | Lens | `lens` | 启用 | §10 | RAW Decode Lens Calibration（Lensfun 启用+scale，部分对应） |
| 12 | Sharpen | `sharpen` | 启用 | §10 | Sharpen（amount/radius/threshold；DRT/Post 所有权模型属 M2-5/M2-6 再收纳） |
| 13 | Vibrance | `vibrance` | 启用 | §10 | Vibrance（±100） |
| 14 | Grain | `grain` | 启用 | §10 | Film Grain（反向独有：Alcedo IPOL 物理模型，Post 拥有属 M2-6） |
| 15 | Bloom | `bloom` | 启用 | §10 | Halation（Post 拥有属 M2-6） |
| 16 | Lut3d | `lut3d` | 启用 | §10 | LMT（CUBE path，Grade 内）+ LUT 面板（M2-3） |
| 17-19 | ColorIn / ColorOut / Gamma（Core 终端三件套） | `colorin`/`colorout`/`gamma` | 启用 | 管线基础设施 | 色彩管线终点，永不禁用（gamma 计入 39 的第 39 席） |

## 启用集——灰区保留（14，Alcedo 近似对应或无对应，按 D6 保留启用）

| # | 模块 | opName | verdict | 依据 | 保留理由 |
|---|---|---|---|---|---|
| 20 | Shadhi | `shadhi` | 启用 | D6 / §9-§10 | Alcedo「局部色调映射」（shadows/highlights 五标量）为其近似对应；语义精化（中灰邻域保色相）属 M2-5 |
| 21 | ToneEqual | `toneequal` | 启用 | D6 / §9 | Alcedo 无 local Laplacian 对应，但「无对应 ≠ 与 Alcedo IA 冲突」；已交付重资产（Phase 3 最重模块），M2-3 收进 Tone/Detail 分组 |
| 22 | Colisa | `colisa` | 启用 | D6 / §10 | Alcedo White/Black/Contrast/Highlights/Shadows 五标量为其子集；保留超集能力 |
| 23 | Levels | `levels` | 启用 | D6 / §10 | 同上（black/white 点语义被 White/Black 标量覆盖大半） |
| 24 | LocalContrast | `bilat` | 启用 | D6 / §10 | Alcedo Clarity（±100 标量）是最近对应；本实现更精细（EIGF），UI 呈现按 Alcedo 单滑块收敛属 M2-3 |
| 25 | Equalizer | `equalizer` | 启用 | D6 / §9 | Alcedo 无（Clarity 最近）；D6 独有增强收 Detail 分组 |
| 26 | Highpass | `highpass` | 启用 | D6 / §9-ROADMAP | Alcedo 无；ROADMAP D2 明示「highpass 收进 Detail 分组作 Lightamer 增强」 |
| 27 | ColorBalanceRGB | `colorbalancergb` | 启用 | D6 / §10 | Alcedo LGG 三轮是其近似对应（§10 列为高优移植项方向）；在 LGG 落地（M2-5）前保留作调色能力，不破坏 IA（M2-3 收纳） |
| 28 | ColorZones | `colorzones` | 启用 | D6 / §10 | Alcedo HLS 8-bin 为其简化 UI 面（§10：可作 colorzones 的简化呈现）；保留内核 |
| 29 | ChannelMixerRGB | `channelmixerrgb` | 启用 | D6 / §9 | Lightamer 独有（Alcedo 无按通道混合）；收「高级」分组（M2-3） |
| 30 | ChannelMixer | `channelmixer` | 启用 | D6 / §9 | 同上；dt 已 DEPRECATED 但属已交付资产，D6 全保留口径不改判 |
| 31 | ColorContrast | `colorcontrast` | 启用 | D6 / §10 | Alcedo Vibrance 近似（Lab a/b 域）；保留 |
| 32 | Velvia | `velvia` | 启用 | D6 / §9 | Lightamer 独有（§9 明示「无按饱和度加权的 velvia」） |
| 33 | Monochrome | `monochrome` | 启用 | D6 / §9 | Lightamer 独有（§9「无专用」，saturation→0 只是凑） |

## 启用集——D6 明确独有项（7 + native 2）

| # | 模块 | opName | verdict | 依据 | 说明 |
|---|---|---|---|---|---|
| 34 | Flip | `flip` | 启用 | D6 / §10 | Alcedo crop/rotation 覆盖部分；保留独立 orientation |
| 35 | Ashift | `ashift` | 启用 | D6 / §9 | Alcedo 无自动透视（有 crop+rotation+aspect） |
| 36 | Soften | `soften` | 启用 | D6 | creative（Orton），Alcedo 无 |
| 37 | Liquify | `liquify` | 启用 | D6 / §9 | Alcedo 无任何变形工具 |
| 38 | Vignette | `vignette` | 启用 | D6 | creative，Alcedo 无 |
| 39 | Dehaze | `hazeremoval` | 启用 | D6 / §9 | Alcedo 无 |
| 40 | Borders | `borders` | 启用 | D6 / §9 | yiyin 印框一等公民（§9：Alcedo 导出无水印/边框） |
| 41 | Watermark | `watermark` | 启用 | D6 / §9 | yiyin 水印一等公民 |
| 42 | SkinSmooth | `skinsmooth` | 启用 | D6 | Lightamer-native（非 dt 派生，不入 39 计数） |
| 43 | TextOverlay | `textoverlay` | 启用 | D6 | Lightamer-native（非 dt 派生，不入 39 计数） |

## 附注

- **testgain**：DEBUG-only dev 模块（Release 编译排除），非产品面，不受本矩阵影响。
- **RAW Decode 页签路径**：D2 禁用后降噪归 CIRAW 解码层（`kCIInputNoiseReductionAmount` 族）；
  其 UI 暴露 = M2-3 七页签的 RAW Decode 页签（M2DIS-04），**本 plan 只保证禁用不堵死该路径**
  （禁用集与 decode 管线零耦合——CIRAW 参数走 `RAWDecoder` 不经 iop registry）。
- **预置 LUT 库**：LUT 库服务 `lut3d`（启用模块），与禁用集零交集。
- **内置预设**：仓内无任何 `.lightamer-preset` 资产（实测 `find` 零命中）——「Phase 12 内置预设
  含 filmic 参数」风险**不存在**；用户自建预设含禁用 op 的处置见 plan §round-trip（degrade 保数据）。

# Phase M2-5: Color Grade 控件集 — Context

> discuss/research 起草稿（2026-09-29）。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` **§2.1 调整目录 18 项全表**（含 JSON key/默认值/范围）+ **§2.2 LGG 色轮**（`color_wheel_model.hpp:34-50`）+ **§2.3 Look 面板分组**（Master/Look/Color/Detail）；需求 = REQUIREMENTS **M2GRADE-01..07**；ROADMAP M2-5 行（含 D4 ACEScc 裁决 + LUT 目录语义 05/06/07）。衔接面 = M2-4 交付的节点模型（`PipelineDocument` 投影 / 7 命令集 / `NodeOwnershipCatalog` 宽限表 / sidecar v5 / `InspectorEditSession` 层作用域）+ M2-3-3 七页签 routing table + 12-5 LUT 资产（`LutLibraryStore`/`Lut3dModule`/`LutPanelView`）。**本 CONTEXT 面向夜间授权裁决**（文末「夜间授权预案」：按推荐自主生效、晨审可推翻）。

## Phase Boundary

**范围**（ROADMAP M2-5 行 + M2GRADE-01..07）：

1. **18 项封闭目录参数对齐**（M2GRADE-01）——逐项参数面/默认值/范围对齐 Feature-map §2.1；`NodeOwnershipCatalog` 宽限表 → 18 目录严格面激活（M2-4 终态注记钦定本 phase）。
2. **LGG 三向色轮新件**（M2GRADE-02）——新 iop（kernel + 三 trackball UI + Reset wheels），params 逐字段对齐 `color_wheel_model.hpp`。
3. **产品默认 look**（M2GRADE-03）——+1.5 EV / contrast +15 / saturation 1.3，仅新导入；用户新建 grade 与 reset 恒 identity。
4. **ACEScc 调色域**（M2GRADE-04，D4 已签核）——Grade 内部 AP1/ACEScc 色适应往返；CAT02 创意白平衡（默认 5999.9934K = identity）；相机 WB 留 RAW Decode/CIRAW 层。
5. **LUT 目录三件套**（M2GRADE-05/06/07）——递归扫描 + 子目录树分组；根目录可配 + 切根重建索引；内置 Alcedo 同款胶片集（许可门第一任务，上游 `JanLohse/spectral_film_lut` 原生获取，禁拷 GPL 仓数据）。
6. **Look/Tone 页面板分组**（§2.3 IA）——Look 四组重组 + 18 目录 add 面与逐项面板。

**非目标（本 phase 明确不做）**：

- **DRT 功能体**（M2-6）——Clarity/Sharpen/Halation/FilmGrain 的「DRT 后全图一次」本体归 M2DRT-05；本 phase 只锁所有权严面 + Look 页占位呈现。
- **蒙版编辑 UI**（M2-7）——零涉及（M2-4 已交付 Grade-owned 数据/绑定面）。
- **tone mapping 归位**（M2-6）——filmicrgb/sigmoid/agx 维持 M2-1 禁用面。
- **LGG 蒙版级联动**——蒙版体系语义 M2-7 裁；本 phase Grade 内 LGG 全图语义。
- **OpenDRT/ACES 2.0 任何参数**（M2-6 面）。

## Existing Code Insights

### 关键语义发现（本 phase 方向裁决的地基，2026-09-29 Grep 实测）

1. **层子 run 边界 = ACEScc 往返的天然插入点**——`LayerCompositeDriver.swift:73-77` 明文三段：A. base sub-run（base 链减终端件）→ S；B. **layer sub-run（input = C_prev）→ L_k**；C. terminal 段（colorout 70.0/gamma 78.0）。**colorin 28.0 恒 base**（:208）。Grade = compositeLayers 的每个子 run，故「Grade 节点内部 AP1/ACEScc 色适应往返」（D4 字面）= 每层子 run 入口一对转换 kernel，中间 18 目录 grading 全在 ACEScc 域，子 run 出口回 linear Rec2020——**合成 blend 仍发生在 Rec2020**（C_k = blend 公式零改动），与 Alcedo「grade 输出 scene-linear、ACEScc 仅调色工作域」语义一致。
2. **`NodeOwnershipCatalog` 宽限表已是 18 目录对照表的骨架**（`NodeOwnershipCatalog.swift:41-84`）——`.drtPost` 四件已裁 **Sharpen→Sharpen / Grain→FilmGrain / Bloom→Halation / Equalizer→Clarity**（M2-4-1 DECISIONS 签核）；`.develop` 收 Temperature（相机 WB = RAW Decode 域，M2GRADE-04 字面）/geometry 五件/yiyin 三件/禁用六件；**default 臂 = .grade**。M2GRADE-01 严格面激活 = 在此表上加目录 id 维度收窄 default 臂，**校验 seam 零改动**（该文件自述「M2-5 narrows the 18 catalogs from this one function without touching the validation seam」）。
3. **`LutLibraryStore` 是单层平面模型，递归化 = registry 键升级**——`Lut3d/LutLibraryStore.swift:105` `contentsOfDirectory` 单层枚举；registry 键 = **文件名**（`InstalledLut.name`，`lut3d` params 存库名引用，12-5 D-6「path dropped at import」惯例）；缺引用 degrade = blit identity + toast 已存在（`isMissing`/D-10 posture）。递归扫描 + 同名冲突 + 可配根目录三件事都压在「键 = 文件名」这一假设上——M2GRADE-05/06 的改造面 = 键升**根相对路径**（旧行 = 根下文件，相对路径退化为文件名，registry.json decode 宽容兼容）+ `InstalledLut` additive 字段（`relativePath`/`subdirectory`）。
4. **既有调色模块参数面与 18 目录是「超集-子集」关系，不是一一对应**——实测：`exposure.Params` = mode/black/exposure/deflicker×2/compensate×2（dt 全量，远超 Alcedo 单 `exposure_ev`）；`shadhi.Params` = radius/shadows/whitepoint/highlights/compress/shadowsCCorrect/highlightsCCorrect/lowApproximation/unbound/algo（Alcedo Shadows/Highlights = ±100 双标量）；`tonecurve.Params` = **Lab 域 L/A/B 三曲线**（curveL/curveA/curveB + CurveType/autoscaleAb/RGBNorm），而 Alcedo Curve = 单位方形点列单曲线；`colorzones.Params` = channel + 三平滑曲线（curveL/C/H），而 Alcedo HLS = **8-bin 离散表**（`hls_adj_table[H,L,S][8]` + h/l/s_range + target_hls）——**结构不同构，非换皮可覆盖**；`colisa.Params` = contrast/brightness/saturation（display-referred RGB 缩放语义，≠ Alcedo 0.3.0「中灰邻域 lightness 保色相」）；`temperature.Params` = red/green/blue gains + preset（**非 K/tint 模型**，CAT02 WB 必须新件）；`vibrance.Params` = 单 amount ±100（可直接对齐）。
5. **V50Order add-only 纪律给新件留足空位**——`V50Order.swift` verbatim 表 94 行，未占用 slot 充裕：40.5（colorharmonizer）/ 41.0（colorbalance）/ 41.2（colorequal）/ 51.0（zonesystem）/ 53.0（relight）/ 55.0（colorcorrection）/ 67.0（splittoning）等；Lightamer 原生行先例 = skinSmooth 66.5 / textOverlay 66.7（「no reorder / unique / add-only」纪律正文在文件头）。新 Grade 件（LGG/CAT02/HLS/contrast 新语义/White/Black/Tint/Saturation）落 RGB 段空位（28.5–69.x），**新位置不重排既有行**。
6. **默认 look 的 mint 注入点已存在**——`EditorState.swift:98-104` pristine seed = terminal trio 缺省参数；`:123` sidecar restore 替换 pristine。`.lra` 缺席 = 未编辑（不变量，M2DIS-04 pristine-decode 腿依赖）；`.lalb` `images` 表已有 `added_time`（`LibrarySchema.swift:141`）+ additive 升版先例（v5 additive 惯例 + schema 版本化）。「仅新导入」可用 **per-image 标记列**在 mint 时分支，零 pristine 语义污染。
7. **七页签 routing table 是代码正本，M2-5 可改**——`EditorTabRoute.swift:112-183`：Tone 页现挂 8 行（exposure/temperature/tonecurve/levels/colisa/shadhi/colorcontrast/toneequal）、Look 页 13 行平铺（vibrance/velvia/monochrome/colorbalancergb/colorzones/skinsmooth + detail 五件 + grain/bloom「parked until M2-6」）、LUT 页挂 lut3d。18 目录激活 + §2.3 分组 = **重写这两页的 rows + 分组壳**，TAB-MATRIX 对账测试随批更新（M2-3-3 既有对账机检）。
8. **面板分派 = `InspectorState.panelView(for:edit:)` provider 注册表**（`InspectorState.swift:155`）——每目录一个 provider，`InspectorEditSession` 层作用域 M2-4 OQ-9-A 已交付（选中 Grade → 面板读写该层 chain）。新件面板 = 新 provider 注册；trackball UI 为唯一全新控件形态，其余（滑杆/曲线/分段卡）复用既有组件。

### Reusable Assets

| 资产 | 位置 | M2-5 复用判定 |
|---|---|---|
| `NodeOwnershipCatalog`（.drtPost/.develop/默认 .grade 三臂 + opName 常量零字面量纪律） | `LightamerIOP/Sources/NodeOwnershipCatalog.swift` | **18 目录严格面激活的唯一位点**——加目录 id 维度，default 臂收窄为显式 13 Grade 目录 |
| `LayerCompositeDriver` 三段子 run 结构（base/layer/terminal + colorin 恒 base） | `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:73-77,205-226` | **ACEScc 往返插入点**——层子 run 头尾转换对；blend 公式与缓存键零改动 |
| `V50Order`（verbatim + add-only + Lightamer 原生行先例） | `LightamerCore/Sources/Foundation/V50Order.swift` | 新件落位唯一合法来源（空位清单见发现 5） |
| `LutLibraryStore`（registry.json 自愈三段式 + 内容去重 + blit-identity degrade + `LutResolving` face） | `LightamerIOP/Sources/Lut3d/LutLibraryStore.swift` | 05/06 的改造基底——递归枚举 + 键升级 + 可配根目录；自愈/degrade 语义原样保留 |
| `CubeLutParser`/`Lut3dModule`/`LutPanelView`（1D/3D + tetrahedral + 色彩空间选择 + missing toast） | `LightamerIOP/Sources/Lut3d/` + `App/Sources/Lightamer/UI/Inspector/LutPanelView.swift` | LMT 目录项现成编辑面——树分组改造挂其库 Picker |
| `ToneCurveLUT`/`CurveTools`（曲线求值 + 交互编辑器） | `LightamerIOP/Sources/ToneCurve/` | Alcedo Curve 单位方形交互复用（编辑器壳），域映射见 OQ-6 |
| `IOPPanelProvider` 注册表 + `InspectorEditSession` 层作用域 | `App/Sources/Lightamer/State/InspectorState.swift:155` + M2-4 交付 | 每目录一 provider 的新面板挂接缝（零新机制） |
| `EditorTabRoutingTable`（单一正本 + TAB-MATRIX 对账机检） | `App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift` | Tone/Look 页重组的代码落点 |
| `EditorState` pristine seed / sidecar restore 双腿 + `HistoryStack` layerScope | `App/Sources/Lightamer/State/EditorState.swift:98-123` | 默认 look mint 注入点（OQ-8）+ 18 目录 add 命令的 history 载体 |
| `LibrarySchema` additive 升版惯例（v2→v1 表 + DECIMAL TEXT L013） | `LightamerCore/Sources/Library/LibrarySchema.swift:138-141` | 默认 look 标记列的 additive 缝（OQ-8） |

### Integration Points

- **App/Core 边界**：新 iop 件落 `LightamerIOP/Sources/<Module>/`（.swift + .metal 对惯例）；`NodeOwnershipCatalog` 目录 id 表同文件扩展；面板/trackball/树 UI 落 App（`UI/Inspector/` + routing table）。
- **层作用域**：18 目录面板经 `InspectorEditSession` 读写**选中 Grade** 的 chain（M2-4 OQ-9-A 已交付，本 phase 零会话层改动）；未选中/Develop = base 链现行为。
- **严格面激活半径**：`addModuleToLayer` typed 校验从宽限转严格（.drtPost 入 Grade 拒绝）+ **新 add 面按目录枚举**；已存 sidecar 加载宽容不变（degrade 不拒载，读者容忍惯例）。

## Open Questions（每条含推荐；夜间授权按推荐生效）

### OQ-1 18 项目录落地策略：逐项对齐表（必裁——决定整 phase 形状）
- **A（推荐）**：**「目录缺失件新造 + 既有件参数面对齐」混合策略**，逐项裁决表（owner 依 `NodeOwnershipCatalog`，全部落盘为目录注册表）：

| Alcedo 目录项 | 落地 | 依据 |
|---|---|---|
| CAT02 White Balance | **新 iop**（K/tint → xy → CAT02 矩阵，ACEScc 域施加；默认 5999.9934K/9.7112783，2000–15000K/±150） | temperature 是 RGB gains 模型，不同构（发现 4）；语义见 OQ-5 |
| Exposure | **对齐 exposure 模块**——面板单滑杆暴露 `exposure`（UI −10…+10 step 0.01，Alcedo EditorTonePanel 范围；模型 ±16 上限参数面保留为超集）；black/deflicker/compensate 折叠为高级组 | dt 全量参数超集保留（D6 收纳惯例），默认值 0 EV 一致 |
| Contrast | **新 iop**——中灰邻域 lightness 保色相语义（0.3.0 新语义，默认 +15 新图；±100） | colisa contrast = RGB 缩放损色相，语义不同构（发现 4）；colisa 保留独有高级件 |
| White / Black | **新 iop**×2（或一个 kernel 两 op）——±100 标量，scene-referred 端点标定语义 | 无既有对应（levels 是 Lab 域三滑杆，不同构）；Alcedo 目录 = 每项独立 instance |
| Shadows / Highlights | **对齐 shadhi**——±100 双标量面板暴露（shadows/highlights 字段已存在），radius/compress/CCorrect/lowApprox/algo 折叠高级组 | shadhi 即「局部色调映射」族（README:77 同类）；参数面零改动 sidecar 兼容 |
| Curve | **对齐 tonecurve**——单位方形点列交互（CurveTools 复用）映射到 curveL（master）；**域语义 plan 期定**：起草倾向 = ACEScc luma 域单曲线（tonecurve kernel 的 L 腿在 ACEScc 域求值），A/B 腿面板不露 | 发现 4：tonecurve 是 Lab 域，直接暴露 = 语义漂移；master 曲线承载是 Alcedo UI 面（单曲线编辑器）的最小忠实映射 |
| HLS | **新 iop**（8-bin 表 + range 权重窗）——见 OQ-6 | colorzones 三平滑曲线不同构 |
| Saturation | **新 iop**——0–4 乘法饱和（ACEScc 域），默认 1.0 | colisa saturation 范围/域不同；Alcedo 独立目录项 |
| Vibrance | **对齐 VibranceModule**——amount ±100 即 `vibrance` | 字段一一对应 |
| Color Wheel (LGG) | **新 iop**——见 OQ-2 | 完全缺失（M2-4 盘点已钉） |
| LMT | **对齐 lut3d**——`cube_path` ↔ 既有库名引用；LUT 面板即编辑面 | 12-5 资产在位 |
| Tint | **新 iop**——±100 独立标量（与 CAT02 WB 内嵌 tint 分立，照抄目录） | 无既有对应 |
| Clarity/Sharpen/Halation/FilmGrain | **归属已裁**（`.drtPost` 四件映射在案）；本 phase 只锁「不入 Grade」+ Look 页占位 | `NodeOwnershipCatalog.swift:44-49` M2-4-1 DECISIONS |

- B：全量语义等价映射既有 33 op（不造新件）——LGG/CAT02/HLS/Contrast 新语义四处无宿主，映射伪造语义 = 与 Alcedo 默认值/观感漂移，违「参数对齐」需求字面。
- C：全部新造 18 件（不动既有）——exposure/shadhi/vibrance/tonecurve/lut3d 五处现成可对齐，重造 = 丢弃 golden 测试资产 + sidecar 不兼容风险。
**推荐 A**；目录注册表（目录 id ↔ op ↔ owner ↔ 参数面暴露清单）落 `NodeOwnershipCatalog.swift` 同批。

### OQ-2 LGG 三向色轮新件实现要点（M2GRADE-02）
- **A（推荐）**：**新 iop `colorwheels`，params 逐字段照抄 `color_wheel_model.hpp:34-50`**——三 wheel（lift/gamma/gain）各 `{disc: SIMD2<Float>, strength: Float, colorOffset: SIMD3<Float>, luminanceOffset: Float}`；lift identity = 全零、gamma/gain identity = 色偏 (1,1,1)；kernel 在 ACEScc 域：lift = 加法偏移、gamma = 幂/乘法、gain = 乘法（disc 极角→色度方向、半径→幅度，strength 缩放；luminanceOffset 加亮度）；数学精貌（gamma 幂基 vs log 域加法）以 Alcedo `color_wheel` kernel 语义为唯一对照源，plan 期核读后钉 golden 容差。v50 位 = 41.0（colorbalance 空位，RGB 段）。UI = SwiftUI 三 trackball（Canvas 自绘圆盘 + DragGesture 写 disc + 数值滑杆 strength/luma），Reset wheels 按钮三轮归 identity；不做 Metal 自绘（节点数个位数，Canvas 帧成本可忽略——M2-4 OQ-5 同款论证）。
- B：复用 colorbalancergb 内核改三轮 UI——其 4×4 参数面（shadows/mid/high/global × YCH + weights/fulcrum）与 CDL 三轮模型不同构，硬套 = 双语义污染；colorbalancergb 保留 D6 独有件（routing 现位不动）。
- C：Metal 自绘 trackball——过度工程（同 OQ-10 论证）。
**推荐 A**；identity 语义（lift 零 / gamma+gain (1,1,1)）与 Reset 行为写入目录注册表。

### OQ-3 ACEScc 调色域插入点（M2GRADE-04 / D4）
- **A（推荐）**：**每层子 run 头尾一对域转换，18 目录 grading 全在 ACEScc 域**——落点 = `LayerCompositeDriver` layer sub-run 入口（linear Rec2020 → AP1 色适应 → ACEScc log）+ 出口（逆变换回 linear Rec2020）；实现形态 = 两个无面板内部 op（v50 空位各一枚，如 40.5/41.2）由 driver 在子 run 装配时自动包夹，**不出现在 add 面与 sidecar 之外的用户可见面**（作为子 run 装配产物随层记录持久化，hash 键天然生效）；blend 合成仍在 Rec2020（发现 1）。CAT02 WB/curve/HLS/LGG/saturation 等 ACEScc 域件的 kernel 直接消费 log 域值，不再各自转换。
- B：每目录件 kernel 各自做域往返——N 层 × M 件冗余转换，且单件开关（enabled=false）时域不一致风险（半途层内混域）。
- C：整条 Grade 链包一次往返（跨层 ACEScc）——层间 blend 被迫在 log 域做（log 域 lerp 非线性失真），且 base 层（Develop 投影）也被裹入，超 D4 字面（「Grade 节点内部」）。
**推荐 A**；性能观察项见 OQ-11；转换 kernel 用 `sRGB→ACEScc` 标准矩阵 + `linear Rec2020→AP1` 色适应（plan 期以常数矩阵 golden 钉死）。

### OQ-4 Develop（base 层）全局链收窄语义（M2-4 Deferred 遗留裁决）
- **A（推荐）**：**宽容现状 + 新增面收窄**——base 层既有 grade-owned op 实例（历史文档里的 exposure/colisa/…）保留可编辑可渲染（加载宽容，永不拒载）；**新 add 面不再向 base 链提供 grade-owned 目录项**（add 菜单在 Develop 作用域只枚举 `.develop` 件：geometry/yiyin 族 + 兼容项折叠组）；base 链新图 pristine 面维持 terminal trio。Tone/Look 页在「未选中节点」态编辑 base 链既有实例（现行为），**选中 Grade 后编辑该层 chain**（M2-4 OQ-9-A 既有作用域）——同一面板双作用域即收窄语义的完整表达。
- B：加载时自动迁移（base 链 grade-owned 实例搬入新首 Grade）——加载即改写文档，破坏非破坏性承诺 + 不可逆（违 one-way 锁精神）。
- C：base 链严格拒绝 grade-owned op（拒载现存文档）——用户现存图全挂，不可接受。
**推荐 A**；「18 目录严格面」的半径 = **新增动作**（add/insert 校验严面），不含历史加载路径。

### OQ-5 CAT02 创意白平衡三层关系（CAT02 WB ↔ temperature 模块 ↔ CIRAW 相机 WB）
- **A（推荐）**：**三层各守其位 + Tone 页 temperature 行摘除**——①CIRAW 相机 WB = 解码层真相（RAW Decode 页 NR/WB 参数族既有，M2DIS-04 交付）；②CAT02 WB = 新 Grade 件（Look 页 Color 组，AP1 白点假设的创意色温，默认 ≈6000K = identity——数值照抄 `cat02_white_balance_model.hpp:18-23`：5999.9934K / tint 9.7112783）；③dt `temperature` 模块 = develop-owned 过渡宿主**保留可编辑但面板行从 Tone 页摘除**、归入 base 链兼容折叠组（Alcedo Tone 页无 WB 行，§2.1 Tone 目录无此项；IA 一致性）。语义红线：CAT02 WB 不回写解码 WB，二者叠加顺序 = 解码（ Develop 域）→ Grade（ACEScc 域）天然分层。
- B：Tone 页保留 temperature 行 + Look 页并挂 CAT02——双 WB 入口并存 = Alcedo IA 偏离 + 用户心智负担（Alcedo 页内提示明确「相机 WB 在 RAW Decode 页」）。
- C：temperature 模块默认面禁用——历史 sidecar 兼容面受损（M2-1 启用矩阵翻案），无收益。
**推荐 A**；routing table Tone 页 −1 行、Look/Color 组 +1 件，TAB-MATRIX 对账同批更新。

### OQ-6 HLS 8-bin：colorzones 改造 vs 新面板新件（M2GRADE-01 子项）
- **A（推荐）**：**新 iop `hls` + 新 Selective Color 面板**——params 照抄 `hls_model.hpp:16-39`：`adj[H][L][S]` 8-bin 表 + `target_hls` {0,0.5,1} + `h_range` 45° / `l_range`/`s_range` 0.1（平滑权重窗）；kernel = 每 bin 中心色相距离窗（45° raised-cosine 权重）加权施加 H/L/S 偏移。UI 呈现按 Alcedo §2.3：Target Hue 选择 + Hue Shift/Lightness/Chroma/Hue Smoothness 滑杆（**Alcedo 单 target UI ↔ 8-bin 模型的映射关系 plan 期核读 Alcedo QML 后钉**——起草倾向 = UI 编辑选中 bin，8 bins 经色环/步进遍历；色环控件复用 CurveTools 邻域组件）。colorzones 保留独有件（routing 现位，D6 收纳）。
- B：colorzones 加 8-bin mode——三平滑曲线内核上叠离散表 = 双模型同模块，golden 测试面翻倍且与 dt 参考语义冲突。
- C：不做 HLS（vibrance+colorzones 凑）——目录封闭面缺项，违 M2GRADE-01 字面。
**推荐 A**。

### OQ-7 LUT 三件套执行序 + 内置集获取与许可门（M2GRADE-05/06/07）
- **A（推荐）**：**执行序 05 → 06 → 07（同 phase 内三个 plan 任务序，07 许可门前置）**——
  - **05 递归扫描**：`LutLibraryStore.rescan()` 改 `enumerator(at:)` 递归 + registry 键升根相对路径（旧行 decode 宽容 = 根下文件，发现 3）；`InstalledLut` additive 增 `relativePath`；同名冲突消歧 = 相对路径天然唯一（display 名撞车加子目录前缀）；面板库 Picker 升子目录树分组/折叠（`LutPanelView`）；刷新语义 = rescan 打开面板触发 + 手动刷新按钮（FSEvents watcher = v2 不做）；缺引用 degrade = 既有 blit identity + toast 零改动。
  - **06 可配根目录**：UserDefaults 键 `lut.library.root`（`ImportDefaults` 同款宿主惯例；路径可达性重验沿 EXP-08 bookmark 先例，外置卷标注 L009 教训）；默认根不变（`~/Library/Application Support/Lightamer/LUTs/`）；**registry.json 跟根走**（每根一份自洽库，切根 = 整库重扫重建，引用缺名 degrade 兜底）；设置页选择器挂 Settings 新节（消费 `LutLibraryStore.shared` 重造）。
  - **07 内置集**：**第一任务 = 许可门**——`git clone https://github.com/JanLohse/spectral_film_lut`（最新 release tag）→ 读 LICENSE/COPYING/README 许可声明 → 与 Alcedo CMake glob 清单对照（`Agfa_*/Fuji_*/Kodak_*.cube` 44 张；**Hasselblad 两张 33³ 与「色彩逆向」子目录 = 用户自放，不入目标**）→ 宽松许可（MIT/CC0 类）才入包：app bundle Resources 首启动拷贝至默认根 `BuiltIn/` 子目录（与用户 LUT 天然分组隔离）+ LICENSE/NOTICE 随包署名；**许可非宽松 → 降级为设置页「一键导入指南」（用户自行下载导入），不入包并登记阻塞（需人工）**。禁从 AlcedoStudio GPL 仓拷任何数据文件（含其公开仓 config/LUTs——已查不存在）。
- B：05/06 合一任务 + 07 并行——许可门未过前内置集打包路径悬空，返工风险；递归扫描与可配根共享 registry 键升级，但 UI 面独立可分任务。
- C：内置集从 Alcedo 安装目录拷贝——GPL 仓数据禁令字面违反（REQUIREMENTS M2GRADE-07 明文），否决项。
**推荐 A**；07 的 clone tag/commit SHA 与许可结论落 plan 证据（`.work/gsd/phases/m2-5-color-grade/evidence/`）。

### OQ-8 产品默认 look 作用域与接线点（M2GRADE-03）
- **A（推荐）**：**per-image 标记列 + mint 时分支注入**——`.lalb` `images` 表 additive 列 `default_look_pending INTEGER DEFAULT 0`（LibrarySchema additive 升版，先例在案）；`ImportService` 入库行写 1；`EditorState` 载入分支：**无 `.lra` 且 flag=1 → pristine seed 之上铸首 Grade 塞默认 look 三参数（exposure +1.5 EV / contrast +15 / saturation 1.3）并清 flag**（内存态；首次编辑随 sidecar 落盘，未编辑则不留痕——「.lra 缺席 = 未编辑」不变量零破坏，M2DIS-04 pristine-decode 腿兼容）；用户新建 grade / reset 恒 identity（目录注册表 identity 语义）；旧导入行 flag=0 = 永不注入。
- B：导入时直接写初始 sidecar——破 pristine 不变量（has_edits/params_hash 投影全污染、未编辑图带「已编辑」假象），否决。
- C：`added_time` 时间截断启发式（晚于 feature 激活即注入）——时钟依赖 + 补导旧片误伤 + 无法 per-image 关闭，脆弱。
**推荐 A**；`library.import.*` 键族旁不新增开关（v1 无「默认 look 开关」需求，Alcedo 亦无；要关闭 = 编辑掉三参数，非破坏性）。

### OQ-9 明细四件（Clarity/Sharpen/Halation/FilmGrain）M2-6 前占位语义
- **A（推荐）**：**归属锁死 + Look/Texture 组占位 + 诚实文案**——四件映射沿用 `NodeOwnershipCatalog` 已裁表（发现 2）；所有权严格面激活（.drtPost 入 Grade = typed error，M2-4 宽限转严格，本 phase 交付）；Look 页 §2.3 分组下四件挂「Look/Detail」组（sharpen/highpass/soften/localcontrast/equalizer/grain/bloom 现有 provider 行重新归组），面板注记「applies pre-DRT for now — moves post-DRT with M2-6」（M2-3-3 「parked until M2-6」注记先例同款）；「DRT 后全图一次」本体 = M2DRT-05，本 phase 零涉及。Equalizer=Clarity 的 UI 简化暴露（单滑杆 ±100）= 面板层呈现决策，参数面不动。
- B：四件从 Look 页摘除等 M2-6——目录 IA 断层（Alcedo Look 组有此四件，§2.3 字面），且 grain/bloom 既有可用面回退无收益。
- C：本 phase 提前实现 post-DRT 全图一次——依赖 DRT 节点本体（M2-6），时序不可能。
**推荐 A**。

### OQ-10 Look/Tone 页面板分组与复用度（§2.3 IA 落地）
- **A（推荐）**：**Look 页重组 Alcedo 四组 + 目录 provider 化**——Look 页 = Master（Saturation/Vibrance）→ Look（四 DRT 件占位，OQ-9）→ Color（CAT02 WB / Selective Color=HLS / Color Wheels=LGG / Tint）→ Detail/Texture（既有 detail 族 + LMT 归 LUT 页不动）；组 = 折叠组壳（`DisclosureGroup`，Alcedo 折叠语义），组内行 = 既有 `IOPPanelProvider` 面（标量滑杆组件复用、曲线 CurveTools 复用、仅 trackball 新写）；Tone 页按 Alcedo Tone 目录收敛（Exposure/Contrast/White/Black/Shadows/Highlights/Curve，levels/colisa/colorcontrast/toneequal 移 compat 折叠组——D6 收纳惯例，不删除）；18 目录 add 面 = 选中 Grade 下「Add Adjustment」按目录枚举（owner 过滤），instance 落该层 chain（`addModuleToLayer` 既有缝 + history layerScope 既有）。
- B：维持平铺 provider 行（只加不减）——IA 违 §2.3，Look 页 13+ 行无分组在 18 目录后不可扫。
- C：每组独立页签——七页签契约（M2-3-3 EditorTabRoute）破坏，否决。
**推荐 A**；TAB-MATRIX 对账机检随批重写（发现 7）。

### OQ-11 性能观察项：ACEScc 往返的 GPU 代价（PREVIEW 预算内？）
- **A（推荐）**：**观察项挂账，不设优化门**——每层子 run ±2 个全屏 pass（3×3 矩阵 + log 编解码，ALU 极轻、无额外纹理分配——转换可折进相邻 kernel 头尾或独立 pass 由 plan 期以 dispatch 框架实测取舍）；预期 PREVIEW 拖滑杆 60fps 无感。验收走查观察清单（沿 M2-3-4 E4 先例）：①≥4 Grade 层链拖 exposure/HLS 滑杆流畅度目测；②FULL pipe 100MP 导出时间 ±5% 带内对比（往返开/关各一轮）；③LUT 树面板万文件目录 rescan 耗时观察（递归枚举规模上限 sanity）。超带才立项专项，不预优化。
- B：设性能门（如往返 ≤2ms/层硬指标）——无基线数据支撑的硬门 = 假精度，观察项足够。
**推荐 A**。

### OQ-12 zh/en 键范围预估
- **A（推荐）**：**随手键 + 收尾 zh-audit 对账补齐**（M2-3-4/M2-4 T4 双先例）——本 phase 键族预估 **100–140 键**：18 目录显示名（`catalog_item_*`）+ Look 四组头 + trackball 三轮标签/Reset wheels + HLS Selective Color 面五滑杆 + Tone 页重组 compat 组 + LUT 树面板（分组/刷新/根目录）+ 设置 LUT 根目录节 + 默认 look 提示 + 严格面错误 toast；zh 值滞后允许，phase 尾 `Scripts/zh-audit.py --check` 对账补齐；语言 code 沿 `zh`。
- B：每任务同步 zh——面板密集期反复打断，两 phase 先例已弃。
**推荐 A**。

## Canonical References

- `research/ALCEDO-FEATURE-MAP.md` §2.1（18 目录全表：`adjustment_catalog.cpp:33-52`/`builtin_type_ids.hpp`/`cat02_white_balance_model.hpp:18-23`/`color_wheel_model.hpp:34-50`/`curve_model.hpp:24-26`/`hls_model.hpp:16-39`/`lmt_model.hpp`/`sharpen_model.hpp:15-19`）+ §2.2（LGG）+ §2.3（Look 分组）+ §2.6（Detail 四件）
- REQUIREMENTS M2GRADE-01..07；ROADMAP M2-5 行（D4 签核 + LUT 05/06/07 语义）
- `LightamerIOP/Sources/NodeOwnershipCatalog.swift`（宽限表/严面位点）+ `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:73-77,205-226`（子 run 结构/ACEScc 插入点）
- `LightamerCore/Sources/Foundation/V50Order.swift`（add-only 纪律 + 空位）
- `LightamerIOP/Sources/Lut3d/LutLibraryStore.swift:83-115`（registry/自愈/degrade 正本）+ `App/Sources/Lightamer/UI/Inspector/LutPanelView.swift`
- `App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift:112-183`（routing 正本）+ `App/Sources/Lightamer/State/InspectorState.swift:155`（provider 缝）+ `App/Sources/Lightamer/State/EditorState.swift:98-123`（pristine/mint 腿）
- `phases/m2-4-node-model/M2-4-CONTEXT.md`（CONTEXT 惯例 + OQ-8 宽限执行 + Deferred「Develop 调整列表归属」移交本 phase）

## Specific Ideas（起草倾向，plan 细化）

- 目录注册表单文件承载：`NodeOwnershipCatalog.swift` 扩展为 `GradeCatalog`（目录 id ↔ op ↔ owner ↔ identity 语义 ↔ 面板暴露清单五元组表），`owner(of:)` 签名不变——严面激活零 seam 改动（该文件自述的激活路径）。
- ACEScc 域转换做成 `Metal/ACESccMath.metal` 公共函数库（矩阵常数 + encode/decode），域转换 op 与各域内 kernel 共用同一份常数（golden 单点钉）。
- 新件单测三件套沿用：纯函数解析 ≤1e-6 + identity 三元组逐字节 + golden 参数点（对照 Alcedo 数值语义，非 GPL 代码）。
- 默认 look 三参数常量落 Core 单源（`GradeCatalog.defaultLook`），ImportService 与 EditorState 双消费点引用同一常量。

## Deferred Ideas

- 蒙版与 18 目录的逐件作用语义（Grade-owned 蒙版 × 单目录项的 blend 细则）——M2-7 裁。
- LUT 面板收藏/搜索/排序（Alcedo `LUTPanel.qml` 有搜索排序——M2GRADE-05 未列，v1 树分组为先，增强挂后）。
- temperature 模块从 33 op 面完全退役（收敛为 CIRAW WB 单入口）——待 CAT02 WB 稳定后按使用数据裁。
- 色环（hue wheel）控件抽象成通用组件——HLS 之外暂无第二消费者，YAGNI。

---

## 夜间授权预案（2026-09-29 起草时点）

本 CONTEXT 提交夜间授权裁决：若无人干预，D-M2-5-CONTEXT-1..12 = **OQ-1..12 全部按推荐 A 生效**。晨审可推翻：推翻任一条 = 修订对应 plan（CONTEXT OQ 原文不改、以 Ruling/勘误注记为准，沿 M2-4-CONTEXT 先例）。plan 期需回填的悬决点（非 OQ 级）：Alcedo Curve 域语义精读（OQ-1 表）、LGG kernel 数学精貌（OQ-2）、HLS 单 target UI ↔ 8-bin 映射（OQ-6）、spectral_film_lut 许可结论与 clone SHA（OQ-7 许可门）、ACEScc 转换 pass 折叠形态（OQ-11）。

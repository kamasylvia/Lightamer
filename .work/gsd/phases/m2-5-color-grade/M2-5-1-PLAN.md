---
phase: m2-5
plan: "M2-5-1"
title: "Grade 新件核（wave 1）——ACEScc 调色域包夹（每层子 run 头尾一对域转换 op，D-M2-5-CONTEXT-3；blend 公式/PixelPipe/PipeCacheKey 零 diff）+ GradeCatalog 18 目录注册表（D1 严格面地基 + defaultLook 常量单源）+ 新 iop 七件八 op（CAT02 WB / Contrast 新语义 / White / Black / Tint / Saturation / LGG colorWheels / HLS——Metal kernel + Params + Swift Float64 参考 golden）+ V50Order LIGHTAMER 行 add-only"
wave: 1
depends_on: ["M2-4"]
autonomous: true
requirements: [M2GRADE-01, M2GRADE-02, M2GRADE-04]
files_modified:
  - LightamerIOP/Sources/NodeOwnershipCatalog.swift         # 修改：GradeCatalog 18 目录注册表（目录 id ↔ op ↔ owner ↔ identity 语义 ↔ 面板暴露清单五元组；owner(of:) 签名零改）+ GradeCatalog.defaultLook 三常量（OQ-8 单源，App 双消费点之 EditorState 侧引用）
  - LightamerIOP/Sources/Registry.swift                     # 修改：新七件 register（default face 注册调用，照既有 `registry.register` 形态追加——checker E3 补申报）+ default face seed 注释同步（testgain DEBUG-only 豁免先例注记随行——E7 依据锚点）；ACEScc envelope 两件不入此文件（KD-2）
  - LightamerCore/Sources/Foundation/V50Order.swift         # 修改：LIGHTAMER-native 行 add-only 追加（acesccIn 20.5 / acesccOut 69.9 / colorWheels 41.0 / cat02WhiteBalance 41.4 / contrast 41.6 / white 41.8 / black 42.0 / saturation 42.2 / tint 42.4 / hls 42.6——KD-3 终值以唯一性测试为门，DECISIONS 签注）
  - LightamerCore/Sources/Pipe/LayerCompositeDriver.swift   # 修改（本 phase 唯一允许触碰的 Pipe 文件）：adjustment-layer leg（②leg）boxes 装配处 ACEScc 包夹——effective chain 含 ≥1 个 18 目录 op（GradeCatalog 查询面）时头尾插入 envelope box；半径 = 该 leg 装配 3-6 行 + 头注；blend 公式/retouch leg/base sub-run/terminal 段/结果 struct 零改动
  - LightamerIOP/Sources/ACEScc/ACESccMath.metal            # 新建：公共函数库——linear Rec2020→AP1 色适应矩阵 + ACEScc encode/decode 常数与函数（域转换 op 与各域内 kernel 共用同一份常数，golden 单点钉）
  - LightamerIOP/Sources/ACEScc/ACESccInModule.swift        # 新建：envelope 入口 op（无面板内部件，driver 直构不经 registry 注册——KD-2）
  - LightamerIOP/Sources/ACEScc/ACESccOutModule.swift       # 新建：envelope 出口 op（逆变换回 linear Rec2020）
  - LightamerIOP/Sources/ACEScc/ACESccConvert.metal         # 新建：两枚域转换 kernel
  - LightamerIOP/Sources/Cat02WB/Cat02WBModule.swift        # 新建：CAT02 创意白平衡（temperature/tint → 照明体 xy → CAT02 适应矩阵；identity = 5999.9934K/9.7112783——KD-4）
  - LightamerIOP/Sources/Cat02WB/Cat02WB.metal              # 新建
  - LightamerIOP/Sources/Contrast/ContrastModule.swift      # 新建：中灰邻域 lightness 保色相 contrast（±100；≠ colisa RGB 缩放语义——KD-5）
  - LightamerIOP/Sources/Contrast/Contrast.metal            # 新建
  - LightamerIOP/Sources/WhiteBlack/WhiteModule.swift       # 新建：White ±100 端点标定（scene-referred）
  - LightamerIOP/Sources/WhiteBlack/BlackModule.swift       # 新建：Black ±100
  - LightamerIOP/Sources/WhiteBlack/WhiteBlack.metal        # 新建：一枚 kernel 双方向（端点标定共享数学，方向参数分 white/black 两 entry）
  - LightamerIOP/Sources/Saturation/SaturationModule.swift  # 新建：0–4 乘法饱和（ACEScc 域，默认 1.0 = identity）
  - LightamerIOP/Sources/Saturation/Saturation.metal        # 新建
  - LightamerIOP/Sources/Tint/TintModule.swift              # 新建：Tint ±100 独立标量（与 CAT02 内嵌 tint 分立，照抄目录）
  - LightamerIOP/Sources/Tint/Tint.metal                    # 新建
  - LightamerIOP/Sources/ColorWheels/ColorWheelsModule.swift # 新建：LGG 三向色轮（params 逐字段照抄 color_wheel_model.hpp:34-50——KD-6）
  - LightamerIOP/Sources/ColorWheels/ColorWheels.metal      # 新建
  - LightamerIOP/Sources/Hls/HlsModule.swift                # 新建：HLS 8-bin（params 逐字段照抄 hls_model.hpp:16-39——KD-7）+ UI↔8-bin 映射纯函数（P2 面板消费）
  - LightamerIOP/Sources/Hls/Hls.metal                      # 新建
  - Project.swift                                           # 修改：新测试文件登记（bundle 无 glob——checker E2 纪律；新源文件目录 tuist generate 覆盖）
  - Tests/LightamerTests/GradeCatalogTests.swift            # 新建（LightamerTestsApp，App 级——完备性经 IOP Registry default face，M2-4-1 NodeOwnershipCatalogTests 同位）：18 目录五元组完备 + owner 矩阵 + defaultLook 常量断言 + V50 唯一性
  - Tests/LightamerTests/ACESccEnvelopeTests.swift          # 新建（LightamerTestsLayers，Core 级——LayerCompositeDriver 直测）：往返 identity 像素断言 + 空 chain 跳过 + retouch/base/terminal 零包夹 + cache 键折叠断言
  - Tests/LightamerTests/GradeKernelGoldenTests.swift       # 新建（LightamerTestsIOPParity——Golden* glob 惯例）：七件 kernel GPU 输出 vs Swift Float64 参考实现（KD-8 容差）+ 各件 identity 三元组
  - Tests/LightamerTests/GradeParamsCodingTests.swift       # 新建（LightamerTestsIOP，IOP 级纯 coding）：Params JSON key 照抄 Alcedo spelling + 默认值/范围钳制 + sidecar round-trip
  - .work/gsd/phases/m2-5-color-grade/M2-5-1-SUMMARY.md     # 新建（收口任务）
  - .work/gsd/phases/m2-5-color-grade/M2-5-1-DECISIONS.md   # 新建（收口任务）
  - .work/GOAL-STATE.md                                     # 续接点追加（收口任务）
  - .work/LESSONS.md                                        # 如踩坑
---

# Plan M2-5-1 — Grade 新件核（ACEScc 域包夹 + GradeCatalog + 新 iop 七件八 op）

> **性质**：管线/算法 plan——App 层零改动（面板与 routing 归 P2/M2-5-2）。三块交付：
> ①ACEScc 调色域的**层子 run 包夹**（D-M2-5-CONTEXT-3 落地——每层子 run 头尾一对域转换
> op，18 目录 grading 全在 ACEScc 域，blend 仍在 Rec2020）；②**GradeCatalog** 18 目录
> 注册表（D-M2-5-CONTEXT-1 的落盘载体 + M2GRADE-04 严格面地基 + defaultLook 单源）；
> ③**新 iop 七件八 op**（CAT02 WB / Contrast 新语义 / White / Black / Tint / Saturation /
> LGG colorWheels / HLS——kernel + Params + Float64 参考 golden；exposure/shadhi/
> vibrance/tonecurve/lut3d 五处既有件对齐**零代码**，其面板暴露清单只在 GradeCatalog
> 声明，P2 消费）。规格锚点 = D-M2-5-CONTEXT-1..4（不得重开）+ Feature-map §2.1/§2.2 +
> REQUIREMENTS M2GRADE-01/02/04。
>
> **执行期精读悬决点**（CONTEXT 预告的四件，全部在本 plan T2-T7 内核读钉死、DECISIONS
> 签注）：LGG kernel 数学精貌（Alcedo `color_wheel` GPU 路径）、Contrast 0.3.0 新语义
> 公式（`contrast` op 源码）、White/Black 端点标定式、HLS 单 target UI↔8-bin 映射的
> 模型侧纯函数。**语义忠实 > 数学家自洽**：Alcedo 实现为唯一对照源，公式照抄思路重写，
> GPL 代码零复制（M2-1 既有红线）。

## 已定裁决（不得重开）

- **D-M2-5-CONTEXT-1（OQ-1 A）**：混合策略——目录缺失件新造（本 plan 七件八 op）+
  既有件参数面对齐（exposure/shadhi/vibrance/tonecurve/lut3d 五处，零代码）；目录注册
  表落 `NodeOwnershipCatalog.swift` 同批，`owner(of:)` 签名不变。
- **D-M2-5-CONTEXT-2（OQ-2 A）**：LGG = 新 iop `colorWheels`，params 逐字段照抄
  `color_wheel_model.hpp:34-50`；lift identity 全零 / gamma、gain identity 色偏
  (1,1,1)；v50 位 41.0。
- **D-M2-5-CONTEXT-3（OQ-3 A）**：ACEScc 往返 = **每层子 run 头尾一对域转换 op**，由
  driver 在子 run 装配时自动包夹；不出现在 add 面与 sidecar；blend 合成仍在 Rec2020。
- **D-M2-5-CONTEXT-4（OQ-4 A）**：base 层宽容现状 + 新增面收窄——**本 plan 不改任何
  加载/校验路径**（收窄的 add 面归 P2）；本 plan 只把 18 目录对照表落盘。
- **M2GRADE-04 字面**：相机 WB 留 RAW Decode/CIRAW 层——本 plan CAT02 WB 为创意色温件，
  与 `TemperatureModule`（develop-owned，不动）分立。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 GradeCatalog = 五元组注册表，owner(of:) 零 seam 改动

```swift
// LightamerIOP/Sources/NodeOwnershipCatalog.swift 扩展（同文件，不新建——D1 落盘位）
public struct GradeCatalogItem: Sendable, Equatable {
    public let catalogID: String          // Alcedo display 稳定 id（如 "cat02WhiteBalance"）
    public let opName: String             // <Module>.opName 常量（零字符串字面量纪律不变）
    public let owner: NodeOwnership       // 13 项 .grade / 4 项 .drtPost / Tint 标量 .grade
    public let identityJSON: String       // identity 参数快照（reset 语义单源，P2 Reset 按钮/新建 grade 消费）
    public let panelExposures: [String]   // 面板暴露清单（主滑杆 key 列表——P2 provider 面声明式来源）
}
public enum GradeCatalog {
    public static let items: [GradeCatalogItem]  // 18 项（§2.1 全表序）
    public static func item(opName: String) -> GradeCatalogItem?
    public static func gradeItems() -> [GradeCatalogItem]       // owner == .grade 的 13+1 项
    public static let defaultLook: [DefaultLookEntry]           // KD-9
}
public struct DefaultLookEntry: Sendable { public let opName: String; public let paramsJSON: String }
```

- **一致性维持答案（KD 必答）**：`owner(of:)` 既有实现改为**消费** `GradeCatalog.items`
  的 owner 列（drtPost 四件/develop 族仍为显式例外常量表——它们不在 18 目录内，两表
  并存但单文件）；**函数签名与语义零变**（default 臂仍 .grade），M2-4-1 交付的校验缝、
  `NodeOwnershipCatalogTests` 全量断言零 diff 通过 = 活体回归证明。18 目录项的 owner
  不再由 default 臂"碰巧对"，而是表内显式——M2GRADE-01「严格面激活」的信息基座。
- **完备性 AC（checker E7 补测试豁免集）**：`GradeCatalog.items` 恰 18 项；
  `gradeItems()` 恰 14（13 Grade 件 + Tint）；`ModuleRegistry` default face ∖
  （18 目录 op 集 ∪ **{testgain}**）= ∅（新七件入表 = 自动闭合；{testgain} =
  DEBUG-only 注册豁免——`Registry.swift` `#if DEBUG` 先例，Release face 不含它；
  GradeCatalogTests 断言旁**注明该豁免依据**，防后来者把 testgain 当漏登）。
- **defaultLook 消费方向**：常量落 IOP（引用 `<Module>.opName` + `<Module>.Params`
  编码），**唯一运行时消费者 = App EditorState mint 分支**（P2 T7 接线；Core
  ImportService 只写 flag=1 不读值——Core 不 import IOP 的方向约束由此不破）。
- **对齐五件 identity 单源核验（checker m5）**：exposure/shadhi/vibrance/tonecurve/
  lut3d 五既有件的 `identityJSON` 逐一以各件 **kernel no-op 参数点**核验入表（与
  GradeKernelGoldenTests 的 identity 断言同源同值，禁手抄面板默认值）；**shadhi
  例外声明**：其面板默认（shadows 50 / highlights -50）是工作点**非恒等点**——
  identity 快照（GradeCatalog 单源，Reset 消费）与面板默认值（P2 provider 从
  Params 默认值引用）**分立两套**，两套值与依据入 DECISIONS。

### KD-2 ACEScc 包夹 = driver 直构 envelope box，零 registry 注册、零用户可见面

- **形态**：`ACESccInModule` / `ACESccOutModule` 是普通 `IOPModule`/`ModuleBoxing`
  conformer，但**不经 `registry.register`**——`LayerCompositeDriver` adjustment-leg
  在 `materializeBoxes` 返回后直接构造：
  ```swift
  // LayerCompositeDriver composite ②leg（现 :380 毗邻），
  // effective chain 含 ≥1 个 18 目录 op 才包夹（checker E2 收窄）：
  if boxes.contains(where: { GradeCatalog.item(opName: $0.opName) != nil }) {
      boxes = [ACESccInBox()] + boxes + [ACESccOutBox()]
  }
  ```
  **包夹条件（checker E2 收窄）**：`!boxes.isEmpty` 只表达「链非空」，不表达
  「grade 域」——收窄为 **effective chain 含 ≥1 个 18 目录 op**（经
  `GradeCatalog.item(opName:)` 查询面判定，禁白名单散抄）；纯非目录链（仅
  develop/DRT/其余既有件）零包夹零代价，「无 grade 栈逐字节不变」的证明面随之
  扩大。（构造细节 = 每次装配铸新实例 UUID——box 瞬态不持久，plane 键用
  `adjustment.id` 不受影响；hash 链经 runSub 的 instances 数组**天然折叠**
  envelope 的 opName+常数 params。）
- **缓存键影响（KD 必答）**：`PipeCacheKey.swift` **零 diff**。envelope 进入 runSub
  的 instances → levelHash 链自动含其常数 hash；`upstreamHash`/`compositePosition`
  语义零变。envelope 的存在是**代码版本事实**（全会话均匀），非 per-key 变量——同一
  会话内不存在"有包夹的旧键"与"无包夹的新键"并存，无 stale-hit 面。跨会话无影响
  （pipe cache 内存态、sidecar 不含 envelope）。
- **半径红线**：不包夹 retouch stroke leg（stroke 走 RetouchEngine 独立路径，结构性
  不经过 boxes 装配）；不包夹 base sub-run（D4 字面"Grade 节点内部"）与 terminal 段
  （display-referred 域，包进 = 语义错位）；空 chain（enabled 且 effective 后仍空）
  与**纯非目录链**（不含 18 目录 op）**跳过包夹**（省 2 个全屏 pass，非 grade 层
  零代价）。`LayerCompositeResult` stats struct 零改动（envelope pass 计入
  layerStats 的既有 run 计数，观测面 P3 走查消费）。
- **数学**：`ACESccMath.metal` 公共库单点钉——linear Rec2020→AP1 色适应 3×3（常数
  矩阵，Float64 Swift 参考推导后降 float32 常数）+ ACEScc log 编解码
  （ACES 文档分段式：`log2(x·)/cut` 两段线性 + 对数段，斜率/截断常数照 ACEScc
  规范 `S(116.02·log10(x))/…` 族——参考实现与 kernel 同一份推导，测试逐常数断言）。
  decode = 精确逆。**头注释红线**：本文件是 ACEScc 域唯一常数源，域内新 kernel 禁
  自带矩阵。
- **identity 往返容差**：GPU encode∘decode vs 输入，绝对容差 **1e-5**（float32 log
  往返 + 纹理量化；线性段小值处相对漂移可放大，故用绝对容差 + 4K 随机域采样断言
  p99.9）。对比先例：SetMix(0)≡bypass 用容差 0 是因为路径恒等，本处是数学往返，
  容差分级不同——AC 写死数值，IEEE 语义（-0/+0 视相等）沿用 checker 口径。

### KD-3 V50Order 新行 = LIGHTAMER add-only，唯一性测试为门

| op | order | 依据 |
|---|---|---|
| acesccIn | 20.5 | **exposure 21.0 之前**（retouch 20.0 之后）——envelope 入口须先于域内全部 op；checker E1：28.2 落 exposure 之后 = 域内最低位 op 先于包夹执行，排序断言不可满足 |
| acesccOut | 69.9 | terminal floor 70.0 之下、splittoning 67.0 之上（envelope 出口恒最高且不出层域） |
| colorWheels | 41.0 | CONTEXT OQ-2 A 钦定；与未注册 dt 行 `colorbalance` 同位 = 28.5 簇先例的声明例外 |
| cat02WhiteBalance | 41.4 | colorequal 41.2 之后 |
| contrast | 41.6 | — |
| white / black | 41.8 / 42.0 | — |
| saturation | 42.2 | — |
| tint | 42.4 | — |
| hls | 42.6 | — |

- **不变量（测试机检，终值如遇未注册 dt 行撞位 ±0.05 内挪、DECISIONS 签注终值）**：
  ①新 LIGHTAMER 行彼此 order 唯一；②与**已注册 op**（ModuleRegistry 可实例化全集）
  零同位；③同位未注册 dt 行仅 `colorWheels↔colorbalance` 一处声明例外；④既有行
  零改动——**形态判据（checker m3）**：`git diff` 仅新增 hunk（零删除行/零修改行，
  **不锚 94/95 具体行数**）+ 既有 V50Order 测试全绿。

### KD-4 CAT02 WB：temperature/tint → 照明体 xy → CAT02 适应矩阵（ACEScc 域施加）

- 参数面照抄 `cat02_white_balance_model.hpp:18-23`：`temperature` 默认
  **5999.9934**（identity，= AP1 白点 x0.32168/y0.33767 在 RAW Custom WB CCT/tint
  映射下的解，Alcedo `AcesWhiteTemperatureTint()` 同值互证），2000–15000；`tint`
  默认 **9.7112783**，±150。JSON key 照抄 `temperature`/`tint`。
- kernel 数学（执行期 T3 核读 Alcedo cat02 GPU 路径钉死、DECISIONS 签注）：读 ACEScc
  域 texel → 施加 CAT02 适应 3×3（照明体 xy 适应到 AP1 白）→ 写回。**不做"更正确"
  的线性域施加**——Alcedo 在 ACEScc 域施加是实测语义，忠实优先（CONTEXT Specific
  Ideas 同款立场）。
- **identity 推导 golden（KD 必答）**：`cat02XY(5999.9934, 9.7112783)` ≈
  (0.32168, 0.33767)（1e-4）；由该 xy 构造的适应矩阵 ≈ I（逐元素 1e-5）——两个断言
  把"默认即 identity"从注释变成机检；2000K/15000K/±150 四角点 vs Float64 参考。

### KD-5 Contrast 新语义 / White / Black：执行期核读钉公式

- **Contrast**（opName `contrast`，±100，默认 0；新图 +15 由 defaultLook 承载不在
  默认参数）：0.3.0 语义 = **中灰邻域 lightness 保色相**（不动中灰、hue 不漂）。
  执行期读 Alcedo `contrast` op + 其 shader 钉公式（工作假设：luma 轴 S/幂曲线围绕
  中灰枢轴、色度按 luma 变化比例缩放——**以源码为准，假设不作数**）。
- **White/Black**（±100，默认 0）：scene-referred 端点标定——执行期读 Alcedo
  white/black op 源码钉式；一枚 kernel 双 entry（方向 flag）。
- **AC 兜底（公式精貌无论如何落地都须满足）**：identity @ 0（±100 全程端点值有界不
  NaN/Inf）；Contrast 单调性（luma 输入序保持）+ 色相漂移 ≤2°（HSL hue 扫描 12 点
  ×3 luma）；golden 参数点（0/+15/±100）vs Float64 参考实现（KD-8 容差）。

### KD-6 colorWheels params 逐字段照抄 `color_wheel_model.hpp:34-50`

```swift
public struct ColorWheelControl: Codable, Hashable, Sendable {
    public var disc: SIMD2<Float>          // JSON: disc.x/disc.y
    public var strength: Float             // 默认 1.0
    public var colorOffset: SIMD3<Float>   // JSON: color_offset.x/y/z
    public var luminanceOffset: Float      // JSON: luminance_offset
    // CodingKeys 照抄 Alcedo spelling（disc/strength/color_offset/luminance_offset）
}
public struct ColorWheelsParams: Codable, Hashable, Sendable {
    public var lift: ColorWheelControl     // identity = 全零
    public var gamma: ColorWheelControl    // identity = colorOffset (1,1,1)
    public var gain: ColorWheelControl     // identity = colorOffset (1,1,1)
}
```

- **kernel 数学（执行期核读 Alcedo color_wheel GPU 路径钉死）**：工作模型 = ACEScc
  域内 lift 加法偏移 / gamma 幂或乘法 / gain 乘法；disc 极角→色度方向、半径→幅度、
  strength 全局缩放、luminanceOffset 加亮度。**精貌（gamma 幂基 vs log 域加法）以
  Alcedo 为唯一对照源**，落 DECISIONS；golden 参数点三轮各一组 + 组合一组。
- identity 语义机检：`IsIdentity` 判定式照抄 Alcedo `color_wheel_model.cpp`
  `IsIdentity`（lift 全零 && gamma/gain colorOffset==(1,1,1)——disc/strength/
  luminanceOffset 不参与 identity 判定，照抄）。

### KD-7 HLS 8-bin：params 照抄 `hls_model.hpp:16-39` + 映射纯函数落 IOP

- Params 全字段：`hueBins[8]`（默认 0..315 步 45）、`adjTable[8]{h,l,s}`、
  `hRangeTable[8]`（默认全 45）、`targetHls{0,0.5,1}`、`hlsAdj{h,l,s}`、
  `hRange=45`、`lRange=0.1`、`sRange=0.1`；JSON keys 照抄
  `hue_bins/hls_adj_table/h_range_table/target_hls/hls_adj/h_range/l_range/s_range`。
- kernel：每像素求 H/L/S → 距各 bin 中心色相距离 raised-cosine 权重（h_range_table
  窗）→ 加权施加 H/L/S 偏移。色彩空间取 H/L/S 的具体式子执行期随 Alcedo hls op
  源码钉。
- **UI↔8-bin 映射纯函数**（`HlsModule` 内静态，P2 面板消费、本 plan 落函数+测试）：
  `applyTargetEdit(params:targetBin:dh:dl:ds:) -> HlsParams`——Alcedo 单 target UI
  写选中 bin 的 adjTable 行 + 同步 hlsAdj/hRange；映射精貌执行期核读
  `EditorLookPanel.qml` Selective Color 节钉死（CONTEXT OQ-6 悬决点）。

### KD-8 golden 参考来源 = 测试内 Swift Float64 参考实现（Alcedo 无 golden 资产）

- 先例 = `Scripts/gen-float-fixtures.py` float64 fixture 管线 + IOPParity bundle
  Golden* 惯例。本 plan 七件的参考实现直接写在
  `GradeKernelGoldenTests.swift`（`ref` 前缀 Float64 纯函数），与 kernel 同一份数学
  推导两个落笔——**公式来源 = Alcedo 源码语义（只读参考，代码零复制）**。
- **容差分级（checker「AC 机检含 IEEE 容差」口径）**：
  - 纯函数（矩阵构造/xy 求解/映射函数）：**≤1e-6**（Swift Float64 对 Float64）。
  - GPU kernel vs Float64 参考：绝对 **≤1e-5**（值域 [-0.5, 2.5] 裁剪后统计，
    p99.9 达标 + max 硬顶 5e-5 报警行）。
  - identity 参数点：**逐像素容差 0**（identity 路径 kernel 早退/常数矩阵≈I，
    走精确断言；-0/+0 视相等）。
- 测试参数点矩阵：每件 ≥4 点（identity / defaultLook 值 / 正负端点中值 / 端点），
  CAT02 另加 KD-4 两断言。

### KD-9 defaultLook 常量 = 三 entry 单源

```swift
// GradeCatalog.defaultLook（KD-1 结构内）：
// exposure { exposure: +1.5 }  /  contrast { contrast: +15 }  /  saturation { saturation: 1.3 }
```
- exposure entry 复用既有 `ExposureModule.Params`（只填 `exposure` 字段，mode/black
  等超集字段取默认）——**默认 look 的 exposure 就是既有 exposure 件实例**，M2GRADE-03
  的 +1.5 EV 无需新件；contrast/saturation entry 用本 plan 新件 Params。JSON 编码
  经各件 Codable（与 sidecar paramsData 同一编码路径），P2 mint 分支直接解码。

## read_first

1. `.work/gsd/phases/m2-5-color-grade/M2-5-CONTEXT.md`——裁决正本（D1..D4 + 三条事实
   基线 + Reusable Assets 表）。
2. `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:69-123,369-432`——三段子 run
   结构 + adjustment-leg boxes 装配（包夹插入点）+ L021 断言（envelope 不得破坏）。
3. `LightamerIOP/Sources/NodeOwnershipCatalog.swift`——宽限表正本 + 零字面量纪律 +
   passthrough/testgain default 臂注记（GradeCatalog 扩展不得破坏）。
4. `LightamerCore/Sources/Foundation/V50Order.swift`——add-only 纪律正文 + 28.5 簇
   同位先例 + Lightamer 原生行注记式样（skinSmooth 66.5）。
5. `LightamerCore/Sources/Pipe/ModuleRegistry.swift:138-175`——materializeBoxes /
   effectiveChain 语义（envelope 包夹的正确层位）。
6. Alcedo 参考源（只读，代码零复制）：`alcedo_studio/src/include/edit/operators/models/
   {cat02_white_balance_model.hpp,color_wheel_model.hpp,hls_model.hpp}` +
   `src/edit/operators/models/{cat02_white_balance_model.cpp,color_wheel_model.cpp,
   hls_model.cpp}` + contrast/white/black op 目录 + 各 op GPU 路径（metal_shader/
   glsl 目录 grep `<op>`）+ `develop_color_transform.hpp` 的
   `AcesWhiteTemperatureTint()`。
7. `Tests/LightamerTests/`（IOPParity Golden* 先例文件任一）+ `Scripts/test-direct.sh`
   头注——测试落点与跑法。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使
   句、body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；git add
   用 `.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；不加 `-derivedDataPath`；新建目录/
   文件后同 commit 内跑 `tuist generate`。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数
   行 + failures 行双读（L028）。**回归基线 = 2240/14skip/0fail**；每任务全套 suite
   绿。**全套跑法 = `Scripts/test-direct.sh --all`（七 bundle）**；跑前必须向
   orchestrator SendMessage 报备；RSS ≥8G = MEMFAIL 机检内置，触发即记 E3 不自行重试
   超两次。在案 flake 隔离复跑 ×3 归因入 SUMMARY。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`PixelPipe.swift`/`PipeCacheKey.swift` **零 diff**；
   `LayerCompositeDriver.swift` 改动半径 = adjustment-leg 包夹 3-6 行 + 头注
   （blend 公式/retouch leg/base sub-run/terminal 段/结果 struct 零改动——diff 越界
   = 违约）；`LightamerSidecar.swift`/`LayerStack.swift`/`MaskSpec.swift`/
   `LibrarySchema.swift` 零触（sidecar 格式零变更——envelope 不入 sidecar 是 D3 字
   面）；新件注册面 = `Registry.swift`（front-matter 已申报——七处 register +
   default face seed 注释同步，T3-T7 随件追加；ACEScc envelope 两件**不**入
   Registry，KD-2）；GPL 参考只读（Alcedo 代码与数据不入库）。
6. **测试登记纪律（checker E2）**：新建测试文件**同 commit** 登记两处——①
   `Project.swift` 对应 bundle sources 显式清单；②
   `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` 增行（`<bundle>\t
   <method-count>\t<file>`）。归属：GradeCatalogTests = **APP**（IOP Registry face+
   catalog 面，NodeOwnershipCatalogTests 同位）；ACESccEnvelopeTests = **LAYERS**
   （Core driver 直测）；GradeKernelGoldenTests = **IOPP**（Golden* 惯例）；
   GradeParamsCodingTests = **IOP**。运行期总数基线相应上移（对账以 BUNDLE 行为准）。
7. **收口核对（checker 教训②）**：T8 `git diff --stat` 与 front-matter files_modified
   逐文件核对，越界 = 违约。
8. **opName 常量纪律**：`NodeOwnershipCatalog.swift` 扩展后 `git grep '"'` 实参零新
   字面量（GradeCatalog opName 引用一律 `<Module>.opName` 常量；identityJSON 字符串
   是参数 JSON 非 op 名，豁免）。

## Tasks

### T1 GradeCatalog 18 目录注册表 + V50Order 新行

- **read_first**：上列 1/3/4。
- **action**
  1. `V50Order.swift`：KD-3 十行 LIGHTAMER add-only 追加（注释式样照 skinSmooth 行：
     `// LIGHTAMER: <名> — <一句语义>`）。
  2. `NodeOwnershipCatalog.swift`：KD-1 全量（GradeCatalogItem/GradeCatalog/
     DefaultLookEntry + 18 项表 + owner(of:) 改消费表 owner 列 + defaultLook 三
     entry）。既有 drtPost/develop 例外常量表保留原样。
  3. 新建 `Tests/LightamerTests/GradeCatalogTests.swift`：恰 18 项 / gradeItems 恰
     14 / 完备性（default face ∖（18 目录 ∪ {testgain}）= ∅——**断言旁注明 testgain
     DEBUG-only 豁免依据**，checker E7）/ owner 矩阵（18 项逐项 + 例外四件 + develop
     族回归）/ KD-3 唯一性三不变量 / defaultLook 三 entry 的 op 与值断言（+1.5/+15/
     1.3）/ 对齐五件 identityJSON no-op 参数点断言（shadhi 断言「面板默认 50/-50 ≠
     identity 快照」分立两值——checker m5）/ 既有 `NodeOwnershipCatalogTests` 零
     改动全绿。
  4. `tuist generate`（新目录批量后统一跑，见 T7 注）+ 测试登记两处（纪律 6）。
- **验收标准**
  - [ ] 18 项完备 + owner 矩阵 + 唯一性 + defaultLook 断言 + 对齐五件 identity
        no-op 断言（m5）全绿；既有所有权测试零改动全绿。
  - [ ] V50Order diff 仅新增 hunk（add-only 形态判据：零删除/零修改行，m3）；
        新十行 add-only。
  - [ ] 测试登记：Project.swift（LightamerTestsApp）+ BUNDLE-MAP 行同 commit 在册。
  - [ ] 全套回归 `0 fail`（基线 2240 + 新增）。

### T2 ACEScc 公共数学库 + 域转换 op 对 + driver 包夹

- **read_first**：上列 2/5/7。
- **action**
  1. 新建 `LightamerIOP/Sources/ACEScc/ACESccMath.metal`（KD-2 数学：Rec2020→AP1
     色适应矩阵 + ACEScc encode/decode；头注「域唯一常数源」红线）。
  2. 新建 `ACESccInModule.swift` / `ACESccOutModule.swift` / `ACESccConvert.metal`
     （两枚 kernel 各调公共库；Params = 空结构——常数件；**不进 registry**）。
  3. `LayerCompositeDriver.swift` adjustment-leg：KD-2 包夹（**effective chain 含
     ≥1 个 18 目录 op 判定才包**——checker E2 收窄，GradeCatalog 查询面）+ 头注
     三行（D3 落点 / 零 sidecar / 红线半径）。
  4. 新建 `Tests/LightamerTests/ACESccEnvelopeTests.swift`：往返 identity 像素断言
     （KD-2 容差 1e-5，p99.9 口径）；空 chain 跳过（链空 → levelHash 不含 envelope
     名）；**纯非目录链零包夹**（仅 develop/DRT 等非 18 目录件的链无 envelope pass）；
     **排序断言（checker E1）**：含 exposure 的层链 effective pieces.first.opName ==
     acesccIn && pieces.last.opName == acesccOut（20.5 < 21.0 机检——envelope 先于
     域内最低位 op、后于全部域内 op）；retouch-only 层零包夹；base/terminal 链零
     包夹（composite 结果像素与改造前 fixture 一致——用既有 LayerCompositeTests
     fixture 形栈，**无 18 目录 op 的栈输出逐字节不变** = 零回归证明）；含 grade
     件的层 sub-run levelHash 折叠 envelope（同层同参两次 composite 缓存 HIT 断言
     = 键稳定）。
  5. **既有层链像素断言盘点（checker E2 任务）**：18 目录含 exposure/shadhi/
     vibrance/tonecurve/lut3d 五既有件——含这五件之一的既有测试栈现落入包夹面，
     其像素断言如需放宽容差（ACEScc 往返漂移 ≤1e-5 量级），**逐条在 DECISIONS
     记因**（断言名 + 原容差 → 新容差 + 漂移来源 = envelope 往返），禁静默改；
     无需放宽者逐条保持原断言并在盘点表中列「保持」结论。
  6. 测试登记两处（LAYERS bundle）。
- **验收标准**
  - [ ] 往返 identity / 空 chain·纯非目录链跳过 / 排序断言（first==acesccIn &&
        last==acesccOut，E1）/ retouch·base·terminal 零包夹 / 无 18 目录 op 栈
        逐字节不变 / 键稳定断言全绿。
  - [ ] 既有层链像素断言盘点完成：放宽者逐条 DECISIONS 记因，零静默改（E2）。
  - [ ] `PixelPipe.swift`/`PipeCacheKey.swift` 零 diff；driver diff 仅包夹半径
        （`git diff` 逐 hunk 核）。
  - [ ] 测试登记在册；全套回归 `0 fail`。

### T3 CAT02 WB 新件

- **read_first**：上列 6（cat02 模型 + GPU 路径 + AcesWhiteTemperatureTint）。
- **action**
  1. 新建 `Cat02WB/` 三件（KD-4：Params temperature/tint 照抄 + kernel ACEScc 域
     施加 + xy/矩阵纯函数 `cat02XY`/`cat02AdaptationMatrix` 落 Module 内静态供测试）。
     registry 注册 + Params 默认值 5999.9934/9.7112783。
  2. `GradeKernelGoldenTests` 追加：KD-4 identity 推导两断言 + 四角点 + 参数点矩阵
     （KD-8 容差分级）。
  3. `GradeParamsCodingTests` 追加：JSON key `temperature/tint` + 范围钳制。
- **验收标准**
  - [ ] identity 两断言（xy≈AP1、矩阵≈I）+ golden 参数点全绿；identity 参数点像素
        容差 0。
  - [ ] 全套回归 `0 fail`。

### T4 Contrast 新语义 + White/Black 新件

- **read_first**：上列 6（contrast/white/black op 源码 + shader）。
- **action**
  1. 新建 `Contrast/` 两件（KD-5：±100；公式执行期按源码钉、DECISIONS 签注终式）。
  2. 新建 `WhiteBlack/` 三件（White/Black 两 op 共享 kernel 双 entry）。
  3. golden 追加：两件 identity @0 容差 0 + Contrast 单调性 + 色相漂移 ≤2°（12 hue
     ×3 luma 扫描）+ 参数点（0/+15/±100）；White/Black 端点值有界断言。
  4. coding 测试追加（JSON key `contrast`/`white`/`black`，范围 ±100）。
- **验收标准**
  - [ ] identity/单调性/色相漂移/golden 参数点全绿；公式终式入 DECISIONS。
  - [ ] 全套回归 `0 fail`。

### T5 Saturation + Tint 新件

- **read_first**：上列 6（saturation/tint op 源码）。
- **action**
  1. 新建 `Saturation/`（0–4 乘法，默认 1.0 identity 容差 0；luma 权重执行期按
     Alcedo 源码钉）与 `Tint/`（±100 独立标量；绿-品红轴式子按源码钉）各两件。
  2. golden + coding 测试追加（同 T3/T4 模式；saturation 另加 0/4 端点无 NaN）。
- **验收标准**
  - [ ] identity/golden/端点断言全绿。全套回归 `0 fail`。

### T6 colorWheels 新件（LGG）

- **read_first**：上列 6（color_wheel 模型/GPU 路径）。
- **action**
  1. 新建 `ColorWheels/` 两件（KD-6 全量：Params 逐字段 + CodingKeys 照抄 +
     IsIdentity 判定式照抄 + kernel ACEScc 域三轮）。
  2. golden 追加：三轮各一参数点 + 组合点；lift identity 全零 / gamma·gain identity
     (1,1,1) 像素容差 0；kernel 数学终式（幂基 vs log 加法）DECISIONS 签注。
  3. coding 测试追加（嵌套 Control JSON round-trip + identity 判定）。
- **验收标准**
  - [ ] 三 identity 像素容差 0 + golden 参数点全绿；IsIdentity 与 Alcedo 判定式逐条
        对应（测试注释列对照）。
  - [ ] 全套回归 `0 fail`。

### T7 HLS 新件 + 映射纯函数

- **read_first**：上列 6（hls 模型 + op + EditorLookPanel Selective Color 节）。
- **action**
  1. 新建 `Hls/` 两件（KD-7 全量：8-bin Params + raised-cosine kernel +
     `applyTargetEdit` 映射纯函数）。
  2. golden 追加：单 bin 施加权重窗形状断言（邻 bin 泄漏 = raised-cosine 预期值）+
     参数点；映射纯函数 Float64 对照（≤1e-6）+ bin 遍历完备（8 bin 逐个可选中编辑）。
  3. coding 测试追加（数组字段 round-trip + 默认表断言）。
  4. `tuist generate` 终跑（本 plan 新目录一次覆盖 T2-T7 全部新目录——如 T1 未跑）。
- **验收标准**
  - [ ] 权重窗/参数点/映射断言全绿；映射终式（单 target ↔ 8-bin）入 DECISIONS
        （OQ-6 悬决点销账）。
  - [ ] 全套回归 `0 fail`。

### T8 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前向 orchestrator SendMessage 报备；计数/
     秒数/bundle 峰值入 SUMMARY）。
  2. 落盘 `M2-5-1-SUMMARY.md`（测试数变化/容差实配值/七件 v50 终位表/envelope 半径
     diff 自核）+ `M2-5-1-DECISIONS.md`（四个执行期精读悬决点终式签注：LGG kernel
     数学 / Contrast 公式 / White·Black 端点式 / HLS 映射 + v50 终值若挪位 + 对齐
     五件 no-op 参数点核验表——shadhi 面板默认 50/-50 与 identity 快照分立两套值
     （m5）+ 既有层链像素断言盘点表（E2：放宽项逐条记因，保持项列结论））。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-5-1 完成 + 下一步 = M2-5-2）；LESSONS 如
     踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 7）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | GradeCatalog 恰 18 项 / gradeItems 14 / 完备性（registry face ∖（18 目录 ∪ {testgain}）= ∅，DEBUG 豁免依据注明——E7）/ owner 矩阵 / 对齐五件 identityJSON no-op 断言（shadhi 分立两值——m5）/ 既有所有权测试零改动全绿 | GradeCatalogTests + 既有 NodeOwnershipCatalogTests |
| 2 | V50Order diff 仅新增 hunk（add-only 形态判据：零删除/零修改行，不锚行数——m3）；新十行 add-only 且唯一性三不变量成立 | `git diff LightamerCore/Sources/Foundation/V50Order.swift` 逐 hunk + GradeCatalogTests 唯一性断言 |
| 3 | ACEScc 往返 identity（GPU vs 输入绝对 ≤1e-5，p99.9；-0/+0 视相等）；空 chain 与纯非目录链跳过；retouch/base/terminal 零包夹；无 18 目录 op 的栈输出逐字节不变；**含 exposure 层链 pieces.first.opName==acesccIn && last==acesccOut（E1 排序断言）**；既有层链像素断言盘点零静默改（E2）；层 sub-run 键稳定（同参二次 composite HIT） | ACESccEnvelopeTests + 盘点表核对 |
| 4 | envelope 零用户可见面：不进 registry、不入 sidecar、add 面不可见（P2 前 = 无枚举源）；`PixelPipe.swift`/`PipeCacheKey.swift` 零 diff | `git diff --name-only` + `git grep -n "ACESccIn" LightamerIOP/Sources/Registry.swift` 零命中 |
| 5 | CAT02 WB：默认 (5999.9934, 9.7112783) → xy≈AP1(0.32168,0.33767)@1e-4 → 矩阵≈I@1e-5；四角点+参数点 golden（纯函数 ≤1e-6 / GPU ≤1e-5） | GradeKernelGoldenTests |
| 6 | Contrast：identity@0 容差 0 + luma 单调 + 色相漂移 ≤2° + golden（0/+15/±100）；White/Black：identity@0 + 端点有界 | GradeKernelGoldenTests |
| 7 | Saturation 0–4（1.0 identity 容差 0、端点无 NaN）；Tint ±100 | GradeKernelGoldenTests |
| 8 | colorWheels params 逐字段=CAML `color_wheel_model.hpp`（CodingKeys 同 spelling）+ IsIdentity 判定式照抄 + 三 identity 容差 0 + golden 参数点 | GradeParamsCodingTests + GradeKernelGoldenTests |
| 9 | HLS params 逐字段=`hls_model.hpp` + 8 bin 权重窗 raised-cosine 断言 + `applyTargetEdit` Float64 对照 ≤1e-6 + 8 bin 遍历完备 | GradeKernelGoldenTests + GradeParamsCodingTests |
| 10 | 全套回归 0 fail，计数 ≈ 2240 + 25..40 | test-direct.sh --all BUNDLE 行双读 |
| 11 | diff 边界 == 申报文件集；driver diff 仅包夹半径 | `git diff --stat` 逐文件核对 |
| 12 | 新测试文件登记闭环（四文件 × Project.swift + BUNDLE-MAP） | `git grep` 双命中 |

## 风险与边界

- **ACEScc 往返 GPU 代价（OQ-11 观察项，非本 plan 门）**：每层 +2 全屏轻 ALU pass；
  本 plan 只保证正确性（identity/键稳定），性能走查归 P3 收口三查。PREVIEW 拖滑杆
  如实测可感卡顿——记 E3 数据，不预优化。
- **既有含目录 op 测试栈的像素断言漂移（checker E2）**：包夹条件收窄后
  exposure/shadhi/vibrance/tonecurve/lut3d 所在链进入包夹面——其漂移上界 =
  ACEScc 往返 ≤1e-5（identity 数学），既有硬断言（容差 0/逐字节）如触发 = 按
  T2 action 5 盘点任务**逐条 DECISIONS 放宽并记因**，禁全局面放宽、禁静默调参；
  纯非目录链保持逐字节断言不动。
- **golden 参考无 Alcedo 资产可依**：Float64 参考实现自建（KD-8）；风险 = 参考与
  kernel 同源推导「自我印证」——缓解 = 公式来源钉 Alcedo 源码语义并在测试注释列
  源文件:行号，DECISIONS 存终式；发现 Alcedo 实现与本推导冲突时**以 Alcedo 为准**
  改参考与 kernel 同批。
- **执行期公式悬决点翻车**：若 Alcedo 某 op 源码/不可读/语义与假设出入过大（如
  contrast 并非 luma 轴曲线）——按源码实测语义实现，DECISIONS 记偏差；AC6 的不变量
  断言（identity/单调/漂移）是语义底线，公式形态可变。
- **包夹与 L021 断言**：envelope box 参与 sub-run 可能影响 pieces 首末 ROI 断言——
  envelope 域变换是逐像素 ROI 恒等算子（dscIn=dscOut），理论零影响；实测若触发
  precondition，先核 envelope 的 ROI 传播面（禁改 L021 断言本身，除非 DECISIONS
  论证 + orchestrator 批注）。
- **colorWheels 与未注册 dt 行 41.0 同位**：28.5 簇先例覆盖；若未来 Lightamer 启用
  dt `colorbalance` 件，届时重排是彼 plan 的事（本 plan DECISIONS 声明在先）。
- **基线上移**：2240 为起算基线；本 plan 预计 +25..40（四测试文件），后续 plan 以
  BUNDLE-MAP 行对账。

## 提交约定

- T1 `feat(iop): grade catalog registry and v50 native rows`
- T2 `feat(pipe): acescc domain envelope per layer sub-run`
- T3 `feat(iop): cat02 creative white balance op`
- T4 `feat(iop): contrast hue-preserving op and white black endpoints`
- T5 `feat(iop): saturation and tint grade ops`
- T6 `feat(iop): lift gamma gain color wheels op`
- T7 `feat(iop): hls 8-bin selective color op`
- T8 `docs(m2-5): close out plan 1 grade kernel core`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-09-30）

checker 判 FAIL（8E+6M）后本 plan 落地项：

- **E1（acesccIn 落位）**：order 28.2 → **20.5**（< exposure 21.0；front-matter
  V50Order 行 + KD-3 表同步 add-only 语义）；T2 action 4 增**排序断言**「含 exposure
  的层链 pieces.first.opName == acesccIn && pieces.last.opName == acesccOut」；
  AC#3 吸收。
- **E2（包夹条件收窄）**：KD-2 `!boxes.isEmpty` → **effective chain 含 ≥1 个 18
  目录 op**（`GradeCatalog.item(opName:)` 查询面）；T2 action 5 增**既有层链像素
  断言盘点任务**——需放宽容差者逐条 DECISIONS 记因，禁静默改；AC#3 + 风险节同步
  （含五既有件的链进包夹面，漂移上界 ≤1e-5）。
- **E3（front-matter 补申报）**：增 `LightamerIOP/Sources/Registry.swift`（七处
  register + default face seed 注释同步）；纪律 5 补注册面归属（T3-T7 随件追加，
  ACEScc envelope 两件不入 Registry）。
- **E7（完备性豁免集）**：KD-1/AC#1 完备性公式改「default face ∖（18 catalog ∪
  {testgain}）= ∅」（testgain = DEBUG-only 注册先例），GradeCatalogTests 断言旁
  注明依据。
- **m3（V50Order 判据形态化）**：KD-3 不变量④/T1 AC/AC#2 改「git diff 仅新增
  hunk（零删除/零修改行）」，不锚 94/95 具体行数。
- **m5（对齐五件 no-op 核验）**：KD-1 增 identity 单源核验 bullet——五件
  identityJSON 逐一以 kernel no-op 参数点核验；**shadhi 面板默认（shadows 50 /
  highlights -50）非恒等点**，identity 快照与面板默认分立两套，DECISIONS 记；
  T1 action 3 断言 + T8 DECISIONS 签注 + AC#1 同步。

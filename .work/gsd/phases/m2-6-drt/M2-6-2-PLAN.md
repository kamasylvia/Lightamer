---
phase: m2-6
plan: "M2-6-2"
title: "ACES 2.0（wave 2）——CAM16 JMh 色貌核（正向+逆向，ACES 2.0 固定观察条件，Swift Float64 + Metal 公共库双落笔）+ ACES 2.0 ODT Float64 参考（JMh 参数化 tonescale + limiting 编码）+ reference gamut compression 内置前置段（aces-core BSD 移植，开关常量默认 on）+ Limiting Space 七选数据表（Rec709/Rec2020/P3-D65/P3-D60/P3-DCI/ProPhoto RGB/Adobe RGB）+ Metal kernel + method 注册口 aces20 臂填充（D1 兑现）+ aces-core 移植署名（NOTICE）"
wave: 2
depends_on: ["M2-6-1"]
autonomous: true
requirements: [M2DRT-03, M2DRT-06]
files_modified:
  - LightamerCore/Sources/Pipe/Drt/Cam16.swift              # 新建：CAM16 JMh 正向/逆向 Float64（ACES 2.0 指定观察条件常数单源；AP1-related 中间空间矩阵随函数族）
  - LightamerCore/Sources/Pipe/Drt/Aces2Reference.swift     # 新建：ACES 2.0 ODT Float64 参考实现（JMh 参数化 tonescale + purity/highlight/shadow 处理 + limiting 编码链；算法结构图头注 = aces-core CTL 转录正本）
  - LightamerCore/Sources/Pipe/Drt/Aces2Limiting.swift      # 新建：Limiting Space 七选数据表（七组 primaries → RGB→XYZ 矩阵 + 编码限制面参数；BSD 数据表 vendored 署名行）
  - LightamerCore/Sources/Pipe/Drt/Aces2Kernels.metal       # 新建：ACES 2.0 compute kernel（CAM16 + ODT + RGC 前置段 + limiting 全内联；参数 MTLBuffer 单 PSO 沿 M2-6-1 KD-4 形态）
  - NOTICE                                                  # 修改：AMPAS aces-core（BSD 风格）署名条目落笔（移植函数清单 + 上游 SHA/版本）
  - Project.swift                                           # 修改：新测试文件登记（checker E2 纪律）
  - Tests/LightamerTests/Aces2MathTests.swift               # 新建（LAYERS，Core 级）：CAM16 往返/锚点 + limiting 表 + RGC 纯函数
  - Tests/LightamerTests/Aces2KernelGoldenTests.swift       # 新建（IOPP，Golden* glob 惯例）：ACES 2.0 kernel vs Float64 参考（探针复用 M2-6-1 生成器）+ method 臂切换
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：两个新测试文件增行
  - .work/gsd/phases/m2-6-drt/M2-6-2-SUMMARY.md             # 新建（收口任务）
  - .work/gsd/phases/m2-6-drt/M2-6-2-DECISIONS.md           # 新建（收口任务）
  - .work/GOAL-STATE.md                                     # 续接点追加（收口任务）
  - .work/LESSONS.md                                        # 如踩坑
---

# Plan M2-6-2 — ACES 2.0（CAM16 JMh 核 + ODT + RGC 前置 + Limiting 七选 + kernel + method 臂填充）

> **性质**：算法 plan——App 层零改动；管线面只动 M2-6-1 已备的 method 分派臂（aces20 stub →
> 真实现）。五块交付：①**CAM16 JMh 色貌核**（正/逆向，ACES 2.0 固定观察条件）；②**ACES 2.0
> ODT Float64 参考**（JMh 参数化 tonescale + limiting——aces-core CTL 为 BSD 风格许可，可带
> 署名直接移植）；③**reference gamut compression 内置前置段**（OQ-4-A：固定前置 stage，开关
> 常量默认 on，非独立 op、非用户参数面、不进节点图）；④**Limiting Space 七选数据表**；⑤
> **Metal kernel + method 注册口 aces20 臂填充**（D-M2-6-CONTEXT-12 的 D1 兑现动作）。规格
> 锚点 = D-M2-6-CONTEXT-3/4（不得重开）+ FEATURE-MAP §5（ACES 2.0 专属节）+ REQUIREMENTS
> M2DRT-03/06。
>
> **执行期精读悬决点**（CONTEXT「夜间授权预案」预告项中属本 plan 的两件，T1-T4 内核读钉死、
> DECISIONS 签注）：①**ACES 2.0 CTL 移植函数清单与数据表经营收**（OQ-3 附注——上游
> aces-core 仓的 CTL transform/lib 函数逐个点名 + vendored 数据表清单 + 上游版本/SHA 入
> DECISIONS）；②PQ/HLG peak→layer 语义中 ACES 侧的 peak 传递（OQ-6 悬决点的 ACES 半边——
> peak nits 进 JMh tonescale limiting 的终式）。**上游获取**：aces-core（github.com/ampas/
> aces-core，BSD 风格许可，`third_party_licenses/aces-core-LICENSE.md` 全文已在 Alcedo 仓
> 在案核验）——执行期经网络拉取 CTL 源码走读（xray 代理可用）；离线兜底 = Alcedo 仓内
> `aces_reference_gamut_compression.h`（GPL 头，只读交叉验证用）+ dctl 内 aces_2_0
> tonescale 分支数值抽检。

## 已定裁决（不得重开）

- **D-M2-6-CONTEXT-3（OQ-3 A）**：aces-core（AMPAS BSD）移植 + v1 子集 = ODT 参数化模型 +
  Limiting 七选；**不落新 LMT 面**（LMT CUBE 已是 Grade 域既有 op）；输入 gamut 恒 linear
  Rec2020（不露 dctl 15 种输入菜单）；HDR peak 路径按 aces-core 规范直实现（**不继承**
  Alcedo v0.2.3 已知损坏项，不读其 metal 移植反推）。
- **D-M2-6-CONTEXT-4（OQ-4 A）**：reference gamut compression = DRT 内置前置段（可开关常量
  默认 on）；不进节点图、不进 18 目录、不占 ownership 面（OpenDRT method 自带 render-space
  purity 处理，无此前置）。
- **D-M2-6-CONTEXT-12（OQ-12 A）**：method 注册口形状 M2-6-1 已落；本 plan 填 aces20 臂 =
  D1 兑现；filmic/sigmoid/agx 仍零注册。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 aces-core 移植边界 = BSD 署名直移植 + v1 函数清单

- **许可面**：aces-core = AMPAS BSD 风格（Licenses/Source/license.txt 全文随上游）——与
  GPLv3 的 OpenDRT **不同**：允许**代码级移植**（保留版权注记 + NOTICE 署名），无需
  clean-room。移植代码头注逐文件带 `Portions Copyright AMPAS; BSD-3-style; see NOTICE`。
  NOTICE 增条目：上游仓 URL + 移植函数清单 + 上游版本/commit SHA。
- **v1 子集函数清单（KD 承诺的「经营收」起算面——执行期对照上游修订增删、DECISIONS 签注
  终清单）**：
  - `ACESlib.Utilities`（色度适应/矩阵工具——与既有 ACESccMath.metal 常数**不重复**，
    引用/复用判定执行期落）；
  - `ACESlib.Tonescale`（JMh 参数化 tonescale——2.0 核心）；
  - `ACESlib.Color_C vocational`/`CAM` 族（CAM16 前向/逆向 + Hellwig 扩展——2.0 的 JMh
    参数化基础）；
  - `ACESlib.LMT` 族中 `Reference Gamut Compression`（ACES 1.3 RGC——KD-3）；
  - ODT 参数化主体（`lib/ACESlib.ODT...` 或 2.0 等价 transform 集——**执行期以上游目录
    实态为准点名**，工作假设 = 2.0 已合入上游 master 的参数化 ODT）。
- **不移植**：RRT 大表（2.0 参数化 ODT 不依赖 1.x RRT 查找面）、全部 LMT 创意族、ACES 1.x
  ODT 逐型号硬编码表——YAGNI（OQ-3-B 拒绝理由的正面表述）。

### KD-2 CAM16 JMh 核 = 双落笔 + 规范锚点

- `Cam16.swift`：CAM16 前向（XYZ → JMh：lightness J / colorfulness M / hue angle h）+
  逆向（JMh → XYZ），ACES 2.0 固定观察条件（白点/适应场/luminous 环境常数——执行期从上游
  CTL 常数转录，单源 + 测试逐常数断言）；含 Hellwig/HKE 修正项（2.0 实装项执行期以上游
  为准）。Metal 侧 = `Aces2Kernels.metal` 公共函数段（同一推导两落笔，M2-6-1 KD-2 纪律
  同款——常数唯一源在 Swift 文件，Metal 禁另立）。
- **锚点（机检）**：往返断言（XYZ→JMh→XYZ ≤1e-6，全域 ramp + 色卡采样）；白点/原色锚点
  （D65 白 → J≈100/M≈0；AP1 原色 h 角对规范表值 ≤1e-4）；执行期另取上游 CTL 单测/注释内
  数值例（如有）抽检 2-3 点（DECISIONS 记点值来源）。
- **working space 衔接**：输入 = working linear Rec2020 → AP0（ACES2065-1）线性转换内置
  kernel 首段（D-M2-6-CONTEXT 衔界面：in_gamut 不露菜单）——矩阵常数 = Rec2020→AP0 色域
  转换（从原色推导，测试断言与 ACESccMath.metal 的 AP1 事实一致性面：AP0/AP1 两矩阵各自
  独立断言，禁互推）。

### KD-3 reference gamut compression 前置段 = 固定 stage 默认 on

- 算法 = ACES 1.3 RGC（P3/Rec709 色域外高饱和收敛：achromatic axis + threshold/limit
  距离压缩幂 1.2——Alcedo `aces_reference_gamut_compression.h:37` 可读形态交叉验证；规范
  正本 = aces-core `lib/ACESlib.LMT.a13.ctl` RGC 段，**BSD 直移植**）。
- **归属形态（OQ-4-A）**：kernel 内固定前置 stage（RGC on/off 为 kernel 参数 buffer 内
  常量，默认 on）；**非**独立 op、无节点图语义、无 ownership 面、无用户参数——面板上无
  对应控件（M2-6-3 面板不暴露）；OpenDRT method 路径**不经过**此段（只 ACES 2.0 kernel
  内置）。
- **测试**：RGC 纯函数（Float64）单测（Gamut 边界外收敛单调 + threshold 内恒等 + 幂参数
  锚点）；kernel golden 含 RGC on/off 两参数点。

### KD-4 Limiting Space 七选数据表

- `Aces2Limiting.swift`：七空间（rec709/rec2020/p3d65/p3d60/p3dci/proPhoto/adobeRGB）各
  一组——primaries xy → RGB→XYZ 矩阵 + 白点 + limiting 编码参数（JMh limiting 边界/
  maxJ 语义随 peak）。数据 = 规范 primaries 数值事实（公开规范表）+ 上游 limiting CTL 常数
  （BSD）——两来源逐行署名注释。
- **测试**：七表完备（枚举驱动）+ 矩阵行/列和与白点映射一致性（RGB 白 → XYZ 白 ≤1e-6）+
  p3d60/p3dci 白点差断言（D60/DCI 白 xy 与规范表值 ≤1e-6）——防转录行错位。

### KD-5 ACES 2.0 ODT Float64 参考 + kernel + method 臂填充

- `Aces2Reference.swift`：`refAces2ODT(record:linearRGB:peak:)` 总入口（与
  `refOpenDRT` 同签名形态——method 无关的统一 golden 接口）：RGC 前置（KD-3）→ AP0 转换
  → CAM16 JMh → tonescale（J 轴 S-curve，peak nits limiting——KD-6）→ M 轴 purity/limiting
  （Limiting Space 七选面，KD-4）→ 逆向 CAM16 → encoding space 线性输出（EOTF 编码仍在
  EotfBox，M2-6-1 KD-4 分离纪律）。头注 = 算法结构图（阶段序照上游 CTL 函数调用序转录，
  注释列上游函数名 + 文件）。
- `Aces2Kernels.metal`：单 compute kernel per-pixel（CAM16+ODT+RGC+limiting 全内联）；
  参数 buffer 化单 PSO（M2-6-1 KD-4 形态照抄）；`limitingSpace`/`peak`/`rgcOn` 经 buffer。
- **method 臂填充（D1 兑现）**：`PixelPipe` 尾段 `DrtMethodBox` 的 aces20 stub 替换为
  真实现分派（M2-6-1 T7 的 `fatalError` stub → kernel 调用）；switch 穷举纪律不变
  （无 default 臂）。**D1 兑现机检**：注册口 = `DrtMethod` 两 case 全部可达 + 面板可见集
  （P3 消费）= `[aces20, opendrt]`；filmic/sigmoid/agx 零注册断言保持。
- **golden（IOPP）**：M2-6-1 探针生成器复用（ramp/色卡网格/极饱和三件套）× 参数点
  （rec709+g22+100（SDR 基线）/ rec2020+st2084+1000（HDR 基线）/ p3d65+g22+100（P3 基线）/
  limiting 七空间各一遍（探针小图）+ RGC on/off）vs Float64 参考（M2-6-1 KD-8 容差谱
  同款；升级评估点流程同款——级联更深（CAM16 往返 + tonescale + limiting）超 1e-5 时按
  值域分级 DECISIONS 签注，禁静默放宽）。
- **HDR peak 路径（KD 必答，OQ-7-A ACES 半边）**：peak ∈ [100,1000] 进 JMh tonescale 的
  limiting 亮度锚（上游 2.0 语义：peak 决定 J_max/高光 rolloff 锚——终式执行期从 CTL 钉死、
  DECISIONS 签注）；**不读 Alcedo metal 反推**（v0.2.3 已知损坏——CONTEXT 非目标明文）；
  SDR（非 HDR EOTF）下 peak 仍参与 tonescale（上游行为如实——测试记录 peak 100 vs 1000
  在 SDR 编码下的输出差存在性，防「peak 只在 HDR 生效」误实现）。

### KD-6 与 M2-6-1 资产的关系（复用/不重复）

| 资产 | 关系 |
|---|---|
| `DrtEotf.swift`/`DrtEotfKernels.metal` 七函数 | **共享**（EOTF 编码在 EotfBox，method 无关）——零重复 |
| `ACESccMath.metal` AP1 矩阵 | **引用判定执行期落**（KD-2）——AP0 矩阵独立新增，禁互推 |
| 探针生成器/golden 容差谱 | **复用**（测试 helper 提取共用或复制最小面——执行期判定，DECISIONS 记） |
| `DrtUniforms` buffer 形态 | ACES 2.0 独立 struct（参数面不同），形态约定照抄 |
| `TerminalTailPolicy`/键折叠 | 零改动（method 只是 DrtMethodBox 内部分派） |

## read_first

1. `.work/gsd/phases/m2-6-drt/M2-6-CONTEXT.md`——D3/D4 裁决正本 + Integration Points。
2. `.work/gsd/phases/m2-6-drt/M2-6-1-PLAN.md` KD-2/KD-4/KD-6/KD-8 + M2-6-1-SUMMARY.md
   （容差实配值/探针生成器位置/PSO 编译基线——本 plan 复用面）。
3. `LightamerCore/Sources/Pipe/Drt/`（M2-6-1 产物全部——DrtEotf/OpenDrtReference/
   OpenDrtKernels/DrtPresets 邻位参照）。
4. aces-core 上游（BSD，可移植）：`github.com/ampas/aces-core` CTL 源（ACESlib.Utilities /
   Tonescale / CAM 族 / LMT.a13 RGC 段 / ODT 参数化 transform）——执行期拉取走读；离线兜底
   = Alcedo 仓 `src/include/edit/runtime/aces_reference_gamut_compression.h`（GPL，只读
   交叉验证）。
5. `LightamerIOP/Sources/ACEScc/ACESccMath.metal`——AP1 常数现位（KD-2 引用判定）。
6. `Tests/LightamerTests/DrtKernelGoldenTests.swift`（M2-6-1 产物——探针生成器复用源）+
   `Scripts/test-direct.sh` 头注。

## 纪律（强制）

1-8 全同 M2-6-1 纪律（提交/构建/测试基线 2327+P1 增量/边界/config 检查/架构红线/测试登记/
收口核对/枚举穷举）。**本 plan 增补**：

9. **架构红线**：`PixelPipe.swift` 本 plan diff 半径 = aces20 stub 臂替换（分派函数内
   数行——禁触尾段装配/键折叠/策略枚举）；`PipeCacheKey.swift`/`HistoryStack.swift`/
   sidecar/App 层零 diff（method 切换不影响键面——method 是 DrtRecord 字段，hash 已折叠）。
10. **上游移植署名纪律**：每个移植函数头注带上游文件名 + AMPAS 版权行；NOTICE 条目与
    代码清单同 commit；GPL 交叉验证源（Alcedo hpp）零复制。

## Tasks

### T1 CAM16 JMh 色貌核

- **read_first**：上列 1/4/5。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/Cam16.swift`：KD-2 全量（前向/逆向 + 观察条件
     常数单源 + Hellwig 项终式签注）。
  2. 新建 `Tests/LightamerTests/Aces2MathTests.swift`（本任务先建）：往返 ≤1e-6（ramp +
     色卡采样）+ 白点/原色锚点 ≤1e-4 + 常数逐个断言 + 上游数值例抽检（DECISIONS 记来源）。
  3. 测试登记两处（LAYERS）。
- **验收标准**
  - [ ] 往返/锚点/常数断言全绿；观察条件终式与 Hellwig 项入 DECISIONS。
  - [ ] 全套回归 `0 fail`（基线 2327 + P1 增量）。

### T2 Limiting Space 七选数据表 + RGC 纯函数

- **read_first**：上列 1/4（limiting CTL + RGC 段）。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/Aces2Limiting.swift`：KD-4 全量（七组表 + 署名
     注释）+ RGC Float64 纯函数族（KD-3）。
  2. `Aces2MathTests.swift` 续：七表完备 + 白点映射一致性 + p3d60/p3dci 白点锚 + RGC
     （threshold 内恒等 / 边界外收敛单调 / 幂 1.2 锚点 / Alcedo hpp 形态交叉验证记录）。
- **验收标准**
  - [ ] 七表/RGC 断言全绿；数据来源逐行署名在册。
  - [ ] 全套回归 `0 fail`。

### T3 ACES 2.0 ODT Float64 参考实现

- **read_first**：上列 1/2/4。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/Aces2Reference.swift`：KD-5 全量（阶段函数族 +
     结构图头注 + `refAces2ODT` 总入口 + peak 传递终式签注）。
  2. `Aces2MathTests.swift` 续：tonescale 单调性（J 轴全域）+ 端点有界无 NaN + peak 差
     存在性断言（100 vs 1000）+ SDR 下 peak 仍生效断言（KD-5 必答）+ 上游数值例抽检。
- **验收标准**
  - [ ] 上述断言全绿；CTL 移植函数清单终版（KD-1）入 DECISIONS（含上游版本/SHA）。
  - [ ] 全套回归 `0 fail`。

### T4 ACES 2.0 Metal kernel + golden + method 臂填充

- **read_first**：上列 2/3/6。
- **action**
  1. 新建 `LightamerCore/Sources/Pipe/Drt/Aces2Kernels.metal`：KD-5 kernel 全量（CAM16
     公共段 + RGC 前置 + ODT + limiting 内联；参数 buffer 单 PSO）。
  2. `PixelPipe.swift`：aces20 stub 臂替换真实现（半径 = 分派函数内数行）。
  3. 新建 `Tests/LightamerTests/Aces2KernelGoldenTests.swift`（IOPP）：KD-5 golden 矩阵
     （探针复用 × 参数点含 limiting 七空间 + RGC on/off）+ 位精确确定性 + method 切换
     （同 record 换 method → 输出变 + 键稳定各自成立）+ PREVIEW/FULL 双路径烟测。
  4. 容差超 1e-5 时按 M2-6-1 KD-8 升级评估点流程处置。
  5. NOTICE aces-core 条目落笔 + 测试登记两处 + `tuist generate`（新目录覆盖 T1-T4）。
- **验收标准**
  - [ ] golden 全绿（或签注分级终谱）；method 臂切换断言绿；`git diff PixelPipe.swift`
        逐 hunk 核（半径 = stub 替换）；NOTICE/登记闭环。
  - [ ] 全套回归 `0 fail`。

### T5 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前报备）。
  2. 落盘 `M2-6-2-SUMMARY.md`（测试数/容差终谱/kernel 编译耗时/limiting 七空间 golden
     结果表）+ `M2-6-2-DECISIONS.md`（CTL 移植函数终清单 + 上游 SHA/peak 终式/Hellwig 项/
     容差分级依据/探针 helper 复用形态）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-6-2 完成 + 下一步 = M2-6-3）；LESSONS 如踩坑。
  4. `git diff --stat` 核对文件边界。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | CAM16：往返 ≤1e-6（ramp+色卡）；白点/原色锚 ≤1e-4；观察条件常数逐个断言；逆向=前向精确逆 | Aces2MathTests |
| 2 | Limiting 七选：七表完备（枚举驱动）+ 白点映射一致性 ≤1e-6 + p3d60/p3dci 白点锚 ≤1e-6 + 来源逐行署名 | Aces2MathTests |
| 3 | RGC：threshold 内恒等（容差 0，-0/+0 视相等）+ 边界外收敛单调 + 幂 1.2 锚 ≤1e-6；OpenDRT 路径不经过此段（分派面断言） | Aces2MathTests + Aces2KernelGoldenTests |
| 4 | ODT 参考：J 轴 tonescale 单调 + 端点有界无 NaN + peak 100/1000 输出差存在 + SDR 下 peak 生效；CTL 函数终清单入 DECISIONS | Aces2MathTests + DECISIONS |
| 5 | kernel golden：探针 × 参数点（含 limiting 七空间 + RGC on/off）≤1e-5 p99.9（或签注分级终谱）+ 位精确确定性 + PREVIEW/FULL 双路径 | Aces2KernelGoldenTests |
| 6 | method 臂：aces20 stub 替换为真实现；switch 穷举无 default；`DrtMethod` 两 case 全可达；filmic/sigmoid/agx 零注册断言保持（Registry grep 雷新增） | Aces2KernelGoldenTests + grep |
| 7 | 署名：NOTICE aces-core 条目（URL/函数清单/版本或 SHA）与移植代码同 commit；每移植函数头注 AMPAS 行；GPL 交叉验证源零复制 | `git grep` NOTICE + 抽查头注 |
| 8 | `PipeCacheKey.swift`/sidecar/`HistoryStack.swift`/App 层零 diff；`PixelPipe.swift` diff = stub 臂替换半径 | `git diff --name-only` + 逐 hunk |
| 9 | 全套回归 0 fail，计数 ≈ 2327 + P1 增量 + 22..35 | test-direct.sh --all TOTAL 行双读 |
| 10 | diff 边界 == 申报文件集；测试登记闭环（两文件 × Project.swift + BUNDLE-MAP 双命中） | `git diff --stat` + `git grep` |

## 风险与边界

- **上游可用性**：aces-core CTL 需网络拉取——离线时 RGC 兜底 = Alcedo hpp 只读交叉验证 +
  dctl aces_2_0 tonescale 分支数值抽检（GPL 数值事实可对照）；CAM16/ODT 主体**无 GPL 兜底**
  （2.0 参数化只在上游）——执行期确认网络可用再开工 T1（不可用 = E3 停，报 orchestrator）。
- **CAM16 逆向多解/迭代收敛**：JMh→XYZ 逆向含迭代（CAM16 逆 Aab 搜索）——Float64 参考与
  Metal 均需固定迭代数/收敛阈保证位精确确定性（同输入两次逐字节断言兜底）；迭代常数单源。
- **Float64 vs GPU 容差谱**：级联更深（AP0 转换 + CAM16 往返 + tonescale + limiting）——
  M2-6-1 KD-8 升级评估点流程预启用；CAM16 迭代在 float32 的收敛域差异是重点观察段
  （极饱和探针）。若某段结构性超谱（>1e-3），回查阶段序/迭代实现，非容差问题。
- **PSO 编译时间**：ACES kernel 与 OpenDRT 同为全内联大 kernel——观察行入 SUMMARY
  （M2-6-1 风险节同口径）。
- **2.0 上游形态不确定度**：aces-core 的 2.0 transform 组织（单文件/多文件/参数表形态）
  以拉取实态为准——KD-1 清单是起算面非承诺面，DECISIONS 签注终清单即合规。
- **不继承 Alcedo 损坏项**：HDR peak 路径只读上游规范/CTL——发现 Alcedo metal 实现与上游
  冲突时以上游为准（与 OpenDRT「以 dctl 为准」的对照源方向相反，此处 = aces-core，注意
  勿混淆）。
- **基线上移**：起算基线 = M2-6-1 验收后总数（2327 + P1 增量）；本 plan 预计 +22..35。

## 提交约定

- T1 `feat(core): cam16 jmh color appearance core`
- T2 `feat(core): limiting space tables and gamut compression math`
- T3 `feat(core): aces 2.0 odt float64 reference`
- T4 `feat(core): aces 2.0 metal kernel and method dispatch`
- T5 `docs(m2-6): close out plan 2 aces 2.0`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

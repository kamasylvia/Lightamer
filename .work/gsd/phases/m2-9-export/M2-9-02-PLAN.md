---
phase: m2-9
plan: "M2-9-02"
title: "ICC=DRT 强制联动渲染链（wave 2a）——DrtOutputColorSpace 映射（encodingSpace×EOTF→CGColorSpace，13-2 资产复用）+ ExportChainBuilder DRT 腿（.drt 尾段重放替换 gamma+colorout 对，OQ-7 A）+ PixelPipe 导出尾格式 float 覆写缝（display 路径零漂移）+ ExportRenderer/Queue DRT 载体扩容 + DRT 导出 E2E golden（11-02 六格式矩阵零漂移红线）"
wave: 2
depends_on: ["M2-9-01"]
autonomous: true
requirements: [M2EXP-04]
estimated_new_tests: 24
bundles: [Export]
files_modified:
  - LightamerCore/Sources/Export/DrtOutputColorSpace.swift        # 新建：DrtEncodingSpace×DrtEotf→CGColorSpace 穷举映射（PQ/HLG 系统空间 + 幂gamma CalibratedRGB + peak 注记）
  - LightamerCore/Sources/Export/ExportChainBuilder.swift         # 修改：exportDrtChain 纯函数（additive；既有 exportChain 逐字节冻结）
  - LightamerCore/Sources/Export/ExportRenderer.swift             # 修改：Request 增 drtTail: DrtTailParams? + 渲染腿传 terminalTail + exit 腿 DRT identity 面
  - LightamerCore/Sources/Export/ExportQueue.swift                # 修改：Job/enqueue additive drtTail 载体（引擎体零 diff——pump/cancel/retry/generation 语义不动）
  - LightamerCore/Sources/Pipe/PixelPipe.swift                    # 修改：尾格式导出覆写缝（additive 属性 + tailPixelFormat .drt 分支 consult 一行——display 路径逐字节零漂移）
  - Tests/LightamerTests/DrtOutputColorSpaceTests.swift           # 新建【Export】
  - Tests/LightamerTests/ExportDrtChainTests.swift                # 新建【Export】
  - Tests/LightamerTests/ExportDrtTailE2ETests.swift              # 新建【Export】
  - Project.swift                                                 # 修改：新测试文件登记
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt    # 修改：双登记
---

# Plan M2-9-02 — ICC=DRT 强制联动渲染链（wave 2a）

> **性质**：本 phase 风险核心 plan——把 OQ-7 A（输出 ICC 与本图 DRT 编码强制联动，
> 五菜单退役、chain 走 `.drt` 尾段重放、输出编码即 DRT 编码）落进导出链，同时背
> **六格式 golden 矩阵（11-02）零漂移**红线。核心发现（research §4 + 源码亲核）：
> `RenderPipeline.process`/`processComposite` **已有** `terminalTail: TerminalTailPolicy
> = .sdrGamma` 参数（PixelPipe.swift:1587/1631，注释明言「EXPORT face 从不设 tail」
> ——缝即为此刻预留）；pipe 的 `.drt` 策略已实现完整终端降级（colorout/gamma/
> borders/watermark + post-four 出主链，尾段 `[DrtMethodBox] → [EotfBox] → borders →
> watermark` 重放，PixelPipe.swift:236-257）——**导出侧缺的只是载体与格式覆写**。
> 唯一新 Core 缝 = 尾段终平面格式：display 尾按 EOTF 分档（SDR→bgra8/16F），导出
> 尾必须恒 float32（quantizer 拥有 [0,1] 钳与位深分档，OQ-8 A 钳位口径不变）。

## 已定裁决（硬约束，不得重开）

- **OQ-7（A：强制联动）**：M2 导出档 chain 从「剔 gamma + 覆写 colorout 对」切换为
  `.drt` 尾段重放；输出编码 = DRT 编码（space/EOTF 即 DRT record 值）；EMBED/OMIT
  checkbox = M2-9-01 已落 `embedICC`（编码消费在 03）。legacy 五空间路径
  （`drtOutput == nil`）**逐字节冻结**——既有 11-02 六格式 golden、E3 双态守卫、
  ExportPipeTests/ExportRendererE2ETests 全量零修改全绿。
- **OQ-8（A：v1 钳位维持）**：PQ/HLG 编码图导出 = 像素经既有 [0,1] 量化钳（HDR 亮度
  压 SDR 白），ICC 如实标 EOTF（`ExportQuantizer` **零 diff**——封存面）；真 HDR
  容器 = V2 UltraHDR（ALCE-02）。
- **borders/watermark 恒 EOTF 后**（m2-6 红线延续）：导出 DRT 腿的印框重放顺序由
  pipe 尾段既有保证（E2 guard），本 plan 的 E2E 断言结构顺序不破坏。
- **D-M2-9-CONTEXT-2（队列引擎零改动）**：`ExportQueue` 仅 additive 载体（Job 字段 +
  enqueue 增参 + snapshot 透传）；pump/cancel/retry/generation/并发 1 语义体零 diff。
- **App 装配点接线**（D-M2-9-CONTEXT-4）：`instancesOverride` 与 `drtTail` 的**构造**
  在 App（M2-9-04）；本 plan 只保证 Core 载体缝 + 渲染消费面正确。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 `DrtOutputColorSpace`（新 Core 纯函数，穷举无 default）

- `drtOutputColorSpace(space: DrtEncodingSpace, eotf: DrtEotf) throws -> CGColorSpace`：
  - **HDR（st2084/hlg）**：系统 PQ/HLG 空间按 space 分派——rec2020 →
    `kCGColorSpaceITUR_2100_*` 族；p3d65+st2084 → P3 PQ 系（可用系统名或 ICC 数据
    路径，执行以 `CGColorSpace` 可用性实测定）；xyz + HDR = typed 拒绝（组合非法）。
  - **SDR 幂 gamma（gamma22/gamma26/bt1886/gamma18）**：
    `CGColorSpaceCreateCalibratedRGB`（primaries 表按 space：rec709/p3_d65/p3_d60/
    p3_dci/rec2020 常量表；xyz→XYZ primaries 常量）+ gamma 分量（bt1886 = γ2.4 近似
    或 Lb=0 精确式——m2-6-1 DECISIONS 的 BT.1886 终式对照，执行裁决记录）。
  - **linear**：各 space 的线性变体（Rec709 linear → extendedLinearSRGB 系 /
    Rec2020 linear 等，13-2 `linearCGColorSpace` 先例同族）。
- **peak 不入 ICC**（v1 面）：peakLuminance 在入队闸门校验（03）+ 渲染消费
  （EotfBox record 内），ICC 标注只承 space+TRC——ALCE-02/UltraHDR V2 预留，DECISIONS
  记录边界。`legacy`/无效组合 typed 抛 `AppError.invalidParameter`。
- 穷举纪律：space×eotf 笛卡尔集 switch 无 default（`legalEOTFs(for:)` 外组合显式
  typed 拒绝——DrtRecord 模型层允许持久 linear/gamma18，映射层全量可达）。

### KD-2 `ExportChainBuilder.exportDrtChain`（additive 纯函数）

- `exportDrtChain(from records: [ModuleInstance], space: DrtEncodingSpace, eotf:
  DrtEotf) -> Built`：`instances` = records **verbatim**（gamma/colorout 的降级由
  pipe `isTerminalTailSkipped` 在管道内做——builder 不再预剔，避免双处语义漂移）；
  `exportTargetOverride` = KD-1 映射（exit 腿 identity 的 source/target）；
  `coloroutOverridden = true`（identity 语义复用既有 exit 面）；`target` 载体记
  DRT 派生（Built.target 类型如需扩 = additive 枚举臂，穷举补全）。
- **既有 `exportChain(from:target:linearVariant:)` 函数体零 diff**（legacy 面）；
  `isLinearVariant` 不动——DRT 档下 TIFF 32f 的「线性变体」专属 legacy 语义：
  **DRT 联动档 TIFF 32f = DRT EOTF 编码值 float32**（「输出编码即 DRT 编码」字面；
  DECISIONS 记录该语义边界，scene-referred TIFF 手作需求 = legacy 档保留可达）。

### KD-3 PixelPipe 导出尾格式覆写缝（本 plan 唯一 Pipe diff）

- additive internal 属性（如 `tailFormatFloatOverride = false`）+ `tailPixelFormat`
  的 `.drt` 分支前置 consult 一行（override 为真 → 恒 `WorkingSpace.pixelFormat`）。
- `RenderPipeline.process`/`processComposite` 增同名透传参数（默认 false——**全部
  既有调用点默认实参零改动**）。
- display 路径零漂移门：`DrtTailTests`（含尾格式分档断言）+ `AIMaskPlaneFormatTests`
  + Drt 系全族测试**零修改全绿**为硬 AC。

### KD-4 renderer/queue 载体扩容

- `ExportRenderer.Request` 增 `drtTail: DrtTailParams? = nil`（additive init 默认参）。
  renderStage：非 nil → step 4 装配切 `exportDrtChain`、step 6 两渲染入口传
  `terminalTail: .drt(drtTail)` + 尾格式覆写真、step 7 exit 腿 source/target =
  `built.exportTargetOverride`（identity）；step 8 quantizer 不动（钳位红线）。
- `ExportQueue.ExportJob` 增 `drtTail` 透传 + `enqueue(images:variants:
  destinationDirectory:instancesOverride:editorSignature:drtTails:)` 增参（默认 nil；
  per-image 数组与 images 等长——nil 或逐图 nil = 引擎零感知）。`StageOutput`/
  snapshot 面不动（DRT 不进 UI 四态）。
- `ExportYiyinInjector` 缝零 diff（DRT 尾段的 borders/watermark 重放读 resident
  boxes——注入器产出的 boxes 语义不变；yiyin+DRT 并存 E2E 一条钉死）。

## read_first

1. `M2-9-CONTEXT.md` 裁决记录 + D-4/OQ-7/OQ-8 正文；`RESEARCH-NOTES.md` §2.2/§2.3/§4
   （依赖面四条 + `.drt` 尾段接线题）。
2. `LightamerCore/Sources/Pipe/PixelPipe.swift`：:130-160（terminalTail 政策）/
   :236-257（isTerminalTailSkipped）/ :269-310（tailPixelFormat .drt 分支）/
   :864-920（runDrtTailLeg）/ :1180-1300（DrtTailParams/DrtTailDisplay/DrtTailAssembly）
   / :1587-1668（RenderPipeline.process/Composite 签名）。
3. `LightamerCore/Sources/Export/ExportChainBuilder.swift` 全文 + `ExportRenderer.swift`
   step 4/6/7（:249-333）+ `ExportQueue.swift` Job/enqueue（:49-232）。
4. `LightamerCore/Sources/Graph/DrtRecord.swift`——`DrtEncodingSpace`/`DrtEotf`/
   `legalEOTFs`/`isHdrEncoding`（穷举域正本）。
5. `LightamerCore/Sources/Foundation/DisplayProfile.swift`——13-2 资产
   （exact-TRC parser/`LinearVariantCache`/linear 变体先例——KD-1 复用面）。
6. `.work/gsd/phases/m2-6-drt/M2-6-3-DECISIONS.md` D4/D9（BT.1886 终式 + 尾平面格式
   修正先例）；`phases/11-export-pipeline/11-02-PLAN.md`（golden 矩阵红线正本）。

## 纪律（强制）

1. 提交/边界/收口纪律同 M2-9-01（§纪律 1/3/6）。
2. **回归红线（本 plan 灵魂）**：11-02 六格式 golden 矩阵 + E3 双态守卫 +
   ExportPipeTests/ExportRendererE2ETests/ExportPhaseE2ETests + DrtTailTests 全族
   **零修改全绿**；`ExportQuantizer.swift`/`ExportQueueContract.swift` 零 diff。
3. 测试全部【Export】bundle；双登记闭环；全套基线 2577/16/0。
4. GPL 纪律同 01（Alcedo `export_icc_profile_resolver.cpp` 只读对标行为，不抄码）。

## Tasks

### T1 DrtOutputColorSpace 映射（KD-1）

- **action**：新建映射文件 + primaries 常量表 + 穷举 switch；测试：全 space×eotf
  笛卡尔可达性（legal 集 = 成功 + 非法组合 typed）+ 幂 gamma 空间 primaries 锚
  （CGColorSpace 读回 primaries 近似比对 ≤1e-6）+ HDR 系统空间名断言 + linear 变体
  identity（13-2 T6 同款）。
- **验收标准**
  - [ ] 笛卡尔全集行为测试绿（无 default switch，编译期断穷举）；非法组合 typed。
  - [ ] zero 新依赖（纯 CoreGraphics）。

### T2 exportDrtChain + renderer/queue 载体（KD-2/KD-4）

- **action**：builder 新函数 + Request/Job/enqueue additive 载体 + renderStage 分派
  （drtTail 分支切装配/terminalTail/exit identity）+ 测试（builder 纯函数：verbatim
  instances/override=映射/identity 语义；renderer 级：合成 sidecar + drtTail 载体
  E2E 出图非空 + destination 命名不变）。
- **验收标准**
  - [ ] legacy 路径（drtTail=nil）既有测试族零修改全绿（`git diff` 测试目录零 hunk）。
  - [ ] DRT E2E：SDR（rec709+gamma22）与 HDR（rec2020+st2084）各一景出图成功 +
        量化钳断言（HDR 值域 [0,1]）。

### T3 PixelPipe 尾格式覆写缝（KD-3）

- **action**：additive 属性 + 一行 consult + RenderPipeline 透传参数；测试：DRT 导出
  E2E 读回面宽断言（输出 plane 位深 = 格式档而非 bgra8——L014 fence 读回纪律）+
  display 尾格式分档既有断言全绿零改。
- **验收标准**
  - [ ] `git diff PixelPipe.swift` 仅 additive 属性 + 一行 consult + RenderPipeline
        签名增参三处；DrtTailTests/AIMaskPlaneFormatTests 零修改全绿。
  - [ ] TIFF 32f DRT 档出图 = 编码值 float32（KD-2 语义边界测试钉）。

### T4 yiyin×DRT 并存 + 波次收尾

- **action**：yiyin variant + drtTail 并存 E2E（印框在 EOTF 后——输出尺寸含边框 +
  尾段顺序结构断言）+ 全 Export bundle 终跑 + `git diff --stat` 对表 + DECISIONS
  底稿（KD-1 bt1886 取式 + peak-ICC 边界 + TIFF32f 语义边界 + HDR P3 系统空间
  实测选择）。
- **验收标准**
  - [ ] yiyin×DRT E2E 绿（印框不 tone-map 语义保持）。
  - [ ] Export bundle 0 fail；新增双登记；diff 边界 == front-matter。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 11-02 六格式 golden + E3 双态 + Export 渲染/队列既有测试族零修改全绿 | 测试目录零 diff + bundle 行 |
| 2 | `ExportQuantizer`/`ExportQueueContract`/`ExportChainBuilder.exportChain` 函数体零 diff | `git diff` 逐 hunk |
| 3 | space×eotf 穷举映射无 default；非法组合 typed 拒绝 | 源码 grep + 测试 |
| 4 | DRT 导出 E2E：SDR/HDR/launch TIFF32f/yiyin 并存四景出图成功 | 测试名 |
| 5 | HDR 输出值域 [0,1]（钳位口径，OQ-8 A） | 测试断言 |
| 6 | PixelPipe diff = 三处 additive（属性/consult/透传参数）；display 尾格式断言零漂移 | `git diff` + DrtTailTests |
| 7 | ExportQueue 引擎体（pump/cancel/retry/generation/concurrency）零 diff，仅 additive 载体 | `git diff` 逐 hunk |
| 8 | Export bundle 0 fail；双登记闭环 | bundle 行 + 两文件 grep |

## 风险与边界

- **HDR P3 系统空间缺口**：p3d65+st2084 若无现成系统命名空间 → ICC 数据构造路径
  （CGColorSpace(iccProfileData:)），实测结论入 DECISIONS；xyz+HDR 组合 typed 拒绝
  是预期行为非缺陷（DrtEncodingSpace.xyz + HDR 无意义组合，UI 层
  legalEOTFs 不可达）。
- **identity 面回归**：DRT 档 exit 腿 source=target=映射空间——若 E3 形态守卫抓出
  双转换（色偏），根因排查顺序 = builder override → pipe 尾降级 → exit source 选择；
  禁止跳过 E3 断言（机检红线）。
- **16F 尾平面精度**：HDR 档尾平面 rgba16Float（display 先例）在导出覆写下保持
  float32 working——若有 16F 中间假设泄漏（blit 链），以 T3 位深断言暴露，修复限
  缝内（不重写尾格式策略）。

## 提交约定

- T1 `feat(m2-9): drt output color space mapping for export encoding`
- T2 `feat(m2-9): export drt chain assembly and renderer/queue carriers`
- T3 `feat(m2-9): export tail plane float override seam`
- T4 `test(m2-9): yiyin-drt coexistence e2e and wave reconciliation`
- 全英文；body 写 what+why（含零漂移红线兑现）；不 push。

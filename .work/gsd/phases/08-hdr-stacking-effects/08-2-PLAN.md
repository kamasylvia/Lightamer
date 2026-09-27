---
phase: 8
plan: "08-2"
title: "创意效果簇 A（W1，与 08-1 正交并行）：vignette 68.0（dt 参数面 verbatim + 单 kernel OpenCL 形直译 + dither 不移植）+ grain 65.0（3-octave simplex verbatim + paper_resp LUT + luma 域注入 + StableHash 确定性种子 L013）+ bloom 61.0（threshold→级联 blur→screen 三段 + 线性域阈值映射 + HDR >1.0 零特判）——各含 CPU float64 参考实现 + dt 数值锚 golden + 面板四件套 + zh catalog"
wave: 1
depends_on: []
autonomous: true
requirements: [IOP-FX-01, IOP-FX-02, IOP-FX-03]
files_modified:
  - LightamerIOP/Sources/Vignette/VignetteModule.swift          # 新建：dt vignette.c:57-72 全参数面（scale/falloff/brightness/saturation/center/whratio/shape/unbound/autoratio）+ IOPModule 实现（identity 快速路径走 L031 路由）
  - LightamerIOP/Sources/Vignette/VignetteKernels.metal         # 新建：单 kernel 直译 extended.cl:308-349（cplen 幂距 + 线性 falloff + 加/乘亮度 + 均值去饱和；**取 OpenCL 形**——cosine 平滑恒用，dt CPU/OpenCL 分歧裁决 §17.3）
  - LightamerIOP/Sources/Vignette/VignetteReference.swift       # 新建：CPU float64 同式直译（golden 正本）
  - LightamerIOP/Sources/Grain/GrainModule.swift                # 新建：scale(≈ISO)/strength/midtones_bias 三滑杆 + seed 派生 StableHash(canonicalParamsBytes ⊕ imageID-UUID-bytes)（L013）+ luma 域注入（Rec2020 luma 系数）
  - LightamerIOP/Sources/Grain/GrainKernels.metal               # 新建：3-octave simplex（f={0.4910,0.9441,1.7280}/a={0.2340,0.7850,1.2150} verbatim + ×32 缩 [-1,1]）+ paper_resp LUT 预烘焙（GRAIN_LUT_DELTA_MAX=2.0/MIN=0.0001/PAPER_GAMMA=1.0）+ GRAIN_SCALE_FACTOR=213.2 ISO 标注
  - LightamerIOP/Sources/Grain/GrainReference.swift             # 新建：float64 simplex 参考实现（与 kernel 同 seed 逐位比对正本）
  - LightamerIOP/Sources/Bloom/BloomModule.swift                # 新建：threshold/size/strength 参数面（bloom.c:47-51）+ 三段编排 + 线性域阈值映射（L_lin=luminance/4.0 参数化白锚、thr_lin=(threshold/100)³、strength 指数提亮形保留）
  - LightamerIOP/Sources/Bloom/BloomKernels.metal               # 新建：threshold kernel（bloom.cl:22-38 直译）+ 降采样级联 blur（÷8 box → 1/8 分辨率小 σ gaussian → bilinear 上采；P5 实测 0.29s vs 1.87s 择优）+ screen blend（1−(1−a)(1−b) 线性域）
  - LightamerIOP/Sources/Bloom/BloomReference.swift             # 新建：float64 三段参考实现（golden 正本）
  - LightamerIOP/Sources/Registry.swift                         # populate +3（vignette/grain/bloom）
  - App/Sources/Lightamer/UI/Inspector/VignettePanelView.swift  # 新建：参数滑杆组（D-H1 三件套）
  - App/Sources/Lightamer/UI/Inspector/GrainPanelView.swift     # 新建：scale(ISO 标注)/strength/midtones_bias（D-H1 三件套）
  - App/Sources/Lightamer/UI/Inspector/BloomPanelView.swift     # 新建：size/threshold/strength（D-H1 三件套）
  - App/Sources/Lightamer/UI/Inspector/IOPPanelProvider.swift   # +3 席（L010 identifier）
  - Resources/Localizable.xcstrings                             # vignette/grain/bloom zh+en 键（L025——zh 标签首屏必查）
  - Tests/LightamerTests/VignetteTests.swift                    # 新建：falloff 曲线采样点 1e-6 容差/brightness ± 支路/unbound 裁剪/层蒙版局部化
  - Tests/LightamerTests/GrainTests.swift                       # 新建：同 seed 同参逐字节确定性/同参异图必异/float64 逐位比对/功率谱对照
  - Tests/LightamerTests/BloomTests.swift                       # 新建：点光源光晕半径/幅值/阈值线性映射数值锚/HDR >1.0 行为/float64 三段比对
  - .work/gsd/phases/08-hdr-stacking-effects/perf.md            # 60fps preview 预算复核记录（三 iop 既有基线不回退）
  - .work/gsd/phases/08-hdr-stacking-effects/08-2-SUMMARY.md
  - .work/gsd/phases/08-hdr-stacking-effects/08-2-DECISIONS.md
  - TODO.md                                                     # 08-2 勾选
  - LESSONS.md                                                  # 如踩坑
---

# Plan 08-2 — 创意效果簇 A：vignette + grain + bloom（W1，与 08-1 正交并行）

> 背景：效果簇三件全部 **dt 参数面 verbatim 移植**（dt 对标 LOCKED；D-08-CONTEXT-5/6/7），槽位
> `V50Order.swift` 预留在表（bloom 61.0 :147 / grain 65.0 :151 / vignette 68.0 :161）——接入 = 注册 +
> kernel，零表迁移。全部 < `terminalTailFloor` 70.0（`LayerCompositeDriver.swift:110`）→ 层蒙版资格
> 天然成立（Phase 7 层栈 API 零新机制消费）。golden 形状 = dt 参考采样点容差断言（CPU float64 双写
> 正本，12-5 遗留#5 口径）；grain 另加确定性双断言（缓存键 + golden 双前提，D-08-CONTEXT-6）。
> 三任务互相独立可任意序；T4 全簇接线复核，T5 收口。

## read_first

1. `.work/gsd/phases/08-hdr-stacking-effects/08-RESEARCH.md`——§8（grain 种子终表 + 缓存键无漏钉 +
   **3-octave simplex 正本**（非白噪声——CONTEXT 措辞精化 §17.1）+ luma 域适配）、§9（bloom dt 正本
   域 + 线性域映射终式 + 级联 blur 择优 + HDR >1.0 零特判）、§14 效果簇总表（vignette/grain/bloom
   三行 = 本 plan 移植规格正本：dt file:line + kernel 规格 + 参考实现 + golden 断言）、§17.3（vignette
   CPU/OpenCL 分歧取 OpenCL 形）
2. `.work/gsd/phases/08-hdr-stacking-effects/08-CONTEXT.md`——D-08-CONTEXT-5（vignette verbatim +
   dither 不移植）、D-08-CONTEXT-6（grain scale≈ISO 合一 + 确定性种子）、D-08-CONTEXT-7（bloom 三段
   verbatim + 线性阈值适配）、验证与红线节（效果 iop golden + grain 双断言 + L025 面板）
3. Darktable 移植正本（只读）：`src/iop/vignette.c`（:57-72 参数面 / :694 process / :715-820 数学 /
   :790-795 CPU cosine 分歧位）+ `data/kernels/extended.cl:308-349`（vignette kernel——**移植正本**）；
   `src/iop/grain.c`（:292-327 simplex f/a 表 / :312 ×32 缩域 / :331-345 paper_resp LUT / :44,540-543
   GRAIN_SCALE_FACTOR + ISO 语义 / :450 zoom 式 / :494 只写 out[0] luma 域）；`src/iop/bloom.c`（:47-51
   参数 / :135-180 三段 / :140 rad 式 / :151-180 L 域数学）+ `data/kernels/bloom.cl:22-38`
   （bloom_threshold）
4. 既有 iop 文件对模板：`LightamerIOP/Sources/Monochrome/`（Module+Kernels 双文件最简形）+
   `LightamerIOP/Sources/Soften/`（creative 系先例）——新模块逐行对位
5. `LightamerIOP/Sources/Registry.swift:21+`——`populate` 注册惯例（await register(opName:){id in}）
6. 面板先例：`App/Sources/Lightamer/UI/Inspector/SkinSmoothPanelView.swift`（07-2 最新三滑杆面板 +
   IOPPanelProvider 注册位 + D-H1 三件套）+ `Lessons` L010（稳定 key 行）/ L025（zh catalog）
7. `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:110`——`terminalTailFloor = 70.0`（三模块
   层蒙版资格依据）+ Phase 7 `blendTriple`/maskPlane 缓存前缀键（零新类消费）
8. `LESSONS.md` L010（面板 key 行）/ L013（StableHash 唯一生成器）/ L020（内容级断言）/ L031（唯一
   路由获取点——identity 快速路径 review 项）+ `AGENTS.md`（Phase 执行模型 + 暂停机制）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，
  Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前。
- **不 push**；**构建勿加 `-derivedDataPath`**；**每新建源/测试/面板文件后跑 `tuist generate`**（11-03
  教训；T1 前先 generate 一次再构建）。
- **回归基线 = 1636/10skip/0fail**（13-3 后基线）；每任务全套 suite 绿；本 plan 收尾轮 = 1553 + 新增，
  0 fail。**在案 flake 归因条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 负载型 flake 若现，隔离
  ×3 归因单列入 SUMMARY，不计违约。
- **L031 路由红线（本 plan Metal 面适用）**：三模块一切 GPU 提交（主 kernel、bloom 级联多 pass、
  **identity 快速路径 blit**——L031 修复清单里 vignette/grain/bloom 同类新模块是重点 review 项）必须
  走 `MetalContext.makeRoutedCommandBuffer()`（`MetalContext.swift:524`）唯一路由获取点，禁自建
  MTLCommandBuffer/硬编 editor queue。
- **参数面 verbatim 红线**：dt 滑杆名/默认值/范围不得「顺手改良」；dither 参数不移植（D-08-CONTEXT-5
  ③裁决）；grain 不另设 ISO 感度参数（scale≈ISO 合一，D-08-CONTEXT-6①）。线性域适配点（bloom 阈值
  映射）只允许 research §9.2 终式，默认手感数值锚不动——**手感校准 = Manual-Only 观感轮预定项**
  （R4），不阻塞本 plan。
- **确定性契约（grain）**：seed = StableHash(canonicalParamsBytes ⊕ imageID-UUID-bytes)；Swift
  `Hasher` 禁入（L013）；「同参异图必异 + 同图同参逐字节相等」双断言是缓存键正确性的硬前提，不得
  放宽为统计断言。
- **perf 口径 = 只记不设门**：三 iop preview 管线 60fps 预算不回退 = 既有 perf 基线对照记录
  （bloom 级联 blur 0.29s @100MP r=64 参考数入 perf.md）；偏差归因注记，不设新硬门。
- RESEARCH/CONTEXT 未覆盖细节（paper_resp LUT 预烘焙 128² vs 直算、autoratio 默认行为、面板分组
  归属）标注**执行期决策**入 `08-2-DECISIONS.md`，不臆造。

## Tasks

### T1 vignette 68.0：参数面 verbatim + 单 kernel OpenCL 形 + golden + 面板

- **action**
  1. 新建 `LightamerIOP/Sources/Vignette/` 文件对三件。参数面 = `vignette.c:57-72` 全表 verbatim：
     `scale`(0-200,80)/`falloff_scale`(0-200,50)/`brightness`(−1..1,−0.5)/`saturation`(−1..1,−0.5)/
     `x`,`y`(center,±1)/`whratio`(0-2,1)/`shape`(0-5,1)/`unbound`(true)/`autoratio`；**dither 参数
     不移植**（8-bit 输出域补丁；float32 全链 + dither 75.0 既有终端模块承担同职责）。
  2. Metal kernel = `extended.cl:308-349` 逐段直译：cplen 幂距（shape 幂 + whratio）+ 线性 falloff +
     brightness 加/乘双支路 + saturation 均值去饱和；**cosine 权重平滑恒用（取 OpenCL 形）**——dt
     CPU 分支仅 dither 路径才有的自身分歧，不跟随（research §17.3）。
  3. `VignetteReference.swift` float64 同式直译（golden 正本）。
  4. **golden**：合成渐变图 × 默认参数 → 已知 falloff 曲线采样点 1e-6 容差；brightness 加/乘 ± 两
     支路分叉断言；`unbound=true` 裁剪语义（值越界不 clamp vs unbound=false 行为差）。
  5. `VignettePanelView`（D-H1 三件套：滑块拖动实时 → 松手恰 1 commit）+ IOPPanelProvider +1 席
     （L010 identifier `iop.vignette.*` 执行期定稿入 DECISIONS）+ zh/en catalog（L025）。
  6. `Registry.populate` 注册 vignette；构建绿。
- **证据**：`VignetteTests`——float64 vs kernel 采样点 1e-6 / 两支路 / unbound / 注册进 table 且
  iopOrder=68.0 < 70.0 层蒙版资格；identity 快速路径走 L031 路由点（代码走查 + 注释锚）。

### T2 grain 65.0：simplex verbatim + 确定性种子 + 确定性 golden + 面板

- **action**
  1. 新建 `LightamerIOP/Sources/Grain/` 文件对三件。参数面 = `grain.c:65-70,542-543` 三滑杆：
     `scale`（coarseness——tooltip「~ISO of the film」语义，UI 标注 ISO）、`strength`(0-100,25)、
     `midtones_bias`(0-100,0)；**不另设 ISO 感度参数**（D-08-CONTEXT-6①）。
  2. Metal kernel = **3-octave simplex 梯度噪声 verbatim**：f={0.4910,0.9441,1.7280}、a={0.2340,
     0.7850,1.2150}、终值 `32·Σ` 缩进 [-1,1]（grain.c:292-327）；paper_resp midtones LUT
     （:331-345，DELTA_MAX=2.0/MIN=0.0001/PAPER_GAMMA=1.0，128² 预烘焙 vs 直算 = 执行期决策）；
     **luma 域注入**（Rec2020 luma 系数）：`pixel += noise·strength·0.15 · paperRespCurve(luma)`；
     zoom/scale 换算走 `GRAIN_SCALE_FACTOR=213.2` 与 :450 zoom 式 verbatim。
  3. **seed 派生**（research §8.1 终表）：`seed = StableHash(canonicalParamsBytes ⊕ imageID-UUID-bytes)`
   （FNV-1a 64；image id = sidecar `imageID` UUID，**非**文件哈希——100MP 重算太贵 + 改名不改身份）；
   坐标域 = (x,y 全图归一 + zoom) + seed。缓存键零改：seed 是 (params,imageID) 纯函数，PipeCacheKey
   已含两者 → 同键 ⇔ 同 seed（research §8.2 无漏钉面；回归测试钉不变量而非改键）。
  4. `GrainReference.swift` float64 simplex（与 kernel 同 seed 逐位比对正本）。
  5. **确定性 golden 双断言**（红线）：同图同参两次渲染逐字节相等；同参异图输出必异（UUID 异 →
     图案异）。谱形对照：合成白场 patch 功率谱 vs dt 数值锚（三 octave 频峰在位）。
  6. `GrainPanelView`（scale 滑杆 ISO 标注 + strength + midtones_bias）+ Provider +1 席 + zh/en。
- **证据**：`GrainTests`——双断言逐字节 / float64 逐位比对 / 功率谱锚 / 缓存假命中负例（同参异图
  键不同断言）/ 注册 65.0。

### T3 bloom 61.0：三段 verbatim + 级联 blur + 线性阈值映射 + HDR 零特判 + 面板

- **action**
  1. 新建 `LightamerIOP/Sources/Bloom/` 文件对三件。参数面 = `bloom.c:47-51`：`size`(0-100,20)/
     `threshold`(0-100,90)/`strength`(0-100,25)；rad = 256·(size+1)/100（:140）。
  2. **三段编排**（:135-180 结构 verbatim）：① threshold kernel（`bloom.cl:22-38` 直译）——线性域
     映射终式（research §9.2）：`L_lin = luminance / 4.0`（4.0 = filmic 白锚，常量参数化）、
     `thr_lin = (threshold/100)³`、`strength` 保留 dt 指数提亮形；② **降采样级联 blur**（P5 择优：
     ÷8 box → 1/8 分辨率小 σ gaussian → bilinear 上采；0.29s vs 3-pass box 1.87s = 6.5×；**MPS 不
     引入**——级联形状 dtype 约束不合，自研 kernel）；③ screen blend 线性域 `1−(1−a)(1−b)`。
  3. **HDR >1.0 零特判**：screen 对 >1 值良定义，bloom 光晕可超 1.0 继续 HDR 域——同公式零改，
     测试钉 >1.0 输入行为（无 clamp 断言）。
  4. `BloomReference.swift` float64 三段参考（golden 正本）。
  5. **golden**：合成点光源 → 光晕半径/幅值断言；threshold 线性映射数值锚（90 → 0.729 → 只取白域
     高光）；float64 三段比对。默认手感 = Manual-Only 观感轮预定项（R4），数值锚不因手感预调。
  6. `BloomPanelView` + Provider +1 席 + zh/en；Registry 注册 bloom。
- **证据**：`BloomTests`——点光源半径/幅值 / 阈值锚 / HDR >1.0 零 clamp / float64 比对 / 级联 blur
  中间分辨率断言（1/8 面存在即形状正确）/ 注册 61.0。

### T4 全簇接线复核 + 60fps 预算复核

- **action**
  1. **层蒙版挂接走查**：三模块各配一个挂层蒙版用例（maskPlane 前缀键 + blendTriple 既有面）——
     蒙版外零改动、蒙版内效果生效（内容级断言，L020）。
  2. **L031 identity 快速路径 review**：三模块参数中性种子恒等逐字节（同 08-yiyin borders 先例
     形状）+ 全部提交走 `makeRoutedCommandBuffer()`（grep 自建 encoder/queue 零命中）。
  3. **V50Order 表复核**：61.0/65.0/68.0 三槽既有，`V50OrderTests` 全绿零移动（本 plan 无新行——
     新行义务在 08-5 text overlay）。
  4. **60fps preview 预算复核**：三 iop 各自挂 preview 管线渲染计时 vs 既有基线（perf.md 记录，
     不回退即过；bloom 级联 0.29s 参考数对账）。
- **证据**：`VignetteTests`/`GrainTests`/`BloomTests` 各扩层蒙版 + 恒等段；perf.md 复核行；grep
  输出贴 SUMMARY。

### T5 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1636/10skip/0fail** + 新增，0 fail；flake 条款见纪律节）；
  TODO.md 08-2 勾选；`08-2-SUMMARY.md`（任务表/commit 表/证据/perf 指针/**Manual-Only：bloom 默认
  手感观感轮预定项**登记）；`08-2-DECISIONS.md`（L010 identifier 全表、paper_resp 烘焙形态、autoratio
  行为、面板分组、其余执行期决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（1553 → N，0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| vignette | falloff 采样 1e-6 / 双支路 / unbound / 68.0 注册 | `Scripts/test-direct.sh 'VignetteTests'` |
| grain | 确定性双断言逐字节 / float64 逐位 / 谱锚 / 65.0 注册 | `Scripts/test-direct.sh 'GrainTests'` |
| bloom | 点光源半径幅值 / 阈值锚 / HDR>1.0 零 clamp / 61.0 注册 | `Scripts/test-direct.sh 'BloomTests'` |
| 接线 | 层蒙版局部化 ×3 / 恒等逐字节 / L031 grep | `Scripts/test-direct.sh`（三类各扩段） |
| perf | 60fps 不回退记录 + 级联 0.29s 对账 | 查 perf.md |
| 回归 | 全 suite 0 fail（基线 1553+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] vignette 68.0：dt 参数面 verbatim（dither 不移植）+ OpenCL 形单 kernel + float64 采样点
      1e-6 + brightness 双支路 + unbound 语义 + 面板四件套
- [ ] grain 65.0：3-octave simplex verbatim（f/a 表 + ×32 缩域）+ paper_resp LUT + luma 域注入 +
      seed = StableHash(params ⊕ imageID)（L013）+ 确定性双断言逐字节 + 功率谱锚 + scale ISO 标注
- [ ] bloom 61.0：threshold→级联 blur→screen 三段 + 线性域映射终式（L_lin/4.0 + (thr/100)³）+
      点光源半径幅值 golden + HDR >1.0 零特判 + 面板四件套
- [ ] 三模块层蒙版局部化（terminalTailFloor 资格）+ 中性种子恒等逐字节 + L031 路由 grep 零自建
- [ ] V50OrderTests 全绿零移动（61.0/65.0/68.0 槽位既有）；60fps preview 预算不回退（perf.md 记录）
- [ ] zh/en catalog 三组键全量（L025）；全 suite 0 fail（1553+新增）；每任务独立提交 + 边界查
      config 开关；不 push；SUMMARY + DECISIONS 落盘

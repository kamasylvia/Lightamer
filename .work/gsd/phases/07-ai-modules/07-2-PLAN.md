---
phase: 7
plan: "07-2"
title: "skinSmooth 频率分离磨皮 iop（AI-05）：V50Order 66.5 新行（dt verbatim 表插非 dt 行首例 + 表头标记）+ 两频分解（GaussianBlur Deriche IIR 低频腿复用）+ 阈值式高频衰减 kernel + Vision 定位（faceContour hull − 五官保护区 ⊗ personSeg）+ float64 parity + 恒等三元组 + 多频 enum 位预留（面板在 07-3）"
wave: 2
depends_on: ["07-1"]
autonomous: true
requirements: [AI-05]
files_modified:
  - LightamerCore/Sources/Foundation/V50Order.swift        # 66.5 新行（soften 66.0 与 splittoning 67.0 之间）+ 表头「非 dt 行」标记（项目首例）
  - LightamerIOP/Sources/SkinSmooth/SkinSmoothModule.swift # 新建：参数面（radius σ/strength a/detail-preserve t + 变体 enum 预留位）+ IOPModule 实现 + seed enabled-neutral
  - LightamerIOP/Sources/SkinSmooth/SkinSmoothKernels.metal # 新建：阈值衰减 + mask 合成 kernel（低频腿复用 GaussianBlur 既有件）
  - LightamerIOP/Sources/SkinSmooth/SkinSmoothReference.swift # 新建：float64 Swift 参考（low/high 分解 + 阈值衰减逐式）
  - LightamerIOP/Sources/SkinSmooth/SkinRegionLocator.swift  # 新建：landmarks → hull − 保护区 CPU 解析几何 + ⊗ personSeg + 羽化 → bake（调用 07-1 AIMaskService 皮肤腿）
  - LightamerIOP/Sources/Registry.swift                    # skinSmooth 注册（66.5）
  - Tests/LightamerTests/SkinSmoothParityTests.swift       # 新建：float64 parity（σ×a×t 组合）+ 恒等三元组
  - Tests/LightamerTests/SkinRegionGeometryTests.swift     # 新建：hull 几何合成点列解析断言（不跑模型）+ yaw 门 + 多脸 union + 空 landmarks 降级
  - Tests/LightamerTests/V50OrderTests.swift               # 66.5 插行唯一性/顺序扩展（如既有套件名不同则并入最近邻套件——执行期决策）
  - input/golden/manifest.md                               # skinSmooth 节（自研参考口径——无 dt 轨，L017 分流落账）
  - .planning/phases/07-ai-modules/07-2-SUMMARY.md
  - .planning/phases/07-ai-modules/07-2-DECISIONS.md
  - TODO.md
  - LESSONS.md                                             # 如踩坑
---

# Plan 07-2 — skinSmooth 频率分离磨皮 iop

> 背景：AI-05 = 频率分离磨皮，**Apple 无内置皮肤平滑滤镜**（`CISmoothLinearGradientSkinTone`
> 类 API 不存在，07-RESEARCH §2 查证）、dt 无 AI 磨皮先例——**自研数学 + Vision 定位**，
> 无 dt parity 轨（L017 分流：float64 自研参考 + 恒等三元组）。裁决 D-07-CONTEXT-6：
> v1 两频高斯分离 + **阈值式高频衰减**（低幅高频=色斑/噪点强衰减、高幅高频=毛孔/发丝/
> 轮廓保留——防塑料感的关键）；多尺度小波/bilateral 变体 v2（enum 位预留）。落位
> D-07-CONTEXT-2：独立 iop **V50Order 66.5 新行**——dt verbatim 表插非 dt 行是项目
> 首例，表头注释标记，沿用不可重排/唯一性纪律（新行只增不改，sidecar order 兼容）。
> 皮肤区域限定（07-RESEARCH §2.2）：`VNDetectFaceLandmarksRequest` 地标 → faceContour
> hull 外扩 −（eyes ∪ brows ∪ outerLips ∪ nostrils）保护区缓冲 ⊗ `VNGeneratePersonSegmentationRequest`
> 人体 matte → Gaussian 羽化 → bake raster 挂层蒙版槽（消费 07-1 AIMaskService 皮肤腿
> + bake 管线）。**hull 几何 = 纯 Swift 解析，不依赖模型输出质量即可单测**。面板/
> 「定位皮肤」按钮在 07-3（本 plan 交付到 module + 定位服务 + 测试）。

## read_first

1. `.planning/phases/07-ai-modules/07-RESEARCH.md` §2（频率分离数学全节 + 既有件盘点表 + hull 几何链）、§6（golden 表 skin hull 行 + 频率分离行）、§7（v50 槽位分析）、Risks 6、§Plan 07-2 行
2. `.planning/phases/07-ai-modules/07-CONTEXT.md` D-07-CONTEXT-2（66.5 落位）/6（两频 + 阈值衰减 + enum 预留）+ 继承定案节（推理输入/fence/失败腿）+ 验证红线节（parity <1e-5 + 恒等三元组）
3. `/Volumes/UNITEK/Documents/Development/darktable/src/iop/highpass.c:140`（σ 链公式 σ = √((r(r+1)8+2)/3) 援引）+ `src/iop/soften.c` / `blurs.c`（模糊族邻域参考）；`src/iop/channelmixerrgb.c:1796-1797`（skin hue 角——v2 parametric 预设参考，v1 不用）
4. `LightamerIOP/Sources/Common/GaussianBlur.swift` + `GaussianBlurKernels.metal`（Deriche IIR 双平面——低频腿直接复用）+ `Highpass/HighpassModule.swift:19-21,134-149`（分解→mix 结构参照）+ `Soften/SoftenModule.swift:24-30`（RGB linear mix 先例）
5. `LightamerCore/Sources/Foundation/V50Order.swift:1-15`（verbatim 表头纪律 + 邻域行）+ `LightamerIOP/Sources/Registry.swift`（注册面 + seed enabled-neutral 先例）
6. `Tests/LightamerTests/` 既有 parity 定式（`BlendOpParityTests` float64 参考模式 / `RetouchParityTests` 恒等三元组模式）+ `input/golden/manifest.md` 节体例
7. `LESSONS.md` L014（fence）/L017（golden 分流——自研参考口径）/L018（IIR RMW/双平面纪律——低频腿复用既已合规，新增 kernel 不触红线亦须守）/L020（内容级断言）/L023（半边契约——如 uniforms 矩阵出现）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 相关文件）；`caffeinate -dis`；单测 `Scripts/test-direct.sh`；**V50Order/Registry 改动后全量回归**（93+ 行 order 表 + 全模块链零回归）。
- **每任务边界检查 `.work/PAUSE`**（任务收尾 commit 后、下一任务开工前；AGENTS.md 2026-09-24 暂停机制）。
- **防空转**：parity 全像素 GPU vs float64 参考真比较循环 + `compared > 0` 断言；恒等三元组**逐字节**（a=0 逐字节恒等 / mask 空 == no-op / 平场恒等——任何 DC-1 blur，L017-proof）；hull 几何断言带方向（hull 内=1 / 保护区=0 / 羽化带 Gaussian 剖面）。
- **V50Order 红线**：66.5 新行**只增不改**——既有行零移动（diff 钉住）；表头注释标记「非 dt 行（Phase 7 skinSmooth）」；唯一性断言（无重槽）。
- **L018 纪律**：低频腿复用既有 GaussianBlur（已合规）；如新增任何邻域 kernel，中间结果走 device buffer 双平面、禁 read_write 纹理同线程 RMW。
- **L014 fence**：定位服务读解码帧（经 07-1 AIMaskService 路径，已固化——本 plan 不另开读回路径）。
- **色彩域**：分解在 linear Rec2020 RGB 三通道独立（SoftenModule 同域先例）；衰减只作用于幅值；不混 half 于阴影敏感路径（Conventions）。
- RESEARCH 未覆盖细节（衰减函数 `k_soft` 软化系数精确形/hull 外扩量与保护区 margin 默认值/额头带闭合算法）标注**执行期决策**入 `07-2-DECISIONS.md`，不臆造。

## Tasks

### T1 V50Order 66.5 新行 + SkinSmoothModule 骨架

- **action**
  1. `V50Order` 插行 `skinSmooth = 66.5`（soften 66.0 与 splittoning 67.0 之间）+ **表头注释标记「非 dt 行（Phase 7 skinSmooth）——项目首例，dt verbatim 纪律对非 dt 行同等适用（不可重排/唯一/只增不改）」**。
  2. `SkinSmoothModule`（.swift 骨架）：参数面 = `radius`（σ_spatial）/ `strength`（a）/ `detailPreserve`（t）三参数 + `variant` enum（v1 单 case `twoBandGaussian`，多频小波/bilateral 位预留——D-07-CONTEXT-6）+ `IOPModule` 全 conformance（ROI 恒等——频率分离是全帧邻域操作，halo 半径 = 低频腿 Gaussian σ 链等效，tileHalo 按 GaussianBlur 既有口径折算，执行期决策）+ seed enabled-neutral（a=0 恒等，liquify `:412-416` 同款先例）。
  3. Registry 注册 + 编辑种子（identity 参数）。
- **证据**：V50 唯一性/顺序断言扩展 + 既有行零移动 diff 钉住 + 全量回归（轨 B 全链零增量——中性插链逐字节恒等，Phase 3-6 全模块基线不受 66.5 插行影响）。

### T2 阈值式高频衰减 kernel + 分解链

- **action**
  1. `SkinSmoothKernels.metal`：`skin_mix`（high = I − low 分解 + 阈值衰减 `attenuate(h) = |h| ≤ t ? h·(1−m·a)·k_soft : h` + mask 合成 `out = low + attenuate(high)`）——低频腿**直接调用既有 GaussianBlur**（Deriche IIR 件，不重写）；σ 链援引 `highpass.c:140`（radius → σ 换算，方向与既有 highpass/soften 一致）。`k_soft` 软化系数形制（硬阈值 vs 平滑过渡）执行期决策落 DECISIONS——默认平滑过渡（防分段边界 banding）。
  2. mask 输入 = 该层 mask 槽的 raster 腿（Phase 6 `MaskCombiner.effectivePlane` 装配产物，module 只收 mask 平面参数——与既有 iop mask 腿同构，不发明新通道）；mask 空 == no-op（恒等三元组之二）。
- **证据**：`SkinSmoothParityTests` 恒等三元组先行（a=0 逐字节 / mask 空 no-op / 平场恒等——任何 DC-1 blur 三证）。

### T3 SkinRegionLocator：hull − 保护区 ⊗ personSeg

- **action**
  1. **CPU 解析几何**（纯 Swift）：`VNFaceObservation.landmarks` → `VNImagePointForFaceLandmarkPoint` 换算图坐标 → `skin_hull` = faceContour 多边形外扩（额头上缘 = 眉毛上缘−faceContour 顶点带状闭合——算法执行期决策）→ `protect` = eyes ∪ brows ∪ outerLips ∪ nostrils 各折线内缩 buffer → `face_mask = hull − protect`（多边形布尔差，纯 Swift 可单测）。
  2. 多脸 union（results 数组逐脸）；**yaw 门**：`|yaw| > 45°`（阈值执行期决策）的脸标记"地标可信度低"→ typed warning 供 UI 提示（不静默给坏 mask）；空 landmarks → typed error 降级腿（不落 mask）。
  3. ⊗ `VNGeneratePersonSegmentationRequest`（`.accurate`）人体 matte（排除背景中与肤色同调物）→ Gaussian 羽化（复用 07-1 bake 羽化）→ `RasterMaskStore.bake` 挂层蒙版槽（服务级 API；「定位皮肤」按钮在 07-3 接线）。Vision 调用经 07-1 `AIMaskService` 皮肤腿（handler/fence/后台 Task/CPU pin 复用）。
- **证据**：`SkinRegionGeometryTests`——**不跑模型**的合成点列断言：正脸（hull 内=1/保护区=0/羽化带 Gaussian 剖面，DrawnMaskRasterTests 模式）/ 侧脸 yaw 门触发 / 多脸 union / 空 landmarks typed error；含 `VNImagePointForFaceLandmarkPoint` 坐标换算的单测（合成 boundingBox + 归一化点）。

### T4 float64 参考 + parity

- **action**
  1. `SkinSmoothReference.swift`：low/high 分解（含与 GPU 同 σ 链）+ 阈值衰减 + mask 合成逐式 float64 复刻。
  2. parity：σ×a×t 组合 6 case（钉参：典型 σ 4-12px 等效档 × a 档 × t 档，含边界 |high| ≈ t 过渡带 case）× 既有 6 fixture 全像素 <1e-5（ParityGate 双闸定式）；manifest skinSmooth 节落账（自研参考口径——**无 dt 轨**，L017 分流记录；refs 生成脚本进 `input/golden/fixtures/` 既有管线，执行期决策）。
- **证据**：`SkinSmoothParityTests` 6 case parity + 恒等三元组全绿 + manifest 节 + 钉参表入 DECISIONS。

### T5 轨 B 回归 + 收口

- **action**：轨 B（skinSmooth 中性插链 == 无模块基线逐字节——种子恒等证明）；全量回归 0 fail；100MP tiling 抽查（低频腿 halo 摊销——GaussianBlur 既有 tileHalo 口径复用，超预算记录不改架构）；TODO 勾选；`07-2-SUMMARY.md` + DECISIONS（k_soft 形制/hull 外扩与 margin 默认值/yaw 阈值/tileHalo 折算）。
- **证据**：轨 B 计数 + 全 suite 计数 + SUMMARY。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| V50 插行 | 66.5 唯一 + 既有行零移动 + 全模块链零回归 | `Scripts/test-direct.sh 'V50OrderTests'` + 全套 |
| 频率分离数学 | GPU vs float64 <1e-5（6 case × fixture，双闸）+ 恒等三元组逐字节 | `Scripts/test-direct.sh 'SkinSmoothParityTests'` |
| hull 几何 | 合成点列：hull 内=1/保护区=0/羽化剖面 + yaw 门 + 多脸 union + 空降级（不跑模型） | `Scripts/test-direct.sh 'SkinRegionGeometryTests'` |
| 定位服务 | 真模型腿（合成人脸 fixture）bbox 容差方向断言 + typed error 腿（07-RESEARCH §6） | `Scripts/test-direct.sh 'SkinRegionGeometryTests'`（模型腿，pin CPU） |
| 轨 B | 中性插链零增量逐字节 | 全套（轨 B 套件） |
| manifest | skinSmooth 节（自研参考口径 + L017 分流落账） | 读 `input/golden/manifest.md` |

## 验收标准（Acceptance）

- [ ] V50Order 66.5 新行 + 表头「非 dt 行」标记（项目首例）+ 唯一性/零移动断言 + 全量回归零破坏
- [ ] 频率分离 parity <1e-5（σ×a×t 6 case 双闸）+ 恒等三元组逐字节（a=0 / mask 空 / 平场）
- [ ] hull 几何解析断言 4 case（正脸/侧脸 yaw 门/多脸 union/空 landmarks 降级）不依赖模型输出；真模型腿 pin CPU 方向断言
- [ ] 低频腿 = 既有 GaussianBlur 复用（零重写）；L018 纪律合规；衰减只作用幅值、linear Rec2020 RGB 分解
- [ ] variant enum 位预留（v2 多频/bilateral 升级缝）+ 决策（k_soft/hull 外扩/margin/yaw 阈值/tileHalo）入 `07-2-DECISIONS.md`
- [ ] manifest skinSmooth 节（自研参考口径）+ 轨 B 中性插链零增量 + 全量 suite 0 fail + SUMMARY 落盘

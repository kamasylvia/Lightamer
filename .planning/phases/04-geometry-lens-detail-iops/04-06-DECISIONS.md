# 04-06 DECISIONS — GUI 显示腿修复决策记录

> Plan 未覆盖点的裁决记录（任务书指令：写入本文件并继续，不停下等确认）。

## D-GUI-1 GUI-1 根因：crop 全帧默认在 scale<1 坍缩（T1 探针结论）

**证据**（`Tests/LightamerTests/GUIProbeTests.swift`，DSC00012.ARW 真实 CIRAW v9
解码 9504×6336，经 coordinator.load 真实路径 + RenderPipeline 消融，
`.work/plans/04-06/probe-gui1.md` 落盘，L014 每次读回前 fence）：

| 腿 | 链 | 结果（760×507，bgra8） |
|---|---|---|
| A | app 真实路径全 seed（22 实例） | 黑：mean=(0,6,5)，<16=94.2%，≥128=0.3% |
| B | trio-only | 亮：mean=(23,66,50)，<16=30.8%，≥128=6.3% |
| C | trio 去 gamma（float32 线性） | 域 sane：mean=(0.069,0.122,0.090) |
| D/E/F/G | trio+单个 sigmoid/filmic/agx/shadhi | 全亮（<16=12–47%） |
| I/J/K/L | 三 filmic 两两 + 三栈叠加 | 全亮（<16=51–60%，逐级压暗但有序） |
| M/N | trio+toneeq/shadhi/colisa；trio+temp/expo/tcurve/levels | 亮（=B/G 同值） |
| O | trio+三栈+shadhi | 亮 |
| H | 全 seed 经 pipe | 黑（<16=99.6%）= A，路径一致 |
| P | 全 seed 去三 filmic（反证） | 仍黑（含 TL 一亮点 (0,69,63)） |
| Q1 | trio+lens/ashift/flip/crop | 黑 |
| Q2 | trio+equalizer/sharpen/bilat | 亮（=B 同值） |
| Q3/Q4 | trio+lens-only；trio+ashift-only | 亮（=B 同值） |
| Q5 | trio+flip+crop | 黑 |
| Q6/Q7 | trio+crop-only 黑 / trio+flip-only 亮 | **二分锁定 crop** |

**候选排除**（plan T1 的 a/b/c）：
- a) displayTexture 选错/中间平面：排除。A 腿 `pixelFormat == .bgra8Unorm`
  ⇒ gamma tail 到达显示腿（tail policy：top-enabled 是 gamma 才分配 bgra8）。
- b) gamma/colorout 未启用或折叠改参：排除。B 腿 trio-only 亮 + H/A 一致；
  host `DisplayProfile.current = ColorSync fallback` 走 CI 精确腿同样亮。
- c) CI 腿输出域错：排除。C 腿线性均值 0.07–0.12（夜景合理）+ 中心值非零。

**根因**：`CropModule.modifyROIIn` 的 clamp 界把已缩放的 `dscIn` 又乘一次
`roi.scale`（double-scale）。`PixelPipe.run` 前向 stamped 的 `dscIn` 是
**entry 缩放后平面尺寸**（760×507 @scale 0.08），而 clamp 界算成
`760×0.08=60 × 507×0.08=40`。后果链：协商 roiIn=60×40 → base 子域渲染
60×40 → `process` blit `width=min(760,60,…)=60` 进 760×507 输出平面
origin-to-origin → 其余全零 → 下游 terminal_copy 越界读零 → 全黑，
仅左上 60×40 有内容（P 腿 TL 亮点即此角；blit uv 上下翻转后落左下，
与 GUI-1“左下树叶亮斑”一致）。
scale=1.0 时 `×scale` 恒等 ⇒ 全部 golden/crop 单测（小合成图全尺寸）
免疫，此路径从未被覆盖。

**修复方向（T2）**：`CropModule.modifyROIIn` clamp 界去掉 `×roi.scale`
（dscIn 本就是本 run 平面像素），+ `CropParityTests` 加 scaled 全帧回归
（trio+crop vs trio-only 在 scale<1 字节一致；pre-fix 黑 vs 亮必红）。
Pipe/Coordinator/Decoder 零改动（plan 预期“Core 不应改”部分成立：
pipe 谈判框架无错，错的是模块侧对 dscIn 坐标系的假设；改动落在
LightamerIOP 模块内）。

**附带观察（本次不动，记账）**：同类 `dscIn × scale` 模式还有
toneequal `diameter = blending × dscIn × scale`（preview smoothing 半径
偏小，质量向非正确性）与 flip `bw/bh`（.none 恒等故免疫）。修 crop 一处，
余者留 Phase 5 结合 roiHint 全面审计，不在本 plan 扩散。

## D-GUI-2 GUI-2+3 同根修：顶点矩形 triangle strip（T3 方向）

- 现状 `editor_blit_vertex` 大三角形 + `uv = ndc/scale` 反算：斜边越界区
  采样 clamp_to_edge（GUI-2 白对角线）+ uv 除法在 fit 矩形外仍有定义
  （GUI-3 越界绘制的结构性来源）。
- 修法（plan 字面）：4 顶点 triangle strip，顶点即 fit 矩形
  （`ViewportFit.fittedRect` → NDC），UV 恒 [0,1] 全纹理；
  letterbox 交给 renderPass clearColor；`aspectFitUniforms` 的 fit 数学
  只算顶点位置。EDR/colorspace（D-COL2 layer 附加）不回退。
- GUI-3 的“800×1120 vs 800×533”读数：crop 坍缩修完后显示纹理即全帧，
  T5 按 PLAYBOOK §2 重新量化（图像外包络 == 网格外包络）；若仍溢出则
  另立根因，不预设。

## D-GUI-3 GUI-4 布局红线落地值（T4 方向）

- AGENTS.md「GUI 布局红线」+ UI-SPEC 三列尺寸：侧栏默认折叠（空态窄列），
  Inspector 默认 ideal 260–280（min 200），视口吃剩余；990pt 窗口视口 ≥50%。
- 约束落列定义处（`navigationSplitViewColumnWidth` min/ideal/max +
  `@AppStorage` 默认值）；`balanced` 样式保留；空态文案不撑宽另查。
- plan 未定侧栏“折叠 vs 窄 icon 列”：选 NavigationSplitViewVisibility
  语义（doubleColumn 隐侧栏为既有 toolbar 行为），默认可见性保持 .all
  但列宽收窄——T5 实测三列宽入 SUMMARY，超红线再收。

## D-GUI-4 探针退役选择（T5 时执行）

- `GUIProbeTests` 按 L012 D-X2 模式退役删除（诊断使命完成；Q 腿是真 RAW
  解码重链，留套件=每次全量 +6s 且与 CropParity 回归重叠）。
- 常驻回归由 `CropParityTests.testScaledFullFrameCropMatchesTrioOnly`
  承担（合成图毫秒级）。证据 md `probe-gui1.md` 保留归档。

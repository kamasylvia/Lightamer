# 05-01-DECISIONS.md — Phase 5 基建决策记录（T1 先行落账；T2–T8 逐任务追加）

> T1 审计结论（含"确认无此问题"项）先于一切 denoise 工作落账——任务书强制项。

## D-05-01-T1: L021 toneequal/flip double-scale 审计还账（2026-09-21）

### 审计表

| 模块 | 钩子/位置 | 行号（修前） | 结论 |
|---|---|---|---|
| toneequal | `modifyROIOut` | ToneEqualModule.swift:255-257 | **免疫**——恒等 `roi = input`，不读 dscIn，无 scale 换算余地 |
| toneequal | `modifyROIIn` | ToneEqualModule.swift:259-261 | **免疫**——恒等 `input = roi`，不读 dscIn，无 scale 换算余地 |
| toneequal | `tileHalo(roi:piece:)` | ToneEqualModule.swift:284-285 | **命中 double-scale，已修**——`d.blending × dscIn.max × roi.scale`；dscIn 已是 entry 缩放后平面像素（PixelPipe.run:515 按 bufInROI 逐级 stamp），再 ×scale 即两次。dt `toneequal.c:1190-1192` 的 `max_size = piece->iwidth`（全分辨率）× `roi_in->scale` 一次；换算终点就是 dscIn 直用 |
| toneequal | `process` 半径 | ToneEqualModule.swift:384-385 | **命中 double-scale，已修**——与 tileHalo 同表达式（`derived.blending × dscIn.max × roiIn.scale`）；04-06 D-GUI-1 附带观察"preview 半径偏小，质量向"即此因。修后 FULL（scale=1.0）数值恒等，tile 路径 halo 同步放大（同一公式） |
| flip | `modifyROIOut` | FlipModule.swift:203-209 | **免疫**——纯几何 W/H swap，不读 dscIn，无 scale 换算 |
| flip | `modifyROIIn` | FlipModule.swift:221-224 | **命中 double-scale，已修**——`bw/bh = swapped(dscIn) × roi.scale`；dt `flip.c:338-339` 的 `buf_out × scale` 中 buf_out 是全分辨率 FORWARD 输出（`get_dimensions` 走 `modify_roi_out` 后的 `roi_in` 全尺寸链，`pixelpipe_hb.c:3364-3396`），`× scale` 一次。换算终点 = swapped(dscIn) 直用（已含 entry 缩放） |
| flip | `process` | FlipModule.swift:260-263 | **免疫**——uniforms 取自 `input.width/height`（真实纹理 dims），不经 dscIn/scale |
| flip | `.none` / transpose | — | **免疫**——`.none` 恒等（`backtransform` 自逆）；transpose 全帧 swap 与 dims 无关（hook 级全帧测试恒绿佐证） |
| crop | `modifyROIIn` | CropModule.swift:170-180 | 04-06 已修（修复范本）；本次审计复核注释已钉坐标系，无新动作 |

### dt 帧语义核实（审计依据链）

- `get_dimensions`（`pixelpipe_hb.c:3360-3405`）：`roi_in` 起于 `{0,0,width_in,height_in,1.0}`——**但这是 FULL 管的维度快照路径**；实际 process 入口 `dt_dev_pixelpipe_process(pipe,dev,x,y,wd,ht,scale)`（`develop.c:788`）的 `scale<1` 来自 viewport zoom（`develop.c:768`），`buf_in` = 全分辨率输入（`set_input`，`pipe->iwidth/height` 全尺寸，`develop.c:659`），`iscale`（mipmap 缩放比，`develop.c:660` `buf.iscale`）经 `create_nodes`（`pixelpipe_hb.c:505`）stamp 进每 piece。`piece->iwidth × roi.scale` = 全尺寸 × 管线缩放 = 本 run 平面像素——与我们的 `dscIn`（entry 缩放后尺寸）同值。
- toneequal `modify_roi_in`（`toneequal.c:1179-1197`）：`max_size = piece->iwidth`（**注意：不是 `buf_in`**——toneequal 的半径锚全分辨率，与 crop 的"本级输入"语义不同；注释已钉此区别）× `roi_in->scale`（**注意：dt 用的是 `roi_in->scale` 而非 `roi_out->scale`**——两者同 run 同值，实现中无差）。
- flip `modify_roi_in`（`flip.c:320-351`）：`backtransform(p,o,orientation, buf_out.width × roi_out->scale, ...)`——`buf_out` = FORWARD 输出（`get_dimensions:3393`），`× scale` 一次。我们的旧码误把"重算 forward 输出"写成 `dscIn × scale`——dscIn 已缩放，属第二次。
- soften 对照（`soften.c:138-142`）：`w = piece->iwidth × piece->iscale; radius = … × roi_in->scale / piece->iscale`——dt 显式 `/iscale` 正规化（`roi.scale ÷ iscale` 同构）；toneequal/flip 无此正规化（直接全幅锚），故换算终点是 dscIn 直用。T2 的 `IOPiece.iscale` 即把此"入口 scale"显式化，供 denoise 半径补偿（`roi.scale ÷ iscale`）消费。

### 修复

- `FlipModule.modifyROIIn`：`bw/bh` 改 swapped(dscIn) 直用 + ROI 帧约定注释（L020/L021）。
- `ToneEqualModule.tileHalo`：去 `× roi.scale` + 帧约定注释；`roi` 参数保留（`IOPModule.tileHalo` 协议签名），`_ = roi` 占位。
- `ToneEqualModule.process`：去 `× roiIn.scale` + 帧约定注释。
- `ToneEqualModule.modifyROIOut/In`、 `FlipModule.modifyROIOut`：恒等/免疫注释钉坐标系前提（任务书红线"所有新代码的 modifyROIIn/Out 注释钉坐标系前提"）。

### 回归证据（pre-fix 红 → post-fix 绿）

`L021DoubleScaleAuditTests`（6 tests，全含非 1.0 scale 档；比较循环 + `compared > 0`）：

| 测试 | pre-fix | post-fix |
|---|---|---|
| testFlipSwapModifyROIInFullFrameAtPreviewScale（rotCCW90/rotCW90/transverse/transpose 全输出→全输入 @scale 0.375） | 红（`(-30,0,48,36)` / `(0,-23,48,36)` / `(-30,-23,48,36)`；transpose 绿=免疫对照） | 绿 |
| testFlipHPartialWindowMirrorsAboutUnscaledWidth（(8,4,16,8)→(24,4,16,8)） | 红（`(-6,4,16,8)`） | 绿 |
| testFlipScaledPreviewPreservesConstantImage（8 态常数 0.5 @longEdge 48，每像素比较） | 红（flipV/flipH/rot180/rotCW90 常数漂 1.0） | 绿 |
| testTrioPlusFlipNoneMatchesTrioOnlyAtPreviewScale（逐字节） | 绿（免疫佐证） | 绿 |
| testToneequalPreviewHaloMatchesDtDiameter（48 档 157 / 760 档 137 / scale=1.0 对照 113 / none 0） | 红（97 / 101；113 绿=FULL 恒等、0 绿=免疫对照） | 绿 |
| testToneequalModifyROIInIsIdentity | 绿（免疫书面化） | 绿 |

- 既有套件 post-fix 全绿：CropParity 9/9、FlipParity 8/8、ToneEqualParity/Module/TilingOverlap/ToneEqualPerf（9 tests 含 100MP 内存门）、GeometryGolden 4/4。
- MDB_MAP_FULL 杂音：VisionDetectTests 遗留（TODO Phase 3 行），本轮 flip/trio 测试亦见同杂音，不影响结果。

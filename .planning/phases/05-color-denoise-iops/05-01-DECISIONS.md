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

## D-05-01-T2: `IOPiece.iscale` 协议增量 + pipe stamp（2026-09-21）

### 语义

- `iscale` = 本 run 的 ENTRY 缩放（dt `piece->iscale`，`pixelpipe_hb.c:505`
  同构）：`PixelPipe.run` 在入口平面 stamp（= 本 run 的 entry 缩放，与 dscIn
  同源同一次性写入）；run 级常量（每 piece 同值）；**tile 驱动
  （executeTiled/executeTiledNegotiated）不得改写**（RESEARCH §3.3 tile
  稳定性约束——TILE 不改 dscIn/iscale stamp；`grep iscale PixelPipe.swift`
  唯一写点 = run 前向 walk）。
- 半径补偿公式 = `roi.scale ÷ iscale`（denoise 四件消费者在 05-06/07/08
  落地，此处只供标量；soften.c:141 `rad × roi_in->scale / piece->iscale`
  先行同式；blend.c:675 feather 同式）。
- `commitParams` 永不触碰（默认 1.0 = full-res 恒等；`IOPiece()` 默认构造
  零扰动——全部既有 `IOPiece()` 构造点行为不变）。
- roiHint 注记：stamp 取 hint 后的 entry ROI scale（hint 即 entry 的一部分；
  T6 回归覆盖 hint 语义不变）。

### 回归证据

`IOPieceIscaleTests`（4 tests，探针记录真实执行值 + `compared > 0`）：
PREVIEW@48 iscale==0.375 / FULL==1.0 / THUMBNAIL 原生小图==1.0；
三探针同 run 全等；FULL toneequal 强制分块下游 probe iscale 仍==1.0。
邻居套件 post-stamp 全绿：L021 6/6、CropParity 9/9、FlipParity 8/8。

## D-05-01-T3/T4: NoiseProfileStore 规范化转换 + 加载/匹配/插值（2026-09-21）

### 转换格式

- 构建期转换（D-05-CONTEXT-2 采纳 RESEARCH 倾向）：`gen_noise_profiles.py`
  读 dt `data/noiseprofiles.json`（树 dc58cf0ba1）→ 规范化输出 bundle
  `noiseprofiles.json`：makers/models 字典序、profiles ISO 升序、a[3]/b[3]
  浮点显式、skip 档保留（加载器跳过，与 dt 语义一致）、version 保留。
- 自校验输出：433 models 集合一致 + 8538 档数全部守恒 + 抽 3 model
  （Canon EOS 1000D / Nikon Z 8 / YI M1）逐值 diff=0 + 有序性 OK。
- 排障注记：`repo_root()` 曾少上一级致产物落 `input/LightamerIOP/...`
  （已修 + 复位）；`Bundle.module.url` 不得带 `subdirectory:
  "NoiseProfiles"`（Tuist/Xcode 资源相位拍平 bundle 根——testRealBundle
  红转绿的定位点）。

### 加载器语义（dt 直译点）

- 匹配 = maker 子串包含（`maker.contains(jsonMaker)`，大小写敏感——dt
  `g_strstr_len` 方向：EXIF Make ∋ JSON maker 串）+ model 精确相等（dt
  `g_strcmp0`）+ skip 档跳过；结果 ISO 升序（dt `g_list_sort`）。
- 插值 = `t = clamp((iso−iso1)/(iso2−iso1),0,1)` a/b 逐通道线性插值
  （noiseprofiles.c:375-390 "stupid linear interpolation" 直译；
  `precondition(p1.iso < p2.iso)` 钉 dt 注释契约）；档外 clamp 首末档。
- miss → generic（`a=1e-4×3, b=0`，noiseprofiles.c:28）。
- actor + 懒加载（首问解析，实测 31ms < 1s 上限）+ 按 maker 索引缓存；
  剖面不进身份（L013）。
- LICENSE-NOTES：上游/转换/内容 + 许可核对未完成声明 + 待用户知悉项
  （核对前不对外分发 release；fallback = 用户指 dt 路径 + generic）。

### 回归证据

`NoiseProfileStoreTests`（5 tests，compared>0）：ILCE-9M3 ISO 140 手算向量
逐通道（t=15/35，a/b 精确到 1e-21/1e-24）+ 精确命中/clamp + maker 子串大小写
陷阱/model 精确/skip 剔除 + generic 逐值 + 真实 bundle <1s + 二问缓存同值。

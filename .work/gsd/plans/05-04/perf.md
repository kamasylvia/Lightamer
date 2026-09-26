# .work/05-04/perf.md — Plan 05-04 PERF 增量记录

> 05-RESEARCH §9 体例：color 组单件 1–2ms@2560 Debug/趟；只对 SC#4 拖动门设门，
> 全链重渲沿用「只记录不设门」既定口径。启用态单件计时留待 05-08 签核轮。

## 单件趟数（设计值，kernel 结构导出）

| 模块 | dispatch 数 | 说明 |
|---|---|---|
| vibrance | 1 | 单 pass 点态（Lab 往返 fuse，03-03 同模式） |
| velvia | 1 | 单 pass 点态（纯 RGB，无 Lab 腿） |
| colorzones | 1 | 单 pass 点态（Lab 往返 fuse + 3 LUT buffer 绑定） |

全部点态、无邻域、无 tiling（tileHalo=0），链增量 ≈ 3 趟 ≈ 3–6ms@2560 Debug
（05-RESEARCH §9 color 组单件 1–2ms/趟；colorzones 的 3×256KB LUT 常驻单 buffer，
commit 期一次性上传，per-frame 只绑 4 buffer，无 per-frame 上传成本）。

## 默认链影响（seed 政策）

- vibrance + velvia + colorzones：seed ENABLED-neutral（amount/strength 0 +
  flat-0.5 曲线 ⇒ 缓存中性，但仍占 dispatch）→ 默认链 +3 趟单 pass
  （exposure/colisa 等既有 enabled-neutral 件同处置；05-03 mixer-contrast 先例）。
- SC#4 拖动门（05-08）：denoise 未启用链上 color 组 +9ms 量级（05-02/05-03/05-04
  合计 8 件），不改变拖动梯子设计；denoise 启用场景以 05-06/05-07 降载三件套为准。

## Signpost

- 新增 kernel 3（vibrance_apply/velvia_apply/colorzones_apply）已进
  `prewarmFunctionNames`（Registry T1/T2），PSO 预热覆盖。
- RenderPipeline 的 per-module signpost 沿用既有管线 instrumentation（05-02/05-03
  未增单件 signpost，本 plan 同 — 单 pass 点态无分段热点可标）。

# .work/05-03/perf.md — Plan 05-03 PERF 增量记录

> 05-RESEARCH §9 体例：color 组单件 1–2ms@2560 Debug/趟；只对 SC#4 拖动门设门，
> 全链重渲沿用「只记录不设门」既定口径。启用态单件计时留待 05-08 签核轮。

## 单件趟数（设计值，kernel 结构导出）

| 模块 | dispatch 数 | 说明 |
|---|---|---|
| channelmixerrgb | 1 | 单 pass 点态（含 5 路运行时分支，同一 PSO） |
| channelmixer legacy | 1 | 单 pass 点态（含 4 模式运行时分支，同一 PSO） |
| colorcontrast | 1 | 单 pass 点态（Lab 往返 fuse，03-03 同模式） |

全部点态、无邻域、无 tiling（tileHalo=0），链增量 ≈ 3 趟 ≈ 3–6ms@2560 Debug
（05-RESEARCH §9 color 组单件 1–2ms/趟）。

## 默认链影响（seed 政策）

- channelmixerrgb：seed DISABLED → `processRec` 对 disabled piece 直通
  （05-02 D7 同构），零 dispatch、零增量。
- channelmixer legacy + colorcontrast：seed ENABLED-neutral（identity 矩阵 ⇒
  缓存中性，但仍占 dispatch）→ 默认链 +2 趟单 pass（exposure/colisa 等既有
  enabled-neutral 件同处置；sharpen/bilat/equalizer 先例）。
- SC#4 拖动门（05-08）：denoise 未启用链上 color 组 +6ms 量级，不改变拖动梯子
  设计；denoise 启用场景以 05-06/05-07 降载三件套为准。

## Signpost

- 新增 kernel 3（channelmixerrgb_apply/channelmixer_apply/colorcontrast_apply）
  已进 `prewarmFunctionNames`（Registry T2/T3），PSO 预热覆盖。
- 启用态单件计时：05-08 签核轮实测（本 plan 不设门）。

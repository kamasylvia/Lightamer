# .work/05-05/perf.md — Plan 05-05 PERF 增量记录

> 05-RESEARCH §9 体例：monochrome ~12 趟（filter + grid 9 + apply）；只对
> SC#4 拖动门设门，全链重渲沿用「只记录不设门」既定口径。

## 单件趟数（设计值，kernel 结构导出）

| pass | dispatch 数 | 说明 |
|---|---|---|
| filter | 1 | 单 pass 点态（Lab 往返 fuse，03-03 同模式） |
| grid splat | 1 | 原子散射（atomic_float，05-05-T1 修） |
| grid blur x/y/z | 3 | 高斯 x/y + −2 阶导 z（ping-pong 双缓冲） |
| grid slice | 1 | 三线性查表 + detail norm |
| slice→filter blit | 1（blit） | in-place 回写（CL 腿 dev_tmp 中转同构） |
| apply | 1 | envelope + highlights + Lab→Rec2020 |
| **合计** | **7 compute + 1 blit** | plan 预估 ~12 趟（CL 腿 local-reduce 多趟；我方直写法 7 趟） |

## 默认链影响（seed 政策）

- monochrome：seed DISABLED（D2）→ 默认链 +0 趟（disabled 件零 dispatch；
  05-02 colorbalancergb T5 零增量先例）。
- 启用态单件 ~7 趟 ≈ 7–14ms@2560 Debug（05-RESEARCH §9 单趟 1–2ms）。
- SC#4 拖动门（05-08）：monochrome 启用链上 grid 腿 5 趟常驻；拖动梯子降档
  策略沿用 denoise 三件套口径（05-06/05-07 落定）。

## Signpost

- 新增 kernel 2（monochrome_filter/monochrome_apply）+ grid 复用 4
  （splat/blur_line/blur_line_z/slice）已进 `prewarmFunctionNames`
  （Registry T1），PSO 预热覆盖。
- RenderPipeline 的 per-module signpost 沿用既有管线 instrumentation
  （05-02/03/04 未增单件 signpost，本 plan 同）。

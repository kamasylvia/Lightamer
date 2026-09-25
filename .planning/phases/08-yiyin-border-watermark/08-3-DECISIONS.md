# Plan 08-3 Decisions（执行期决策记录）

> 依据 plan 纪律：RESEARCH/CONTEXT 未覆盖的实现细节一律标注**执行期决策**落本文件，不臆造。
> 每条含：决策 + 依据 + 影响。编号 D-08-3-N（代码注释引用同名）。

## D-08-3-T0-1: yiyin_watermark_row alpha 因子修正（08-2 验收必修，随本 plan 首个 fix）

**决策**：`yiyin_watermark_row` kernel 改为编码域 un-premultiply + 线性 alpha 因子：
`out = a · M·srgbDecode(row.rgb / a) + (1 − a) · plane.rgb`（除法结果 clamp [0,1]）。
**依据**：08-2 验收员 CG 探针实证——8-bit sRGB `premultipliedLast` 位图 = **编码域预乘**
（白字 glyph 边缘 r == a 精确；alpha 0.5 白块 r=128/a=128），即存储 rgb = a×encode(color)、
a = 线性 coverage。08-2 首版 kernel 对预乘 rgb 过 EOTF 后又以 `1 − srgbDecode(a)` 作背景
因子——coverage 被二次 EOTF（0.5→0.214），AA 边缘有效覆盖率减半，文字偏瘦。
**影响**：部分覆盖像素合成结果变宽变实（修正方向）；已冻 golden 不受影响（golden 冻
**行位图**——渲染器产物未动）；合成腿测试内容级（上带恒等/下带有差异）照旧成立；
`testRowBitmapInk` 的 r≥a 注释更正（白墨 r==a）；08-2-DECISIONS D-08-2-7 末条同步更正。
T0 全套回归 0 fail 实证。

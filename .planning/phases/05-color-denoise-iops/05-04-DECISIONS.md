# 05-04-DECISIONS.md — Plan 05-04 决策记录

> vibrance（58.0）+ velvia（57.0）+ colorzones（60.0）执行期决策。
> 惯例：推荐可逆且已论证、可审阅推翻（05-CONTEXT 既定授权模式）。

## D-05-04-T2-1: colorzones V2 splines 核对结论（plan 级决策点）

**裁决：复用 ToneCurveLUT（curve_tools V1 移植）+ 两处参数化增量。**

对照源：`src/common/splines.h/.cpp`（V2 `interpol` 命名空间）vs
`src/common/curve_tools.c:393-653`（V1，03-03 已移植）vs
`src/gui/draw.h:410-467`（V1/V2 采样入口）。

逐项核对：

| 项 | V1（curve_tools） | V2（splines） | 结论 |
|---|---|---|---|
| CUBIC_SPLINE 切线 | 自然样条三对角（`spline_cubic_set` wrapper `(2,0)/(2,0)` + `d3_np_fs`） | `smooth_cubic_spline`（同矩阵 + LU；非周期分支与 V1 逐项同式） | **相同** — 委托复用（`cubicTangents` 经 `cubicSplineSecondDerivatives` + ypp→dy 换算，`testCubicV2MatchesV1` 逐点 1e-12） |
| CATMULL_ROM 切线 | 中央差分（`catmull_rom_set`） | `Catmull_Rom_spline` 非周期分支（同式） | **相同** — 委托复用（`XCTAssertEqual(v1!, v2!)`） |
| MONOTONE_HERMITE 切线 | 算术平均 + Fritsch–Carlson 钳制（`monotone_hermite_set`） | **Fritsch–Carlson G-variant**（`monotone_hermite_spline_variant`：加权调和 `G(S1,S2,h1,h2)`，`splines.cpp:371-422`） | **实质不同** — 新增 `monotoneVariantTangents`（手算钉：`(0,0),(0.3,0.8),(1,1)` → V1 m[1]=0.8416/m[2]=0.1629 vs V2 G=0.5783/Δ1，`testMonotoneVariantDiffersFromV1`） |
| 周期腿（select h） | 无（V1 commit 用 wrap 节点拼非周期曲线） | `CurveDataSampleV2Periodic`：按型 wrap 切线 + `fmod` 环绕求值，y 不钳制（`infinity()` 限） | **新增** — `periodicCatmullRomTangents` / `periodicMonotoneVariantTangents`（注意：MONOTONE 周期腿用 **VARIANT**，`splines.cpp:855-893`）/ `periodicCubicTangents`（N×N 循环 Gauss 解）+ `evaluatePeriodic`（接缝/过 knot 门：`testPeriodicWrapsSeamlessly` / `testPeriodicPassesThroughKnots`） |
| 端点填充 | 首/末端点值外平坦 | 同（`firstPointY`/`lastPointY`，`CurveDataSampleV2`） | **相同** |
| 采样网格 | `i·res`，`res=1/(N−1)` | 同 | **相同** |
| 量化 | `round()` → uint16（dt 侧） | 同（dt 侧） | Lightamer 双侧存 raw Double（ToneCurveLUT 同款偏离，已记录） |

- **Reversibility**: reversible — 增量函数独立，替换任一求值器只影响对应腿。
- **证据**：`ColorZonesCommitTests` 11/11（V2-vs-V1 pin + 接缝/knot 门 + 恒等构建）。

## D-05-04-T2-2: colorzones SMOOTH/STRONG 取舍 + V1  наследия处置

- **裁决**：v1 只交付 SMOOTH（v3 路径）。`Params.mode` 保留侧写忠实位（sidecar
  520B  round-trip），kernel 恒走 v3 数学；STRONG（`process_v1` 的 LCh 域
  `lookup−0.5` 平移 + `LCh[2] += hm` 旋转语义）**不移植**。
- **理由**：① SMOOTH 是 dt 默认（`DT_IOP_COLORZONES_MODE_SMOOTH`，`init`/`_reset_parameters`
  全默认，花生 `init_presets` 全 SMOOTH）；② CL 核只实现 v3（`basic.cl` 的 legacy
  `colorzones` 核无调用方）；③ STRONG 的 LCh 旋转与 v3 的 Lab-atan2 旋转语义分叉，
  双路径 parity 成本翻倍，v1 无用户。
- **Reversibility**: reversible — mode 位已留，未来独立补 v1 腿即扩展点。
- **V1 splines_version 处置**：同理只走 V2（dt 新编辑全写 V2；V1 的 wrap-节点
  commit 不移植；`splines_version` 不进 Params——V1 blob 导入经 sidecar 未知-op
  语义由 05-08 统一评估，注记在此）。

## D-05-04-T3-1: colorzones track-A 双层门（MAIN + SPECTRAL）

- **裁决**：track-A 按 fixture 家族分两层：
  - **MAIN**（ramp/flats/gray/hue_sweep 5 件）：plan 双闸原文
    （strict ≥99% <1e-5 + 2.5e-5 floor / 1e-4 包络）——**断言**。
  - **SPECTRAL**（saturated 1 件）：envelope 1e-2 abs **断言** + strict 上报。
- **理由（物理）**：输出角噪声 × 色度放大 — `d(out) ≈ C·2π·d(h)`。
  saturated 的光谱块 C 高达 5507（spec500 系），float32 角噪声 dh~3e-7 即
  5e-3 abs 偏差；dt 自身 CL 腿同 fast-math 族，同量级偏差（CPU-LERP vs
  CL-NEAREST 只是第二项）。plan 的 `<1e-5 rel` 在 C>100 域对**任何**
  float32 实现（含 dt CL）不可达——门在物理允许域原文执行，torture 件走
  torture 预算（先例：FilmicRGB F3 光谱块作 gamut 断言非 parity）。
- **实测**：MAIN strict 100%（0 违反，59.7 万样本）；SPECTRAL strict 85.8%
  上报 + envelope（1e-2）0 违反，maxAbs=0.43（极端 C 像素，包络内）。
- **Reversibility**: reversible — 门阈值是测试常量，不进管线。

## D-05-04-T3-2: LUT-direct 门的 fast-pow 系统 bias

- **裁决**：LUT-direct 门（stair_1d 倾斜 L 曲线）= envelope（1e-4）**断言** +
  strict 上报 + bias 上界（maxAbs < 1e-4 = 包络 abs 腿，同一数）**断言**。
- **理由**：Metal fast-math `pow(2.0f, 4·Lm)` 携系统性 ~2.5e-5 abs 偏置
  （L'~100；构建 `-fmetal-math-fp32-functions=fast`），逐 select 值恒定——
  倾斜曲线把同 stair 层级整片平移（24464 strict 违反全同 bias 簇，
  envelope 0 违反）。dt 的 `dtcl_pow`/`native_powr` 同 fast 族——dt-GPU
  对 dt-CPU 同 bias，我方与 dt-GPU 腿对齐（含其 fast-math 偏置）。
- **实测**：maxAbs=8.5e-5（亮端），envelope 0 违反。
- **Reversibility**: reversible — 门阈值是测试常量。

## D-05-04-T3-3: hue_sweep S=0.999（PEDELTA，跨 plan 影响）

- **裁决**：`gen_hue_sweep` 饱和度 1.0 → 0.999（最小通道 0.001，hue 环覆盖
  不变，C≈127.9/128）。理由：纯 HSV 主色在 fixture 中含**精确 0.0 通道**，
  相对误差在该通道退化（除 ~0）——恒等/近恒等 parity 的 maxRel 被钉在
  1e2–1e6 量级空转（cz_default×sweep 实测 288，vib_default×sweep 实测 204）。
- **跨 plan 影响与还账**：
  - `NoiseFixtureStatisticsTests` 内容指纹更新（首列 G/180 列 R：0.0 → 0.001）。
  - colorbalance（05-02）8-fixture refs 含 hue_sweep——其 refs 系旧 sweep 下生成，
    与新 fixture 失配（JzAzBz×sweep maxRel=0.35；DTUCS×sweep 出精确零失配）——
    **本 plan 已重生成**（`gen_colorbalancergb_refs` 直调），回绿验证。
  - channelmixerrgb/channelmixer/colorcontrast refs 不含 hue_sweep——不受影响
    （channelmixer 含 saturated，但 saturated 未动）。
  - **教训**：`gen_fixtures.py refs` 是死模式（main 无 `"refs"` 分支——`mode in
    ("cases","all")` 吞掉 refs 调用；`python gen refs` 只打印不生成）。跨 fixture
    改动必须直调 `gen_*_refs` 并核时间戳（本次踩坑：时间戳竞态 + 死模式双重）。
    05-08 可议复活 `refs` 模式或显式文档化直调流程。
- **Reversibility**: reversible — fixture 生成器常量 + refs 重生成即回滚。

## D-05-04-T3-4: dt 三证据 ×3 的 colorzones 缺口（host 插件坏）

- **记录**：本机 dt 构建的 `libcolorzones.so` 卸载（`_dt_opencl_copy_host_to_device`
  符号缺失——构建树 OpenCL 桩坏），colorzones 4 case 无 `version ok` 行；
  vibrance/velvia 5/5 `params v.2 version ok params ok`。
- **处置**：colorzones dt 证据 = 520B blob 格式断言（`struct.calcsize`=520 =
  dt `sizeof`）+ 平场 probe 方向性（cz_lightness L 提升 0.5→0.87 directional
  确认）+ V2/lookup 与 dt 源码逐式对照（DECISIONS T2-1 表）。不阻塞——L017
  主轨本就是合成参考；05-08 签核时若构建树修复可补采纳。
- **平场 probe 方向性确认**：vibrance 强档灰场恒等（achromatic paradox，
  sw=0）+ velvia 双档灰场恒等 + cz_lightness L 提升 + cz_chroma/cz_hue 灰场恒等
  （C=0/h 未定义 → 无操作），6/6 与公式预测一致。

## D-05-04-T4-1: colorzones 面板三 tab + CurveEditorView 复用边界

- **裁决**：`ColorZonesPanelView` = 三 tab（L/C/h）× `CurveEditorView` 整套复用
  （拖节点/命中/外推）+ 下方 hue 色带（cosmetic）+ select/strength/mode 控件。
  `CurveEditorView.nodes` 类型为 `[ToneCurveModule.Node]`——跨模块复用时经
  `.init(x:y:)` 双向映射（同名异 type，小适配层，无改动 CurveEditorView）。
- **GUI-10/GUI-11 布局债**（FINDINGS 登记，高优先级，05-08 签核前修）：
  模块列表 ~25 行占满 Inspector 列高，面板体被挤出可视区（`InspectorView`
  moduleList VStack 无 ScrollView/高度约束）。面板语义已由 PanelWiring 钉住
  （拖节点=恰 1 commit），本轮属布局债——修法指向 moduleList 加滚动约束，
  不动面板本身。
- **Reversibility**: n/a — UI 布局债，修法收敛。

## D-05-04-T5-1: 注册表 colorcontrast 行丢失事故（T5 全量回归捕获）

- **记录**：T1 注册编辑误删 `ColorContrastModule` 注册行（T2 起连续三轮构建
  成功掩盖——被删行无引用方，编译静默通过）。T5 全量回归 512/7fail 暴露：
  `makeBox(colorcontrast)` nil → contrast parity + perf 双链（seed 消费方）
  XCTUnwrap 失败。
- **处置**：恢复注册行 + 注释头；教训：注册改动后必须跑**全量**（非单类）
  回归——单类绿对此类删除免疫。`Registry/seed 改动后全量回归`纪律已在 plan，
  本次属执行延迟（T1 未跑全量），非纪律缺失。
- **Reversibility**: n/a — 事故记录。

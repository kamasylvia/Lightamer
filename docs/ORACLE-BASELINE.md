# ORACLE-BASELINE — 官方对照包 5.6.2 与钉点 `679d594f5d` 的差异报告（A5）

> 结论：给官方工具写的 XMP 夹具，**按 5.6.2 的模块版本号与参数布局写**。
> 21 个模块里 17 个三版本逐字节相同；4 个在 master 变了（§3），5.6.2 与 5.7.0 在全部
> 21 个的版本号与结构体上**完全相同**。我们不读 darktable 历史（A-12），master 布局只影响以后移植，
> 不影响夹具。

## §1 三版本

| 代号 | 含义 | 提交 | 日期 |
|---|---|---|---|
| 5.6.2 | 官方对照包（`Scripts/oracle.lock`） | `908607e556` | 2026-10-04 |
| 5.7.0 | 源码标签（无官方 macOS 包） | `e5330da743` | 2026-06-19 |
| master | 参数/顺序钉点（A-1） | `679d594f5d` | 2026-11-22 |

源码树：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`。

## §2 21 模块总表（第 0 期，`CORE-DESIGN-TABLES.md` T2 口径去 `clipping`）

`v` = `DT_MODULE_INTROSPECTION` 版本；`size` = params 结构体 `sizeof`（LP64，clang 实测）；
`defaults` = 默认值有无变化（5.6.2 → master）。

| order | 模块 | v 5.6.2 | v 5.7.0 | v master | size 5.6.2 | size 5.7.0 | size master | defaults | 备注 |
|---|---|---:|---:|---:|---:|---:|---:|---|---|
| 1.0 | rawprepare | 2 | 2 | 2 | 32 | 32 | 32 | 不变 | DNG gain-map 支持进 `commit/process` |
| 3.0 | temperature | 4 | 4 | **5** | 20 | 20 | **24** | 加 `late_correction`=FALSE | §3 |
| 4.0 | highlights | 4 | 4 | **5** | 48 | 48 | **40** | 删未用 `blendL/blendC`；Bayer 默认不变 | §3 |
| 5.0 | cacorrect | 2 | 2 | 2 | 8 | 8 | 8 | 不变 | `process` 重写 |
| 6.0 | hotpixels | 1 | 1 | 1 | 16 | 16 | 16 | 不变 | 多为 GUI；`process` 动过 |
| 8.0 | demosaic | 6 | 6 | **8** | 48 | 48 | **60** | **`cs_radius` 默认 0.0→0.5**；加 3 字段 | §3 |
| 13.0 | lens | 10 | 10 | 10 | 356 | 356 | 356 | 不变 | lensfun CL 路 + MD v2 重写 |
| 13.5 | cacorrectrgb | 1 | 1 | 1 | 20 | 20 | 20 | 不变 | 仅 GUI 默认 setter 改法 |
| 15.0 | ashift | 5 | 5 | 5 | 892 | 892 | 892 | 不变 | 求解器/GUI  churn |
| 16.0 | flip | 2 | 2 | 2 | 4 | 4 | 4 | 不变 | 仅版权年 + 头文件 |
| 21.0 | exposure | 7 | 7 | 7 | 28 | 28 | 28 | **DNG 默认曝光加 `dng_baseline_exposure`**（ARW 不变） | deflicker 重构 |
| 24.5 | crop | 3 | 3 | 3 | 24 | 24 | 24 | **相机画幅自动启用**（§4） | GUI 为主 |
| 28.0 | colorin | 7 | 7 | **8** | 1044 | 1044 | **1048** | 加 `output_rgb`=TRUE | §3 |
| 42.0 | rgbcurve | 1 | 1 | 1 | 516 | 516 | 516 | 不变 | 曲线编辑器 GUI 重写 |
| 43.0 | rgblevels | 1 | 1 | 1 | 44 | 44 | 44 | 不变 | 区间交互 GUI 重写 |
| 48.0 | tonecurve | 5 | 5 | 5 | 520 | 520 | 520 | 不变 | 节点编辑器 GUI 重写 + 预设 |
| 69.4 | finalscale | 1 | 1 | 1 | 4 | 4 | 4 | 不变 | ROI/tiling/+process/CL 微调 |
| 70.0 | colorout | 5 | 5 | 5 | 520 | 520 | 520 | 不变 | 新增 lcms2 fastpath + `commit` 重写 |
| 73.0 | overexposed | — | — | — | (4) | (4) | (4) | 不适用（`NO_HISTORY_STACK`，永不进 XMP；运行时 `{int dummy}` 4B） | 显示色/process 重写 |
| 75.0 | dither | 2 | 2 | 2 | 32 | 32 | 32 | 不变 | random/FS/posterize 过程 |
| 78.0 | gamma | 1 | 1 | 1 | 8 | 8 | 8 | 不变 | 输出拷贝/显示重构 + `process` |

读法：17 行三版本版本号与结构体逐字节相同；4 行（temperature/highlights/demosaic/colorin）
只在 master 变，5.6.2 ≡ 5.7.0。`overexposed` 无 introspection 版本（`init` 直设
`params_size`），不进历史。

## §3 四个变结构的模块（5.7.0 → master 全量 diff，结构体部分）

- **temperature v4→v5（20B→24B）**：尾部加 `gboolean late_correction; // $DEFAULT: FALSE`
  （"prepare data for color calibration"）。`legacy_params` 有 `old_version == 4` 分支。
- **highlights v4→v5（48B→40B）**：删 `float blendL; // unused` 与 `float blendC; // unused`，
  其余 10 字段（含 `$DEFAULT`）逐字不变。`legacy_params` 覆盖旧版。
- **demosaic v6→v8（48B→60B）**：版本跳两级——v7 = moire 检测预备（`7414ef40` "Prepare demosaic
  for moire detection"），v8 = DNG GainMap（`c7d98b58` "dng_opcode: apply the GainMap from
  DNG OpcodeList3"）。新字段 `float moire_thrs;`（0.0）、`float moire_mix;`（0.0）、
  `gboolean dng_gainmap;`（TRUE）；**`cs_radius` 的 `$DEFAULT` 由 0.0 改 0.5**（§4 唯一改既有
  默认值的字段）。`legacy_params` 有 v6、v7 两分支。
- **colorin v7→v8（1044B→1048B）**：尾部加 `gboolean output_rgb; // $DEFAULT: TRUE`。
  `legacy_params` 有 `old_version == 7` 分支。

## §4 默认值变化（5.6.2 → master，逐项到代码行）

1. **demosaic `cs_radius` 0.0 → 0.5**（`src/iop/demosaic.c` params 结构体 `$DEFAULT` 行）：
   唯一改既有字段默认值的模块。注释称 0.5 覆盖几乎所有 sensor/lens 组合。
2. **exposure DNG 默认曝光**（`reload_defaults`）：
   `d->exposure = (mono ? 0.0f : 0.7f) + image_storage.dng_baseline_exposure;`
   非 DNG（ARW）的 `dng_baseline_exposure` 为 0，默认不变。
3. **crop 相机画幅自动启用**（`reload_defaults` 新增约 60 行）：机内画幅（`camera_ratio_n/d`）
   或 usercrop 存在时按该画幅预置参数并 `default_enabled = TRUE`；此前恒 FALSE。
4. **temperature/colorin 新字段默认值**：`late_correction`=FALSE、`output_rgb`=TRUE、
   moire 双 0.0、`dng_gainmap`=TRUE（§3）。既有字段不动。
5. **highlights 4Bayer 来回**：5.6.2→5.7.0 删 `is_4bayer` 特判（§5），5.7.0→master 以
   `rawprep && !is_4bayer ? OPPOSED : CLIP` 形式加回；Bayer 默认恒 OPPOSED，不变。
6. 其余 15 个模块：`$DEFAULT` 行、`reload_defaults`、`init` 均无语义变化
   （`cacorrectrgb` 仅 GUI 的 `gtk_toggle_button_set_active` 换 `dt_bauhaus_toggle_set_default`；
   `rgbcurve/tonecurve` 仅变量改名）。

## §5 5.6.2 → 5.7.0（17 个零 diff，4 个如下）

- **highlights**（5+8 行）：删 `is_4bayer` 特判（仅 4Bayer 行为变）；
  `tiling->factor_cl` 系数 7→5（显存预算，非像素）。
- **demosaic**（3+9 行）：`green_eq` 清理逻辑重构（passing/bayer4/单色同结果；越界旧值不再钳制）。
- **lens**（0+4 行）：纯 GUI（`DT_ENTER/LEAVE_GUI_UPDATE` 包裹删除）。
- **colorin**（11+8 行）：`process`/`process_cl` 的系数修正由
  `coeffs[k] = D65coeffs[k]` 改 `coeffs[k] *= coeffs[k]`（**真渲染变化**，correction 画像素级不同；
  默认值不动）。附带两行静态零/壹向量。

## §6 结论：夹具按 5.6.2 写

1. 读夹具的是 5.6.2 的 `darktable-cli`，它按
   `modversion == version() && len == params_size` 判（HISTORY-COMPAT §3），
   所以 `operation/modversion/params` 三件必须取 5.6.2 的值（本表 5.6.2 列）。
2. 本波两模块三版本全同：exposure v7/28B、flip v2/4B（字段表见 `fixtures/oracle/README.md`），
   无版本选择风险。
3. 以后移植 temperature/highlights/demosaic/colorin 时：移植 master 代码（master 参数），
   但写给官方包的 XMP 仍按 5.6.2 布局（v4/20B、v4/48B、v6/48B、v7/1044B）编码——两形态并存，
   由各移植波的 `DtParamsEncoder` 承担，不做迁移链（A-12）。
4. 渲染行为差（§2 备注列、§5 colorin）只影响"官方包输出长什么样"，不影响夹具写法；
   oracle 门（`cmp` 容差）以自检实测为准。

## §7 方法与命令（可重跑）

```bash
DT=/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master
# 版本号
git -C $DT show release-5.6.2:src/iop/exposure.c | grep DT_MODULE_INTROSPECTION
# 结构体对照（brace-matched 抽取 + 归一化哈希，脚本 /tmp/abl_parse.py）
git -C $DT show <rev>:src/iop/<mod>.c
# sizeof：抽出的结构体 + 存根（glib 类型 + 28 个 enum=int + 2 个 node 结构 + 6 个数组界宏）
#   拼成单 C 文件，Apple clang 编译打印（脚本 /tmp/abl_gen.py），LP64 = 官方包 ABI
cc -o /tmp/abl/sizeof /tmp/abl/sizeof.c && /tmp/abl/sizeof
# 默认值/行为：两段 diff + 函数级归纳
git -C $DT diff release-5.6.2 release-5.7.0 -- src/iop/
git -C $DT diff release-5.7.0 679d594f5d -- src/iop/ | grep -E '^[+-].*(DEFAULT|reload_defaults|legacy_params)'
```

结构体"相同"指注释归一化后字节相同；全部 28 个 `dt_*_t` 类型逐个核对为 `typedef enum`
（4B），两处 node 结构（`tonecurve/rgbcurve`）三版本同为 `{float x, y}` 8B；
数组界宏 `DT_IOP_COLOR_ICC_LEN`=512、`DT_IOP_RGBCURVE_MAXNODES`=20（=`MAX_ANCHORS`）、
两处 `MAX_CHANNELS`=3（枚举值）、`DT_IOP_TONECURVE_MAXNODES`=20、`MAX_SAVED_LINES`=50。
数字锚点：`release-5.6.2`=`908607e556`，`release-5.7.0`=`e5330da743`。

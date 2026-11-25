# CORE-DESIGN-TABLES — 长表（正文见 CORE-DESIGN.md）

口径：上游 refs/dt-master @ 679d594f5d（2026-11-22）；行数 = `wc -l` 含注释空行；
params = LP64 手算；`.cl` 映射以各模块 `init_global` 的 program 号 + `data/kernels/programs.conf` 为准。

## T1 模块回调全表（`src/iop/iop_api.h`，57 个 + process_plain 非表成员）

宏语义（`src/common/module_api.h:28-76`）：REQUIRED 必实现；DEFAULT 有默认实现可覆盖；
OPTIONAL 可为 NULL（调用前判空）。P0 列 = 第 0 期 Rust trait 是否需要。

| # | 回调 | 签名（iop_api.h 行号） | 何时调 | P0 |
|---|---|---|---|---|
| 1 | init_presets | `OPTIONAL(void, init_presets, so*)` :61 | 启动每模块一次，注册内置预设 | 否 |
| 2 | init_global | `OPTIONAL(void, init_global, so*)` :63 | 启动每 so 一次（OpenCL kernel 等） | 否（OnceLock） |
| 3 | cleanup_global | `OPTIONAL(void, cleanup_global, so*)` :65 | 退出 | 否 |
| 4 | name | `REQUIRED(const char*, name, void)` :68 | 处处（op 名） | 是 op_name() |
| 5 | aliases | `DEFAULT(const char*, aliases, void)` :71 | 搜索 | 否 |
| 6 | default_group | `DEFAULT(int, default_group, void)` :73 | UI 分组 | 否 |
| 7 | flags | `DEFAULT(int, flags, void)` :75 | 管线判行为（TILING/BLEND/DISTORT…；imageop.h:72-101） | 是（子集） |
| 8 | deprecated_msg | `DEFAULT(const char*, deprecated_msg, void)` :77 | UI 警告 | 否 |
| 9 | description | `DEFAULT(const char**, description, self)` :80 | tooltip | 否 |
| 10 | operation_tags | `DEFAULT(int, operation_tags, void)` :82 | DISTORT 位定 mask 旁路（pixelpipe_hb.c:2639） | 是 |
| 11 | operation_tags_filter | `DEFAULT(int, operation_tags_filter, void)` :83 | 跳过逻辑过滤 | 可选 |
| 12 | input_format | `DEFAULT(void, input_format, self,pipe,piece,dsc)` :86 | 定输入 bpp | 否（固定 float4） |
| 13 | output_format | `DEFAULT(void, output_format, …)` :91 | 定输出 bpp（pixelpipe_hb.c:2618） | 否（固定 float4） |
| 14 | default_colorspace | `REQUIRED(cst, default_colorspace, self,pipe,piece)` :97 | 色彩回退基准 | 是 |
| 15 | input_colorspace | `DEFAULT(cst, input_colorspace, …)` :102 | 每 piece 前自动变换（pixelpipe_hb.c:1801） | 是 |
| 16 | output_colorspace | `DEFAULT(cst, output_colorspace, …)` :107 | 处理后记 pipe->dsc.cst（:1965） | 是 |
| 17 | blend_colorspace | `DEFAULT(cst, blend_colorspace, …)` :112 | blend 前变换目标（blend.c:143） | 预留（默认关） |
| 18 | tiling_callback | `DEFAULT(void, tiling_callback, self,piece,roi_in,roi_out,tiling)` :119 | 每 piece 前填 factor/overlap/align（tiling.h:25-41） | 是（可默认） |
| 19-28 | GUI 十件 | gui_update/reset/init/color_picker/gui_changed/gui_cleanup/gui_post_expose/canvas_overlay/gui_focus/mouse_actions :127-157 | 仅 darkroom GUI | 否 |
| 29-33 | 画布事件 | mouse_leave/moved/button_released/button_pressed/scrolled :160-181 | 仅交互模块 | 否 |
| 34 | init | `OPTIONAL(void, init, self)` :187（必须设 params_size） | 建实例 | 是（Params::default） |
| 35 | cleanup | `DEFAULT(void, cleanup, self)` :188 | 删实例 | 否（Drop） |
| 36 | init_pipe | `DEFAULT(void, init_pipe, self,pipe,piece)` :191 | 建 piece，分配 piece->data | 是（可并入 commit） |
| 37 | commit_params | `DEFAULT(void, commit_params, self,params,pipe,piece)` :199 | 参数→piece 提交，算 piece->hash | 是（核心） |
| 38 | reload_defaults | `OPTIONAL(void, reload_defaults, self)` :204 | RAW 加载后更新默认参数 | 可选 |
| 39 | change_image | `OPTIONAL(void, change_image, self)` :206 | 切图 | 否 |
| 40 | cleanup_pipe | `DEFAULT(void, cleanup_pipe, self,pipe,piece)` :209 | 释 piece->data | 否（Drop） |
| 41 | modify_roi_in | `OPTIONAL(void, modify_roi_in, self,piece,roi_out,roi_in)` :226 | 第 2 遍反推输入 ROI（调用点 pixelpipe_hb.c:2575） | 是（默认恒等） |
| 42 | modify_roi_out | `OPTIONAL(void, modify_roi_out, self,piece,roi_out,roi_in)` :240 | 第 1 遍前推输出尺寸（get_dimensions:4026） | 是（默认恒等） |
| 43 | legacy_params | `OPTIONAL(int, legacy_params, self,old,old_ver,new*,new_size*,new_ver*)` :244 | 历史/预设版本迁移 | 否（定 v1） |
| 44 | masks_selection_changed | `OPTIONAL(void, masks_selection_changed, self,form_id)` :251 | mask 选形变化 | 否 |
| 45 | process | `REQUIRED(void, process, self,piece,i,o,roi_in,roi_out)` :260 | CPU 主路径（:1937，仅 OpenMP SIMD） | 是（核心） |
| 46 | process_tiling | `DEFAULT(void, process_tiling, …,bpp)` :267 | 内存不足分块（:1899） | 是（默认分块器） |
| 47 | process_cl | `OPTIONAL(int, process_cl, self,piece,dev_in,dev_out,…)` :281 | GPU 路径（返 CL 错误码） | 否（P0 无 GPU） |
| 48 | process_tiling_cl | `DEFAULT(int, process_tiling_cl, …)` :288 | GPU 分块 | 否 |
| 49 | distort_transform | `OPTIONAL(gboolean, distort_transform, self,piece,points,n)` :301 | 几何前向（IOP_TAG_DISTORT） | 可选（lens/clip 要） |
| 50 | distort_backtransform | `OPTIONAL(gboolean, distort_backtransform, …)` :306 | 几何逆向 | 同上 |
| 51 | distort_mask | `OPTIONAL(void, distort_mask, self,piece,in,out,…)` :310 | mask 随几何变形（:4632） | 否 |
| 52-56 | introspection | introspection_init/get_introspection/get_linear/get_p/get_f :320-324 | 参数自省/序列化 | 否（serde） |
| 57 | set_preferences | `OPTIONAL(void, set_preferences, GMenu*,GAction*,self)` :327 | 预设菜单偏好项 | 否 |
| — | process_plain | 非 api 表成员（imageop.h:158,299 裸函数指针） | 遗留直调入口 | 否 |

管线类型位（`src/develop/pixelpipe.h:40-63`）：
EXPORT=1<<0, FULL=1<<1, PREVIEW=1<<2, THUMBNAIL=1<<3, PREVIEW2=1<<4；
SCREEN=PREVIEW|FULL|PREVIEW2, CANVAS=FULL|PREVIEW2, BASIC=FULL|PREVIEW；
修饰 FAST=1<<8, IMAGE=1<<9, IMAGE_FINAL=1<<10。
缓存配额（pixelpipe_hb.c:218-276）：full 64 行（无 cache 则 DT_PIPECACHE_MIN=2），
preview 12 行，preview2 5 行，export/thumbnail MIN 行 + 预分配 4*float*w*h。

单模块处理 13 步（S0 建图 → S1 提交 → S2 前推几何 → S3 查缓存 → S4 反推 ROI →
S5 定格式 → S6 mask 旁路 → S7 tiling 决策 → S8 进变换 → S9 直方图/拾色 →
S10 process → S11 出变换 → S12 blend → S13 写缓存），file:line 见 C1 scout 报告
（agent 已归档，关键行：pixelpipe_hb.c:4026/2385/2539/2618/2672/1801/1937/1994/2026）。

## T2 第 0 期模块清单（v50 RAW 顺序，`src/common/iop_order.c:306+`）

clipping 已 deprecated（`src/iop/clipping.c:337-340` 原文 “this module is deprecated. please use the crop, orientation and/or rotate and perspective modules instead.”），第 0 期裁剪只取 crop。lane = C7 估算（估算）。

| order | 模块 | 源文件 | 行数 | .cl（program#） | params（字段/字节） | 外部依赖 | 双版 | lane |
|---|---|---|---|---|---|---|---|---|
| 1.0 | rawprepare | iop/rawprepare.c | 1112 | basic.cl#2 | 7f 32B | 无 | ✅ | 1 |
| 3.0 | temperature(WB) | iop/temperature.c | 2385 | basic.cl#2 | 6f 24B | lcms2.h | ✅ | 2 |
| 4.0 | highlights | iop/highlights.c | 1451 | basic.cl#2 | 10f 40B | 无 | ✅ | 2 |
| 5.0 | cacorrect | iop/cacorrect.c | 1806 | cacorrect.cl#49 (443行) | 2f 8B | 无 | ✅ | 2 |
| 6.0 | hotpixels | iop/hotpixels.c | 588 | basic.cl#2 | 4f 16B | 无 | ✅ | 1 |
| 8.0 | demosaic | iop/demosaic.c | 2244+子目录12文件(xtrans最大118KB) | ppg#0/vng#15/markesteijn#16/rcd#31/amaze#51/lmmse#52/other#14/capture#38 | 15f 60B | 内部imageio_rawspeed.h | ✅(部分mode回退CPU) | 4 |
| 13.0 | lens | iop/lens.cc | 5209 | basic.cl#2 | 26f 356B | lensfun.h | ✅ | 3 |
| 13.5 | cacorrectrgb | iop/cacorrectrgb.c | 953 | cacorrectrgb.cl#47 (323行) | 5f 20B | 无 | ✅ | 2 |
| 15.0 | ashift | iop/ashift.c | 6280(+lsd/nmsimplex求解器) | basic.cl#2 | 17f 892B | 无 | ✅ | 3 |
| 16.0 | flip | iop/flip.c | 631 | basic.cl#2 | 1f 4B | 无 | ✅ | 1 |
| 17.0 | clipping | iop/clipping.c | 3348 | basic.cl#2 | 21f 84B | 无 | ✅ | —（deprecated，不取） |
| 21.0 | exposure | iop/exposure.c | 1392 | basic.cl#2 | 7f 28B | 无 | ✅ | 1 |
| 24.5 | crop | iop/crop.c | 2035 | 无（CL=copy） | 6f 24B | 无 | ✅copy | 2 |
| 28.0 | colorin | iop/colorin.c | 2622 | basic.cl#2 | 8f 1048B | lcms2.h+png/tiff内部头 | ✅ | 2 |
| 42.0 | rgbcurve | iop/rgbcurve.c | 1958 | rgbcurve.cl#25 (65行) | 6f 516B | 无 | ✅ | 2 |
| 43.0 | rgblevels | iop/rgblevels.c | 1529 | rgblevels.cl#29 (81行) | 3f 44B | 无 | ✅ | 2 |
| 48.0 | tonecurve | iop/tonecurve.c | 1987 | basic.cl#2 | 7f 520B | 无 | ✅ | 2 |
| 69.4 | finalscale | iop/finalscale.c | 270 | 无自有（公共clip_and_zoom） | 1f 4B | 无 | ✅ | 1 |
| 70.0 | colorout | iop/colorout.c | 1532 | basic.cl#2（CL侧bake 65³ CLUT） | 3f 520B | lcms2间接 | ✅ | 2 |
| 73.0 | overexposed | iop/overexposed.c | 442 | basic.cl#2 | 无params（运行时阈值） | cairo.h | ✅ | 1 |
| 75.0 | dither | iop/dither.c | 788 | extended.cl#8 (1106行) | 3f 32B | 无 | ✅ | 1 |
| 78.0 | gamma | iop/gamma.c | 347 | 无（CPU-only） | 2f 8B | 无 | ❌CPU | 1 |

合计（去 clipping，21 模块顶层文件）：C/C++ **37,561 行**；另 demosaicing/ 7,722 + ashift 求解器 2,703，全量 47,986。program 行锚点见 scout 报告；
定论：WB=temperature（name "white balance"）；lens=几何+TCA+暗角一体（MODFLAG 三位）；
tonecurve/rgbcurve/rgblevels 默认全关，分处 42/43/48 非二选一；overexposed=HIDDEN 显示辅助；
显示链 colorout(70.0)→gamma(78.0)，display ICC 由 colorout params 指定。
CPU/GPU 数值差异注释：P0 21 模块 grep 全无命中（仅色域容差/防除零等无关项）。复现模式：`grep -rniE "tolerance|CPU[-_ ]?(GPU|OPENCL)|GPU[-_ ]?CPU|OPENCL[-_ ]?(DIFF|MISMATCH)|differs from (cpu|opencl)"` 21 文件。

## T3 去马赛克计时（A7R5 9568x6376，OpenMP 10 线程，`--iters 5` 取中位）

rawspeed 自带去马赛克算法：**无**。`interpolators/` 仅 `Cr2sRawInterpolator`（Canon sRAW
YCbCr 插值，非 Bayer/X-Trans 去马赛克）。下表为 spike 自写基线（black 减+white 归一，
float32 RGB 输出，防死码 checksum 跨构建复现一致）。

| 段 | 历次 (ms) | 代表值 |
|---|---|---|
| rawspeed decode | —（单次 50.7；dump 轮 41.1） | ~46 |
| bilinear 3x3 | 57.6 29.2 23.9 27.8 23.7 | 27.8 |
| MHC 5x5 | 45.5 48.3 43.3 43.4 41.6 | 43.4 |
| bilinear 重验证 | 29.9 26.1（2 次全列，非中位） | — |
| MHC 重验证 | 43.3 43.4（2 次全列，非中位） | — |

checksum（防死码，每 4096 采样和）：bilinear 3576.551542，MHC 3673.206641，两轮逐位一致。
计时口径：`steady_clock` 墙钟，含 OpenMP fork/join，不含分配（out 预分配）与 dump 写盘。

## T4 线性对比（自写 MHC+WB+矩阵 vs CIRAW extended-linear-sRGB，转储全分辨率）

| 项 | 值 |
|---|---|
| ours | 9568x6376 float32 RGB，camera 原生，black 512 减，white 15360 归一；均值 0.08169 |
| cir | 9504x6336 float32 RGBA（取 RGB），CIRAW v8 渲染 1203.1 ms；均值 0.24086 |
| WB | rawspeed wbCoeffs 2536/1024/1778 → 增益 (2.4766, 1, 1.7363) |
| 矩阵 | cameras.xml XYZ→camera（见 T4b），求逆作 camera→XYZ；XYZ→sRGB 用 D65 标准矩阵（非 Bradford 适配，同 D65 直接变换） |
| 对齐 | 中心裁 (oy=20, ox=32)；几何差 64x40 系 Apple 额外裁剪 |
| RAW mean/max | 0.169369 / 8.194610（linear sRGB 单位） |
| gain fit | 0.71251；NORM mean/max 0.140293 / 5.551161 |
| 均值 ours/cir | (0.44625, 0.11015, 0.10181) / (0.24510, 0.38119, 0.09628) |

T4b cameras.xml A7R5 矩阵（XYZ→camera，D65，verbatim）：
0.820000 -0.297600 -0.071900 / -0.429600 1.205300 0.253200 / -0.042900 0.128200 0.577400。
WB 变体试验（1/8 降采样，脚本 compare_down8.py + 输出 down8.log，decode-spike-src/）：无 WB 版 mean 0.1285 为最小，带 WB 版 0.1699——WB 处理是主色偏源。
neutralChromaticity：ARW (0.345350, 0.362652)；DNG-T0 (0.335336, 0.356312)。

## T5 DNG 偏色诊断（bench cmp，2560 档，0..255）

| 试验 | AsShotNeutral | thumb | bench mean_abs_diff | 结论 |
|---|---|---|---|---|
| T0 基线（复现） | (0.40379, 1, 0.57593) | 113/130/56 | 22.784 | 复现上一轮 22.8 |
| T1 unit | (1, 1, 1) | 0/135/64（R=0！） | 55.935 | neutral 极敏感，unit 错 |
| T2 拟合 | (0.38772, 0.88989, 0.44585) | 105/128/70 | 23.275 | 均值拟合不改善→非 WB 可缩放残差 |

neutralChromaticity：T2 (0.357356, 0.379094)，相对 T0 向 ARW (0.345,0.363) 反方向过冲。
Writer tag 自查（对照 DNG 1.4 CFA 必需）：DNGVersion/Backward/UniqueCameraModel/CFARepeat/CFAPattern/
BlackLevel(2x2 RATIONAL)/WhiteLevel/ColorMatrix1(SRATIONAL x1e4)/CFAPlaneColor/CFALayout/AnalogBalance/
AsShotNeutral(x1e6)/CalibrationIlluminant1=DNG 21/ActiveArea/DefaultScale/DefaultCrop/BaselineExposure=0——齐全；
LinearizationTable 缺席正确（线性数据）；ForwardMatrix/CameraCalibration 缺席合法（reader 自推）。
结论：writer 合规；偏色主因 = cameras.xml 校准数据 vs Apple 内置 A7R5 profile 数据源差异（推断，有 T1/T2 诊断支撑）；
真修 = 色卡标定或相机实测矩阵（本 lane 外）。三轮 bench cmp 原始输出：decode-oracle-evidence/dngfix-cmp-t{0,1,2}.log。

## T6 Oracle 全分辨率轮（9568x6376 PNG16，~311MB/张）

| 输出 | 后端证据 | wall | user | 大小 | sha256（前 16） |
|---|---|---|---|---|---|
| g0-full-cpu.png | NOT utilized | 19.85s | 23.32s | 310908453 | 3a471c4250c08e26 |
| g0-full-cpu-r2.png | —（重复轮） | 18.54s | 22.84s | 310908453 | 3a8559d488e74266 |
| g0-full-cl_01.png | 161/161 events, RCD tiled | 20.53s | 13.68s | 310910402 | 50954a186144dbbe |
| g1-full-cpu.png | — | 17.60s | 22.00s | 312373549 | ec9f5145288063ea |
| g1-full-cl.png | — | 20.84s | 13.43s | 312373553 | — |
| g2-full-cpu.png | — | 18.88s | 22.66s | 312164304 | — |
| g2-full-cl.png | — | 18.66s | 13.50s | 312164987 | — |

像素对照（cmp16.py，LSB16）：repeat mean/max 0/0；cpu-cl 三组 mean ≈0.013-0.014，max 842-904，
in_tol(1/255) ≥0.99999994。跨组：G0-G1 mean 2600.87（曝光生效），G1-G2 mean 7747.82
（flip，三通道均值逐位相等）。

## T7 着色器盘点（P0 相关）

darktable 侧（P0 21 模块所需 kernel 栖身处）：basic.cl 4618 行（12 模块共用：
rawprepare/temperature/highlights/hotpixels/exposure/colorin/lens/flip/ashift/tonecurve/
colorout/overexposed；program=2 逐文件实证）；cacorrect.cl 443；cacorrectrgb.cl 323；
rgbcurve.cl 65；rgblevels.cl 81；extended.cl 1106（dither 用其中 dither 系）；
demosaic 系 8 文件共 ~4316 行（ppg 781/vng 358/markesteijn 915/rcd 356/amaze 863/
lmmse 418/other 105/capture 520）。P0 起步子集（RCD-only demosaic）：basic.cl 相关核
+ cacorrect/cacorrectrgb + rgbcurve/rgblevels + rcd.cl + dither 系 ≈ 6000 行 OM（估算，
basic.cl 需逐核裁剪，整文件 4618 行含大量 P0 外模块核）。

Lightamer 侧（全仓 75 .metal：IOP 59 + Core 13 + App 1 + spike 证据 2）：命中 P0 模块名
6/21：Temperature/Exposure/Lens/Flip/Ashift/ToneCurve（Exposure 系 basic.cl exposure 逐字移植；
Levels 系 Lab 版 levels.c，非 rgblevels，不计）。结论：73 个产品 .metal 里 P0 可用 6 个，
其余 P0 模块无对应 Metal 资产。

## T8 工作区与 lane 估算（估算）

Crate 划分见 §6。lane 口径：1 lane = 1–2h ≈ 1000 行带测试代码（任务给定校准）。
模块 lane 见 T2 末列，合计 38（1x8 + 2x10 + 3x2 + 4x1 = 8+20+6+4）。
基础设施 lane（粗估）：pipe-core（trait+调度+缓存+tiling）3；decode（rawspeed 集成+
黑白电平/WB/矩阵消费）2；blend/mask 基础 2；色彩管理+显示 2；导出 4 格式 2；
导入/图库/历史/撤销 3。 infra ≈ 14。P0 总≈ 52 lane（纯估算，不含 UI 与 review 修订）。

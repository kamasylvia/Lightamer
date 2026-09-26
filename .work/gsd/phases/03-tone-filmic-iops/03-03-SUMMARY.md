# Plan 03-03 — Summary

**Executed:** 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE（IOP-TONE-03/05/06 green；LabRoundTrip 共享件落地，03-04 可直接复用）

Lab 域三模块全量交付：**colisa（47.0）/ tonecurve（48.0，10001 点 LUT + 三插值 + 外推 + autoscale 全家族）/ levels（49.0，manual + automatic 256-bin 直方图归约）**，全部以共享件 `LabRoundTrip`（CPU Double + Metal 单 pass 内联）为地基，轨 A golden parity + 轨 B 双判据 + 面板三件套齐备。全 suite **199 tests 全绿**（3 skip 合规）。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 03-03-T1 | `LabRoundTrip`（Common/）：BT.2020 Rec2020→XYZ（项目唯一常量集）+ Bradford D65→D50 + Lab 参考白锚定管线白 → **中性 a=b=0 精确**；dt 同形 f（cbrt/cube，κ=24389/27、ε=216/24389）负值有定义（光谱 fixture）；`LabMath.h`（MSL 内联，无 cbrt → 有号 powr(1/3)）+ `LabKernels.metal` 独立往返 pass；LabRoundTripTests（向量/20k 随机往返/无界语义/GPU 腿/轨 B Lab 对插入 8-bit 输出 ≤1 LSB）；管线级 Lab 共享 v1 不做（Open#9 → Phase 5+） | 3932653 |
| 03-03-T2 | `ColisaModule`（+kernel）：ctable/ltable（colisa.c:190-235 逐行）+ extrapolation 拟合 + 单 packed MTLBuffer；kernel 单 pass Rec2020→Lab→(ctable→ltable nearest 查表 + 幂外推；a,b×(sat+1))→Lab→Rec2020；5 case × 6 fixture parity + 轨 B + 注册 | a60d43d |
| 03-03-T3 | `ToneCurveModule`（+`ToneCurveLUT`+kernel）：curve_tools.c 三插值逐行（monotone hermite/catmull-rom/natural cubic + d3_np_fs）+ L/a/b 表缩放 + XYZ/RGB 联动表重推导（RGB 走工作域 Rec2020，dt 硬编码 ProPhoto）+ 5 组外推拟合 + `rgb_norms.h` norm 家族（LUMINANCE=Rec2020 Y 行）；`CurveEditorView`（拖节点，显示 = 实时 CPU LUT——显示即管线数学）+ ToneCurvePanelView；4 case × 5 fixture（含 stair_1d LUT 分辨率靶） | b745d72 |
| 03-03-T4 | `LevelsModule`（+kernel）：compute_lut 逐行（manual）+ 单 pass kernel（L_in≤black→0 / nearest LUT / 白外无界幂律；色度 CPU 形 `a,b×L_out/max(L,0.01)`）；3 manual case × 6 fixture parity + 色度保持断言 + 轨 B + 注册 | 15ea14d |
| 03-03-T5 | `HistogramReduce`（Common/，两趟 256-bin 线程组原子归约，Lab L 内联；MPS 备选不接线——单调用接口可换）+ levels automatic（percentile 三点 levels.c:212-250 逐行 → LUT 重写 → apply，每 run 重算）；直方图解析 ±1 bin + 自洽 parity <1e-4 + ΔE p99<1.0；signpost 计时位 | 0c278e8 |
| 03-03-T6 | Colisa/Levels/ToneCurve 三面板（三滑块 / 模式切换+双 role 点滑块 / 曲线编辑器+autoscale pickers）+ provider 注册 + pristine 种子 +39 条本地化；PanelWiringTests +4（三面板拖动=恰 1 条 commit、colisa 归零还原 hash、levels 模式切换离散一条）；VALIDATION 三行 ✅ + TODO 更新 | dfd3697 |

## 验证（质量门全过）

- **全 suite**：199 tests, 0 failures, 3 skips（合规 skip 不变）
- **T1**：Double 往返 <1e-9（实测 2.4e-15）20k 随机全域（含负值/超界）；GPU float32 往返 <1e-6（域内）；白/灰 a=b=0 精确；三原色对设计期常量 1e-7
- **T2-T4 轨 A**：colisa 5 case、tonecurve 4 case、levels 3 case × 各自 fixture 组，ParityGate 双闸（≥99% 样本 <1e-5 相对 + 2.5e-5 abs floor；100% <1e-4 包络）全过
- **T5 automatic**：GPU 直方图 vs 解析（漂移 ≤8 counts）、三点 ±1 bin（plan 闸）、parity <1e-4 rel+abs、ΔE p99 <1.0
- **轨 B**：colisa/tonecurve/levels identity 插入默认链 → 中性度 <2/255 全过；Lab 对插入输出 8-bit 字节稳定
- **面板**：PanelWiringTests 10/10（三面板拖动恰 1 条 commit、归零还原原 paramsHash、模式切换离散一条）
- **注册**：colisa 47.0 / tonecurve 48.0 / levels 49.0（.Lab colorspace）全部断言

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | colisa brightness gamma 用**源码形态** `1/(1+b)` / `(1−b)`（rescale ×2 后），非 plan 文本的 `10^(−brightness)` | plan 引用有误——colisa.c:220 无该式；源码逐行核过（模块头注 divergence） |
| 2 | LUT 查表索引**四舍五入**替代 dt 的截断（≤1 LSB 语义差） | 中性像素 a_in=0.5 恰在截断边界（0.5×65536=32768 整），f32 色度噪声系统性翻转 ±1 索引（stair_1d 实测 21% strict 违规）；舍入使索引在噪声下稳定，消除整类悬崖 |
| 3 | LUT 表值**不做 dt 的 1/65536 整数量化**（≤1 LSB） | 消除表构造侧量化悬崖；与偏差 #2 同族，nearest 查表语义保留 |
| 4 | ParityGate 双闸（≥99% <1e-5 rel + 2.5e-5 abs floor；100% <1e-4 包络）替代逐像素 1e-5 单闸 | f32-vs-f64 在对抗网格（stair_1d 直击 LUT 分辨率、ramp 幂律网格 2^13.75=13862.504 恰在舍入边界）的残余翻转率 0.16–0.52%，幅度 ≤2 LSB（3.5e-5），是 nearest 查表语义的固有属性；包络 100% 硬闸保证无超差 |
| 5 | levels automatic 参考为**在测自洽**（GPU 直方图→levels→LUT→apply vs 同 levels 的 float64 求值），非预生成逐像素 EXR | f64 直方图分箱与 GPU f32 分箱在 ~1e-4 像素上分歧，单个 percentile 交叉 bin 翻转 → 全局 LUT 变化，<1e-4 像素闸不可吸收；自洽设计使「percentile→LUT→apply」链路确定性可验 + 直方图另以解析 ±1 bin 锁定（plan 验收原文即 ±1 bin） |
| 6 | levels automatic 256 bins（plan 指定），dt 用 16384 + FULL 从 preview 直方图 hash 同步 | plan mandate；每 run 重算 divergence 记录于模块头（#1） |
| 7 | tonecurve `tonecurve_preset`（UI-state int）不移植 | dt 内无像素效果；XMP blob 侧仍按 dt struct 全布局打包 |
| 8 | LabMath 常量：Lab 参考白 = Bradford×Rec2020→XYZ×(1,1,1)（非 dt 的圆整 ICC D50 (0.9642,1,0.8249)） | 锚定管线自身白点 → 中性 a=b=0 精确（轨 B 无色度噪声的前提）；与 dt 的差异 ~1e-4，uniform probe 证据按 1e-3 容差核算 |
| 9 | dt probe 路线对 Lab 链整体不可用（新 finding，见下）→ track-A 参考全部合成（L017 ①路线），dt 侧证据 = XMP 采纳实证（DB op_params hex + params ok 日志）+ 源码行号引用 | 见 manifest「colisa probe route unavailable」 |

## 本轮新发现（manifest + 模块头已落账）

1. **dt libcolisa/libtonecurve/liblevels .so 陈旧**：构建树内这三个插件先于 "Rename some OpenCL functions"（199d03a3c7）编译，libcolisa 引用已改名的旧符号 → **dlopen 失败，模块整个不加载**；`cmake --build --target colisa tonecurve levels` 重建后加载成功。liblevels 重建后同证；librgblevels 仍陈旧（启动期噪声，不进 golden 链）。
2. **dt-cli Lab 链 piece 态损坏（L017 扩展）**：XMP 采纳正常（DB op_params hex == 钉参 blob、`params ok`、`successfully loaded module ... from history`），但导出管线对 colisa/tonecurve 应用非确定 piece 态——饱和度=-1 时灰输入变黑（a=b=0 在任何增益下必须保持灰，数学上排除模块语义）→ probe 证据链中断；合成参考路线（L017 ①）覆盖 colisa/tonecurve/levels 全部 track-A。
3. **invert() 拼写错误自伤一次**：LabRoundTrip.swift 首版 reverse 矩阵 [2][1] 元素写错（`a0*b1` 应为 `a0*c1`）——往返测试当场抓获（往返恒等测试正是为此存在）；03-02 的 WhiteBalanceMath 同名函数本身正确（WB 的增益比值数学对该类错误不敏感，属侥幸），已复核。

## 交接给下游

- **03-04（shadhi + sigmoid）**：`LabRoundTrip`（Common/）直接复用——shadhi 的 Lab 域 L 通道模糊即 forward→op→inverse 同构；`LabMath.h` 内联函数是其 kernel 的模板。shadhi golden 同样走合成参考 + 采纳实证路线（probe 对 Lab 链不可用已证）。
- **03-06（filmic auto 三键）**：`HistogramReduce.histogramL` 单调用即可复用（bins 参数化）；auto black/white 需 min/max 归约时在同文件加 kernel 即可。
- **ParityGate**：后续一切 nearest-LUT 模块的标准闸；strictFraction/abs floor 已按实测物理标定，勿再收紧。
- **gen_fixtures.py `refs` 模式**：新增 Lab 模块 case 时扩展对应 `gen_<module>_refs` + `CASES` 表 + `regenerate.sh` ③ 段循环 + manifest 段落（levels_auto 的自洽参考注记是范例）。
- **dt 侧插件陈旧检查**：任何新 dt-cli golden 前先 `nm -u build/lib/darktable/plugins/lib<op>.so | grep copy_host` 核对符号代际（改名提交 199d03a3c7 之后才有效）。

## 环境注记

- dt 源码树本地补丁未动（sidecar_jobs.c 两处 no_thread_safety_analysis，03-02 遗留）；本轮仅重建三个插件 target + 生成 golden。
- Resilio Sync 按 L009 惯例 SIGSTOP 于构建期，会话结束 SIGCONT。
- `.work/plans/03-03/` 未立卷（过程探针均在 /tmp 内联，无长程产物）；本 SUMMARY + manifest + 模块头即全部记录。

## Artifacts

- `LightamerIOP/Sources/Common/`：LabRoundTrip.swift / LabMath.h / LabKernels.metal / IOPExpFit.swift / HistogramReduce.swift / HistogramReduceKernels.metal
- `LightamerIOP/Sources/{Colisa,ToneCurve,Levels}/`：.swift+.metal 对 ×3（ToneCurve 另含 ToneCurveLUT.swift）
- `App/Sources/Lightamer/UI/Inspector/`：CurveEditorView / ToneCurvePanelView / ColisaPanelView / LevelsPanelView + InspectorState 注册
- golden：`cases/{colisa_*,tonecurve_*,levels_*}.xmp` ×12 + 合成参考 `output/*.exr`（gitignored，regenerate.sh 可复现）+ manifest 映射表 ×3 + 自动参考注记
- Tests：`LabRoundTripTests`(6) / `ColisaParityTests`(7) / `ToneCurveParityTests`(8) / `LevelsParityTests`(9) / `ParityGate.swift` / PanelWiringTests +4
- VALIDATION IOP-TONE-03/05/06 ✅；TODO Phase 3 → 3/6

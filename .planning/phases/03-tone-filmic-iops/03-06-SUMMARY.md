# Plan 03-06 Summary — filmicrgb（F0-F4）+ agx 变体 + PERF-5 正式记录 + Phase 3 签核

**Status:** Complete（2026-09-20）
**验收:** 全 suite **267 tests / 0 failures / 3 documented skips**（连续两轮）；filmicrgb F0-F4 子阶段独立 golden 全绿 + `AgXTests` 5/5；PERF-5 正式 CI 记录落账（Release warm median 36.23ms，预算 16.6ms 未达、杠杆分配注记，见 `.work/plans/03/perf-record.md`）；`03-VALIDATION.md` 签核（`nyquist_compliant: true`，SC#3 ⚠️ 注记）。

## 交付物

- **T0 checkpoint（D-T1 范围定稿）**：三项决定全部按推荐采纳（colorscience 只落 V5 / 高光重建子树划出（仅 mask kernel + 参数位）/ preserve_color norm 家族全实现、V5 固定 MAX_RGB），用户确认记录 + 全部源码勘误落 `03-06-DECISIONS.md`。
- **T1 `FilmicSpline`（F0）**：`compute_spline` v1/v2/v3 三分支全直译（v3 运行时钉死、三分支单测覆盖）+ `_compute_output_power` + norm 界。`CPUDerivationTests` +6：默认组手算锚点（output_power=4.168313824554027、grey_display=2/3 精确落对角线、norm 界 0.000720703125/2.952）、10 点变参组对独立参考、curve 三型 × 三段连续性、非法组合（latitude>100/负对比度/极端 balance）无 NaN。
- **T2 `FilmicRGBKernels.metal`（F1+F2）**：`filmicrgb_v5` 单 kernel 逐式直译 `filmic_chroma_v5`（filmic.cl:651-719）——norm(MAX_RGB 钉死)→ratios（**无 sanitize**，plan 文本 v1 混写勘误）→log→spline→clamp→pow→max_rgb；naive 逐通道；(0.5∓sat) 混合；Ych/gamut 全链。`filmic_mask_clipped_pixels`（F5 参数位）。
- **T3/T4 `YrgGamut`（F3）**：`matrixIn/Out` = LMS2006·CAT16·Bradford·Rec2020 编译期常量积（dt `prepare_RGB_Yrg_matrices` 同构）；Yrg⇄Ych、`gamut_check_Yrg`、clip-chroma 族（Kirk 三角常量逐值搬移）、`filmic_desaturate_v4`、`gamut_check_RGB`。F3 golden：out-of-Rec2020 光谱块全部入域 + 中性轴不受 gamut 段影响（1e-6）。
- **T5 全模块**：`FilmicRGBModule`（v50=46.0 注册 + editing seed）；auto 三键 `AutoKey`（grey=/2 + K 对称移、black/white=全图 min/max 走新 `HistogramReduce.rgbMinMax` 两趟 uint 编码原子归约）+ `FilmicRGBPanelView`（形状滑块 + auto 键——grey 走吸管、black/white 走全图统计 + preserve/colorscience Picker + V5 锁定注记）。
- **T6 `AgXModule` + `AgXKernels.metal`（IOP-FILM-03）**：`_calculate_tone_mapping_params` 全推导（pivot/gamma 补偿斜率/toe/shoulder scale + fallback）+ primaries 四矩阵（复用 SigmoidProfile builder；base Rec2020==work 恒等）；`kernel_agx`（compress_into_gamut→log→trapezoid curve→look→gamma→HSV hue lerp）直译；v50=45.5 注册 + `AgXPanelView` + editing seed。hatchless 无对标注记。
- **golden 基建**：gen_fixtures.py +6 filmic case +6 agx case + float64 参考（**float32-FMA 逐式复刻**——M 系数 f32 发布网格 + `math.fma` 单舍入 Horner 复刻 Apple GPU fp-contract，缺一即 3-5e-5 系统差）；regenerate.sh ③d adoption probes（filmic/agx 每 case 单跑采 adoption 证据）；manifest 终稿两节字段映射表。
- **T7 PERF-5**：`PreviewChainPerfTests` 2/2 进套；`MetalContext.prewarmPipelineStates` + PipeCoordinator load 后台预热 Task（prewarm 名单含 16 kernel，`colorout_matrix` 因 isP3 function-constant 无默认不可泛型预热已注记排除）；`.work/plans/03/perf-record.md` 正式记录。

## 中间排障（探针抓出的缺陷/勘误）

1. **Python 参考 `log2(x)` 漏除 grey**（T5）：filmic_default×ramp 全像素 rel≈4.4——逐像素对照定位为参考端漏除；改 `log2(x/grey)` 后归零。教训延续 03-05「parity 失败先疑参考端」。
2. **Swift rational 闭合式漏 `−1`**（T5）：`(sqrt(...)−1)/(2x)` 的 −1 缺失使 soft_safe（rational shoulder）差 5e-3——Python/Swift 双实现互差定位到段级。
3. **float32 系数网格 + FMA**（T5）：陡 poly4 shoulder 上 Double 参考与 float32 GPU 差 3-5e-5/25% 像素——参考改为「f32 系数发布网格 + fma 单舍入 Horner」后塌缩到 ~1e-7（toneequal f32-choleski 同族决策）。
4. **`saturated` 划出 filmic 数值 parity**（T5）：RGB 块设计含零通道，round-trip 后 ±1e-7 噪声落 log 未定义边界，fast-math 符号/NaN 处理决定分支（dt 自身 CPU/GPU 腿亦不一致）→ 该 fixture 保留 F3 合法性靶、退出数值 parity（DECISIONS 落账）。
5. **PSO 预热崩溃**（T7）：`colorout_matrix` 的 isP3 function-constant 无 MSL 默认，nil-constants PSO 在 Metal validation abort（非 NSError）——预热名单排除并注记，显示档 PSO 由首渲自然预热。
6. **Release 测试构建三连**（T7）：DEBUG 探针调用未加 `#if DEBUG`（LightamerApp）；@testable 需 Release `ENABLE_TESTABILITY=YES`（Project.swift）；hardened runtime 库验证拒载同 Team-ID 框架（L011 同族）→ 正式门以 `ENABLE_HARDENED_RUNTIME=NO` CLI 覆盖跑 Release（项目设置不动）。

## PERF-5 结论（对 16.6ms 预算）

- **实测**：Release warm median **36.23ms**（11 iop 全链、稳定 imageID 拖拽形状、PSO 预热后；Debug 37.63；03-05 预验 63.4 的改善 = PSO 预热 + 形状修正——per-frame UUID 形状令输入平面每帧重物化 ~11ms，非 app 真实语义）。
- **预算账证伪**：RESEARCH §8 的 7-10 趟假设 → 实测 ~40 GPU 趟（toneequal EIGF ~12-15、Lab 往返 2×3、shadhi 模糊、元素级 ~10）。
- **晚链单滑块拖拽 2-6ms ✓ 60fps**（sigmoid/filmic/agx/colisa 等用户高频路径）；最坏情形 = exposure/WB tick（链首全下游重渲）。
- **剩余杠杆已分配**：管线级 Lab 往返共享（Open#9 → Phase 5+）、跨模块 dispatch 批合并（Phase 4+）、toneequal EIGF 分档降采样。SC#3 = ⚠️ 部分达成（VALIDATION 注记），Manual-Only Instruments 目检待人工。

## checkpoint 产物

- D-T1 三项范围决定 + 5 条源码勘误（V5 无 sanitize / Y1931→2006=1.05785528 含 CAT16 / gamut 段 saturation 恒 0 / auto_hardness GUI→commit / LUMINANCE 实现域）+ agx rendering_to_xyz 白点偏差 + PERF-5 口径 → `03-06-DECISIONS.md`。
- dt 侧证据形态：filmic/agx CPU 腿在本机导出崩溃（sigmoid per_channel SIGSEGV 同族扩展）→ 参考全合成；dt 侧 = 库 DB `op_params` hex（filmic 116B 逐字节核对）+ history load + piece commit + agx `params v. 7: version ok params ok`。

## Verification 对账

| VALIDATION 行 | 结果 |
|---|---|
| IOP-FILM-01（filmicrgb F0-F4） | ✅ `CPUDerivationTests` F0 节 6/6 + `FilmicRGBTests` 10/10（F1 三方分段门 + F2/F4 组合 parity + F3 入域/中性 + norm 族 + auto 三键 + F5 mask + 轨 B + 注册） |
| IOP-FILM-03（agx） | ✅ `AgXTests` 5/5（golden parity + 曲线不变式 + primaries 偏差钉双实现 + round-trip + 注册） |
| PERF-5 | ⚠️ 记录完成、预算未达：Release 36.23ms / 45ms 回归界；晚链 2-6ms ✓；杠杆分配（`.work/plans/03/perf-record.md`） |
| Phase 3 签核 | ✅ `03-VALIDATION.md` 签核（nyquist_compliant: true；SC#1/2/4 ✓、SC#3 ⚠️ 注记） |

**测试计数**：244（03-05 末）→ **267**（+F0 节 6、FilmicRGB 10、AgX 5、Perf 2；3 documented skips 不变）。

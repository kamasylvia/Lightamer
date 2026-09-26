# Plan 03-04 Summary — shadhi + sigmoid（D-T2 scene-referred 基线）

**Status:** Complete（2026-09-19）
**验收:** 全 suite **220 tests / 0 failures / 3 documented skips**（连续两次全量稳定）；shadhi parity <1e-4 + ΔE p99 <1.0、sigmoid parity <1e-5、GPU 曲线约束（f(0)/f(grey)/f(∞)）、双路径中性、轨 B 双向插入全绿。

## 交付物

- **T1 `Common/GaussianBlur`**：dt `_compute_gauss_params`（ZERO order，Double 推导 Float 发布）+ Deriche IIR col→row→store 三 pass（`device float4*` 双平面，dt `gaussian.cl` `__global float4*` 原形）。σ≤0 直通；bounds clamp 语义 = dt Labmin/Labmax。
- **T2 `ShadhiModule`**（v50=50.0，.Lab）：Lab 域 prep→blur→mix 三 kernel；overlay 数学（shadhi.c:399-490）标量直译（含 :462/:486 dt quirk）；commit-time derive（±2 rescale / compress ≤0.99 / 符号折叠 ccorrect / unbound_mask）。bilateral 腿 = Phase 5（checkpoint 决策记录在模块头），golden 全钉 `shadhi_algo=gaussian`。
- **T3/T4 `SigmoidModule`**（v50=45.3，.RGB）+ `SigmoidDerivation`：commit_params 四标量（paper_power=5^(−skew)、film_power 数值差分、film_fog、paper_exposure）**Double 推导**（偏离记录：dt 用 powf float32；publish 仍 float32 网格）+ primaries 矩阵链（`_calculate_adjusted_primaries` 方向语义；默认路径恒等）+ 双 kernel（per_channel 含 hue/energy 保持 40 行直译；rgb_ratio 含双曲 gamut 压缩）。
- **T5** `SigmoidPanelView`（四滑块 + processing Picker + dt 预设菜单）+ `ShadhiPanelView`（radius/shadows/highlights/compress/ccorrect ×2 + algo Picker——bilateral 显示但禁用 + Phase 5 注记）+ `InspectorState` 注册 + `PanelWiringTests` +4（append+drag 恰 1+1 条 commit、bilateral 守恒）。
- golden：shadhi 4 case + sigmoid 5 case × 6 fixture 钉参 XMP + manifest blob/sha256 映射表 + regenerate.sh 两段（`SIGMOID_PARAMS_FORMAT <ffffiffffffffi` 56B / `SHADHI_PARAMS_FORMAT <i8fIfi` 48B）。
- **D-T2 兑现**：sigmoid 基线（面板/golden/缓存链路）先于 filmicrgb 落地，03-06 read_first 可引用。

## 根因分析（本 plan 修复的三类缺陷，均由中间探针逐层定位）

1. **sigmoid GPU「符号翻转」（实为 G 通道取反）** — `SigmoidProfile.invert3` 行 1 第 3 列余因子单字符笔误：`(a[2]*b[0] − a[0]*b[1])/det`，应为 `b[2]`。默认参数下三个 primaries 矩阵本应恒等，G 行却成 `[0, 0.9735, −1.0001]` → 中性输入的 G = −f(v)（R/B 正确，故曲线约束测试只挂 G）。探针（打印 piece buffer + 直调 kernel）定位到「矩阵非恒等 → invert3 输出与数学验证不符 → 磁盘字节比对抓出单格」。教训：**Read 工具转写与磁盘字节可能有出入，疑点必须 `cat -v`/grep 原始字节定案**。
2. **GaussianBlur forward 分支丢失** — 首版 kernel 用 `texture2d<float, access::read_write>` 做 backward 的 `out.read + yc` 累加：**macOS 27/M4 上同线程 write→read 不回报写入值（返回 0）**，blur 静默退化为纯 backward 分量。dt 的 OpenCL 正因如此用 `__global float4*`。→ 按 dt 原形改 device buffer 平面（L018）。
3. **GaussianBlur 行 pass 原位读写 DC 坍缩** — 单平面原位实现下，backward 读到的「输入」是 forward 刚写的输出，平场增益坍缩为 `coefp·(1+coefn)` = 0.77578（σ=8，与观测 0.38789=0.5×0.77578 精确吻合）。→ 双平面（dt 水平 pass 本就是读一写一）。

## 附带发现与修复

- **L018（新 LESSONS）**：read_write 纹理同线程 RMW 不回报写入值；`.private` buffer 分配会**确定性毒化同进程后续 CI 渲染**（macOS 27 beta 驱动/分配器交互——σ=20 IIR 写入模式触发，viewed-下半帧丢失）。→ blur 平面统一 `.shared`；跨测试污染排查法（单跑→字母序前驱二分→参数内二分→分配路径替换）入 L018。
- **`GaussianBlur.coeffs` 改 Double 推导**：float expf 路径与 float64 参考的 ~ulp 系数差在大 σ（极点近 1，放大 ~1/(1−ema)²）下放大到 1e-4 级，破坏 shadhi parity 门；统一为 float64 公式的 float32 网格点后 shadhi 全绿。σ=20 的 GPU-vs-float64 残差 6e-6 = 纯 float32 舍入（同系数），gate 按 σ 分档（≤5: 1e-6，>5: 2e-5）并记录。
- **CPU 约束测试精度档位**：f(grey)=0.1845 断言在 float32 量化 scalars 下为 ~2e-8 漂移（非推导错误，`testSigmoidFourScalarDerivation` 同源互验 <1e-9 全过）→ 约束门分 Double 档（trace，1e-12）与 float32 网格档（1e-7）。
- **GoldenColorTests D-COL1 链范围收窄**：03-04 起 Registry 默认链带 sigmoid/shadhi；shadhi 默认阴影 +50 是**按设计生效**的局部算子（dt 同样默认启用），会空间性移动 patch 色度——D-COL1 是 02 期终端三件套色管理门，改为显式钉三件套范围（iop 级中性由 `SigmoidTests.testGraysStayNeutralOnBothPaths` + `ShadhiParityTests` 轨 B 独立把守，均绿）。
- **参考路线（L017 延续）**：shadhi/sigmoid golden 全部为 gen_fixtures float64 合成参考；dt 侧证据 = XMP v5/v3 blob 采纳实证 + 平场 PFM probes（sigmoid rgb_ratio 平场三点 ≤1e-5；per_channel 在本 dt 构建下 SIGSEGV，manifest 落账，由双实现+共享推导钉住）。smooth 案例的 primaries 路径钉双实现（dt 侧矩阵乘序歧义记录在模块头，Phase 5 复核）。

## Verification 对账

| VALIDATION 行 | 结果 |
|---|---|
| IOP-TONE-04（shadhi，Lab 域） | ✅ `ShadhiParityTests` 4/4（<1e-4 + ΔE p99<1.0 + 恒等逐像素 + 轨 B + 注册） |
| IOP-FILM-02（sigmoid） | ✅ `CPUDerivationTests` sigmoid 节 3/3 + `SigmoidTests` 6/6（5 case × 6 fixture <1e-5 + GPU 约束 + 中性 + 轨 B + 注册） |
| 轨 B 回归 | ✅ 双向插入绿；GoldenColor D-COL1 链范围收窄（理由见上） |

**测试计数**：199（03-03 末）→ **220**（+shadhi parity 4、sigmoid 6、gaussian 5、CPU sigmoid/shadhi 节 5、面板 wiring 2；3 documented skips 不变）。

## checkpoint 产物（对 plan）

- bilateral 腿 → Phase 5（与 IOP-DENOISE-03 共享 dt_bilateral 移植）— 模块头 + 面板注记落地。
- displayed-domain middle_grey 校准 = 产品语义任务，与 parity 解耦 — `SigmoidDerivation` 头注记录。

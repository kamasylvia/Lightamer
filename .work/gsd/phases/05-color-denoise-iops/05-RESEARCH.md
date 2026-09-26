# Phase 5 Research: Color & Denoise iops

**Researched:** 2026-09-21
**Confidence 汇总：** darktable 模式映射 = High（color 组 7 模块 + denoise 组 3 模块源码逐段核过，域/flags/kernel 全部实证）；噪声剖面机制 = High（`noiseprofiles.json` 本机解析实测：1.79MB / 19 makers / 433 models / per-ISO a[3]+b[3]）；raw-domain 不可移植裁决 = High（hotpixels/rawdenoise `IOP_CS_RAW` 源码实证 + Spike A CIRAW 无 hot-pixel 键双重证实）；NLMeans/wavelet GPU 预算 = High（dt tiling_callback factor/overlap 逐值核过）但 tile 内 max_scale 稳定性依赖 dscIn 全幅 stamp = Med（需 plan 期测试钉住）；bilateral 5D grid 的 grid-size 公式 = Med（`_compute_sigmas` 的 scale 折算实现期定稿）；monochrome CPU/CL sigma² 常量不一致 = High（dt 源码自身分歧，已定位到行）。

---

## Summary

Phase 5 = 12 个需求（IOP-COLOR-01..07/09 + IOP-DENOISE-01..04），ROADMAP SC#4 含**真实 60fps 拖动门**与 **tiling fallback 首次承重**（100MP NLMeans）。核心结论：

1. **12 需求 → 11 个 dt 模块映射，全部可移植**（槽位 V50Order 现表全数在）：colorbalancergb 41.5 / channelmixerrgb 28.5 / channelmixer 39.0 / vibrance 58.0 / colorzones 60.0 / monochrome 64.0 / velvia 57.0 / colorcontrast 56.0 + denoiseprofile 9.0 / nlmeans 29.0 / bilateral(surface blur) 10.0。**关键勘误（推翻任务书预判）**：dt `denoiseprofile`（9.0）**不是 raw-domain**——`default_colorspace = IOP_CS_RGB`（denoiseprofile.c:837-843），位于 demosaic(8.0) **之后**、colorin(28.0) 之前，处理 post-demosaic 线性 RGB；真正 raw-domain 的 hotpixels(6.0)/rawdenoise(7.0)/cacorrect(5.0) 才不可移植。**IOP-DENOISE-01 的最复杂移植（denoiseprofile.cl 波列 + NLMeans 双模式 + Anscombe VST）完全落在 CIRAW 显影域管线可达的位置**，无 Bayer 域障碍（与 04-05 cacorrect 教训对照，本阶段无同类风险）。
2. **per-camera 噪声剖面 = 直接搬 dt 的 JSON 机制**：dt 剖面不在代码里，是数据文件 `data/noiseprofiles.json`（本机实测 1,792,326 B，19 makers / 433 models，每 model 按 ISO 档存 `a[3]/b[3]` Poisson-Gaussian 拟合，每档 ~200B）；匹配 = maker 子串 + model 精确（noiseprofiles.c:227-333），ISO 插值 = 括弧档**线性插值**（noiseprofiles.c:375-390），miss 回落 generic（a=1e-4, b=0，纯 Poisson，noiseprofiles.c:28）。Lightamer v1 = 内置同一 JSON（~1.8MB，启动懒解析、按 maker 索引缓存）+ EXIF maker/model/ISO（RAW-06 已读）→ 线性插值 → generic 回落。**推荐内置全量**：体积一个量级小于 Lensfun 曾担心的数字，无网络依赖，与 Phase 1 spike 的正式验证闭环。
3. **NLMeans = Goossens 滑窗 GPU 方案直译，预算可承受但 60fps 拖动必须走 dt 同款预览降载**：5 个 kernel（dist/horiz/vert/accu/finish，nlmeans.cl:37-253），每偏移 q 跑 4 趟，搜索半径 K=7 时 120 组偏移 ≈ 481 趟；dt 预览管自带降载三件套（K clamp 3、decimate 半采样、scattering 改写——denoiseprofile.c:1626-1631 / nlmeans.c:368）——照搬后 PREVIEW ≈ 112 趟可控制在 ~30-60ms；100MP FULL working set factor 5.0（nlmeans.c:336）≈ 8.2GB > 3GB 预算 → **TilingPlan 首次承重**（halo = P+K，tiling_callback nlmeans.c:328-341）。
4. **colorbalancergb 是 color 组最大件，但 Phase 3 已铺好 70% 基建**：RGB→LMS2006→Yrg→Ych 的常量矩阵链与 `YrgGamut.swift`（filmicrgb F2-F4 已交付）同源；CL kernel `colorbalancergb`（extended.cl:752-1042，~290 行）单 pass 直译；4-way（global/shadows/midtones/highlights）Y/C/H + brilliance/saturation/vibrance/contrast 全部是 commit_params 预计算标量/向量 → uniforms，与 filmicrgb 的 CPU 推导 + GPU 求值模式完全同构。
5. **ROI/帧约定**：11 个模块**全部恒等 ROI**（dt 无一覆盖 modify_roi_out/in，全靠 `IOP_FLAGS_ALLOW_TILING` + tiling_callback）——ROI 协商在 Phase 4 已端到端，本阶段零协议改动，只有 tileHalo/tileWorkingSet 声明（`IOPModule.swift:124-130` seam 现成）。**L021 前提重申**：dscIn 已含 entry 缩放，denoise 的半径补偿用「roi.scale ÷ 入口 iscale」（dt `fmin(roi.scale,2)/fmax(iscale,1)` 同构），禁止再对 dscIn 乘 scale；**04-06 遗留的 toneequal/flip dscIn×scale 审计挂账在本阶段还清**（TODO Phase 3 遗留节 + L021）。
6. **golden 主轨 = 合成参考**（L017 约束不变）：11 个模块全是空间变化算子族（denoise 更是），dt-cli float EXR 不可作主轨；每模块 float64/float32 逐式复刻参考 + dt 侧三证据（DB op_params hex 采纳 + `--d params` ok + **均匀平场 PFM probe**——点态 color 模块平场入→平场出，恰是 L017 已证正确的域）。denoise 参考图像策略 = **clean fixture + 按剖面加噪（种子化 Poisson-Gaussian）→ 我们的 denoise vs float64 参考实现双方同跑比对**；dt-cli 只作参数采纳与平场恒等探针。
7. **IOP-DENOISE-04 拆解裁决**：chromatic noise → 由 denoiseprofile Y0U0V0 模式 + nlmeans chroma 参数承载（可移植，随 DENOISE-01/02 交付）；**hot pixels（dt hotpixels.c:94 IOP_CS_RAW）与 dark frame subtraction → defer**：前者需要 demosaic 前 Bayer 邻域（CIRAW 已消化，且 Spike A 证实 CIRAW 无 despeckle/hot-pixel 键可关），后者需要解码前传感器访问（CIRAW 不暴露）。defer 记录为正式决策（延续 D-04-05-T0-0 口径），不是缺口。
8. **60fps/PERF-5**：color 组 7 件全部单 pass 点态（每件 1-2ms@2560 Debug），链增量小；denoise 组是唯一重件。Open#9（管线级 Lab 往返共享）在 Phase 3/4 分配到「Phase 5+」——本研究**建议 v1 不做管线级 Lab leg**（§9 论证：Lab 模块在真实用户栈里会被 RGB 模块打断，共享腿的缓存域一致性问题复杂度 > 收益；36ms→16.6ms 的主杠杆是 dispatch 批合并 + PSO 预热），将其转为「若 SC#4 拖动门失败才启用」的预案，需 planner 认可这一改动。
9. **plan 切分建议 8 个**（依赖序：共享件+剖面基建 → color 两波 → denoise 三波 → 签核），每 plan T 数与验收要点见文末「Plan 拆分建议」节。

---

## Implementation Approaches

### 1. 模块清单与 v50 槽位（含 raw-domain 专项论证）

#### 1.1 需求 → dt 模块 → 槽位总表

源码树同 Phase 2-4（dc58cf0ba1，2026-08-02）。struct 字节数按 dt 定义逐字段累计（用于 XMP 钉参 blob 生成，L015 hex 配方）。

| 需求 | dt op | v50 槽位（V50Order.swift 行） | 域（dt default_colorspace） | params 版式 | flags | 移植裁决 |
|---|---|---|---|---|---|---|
| IOP-COLOR-01 | `colorbalancergb` | 41.5（:105） | **RGB** scene-linear（colorbalancergb.c:197-202） | v5：32 float + 1 enum = 132B（:60-110） | TILING+BLEND（:832 同族） | ✅ 直译（§4） |
| IOP-COLOR-02 | `channelmixerrgb`（显示名 "color calibration"） | 28.5（:62；与 diffuse 等 6 模块共槽，history 序 tie-break 已在 02-05 兑现） | **RGB** scene-linear（channelmixerrgb.c:254-259） | v3：6×4 float + 6 bool + 5 enum + x/y/temp/gamut/clip/version = 160B（:88-113） | TILING+BLEND（:244） | ✅（§5.1；color-checker 自动剖面子树 defer） |
| IOP-COLOR-03 | `vibrance` | 58.0（:139） | **Lab**（vibrance.c:83-88） | v2：1 float = 4B（:37-40） | TILING+BLEND+**DEPRECATED**（:72-76） | ✅ 单 kernel（§5.4；dt 标弃用、指 colorbalancergb 的 vibrance 滑块——我们按需求独立交付，头注记录） |
| IOP-COLOR-04 | `channelmixer`（legacy，显示名 "channel mixer"） | 39.0（:97） | **RGB**（channelmixer.c:157） | 3×4 float + algorithm enum = 52B（:81-96） | deprecated（:126 deprecated_msg） | ✅ 单 kernel 3×3 mix（§5.1 尾） |
| IOP-COLOR-05 | `colorzones` | 60.0（:140） | **Lab**（colorzones.c:159-164） | 3 曲线×20 节点 + channel/strength/mode/splines_version = 520B（:81-92） | TILING+BLEND（:149-153） | ✅（§5.2；CurveTools 复用） |
| IOP-COLOR-06 | `monochrome` | 64.0（:144） | **Lab**（monochrome.c:89-94） | v2：a/b/size/highlights 4 float = 16B（:47-53） | TILING+BLEND（:84-87） | ✅（§5.3；内含 bilateral grid 腿） |
| IOP-COLOR-07 | `velvia` | 57.0（:138） | **RGB** scene-linear（velvia.c:86-91） | v2：strength/bias 2 float = 8B（:41-45） | TILING+BLEND（:76-79） | ✅ 单 kernel（§5.5） |
| IOP-COLOR-09 | `colorcontrast` | 56.0（:137） | **Lab**（colorcontrast.c:102-107） | v2：4 float + unbound int = 20B（:36-43） | TILING+BLEND（:92-95） | ✅ 单 kernel（§5.6；rgbcurve/rgblevels 是否随行 → Open Question 1） |
| IOP-DENOISE-01 | `denoiseprofile` | 9.0（:33） | **RGB**（denoiseprofile.c:837-843）——**post-demosaic，非 raw** | v12：8 float + a[3]+b[3] + mode + x/y[6][7]×2 + 3 bool + wavelet_mode + bool = 244B（:99-129） | TILING+BLEND（:832-835） | ✅ 全项目第二难移植，两模式（§3 + §5.7） |
| IOP-DENOISE-02 | `nlmeans`（显示名 "astrophoto denoise"） | 29.0（:72，表注「needs a signal as scene-referred as possible (even if it works in Lab)」） | **Lab**（nlmeans.c:94-99） | v2：radius/strength/luma/chroma 4 float = 16B（:45-52） | TILING+BLEND（:145-148） | ✅ kernel 群直译（§3） |
| IOP-DENOISE-03 | `bilateral`（显示名 "surface blur" / "denoise (bilateral filter)"） | 10.0（:34） | **RGB**（bilateral.cc:94） | radius + reserved + red/green/blue 5 float = 20B（:52-58） | TILING（bilateral.cc） | ✅ 直接窗口 ≤6px + 5D grid 两档（§5.8） |
| IOP-DENOISE-04 | chromatic → 上面三件承载；hot pixels → dt `hotpixels` 6.0；dark frame → 无 dt 独立模块（rawprepare 域操作） | 6.0（:30） | **RAW**（hotpixels.c:94 `IOP_CS_RAW`；rawdenoise.c:161 同） | — | — | **chromatic ✅ 随 DENOISE-01/02；hot pixels / dark frame defer**（§1.2） |

槽位硬约束（iop_order.c 注释随 V50Order 移植已在表内）：
- **channelmixerrgb 28.5 紧跟 colorin 28.0**——表注「calibration to 'neutral' exchange colour space」（V50Order.swift:73-75）：它按工作色域 primaries 做 mix，必须在 colorin 之后。28.5 共槽 6 模块互斥共存的 tie-break 已由 02-05 `effectiveInstances()`（iopOrder+multiPriority+opName）覆盖，本阶段第一个真实消费者。
- **denoiseprofile 9.0 在 temperature 3.0 之后、lens 13.0 之前**：dt 语义 = 去噪在 WB 后（`wb_adaptive_anscombe` 默认 TRUE 即以 WB 系数为条件）、在几何重采样前（先去噪再插值，不放大噪声）。默认链天然满足。
- **nlmeans 29.0 在 colorin 28.0 之后**：Lab 域需要已校准的颜色（表注原文）。LabRoundTrip 的中性 a=b=0 锚定（03-03 T1）是它的 parity 前提。

#### 1.2 raw-domain 专项论证（任务书 §1 要求的勘误记录）

- **dt 管线的三段结构**：rawprepare(1.0) → … → cacorrect(5.0)/hotpixels(6.0)/rawdenoise(7.0) → **demosaic(8.0)** → **denoiseprofile(9.0)**/bilateral(10.0) → … → colorin(28.0)。5.0/6.0/7.0 三件在 demosaic **前**，处理单通道 RAW；`denoiseprofile` 虽名为 "raw denoise"（需求文案沿用），**实际在 demosaic 后的线性 RGB 上工作**：`default_colorspace` 返回 `IOP_CS_RGB`（denoiseprofile.c:837-843），process 直接消费 float4 RGB（:2598-2620），方差模型按「绿通道拟合 × WB 系数」应用到 RGB（process_wavelets 内 `aa = d->a[1]·wb`，:1519-1523）。
- **Lightamer 等价位置**：我们的管线入口 = CIRAW 已显影的 linear Rec2020——与 dt「demosaic 后、colorin 前的相机 RGB」同层（色域差 = 已知近似，dt 自身只用绿通道拟合 + WB 缩放，色域敏感性有限；记 divergence 头注）。**落在槽位 9.0**（temperature 3.0 后），管线数据流无任何新要求。
- **不可移植清单（正式 defer，非缺口）**：hotpixels（Bayer 域邻域检测，hotpixels.c:94 `IOP_CS_RAW`；:363-410 明确 `dt_image_is_raw` 才启用）；rawdenoise（RAW 域波列收缩，rawdenoise.c:161）；cacorrect（04-05-DECISIONS D-04-05-T0-0 已 defer 到本阶段复议——**复议结论：维持 defer**，同一 Bayer 域论证成立）。旁证：Spike A 实测 CIRAW 的 NR 键族里 `despeckleAmount=UNSUPPORTED`（spike-a-probe-output.txt:27-63 全样本），无 hot-pixel 开关可关——热像素已在 Apple 解码内处理或保留，我们无法在显影域重做 dt 的 Bayer 域检测。dark frame subtraction 需解码前传感器帧访问，CIRAW 不暴露，v1 无路径。
- **chromatic noise 承载**：denoiseprofile 的 `wavelet_color_mode = Y0U0V0`（默认，denoiseprofile.c:126-127）即亮度/色度分离去噪（Y0U0V0 空间 = "Secrets of image denoising cuisine" 变换，:1495-1502）；nlmeans 的 `chroma` 参数独立控色度平滑（nlmeans.c:51）。DENOISE-04 的 chromatic 半边随这两件交付，无独立模块。

### 2. per-camera 噪声剖面方案裁决（Phase 1 spike 的正式验证）

#### 2.1 dt 机制（源码 + 数据实测）

- **数据文件**：`data/noiseprofiles.json`（dt 树 data/ 目录，1,792,326 B）。结构：`{version:0, noiseprofiles:[{maker, models:[{model, comment, profiles:[{name, iso, a[3], b[3]}]}]}]}`。本机解析实测：**19 makers / 433 models**；单 model 的 ISO 档约 10-30 档（如 ILCE-9M3 从 ISO 125 起以 1/3EV 步进）；每档 ~200B。a/b = Poisson-Gaussian 方差模型 `var = a·I + b` 的逐通道（R/G/B）拟合，**标定域 = 传感器线性域**（文件头注释 "raw-raw data"，noiseprofiles.c:26 `DT_NOISE_PROFILE_VERSION`）。
- **匹配**（noiseprofiles.c:227-333）：maker 用 `strstr` 子串包含、model 用 `strcmp` 精确匹配；支持 `skip:true` 档位；miss → `dt_noiseprofile_generic = {a:1e-4×3, b:0}`（:28）。
- **ISO 插值**（:375-390）：取括弧两档**线性插值** a/b（源码自注 "stupid linear interpolation. to be confirmed for gaussian part"）。
- **消费**（denoiseprofile.c）：reload_defaults 按 EXIF ISO 自动选档（:2677-2690 起），highlight-preservation 整 EV 补偿（`_get_iso_highlight_preservation_shift`，:2693-2706，每整档 ISO ×2 计）；GUI 允许手动挑档/挑 generic。**wb_adaptive_anscombe**（:123）默认 TRUE：VST 的 p 参数按 WB 系数自适应（nlmeans_precondition :2313-2325 `p = shadows + 0.1·log(scale/wb)`）。

#### 2.2 Lightamer v1 方案（推荐 + 理由 + 体积）

**推荐：内置全量 JSON（1.79MB 入 bundle）+ EXIF 三元组（maker/model/ISO，RAW-06 已读）线性插值 + generic 回落，无网络、无用户配置。**

- **体积**：1.79MB 对桌面 app 可忽略（对照：Lensfun XML 实测 4.2MB 走首跑下载；剖面文件小一个量级且**无版本时效问题**——传感器噪声特性不随镜头库更新），不值得做「内置子集 + 下载补全」的复杂度。
- **解析**：Foundation `JSONParser`→ 无，用 `JSONSerialization` 单次解析（1.8MB 一次 ~50ms 级）+ 按 maker 建字典索引缓存；或构建期转成紧凑二进制（Codable 快照）。plan 期二选一，倾向**构建期转换脚本（gen_fixtures.py 同族）→ bundle 内自有格式**，规避运行时 JSON 键序/浮点解析差异（L013 精神：入身份的字段显式折叠；剖面不进身份哈希，风险低）。
- **许可证（Open Question 2）**：dt 的 noiseprofiles.json 是社区贡献数据（GPL 项目内）。Lightamer 开源（MIT 倾向）——数据文件再分发需核对贡献者许可；备选 = 运行时让用户指向 dt 安装的数据文件 + generic 内置。**默认按「数据文件单独 LICENSE 注记」处理，用户裁决。**
- **Phase 1 spike 的正式验证闭环**：spike-a 结论「RAW 9 不减少 denoiseprofile 移植需求（v9 下 CIRAW NR 键几乎全部 no-op——spike-a-probe-output.txt:31-50 实测 luminanceNR=NO-OP）」→ 本方案即其正式承接：剖面来源不依赖 CIRAW，CIRAW 键位 no-op 与我们无耦合。
- **UI**：denoiseprofile 面板 profile 行 = 「Auto（EXIF）」+ model+ISO 只读显示 + 手动 ISO 滑块 + generic；miss（未收录机型）toast 一次 + generic 生效，不阻塞。

### 3. NLMeans 移植难点（patch 距离 GPU 化 / 搜索半径与性能 / 100MP tiling 预算 / 共享件复用点）

#### 3.1 算法结构（nlmeans.cl 逐 kernel 核过）

Goossens et al. 2010 滑窗方案（nlmeans.cl:21-24 注明出处）——**patch 距离 GPU 化的关键是把 O(N·(2P+1)²) 的逐 patch 距离分解为「单偏移距离图 + 两次 separable box 累加」**：

1. `nlmeans_dist`（:37-68）：对每个搜索偏移 q，逐像素算 `|I(p) − I(p+q)|²·norm2`（Lab 域：norm2 = {nL², nC², nC²}，nL=1/120、nC=1/512，nlmeans.c:363-365）→ 单通道 buffer U4。
2. `nlmeans_horiz`（:70-123）：U4 沿 x 做 (2P+1) box 和（local memory 翼区填充，workgroup 滑窗）。
3. `nlmeans_vert`（:125-181）：沿 y box 和 → 完整 patch 距离；立即施加权重 `g = fast_mexp2f(dist·sharpness)`（:26-30，sharpness = 3000/(1+strength)，nlmeans.c:360）。
4. `nlmeans_accu`（:183-230）：对称累积 `U2 += w(p,q)·I(p+q) + w(p,−q)·I(p−q)`（权重图平移读取，出界置零）。
5. 全部偏移跑完后 `nlmeans_finish`（:233-253）：`out = in·(1−weight) + (U2/U3)·weight`（weight=luma/chroma 混合向量，nlmeans.c:213）。

偏移循环 = j ∈ [−K,0]、i ∈ [−K,K]（对称半平面，K = 搜索半径）：nlmeans 模块 K = ceil(7·scale)（nlmeans.c:172）；denoiseprofile NLMeans 腿 K = nbhood 参数（默认 7）+ scattering 扩展（denoiseprofile.c:1614-1631，`K_scattered = ceil(scattering·(K³+7K√K)/6)+K`）。K=7 → 120 组偏移 × 4 kernel + finish = **481 趟**。

#### 3.2 性能与 60fps 拖动策略

- FULL 质量渲染在任何分辨率都重（dt 同病）；**dt 的预览降载三件套照搬**：
  1. 预览/缩略图管 K clamp 到 3（denoiseprofile.c:1626-1631：`if(dt_pipe_is_fast||preview||thumb) K = MIN(3,K)`；nlmeans 模块自身没 clamp K 但有 decimate）；
  2. `decimate` 半采样 patch（nlmeans.c:367-368：preview/thumb 跳一半 patch；nlmeans_core 的参数位，GPU 腿在 dist/accu 里按 2 步进实现）；
  3. 我们的 D-C3 交互梯子：拖动 tick 用低一档 PREVIEW（1440px），松手 commit 后当前档重渲。
  三件叠加后 PREVIEW ≈ 28 组偏移 × 4 = 113 趟 @1440px（约 1440×1080×16B = 24MB/趟读写）≈ 30-60ms Debug——SC#4 拖动门的承载方案（配 §9 批合并）。
- denoiseprofile NLMeans 腿复用同一 kernel 群 + 前置 VST（precondition）+ 后置逆 VST（backtransform），`P==0` 退化为快速 bilateral（denoiseprofile.c:1809 注释原文）——**denoiseprofile 的 NLMeans 模式 = VST + 同一套 nlmeans kernel + 逆 VST**，plan 切分上先交付 nlmeans 模块、denoiseprofile 直接消费（共享件关系与 03-04 GaussianBlur → shadhi 同构）。

#### 3.3 100MP tiling 预算（TilingPlan halo）

- working set：dt `tiling_callback`（nlmeans.c:328-341）`factor = 2.0+1.0+0.25×4 = 4.0`（CPU）/ `factor_cl = 4.0 + 0.25×4 = 5.0`（in + out + U2(float4) + 4 个单通道轮转 bucket）。100MP FULL = 11648×8736×16B ≈ 1.63GB/平面 → **8.2GB > 3GB 预算 → 必然分块**（Spike B 实测 float32 单平面 1.55GB 峰值 2.0-2.8GB 同量级）。
- halo：`overlap = P + K`（nlmeans.c:339）——dist 的 q 偏移读 ±K、box 和伸 P；tileWiden = P + K 即可保证分块==整幅。TilingPlan（`LightamerCore/Sources/Pipe/Tiling/TilingPlan.swift:58-118`，overlap 内缩 + halo 外扩读）+ `executeTiledNegotiated`（`PixelPipe.swift:334-344`）现成，模块只声明 `tileHalo = P+K`、`tileWorkingSetBytesPerPixel = 5×16 = 80`。toneequal 首战（03-05 T6「强制分块 vs 整幅 <1e-5」双门）照搬为验收模板。
- **tile 内 K/P 常数稳定性**：dt 以 `piece->iscale`（pipe 级）而非 tile 尺寸算 P/K——我们对应「iscale 取入口 scale，不随 tile 变」；**约束：TILE 驱动不得改 dscIn/iscale stamp**（L021 已钉的管线约束，本阶段是它第一次真正承重，plan 加测试钉住）。
- denoiseprofile 波列模式 tiling：`factor_cl = 3.5 + max_scale`（≤10.5，denoiseprofile.c tiling_callback wavelet 分支）→ 100MP FULL 17GB 级 → 同样必然分块；`overlap = 2^max_scale`（≤128px）。**max_scale 由 buf_in 尺寸的 20% 支撑域规则导出**（:1436-1455）——dscIn 保持全幅 stamp 时 tile 内 max_scale 与整幅一致，band 数稳定，halo 2^max_scale 精确覆盖 5×5 a-trous 在最大 stride 的触达半径。

#### 3.4 共享件复用点（现码核过）

| 复用件 | 位置 | 服务于 |
|---|---|---|
| GaussianBlur（Deriche IIR + 双平面三 pass） | `LightamerIOP/Sources/Common/GaussianBlur.swift:80,164` | denoiseprofile 波列不直接用（eaw 是 5×5 a-trous 非 IIR）；nlmeans 无模糊腿。真正的复用是**kernel 工程纪律**（L018 buffer 双平面、local memory 滑窗同款） |
| HistogramReduce（两趟原子归约） | `Common/HistogramReduce.swift:44,140` | denoiseprofile 波列的 `sum_y2` 方差估计 = reduce_first/reduce_second 两趟 float4 归约（denoiseprofile.cl:493-577）——**同款两趟原子模式，值得抽成 `Reduce` 通用件或加 `sumOfSquares` kernel** |
| LabRoundTrip / LabKernels | `Common/LabRoundTrip.swift:36-125` + `Common/LabKernels.metal:18,28` | nlmeans 的 Lab 域往返（nlmeans 29.0 Lab）；与 03-03 同模式内联 |
| YrgGamut（CAT16/LMS2006/Yrg/Ych） | `LightamerIOP/Sources/FilmicRGB/YrgGamut.swift` | **colorbalancergb 的整条色空间链**（§4）；与 filmicrgb 共享编译期常量积 |
| CorrectionLUT / CurveTools | `ToneEqual/CorrectionLUT.swift` + 03-03 ToneCurve 的 curve_tools 移植 | colorzones 三曲线 → 0x10000 LUT（同 tonecurve 48/49 的 LUT 管线模式）；monochrome/denoiseprofile 的 force 曲线同族 |
| TilingPlan / executeTiledNegotiated | `Pipe/Tiling/TilingPlan.swift` + `PixelPipe.swift:334` | denoise 三件的 100MP 承重（§3.3） |
| ParityGate 双闸 | `Tests/LightamerTests/ParityGate.swift` | LUT nearest 截断双闸（03-03 定型）服务 colorzones/colorcontrast 的 LUT 查表 |

### 4. colorbalancergb（全局/primaries/4-way 数学链 + extended.cl 直译点 + UI 形态）

- **参数面**（colorbalancergb.c:60-110，v5）：4-way（global/shadows/midtones/highlights）各 Y(lum ∈[−1,1])/C(chroma ∈[0,1])/H(hue ∈[0,360]) 12 项 + shadows/highlights fall-off weight + white/mask-grey fulcrum + chroma 四区 + saturation 四区（+公式枚举）+ brilliance 四区（v2）+ vibrance/contrast/grey_fulcrum（v4）+ hue_angle。
- **数学链**（process :579-947 + kernel extended.cl:752-1042 逐段核）：
  1. 常量矩阵预乘（commit 时）：`RGB→[XYZ_D50]→[D65 CAT16]→LMS2006` 合成 input_matrix；逆链 output_matrix（:621-647）。**矩阵常量全部已在 YrgGamut.swift（filmicrgb 同链）**；我们工作域即 linear Rec2020，`Rec2020→XYZ` 常量在 LabRoundTrip——同一套，零新推导。
  2. 逐像素：clip 负值 → LMS → Yrg → Ych；`Ych.y = chroma`、`(Ych.z,w) = (cos,sin)h`；**opacity masks**：`pow(Y, 0.4101)` 为轴（0.1845 中灰 = 50%），shadows/midtones/highlights 权重滑块控制 fall-off（kernel opacity_masks）。
  3. hue 旋转矩阵作用于 (cos,sin)；chroma_boost = 全局+各区点积 + **vibrance = vib·(1−chroma^|vib|)**（extended.cl:807——dt 的 vibrance 滑块真身，deprecated 模块同公式族）；`gamut_check_Yrg`（YrgGamut 已有 clip-chroma 族）恒定 Y/h 裁 chroma。
  4. 回 RGB 后：global offset → shadows/highlights 双斜率掩乘 → midtones Y 斜率（幂）→ brilliance（chroma 缩放的亮度补偿）→ saturation 三版公式（v5 enum）→ contrast（grey_fulcrum 幂）。
  5. gamut_LUT（Ych 域 1D LUT，commit 时由 gamut 参数构建）。
- **直译点**：CL kernel 单 pass 320 行；CPU 侧 commit_params 的预计算（masks/weights/LUT/矩阵转置）照 filmicrgb 模式搬 Swift（FilmicSpline 的「CPU 推导 + GPU 求值」样板）；`mask_display`（棋盘格 mask 预览，kernel 尾部 checker 分支）v1 划出（Phase 6 蒙版域）。
- **UI 形态建议**：dt 是 4 个叠色轮 + 多组滑块。SwiftUI 推荐：4 折叠区（Global/Shadows/Midtones/Highlights）各含 hue 圆盘（Canvas 点击/拖动设 H，半径即 C——ToneEqualPanelView 的 Canvas 拖拽模式）+ Y 滑块；再加 Chroma/Saturation/Brilliance 三组四区滑块 + Vibrance/Contrast/Hue 滑块 + saturation 公式 Picker。默认全中性。**默认参数不恒等**（gamut_check 默认 gamut=1.0 对宽色域输入裁剪）→ seed **disabled**（与 highpass/soften D11 同款处置，DECISIONS 记录）。

### 5. 其余模块逐个

#### 5.1 channelmixerrgb（IOP-COLOR-02）+ channelmixer legacy（IOP-COLOR-04）

- **channelmixerrgb**（channelmixerrgb.c，4773 行）：核心 per-pixel = 5 条预计算矩阵路径之一（`channelmixer_rgb_xyz / cat16 / bradford_full / bradford_linear / rgb`，kernel 在 `data/kernels/channelmixer.cl:106-685`）+ mix 矩阵 + grey/saturation/lightness 行变换 + gamut 压缩（clip 负 RGB）。commit_params 重活在 CPU：illuminant 选择（D 系列/F 系列/LED/黑体/custom xy/camera）→ `illuminant_xy_to_XYZ`（`src/common/illuminants.h:181`）→ CAT16/Bradford 到 LMS 的 adaptation 矩阵（CAT16 常量已在 YrgGamut；Bradford 在 LabRoundTrip 有 D50 特例，**需要泛化为任意源白点**——增量小）；`find_temperature_from_raw_coeffs`（illuminants.h:220,389）把相机 WB 系数反解 CCT——**依赖 temperature.c 的 XYZ_to_CAM 逆向，Phase 3 WhiteBalanceMath 已有同源表格，可复用**。saturation 三版公式（v3 enum）+ normalize 开关逐式直译。
- **v1 划出**：color-checker 自动剖面子树（`_extract_color_checker`/24 色块单应/delta-E 求解，:2114-2230 的 run_profile 分支 + `src/common/colorchecker.h`）与 AI WB 检测（`#ifdef AI_ACTIVATED`，默认不编译）——前者是「拍色卡自动建 profile」工作流（建议 v2/Phase 12 预设生态再议），划出后 channelmixerrgb 剩 ~1500 行核心，量级与 filmicrgb 相当。**params 位保留**（illuminant enum 含 camera/检测项时 UI 禁用+注记）。
- **channelmixer legacy**（channelmixer.c，39.0）：3×3 增益矩阵（每输出通道 R/G/B ∈[−200%,200%]）+ algorithm v1/v2（v2 含输出归一）。单 kernel（extended.cl:140 `channelmixer`）。与 channelmixerrgb 的 mix 行数学重复但语义独立（无 illuminant/无 gamut）；作为独立小模块交付（UI = 输出通道 Picker + 3 滑块），golden 合成参考 trivial。**注意 dt 已弃用**（deprecated_msg :126）——我们按 IOP-COLOR-04 需求交付，头注记录。

#### 5.2 colorzones（IOP-COLOR-05）

- 3 条曲线（L/C/h）各 ≤20 节点，select-by = L(/100)/C(/128)/h(atan2(b,a))；曲线类型 CUBIC_SPLINE/CATMULL_ROM/MONOTONE_HERMITE = **tonecurve 已移植的 curve_tools 三插值同族**（03-03 T3），v2 splines（`dt_draw_curve_calc_values_V2`，colorzones.c:2871 路径）需增量核对与 curve_tools 的差异（plan 期对照 draw.h；若 V2 只是端点处理差异则复用）。commit 时 3× 0x10000 float LUT（:123 `lut[3][0x10000]`，构建 :2871 起）——tonecurve/levels 的 LUT 管线模式直接套。
- 逐像素（process_v3 :526-570）：h=atan2(b,a) 归一、C=hypot(b,a)；select 曲线查 LUT 得 Lm/Cm/hm；`L' = L·2^(4·Lm)`、a'/b' = C·Cm 转 (h+hm) 角。hue 模式自带低饱和混合抑制（blend = (1−C/128)²）。smooth/strong 两模式（v1 legacy 分支只做 strong parity 备查）。kernel `colorzones_v3`（basic.cl:3131-3185）+ 3 LUT 纹理上传（256×256 伪装纹理，我们直接用 MTLBuffer float 数组 + 手写索引查表，同 CorrectionLUT 模式）。
- **UI**：3-tab（L/C/h）Canvas 曲线编辑器（拖节点）+ select-by Picker + strength + mode——**CurveEditorView（03-03）拖节点/命中/外推整套复用**，加 colorzones 特有的下方 hue 色带背景。

#### 5.3 monochrome（IOP-COLOR-06）

- 数学（monochrome.c:168-239）：`filter = exp(−clamp(((a−ai)²+(b−bi)²)/σ²,0,1))`（σ² = (size·128)²，a/b = Lab 色度平面上的滤镜色相点）→ 对 filter 贡献做 **bilateral grid 平滑**（sigma_r=250、sigma_s=20/scale、detail=−1 基底层，:225-229）→ `envelope(L)`（:177-195 分段）+ highlights 滑块混合 → `out = (1−t)·in + t·(filter/100)·in`。
- **关键发现（dt 自身 CPU/CL 分歧）**：CPU `sigma2 = 2.0f·(size·128)²`（:205）vs CL `sigma2 = (size·128)²`（:257）——差 2 倍滤波宽度。**golden 参考钉 CPU 版**（dt-cli 无 OpenCL 走 CPU 路径），Lightamer kernel 按 CPU 公式，头注记录 dt CL 腿的已知偏差。
- **bilateral grid 腿的选型（plan 级决策，Open Question 4）**：(a) 移植 dt 3D bilateral grid（`src/common/bilateral.c` splat/blur/slice + bilateral.cl 的 grid kernel——与 surface blur 的 5D grid 是**两套不同实现**，monochrome/bilat/shadhi 用 3D luma grid）；(b) 用 03-05 EIGF 替代（语义近似、公式不同 → golden 走合成参考，放弃 monochrome 的 dt-cli 平场外一致域）。推荐 (a)：3D grid ~300 行 C + 3 kernel，换 monochrome + 未来 bilat/shadhi bilateral 腿的 dt 同源 parity，性价比高；且 grid splat 的原子散射与 HistogramReduce 同模式。
- **UI**：Lab 色度平面色轮（Canvas 点击设 a/b——dt 同款交互）+ size + highlights 滑块。

#### 5.4 vibrance（IOP-COLOR-03）

单参数 Lab 点态：`sw = √(a²+b²)/256`；`out = {L·(1−0.25·amount·sw), a·(1+amount·sw), b·(1+amount·sw)}`（vibrance.c:111-127）。单 kernel 直译。dt 标 DEPRECATED 指向 colorbalancergb 的 vibrance——两者公式不同族（此为 Lab 域旧版、彼为 Ych 域），**按需求独立交付**，面板单滑块 + 模块头注记录弃用背景与推荐去向。

#### 5.5 velvia（IOP-COLOR-07）

RGB 线性域点态（velvia.c:162-197）：pmax/pmin → psat（HSL 饱和公式）→ pweight（低饱和 + 黑白两端加权，bias 控 mid-tone 偏置）→ `out[c] = clamp(c + sat·(c − 0.5·(othersum)), 0, 1)`。**注意 clamp [0,1] 是 dt 公式本体**（对 >1 的 HDR 值会截断）——照搬保 parity，头注记录 scene-referred 语义局限（dt description 也自认 display-referred 倾向）。单 kernel。

#### 5.6 colorcontrast（IOP-COLOR-09）

Lab 域 a/b 通道线性斜率+偏移：`slope={1,a_steepness,b_steepness}`、`offset={0,a_offset,b_offset}`；unbound=1 无界、否则 clamp a/b ∈[−128,128]（colorcontrast.c:189-220）。单 kernel。**「color correction curves」半边的 rgbcurve(42.0)/rgblevels(43.0)**：与已交付 tonecurve/levels 同构（RGB 通道版），增量 = 联动表重推导已在 03-03 做过（tonecurve 的 XYZ/RGB 联动），建议划出或 stretch（Open Question 1）。

#### 5.7 denoiseprofile（IOP-DENOISE-01，全项目第二难移植）

- **双模式 + auto**（:99-129）：WAVELETS（默认）/ NLMEANS / VARIANCE（自动方差估计）+ 各自 AUTO 档。v1 交付 WAVELETS + NLMEANS 两模式；VARIANCE（process_variance :1890 起，局部方差统计自动定 strength）划出（Open Question 5），AUTO 档先映射到「用剖面 infer 参数族」（`infer_radius/scattering/shadows/bias_from_profile`，:2622-2650 已有解析式，直译即可）。
- **波列模式管线**（process_wavelets :1423-1658 + denoiseprofile.cl）：
  1. precondition VST（Anscombe 广义）：v1 legacy（:denoiseprofile.cl:31-54）/ v2 general power（:56-79）/ Y0U0V0 变体（:81-114）——参数 a·compensate_p、p(shadows+WB 自适应)、b、wb 全 commit 时算好 → uniforms。
  2. 逐 band（≤7）：`denoiseprofile_decompose`（:421-465）= 5×5 B3-spline a-trous + **edge-aware 权重** `weight = fast_mexp2f(max(0, |c1−c2|²·inv_sigma2 − 9))`（:434-447，var=0.02/off2=9）→ detail = pixel − coarse；reduce_first/second 两趟归约 sum_y2（:493-577）；**Bayesshrink 阈值**（variance_stabilizing_xform，denoiseprofile.c:1346-1422）：`thrs = 8·force²·4·sb2/std_x`，force = 6 通道（ALL/R/G/B/Y0/U0V0）× 7 band 用户曲线（x/y 表 → commit 时算 force，:1380-1420）；`denoiseprofile_synthesize`（:467-486）软阈值 `copysign(max(0,|d|−thrs),d)·boost + coarse`。
  3. backtransform（逆 VST，:327-400 三变体）+ bias 校正。
  - band 循环里 out 原地累加（synthesize 写 out=out+…）——**L018 红线**：MSL 同线程 read_write 纹理 RMW 不可靠 → 照 dt CPU 原形用 `device float4*` buffer 平面，band 间双缓冲（decompose 读 buf1 写 buf2，swap）。
  - 5×5 filter 常量 = B3 样条外积 25 tap，CPU 传入 buffer（与 dt 一致，filter 由宿主构建，:1562 传参）。
- **NLMeans 模式**：precondition → nlmeans kernel 群（§3）→ nlmeans_backtransform（denoiseprofile.c 侧，含 bias）。norm 公式 `0.045/(2P+1)²`（:1638-1650，fix_anscombe_and_nlmeans_norm 兼容开关默认 TRUE）。
- **wb_adaptive_anscombe / use_new_vst / fix_norm 三个兼容 bool**：默认全 TRUE，params 结构保留位（sidecar 兼容），kernel 走新路径；legacy 路径不移植（头注）。
- **tiling_callback 波列分支**（factor_cl = 3.5+max_scale、overlap = 2^max_scale）→ tileHalo 声明；max_scale 推导（20% 支撑域规则）用 dscIn 全幅尺寸（§3.3 tile 稳定性约束）。

#### 5.8 bilateral / surface blur（IOP-DENOISE-03）

dt `bilateral`（bilateral.cc，order 10.0）：RGB 域，radius（空间 σ，1-50 默认 15）+ 三通道域 σ（默认 0.005）。三档实现（:121-318）：rad = `3σ_s+1`，**rad ≤ 6 → 直接窗口核**（高斯空间权重 × RGB 域高斯权，:175-254）；**rad > 6 → 5D permutohedral lattice（CPU）/ 5D grid（CL，bilateral.cl：grid_splat/blur×5/slice，原子散射）**；thumbnail 直接跳过。`_compute_sigmas` 把 radius 按 roi.scale/iscale 折算（:320 起，实现期逐行核——**Confidence Med**）。Metal 方案：rad≤6 单 kernel 直接窗口（small-radius 主场景，PREVIEW 常态）；大半径走 5D grid 三 kernel（splat 用 atomics 同 HistogramReduce 模式；grid 尺寸 = ceil(dim/σ) 积，**plan 期钉公式与内存上界**，超预算回落 tiling）。tiling `overlap = rad`（bilateral.cc:360）。

### 6. ROI/帧约定（逐模块 modifyROIIn/Out 语义 + 坐标系前提）

- **全部 11 个模块 ROI 恒等**：dt 无一覆盖 modify_roi_out/in（逐文件 grep 证实），空间支持全靠 `IOP_FLAGS_ALLOW_TILING` + tiling_callback 的 factor/overlap。Lightamer 对应：modifyROIOut/In 全用协议默认恒等（`IOPModule.swift:138-143`），空间算子声明 `tileHalo/tileWorkingSetBytesPerPixel`：

| 模块 | modifyROI | tileHalo | tileWorkingSet B/px | 依据 |
|---|---|---|---|---|
| colorbalancergb/channelmixerrgb/channelmixer/colorcontrast/vibrance/velvia/colorzones | 恒等 | 0（禁 tile） | 16 | 点态；dt 标 ALLOW_TILING 但无邻域 |
| monochrome | 恒等 | 3D grid 半径（≈2σ_s，monochrome.c tiling_callback :316-340 factor 3.0+bilat_mem） | 16+grid 摊销（plan 钉） | 内部 bilateral grid |
| nlmeans | 恒等 | P+K（nlmeans.c:339） | 80（factor_cl 5.0×16） | §3.3 |
| denoiseprofile（NLMeans 腿） | 恒等 | P+K_scattered（tiling_callback :2200-2215） | 80 | 同上 |
| denoiseprofile（波列腿） | 恒等 | 2^max_scale（≤128） | (3.5+max_scale)×16 上界 | §3.3 |
| bilateral | 恒等 | rad（bilateral.cc:360） | 直连 32 / grid 按 grid_bytes 摊销（plan 钉） | §5.8 |

- **坐标系前提（L020/L021 强制重申）**：
  1. dscIn 是**本 run 平面像素**（已含 entry 缩放 + 前向 ROI 协商），模块钩子与 process 内**禁止再 ×scale**——denoise 半径补偿只用「roi.scale ÷ 入口 iscale」标量（dt `fmin(roi.scale,2)/fmax(piece.iscale,1)` 同构，nlmeans.c:170）。**协议增量：`IOPiece` 补 `iscale`（入口 scale，run() 随 dscIn 一起 stamp，dt piece->iscale 同构）**——一行级管线改动，denoise 四件与未来 atrous/lowpass 共用。
  2. tile 驱动不改 dscIn/iscale stamp（现约束「TILE 不得改 dscIn」的推广），否则 max_scale/P/K 漂移。
  3. 内容级断言兜底（L020 对策③）：denoise 模块的记账测试（分块==整幅）之外，必须有**内容级** parity（合成参考），纯尺寸断言对错位免疫。
- **04-06 遗留审计（本阶段还账）**：toneequal（blending 直径 preview 半径偏小，质量向）/ flip（.none 恒等免疫）的 `dscIn × scale` 同类排查（TODO Phase 3 遗留节；L021）→ 并入 Plan 5-1 共享件 plan 的第一个 task，逐处核实并补常驻回归。

### 7. Golden 验证策略（逐模块参考来源 + 钉参 case 数 + 容差档）

**L017 约束下的分流**（denoise 全族是空间变化算子；color 组虽然点态，但 dt-cli 侧仍以平场 probe + 采纳实证为 dt 证据，变化图像 EXR 不采信）：

| 模块 | 轨 A（dt-cli） | 合成参考（L017 路线①） | 轨 B | 钉参 case 数（初值） |
|---|---|---|---|---|
| colorbalancergb | 平场 PFM probe + DB op_params hex 采纳（116B blob v5）+ `--d params` ok | float64 逐式复刻（Rec2020→LMS2006→Yrg→Ych→4-way→逆链；矩阵常量与 YrgGamut 同源交叉验证）+ 全默认逐字节恒等门（in-gamut fixture）+ 各参数族方向断言 | ✅ | 6 case × 4 fixture |
| channelmixerrgb | 同上（160B blob v3） | float64 矩阵链复刻（illuminant→CAT 矩阵 + mix + sat/lightness/grey 三版公式）；CAT16/Bradford 常量与 YrgGamut/LabRoundTrip 交叉 | ✅ | 6 case × 4 fixture |
| channelmixer | 同上 | 3×3 mix 公式参考（trivial） | ✅ | 3 case × 4 fixture |
| colorzones | 平场 probe（平场 → h/C 常数 → 查表 → 平场）| 曲线 LUT（CPU 参考与 CurveTools 同源）+ 逐像素公式参考；LUT 索引双闸（ParityGate，03-03 定型） | ✅ | 4 case × 4 fixture |
| colorcontrast | 平场 probe | 线性公式参考 + unbound 双档 | ✅ | 3 case × 4 fixture |
| vibrance | 平场 probe | 公式参考 + amount=0 恒等 | ✅ | 2 case × 4 fixture |
| velvia | 平场 probe | 公式参考 + strength=0 恒等 + clamp 行为点检 | ✅ | 3 case × 4 fixture |
| monochrome | 平场 probe（平场 → filter 常数 → grid 平场 → 恒等？否——filter·in 仍是标量乘，恒等仅 size 使 filter→1 时）| float64 复刻 filter+envelope+highlights；bilateral grid 腿按 (a) 方案移植时 grid splat/blur/slice 的 float64 参考（grid 逻辑确定性，64×64 小图可 Python 复算）；按 (b) EIGF 替代则公式随 EIGF | ✅ | 4 case × 4 fixture |
| denoiseprofile（波列） | **加噪图不可 dt-cli**（空间变化 + L017）；采纳实证照走（244B blob v12 hex + params ok + 平场恒等探针：平场加噪关闭 + force=0.5 默认下平场去噪≈平场，容差档） | **clean + 按剖面加噪 → 双方同去噪比对**：gen_fixtures.py 增 Poisson-Gaussian 加噪器（`var=a·I+b`，种子化，numpy Generator）；参考实现 = 波列链 Python/float64 逐式复刻（decompose 权重、Bayesshrink 阈值、VST 逆变换；64-128px 小图可行性已核——5×5 stride 翻倍逐 band） | ✅ | 5 case × 3 fixture（含深阴影/高饱和 torture crop） |
| denoiseprofile（NLMeans 腿） | 同上 | nlmeans Goossens 算法 Python 参考（小图）+ VST 前后变换复用波列参考件；P=0 退化为 bilateral 的解析点检 | ✅ | 3 case × 3 fixture |
| nlmeans | 同上 | 同一 Goossens Python 参考（Lab 域 norm2 修正）；strength→∞/luma=0 等极限点检 | ✅ | 4 case × 3 fixture |
| bilateral | 同上 | rad≤6 直接窗口公式参考（float64）；5D grid 参考按 grid 逻辑复刻（小图）；σ→ 极限恒等 | ✅ | 3 case × 3 fixture |

- **加噪器即剖面验证器**：用 noiseprofiles.json 里某真实机型档位（如 ILCE-9M3 ISO 125/1600）对 clean fixture 加噪 → 我们的 denoiseprofile 用同剖面去噪 → 与参考实现比对；**再加一档「剖面错配」（ISO 125 剖面去噪 ISO 1600 噪声）断言欠去噪方向**——这就是 Phase 1「raw denoise profiling feasibility」spike 的正式量化验证（SC#2）。
- **fixture 增补**（现 18 RAW + 74 合成 EXR 基础上）：① 加噪版 canonical 集（按上述剖面）；② hue 全环 sweep 渐变（colorzones/colorcontrast 的 select 域覆盖；喂我们自己的管线做 parity，无 L017 风险）；③ delta 脉冲图（nlmeans/bilateral 核响应目检 + 参考比对）；④ 深阴影噪声 torture crop（SC#3 的 torture 三件套直指）。
- **容差档**（ParityGate 双闸沿用）：点态 RGB/Lab 数学 <1e-5 rel（03 门）；含 pow/cbrt 链的 Lab 通道 <1e-4 + ΔE76 p99<1.0（03-03/03-04 门）；denoise 族 <1e-3 rel + 恒等/极限门逐字节（累加顺序差容差）；LUT 查表走双闸（≥99% <1e-5 + 2.5e-5 floor / 1e-4 包络）。
- **dt 侧采纳证据模板**：每模块 1 组钉参 XMP（L015 hex 配方；gen_fixtures 增 `denoiseprofile_params_blob`/`channelmixerrgb_params_blob` 等）→ 库 DB op_params hex + `--core -d params` "version ok params ok" + 平场 PFM probe——三件套照 03-02 定式，manifest 逐模块落账。

### 8. GUI 面（按 AGENTS.md 约定 + PLAYBOOK §4 红线）

- **面板清单**（全部走 D-T6 `IOPPanelProvider` + `LightamerSlider` 三件套映射 + zh/en String Catalog + L010 identifier）：
  - ColorBalanceRGBPanelView：4 区折叠（Global/Shadows/Midtones/Highlights），每区 hue 圆盘（Canvas 拖动，半径=C）+ Y 滑块；Chroma/Saturation/Brilliance 三组四滑块；Vibrance/Contrast/Hue/Fulcrum 滑块；saturation 公式 Picker。
  - ChannelMixerRGBPanelView：三输出通道 × 三增益滑块矩阵 + normalize 开关 + saturation/lightness/grey 组 + illuminant 区（D/F/LED/黑体/custom/camera Picker + x/y 或 CCT + adaptation Picker + gamut 滑块 + clip 开关）；色卡剖面区 v1 隐藏（参数位保留）。
  - ChannelMixerPanelView（legacy）：输出通道 Picker + 3 滑块 + 算法 Picker。
  - ColorZonesPanelView：L/C/h 三 tab 曲线（CurveEditorView 复用 + hue 色带背景）+ select-by/strength/mode 控件。
  - MonochromePanelView：Lab 色度色轮 Canvas（点击设 filter 色）+ size + highlights。
  - VibrancePanelView / VelviaPanelView / ColorContrastPanelView：滑块组（1/2/4+toggle）。
  - DenoiseProfilePanelView：mode Picker（Wavelets/NLMeans）+ profile 行（Auto(EXIF)+机型/ISO 只读 + 手动 ISO + generic）+ patch/search radius/strength/shadows/bias/scattering/central-weight 滑块 + Y0U0V0|RGB Picker + 7-band force 曲线（ALL/Y0U0V0 tab，Canvas 曲线——CorrectionLUT 的同源曲线模式）。
  - NLMeansPanelView：4 滑块。BilateralPanelView：radius + 3 σ 滑块。
- **红线对照**：视口主导（新增面板不撑宽 Inspector，280pt 约束沿用 L021 布局定案）；交互路由全走 D-H1（拖动实时 → 松手恰 1 history commit）；XCUITest identifier 全量；交互手感挂 L011 口径（Manual-Only 表登记）。
- **PanelWiringTests 增量**：每面板 ≥1 代表性滑块的「拖动=恰 1 commit + 归零还原 paramsHash=缓存全 hit」断言（03-02 定式）；denoiseprofile 的 profile 行切换 = 离散单 commit 断言。
- **GUI 验收轮**（AGENTS.md Phase 执行模型硬性项 + PLAYBOOK）：UI-bearing plan 收尾跑真实 RAW 载入 → 模块行点击展开 → 代表性滑块 AX 拖动 → screencapture 量化（亮度域/无伪影）→ FINDINGS.md 登记；denoise 面板额外目验「启用后渲染变化 + 预览降载下无 tile 缝」（tile 缝人工判据 + 分块==整幅自动门双保险）。

### 9. 性能预算（GPU 趟数 + 100MP working set + PERF-5 杠杆兑现）

- **GPU 趟数/模块**（PREVIEW ≈2560px，Debug 单趟 ~1-3ms@70MB 平面）：color 组 7 件各 1 趟（~1-2ms）；monochrome ~12 趟（filter+grid 9+apply）；bilateral ≤10 趟（直连 1 趟小半径）；denoiseprofile 波列 ~25-30 趟（precondition+≤6 band×4+backtransform）；nlmeans 满血 481 趟 / **预览降载 ~113 趟**（§3.2）。链增量主要来自 denoise 启用场景——单帧全链预期 33ms 基线 + color 组 ~10ms + denoise 单件 30-60ms。
- **100MP FULL working set**：全链基线 1.63GB/平面；denoise 三件 tiling 承重（§3.3 预算表）——`MemoryBudgetTests` 扩展：denoise 模块 FULL Δfootprint 有界（TilingPlan 网格 + halo 记账），验收照 toneequal「Δfootprint <3GB」门。**TilingPlan 自 02-05 脚手架 + 03-05 首战后，本阶段成为多模块常态路径**（nlmeans/denoiseprofile/bilateral/monochrome 四消费者），executeTiledNegotiated 的回归网要先行加固（照 04-01「先加测试再动实现」纪律）。
- **PERF-5 / SC#4 60fps 杠杆分配**：
  1. **dispatch 批合并**（04-07 分配到 Phase 4+，未兑现）：同模块多 kernel 的 encoder 复用 + 跨小 kernel 合批——denoise 的 kernel 群是最大受益者（波列 25 趟 → 若共享 encoder 会话省 launch 开销）。建议本阶段落一个 bounded 版本：`MetalContext` 增「多 dispatch 复用 command buffer」辅助（现 dispatch2DTexture 每 dispatch 一 commit？——若已是批内复用则记录并关闭此项，plan 期核）。
  2. **Open#9（管线级 Lab 往返共享）处置变更（需 planner 认可，见 Summary#8）**：v1 不做。论证：① Lab 模块链在真实栈中被任意 RGB 模块切断（tonecurve 48 与 colorcontrast 56 之间隔着 filmic/sigmoid 族 45-46），共享腿只对连续 run 生效，收益不稳；② 共享腿的中间平面是 Lab 值 → 每模块缓存平面的域随邻居组合变化，PipeCacheKey 需绑域一致谓词，复杂度/风险 > 恒定 2 趟/模块的收益；③ 36.23→33.42ms 的实测构成（04-07）显示全链成本分散在 ~40 趟小 kernel，批合并与 Release/PSO 预热杠杆更大。**替代承诺**：SC#4 拖动门若在 denoise/color 全启用链上实测失败，Open#9 作为应急 plan 启用（触发条件与门槛写进 plan）。
  3. **denoise 预览降载三件套**（§3.2）+ D-C3 拖动梯子降档 = SC#4 的直接兑现点。
- **signpost 记账**：新模块逐个记录单帧增量（04-07 模式），`.work/05/perf.md` 落账；只对 SC#4 拖动门设门，全链重渲沿用「只记录不设门」既定口径。

### Plan 拆分建议（8 个，依赖序）

| Plan | 内容 | T 数（估） | 验收要点 |
|---|---|---|---|
| **5-1 共享件与剖面基建** | `NoiseProfileStore`（JSON/转换+匹配+插值+generic 回落 + Tests）；`IOPiece.iscale` 协议增量 + PixelPipe stamp；bilateral 3D grid（monochrome 用，若 OQ4 选 a）；HistogramReduce 抽 `sumOfSquares`/两趟归约通用化；gen_fixtures.py 增加噪器 + 新 fixture（hue sweep/delta/噪声集）+ 剖面钉参 XMP 配方；**L021 遗留审计（toneequal/flip dscIn×scale）**；executeTiledNegotiated 回归加固 | 7-8 | 剖面匹配/插值单测（手算向量）；加噪器统计检验（variance 实测 vs a·I+b）；L021 审计结论逐处落账；tile 回归先行全绿 |
| **5-2 colorbalancergb** | §4 全链：Swift 预计算 + kernel 直译 + 4-way 面板 + golden（含 in-gamut 恒等门） | 4-5 | 6 case parity <1e-5 + 平场 dt probe 三证据 + Canvas 色轮拖动=1 commit |
| **5-3 channelmixerrgb + channelmixer** | §5.1 两模块 + illuminant/CAT 泛化 + mix/sat/lightness/grey + 两面板 + golden | 5 | 矩阵链 float64 交叉 + illuminant 变更缓存失效链 + legacy 单 kernel parity |
| **5-4 colorzones + colorcontrast + vibrance + velvia** | §5.2/5.4/5.5/5.6 四件 + CurveEditor 复用 + 三面板（zones 曲线面板最重） | 5-6 | LUT 双闸 + hue sweep 覆盖 + 4 平场 probe 三证据 |
| **5-5 monochrome** | §5.3（含 grid 腿或 EIGF 决策执行）+ 色轮面板 + golden | 3-4 | CPU/CL sigma² 分歧钉 CPU + grid==直接窗口小半径交叉 |
| **5-6 nlmeans（共享核心先行）** | nlmeans kernel 群（dist/horiz/vert/accu/finish）+ Goossens Python 参考 + nlmeans 模块（29.0，Lab）+ tiling 承重首验（halo P+K）+ 面板 | 5 | 小图参考 parity <1e-3 + 分块==整幅 <1e-3 + 预览降载三件套常量钉死 |
| **5-7 denoiseprofile（第二难攻坚）** | VST 三变体 + eaw decompose/synthesize + Bayesshrink 阈值 + backtransform + 剖面接线（NoiseProfileStore 消费）+ NLMeans 腿 + 波列 tiling + 面板（force 曲线）+ **加噪→去噪闭环 golden（SC#2 正式验证）** | 6-7 | 波列参考 parity + 剖面错配方向断言 + FULL tiling 双门 + 平场探针 |
| **5-8 bilateral surface blur + defer 决议 + 签核** | §5.8 两档实现 + 面板；IOP-DENOISE-04 defer 决议文档化（hotpixels/dark-frame，含 cacorrect 复议结论）；Phase 5 签核（VALIDATION/VERIFICATION 准备、PERF 记录、sidecar 新 op round-trip、轨 B 全链回归、GUI 验收轮汇总） | 4-5 | 直连/grid 两档交叉 + 12 需求 SC#1-4 证据逐条 + 全 suite 绿 |

依赖序：5-1 → (5-2, 5-3, 5-4 可并行) → 5-5（依赖 5-1 grid 决策）→ 5-6 → 5-7（依赖 5-1 剖面 + 5-6 kernel 群）→ 5-8。总量 ~39-44 T，与 Phase 4（7 plans）同量级偏上，符合「12 需求 + 全项目第二难移植」的体量。

## Validation Architecture

1. **顺序**：5-1 基建全绿后模块 plan 才动工（剖面/加噪器/iscale/tile 回归是所有 denoise parity 的前置）；5-6 先于 5-7（kernel 群共享）。
2. **双轨 golden**：主轨合成参考（§7 表）；dt-cli 仅作采纳三证据 + 平场 probe（每模块 manifest 落账，L017 双重 probe 纪律对任何新 dt-cli case 首用前强制）。
3. **轨 B**：全模块插链 ColorSync 中性度 + 交叉一致性不回归（D-COL1 双判据）——color 组默认 disabled seed，启用态中性由独立门把守（03-04 收窄口径延续）。
4. **tiling 承重 harness**（SC#4 后半）：nlmeans/denoiseprofile/monochrome/bilateral 各一组「强制分块 vs 整幅」数值门（<1e-3）+ MemoryBudgetTests FULL Δfootprint 记账 + TILE 不改 dscIn/iscale 常驻断言。
5. **SC#2 专项**：加噪→去噪闭环 + 剖面匹配/错配方向断言 + generic 回落链测试 = Phase 1 spike 的正式验证记录（进 05-VALIDATION）。
6. **性能**：SC#4 拖动门（60fps）= denoise 单件启用 + color 全启用两条链的 PREVIEW 拖动实测（PreviewChainPerfTests 扩展，03-06 T7 模式）；失败触发 Open#9 应急预案（§9 预案）。

## Risks & Gotchas

1. **denoiseprofile 是真正的第二难**：VST（三变体）+ eaw 波列 + Bayesshrink + NLMeans 四套机制叠在一个模块；band 循环的原地累加直接踩 L018（read_write RMW）——**全部中间态走 `device float4*` buffer 双平面**（03-04 定式），禁 image2d read_write。参考实现先于 kernel 写（Python float64 逐式），kernel 与参考同步推进（filmicrgb F1 三方门模式）。
2. **nlmeans 的 local memory 滑窗**（horiz/vert 的翼区填充，nlmeans.cl:86-107）：MSL `threadgroup` 内存 + barrier 语义与 CL 等价，但 workgroup 尺寸选择（dt 由 `dt_opencl_local_buffer_opt` 探测 2^16 上限）需在 Metal 上以 threadgroupMemoryLength 显式定——plan 期用 dispatch2D 的 groupSize 参数化并做尺寸扫描测试。
3. **max_scale/tile 稳定性**（§3.3）：dscIn/iscale 的 tile 不变性若被破坏，band 数随 tile 尺寸漂移 → tile 缝可见。常驻断言 + 分块==整幅门双保险。
4. **色域近似 divergence**：dt 剖面标定在传感器域、应用于相机 RGB；我们在 Rec2020。误差表现为去噪强度分布的小偏差（非结构伪影），头注 + SC#2 的错配方向断言兜住语义正确性。
5. **monochrome CPU/CL 分歧**（§5.3）：golden 钉 CPU 版；若未来用户报「与 dt OpenCL 输出不同」即此已知分歧，manifest 记录。
6. **dt 侧采纳证据的 blob 尺寸**：denoiseprofile params v12 = 244B / channelmixerrgb v3 = 160B / colorbalancergb v5 = 132B——XMP hex 配方按各自 struct 逐字段 pack（L015 教训：hex 非 base64）；**denoiseprofile 的 x/y[6][7] 力曲线**让 blob 变长，pack 脚本先过 `--d params` 版本校验。
7. **noiseprofiles.json 许可证**（§2.2/OQ2）：分发前核对；阻塞时降级「generic 内置 + 用户指路径」不阻塞工程。
8. **L014/L019 常规适用**：读回前 fence；xcodebuild 前查弹窗。GUI 验收轮按 PLAYBOOK §0-§6。
9. **sidecar 兼容**：11 个新 op 进 `instances`——未知 op 透传降级（02-06）已备；params 全 Codable+Hashable 经 ParamsCoding（L013）；v50 槽位照表，无重排。
10. **dt 28.5 共槽**：channelmixerrgb 与 diffuse/censorize/negadoctor/blurs/primaries 同槽——我们只注册 channelmixerrgb，无冲突；但 sidecar 若未来导入含同槽多实例的历史需 tie-break（effectiveInstances 已按 opName tertiary 排序，回归测试补一例）。
11. **IOP-DENOISE-04 defer 的验收口径**：SC#3 措辞「hot-pixel/dark-frame/chromatic-noise reduction all reduce noise without detail loss」——chromatic 半边有承载；hot-pixel/dark-frame defer 需要在 05-VALIDATION 里以「ROADMAP 需求文字与 dt 域现实的落差」正式记录（类比 04 对 IOP-DETAIL-01「高斯/拉普拉斯变体」的注记口径），非缺口而是需求解释权裁决——建议 planner 在 DISCUSSION-LOG 落 DECISION。

## Open Questions for Planning

1. **IOP-COLOR-09 的「curves」半边**：colorcontrast 为需求本体（推荐）；rgbcurve(42.0)/rgblevels(43.0) 是否随行（tonecurve/levels 的 RGB 变体，CurveTools 全复用，增量 ~2 天）？推荐划出 v1 或作 5-4 stretch，planner 拍板。
2. **noiseprofiles.json 分发**：内置全量 + 数据文件 LICENSE 注记（推荐）vs generic 内置 + 用户指 dt 数据路径。涉及许可证核对（dt GPL 项目内的贡献数据再分发）。
3. **denoiseprofile 的 VARIANCE/AUTO 模式**：v1 交付 WAVELETS+NLMEANS 两手动模式 + 剖面 AUTO 参数推断（infer_* 解析式直译，推荐），VARIANCE 局部方差自检划出？
4. **monochrome 的 bilateral 腿**：移植 dt 3D grid（推荐，换 monochrome+bilat/shadhi bilateral 腿未来 parity）vs EIGF 替代（省 ~2 天、语义分叉、golden 全合成）。
5. **channelmixerrgb 的 color-checker 剖面子树**：划出 v1（推荐，params 位保留）vs 随 5-3 交付。涉及 `src/common/colorchecker.h` 24 色块参考数据同许可证问题（同 OQ2）。
6. **Open#9 处置变更**：管线级 Lab leg v1 不做（本研究论证），降级为「SC#4 拖动门失败的应急预案」——需 planner/用户认可对 03/04 签核批分配的修订。
7. **bilateral 大半径 5D grid 的内存上界**：grid_bytes 公式与预算回落策略（超预算 → tiling vs 拒绝大参数）在 5-8 plan 期定；是否需要 UI 端 σ·radius 乘积软上限（dt 用 maxbuf 机制，我们用 TilingPlan 对应物）。
8. **vibrance 独立模块 vs colorbalancergb 滑块映射**：dt 标弃用指向 colorbalancergb——我们按需求独立交付（推荐，4B params 成本≈0），还是 COLOR-03 由 colorbalancergb 的 vibrance 滑块代偿、不建独立模块？

## Sources

### Darktable（本地源码，file:line 均已核；树 dc58cf0ba1 2026-08-02，与 Phase 2-4 同）

- `src/common/iop_order.c:298-415`（v50 表；本树无独立行号核过——V50Order.swift:1-22 记录移植源）+ `V50Order.swift` 槽位注释
- `src/iop/denoiseprofile.c` — params v12（:97-129）、flags/default_colorspace RGB（:832-843）、process 分派（:2598-2620）、process_wavelets（:1423-1658，VST/最大 band 推导 :1436-1455、Y0U0V0 矩阵 :1495-1502、绿通道拟合 :1519-1523）、variance_stabilizing_xform/Bayesshrink（:1346-1422）、process_nlmeans（:1772-1858）、nlmeans_norm（:1638-1650）/scattering（:1614-1631）、infer_* auto 参数（:2622-2650）、highlight-pres ISO shift（:2693-2706）、tiling_callback（NLMeans 分支 factor_cl=4+NUM_BUCKETS·0.25、波列 factor_cl=3.5+max_scale、overlap=2^max_scale）
- `src/iop/nlmeans.c` — params v2（:45-52）、Lab 域（:94-99）、P/K/sharpness（:170-173,357-360）、norm2（:362-365）、decimate（:367-368）、CL bucket 轮转（:229-310）、tiling_callback factor_cl=5.0/overlap=P+K（:328-341）
- `data/kernels/nlmeans.cl:26-253` — gh/ddirac/dist/horiz/vert/accu/finish 全五 kernel（Goossens 出处注 :21-24）
- `data/kernels/denoiseprofile.cl` — precondition 三变体（:31-114）、backtransform_Y0U0V0（:400-432）、weight（:434-447）、decompose/synthesize（:421-486）、reduce_first/second（:493-577）
- `src/common/noiseprofiles.c` — generic（:28）、JSON 加载（:36-80）、匹配 maker strstr/model strcmp（:227-333）、ISO 线性插值（:375-390）；`data/noiseprofiles.json` 本机实测（1,792,326B / 19 makers / 433 models / per-ISO a[3],b[3]）
- `src/iop/colorbalancergb.c` — params v5（:60-110）、RGB 域（:197-202）、矩阵预乘链（:621-647）、逐像素 4-way（:660-947）；`data/kernels/extended.cl:752-1042` `colorbalancergb` kernel（vibrance 公式 :807）
- `src/iop/channelmixerrgb.c` — params v3（:88-113）、RGB 域（:254-259）、flags（:244）、process 矩阵分支（:2114-2294）、CL 全局 5 kernel（:224-232）；`data/kernels/channelmixer.cl:106-685`
- `src/iop/channelmixer.c` — deprecated（:126）、RGB 域（:157）、params 3×4（:81-96）；`extended.cl:140`
- `src/iop/colorzones.c` — 常量/params（:36-92）、Lab 域（:159-164）、process_v3（:526-570）、LUT 3×0x10000（:123，构建 :2871）、CL（:596-640）；`data/kernels/basic.cl:3121-3185`
- `src/iop/monochrome.c` — params（:47-53）、Lab 域（:89-94）、_color_filter/_envelope（:168-195）、process CPU（:197-239，**sigma2 2×** :205）、CL（:246-299，**sigma2 1×** :257）、tiling_callback（:316-340）；`data/kernels/basic.cl:2992` monochrome_filter
- `src/iop/velvia.c` — params（:41-45）、RGB 线性域（:86-91）、process 公式与 clamp（:162-197）
- `src/iop/vibrance.c` — params（:37-40）、Lab 域（:83-88）、**DEPRECATED flag + msg**（:57-76）、process（:100-128）
- `src/iop/colorcontrast.c` — params（:36-43）、Lab 域（:102-107）、process unbound 双档（:166-221）
- `src/iop/bilateral.cc` — "surface blur"（:72-77）、RGB 域（:94）、params 5σ（:52-58）、三档 process（:121-318，MAX_DIRECT_STAMP_RADIUS=6 :48）、5D lattice（:266-310）、tiling overlap=rad（:360）、`data/kernels/bilateral.cl`（5D grid splat/blur/slice）
- `src/iop/hotpixels.c:94,363-410` + `src/iop/rawdenoise.c:161,510,538` — IOP_CS_RAW / `dt_image_is_raw` 门（defer 证据）
- `src/common/illuminants.h:181,220,389`（illuminant_xy_to_XYZ / find_temperature_from_raw_coeffs）、`src/common/colorchecker.h`、`src/common/gamut_mapping.h`（v1 划出子树的定位）

### Lightamer 代码（现码，file:line 核过）

- `LightamerCore/Sources/Pipe/IOPModule.swift:59-143`（协议钩子 + tileHalo/tileWorkingSet seam :124-130 + 默认恒等 ROI :138-143）
- `LightamerCore/Sources/Pipe/Tiling/TilingPlan.swift:1-119`（overlap 内缩 + halo 外扩读的 LIVE 语义 + Phase 5 注记 :11-13）
- `LightamerCore/Sources/Pipe/PixelPipe.swift:248-344`（executeTiled / executeTiledNegotiated + dscIn stamp 约束）
- `LightamerCore/Sources/Foundation/V50Order.swift:24-150`（93 条全表 + 28.5 共槽注释 :11-15 + denoise/color 槽位行）
- `LightamerIOP/Sources/Common/`：GaussianBlur（:80,164）、LabRoundTrip（:36-125）、LabKernels.metal（:18,28）、HistogramReduce（:44,109,140）、IOPExpFit
- `LightamerIOP/Sources/FilmicRGB/YrgGamut.swift`（CAT16/LMS2006/Yrg/Ych 常量与 clip-chroma 族 = colorbalancergb 复用面）；`ToneEqual/CorrectionLUT.swift`（band→LUT→apply 模式）
- `LightamerIOP/Sources/Registry.swift`（注册/seed/prewarm 模式）；`Tests/LightamerTests/ParityGate.swift`（LUT 双闸）
- `App/Sources/Lightamer/UI/Inspector/ToneEqualPanelView.swift` + `CurveEditorView`（Canvas 曲线/色轮 UI 复用面）；`PipeCoordinator`（D-H1 三件套 / D-C3 梯子）

### 项目文档与本机实测

- `.planning/ROADMAP.md` §Phase 5（SC#1-4 + spike 表 + IOP-COLOR-08→Phase 12 注记）；`.planning/REQUIREMENTS.md` IOP-COLOR/DENOISE 条目 + 映射表（:307-323）
- `.planning/phases/01-*/spike-a-ciraw9-boundary.md`（§2.4 denoise 结论 + spike-a-probe-output.txt:27-63 NR 键实测）+ `spike-b-100mp-perf.md`（1.55GB 平面/内存实测）
- `.planning/phases/03-tone-filmic-iops/03-RESEARCH.md`（体例 + Open#9 原文 :296 + dt-cli/golden 定式）、`03-06-SUMMARY.md`（PERF-5 36.23ms + 杠杆分配）
- `.planning/phases/04-geometry-lens-detail-iops/04-RESEARCH.md`（ROI 协商现码分析 + L017 分流表 + Vision/面板样板）、`04-VERIFICATION.md`（defer 移交清单：cacorrect 复议/PERF-5/L021 审计→Phase 5）
- `LESSONS.md` L006（禁 half）/L008（endEncoding）/L013（哈希键序）/L014（fence）/L015（XMP hex）/L016（EXR reader/linear 2020）/L017（dt-cli 空间损坏分流）/L018（RMW/private 毒化）/L020（ROI 坐标系前提）/L021（dscIn 禁再 ×scale + GUI 验收红线）
- `.work/gui-acceptance/PLAYBOOK.md`（GUI 验收操作细则 + §4 断言口径）；`TODO.md` Phase 3/4 遗留节（L021 审计、PERF-5、Open#9 挂账）
- AGENTS.md（Conventions：linear Rec2020/float32 RGBA/v50_order/golden-image 硬约定；Phase 执行模型：omp 执行 + 验收分工）

---

*Phase 5 Research — 2026-09-21。产物仅本文件；未提交 git。*

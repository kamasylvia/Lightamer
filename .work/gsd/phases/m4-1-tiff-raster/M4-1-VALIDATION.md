---
phase: M4-1
slug: tiff-raster
status: validated
nyquist_compliant: true
created: 2026-10-10
validated: 2026-10-10
---

# Phase M4-1 — Validation（TIFF 栅格开发链，RASTER-IN-01 收窄版）

> 体例对齐 `phases/m2-11-performance/M2-11-VALIDATION.md`。**双重验收（config
> `dual_acceptance = true`）双路 PASS 后成文**（m1 工序兑现）：01 底座批 + 02
> 切换收口批各持 zcode / omp 两路独立验收记录（`M4-1-01-ACCEPTANCE.md` +
> `M4-1-01-ACCEPTANCE-OMP.md` + `M4-1-02-ACCEPTANCE.md` +
> `M4-1-02-ACCEPTANCE-OMP.md`）。**翻账只认证据**：SC 三列对账正本 = 两路
> ACCEPTANCE + 终验亲跑数字；charter 验收形态三件 = round-trip ✓ / ICC 语义
> golden ✓ / HDR TIFF EDR ✓（ROADMAP §M4-1 行）。
> **SC 数字对账基线 = 全套 `--all` 终验 `TOTAL|3335/16/0|1604s` 亲证值**
> （2026-10-10 收口轮，exit 0 零 MEMFAIL；zcode 验收路独立复跑
> `TOTAL|3335/16/0|1584s` 逐位命中；对账链 **3174 → 3276 → 3335**：
> 3174（M3 终值）+ 102（01 = 7 新文件 99 + 既有 +3）+ 59（02 = 7 新文件 52
> + 既有 +7）= 3335，逐 bundle 分账两式互证逐位闭合；skip 恒 16 零新增）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / parity / 直启宿主 / 实机走查轨 / 上游 CTL + Alcedo 正本对表） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/崩溃签名/L055 机检全挂靠） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3335 tests / 16 skip / 0 fail**（1604s，02 执行批 2026-10-10 收口轮亲跑；zcode 验收路 1584s 独立复跑逐位命中；两轮零 MEMFAIL；IOPParity 峰值 8104MB < 8192 门〔验收轮 6998MB——两轮方差 obs 在册，MEMFAIL 兜底零触发〕；L055 双保险亲核 = 末条 Executed 全挂 'All tests' + 七 bundle 崩溃签名零命中） |
| **基线演变** | 3174（M3-4-02 终值）→ 02 波执行预期 3276（+102）→ **3335 精确**（+59：IOP +18〔RasterRouting 12 + RasterDecodeLeg +6〕/ Library +21〔16+4+1〕/ App +17〔7+5+5〕/ Export +3；IOPParity/Layers/Sessions 零新增）；逐 bundle：IOP **562/1/0** / IOPParity **427/3/0** / Layers **394/3/0** / Library **619/4/0** / Sessions **279/4/0** / Export **350/1/0** / App **704/0/0** |
| **SC 数字面** | fwd-first display 恒等 **4.440892098500626e-15**（机器精确）；display-first 网格 10985 点 in-domain worst **3.841e-3**（门 4e-3 内）；RASTERPARITY 五键近黑 = **0**（FMA 清白）+ p99.9 4.4e-4..6.5e-4 @100 / 4.9e-3 @1000 + scene-linear 8.66e-8；sRGB ICC decode 方向 @256 maxDev **7.6e-6**；SC#1 γ22 行 u8Fixed8 邻域 2.1992（<0.01）——正本 = 两路 ACCEPTANCE §二/§三亲跑 print 行 |
| **zh 对账** | 01 波 +1 键（`drt_eotf_srgb_piecewise`，1585/1823 PASS）→ 02 波 +25 键（1610/1848 PASS）；xcstrings 尾块纯插入（Python 键级比对 added 25 / removed 0 / modified 0 双路亲证）；选择器 countText = 显式 switch 静态键（V14/F-2 禁令合规双路核） |
| **在案 flake（本 phase 事件）** | **omp-minor-1（02）**：Export bundle `testEditReplaySurvivesFlushAndReload` 写腿在直启宿主下轮后遗留仓库 fixture 目录孤儿 `.lra` → 确定性污染下一轮 App bundle `testRestoreWinsOverDerive`（跨 bundle 轮间污染；三轮对照实验 R1-R4 亲证；干净树首轮不可见，第二轮必现 704/0/1）。产线零影响、测试卫生问题、不阻塞（修复方向明确：写方改 tmp 域拷贝 + 双前清）；IOPParity/IOP 峰值 RSS 轮间方差（8104↔6998 / 7280↔7729MB）超 ±3% 注记带——贴线记录保持 + 机检兜底，AGENTS 口径（连续 MEMFAIL 才干预）零触发 |
| **GUI 证据** | omp 实机走查一轮五义（`.work/gui-acceptance/m4-1-02/` 三证据图 + probe 日志 + `.lalb` 独立验库）：①TIFF 导入链通（probe row + images 表 1 行）②新腿渲染（64×64 彩条正常显示非黑屏）③DRT 面板开箱即 DRT（ACES 2.0 + Rec.709 + Gamma 2.2 + 峰值 100 全件活跃）④编辑全链（峰值滑杆 100→1000 nits → 落盘 `.lra` history 1 item `peak_luminance=1000`）⑤JPEG 设计内拒绝（`.lalb` 无行 = M2-2 既有语义非回退） |

---

## SC 三列对照（charter 验收形态逐件对表）

| SC | 判据（charter 正本） | 终态 |
|---|---|---|
| **SC#1** | TIFF 开发链 round-trip ✓（抽样矩阵真队列） | **Delivered**：`RasterRoundTripTests` 3 法经**真 ExportQueue**（enqueue → waitUntilIdle → done 态 → 落盘文件重 decode）亲绿〔zcode §五 + omp 复核〕——drd 恒装配 + 三行编码对（srgbPiecewise round-trip / γ22 u8Fixed8 邻域 2.1992 / HDR 行 rec2020+st2084 16-bit PQ 落地 → ColorSync 序列化 ICC 呈 LUT 型 → 重导入 `iccLutConverted` CI 臂〔KD-1 唯一 LUT 面，DECISIONS §6 实测面〕）+ inverse→forward 带 8e-3 相对门 + D-H1 生产提交面编辑重放像素稳定 |
| **SC#2** | ICC 语义 golden ✓ + 全矩阵 IOP/IOPParity 逐位 | **Delivered**：21 fixture 幂等矩阵（生成器双跑同 shasum 亲证）× `RasterColorDescriptionTests` 28 + `RasterIccSemanticsTests` 20（IFD tag-34675 真链 + TRC 公开标准双锚 + 平台行为钉三法）；`Aces2InverseTests` 8（fwd-first 4.4e-15 / display-first 网格带 / FMA 近黑哨兵 1e-6 全绿）；`RasterKernelParityTests` 3（33³×五键近黑=0）；canonicalization 阶梯四形正负测八法；**E1 终证** = IOP 562/1/0 + IOPParity 427/3/0 逐位基线零漂移（HDRPipelineMatrix torture/merge 产品经新腿 sceneLinear 矩阵支回流）——01/02 双批双路亲跑 |
| **SC#3** | HDR TIFF EDR ✓（视口五法） | **Delivered**：`RasterHdrViewportTests` 5 法亲绿——PQ/HLG fixture → `derive(rec2020, st2084/hlg)` → **真 CAMetalLayer 断言** 16F + `wantsExtendedDynamicRangeContent` + `itur_2100_PQ/HLG` colorspace；peak 1000/4000 贯通；`ExportVariant.validate` 峰值门零扰动；followGate 互斥。omp 实机旁证 = DRT 面板开箱活跃五件（走查 #3） |

## 七项生效值对照（`M4-1-CONTEXT.md` 裁决记录 2026-10-10 → 落点终态）

| # | 生效值（OQ 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | raster 默认 DRT = Alcedo D2 同形 + `DrtEotf.srgbPiecewise` additive | 01 KD-8/KD-9 + 02 KD-2 | **落地**：seed 三支 carrier-only（sidecar 零写直到编辑）+ mint skip + undo 到顶 derive 重铺（「DRT 恒在」偏离 RAW 登记）；srgbPiecewise 四通（serde `"srgb_piecewise"` / kernelIndex **7**〔Alcedo `drt_node_model.hpp:46` 逐字亲证〕/ legalEOTFs rec709+p3d65 增行 / 导出 curv 采样表非 para〔L053 守住〕）；唯一生产可见变化 = RAW 文档 EOTF picker 增 sRGB 行（双路确认无第二处） |
| 2 | 新 TIFF 开发分支（limiting = 源 primaries） | 01 KD-3/KD-5/KD-6 + 02 KD-1 | **落地**：decodeTIFF 原生字节腿（8/16/32F 零转换保源 primaries / 灰→RGB / alpha 丢弃不反 premul / CMYK typed 拒 / 多页取 0）；PixelPipe 分派键 = `rasterColor`（三 CI return 之前，checker m2 订正形态）；windowedPayload top-first + LE 读回（自抓自修两件在册） |
| 3 | 逆变换 = aces-core 移植 + RGC 逆不移植 + raster RGC 恒关 | 01 KD-3/KD-9 | **落地**：`Aces2InverseReference`（上游 SHA `069b0bc3` 逐行对表：stage 序 / E3 数据依赖序 :544-560 逐字 / gamut_compress_inv :890-917 / vestigial `bool invert` 去参无损）；fwd-first 恒等 4.4e-15 = 同源一致性主张成立；RGC-off = render-side 政策单源（DrtRecord 零字段零 hash 面）**晨审可翻**（挂账 #5） |
| 4 | HDR 旗标 = PQ/HLG TRC ∨ float 探针 >1.0；DRT-HDR 既有臂；徽标 defer | 01 KD-9 + 02 KD-5 | **落地**：`isHdrRaster` 三支 + derive 探针 HDR 分支 → (rec2020, st2084)；视口走 M2-6 既有臂零新渲染代码；图库徽标 defer 维持 |
| 5 | 选择器默认双开 + `library.import.categories` 新键 + rawExtensions 正交 | 02 KD-4 | **落地**：ImportCategory OptionSet（缺键/域外 = 双开）；`LibrarySchema.tiffRasterExtensions` 硬编码不入 rawExtensions（两键正交双路亲读）；选择器 checkbox×2 + 不可勾计数 + V14 静态键 |
| 6 | TIFF 整体切新分支 + 旧臂退役保留 + JPEG/PNG 零回退 | 02 KD-1/KD-3 | **落地**：decode() 三分派序（RAW → TIFF → raster）；`decodeRaster` 本体零改 + 退役头注 + **退役臂快照测试**（直调仍 nil-raster CI 面）；RasterRoutingTests jpeg/png/heic 三 UTI 机检锚 + 管分派判别值断言（code-128 ≠ 0.2159，真判别非冒烟）；E2 普查 17 真消费面逐个处置（NeutralTarget TIFF→PNG 像素恒等换容器 + 翻转 AC 恰一处原位改名） |
| 7 | import 三模式零特例 + excludedType 分账 | 02 T6 | **落地**：ImportTransportTiffTests 4 法（move/copy/link 字节 + `.lra` 随行 + 重复跳过 + link 外部替换 → 描述 decode-time 重解析 + contentDedupeID 翻新）；`ImportProgress.excludedType` additive 缺省 0 |

## 双重验收记录（dual_acceptance 双路，两批各自独立）

| 批 | zcode 路（首验） | omp 路（串行二次） | 分歧与订正 |
|---|---|---|---|
| **M4-1-01**（底座批，11 commits `80c96c2..4346dbe`） | **PASS / 0E + 0M + 3obs**（`M4-1-01-ACCEPTANCE.md`：亲跑四 bundle 逐位 + 上游 CTL `069b0bc3` 数学审计 + ICC 解析审计 + 红线机检亲跑零 diff + 偏差五条全裁定成立） | **PASS / 0E + 1M + 3obs**（`M4-1-01-ACCEPTANCE-OMP.md`：定向复跑三 bundle 逐位 + uv/Python 独立数学复算逐位 + 上游/Alcedo 正本对表） | **omp-minor-1 = ②默认字面五处写 Rec.709、实际落地 rec2020**（机制面自洽：无 ICC 色域未知 limiting 取最大包络更保守；三处测试与 HDR 分支全按 rec2020 走）——**行为正确、字面错，02 批订正五处字面为 Rec.2020 + DECISIONS 登记**（字面登记路径行使，晨审若翻行为需同步改三处测试与 HDR 分支预期，默认不建议）；omp-obs-1 BUNDLE-MAP 五处失准 → 02 批勘误；omp-obs-2 `ExportDrtChainTests.swift` 后缀剥离 → 02 批恢复；omp-obs-3 IOP 峰值方差记观察；zcode 三 obs 双路一致（obs-3 精确值 `0.0038412827070091193` omp 逐位复现） |
| **M4-1-02**（切换收口批，7 commits `1b2b520..e6effc3`） | **PASS / 0E + 0M + 3obs**（`M4-1-02-ACCEPTANCE.md`：全套 `--all` 独立复跑 3335/16/0 逐位 + 翻转面审计抽 8 文件逐个核 + 读码核 + 红线亲跑零 diff） | **PASS / 0E + 1M + 2obs**（`M4-1-02-ACCEPTANCE-OMP.md`：定向复跑 Library 619/4/0 + App 704/0/0 干净树逐位〔含 peak RSS 2831MB 精确命中〕+ 实机走查五义 + 读码抽查四处） | **omp-minor-1（02）= Export→App 跨 bundle 轮间污染孤儿 `.lra`**（首验漏记——干净树首轮不可见；omp 三轮对照实验定根因 + 定级 minor；修复方向明确，**留观挂账待修复批**，见挂账 #6）；分歧余三：obs-1 E2 普查口径差（43 vs 45，交集 17 精确一致双路确认）/ obs-2 外扩面漏列增补（front-matter 未同步四件，登记面事项）/ JPEG 走查口径澄清（导入图库面非本批行为 → 机检锚替代验证，两路口径实一致） |

四路验收全部 PASS、零 error、零未订正 minor（01 minor-1 已由 02 批订正闭环；02 minor-1 测试卫生问题登记挂账）。

## Per-Plan Map（M4-1-01..02）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M4-1-01 底座批 | 描述解析（解析序 ①→①′→②→③ + IFD tag-34675 + canonicalization 阶梯）+ 21 fixture 幂等矩阵 + 逆变换 Float64 authority（`outputTransform_inv` 移植 + kernel 镜像）+ 原生解码腿 + srgbPiecewise 全族 + RasterDefaultRecord derive（新腿直驱，decode 路由不切） | `80c96c2`/`d391946`/`2de7b99`/`d3a0268`/`daf3542`/`d9b8a51`/`01c46b1`/`07cbbde`/`7f7f000`/`5b2caa7` + T11 docs | 双路 PASS（0E；omp-minor-1 由 02 订正） |
| M4-1-02 切换收口批 | decode() UTI 分流翻转 + PixelPipe 分派 + seed/门控/编辑面 + HDR 视口臂 + 导入掩码/选择器/三模式运输 + SC#1 收口 + E2 普查处置 + omp-minor-1 订正 + BUNDLE-MAP 勘误 | `1b2b520`〔T1+T2 合并·可构建性裁定〕/`db7f7dc`/`ad9f7dc`/`a565f1e`/`5790526`/`ef0183c` + T8 docs | 双路 PASS（0E；omp-minor-1 测试卫生挂账） |

零红线域终态：`git diff 71f8f8d..HEAD` + `git diff 1220581..HEAD` 定向机检双批双路亲跑 =
`Aces2Kernels.metal` / `LightamerIOP/` / `Sidecar/` / `Pipe/History/` / `Library/`〔01〕/
`Graph/DrtRecord.swift`〔02〕**全零命中**；decodeRaster 本体零改（退役保留 + 快照测试钉住）；
sidecar/`.lalb` 零 schema 变更（持久化 = 零迁移）；六格式导出矩阵零改动（产线 Export 文件
零触碰）；RAW 文档渲染零变化（分派键 = rasterColor，RAW/CI-raster 路径不触）；JPEG/PNG/HEIC
零回退机检锚亲绿。GPL/Alcedo/aces-core 参考全程只读（Apache-2.0 NOTICE additive 在册）；
`.xmp` 零读写删。

---

## 挂账总汇编（M4-1 单一移交清单，五项全带锚点）

1. **深影饱和中性化观察项**（01 DECISIONS §4）：forward 的 gamut 边界 guard 对深影饱和色
   归零 M（上游 CTL 固有 :728-774 同形，M2-6 起产线携带）；inv∘fwd display 级恒等 4.4e-15
   机器精确不受损；真实照片经新腿 + 默认 record 回看可能中性化（与 Alcedo OCIO 逆的接受面
   同族）——gui-acceptance 走查观察；产品级处置（如 OCIO GPU-form 边界估计替换 CTL 形）另立 plan。
2. **HDR TIFF 重导入 LUT 臂面**（02 DECISIONS §6）：导出 PQ TIFF 的系统名 ICC 经 ColorSync
   序列化后呈现 LUT 型（A2B0）→ 重导入走 `iccLutConverted` CI 臂（PQ 语义在色彩管理内幸存，
   KD-1 钦定唯一 LUT 面；SC#1 HDR 行断言钉住）；像素往返由 srgb 行 band + ColorSync 管理
   承载；UltraHDR peak 容器维持 ALCE-02 M4 挂账不动。
3. **CMYK / 16-bit gray typed 拒 UX**（02 DECISIONS §7 行为变化登记）：open 时 decode 错误
   alert（翻转前静默走 CI 可开 = 设计内变化）；仅错误面无引导 UX——用户诉求出现时再裁
   （转档提示 / 静默 CI 兜底开图等候选）。
4. **16-bit gray 原生腿补腿**（01 DECISIONS §6/§8 待供件）：CGBitmapContext 无任何 16-bit
   gray 受支持 context 面（host 探针 8 形态）→ typed reject；需求驱动立项，当前 zero 用户面。
5. **raster RGC 恒关（render-side 政策，晨审可翻）**（CHECKER §一）：`rgcOn(rasterColor:)`
   单源非持久字段（DrtRecord 零字段零 hash 面）；翻案 = `params(space:peak:rgcOn:)` 调用点
   传值一处改（技术可行性亲证在册）+ 可选 additive `rgcOn: Bool?` 升级路径（stableHash nil
   零漂移钉死形态 KD-9 预置）；RGC 逆不移植维持上游同界。
6. **omp-minor-1（02）测试卫生修复批**：`testEditReplaySurvivesFlushAndReload` 改 tmp 域
   fixture 拷贝 + 写/读双侧前清（双保险；`DrtPersistenceTests` UUID tmp 面先例）+ 顺路排查
   defer write-behind 竞速（obs-omp-1：同形态真写腿测试 /tmp 残余面，低优先级）——M4-2 派
   前修复批或独立小批，归属晨审裁。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。SC#1/SC#2/SC#3 每条均有 ≥1 机器锚
  （RasterRoundTripTests 3 / RasterIccSemanticsTests 20 + RasterColorDescriptionTests 28 +
  Aces2InverseTests 8 + RasterKernelParityTests 3 / RasterHdrViewportTests 5〔真 CAMetalLayer
  断言〕+ RasterRoutingTests 12 + RasterEditFaceTests 7 + ImportCategoryTests 16 +
  ImportCategorySelectorTests 5 + ImportTransportTiffTests 4）+ ≥1 数字/实证背书（终验
  3335/16/0 双轮亲跑 + 上游 CTL `069b0bc3` 逐行对表 + Alcedo 正本亲核 + omp 实机走查三图
  + probe 日志 + `.lalb` 验库）。
- 采样密度：两 plan 全 AC 逐条机检（01: 99 新测 / 02: 52 新测 + 既有 +7）+ **四路独立验收
  复跑**（01 zcode 四 bundle + omp 三 bundle；02 zcode 全套 + omp 定向双 bundle）+ checker
  FAIL 6E+4M 先审后放（E1 红线自撞修复 = IOPP 逐位基线幸存的前提）；「无证据 ✅」零项。
- 数字对账：全套 `--all` 执行批（1604s）与 zcode 验收路（1584s）两轮逐位命中 + omp 干净树
  定向轮再证（App 704/0/0 含 peak RSS 精确命中）——三源互证。

## 特殊事项入册（phase 级事件台账）

1. **checker FAIL 6E+4M 先审后放**（`M4-1-CHECKER.md`）：E1（linear-ICC float32 半边缺失
   = IOPP 逐位基线红线被自身路由翻转击穿）为灵魂修复——①′ 解析半边落地后 HDRPipelineMatrix
   torture/merge 产品经新腿 sceneLinear 矩阵支回流，逐位基线零漂移（E1 终证）；E3 数据依赖
   序 / E4 联合规则 / E5 canonicalization 两支 / E6 srgbPiecewise 全清单（含 App 两件 +
   hdrDrawable 布尔链）全数落地。
2. **执行期两处自抓自修**（02 DECISIONS §3/§4）：windowedPayload 大端误读 → LE 读回修正
   （RAW03 读出垃圾值自暴露）；row0=TOP 方向勘误（RAW03 钉值证据链：CI 腿自 02-06 全绿 →
   bottom-first 首版位移 8 行被抓 → top-first 回退逐位命中——planner 假设被实测推翻在册）。
3. **T1+T2 合并 commit**（02 DECISIONS §1，可构建性裁定：拆分留下编译不过中间态破坏
   bisect；T3 起恢复逐任务提交；双路验收确认无分歧）。
4. **MAT3 逆矩阵笔误修复**（01 DECISIONS §3：伴随式第 3 元素 `a[0][2]*a[1][0]` →
   `a[0][2]*a[1][1]`，chad 反解 0.03 级漂移根因；export 侧同名 Mat3 核对正确未触碰）。
5. **平台事实入册**（01 DECISIONS §2）：ICC 提取走 TIFF IFD tag-34675 直读，不走
   `copyICCData`——ImageIO 对无 ICC 文件合成 colorspace + ColorSync 近似匹配降级替换
   （22 fixture 探针记录），colorspace 面结构性失真；平台行为钉测试三法在册。

## 授权记录（C 档第 3 停 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8/9/10/11 + M3 全系
  VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」（01/02 两波执行 + 双验收编排
  同一授权链）。
- 依授权，本 VALIDATION 由 VALIDATION 成文 executor 落盘签核（`[gsd] paused=false /
  auto=true` 全程未动）；用户晨审可推翻本签核（推翻 = M4-1 签核作废回退，已交付面与
  四路执行/验收证据不受影响；翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode VALIDATION executor（2026-10-10 晨批）；**doc-only——零源码 diff**
  （`git status` 对表 = 本批全 docs + 两份 omp 验收报告入库）。
- **呈报裁决点（禁静默）**：①02 omp-minor-1 测试卫生修复批归属（M4-2 前置 or 留观）；
  ②raster RGC 恒关翻案权（挂账 #5）；③挂账 #1/#3 产品级处置立项与否（等用户诉求）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：RASTER-IN-01 **Delivered 终态**注记（收窄版 TIFF only 交付面全落账）。
- ROADMAP：M4-1 行 ✅ 闭环（终态 3335/16skip/0fail）。
- STATE：M4-1 complete + current_phase 翻新 = next M4-2。
- TODO：M4-1 条目落账（[x]）。
- GOAL-STATE：续接点翻新 = **M4-1 closed → M4-2 Follow Edges V2 换锚重做**。
- 未 push；GUI app / 测试宿主进程零残留（omp 走查毕已 quit + defaults 零触碰 + 孤儿已清）。

## 签核

- SC#1/SC#2/SC#3 + 七项生效值全项 **Delivered**（三列证据齐；数字对账 = 终验双轮亲证
  基线 3335/16/0）。
- `status: validated` + `nyquist_compliant: true`。
- **M4-1（TIFF 栅格开发链）closed**：两 plan 全 dual-acceptance PASS，终验
  `TOTAL|3335/16/0|1604s`；挂账单一清单六项（深影中性化 / HDR LUT 臂面 / CMYK·16-bit
  gray UX / 16-bit gray 补腿 / RGC 恒关晨审可翻 / omp-minor-1 修复批）移交。
- 晨审裁决项：omp-minor-1 修复批归属 + RGC 翻案权 + 挂账 #1/#3 立项 + 签核推翻窗
  （原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**

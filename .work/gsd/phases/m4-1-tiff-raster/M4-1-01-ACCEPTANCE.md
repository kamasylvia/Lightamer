# M4-1-01-ACCEPTANCE — 双重验收记录（dual_acceptance = true）

> 验收对象 = M4-1-01（TIFF 开发分支底座批，11 commits `80c96c2..4346dbe`，基线
> `71f8f8d`）。零共享上下文独立验收：亲跑 + 亲读 + 上游/Alcedo 正本对表，不轻信
> SUMMARY/DECISIONS。证据日志 = `evidence/m4-1-01/acceptance/`（build.log +
> testrun.log 四 bundle 全量）+ `/tmp/la-direct-tests-*.log`（print 值）。
> 验收日期 = 2026-10-10 夜（build @ `4346dbe` exit 0）。

## 结论

**zcode 路：PASS / 0 error + 0 minor + 3 observation（全部登记不修，不阻塞）。**

**omp 路（串行二次验收）：待 orchestrator 编排**——按 config `dual_acceptance = true`
由 orchestrator 在本文件追加 omp 路（computer-use 走查 + 抽测）结论后方可闭环。

---

## §一 亲跑数字（四 bundle 定向轮全量，`Scripts/test-direct.sh`，零 MEMFAIL）

| bundle | 亲跑 | 申报 | 基线 | 判定 |
|---|---|---|---|---|
| IOP | **544/1/0**（142s，peak 7280MB） | 544/1/0 | 483/1/0 | ✅ 逐位命中 |
| IOPParity | **427/3/0**（450s，peak 6002MB） | 427/3/0 | 408/3/0 | ✅ 逐位命中 |
| Layers | **394/3/0**（150s，peak 1183MB） | 394/3/0 | 378/3/0 | ✅ 逐位命中 |
| Export | **347/1/0**（197s，peak 6517MB） | 347/1/0 | 342/1/0 | ✅ 逐位命中 |
| App（DrtViewportTests 定向） | **7/0/0**（3s） | 7/0/0 | — | ✅ 命中 |

- 四 bundle 合计 **1712/8/0**；新增分账 IOP +61（28+20+13）/ IOPP +19（8+8+3）/
  Layers +16（14+2）/ Export +5 = +101 + App +1 = **+102** 与申报一致。
- 八个新 suite 各归其 bundle 全数 passed（逐 suite 日志行亲核）。
- zh-audit `--check` 复跑：**PASS 1585 source / 1823 catalog**（+1 键 =
  `drt_eotf_srgb_piecewise`，E6 勘误兑现）。

## §二 逆编排数学审计（对上游 CTL 正本，SHA `069b0bc3`）

上游正本经 GitHub raw 拉取核验（OutputTransform.ctl 1702 行 / Tonescale.ctl 96 行，
锚点行与移植注记逐条吻合）：

1. **stage 序**：`outputTransform_inv`（:1690-1700）= RGB_to_JMh(limit_params) →
   gamut_compress_inv → tonemap_and_compress_inv → JMh_to_RGB(input_params)；
   `Aces2InverseReference.runPixel` 逐段同构 + [i7'] peak/100 缩放（refLuminance=100
   上游 :61 亲证）+ [i0'] ap0ToRec2020 working-space 出口（申报在册的结构性偏离）。
2. **E3 数据依赖序**：上游 `tonemap_and_compress_inv`（:544-560）= J_to_Y →
   tonescale_inv(Y/ref) → Y_to_J(linear·ref) → chroma_compress_inv(JMh_tc, J)（文件内
   注释「Applies the inverse tonescale, then uncompresses M」逐字在）；Swift 侧
   `tonemapAndCompressInv` 与 kernel 侧 `riTonemapAndCompressInv` 均按此序落笔，
   文件头 stage 图同序。上游 `chroma_compress_inv` 的 `bool invert` 形参在函数体内
   未被消费（vestigial），Swift 去参无损。
3. **gamut_compress_inv**（:890-917）：三 guard（J≤0 / M<0∨J>limit_J_max）+
   analyticalThreshold 二次估值闭式，Swift 逐行同形。
4. **复用件**：`tonescaleInv`/`chromaCompressInv`/`jToY`/`yToJ`/`compressGamut`
   (invert:) 与上游逐行对表（M2-6-2 既有面零触碰；`Aces2Reference.swift` 本批 diff
   = 9 行纯头注，`git show d3a0268` 亲核）。
5. **forward gamut guard（偏差①核实）**：上游 `compress_gamut` :742-747
   `if (gamut_boundary_M <= 0.) return {J, 0., h}` 逐字亲证——深影饱和 M 归零为
   上游固有，非移植引入。DECISIONS §4 登记合理。
6. **实测带亲证**（IOPParity 日志 print 行直接取证）：
   - fwd-first display 恒等 worst = **4.440892098500626e-15**（申报 4.4e-15 命中，
     机器精确）；
   - display-first 13³×5 键网格 total=**10985**，artifactClass(M-zeroed)=**1**，
     outOfClampDomain=**57**，worstInDomain=**3.8412827e-3** @rec2020@100（门 4e-3
     内；申报「3.9e-3」为进位口径，见 obs-3）；1+57/10985 = 0.53% 少数类，测试内
     建「artifact 类 ≤ total/5 结构嫌疑门」，合理；
   - FMA 近黑哨兵（1e-7..1e-4 线性光，五键）：门 1e-6 全绿；Float64 与 f32 kernel
     双侧零漂移结论成立（swiftc 无 fast-math 契约 + 实测双证）。

## §三 kernel parity 实测（T8 print 行亲证）

`RASTERPARITY` 五键 + scene-linear：

| 键 | worst | p99.9 | nearBlack |
|---|---|---|---|
| rec709@100 | 0.2639（近白角 (1,1,0.969)） | 6.50e-4 | **0.0** |
| p3d65@100 | 0.0205 | 5.44e-4 | **0.0** |
| adobeRGB@100 | 0.0134 | 4.41e-4 | **0.0** |
| rec2020@100 | 0.0107 | 4.73e-4 | **0.0** |
| rec2020@1000 | 0.1075 | 4.85e-3 | **0.0** |
| scene-linear | 8.66e-8（矩阵支） | — | — |

- **近黑 = 0 全五键**（FMA 清白申报亲证）；p999 带 4.4e-4..6.5e-4 @100 /
  4.9e-3 @1000 与 DECISIONS §5 一致；worst 集中近白角（逆 tonescale 病态顶）与
  上游 R2 面叙述一致。plan 1e-5 字面对全网格 f32 不可达，6e-3/0.3+近黑 1e-6 实测
  钉门 = M3-1-E5「门结构实测收窄」先例的正当行使，裁定成立。

## §四 ICC 解析审计

1. **解析序 ①→①′→②→③**：`RasterColorResolver.resolve` 结构完整；①′
   （E1）= `applyPriméRule`（isFloat ∧ transfer==.linear ∧ displayReferred →
   sceneLinear + reason），正测 `testLinearICCFloat32BecomesSceneLinear` + fixture
   测试双在册；②③默认 + `defaultReason` 在册。
2. **usable 三检查**：非退化三角（shoelace 0.005 门）+ 白点 barycentric 域内
   （±0.01 容差）+ 曲线单调（1e-6 噪声容差），顺位下落非报错；负测四法在册
   （退化/白点在外/非单调/TRC 失配）。
3. **canonicalization 阶梯**：identity 1e-4 → PQ/HLG 2e-4 → sRGB 1e-4 → 纯 γ 1e-4，
   端点归一化（scale-invariant）；正负测八法在册（within/beyond × 四形）。γ 估计器
   = 瞬时 γ 中位数（偏差②核实：log-log LSQ 在 u16 异方差噪声下漂 ~0.005 的实测
   记录在 DECISIONS §1，中位数残差 ~8e-6；「幂拟合 γ」语义保留，裁定合理）。
4. **chad 反解**：PCS = chad×native → native = chad⁻¹×PCS；无 chad 时 Bradford
   D50→wtpt 重建；Bradford 常数与逆矩阵均为公开标准值；伴随式逆矩阵逐元素核对
   正确（T3 修复的 `a[0][2]*a[1][1]` 笔误已消，现式无误）。
5. **LUT 判别**：`model==.rgb && !hasMatrixShaper && hasA2B0` → CI 腿分支——双 tag
   并存时 matrix-shaper 胜（Alcedo D4「A2B0 **with no** matrix-shaper tags」同款），
   正测 + fixture 双在册。
6. **IFD tag-34675 路径（偏差③核实）**：`tiffEmbeddedICCData` 双字节序 + 有界读取
   （头 8B → IFD0 ≤4096 entries → 单次 ranged read，64MB 帽）；不走
   `CGColorSpace.copyICCData` 的理由 = 平台失真探针（ImageIO 对无 ICC 文件合成
   colorspace / ColorSync 近似匹配降级替换）——22 fixture 探针记录在 DECISIONS §2，
   平台行为钉测试三法在册（`testNoICCFixturePresentsSynthesizedSystemSRGB` /
   `testUntaggedFloat32PresentsExtendedLinearSRGB` / `testCMYKFixturePresentsCMYKModel`）。
   证据链完整，裁定合理（KD-1「tag 34675」字面兑现）。
7. **tag 解码细节抽查**：cicp（+8 起 4 字节）/ mDCv（maxLum at base+16，×10000）/
   ccll / curv（count 0/1/N 三态，u8Fixed8 /256）/ para type 0..4 参数个数
   1/3/4/5/7 + ICC.1:2022 §10.5.3 公式——全对。
8. **peak 阶梯**：mDCv → MaxCLL → 1000 递补，clamp [100,10000]；HLG 恒 1000；
   边界测试在册。
9. **profileHash** = SHA-256 截断 8 字节，测试在册；`stableFingerprint` = 字段显式
   FNV（L013 纪律，discriminant+bit-pattern 折叠），测试在册。

## §五 解码腿与路由零翻转红线

- `decodeTIFF`：多页取 0 / CMYK typed 拒 / LUT-ICC 唯一 CI 腿（rasterNative=nil +
  `iccLutConverted`）/ 原生字节腿（匹配 context 数值拷贝：8/16/32F、灰→RGB、
  alpha 丢弃不反 premul、16-bit gray typed 拒=登记缺口）/ 内容探针 ≤4096 格。
- **路由 golden**：`testProductionDecodeRoutingStillCIPath`——生产 `RAWDecoder.decode`
  对 TIFF 返回 `rasterColor == nil ∧ rasterNative == nil`（防提前翻转）；亲读
  `git diff 71f8f8d..HEAD -- LightamerCore/Sources/Decode/RAWDecoder.swift` =
  仅 `contentDedupeID` 可见性一行（申报外扩件①）。
- **红线机检亲跑**（`git diff 71f8f8d..HEAD --stat`）：`Aces2Kernels.metal` /
  `LightamerIOP/` / `Sidecar/` / `Pipe/History/` / `Library/` **全零命中**；全量
  changed-file 清单 = front-matter ∪ 申报外扩五件，无第六件。
- JPEG/PNG/RAW 零回退：路由不切 + 渲染管线零 diff（LightamerIOP 全零 + App 层仅
  两申报文件），结构成立。

## §六 srgbPiecewise 四通 + 唯一用户可见变化

1. serde rawValue `"srgb_piecewise"`（DrtEotf.swift:79）——Alcedo
   `editor_panel_projection.cpp:169` 同拼写亲证。
2. `kernelIndex` ordinal **7**——Alcedo `drt_node_model.hpp:46` `SrgbPiecewise = 7`
   逐字亲证；kernel 镜像 case 7 双向（encode/decode）在册 + 常数探针测试。
3. `legalEOTFs`：rec709=[srgbPiecewise, gamma22, bt1886] / p3d65=[gamma22, st2084,
   srgbPiecewise]（顺序=KD-9 fallback 链）；p3d60/p3dci/xyz/rec2020 单值/HDR 集不动；
   `isHdrEncoding` 显式 `.srgbPiecewise → false` 臂（:466）——accept-set 集合等式
   测试既有面更新在册。
4. 导出臂：六空间组逐臂核对（rec709/p3d65 → calibratedICC **curv 1024 点采样表**；
   p3d60/p3dci/xyz/rec2020 → typed illegal）——**非 para（L053 守住）**，负测
   `testSrgbPiecewiseICCNotAParametricTag` 在册；round-trip 经**真 TIFF 写入 →
   IFD ICC 重读 → resolve 回 `srgbPiecewise`**（rec709+p3d65 双测；方向事实
   = ICC TRC 为线性化方向，ColorSync 写路径 reserialize 的 encode 方向失真不影响
   canonicalization 消费的 decode 方向——`testPixelRoundTripThroughThePiecewiseICC`
   carrier 钉 1e-4，偏差④核实合理）。
5. App 层：`DrtPanelView.eotfName` 补臂 + 新键 `drt_eotf_srgb_piecewise`（xcstrings
   尾块纯插入 +17 行，en/zh="sRGB"，与 Alcedo QML label 同值）；
   `EditorMTKView.drtLayerColorSpace` SDR 幂组补臂 + γ2.2 近似（CGColorSpace 无分段
   表形式，近似偏差 DECISIONS 在案）；**`drtSurfaceSpec.hdrDrawable` 布尔链补
   `&& != .srgbPiecewise`**（非 switch 面，负测
   `testSrgbPiecewiseRecordIsNotHdrDrawable` 在册，App 定向 7/0/0 绿）。
6. **唯一生产可见变化确认**：RAW 文档 DRT 面板 EOTF picker 增 sRGB 行（picker
   数据源 = legalEOTFs 单源；渲染面/管线零接线零变化）——与申报一致，无第二处
   用户可见面。

## §七 默认 record 推导（KD-9/E4）

`RasterDefaultRecord.derive`：两表分离（limitingSpace 七值源域保留 / encodingSpace
显示域 AdobeRGB/ProPhoto→rec709+reason）/ 联合规则（每落点 ∈ legalEOTFs(space)，
TRC legality 复核 + TRC-home 跟随 + fallback head 兜底）/ γ pinned fits（2.6/2.4/
2.2/1.8→gamma22+reason，gamma18 永不产出）/ linear 特例（→(rec709, srgbPiecewise)；
rec2020 primaries + SDR linear 不落 rec2020）/ 探针 HDR 分支（sceneLinear ∧
probe>1.0 → (rec2020, st2084)）/ fallback 链首 = legalEOTFs[0]。`isHdrRaster` 三支
+ `rgcOn` 政策单源（DrtRecord 零字段零 hash 面）读码全对；14 法逐行测试在册
（含 stableHash 零漂移负测 = DrtRecord 结构零变更铁证）。

## §八 fixture 矩阵与幂等

21 fixture 在盘（位深×ICC×特形全矩阵，E1 半边 `linear-icc-float32.tif` 与双 tag
`dual-tag-matrix-a2b0-16.tif` 都在）；**幂等亲证**：`uv run --with tifffile --with
numpy python3 Scripts/gen-tiff-fixtures.py` 重跑后 `git status Tests/Fixtures/TiffRaster/`
全净（字节一致）。

## §九 逐 commit 边界（10 任务 commit + T11 docs）

十 commit 逐一 `git show --name-status` 核对：全部落在 front-matter ∪ 申报外扩五件
内；commit message 与 plan 提交约定逐字同（Conventional Commits 全英文）。T3 携
parser 修复 + 生成器修复 + fixture 重生成（DECISIONS §3 申报在册）。无越界。

## §十 observation（登记不修，不阻塞）

- **obs-1**：`decodeTIFF` 两处 `resolve` 调用恒传 `colorSpaceName: nil`——KD-1 的
  命名色彩空间快路径在产线解码路不可达（仅测试直达）。字节解析路径对同型 profile
  语义等价（canonicalization 阶梯吸收同形表），零正确性缺口；M4-1-02 接线时可
  顺路补（可选项，非义务）。
- **obs-2**：T7 提交（`01c46b1`）提前携带 T8 的两个测试文件（plan T7 清单未含
  `RasterInputPlaneTests`）——相邻任务文件序提前，净内容与 task 划分等价，全数在
  front-matter 内；记序注记不记违反。
- **obs-3**：round-trip display-first 带申报口径「3.9e-3」= 实测 3.8412827e-3 的
  进位（门 4e-3 内 4% 余量）；fwd-first 面（严格 1e-3 门）实测 4.4e-15 机器精确。
  记录精确值供 02 收口对账引用。

## §十一 偏差五条逐条裁定（全成立）

| # | 偏差 | 核实方式 | 裁定 |
|---|---|---|---|
| 1 | gamut guard 深影归零（上游固有） | 上游 :742-747 逐字 + 实测 1 点 M-zeroed | ✅ 上游原文行为，登记合理 |
| 2 | γ 拟合换瞬时中位数 | RasterTRC.canonicalize 读码 + 门距表 | ✅ 实测驱动，语义保留 |
| 3 | ICC 走 IFD tag-34675 | 探针记录 + 平台钉测试三法 | ✅ KD-1 字面兑现 |
| 4 | TRC encode 方向被 ColorSync 反转 | Export carrier 钉测试 + 方向注记 | ✅ decode 方向幸存 7.6e-6 口径成立 |
| 5 | 申报外扩五件 | 逐 commit 边界 + changed-file 全清单 | ✅ 全数申报在册，无第六件 |

## §十二 验收批增量

本文件 + GOAL-STATE 验收条目（单 docs commit，未 push）。无产线代码触碰，无测试
修改。omp 二次验收由 orchestrator 串行编排后在本文件追加。

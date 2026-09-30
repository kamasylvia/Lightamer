# M2-6-2 DECISIONS — 执行期签注（悬决点终式 + 容差谱 + 偏离声明）

> 每条对应 plan「执行期精读悬决点」/KD 必答/执行期发现；正本 = M2-6-2-PLAN.md（905e979）。
> 上游实态：aces-aswf/aces-core（ampas 路径保留为上游身份），**v2.0 main SHA
> 069b0bc3e1f6c62820f19fdae2fecec3f4fc0f80**（2026-09-01）+ **tag v1.3**（RGC 段）。

## §D1 许可终式（KD-1 工作假设的重大订正）

- **v2.0 main = Apache-2.0**（README SPDX + LICENSE 全文；v2.0 组织重构时换约）。plan/CONTEXT 的
  「AMPAS BSD 风格」来自 Alcedo `third_party_licenses/aces-core-LICENSE.md`——那是 **v1.x 时代**
  的存档。BSD 假设仅对 **tag v1.3**（RGC 取材段）成立。Apache-2.0 对「代码级移植 + 署名」结论
  无损（同为宽松许可且含专利授权）——按 Apache 条款落地：NOTICE 全文条目（URL/版本 SHA/移植
  函数清单）+ `third_party_licenses/aces-core-LICENSE-Apache-2.0.txt` + 每移植文件头注署名。
- **KD-1 v1 子集函数终清单**（经营收——执行期对照上游实态收口，未移植项及理由）：
  - 已移植（OutputTransform.ctl）：init_JMhParams；RGB↔Aab↔JMh 双向族；PRC fwd/inv；
    Achromatic↔J；clamp_AP0_to_AP1；chroma_compress_norm/fwd/inv；toe；reinhard_remap；
    compression_vector_slope；solve_J_intersect；smin_scaled；estimate_line_and_boundary_
    intersection_M；find_gamut_boundary_intersection；get_focus_gain；remap_M；compute_focus_J；
    init_HueDependentGamutParams；compress_gamut；gamut_compress_fwd；cusp_from_table；
    lookup_hue_interval；unit_cube_cusp_corners；build_limiting_cusp_corners_tables；find_reach_
    corners_table；extract_sorted_cube_hues；build_hue_sample_interval；build_hue_table；find_
    display_cusp_for_hue；build_cusp_table；make_uniform_hue_gamut_table；make_reach_m_table；
    generate_gamma_test_data；evaluate_gamma_fit；make_upper_hull_gamma_table；determine_hue_
    linearity_search_range；init_ODTParams（→ Params）；outputTransform_fwd；wrap_to_360/hue_
    position_in_uniform_table/next_position_in_table/base_hue_for_position/reach_M_from_table。
  - 已移植（Tonescale.ctl）：TSParams/init_TSParams/tonescale_fwd/inv。
  - 已移植（Utilities.ctl）：RGBtoXYZ_f33 公式（XYZtoRGB_f33 = 精确逆）。
  - 已移植（v1.3 LMT.Academy.GamutCompress.ctl）：compress 距离整形器 + LIM/THR/PWR 常数表
    （RGC 前置段）。
  - **不移植**（与 plan 一致 + 执行期增补）：outputTransform_inv（forward-only 渲染路径）、
    `hueDependentUpperHullGamma`（上游 forward 路径死代码——init_HueDependentGamutParams 自带
    lerp 版）、HSV_to_RGB/print_*/调试族、DisplayEncoding.ctl 全部（EOTF = EotfBox 七函数，
    KD-4 分离）、ColorSpaces.ctl 的 CAT 函数（我们不暴露 CAT 选项；白点适配已 bake 进 JMhParams）、
    RRT/LMT 创意族/1.x ODT 硬表（KD-1 YAGNI 原文）。
- **multi_f3_f33 行向量约定**：CTL 向量×矩阵 = 行向量（其矩阵存储 = 数学转置）——全部按数学
  形式（列向量，DrtMat3 行主序）重推导，逐函数注释携带上游恒等链。SUMMARY 偏差 2 的教训锚 =
  白点映射测试（M·(1,1,1) = whiteXYZ ≤1e-12，已永久钉入）。

## §D2 固定观察条件 + Hellwig 项终式（KD-2 必答）

上游 ACES 2.0 的 JMh 不是教科书 CAM16——固定环境常量（OutputTransform.ctl :60-71）：ref=100、
L_A=100、Y_b=20、dim surround=(0.9, 0.59, 0.9)、J_scale=100、cam_nl_Y_reference=100（offset
27.13、scale 400）。**Hellwig 项以上游实装形态进入**：无独立 HKE 函数——`cz = model_gamma =
surround[1]·(1.48+√(Y_b/ref)) = 1.137056021344975`（Hellwig 2022 指数形）+ chroma_compress 的
`M·(J'/J)^modelGamma_inv` 重标定（M/J 比守恒）。逆向**无迭代**：2.0 简化式的 A↔J 幂关系有闭式
逆（plan 风险节「逆向含迭代（CAM16 逆 Aab 搜索）」预勘不成立——以拉取实态为准，DECISIONS 签注）。
adaptation = exact form（D_RGB = F_L_n·Y_w/RGB_w）；Aab 矩阵 A 列 ÷A_w、a/b 列 ×43×surround[2]，
整体 ×400（cam_nl_scale）；A_w_J = PRC_fwd(F_L) 只进 Y↔J 桥（J_to_Y/Y_to_J），RGB→JMh 直路径
不经过（Aab[0] 已按 A_w 归一）。

## §D3 原色/hue 锚与上游数值例（KD-2「抽检 2-3 点」必答）

上游 v2.0 无内嵌数值例（CTL 无测试向量）——替代锚三层：①SMPTE ST 2065-1 公布矩阵（AP0↔XYZ 逐
元 1e-9 直等）+ AP1→XYZ 公布表（1e-4 带——公布值本身由 3 位小数原色推导）；②白编码不变性
（AP0/AP1 同白 → 同 XYZ 必同 JMh，1e-8/J 1e-6/h 全立方扫）；③白点 J=100/M=0（1e-9，构造恒等）。
AP1 原色 hue 记录基线（50% 白混合，域内）：red 13.9828° / green 155.6313° / blue 278.3982°
（testPrimaryHuesAreOrderedAndAnchored 钉值）。**公布 "AP0→AP1" 表弃用**：记忆表值经 XYZ 守恒
双向证伪（两个方向读法都不守恒）——结构性锚替代（同白 (1,1,1)→(1,1,1) + 五点 XYZ 守恒 1e-9）。

## §D4 RGC 终式（KD-3）

v1.3 `LMT.Academy.GamutCompress.ctl`（transformId LMT.Academy.GamutCompress.a1.3.0，BSD 时代）
逐行转录：LIM 1.147/1.264/1.312、THR 0.815/0.803/0.880、PWR 1.2；`compress` 距离整形器
（scl = (lim−thr)/(((1−thr)/(lim−thr))^−pwr −1)^(1/pwr)）；AP0→AP1→achromatic 距离→压缩→重组
→AP0。Alcedo hpp 交叉验证（只读）：常数表一致、形态一致（其 Kernel 无逆臂差异——我们同样只取
forward）。新锚：`compress(lim) = 1.0` **精确命中**（y=1 交点构造的定义式，1e-12）。
归属 = kernel 常量前置段（gam2.z 标志位，默认 on）；OpenDRT 路径不经过（DrtMethodBox 分派面 +
`testOpenDRTPathNeverRunsTheRGC` 活体校验：opendrt kernel vs RGC-free 参考黄金仍绿）。

## §D5 peak 传递终式（KD-5/OQ-7 ACES 半边必答）

- `limit_J_max = Y_to_J(peakLuminance, input_params)`（Y 域 = nits，白=100）——peak 直接决定
  JMh limiting 的 J 上限（上游 init_ODTParams :1648 原式）。
- tonescale 内部：n=peak 进 TSParams 全链（r_hit/m_0/c_t/w_i/log_peak）——**SDR 下 peak 照常
  生效**（上游行为如实；`testODTSDRPeakStillActive` 钉死「peak 只在 HDR 生效」误实现的反面）。
- 输出标定：`outputTransform_fwd` 输出 = limiting RGB，1.0 = **100-nit 参考白**（上游交显示
  编码的域）；Lightamer EotfBox 合同为 1.0 = peak nits → 末段 ×(100/peak)（stage [7]）。
- 灰锚实测：18% AP0 中性灰 @peak100 → 0.10000 峰归一（**10.0 nits**）。上游设计意图 c_d=10.013
  nits（c_t = 0.10013）——但 `g_ipp2` 用 u 链的 m 而 f 用 u_2 链的 m_2，构造落点 = 10.0（0.013
  构造间隙，上游数值事实；锚按实测 10.0 ±1e-4 钉）。

## §D6 上游 UB/形态不确定度终式（plan 风险节必答）

- `build_hue_table` 首轮读未初始化 `last_idx`（CTL 数组无零初始化保证）——Swift 以 −1 起算
  （首轮 `last_idx == nominal_idx` 恒假，语义 = 「首轮不触发同位调整」）。确定性 ✓（固定
  二分界 + 同输入同表，golden 位精确兜底）。
- 表几何：tableSize=360、totalTableSize=362（±360 环绕入口）、cusp 三元组 stride-3 打进
  float4 平面（272 float4，1088 槽）；kernel 侧读法 `tableCusps[flat/4][flat%4]`。
- reach_M 表粗搜上限 1300/步 50 + 1e-2 二分；cusp 角二分 1e-3；display cusp 1e-7；gamma 搜
  step 0.4/精度 1e-5——全部固定迭代数转录，无收敛域浮动。

## §D7 golden helper 复用形态（KD-6 必答）

**复制最小面**（非提取共用）：probePixels/compare/makeTexture 三件 + dispatch 骨架复制进
Aces2KernelGoldenTests。理由：提取需改 DrtKernelGoldenTests.swift（本 plan 申报集外文件）——
复制 = 更小 diff 足迹；两文件头注互指（「byte-identical generators」）。DECISIONS 即记录。

## §D8 容差谱终版（KD-8 逐断言签注）

| 断言 | 终带 | 依据 |
|---|---|---|
| Float64 常数/矩阵锚（AP0 族/白点/观察条件） | ≤1e-9（公布 AP1 表 1e-4） | 公布值精度 |
| CAM16 往返（域内） | ≤1e-6（ramp+色卡+极饱和×4 参数集） | 实测全绿 |
| PRC 往返（<0.99 膝下） | ≤1e-9 | 实测 |
| RGC 整形器 | threshold 内恒等容差 0；闭式锚 1e-12；compress(lim)=1.0 精确 | 构造恒等 |
| tonescale fwd/inv 往返（[0,r_hit]，逆域 = ref 归一） | ≤1e-6 | 实测 |
| chroma_compress fwd/inv 往返 | ≤1e-6 | 实测 |
| **kernel golden（11 参数点 × 探针，KD-8 主带）** | p99.9≤1e-5 + max≤5e-5 | **实测 worst p99.9=2.28e-6 / max=3.22e-6**——升级协议未动用 |
| IEEE | -0/+0 相等；NaN/Inf 恒 fail | 全 AC 口径 |
| golden 输入对齐 | 两侧同字节输入（探针直喂） | 同 M2-6-1 §D4 原则 |

级联预期（CAM16 pow/三角链）比 OpenDRT（5.4e-7）深约 4×，仍远低于 1e-5——CAM16 float32 收敛域
风险节未兑现为实际问题。

## §D9 执行期实现裁决（半径内 + E4 族补充声明）

1. **Params 记忆缓存**：NSLock 盒（`@unchecked Sendable`）键 = FNV(space rawValue ⊕ peak bits ⊕
   rgc)。表构建 ~10⁵ CAM16 求值——无缓存则每 dispatch 重建不可交互；缓存 = 新代码全在
   Aces2Reference.swift（申报文件）内，PixelPipe 只增 `aces2Uniforms` 可选 + switch 臂。
2. **E4 族补充（3+1 文件，commit body 申报）**：`isRenderImplemented` 翻面 = OpenDrtReference.swift
   （P1 植入谓词处——不翻则 aces20 永远被 typed refusal 拦截，D1 兑现不可能）；两处 stub-pin
   断言（DrtKernelGoldenTests/DrtTailTests）随翻面同步——拒绝测试改为活臂渲染断言（输出存在 +
   与 opendrt 分歧 + SDR 格式）。`third_party_licenses/aces-core-LICENSE-Apache-2.0.txt` 新增
   （Apache 再分派条款）。四件均在 SUMMARY 红线核节申报，验收核对 diff 边界时按此口径。
3. **Metal 结构布局**：uniforms = 纯 float4 平面（588 × 16B）——零混合对齐面（float3 成员会引入
   16B 对齐缝隙，弃）；hue_linearity_search_range 骑 ts2.zw（浮点槽载 int2）；rgcOn 骑 gam2.z。
   size-probe kernel 钉 9408 字节。
4. **测试域修正三件**（SUMMARY 偏差 3/7 + 灰锚）：A≤0 塌缩域跳过 + 占比上限断言；tonescale 逆
   测试用 ref 归一化域（上游 :552 用法）；ODT 灰锚输入 = AP0 中性灰映射回 Rec2020（D65 灰非
   AP0 中性——无 CAT 的固定原色转换固有，另钉 R/G 漂移 <0.02 面）。
5. **执行环境**（非代码）：App bundle 首轮 3 fail = 纯环境（ENOSPC——193 个 sidecarv5 残留目录
   13GB + Vision Code=9 瞬态），清盘后 376/0/0 复跑全绿；LESSONS 候选已记。

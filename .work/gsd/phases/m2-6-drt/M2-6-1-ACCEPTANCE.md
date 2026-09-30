# M2-6-1 ACCEPTANCE — OpenDRT 核（wave 1）独立验收

> 验收：ZCode 验收 subagent，2026-10-01。对象 = 执行方 9 commits（`b1ac572`..`4289f12`，
> 正本 = checker 修正版 `905e979`）。方式 = AC 逐条核对 + 六重点定向抽查 + 三域独立复跑
> （全套不重跑，批准门）。**结论头：PASS / 0 error + 3 minor（均已处置或注记）。**

## 一、复跑 vs 声明

| 域 | 声明 | 本轮独立复跑 | 判定 |
|---|---|---|---|
| IOPParity | 357/3/0 | **357/3/0**（279s，peakRSS 5983MB < 8G 门） | ✅ 逐值一致 |
| App | 376/0/0 | 376/0/**1**（`SidecarV5Tests.testWriteLeg…` 120s 超时型）→ **隔离复跑 ×3 = 10/0/0 全绿** | ✅ 在案 flake（见 F2） |
| Layers | 234/3/0 | **233/3/0**（DrtRecord 17 + DrtEotf 13 + DrtPresets 11 + DrtTail 12 逐类精确） | ✅ 0 fail；计数差 1 = 记账勘误（F1） |
| golden 实测 | worst p99.9=5.4e-7 / max=6.9e-7 | **本轮 WORST p99.9=5.364e-7 / max=6.855e-7**（12 组合全带内，band 1e-5 未触） | ✅ 复算吻合 |
| EOTF 频带 | st2084 decode p99.9≤5e-5 签注 | Layers 轮 13 处 ALARM-CHECK 行全过硬顶 5e-5（未 break） | ✅ |
| 全套 | 2403/16/0 | 三域实测 + 未复跑四域声明 = **2402/16/0**（+76 增量精确） | ⚠️ F1 记账勘误已修 |

增量对账：四 DRT 测试类 + golden 类 + sidecar 类方法数（17/13/15/11/12/8 = 76）与
BUNDLE-MAP 增行、Project.swift 双登记、实际 executed 逐类吻合——**+76 增量精确成立**。
±1 出在既有基线记账（M2-5-3 实测 executed 2327 vs 基线 BUNDLE-MAP 行和 2326），非本 plan
引入；SUMMARY/GOAL-STATE 已随本验收批勘误（2403→2402、Layers 234→233）。

## 二、六重点核查结论

### ① 转录忠实性（单列——本轮核心）

**判定：忠实。** 以 `/Volumes/UNITEK/Documents/Development/AlcedoStudio/alcedo_studio/src/
config/DRTs/OpenDRT.dctl`（GPL 仓只读）为对照源，抽验覆盖：

- **逐段抽验 ≥6 段（实抽 25/25 全对照）**：前置 tonescale 常数块（:943-959）14 项逐式
  一致（ts_x1/ts_y1/ts_x0/ts_y0/ts_s0/ts_p/ts_s10/ts_m1/ts_m2/ts_s/ts_dsc/pt_cmp_Lf/
  s_Lp100/ts_s1）；[1] gamut→P3D65、[2] 去饱和（rs_w 权重/sat_L）、[3] offset、[4]
  tonescale norm、[5] opponent/ach_d/hue 旋转 +1.10714931/三张 gauss 色相角表（0.66/0.5
  宽度逐值）、[6]-[9] brilliance/contrast low/high/hyperbolic、[10]-[16] hue contrast
  （hc_c 两步构造逐项）/hue shift RGB+CMY（hsf 差分序）/purity 三段/achromatic lerp、
  [17] 逆渲染空间、[18] display_gamut_whitepoint（CAT 矩阵分域 + cwp_f 混合 +
  **cwp_norm 五表 24 值逐一比对全等**）、[19]-[24] post brilliance（1.1×x²/(x+0.1)
  构造）/softplus/终段 tonescale/P3-limited clamp/显示 clamp。enable 位 → 值域投影的
  等价性逐 preset 核过（tsprst11 陷阱 = dctl :818 实态 `tn_hcon=1.0/enable=0`，表存 0，
  测试 pin 在册）。25 阶段结构图 ↔ dctl 行号清单（SUMMARY §结构图）抽 8 行抽查全对。
- **Kernel 镜像**：`OpenDrtKernels.metal` 与 Float64 参考逐段同构（段号共享词表），
  golden 12 组合 p99.9 ≤5.4e-7 佐证两脸一致。
- **Alcedo expected bins「53/53 逐位一致」抽 2 look 复算**：以 numpy 独立解析
  `cuda_opendrt_{standard,arriba}_{rec709_gamma22,rec2020_pq_1000nit}_expected_params.bin`
  （正确偏移 = 788 起 floats/1000 起派生段），**standard + arriba × 两变体全部 53/53
  float32 位级一致**；派生常数 14 项以我方 Float64 公式独立复算 → float32 舍入内全符
  （ts_p=tn_con/1.1 同时独立印证 surround=bright 派生表）；PQ 行 ts_dsc 差（bin 0.01 vs
  我方 0.1@peak1000）= §D3 已文档化峰值归一折叠，placement 恒等（ts_y1×ts_dsc 两侧同积）。
  metal_*.bin 全零非声明对象（§D7 只引 cuda 行，无涉）。
- **rawValue 终式**：`drt_node_model.cpp` ToJson（:24-89）逐值核对 `aces_2_0/open_drt/
  rec709/rec2020/p3_d65/st2084/hlg/gamma_2_6/bt1886/gamma_1_8/gamma_2_2` 全符 §D1；
  超 hpp 值域的 6/7 值枚举偏离声明在册（m4）。
- **GPL 边界**：dctl 代码/文本零复制（结构 + 数值事实转录）；NOTICE 仓根在册（jedypod
  v1.1.0 GPLv3 署名 + 独立实现声明 + MIT 本体）；GPL bins 不入 CI/断言。

### ② E2 尾段序锁 + E1 机械替换

- **guard 断言真实**：`testTailAssemblyOrderIsMethodEotfBordersWatermark`（序断言
  74→75→76→77，watermark 末位「印框后无 tone map 段」）+ `testDrtTailDiffers…`（域断言：
  画布带 = 显示白 1.0 后画——PQ 编码白应为 ~0.75 码值，断言可区分装配序错误）双锁。
- **E1 活体证明复核**：`EDRViewportTests.swift` diff = 单传点机械替换（edr →
  .edrLinear/.sdrGamma 条件式），断言语句零改动；`PipeCoordinator.swift` 四传点同型
  机械替换；`git grep edrDisplayLeg` 残留仅派生属性定义 + 注释（AC#10 口径）；两处既有
  gamma skip 判定点收敛为 `isTerminalTailSkipped` 后 .sdrGamma/.edrLinear 语义逐值等价
  （空集/gamma 单元素），EDR 既有测试零改动全绿。
- **缓存局部性**：`testEOTFSwitchReRunsOnlyTheTail` 实测 2 miss/1 hit（尾平面 MISS、
  colorout 前全 HIT）——KD-6 键折叠设计机检在册；红线七文件 `git diff --name-only` 零
  命中（机检复核）。

### ③ 容差谱真实性

- **golden p99.9 复算**：见上表——实测 5.364e-7/6.855e-7 与声明 5.4e-7/6.9e-7 为同数
  舍入；1e-5 带富余 ~18×，KD-8 升级协议确未动用（golden 层）。
- **st2084 decode 5e-5 升带数学论证独立复核**：numpy float32 逐步仿算（同 kernel 算子
  序）复现机制与量级——分母 `c2 − c3·e^(1/m2)` float32 相对误差实测 max 9.35e-6
  （≈2 位有效丢失）→ 外层 `^(1/m1)` 放大 ×6.28 → y 相对误差包络实测 **5.87e-5**，与
  DECISIONS §D2 的「~4e-5 包络」同量级同机制；测得 p99.9=2.9e-5 < 签注带 5e-5 < 仿算
  上界，带选合理且非静默放宽（§D4 逐断言签注在册）。公式忠实 BT.2100（不重结合）。

### ④ sidecar v6

- `LightamerSidecar.swift` diff 逐 hunk 全 additive：decodeIfPresent/encodeIfPresent/
  CodingKeys 增行/init 默认参——nil = pristine 保持 key ABSENT（v5 字节零漂移）。
- 测试面：v6 round-trip、v5-shaped 读 nil、schema 99 带/不带 record 双容忍、
  **hash-isolation 双向 pin**（record 不动 historyHash + record.stableHash 与
  decodeParamsHash/instance 解耦）——set-fields-move 判定的 sidecar 面与 T7 尾平面键
  折叠分工清楚，HistoryStack 零触红线由测试注记固化。
- 版本 pin 机械同步（SidecarV5Tests ×1 + SidecarMetadataV3Tests ×3）= 申报内、断言零
  弱化（同形状重钉新当前版本）。

### ⑤ 预设三件套 + NOTICE

- 三件套数值 = 程序化生成声明与实态一致：standard/arriba 快照与 dctl look 分支及
  expected bins 双向比对逐位一致（①项）；tonescale 14 项 rawValue 按 Alcedo QML 拼写
  （EditorDisplayTransformPanel.qml 域）；creative white 7 项 + look→cwp 表（aery=D75/
  dystopic=D60/umbra=D50）与 dctl 实态一致；tsprst11 陷阱投影测试 pin 在册；NOTICE 在
  仓根（45 行，含 aces-core P2 占位）。
- `applyPreset` 原子性（单 record 三决策一次落）、`isCustomLook` 派生语义（改一字段
  翻 true/复原 false）、`resolvedCreativeWhiteOrdinal` 解析序测试齐备。

### ⑥ 9 条偏差合理性

逐条核过，全部合理且已签注：①HLG 绝对 1000-nit 域（数学复核：encode/decode 域换算
边界单次进出，任意峰值 round-trip 恒等）；②尾平面全携显示格式（blit 不能跨格式转换，
SDR unorm 量化 = 最终量化，字节等价论证成立）；③walk skip 扩 ROI 钩子（skip 模块
modifyROIOut 不跳过则 borders 画布协商进主链——机制必要）；④ts_dsc 恒 SDR 形折叠
（bins + 乘积恒等双证）；⑤enable→value 投影含 tsprst11 陷阱（dctl :818 实态）；⑥
rawValue cpp ToJson 终式；⑦BT.1886 Lb=0 纯 2.4（dctl `eotf_p = 2+eotf×0.2` 同型）；
⑧tonescale 14 项勘误（dctl tsprst0..13 实枚举）；⑨st2084 decode 5e-5 升带（③项独立
复核）。Metal gamma 族通道 bug/L014 fence 自伤两例均为自测抓到即修，处置合规。

## 三、AC 总表核对（12 条）

| # | AC | 判定 |
|---|---|---|
| 1 | schema 四枚举 2/7/6/7 + key 清单 + 默认值 + canonical 字节 + stableHash | ✅ DrtRecordTests 17 法（hpp 逐字段对照复核） |
| 2 | 联动表六空间 + isHdrEncoding | ✅ 字面表逐行 + 线性/gamma18 全域非法断言 |
| 3 | EOTF 七函数锚点/往返/GPU 频带/peak 无效/IEEE | ✅ DrtEotfTests 13 法（Layers 轮 0 fail） |
| 4 | 参考 primitive 锚点/单调/有界 + 结构图对应 | ✅ 本报告 §二①（25 段全对照） |
| 5 | golden 12 组合 + 位精确 + 双路径 | ✅ 复算 5.364e-7/6.855e-7（声明同数） |
| 6 | 预设三件套 + NOTICE + 抽检结论 | ✅ bins 复算 53/53 × 2 look |
| 7 | sidecar v6 additive + 零漂移 + 容忍 | ✅ 逐 hunk + DrtSidecarTests 8 法 |
| 8 | drtTail 零行为差/E1 等价/三态格式/skip/序锁/键 | ✅ DrtTailTests 12 法 + EDR 14/14 零改动 |
| 9 | 注册口穷举无 default + aces20 stub + 零注册 | ✅ grep Registry/V50Order 零命中 |
| 10 | 红线零 diff + edrDisplayLeg 清零 + 机械替换 | ✅ 机检（本报告 §二②） |
| 11 | 全套 0 fail | ✅ 2402/16/0（±1 记账勘误 F1；0 fail 不受影响） |
| 12 | diff 边界 = 申报集 + 登记闭环 | ✅ `git diff 905e979..4289f12 --name-only` 逐文件核 |

## 四、Findings（0 error + 3 minor）

- **F1（minor，已修）**：收口记账 ±1——SUMMARY/GOAL-STATE 的「2403/16/0、Layers 234」
  与实测/map 算术（2402/233）差 1；+76 增量本身精确。随本验收批勘误（SUMMARY/GOAL-STATE
  注记），基线重钉挂 M2-6-2 收口全套 sweep。
- **F2（minor，注记）**：`SidecarV5Tests.testWriteLeg…` 全 bundle 负载下偶发 120s 超时
  型 flake（200ms 轮询异步 decode readback），与执行方在案 flake 同测试同族；隔离复跑
  ×3 全绿归因测试时序。建议 P3 面板接线批顺手把轮询超时/退避调优（非本 plan 半径）。
- **F3（minor，注记）**：st2084 升带的「numpy float32 仿算佐证」未落独立佐证文件
  （DECISIONS §D2/§D4 仅文字声明）——本验收已独立仿算复现同机制同量级（分母 rel 9.35e-6
  × ^(1/m1) 放大 → 5.87e-5 包络），验证需求已覆盖；后续如需复核，脚本式样可入
  `.work/gsd/artifacts/` 归档，不阻塞。
- 另记（非缺陷）：DrtTailTests 用 rec709+st2084（legalEOTFs 非法组合）驱动 HDR 面——
  模型层不钳制符合 KD-2（Core 纯函数不钳、P3 UI 吸附执法），合法组合执法归 M2-6-3
  面板接线，届时注意。

## 五、翻账清单（本 commit 同批）

- REQUIREMENTS：**M2DRT-02 [x] Delivered**（OpenDRT 核；bins 复算注记）；**M2DRT-04
  回落 [ ] 部分交付注记**（EOTF 核/legalEOTFs/isHdrEncoding/drtTail 渲染腿已交付，
  面板/视口/导出链接线归 P3/M2-9）；**M2DRT-06 回落 [ ]**（注册口本体交付注记，终验
  留 P2 aces20 翻面后）；M2DRT-01/03/05 留后续（原文零改）。
- SUMMARY/GOAL-STATE：F1 计数勘误（2402/233）。
- 本报告落盘。

## 六、后续缝

M2-6-2（P2 aces20：isRenderImplemented 翻面 + DrtMethodBox 分派臂 + NOTICE 条目 2）→
M2-6-3（P3 面板/HDR 视口 colorSpace/Post 四件插槽填充——74/75 间插槽序锁已由 guard
断言固化）。

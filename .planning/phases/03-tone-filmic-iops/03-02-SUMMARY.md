# Plan 03-02 — Summary

**Executed:** 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE（IOP-TONE-02 green；D-T4/D-T6 落地）

WB temperature/tint 全链交付：**Kelvin↔gains Rec2020 原生换算（dt 同源数学 <1e-4）+ 吸管
端到端中性化 + D-T6 Inspector 面板框架（exposure/WB 首两面板）**。全 suite
**165 tests 全绿**（3 skip 合规）。D-T4 吸管 plumbing 同时成为 03-06 filmic auto
三键的地基。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 03-02-T1 | `CIEData.swift`（dt `cie_colorimetric_tables.c` 逐值搬移：1931 2° 观察者 81 点 + daylight S0/S1/S2 107 点）+ `WhiteBalanceMath`（K→XYZ 与 dt 同源 <1e-4；Rec2020 原生 `gains = W/T`；Y-hack tint；K↔gains 二分 1e-4K）+ CPUDerivationTests WB 节（C harness 已知向量/锚点/方向/round-trip/吸管） | cc36402 |
| 03-02-T2 | `TemperatureModule`（.swift+.metal 对，v50=3.0 注册 + slot 语义 divergence 头注）+ `TemperatureKernels.metal`（whitebalance_4f 同构）+ golden 钉参组 4 case + PFM probes + 合成参考 + `TemperatureParityTests`（轨 A/轨 B/probe/kernel） | cc36402 |
| 03-02-T3 | `IOPPanelProvider` + `InspectorEditSession`（D-H1 三件套 façade）+ `LightamerSlider`（双击归零）+ `InspectorState` provider 分发 + 吸管模式状态 + `PanelWiringTests` | 4960fe0 |
| 03-02-T4 | `ExposurePanelView` + `TemperaturePanelView`（增益为持久真值、K/tint 派生、preset picker）挂进实体化 `InspectorView`；pristine 编辑种子 = terminal trio + temperature/exposure（identity，缓存中性） | 4960fe0 |
| 03-02-T5 | `PipeCoordinator.pickColor`（视口点→真 aspect-fit uv→线性段重渲（缓存全 hit）→L014 fence→5×5 面积均值）+ EditorAreaView 吸管模式（十字光标 + SpatialTapGesture 路由）+ blit shader uv 真适配修复 + `EyedropperTests` | 1d68711 |
| 03-02-T6 | 吸管端到端签收（蓝偏平场 → gains = normalize(1/picked) → 真管线 → 中性 <1e-5）+ VALIDATION IOP-TONE-02 ✅ + TODO/GOAL-STATE | 1d68711 / 1e77c73 |

## 验证（质量门全过）

- **单测**：165 tests, 0 failures, 3 skips（合规 skip 不变），`-only-testing:LightamerTests`
- **CPU 数学**（CPUDerivationTests WB 节）：K→XYZ 对 dt 参照 harness 三点 <1e-4（黑体/日光双支）；D65 锚恒等 (1,1,1)（1e-12）；升 K 蓝增益单调降/红升 + tint 升绿升；K↔gains round-trip <1e-3 K（实际 <1e-4，二分 1e-4K）；吸管中性解 = dt temperature.c:1933-1955 逐值（含 ≤0.001 回退与 8 钳制）
- **golden 轨 A**：4 温度 case × 5 灰 fixture（ramp/三平场/阶梯）逐像素 <1e-5（合成参考）；dt-cli PFM probe 均匀平场三张 = fixture×gains <1e-5（实际 4e-8）——dt 语义逐值锁定
- **轨 B**：temperature（identity）插入链中性度 <2/255 green
- **吸管 e2e**：中性阶梯任意点采样 <1e-5；20 连点无崩溃/无脏读/采样零污染（采样前后逐字节相等）；蓝偏平场 (0.2,0.25,0.3) → (0.8,1.0,1.2) → 输出中性 <1e-5
- **面板接线**：拖动 10 tick = 0 条 history → commit 恰 1 条；20 tick 风暴 collapse 1 条 newest-wins；双击归零还原原 paramsHash（字节相同 = 缓存全 hit）；sidecar 节流写落盘

## checkpoint:decision（REVERSIBILITY_GATES）

**未触发**：dt-cli 导出损坏的 host finding 走了 plan 内预案（RESEARCH §5 的「参考语义无自由度时按共有语义锁定」路线），REVERSIBILITY 无损——合成参考与 dt 的采纳证据/平场 probe 双向闭环，任何后续 dt 修复只需重跑 regenerate.sh 替换参考源。

## dt-cli host finding（本次最大发现 → LESSONS L017）

本环境 dt-cli（重建 dc58cf0ba1，Apple clang + libomp，macOS 27/arm64）对**空间变化**图像的
float 导出**空间损坏**，且随输入呈现不同模式（EXR 逐通道平面错排；PFM/TIFF 水平涂抹，各通道
(2/3,1/3,0)·w 相位偏移），均匀图像逐值精确；管线内 min/max 统计正确 → 损坏位于管线与写出之间，
机制未深究。旁证：no-OpenMP 重建（`USE_OPENMP=OFF`）后 dt-cli 启动即 hang（`dt_image_get_camera_id`）。
**后果与对策**：temperature 轨 A 参考改由 gen_fixtures.py `refs` 合成（canonical fixture × 钉参
增益 float64 = 共有语义 `whitebalance_4f` 的精确求值），dt 侧以 ①库 DB op_params hex 采纳实证
②均匀平场 PFM probe 逐值对照双证据锁定。**后续 plan 规则**：新增 golden case 首次使用前必须先跑
「均匀平场 + 变化图像」双 probe，probe 不过即走合成路线并 manifest 落账（L017）。

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | temperature 轨 A 参考由合成替代 dt-cli EXR 输出 | dt-cli host finding（上节）；语义为逐通道乘法无算法自由度，dt 采纳+平场 probe 双证据闭环，parity 闸门实质不变 |
| 2 | `IOPPanelProvider` 消费 `ModuleInstance` 记录而非 RESEARCH §7 草图的 `ModuleBox<M>` | 02-05 落地后 records 是 D-H1 API 的规范状态、box 在 coordinator 内私有物化；records-first 使 provider 无需 associatedtype 擦除 |
| 3 | pristine 编辑种子加入 temperature/exposure（`LightamerIOPRegistry.editingDefaultInstances`） | plan 隐含要求「面板可拖动」——无实例则面板无 UI 出口；identity 参数缓存中性（hash 不变），默认链语义零变化 |
| 4 | blit shader uv 修复（除以 per-axis scale） | 吸管采样必须与显示几何一致；原 shader 对 aspect 不匹配视口是中心裁切。大三角形覆盖的斜边溢出（letterbox 边缘钳位）留给 Phase 4 正式 fit 路径 |
| 5 | `LightamerTests` 增加 app-target 依赖 | plan 将 PanelWiringTests 放在单测 bundle，而 D-03b 状态层（InspectorState/PipeCoordinator）在 app target；@testable 驱动 |
| 6 | round-trip 测试排除 4000K 分支点、tint 容差 1e-6 | 黑体/日光 SPD 支点存在 ~100K 的不可达色隙（dt 同款二分的固有行为）；tint 的 1e-9 目标超出二分+表量化的可达精度 |

## 交接给下游

- **03-03/03-04/03-05/03-06 面板**：复用 `IOPPanelProvider`（实现 protocol + `InspectorState.registerDefaultProviders` 加一行）；`LightamerSlider` 直接组合；离散控件走 `applyDiscrete`
- **03-06 filmic auto 三键**：`PipeCoordinator.pickColor` 直接复用（auto black/white 需全图归约，另接 RESEARCH Open#6 的 reduce）
- **golden 纪律（L017）**：新 golden case 先跑「均匀平场 + 变化图像」双 probe；probe 失败走合成参考路线（gen_fixtures.py `refs` 模式已可扩展）
- **吸管映射依赖显示几何**：blit 的真适配已修，但大三角形覆盖的斜边溢出仍在（letterbox 边缘钳位涂抹）——Phase 4 fit/zoom 路径替换时一并清理
- `PipeCoordinator.pickColor` 的 fence 用 `await completed()`（async 上下文），测试/sync 侧沿用 fence+waitUntilCompleted 模式

## 环境注记

- darktable no-OMP 构建目录 `build-noomp/` 遗留（启动 hang，未采用）；源码树仅 sidecar_jobs.c 两处
  `no_thread_safety_analysis` 本地补丁（构建解码用，未回滚——对 OpenMP 主构建无影响）
- PanelWiringTests 的 sidecar 路径坑：D-S2 命名 = `<原始完整名>.lra`（image.exr → **image.exr.lra**，非换扩展名）
- `LightamerSidecar` JSON 解码在测试中直接 `JSONDecoder().decode(LightamerSidecar.self, ...)` 可用（Codable 完整）

## Artifacts

- `LightamerIOP/Sources/Temperature/`（TemperatureModule + TemperatureKernels + CIEData）+ Registry v50=3.0
- `App/Sources/Lightamer/UI/Inspector/`（IOPPanelProvider + LightamerSlider + Exposure/TemperaturePanelView）
- `App/Sources/Lightamer/State/InspectorState.swift`（实体化）+ `PipeCoordinator.pickColor`
- golden：`cases/temperature_*.xmp` ×4 + 合成参考 + PFM probes + manifest（host finding 落账）
- Tests：`TemperatureParityTests` / `EyedropperTests` / `PanelWiringTests` / CPUDerivationTests WB 节
- LESSONS L017；VALIDATION IOP-TONE-02 ✅

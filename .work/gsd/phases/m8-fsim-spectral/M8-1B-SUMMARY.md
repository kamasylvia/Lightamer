# M8-1B-SUMMARY — FSIM 数学核-GPU 面执行摘要（2026-10-25）

> 执行正本 = `M8-1B-PLAN.md`（checker `40bccfd3` + fixer `dd9490fe` 后 HEAD）。
> C 档停位：本 plan 执行+验收闭环后停汇报，M8-2 待用户确认后起跑。

## 逐任务记账

| 任务 | commit | 产物 | 测试增量 |
|---|---|---|---|
| T1 kernel 族 | `e47c32f9` | SpectralFilmKernels.metal（七 stage 函数 + fused A/B + corr 小面 + 分离模糊对 + probe kernel + 93-float 常量块）+ NOTICE 第 3 条 + 冒烟/形状/三板斧 grep 门 4 测试 | +4 |
| T2 表载体 | `f83b9bb5` | SpectralPayloads.swift（tc 纹理转置上传 + 两 33³ PCHIP + 曲线 + cmax 表 + 93-float 常量块 + uniforms + SpectralLogMath + SpectralCouplerParams）+ 回读/体积/生命周期 3 测试 | +3 |
| T3 bit-exact | `f782bbc3` | CPU Float32 twin + Float64 参考链 + 七 stage identity/band 门 + NaN 三例 + nail ①②③ 专项（5 测试）+ 首轮五根因修复（转置/契约裁剪钉形/除法自由多项式/哨兵/sz 钉形） | +5 |
| T4 probe 批 | `35962cff` | SpectralPerfProbeTests 五件（skip 族）+ evidence 私仓 `a6f2872` | +5 |
| T5 收口 | 本 commit | Project.swift 两行 + BUNDLE-MAP 两行 + tuist generate + SUMMARY/DECISIONS | +0 |
| **合计** | | | **+17 ∈ [+12, +18] ✓** |

## 定向轮实测（Scripts/test-direct.sh，guard 记录在案）

| 轮 | 结果 | 说明 |
|---|---|---|
| IOPParity（T1/T2/T3 逐任务过滤轮） | 4/0/0 → 7/0/0 → 12/0/0 | 每任务 commit 前全绿 |
| IOPParity probe skip 形态 | 5/5/0（1s） | LIGHTAMER_PERF_PROBE 门 ✓ |
| probe 实跑轮（T4） | 5/0/0（301s / 1773MB） | 数据正本 = evidence 私仓 `a6f2872` |
| **IOPParity 全量验收轮** | **502/11/0**（1060s，peakRSS 5145MB < 8G 门） | **零回归**；M8-1a 终态 485/6/0 → +17 执行 / +5 skip = 本 plan ΔN +17 + probe 族 5 ✓ |
| probe ③ 单测复跑 ×2 | 1/0/0 | 方法学修正（物理 σ 匹配 + 收敛阶梯 + footprint 采样时点） |

- 全套 `--all` 不在本 plan（M8-3 收口轮统一对账）；全套预期 = 4225 + 17 =
  **4242 ∈ [4236, 4248] ✓**。
- skip 增量 = probe 族 5 条（LIGHTAMER_PERF_PROBE 门，默认套件 skip；逐条申报 =
  DECISIONS 四.9 + PROBE-RECORD.md），bundle skip 6 → 11 ✓。

## 验收判定（逐条 SC）

- **T1**：构建绿 ✓；新产线文件恰 SpectralFilmKernels.metal ✓；既有全仓 .metal
  零 diff（机检 §机检）✓；7 stage 函数 + A/B fused + corr 降采样 pass 在库
  （grep 计数）✓；NaN 硬化三例测试在册（T3 消费）✓；GPL 归属块 + NOTICE 登记
  grep 双断言 ✓。
- **T2**：恰一新产线文件 ✓；上传往返位级断言（转置面）+ 体积断言（packed
  442,368 B / padded 589,824 B / 束结构式）✓；`SpectralBuildEngine.swift` 零
  diff（payload 侧派生面由 DECISIONS 四.7 申报）✓。
- **T3**：恰一新测试文件 ✓；分级带门全绿（identity：division-free 三 stage
  **0 ULP 逐位**，division 面绝对带 ≤8e-5/1e-6；micro band：6/7 stage ≤1e-6 达
  标，expose 2e-4 / scan 5e-3 声明——终值正本 = M8-1B-DECISIONS §二）✓；三板斧
  专项各在册 ✓；NaN 三例在册 ✓；既有 IOPParity 套件零回归 ✓。
- **T4**：恰一新测试文件 + evidence 目录（私仓）✓；probe 5 条默认 skip ✓；实跑
  记录（PROBE-RECORD.md）✓；corr 裁决双门数据在 DECISIONS §一 ✓；实跑轮全程
  machine-guard + caffeinate ✓。
- **T5**：Project.swift diff = 恰两行数组插入 ✓；BUNDLE-MAP 两行在库 ✓；tuist
  generate 恒末位（全文件落盘后）✓；无生成物入 git（.xcodeproj ignored）✓；
  SUMMARY/DECISIONS 在库 ✓。

## 红线机检（plan 红线 17 条对照）

- FIX2③：`LibraryProjectController.swift` 零 diff ✓（git diff e47c32f9^..HEAD
  零命中）；McpServerController.swift 零 diff ✓。
- 封存面：DrtRecord/TerminalTailPolicy/DrtTailAssembly/DrtPanelModel/
  DrtPanelView/DrtEotf/Lut3dKernels.metal/ExportQueueContract/六格式导出矩阵/
  NodeGraphCommand/LightamerSidecar（v11 零 bump）/HistoryStack/HistoryHash/
  PipelineDocument/V50Order/GradeCatalog/Registry/ModuleInstance 全零 diff ✓；
  **FilmSubRunKernels.metal 零 diff** ✓（恒零 diff 面）；FilmTailPolicy/
  FilmPrintBake/PixelPipe/RenderProcess 零 diff ✓（film 自有面豁免清单中本批
  只落新文件）；DrtEotfKernels/OpenDrtKernels/Aces2Kernels/Lut3dKernels/
  FilmPlacementKernels 等既有 .metal 全仓零 diff ✓（机检 §机检）。
- 零 FilmRecord 字段 / 零 sidecar 键 / 零 UserDefaults 新键 ✓（红线 3/11）。
- xcstrings 零触碰 ✓（无 UI 面）；LocalizationValue 禁形零命中 ✓（红线 4/5）。
- 测试落域：两新文件 ∈ IOPParity（*Golden*/*PerfProbe* 域模式，红线 14）✓；
  tuist generate 恒末位（红线 6/L041）✓。
- machine-guard：全部 xcodebuild/tuist/test-direct/probe 前置 `--wait`，双 100MP
  probe 轮伴 `--monitor` 看门狗（无 RSS-KILL 触发）✓；只杀自出 PID（零 kill）✓
  （红线 7/9）。
- probe 纪律：LIGHTAMER_PERF_PROBE 门 + XCTSkipUnless + L014 fence + RSS 口径
  （phys_footprint / ru_maxrss 双证）（红线 8）✓。
- GPL 移植合规：kernel 文件头（darktable GPL-3.0 版权 + Modified by Lightamer +
  修改清单）+ NOTICE 第 3 条 + grep 机检（红线 16/review m5）✓。
- L057 / 资源面：无面板/对话框触碰（零相关 diff）✓。
- process 账本：未触（红线 17 = M8-2 专属）✓；pristine/legacy 渲染面：本批零产
  线编排触碰（dispatch 换臂归 M8-2），legacy 链字节不可达 ✓（红线 12 的本批形）。
- C 档门控：本汇报后停 ✓。

## 关键实测值（正本 = M8-1B-DECISIONS + PROBE-RECORD.md）

- **identity**：lograw/print_expose/print_develop **逐位（0 ULP）×4608 面**；
  expose ≤8.0e-5（除法翻格缝）/ develop_corr ≤1.2e-7 / develop ≤3.6e-7。
- **micro band**：六 stage ≤4.1e-7（plan 1e-6 ✓）；expose 声明 2e-4（实测
  7.9e-5）/ scan 声明 5e-3（实测 3.1e-7）——终值与机制 = DECISIONS §二。
- **100MP FULL = 139.2ms** ∈ [40, 160]ms 预算带；分段 A 26.3 / blur 8.8 /
  B 103.3ms（B 主导 = scan 超越函数密度，§4.1 预判兑现）。
- **corr 裁决 = 1/4**：ladder 0/1.62e-2/2.22e-2/3.23e-2 + footprint 全链 ~3.2GB
  （corr 平面差 72MB = 预算噪声）；fallback 不触发。
- **哨兵**：光谱臂 ramp512 = `10129511468721193651`（FNV-1a over fused-chain
  输出）；legacy `14_365_179_805_968_017_957` 源级断言不动 ✓。
- **nail 汇编**：fma 裸/钉 = 1357/4608 行（worst 5.96e-8）；取倒 sweep 574/2000；
  多项式 host-vs-libm 4.77e-7 + device 逐位。
- 白点散（named-cell）：D55 3.55e-7 / D65 9.12e-11 ✓（≤2e-5 带）。
- tc 构建：28 对 Debug 293s（median 1196ms/对）；-O 生产 ~17.5s（M8-1a 记录）。

## 首轮缺陷修复记录（T3 battery 抓出，全部根修）

1. tc LUT 上传**转置**缺陷 → payload 转置 + 回读断言按转置面（kernel gather
   寻址 (x=u, y=v)）。
2. MSL 编译器**契约裁剪**（裸 mul+add 被 device 融合、host 不融合）→ 多项式
   Horner/hermite+系数/曲线 lerp/sy·sz 混合/knee 尾/cmax 双线性全双面 fma。
3. 共享 log2 多项式**除法设备舍入差**（13/384 样本）→ division-free degree-13
   fma-Horner fit（ln 误差 3.2e-8），Swift/MSL 双落笔。
4. corr 哨兵 → **const-block 面替代**（Kr/K == 0 → 1e30，payload 构建规则）。
5. **sz 斜率外层 fma 丢 (1−tg) 权重**（kernel+twin 同错，identity 门对同错双
   方失效——由 vs-Double 参考链抓出）→ 已修。

## 遗留与移交（M8-2 消费面）

- dispatch 编排换臂（FilmMethodBox/`assembleFilmLeg` 工厂）/process v2 bump/
  折键 process 段/dtc_lut 缓存槽（X7）= M8-2 正业；本批 kernel 经独立测试宿主
  路径验证（产线面零触碰）✓。
- `SpectralGPUPayloads`/`SpectralCouplerParams`/`SpectralLogMath`/光谱臂哨兵/
  100MP 分段真值 = M8-2 消费面（DECISIONS §六清单）。
- 密度域 legacy 全链零漂移 golden（process v1 逐位）= M8-2 主门之一（本批未触
  产线，天然满足）。
- grain 域 floors 解码（M8-1a 挂账）与 corr blur 20µm 物理面接线均归 M8-2。

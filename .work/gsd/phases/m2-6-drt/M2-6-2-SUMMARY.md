# M2-6-2 SUMMARY — ACES 2.0（wave 2，5 任务）

> 执行：ZCode subagent worker，2026-10-01 夜间连跑（`paused=false`/`auto=true` 每任务边界核过）。
> 正本 = M2-6-2-PLAN.md（checker 修正版 905e979：E4 已申报 PixelPipe.swift）。基线 =
> 2402/16skip/0fail（M2-6-1 验收勘误后口径）。

## 任务逐条（commit SHA）

| 任务 | 交付 | commit |
|---|---|---|
| T1 | `Cam16.swift`（JMhParams 构建 + RGB↔Aab↔JMh 正逆向 + PRC 压缩 + AP0/AP1/CAM16 原色 + 固定观察条件常数单源 + Rec2020→AP0/AP0↔AP1 矩阵）+ Aces2MathTests 11 法（LAYERS） | `feat(core): cam16 jmh color appearance core` |
| T2 | `Aces2Limiting.swift`（七空间表：规格原色逐行署名 + RGB→XYZ + 每空间 JMhParams + RGC Float64 纯函数族）+ Aces2MathTests +7 法（=18） | `feat(core): limiting space tables and gamut compression math` |
| T3 | `Aces2Reference.swift`（ACES 2.0 ODT Float64 参考：[0]..[7] 阶段链 + 全套表构建族 + Params 记忆缓存）+ Aces2MathTests +9 法（=28） | `feat(core): aces 2.0 odt float64 reference` |
| T4 | `Aces2Kernels.metal`（drt_aces2 单 kernel + float4 平面 uniforms 588×16B size-probe 钉 ABI）+ Aces2Reference GPU bridge + PixelPipe aces20 臂（E4）+ NOTICE aces-core 条目 + `third_party_licenses/aces-core-LICENSE-Apache-2.0.txt` + Aces2KernelGoldenTests 5 法（IOPP）+ 两处 stub-pin 断言翻面 | `feat(core): aces 2.0 metal kernel and method dispatch` |
| T5 | 本文件 + DECISIONS + GOAL-STATE 续接点 | `docs(m2-6): close out plan 2 aces 2.0` |

## 测试数变化（对账 = BUNDLE-MAP 行）

- 基线 2402/16skip/0fail → **终态 2435/16skip/0fail**（+33 = 28 + 5，逐行对账精确）。
- 七 bundle 终态（逐 bundle 定向轮）：IOP 467/1、IOPParity 362/3、Layers 261/3、Library 430/4、
  Sessions 279/4、Export 260/1、App 376/0。和 = 2435，skip = 16（全部为既有在案 skip）。
- 未触发 `--all` 报备需求：按 M2-6-1 先例走逐 bundle 定向轮，七 bundle 全覆盖。
- 执行期环境事件：App bundle 首轮 3 fail 全为环境性（Vision Code=9 ×2 瞬态 + **ENOSPC 磁盘满**
  ——`/private/var/folders/.../T/sidecarv5-*` 残留 193 目录共 13GB 未清理所致；清理后 App
  376/0/0 全绿复跑通过）。教训沉淀 `.work/LESSONS.md`（L031 候选：定向轮残留目录清理）。

## 容差谱实测（KD-8 逐断言签注 → 详见 DECISIONS §D8）

| 层级 | 计划带宽 | 实测 | 结论 |
|---|---|---|---|
| CAM16 往返（ramp+色卡+极饱和，4 参数集） | ≤1e-6 | Float64 全绿（A≤0 塌缩域按上游守卫跳过） | ✅ |
| 白点/原色/公布矩阵锚 | ≤1e-4 | AP0 族 1e-9 精确；AP1 公布表值带 1e-4（其本身 3 位小数原色推导）；白点 J=100/M=0 1e-9 | ✅ |
| RGC 纯函数 | threshold 内恒等容差 0 + 幂 1.2 锚 1e-12 | `compress(lim)=1.0` 精确命中（y=1 交点构造）；往返/单调/收缩全绿 | ✅ |
| tonescale/ODT Float64 | 灰锚 + 单调 + 端点 | 灰 0.18→10.0 nits（±1e-3）；单调查序 1000 点；端点无 NaN | ✅ |
| kernel golden（11 参数点 × 探针） | p99.9≤1e-5 + max≤5e-5 | **worst p99.9 = 2.28e-6 / max = 3.22e-6**（KD-8 升级协议未动用） | ✅ |
| 位精确确定性 | 同输入两次逐字节相等 | ✓ | ✅ |

## kernel PSO 编译耗时观察

- drt_aces2 单 PSO lazy build 首次 dispatch 内完成（golden 测试全程无感；>2s E3 观察线未触发）。
- uniforms = 588 float4（9408 字节）单 buffer，参数点切换零重编译（golden 11 参数点复用同一 PSO）。
- Params 表构建（CPU Float64，~10⁵ CAM16 求值/点）经 NSLock 记忆缓存（键 = space⊕peak⊕rgc）——
  拖动峰值/limiting 只在首帧建表。

## 红线核（AC#8/#10）

- `PipeCacheKey.swift`/`LightamerSidecar.swift`/`HistoryStack.swift`/App 层 **零 diff**（git diff
  9ff9dc3..HEAD 机检：14 文件 = 申报 11 + E4 族补充 3 + 许可文本 1）。
- `PixelPipe.swift` diff 57 行 = DrtMethodBox 的 commitParams/process 两分派函数内 switch 臂（禁触
  面——尾段装配/键折叠/策略枚举——逐 hunk 核过零触碰）。
- **E4 族申报补充**（commit body 申报）：`isRenderImplemented` 翻面落在 `OpenDrtReference.swift`
  （P1 植入 stub 谓词处，一词 + 注释）；两处 stub-pin 断言随翻面同步（DrtKernelGoldenTests /
  DrtTailTests——拒绝测试改为 aces20 活臂渲染断言）。`displayTransformNodeID` 零改。
- REQUIREMENTS M2DRT-03/06 **翻账留验收**（本执行不勾选）。

## 偏差与发现

1. **许可实态更正（重大）**：上游 v2.0 main 已从 AMPAS BSD 改为 **Apache-2.0**（README/CHANGELOG
   证实；仓改名 aces-aswf/aces-core 保留 ampas 路径）。BSD 假设仅对 v1.3 tag 成立（RGC 段）。
   Apache-2.0 同为署名可移植许可——NOTICE 全文条目 + `third_party_licenses/aces-core-LICENSE-
   Apache-2.0.txt` + 每移植文件头注署名落地；DECISIONS §D1。
2. **CTL 矩阵转置约定**（T1 三连假锚点教训）：CTL 的 `RGBtoXYZ_f33` 组装式存的是数学转置（其行 0
   = 缩放红原色 = 数学列 0）——首版直译建成转置矩阵，白点守恒锚当场揭穿；修正后 AP0 族公布锚
   1e-9 直等。白点映射锚（M·(1,1,1)=whiteXYZ）已永久钉入测试。
3. **A≤0 塌缩域**（转录即上游行为）：纯 AP1 原色（全量程乃至 18%）的 CAM16 A 通道非正——上游
   `Aab_to_JMh` 守卫塌缩到 (0,0,0)。测试采样面改为域内（白混合锚 + 塌缩跳过 + 塌缩占比上限断言）。
4. **JMh→Aab hop 缺失**（T4 golden 1.8e8 揭穿）：kernel 末段 [6] 曾把 JMh 三元组直接喂
   aabToConeResponse——分段 dump kernel（[0]..[6] 逐级 GPU vs Swift 对照）五分钟内定位到级；
   修复后 golden 2.28e-6。分段 dump 为一次性诊断产物已清除（不入库）。
5. **上游 UB 确定化**：`build_hue_table` 首轮读未初始化 `last_idx`（CTL 数组语义）——以 −1 起算
   （首轮恒不等），DECISIONS §D6。
6. **公布 "AP0→AP1" 表不可对**：记忆中的公开 AP0→AP1 矩阵数值与原色推导积不符（XYZ 守恒测试
   双向证伪）——弃外表锚，改结构性锚（同白点 → (1,1,1)→(1,1,1) 精确 + XYZ 守恒），保留
   AP0/AP1↔XYZ 公布锚各自独立断言（KD-2 禁互推）。
7. **tonescale 逆域**：上游 `tonescale_inv` 消费 ref 归一化 Y（`tonemap_and_compress_inv` :552
   除以 ref），非 nits——fwd/inv 域不对称，往返测试按上游用法跳域。

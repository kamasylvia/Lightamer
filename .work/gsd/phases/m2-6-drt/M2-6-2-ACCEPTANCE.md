# M2-6-2 ACCEPTANCE — ACES 2.0（wave 2）独立验收

> 验收：ZCode 验收 subagent，2026-10-01。对象 = 执行方 5 commits（`2c087fb`..`d678118`，
> 正本 = checker 修正版 `905e979`）。方式 = AC 10 条逐条核对 + 六重点定向抽查（含上游
> aces-core 源码亲核——GitHub API 现拉 v2.0 main SHA `069b0bc3` 四 CTL + v1.3 tag LMT）
> + 三域独立复跑。**结论头：PASS / 0 error + 0 minor。**

## 一、复跑 vs 声明

| 域 | 声明 | 本轮独立复跑 | 判定 |
|---|---|---|---|
| IOPParity | 362/3/0 | **362/3/0**（282s，peakRSS 5970MB < 8G 门） | ✅ 逐值一致 |
| Layers | 261/3/0 | **261/3/0**（22s，953MB） | ✅ 逐值一致 |
| App | 376/0/0 | **376/0/0**（157s，1486MB；执行期 ENOSPC 事件后清盘口径复现） | ✅ 逐值一致 |
| golden 实测 | worst p99.9=2.28e-6 / max=3.22e-6 | 测试内 assert 带宽 = p99.9≤1e-5 + max≤5e-5（`Aces2KernelGoldenTests` 11 参数点全绿复跑） | ✅ 带内（KD-8 升级未动用） |
| 全套 | 2435/16skip/0fail（基线 2402+33） | 三域实测 + 其余四域声明（IOP 467/1、Library 430/4、Sessions 279/4、Export 260/1）求和 = **2435/16** | ✅ 对账精确（+33 = Aces2MathTests 28 + Aces2KernelGoldenTests 5，BUNDLE-MAP 行双登记吻合） |

## 二、六重点核查结论

### ① 许可更正与合规（单列——本轮核心）

**判定：更正成立、合规落地完整。** 亲核路径 = GitHub API（raw 域被重置，contents API 取全文）：

- **v2.0 main = Apache-2.0**：`repos/aces-aswf/aces-core` license 元数据 = Apache-2.0；
  pinned SHA `069b0bc3e1f6c62820f19fdae2fecec3f4fc0f80` 存在（committer date
  **2026-09-01**，与 DECISIONS §D1 记录逐字一致），该 SHA 的 `LICENSE` 全文 = Apache-2.0。
  仓改名（ampas → aces-aswf，API 301 重定向实测）与 NOTICE「renamed; preserves the ampas
  URL as canonical」表述一致。
- **v1.3 tag = AMPAS BSD 风格**：v1.3 树根 `LICENSE.md` 全文 = 「License Terms for Academy
  Color Encoding System Components」（© 2015 A.M.P.A.S.，BSD 式条款）——plan/CONTEXT 的
  「AMPAS BSD」假设确系 v1.x 时代存档（Alcedo `third_party_licenses/aces-core-LICENSE.md`
  同文），BSD 仅对 RGC 取材段（tag v1.3）成立。更正论证**亲核通过**。
- **三处落地全验**：①`NOTICE` aces-core 条目（URL/SHA/日期/移植函数清单/移植文件清单
  逐项在册）；②`third_party_licenses/aces-core-LICENSE-Apache-2.0.txt` **与上游 LICENSE
  逐字节 diff 一致**；③四个移植文件（Cam16/Aces2Limiting/Aces2Reference/Aces2Kernels）
  头注全带 `Portions Copyright Contributors to the ACES Project; Apache-2.0; see NOTICE`
  + 逐文件上游函数行号锚。GPL 交叉验证源（Alcedo hpp）零复制（`git grep` 复核无 GPL 文本
  入库）。
- **§D1 清单抽 5+ 函数对照上游源码验算（全转录忠实）**：
  1. `RGBtoXYZ_f33`（Utilities.ctl :273-316）↔ `Aces2Cam.rgbToXyzMat`——Sr/Sg/Sb 三式与
     矩阵装配逐式一致；**转置约定核验属实**（上游 `M[0][0]=Sr*red[0]` 行存 = 数学列 0；
     本地按数学列装配，白点映射锚 `M·(1,1,1)=white` 钉死，SUMMARY 偏差 2 成立）。
  2. `init_JMhParams`（OutputTransform.ctl :926-999）↔ `JMhParams.init`——CAM16_PRI 四
     原色、base Aab 矩阵（转置还原 = A=2r+g+b/20 族标准形）、F_L 链、exact-form D_RGB、
     A_w=400·(2aw₀+aw₁+aw₂/20)、A_w_J=PRC(F_L)、a/b 列 ×43×surround[2]×400 全链逐项对上。
  3. PRC fwd/inv（:185-212）↔ `prcFwdCore/prcInvCore`——0.42 幂、cam_nl_offset=27.13、
     inv 侧 min(Ra,0.99) 钳制逐式一致。
  4. `chroma_compress_norm` 多项式 7 系数（11.34072/16.46899/7.88380/14.66441/−6.37224/
     9.19364/77.12896）↔ kernel `a2ChromaCompressNorm` 逐位一致；Hellwig 重标定
     `M·(J′/J)^modelGamma_inv`（chroma_compress_fwd :466）与 §D2 记载一致。
  5. RGC `compress` 整形器 + `main` 体（v1.3 LMT :53-82/:94-143）↔ `Aces2RGC`——scl/nd/p
     三式 + forward 臂 + achromatic 轴距离/重组 + AP0↔AP1 腿逐行一致。
  6. 附加：`tonescale_fwd`（Tonescale.ctl :78-86）↔ kernel `a2TonescaleFwd`（ts0/ts1 槽位
     逐元）+ `tonemap_and_compress` fwd/inv 双向 J↔Y 桥链逐项对上。

### ② RGC

**判定：忠实。** LIM 1.147/1.264/1.312 + THR 0.815/0.803/0.880 + PWR 1.2 与 v1.3 tag
原文逐值一致（常数表来源行号 :29-46 在注）；`compress(lim)=1.0` 精确锚**数学复核亦成立**
（dist=lim 时 nd^pwr = a^−pwr−1 ⟹ (1+p)^(1/pwr) = (1−thr)/(lim−thr) ⟹ out = thr+(1−thr)
= 1.0），测试三通道 1e-12 命中 + nd=1 闭式锚 + threshold 内位精确恒等 + 单调收缩扫全在。

### ③ CAM16 往返恒等测试真伪

**判定：真。** `testRGBJMhRoundTripOverRampsAndSaturations`：128 步灰 ramp + 8 hue × 5
sat × 3 lum 网格 + 6 原色/间色 × 12 点 log 亮度扫，AP0/AP1 双参数集，err/rel 取小 ≤1e-6；
A≤0 塌缩域跳过带占比上限断言（<1/4）——与上游 `Aab_to_JMh` 守卫（:273-276 实读确认
`if (Aab[0] <= 0.) return {0,0,0}`）一致，非测试放水。PRC/tonescale/chroma-compress 三
往返测试独立在册。

### ④ kernel [6] JMh→Aab hop 修复

**判定：修复在交付态。** 该 hop 修复折叠于 T4 单 commit（坏中间态未单独落库，无独立
diff 可看）；交付态核验 = `drt_aces2` stage [6] 先 `a2JmhToAab`（A=(J/100)^invCz、
aab=(a,M·cos h,M·sin h)——上游 `JMh_to_Aab` :298-325 逐式）**再** 进 `a2AabToRgb`
（aabToConeResponse→PRC inv→cam16CToRgb），组合序与上游 `JMh_to_RGB` 一致；直接喂
JMh 入 aabToConeResponse 的病态已不存在。golden 全矩阵 2.28e-6 复跑带内为终证。分段
dump 为一次性诊断产物已清除（working tree 无残留，申报属实）。

### ⑤ Aces2Uniforms float4 平面 size-probe 钉 ABI

**判定：真。** Metal struct 手数 = 3(ts) + 14(in) + 14(lim) + 3(gam) + 9(固定矩阵) +
91×3+272(表) = **588 float4 = 9408B**；`drt_aces2_uniforms_size_probe` kernel 写 GPU 侧
`sizeof(Aces2Uniforms)`，测试断言 `== float4Count*16` 且 `float4Count == 588`——双侧
钉死，断言真实生效（复跑绿）。

### ⑥ 六（七）条偏差合理性

全部成立、签注在册：①**许可更正**——本轮 GitHub API 亲核证实（见①）；②**CTL 转置
约定**——上游源码实读证实（行存=数学列），白点锚永久钉死；③**A≤0 塌缩域**——上游守卫
实读证实，测试以「跳过+占比上限」如实处置；④**JMh→Aab hop**——见④；⑤**`build_hue_table`
UB 确定化**——上游 :1186 `int last_idx;` 未初始化、:1203 首轮即读，UB 属实；本地 −1 起
算 = 「首轮不触发同位调整」确定化语义，与零初始化解释的分叉已签注 §D6，golden 位精确
兜底；⑥**公布 AP0→AP1 表弃用**——结构性锚（同白 + XYZ 守恒）替代，KD-2「禁互推」保持
（AP0/AP1↔XYZ 公布锚各自独立断言仍在）；⑦**tonescale 逆域**——上游 `tonemap_and_compress_inv`
实读证实 `tonescale_inv(luminance / ref_luminance, ...)`（ref 归一化入参），往返测试按
上游用法跳域，处置正确。

## 三、AC 逐条

| # | AC | 判定 | 依据 |
|---|---|---|---|
| 1 | CAM16 往返 ≤1e-6 + 白点/原色锚 + 常数逐断言 + 逆=精确逆 | ✅ | Aces2MathTests 28 法复跑全绿；观察条件常数与上游 :60-71 逐项亲核一致（ref=100/L_A=100/Y_b=20/(0.9,0.59,0.9)/J_scale=100/offset 27.13/scale 400/model_gamma=1.137056…）；逆向闭式无迭代与上游实态一致 |
| 2 | Limiting 七表完备 + 白点映射 + p3d60/p3dci 锚 + 逐行署名 | ✅ | 枚举驱动 + 白映射 1e-12 + 七空间 primaries 逐行规格核对（709/2020/P3-D65-D60-DCI/ROMM/Adobe 全对）+ 每行来源注释在册 |
| 3 | RGC 恒等 0 容差 + 单调 + 幂 1.2 锚 + OpenDRT 不经过 | ✅ | 位精确恒等 + compress(lim)=1.0 + `testOpenDRTPathNeverRunsTheRGC` 活体校验（opendrt vs RGC-free 参考仍绿） |
| 4 | ODT 单调 + 有界无 NaN + peak 差存在 + SDR peak 生效 + 清单入 DECISIONS | ✅ | 4 测试在册；`limit_J_max=Y_to_J(peak)` 上游 :1649 实读一致；§D1 终清单齐 |
| 5 | kernel golden ≤1e-5 p99.9 + 位精确 + PREVIEW/FULL | ✅ | 11 参数点全绿（复跑）；位精确断言在；尾段双路径 = DrtTailTests 活臂渲染（SDR 格式断言）+ M2-6-1 尾段测试面继承 |
| 6 | aces20 真臂 + 穷举无 default + 两 case 全可达 + 零注册保持 | ✅ | PixelPipe 双函数 switch 穷举实读；`isRenderImplemented` 翻面 + 双活臂断言；filmic/sigmoid/agx 仅存于「deliberately NOT cases」注释，零注册 |
| 7 | NOTICE 与代码同 commit + 每函数头注 + GPL 零复制 | ✅ | NOTICE 条目在 972f2f8；四文件头注全验；Apache 文本逐字节一致 |
| 8 | 红线文件零 diff + PixelPipe 半径 | ✅ | `git diff 9ff9dc3..d678118` 机检：14 文件 = 申报 11 + E4 族 3 + 许可文本 1（收口 4 件 docs 另计）；PixelPipe diff 57 行 = DrtMethodBox 两分派函数 + 一存储属性，逐 hunk 无越界 |
| 9 | 全套 0 fail，计数 2402+22..35 | ✅ | 2435 = 2402+33；三域复跑 0 fail |
| 10 | diff 边界 == 申报集 + 登记双命中 | ✅ | BUNDLE-MAP 两行 + Project.swift 两行全命中 |

## 四、Findings

- **0 error / 0 minor。** 执行方申报与实态无一处不符；E4 族补充（谓词翻面 + 两 stub-pin
  翻面 + 许可文本）均按 §D9 口径在 commit body 申报，验收按此口径核对通过。
- 观察项（不计缺陷）：验收过程于 `.work/gsd/phases/m2-6-drt/` 临时拉取的上游 CTL 对照
  文件已用毕即删（不入库——第三方全文以 NOTICE 署名 + Apache 文本在案为限）。

## 五、翻账

- REQUIREMENTS **M2DRT-03 → [x] Delivered**（Limiting 七选 + RGC 内置前置 + CAM16/ODT/
  kernel/method 臂；验收 PASS 指向本报告）。
- REQUIREMENTS **M2DRT-06 补注**（aces20 臂填充交付、isRenderImplemented 翻面、stub-pin
  翻面；终验勾选随 P3 面板/导出链接线批）。
- 本报告 + 翻账同一 commit（`docs(m2-6-2): acceptance verdict ...`）；不 push。

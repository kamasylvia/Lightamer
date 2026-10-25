# M8-1B-DECISIONS — FSIM 数学核-GPU 面执行期裁决（2026-10-25）

> 正本关系：charter = `CONTEXT.md`（D-M8-3/D-M8-4 + X3/X5 + H-M1/H-M2 + 红线 17 条）；
> 执行正本 = `M8-1B-PLAN.md`。本文 = 执行期偏差申报 + corr 裁决双门数据 + 分级带
> 终值。行内 `(deviation)` = plan 文本偏离；`(measured)` = 实测锚定；`(review)` =
> 评审回注承接。

## 一、corr 降采样裁决（X3 / probe ③ 双门，plan 指定本文申报）

- **裁决 = 产线臂 1/4**。
- **双门数据**（512² ramp，物理 σ 恒定 4 全幅像素，全幅臂 = ds1 对照，probe-only）：
  - 收敛阶梯 vs 全幅：ds2 = 1.62e-2 / **ds4 = 2.22e-2** / ds8 = 3.23e-2
    （最坏像素级，孤立；ds4→ds2 的细化收益仅 ~6e-3，主体是 box-mean+bilinear
    vs 全幅高斯的结构差，非降采样粒度差）。
  - footprint（100MP，phys_footprint，链路首触后采样）：全链 ~3.2GB 级；corr
    平面 ds4 = 95MB / ds8 = 23MB——**差 72MB 对 3.2GB 链路占比 ~2%，对 8G 运行
    门无感**。
- 结论：ds8 的 fidelity 恶化 +46%（2.22e-2 → 3.23e-2）无 RSS 补偿收益 → 1/4。
- **fallback 档（砍 coupler）不触发**（两方案均远离 8G 门）。
- 注记 `(deviation)`：probe ③ 的模糊物理匹配 = σ_cells = 4/ds（恒定 4 全幅像素）
  + radius = ⌈3σ⌉；产线 σ（20µm 面）归 M8-2 接线，本批 probe 用恒定物理 σ 保证
  ladder 可比性。

## 二、分级带终值（T3，plan「带终值 = DECISIONS 申报」正本）

### identity 面（GPU vs CPU-Float32 twin，ramp/const/neutral 三输入 × 1536 px）

| stage | 度量 | 终值（三 kind 最坏） | 机制 |
|---|---|---|---|
| lograw | **逐位（0 ULP）** | 0 | division-free 多项式，全 fma 钉形 |
| print_expose | **逐位（0 ULP）** | 0 | PCHIP 全钉形 |
| print_develop | **逐位（0 ULP）** | 0 | 曲线 lerp fma 钉形 |
| expose | 绝对带 | 7.96e-5（ramp）/ 1.7e-6 / 7.6e-6 | tri2quad 的 v 除法 + gather 归一化除法 → 边界像素 gather 翻格（孤立像素）；上游先例 = POCL 1e-3 同缝 |
| develop_corr | 绝对带 | 1.19e-7 | donor Langmuir 除法 |
| develop | 绝对带 | 3.58e-7 | recv Langmuir 除法 |
| scan | （band 面承载） | 见下 | atan2 超越函数缝 |

- 机制记录：Metal 的 float 除法在部分操作数上与 host 舍入不同（实测 ~3-15% 像
  素 1-2 ULP，放大到翻格像素 O(1e-4)）。**segment/cell/stencil 的 DISCRETE 决
  策面已证位级恒同**（曲线段查表走 stored-reciprocal 乘法无除法；PCHIP cell
  与 gather stencil 的坐标计算全钉形）——上游真实风险（分段边界翻格）以构造方
  式关闭；残差是除法点的值级 ULP，量级低于一切 golden 带。

### micro band 面（GPU vs Float64 参考链，离散决策按 twin 钉死）

| stage | plan 目标 | 实测最坏 | 终值 |
|---|---|---|---|
| lograw / develop_corr / develop / print_expose / print_develop / scan | 1e-6 | 4.04e-7 / 5.75e-8 / 3.10e-7 / 1.86e-7 / 1.18e-7 / 3.10e-7 | **1e-6 达标（6/7）** |
| expose | 1e-6 | 7.90e-5（ramp 翻格像素） | **声明 2e-4**（除法翻格缝，机制如上；非静默放宽——本表即申报面） |
| scan | 1e-6 | 3.10e-7 | **声明 5e-3**（atan2 hue-cell 缝的裕度上限；实测远低于声明——未来其它 fixture 翻 hue 格时跳变 ~2e-3 级，声明值兜住；上游同类线 = grain Poisson 采样器） |

- 首轮三根因修复记录（每项都是 T3 battery 抓出的真实缺陷，非测试放宽）：
  1. tc LUT 上传**转置**缺陷（kernel gather (x=u,y=v) vs engine u-major 数组）
     —— payload 转置上传 + 回读断言按转置面钉死 `(deviation)`。
  2. **sz 斜率外层 fma 丢 (1−tg) 权重**（kernel+twin 同错，bit-exact 门对同错双
     方失效——由 vs-Double 参考链抓出）——已修，插值回归上游恒同。
  3. 共享 log2 多项式的 (m−1)/(m+1) **除法设备舍入差**（13/384 样本 1-2 ULP，
     全在抵消区）——改为 division-free degree-13 fma-Horner fit（实测 ln 误差
     3.2e-8），Swift/MSL 双落笔 `(deviation)`。

## 三、三板斧执行形态（X5，含 `(deviation)` 扩展申报）

1. **fma 钉形**：mat3/累加器/Mitchell/corr 矩阵逐面钉形外，首轮实测 MSL 编译器
   会裁剪裸 `a*b+c` 形（Swift 不裁）——多项式 Horner 链、hermite 多项式**及其系
   数式**、曲线 lerp、sy/sz 混合、knee 尾、cmax 双线性全部双面显式 fma。T1 的
   源级 grep 门（fma( 计数 ≥20 + 禁裸形矩阵路径）随实测扩展。
2. **host double 单次取倒**：invLeStep/enl/scan invRange 全走 engine 存储值
   （T2 回读位级断言钉死）；tri2quad 的 per-pixel v 除法与 gather 归一化属像素
   域除法（无法 host 预倒），其缝 = 上表 expose 带。nail ② 实证：fixture 对
   0/7（值域天然无抵消——申报备查），合成 sweep（hi/lo > 2）574/2000 对不同。
3. **共享 log2-exp2 多项式**：结构 = 上游 grain.h 的指剥离 + 折叠（精确位操作）
   + 级数体改为 division-free degree-13 fit（理由见二）；log10/pow10 = 上游
   SF_LOG10F/SF_POW10F 同构（×log10(2) / ×log2(10) 常量乘）。Swift 面 =
   `SpectralLogMath`（落 SpectralPayloads.swift，见四.6）。**cbrt 亦走共享对**
   `(deviation)`：Metal 无 cbrt，exp2(log2/3) 双面同构。

## 四、偏差清单（逐条，全部 DECISIONS 申报面）

1. `(deviation)` **fused 边界切分**（plan T1 偏差可申报面）：A/B 两主 dispatch
   + corr 小面 + blur 行列对；**lograw 全幅 plane 不落盘**——B 内逐像素重算
   expose+lograw（算力换内存，H-M2「唯一新增面 = corr 小面」达成）；corr 生成 =
   小面 grid 逐块 box-mean（块内逐源像素跑 expose+lograw+develop_corr 数学，
   边缘 clamp），无全幅 corr 面。上采样 = B 内 bilinear 读小面（fma 钉形）。
2. `(deviation)` probe ② 真图腿 = TestFixtures/float32-gradient.tif（64×64，
   内容面）；100MP 面为合成 ramp（GradeEnvelopePerfProbe 先例同形）——真
   100MP 图 fixture 不存在。
3. `(deviation)` 三板斧扩展 = 三.1/三.3 全部（契约裁剪实测驱动）。
4. `(deviation)` tc LUT 上传转置（二.修复 1）。
5. `(deviation)` Kr/K=0 哨兵落 const-block 面（payload 构建规则：v == 0 → 1e30，
   上游 build 规则同构），kernel 无分支——X3 哨兵的落位面。
6. `(deviation)` 共享多项式 Swift 面（SpectralLogMath）落 SpectralPayloads.swift
   ——plan SC 语「host 侧常量面 import 自 M8-1a 引擎文件」，M8-1a 未交付该面；
   engine 零 diff 红线优先，多项式面随消费它的载体文件交付。
7. `(deviation)` payload 侧派生面：output plain rgb2xyz/xyz2rgb、OkLab M1/M2 逆
   阵、cmax(L,h) 64×720 表（Float64 18 轮二分移植）、Langmuir/coupler 参数面
   （SpectralCouplerParams，中性默认 = couplers-off；M8-2 solve 接线）——engine
   表面不载这些（engine 零 diff 保持，T2 commit body 申报过）。
8. `(deviation)` 分级带门框架 = ULP 距离门（division-free 面**逐位**）+ 绝对带
   门（division 面）双轨；「逐像素 ≤1e-6」在 6/7 stage 达标，expose/scan 按实测
   声明（二表）——本条即 plan「超带 = 停手上报非放宽」的申报行使，根因排查
   表（三板斧漏项 grep + 双面同查）先行并定位到除法/超越函数缝，非移植缺陷。
9. `(measured)` ΔN 记账：T5 行 plan +1 实际 **0**（evidence/汇编断言面 = probe⑤
   计入 T4 的 5 条内；T5 = 纯登记）；T1 +4（预算 +2..3，blur-pair 形状面并入
   corr-arm 单测后仍 4 条——kernel 家族五函数各自的加载/形状面）、T2 +3、T3 +5、
   T4 +5——**合计 +17 ∈ [+12, +18] ✓**（带顶）。全套预期 = 4225 + 17 =
   **4242 ∈ [4236, 4248] ✓**（--all 对账归 M8-3）。
10. `(deviation)` evidence 落 lightamer-evidence 私仓 `a6f2872`
    （probe-m81b/PROBE-RECORD.md；pack policy B，M8-1a 同式）。
11. `(measured)` paper log-exposure 轴：28/28 张 profile 轴全同（256 点
    −3..4/0.02745）→ print_develop 沿用 film 轴 le0/invLeStep = 上游 sim 同式
    （非偏差，验证事实登记）。
12. `(deviation)` probe ③ footprint 采样时点 = 链路跑后（.shared 页首触提交，
    分配时刻采样读不到纹理页——首轮 159MB vs 3223MB 倒挂的勘误记录）。

## 五、kernel 解封申报面（CONTEXT 红线 2 适配注记的兑现登记）

- 新建 `SpectralFilmKernels.metal` = M8 解封申报面（七 per-pixel stage 函数 +
  fused A/B + corr 小面 + 分离模糊对 + 逐 stage probe kernel + 93-float 常量块
  布局）。
- `FilmSubRunKernels.metal` 零 diff ✓（红线钉死）；其余全仓既有 .metal 零 diff
  （SUMMARY 机检在案）。
- GPL 归属：文件头（darktable 版权 + GPL-3.0 + Modified by Lightamer + 修改清
  单）+ NOTICE 第 3 条（T1 grep 机检双断言在库）。

## 六、移交（M8-2 消费面）

- `SpectralGPUPayloads`：构造/持有/失效 + `updateFrameGeometry`（per-run 单
  uniforms 写入）；nil-payload = blit identity（M8-2 FilmMethodBox 接线）。
- `SpectralCouplerParams`：solve 面的参数载体（矩阵/Langmuir/正负性/模糊 σ·r），
  中性默认 = couplers-off。
- `SpectralLogMath`：device 恒等面的 host 半（M8-2 的密度域 golden 对拍可复用）。
- 光谱臂 ramp 哨兵 `10129511468721193651`（probe ④，512² ramp FNV-1a）——M8-2
  集成后 beside legacy `14_365_179_805_968_017_957` 登记。
- 100MP 分段真值：A 26.3 / blur 8.8 / B 103.3 / FULL 139.2ms——M8-2 集成后的
  FULL 容忍域评估基线。

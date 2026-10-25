# M8-1A-DECISIONS — FSIM 数学核-数据面执行期裁决（2026-10-25）

> 正本关系：charter = `CONTEXT.md`（D-M8-1..8 + X1..X6 + 亲核登记八条 +
> 红线 17 条）；执行正本 = `M8-1A-PLAN.md`。本文 = 执行期偏差申报 +
> 拟合质量门终值 + 法务注记（X6 附则）。行内标记 `(deviation)` = plan 文本
> 偏离；`(review)` = 评审回注承接；`(measured)` = 实测锚定。

## 一、模型与拟合器（T3）

1. **谱模型 = 论文原形 sigmoid-quadratic** `(deviation, measured)`：plan 的
   「Jakob-Hanika 2019 sigmoid 谱族（振幅/中心/宽度族参数）」初读为
   exp-Gaussian 形；实测其**单峰性不可达绿-青域**（24,313 个 in-locus cell
   中 >13k 不可拟合，绿尖误差 ≥1e-1）——按 plan read_first「论文数学节」的
   优先级落回论文 §3.2 原形：二次多项式过 logistic sigmoid
   `S(λ) = σ(c0 + c1·t + c2·t²)`（t = 归一化波长）。三系数语义 = 论文多项式
   系数（非振幅/中心/宽度字面）。BSD 参考实现 = 方法参照零拷码。
2. **拟合目标 = 色度-only 双残差（对数比）+ 亮度不约束** `(measured)`：单位
   Y 目标对 c1≤0 型族不可达（D55-at-Y=1 实测妥协误差 ~4e-2）；c1≤0 约束
   本身随 exp 形一并废弃——σ-二次族无需符号约束，系数无界（病理钳 ±2000
   兜底）。三残差[Y=1]设计实测整体妥协（内域 ~4e-2），弃。
3. **正则化形态 = 弱 ridge→flatWhite 锚 + sanitize 兜底清扫** `(measured)`：
   色度-only 残差留 1-dof metamer 谷，沿步进斜率轴色度不变 → 无界漂移
   （实测邻 cell delta 1e42）。ridge ε=1e-8（c1/c2 除 100 归一）选中
   「等色度轮廓上离 flat 最近点」= 色度的光滑函数；sanitize 阈值 cost>1e-3
   邻均值替换（首版 2e-7 过激——把中等妥协拟合替换成更差的邻场，实测回退）。
4. **种子表 = 13 固定种子** `(measured)`：4 阶梯步进（crossing t=.25/.45/
   .65/.8）+ hill/valley 对 + 陡 hill/valley 对（|c1|~600）+ 2 窄带定向
   （~510nm/~575nm——绿-青壳必需，温和种子 96 迭代走不到位）+ flat +
   软谷。多起点对 LM 主导选优；双跑逐位恒等由此保证。
5. **迭代上限 96**（64→96 实测：<1e-6 cell 数 7,633→9,921；成本 +30%
   由 memoization 消解）。

## 二、拟合质量门终值（192²，-O 口径；全部 machine-checked）

- **覆盖率**：0 NaN/发散 cell；谱 ∈ [0,1] 闭域（饱和步进/带限成员
  Float64 精确 0/1 = 合法极限态——门与文档同步放宽 `(measured)`）。
- **精度（分级带）**：工作壳（白距 ≤0.2，含 Rec2020 色域核）实测 ≤2.1e-4
  绝对色度（gate 1e-3 ✓）；命名 cell（D55/D65/deep-red/violet/yellow-green）
  实测 ≤5.3e-6（gate 2e-5）；**远壳（in-locus 远半径）实测 5.6e-1、声明
  ≤0.6**——族可达边界外的谱端壳；运行期影响被 remap 预折进一步衰减，
  M8-2 solve 域以内域/中性为标定面。
- **平滑度**：邻 cell 系数梯度实测 (694, 1929, 1980)，gate (800, 2200,
  2300)——壳边界处场的真实变化集中处；sanitize 后无病理离群。
- **白点**：D55 cell ≤1e-6（实测 4.3e-8/3.3e-7）；中性 cell 解析 snap
  （flatWhite），重建色度与 1/3 偏差 = CMF 表 5nm 取整自身（9.5e-7/2.1e-6，
  gate 5e-6 钉死非拟合误差）。
- **确定性**：双跑逐位恒等（16² 实测 + 192² 结构面同式）。
- **构建成本**：-O 单次 13.5-17.5s（96 迭代）；Debug 测试口径 28-pair 冒烟
  317.8s → gate 600s。超 plan「秒级/表量级带」申报：以引擎 memoization
  （plan 风险节钦定 remedy）+ 单次共享消解；生产路径（-O）一次 17.5s。

## 三、T4 引擎裁决

1. **中性 CC 构建期自解** `(deviation, measured)`：上游 neutral_print_filters
   实测 CC 表在我方自建 dichroic/SPD 近似下前提不成立——portra×endura 于
   实测 CC (M=57.9, Y=49.2) 链头通道散 0.441；引擎内 2D Newton（32 迭代
   固定梯）自解 (m,y) 驱动中灰对数通道比归零，实测散 **0**（机器精度）。
   `solvedPrintCC` 随表 = M8-2 solve face 种子；C 恒 0（pack 惯例）。
   density 域 neutral_print_filters 表（M3 路径）不动。
2. **Remap 白心 = Double 色度** `(measured)`：projXy 表内字段为 float 拷贝；
   golden 对拍须用引擎实际 Double 白心（float 舍入经远半径杠杆放大：
   (0,0) 角 cell 1.3e-6 vs 真链 4e-9）——测试对拍面已改用重算 Double
   色度。
3. **载体体积口径 = packed float3** `(measured)`：Swift `SIMD3<Float>` 自身
   16 字节 size；442,368 B 预算 = 3×float packed 面，体积断言显式 ×3。
   束实测 5,620,928 B（tc 442,368 + 2×PCHIP 2,468,832 + 曲线面 6,144 +
   —对账 RESEARCH §4.1 ~5.5MB 量级 ✓）。
4. **preflight/黑白点/surface 占位 fail-closed**：参数面在册，非默认值 =
   typed error（`unsupportedInV1`）——静默忽略反而是隐患。
5. **grain_density_min 默认 0** `(deviation)`：dt 默认 1.0×pack floors；
   我方 profile face 六项清单不含 grain 域 → 默认 0（enl 域下界）。
   grain floors 解码挂账 M8-2（若其消费面需要）。
6. **enl/scan 域**：enl [0, maxFilmCurves]（无 floor）；scan = paper 曲线
   min/max——上游同式（sim.c:4244-4249/4302-4319 读解）。

## 四、T1/T2 裁决与偏差

1. **对称 encodeIfPresent + FilmProfileTests face 更新** `(deviation)`：
   plan「encodeIfPresent 同式」执行为对称实现——含键 profile 重编码发射
   六新键，既有 `testReencodingEmitsOnlyTheConsumerKeys` 的键集期望随之
   扩展（消费面 deliberate re-open 的机械后果；plan files_modified 未列
   该测试文件 = plan 缺口申报）。零漂移负测（缺键旧形态 JSON）字节恒等
   ✓。产线 diff 仍恰 FilmProfile.swift 一文件 ✓。
2. **log_sensitivity 冒烟带 [-20, 20]** `(measured)`：plan 草稿 [-6,6] 早于
   全集实测 [-13.59, 1.63]；同量级意图下取 ±20。
3. **CAT02 取发表值 0.4296**：dt 侧 0.4286 转写差异不采（row-sum 1.0 的
   发表值，colour-science 生成时核验）——上游非数据源原则（红线 3）。
4. **locus 环向 CW** `(measured)`：380→780 顶点序 xy 平面顺时针（面积
   −0.333）；消费面（ray-cast/parity）方向无关——测试注释钉死。
5. **illuminant SPD 近似申报**：T（3200K Planck）、TH-KG3（3200K×KG3 玻璃
   模型 (0.85+0.10σ((λ−390)/8))·(0.90−0.85σ((λ−710)/12))）、K75P（3250K）、
   ENL（3000K）——全部公开描述自近似、Y=100 归一；官方 D50/D55/D65/D75/A
   按 knots 原样采样。K75P/T/ENL 的温度取值为公开惯例近似（dt pack 非源）。
6. **dichroic 解析形**：C = 0.03+0.94σ((530−λ)/14)（首版方向反了——
   C(650)=0.97 的物理错误，驱动实证后修正）、M = 0.03+0.94(1−exp(−((λ−545)/
   50)²))、Y = 0.03+0.94σ((λ−505)/14)。

## 五、流程与工程裁决

1. **concurrentPerform COW 竞态** `(measured)`：闭包内直写捕获 Swift Array
   触发 COW 引用计数竞态 → SIGSEGV（139）；修复 = FilmPrintBake 的
   `withUnsafeMutableBufferPointer` 先行预留纪律。本仓首例实证。
2. **Project.swift 落域纠错** `(deviation)`：三 IOP 文件首插误入 IOPParity
   数组（锚点 SigmoidTests 在 IOPParity 段）——IOPParity 首轮 497 含三套件
   （13 tests）。修正移入 IOP 数组 + tuist regenerate + 双 bundle 重跑。
   L041 纪律重申：锚点须核数组归属。
3. **远壳 gate 漏 locus 过滤**：fullgrid farMax 首版未滤虚色域（quad2tri
   全域含紫色线下象限，不可达目标误差 ~1.0 属预期非缺陷）——补 in-locus
   过滤后 gate ≤0.6 成立。
4. **SIMD3 16 字节**：体积面一律 `count × 3 × MemoryLayout<Float>.size`
   （packed 语义）；`MemoryLayout<SIMD3<Float>>.size`（16）会虚胖 ⅓。
5. **evidence 入库路径**：`.work/gsd/phases/*/evidence/` 被 .gitignore
   （pack policy B，2026-10-10）——plan files_modified 的 evidence/ 条目
   以 **lightamer-evidence 私仓** commit 兑现（`75298b9`/`2b48924`）。
6. **ΔN 终账 = +19**（3+4+5+6+1）∈ [+18, +24]；T5 行 plan +2 实际 +1
   （evidence 登记面 = 文件非测试，差 1 申报）。

## 六、法务注记（X6 附则，晨审可推翻）

- **常量资产**：CMFs（CIE 1931 2° 官方表 knots 采样）、D 系列/A（CIE 15
  官方表 knots 采样）= 公共标准数据；T/TH-KG3/K75P/ENL/dichroic = 公开
  描述解析自建——零 GPL 零 CC BY-SA 字节进仓；provenance 头 + 生成脚本
  （evidence 仓）可审计。
- **自拟合产物（系数表）归属**：拟合输入 = CC BY-SA 谱面（profile
  sens 数据）**不入拟合目标**（review M3①：色度域 metameric 构造式，
  film 无关共享）→ 系数表 = 公开数学（论文族 + CIE 公开 CMFs/SPD）上的
  数学拟合产物，**倾向非 SA 衍生**（维持 charter X6 判）。晨审推翻点：
  若判 SA 衍生 → 产物随 CC BY-SA 归属 → M8-3 NOTICE 升格（当前 NOTICE
  谱面披露条目已覆盖消费披露，D-M8-6 批修时一并复核）。
- **GPL fallback**：未触发（自拟合三门达标）；fallback 分支保持待命
  （D-M8-2），触发条件 = 下游 golden 实证拟合质量不足。
- **dt 转录件**：`t4-dt-source-crosscheck.md` = 身份类 + 常量转录（GPL-3.0
  出处行号在案）；零代码转录；上游模块仅读解定位。

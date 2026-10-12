# M5-3-01 DECISIONS — 全景数学核心批（wave 1）

> 执行批 2026-10-12（夜间全自动授权在案）。六个任务 T1-T6 六提交
> （3fa930a / 96056d7 / c6f020b / 8ec142e / e591c89 / 收口批）。本文记录
> KD 偏差、钉门字面、探针定案与登记缺陷。规格正本 = M5-3-01-PLAN.md，
> 裁决正本 = M5-3-CONTEXT.md（OQ-1..7 全按推荐）。

## §1 KD 偏差与勘误（执行批申报）

### D-1 置信度公式勘误（KD-2 文本 vs 实现）

Plan KD-2 文本写「置信度 = `1 − inliers/(8 + 0.3·matches)`」——转写笔误。
实现 = OpenCV detail `MatchesInfo.confidence` 原形 **`inliers/(8 + 0.3·matches)`**
（越高越好，上界 10/3 = m→∞ 极限）：`1 − x` 形上界为 1，无法承载 plan 自己
引证的 10/3 上界，且 merge.py:231-233 的 `confidence > .6` **保留门**只有
「越高越好」语义才成立（checker §二亦按无 1− 形验算上界）。真值表测试
（PanoMatchTests.testConfidenceFormulaTruthTable）按 OpenCV 形钉 6 行。

### D-2 DoG 定夺依据（KD-1 planner 裁决的依据落字义务）

裁 DoG（SIFT 同构）非 Harris-Laplace：①Lumen merge.py:217-218 明注
「SIFT 在低对比摄影地形上比 Stitcher 默认 ORB 稳」——同构复刻该语义；
②DoG 尺度空间 + 3×3×3 极值 + 定向梯度描述子是零依赖自实现的最短路径
（Harris-Laplace 需另建尺度选择面，工作量同级而无低对比先例背书）；
③六段链参数全部可从 merge.py:214-224 直值转录（1200px/6000/seed 121/
<10 typed），golden 确定性自握。**剪裁申报**：亚像素精化不做（预览域 +
3px RANSAC 阈下收益边际）；主方向单峰 + 最近邻 bin；描述子空间线性分配
（角度线性劈分保 SIFT 标准形）。

### D-3 N=2 退化注记（KD-5）

BA 参数 7（f + 2×3 rotvec）对单 bundle 射线欠定；LM 阻尼 + 初值锚定兜底，
typed 收敛门（improvementFloor，见 D-5）守底。PanoCameraTests
.testLMBundleN2DegenerateConverges 以 exact 数据 + 扰动初值钉收敛。
G2 覆盖 N=2/N=4 两档（G1 two-view/four-view + G2 四视图）。

### D-4 相机段居中坐标契约（新增，产线语义）

**相机段全部入口吃居中像素坐标（主点在原点）**——M5-3-02 腿按帧中线
居中后喂入。依据：calibrationK = diag(f,f,1) 不含主点；未居中的像素域 H
其 h2 行混入主点项，focalFromHomography 系统性偏高 4-6×（探针亲证：
同一数据居中前 medianFocal 2454 vs 居中后 501.5，真值 500）。这与
OpenCV stitching 的 centered-coordinate 语义一致。PanoCamera 头注已钉。

### D-5 BA 成功判据 = 数据相对（KD-5 收敛门的落地形）

「残差相对下降 < ε」在两个坑上失败，最终判据 = **代价相对初始代价的
实质下降**（improvementFloor 1e-6），三条退出路径（相对下降 < tolerance /
λ 爆炸 / 迭代帽）统一裁决：
①绝对 RMS 门（1e-6 rad）不可达——像素量化地板 ≈ pixel/f（0.5px@f500 =
1e-3），探针亲证全部初值 nil；
②前向差分噪声地板使相对下降判据在解已良时反复 REJECT → λ 爆炸 → nil。
数据相对判据同时保住 T3 的 typed-gate 测试（maxIterations: 0 → 无接受步
→ nil）。

### D-6 BA 残差世界侧（Rᵀ·u，非 R·u）

弦角代价对 R ↔ Rᵀ 族**精确简并**（|R_iᵀa − R_jᵀb|² ≡ |R_i a − R_j b|²，
标量转置可证）。BA 残差必须取**世界方向** d = Rᵀ·u（cam = R·world 的
逆）：R·u 形静默拟合出转置旋转族（anchoredErr ≈ 2θ 指纹，探针亲证：
θ=20/35/50° → err 30/70/100°）。修后 G2 anchoredErr ≤ 0.095°。头注钉
「world side is load-bearing」。

### D-7 旋转初始化 = RANSAC H 正交化（HomographyBasedEstimator 语义）

弦角代价的转置简并 + identity 初始化使 LM 从任何初值落入转置盆地
（数据相对判据下「成功」但旋转错 2θ）。修复 = `initialRotation(from:
focal:)` = orthogonalize(K⁻¹·H·K)（Gram-Schmidt，确定性）作为 BA 旋转
种子——KD-5「focal-from-homography 初值」的经典伴生步，M5-3-02 腿照用。

## §2 G2 钉门字面（KD-9 钉门程序：首轮实测 → 落字 → 断言）

场景 = 盖章渲染致密不规则点阵（1200 点，12 尺寸类 2-13px，700×500@f500，
yaw ±10°/±25°）。首轮实测（init=medianFocal 路径）：

| 量 | 实测 | 硬上限 |
|---|---|---|
| f 相对误差 | **0.27%**（501.33 vs 500） | 5% |
| gauge 锚定 R 角误差（最大，view3） | **0.095°** | 2° |
| inlier 率（几何对应集，6 对全 100%） | **100%** | 60% |
| BA rms（bundle 0,1） | 0.001999（真值旋转 0.002065——解略优于真值 = 量化噪声吸收） | — |

测试断言硬上限（PanoGoldenTests.testG2RecoversFocalAndRotations），
实测带宽于上限 5-20×，无需收窄。

## §3 G2 对应段换轨申报（fixture 域发现，非实现缺陷）

描述子匹配路径在合成点阵 fixture 上产生**错误共识匹配**（同尺寸 blob
歧义：knn 把同尺寸异位点排前，RANSAC 19/19 全内点锁死平移式错模型，
0/19 为真对应——探针逐段亲证）。处置：G2 的对应段改**几何导出**（测试
本地真值 H 的互最近邻 ≤2px + 逆映射互检 ≤2.5px）以隔离门所命名的相机
数学；匹配段质量由 PanoFeatureTests（判别性：真匹配距离 ≈2e-7 ≪ 干扰
0.5×）+ G1（确定性）钉住；产线腿（M5-3-02）跑真实摄影内容（Lumen SIFT
语义的正本场景）+ typed 三态失败面兜底。**非「调 golden 凑带」**：硬上限
未动，场景/对应段属 fixture 设计域，本条即申报记录。Vision pairwise
spike（OQ-1 备选）仍为低纹理回落候补。

## §4 探针定案（swiftc 直编独立复算，M2-7 方法论）

全链数值独立复算 = stub（grayCoefficients + srgbPiecewiseEncode）+
Mat3D/PanoFeature/PanoMatch/PanoCamera 原文 + 场景 main，-Onone 直编。
探针定案清单：①描述子角度回绕需 floor-mod（负 position 经带符号 % 越
界崩溃）；②√u 范数 = √‖u‖₁ ≠ 1 → root 归一后需终 L2；③focal 闭式
（H·K = K·R 列关系两式）对精确 H 机器精度恢复；④渲染器 asin 前必须
单位化 world（否则纬度被位置相关缩放，跨视图几何全破）；⑤居中坐标契约
（D-4）；⑥BA 世界侧（D-6）；⑦旋转初始化（D-7）。探针目录 /tmp（即弃）。

## §5 既有测试面最小必要随批申报（files_modified 外）

`MertensMergeKindTests` 两处 CaseIterable 计数钉（6 → 7）——additive
第七 case 的编译级语义连带，M5-3-01 additive 的必然结果；mirror 循环
测试结构不变。除此 + front-matter 文件外零越界（git diff c38eef3..HEAD
stat 亲核：其余全为 front-matter 文件与本批前已存在的 docs 提交）。

## §6 G2 其余两门的字面

- 连通性负测：95° 反向视图经 knn+ratio+RANSAC+边门后不与参考族成边，
  BFS 闭包 3 ≠ 4 → `panorama images disconnected: ` 前缀 ✓。
- 低纹理负测：纯平图 0 特征 < 10 → `panorama alignment failed: ` 前缀 ✓。

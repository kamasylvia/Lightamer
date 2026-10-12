# M5-3-01 SUMMARY — 全景数学核心批（wave 1）

> 执行批 2026-10-12（夜间全自动授权在案；续班开跑——前任 API 瞬态零产物，
> 按原 plan 全新执行）。六任务六提交，收口本批。规格 = M5-3-01-PLAN.md；
> 偏差/钉门/探针定案正本 = M5-3-01-DECISIONS.md（§1-§6）。

## 任务序与提交

| 任务 | 产物 | commit | 测试（定向轮） |
|---|---|---|---|
| T1 | PanoFeature.swift（预览灰度双缝/金字塔/DoG/主方向/描述子/帽）+ PanoFeatureTests | `3fa930a` | 9/0/0 |
| T2 | PanoMatch.swift（PanoRNG 121/knn/Lowe/DLT/RANSAC/置信度/BFS/typed 词汇）+ PanoMatchTests | `96056d7` | 9/0/0 |
| T3 | PanoCamera.swift（f 闭式/中位数锚/LM BA 3N+1/wave correct）+ PanoCameraTests | `c6f020b` | 7/0/0 |
| T4 | MergeKind.pano additive 四臂 + runPanoLeg typed stub + 32 门 + MergeParams 三字段 + Provenance 镜像双常量 + 两测试文件 | `8ec142e` | IOP 8/0/0 + LIB 5/0/0 |
| T5 | PanoGoldenTests（G1 双跑逐位 + G2 合成恢复靶）+ PanoCamera 探针修复（残差世界侧/数据相对判据/initialRotation/居中契约） | `e591c89` | 5/0/0 |
| T6 | 定向三 bundle 全轮 + 红线自证 + 收口文档（本批） | 收口提交 | 见下 |

T1-T4 期间另有 ②④checker 注记落地：②`preparePreviewGray` 拆双缝
（rgbaLinear/rgbaEncoded，encoded 缝跳过再编码——负测钉死双重编码发散）；
④预览降采样尺寸表 6 行（非 8）；grep 门含 `\.random\(`（T6 实跑 0 命中）。

## 收口轮数字（定向三 bundle，2026-10-12）

| bundle | 本轮 | 基线增量 | MEMFAIL |
|---|---|---|---|
| IOP | **642/1/0**（160s） | 609 → +33（Feature 9/Match 9/Camera 7/MergeKind 8） | 0 |
| IOPParity | **456/3/0**（788s） | 451 → +5（Golden） | 0 |
| Library | **636/4/0**（78s） | 631 → +5（Provenance） | 0 |

- **对账**：3539（M5-2 修复后基线）+ 43 新测试 = **3582**；定向七 bundle
  拼表口径 pass 3582 / skip 22（1+3+4+4+4+2+4 = 22 = 既有 22，零新增
  skip）/ **fail 0**。估数 +42..52 ✓（实际 +43）。
- 新测试全小 fixture（≤700×500 预览域合成面），IOP 峰值 326MB 级、零
  MEMFAIL——贴线 bundle（IOP/IOPParity）无增量风险亲证。

## 零 diff 红线自证（T6 收口轮实测）

```
git diff c38eef3..HEAD -- LightamerIOP/ Sidecar/ Pipe/ Graph/   → 0 命中
git diff c38eef3..HEAD -- '*.metal'                             → 0 命中
git diff c38eef3..HEAD -- ExifPrecheck.swift                    → 0 命中
Project.swift dependencies 块                                    → 0 diff（5 行 diff 全为测试登记）
grep -rnE "SystemRandomNumberGenerator|srand|arc4random|\.random\(" Pano*.swift → 0 命中
```

既有六 kind 零回归：快照负测（rawValue/tag/stepTotal 全表）+
`MertensMergeKindTests` 计数钉 6→7 更新（additive 连带，DECISIONS §5 申报）
+ hdrMerge 33 张 enqueue 既有行为原样（32 门 kind 条件式反测）。

## 数学核心证据（DECISIONS §2/§4 详）

- **DoG 检出**：合成点阵 36 中心 ≥24 命中（4px 半径）；octave 层数表
  6 行；降采样尺寸表 6 行；制备双跑逐位。
- **DLT**：已知 H（42→35 点精确）逐元素 ≤1e-9 恢复。
- **RANSAC**：±1px 噪声 35 真内点 ≥33 存活 + 投影域恢复带 ≤2.5px + 双跑
  逐位（H bitPattern/inliers/iterations 三重）。
- **f 初值**：已知 f=800 的 H 分解 ≤1e-9；中位数锚抗单对离群（9999 对不
  动 620）；居中契约下实测链级 medianFocal 501.5（真值 500）。
- **LM BA**：四已知相机恢复 f 1e-4 + gauge 不变 pairwise 角 0.05°；
  N=2 退化收敛；typed 门（空/零迭代 → nil）。
- **G1 bit-identity**：两视图/四视图全链双跑——keypoints/descriptors/
  homographies/solution/corrected 全 bitPattern 逐位相等。
- **G2 恢复**（硬上限内，DECISIONS §2 钉门字面）：f 误差 0.27%（≤5%）、
  gauge 锚定 R 误差 ≤0.095°（≤2°）、inlier 率 100%（≥60%）。

## 批内发现与申报（DECISIONS §1-§5 详）

1. **置信度公式勘误**：plan 文本 `1 − inliers/(8+0.3m)` 为转写笔误，实现
   按 OpenCV detail 原形 `inliers/(8+0.3·matches)`（10/3 上界 + `>.6` 保留
   门语义唯一自洽）。
2. **居中坐标契约**（D-4）：相机段吃居中像素坐标——未居中 f 偏 4-6×
   （探针亲证）。M5-3-02 腿按帧中线居中喂入。
3. **BA 残差世界侧**（D-6）：`Rᵀ·u` 非 `R·u`——弦角代价对转置族精确简
   并，R·u 静默拟合转置旋转（2θ 指纹）。
4. **BA 成功判据数据相对**（D-5）：绝对 RMS 门不可达（量化地板 pixel/f）
   + FD 噪声地板 → improvementFloor 判据。
5. **initialRotation**（D-7）：K⁻¹HK 正交化种子——identity 初始化落入转
   置盆地。
6. **G2 对应段换轨**（§3）：描述子匹配在合成点阵上产生错误共识（0/19
   真），G2 对应段几何导出隔离相机数学；匹配质量由 T1+G1 钉；Vision
   spike 仍为低纹理候补。
7. **渲染器 asin 单位化**（测试侧）：未单位化 world 的 asin 使纬度位置相
   关缩放、跨视图几何全破——golden 首轮即抓出。

## bundle 分账（BUNDLE-MAP 增行已随各自任务 commit）

PanoFeatureTests/PanoMatchTests/PanoCameraTests/PanoMergeKindTests → IOP；
PanoProvenanceTests → LIB；PanoGoldenTests → IOPP（*Golden* 域模式）。

## 验收与续接

- **双重验收待派**（config `dual_acceptance = true`，m1）：本批执行完成，
  待 orchestrator 派 zcode 独立验收（PASS 后串行 omp 二验，严禁并发），
  结论落 `M5-3-01-ACCEPTANCE.md`（本批未创建——验收波产物）。
- **C 档第 2 停**：执行+验收闭环后停——汇报本 plan 战果 + M5-3-02 摘要，
  等用户确认再启。
- M5-3-02（生产腿）待启：runPanoLeg 换腿体（bounded_rois/spherical_map/
  增益/tile 融合/inner_crop/BandStreamer 32f sRGB 落盘）+ G3 分段 golden
  + 预算探针（L077 runbook 四步照办）+ dgelsd 最小范数优先（checker O2）。

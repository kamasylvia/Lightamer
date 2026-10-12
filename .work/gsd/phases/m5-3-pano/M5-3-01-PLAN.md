---
phase: m5-3
plan: "M5-3-01"
title: "全景数学核心批（wave 1 = RESEARCH §6 plan-01）——PanoFeature（DoG 多尺度关键点 + 定向梯度描述子 + 预览灰度制备）+ PanoMatch（种子化 LCG + BF knn 比值检验 + RANSAC 4-point DLT 单应 + 连通性 BFS 门 + typed 三态词汇）+ PanoCamera（focal-from-homography 初值 + LM BA 3N+1 + 横向 wave correct）+ MergeKind.pano additive（provenanceKind/defaultTag/stepTotal 3N+6/dispatch typed stub）+ MergeParams additive 三记录字段 + ProvenanceReplay 词汇镜像 + G1 bit-identity + G2 合成恢复靶"
wave: 1
depends_on: []
autonomous: true
requirements: ["IOP-PANO-01"]
estimated_tests: "+42..52"
test_bundles: [IOP, IOPParity, Library]
files_modified:
  - LightamerCore/Sources/Stack/PanoFeature.swift     # 新建：预览灰度制备（sRGB→Rec709 luma→≤1200px box 降采样）/高斯金字塔/DoG 极值（对比度阈+边缘比阈）/主方向/128 维定向梯度描述子/root 归一/6000 特征帽截断；文件头 MIT 归属注记（Lumen 特征段参数转录）
  - LightamerCore/Sources/Stack/PanoMatch.swift       # 新建：PanoRNG 64-bit LCG（种子常量 121）+ BF knn（vDSP 矩阵乘 + top-2 tie-break 索引序）+ Lowe 比值 0.3 + 4-point DLT 归一单应 + RANSAC 自适应迭代（唯一 RNG 流）+ 置信度公式 + 边门（conf>0.6 且 inliers≥10）+ BFS 连通性门 + typed 三态词汇常量
  - LightamerCore/Sources/Stack/PanoCamera.swift      # 新建：focal-from-homography 初值 + LM BA（3N+1 参数，Double 内部，Accelerate dgesv）+ 收敛门 typed + 横向 wave correct（Jacobi 特征向量 + 符号定向）+ 相机 K() 构造面
  - LightamerCore/Sources/Stack/StackMergeService.swift # 修改：MergeKind + case pano = "pano-merge"（provenanceKind/defaultTag("pano")/stepTotal 3N+6/runProductionMerge 四 switch 补臂）+ runPanoLeg typed stub（KD-6）+ MergeParams additive 三 optional（panoCanvas/panoGains/panoCrop）+ enqueue kind 条件式 32 上限门（.pano 专用，既有 kind 路径逐字节不动）
  - LightamerCore/Sources/Stack/ProvenanceReplay.swift # 修改：SidecarProvenance.Kind + case panoMerge（raw 值恒等镜像）+ panoAlgorithmName/panoImplementationVersion 常量
  - Tests/LightamerTests/PanoFeatureTests.swift       # 新建（IOP/Core 级）：金字塔/DoG 检出/主方向等变性/描述子判别性/帽截断/预览降采样
  - Tests/LightamerTests/PanoMatchTests.swift         # 新建（IOP/Core 级）：knn/比值门/DLT 恢复/RANSAC 噪声/置信度表/边门正反/BFS typed/双跑逐位
  - Tests/LightamerTests/PanoCameraTests.swift        # 新建（IOP/Core 级）：f 初值/LM 恢复/N=2 退化/wave correct 幂等+摆正/typed/双跑逐位
  - Tests/LightamerTests/PanoMergeKindTests.swift     # 新建（IOP/Core 级）：kind 词汇/tag/stepTotal/进度恒式/stub typed 形/32 门正反/六既有 kind 快照负测
  - Tests/LightamerTests/PanoProvenanceTests.swift    # 新建（LIB/Core 级，MertensProvenanceTests 同位）：Kind 镜像/旧 MergeParams JSON 逐字节零漂移/encodeIfPresent 往返/算法名常量
  - Tests/LightamerTests/PanoGoldenTests.swift        # 新建（IOPP 级，*Golden* 域模式）：G1 双跑 bit-identity（两/四视图）+ G2 合成恢复靶（测试本地闭式投影器，R/f 恢复带 + 连通性正反 + 低纹理负测）
  - Project.swift                                     # 修改：新测试文件登记对应 target 数组（显式清单无 glob）+ tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：六新测试文件增行登记（E2 纪律，随各自任务 commit）
  - .work/gsd/phases/m5-3-pano/M5-3-01-SUMMARY.md     # 新建（T6）
  - .work/gsd/phases/m5-3-pano/M5-3-01-DECISIONS.md   # 新建（T6）
  - .work/gsd/phases/m5-3-pano/M5-3-01-ACCEPTANCE.md  # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/GOAL-STATE.md                               # 修改：续接点
  - .work/TODO.md                                     # 修改：M5-3 条目
  - .work/LESSONS.md                                  # 如踩坑
---

# Plan M5-3-01 — 全景数学核心批（wave 1：特征 → 匹配 → 相机 → 类型 additive → golden 两门）

> **性质**：M5-3 三 plan 之首。本批交付全景合成（IOP-PANO-01）的**全部对齐数学面
> 与类型 additive 面**（Core `Stack/` 域纯函数族），但**不切生产入口**——`.pano`
> 的 dispatch 臂落 typed stub（M5-2-01/M4-1-01「路由不切」先例：生产腿 =
> M5-3-02，UI 与收口 = M5-3-03）。本批唯一编译必需的既有面改动 = `MergeKind`
> 穷举 switch 四处补臂（provenanceKind/defaultTag/stepTotal/runProductionMerge），
> 全部 additive、既有六 kind 行为零变化（G5 钉死）。规格正本 =
> `RESEARCH-NOTES.md`（merge.py file:line 亲读）；裁决正本 = `M5-3-CONTEXT.md`
> 裁决记录（OQ-1..7 全按推荐，2026-10-16 用户回批）。
>
> **基线**：**3539/22/0**（M5-2 VALIDATION 2026-10-15 终验拼表 `TOTAL 3538/22/0`
> + E-1 修复回归法 = 修复后基线 3539，对账链 3477+39+22+1 亲证值；GOAL-STATE
> 续接点同值）。IOP 贴线纪律：本批全部新测试小 fixture（≤1200² 预览域合成面），
> 零大图单测——大图预算面全部推 M5-3-02 探针。

## 已定裁决（生效值，硬约束，不得重开）

M5-3 OQ-1..7 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-16 用户回批）。本 plan
承载其中数学/类型面；生产腿/画布/预算 = M5-3-02；UI/分账/收口 = M5-3-03：

1. **OQ-1 = A**：特征/对齐**全自实现**（多尺度关键点 + 定向描述子 + knn 比值
   + RANSAC 单应，纯函数 + 种子化 RNG，确定性/G1 bit-identity 完全自握）；
   Vision `VNHomographicImageRegistrationRequest` 只作低纹理 spike 候选，
   **不作产线**；零新 SPM（OpenCV 零入仓）；Lumen MIT 语义/参数移植带归属注记；
   OpenCV detail API 语义只读（BSD，代码零复制）。
2. **OQ-2 = A（数学面）**：相机模型 = **单焦 f + N×R**（3N+1 参数）LM BA +
   横向 wave correct；per-image 独立焦距/畸变/tilt 不做（V2 另议）。
3. **OQ-3 = A**：全链 sRGB 编码 float32 [0,1]（Mertens 腿同域）——本 plan 的
   特征/匹配灰度面即此域的 Rec709 luma 派生（`DrtEotfMath.srgbPiecewise`
   接缝现成，Mertens 先例）。
4. **OQ-4 = A**：张数门 **2..32**（本 plan 常量与门面）；200MP 画布帽 + ×0.998
   收缩循环 = M5-3-02 投影面承载（本 plan 只钉 typed 词汇）。
5. **OQ-5 = A**：恒 inner_crop（v1 无开关）+ alpha 不写——落地面 = M5-3-02。
6. **OQ-6 = A**：v1 全 CPU（Accelerate/vDSP）——本 plan 数值面零 Metal、
   **零新 `.metal`**；越门 GPU 化另立项。
7. **OQ-7 = A（类型面）**：`MergeKind.pano` additive + dispatch typed stub +
   provenance 词汇镜像；预览画布/参考帧手选/use_edits 挂 V2（本 plan 零 UI）。

**架构红线（本 plan 全程 + checker 机检面）**：
- **零新 SPM**：`Project.swift` dependencies 块零 diff；零 OpenCV/第三方特征
  库符号。
- **零新 `.metal`**：收口任务 `git diff <基线>..HEAD` 无 `*.metal` 命中并截屏
  入 SUMMARY。
- `LightamerIOP/` **零 diff**；`LightamerCore/Sources/Sidecar/`、`Pipe/`、
  `Graph/` 零 diff；sidecar schemaVersion 不动（MergeParams additive 走
  synthesized encodeIfPresent，旧档逐字节零漂移专测钉死）。
- **既有六 kind 行为零变化**：hdrMerge/focusStack/stackAverage/stackMedian/
  stackSigma/hdrMertens 的 enqueue/stepTotal/tag/provenance/腿体逐字节不动
  （新 case 纯 additive；enqueue 的 2..32 上限门 = kind 条件式，.pano 专用）。
- 既有路由零切换：`enqueue` 无新调用方（App 面 = M5-3-03）；stub 臂 typed
  失败形态（KD-6）。
- `ExifPrecheck.swift` **零 diff**——pano 不消费 EXIF EV/bracket 语义（异视点
  输入无 bracket 前提；Lumen merge_images 对 pano 亦无 EXIF 门，仅张数/形状门）。
- darktable GPL 零复制。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 检测器 = DoG 多尺度（research「DoG 或 Harris-Laplace 二选一 spike 定」的 planner 定夺）

- **裁 DoG（SIFT 同构）**：Lumen 正是 SIFT（`nfeatures=6000`，merge.py:219-222；
  「SIFT 在低对比摄影地形上比 Stitcher 默认 ORB 稳」注释在案 merge.py:217-218）。
  DoG + 梯度描述子 = 该语义的零依赖自实现同构；Harris-Laplace 需另建尺度选择
  面，工作量同级而低对比稳定性无先例背书。依据入 DECISIONS。
- 尺度空间：高斯金字塔 octave 数随预览尺寸自适应（≤1200px → 4-6 octave）、每
  octave 3 层差分；DoG 3×3×3 邻域极值 + 对比度阈 + 边缘比阈（低主曲率剔除）；
  **亚像素精化不做**（预览域 + 3px RANSAC 阈下收益边际——剪裁入 DECISIONS）；
  特征帽 6000（Lumen 同值，响应排序截断）；**<10 特征 = typed 对齐失败**
  （merge.py:223-224 语义：「部分照片缺少可识别细节」）。
- 输入域：预览灰度 = 全分辨率平面（M5-3-02 腿 render 后传入）→ sRGB 编码
  （`DrtEotfMath.srgbPiecewise`）→ Rec709 luma（`MertensFusion.grayCoefficients`
  同系数）→ 长边 ≤1200px box-filter 降采样（INTER_AREA 语义的确定性整数盒
  滤波）。制备函数本 plan 交付，生产消费 = M5-3-02 腿。

### KD-2 描述子与匹配（merge.py:225-233 语义转录；BSD API 语义只读）

- 描述子 = 4×4×8 = **128 维定向梯度统计**（主方向 = 梯度直方图峰、窗口 1.5σ；
  **root 归一** = L2 后逐分量开方——rootSIFT 惯例，欧氏距离等价卡方核）。
- 匹配 = BF knn k=2 + **Lowe 比值 0.3**（Lumen
  `BestOf2NearestMatcher_create(False, .3, ...)` 语义锚 merge.py:227-229）；
  实现 = 描述子矩阵 vDSP 矩阵乘 + top-2 选择（**tie-break = 索引序**，确定性）。
  预算：6000²×128 ≈ 4.6 GFLOP/pair，vDSP 亚秒；pairwise O(N²) × N≤32 在预览域
  可接受（RESEARCH §3.2 预算锚）。
- 边门（merge.py:232-234 语义）：置信度 = `1 − inliers/(8 + 0.3·matches)`
  （OpenCV detail 公式，上界 10/3——merge.py:225-227 注释亲读）**> 0.6 且
  inliers ≥ 10** 为有效边。

### KD-3 种子化 RNG（G1 前提；红线机检面）

- `PanoRNG`（PanoMatch.swift 内嵌 struct）= 64-bit LCG（`state = state &*
  6364136223846793005 &+ 1442695040888963407`，MMIX 常数——测试侧
  HDRMergeMathTests LCG 同族先例）；**种子常量 121**（Lumen
  `cv2.setRNGSeed(121)` merge.py:220 锚；语义 = RANSAC 随机过程确定性锚定，
  非统计质量声明）。
- RANSAC 采样与自适应迭代全程走唯一 RNG 流；**禁系统随机源**：收口 grep 门
  `SystemRandomNumberGenerator|srand|arc4random` 于 `LightamerCore/Sources/
  Stack/Pano*.swift` 零命中（截屏入 SUMMARY）。

### KD-4 RANSAC 单应 + 连通性门 + typed 三态词汇

- 4-point DLT 单应（Hartley 对称归一形）+ 内点阈 **3px**（预览域；Lumen
  stack_transforms `ransacReprojThreshold=3` 先例）+ 自适应迭代（目标置信
  0.999 停，硬帽 **3000**——Lumen maxIters=3000 先例）；最优模型 = 内点数
  最大，tie-break = 最早达到（RNG 序决定，确定性）。
- 连通性 = 从参考帧 BFS 闭包（merge.py:236-238 原语义）；
  `connected.count != images.count` → typed 失败。
- **typed 失败三态词汇**（P3 zh 映射的消费契约，canonical 前缀钉死，载体 =
  `AppError.invalidParameter`——typed 重试可失败态，Mertens stub 同形）：
  - `"panorama alignment failed: ..."`（特征不足/无有效匹配/RANSAC 失败/BA 不收敛）
  - `"panorama images disconnected: ..."`（连通性门）
  - `"panorama canvas invalid: ..."`（M5-3-02 投影/crop 面；词汇本 plan 先钉）

### KD-5 相机模型与 BA（merge.py:239-247 语义；M5-1 零依赖数值先例）

- f 初值 = **focal-from-homography** 经典式（两视图 H = K₂R K₁⁻¹ 分解出 f²
  闭式解；多对取中位数——merge.py:251 中位数锚同精神）。
- BA = **LM（λ 阻尼自适应）**，参数 3N+1 = f(1) + 每图旋转向量(3N)；残差 =
  匹配点射线角重投影；**内部 Double**（数值稳定性；交界处 f32 化，L048
  惯例）；Jacobian 稠密前向差分；线性解 = Accelerate `dgesv`；收敛门 = 残差
  相对下降 < ε 或迭代帽（不收敛 → typed "alignment failed" 族）。
- wave correct = 横向：Σ(Rᵢ 首行)(Rᵢ 首行)ᵀ 3×3 对称阵**最小特征向量** →
  全局旋转修正；Jacobi 旋转法求特征向量（确定性闭迭代）；**符号定向** = 修正
  后 Σ 首行 x 分量 ≥ 0（标准式，DECISIONS 记录）；幂等纯函数（二次调用零变化）。
- N=2 退化：BA 参数 7 的欠定面由 LM 阻尼 + 初值锚定兜住（typed 收敛门守底）
  ——DECISIONS 记录；G2 覆盖 N=2/N=4 两档。

### KD-6 MergeKind.pano additive + stepTotal 3N+6 推导 + stub

- `case pano = "pano-merge"`（Codable raw additive；CaseIterable +1——编译期
  破四处穷举 switch，逐处补臂：`provenanceKind` 镜像同名 case / `defaultTag`
  → `"pano"`（产物 `<base>_pano.tif`，与 `_hdr`/`_mertens` 分账）/ `stepTotal`
  → `sources*3 + 6` / `runProductionMerge` → `runPanoLeg(work)`）。
- **stepTotal 3N+6 推导**（Mertens 4N+3 同款诚实声明）：decode N（`execute`
  循环逐源 bump）+ 特征 N（逐源特征步）+ 融合 N（tile-paced 补足，M5-3-02
  腿消费）+ 6 = 匹配+BA+波校正 1 + 画布/ROI 1 + 增益 1 + write 1 + sidecar 1
  + settle 1。`done == total` 恒式测试钉死（合成 decode 腿 + stub 路径到
  typed 失败点前的恒式语义按 M5-2-01 同形钉）。
- **`runPanoLeg` 本 plan = typed stub**：
  `throw AppError.invalidParameter("pano-merge production leg lands in M5-3-02")`
  ——M5-2-01 KD-4 同形（dispatch 结构两 plan 间零二次编辑，02 只换腿体）。
- **enqueue 上限门**：kind 条件式——`.pano` 且 `sources.count > 32` →
  `AppError.invalidParameter`（OQ-4 张数门 2..32；下限 2 = 既有 guard 原样；
  既有六 kind 路径逐字节不动，纯 additive if 分支）。

### KD-7 MergeParams additive 三记录字段（resolved 快照面）

- `panoCanvas: [Int]?`（解析画布 [w,h]）/ `panoGains: [Double]?`（解析增益，
  参考帧首）/ `panoCrop: [Int]?`（裁切矩形 [x0,y0,x1,y1]）——全 additive
  optional，init 尾参缺省 nil，既有调用点零改动；**消费与回写 = M5-3-02 腿**
  （08-3 `pyramidLevels` / Mertens `mertensLevels` resolved 回写先例——
  provenance states what ran）；v1 零输入 override（画布/增益/裁切全自动）。
  旧 MergeParams Codable JSON **逐字节零漂移**专测（golden JSON 字面）。

### KD-8 provenance 词汇镜像与算法身份

- `SidecarProvenance.Kind` + `case panoMerge = "pano-merge"`（两枚举 raw 值
  逐一对齐的既有纪律）；`ProvenanceReplay.panoAlgorithmName =
  "spherical-feature-panorama"`、`panoImplementationVersion = "1"`（独立身份
  ——数学演进互不牵连，mertens 双常量先例同形）。消费 = M5-3-02。

### KD-9 golden 门定义（G1/G2；G3 = M5-3-02、G4/G6 = M5-3-03）

- **G1 bit-identity**：合成两视图 + 四视图景各一法，特征→匹配→RANSAC→f 初值
  →BA→wave correct 全链双跑**逐位相等**（全 CPU 顺序归约 + 唯一 RNG 流——
  KD-3 确定性前提的直接证明）。
- **G2 合成恢复靶**：已知真值 K/R 渲染合成视图（**测试本地闭式球面投影器**
  ——刻意不 import 产线 pano 文件，防 golden 循环；合成源 = 高纹理网格+角标
  +梯度块；受控单图变体，Lumen `merge_diagnostics.py` 先例语义）→ 链恢复
  R/f 对照真值。**钉门程序**（M5-2-01 G2 同款）：首轮实测记录带 → DECISIONS
  落字面 → 测试钉实测带；**硬上限** = f 相对误差 ≤5%、R 角误差 ≤2°、
  inlier 率 ≥60%（预览域合成理想景的保守带；超上限 = 实现缺陷先查归一化/
  求和序，禁调 golden 凑带）。连通性正反测：中间图剔除 → typed disconnected；
  纯平图 → typed alignment failed（<10 特征）。

## read_first

1. `.work/gsd/phases/m5-3-pano/M5-3-CONTEXT.md`（裁决记录 = 七生效值正本）+
   `RESEARCH-NOTES.md`（merge.py file:line 读解/落地面设计全锚）
2. `/Volumes/UNITEK/Documents/Development/lumen-raw/lumen/merge.py` :192-315
   （MIT 正本：特征/匹配/建图/相机/波校正逐段对照移植；MIT 归属注记义务）
3. `LightamerCore/Sources/Stack/StackMergeService.swift` 全文（MergeKind/
   MergeParams/stepTotal/defaultTag/runProductionMerge dispatch——additive 落点）
4. `LightamerCore/Sources/Stack/ProvenanceReplay.swift`（Kind 词汇/Algorithm
   身份/mertens 双常量先例）
5. `LightamerCore/Sources/Stack/MertensFusion.swift` 头注（MIT 归属注记体例 +
   sRGB 域约定）+ `MTBAlign.swift`（对齐面先例对照——pano 不复用 MTB，异视点
   单应域）
6. `LightamerCore/Sources/Pipe/Drt/DrtEotf.swift` :160-260
   （srgbPiecewiseEncode——预览灰度制备的编码接缝）
7. `Tests/LightamerTests/HDRMergeMathTests.swift`（LCG 形 + Stack 域测试基建）
   + `Tests/LightamerTests/MTBAlignTests.swift`（合成面/typed 断言先例）
8. `Project.swift` :1-30/:123-145（模块依赖图亲核——IOP → Core 方向）
9. `.work/gsd/phases/m5-2-mertens/M5-2-01-PLAN.md`（本 plan 体例正本——
   stub/additive/golden 钉门程序全先例）
10. `.work/gsd/phases/m5-2-mertens/M5-2-VALIDATION.md`（基线 3539/22/0 亲证值
    + 对账链）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；
  front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记进
  BUNDLE-MAP（E2）+ `Project.swift` 对应数组（L041：`tuist generate` 恒为该批
  最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 =
  `Scripts/test-direct.sh --bundle <域>`（直启宿主；全套 `--all` 需 orchestrator
  批准，本 plan 不申请）。
- **L072 跨 bundle 污染**：合成 fixture 与临时产物一律 temp 域
  （`FileManager.default.temporaryDirectory` 子目录 + `defer` 清理）。
- **L048 比较空间纪律**：golden 比较 decode 回线性/f32 产线常数
  `Double(Float(x))` 升维；BA 段 Double 内部、交界 f32 化。
- **零 diff 红线自证**（T6 收口）：`git diff <M5-2 终点 SHA>..HEAD --
  LightamerIOP/ LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Pipe/
  LightamerCore/Sources/Graph/ '*.metal'` 零命中 + `Project.swift`
  dependencies 块零 diff + 系统随机源 grep 门（KD-3），截屏入 SUMMARY。
- **fixture 域纪律**：测试输入 = 代码内合成平面（零盘上资产、零新 fixture 目录）。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 PanoFeature 纯函数族（KD-1）

- read_first 2/6 → 新建 `LightamerCore/Sources/Stack/PanoFeature.swift`：文件头
  MIT 归属注记（Lumen 特征段参数转录：1200px 预览/6000 帽/低对比地形锚）+
  算法注记（DoG 多尺度 + 128 维定向梯度描述子，SIFT 语义零依赖自实现；
  OpenCV 零入仓）→ 预览灰度制备（sRGB 编码→Rec709 luma→≤1200 box 降采样）/
  高斯金字塔/DoG 极值（对比度阈+边缘比阈）/主方向/描述子/root 归一/特征帽截断。
- 验收：`PanoFeatureTests`（IOP）——金字塔层数表/DoG 合成点阵检出（已知角点
  命中）/主方向旋转等变性（块旋转 ±45° 方向跟随）/描述子判别性（同点跨视图
  距离 < 异点距离）/root 归一单位范数/特征帽截断/预览降采样尺寸表
  （1201→ ≤1200 比例表）/制备双跑逐位。

### T2 PanoMatch 纯函数族（KD-2/KD-3/KD-4）

- read_first 2 → 新建 `LightamerCore/Sources/Stack/PanoMatch.swift`：PanoRNG
  LCG + 种子常量/BF knn（vDSP 矩阵乘 + top-2 tie-break 索引序）/Lowe 比值门/
  4-point DLT（归一形）/RANSAC 自适应迭代（唯一 RNG 流 + 硬帽 3000）/置信度
  公式/边门/BFS 连通性门/typed 三态词汇常量（KD-4）。
- 验收：`PanoMatchTests`（IOP）——knn top-2 小阵直查/比值门边界（0.3 上下
  各一）/DLT 已知 H 恢复（合成点对零噪 → 带 ≤1e-9；真值 H 任意给定）/
  RANSAC 噪声内点率恢复/置信度公式真值表/边门正反（conf ≤0.6 或 inliers <10
  → 无边）/BFS 不连通 typed 前缀断言/RNG 流双跑逐位。

### T3 PanoCamera 纯函数族（KD-5）

- read_first 2 → 新建 `LightamerCore/Sources/Stack/PanoCamera.swift`：
  focal-from-homography 初值/LM BA（3N+1，Double 内部，dgesv 线性解）/收敛门
  + typed/横向 wave correct（Jacobi 特征向量 + 符号定向）/相机 K() 构造面。
- 验收：`PanoCameraTests`（IOP）——f 初值已知 H 分解带/LM 合成恢复（已知
  f+R 生成匹配 → 恢复带，实测收窄钉）/N=2 退化收敛/wave correct 幂等
  （二次调用逐位零变化）+ 已知倾斜阵摆正/f 中位数锚/typed 不收敛前缀/双跑逐位。

### T4 MergeKind/MergeParams/Provenance additive + typed stub（KD-6/KD-7/KD-8）

- read_first 3/4 → `StackMergeService.swift`：`case pano` + 四 switch 补臂 +
  `runPanoLeg` typed stub + `MergeParams` 三 optional（init 尾参缺省 nil——
  既有调用点零改动）+ enqueue kind 条件式 32 上限门 →
  `ProvenanceReplay.swift`：Kind 镜像 case + 双常量。
- 验收：`PanoMergeKindTests`（IOP）——rawValue `"pano-merge"`/provenanceKind
  镜像/`defaultTag(.pano) == "pano"`/`stepTotal(.pano) == 3N+6`（N=3 直查）/
  stub typed 失败形态（enqueue `.pano` → `.failed(.invalidParameter)` 断言）/
  **六既有 kind 快照原值不变负测**（stepTotal/tag/rawValue 全表）/32 上限门
  正反（`.pano` 33 张 → enqueue typed；`.hdrMerge` 33 张 → 既有行为原样）。
  `PanoProvenanceTests`（LIB）——Kind 两枚举 raw 值全对齐镜像断言 + **旧
  MergeParams（无新字段）Codable JSON 逐字节零漂移**（golden JSON 字面）+
  新字段 encodeIfPresent 往返 + 算法名/版本常量。

### T5 golden 批 G1/G2（KD-9）

- read_first 7 → `PanoGoldenTests`（IOPP，*Golden* 域模式）：G1 双跑
  bit-identity（两视图/四视图各一法）/ G2 合成恢复靶（**测试本地闭式投影器**
  渲染 N 视图 → 链恢复 R/f 带钉 + 连通性正反 + 低纹理 typed 负测）。钉门程序
  = 首轮实测 → DECISIONS 落字面 → 断言实测带（硬上限 KD-9 三条）。
- 验收：全绿；实测带与 DoG 定夺依据入 DECISIONS；失败先查归一化/求和序，
  禁调 golden 凑带。

### T6 G5 共存零回归 + 收口

- 收口轮：`--bundle IOP` + `--bundle IOPParity` + `--bundle Library` 定向轮
  全绿（exit 0 + 零 MEMFAIL——新测试全小 fixture，理论零增量；MEMFAIL 先查
  重测顺序漂移按 AGENTS 口径）+ 零 diff 红线自证清单（纪律节五路 grep 截屏，
  含系统随机源门）+ SUMMARY（任务序/实测带/bundle 分账/恒式证据）+ DECISIONS
  （KD 偏差/G2 钉门字面/DoG 定夺依据/N=2 退化注记/亚像素剪裁）+ GOAL-STATE
  续接点（M5-3-02 待启）+ TODO 同批。
- **双重验收（config `dual_acceptance = true`，m1）**：zcode subagent 独立
  验收 PASS 后 → **串行** omp 二次验收（**严禁并发**——单实例硬约束）；两路
  结论（PASS/FAIL + 证据）落 `M5-3-01-ACCEPTANCE.md`；FAIL 回注修复批后重走
  验收。
- **C 档第 2 停**：执行+验收闭环后停——汇报本 plan 战果 + M5-3-02 摘要，
  等用户确认再启。

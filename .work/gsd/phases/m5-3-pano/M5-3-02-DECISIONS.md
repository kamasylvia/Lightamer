# M5-3-02 DECISIONS — 全景生产腿批（wave 2）偏差与定案正本

> 执行批 2026-10-13（夜间全自动授权「开跑，不要停」在案）。规格 =
> M5-3-02-PLAN.md + checker 回注 5 minor 同批采纳；本文件 = 执行期
> 偏差/定夺/探针定案正本（§1-§6）。

## §1 基线勘误链与对账（checker ③「+32 正本」吸收申报）

派发注记 ③「基线勘误链笔误 +32 正本」：CHECKER §七亲核基线 =
M5-2-VALIDATION「修复后基线 3539/22/0」（对账链 3477+39+22 = 3538 +
E-1 回归法 +1）；M5-3-01 后拼表起算 = **3582/22/0**（3539 + 43）。本
批收口对账（§SUMMARY）按 3582 + 本批增量记录；「+32」字面在
M5-3-CHECKER/02-PLAN 全文零命中（grep 亲证），判定 = 派发注记转写
残迹，无对应 plan 文本需改——照办勿疑落为本条申报，不重开基线。

## §2 求解器定夺：dgelsd 最小范数（checker O2 采纳，非等价自由度）

正规方程（dgesv）在不连通分量上奇异（全零列 → NaN）；`PanoGain
.solveLstsq` = Accelerate `dgelsd`（SVD 最小范数，rcond = −1 即机器
精度，numpy `rcond=None` 语义）——不连通图增益恒 1（merge.py:257-258
注释语义载体）。LAPACK 签名 = 14 参（无 liwork 形参；iwork 尺寸经
lwork=−1 查询自 iwork[0] 回读）——首版 15 参调用编译期抓获。

## §3 FloatTIFFWriter 容器策略定夺（checker minor-3 采纳）

**手写 classic strip TIFF**（非 sequential CGDataProvider）：头 8B +
RGBA float32 行逐带直写 + finish() 时 IFD/外部值（BitsPerSample/
SampleFormat/Software/ICC 经 `CGColorSpace.copyICCData`）+ 头偏移回填
+ 同目录原子晋升（L009/never-overwrite）。ImageIO 一次性 finalize 需
全平面驻留，触红线；strip TIFF 单遍流式。ROWS-per-strip 契约 =
首 strip 行数、仅末 strip 可短（finish 校验）。`writeFloatTIFF` 零
diff（ BandStreamer diff 中仅头注提及，红线 grep 亲证 §SUMMARY）。

## §4 双 pass 几何/融合分离（KD-5 依据落字）

valid = weight>0，而 weight = Σ alpha·inside：alpha = clip(到源边缘
距离/(min(ih,iw)×0.12), 0.001, 1)×inside——纯几何量（只依赖映射坐标
与源尺寸，不读像素）→ 裁切界可先于像素融合解析。pass 1 =
`panoValidMask`（UInt8 1B/px，196MB @196MP 实测）+ PanoCrop；pass 2 =
`panoFuseRows` 逐带。extent 不做一致门（KD-10 异视点合法）与
Mertens/HDR 分界显式申报于腿头注。G3② 权重归一/羽化带落
PanoLegTests 两法（T6 补靶）。

## §5 探针三连杀与产线修复（perf.md 事故节正本）

- 第 1 轮（8192×6144 源）融合段系统杀（footprint 24GB，L077 签名但
  staged 已 sync——非 ①脏页）。**定位**：task_vm_info 逐 band 打点 +
  三臂隔离（fuse-only / reads-only / write 同斜率 +77MB/band 小画布）
  → 增长 ∝ staged **读体量**：逐 tile×源重读同批源行（84 列 tile）+
  freed-but-resident 大块计账。
- **产线修复**：`panoFuseRows` 改 band×源一次联合 span 读（64×64
  strided 采样 + ±128 行 pad；8×grown-once 条带缓冲）——读体量 84×
  降，footprint 爬升 10× 降（+242MB/band 残余，峰值 6.8GB），RSS
  3.8GB 平稳，PanoLegTests 双跑逐位 8/0/0→10/0/0 保持（联合 span ⊇
  每 tile span，gather 只读 inside 邻域，位值不受读边界影响）。
- **源尺寸钉 8×6144×4608 ≈28MP**（staged 3.6GB；minor-5 建议 ~50MP
  因首轮磁盘预算与事故定位调整；画布仍 ≈196-199MP，测量对象不变）。
  诊断三臂与 `syncForDiagnostics` 钩子保留在探针文件（env 门后，主
  套件不可见）。

## §6 其他定夺与申报

1. **plan 无「checker 回注」引注块**：派发注记所指 2026-10-16 引注块
   在 M5-3-02-PLAN.md 零命中（mtime 2026-10-12；checker 采纳实际落点
   = 01 批 ②④ + 本批 ③⑤ + 03 批 ①）；五 minor 采纳落点本批 = ③
   （§3 容器策略）、⑤（L077 四步照办 + 源尺寸钉）、O2（§2 dgelsd）、
   minor-2 之 02 侧（腿消费 encoded 缝——`panoPreviewGrayFromEncoded`
   位等价漂移守卫双测）。
2. **精度域定夺**：`sphericalMap` 角度/旋转 Double、结果 Float32
   （Lumen 实际路径——其 f32 arange 对 f64 rect/scale 提升）；G3①
   worst |Δ| = 2.44e-4 px（12288 点，带 ≤1e-3 钉）。
3. **超帽 canvas-invalid 腿级测试降级为单元级**：200MP 帽在测试尺度
   fixture 下不可达（shrink 单轮即收敛——area' = cap×0.996² 数学必
   然），腿级构造需 GB 级 staged 源；typed 路径由
   PanoWarpTests.boundedCanvas 单元直测（projection-invalid 臂）+ 帽
   下接受/越轮 typed 双法。8 轮不达臂保留（Lumen parity），实践不可
   达性本条申报。
4. **01 stub 测试退役**：`testPanoStubTypedFailure` 随腿体替换删除
   （M5-2-02 先例）；`PanoMergeKindTests` 文件 = files_modified 外最
   小必要修改（MertensMergeKindTests 6→7 同款申报），窗口恒式测试
   （合成腿 bump 2N+5 后 typed fail）保留原样——它不触产线腿。
5. **rowProvider 臂 async 化**：计划文本签名无 async 标注；融合 bump
   须在 provider 内 band-paced（landStackProduct 的写循环 await），
   故 `((_ firstRow: Int, _ rowCount: Int) async throws -> [Float])?`
   ——功能等价（Swift 函数类型禁参标签，编译期修正）。融合 N bump =
   每 band 调用递减预算，band 数 < N 时 landStackProduct 返回后补足
   （计数诚实，顺序申报）。
6. **探针 skip 增量 +2**（O3 估 +1）：`PanoFusionPerfProbeTests` 两法
   （主探针 + 诊断）均 env 门；全套口径 skip 22 → 24。
7. **浮点纹理 fixture 定案**（PanoLegTests 探针发现链）：raw 域作者
   纹理经腿侧 sRGB 编码后 DoG 对比跌破 0.0667 门（0 特征，3 轮迭代
   亲证）→ **编码域作者 + srgbDecode 还原**（点阵对比在 encode 后精
   确还原），逐点强度/尺寸变化 + 噪声上下文破 G2 同族描述子歧义；
   出界回填 = 环绕采样（平色回填 0 特征）+ disconnected 视图独立种
   子。值域 k/64（2^-6 half-exact）。
8. **medianFocal 2× 观察项**：探针 fixture 下 focal-from-homography
   初值 1016（真值 500，±10° 视差 + 量化噪声）；BA 数据相对判据下收
   敛、腿全链绿——初值精度不设门（golden G2 已在 01 钉几何恢复带），
   记观察项。

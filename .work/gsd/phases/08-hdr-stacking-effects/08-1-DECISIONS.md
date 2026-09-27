# Plan 08-1 执行期决策（D-08-1-*）

> RESEARCH/CONTEXT 未覆盖细节的执行期定夺，逐条编号。日期：2026-09-28。

## D-08-1-1 行带流式的 CIRAW 现实化形态

research §6「合并遍逐 256 行带解码/累积」预设源可按行解码；CIRAW/ImageIO **无逐行解码能力**
（RAW 是整帧模型）。落地形态 = 「每遍整帧解码一次、按带消费、带尽即弃」：

- 驻留集 = 累积面（与 N 无关：deGhost off 28 B/px、on 41 B/px，`BandStreamer.accumulatorBytes`
  钉死）+ **单个**瞬态整帧解码渲染（100MP RGBA float32 ≈1.63GB）；N 源全驻（7.3–9.8GB）否决
  依旧成立。
- 解码次数 = N（align 遍）+ N（merge 遍）+ deGhost 时再 ×N = 2N/3N 次 CIRAW（research 预算表
  ×6 = 3 源 × 2 遍同形；deGhost 加一遍在 §12 预算带的 ghost 段内）。
- R3 红线不动摇：恒量内存断言 = `HDRMergeMathTests.testAccumulatorFootprintIndependentOfSourceCount`。

## D-08-1-2 float TIFF「分行 append」不可行 → 整帧 finalize + 同目录 tmp 晋升

plan T3「CGImageDestination 逐带 append」：ImageIO 的 TIFF writer 无 scanline append API
（`CGImageDestinationAddImage` 只加整图页；多页 TIFF 非行带且 `RAWDecoder` 只读页 0）。落地 =
整帧 finalize（`CGDataProvider` 零拷贝引用累积完成的平面）+ `X.tmp-<uuid>` → rename 同目录晋升
（L009；scanner 的 `.tmp-` 排除天然遮蔽半成品）。**不覆盖**钉在 writer 边界（目标存在即
`encodeFailed` 拒绝——`BandStreamer.writeFloatTIFF` + `testFloatTIFFRefusesOverwrite`）。
产物 tag = linear Rec2020（FOUND-02 域随文件走，RAW-03 读回保深）。

## D-08-1-3 权重域与 HOLE 判定的通道语义

- 权重**逐通道**（Robertson 正典；红通道裁剪只零化红），`L̂` 三通道独立加权。
- weight-map（单通道）= 三通道 Σw 的 **min**（任一通道 Σw==0 → 该像素 HOLE）——保守覆盖语义。
- HOLE 像素输出 0.0（黑）。

## D-08-1-4 ghost σ̂ 拍噪声模型系数（plan 预留的执行期决策位）

`σ̂(L̂) = 0.05 + 0.02/√(L̂ + ε)`：5% 噪声地板（research P2 实测锚）+ **2%/√L̂ 拍噪声项**
（L̂=1 处相对 2%，向暗部展开——现代传感器基础 ISO 的物理量级；P2 未钉系数，此为定夺）。
k = 3（research 定值）。残差域 = 线性亮度归一化域（research §4.1 定死：非权重域）。
ghost 判定任一通道超阈 → **整帧**该像素该源零权（移动物三通道同动——P2 形状）。

## D-08-1-5 ghost 判定的共识域与两遍解码

L̂₀（含全部源的 phase-1 共识）冻结后，phase-2 逐源逐带判 rᵢ 重聚合。**phase-2 需要重解码**
（像素面在 phase-1 后已释放；band-pool 形态要求 N 源同带同时驻留 = 与源序解码矛盾）。
deGhost=true 总解码 = 3N 次；deGhost=false 跳过残差统计与 mask 生成（零 IO 零额外解码，
`deGhost:false` 零开销档由测试钉）。

## D-08-1-6 MTB 金字塔的自适应底层 + level-0 低纹理检查

fixture 路径学发现，钉进实现（research §2.1 表在 100MP 域不变）：

- **有效底层自适应**：最粗搜索级的宽度 ≥16 px（且高 ≥12）——更粗的中位位图信噪崩塌，错误
  种子逐级 ×2 级联放大（512px fixture 建 8 级的 4×3 底层实测必偏）。100MP 8 级（91×68）不受
  影响，参数表 verbatim 保留。
- **低纹理检查在 level-0**：粗级把平坦场量化为均匀位图 → 误判 lowTexture；(5,5) 位移被误判
  实证。level-0 的 dominant-bit 比 ≥0.99 才判低纹理。
- fixture 教训两则（测试资产）：clamp 平移丢边带 → 直方图中位漂移 → 阈值位图斑点（xor 测试改
  环形平移）；texture 最大值钉中央（clamp 不可丢位置）防 max 归一漂移。

## D-08-1-7 exposureRatio 自检 = 交集带中位

§1.2「双方均未裁剪的重叠亮度带」落地为**两帧 gates 交集的 index 对齐像素带**（各自带会在
高增益帧截断分布、中位比被压——实测 4× 增益测出 1.2×）。带样本 <16 判无法验证。
EXIF 缺失元数据（合成/老机身合法）= warning 不拒绝（机身/镜头不一致才 reject；nil vs 值 =
warning）；ISO override 后 ΔEV = 快门比 + ISO 比（光圈差进比例自检兜底）。

## D-08-1-8 service 形状（ExportQueue 对位）与 legs 注入

并发 = 1（内存红线）；进度窗 = (align N) + (merge N) + (deGhost ? N : 0) + (写 1 + sidecar 1)
+ 1（终态 settle），leg 侧 bump 义务 N_merge+2（stub 与生产 leg 同遵守）；decode/write 硬失败
retry-able（decodeFailed/encodeFailed typed），对齐失败是 provenance 标注非错误；写边界后
cancel 不可 un-write（.done 诚实）。legs 注入面（decodeLeg/mergeLeg）= 11-04 测试缝惯例。
低优先级 = 独立 MTLCommandQueue（MTLQueue 无优先级 API 的 11-RESEARCH 事实）+ Utility-QoS
runner；服务自包含域，队内读回 L014 fence——L031 措辞遵守。

## D-08-1-9 App 编排面（最小入口）

menu（多选 ≥2）→ sheet dialog（deGhost toggle + N 张提示 + N=3 统计弱诚实文案）→ enqueue →
queued toast → done toast（holeFraction 百分比 + EXPLICIT reconcile ingest + grid reload）/
failed toast（typed error）。进度条 UI 缺席 = toast 交换（100MP 全程 15–40s 量级；正式进度面
随 08-3/08-5 打磨——执行期简化，键位已留 xcstrings）。新增本地化键 8 枚（zh+en 同批，L025）。

## D-08-1-10 sidecar v4 re-encode 不改写版本

decode 路径保留文档自身 schemaVersion（v3 文档 re-encode 仍写 3——不静默改写既有文档；current
版本只由 value-init 路径=新写入方产出）。provenance 编码用 encodeIfPresent（layerStack 先例：
optional 结构键缺席而非 null；v3 五标量键 always-write 惯例不适用）。`driftDetected` hash
隔离（provenance 不是管线参数，不进 HistoryHash）。

## D-08-1-11 `.lra.masks/` 排除面（scan 单点）

ghost PNG 落 `<产物>.lra.masks/`；该目录**不是**点前缀/保留集，`isExcludedDirectory` 不命中
→ descent 进入（无害），但 `*.png` 在 rasterExtensions 内会成 browse 行。修复 = scan 采集面
relPath 含 `.lra.masks/` 一律 continue（scan 是 reconcile 的唯一采集面，index 一致）。9-2
watcher 的 `isWatcherExcludedFile` 无路径参数不动（外部向 masks 目录写 PNG 的 FSEvents 事件
会触发 reconcile，但 reconcile 重扫后同类行被排除 = 无净效应；不另改共享谓词）。

## D-08-1-12 T7 矩阵基座的 parity 分层（回注 planner/08-5）

plan「数值 parity = float32 CPU 参考实现逐点容差（Phase 3 golden 形状）」的 filmicrgb/sigmoid
链段，其参考正本 = dt 侧 golden 生成器（input/golden/regenerate.sh），**不产出组合链工件**。
基座分层落地：①已知值 patch × [colorin, exposure] = 解析参考逐点（×2^EV，1e-5；65504→131008
无钳制存活 = HDR-04 承重钉）②全链 toneequal(0) 尾恒等（maxDev=0.0）③torture 有限性诊断。
**filmic/sigmoid 的 dt 交叉由既有 Phase 3 套件背书**；组合链 dt golden 扩展 + lut3d 列 =
08-5 收口。

## D-08-1-13 T7 执行期发现（回注 08-5，两项）

1. **CI input 腿 half 下溢**：`CIContextPool` workingFormat RGBAh 对 sub-1e-4 场景线性值
   下溢丢失（shadow_torture.exr 96×96 经管线输出全黑；同链 64×32 合成 patch 正常）——L006
   half-banding 的 HDR 域面。合并产物真实值域（0.001–100）多在 half normal 域内，但暗部
   ≤6e-8 subnormal 面存在。归 08-5 preview float32 预算复核。
2. **torture 96×96 vs patch 64×32 管线行为分歧未定位**（同链同域前者的输出恒黑而后者正常；
   解码面 decodedMax=4.0 正常）。探针留测试内（TORTURE-CHAIN-PROBE），08-5 收口复核。
3. **24MP 全程秒表 73.5s（Debug 宿主）**：research 11.2ns/px 为 Release -O 探针，Debug 内
   循环 ≥10× 慢；外推 100MP ≈312s（Debug 上界）。Release 口径复测归 08-5/独立验证批
   （Project.swift @testable 与 Release 测试互斥，无法在本 plan 直测）。

## D-08-1-14 测试基建小项

- `Scripts/test-direct.sh` 判据 grep 补 `-a`：直启宿主日志含 GPU 原始字节，BSD grep binary
  判定使 Executed/failures 计数静默归零（13-2 LESSONS 观察到、本轮实际触发修复）。
- 12-1 的 SidecarMetadataV3Tests 字节 golden 随 v4 升级重钉（预期破坏面：版本行 3→4 +
  provenance 缺席断言；五键 always-write 形不变）。
- Toast 进度形态简化为 queued/done/failed 三 toast（D-08-1-9），进度条留 08-3/08-5。

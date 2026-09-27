# Plan 08-3 — DECISIONS（执行期决策，research/CONTEXT 未覆盖或需落档的细节）

## D-08-3-T1-1 SML 边界语义 = clamp-first

kernel 与 CPU mirror 均先钳位窗位、再在被钳位处计算 ML（虚位的 ML 不参与求和）。首版 CPU
mirror 以"虚位自身梯度归零"口径实现，与 kernel 逐位分歧（GPU/CPU 比值 ~1.2–1.5，977 断言
失败）——以 kernel 语义为准统一（P5 原型即 clamp 形）。测试钉：双位 parity（1% 容差）。

## D-08-3-T1-2 L031 路由红线在服务域的兑现形态

SML kernel 不经 `MetalContext.makeRoutedCommandBuffer()`：StackMergeService 的专属
MTLCommandQueue 是 08-1 确立的自包含域（producer/consumer 同队，构造性无跨队竞速）；改经
MetalContext 反而把 SML 提交到 editor/export 队——恰好制造 L031 存在所要防止的跨队读早竞态。
兑现形态 = **FocusMeasure 是该域的唯一提交点**（`queue` 为参数，生产只传 service.mergeQueue；
L031 grep：Stack 目录仅 FocusMeasure.swift:173 一处 `queue.makeCommandBuffer()`，即该唯一提交点）。
读回 L014 = 产出 CB `waitUntilCompleted()`（比独立空 fence 更强的同 CB drain）。

## D-08-3-T1-3 无 drain 竞态负例的证明性测试形态

纯"提交即读"的零初始化依赖不可靠（MTLBuffer 新分配内容未定义）。定形 = `dispatch(into:)`
内部缝让测试复用同一输出 buffer：①纹理 dispatch（drain）→ buffer 含纹理图（非零）；
②常量场 dispatch（spin 4M ≈ ms 级延迟，**不等待**）→ 立即读 → 仍是①的旧图 = 读到旧面的
直接证据；③常量场 drained 对照 = 全零。时间窗确定性：GPU 完成需 ms，CPU 读落在提交后 µs。

## D-08-3-T1-4 half 往返容差 = 1% 相对 + 1e-4 绝对地板

half（11-bit mantissa）+ float32 kernel 累加的合成误差实测 ≪1%（最差相对 ~0.1%）；容差
取 1% 相对（近零格以 1e-4 绝对地板防除零）。

## D-08-3-T2-1 融合带 halo = 32 行（±）

5 级金字塔感受野 ≈ 2·(2⁰+2¹+2²+2³) = 30 行；halo 取 32 行覆盖。strip 边缘 clamp 只污染
带外行（带内行严格等于全图融合）。工作集账面：`bandWorkingSetBytes` = N×(band+2·halo)×W×
(4+1)ch float + 累加器几何级数项；N=8@11656 宽 ≈ 740 MB < 单幅全帧驻留（1.63 GB），断言钉
「O(band) 且严格亚帧」。

## D-08-3-T2-2 金字塔对 = binomial reduce + **线性 2× expand**（否决零填充 4h 伴随核）

首版 expand 用 Burt-Adelson 零填充 + 4·h 闭式（even (1,4,6,4,1)/4 / odd (1,4,4,1)/4）：
常数场 DC 增益 = 4（偶相位核和 16/4）→ 拉普拉斯望远镜在高频 fixture 上爆炸（MAE 0.84，
融合值漂出 [0,1] 至 ±10）。改用 DC=1 的线性 2× 伴随（偶 = 原样、奇 = 邻均值）后望远镜
严格成立：同源双份重构 = 原图（1e-3 float32），清晰区 MAE 0.84 → **0.0016**（P5 量级）。
文献 expand 形态在无缩放补偿时不可用——一致性（reduce/expand 互逆于常数）才是融合正确的
充要条件，记录为移植陷阱。

## D-08-3-T2-3 无权重区域的融合语义

局部 quality=0 洞**不**产出黑（粗层在该区域消失后由 expand 回灌邻域值——enfuse 同款软融合
语义）；全源全域无权重才逐层 BL=0 → 严格黑。测试按全域无权重钉黑场 + 局部洞只钉非 NaN。

## D-08-3-T3-1 σ 估计式与 k 值 = population σ（ddof=0）、k 默认 2.5

population σ 下 N 样本集最大 |z| = √(N−1)：k=2.5 需要 N ≥ 8 才可能剔除（N=7 的 √6 ≈ 2.45
< 2.5 恒不可剔）；star-field E2E（N=8）钉默认 k 的真剔除面，解析 golden（N=6）以 k=2.0 钉
数学。`maxZScore` 辅助函数 = √(N−1)（注意 (N−1)/√N 是 ddof=1 口径，勿混）。

## D-08-3-T3-2 median 偶数口径 = 双中位均值

标准统计口径（排序后取中央两元素均值）；奇数取中央元。解析 golden 钉两支。

## D-08-3-T4-1 params 快照含 nccMeasuredMin 的身份稳定性

测得 NCC 最小值进 `algorithm.params`（plan 字面「NCC 结果」入快照）。可入的原因 = NCC 是
同参同源的确定性函数：重放身份哈希（params 参与投影）在重跑间逐位稳定，等价提示与重放
幂等不受污染；源漂移时 stableHash 先变，身份本就不同。

## D-08-3-T4-2 tag 拼法 = 复合词汇表

`<base>_fstack.tif`；堆栈降噪三分支统一 `<base>_stack_avg|_stack_med|_stack_sig.tif`
（非 plan 备选的「average 裸 `_stack`」——三模式文件名可自解释、kind 可从文件名恢复、
防撞递增照 ExportNamer）。`params.tag` 非空时优先（用户显式 tag 胜出）。

## D-08-3-T4-3 暂存（staging）IO = R3 的诚实代价

median/sigma 需要带外随机访问 N 源行，而 CIRAW/ImageIO 不能按行解码（08-1 D-08-1 已记），
band-outer 唯一可行形态 = 每源解码一次后整面暂存临时文件（float RGBA 原样 + half quality），
终段按带读回。内存账：常驻 = 输出面（N 无关）+ 单带 N 值栈（≈286MB 上界）；代价 = 100MP
N=8 时 ~9.7GB×2 的顺序 IO（research §12 预算表未单列，perf.md 偏差注记即此条）。临时目录
`FileManager.temporaryDirectory/la-stack-<uuid>/`，defer 整目录删除（错误路径亦清），不进
会话、不触源文件、无 rename（L009 不适用）。

## D-08-3-T4-4 focus/stack 预检判据差异表（vs research §2.4 HDR 表）

| 字段 | HDR（08-1） | focus/stack（08-3） |
|---|---|---|
| 机身/镜头 | 严格（镜头缺任一侧 = 警告） | 同（原样） |
| 焦距 | 严格（0.5mm） | 同（原样） |
| 光圈 | 严格；override 放行+警告 | **同**（景深一致性前提，维持拒绝/override） |
| ISO | 严格；同 override | 差异 = **警告**（isoRatio 不进 ΔEV） |
| 快门 | 必须**互异**（等快门 = 拒「非包围」） | 差异 = **警告**（等快门合法——对焦轨/堆栈常态） |
| ΔEV 组成 | log2(t_ref/t_i)+log2(ISO 比) | 恒 0（堆栈不做曝光加权，无 §1.2 比例自检） |

测试钉互斥对照面：等快门 → HDR 拒 / stack ok；ISO 差 → stack 警告；光圈差 → 两者同拒、
override 同放行。

## D-08-3-T5-1 融合/软化计算域 = CPU float32（GPU 仅 SML）

金字塔/软化保持 CPU（P5 原型即 CPU 形，golden 直接同构）；plan 纪律的「GPU 提交走唯一路由」
条款约束**若为 GPU**的提交路径，不强制融合 GPU 化。100MP N=8 CPU 融合估 10–20s（只记），
GPU 化留 Phase 15 候补。

## D-08-3-T6-1 fixture 走 raster 解码路径（.tif）

服务段 E2E 源用 `.tif` + 纹理 float TIFF：`utiForFile` 内容嗅探 → public.tiff → ImageIO
raster 解码（RAW-03 面），绕开 CIRAW 对合成 TIFF 的偶发 nil（与 ProvenanceV4Tests 的
64×64 常量 fixture 行为分叉实测在案）。堆栈消费任意 raster 合法；RAW 特有面（EXIF/比例
自检）归 08-1 既有测试。纹理幅度与 pinned max 按 MTBAlignTests 规范（防规范化散斑）。

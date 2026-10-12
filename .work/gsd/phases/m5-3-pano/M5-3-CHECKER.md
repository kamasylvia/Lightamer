# M5-3 CHECKER — 全景合成 plan 集（M5-3-01 + M5-3-02 + M5-3-03）从严审查

> Checker = zcode subagent（从严口径）。审查对象 = `M5-3-01-PLAN.md` /
> `M5-3-02-PLAN.md` / `M5-3-03-PLAN.md`，规格正本 `RESEARCH-NOTES.md`，裁决
> 正本 `M5-3-CONTEXT.md` 裁决记录（2026-10-16 用户回批，OQ-1..7 全按推荐）。
> 源码锚全部亲核（非转述）；Lumen `lumen/merge.py` :12/:62/:100-117/:192-315
> 逐段对照亲读。日期 = 2026-10-09（checker 派发批）。

# PASS / 0 error + 5 minor

5 处 minor 均为穿线登记/跨 plan 接缝/红线门硬化/执行环境 runbook 级，
**不阻断派发**；处方随条，建议 orchestrator 派发前一笔勘误（或各自执行批
T 收口 DECISIONS 随手吸收）。逐维审查如下。

## 一、裁决一致性（七项生效值 → AC 对表）——PASS

| 生效值 | 落点 | 判定 |
|---|---|---|
| OQ-1 = A 自实现特征链（DoG/匹配/RANSAC，MIT 注记，OpenCV 零入仓，Vision 仅 spike 候选） | 01 生效值 1 + KD-1/KD-2（`git grep` opencv 门 + dependencies 零 diff + 零新 `.metal`） | ✅ |
| OQ-2 = A 单焦 f+N×R LM BA（3N+1）+ 横向 wave correct | 01 生效值 2 + KD-5；02 KD-2/KD-3（K 对角 + median 焦距）；per-image 焦距/畸变 = V2 挂账（03 KD-8） | ✅ |
| OQ-3 = A 全链 sRGB 编码 float32 + sRGB 32f TIFF | 01 生效值 3（灰度制备接缝）+ 02 生效值 1/KD-1/KD-9（`productColorSpace` Mertens T2 同参 + M4-1 ICC tag 域判别零新机制） | ✅ |
| OQ-4 = A 200MP 帽 + 2..32 张 + 8G 探针钉 | 01 生效值 4（张数门常量 + enqueue kind 条件式 32 上限）+ 02 生效值 2/KD-4（`maxCanvasPixels = 200_000_000`，Lumen :12 亲核）+ KD-12（`RSS_LIMIT_MB=8192` 机检亲核在册） | ✅ |
| OQ-5 = A 恒 inner_crop + alpha 不写 | 02 生效值 3/KD-8/KD-9（alpha 恒 1；crop `[x0,y0,x1,y1]` 入 provenance）；01 生效值 5 先钉词汇 | ✅ |
| OQ-6 = A v1 全 CPU 零 `.metal`，越门 GPU 另立项 | 01 生效值 6 + 02 生效值 4/KD-12（NO GATE 声明 + 决策面上报） | ✅ |
| OQ-7 = A `.pano` additive 第七 case + 简形 sheet；预览/手选/use_edits 挂 V2 | 01 KD-6/KD-8（typed stub，路由不切）+ 02 KD-10（换腿体零二次编辑）+ 03 KD-1/KD-2（零控件 sheet；文案四项生效值落点） | ✅ |

- 七值跨 plan 切分自洽：数学面 = 01、落地面 = 02、UI/分账/收口 = 03，无
  重叠无遗漏；V1/V2 边界三处（01/02/03 KD 挂账）与 CONTEXT 裁决记录逐字
  对齐。✅
- `dual_acceptance = true`（`.work/config.toml [gsd]` 亲核）→ 三 plan 收口
  任务均落「zcode PASS → 串行 omp 二次验收，严禁并发」+ ACCEPTANCE 落盘。
  `paused = false` / `auto = true` 亲核，无门控冲突。✅
- C 档三停齐备：第 1 停已兑现（CONTEXT 裁决记录在案）；01/02 各 C 档第 2
  停；03 = Phase 签核前第 3 门。✅

## 二、算法实现——PASS（2 minor：minor-2 及观察 O2）

亲核 `lumen/merge.py` 全文对照：

- **六段链参数逐值吻合**：预览 ≤1200（`small(im,1200)` :215）/ SIFT 语义
  6000 帽（:219）/ 种子 121（:220）/ <10 特征 typed（:223-224）/ Lowe 比值
  0.3（:227）/ 边门 conf>0.6 ∧ inliers≥10（:231-233）/ BFS 连通性（:235-238）
  / refinement mask 只开 f+R（:244-245，与 01 KD-5「3N+1」一致）/ wave
  correct HORIZ（:246）/ `inv(preview_scale) @ K()` + median 焦距（:252-253）
  / bounded_rois ×0.998 ≤8 轮（:192-202）/ `PANORAMA_MAX_PIXELS=200_000_000`
  （:12）/ spherical_map 逐式（:205-211，z>1e-6 无效 = −1）/ 增益 ≥80px ∧
  (0.04,0.9) ∧ 锚权重 10 ∧ `exp(clip(±.5))`（:259-273）/ 512px tile + 12%
  短边羽化带 + `1e-8` + BORDER_REPLICATE（:274-289）/ inner_crop ≤1024-cell
  min-pool + 直方图栈 + 空矩形 raise（:100-117）/ merge_images 2..32 门 +
  crop 默认 on + finite 校验（:293-315）。**01/02 各 KD 的直译声明全部与
  Lumen 原文逐段对得上，无虚指锚。** ✅
- **RANSAC 常量锚亲核**：内点阈 3px + 硬帽 3000 = Lumen
  `estimateAffinePartial2D(..., ransacReprojThreshold=3, maxIters=3000)`
  （merge.py:62 亲核）——01 KD-4 引证成立。✅
- **置信度公式** `1 − inliers/(8 + 0.3·matches)`：OpenCV detail 公式正确；
  10/3 上界 = inliers/(8+0.3m) 的 m→∞ 极限，与 :225-226 注释语义一致；
  对 conf>0.6 门控，min-clamp 差异无观测后果。✅
- **DoG 定夺（research 留白的 planner 裁决）**：KD-1 裁 DoG（SIFT 同构，
  Lumen 低对比地形注释 :217-218 在案）+ 依据落 DECISIONS 义务 + 亚像素精化
  剪裁（3px RANSAC 阈下收益边际）显式申报——程序合规。✅
- **LM BA/wave correct 数学**：残差 = 射线角重投影（BundleAdjusterRay 同形）；
  wave correct = Σ 首行外积最小特征向量 + 符号定向（Σ 首行 x ≥ 0，OpenCV
  标准式）+ 幂等可测；N=2 欠定退化 = LM 阻尼 + typed 收敛门守底 + DECISIONS
  义务 + G2 覆盖 N=2/N=4——申报完整。✅
- **G2/G3 防循环**：01 G2 渲染器与 02 G3① 对照解均「测试本地闭式实现、
  刻意不 import 产线 pano 文件」——双向独立声明在案。✅
- **G2 硬上限**（f ≤5% / R ≤2° / inlier ≥60%）+ 钉门程序（首轮实测 →
  DECISIONS 落字面 → 断言实测带，禁调 golden 凑带）= M5-2-01 同款，程序
  成立。✅

### minor-2（01 KD-1 × 02 KD-1）：预览灰度制备的编码段与腿侧 staged 平面二次编码缝

01 KD-1 制备函数 =「全分辨率平面 → **sRGB 编码** → Rec709 luma → ≤1200
降采样」；02 KD-1 编排 =「render → **sRGB 编码 in-place** → staged → **同
平面派生预览灰度（M5-3-01 制备函数）**」。腿侧入参平面**已编码**，按 01 字面
再走制备函数 = 双重编码（srgbEncode∘srgbEncode，画面系统性提亮，特征阈值
行为漂移；确定性不破、G2 自洽、腿级 typed 门不红——**属可静默漏网的隐性
质量缺陷**）。增益采样面（02 KD-6，同平面 luma 域）同理。
**处方**：01 T1 把制备函数拆两个缝——`preparePreviewGray(from:encoded:)` 或
编码段独立暴露；02 KD-1 加一句「派生预览灰度 = 已编码平面的 luma+降采样，
编码段跳过」。执行批入 02 DECISIONS。

### 观察 O2（02 KD-6）：增益求解器「执行期定」的两个选项不等价

正规方程（dgesv）在不连通分量上**奇异**（该图列全零 → NaN），最小范数性质
正是 Lumen 注释（:257-258）锚定的「不连通不静默丢失」语义载体；dgelsd
（SVD min-norm）才满足。T2「不连通图增益有解」负测会抓住错误选项，故不成
error；DECISIONS 记录时**应显式记 dgelsd 最小范数优先**（或锚行消除法），
勿把两选项当等价自由度。

## 三、内存红线（双 pass 几何/融合分离）——PASS（1 minor）

- **数学依据已落纸**：02 KD-5「valid = weight>0，而 weight = Σ α·inside
  纯几何量（α 只依赖源图尺寸与映射坐标，不依赖像素值）——裁切界可先于
  像素融合解析」——论证成立（α = clip(edge/(min(ih,iw)×.12))×inside，全
  几何；与 Lumen :274-289 逐 tile `weight>0` 同量），DECISIONS 落字义务
  在册。✅
- **两 pass 与单 pass 参考的等价钉**：G3「小画布上两 pass 裁切输出 ==
  naive 单 pass 全画布融合后裁切参考**逐位**」——双 pass 分离的正确性门
  已钉。✅
- **全画布像素面 3.2GB（200MP×16B/px，算术亲核）永不物化**：无 memmap、
  无 staged 输出画布、行带直写——红线文字明确。✅
- **landStackProduct additive `rowProvider` 参**：nil = 既有 rgba 全平面
  路径字节零漂移（专测钉死，02 T4）；非 nil = 行带路径，sidecar/provenance/
  命名段全复用——共享尾段零重实现成立。✅
- **band 起点整除 2^(L−1) 约束（M4-2-02/M5-2 先例）**：该约束属金字塔带
  融合（mertensAlignedBands :1245-1260 亲核）；pano tile 融合无金字塔、无
  此前提，两 plan 未误引——适用面干净。✅
- **extent 不做一致门**（异视点合法）与 Mertens/HDR 的分界已显式申报
  （KD-10，DECISIONS 义务）。✅

### minor-3（02 KD-9）：FloatTIFFWriter 容器策略 hedge 与 BandStreamer 头注的 ImageIO 一次性约束

BandStreamer 头注亲核（:23-25）：「ImageIO finalizes a TIFF in one shot
（no scanline append API），所以 writer 在成品平面上建 CGImage」。02 KD-9
新 `FloatTIFFWriter`（构造 + `write(rows:)` + `finish()`）在「无 memmap、
无 staged 输出画布」红线下**不能**内部复用 `writeFloatTIFF`（其要求全平面
且 `Data(buffer:)` 再造一份全尺寸拷贝）；可行形只有两条：
sequential `CGDataProvider`（Finalize 时回调拉行，融合驱动驻留至 finish）
或手写 strip TIFF（头 + IFD 占位回填 + ICC payload 经
`CGColorSpaceCopyICCData` 嵌入——L053 三坑在案）。KD-9 的「可内部委托或
并列」hedge 在流式形下**只有后者语义可行，前者需 sequential provider 形**
——不指明则执行侧可能退化成「缓冲全平面再一次性写」，红线被静默违反且
8G 探针未必抓得住（3.2GB 平面 + 拷贝 ≈6.4GB 贴线可过）。
**处方**：02 KD-9 删「内部委托」歧义，改为「容器策略二选一（sequential
CGDataProvider / 手写 strip TIFF + ICC 嵌入）落 DECISIONS + 头注同步更新」；
02 T4 加一条流式形申报断言（pano 路径写盘仅经 FloatTIFFWriter.write 逐带
调用——SUMMARY 自证项）。产物域判别负测（sRGB tag round-trip）已有，保留。

## 四、确定性门——PASS（1 minor）

- **PanoRNG 种子 121**：`cv2.setRNGSeed(121)` merge.py:220 亲核；LCG 常数
  MMIX 族（HDRMergeMathTests 先例同族）；语义定位（RANSAC 确定性锚定，非
  统计质量声明）准确。✅
- **唯一 RNG 流**：RANSAC 采样 + 自适应迭代全程单流；最优模型 tie-break =
  最早达到（RNG 序）；knn tie-break = 索引序——确定性全部自握。✅
- **G1 双门**：01 KD-9 全链（特征→匹配→RANSAC→f→BA→wave）双跑逐位 +
  02 KD-11 腿级闭环（含落盘字节）——两层覆盖，程序完整。✅
- **禁系统随机源 grep 门**：KD-3 门面在册（见 minor-4）。
- **golden 投影器独立**（§二已核）。✅

### minor-4（01 KD-3）：grep 门模式漏 `Double.random` / `Float.random` 族

门 = `SystemRandomNumberGenerator|srand|arc4random`——`Float.random(in:)`/
`Double.random(in:)` 底层即 SystemRandomNumberGenerator 但**不含该类型名字
面**，门可漏。**处方**：模式补 `|\.random\(`（一行）；02/03 G5 终验 grep
同批更新。

## 五、编译/结构——PASS

- **「四处穷举 switch」主张逐点亲核成立**：`provenanceKind`（StackMerge
  Service.swift :258-267）/ `stepTotal`（:573-584）/ `defaultTag`（:588-597）/
  `runProductionMerge`（:861-871）为仅有的 MergeKind 穷举 switch；第五处
  `runStackAggregateLeg` 内 switch 带 default（:1825-1831）不破。全仓 grep
  证实 App/IOP 侧零其它 MergeKind/`SidecarProvenance.Kind` 穷举消费面
  （仅 LightamerApp :943 enqueue 字面 + :959 局部变量 + Coordinator :131
  注释）。`case pano` additive 编译期破四面、逐处补臂方案精确。✅
- **MergeParams additive**：init 尾部追三 optional（现 13 参 :329-343 亲核），
  既有调用点零改动；synthesized encodeIfPresent 旧档零漂移 + golden JSON
  字面专测——Mertens 双字段同款先例在案。✅
- **ProvenanceReplay**：Kind :39-46 raw 镜像纪律 + mertens 双常量 :151-154
  先例位——`panoMerge` 镜像 + 双常量 additive 成立；`provenanceHash` 含
  params Codable，旧档不含新字段 → 哈希稳定。✅
- **stepTotal 3N+6 推导验算**：decode N（service execute 循环 :723-738 bump）
  + 特征 N（KD-10）+ 融合 N（tile-paced 补足，mertensBandOuterFuse
  bumpBudget 同形 :1345-1353）+ 6（匹配/BA/波 1 + 画布/ROI 1 + 增益 1 +
  write 1 + sidecar 1 + settle 1）= 3N+6，01 KD-6 与 02 KD-10 两处声明
  逐字一致；done==total 恒式测试钉死。诚实声明面优于 08-3 族（研究注记
  在案）。✅
- **stub→真腿交接**：01 落 `runPanoLeg` typed stub（M5-2-01/M4-1-01 路由
  不切形亲核在案），02 只换腿体零二次编辑。✅
- **零新 SPM / 零 `.metal` / 零 IOP / Sidecar / Pipe / History / Graph /
  ExportQueue**：三 plan 红线清单 + 收口 grep 自证全覆盖；01 还显式钉
  `ExifPrecheck.swift` 零 diff（pano 不消费 EXIF/bracket——Lumen
  merge_images 对 pano 亦无 EXIF 门，亲核成立）。✅
- **tuist generate 恒末位（L041）+ BUNDLE-MAP 增行（E2）**：三 plan 纪律
  节齐备。✅

## 六、性能——PASS（1 minor：minor-5）

- **预算探针双保险**：env 门 `LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless（默认
  skip）+ `RSS_LIMIT_MB=8192` 机检（test-direct.sh :70 亲核）+ 批准制 +
  运行中监视——AGENTS 资源监控节全对齐。✅
- **落域 rationale 成立**：EXPORT 既有峰值 6443MB（M5-2-VALIDATION :32 亲
  核），是七 bundle 中余量最宽者；探针真产线直驱（`nonisolated static
  internal` 缝，mertensBandOuterFuse 先例）。✅
- **内存账对照**：valid 掩码 200MB（1B/px）+ O(tile²) accum/weight + staged
  IO 行带缓冲 + 预览域 <1GB——KD-5 账面自洽；探针实测回填 perf.md。✅
- **CPU 预算现实性**：Mertens 同域先例 = 融合核 172.24s@100MP×5（GOAL-STATE
  M5-2-02 行亲核）；pano 200MP×8 墙钟分钟到十分钟级、NO GATE + 越门 GPU
  另立项——OQ-6 程序闭环。特征段 vDSP 亚秒/pair、O(N²)×N≤32 预览域可接受
  （RESEARCH §3.2 锚）。✅
- **01 不申请 `--all`**（新测试全小 fixture）；02/03 收口轮 `--all` 单独
  申请——贴线纪律（IOP 7657MB / IOPParity 7738MB 亲核）对齐。✅

### minor-5（02 KD-12/T5）：L077 runbook 未挂——panorama 族被 L077 适用条款点名

亲核 `.work/LESSONS.md` L077（:799-830）：**「适用：一切 GB 级 staged IO 的
测试/基准（100MP 级 merge/export/panorama 族）」——正文直接点名 pano**。
02 探针 = 项目史上最大 staged 集（200MP 画布 × 8 合成源；源尺寸未钉，若
百 MP 级源则 staged 可达 12.8GB+），而 02 纪律节只挂了 L072，未挂 L077
四步（staged 写后 `synchronizeFile` 回写 / PERF 行 stderr / 轮前后
`$TMPDIR` 模式清扫 / 开跑前 `df`+swap 预检）——M5-2-02 三连环事故
（footprint 杀进程 → defer 不跑残留 → ENOSPC 卡 harness）有高概率原样
重演。**处方**：02 T5 纪律 + KD-12 各加一句 L077 runbook 引用（四步全照）；
探针源尺寸显式钉（建议 8 × ~50MP 合成源 → 200MP 画布，staged ≈6.4GB）+
磁盘预算行入 perf.md。

## 七、测试对账——PASS（1 minor）

- **基线**：3539/22/0 = M5-2-VALIDATION 「修复后基线 3539/22/0」（:22 亲核）
  + 对账链 3477+39+22 = 3538 + E-1 回归法 +1——01 基线段引证准确；02/03
  「前 plan SUMMARY 记账后起算」衔接措辞照 M5-2-02 先例。✅
- **估数**：+42..52 / +30..40 / +5..8 = **+77..100**，与派发口径逐字一致。✅
- **bundle 分账核对（BUNDLE-MAP + Project.swift 亲核）**：01 五测试文件 =
  PanoFeature/Match/Camera/MergeKind（IOP，HDRMergeMathTests/StackMerge
  ServiceTests 同位）/ PanoProvenance（LIB，MertensProvenanceTests 同位
  Project.swift :596）/ PanoGolden（IOPP，MertensFusionGoldenTests :338 同
  位）→ test_bundles [IOP, IOPParity, Library] 全覆盖；02 五文件 =
  Warp/Gain/Crop/Leg（IOP）/ FusionPerfProbe（EXPORT，:722 先例位）→
  [IOP, Export] 覆盖（M5-2-02 minor-5 型「空分账」不复发）；03 一文件 =
  MergeUI（APP，:815 先例位）→ [App]。✅
- **typed 三态词汇跨 plan 钉死**：01 KD-4 canonical 前缀（`panorama
  alignment failed / panorama images disconnected / panorama canvas
  invalid`）→ 02 消费（KD-4/KD-8/KD-10）→ 03 前缀表 zh 三键映射 + 非前缀
  透传——契约链无断裂；载体 `AppError.invalidParameter` = Mertens stub
  同形（:906-916 亲核）。✅
- **zh 八键**（browser_menu_pano / dialog title/body/start / toast_pano_
  queued / error×3）+ V15 `zh-audit --check` 实跑对账 + 尾块纯插入——
  Mertens 5 键先例 +1 三态，程序合规。✅
- **G6 MANIFEST / G4 evidence / VALIDATION 挂账汇编**：落点与体例正本
  （m5-2 MANIFEST/VALIDATION）对齐；G4 仓外脚本零入源码树纪律在册。✅

### minor-1（03 files_modified）：ContentView.swift 穿线缺登记——M5-2-02 同款陷阱复发

亲核穿线链：`SessionBrowserView.onHDRMertens`（:62）由 **ContentView.swift
:461-464** 装配（`Task { await sessionCoordinator.mertensMergeHandler?...
}`）；`panoMergeHandler` seam 需要同位第四段 `onPano:` 穿线，而 03
files_modified 只列 SessionBrowserView / SessionCoordinator / LightamerApp
——ContentView 缺席。M5-2-02 已踩过同坑（GOAL-STATE：「ContentView 穿线 =
files_modified 外申报」）。**处方**：03 front-matter 补
`App/Sources/Lightamer/UI/ContentView.swift`（T1 修改说明 + 一行穿线），
或最低限度 T1 注记「预期 files_modified 外申报面」。

## 八、goal-backward——PASS

- **IOP-PANO-01 交付定义**（REQUIREMENTS :374 亲核：特征匹配对齐 + 相机参
  数优化 + 球面投影 + 分块羽化融合 + 100MP+ 入正常编辑管线 + 新合成模式）
  由三 plan 合计全覆盖；验收形态（分段 golden + 8G 预算 + 走查）= G1-G6 +
  预算门七门落位（G1/G2 = 01，G3/预算 = 02，G4/G5/G6 = 03，VALIDATION
  全表逐门引用 evidence 正本）。✅
- **产物入编辑链**：sRGB 32f TIFF → M4-1 raster ingest（域判别 = ICC tag
  基，RasterColorDescription resolve 规则亲核在 BandStreamer 头注与
  MertensRasterDomainTests）——零新机制声明成立。✅
- **M5-4 衔接**：VALIDATION 兼「全史瘦身手术」第二次（strip 集重算非空才
  动手）= CONTEXT 下一步原文；GOAL-STATE 续接点链证实 M5-2 closed → M5-3
  为当前站（M5 续接点 19 行亲核）。✅
- **收尾三件套**：三 plan 的 SUMMARY/DECISIONS/ACCEPTANCE + GOAL-STATE/
  TODO/LESSONS + 03 AGENTS.md 架构增量节（封存面 additive 申报六新文件 +
  FloatTIFFWriter + StagedSet.readRows）全在 files_modified。✅

## 观察项（不计级，供执行批参考）

- **O1（01 KD-4 行锚 ±1）**：边门引「merge.py:232-234」实际 :231-233——
  语义亲核成立，不改不修。
- **O2**（§二已述）：增益求解器 DECISIONS 记 dgelsd 最小范数优先，勿当
  等价自由度。
- **O3（skip 簿记）**：02 探针 +1 env 门 skip（全套 skip 22→23）——02/03
  SUMMARY 对账链记得记 skip 增量（M5-2 同款，:33 「skip 21→22」先例）。
- **O4（IOPParity 贴线）**：IOPP 既有峰值 7738MB 为最紧 bundle；PanoGolden
  全小 fixture 增量可忽略（跨测残留 0.18-2.4MB/test，SPIKE 口径）——01 T6
  已挂 MEMFAIL 漂移口径，无需动作。
- **O5（探针源尺寸）**：并入 minor-5 处方（显式钉 8×~50MP + 磁盘预算行）。

## 亲核锚清单（本报告事实基础）

- `LightamerCore/Sources/Stack/StackMergeService.swift`（全文 2236 行——
  MergeKind :249-268 / provenanceKind :258-267 / MergeParams init :329-343 /
  enqueue N≥2 guard :526-529 / execute decode bump :723-738 /
  stepTotal 双式 :560-584 / defaultTag :588-597 / dispatch :855-871 /
  runMertensLeg :901-1070 / mertensDisplayEncodeInPlace :1079-1090 /
  mertensAlignedBands :1245-1260 / mertensBandOuterFuse :1272-1355〔bump
  补足 :1345-1353〕/ landStackProduct :1944-2037 / StagedSet :2044-2235 /
  runStackAggregateLeg default-arm switch :1824-1831）
- `LightamerCore/Sources/Stack/ProvenanceReplay.swift`（Kind :39-46 /
  mertens 双常量 :151-154 / provenanceHash :204-230）
- `LightamerCore/Sources/Stack/BandStreamer.swift`（全文——头注 ImageIO
  one-shot :23-25 / writeFloatTIFF :156-242 / `Data(buffer:)` 全尺寸拷贝
  :180-184）
- `LightamerCore/Sources/Stack/MertensFusion.swift`（头注 MIT 归属 + sRGB
  域 + grayCoefficients Rec709 :62-64）
- `LightamerCore/Sources/Pipe/Drt/DrtEotf.swift`（srgbPiecewiseEncode/Decode
  :169-182，自带 [0,1] clamp）
- `Project.swift`（MertensFusionGoldenTests :338〔IOPP 数组〕/
  MertensFusionTests·LegTests·RasterDomainTests·MergeKindTests :415-418〔IOP〕
  / MertensProvenanceTests :596〔Library〕/ FusionPerfProbeTests :722
  〔Export〕/ MergeUITests :815〔App〕；:97 WebP package 行）
- `App/Sources/Lightamer/UI/SessionBrowserView.swift`（onHDRMerge :55 /
  onHDRMertens :62 / 菜单 gate :158-185 / 触发 :339/:366）
- `App/Sources/Lightamer/UI/ContentView.swift`（:461-464 onHDRMertens 穿线
  ——minor-1 正本）
- `App/Sources/Lightamer/Session/SessionCoordinator.swift`（mertensMerge
  Handler :131）；`App/Sources/Lightamer/UI/LightamerApp.swift`（mertens
  接线 :931-955、MergeKind 局部 :959）
- `Resources/Localizable.xcstrings`（browser_menu_focus_stack 块 ≈:1296）
- `Scripts/test-direct.sh`（RSS_LIMIT_MB=8192 :70 / MEMFAIL :34）
- `.work/config.toml [gsd]`（dual_acceptance=true / paused=false / auto=true）
- `.work/GOAL-STATE.md`（M5 续接点 :19-23——M5-2 closed / 3538 拼表 / 3539
  修复后基线 / Mertens 探针 172.24s@100MP×5 + 6248MB）
- `.work/LESSONS.md`（L072 :743 / L075 :760 / **L077 :799-830——panorama 族
  点名适用**）
- `.work/gsd/REQUIREMENTS.md`（IOP-PANO-01 :374）
- `.work/gsd/phases/m5-2-mertens/M5-2-VALIDATION.md`（:20-22 基线 / :32 七
  bundle 逐行 RSS / :33 对账链 / :68 回归法）
- `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（IOPP =
  Parity/Golden 域模式 :13；IOP/Library/Export/App 显式行）
- `/Volumes/UNITEK/Documents/Development/lumen-raw/lumen/merge.py`（:12
  PANORAMA_MAX_PIXELS / :25-27 small INTER_AREA / :62 RANSAC 3px+3000 /
  :100-117 inner_crop / :192-202 bounded_rois / :205-211 spherical_map /
  :213-289 panorama 全段〔:215 预览 / :217-220 SIFT+RNG 注记 / :223-238
  匹配建图连通性 / :239-247 相机+BA+wave / :249-257 尺度回投+帽 / :259-273
  增益 / :274-289 tile 融合〕/ :293-315 merge_images）

## 结论

**PASS / 0 error + 5 minor**。三 plan 规格与七项生效值、源码现状、Lumen MIT
正本三方对表闭合；file:line 锚全部亲核无虚指；「四处穷举 switch」「3539
基线」「+77..100 估数」「bundle 分账」「typed 三态契约链」五个高.assert
主张逐点验真。五处 minor = 穿线登记（minor-1）/ 跨 plan 编码缝（minor-2）/
落盘容器策略 hedge（minor-3）/ grep 门硬化（minor-4）/ L077 runbook
（minor-5），处方随条、不阻断派发（建议 orchestrator 派发前一笔勘误，或
各 plan 执行批 T 收口随手吸收 + DECISIONS 落字）。

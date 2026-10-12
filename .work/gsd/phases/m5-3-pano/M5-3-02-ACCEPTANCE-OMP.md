# M5-3-02-ACCEPTANCE-OMP — omp 二次验收报告（独立第二遍）

> 结论头：**FAIL / 1 error + 4 minor**
> 验收员 = omp（zcode 首验 PASS / 1E 已修之后，独立串行第二遍）。
> HEAD = `b59c03c`（首验收口提交；验收批 `7ece3d3` 在内）。
> 五步程序逐项独立执行，不轻信首验数字与结论。

---

## 一、亲跑对表（两 bundle 独立复跑，exit 0 全绿）

| bundle | 本轮（亲跑） | 首验 | 申报 | 对表 | peak RSS | MEMFAIL |
|---|---|---|---|---|---|---|
| IOP | **683/1/0**（440s） | 683/1/0（443s） | 682/1/0 | ✓ 与首验逐位一致（+1 系第 11 腿法账面漂移，见首验 m-b） | 7202MB | 0 |
| Export | **353/4/0**（204s） | 353/4/0（200s） | 353/4/0 | ✓ 逐位 | 6053MB | 0 |

- 命令：`caffeinate -dis Scripts/test-direct.sh --bundle IOP` / `--bundle Export`（直启宿主，尾行 `OK (direct launch, no testmanagerd)` 两束亲见）。
- skip 亲查：IOP 1（QuickLook 探针类）/ Export 4（Mertens 探针 + pano 探针两法 + QuickLook 探针），与首验口径一致。
- 法数亲核：`grep -c "func test"` = Warp 8 / Gain 13 / Crop 10 / Leg 11 / Probe 2 / MergeKind 7（stub 退役后），与首验 §一一致；全仓 `3627`（含 App 域 4 法，首验 3623 系 Core 拼表口径，口径差非分歧）。

## 二、数学抽查（三项独立复算，uv/Python 零共享代码，全 PASS）

- **OMP-1 前向互逆**：Swift 约定（后向 `R·ray` 列约定 / 前向 `Rᵀ·cam`）逐式复刻，500 随机点 roundtrip 最大误差 **2.97e-13 px** ✓（精确逆成立；与产线测试 ≤1e-2 px 钉同向，余量 10 个量级）。
- **OMP-2 boundedCanvas 收缩**：`scale *= sqrt(cap/area)·0.998` 下单轮面积恒落 `cap×0.998²`（2.5e8/1e9/4e9 三初值亲算逐位），≤8 轮恒够 ✓（DECISIONS §6.3「8 轮不达臂实践不可达」申报成立）。
- **OMP-3 中位 log 方程 + dgelsd 语义**：连通三图链求解恢复真值 **4.75e-4**（融合后三源亮度全对齐 1.1052/1.1056/1.1054 ✓ 补偿方向正确）；不连通分量 min-norm 解 = 0 → 增益恒 1 ✓；正规方程 rank 2/3 奇异前提亲证 ✓（checker O2 选型依据成立）；clip 天花板 e^0.5 = 1.648721 ✓。
  - 诚实登记：首轮观测符号写反（`t_i−t_j` 误作 `t_j−t_i`，|Δ| 0.5）= 脚本自身 bug，修正后过。与首验 M4「脚本 bug 反证产线守卫」同款。
- **附加（转置族独立复核）**：同 R 下 Lumen `rays@r` vs Swift `R·ray` 发散 0.256，而 `Rᵀ·ray == rays@r` 逐位 ✓——首验 §四 M5「转置族吸收于约定差」复核成立，PanoWarp 头注 `row form verbatim` 措辞问题属实（cosmetic，见 m-omp-3）。

## 三、文档核对（SUMMARY/DECISIONS/perf.md 三 pass）

- **双 pass 分离**：`panoValidMask`（StackMergeService.swift:1287）全文零 staged 读、零像素值依赖，纯几何亲证 ✓；`panoFeatherAlpha`（:1269）参数仅 (mx, my, 源尺寸)，与 merge.py:279-281 逐式一致 ✓；`panoFuseRows`（:1346）`accum/weight` + `clip(accum/max(weight,1e-8),0,1)` + alpha 恒 1，与 merge.py:274-288 逐式对齐 ✓；确定性顺序（tile 行主序 + 源 index 序）在码 ✓。
- **196MP 探针**：perf.md 批准轮（196MP 画布 / 几何 183.8s / 融合+流写 895.4s / ru_maxrss 3814MB / footprint 峰值 6757MB / +242MB/band 残余）与 SUMMARY 生产腿证据节逐值一致 ✓；探针几何（6144×4608×8 / 10° yaw / f=30k）经本报告独立复算得画布 **42774×4599 = 196.7MP** ✓ 与 perf.md 逐位吻合。
- **E-1 修复**：`7ece3d3` diff 亲读 = 诊断臂 `firstIndex(of:)` → `enumerated()` 索引迭代 2 行，零行为变化 ✓；破窗亲证（`06cb9dc` 版 :273 含 `firstIndex(of:)`，`613c8ad` 引入）✓；pano 域 `firstIndex(of:)` 全仓 sweep 零残留 ✓。
- **红线机检**（亲跑）：IOP/Sidecar/Export/Graph/`*.metal`/Pipe/History/ExifPrecheck 八路 diff 全 0 行 ✓；Project.swift diff = 5 行测试登记，dependencies 零命中 ✓；Pano 源+测 RNG grep exit 1 ✓；`writeFloatTIFF` 本体零 diff（BandStreamer diff 纯 +308 行 additive）✓；腿体删除行仅 13 行（stub 体 + landStackProduct 旧写段 + readPixelRow 并行格式 2 行）✓。

## 四、读码抽查（六项）

1. **E-1 编译破修复** ✓（见 §三）：`enumerated()` 索引与 `firstIndex(of:)` 在互异元素下恒等，零行为变化成立。
2. **LUT staticSampleMask 单源化兜底** ✓：Mertens 腿 LUT 段（:1650-1672）改走 `MertensFusion.staticSampleMask`（merge.py:146 `static<64 → 全格 static` fallback 在 :368-371）+ 注释写明替换的内联走查无 fallback（全 motion 掩码 = percentile 前置 crash / 近全 motion = 静默发散）✓。**但注意**：该修复落点 = **Mertens 腿**（`runMertensLeg`），非 pano 腿；属 M5-3-02 T5 探针事故顺手修复的既有腿缺陷，M5-2-02 验收未覆盖。回归面 = 本轮 IOP 683 全绿中的 Mertens 全族 ✓。
3. **StagedSet.readRows** ✓：双变体重（`into` 复用版 grown-once + 返回值版），界外零填充 + 行数守卫 + `bytesPerRow` per-source 步长（KD-10 混尺寸合法面）✓；`into` 版 filled 前缀语义与 fuse 端 `span.count` 守卫配对 ✓。附带发现：`readPixelRow` 首行并行格式（:2883 两语句同行）= T4 批附带 whitespace 漂移，cosmetic（m-omp-4）。
4. **rowProvider additive nil 零漂移** ✓：`landStackProduct`（:2600）nil 臂 = 原 `writeFloatTIFF` 调用逐字保留（diff 删除 4 行 = 被 if/else 包裹的原调用，原样落 else 臂 :2617-2621）✓；非 nil 臂 band 尺寸 guard + `FloatTIFFWriter` 流写 ✓；既有六 kind 全走 nil 臂由 IOP 683 全绿亲证 ✓。
5. **手写 strip TIFF** ✓：II 头 + 8B 占位回填 + 14 tag 升序 IFD（256/257/258/259=1/262=2/273/277=4/278/279/284/305/338=1/339=[3×4]/34675，单 strip 内联/多 strip 外置双臂）+ RowsPerStrip 契约（首 strip 行数 + 仅末可短，finish 校验）+ 4GiB classic 门 + 同目录原子晋升 never-overwrite + deinit 未 finish 清理 ✓；`precondition(ifd.count == ifdSize)` 版式钉 ✓。
6. **sRGB ICC** ✓：`colorSpace.copyICCData()` 经 tag 34675 UNDEFINED 型嵌入，pano 腿传 `CGColorSpace.sRGB`（Mertens T2 同参）✓；产物重导入 resolve `.srgbPiecewise/.displayReferred` 由 happy-path 测试真链（RAWDecoder）亲证 ✓。

## 五、ERROR（1）：panoFuseRows band-span X 守卫漏 originX——左半画布必杀带

- **位置**：`StackMergeService.panoFuseRows` band-span 段（:1364-1369）：
  ```swift
  guard roi.x + roi.width > cropX0, roi.x < cropX1,   // ← X 双侧漏 originX
        roi.y + roi.height > canvas.originY + firstRow,
        roi.y < canvas.originY + firstRow + rowCount  // ← Y 双侧正确带 originY
  ```
  同文件六处同名 ROI 相交守卫五处带 origin（pass1 :1301-1304、tile 段 :1420-1423 均为 `canvas.originX + tile` 四侧全帧），**仅 band-span X 双侧漏**——孤立笔误形态，坐标帧混用（angle·scale 帧 ROI 值 vs canvas 帧 crop 阈）。
- **机理（严格证明）**：记 ox = originX。误跳 ⟺ 守卫判跳 ∧ 正确判留。ox<0 时左杀带 = `(ox+cropX0, cropX0]`（宽 |ox|）；ox>0 时右杀带 = `[cropX1, ox+cropX1)`（宽 ox）。杀带宽度 = |ox|，与符号无关——不是"ox>0 才触发"，**ox≠0 即有杀带**。
- **探针几何定量（独立复算）**：6144×4608×8 / 10° yaw / f=30k → ox = **−21387**，杀带 = (−21387, 0] 宽 21387px；src5/6/7 右缘 −4793/−10029/−15265 落带内 → **3/8 源 band-span 全 band 误跳**（span.count = 0 → tile 段 :1418 `guard span.count > 0` 连跳，**整源贡献静默丢失**，融合输出在这些源的独占覆盖区退化为黑/余源均值）。
- **后果链**：
  1. perf.md 批准轮 196MP 融合产物 = **5/8 源融合**（数值上仍是"真产线直驱"的墙钟/ru_maxrss，但融合语义非全源——NO GATE 项，预算结论方向不受影响，见 m-omp-1 联动）。
  2. pass1/pass2 一致性破：pass1（守卫正确）valid 掩码含被误跳源的独占区 → crop 覆盖这些列 → pass2 该列 weight = 0 → 输出黑列/黑块。不是"读边界不影响位值"（DECISIONS §5 的论证前提是联合 span ⊇ 每 tile span——**被整源跳过时该前提对该源空洞化**）。
  3. 触发频率：杀带宽 = |ox|；全景左半画布天然宽杀带（ox = 全局最小 ROI 左缘恒 ≤0，典型 −10⁴ 量级）→ **生产高频触发**，非角落。
- **测试盲区机理**：PanoLeg fixture（720×520×3 / ±10°）ox = −399，杀带 (−399,0]，三源右缘 399/312/225 全 >0 → 零命中；G3②/two-pass 测试（120×90 / ±6°）ox = −68，杀带 (−68,0]，两源右缘 68/43 全 >0 → 零命中。**对称小几何 + 右缘>0 = 系统性盲区**，与 fixture 同构——故三测试族全绿而缺陷存活。
- **修复处方**（一行，零行为面外溢）：X 双侧补 `canvas.originX`：
  ```swift
  guard roi.x + roi.width > canvas.originX + cropX0, roi.x < canvas.originX + cropX1,
  ```
  并补一回归法：非对称几何（任一源 ROI 右缘 ≤ cropX0 的 angle 帧坐标）下该源独占列融合值 == 自身色（`span.count > 0` 断言 + 端到端色值断言双钉）。
- **与首验的分歧点**：首验 §三审计了联合 span ⊇ tile span 的位值不变性与陈旧尾 guard，但未核 band-span 守卫自身的坐标帧——该守卫是"读边界"的前提而非读边界本身，漏检。本 error 为 omp 二验独立发现，首验 PASS 结论的前置条件不成立。

## 六、MINOR（4）

- **m-omp-1（provenance 联动，NO GATE）**：perf.md 批准轮融合段（895.4s / 193MP / 0.2MPx/s / 产物 3.1GB / footprint 6.8GB）在 E-omp-1 下产自 5/8 源融合——墙钟量级结论（CPU 预算未被证伪）方向成立（8 源全融合只增 ~1.6× 融合段墙钟，仍 15 分钟级；内存账 valid 掩码/accum/条带与源数线性无关或弱关），但**融合语义数字（fused-mpx/吞吐/产物字节）不可引用为全源融合基线**。E-omp-1 修复后是否重跑探针 = orchestrator 决策项（~18min/Δ磁盘 ~7GB，现 free 充裕；首验 m-f 的 HEAD 不可复原 caveat 同适用）。
- **m-omp-2（账面，首验 m-a 复核确认）**：BUNDLE-MAP `IOP 14 PanoGainTests`（实 13）+ `EXPORT 1 PanoFusionPerfProbeTests`（实 2）两处错记亲证 ✓；另 `M5-3-02` 增行注释落款「2026-10-09 执行期」实为 10-13 批——日期笔误，同 m-a 修。
- **m-omp-3（cosmetic，首验 m-d 复核确认）**：PanoWarp 头注「the Lumen row form verbatim」指标级不精确（转置族吸收于约定差，本报告 §二附加复核成立）✓；数学正确性不受影响。
- **m-omp-4（cosmetic，新发现）**：`readPixelRow` 首行并行格式（:2883 `{` 后同行续语句）= T4 批附带 whitespace 漂移；行为零影响，随 E-omp-1 修复批顺手换行。

## 七、与首验分歧点汇总

| # | 首验 | omp 二验 | 裁决 |
|---|---|---|---|
| 1 | PASS（§三：联合 span 位值不变性成立） | **FAIL**：band-span X 守卫漏 originX，探针几何 3/8 源整源误跳——§三论证前提对被跳源空洞化 | **实质分歧**：首验漏检坐标帧，E-omp-1 为 error |
| 2 | m-f：探针数字 provenance caveat（被覆写二进制） | 同意 + 追加 m-omp-1：即使二进制新鲜，融合语义仍是 5/8 源——两 caveat 叠加 | 补充，非推翻 |
| 3 | m-a/m-b/m-c/m-d | m-a/m-b/m-d 复核确认；m-c 同意（时序粒度） | 一致 |
| 4 | §六 LUT 兜底未单列 | §四-2 明确落点 = Mertens 腿（跨腿顺手修复），回归面 = IOP 全绿 Mertens 族 | 补充说明 |

## 八、验收程序自检

- [x] 读 ACCEPTANCE + DECISIONS §1-§6 + PLAN（checker 回注 ①-⑤落点：§3 容器/§5 L077+源尺寸/O2 dgelsd/minor-2 encoded 缝——DECISIONS §6.1 申报亲核在码）+ perf.md
- [x] 定向复跑 IOP 683/1/0 + Export 353/4/0（对表首验逐位）
- [x] 数学抽查三项独立复算（互逆 2.97e-13 / 收缩单轮必收 / 方程 4.75e-4 + min-norm + 奇异 + 天花板）+ 转置族复核
- [x] 文档核对（双 pass 分离 / 196MP 探针逐值 / E-1 修复 diff / 红线八路零 diff）
- [x] 读码抽查六项（E-1 / LUT 兜底 / readRows / rowProvider / strip TIFF / sRGB ICC）
- [x] E-omp-1 证据链：源码行 + 六守卫并列 + 严格证明 + 探针/fixture/G3②三几何定量 + 测试盲区机理 + 修复处方

**修复后重验门**：E-omp-1 一行修复 + 非对称几何回归法 → 定向 IOP 轮重跑（683→684 预期）→ omp 对修复批增量复验（守卫行 + 回归法 + 复跑尾行），不重走全程序。

OMP-VERDICT: FAIL

---

## 复验（修复后）

> 修复批 = E-omp-1 一行修复 + m-omp-4 顺手换行 + 非对称几何回归法 +
> probe 参与门 PERF 行 + perf.md 重测节。程序按 §八重验门四步，不重走
> 全程序。复验日期 2026-10-13。

### ① 守卫行（增量 diff 亲核）

`StackMergeService.panoFuseRows` band-span 段（修复后 :1371-1374）：

```swift
guard roi.x + roi.width > canvas.originX + cropX0,
      roi.x < canvas.originX + cropX1,
      roi.y + roi.height > canvas.originY + firstRow,
      roi.y < canvas.originY + firstRow + rowCount
```

X 双侧补 `canvas.originX`，与本函数 tile 段（:1426-1429）及 pass1
（:1301-1304）四侧全帧同构；全文件 ROI 相交守卫 sweep 三处全部带
origin，无第二处漏帧。附带 m-omp-4：`readPixelRow` 首行并行语句换行
（:2889，whitespace，零行为）。生产面 diff 合计 7 行（守卫 6 + 换行 1）。

### ② 非对称几何回归法（`testFuseRowsBandSpanGuardAsymmetricOriginX`，IOP bundle）

- **几何**：双源 720×520 / f=800 / yaw ±10° → originX = **−478**（画布
  956×503）。左源（yaw +10°）world x [−478, 199)、local [0, 677)；右源
  （yaw −10°）world x [−199, 478)、local [279, 956)。关键非对称性：
  左源**独占区**（local [0, 279)）横跨其 world 右缘 199——修复前杀带
  （world 右缘 ≤ cropX0 即杀，即 cropX0 ∈ [199, 677) 带内必杀）与
  独占列相交，守卫差异对输出可见。既有对称 fixture（±6° f=120 →
  ox=−68、右缘全正）结构性盲区由此破除。
- **腿 1（边界交叠）**：band 窗 local x [239, 269)——起点在左源 world
  右缘 199 之右（杀带内）、终点在右源 local 左缘 279 之前（全列左源
  独占单覆盖）。断言：中带行全列 == 左源自身色 0.3（`span.count > 0`
  链的端到端钉——被跳源列 black：weight 0 → `max(weight,1e-8)` 归一
  出 0）。**修复前红：30/30 列断言失败（实测 0.0）**。
- **腿 2（不相交）**：band 窗 local x [697, 757)——起点在左源 local
  右缘 677 之右（真不相交，修复后守卫必须仍跳过），仅右源覆盖。
  断言：全列 == 右源自身色 0.7（钉「修复不误纳不相交源」+ 左源零
  贡献）。**修复前红：60/60 列断言失败**——修复前 buggy 比较把右源
  也杀了（右源 world 右缘 478 ≤ 697 = cropX0），整窗黑。
- 红绿证据：修复前过滤轮 `1 executed, 90 failures`（30+60 两腿全红）
  → 修复后同轮 `1 executed, 0 failures`。回归法 +1 = §③ 683→684。

### ③ 定向 IOP 轮重跑

**684/1/0**（peakRSS 7298MB，426s，exit 0，`OK (direct launch, no
testmanagerd)` 尾行亲见）——683 + 1 = 684 精确命中（新增回归法），
零连带破。skip 1 = QuickLook 探针类（口径同首验）。

### ④ probe 复跑对账（同协议双跑，8 源全参与门）

probe 增设参与门 PERF 行（probe 侧以融合同一 rois+crop 复算守卫谓词，
零重实现）。同协议 = Debug 直启宿主 + `/usr/bin/time -l` ru_maxrss
机检 + probe 自带 10GB 磁盘预检，双跑：

| 门/段 | R1 | R2 | 批准轮（5/8） |
|---|---|---|---|
| **参与门** | **8/8**（sources=0..7） | **8/8** | （未测；§五复算 = 5/8） |
| 画布/crop | 42774×4599 / [42,42] 42732×4536 | 逐位同 R1 | 逐位同 |
| 融合+流写 | 1630.9s / 0.1 MPx/s | 1634.1s / 0.1 MPx/s（双跑 ±0.2%） | 895.4s / 0.2 MPx/s |
| 产物字节 | 3 101 321 140 | 3 101 321 140 | 3 101 321 140（逐位同，crop 决定） |
| ru_maxrss | **5033MB**（8G 门内） | **5653MB**（8G 门内） | 3814MB |
| exit | 0（1 test, 0 failures，1870.4s） | 0（1 test, 0 failures，1870.1s） | 0 |

**裁决回翻判定**：参与门 8/8 ≥ 6/8——§五「3/8 源误跳」定量经修复后
直测证实（修复前 5/8 参与、修复后 8/8 参与，杀带 src5/6/7 复活），
m-omp-1 的 provenance caveat 解除：perf.md「修复批重测轮」节为全源
基线正本（融合 1.82× 墙钟 = 3 补回源的 span 读 + gather 增量，CPU
预算结论方向不变，NO GATE 维持关闭）。

OMP-REVERDICT: PASS（1 error 修复亲证：守卫行 ① + 回归法红绿 ② +
684 重跑 ③ + 8/8 双跑 ④）

# M5-3-02 ACCEPTANCE — 全景生产腿批（wave 2）独立验收记录

> **双重验收制度**（config `dual_acceptance = true`）：本文件 = 两路结论正本。
> **第一路 = zcode 独立验收（本文件 §一..§八，2026-10-13 凌晨）：PASS / 1 error（当场修复闭环 `7ece3d3`）+ 5 minor**。
> 第二路 = omp 二次验收（orchestrator 串行派遣，严禁并发；结论落 §九）。

---

## 一、亲跑对表（两 bundle，HEAD 新鲜构建，独立复跑，exit 0 全绿）

| bundle | 本轮（亲跑） | 申报 | 对表 | peak RSS | MEMFAIL |
|---|---|---|---|---|---|
| IOP | **683/1/0**（443s） | 682/1/0 | **+1**（见 E-1/m-b：第 11 腿测试与收口 docs 同 commit 落地，申报数字陈旧；683 = 642+42新−1 stub，全绿） | 7011MB | 0 |
| Export | **353/4/0**（200s） | 353/4/0 | ✓ 逐位 | 5961MB | 0 |

- **构建新鲜度亲证**：执行方收口后 HEAD 的 Export bundle **编译破**（E-1，§二）——亲跑前先 `fix(M5-3-02)`（`7ece3d3`）+ 全量 `xcodebuild build-for-testing`（TEST BUILD SUCCEEDED）再跑；两二进制 mtime（04:29:47）晚于全部源文件；`strings` 亲证 IOP 二进制含 `testTwoPassCropEqualsNaiveFullCanvasFusion`（收口提交新法）。
- **skip 亲查明细**：IOP 1 skip / Export 4 skip（Mertens 探针 + pano 探针两法 + QuickLook 探针——env 门逐条 skipped 行亲读）。基线 Export 非 pano skip 实为 2（Mertens+QuickLook）+ 本批 pano 探针 2 = 4 ✓ 内部自洽。
- **法数对账亲证**：`grep -c "func test"` = Warp 8 / Gain 13 / Crop 10 / Leg 11 / Probe 2 / MergeKind 7（stub 退役后），与 BUNDLE-MAP 增行对照见 m-a（两处错记）。HEAD 全局对账 = 3582 + 42 − 1 = **3623** ✓（执行方总数口径正确）。
- 亲跑命令：`caffeinate -dis Scripts/test-direct.sh --bundle IOP` / `--bundle Export`（直启宿主，尾行 `OK (direct launch, no testmanagerd)` 两束亲见）。

## 二、E-1（error，当场修复闭环）：收口态 HEAD 的 Export bundle 编译破

- **发现**：`xcodebuild build-for-testing`（基 f5b56b7..06cb9dc）exit 65——`Tests/LightamerTests/PanoFusionPerfProbeTests.swift:273` `geometries.firstIndex(of:)` 作用于 `[PanoSourceGeometry]`，元素不 conform `Equatable`，编译期必败。任何新 clone/重建无法产出 Export bundle。
- **逃逸机理**：该文件 env 门（`LIGHTAMER_PERF_PROBE=1` 否则 XCTSkip）——默认套件可见性为零，定向 IOP 轮不触；执行方收口 IOP 轮（682，dgzsvdww 二进制 04:14 含 11 法）跑通而 Export 目标从未以 committed 源构建成功；其申报 Export 轮（04:05 日志）跑在**被覆写前的旧二进制**上（351 非探针测试不依赖差异面 + 探针两法 skip，结果碰巧不敏感——但「收口轮 = HEAD 验证」的声明在该 bundle 上不成立）。
- **修复**：`7ece3d3` = 诊断臂改 `enumerated()` 索引迭代（元素互异，index 恒等，零行为变化）+ 全量重建 + 本节两 bundle 亲跑 = 回归证据。
- **波及面诚实登记**：perf.md 批准轮探针数字产自「修复已在、探针文件为编译破前版本」的被覆写二进制（时间线唯一自洽解），**不可在 HEAD 复原**；产线修复本体（band×源联合 span 读）已由 HEAD 全绿套件 + 双跑逐位亲证，唯 196MP 探针数字本身保留 provenance caveat（m-f，NO GATE——HEAD 重跑与否 = orchestrator 决策项）。

## 三、双 pass 分离审计（KD-5 内存红线本体，读码亲证）

- **pass 1 = `panoValidMask`（StackMergeService.swift:1287）**：逐 tile 逐源 `sphericalMap` → inside 门（`sx≥0 ∧ sy≥0 ∧ sx≤Float(w−1) ∧ sy≤Float(h−1)`）→ UInt8 1B/px。**全文零 staged 读、零像素值依赖**——纯几何亲证（只有地图坐标与源尺寸）。
- **纯几何依据（DECISIONS §4）读码成立**：weight = Σ `panoFeatherAlpha`，而 `panoFeatherAlpha`（:1269）= `clip(edge/(min(ih,iw)×0.12), 0.001, 1) × inside`，参数仅 (mx, my, source 尺寸)——merge.py:279-281 直译逐式对照一致。valid=weight>0 恒式的数学前提在码。
- **pass 2 = `panoFuseRows`（:1346）**：band×源联合 span 读（64×64 strided 采样 + ±128 pad，grown-once 条带）→ 512px tile 走查 → 双线性 gather（clamp = BORDER_REPLICATE 语义）→ `accum += warped×(α·gain)` / `weight += α` → `clip(accum/max(weight,1e-8), 0, 1)`、alpha 恒 1（OQ-5）——与 merge.py:274-288 逐式对齐亲证；确定性顺序（tile 行主序 + 源 index 序）在码（G1 锚）。
- **valid=weight>0 行对行亲证（G3②）**：`testFusedRowsWeightNormalizationProfile` 双恒色源端到端（单覆盖=自身色/深叠=均值）+ 逐行 covered==validCount 断言在码（PanoLegTests:617-624）+ 本轮亲跑绿。
- **联合 span ⊇ 每 tile span 的位值不变性**：gather 只读 inside 邻域；陈旧尾防御 guard（`row1+c1+3 ≥ span.count → skip`）= 诚实降级（hit 时该像素 weight=0 → 黑点，属已登记结构性风险；测试尺度 + 探针尺度均未触发——双跑逐位 + two-pass==naive 逐位钉）。
- **两 pass 输出逐位等价钉（KD-5 正确性门）**：`testTwoPassCropEqualsNaiveFullCanvasFusion`（裁切窗融合 == 全画布融合后裁切，bitPattern 逐通道断言）在码 + 亲跑绿。

## 四、数学审计（Warp/Gain/Crop 逐式对照 + numpy 独立复算 5/5 PASS）

- **sphericalMap vs Lumen（merge.py:205-211）**：u/v 射线构造（sinv·sinu, −cosv, sinv·cosu）、z>1e-6 有效门、−1 无效标记、Float32 结果域——逐式一致 ✓。**旋转 application 指标级 ≠ Lumen 行式**：Lumen `rays@r`（行向量 = Rᵀ·ray 列约定，其 R = OpenCV cam→world）vs Swift `R·ray`（列约定，其 R = PanoCamera world→cam）——**numpy M5 复算亲证同 R 矩阵下两式发散（max|Δ| 230/705 px，互为转置族）**；Swift 正确性锚 = 自身约定自洽（BA 残差 Rᵀ·u₁−Rᵀ·u₂ 世界侧显式钉「R·u 属转置族」PanoCamera 头注：29-30 + 波 1 G2 golden 定向恢复 + 波 2 happy-path 全链真纹理事愈合成）——数学正确，头注「row form verbatim」措辞指标级不精确（m-d，cosmetic）。
- **projectToCanvas 前向互逆**：cam_ray = ((x−cx)/f, (y−cy)/f, 1) → world = Rᵀ·cam → (atan2, acos)·scale——sphericalMap z>0 支上的精确逆（测试 :123 逐点 ≤1e-2 px 钉 + 亲跑绿）。
- **boundedCanvas（merge.py:192-202 直译）**：≤8 轮、`scale *= sqrt(cap/(w·h))·0.998`、w·h≤200MP 收、零面积/非有限 → typed `FailurePrefix.canvas` 词汇——逐式一致 ✓；ROI = 全边框走查 floor/ceil 保守 ✓。
- **PanoGain（merge.py:255-273 直译）**：≤900px round() 采样画布 / ≥80 样本门 / (0.04,0.9) 开区间双值门 / 方程 `g_i−g_j = median(log(J_j/J_i))` / 锚行权重 10 值 0 / `exp(clip(±0.5))` / 参考帧增益 1——逐式一致 ✓。**dgelsd 最小范数（checker O2）**：14 参 LAPACK 签名 + lwork=−1 查询（iwork[0] 回读）+ 查询后 fresh operands 重装——读码正确。
- **numpy 独立复算（脚本 /tmp/m5302_gain_audit.py，与产线零共享代码）**：M1 方程语义补偿方向恢复（exp 解 == 1/truth，1e-9）✓；M2 不连通分量 min-norm 解 = 0 → 增益恒 1 ✓；M3 正规方程奇异前提亲证（rank 2/3）✓；M4 clip 天花板 e^0.5=1.6487 ✓（首轮 assert 方向写反 = 脚本自身 bug，修正后过——与波 1 同款「脚本 bug 反证产线守卫」诚实登记）；M5 转置族发散亲证（上述）。
- **PanoCrop（merge.py:100-117 直译）**：step = ceil(max/1024)、保守 min-pool（一格污染）、直方图栈（严格更大面积 tie-break + 严格 < 压栈守卫 + 哨兵 0）、空矩形 typed、`x0*step…min(w,x1*step)` 重标——与 Lumen 逐字对齐 ✓；naive O(N²M²) 参照同网格前缀和 + 同 tie-break（G3④ 五形状逐位 + 随机网格面积一致，亲跑绿）。

## 五、红线机检（亲跑命令，非转述）

```
git diff f5b56b7..HEAD -- LightamerIOP/                          → 0 行
git diff f5b56b7..HEAD -- LightamerCore/Sources/Sidecar/         → 0 行
git diff f5b56b7..HEAD -- LightamerCore/Sources/Export/          → 0 行
git diff f5b56b7..HEAD -- LightamerCore/Sources/Graph/           → 0 行
git diff f5b56b7..HEAD -- '*.metal'                              → 0 行
git diff f5b56b7..HEAD -- LightamerCore/Sources/Pipe/            → 0 行
git diff f5b56b7..HEAD -- LightamerCore/Sources/History/         → 0 行
git diff f5b56b7..HEAD -- '*ExifPrecheck.swift'                  → 0 行
Project.swift diff = 5 行测试登记（IOP 4 + Export 1），dependencies 零 diff
grep -rnE "SystemRandomNumberGenerator|srand|arc4random|\.random\(" Pano*.swift（源+测）
  → 0 命中（exit 1 = PASS）
sidecar schemaVersion → 零触（Sidecar/ 零 diff）；App/ 零触（runModal 门 n/a）
```

- **leg 体零 diff 精查**：diff 中 `func runHDRLeg/runMertensLeg/runFocusStackLeg/runStackAggregateLeg/func landStackProduct` 签名行零命中；`runStackAggregateLeg` 函数体 rowProvider 引用 = 0；既有六 kind 零回归由 IOP 683 全绿亲证（HDRMerge/MTB/Focus/Mertens 全族在轮）。
- **MIT 归属注记**：PanoWarp/PanoGain/PanoCrop 三文件头注齐备（merge.py:205-211/:192-202/:259-272/:100-117/:279-281 逐锚在注）。

## 六、additive / typed / 词汇核验（读码 + 测试点验）

- **StagedSet.readRows additive**：全宽行带无 shift 读 + `into` 复用变体（grown-once，返回 filled 前缀）+ 界外零填充；既有 `readShiftedPixels` 零改（diff 亲证仅新增）。
- **FloatTIFFWriter（手写 classic strip TIFF）**：II\* 头 + 8B 占位回填；14 tag 升序 IFD（256/257/258[32×4]/259=1/262=2/273/277=4/278/279/284/305/338=1/339=[3×4]/34675）+ ICC 经 `copyICCData`（sRGB）+ RowsPerStrip 契约（仅末 strip 可短，finish 校验）+ 4GiB classic 门 + 同目录原子晋升 never-overwrite（L009）+ deinit 未 finish 清理；`writeFloatTIFF` 本体零 diff 亲读在案；ImageIO 回读逐位 round-trip 测试在码 + 亲跑绿。
- **landStackProduct rowProvider 臂**：缺省 nil = `writeFloatTIFF` 全平面路径（六 kind 全轮绿 = 零漂移证人）+ 非 nil 带 band 尺寸 guard + async 签名（DECISIONS §6.5 申报）。
- **runPanoLeg 编排**：N∈2..32 腿级 guard（`decoded.count >= 2` + 上游 32 门）+ extent 门故意缺席注释在码（KD-10）+ 进度 = 特征 N + 链 1 + 画布 1 + 增益 1 + 融合 N（band-paced 预算递减 + band 不足补足）+ write/sidecar/settle——`done==total` 恒式测试亲跑绿；typed 三态词汇消费（alignment/disconnected/canvas 前缀）测试在码。
- **provenance 快照**：panoCanvas/panoGains/panoCrop + alignment 标签（reference/inliers=n 确定性）+ warnings（clip 触发）——happy path 测试逐字段断言 + 真 raster 重导入（RAWDecoder 链）resolve `.srgbPiecewise/.displayReferred` + ICC hash 非默认亲证。
- **stub 退役**：`PanoMergeKindTests` 仅删 stub 法 + 头注 MARK（diff 38 行亲读）；窗口恒式测试（2N+5 后 typed fail）保留原样 ✓；`MertensLegTests` 等既有测试零修改（全 Tests/ diff = 6 个 pano 文件亲证）。

## 七、逐 commit 边界（八提交 vs front-matter 亲核）

| commit | 任务 | stat 亲核 | 判定 |
|---|---|---|---|
| `ba2b2cc` | T1 | PanoWarp 318 + 测试 253 + Project +1 + MAP +8 | ✓ |
| `1daad17` | T2 | PanoGain 293 + 测试 348 + 登记 | ✓（MAP 记 14 错，m-a） |
| `b6332ba` | T3 | PanoCrop 186 + 测试 224 + 登记 | ✓ |
| `fa10355` | T4 | Service +620 / BandStreamer +299 / Leg 测试 576 / MergeKind 38 / 登记 | ✓（files_modified 外 MergeKind 申报在案，合理——腿体替换编译级连带） |
| `613c8ad` | T5 | Probe 392 + perf.md 65 + Service 修复 149 + BandStreamer 9 + 登记 | ✓ |
| `940a658` | T6 | G3② 两法 +111 + MAP 10 | ✓ |
| `06cb9dc` | T6 收口 | SUMMARY/DECISIONS/GOAL/TODO + **Leg 测试 +72（第 11 法）+ MAP 11** | ✓ 边界，但数字/m-a/m-b/m-c 三账面漂移同源 |
| `7ece3d3` | 验收批 | probe 修复 2 行（本波验收产物） | ✓ |

## 八、发现（1 error 已修闭环 + 5 minor）

- **E-1（error，已修）**：§二——HEAD Export bundle 编译破；`7ece3d3` 修复 + 重建 + 双 bundle 亲跑闭环。
- **m-a（账面）**：BUNDLE-MAP 两处法数错记——`IOP 14 PanoGainTests`（实 13）、`EXPORT 1 PanoFusionPerfProbeTests`（实 2，其 commit message 自述 2 法）。不触任何 run 数字（bundle 计数以宿主 executed 为准），随收口顺手订正即可。
- **m-b（账面）**：SUMMARY/GOAL-STATE「IOP 682/1/0」在含第 11 法的自身 commit 下即陈旧——HEAD 实为 **683/1/0**（本轮亲跑）；总数对账 3582+41=3623 恰好正确（42 新 −1 退役），唯 bundle 分解行（Warp 8/Gain 13/Crop 10/**Leg 10**）与 +41 自身不自洽（8+13+10+10−1=40≠41）。
- **m-c（时序粒度）**：第 11 腿测试落 docs 收口 commit（`06cb9dc`）——01 批 m-a/m-b 同款；且执行方 IOP 682 轮必然跑在末法入二进制之前（时间线反推），「收口轮」数字与 HEAD 终态隔一次未记录的重建。后续 additive 批：测试与收口 docs 分 commit 时，数字以 HEAD 重验为准。
- **m-d（cosmetic）**：PanoWarp 头注「the Lumen row form verbatim」指标级不精确（§四 M5：转置族吸收于约定差）；数学正确性不受影响。
- **m-f（provenance）**：perf.md 批准轮数字产自被覆写二进制（§二波及面）；NO GATE 项，HEAD 重跑（~18min/Δ磁盘 ~7GB，现 free 充裕）与否则于 orchestrator——production 修复本体已由 HEAD 全绿 + 双跑逐位亲证，不阻塞。
- 顺手订正（本批验收产物）：探针文件头注两行陈旧源尺寸（8192×6144/50MP → 6144×4608/28.3MP，doc-only）；`M5-3-CHECKER.md` 置信度公式行补 D-1 勘误注记（01 批 m-omp-1 遗留，本批兑现）。

## 九、omp 二次验收（占位，orchestrator 串行派遣后回填）

- [ ] omp 结论（PASS/FAIL + 证据）：**待派**。
- 两路 PASS → C 档第 2 停（战果汇报 + M5-3-03 摘要等用户确认）。

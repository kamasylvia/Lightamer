# Plan 05-06 Summary — nlmeans（IOP-DENOISE-02，v50 29.0，Lab）

**执行**：2026-09-22 夜间 subagent（ZCode executor）。**状态：完成**
（全套 543 tests / 3 skip / 0 fail；GUI 走查 PASS-with-GUI-13——并发崩溃
发现已立案，非本 plan 修复范围）。

## 任务完成表

| 任务 | commit | 验证数字 |
|---|---|---|
| T1 kernel 群直译 + threadgroup 滑窗 + 尺寸扫描 | `a61f746` | 扫描 {64,128,256,512} 全组合**逐字节一致**；平场恒等 <1e-4（实测 ~1e-6 级）；噪声 RMS-to-truth 降 0.8× 门；fast_mexp2f 位级复刻；IOPiece.pipeType stamp |
| T2 Goossens Python 参考 + 模块/注册/seed + 降载三件套 | `4abda0f` | 12 参考 EXR 生成（4 case × 3 fixture，float64）；K clamp 3 + decimate 28→14 偏移（481→57 趟）常量入测试 pin；seed DISABLED（D-05-06-T2-1）；V50 +1（29.0，colorin < nlmeans < colorchecker）；全套回归 543/3/0 |
| T3 golden 4×3 + 极限门 + tiling 承重双门 | `2663a2c` | parity **12/12 maxRel ≤ 5.7e-6**（门 1e-3）；strength 单调三档（0.0335→0.0141→0.0136 高频能量）+ 平场 s=0 恒等 <1e-4；luma=0：maxΔL 6.5e-4 vs rmsΔab 6.4；chroma=0：maxΔab 2.7e-3 vs rmsΔL 1.34（IOP-DENOISE-04 chroma 半边断言，05-08 引用）；分块==整幅 <1e-3（grid 20 tiles>1 证实）+ FULL footprint Δ352MB < 3GB（32MB 强制分块） |
| T4 dt 三证据 + manifest | `f3d36bb` | 4/4 `params v. 2: version ok params ok` + DB op_params hex == XMP blob **byte-identical**；平场探针 **max_dev = 0.0** 全平面（4/4，导出路径正常——无 05-05 BROKEN-route 附加条件）；manifest nlmeans 节落账 |
| T5 面板 + wiring + GUI 走查 + 轨 B + PERF | 本提交 | 面板 4 滑块 + zh/en catalog + Inspector zh 显示名；PanelWiring +2（dispatch + 拖动=1 commit + 归零还原 paramsHash 全 hit）；轨 B nlmeans 插链中性 6 patch 全过；PERF 两档 57.8ms / 430.9ms（7.5×）+ PREVIEW 全链 97.1ms → `.work/plans/05-06/perf.md` |

## 验收标准对照

- [x] kernel 群：扫描全组合一致 + blockSize=128 入 DECISIONS（D-05-06-T1-1）；
      L018 buffer 轮转（U2 float4 + 4 单通 bucket host 旋转，无 read_write RMW）
- [x] 轨 A：4×3 <1e-3（实测 ≤5.7e-6，真循环 compared>0 + 跨 fixture 非空转）
      + strength→∞/luma=0/strength=0 三门（方向口径，D-05-06-T2-1）
- [x] tiling 承重：分块==整幅 <1e-3（grid>1 断言，TilingPlan 同参纯函数）
      + FULL Δfootprint 352MB <3GB + K/P iscale 派生不随 tile 变（pin）
- [x] 预览降载三件套常量钉死（D-05-06-T2-2）+ D-C3 零改动接参数（已通用化）
      + 降载路径命中证据（57 趟 57.8ms vs 481 趟 430.9ms；GUI 拖动渲染跟随
      30069 px 变化量化）
- [x] dt 三证据 + manifest 节 + IOP-DENOISE-04 chroma 断言（05-08 引用）
- [x] 面板 + PanelWiring +2 + catalog + a11y identifier + GUI 走查（SC#4 首测数字）
- [x] 轨 B 双判据：`testTrackBNeutralityWithNLMeansInserted`（strength=0 插链
      中性 patch 6/6 + 水位保持——Lab a=b=0 锚定不破）；PERF 两档落 perf.md
- [x] 全 suite 绿：**543 tests / 3 skip / 0 fail**（基线 535 → +8）；ROI/iscale
      头注钉死（modifyROI 恒等 + scale 折算只用 roi.scale ÷ piece.iscale）

## 新增/改动文件

- `LightamerIOP/Sources/NLMeans/NLMeansKernels.metal`（六 kernel：lab_forward
  + dist/horiz/vert/accu/finish）
- `LightamerIOP/Sources/NLMeans/NLMeansModule.swift`（模块 + 引擎编排 + 派生）
- `LightamerCore/Sources/Pipe/IOPiece.swift` + `PixelPipe.swift`（pipeType stamp）
- `LightamerIOP/Sources/Registry.swift`（注册/prewarm ×6/seed DISABLED）
- `App/Sources/Lightamer/UI/Inspector/NLMeansPanelView.swift`（新）
- `App/Sources/Lightamer/UI/InspectorView.swift`（zh 显示名映射 +1）
- `App/Sources/Lightamer/State/InspectorState.swift`（provider 注册）
- `Resources/Localizable.xcstrings`（+7 键 zh/en）
- 测试：`NLMeansParityTests.swift`（11）、`IOPieceIscaleTests.swift`（+1）、
  `V50OrderTests.swift`（+1）、`PanelWiringTests.swift`（+2）、
  `MemoryBudgetTests.swift`（+1）、`PreviewChainPerfTests.swift`（+1）、
  `GeometryGoldenTests.swift`（+1 轨 B）
- golden：gen_fixtures.py nlmeans 段（fast_mexp2f 位级 + Goossens float64 全链
  + 4 case XMP blob 配方）；12 参考 EXR 本地生成（.gitignore 惯例不入库）

## 遗留 / 风险

1. **GUI-13（高，05-08 前必修）**：启用 commit + 立即拖动 tick 并发 →
   `ModuleBox.setParams` Data over-release SIGABRT（D-05-06-T5-2；栈无
   nlmeans 帧，D-H1 通用竞态）。settle 后不复现；SC#4 签核前 coordinator
   侧串行化。
2. **GUI-12（中，沿用）**：模块列表 28 行把面板体挤出可视区——nlmeans 面板
   AX 径可达但不可见，随 moduleList 滚动约束同修。
3. PERF 正式 60fps 门在 05-08（Release + GUI 实测）；本轮 Debug 数字已证
   降载杠杆 7.5× 与降载路径命中。
4. 性能未调优面：每偏移 4 个独立 command buffer commit（480 commit @满血）
   ——dispatch 批合并（PERF-5 杠杆①）在 05-07/05-08 兑现时对本 kernel 群
   收益最大（481 趟摊薄 encoder 开销）。
5. workgroup 64/128/256/512 正确性全等但性能未扫（夜间不做性能定值；
   dt 双维独立 opt 同留 PERF 轮）。

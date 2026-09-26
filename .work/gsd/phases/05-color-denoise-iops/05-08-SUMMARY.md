# Plan 05-08 Summary — bilateral/surface blur + defer 决议 + Phase 5 签核

**执行**：2026-09-23 夜间 subagent（ZCode executor）。**状态：完成——Phase 5 签核**
（终轮全 suite **609 tests / 3 skip / 0 fail**（touch Tests + build-for-testing 重编复跑防增量吞测试更新）；
05-VALIDATION `status: validated` + `nyquist_compliant: true`）。

## 任务完成表

| 任务 | commit | 验证数字 |
|---|---|---|
| T1 直连档 + 模块 + σ 折算逐行核 + 注册/seed | T1 commit（`feat(bilateral): T1…`） | `_compute_sigmas` 逐行对照表（D-05-08-T1-1，Med confidence 钉死：σs=radius×roi.scale/iscale 裸式无 clamp）；leg 路径切换钉参（rad 5/6 直连、7/8 grid、σ<0.1 恒等、thumbnail 跳直连、rad 收缩）；直连 vs 精确公式 **8e-7**（门 1e-5）；σ→0 恒等逐字节；V50Order +1（9.0<10.0<21.0）；seed DISABLED（D-05-08-T1-3：radius MIN 1.0 无零参恒等，plan 中性 seed 前件不成立） |
| T2 5D grid 档 + OQ7 定稿 | T2 commit（`feat(bilateral): T2…`） | 稠密 5D 网格（pentalinear 32 角原子散射 + blur x/y + slice val/w）；网格档 vs 同算法 float64 参考 **8.6e-7**（门 1e-3）；近似包络测量 vs 精确公式 maxAbs 0.013-0.021（<0.05 回归界，cell=σ 粒度固有——dt lattice 同族，D-05-08-T2-2）；确定性 <1e-6；**分块==整幅 4.5e-7**（grid>1）；**OQ7 定稿**（D-05-08-T2-1）：grid_bytes=Π cells×16B、预算 1.5GB、100MP 默认放粗 ×9.23→1.47GB、回落=TilingPlan 分块（摊销 B/px=32+grid/plane px，dt maxbuf 对应物）、UI 软上限拒绝 |
| T3 golden 3×3 + 极限门 + dt 三证据 | T3 commit（`feat(bilateral): T3…`） | 9 参考 EXR + sha256 总账；golden parity **9/9 全部 <1e-6**；dt-cli 采纳 **3/3**（loader + params v.1 ok + DB hex==blob 20B）；平场探针 direct=0.0 / boundary 内区 0.0 / grid_large dt lattice 上游垃圾已记录；delta 脉冲响应剖面（远场逐位回平场） |
| T4 面板 + defer 决议 | T4 commit（`feat(bilateral): T4…`） | BilateralPanelView 4 滑块（dt soft range：radius 1-30、σ 0.0001-0.1@4 位）+ D-H1 三件套 + catalog 8 keys + Inspector zh 名同轮；PanelWiring **54/54**（+2：dispatch + 拖动恰 1 commit + 复位还原 pristine hash + GUI-7 auto-enable）；**IOP-DENOISE-04 defer 决议**（D-05-08-T4-1：chromatic 已交付（05-06/05-07 承载）/ hotpixels+dark-frame 正式 defer（Bayer 域+CIRAW 无 despeckle 双证据）/ cacorrect 维持 defer 与 Phase 6 无关） |
| T5 sidecar 11 op + 轨 B 全链 | T5 commit（`feat(phase5): T5…`） | Phase5SidecarTests **12/12**（11 op 非默认 params JSON round-trip + registry 物化 + 未知 op 降级复核）；GeometryGolden track B 扩链（+nlmeans/bilateral disabled）= **Phase 3+4+5 全模块**（Phase 6 基线）双判据绿 |
| T6 SC#4 拖动门 + PERF-5 + 签核 | 本提交 | **SC#4 两链实测**（testPhase5DragGateTwoChains，Debug）：color 七件全启用拖 vibrance **4.8ms 中位**（60fps 达标，余量 3.5×）；denoise 单件（nlmeans 降载档）拖 strength **85.7ms 未达标** → Open#9 应急判定成立但判定依据表明 Lab 共享贡献 ~5%（非正杠杆），判定依据落 `.work/05/perf.md` + DECISIONS D-05-08-T6-1 后收口（应急工作不在本 plan）；PERF-5 增量记录 vs 04 基线 33.42ms；GUI 汇总（W1-W7 闭环 + bilateral 自动化覆盖；真机视觉走查 Manual-Only L011）；SC#1-4 证据指针落 05-DISCUSSION-LOG；05-VALIDATION 全行 ✅ + 需求注记行（IOP-DENOISE-04 / IOP-COLOR-09 / SC#3 措辞 / SC#4 判定）；REQUIREMENTS.md Phase 3/4/5 行同批翻账；manifest Phase 5 总账 11/11 |

## 验收标准对照（plan Acceptance 逐条）

- [x] bilateral：直连 <1e-5（实测 8e-7）+ grid <1e-3（实测 8.6e-7 vs 同算法参考）+ 两档路径切换断言（rad 5-8）+ σ→0 恒等逐字节 + `_compute_sigmas` 逐行对照表（D-05-08-T1-1）
- [x] OQ7 定稿落 DECISIONS（公式 + 100MP 上界表 + 回落策略=TilingPlan 分块）+ grid 摊销 B/px 定值（32+amortized，leg-aware）
- [x] IOP-DENOISE-04 defer 决议文档化（D-05-08-T4-1 四半边表）+ VALIDATION 需求注记行
- [x] sidecar 11 op round-trip 12/12 + 未知 op 降级回归绿
- [x] SC#4 拖动门两链帧率数字（4.8ms / 85.7ms Debug）+ Open#9 启用判定结论落 DECISIONS（D-05-08-T6-1）
- [x] SC#1-4 证据指针逐条落 DISCUSSION-LOG；缺口零静默（SC#4 denoise 链公开挂账 TODO）
- [x] manifest Phase 5 golden 总账 11/11（含 SC#2 行）；PERF-5 记录 `.work/05/perf.md`
- [x] GUI 验收轮汇总（W1-W7 闭环 + bilateral 自动化覆盖）；Manual-Only 4 行 L011 口径登记
- [x] `05-VALIDATION.md`：`status: validated` + `nyquist_compliant: true` + 全行 ✅ + 移交清单；TODO/LESSONS（L024）/AGENTS/REQUIREMENTS 同批更新（§3.1）
- [x] 全量 `xcodebuild test` 终轮绿（**609/3skip/0fail**）；无 /tmp 过程产物残留；无常驻 app 实例残留（quit + 临时 ARW/lra 清理）

## Phase 6 移交清单

1. **mask_display 挂点**：colorbalancerggb 的 mask_display 棋盘预览属 Phase 6 蒙版域（05-02 deferred 记录）；蒙版渲染挂点在 pipe 的 per-iop mask 机制（dt blendop 对位），Phase 6 plan 期接。
2. **colorbalancergb opacity masks 蒙版化接口**：模块 flags 已带 `.supportsBlending`——Phase 6 的 per-layer iop 复用同一 blend 腿时无需改模块（BlendMode 常量错位问题见 06-RESEARCH Open Questions，6-1 前拍板）。
3. **Lab 域模块清单**（Open#9 应急相关）：nlmeans 29.0 / colorzones 60.0 / colorcontrast 56.0 / vibrance 58.0 / monochrome 64.0——LabRoundTrip/LabKernels 共享件就绪（03-03）；Lab leg 的收益与局限见 `.work/05/perf.md` 判定（对 nlmeans 缺口 ~5%）。
4. **Open#9 应急状态**：SC#4 denoise 链未达标 → 应急判定成立但非正杠杆（上述）；Phase 6 若接 denoise 拖动 60fps 目标，正杠杆 = 更深预览降载（K/window/分辨率），不是 Lab leg。
5. **cacorrect defer 终局结论**：维持 defer（RAW 域），与 Phase 6 无关，重启 = v2 自研 RAW 解码（D-05-08-T4-1）；hotpixels/dark-frame 同门同结论。
6. **轨 B 全链基线**：GeometryGoldenTests track B 现含 Phase 3+4+5 全部模块（中性/禁用插链）——Phase 6 每个新模块/图层机制以此链为零增量基线。
7. **rgbcurve/rgblevels stretch**：槽位 42.0/43.0 在 V50Order 现表；CurveTools 全复用，D-05-CONTEXT-1（非 defer，Phase 6+ 可选补齐）。
8. **sidecar/管线既有约束**（Phase 6 图层持久化直接沿用）：UInt64 哈希 decimal String 入盘（ONE-WAY）、StableHash 唯一生成器、D-H1 三件套、apply 同步契约（GUI-10 修复）。

## 遗留 / 挂账

- PERF-5 denoise 链 60fps 未达标（公开挂账 TODO，正杠杆分析见 perf.md）——本 plan 判定后收口，不在后续静默放宽。
- Manual-Only 4 行（bilateral 视觉走查 / torture 目检 / Release 复测 / LICENSE 核对）——VALIDATION 表登记。
- 已知 flake：testCrossConsistencySyntheticTarget/LinearDomain 负载态偶发（02-04 台账在案，隔离复跑判定，本轮未复现）。

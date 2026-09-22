# Plan 02-06 — Summary

**Executed:** 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE（Phase 2 随本 plan 收口）

非破坏性闭环落地：**`.lra` sidecar 持久化（HIST-03）+ 漂移检测（HIST-04/SC#5）+
会话内存预算执行器（D-C1/D-C2）+ RAW-03 float 位深保真 + Phase 2 签核**。
Checkpoint 02-06-01 七锁全 affirmed（含 **UInt64-as-String** ONE-WAY 锁）。
Tracer 闭环达成：开图 → sidecar 载入（或 pristine）→ 编辑 → history commit →
2s 节流落盘 → 退出 → 重启 → 重开 → **参数与渲染输出字节级一致**（真机探针 +
Core 级测试双证）。执行中逼出并修复一个 pre-existing 真缺陷（colorout ColorSync
腿跨队列读竞态，LESSONS L014）。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 02-06-01 | checkpoint:decision — D-S1/S2/D-C1 七锁 affirmed（schema 键位/UInt64-as-String/未知 op/漂移/预算/imageID 铸造） | e9edd50 |
| 02-06-02 | `LightamerSidecar` schema v1 + `UInt64String` wrapper + `driftDetected`/`degradedForUnknownOps` primitives + ModuleInstance/HistoryStack 恢复构造器 + API.md | 3a11cb6 |
| 02-06-03 | `SidecarStore` actor：2s debounce 合并（末文档胜）/ 同目录 tmp 原子晋升 / 损坏→nil；`AppError.sidecarWriteFailed`；fake-clock 可测 | 5429570 |
| 02-06-04 | App 接线：load 切换 flush→restore-or-fresh、scheduleWrite 挂 history-move、terminate 有界同步 flush、漂移/未知 op/write-fail toast、StatusBar toast 面 + xcstrings zh/en、DEBUG headless 探针；**L014 fence 修复**；roundtrip.md | 5e0d699 |
| 02-06-05 | `PipeCache.enforceBudget(now:keeping:)`（锁定 4 层序 + floor）+ `KeepingPolicy/Freed` + `CIContextPool.clearCaches`/`MetalContext.clearCICaches` + coordinator load 入口/60s sweep 双触发 + >500MB toast 节流 | c208339 |
| 02-06-06 | RAW-03：`Scripts/gen-float-fixtures.py`（uv 可复现）+ 32f TIFF/EXR fixtures（0.0/0.5/1.0/2.0/65504.0 pinned）+ `RAW03Tests`（7）；宿主决策记录于 `decodeRaster` | 6a72691 |
| 02-06-07 | 漂移注入（不回写）+ 未知 op 降级测试；VALIDATION Wave 0 三行 ✅ | c336da4 |
| 02-06-08 | 全套件 + VALIDATION 签核（SC#1..5 + 需求追溯 7/7）+ TODO + AGENTS.md 增量 + LESSONS L014 + 本 SUMMARY | 本批 |

## 验证（质量门全过）

- 单测 **133 全绿，0 失败**（3 skip 合规：RAW 大样本 + ColorChecker 待补拍）；`xcodebuild test` unit 腿 ~3.4s
- UITests：L011 环境遗留（automation-mode 授权超时）→ ⚠️ pending-manual，rerun 命令记录于 VALIDATION sign-off
- **SC#3 真机双跑**（`.work/plans/02-06/roundtrip.md`）：edit 跑 displayHash `1dbb380e2153fea0` = verify 跑一致，dump 字节 `cmp` IDENTICAL；恢复日志 history 1/1、position 0、topParamsHash/imageID 全对
- 新测试覆盖（plan 验收逐项）：
  - schema round-trip 全等（真实 HistoryStack + undo 中态 + redo 尾）+ UInt64-as-String 盘上拼写 + 裸数字防御解码 + D-S2 命名可逆
  - debounce 合并（fake clock 单 sleeper / 单文件 / 末文档胜）+ flushNow 幂等 + 原子写双腿无 tmp + 损坏/缺失 → nil
  - **漂移注入**：检测 + **不回写**（文件原样）+ 后续编辑正常回写且自洽
  - **未知 op**：paramsData 字节保持 + enabled=false + opName/multiName/id 保真
  - enforceBudget：4 层矩阵 + tier 内 LRU + tier-3 留 previous + tier-4 + no-op + **6 连加载循环**（≤floor，≥1 实逐）+ clearCICaches 冒烟
  - RAW-03：TIFF/EXR 输入平面极值保真（65504.0）+ 内部级不钳制 + gamma 唯一钳制点 + 16-bit HEIC raster 路径
- grep 守卫：`.xmp` 零读写代码路径（仅注释）；App 层验证 = 构建走查 + 进程内探针（App target 不可 import，02-05 偏差 #1 连续先例）

## 执行过程抓出并修复的缺陷

1. **colorout ColorSync 腿跨队列读竞态（真产码缺陷 → LESSONS L014）**：
   `CIContextPool.convertTexture` 用 CI 自己的内部队列渲染纹理背书 CIImage，
   而输入平面在我们队列上 commit 未完成——restore 5-dispatch 渲染 4/4 稳定读
   到全零平面（黑图），live-edit 短渲染 2/2 侥幸通过。修复 = CI 读取前空
   command buffer fence + `waitUntilCompleted`。该缺陷 02-04 引入 fallback 腿
   起即存在，由 02-06 的 SC#3 字节级验收逼出。
2. **测试端读取竞态（非产码）**：`getBytes` 不等 in-flight encoder——新测试
   初版漏 drain 读到半写内存（"黑图"假象之一）；Golden/Trio 既有测试自带
   `drain()`，新测试已补并记入 L014 对策。
3. **探针 argv[0] 误选**（非产码）：headless 探针首版把进程可执行路径当图像
   参数；改为 `dropFirst()` + odoc open 事件双通道。

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | `SidecarStore` init 为 `destination: URL`（.lra 全路径）而非 plan 草案 `directory: URL` | per-image store 天然以完整目的地命名（`sidecarURL(for:)` 产物）；语义等同，目录推导在 writeAtomic 内部 |
| 2 | `MetalContext.clearCICaches()` 为 actor-isolated async 而非 plan 草案 `nonisolated` | nonisolated 无法触碰 actor 私有 `ciContextPool`；调用侧语义一致（都 await） |
| 3 | scheduleWrite 挂在 history-move 调用点（commit/undo/redo/jump）而非 `historyDidChange()` 内部 | live 拖动 tick 也流经 historyDidChange；sidecar 必须只反映已提交 history（rebuild-from-history 不变量），plan 验收原文（"history commit → throttled write"）语义一致 |
| 4 | 未知 op 降级实现为 `LightamerSidecar.degradedForUnknownOps(registry:)` Core 级函数（plan 只要求行为） | App target 不可被单测 import（02-05 偏差 #1 先例）；行为必须在 Core 层可测 |
| 5 | `terminateHandler` 形状 `(@MainActor @Sendable () -> Void)?` + `MainActor.assumeIsolated` | applicationWillTerminate 回调在 Swift 6 视角 nonisolated；该闭包形状是捕获 MainActor 状态的合规写法 |
| 6 | probe 输出镜像进 unified log（print 之外） | `open` 启动 detached stdout；headless 判定依赖日志 |
| 7 | RAW-03 HIF 以 16-bit HEIC fixture 钉 raster 路径（float-HIF fixture 本机无编码器） | plan 预案原文允许（"HIF 限制如实记录于测试注释"）；float-HIF 保真随 Phase 8 真实样本落地 |
| 8 | `HistoryStack.init(items:position:)` / `ModuleInstance` 字段级 init 为**新增 internal 构造器**（超出 plan 产物清单） | 恢复路径必需：runtime mutation 面（commit/undo/redo/jump）无法重建历史 item id/timestamp，未知 op 无法经 typed init 构造；均 internal，公共面不变 |

## 交接给下游

- **Phase 3**：每个新 iop 注册进 registry 后自动获得 sidecar 持久化；滑块走
  `beginContinuousEdit/setLiveParams/commitContinuousEdit`，commit 即自动节流
  落盘；golden harness（双判据）为 merge gate
- **Phase 4**：`requestFull()`/FULL 管线为 zoom-ROI 入口；`enforceBudget` 已
  就位承接 ROI 协商的新缓存行
- **Phase 5**：`TilingPlan` 挂接点注记在 `PixelPipe.processRec`
- **Phase 6**：`layerStack` sidecar 字段（null 占位）+ `HistoryItem.layerScope`
  直接激活；mask 引用链依赖 imageID（已跨会话稳定）
- **Phase 8**：EDR 内存重审时 `enforceBudget` 阈值即调节点
- **Phase 9**：Session 切换 `invalidateAll` 钩子注记在 coordinator load 入口；
  `.xmp` 互通决策重议

## 环境注记

- L009 全程生效（USB 卷：`xcodebuild -version` 首次 7.5s 冷态 → 热态 0.04s，未进入病态）
- 新文件后 `tuist generate` ×2（Sidecar 目录、测试文件）
- `xcodebuild -quiet` 幻影报错两段式确认沿用（完整日志 BUILD SUCCEEDED 为准）
- UITests 环境遗留沿用 L011 pending-manual 口径（代码就绪，解锁/授权后单跑即绿）

## Phase 2 收口

ROADMAP §Phase 2 成功标准 SC#1..5 全数有证据指针（`02-VALIDATION.md` 对照表）；
需求 FOUND-04 / COLOR-01 / COLOR-04 / HIST-01..04 / RAW-03 追溯 7/7 落地；
6/6 plans executed；pending-manual 4 项全部为环境类（不阻塞 Phase 3 开工）。

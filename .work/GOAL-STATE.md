# GOAL-STATE — Lightamer GSD 全自动推进

> 保活巡检（Cron）的正本指令文件。每次巡检运行：**先读本文件 → 执行"下一步动作"队列的第一项 → 完成后更新本文件（状态 + 下一动作）→ 提交推送**。
> 项目根：`/Volumes/UNITEK/Documents/Development/Lightamer`（所有命令在此目录执行）

## 总目标

按 `.planning/ROADMAP.md`（13 阶段）逐阶段推进 Lightamer：每阶段 discuss → plan → execute → verify-work → 闭环。当前聚焦：**Phase 1 闭环（issue #1 修复）→ Phase 2 全周期**。

## 当前状态（2026-09-23 07:3x，HOLD 待换阵容）

- **HOLD（2026-09-23 07:3x）：用户切换阵容**——在途 05-08 worker 跑完当前任务即停（本标记阻止一切新派遣）；worker 退出后 orchestrator 复确认 HOLD（防 L022 回卷）。切换完成后用户告知新阵容即恢复队列（W7 05-08 重新派遣）。


- **Phase 4：已闭环**（VERIFICATION.md GOAL ACHIEVED；04-01..04-08 全 PASS）
- **Phase 5：Color & Denoise**——RESEARCH+CONTEXT+8 plans 定稿
  - 05-01 ✅（426）→ 05-02 ✅（445）→ 05-03 ✅（修复轮 480）→ 05-04 ✅（修复轮+复验 512）
  - 05-05 ✅ 闭环（验收 PASS-with-notes：7/7 AC 独立证实、luma corr 0.9776、撤销逐位回退、4 notes 非阻塞；535 tests）
  - 05-06 ✅ 执行完成（2026-09-22 夜间 ZCode subagent；5 commits a61f746..061c4aa；全套 553/3skip/0fail）：nlmeans 29.0 Goossens 五 kernel 直译（parity 12/12 ≤5.7e-6）+ dt 三证据 4/4（DB hex byte-identical + 平场 max_dev=0.0）+ tiling 承重双门（分块==整幅、Δfootprint 352MB）+ 预览降载三件套（57 vs 481 趟，7.5×）+ 面板/轨 B/PERF；SUMMARY+DECISIONS 落盘；**seed DISABLED（plan「strength=0 恒等」证伪，D-05-06-T2-1）**；**新发现 GUI-13（高）**：启用 commit + 立即拖动 tick 并发 → ModuleBox.setParams SIGABRT（D-H1 通用竞态，非 nlmeans 特有，05-08 拖动门签核前必修，崩溃报告 .work/plans/05-06/adoption/）；待验收轮（05-07 执行前/后安排）
  - 05-07 ✅ 执行完成（2026-09-23 续跑 executor 接力前任 T5 中途在制品；7 commits 2ccbae6..d5576fe；全套 **581/3skip/0fail**）：denoiseprofile 9.0 VST 三变体 + eaw 波列双缓冲（L018）+ NLMeans 腿（复用 05-06 kernel 群 norm2=(1,1,1)）+ 剖面接线（NoiseProfileStore EXIF/sentinel/generic/手动 ISO）+ 波列 tiling halo=2^max_scale；parity **8 case×3 fixture ≤9e-6**；**SC#2 = PASS 落账 manifest**（clean-truth 基线：correct 0.00071 < generic 0.00075 < 错配 0.00111 欠去噪方向）；**dt 采纳 8/8**（v12 416B byte-identical + 平场探针容差档；「OpenCL 桩坏受阻」预期经 05-06 conf opencl=false 解除，D-05-07-T5-4）+ 面板（mode/VARIANCE 禁用/profile 三态/7 滑块/force 曲线双 tab）+ PanelWiring +1 + 轨 B + PERF7（波列 31 趟 41.7ms，FULL 35 tiles）+ GUI 走查 PASS（GUI-12 复发沿用：30 行列表面板体挤出可视区）；SUMMARY+DECISIONS 落盘
  - **W6 GUI 修复轮** ✅ 闭环（2026-09-23 夜间 subagent worker；3 commits `909b7bd`/`fffd51d`/`bacfd01`；全套 **582/3skip/0fail** = 基线 581 + GUI-13 并发回归测试）：**GUI-10 + GUI-13 同根修复**——commitParams/setParams/apply 全同步（BREAKING CHANGE 落账）+ rematerializeInstances 两段式（registry 预解析前置、物化循环零挂起点，MainActor 原子）+ TaskGroup ×100 交错回归测试（4/4 稳定）+ 真机 20 轮 AX toggle×滑块背靠背零 settle 压力零崩溃无新 .ips；**GUI-11 + GUI-12 同修**——moduleList 入 ScrollView 高度 min(内容, 列 38%)，面板体 AX 实测 472pt ≥ 240 红线、折叠下方黑白面板整面板可见；GUI-1..4/撤销链/亮度域回归全过；VST 门 1e-6（实测 2.4e-7）+ varf 精确式 + DECISIONS T6-5（dt manual 预填分歧明示）；FINDINGS「W6 修复轮闭环」节 + 3 张证据截图落盘。勿 push（本地 commit 即完成态）
- **模式 = matrix vibe 编排（2026-09-22 用户确认）**：omp 执行 plan + subagent 验收；23:00-9:00 全 subagents（workspace config vibe night slot subagent:auto + review slot3 subagent:4）；14-18 review 休眠窗
- **已确认分派**：W1 05-05 复审（18:00 起 4 CLI lanes per slot2，TASK.md 在 .work/matrix/05-05-r1/review/）→ ~~W2 05-06 执行~~ ✅（2026-09-22 夜间 ZCode subagent 完成，omp 未用）→ ~~W3 05-07 执行~~ ✅（2026-09-23 续跑 executor 完成；前任 subagent T1/T2-T4 已提交，T5 中途在制品由续跑班收口）→ W4+ = 05-08 VALIDATION（引用 manifest SC#2 = PASS 行）+ 05-05/05-06/05-07 验收轮安排
- **运维要点**：omp 模型 API 走 px 代理（停滞处置 = px --up）；1mcp 已拉起（3050）；**push 暂停**（用户指令：本地 commit 即完成态，当前待推 17 commits）
- **待办**：~~GUI-10/13~~ ✅ 闭环（2026-09-23 W6 夜间 subagent：commitParams/setParams/apply 全同步 + rematerialize 两段式零挂起，`909b7bd`；并发回归测试 ×100 + 真机 20 轮背靠背压力零崩溃）——~~GUI-11/12~~ ✅ 同轮闭环（moduleList ScrollView 高度 = min(内容, 列 38%)，面板体 472pt ≥ 240 红线，`fffd51d`）；05-07 notes 收口 `bacfd01`（VST 门 1e-6 / varf 精确式 / DECISIONS T6-5）；FINDINGS W6 闭环节 + 复验数字落盘；trackB flake（05-08 复估）
- **教训新增**：L022 强化——omp closeout 会把 GOAL-STATE 回卷至其启动快照（丢失全部中间进展），omp prompt 必须加「closeout 更新 GOAL-STATE 先读现文件增量改，禁整文件回写旧快照」

## 下一步动作队列（按序执行，完成一项划掉并更新）

1. ~~**修复 issue #1**~~ ✅ 关闭（2026-09-18）：drawable 回读证实渲染/blit 全链正常（JPEG drawable 采样含图像内容）；黑屏为多窗口调试堆积的呈现竞争——真实单窗口使用正常（干净复现截图 4.2MB 完整显示）。转 backlog：多窗口呈现管理（Phase 2/9）。
2. **
   - 复现路径：启动 app → `open -a Lightamer input/RAW/DSC00012.jpg`（60MP JPEG，Display P3）→ 视口黑屏；对照 `input/RAW/DSC09991.ARW` 显示正常。
   - 已排除：管线（harness `.work/plans/01-06/jpeg-debug.swift` 对两者均渲染非黑，9504×6336，avg≈420）。
   - 嫌疑聚焦：(a) `EditorState.renderDisplayTexture` 对 JPEG 抛错被 catch 吞掉（加临时日志或断点）；(b) `CIContextPool` 对 Display-P3 CIImage 的 bitmap 渲染分支返回空/黑（ARW 走 CIRAW CIImage 正常）；(c) MTKView `hasSameSourceTexture` 同步竞态。
   - 诊断手法：headless harness `.work/plans/01-06/jpeg-debug.swift` 已可复现管线；app 内路径差异 = 真实 layerStack（harness 已加）+ EditorState 前置状态。可给 `renderDisplayTexture` 的 catch 加 `print`（stderr）后直接运行二进制抓 stderr。
   - 修复后：`open -a` JPEG → 截图确认显示 → unit suite 无回归 → UAT 测试 3 改 pass。
   - **已排除**（2026-09-18 晚）：(1) 管线本身——two-render harness 同上下文 ARW→JPEG→ARW 三次渲染全部非黑（377/364/377）；(2) drawable 竞态——加重试后 draw 全部 drawable=true 执行；(3) render 抛错——探针 `RENDER ok: DSC00012.jpg → 6336×9504`。
   - **当前锁定**：MTKView 绑定链。draw 全部执行（21:19:33 一毫秒内 13 次连续 DRAW，反常的 setNeedsDisplay 风暴）、pso=true、drawable=true，但屏幕=画布色 → draw 走了 `sourceTexture == nil` 的 clear 分支，即 Coordinator.sourceTexture 在 draw 时为 nil，尽管 renderDisplayTexture 已设置 displayTexture。→ 检查 EditorMTKView 的 `@Binding sourceTexture` → updateNSView → hasSameSourceTexture(`===` 引用比较) 链路；疑点：`.task(id:)` 重启时机 vs updateNSView 时序，或 Binding 更新丢失。
   - 探针已插桩（保留）：EditorMTKView.drawProbe + EditorState RENDER 探针（os_log debug，`log stream --level debug --predicate 'process == "Lightamer"'` 可见）。
   - 下一步：在 updateNSView 里加探针打印 Binding 到达的 texture 状态；若 Binding 确实更新但 coordinator 没拿到，检查 EditorMTKView 是否被 SwiftUI 重建（identity 变化导致 Coordinator 重建、sourceTexture 丢失）。
   - **updateNSView 探针结果（2026-09-18 巡检）**：Binding 链完好——`UPDATE incoming=6336x9504 changed=true`（新纹理到达并推送 coordinator），随后 DRAW 全部执行（drawable=true）。usage 正确（renderTarget+shaderRead+shared）。CIContextPool 纹理无责。
   - **剩余未验证**：(a) drawable 回读——draw 后采样 drawable 内容确认 blit 是否真的写入了图像（区分"blit 采样黑"vs"呈现层黑"）；(b) ARW 阶段截图对比（重建后 ARW 是否还显示——缩小回归范围）；(c) 多窗口实例堆积时 XCUITest/截屏对准的是哪个窗口。
3. ~~**Phase 1 闭环**~~ ✅ 完成（2026-09-18 巡检）：UAT 全 pass；STATE.md status → complete（受控直改，本版 gsd-tools 无 transition verb，已在 commit 说明）；TODO.md 同步。
4. ~~**Phase 2 discuss**~~ ✅ 完成（02-CONTEXT.md + DISCUSSION-LOG.md，13 项自主决策）：`$gsd-discuss-phase 2`（新会话式流程，产出 `02-CONTEXT.md`；输入 = Phase 1 spike 结论 + PERF-BASELINE + issue #1 修复经验）。
5. ~~**Phase 2 plan**~~ ✅ 完成（02-RESEARCH.md 42KB + 6 plans 02-01..06，checker 10 项修复，VALIDATION waves 校正）：`$gsd-plan-phase 2`（research → plans → checker）。
6. **Phase 2 execute** ← 进行中：~~02-01~~ ✅ 完成（2026-09-19：issue#1 真根因=WindowGroup per-odoc 开窗，单 Window 修复，UAT 9/9，L012；9 commits）；~~02-02~~ ✅ ~~02-03~~ ✅ ~~02-04~~ ✅（终端三件套+Registry+golden 双判据，83/83，L013 对策 ParamsCoding 落地）~~02-05~~ ✅（HistoryStack 九字段身份元组+compress+D-H1 三件套+TilingPlan 脚手架，106 tests，history wired）~~02-06~~ ✅（.lra schema v1 + 2s debounce 原子写 + 漂移检测；clearCaches 4 层逐出；RAW-03 65504 pinned；L014 ColorSync 跨队列竞态修复）。**Phase 2 执行 6/6 完成**：`$gsd-execute-phase 2`（波次执行，每 SUMMARY 落盘后提交）。
7. **循环进入 Phase 3+** ← ~~Phase 3 discuss~~ ✅ 完成（03-CONTEXT.md：sigmoid 先行→filmicrgb 全移植、toneequal 全局 5-band、darktable-cli golden 打通、Inspector 面板框架）→ ~~Phase 3 research~~ ✅（45KB：每模块参数/kernel 规格、filmicrgb F0-F4 分解、Lab 域发现、darktable-cli 重建修复）→ ~~plan~~ ✅（6 plans 03-01..06，5 waves，checker 10 项修复）→ **Phase 3 execute 进行中**：~~03-01~~ ✅（dt-cli 重建 + fixtures + parity 双轨 harness + exposure tracer <1e-5 green，143 tests，L015/L016）→ ~~03-02~~ ✅（temperature iop v50=3.0 + Rec2020 原生 K↔gains + D-T6 Inspector 面板框架 + D-T4 吸管 plumbing + golden 合成参考策略，165 tests，L017）→ ~~03-03~~ ✅（Lab 域三模块 tonecurve 48.0/colisa 47.0/levels 49.0 + LabRoundTrip 共享件 + HistogramReduce + ParityGate 双闸 + 三面板，199 tests，L017 扩展：Lab 链 probe 不可用/陈旧插件 .so 重建；8 commits 3932653..3889171）→ ~~03-04~~ ✅（shadhi+sigmoid 复用 LabRoundTrip）→ ~~03-05~~ ✅（toneequal 9-band+EIGF+TilingPlan，244 tests）→ ~~03-06~~ ✅（filmicrgb+agx，267 tests）→ **Phase 3 执行 6/6 完成**
8. **Phase 4 execute** ← 进行中：~~04-01~~ ✅ 执行+验收 PASS（ROI 协商+executeTiled，282 tests）；~~04-02 omp 执行~~ ✅（crop+flip+overlay，5 commits）→ ~~04-02~~ ✅ 闭环 PASS（311 全绿，L019/L020）→ ~~04-03~~ ✅ 闭环 PASS（omp 5 commits + 验收 PASS-with-notes→3 项修复→332 全绿；union-clamp 管线修复核查通过）→ ~~04-04~~ ✅ 完成（2026-09-21：lens 三层 12 commits；355 tests 0 fail；SUMMARY+VALIDATION+TODO 签收）→ **04-05 执行** → 04-06 → Phase 4 verify-work

~~保活巡检暂停已于 2026-09-19 恢复~~（新 automation `automation-09a53a4e-ebf3-4ae8-b8eb-32c179466a6e`，每 30 分钟；旧 ID 已删）。

## 阻塞（需人工）

（当前无——XCUITest 代码就绪待解锁控制台；ColorChecker 补拍为 skip-with-reason 不阻塞）

## 巡检运行规则（每次 Cron 触发时遵守）

- **顺序推进**：只做队列第一项；完成后立即提交（`node $HOME/.codex/gsd-core/bin/gsd-tools.cjs query commit "..." --files <files>`，或直接 git commit——遵循 Conventional Commits、只 add 相关文件）并 `git push origin main`，然后更新本文件队列与"当前状态"。
- **构建保护**：构建/测试前 `caffeinate -dis <cmd>` 防休眠。USB 卷慢时（`time xcodebuild -version` >2s）只记录慢态，**不例行 SIGSTOP Resilio**（L009 归因已修正 2026-09-20：仅当确认 Resilio 正在活跃传输时才暂停作诊断性 A/B，构建完 `kill -CONT` 恢复）。
- **GUI 限制**：XCUITest/截图目检需要解锁的控制台——用 `screencapture -x /tmp/probe.png && stat -f%z` 判断（<200KB≈锁屏/黑屏）。锁屏时跳过 GUI 验证，在 GOAL-STATE 标注"待人工解锁"，继续做 headless 可推进项。
- **密码弹窗**：若出现 "XCTest 正在尝试 Enable UI Automation" 密码弹窗——当前签名授权已持久化，不应再弹；若真弹出（新二进制形态），记录到"阻塞（需人工）"章节并跳过 GUI 测试。
- **禁止事项**：不 `git add -A`；不直写 STATE.md/ROADMAP.md（用 gsd-tools verb）；不在 NAS 原目录写入（只读参考，样例 Copy 到 `input/RAW/`，已 gitignore）；不动 ZCode 自身进程。
- **日志**：每次巡检在 `.work/GSD-PROGRESS.log` 追加一行 `[时间] 动作 → 结果`。
- **遇到不可自动化的阻塞**（需真人密码/锁屏/确认）：写入下方"阻塞（需人工）"章节，跳过并继续队列中可 headless 推进的项。

~~保活巡检暂停已于 2026-09-19 恢复~~（新 automation `automation-09a53a4e-ebf3-4ae8-b8eb-32c179466a6e`，每 30 分钟；旧 ID 已删）。

## 阻塞（需人工）

（当前无——XCUITest 授权已持久化；如巡检发现新阻塞，登记此处）

## 已完成里程碑

- [x] 2026-09-16/18: Phase 1 六计划执行完毕（40+ commits）；unit 36 绿；XCUITest 1 pass+2 skip；Spike A/B 报告；L001-L011 经验沉淀
- [x] 2026-09-18: UAT 5/6（issue #1 待修）
- [x] 2026-09-18: issue #1 关闭（重定性：多窗口呈现竞争，非渲染缺陷；JPEG 干净复现完美显示）

---
*正本：本文件。Cron 巡检 prompt 指向此文件。任务完成/中止时由巡检运行删除自动化并在此记录。*

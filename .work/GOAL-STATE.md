# GOAL-STATE — Lightamer GSD 全自动推进

> 保活巡检（Cron）的正本指令文件。每次巡检运行：**先读本文件 → 执行"下一步动作"队列的第一项 → 完成后更新本文件（状态 + 下一动作）→ 提交推送**。
> 项目根：`/Volumes/UNITEK/Documents/Development/Lightamer`（所有命令在此目录执行）

## 总目标

按 `.planning/ROADMAP.md`（13 阶段）逐阶段推进 Lightamer：每阶段 discuss → plan → execute → verify-work → 闭环。当前聚焦：**Phase 1 闭环（issue #1 修复）→ Phase 2 全周期**。

## 当前状态（2026-09-18 深夜，巡检更新）

- Phase 1：**已闭环**（STATE status=complete）。UAT 6/6；unit 36 绿；XCUITest 1 pass+2 skip
- Phase 2：**全部 6 plans 执行完成**（133 tests 绿；VALIDATION 签核；L014）
- Phase 3：CONTEXT/RESEARCH(45KB)/VALIDATION/6 plans 定稿并通过 checker。待执行
- issue #1 已关闭：重定性为多窗口调试堆积的呈现竞争（drawable 回读证实 blit 内容正确），转 Phase 2 backlog（窗口生命周期管理）。单窗口真实使用完全正常。
- 环境：macOS 27 + Xcode 27.0 + Tuist 4.208；签名证书 "Lightamer Dev"（已装入 login keychain，全 target Manual 签名）；DerivedData 在内置 SSD；仓库在慢速 USB 卷（L009）。

## 下一步动作队列（按序执行，完成一项划掉并更新）

1. ~~**修复 issue #1**~~ ✅ 关闭（2026-09-18）：drawable 回读证实渲染/blit 全链正常（JPEG drawable 采样含图像内容）；黑屏为多窗口调试堆积的呈现竞争——真实单窗口使用正常（干净复现截图 4.2MB 完整显示）。转 backlog：多窗口呈现管理（Phase 2/9）。
2. **
   - 复现路径：启动 app → `open -a Lightamer input/RAW/DSC00012.jpg`（60MP JPEG，Display P3）→ 视口黑屏；对照 `input/RAW/DSC09991.ARW` 显示正常。
   - 已排除：管线（harness `.work/01-06/jpeg-debug.swift` 对两者均渲染非黑，9504×6336，avg≈420）。
   - 嫌疑聚焦：(a) `EditorState.renderDisplayTexture` 对 JPEG 抛错被 catch 吞掉（加临时日志或断点）；(b) `CIContextPool` 对 Display-P3 CIImage 的 bitmap 渲染分支返回空/黑（ARW 走 CIRAW CIImage 正常）；(c) MTKView `hasSameSourceTexture` 同步竞态。
   - 诊断手法：headless harness `.work/01-06/jpeg-debug.swift` 已可复现管线；app 内路径差异 = 真实 layerStack（harness 已加）+ EditorState 前置状态。可给 `renderDisplayTexture` 的 catch 加 `print`（stderr）后直接运行二进制抓 stderr。
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
7. **循环进入 Phase 3+** ← ~~Phase 3 discuss~~ ✅ 完成（03-CONTEXT.md：sigmoid 先行→filmicrgb 全移植、toneequal 全局 5-band、darktable-cli golden 打通、Inspector 面板框架）→ ~~Phase 3 research~~ ✅（45KB：每模块参数/kernel 规格、filmicrgb F0-F4 分解、Lab 域发现、darktable-cli 重建修复）→ ~~plan~~ ✅（6 plans 03-01..06，5 waves，checker 10 项修复）→ **下一项：Phase 3 execute**（wave 1: dt-cli 重建+fixtures+exposure parity tracer；wave 2: WB+面板 ∥ curve/levels/colisa；wave 3: shadhi+sigmoid；wave 4: toneequal TilingPlan 首战；wave 5: filmicrgb+签核）

## 阻塞（需人工）

（当前无——XCUITest 代码就绪待解锁控制台；ColorChecker 补拍为 skip-with-reason 不阻塞）

## 巡检运行规则（每次 Cron 触发时遵守）

- **顺序推进**：只做队列第一项；完成后立即提交（`node $HOME/.codex/gsd-core/bin/gsd-tools.cjs query commit "..." --files <files>`，或直接 git commit——遵循 Conventional Commits、只 add 相关文件）并 `git push origin main`，然后更新本文件队列与"当前状态"。
- **构建保护**：构建/测试前 `caffeinate -dis <cmd>` 防休眠；USB 卷慢时（`time xcodebuild -version` >2s）先 `kill -STOP` Resilio 进程（1895/1916 等按当时 pgrep），构建完 `kill -CONT` 恢复。
- **GUI 限制**：XCUITest/截图目检需要解锁的控制台——用 `screencapture -x /tmp/probe.png && stat -f%z` 判断（<200KB≈锁屏/黑屏）。锁屏时跳过 GUI 验证，在 GOAL-STATE 标注"待人工解锁"，继续做 headless 可推进项。
- **密码弹窗**：若出现 "XCTest 正在尝试 Enable UI Automation" 密码弹窗——当前签名授权已持久化，不应再弹；若真弹出（新二进制形态），记录到"阻塞（需人工）"章节并跳过 GUI 测试。
- **禁止事项**：不 `git add -A`；不直写 STATE.md/ROADMAP.md（用 gsd-tools verb）；不在 NAS 原目录写入（只读参考，样例 Copy 到 `input/RAW/`，已 gitignore）；不动 ZCode 自身进程。
- **日志**：每次巡检在 `.work/GSD-PROGRESS.log` 追加一行 `[时间] 动作 → 结果`。
- **遇到不可自动化的阻塞**（需真人密码/锁屏/确认）：写入下方"阻塞（需人工）"章节，跳过并继续队列中可 headless 推进的项。

## 阻塞（需人工）

（当前无——XCUITest 授权已持久化；如巡检发现新阻塞，登记此处）

## 已完成里程碑

- [x] 2026-09-16/18: Phase 1 六计划执行完毕（40+ commits）；unit 36 绿；XCUITest 1 pass+2 skip；Spike A/B 报告；L001-L011 经验沉淀
- [x] 2026-09-18: UAT 5/6（issue #1 待修）
- [x] 2026-09-18: issue #1 关闭（重定性：多窗口呈现竞争，非渲染缺陷；JPEG 干净复现完美显示）

---
*正本：本文件。Cron 巡检 prompt 指向此文件。任务完成/中止时由巡检运行删除自动化并在此记录。*

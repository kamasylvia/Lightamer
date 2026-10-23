# R3 修复批综合验收（ACCEPTANCE — 双路合并：plan 忠实 + 对抗角度）

**结论：PASS / 0 blocking + 0 major + 0 minor + 2 obs**

- 验收人：zcode 综合验收 subagent（2026-10-22/23）
- 对象：`3d325125`(F2-1)/`22082049`(标记接线)/`856f2396`(gamma E 族)/`8a1a5c2d`(docs)
- 主树 HEAD = `8a1a5c2d` 未动；验收零源码改动（负腿掏空已 `git checkout` 还原，tracked 面 0 diff）
- 独立复跑全套 = **TOTAL|4112/40/0|2294s OK**（guard 锁 + nohup + 全程监视，零 MEMFAIL）

---

## 1. F2-1 ImportModeDialog 重注入 —— PASS

**diff 亲读**（对照 M2-8-3 先例形态）：`ImportModeDialogSheetContent` 以 init 参数携
`AgentControlCoordinator`，`body` 内 `ImportModeDialog(...).environment(agentControl)` —— 与
`AdjustmentTransferSheetContent`（M2-8-3 FINDING-A 修复，App/Sources/Lightamer/UI/Shell/
AdjustmentTransferView.swift:330）逐形同构（显式 re-inject carrier + shell sheet 闭包装 content face，
LightamerShell.swift sheet 闭包已换挂新 face）。壳闭包注释点明 boundary rule，原 `@Environment` 读点
留 ImportModeDialog 内不动（正确——读点不动、注点在 sheet 树内）。

**负腿亲跑**：掏空 `.environment(agentControl)` → 重建（`negbuild-acc.log`，TEST BUILD SUCCEEDED）→
`test-direct.sh 'SheetEnvironmentInjectionTests'` → **同签名 Fatal 亲锤**：
`SwiftUICore/Environment+Objects.swift:34: Fatal error: No Observable object of type
AgentControlCoordinator found`（CopyAdjustments 腿先 pass，ImportFolder 腿挂载即 trap，host exit=133，
verdict=crash）。与 executor 证据 `r3-fixes/all-runs/negleg-crash-signature.txt` 逐行同签名（同文件同
行号同文案）。自跑证据 = `r3-fixes/all-runs/negleg-acc.log` + `negleg-host-crash-acc.log`。

**正腿**：还原重建后 `SheetEnvironmentInjectionTests` **2/0/0**（真 .sheet 挂载 + onAppear 探针过首个
environment update）。**真机复验**（本验收亲驱，证据 `.work/gui-acceptance/r3/acc-04..09`）：
⌘⇧I Import Folder → AX 选中 src → 打开 → **sheet 挂载存活（修复前 = 此刻确定性 EXC_BREAKPOINT）** →
扫描 3 RAW → 导入完成（3 缩略图入格 + 图库概览 3 照片 + AI 询问 sheet 同活）。全流程闭合。

## 2. 标记链接线 —— PASS

**diff 亲读**：`WorkspaceModel.MarkCommand` 四 case + `pendingMarkCommand/requestMark/
consumeMarkCommand`（pendingStackCommand 孪生，单槽单消费者）；`LightamerShellFace.routeLibraryMark`
phase 门（`NSMenuBridgeController.shared.workspace.phase == .library`）拦在四 mark 方法
（applyRating/applyColor/applyFlag/toggleFlag）最前，library 相位写请求域即返回，否则 session 路径
原样；`MarkCommandModifier.onChange` 消费 → `LibraryMarkApplier`（walk-order 选择 + ImageLinker 三态
解析 + toggle 读网格投影 + uniform-Lr 规则）→ `LibraryMetadataWriter`（加性 clear 三 flag，R1 API 零
break）→ `refreshRows(ids:)` + `inspector.refresh()`。

**接线死路攻击（源码审计）**：
- *实例身份*：`WorkspaceHostView.onAppear → noteWorkspace(workspace)`（WorkspaceHostView.swift:192）
  —— shell 路由写的与 modifier 消费的是同一 WorkspaceModel 实例（单窗形态），无第二个 note 点。
- *绕过 refreshRows 的 writer 调用链*：`LibraryMetadataWriter.apply` 生产面调用点全仓唯一 =
  WorkspaceHostView:886（Applier 内，写后恒 refreshRows + inspector refresh）；`setMetadataMarks` 唯一
  生产调用点 = writer 内部投影批；MCP 面（O1-O3）全只读。**无死路写面**。
- *投影批失败路径*：`try? await grid.refreshRows` 失败 = 盘上真相已落、UI 短暂 stale、下一轮 mark
  round-trip 盘真相（SC#2-soft 已注册语义，非死路）。
- *连发攻击（真机）*：5 星 → 清除评分 → 5 星（150ms 间隔连发）终态 DB=5 + sidecar=5 —— 命令域串行
  语义成立，终态无丢失。
- **obs-1（竞态窗口，非缺陷级）**：单槽请求域在两次 mark 落入同一 SwiftUI update pass 时仅后值可见
  （先值被覆写不消费）；且两个 Applier Task 若在毫秒级窗内并发起跑，per-edit 的 compose(读)→write 原子
  段之间无跨 Task 互斥，理论可交错（后写胜）。输入面（菜单/键盘 autorepeat ≥ 数十 ms）实际不可达此窗；
  语义与 D5 采纳的 pendingStackCommand 孪生完全一致（「one request owner」为注册设计）。不改判，挂观察。

**测试亲跑**：`LibraryMarkWiringTests` **5/0/0**（真实 .lalb + 真实文件：端到端/清除面/uniform-Lr/双
no-op guard）。**真机三重零闭合复验**（亲驱）：菜单 5 星 → 徽章 ★★★★★（acc-11）+ DB
`images.rating=5` + `Media/.../A.ARW.lra` 落盘（schemaVersion 11, rating=5）；清除评分 → DB NULL +
sidecar `rating=None` + 徽章消失 + inspector 聚合回 Unrated/高分组 0（acc-12）。三面齐动齐清。

## 3. gamma E 族显式形 —— PASS

**diff 亲读**：`String(format: String(localized: "rawdecode_raster_trc_gamma_value"),
String(format: "%.2f", g))` —— 静态键 + 值分离（V14/KD-4 ratingMenuLabel 家族形）；插值构键禁形清零。

**xcstrings 键迁移 diff**：键 `"rawdecode_raster_trc_gamma_value %@"`（%@ 在键内）→
`"rawdecode_raster_trc_gamma_value"`，en `gamma %@` / zh `伽马 %@` 迁入值槽，extractionState=manual
保持；整文件 JSON 解析通过（`json.load` OK，D6 文本块编辑约束守恒——非 JSON 重写）；旧键全仓零残留
（grep 0 命中）。

**zh-audit 双 PASS 复跑**：`--check` PASS（1688 source keys / 2005 catalog keys / 40 interp keys
variant-PRESENT / zh complete / locales {en, zh}——数字与 commit 申报一致）+ `--self-test` PASS。

**渲染抽验（亲机）**：构造 Generic RGB Profile（gamma 1.8）TIFF 导入并开编辑器 → RAW 页 raster 读出：
配置文件=Generic RGB Profile / 来源=内嵌 ICC / **传递曲线=「伽马 1.80」**（acc-13）——静态键 + `%.2f`
格式化值正确渲染，非裸键、非未替换 %@。

## 4. 全套独立复跑 —— PASS（对账申报）

guard 锁后 nohup + 全程监视（IOP 峰 6830MB 贴线门内，IOPParity 6064，无 MEMFAIL）：

| bundle | executed/skip/fail | peakRSS | seconds |
|---|---|---|---|
| IOP | 753/5/0 | 6830MB | 477s |
| IOPParity | 478/6/0 | 6064MB | 725s |
| Layers | 494/5/0 | 813MB | 158s |
| Library | 747/4/0 | 627MB | 85s |
| Sessions | 285/9/0 | 1243MB | 79s |
| Export | 385/5/0 | 4997MB | 215s |
| App | 970/6/0 | 2832MB | 555s |
| **TOTAL** | **4112/40/0** | — | 2294s |

**对账**：任务公式 `4106+Δ/40+Δ`，Δ = F2-1 新法 1 + 接线 5 法 + gamma 0 = 6 → 期望 4112/40/0，
实测**逐位一致**；executor 分 bundle 申报 App 970/6/0、Library 747/4/0 **逐位复现**。日志 =
`r12-repairs/all-runs/r3-acc-all.log`。

## 5. 回归面 —— PASS

- **FIX2③**：`git diff bc45d6a6..8a1a5c2d -- '**/LibraryProjectController.swift'` = 0 行（连续第七波
  零 diff）。
- **封存面**：全 17 件清单（DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels.metal/
  DrtEotf/ExportQueueContract/ExportFormatSpec/ImageIOEncoders/WebPEncoder/NodeGraphCommand/sidecar
  schema/HistoryStack/HistoryHash/PipelineDocument/V50Order/GradeCatalog）range diff = 0 行。
- **三窗**（P1 修复持续，亲机）：⌘, Settings（acc-14）/ Edit▸预设管理器（acc-15）/ Edit▸MCP Agent
  启动器（acc-16）三窗同开共存，PID 全程不变。
- **壳交接 churn**（亲机，静置）：idle CPU 0.0-0.2%（top 4 连采 + ps 双采），RSS 485MB（<3G 触发线
  一个量级），无 remount churn。
- 主树 HEAD `8a1a5c2d` 未动；验收后 tracked 面 0 diff；Lightamer/构建进程全数清零；走查 scratch
  （/tmp/r3-acc）即弃已清，家目录零残留（过程事故已即时纠偏：AX 直写绕过保存面板路径展开致项目一度
  落 ~/Documents，quit + 删净后改键入 + go-to 路线重建于 /tmp——净轮证据不受扰）。

---

## 分级清单

- **blocking (0)**：无。
- **major (0)**：无。
- **minor (0)**：无。
- **obs (2)**：
  1. 标记请求域单槽语义：同帧双 mark 后值胜（先值不消费）+ 毫秒窗内双 Applier Task 理论可交错（每
     edit 读-写段无跨 Task 互斥）——输入面不可达、与 D5 注册设计（pendingStackCommand 孪生）同构，
     挂观察不改判。
  2. gamma 读出节为 raster 面专属（CIRAW RAW 文档显示 NR/解码器节、无 raster 读出）——RawDecodePanelView
     既有的 either/or 布局，非本批引入；gamma 抽验需 raster 载体（本验收专造 Generic RGB TIFF 达成），
     记为走查成本注记。

**验收材料**：真机证据 `.work/gui-acceptance/r3/acc-01..16`（MANIFEST.md 同目录）；负腿自跑
`r3-fixes/all-runs/negleg-{acc.log,host-crash-acc.log,negbuild-acc.log,posbuild-acc.log}`；全套日志
`r12-repairs/all-runs/r3-acc-all.log`。

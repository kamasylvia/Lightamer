# M8-3-SUMMARY — FSIM 面板+收口执行摘要（2026-10-26）

> 执行正本 = `M8-3-PLAN.md`（checker `40bccfd3` + fixer `dd9490fe` + R1
> `bc2baf39` 后 HEAD）；偏差与裁定的正本 = `M8-3-DECISIONS.md`（本文只
> 记账 + 验收判定，不重复裁定正文）。C 档停位：本 plan 执行+验收闭环后
> 停汇报（VALIDATION 前停——verify-work 结论给用户过目）。

## 逐任务记账

| 任务 | commit | 产物 | 测试增量 |
|---|---|---|---|
| T1 UI 零新增 | `06ac0d41` | FilmPanelSpectralUITests（源清单快照 31 id 恒等 + AX 活树零陌名 + adaptation 零暴露三面）+ grep 组证据（DECISIONS 引） | +3 |
| T2 probe 跟随 | `1890febe` | DualArmGolden E1/E2（v2 臂 probe 形输出在案 + 双臂读数对照）+ probe ③⑤ 终态复测零漂移 | +2 |
| T3 迁移 UX | `d6a3c32f` | FilmMigrationAction 纯模型 + 面板行/确认 sheet + 键族六键 + 生产面 renderProcess 接线（DECISIONS 一——M8-2 欠账补齐）+ ProcessVersionCarrierTests 双 pin 机械移动 | +4 |
| T4 曝光语义 + NOTICE | `0809be19` | SpectralExposureSemanticsTests 四法（solve gain 消费层终账 + ev_scale ≡ 1 双钉 + descriptor 曝光不变 + NOTICE 升格断言）+ NOTICE §2 升格 + AGENTS/M3-2 勘误行 | +4 |
| T5 --all 收口 | `af84ddc1` + 收口轮 | 三轮同值 4286/46/0（装配式对账——ToneEqualPerf 环境型 flake verdict + Library/Sessions 陈旧 pin 修复）+ gui 走查证据（`.work/gui-acceptance/m8/MANIFEST.md`） | 0（对账式；pin 修复测试面 0 增量——既有法改期望值） |
| T6 收口 | 本 commit | Project.swift 第二行 + BUNDLE-MAP 两行 + tuist 末位 + SUMMARY/DECISIONS/VALIDATION 预备 | 0 |
| **合计** | | | **+13** ∈ [+10, +14] ✓ |

## 定向轮实测（Scripts/test-direct.sh，全程 machine-guard 记录在案）

| 轮 | 结果 | 说明 |
|---|---|---|
| App FilmPanelSpectralUITests（T1 时点） | 3/0/0（16s） | 快照/活树/源 token 三面绿 |
| IOPParity SpectralDualArmGoldenTests（T2 时点） | 12/0/0（644s，378MB） | 既有 10 + 新 2；读数对照 M83-PROBE-READOUT 两行在 log |
| IOPParity SpectralPerfProbeTests（T2 复测，LIGHTAMER_PERF_PROBE=1） | 5/0/0（315s，1282MB） | probe ③⑤ 零数值漂移（DECISIONS 四表） |
| App FilmPanelSpectralUITests（T3 时点） | 7/0/0（251s，314MB） | 端到端迁移 239.9s（光谱臂重渲染，DECISIONS 六.3） |
| App ProcessVersionCarrierTests（T3 pin 移动后） | 8/0/0（11s） | 两处 literal-1 → current.rawValue |
| App 全量（T3 后） | 1014/6/0（598s，2832MB） | 双失败 = 陈旧 pin（pin 移动前轮），移动后清零 |
| IOPParity SpectralExposureSemanticsTests（T4） | 4/0/0（278s，206MB） | T5 期间又一轮 4/0/0 复证 |
| IOPParity ToneEqualPerfTests 隔离复核（T5） | 1/0/0（77.6ms）+ 全 bundle 529/11/0（105.4ms） | --all 热态 157.9/135.3 双败 = 环境型 flake verdict（M8-2 DECISIONS 十二同族） |
| Library / Sessions（pin 修复后） | 778/4/0 / 285/9/0 | af84ddc1 三 pin 移动（M8-2 漏网面） |
| **全套 --all** | **4286/46/0 三轮同值（§T5）** | |

## T5 — 全套 --all 三轮对账（2026-10-26 执行）

**执行形态申报**：`Scripts/test-direct.sh --all` 的红即停设计（"前序
bundle 红即停"）在本轮两次触发——①`ToneEqualPerfTests
.testPreviewFullChainFrameTime`（环境型 flake 家族：--all 语境 = IOP
17 分钟重渲后的热态，warm median 157.9/135.3 > 120ms 界；**同 build
隔离轮两次全绿**——单类 1/0/0（77.6ms）+ 全 bundle 529/11/0
（105.4ms），M2-11-01 verdict 口径 + M8-2 DECISIONS 十二同族归因，非
本批缺陷——本批零触该路径：filmTail nil 渲染对 renderProcess 线程
不可见）；②`ProcessVersionCarrierTests`/Library/Sessions 的四处
literal-1 陈旧 pin（`af84ddc1` 修复，M8-2 机械面移动漏网——M8-2 定向
轮未跑 Library/Sessions/App 三 bundle）。三轮以 **逐 bundle 门控装配
式**执行（每 bundle 独立 `--bundle` 调用 + 每调用前置
`machine-guard.sh --wait`；G4 磁盘门贴线震荡逐轮修剪我方构建缓存，
DECISIONS 六.4）。

**三轮同值（全部绿）**：

| bundle | R1 | R2 | R3 | 峰值 RSS（R1-R3 最大） |
|---|---|---|---|---|
| IOP | 788/5/0 | 788/5/0 | 788/5/0 | 5712 / 5769 / 5603 MB |
| IOPParity | 529/11/0 | 529/11/0 | 529/11/0 | 4339 / 5324 / 5493 MB |
| Layers | 507/6/0 | 507/6/0 | 507/6/0 | 625 / 815 / 815 MB |
| Library | 778/4/0 | 778/4/0 | 778/4/0 | 676 / 749 / 749 MB |
| Sessions | 285/9/0 | 285/9/0 | 285/9/0 | 1106 / 1205 / 1206 MB |
| Export | 385/5/0 | 385/5/0 | 385/5/0 | 3371 / 5072 / 5303 MB |
| App | 1014/6/0 | 1014/6/0 | 1014/6/0 | 2832 / 2832 / 2832 MB |
| **TOTAL** | **4286/46/0** | **4286/46/0** | **4286/46/0** | 全轮 < 8G 门，零 MEMFAIL 零 crash |

- **终值对账**：4206（基线）+ 80（M8 全批 ΔN：19+17+31+13）= **4286
  ∈ [4283, 4287] ✓**（预期带正中：4273 M8-2 后实账 + 13 本批分账）。
- **skip 对账**：46 = 基线 41 + **1b probe 族 5**（
  SpectralPerfProbeTests，LIGHTAMER_PERF_PROBE 门）——逐族申报无静默
  吸收；本批零新 skip。
- **运行监视**：`--monitor 21600` 看门狗伴跑全程在位（PID 82010，v1.4
  RSS-KILL 零触发）；每轮 machine-guard 记录在案；测试宿主零清理
  （退出即清）；`caffeinate -dis` 包裹全部轮次。
- **M8-2 遗留 flake 复核**：GoldenColorTests（M8-2 DECISIONS 十二登记）
  本批三轮全绿零复现——环境型归因销账。
- **gui 走查证据**：`.work/gui-acceptance/m8/MANIFEST.md`（迁移 UX 四面
  截图 + v2 readout 活面 + 渲染翻面活面；合成输入环境的 sheet 确认非
  确定性如实申报——持久化活面由 APP bundle 端到端机检承载，人工复核行
  登记）。

## 验收判定（逐条 SC，机检面）

- **T1** ✓ 构建绿；产线 diff = 零（纯测试 + Project.swift 测试数组行）；
  控件清单快照测试在册（31 id 集合恒等 + 活树陌名零）；grep 组零命中
  输出留档（adaptationBandwidth/adaptationSurface/upsampling = 0；
  UserDefaults 键面零新增）；`--bundle App` 定向零回归。
- **T2** ✓ 构建绿；FilmDescriptor/FilmDescriptorProbe 零 diff（源级 +
  FilmDescriptorTests 全绿双证）；v2 臂 probe 形输出在案（E1）+ 读数
  对照落 DECISIONS 五（E2，不断言相等）；probe ③⑤ 终态复测零漂移
  （DECISIONS 四表）。
- **T3** ✓ 构建绿；`git diff --stat` 产线面 = plan 两文件 + 接线三文件
  + xcstrings（DECISIONS 一/二申报）；`.runModal(` 于 App/Sources 零
  命中；LocalizationValue 禁形零命中；zh-audit 双 PASS 输出在案；迁移
  commit 后 sidecar process=2 往返断言在册 + 零 pixel item 断言在册 +
  零自动迁移 grep 在册；`--bundle App` 定向零回归。
- **T4** ✓ 构建绿；diff 面 = NOTICE + AGENTS.md + M3-2 NOTES（勘误行）
  + 一新测试文件；`Resources/FilmProfiles/profiles/` 与
  `neutral_print_filters.json` 与 `MANIFEST.sha256` 零 diff（git status
  核对 + 测试内 pin 计数断言）；MANIFEST 对账既有测试跑绿；措辞旧串
  残留 grep = 零（README/help 命中点清单 = 空，DECISIONS 三）；exposureEv
  负测组绿。
- **T5** ✓ 三轮同值 4286/46/0 ∈ [4283, 4287]（越带申报无）；skip 46 = 41
  + 1b probe 族 5 逐族申报；红即停两次触发的处置 = verdict 口径复核
  （ToneEqualPerf 隔离全绿）+ pin 修复（af84ddc1）；MEMFAIL 零；gui
  走查 MANIFEST 在库（六项证据 + 如实申报面）。
- **T6** ✓ Project.swift diff = 恰两行（T1 App 行 + T4 IOPParity 行）；
  BUNDLE-MAP 两行在库；tuist generate 恒末位；SUMMARY/DECISIONS/
  VALIDATION 预备在库；无生成物入 git（.xcodeproj ignored）。

## 红线机检（plan 红线 17 条对照·高相关项）

- FIX2③：`LibraryProjectController.swift` 零 diff ✓（06ac0d41^..HEAD
  零命中）；McpServerController.swift 零 diff ✓。
- 封存面：DrtRecord/TerminalTailPolicy/DrtTailAssembly/DrtPanelModel/
  DrtPanelView/DrtEotf/Lut3dKernels.metal/ExportQueueContract/六格式导出
  矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/NodeGraphCommand/
  LightamerSidecar（v11 零 bump）/HistoryStack/HistoryHash/PipelineDocument
  /V50Order/GradeCatalog/Registry/ModuleInstance 全零 diff ✓；
  **FilmSubRunKernels.metal 零 diff** ✓；FilmSubRun 密度冻结面
  （FilmFilterPackSolver/assembleDensityFilmLeg/film_subrun kernel）零
  diff ✓。ExportRenderer 非封存面（红线 2 清单外——DECISIONS 一申报面）。
- 零 FilmRecord 字段（键集冻结七键断言在册）/ 零 sidecar 新键 / 零
  schema bump / **零 UserDefaults 新键**（红线 3/11——迁移动作不落偏好）
  ✓。
- xcstrings 尾块纯插入（+96 行零删除行）+ zh-audit 双 PASS ✓（红线 4）；
  LocalizationValue 禁形零命中 ✓（红线 5）。
- L041：两测试文件各自入数组同批 + tuist generate 末位 ✓（红线 6）。
- 机器级单重活（红线 7/9）：全部 xcodebuild/tuist/test-direct 前置
  guard（G4 贴线震荡逐轮修剪我方构建缓存换通行，DECISIONS 六.4；未获
  授权未绕门）；--all = orchestrator 派单预批（红线 9 批准制兑现）；
  `--monitor 21600` 看门狗伴跑在位；只杀自出 PID（零 kill）✓。
- probe 纪律（红线 8）：LIGHTAMER_PERF_PROBE 门 + L014 fence + RSS 口径
  ✓（T2 复测轮）。
- L057（红线 13）：`.runModal(` App/Sources 零命中；确认 sheet =
  SwiftUI sheet ✓。
- 默认中性零行为门（红线 12）：pristine 文档 v1/v2 逐位恒等（既有 D 组
  跑绿）；缩略图恒 legacy（threading 的 .thumbnail 门）；导出面零新增
  开关（$jobFilmTail 递缝零改；export process 跟随文档 = 红线 12 本式）
  ✓。
- 测试落域（红线 14）：FilmPanelSpectralUITests ∈ App、
  SpectralExposureSemanticsTests ∈ IOPParity ✓。
- commit 纪律（红线 15）：每任务独立 commit（`test(m83)`/`feat(m83)`/
  `docs(m83)`，零 issue ref，只 add 相关文件）✓。
- GPL 合规（红线 16）：本批零 GPL 转录件 ✓。
- process 账本（红线 17）：M8-2 专属，本批零 bump ✓。
- C 档门控：本汇报后停（VALIDATION 前）✓。

## 偏差清单（逐条，正本 = M8-3-DECISIONS 八）

1. `(deviation)` 生产面 renderProcess 接线三文件（M8-2 欠账，D-M8-1 读
   面完成）——DECISIONS 一。
2. `(deviation)` 迁移 marker item（零 pixel item 读法）+ undo 边界
   （撤 marker 不撤 process）——DECISIONS 二。
3. `(deviation)` commitProcessMigrationMarker 落 EditorState.swift 本体
   ——DECISIONS 二末件。
4. `(deviation)` ProcessVersionCarrierTests 双 pin 机械移动（M8-2 漏网）
   ——DECISIONS 六.1；同类三 pin（Library Import/Metadata + Sessions
   BatchApplier）= `af84ddc1`——T5 全量对账抓出的第二组漏网面。
5. `(measured)` 迁移端到端 240s（cmax per-run 观察项）——DECISIONS 六.3。
6. `(measured)` 措辞命中点 = NOTICE/AGENTS/M3-2 NOTES 三处，README/help
   零命中——DECISIONS 三。
7. `(measured)` --all 红即停两次（ToneEqualPerf 环境型 + 陈旧 pin）→
   装配式三轮对账（DECISIONS 六.5 形态）；ToneEqualPerf 隔离轮全绿
   verdict。

## 遗留与移交

- **cmax per-run 重建**：迁移端到端 240s 实测把 M8-2 DECISIONS 七的
  观察项放大到 App 测试域——升格第二缓存面的立项输入（挂账 M8-3+）。
- **descriptor v2 重锚定**：probe scan 面仍密度域（DECISIONS 六.2
  posture）；v2 臂 probe 形输出已在案（工厂/盒两级），未来重锚定的
  起点面。
- **Data 卷贴线**：G4 门（25GB）与系统卷常态 ~25.5GB 自由空间的长期
  张力 = 编排侧资源注记（DECISIONS 六.4）。

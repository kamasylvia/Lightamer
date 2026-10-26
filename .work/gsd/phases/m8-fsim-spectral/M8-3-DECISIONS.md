# M8-3-DECISIONS — FSIM 面板+收口执行期裁决（2026-10-26）

> 正本关系：charter = `CONTEXT.md`（D-M8-6/D-M8-7/D-M8-8 + 红线 17 条 + 亲核
> 登记⑦）；执行正本 = `M8-3-PLAN.md`（checker `40bccfd3` + fixer `dd9490fe`
> + R1 `bc2baf39` 后 HEAD）。本文 = 执行期偏差申报 + 迁移 UX 形态登记 +
> 措辞命中点清单 + probe 复测对账。行内 `(deviation)` = plan 文本偏离；
> `(measured)` = 实测锚定。

## 一、生产面 renderProcess 接线（M8-2 欠账补齐——最大偏差申报）

`(deviation)` plan files_modified 未列 `PipeCoordinator.swift` /
`WorkspaceModel.swift` / `ExportRenderer.swift`，但**没有它们迁移 UX 是
视觉 no-op、光谱核在产线永不可达**：

- **缺口本体**：M6-2-01 注册的「coordinator threading = first fork
  batch's registered follow-up」（PixelPipe.swift M6-2-01 T2 注释原文）
  在 M8-2 未兑现——`renderCurrentChain` / `ExportRenderer` 均不传
  `renderProcess:`（默认 `.legacy`），`assembleFilmLeg` 的 exhaustive
  switch 在产线恒走密度臂。M8-2 mint 已给新档盖 `process: 2`，即
  **M8-2 后全部新文档 sidecar 标 v2 而渲染恒 v1**——D-M8-1「process ≥ 2
  = 光谱核」裁决的可执行前提 = 存在读面。
- **兑现面（本批）**：①`renderCurrentChain` 两入口（`RenderPipeline
  .process` / `.processComposite`）传 `workspace.processVersion(for:)`——
  **thumbnail 恒 legacy**（M3-3 thumbnail 门孪生，缩略图缓存键空间不动）；
  ②`ExportRenderer` 从磁盘 sidecar `document.process ?? .legacy` 派生
  （override 臂同读磁盘——红线 12「filmTail 跟随文档 record + process」
  的 export 面）；③其余调用点零触（ColorMatch filmTail nil /
  QuickLook 无 filmTail / SessionThumbnail+Culling = thumbnail 域）。
- **测试安全面**：既有测试全部经 `RenderPipeline.process(filmTail:…)`
  显式传参（默认 `.legacy` 不变）或走 `filmTailPolicy(for:)`（无 process
  维度）——零回归亲证（App 全量 1014/6/0 + IOPParity 定向轮）。
- **裁决依据**：D-M8-1 单源键语义的实现完成 ≠ 扩面；不在 plan 停手清单
  （新增光谱控件/adaptation 开关/自动迁移/profile JSON/UserDefaults 新键）
  之列。

## 二、迁移 UX 形态（M6-2 §6 正主兑现 + undo 边界裁决）

- **动作形态**：`FilmMigrationAction` 纯模型（evaluate 表：v1/legacy 可
  迁、v2/forward 已当前、film 拖拽在飞拒、无 film record 不适用——
  process 只影响 film leg，无 film 文档迁移无渲染语义）→ 面板行
  （v2 档隐藏 = 零观感差）→ 确认 sheet（L057 缝——SwiftUI sheet 非
  runModal；内容面 init 参数注入零 `@Environment` 读——M2-8 sheet 环境
  危险类**结构性缺席**，负腿形态不适用，以真实 sheet 挂载测试钉面）。
- **commit 形态**：`runProcessMigration` 一次离散步 = 载体升 2
  （`WorkspaceModel.setProcessVersion` = **M6-2-01 注册的首个 runtime
  写面**，唯一生产调用者）+ **一枚文档级 film-scope marker item**
  （`history_process_migrate`，payload = 当前 film record 逐字不变——
  「迁移非数据变换」；零 pixel item，实例集零污染）+ 重渲染 + sidecar
  写（process=2 落盘）。
- **undo 边界**（M6-2 §6 前瞻的裁决落地）：⌘Z 撤 marker **不撤 process**
  （HistoryStack 封存面零 diff 红线——process 无 history 槽位）；M6-2
  前瞻「迁移可 undo」降级为 marker 语义，不可逆面 = 无（process 是渲染
  代际非数据变换，回滚窗口 = plan 前置红线第 4 条 clamp 语义）。
  `(deviation)` plan T3 验收「history items 零增量」按「零 pixel item」
  兑现（marker item 在册）——plan SC 的 `history_process_migrate（commit
  键）` 与「零 item」两句按此读法自洽。
- **键族**：`history_process_migrate` + `panel_film_migrate_body/button/
  cancel/confirm/title` 六键 xcstrings 尾块纯插入（+96 行，diff 实测）；
  zh-audit `--check`（1726 source keys / 2041 catalog keys）+ `--self-test`
  双 PASS。
- **零自动迁移负测**：grep 实录（`setProcessVersion|runProcessMigration|
  commitProcessMigrationMarker` 于 App/Sources）= 写面唯一调用者
  `runProcessMigration`，迁移面唯一调用者 `FilmPanelModel.runMigration`
  （面板 confirm 路径）；载入腿两分支（restore prime / pristine mint）
  走 `restoreProcessVersion` 原面孔未触。
- **末件注记**：`commitProcessMigrationMarker` 落 `EditorState.swift`
  本体而非新文件（`projectWriteSuppressed`/`baseInstances` 为 file-private
  ——跨文件 extension 不可达；新文件承载纯模型 `FilmMigrationAction`）。
  `(deviation)` plan files_modified 的「EditorState+FilmMigration.swift
  = 迁移动作」按纯模型兑现。

## 三、措辞批修命中点清单（D-M8-6 三面）

1. **NOTICE §2 消费披露升格**（我方文件可改）：「are NOT consumed as a
   spectral forward model … the density domain only」→「ARE consumed as
   a per-wavelength material chain …（DIR coupler 结构在位出厂中性——
   profile 集无 coupler 测量数据）… metameric reconstruction」；密度域
   消费面保留为 v1 冻结臂披露。诚实性注记：couplers-off 出厂态写明
   （M8-2 DECISIONS 四的承接）。
2. **用户可见措辞升格**：「光谱重建材质模拟（逐波长），非场景光谱重放」
   ——README/help 面 grep 实测**零命中**（旧措辞仅存在于 NOTICE/AGENTS/
   M3-2 NOTES 三处历史文档面）；xcstrings 零命中。命中点清单 = 空
   （`grep -rn "物理流程建模|非光谱重放|physical process modelling"
   README.md App/Sources LightamerCore/Sources docs` = 零行）。
3. **历史文档勘误行追加（原文不改）**：AGENTS.md M3-3 增量节「光谱不可达
   架构注记」bullet 下追加勘误行（M3-3 惯例）+ M8 里程碑行补 M8-3 增量
   面；M3-2 `RESEARCH-NOTES.md` §1 勘误块后追加第二勘误行（2026-10-08
   首勘误先例同式）。

## 四、probe ③⑤ 终态复测对账（T2，M8-2 集成后二进制）

`LIGHTAMER_PERF_PROBE=1` IOPParity SpectralPerfProbeTests **5/0/0**
（315s，peakRSS 1282MB）——对 M8-1B 记录**零数值漂移**：

| 探针 | 终态实测 | M8-1B 记录 | 判定 |
|---|---|---|---|
| ③ footprint | ds4 corrPlane=95MB / ds8=23MB（全链 physFootprint 3231MB 级） | ds4 95MB / ds8 23MB | ✓ 1/4 裁决面不变 |
| ⑤ fma | bareVsPinned=1357/4608, worstAbs=5.96e-8 | 1357/4608, 5.96e-8 | ✓ |
| ⑤ 取倒 | differingSweeps=574/2000 | 574/2000 | ✓ |
| ⑤ 多项式 | hostVsLibmMaxAbs=4.77e-7（device 逐位） | 4.77e-7 | ✓ |
| ④ 哨兵 | ramp512=10129511468721193651 | 同值（登记消费） | ✓ |
| ① tc 构建 | 298.7s（Debug 28 对） | 317.8s → gate 600s | ✓ 带内 |

probe ③⑤ 的 coupler 降采样臂决策（1/4）与求值序在终态二进制上复验成立。

## 五、读数对照表（T2 E2，双档 probe 输出，by design）

同 probe ramp（1024×1，0.184·2^E，E∈[−12,+12]，portra×endura，histogram
nil，默认 record）经同工厂双臂 + 生产 FilmMethodBox dispatch：

| 臂 | 输出面 FNV-1a | 中点 luma（0.2627R+0.6780G+0.0593B） |
|---|---|---|
| 密度（默认 call form——生产 descriptor probe 面） | 2170697048830956364 | 0.18535016 |
| 光谱（renderProcess 2——工厂跟随面） | 8672147073903936103 | 0.18041790 |

读数差 = 核换代语义（D-M8-7 by design），非回归；生产 descriptor probe
call site 保持默认臂（密度锚定 posture——M3-4 宽容度数学的标定面；
FilmDescriptorCache 键无 process 维，posture 登记于本文六.2）。

## 六、其他裁决与注记

1. **`ProcessVersionCarrierTests` 双 pin 机械移动**（`fix` 面随 T3 commit）：
   两处 literal `as? Int == 1` mint 面钉 → `current.rawValue`（30a05d20
   同式）。根因 = M8-2 bump 的机械面移动漏网——M8-2 定向轮只跑了
   IOP/IOPParity/Layers，App bundle 未重跑；本批 App 全量轮抓出。非本批
   回归（M8-2 HEAD 上同失败）。
2. **descriptor 生产 posture 登记**：宽容度 descriptor/probe 本批保持
   密度域锚定（probe 的 scan 面 = 密度域数学 systemDensity；换 v2 需要
   scan 面重推导 = 面板数学重标定——D-M8-8 同域理由，零收益不做）；
   v2 臂的 probe 形输出已在工厂/盒两级在案（T2 E1/E2），为未来重锚定
   预留。
3. **迁移端到端测试时长** `(measured)`：239.9s——迁移触发重渲染走光谱臂
   （tc 表 build + per-run payload 重建含 cmax 64×720×18 轮二分，M8-2
   DECISIONS 七的 cmax 观察项在 App 测试域实测放大）；非测试缺陷，观察
   项数据点登记。
4. **机器资源注记**：Data 卷可用空间全程贴 G4 门（25GB）运行——执行期
   多次 GUARD BLOCK（24000-25500MB 带内震荡），以我方可再生构建缓存
   （Intermediates/Index/SourcePackages/SDKExplicitPrecompiledModules/
   ModuleCache）逐轮修剪换通行；用户域缓存（go-build 3.6GB 等）未触。
   T5 --all 轮在 trim 后基线 ~25.7GB 通过。
4. **T5 红即停两次处置**（对账轮实录）：①`ToneEqualPerfTests
   .testPreviewFullChainFrameTime` --all 热态 157.9/135.3 双败 vs 隔离轮
   77.6/105.4 全绿 = 环境型 flake verdict（M2-11-01 口径 + M8-2 DECISIONS
   十二同族；本批零触该路径——filmTail nil 对 renderProcess 线程不可
   见）；②Library/Sessions 的三处 literal-1 陈旧 pin（M8-2 漏网第二组，
   `af84ddc1`）。三轮以逐 bundle 门控装配式执行（每调用前置 guard
   --wait），TOTAL 4286/46/0 三轮同值 ∈ [4283, 4287] ✓；GoldenColorTests
   （M8-2 十二登记）三轮零复现 = 环境型归因销账。
5. **SidecarStore 去抖写观察项（gui 走查期发现，M8-3+ 挂账）**：probe
   空闲实例上 debounce 写从未自发落盘（两次会话一致；quit 的
   termination flush 才落）——正常会话路径由
   ProcessVersionCarrierTests 真盘写读机检覆盖，非缺陷定性。
6. **--all 装配式对账形态**：`--all` 的红即停（"前序 bundle 红即停"）
   与环境型 flake/陈旧 pin 组合下，单次调用不可收敛；装配式（每 bundle
   独立调用 + 每调用 guard --wait）= 本批对账形态登记，供后续收口轮
   引用。

## 七、ΔN 记账（分账带 +10..14）

| 任务 | commit | 测试增量 | plan 带 |
|---|---|---|---|
| T1 UI 零新增 | `06ac0d41` | FilmPanelSpectralUITests **3** | +2..3 |
| T2 probe 跟随 | `1890febe` | DualArmGolden 扩 **2** | +2..3 |
| T3 迁移 UX | `d6a3c32f` | FilmPanelSpectralUITests 扩 **4**（模型表/端到端/sheet 挂载/inert 负测） | +4..5 |
| T4 曝光语义 + NOTICE | `0809be19` | SpectralExposureSemanticsTests **4** | +2..3 |
| T5 --all | `af84ddc1` + 收口轮 | 0（对账式；pin 修复 = 既有法期望值改写零增量） | 0 |
| T6 收口 | 收口 commit | 0 | 0 |
| **合计** | | **+13** ∈ [+10, +14] ✓ | |

越带申报：无（T4 +4 顶格 = NOTICE 断言组 + uniforms 双钉面各一法，
均在 plan 行语义内）。

## 八、偏差清单汇总（逐条）

1. `(deviation)` 生产面 renderProcess 接线三文件（PipeCoordinator/
   WorkspaceModel/ExportRenderer）——本文一（M8-2 欠账，D-M8-1 读面）。
2. `(deviation)` 迁移 marker item（plan「零 item」读法收窄为零 pixel
   item；undo 边界 = 撤 marker 不撤 process）——本文二。
3. `(deviation)` `commitProcessMigrationMarker` 落 EditorState.swift
   本体（file-private 成员域）——本文二末件。
4. `(deviation)` ProcessVersionCarrierTests 双 pin 机械移动（M8-2 漏网
   面修复）——本文六.1。
5. `(measured)` 迁移端到端 240s（cmax per-run 观察项放大）——本文六.3。
6. `(measured)` 措辞命中点清单 = NOTICE/AGENTS/M3-2 NOTES 三处，README/
   help 零命中——本文三。
7. `(deviation)` Library/Sessions 三 pin 机械移动（`af84ddc1`，M8-2 漏网
   第二组）——本文六.4。
8. `(measured)` --all 装配式三轮对账（红即停处置）——本文六.4/六.6。
9. `(measured)` SidecarStore 去抖写 probe 环境观察项——本文六.5。

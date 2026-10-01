# M2-6-3 SUMMARY — 面板 + EOTF 联动 + HDR 视口 + Post 四件迁移 + 收口（wave 3，7 任务）

> 执行：ZCode subagent worker，2026-10-01 夜间连跑（`paused=false`/`auto=true` 每任务
> 边界核过）。正本 = M2-6-3-PLAN.md（checker 修正版 905e979：E3 follow gate 扩展 +
> E5 键折叠 post-params + m2 同位订正 + m5 分支措辞，全部落地）。基线 = 2435/16skip/
> 0fail（P2 验收后口径）。

## 任务逐条（commit SHA）

| 任务 | 交付 | commit |
|---|---|---|
| T1 | DRT 持久化四件（carrier/写腿/restore 腿/run 传点）+ HistoryItem additive `drtRecord` + `commitDrt`/`drtDocumentScope`/`effectiveDrtRecord` + historyHash DRT 折叠（set-fields-move）+ sidecar history item 投影同步 + `driftDetected` 同式重算 + live/commit 三件 + undo/redo/jump carrier 同步 + DrtPersistenceTests 7 法（APP） | `feat(app): drt persistence with document history integration` |
| T2 | `DrtPanelModel`（读三级投影 + 三动作面 + 结构描述符 + peak 三件式）+ `DrtPanelView`（Method 恒展开/Color & Encoding/aces20 限色组/opendrt 预设三件套）+ 占位特面退休（枚举保留、渲染臂换真面板——DECISIONS D1）+ 35 面板键入账 + 1 键退役 + DrtPanelModelTests 6 法（APP） | `feat(app): display transform panel with method card` |
| T3 | EOTF 联动吸附（模型 T2 已落；本批 = 矩阵测试批）+ 模型读面改 history 真相（真缺陷①）+ 通知腿 history 同步（真缺陷②）+ 吸附矩阵（pristine 入口 6 target + (space,legal EOTF)×target 顺序状态机 ~60 组合机检）+ 原子 undo + picker 单源钉 + DrtPanelModelTests 6→9 法 | `feat(app): eotf linkage snapping for encoding space` |
| T4 | 视口四态（DRT-SDR/DRT-HDR/DRT-linear/legacy 双面）+ `DrtSurfaceSpec` 推送 + BlitRegime 两臂（drtSDR/drtFloat16，legacy 三臂默认参零差）+ **E3 follow gate 扩展**（`followGateActive` 纯函数 = `!edrActive && !drtTailActive`）+ colorspace 终式（itur_2100_PQ/HLG——SDK 无 extended 变体，plan 字母修正）+ 互斥双层面 + DrtViewportTests 6 法（APP） | `feat(app): hdr viewport for drt encoded output` |
| T5 | Post 四件主链 skip + `TailOrderedBox` 槽位重放（74.1+，原 box 转发零新 kernel）+ 种子折 post 集（E5，空集零折叠 P1 位等）+ 尾平面格式修正（EOTF 前 float32 + P1 输入面缺陷退休）+ App 侧 catalog 注入 + Look 页四注摘除 + 键退役 + DrtPostMigrationTests 6 法（LAYERS）+ EditorStackRoutingTests note 翻面（E4 先例申报） | `feat(iop): migrate post four after display transform` |
| T6 | zh-audit PASS（1282 源键/1495 目录键）+ TAB-MATRIX 勘误行（displayTransform 页 + Look 页四行 + IA 节）+ FEATURE-MAP 45→53 勘误注记 + AGENTS.md M2-6 增量节 + bench 观察行测试（OQ-10）+ method 注册口机检（Registry 零 diff 核）+ DrtPostMigrationTests 6→7 法 | `chore(m2-6): method registry closeout zh audit and tab matrix errata` |
| T7 | 本文件 + DECISIONS + GOAL-STATE phase 翻账 + TODO 收口 + EditorStackRoutingTests 转录断言翻面（TAB-MATRIX 实态同步）+ 收口提交 | `docs(m2-6): close out plan 3 and the m2-6 phase` |

## 测试数变化（对账 = BUNDLE-MAP 行）

- 基线 2435/16skip/0fail → **终态 2464/16skip/0fail**（+29 = 7+9+6+7，逐行对账精确）。
- 七 bundle 终态（逐 bundle 定向轮，T7 终跑口径）：IOP 467/1、IOPParity 362/3、
  Layers 268/3、Library 430/4、Sessions 279/4、Export 260/1、App 398/0。
  和 = 2464，skip = 16（全部既有在案 skip）。`--all` 未触发报备需求（P1/P2 同款
  定向轮等价覆盖，七 bundle 全绿）。
- 执行期 flake 一次：App 全量 `EditorStackRoutingTests
  .testTabMatrixMatchesTheRoutingTableLineByLine` 1 fail——非时序，是 T6 的 TAB-MATRIX
  勘误把「arrives with M2-6」占位文字换掉后转录断言未随动（T6 文档批的机械遗漏），
  T7 翻面修正（`DrtPanelView` marker）+ App 全量复跑 398/0/0 绿。

## AC 总表核验（逐条机检）

| # | AC | 结果 |
|---|---|---|
| 1 | 持久化链（carrier 隔离/写腿一次/restore 三态/undo-redo 一步回/hash 折叠/旧档零漂移/pristine 不写 key） | ✅ DrtPersistenceTests 7/0 |
| 2 | 面板（Method 恒展开 + FEATURE-MAP §5 逐行 + 预设单 commit + custom 派生 + peak 钳制 + Vignette 原位 + 占位不再产生） | ✅ DrtPanelModelTests 9/0 + grep 审计（枚举处置 = DECISIONS D1） |
| 3 | EOTF 吸附（矩阵机检 + 原子 commit + 联动单源） | ✅ DrtPanelModelTests（矩阵 ~60 组合）+ grep（App 层零第二实现） |
| 4 | HDR 视口（四分支矩阵/非 DRT 逐字节/手动 EDR 原样/互斥/colorSpace 非 nil/E3 gate） | ✅ DrtViewportTests 6/0 + 既有 EDRViewportTests 5/0 零差 |
| 5 | Post 四件（skip/尾段序/golden 重钉/键局部性/非 drt 零回归） | ✅ DrtPostMigrationTests 7/0 + DrtTailTests 12/0（P1 face 保持） |
| 6 | `panel_note_pre_drt` 零残留 + TAB-MATRIX 勘误行 + 注册面零 diff | ✅ grep 零残留 + Registry/PipelineDocument/NodeOwnershipCatalog/V50Order/PipeCacheKey 五文件 `git diff` = 0 |
| 7 | zh 全落账 + audit PASS + 专名不译 | ✅ PASS（1282/1495/{en,zh}） |
| 8 | 红线五文件零 diff + PixelPipe/EditorMTKView 半径逐 hunk | ✅（PixelPipe = skip 集/插槽/种子折/格式面；EditorMTKView = surface/两臂/gate/终式） |
| 9 | 全套 0 fail，计数 ≈ 基线 +25..40 | ✅ 2464 = 2435 + 29（定向轮双读） |
| 10 | diff 边界 + 测试登记闭环 + front-matter 申报 | ✅ 24 文件 = 申报 21 + E4 先例补充 3（EDRControlView/EditorAreaView/EditorStackRoutingTests——各 commit body 申报；LayerCompositeDriver 零 diff：postOpNames 随 TerminalTailPolicy 携带，透传零改动） |

## bench 观察行（OQ-10，非门）

- DRT 尾段全链（method + post 四件 + EOTF，SDR record）@ PREVIEW 2560 长边合成图：
  **cold 117ms / warm 85ms**（同进程二次渲染，缓存热）。
- FULL 1024×640 小图全链：**20ms**。100MP 全幅 bench 非 gate（60fps 复验归 M2-11 惯例）。

## 重校准锚表（DECISIONS D4 摘录）

| 模块 | 尾段 solo 参数 | 中心 BGRA |
|---|---|---|
| sharpen | 2.0/0.8/0.0 | [149,149,149,255] |
| equalizer | g0 0.5 | [149,149,149,255] |
| bloom | 默认 | [149,149,149,255] |
| grain | 默认 | [145,146,146,255] |

kernel/reference 字节零改（零新 kernel 红线）；display 域视觉强度 = 走查观察项。

## 走查观察项清单（纪律 11，非门，待 gui 轮）

1. HDR 屏实机 DRT-HDR 预览 + 非 EDR 屏 PQ/HLG 降容显示（未备实机）。
2. DRT-HDR drawable 的 canvas mat 深浅（linear clear 值在 PQ 域的解释）。
3. Post 四件 display 域视觉强度（bloom scene 锚 / grain 曝光曲线观感）。
4. EOTF 切换 FULL 大图时延（尾平面重算，PREVIEW 桶 ms 级已由键局部性保证）。
5. 预设三件套手感（Look/Tonescale/White picker 单 commit 语义）。

## 执行期偏差与发现

1. **两处执行期悬决**按 plan 授权钉死并签注 DECISIONS：HistoryItem snapshot 槽 =
   占位 + drtDocumentScope 忽略面（D6）；specialContent 枚举 = 保留 case 换渲染臂
   （D1）。
2. **真缺陷两枚**（T3 矩阵测试揭穿，修在模型/协调器）：①面板读 carrier 滞后于异
   步同步 → 快速连点基于陈旧记录提交（改读 history 投影 + liveRecord 拖动层）；
   ②滞后通知 Task 用捕获值覆写 carrier → undo 后被旧值踩脏（改 history 真相同步，
   幂等）。
3. **P1 缺陷退休一枚**（T5）：主链顶面（尾段输入）在 .drt 下走显示格式 → SDR
   record 的 DRT 输入被量化到 8-bit scene-linear；Post 插入会继承放大 → 主链顶面
   回 float32（DECISIONS D9；DrtTailTests 12/0 保持绿）。
4. **plan 字母修正一枚**（T4）：SDK 无 `extendedITUR_2100*` colorSpace 常数——终
   式落 `itur_2100_PQ/HLG`（绝对编码无需扩展变体；DECISIONS D2）。
5. **机械翻面两处**（E4 先例，commit body 申报）：EditorStackRoutingTests 的 D9
   note 钉翻 absence（T5）+ TAB-MATRIX 转录断言钉 `DrtPanelView` marker（T7）。
6. **LayerCompositeDriver 零 diff**（front-matter 申报内）：postOpNames 随
   `TerminalTailPolicy` 携带，driver 透传面天然零改动。

## M2-6 phase 全景（3 plans 终态）

| plan | 交付 | 终态 commit |
|---|---|---|
| M2-6-1 | OpenDRT 核（DrtRecord/EOTF 七函数+kernel/Float64 参考/kernel golden/预设三件套/sidecar v6/TerminalTailPolicy+尾段装配） | 4289f12（验收 9ff9dc3 pass 0E3m） |
| M2-6-2 | ACES 2.0（CAM16/JMh/限色七表+RGC/ODT 参考/kernel+method 分派；Apache-2.0 署名链） | d678118（验收 12888dc pass 0E0m） |
| M2-6-3 | 面板 + 联动吸附 + HDR 视口 + Post 四件迁移 + 持久化链 + 收口（本 plan） | 本批 |

**M2DRT 全族终态**：M2DRT-01 面板 ✅、02 预设三件套 ✅、03 ACES 2.0 ✅、
04 Color & Encoding + HDR 判定 ✅、05 Post 四件 DRT 后一次 ✅、06 method 注册口 ✅
（filmic/sigmoid/agx v1 禁用维持；parity 后评估回归挂账 = AGENTS.md M2-6 节注记）。
REQUIREMENTS 勾选按惯例留 verify-work/签核批（本执行只登记完成态）。

## 交接面

- M2-9 导出腿：EOTF 编码核 + `isHdrEncoding` 判定 + DrtTailParams 复用面已备；
  writer/ICC/队列集成按 ROADMAP M2-9 行接线（输出 ICC = 本图 DRT 编码强制联动）。
- 图库 HDR 标志位：判定 API 已交付，`.lalb` 投影列消费归库面后续 plan。
- M2-11：60fps 复验（本 phase bench 行为基线输入）。

# Plan 07-3 Summary — AI-06/07 集成精修 + Phase 7 终签核

**Status: COMPLETE**（2026-09-24；T1-T6 全部完成；全 suite **845 tests / 6 skip / 0 fail**
（终轮 = touch Tests + `build-for-testing` 重编复跑；基线 830→845 +15 = 07-3 三测试文件
增量；基线演变 788→812（07-1）→830（07-2）→835（07-3 T1+T2 后）→845（T3 +4 / T4 +6））；
未 push）

> 执行班次：T1-T4 由前班 executor 完成（4 commits）后因 provider 停滞被回收；
> T5（终签核 + 移交 + 收口）由续班 executor 完成（本 commit）。

## 任务完成表

| 任务 | commit | 交付 | 验证数字 |
|---|---|---|---|
| T1 MaskToolbar AI 组 + instance 勾选浮层 + 下载三态 | `2fae8ca`（与 T2 合并，D-07-3-T1-2） | `AIMaskEditing` 唯一 bake 通道（D-07-3-T1-1）+ MaskToolbar AI 组（层 A 一键 / 层 B 三态门控复用 app 级 AIDownloadModel，D-07-3-T1-4）+ `InstancePickerOverlay`（checkbox 子集 + 预览高亮零额外推理）+ display tint 扩展任意 payload（D-07-3-T1-3） | `testAIMaskCommitOneSnapshotUndoAndRefineOverwrite`（⌘Z 恰 1 snapshot + PNG 落盘 + landing form + 同文件新 hash 精修逐级还原）+ `testAIMaskSourceFileIdentity` + `testLayerBEntryGateStates`（三态跃迁矩阵） |
| T2 tap-to-segment 第 4 编辑模式 | `2fae8ca`（同上） | `SegmentSession` + `SegmentEditingOverlayHost`（tap 含点/⌥·右键排点/⇧拖 box；13/11 预算满禁点 typed throw；Y 翻转留 `AIMaskPoint`；scribble 升级缝预留——D-07-CONTEXT-4）+ 路由插位 mask>liquify>retouch>segment>crop（D-07-3-T2-1） | `testSegmentRouteMutexExhaustive`（五模式互斥穷举）+ `testSegmentSessionBudgetAndYFlipWiring`（预算 + Y 翻转向量） |
| T3 skinSmooth 面板第 25 席 + 「定位皮肤」 | `62117cd` | `SkinSmoothPanelView`（三滑块 D-H1 + variant 禁用 Picker（D-07-3-T3-1）+ 定位皮肤（decode 帧锚定 + 同 bake 通道，D-07-3-T3-2）+ 保护区显示 toggle）+ InspectorState 注册 + yaw 门 toast 非静默 | PanelWiringTests +4（`testSkinSmoothPanelDispatch` / `testSkinSmoothLayerScopeDragCommitsOnceAndUndoRestores` / `testSkinLocateCommitWritesMaskSlotOneCommit` / `testSkinSmoothEnabledCompositeDiffersFromDisabled`——低幅条纹板防空转，D-07-3-T3-3）；PanelWiring 60/60 |
| T4a 五条覆盖路径 E2E + sidecar 零升级 | `7aab710` | `AIMaskEditPathsTests`（drawn 差集修补 / parametric ⊓ 收紧 / invert 逐字节往返 / 羽化重 bake hash 翻转 / refine 同 maskID 覆盖 + MISS-then-HIT 记账——全走合成自身装配 `MaskCombiner.effectivePlane`）+ sidecar schema 零升级（AI 参数永不落盘） | 6/6 内容级断言（L020 方向 + 字节级）；remove-mask 子树 → 层记录逐字节还原 |
| T4b GUI 验收轮（真机） | `f4c3c3a` | FINDINGS「Plan 07-3 T4 AI 集成 GUI 验收轮」（2026-09-24 16:15-17:05 解锁屏真机 + 7 截图）+ GUI-19/20 登记（D-07-3-T4-1）+ Manual-Only 追加 4 行 | 层 A 真实 CR3 推理 bake `ai-subject-<uuid>.png`；**overlay ΔR 量化（06-03 口径）= 变化像素 10.31% / 黄染新增 8.97% / mean \|Δ\|luma 13.0**；GUI 级 ⌘Z 恰 1（sidecar position 1→0）；层 B 三态走查（zh 弹窗/declined 持久化/置灰引导）；zh 标签首屏全量（L025） |
| T5 Phase 7 终签核 + Phase 8 移交 | 本 commit | `07-VALIDATION.md`（**`status: validated` + `nyquist_compliant: true`**；Per-Task Map 全 ✅ + Manual-Only 7 行汇总 + SC#5 warm 裁定注记）+ `07-DISCUSSION-LOG.md`（SC#1-5 证据指针终节 + Phase 8 移交清单六面 + 遗留对表）+ REQUIREMENTS AI-01/05/06/07 翻账（Delivered ×4）+ manifest「Phase 7 golden 完整性总账」节 + `07-3-DECISIONS.md`（11 条）+ TODO/GOAL-STATE/PROGRESS.log 收口 | 终轮全套 **845/6skip/0fail**（touch + build-for-testing 重编复跑，206.5s）；C 档第 3 停执行记录落 D-07-3-T5-1 |

## 验收标准对账（Acceptance，plan 原文逐条）

- [x] MaskToolbar AI 组 + instance 勾选浮层 + 下载三态（未下载置灰引导/下载中/就绪）+ 首启预下载提示；生成 = ⌘Z 恰 1 commit stackSnapshot —— T1（LayerUIWiring 5 测试 + GUI 真机）
- [x] tap-to-segment 第 4 编辑模式：tap 含/排点 + ⇧box + Y 翻转接线 + 13/11 满禁点 + 互斥路由穷举 + scribble 升级缝注记；精修 = 同 maskID 覆盖重 bake + 逐级 ⌘Z —— T2（+refine 逐级 hash 还原断言）
- [x] skinSmooth 面板四件套 + PanelWiring（三滑块恰 1 commit + 定位皮肤 = mask 槽 1 commit）+ yaw 门提示不静默 + zh 标签（首屏 GUI 轮全量核过；PanelWiring 60/60）
- [x] 五条覆盖路径 E2E 内容级断言 + sidecar schema 零升级（AI 参数不落盘）—— T4a（AIMaskEditPathsTests 6/6）
- [x] GUI 验收轮：overlay ΔR 量化落 FINDINGS（10.31%/8.97%）+ Manual-Only 表 + PLAYBOOK 口径 + 7 截图归档 —— T4b
- [x] **C 档第 3 停执行记录**（D-07-3-T5-1：07-2 用户门已过 + 本轮签核派遣）；SC#1-5 证据指针落 07-DISCUSSION-LOG；`07-VALIDATION.md` validated + nyquist true + 需求注记行；REQUIREMENTS 翻账 + manifest 收口 + Phase 8 移交清单
- [x] 全量 suite 0 fail（845/6skip）；无 /tmp 过程产物入工作区；决策入 `07-3-DECISIONS.md`（11 条）；SUMMARY 落盘

## Phase 7 全阶段收口（07-1 + 07-2 + 07-3）

- **4/4 需求 Delivered**（AI-01/05/06/07）；SC#1-5 全 PASS（SC#2 pore 目检 1 行
  Manual-Only 挂账；SC#5 层 B ready 跃迁受 GUI-20 beta 资产供给阻断——Developer ID
  签名复验 = v1 后观察项）
- 全 suite 788→**845**（+57：07-1 +24 / 07-2 +18 / 07-3 +15）；skip 3→6（层 B 推理
  2 条 + 卡通脸 1 条 = 真模型腿宿主 skip-with-reason）
- 金字塔证据形态：确定性门逐字节 + 语义门方向断言 + float64 参考轨 parity（L017
  AI 变体三轨）+ 内容级 E2E + 真机 GUI 量化
- 遗留零静默：GUI-19/GUI-20 + Manual-Only 5 行 + beta API 漂移升级缝（07-1 遗留 2）
  ——全表见 07-DISCUSSION-LOG 移交清单③

## 遗留/移交

1. **Phase 8 移交清单**（正本 07-DISCUSSION-LOG 终节）：RasterMaskRef / 层栈 API 面 /
   缓存面（零新缓存类）/ skinSmooth 66.5 槽位（与 Phase 8 watermark 77.0/78.0 无冲突）/
   AIMaskService 复用面（pluggable segmentation）/ Vision 推理基建。
2. **GUI-19**（中）：模块行不显示——UI 打磨轮；**GUI-20**（低-中）：Developer ID 签名
   复验层 B 资产下载——v1 后。
3. **Manual-Only 5 行挂账**：tap 手感 / pore 目检（待含人脸样张）/ instance 浮层真机 /
   （闭环 2 行：层 A 真机 + 层 B 三态 UI——详见 07-VALIDATION 表）。
4. GoldenColor flake 既有行继续跟踪（07-2 遗留 4，与 AI 改动无关）。

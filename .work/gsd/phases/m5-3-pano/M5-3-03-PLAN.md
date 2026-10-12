---
phase: m5-3
plan: "M5-3-03"
title: "全景 UI 与收口批（wave 3 = RESEARCH §6 plan-03）——Session legacy merge 菜单第三项「全景合成」+ 简形 sheet（零控件）+ panoMergeHandler seam + enqueue .pano 接线 + _pano 分账 toast + typed 三态 zh 映射面 + zh 键族八键尾块纯插入 + G4 OpenCV 结构对照 evidence + G5 红线机检收口 + G6 走查 MANIFEST + M5-3 VALIDATION 签核 + AGENTS.md 架构增量节"
wave: 3
depends_on: ["M5-3-02"]
autonomous: true
requirements: ["IOP-PANO-01"]
estimated_tests: "+5..8"
test_bundles: [App]
files_modified:
  - App/Sources/Lightamer/UI/SessionBrowserView.swift      # 修改：merge 菜单第三项（browser_menu_pano）+ 全景确认 sheet（简形：标题/正文/取消/开始——零档位控件，OQ-7）+ onPano seam（nil = 隐藏，既有 gate 形）
  - App/Sources/Lightamer/UI/ContentView.swift             # 修改：onPano 穿线第四段（SessionBrowserView 装配点 :461-464 同位——checker minor-1 补登记）
  - App/Sources/Lightamer/Session/SessionCoordinator.swift # 修改：panoMergeHandler seam（mertensMergeHandler/focusStackHandler 同形）
  - App/Sources/Lightamer/UI/LightamerApp.swift            # 修改：app root 接线——enqueue kind: .pano + MergeParams(deGhost: false, tag: nil) + toast_pano_queued + typed 三态 zh 映射面（failureHook 前缀表 → 三 zh 键，纯函数可机检）
  - Resources/Localizable.xcstrings                        # 修改：8 键尾块纯插入（browser_menu_pano / pano_dialog_title / pano_dialog_body / pano_dialog_start / toast_pano_queued / pano_error_alignment / pano_error_disconnected / pano_error_canvas）
  - Tests/LightamerTests/PanoMergeUITests.swift            # 新建（APP/App 级）：seam 存在性/enqueue 参数映射（tag nil → defaultTag "pano"）/菜单可见性 gate/zh 映射三前缀纯函数表
  - Project.swift                                          # 修改：新测试文件登记 target 数组 + tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # 修改：新测试文件增行登记（E2）
  - .work/gsd/phases/m5-3-pano/evidence/opencv-structural-compare/ # 新建：G4 仓外一次性对照（uv 脚本 + 结构对照报告——非门值，KD-5，不入 CI）
  - .work/gui-acceptance/m5-3/MANIFEST.md                  # 新建：G6 走查 Manual-Only 行配方（三重叠样张合一 + crop 观感 + _pano 分账 + 重导入编辑链）
  - .work/gsd/phases/m5-3-pano/M5-3-03-SUMMARY.md          # 新建（T5）
  - .work/gsd/phases/m5-3-pano/M5-3-03-DECISIONS.md        # 新建（T5）
  - .work/gsd/phases/m5-3-pano/M5-3-03-ACCEPTANCE.md       # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/gsd/phases/m5-3-pano/M5-3-VALIDATION.md          # 新建（T5——phase 签核面，SC 三列对表 + 基线对账链 + 七门全表）
  - AGENTS.md                                              # 修改：M5-3 架构增量节（腿形/typed 三态词汇/键族登记/双 pass 内存形/封存面零解封申报）
  - .work/GOAL-STATE.md                                    # 修改：续接点
  - .work/TODO.md                                          # 修改：M5-3 条目
  - .work/LESSONS.md                                       # 如踩坑
---

# Plan M5-3-03 — 全景 UI 与收口批（wave 3：UI 接线 → typed zh 面 → G4/G5/G6 → phase 收口）

> **性质**：M5-3 收尾 plan（依赖 M5-3-02 全绿）。本批执行**用户面与收口**：
> ①Session legacy face merge 菜单第三项 + 简形 sheet + `_pano` 分账 toast
> （Mertens `45bcfe4` 先例同构）；②typed 三态 zh 映射面（Core canonical
> 前缀 → zh 键）；③G4 OpenCV 结构对照 evidence（仓外一次性，非门值）+
> G5 红线机检收口 + G6 走查 MANIFEST；④M5-3 VALIDATION 签核 + AGENTS.md
> 架构增量节。**既有六 kind UI/行为零回退 + 零新 SPM/零 `.metal` 全程**
> 为本批第一红线（G5 终验）。
>
> **基线**：M5-3-02 验收后的实测全套值（对账链 = **3539/22/0** + M5-3-01
> 增量 + M5-3-02 增量；02-SUMMARY 记账后起算）。全套 `--all` 轮照批准制
> （本 plan 收口轮申请——M5-2-02 同款）。

## 已定裁决（生效值，硬约束，不得重开）

承 M5-3-01/02 已列七值；本 plan 承载 UI 与收口生效值：

1. **OQ-7 = A（UI 面）**：`.pano` additive 第七 case + **Session legacy face
   merge 菜单第三项「全景合成」**（Project face 无入口——merge 菜单仅
   legacy 面有，Mertens omp 走查在案）+ **简形 sheet 零/极少控件**（Mertens
   先例：标题 + body 说明 + 取消/开始；文案注明「重叠 ≥30%、同一视点、画布
   上限 2 亿像素、超限等比缩小、恒自动裁边」）；**v1 不做**（V2 挂账）：预览
   合成画布 / 参考帧手选 / use_edits / deghost 类档位（pano 无此面）。
2. **OQ-5 = A（分账面）**：`_pano` 后缀分账（defaultTag 消费已在 02 落地，
   本 plan 走查钉观感）+ provenance details（canvas/gains/crop 快照——02
   已回写，本 plan VALIDATION 对表）。
3. **OQ-1/2/3/4/6 = A（终验面）**：自实现特征链 / 单焦 f+N×R / sRGB 32f
   产物 / 200MP+2..32+8G / 全 CPU——七门全表（G1-G6 + 预算门）入
   VALIDATION，逐门引用 01/02 evidence 正本。

**架构红线（本 plan 全程 + checker 机检面）**：
- **既有 UI 零回退**：merge 菜单前两项（HDR 合并/HDR 合并（Mertens 快速））
  与 focus/stack 项逐字节不动（纯 additive 第三项）；`mertensMergeHandler`/
  `focusStackHandler` seam 零 diff。
- **零新 SPM**（dependencies 块零 diff）+ **零新 `.metal`**（全程 git diff
  grep 截屏入 SUMMARY）+ `LightamerIOP/`/`LightamerCore/Sources/Sidecar/`/
  `Pipe/History/`/`Graph/`（V50Order/Registry）零 diff + sidecar
  schemaVersion 不动 + **ExportQueue/六格式矩阵零 diff**。
- **Robertson/Mertens 路径字节零回退**（六 kind 快照终验）。
- **禁系统随机源** grep 门（P1 KD-3 词汇，全 pano 面终验）。
- darktable GPL 零复制；OpenCV detail 语义只读（G4 脚本仓外，零入仓代码）；
  Lumen MIT 注记在库核验。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 菜单/sheet/seam 形（Mertens `45bcfe4` 先例同构）

- `SessionBrowserView`：merge 菜单第三项 `browser_menu_pano` + 全景确认
  sheet（简形四件：title/body/取消/开始——**零档位控件**）+ `onPano` seam
  （nil = 隐藏，既有 gate 形——hdrMertens 同构）。
- `SessionCoordinator`：`panoMergeHandler: ((_ relPaths: [String]) async ->
  Void)?` seam（mertensMergeHandler :131 同形同位）。
- sheet body 文案（单键承载）：「选择同一视点、重叠约 30% 以上的照片；画布
  上限 2 亿像素，超限自动等比缩小；结果恒自动裁去无效边缘。」——四项生效值
  的用户可见表达（OQ-4/5/7 文案落点）。

### KD-2 enqueue 接线（LightamerApp root）

- `enqueue(kind: .pano, sources: urls, params: MergeParams(deGhost: false,
  tag: nil), sessionRoot: ...)`——tag nil → `defaultTag(.pano) = "pano"`
  分账（LightamerApp :943 mertens 接线同构；deGhost 对 pano 不消费——腿级
  语义，App 恒传 false 显式形）。
- `toast_pano_queued` 完成面照 `toast_hdr_mertens_queued` 同构。

### KD-3 typed 三态 zh 映射面（P1 KD-4 词汇的消费端）

- App 侧前缀表（**纯函数可机检**）：`"panorama alignment failed"` →
  `pano_error_alignment` / `"panorama images disconnected"` →
  `pano_error_disconnected` / `"panorama canvas invalid"` →
  `pano_error_canvas`；非前缀 = 原 message 透传（**既有错误面零变化**）。
- 挂载点 = merge failureHook 既有面（Mertens FAIL toast 同路——hook 消费端
  的显示层映射，Core 错误词汇零改）。

### KD-4 zh 键族（8 键；xcstrings 尾块纯插入）

- `browser_menu_pano` / `pano_dialog_title` / `pano_dialog_body` /
  `pano_dialog_start` / `toast_pano_queued` / `pano_error_alignment` /
  `pano_error_disconnected` / `pano_error_canvas`——历史键字节与顺序零触碰，
  diff = 纯插入（Mertens 5 键先例 +1 类型三态）。
- **提取器硬化对账**：`zh-audit --check` 实跑一轮对账（V15 教训——硬化后
  首轮实抓过真缺口；本批 8 键全静态可见，MISSING 期望 = 0）。

### KD-5 G4 OpenCV 结构对照（research §4 G4 行；非门值不入 CI）

- **仓外一次性** uv 脚本（`opencv-python-headless`）：`cv2.detail.Stitcher`
  链 vs 我方链（M5-3-01/02 数学面）**结构形态对照**——段序（特征→匹配→
  相机→投影→增益→融合→裁切）/门值（ratio/置信度/边门/帽）/裁切行为逐项
  对表 + 小样本数值并记（**非门值**——两实现常数域不同，只对照结构语义）。
- 产物 = `evidence/opencv-structural-compare/`（脚本 + 报告 md）；报告结论
  入 VALIDATION G4 行；脚本零入仓源码树（仓外运行，产物登记 evidence）。

### KD-6 G5 红线机检收口（终验面）

- 六既有 kind 快照/字节零漂移（P1 T4 负测 + P2 landStackProduct nil 路径
  负测 + 本 plan UI 前两项零 diff）三面合一清单。
- 零新 SPM（dependencies 块 diff 零命中）/ 零 `.metal`（全程 git diff
  grep）/ 禁系统随机源（Stack/Pano* grep）/ sidecar schemaVersion 不动 /
  ExportQueue/六格式矩阵零 diff / V50Order/Registry 零触——逐项截屏入
  SUMMARY。

### KD-7 G6 走查 MANIFEST（Manual-Only 行配方）

- `.work/gui-acceptance/m5-3/MANIFEST.md` 行配方：①三张重叠样张合一张
  （同视点扫幅样张——RAW bracket 不适用；fixture 来源 = 用户样张或合成
  TIFF 序列，MANIFEST 注明）②crop 观感（无效边缘裁净）③`_pano` 分账
  落盘名（`<stem>_pano.tif`）④typed 失败 toast（两张无重叠样张 →
  disconnected zh 文案）⑤产物重导入编辑链（打开 → 调整 → sidecar/版本面
  正常 + M4-1 输入色 readout 显示 sRGB）。
- **Manual-Only 依据** = 菜单/画布/步进器合成激活环境级全惰先例（M3-4
  MANIFEST 同款措辞）；omp 实机取证回填可选（M5-2 G6 行 2 先例）。

### KD-8 VALIDATION 签核面

- SC 三列对表（IOP-PANO-01 REQUIREMENTS 行 → Delivered）+ 基线对账链
  （**3539/22/0** + P1 增量 + P2 增量 + P3 增量逐位闭合）+ 七门全表
  （G1 确定性 / G2 合成恢复 / G3 分段 golden / G4 结构对照 / G5 红线机检 /
  G6 走查 / 预算门——逐门引用 01/02 evidence 正本与 perf.md）。
- **挂账汇编**（单一清单）：V2 = 预览画布 / 参考帧手选 / use_edits /
  per-image 焦距 / multiband 融合；perf 观察项 = 探针越门则 GPU 另立项；
  手动 Y/M 增益微调不设（全自动面，research §3.7）。
- M5-4 VALIDATION 兼「全史瘦身手术」第二次衔接注记（strip 集重算非空才
  动手——CONTEXT 下一步原文）。

### KD-9 AGENTS.md M5-3 架构增量节

- 腿形（双 pass 几何/融合分离 + tile 流式 + 行带直写）/ typed 三态词汇
  （canonical 前缀 = App zh 映射契约）/ 键族登记（8 键）/ `_pano` 分账 /
  PanoRNG 种子纪律 / 封存面零解封申报（`2fee806..c5f5dce` 清单外新增面 =
  PanoFeature/PanoMatch/PanoCamera/PanoWarp/PanoGain/PanoCrop 六新文件 +
  FloatTIFFWriter + StagedSet.readRows——全 additive 申报）。

## read_first

1. `.work/gsd/phases/m5-3-pano/M5-3-CONTEXT.md` + `M5-3-01-PLAN.md` +
   `M5-3-02-PLAN.md`/两 DECISIONS（七生效值 + P1 typed 词汇 + P2 落地面
   ——本 plan 全部消费契约）
2. `App/Sources/Lightamer/UI/SessionBrowserView.swift` :150-380（merge 菜单
   两项/sheet/onHDRMertens seam 形）+ `SessionCoordinator.swift` :120-150
   （handler seam 形）+ `App/Sources/Lightamer/UI/LightamerApp.swift`
   :920-960（enqueue 接线形）
3. `Resources/Localizable.xcstrings`（`browser_menu_hdr_mertens` 键块体例 +
   尾块纯插入纪律；`browser_menu_focus_stack` :1296 等历史块零触碰核对）
4. `Tests/LightamerTests/MertensMergeUITests.swift`（UI seam 测试先例形）
5. `.work/gsd/phases/m5-2-mertens/M5-2-02-PLAN.md` T3-T5（UI/走查/收口任务
   体例正本）+ `.work/gui-acceptance/m5-2/MANIFEST.md`（G6 MANIFEST 体例）
6. `.work/gsd/phases/m5-2-mertens/M5-2-VALIDATION.md`（VALIDATION 体例正本
   ——SC 三列/对账链/门全表/挂账汇编）
7. `Scripts/zh-audit.py`（--check 对账；V15 提取器形态）
8. `Scripts/test-direct.sh`（--bundle 分账/批准制 --all）
9. `.work/gsd/phases/m5-3-pano/M5-3-02-SUMMARY.md`（P2 实测基线增量——
   本 plan 对账链起算点）+ `perf.md`（预算门行引用源）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件）；
  新测试文件随任务 commit 登记进 BUNDLE-MAP（E2）+ `Project.swift`
  对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 =
  `Scripts/test-direct.sh --bundle <域>`；全套 `--all` 收口轮申请批准
  （批准后运行中监视：8G 门/kill 线照 AGENTS 资源监控节）。
- **L072**：UI 测试临时文件一律 temp 域 + `defer` 清理。
- **L057**：面板族一律 `PanelPresentation.present` 缝——本 plan sheet 走
  SwiftUI `.sheet`（Mertens 同形，非 NSOpenPanel 族，不触 runModal 禁令；
  `grep -rn "\.runModal(" App/Sources` 零命中门随 G5 复核）。
- **零 diff 红线自证**（T5）：`git diff <M5-3-02 终点 SHA>..HEAD --
  LightamerIOP/ LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Export/
  '*.metal'` 零命中 + dependencies 块零 diff + 六 kind 快照 + 系统随机源
  grep + runModal grep，全截屏入 SUMMARY。
- **G4 脚本仓外纪律**：脚本与运行产物只落 evidence/（仓外执行，源码树零
  Python/opencv 痕迹）。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 菜单第三项 + sheet + seam + enqueue 接线（KD-1/KD-2）+ zh 键族（KD-4）

- read_first 2/3 → `SessionBrowserView.swift`（第三项 + sheet + onPano seam）
  → `SessionCoordinator.swift`（panoMergeHandler seam）→
  `LightamerApp.swift`（enqueue .pano + toast）→ `Localizable.xcstrings`
  8 键尾块纯插入。
- 验收：编译绿；菜单前两项与 focus/stack 项 diff 零命中（additive 目检 +
  git diff 证据）；8 键 zh 值非裸键；`zh-audit --check` MISSING = 0
  （KD-4 对账）。

### T2 typed 三态 zh 映射 + PanoMergeUITests（KD-3）

- read_first 4 → `LightamerApp.swift` 映射面纯函数（前缀表）+ failureHook
  消费点接线 → `PanoMergeUITests`（APP）。
- 验收：`PanoMergeUITests` 全绿——seam 存在性（onPano nil = 菜单隐藏）/
  enqueue 参数映射（kind .pano + tag nil → "pano" 分账名）/映射纯函数三
  前缀正反（非前缀透传）/菜单可见性 gate。

### T3 G4 OpenCV 结构对照 evidence（KD-5）

- read_first 1 → 仓外 uv 脚本（Stitcher 链 vs 我方链结构对表 + 小样本数值
  并记）→ 报告落 `evidence/opencv-structural-compare/`。
- 验收：报告七段链逐项对表结论在册（段序/门值/裁切行为）；**非门值**声明
  显式；源码树零 opencv 痕迹（grep 截屏）。

### T4 G5 红线机检 + G6 MANIFEST（KD-6/KD-7）

- read_first 5 → G5 三面合一清单（六 kind 快照/零 SPM/零 .metal/随机源/
  schemaVersion/ExportQueue 零 diff/V50Order/Registry/runModal grep）+
  `.work/gui-acceptance/m5-3/MANIFEST.md` 五行配方。
- 验收：G5 清单逐项截屏；MANIFEST 行配方含 fixture 来源注记 + Manual-Only
  依据引用。

### T5 VALIDATION + AGENTS.md + 收口（KD-8/KD-9）

- 收口轮：`--bundle App` 定向轮全绿 +（批准的）全套 `--all` 轮拼表
  （7 bundle 定向拼表口径照 M5-2 VALIDATION 先例）+ 零 diff 自证终验截屏 +
  SUMMARY（任务序/键族登记/对账链闭合）+ DECISIONS（KD 偏差/G4 结论/
  V2 挂账确认）→ `M5-3-VALIDATION.md`（SC 三列 + 对账链 + 七门全表 +
  挂账汇编）→ AGENTS.md M5-3 架构增量节 → GOAL-STATE 续接点（M5-3 closed，
  下一步 = M5-4 VALIDATION 兼瘦身手术第二次）+ TODO 同批。
- **双重验收（config `dual_acceptance = true`，m1）**：zcode subagent 独立
  验收 PASS 后 → **串行** omp 二次验收（**严禁并发**；可选含 omp 实机 G6
  取证回填——M5-2 先例）；两路结论落 `M5-3-03-ACCEPTANCE.md`；FAIL 回注
  修复批后重走验收。
- **Phase 签核（VALIDATION）前停（C 档第 3 门）**：verify-work 结论给用户
  过目后签核。

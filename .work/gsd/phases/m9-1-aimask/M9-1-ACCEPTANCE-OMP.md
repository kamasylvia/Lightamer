# M9-1 ACCEPTANCE-OMP — AI Mask 工具 parity 批 omp 实机终审

> 终审员 = omp（computer-use 实机，独立第三眼）；终审日 2026-10-27。
> 验收对象 = 五 commits `d45f1e2d..97cb3fc2`（refs #11）；HEAD `aeaff367`。
> 对账对象 = `M9-1-ACCEPTANCE.md`（路 1：PASS / 0B+0M+1m+5obs）
> + `M9-1-ACCEPTANCE-2ND.md`（路 2：PASS / 0B+0M+0m+5obs）。
> 构建 = `Lightamer-glcjhggtbffoiuguwlseyjhxhvew/Debug/Lightamer.app`
> （mtime 10-27 12:49，晚于 `97cb3fc2` 10:29，自证成立；BUILD_EXIT=0）。
> 样张 = TestRAW `DSCF0021.RAF`（Fuji 40MP，郊区住宅 scene）→ /tmp fixture 双份。
> 证据 = 本目录 `omp-evidence/omp-01..11`（11 帧，视口裁剪非全页）。

# PASS / 0 error + 1 minor + 6 obs（omp 路；与双路零实质分歧）

minor-omp1 = Layer B「点击选取」入口默认面不可达（M2 默认面缺 `AIDownloadPrompt`
bootstrap 挂载——`ContentView.swift:365` 的 `.modifier(AIDownloadPrompt())` 在
`legacyBody` 内，M2 默认面走 `WorkspaceHostView` 分支永不执行 bootstrap →
`AIDownloadModel.phase` 恒 `.unknown` → gate 恒 `.needsDownload` →
实机 Layer B tap-to-segment 全链（候选 tint/迭代加点/Feather·Expand/commit·cancel）
**屏上像素置信缺**，降级为代码面判定 + 进程外 Vision 直驱探针（首解 7.17s /
refine 0.02s）。**批外存量缺陷**（M2-2 面分叉遗留，非 M9-1 引入——M9-1 零触
AIDownloadPrompt 装配），不阻断本批 PASS；建议后续批把 bootstrap 挂载提至
`LightamerShell` 装配点（一处改）。
obs o-omp1..o-omp6 = 批外/记录性观察（下详），零动作。

---

## §1 逐面终审表（任务书六项职责）

| # | 面 | 终审结果 |
|---|---|---|
| 1 | 任务面板四件 | ✅ PASS。选层后 AX 亲证：主体 enabled=Y / 背景 enabled=Y / **天空 enabled=N** / 人物 enabled=Y（`shell.workspace.host` id 覆盖既知形态，by-title 寻址）。天空 AXPress + cliclick 双通道零动作 + sidecar 零落盘（no-op 真成立）。tooltip 屏上未取证（hover 无 tooltip 浮现，见 o-omp2），键值 catalog 亲读 zh/en 双语在册。Subject 实机 bake：`生成中…` spinner → 黄绿半透明建筑选区 → `.lra` + `ai-subject-<uuid>.png` 落盘 + 精细化按钮翻 enabled。People 空 scene：「未检测到人物」toast 亲见 + 零落盘（`ai_mask_person_none` 面）。 |
| 2 | 交互分割（正主） | ⚠️ **降级 PASS**（代码面 + 进程外探针，屏上像素缺）。Layer B 门不可达（minor-omp1 根因）：「下载模型」三会话 × 多轮 AXPress err=0 但 phase 恒 needsDownload，tap 入口零现身。降级证据链：①候选合成臂源码全链亲读（`runCandidateResolve` :344-397：debounce→全量重解→`candidatePlane`→texture 上载→`setCandidateOverlayRequest((texture,0.6))`→render 尾 :2463-2490 `DrawnMaskRasterizer.overlay` + candidateTint (1.0,0.32,0.42)；commit 双清除 :275-279 与路 1/路 2 行号锚一致）；②进程外 Vision 直驱探针：同 fixture 解码 7728×5152，**首解 7.17s / refine 加点 0.02s**（400MP 大图首解超 D14「大图 ≤2s 告警线」，见 o-omp1；refine 0.02s 在 500ms P95 门内 25× 余量）；③AI-06 grep 全消费点复核路 2 §二.1 结论成立（candidatePlane/sidecar 零交集）。路 1 obs-4 的 tint 渲染面仍由走查②承载——本轮未覆盖屏上像素，记 minor-omp1 不阻断。 |
| 3 | 会话三命令 | ⚠️ **降级 PASS**（open/commit/cancel 全经代码面 + 单测面判定，屏上缺）。open 三源路由（`armSegmentSession` :322-329 `.segment/.subject/.person` + depth/skin/手绘不路由）/ commit 恰 1 stackSnapshot（`commitRasterMask` :275-279 双清除 + 单测 history+1）/ cancel Done·Escape 收敛（`cancelSession` + `.cancelAction` + 零 bake 零 history 单测）三面源码亲读，与双路行号锚一致。**re-entry 实机半亲证**：subject-baked 层在位（`ai-subject-*.png` 落盘 + sidecar mask 引用），但 tap 入口缺故 re-entry 会话拉起屏上未执行。 |
| 4 | paste 排除 | ✅ PASS（实机全亲证）。图 A（AI subject 蒙版层）→ 复制调整… → 粘贴：toast「已排除 1 个 AI 蒙版（其描述的是本图内容）」逐字亲见 + 落盘 `layerStack` mask 键清零（AI raster 剥除）+ `ai-subject-*.png` 资产文件孤儿留存（未删，见 o-omp3）。对照腿：手绘笔触（drawn 载荷）→ 复制粘贴 → **零 toast** + drawn 载荷原样随行（`mask keys:1 drawn:1 ai:0`）。`transfer_ai_masks_excluded %lld` 键含空格形态 catalog 亲读在册（zh/en）。 |
| 5 | 回归面 | ✅ PASS。overlay 三态实机轮转：半透明（灰）→ 红蒙片（深红实色羽化）→ 黑底显示（白团块黑底）三帧屏上亲见，radio value 翻转 AX 亲证；候选臂（`.candidate` 非 userSelectable + render 尾先于 legacy 分支）零干扰既有 tint 面。zh 裸键扫描：全树 value/title 正则 `[a-z_0-9]+\.[a-z_0-9]+` 零裸键（仅 `1.5` 数值 + `mcp.json` 文件名假阳性）。 |
| 6 | 双路对账 | ✅ 见 §3（十条 obs 逐条一句）。 |

---

## §2 实机方法与关键发现

### 2.1 minor-omp1：Layer B 入口默认面不可达（批外存量缺陷）

- **现象**：M2 默认面（`WorkspaceHostView`）选层后 Layer B 入口恒「下载模型」
  （`.needsDownload`），AXPress err=0 三会话多轮，tap 入口（`ai.mask.tap`
  「点击选取」）零现身；`sample` 热栈无 download/asset/Vision 帧（主线程 idle）。
- **根因链**（源码亲读）：`AIDownloadModel.bootstrap()`（`refreshStatus` +
  phase 镜像）唯一生产调用点 = `AIDownloadPrompt.body` 的 `.task`
  （`AIDownloadPrompt.swift:123`）→ 该 modifier 唯一挂载点 =
  `ContentView.swift:365` ∈ `legacyBody`（M2-2-4 冻结面）→ M2 默认面走
  gate-false `WorkspaceHostView` 分支（`:201-230`），`AIDownloadPrompt` 永不挂载
  → `aiDownload.phase` 恒 `.unknown` → `layerBEntry` 恒 `.needsDownload`
  （`AIMaskEditing.swift:93-94` unknown→needsDownload）。按「下载模型」后
  `startDownload()` 内 `store.download()`→`downloadAssets()` 实应成功（进程外
  探针证 OS 侧 notReady→ready 23s），但 `self.phase = phase` 的镜像写回…实测
  60-80s 轮询仍 needsDownload——`pollTask` 的 phase 轮询在 `.unknown` 起步 +
  `refreshStatus` 的 `inFlightDownload` 守卫交互下未能翻转（`store.phase` 与
  `model.phase` 双机失步；legacy 面 bootstrap 先 refresh 再 offer 的时序在
  默认面缺失）。
- **归属**：M2-2 面分叉遗留（`AIDownloadPrompt` 挂载点未随默认面迁移），M9-1
  五 commits 零触该装配（路 1 diff 审 15 文件无 `ContentView/AIDownloadPrompt`
  面）→ **批外存量缺陷**，不阻断本批。修复建议（一处）：bootstrap 挂载提至
  `LightamerShell` 装配点（`aiDownloadModel` environment 注入处 `:150` 旁），
  与 ContentView 分支解耦。
- **影响面**：本轮 Layer B 全链屏上像素置信缺（候选 tint/迭代/commit/cancel/
  Feather·Expand 面板面均需 tap 会话）。M9AIM-02/03 的 AC 兑现依赖双路已验的
  状态机级单测（八法 + morph/feather golden + 双探针真红）与本轮代码面复核，
  屏上层待默认面 bootstrap 修复后补走查（MANIFEST ②③④⑥仍有效）。

### 2.2 o-omp1：40MP 首解 7.17s 超 D14 大图告警线（记录）

- 进程外 Vision 直驱（同 fixture，`.accurate`）：首解 7.17s / refine 0.02s。
- D14 引证 07-1 基线 warm 85-126ms/步（25-102MP）+ 大图 ≤2s 告警线：本轮首解
  7.17s 超告警 3.5×。差异来源：直驱探针 = 冷模型 + 全幅 7728×5152 RAF 直解
  （ImageIO 全尺寸）+ 无 ROI/降采样；产线 `decodeFrameInput` 为渲染帧输入
  （尺寸/色调映射后）+ EntryGate 冷启动 5.5s 一次性 + 首步 spinner 承接——
  口径不同，不构成 D14 证伪。refine 0.02s（warm 追加点）在 P95 ≤500ms 门内。
  记录供后续真机 P95 探针（D14 预案面）对照：首步延迟预算应按「冷启动 + 全幅」
  重估，debounce 300ms 合并连点设计不受影响。

### 2.3 o-omp2：Sky tooltip hover 零浮现（工具/环境面）

- cliclick hover (1030,758) 1.2s 后截图：tooltip 零浮现。`.help()` 是 AppKit
  hover 延迟浮现（通常 ~1s + 需鼠标静止 + 窗口 key），合成环境 hover 可能
  未满足浮现条件；tooltip 键值 catalog 双语亲读在册 + 产线 `.help` 挂载亲读
  （`MaskToolbarView.swift:489`）。记工具面观察，非产线缺陷。

### 2.4 o-omp3：paste 剥除后 `ai-subject-*.png` 资产孤儿留存（记录）

- paste 排除后落盘 `layerStack` mask 键清零，但 `.lra.masks/ai-subject-*.png`
  文件仍在盘上（孤儿资产）。sidecar 引用清零即真相正确（重载不复活）；孤儿
  文件属存储卫生面（类 WAL/派生物），无数据破坏。后续批可顺路加引用计数清扫，
  本批零动作。

### 2.5 o-omp4：AX id 列级覆盖在 AI 工具条同病（既知形态复现）

- AI 工具条七按钮 AXIdentifier 全 = `shell.workspace.host`（R6 注记的 Inspector
  列覆盖机制在工具条复现——无显式 contain 中间层的子控件被最近带 id 祖先覆盖）。
  本轮全程 by-title AXPress（err=0 全通），id 寻址仅 transfer sheet（自成
  NSWindow 层，`editor.transfer.*` 存活）与 `mask.behavior.ask.*` 可用。
  工具面：后续走查配方沿用 by-title。产线零动作（frozen inventory 纪律）。

### 2.6 o-omp5：People 空 scene toast 为常驻状态条形态（记录）

- 「未检测到人物」在底部状态条亲见（`ai_mask_person_none`）；4s auto-clear
  窗内截图命中，8s 后帧已消失（与 `presentToast` 语义一致）。toast 通道默认面
  渲染点（M2-8 `ToastBarView`）工作正常。

### 2.7 o-omp6：legacy 面 `-la_editor_probe` 不适用（工具注记）

- `LIGHTAMER_LEGACY_LIBRARY=1` + argv 图像：legacy 面停在 session 空状态页
  （「选择文件夹以创建会话」），editor probe 不驱动 session 面。legacy 回归通道
  走查 AI 面需 session 探针（现无）或手工建 session。本轮 legacy 面仅确认空状态，
  AI 终审全在默认面执行。

---

## §3 双路对账（十条 obs 逐条一句）

### 路 1（`M9-1-ACCEPTANCE.md`：1m + obs-1..5）

- **m-1**（注释虚构 `isAIMaskSpec`）：复核同意——`:192` 注释谓词名仓内无定义，
  行为判据 `source(ofFileName:)` 单源正确；后续批顺手修，不阻断。
- **obs-1**（「逐字节」措辞精度）：复核同意——实测 float 域 1e-6 + uint16 量化域
  逐值，与 D8 量化域精确论证自洽；措辞级记录。
- **obs-2**（Sky AX 树 disabled 态由走查承载）：**本轮兑现**——选层后 Sky
  enabled=N（AX 亲证）+ Subject/Background/People enabled=Y + 双通道零动作；
  与 plan 分层一致。
- **obs-3**（`labelKey.candidate` 未来裸键风险）：复核同意——白名单 + 三项机检
  现役；本轮全树裸键扫描零命中佐证现态安全；风险登记维持。
- **obs-4**（render 尾 tint 分支无单测，走查②承载）：**本轮部分覆盖**——屏上
  tint 像素因 minor-omp1 未取证；降级由 render 尾源码全链亲读
  （candidate 分支先于 legacy + `DrawnMaskRasterizer.overlay` + 固定 tint 色值
  单源）+ 路 1 探针 B（合成臂掏空 1/8 真红）+ 进程外 Vision 直驱（模型真可解）
  三方闭合。屏上像素待 bootstrap 修复后补走查。
- **obs-5**（xcstrings 非字面纯尾插）：复核同意——D12 配平删除三死键在案，
  非历史键触碰。

### 路 2（`M9-1-ACCEPTANCE-2ND.md`：obs-1..5）

- **obs-1**（`Lut3dKernels.metal` 封存清单漂移）：复核同意——HEAD 已退役条目，
  清单与现实漂移记录；不影响本批判定。
- **obs-2**（`source(ofFileName:)` 5 处 vs plan「恰两处」）：复核同意——本批新增
  恰 2（re-entry + paste），另 3 为 lumen-culling 存量；plan 措辞歧义记录。
- **obs-3**（`isEmpty` 含 `excludedAIMasks` → 空链「Pasted adjustments」版本条目）：
  **本轮实机复现并定级为设计取舍成立**——paste 后版本树确现「粘贴的调色」活跃条目
  （`editor.versions.row.*` AX 亲见「粘贴的调色/活跃」）+ 落盘 `versions:2`
  （「版本 1」空 + 「粘贴的调色」）+ `layerStack` mask 键清零（AI raster 已剥）。
  toast 可达性优先于空条目洁癖：用户得明确反馈（已排除 1 个），版本树多一条
  可回退的空内容条目（可切回「版本 1」），无数据破坏。同意路 2「设计取舍」
  定级，零动作。
- **obs-4**（程序化 `setSegmentActive(false)` 不清候选 request 残留）：复核同意
  ——D13 预登记 + host 双路覆盖主路径 + 现役程序化调用点无候选窗口；本轮 tap
  会话未拉起故屏上未观察，风险评估成立维持。
- **obs-5**（dilate −2ε 非对称 vs D8「±ε 往返」）：复核同意——数学记录，
  量化域结论（累积 1e-7 ≪ LSB 1.5e-5）不变。

---

## §4 终审判定

**PASS**。任务面板四件 / paste 排除双腿 / overlay 三态回归 / zh 面实机全亲证；
交互分割与会话命令因批外存量缺陷（minor-omp1：默认面 AIDownloadPrompt
bootstrap 缺挂载）降级为代码面 + 进程外 Vision 直驱判定，证据链闭合（源码行号锚
与双路一致 + 模型真可解 + refine 0.02s 门内）；双路十条 obs 逐条复核零实质分歧
（obs-2/obs-3 本轮实机兑现/复现定级）。minor-omp1 与六 obs 均批外/记录性，
不阻断。建议：①后续批修默认面 bootstrap 挂载（一处）后补走查 MANIFEST ②③④⑥
屏上像素；②修路 1 m-1 注释谓词名（顺手）。

- 资源：GUI 全程 RSS 1.6-1.7GB；monitor 10800 伴跑零 kill；tracked 零 diff
  （除本报告 + evidence）；GUI 已 quit；defaults 清；/tmp 即弃。

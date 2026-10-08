# M3-1-03 SUMMARY — 小件族合并批 + zh 清算 + M3-1 phase 收口

> 收口 2026-10-08（夜间全自动授权）。基线：M3-1-02 验收批终态（`0241a1c` HEAD）。
> 裁决锚：OQ-M3-1-6①（自动降档）/ OQ-M3-1-7①（四任务一 plan）；plan 内「> checker
> 回注」引注（M6 旁路键控 + FULL 桶判定面语义）照办（DECISIONS D3/D4）。引擎零改动
> plan——红线域 `git diff --name-only` 全程零命中（§七）。

## 一、交付面（四任务 + 收口）

- **T1 冲突档选择器**（M2-9-VALIDATION 挂账#4 关闭）：`ExportM2PanelModel` +=
  `collisionPolicy` 会话态字段（Increment 默认 = 历史行为逐位）；命名节三档 Picker
  （`export.page.collision`，档名技术专名 + zh 尾注四键 append 尾部）；run face 经
  `makeRunAssembly` 纯缝透传进 `enqueueExportM2` 既有形参——引擎/`ExportState`/
  legacy sheet 零 diff。`ExportCollisionPickerTests` 5 测（模型默认/写面/装配缝逐档/
  门与投影面/AX 挂载）。
- **T2 peak-ICC 说明行**：`drtReadout` HDR 档（`isHdrEncoding` Core 单源判定）追加
  caption（键 `export_drt_peak_note` 一枚，zh/en 同批）：ICC 只承 space+TRC、peak
  不进 ICC、真容器 UltraHDR（ALCE-02 M4）。SDR 档渲染零变化；`DrtOutputColorSpace`/
  `ExportICCStrip` 零 diff（签名面零触碰红线）。
- **T3 denoise 拖动降档**（OQ-6① 自动）：`EditorState` 旁路面（实例身份键控 +
  先验 enabled 记忆 + upsert 投影强制 + commit 自愈 + 重建清扫）；session →
  coordinator → EditorState 路由；`NLMeansPanelView` 四滑杆 dragBegin/dragEnd 挂点 +
  状态条 toast「预览降档——松手恢复全质量」（键一枚）；松手落既有恰一 commit（零新
  commit 面）。`NLMeansDragDowngradeTests` 6 测。`NLMeansModule`/`PixelPipe` 零 diff。
- **T4 zh 清算**（V14/V15/F1）：标记菜单两处动态键位 → 显式 switch 静态键（11 键
  在册非补键）；`zh-audit.py` 提取器硬化（next-line continuation 形态 1c + self-test
  负测两样例——D5 脚本自测形态）；硬化首轮即抓两枚真缺口
  `search_{exif,clip}_placeholder`（catalog 从未在册 = 运行时 zh 缺失）同批入账
  （D6）；F1 四处 verbatim zh 缺口清账（`project_face_*` 四键，M2-3-4 挂账销账）。
- **T5 phase 收口**：全套 `--all` 报备终轮 + 本 SUMMARY（含 phase 小结）/ DECISIONS /
  AGENTS 增量节 / GOAL-STATE phase 终态 / TODO 清账 / BUNDLE-MAP 对账；GUI 走查批
  （MANIFEST 附录 + 五证据图）。

## 二、任务与提交

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `7a800a5` | `feat(app): export m2 collision policy picker`——model 字段 + Picker + 装配缝 + 4 键 + 5 测 + 登记 + generate 批尾（L041）；定向 5/0/0 + App 654/0/0 + Export 338/1/0 |
| T2 | `158a468` | `feat(app): hdr drt readout peak-icc note line`——readout HDR 档追加 + 1 键；红线零命中 |
| T3 | `c5afe0d` | `feat(app): nlmeans drag-time preview bypass with single commit restore`——EditorState 旁路三防线 + 路由 + 面板挂点 + toast 键 + 6 测 + 登记 + generate 批尾；定向 6/0/0 + App 660/0/0 |
| T4 | `d4ae750` | `fix(app): explicit rating/color menu keys and zh-audit extractor hardening`——switch 化 + 提取器 1c + self-test 扩 + F1 四键 + 2 真缺口入账；App 660/0/0 复跑绿 |
| T5 | 本批 | 收口账本 + MANIFEST 附录 + GOAL-STATE/TODO/AGENTS |

## 三、验收锚（CONTEXT §七 M3-1 相干条目）状态表

| # | 锚 | 状态 | 证据 |
|---|---|---|---|
| 3 | 冲突档：Picker → 队列行为 + 挂账#4 关闭 | **达成** | 装配缝逐档测试 + state 层真队列透传（ExportAssemblyTests 既有面）+ 走查菜单/选择翻转（MANIFEST 附录 #2/#3）；挂账#4 关闭 = 本节声明（M2-9-VALIDATION 历史行未改写） |
| 4 | peak-ICC：HDR 档说明行 + 键入账 | **达成** | 走查双态实测（SDR 无行/HDR 有行 + EOTF 吸附联动活体，MANIFEST 附录 #4）+ `--check` PASS |
| 5 | denoise：拖动降档单测 + 松手一 commit + 实机观感走查 | **状态层达成 / 实机 Manual-Only** | 6 测钉死（D3/D4）+ 实机不可达登记（D8，补走查配方在 MANIFEST） |
| 6 | zh：`--check` PASS + 标记菜单实机中文 + 提取器负测 | **达成** | 1534/1772 PASS + 菜单 13 键 zh 截图（MANIFEST 附录 #5）+ self-test 负测两样例 |
| 7 | 全套：`--all` 终轮绿 + 红线零 diff | **达成**（数字见 §四） | 全套轮 + §七机检 |
| 1/2 | M2GRADE-08 golden / YIYIN-09 走查 | 非 plan 面 | M3-1-01/02 各自 SUMMARY/ACCEPTANCE（本 plan 零触碰） |

M2-9-VALIDATION 挂账#4 **关闭声明**：三档 Picker 在场（Increment 默认）、选择值达
队列（装配缝测试 + 引擎消费面既有断言）、三档行为走查（菜单实证）——关闭判据三条
全落，历史文档零改写。

## 四、测试数字 vs 基线（M3-1 phase 对账链）

| bundle | M3-1 前 | 01 后 | 02 后 | 03 后（终态） |
|---|---|---|---|---|
| IOP | 471/1/0 | 471/1/0 | — | 全套轮实测 |
| IOPParity | 363/3/0 | 389/3/0 | — | 全套轮实测 |
| Layers | 268/3/0 | — | — | 全套轮实测 |
| Library | 581/4/0 | 587/4/0 | — | 全套轮实测 |
| Sessions | 279/4/0 | — | — | 全套轮实测 |
| Export | 337/1/0 | — | — | 338/1/0（定向轮实测） |
| App | 630/0/0 | 635/0/0 | 649/0/0 | **660/0/0**（定向轮实测） |

**登记面终值对账式**：2962（基线 2961 + `08dd061` +1）+ 37（01：IOPP 24 + LIB 6 +
APP 5 + Golden 2）+ 14（02：YiyinSheetSizingTests）+ **11**（本 plan：Picker 5 +
Bypass 6）= **3024**；登记面起算 3013（2999+14）+ 11 = 3024 两式互证。**全套 `--all`
终验轮实测 TOTAL = 3024/16/0**（§八）——终值 = 判定式逐位命中，禁凑数对账成立。

zh-audit `--check`：1510/1760（起算）→ **1534 source / 1772 catalog PASS**（终态；
+24 静态键 = 硬化 surfaced 的 continuation 形态族，+12 catalog 键 = 4 collision +
1 peak note + 1 nlmeans toast + 4 project_face + 2 search 占位符）。

## 五、走查结论（MANIFEST 附录正本）

1. **F1 zh 清账屏上实证** ✓（默认面两键 + 打开态两键 AX 逐字）
2. **冲突档 Picker 在场 + 默认 Increment + zh 档名** ✓（AX 值 + 截图）
3. **三档菜单 + 选择翻转** ✓（Fail 选择 AX 值实测翻转；会话态 remount 复位 = D1 裁定语义）
4. **peak-ICC 双态** ✓（SDR 无行 / Rec.2020→PQ 吸附后有行，AX text + 截图）
5. **标记菜单 13 键 zh** ✓（菜单 dump + 截图）
6. **T3 实机拖动** = Manual-Only（D8；状态层六测 + 挂点编译期 + D-H1 既有语义补偿）

## 六、偏差与挂账

- **T3 实机观感走查未竟**（D8）：nlmeans 默认 IA 不可达 + legacy 宿主断层；补走查
  配方在 MANIFEST 附录，归 legacy 修复批/zh sweep 余量顺路。
- **D6 真缺口两键**（search 占位符）已修于本批（T4 授权内）；**D7 两处 verbatim
  「Import Folder…」同族**（File 菜单 :1301 / 面板标题 :1635）登记不修（M2-3-4
  先例），归 zh 专项余量。
- **冲突档跨页记忆**：会话态裁定（KD-1/D1）——用户如需跨会话记忆 = 新挂账（键登记
  纪律外零新增）。
- **拖动窗内并发 FULL 缺 denoise**：已登记风险（plan 风险节 + D4），根治归 M4
  coordinator 串行化余量。
- **L057 面板族加固**：下一波专项（GOAL-STATE 队列行在案）——本 plan 对
  ExportInspectorView 的触碰已按 orchestrator 指令最小化（Picker + readout 两处增量
  hunk，面板族加固不受扰）。

## 七、diff 边界核对（红线机检）

产线 diff = `ExportInspectorView.swift`（model 字段/Picker/装配缝/readout——申报集内）
+ `EditorState.swift`/`PipeCoordinator.swift`/`IOPPanelProvider.swift`/
`NLMeansPanelView.swift`（T3 申报集）+ `LightamerApp.swift`/`ContentView.swift`（T4
申报集）+ `Localizable.xcstrings`（append 尾部纯插入 + F1/硬化键块）+
`Scripts/zh-audit.py` + 测试两新文件 + `Project.swift`/BUNDLE-MAP（登记）+ 收口账本。

**红线域 `git diff --name-only` 全程零命中**（每 commit 前机检留痕）：`ExportNamer.swift`
/ `NLMeansModule.swift` / `PixelPipe.swift` / `DrtOutputColorSpace.swift` /
`ExportState.swift` / `DrtEotf.swift` / 六格式矩阵编码器 / `WebPEncoder` /
`PipeCacheKey` / `V50Order` / `ModuleRegistry` / `Lut3dKernels.metal`。

## 八、全套 `--all` 终验轮运行记录

- 预备：`build-for-testing` @ T4 终态（d4ae750 树 + 收口账本前）exit 0；fresh 产物
  （LightamerTests*.xctest 七件 mtime 同源）。
- 轮次：报备制（本 plan 收口 = 批准在案）；运行中 Lightamer 测试宿主进程监视
  （ps CPU/mem 巡视）+ 脚本 MEMFAIL 机检兜底（`RSS_LIMIT_MB=8192`）。
- **结果：`TOTAL|3024/16/0|1077s`，exit 0，零 MEMFAIL**：

  | bundle | 实测 | 峰值 RSS | 判据 |
  |---|---|---|---|
  | IOP | 471/1/0 | 7860MB | `08dd061` 逐位基线零漂移；<8192 门 |
  | IOPParity | 389/3/0 | 5985MB | 01 终态逐位 |
  | Layers | 300/3/0 | 1145MB | 登记面 |
  | Library | 587/4/0 | 604MB | 01 终态逐位 |
  | Sessions | 279/4/0 | 1653MB | 登记面 |
  | Export | 338/1/0 | 6452MB | 引擎钉死族零改全绿 |
  | App | 660/0/0 | 2831MB | 649 + 本 plan 11 |
  | **TOTAL** | **3024/16/0** | — | = 2962+37+14+11 判定式精确命中 |

- L055 双保险判据亲核：七 bundle 末条 Executed 行全部挂靠 `Test Suite 'All tests'`
  总计段 + passed 数与 BUNDLE 行一致；`terminated abnormally` /
  `Restarting after unexpected exit` 全日志零命中。

## 九、M3-1 phase 小结（W1 三 plan 收口）

**phase 主线**：Milestone 3「胶片暗房」W1 前置批三 plan 全闭环——

1. **M3-1-01 M2GRADE-08**（LUT 作者编码建模）：编码目录 17 条 + 传递曲线 Float64
   正逆族 + Params additive 编码对 + 宿主复合表重烘焙（零新 kernel）+ 库内记忆三层
   序 + 面板双 Picker + 全链 golden（方向探针防自参照）；内置 40 张补标
   LogC4/AWG4→BT.1886（观感变化 = 修偏差非回归，交付注记在案）；FSIM-01 软前置
   （目录表 + 曲线函数族）就位待 M3-3 消费。六 commit，+37 测。
2. **M3-1-02 YIYIN-09**（yiyin sheet 拖拽调尺寸）：上游 PR #126 五语义映射（双钳制/
   松手持久/拖动禁重算/容器跟随/读数），纯数学 + 值类型 + @Observable 模型分层，
   14 测 + 实机六探针走查；`.global` 锚定执行期修复 + D6 机制修订（验收批）；
   F-1 扩围登记（New Project 面板取消即崩 → L057 家族）。四 commit，+14 测。
3. **M3-1-03 小件族**（本 plan）：冲突档选择器（挂账#4 关闭）+ peak-ICC 说明面 +
   denoise 拖动降档（OQ-6① 兑现）+ V14/V15/F1 zh 清算（提取器硬化 + 两枚真缺口
   意外战果）；四 commit，+11 测。

**phase 终态对账**：登记面 2962 → **3024**（+62：37+14+11）；zh-audit 1510 → 1534
source / 1760 → 1772 catalog，全程 PASS；三 plan 红线域零命中（各 SUMMARY 机检节）；
MEMFAIL 全程零。CONTEXT §七验收锚：#1/#2（01/02 面）+ #3-#7（本 plan 收口）全落。

**M3-2 交接**：
- W1 交付物就绪面：编码目录/曲线函数族（FSIM-01 消费）/LUT 三层序记忆（M3-3 LUT
  面直接复用）/yiyin sheet 拖拽语义（Phase 14 面板化参考）。
- 阻塞与余量：**L057 面板族加固专项**（GOAL-STATE 队列行：修复范围 = M3-1-02
  ACCEPTANCE §三全集，排 M3-1-03 落地后 = 现在起可派）；M4 coordinator 串行化
  （拖动窗并发 FULL + ToneEqual 同源）；T3 补走查配方（legacy 修复批顺路）；D7
  两处 verbatim 同族（zh 余量）；冲突档跨会话记忆（等用户诉求）。
- GOAL-STATE 续接点已更新（本批 commit）；REQUIREMENTS/CONTEXT 无本批新条目
  （挂账清偿批）。

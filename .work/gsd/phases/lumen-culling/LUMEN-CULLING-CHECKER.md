# LUMEN-CULLING-CHECKER — 图库选片批 fixer 后 checker 复核（2026-10-23）

> 复核对象：`CONTEXT.md` + `LUMEN-A/B/C-PLAN.md`（fixer `a0e43b44` 后 HEAD，
> +349/−182）对照评审正本 `LENS-CULLING-PLAN-REVIEW.md`（`dbc31523`）
> 18 条处方（B-1 + 5 major + 12 minor）。只读 + 本报告落盘 commit；零源码
> 触碰。复核方式：18 条逐条对账 + ΔN 数值冻结 diff + 负向 grep + 生产坐标
> 与 Lumen v2.0.1 上游实读双抽验。

## 结论头

**放行 / 0 residual + 4 note**

18 条处方全部落位且落对；`(review …)` 标记全批 98 处（CONTEXT 14 / A 47 /
B 15 / C 22），抽核覆盖全部 18 条落位点（≫12 处下限）；负向 grep 三面
（旧公式记法 / 不存在测试目录 / yiyinInjector 参数形）零活规格残留；
ΔN 数值带 fix 前后逐数全同；零源码触碰 git 核成立。4 条 note 均为
锚点微漂 / 判据字面余量 / 承自评审的带顶差 1——无一条构成执行墙或
处方未落，均不拦放行。

---

## 一、18 条逐条对账（全落）

| # | 处方 | 落位核 | 判定 |
|---|---|---|---|
| B-1 | 公式四处改写 Lumen 实式 + 两分支 | CONTEXT X3（各方向 log2(P90 比值)→四方向 min→`(min+4)/5.5*100` 钳 0-100 + 记法红线「log2 逐方向先施」+ ≈72.7 锚点 + strong 空→0.0〔:83 记〕/ min(shape)<64→nil〔:79 记〕两分支）+ §测试策略 + Plan A SC / T3 action / 红线 4 / T3 grep 机检「旧式 `log2((min+4)/5.5)` 零残留」/ 风险面「min 与 log2 施加序」/ 回滚申报面——fix 前 SC:9/T3:203/红线:18/CONTEXT X3 四处旧式实读确认，今全改 | ✓ |
| M-1 | imagesColumns 双点 + frozen 测试 + grep 恰两处 | Plan A T1 action 第 3 步（`:156-186` 数组尾段追加、`default_look_pending :184` 同位）+ 测试步（`testImagesTwentyNineColumnsVerbatim :114` 更名/断言 29→36 + `LibrarySchemaV5Tests :307-310` + V6Tests 新冻结族）+ SC + grep「七列拼写各恰**两**处（DDL + imagesColumns）」+ ΔN 表 T1 构成注记 | ✓ |
| M-2 | App 装配面 | Plan A T5 action 4/6（`LibraryAnalysisWiring.swift` 新建：项目打开启动点 + enabled 门 + 导出/AI 探针注入 + Registry App 侧 `@MainActor` 适配 handle）+ `LightamerShell.swift` 最小触点 + files_modified 两行 + `LibraryAnalysisWiringTests`（APP）+ test_bundles [LIB, APP] + T5 验收「恰四产线文件 + LightamerCore 域 App import 零命中」+ Project.swift 八文件（七 LIB + 一 APP） | ✓ |
| M-3 | Settings 开关行 | Plan A T7 action 5（`SettingsPages.swift` additive 一节 + 标签/说明 xcstrings 两键 + 消费 T5 键单常量）+ files_modified + T7 验收「恰四产线文件含 SettingsPages」+ CONTEXT 修复轮 M-3 条 | ✓ |
| M-4 | FIX2③ 采纳 (a) 形 | CONTEXT 红线 1 / 勘误② / X8 / 晨审索引四点全改「GUI post-assignment ⇒ McpServerController 三 plan 全程零 diff、零例外；makeEditingSeams 参数形弃用」+ 三 plan 红线 1 + Plan C T3 SC/action 3/grep 判据/回滚禁触/风险节/裁定 5/files_modified LightamerShell 行 + fix 前 SC「makeEditingSeams 恰一 additive 装配行（唯一例外）」旧式实读确认已除 | ✓ |
| M-5 | 测试路径平铺 | B 两件 + C 三件 paths 全改 `Tests/LightamerTests/<Name>.swift` + 「平铺目录 + Project.swift 数组显式行 + BUNDLE-MAP 登记行」表述 + B T7/C T4 action 复述；实测 `Tests/` = Fixtures/LightamerTests/LightamerUITests（无 IOP/App/Layers 目录）、LightamerTestsIOP(:393)/Layers(:506)/App(:809) 数组在案、「No directory glob…stay flat」注释在案 | ✓ |
| m-1 | futureSchema 措辞 | Plan A T1 回滚：「`LibraryError.futureSchema` 硬拒〔by design——ProjectFileStore:271-273 guard〕，数据无损，新二进制重开即愈」；guard 实位 :270-272 吻合 | ✓ |
| m-2 | 通知缝 + 徽章刷新 | T5 action 1 additive 通知缝（明示「无既有行变更通道可复用」+ execute 期 DECISIONS 定形）+ 红线 5 + T7 action 3 徽章刷新挂接点（含 stale-until-refresh 臂） | ✓ |
| m-3 | 上游向量缺失 | CONTEXT X4 + §测试策略「已核 38 文件无 annotate_bursts 向量→自织 + 对拍正路径」+ Plan A T6 test + Plan C T1 场景参照（test_v170_masks 四 fine-pass：twigs:44/broad-ramps:60/guide-size:77/raster-blocks:89 实读吻合） | ✓ |
| m-4 | auto_masks 行号 | CONTEXT X8 + Plan C read_first/T2：「v2.0.1 `:143-219`；RESEARCH :121-219 = v1.7.0 域」；实读 v2.0.1 `def refine_masks_later` = :143 ✓ | ✓ |
| m-5 | 比较器三钉 | Plan A T6 action 5 DECISIONS 必钉三件（双字段比较器或 golden 语义换算 / `_similar` nil→True :825-827 / 组 id canonical 串输入）+ SC + files_modified DECISIONS 注记；best 元组 `(not eyes_closed, sharpness, -index)` :876 实读吻合 | ✓ |
| m-6 | 转栈显式收编 | Plan A 裁定 3（contextMenu → `createStack :625` 一键，消灭死胡同条款；折叠 = 徽章指示行不隐藏）+ T7 action 3 + 合成 store 断言 + files_modified 注记 | ✓ |
| m-7 | B 申报制触点 | Plan B files_modified 补 `PipeCoordinator.swift` + `LibraryGridView.swift` 两行「申报制触点——review m-7」 | ✓ |
| m-8 | 红线编号统一 | 本地引用全带「本地红线 N——m-8 编号显式化」前缀、全局引用全带「CONTEXT 红线 N」前缀（B/C 全部引用逐处扫过：本地 3/4/5 显式、CONTEXT 1/2 显式、其余全局引用无本地碰撞可能）；原混淆位点（C T2→CONTEXT 红线 2、B T3→本地红线 4）全消歧 | ✓ |
| m-9 | shared holder 形 | Plan B T2 action 5（`LutLibraryStore.shared` 先例同形：private static + NSLock + `replaceShared(_:)`）+ 并发测试挂单例假设 + SC + DECISIONS | ✓ |
| m-10 | 弃层申报 + mtime ns | Plan B SC + T2 action 1（mtime ns、`preview_cache.py:75` 同形）+ action 5 弃层申报（2560 JPEG 层弃 + 320 thumbs 层 `.lathumbs` 承担）+ DECISIONS | ✓ |
| m-11 | .session 负测 | Plan A T7 action 6（`.session` 四新案 typed unsupported 负测 + 34 列 frozen 理由）+ SC + 验收负向判据「.session 翻译臂零 SQL 生成」+ ΔN 表 | ✓ |
| m-12 | 勘误计数 | CONTEXT 头「转写勘误四条 + 吻合抽核记录一条」+ §勘误计数口径行 + Plan A「勘误四条〔① FilterField 16 案〕」；「勘误五条」全批零残留（grep 空） | ✓ |

## 二、ΔN 算术冻结核（通过）

- fix 前（`ea89267f`）vs fix 后（HEAD）三 plan 全部 `N..M` 数值 token 多重集
  diff = **空**（A +12..15 / B +14..18 / C +6..7；A 终态 4124..4127 /
  B 4138..4145 / 批终值 4144..4152 逐数全同）；唯一改动 = A T5 行增
  「〔含 APP 装配/门控面——review M-2〕」构成注记，带值未动——与 fixer
  「无数值修订」申报一致，M-2 装配测试折入 T5 既有 +2 成立。
- B 分账算术精确（14..18 = 3..4+3+2+3..4+2+1..2+0..1）；A/C 带顶差 1 见
  note N4（承自评审 §4.4 同式放行，非 fixer 引入）。

## 三、标记与残检（通过）

- `(review` 标记 98 处（CONTEXT 14 / A 47 / B 15 / C 22），本复核按处方
  逐条走到位位点，覆盖全部 18 条（≫12 抽核下限）。
- 负向 grep 三面：
  1. 旧公式 `log2((min+4)` 全批 3 处命中 = 禁令/对照提及（CONTEXT X3 禁
     式 + Plan A T3 机检判据 + CONTEXT 修复轮 B-1 对照），零活规格残留。
  2. `Tests/LightamerTestsIOP|App|Layers/` 2 处命中均为否定句（「无 …
     目录」），零活路径。
  3. `yiyinInjector` 命中均为 additive-var 先例引用（`EditingToolset:91`
     实位吻合，该先例保留合法）或 makeEditingSeams 参数形弃用宣告，零
     参数形活规格。
- 评审外发明核：fixer 申报唯一出入点 = M-4 授权外扩一面。fix 前 diff
  实读：X8（旧 :403「makeEditingSeams 内 additive 装配行恰一处 = FIX2③
  适配唯一」）、勘误②（旧 :427-428「供给必然在该函数内一行」）、晨审
  索引红线 1 行同载旧供给形——不同步即与改写后红线 1 自相矛盾。三处
  同步 = M-4 同条款一致性改写，非新裁决，正当。
- m-8 编号消歧全扫：B/C 每处「红线 N」引用前缀逐处核过（见对账表行），
  零裸歧义引用。

## 四、可执行性抽验（通过）

- **B-1 公式逐步可复算**：Lumen v2.0.1 `culling.py` 实读（本机
  lumen-raw `git show v2.0.1:`）——`levels.append(np.log2(np.percentile(
  second[strong]/first[strong], 90)))` → `float(np.clip((min(levels)+4)/
  5.5*100, 0, 100))`，与修复后文本逐位同构；min 比值=1 → (0+4)/5.5×100
  = 72.727 ≈72.7 复算吻合；常量面 SHARPNESS_EDGE=1600 / `_tiles(size=32)`
  / CLOSED=.16 / DETECT_EDGE=1280 / MIN_FACE=.03 全中（T3/T4 直译参数
  有着落）。Plan A T3 按 SC（合成图样 + NumPy 参考双写 + 标定锚
  1.2px≈55/2px≈30）可实现出与上游一致的 golden。
- **M-2 装配缝**：`LightamerShell.swift:1112`（makeEditingSeams 构造）
  实位吻合；Plan A T5 的 Shell 最小触点（KD-5 sink 装配形）与 Plan C T3
  的 Shell post-assignment 赋值（`projectWriteProbe` 先例形，X8 一致）
  分属两 plan 串行 additive，互不冲突；Registry 锚 `:53 protocol / :80
  class / :87 register` 三点实读全中。
- **M-5 平铺**：`Tests/` 实测无 IOP/App/Layers 目录；三 target 数组 +
  平铺注释在案；`LibrarySchema` 冻结锚（`:116` v5 / imagesColumns :155-186
  / `default_look_pending` 数组 `:184` + DDL `:307`）、frozen 测试锚
  （`LibrarySchemaTests` func :113 起、`LibrarySchemaV5Tests :307-310`
  assertColumns）实读吻合——M-1 双登记点处方与现状对得上。
- 其余抽验：`LibraryStore` `:455 setMetadataMarks` / `:625 createStack` /
  `:116 createAlbum`；`ProjectFileStore` futureSchema guard :270-272；
  `SettingsPages.swift` 在库；best 元组 :876 / `_similar` 尾式 :825；
  v2.0.1 tests/ 零 burst 向量（`grep -ci burst` = 0）——均与 plan 文本
  一致。

## 五、零源码触碰核（通过）

`git show --stat a0e43b44`：恰 4 文件全在 `.work/gsd/phases/lumen-culling/`
（CONTEXT +137/-x、A、B、C，合计 +349/−182），零产线/测试/脚本路径；
本 checker 同样零源码触碰，唯一产出 = 本文件。

## 六、Note 清单（4 条，均不拦放行）

- **N1（锚点 ±2，承自评审）**：LightamerShell post-assignment 先例实位
  `:1124`（`editingSeams.projectWriteProbe = projectWriteProbe`；构造点
  `:1112` ✓），评审正本/CONTEXT/Plan C 记 `:1126`。锚语句全仓唯一、
  grep 可达，零执行风险；execute 期（Plan C T3 read_first）顺手勘正。
- **N2（上游锚 ±2，承自评审）**：culling.py 分支锚实位——strong 空
  `return 0.` = :85（plan 记 :83）、`min(gray.shape) < 64 → None` = :76-77
  （plan 记 :79）；公式块 `:84-87` ✓ 精确。代码引文逐字在案 + read_first
  已给 `culling.py:34-94` 全域，直译无歧义。
- **N3（SC 判据字面余量）**：Plan C T3 验收 grep「`refineMasks` 恰两处」
  按字面标识符计数少算工具体消费位点（yiyinInjector 先例形 = 声明 :91 +
  工具体 unwrap :487 + 透传 :518；refineMasks 同形预期 ≥3 处）。门意图
  （声明恰 1 + Shell 装配赋值恰 1、无额外赋值位点）已由括注写明——
  execute 期命中 3 处时按括注解读或在 DECISIONS 申报一笔，非硬门冲突。
- **N4（ΔN 带顶差 1，承自评审 §4.4 同式放行）**：A 各案上限合计 = 16
  （vs 带 15）、C = 8（vs 带 7）、批顶 = 42（vs 40）——带下限与终值带
  下沿全部精确（12/14/6/32/4144）。带 = 对账式非死数 + 越带申报制，
  最坏情形 = T8 收口多写一条申报理由；fixer 冻结令禁止改数，维持原带
  正确。
- 附注（计数微差，不计 note）：m-3「v2.0.1 tests/ 38 文件」实测
  `ls-tree -r` = 37 文件（计法差，如含树目）；载荷断言「零 burst 向量」
  实测成立，不受影响。

## 七、放行条件

修复轮六条（B-1/M-1..M-5）已闭环 + m-1..m-12 全消化——按评审 §五「修完
1-6 即可放行 LUMEN-A 执行」：**LUMEN-A 可放行**（C 档门控照常；执行排
F0'-prod + LENS-01 链收口后 + machine-guard 红线照守）。N1-N4 建议
execute 期 DECISIONS/勘正顺手带过，不设独立修复轮。

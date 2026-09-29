# M2-3-4 DECISIONS（执行偏差与裁决记录）

> Plan M2-3-4（收口）。全部为执行级裁决；plan 已定裁决（D1/D5/D9/D10/D12 + KD-1..3）不重开。

## D-orch-1 终跑口径变更（orchestrator 指令，2026-09-30）

全套回归终跑被用户强杀（全 suite 测试宿主 7.5G + 系统 swap 6.5G——16GB 机结构性上限；test bundle
拆分提级 M2-4 首个 plan）。收尾改为：引用最后全绿基线（M2-3-3 验收 R2 2160/14skip/0fail @
`d7f87fe`，790.8s）+ w4 变更面域内定向验证（zh-audit 双模式 + 定向 6 类 55 测试 0 fail）。
SUMMARY 显式登记 deferred 非缺口。AC#8 按「基线引用 + deferred 登记」口径核销。

## D-t1-1 zh-audit 扫描面与断言形态（KD-1 细化）

- 扫描域 = 仓库全 Swift 非 Tests 文件（KD-1 的「App 层 UI 目录 + Core 面向 UI 键」超集——实际全部
  localized 键均在 App 层，超集无害且防漏）。
- 断言①提取三形态：`String(localized: "K"`、**续行形态**（`\n localized: "K",`——P2/P3 调用风格，
  首跑实测漏 79 键后补）、`Text("K")`；蛇形键形过滤 + verbatim/注释排除照 KD-1。
- 断言②覆盖规则（机械消化动态族，白名单最小化）：静态键 ∪ 引号字面任意位出现（bare
  LocalizedStringKey：`case .grid: "browser_mode_grid"`/`labelKey:`）∪ 插值前缀族
  （`"prefix \(x)"` → 覆盖 `prefix`/`prefix_*`/`prefix_ %lld` 型 catalog 键——
  `"metadata_rating_\(stars)"` → metadata_rating_1..5）。66 孤儿消化至 7。
- 断言①对插值键**只查存在性不查缺**（动态族无法静态验证确切 catalog 拼写——诚实录为局限，
  任何 catalog 缺失由断言③兜 zh 完备）。

## D-allow 内建豁免 7 键逐条归因（KD-1 白名单非转义门）

全部为无任何存活引用的死键（静态/字面/动态族三规则后仍零覆盖，逐一 git grep 实证）：
1. `a11y_inspector_label` — M1 inspector a11y 提示退役
2. `inspector_no_modules` — M1 空态标题退役
3. `inspector_no_modules_body` — 同上 body
4. `module_bilateral` — 禁用模块标签（M2-1 收窄失挂）
5. `settings_placeholder` — 被 `settings_placeholder_arrives/_hint` 取代
6. `smart_album_no_chips_hint` — M1 智能相册提示退役
7. `toast_session_index_failed` — M1 会话索引 toast 退役

处置 = catalog 保留（代码保留裁决 M2LIB-06 的同族政策；catalog 修剪超本 plan 范围，登记待办）。

## D-t1-2 verbatim 转换范围 = 静态文案（P1-P3 交付面内的 M2-2 欠账）

M2-2 三文件（ImportModeDialog/ImportProgressView/LibraryWelcomeView）文件头注释明文
「Verbatim strings: zh localization lands with the M2-3 shell」——T1 兑现。**只转静态 UI 文案**；
动态数据（文件夹名/路径/计数载荷——RelinkSheetView/GlobalSearchDialog/LibraryInspectorView 全部
verbatim 实为模型侧已本地化值或数据）保持 verbatim。插值文案走
`String(localized: "plain_key", defaultValue: "…\(arg)…")` 形态（plain key + defaultValue 插值 =
String Catalog 标准参数携带语义），不新增 `%@` 型键名。

## D-t1-3 三处测试断言 locale 无关化（被杀套件 3 fail 的归因与处置）

被强杀套件暴露的 3 fail（BackgroundTaskRegistryTests ×2 + LibraryRelinkModelTests ×1）全部为
「断言英文字面 copy」被 T1 本地化影响（zh locale 下 `tasks_import_counts` 渲染
「已处理 40 / 100」）。处置 = 断言改计数存在性/标题非空（locale 无关），测试意图（计数随行、
单调、标题在）不变。同批定向复跑 6 类 55 测试 0 fail。**非产品缺陷，零产品代码改动。**

## D-t2-1 走查坐标法（computer-use 实操记录）

Alcedo（Qt）AX 树可用但 tab 命中框与估算坐标偏差大 → 逐屏以 wshot（窗口捕获）+ AX 精确元素
（Alcedo tab 行 AXButton 有 zh description 可枚举）混合导航；Lightamer 侧全 AX marker 驱动。
NSOpenPanel 的「前往文件夹」sheet 对合成键盘事件不响应（macOS 自动化已知面）→ 改走
`NSNavLastRootDirectory` defaults + 面板重开（对自身 app defaults 写入，无用户数据触碰）。
两处失败尝试如实留痕：Alcedo go-to sheet 弃用（import 确认框证据受限记 偏差-接受）；
合成滚轮对胶片条 List 不生效（观察清单①如实记）。

## D-t2-2 Alcedo 侧零污染核验

仅导航点击 + 窗口截图；未导入任何图像到其项目（import 确认框在取消路径）；未改任何设置项
（语言下拉/默认行为/键盘页只看不点）；退出未保存会话态；其用户项目
`20260523 村长 柚柚子.alcd` 文件原样（8.0MB，mtime 不变）。

## D-t2-3 真缺陷 A/B 的条目形态与边界纪律

走查发现的两个功能性缺陷**不入逐屏表判定词**（D1 判定语义 = IA/布局/交互；渲染/管线缺陷属
功能域），另立 MANIFEST「真缺陷」节 + SUMMARY 表 + TODO/GOAL-STATE 挂账。两者根因文件均不
在本 plan 申报集（A = M2-2 面 ImportService/LibraryProjectController；B = M2-3-3 面
EditorState/WorkspaceModel resolver），按「新发现缺陷一律另立清单条目 + 修复越界禁止」纪律
转专项而非顺手修。E4 观察项③（示波器帧率）被 B 阻断，如实记「不可观察」而非伪结论。

## D-t2-4 判定词封闭集的 locale 注记

AC#4 提取命令在 en_US.UTF-8 locale 下 `sort -u` 将「一致」并入「判定」桶（macOS sort 对该
UTF-8 序列 collation 合并；LC_ALL=C 复核真实分布 = 一致 51 / 偏差-接受 22（含 1 设计差异）/
表头 20）。两口径的 sort -u 输出均 ⊆ 封闭集 → AC#4 PASS 双口径成立。注记入 MANIFEST。

## D-t3-1 Core diff 三文件 = 申报连带（KD-3 #3 口径）

`897bcb2..HEAD` LightamerCore/ = RAWDecoder.swift（P3 例外缝）+ RAWTechnicalParams.swift +
HistoryHash.swift（M2-3-3 KD-4/D1 膨胀字段申报连带，同 commit `921a98f` 落）——恰 = plan
KD-3 #3 「一文件 + kd-4 声明连带（如触发）」的触发形态，非越界。

## D-t3-2 验收抽查记录位空置

D10 硬约定验收方独立抽查 2-3 屏——MANIFEST 抽查记录位空置待验收 subagent 填写；抽查与
executor 判定不一致 → 该屏重开（验收轮语义，非本 plan 自动化范围）。

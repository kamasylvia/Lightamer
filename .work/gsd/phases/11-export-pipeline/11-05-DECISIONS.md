# Plan 11-05 DECISIONS — 执行期决策清单

> 收口批执行期决策。编号 D1..D5；体例照 11-01..11-04。执行日 = 2026-09-26（macOS 27.0 / M4）。

## D1：C 档第 3 停按夜间授权先例执行翻账（先例 = D-07-3-T5-1 / D-09-05-T1-1）

签核推进在夜间自动推进场景执行（无实时用户在环）：按 plan 纪律节写明的先例
——「夜间授权 = 签核推进授权，签核结论以 VALIDATION frontmatter 为准，用户终验
留 verify-work 轮」——T4 翻账在 VALIDATION 落盘后同批执行。依据三件：
① config.toml `auto=true / paused=false`（2026-09-26 23:4x 用户解除暂停 +
「继续全自动推进」指令）任务边界逐次复核在案；② 先例两案（Phase 7/9 同场景）
均有用户事后追认记录；③ 翻账只认证据（SC 三列零缺签）。**晨审可推翻**：推翻
任一 SC 判定 → 回注重开受影响面（REQUIREMENTS/TODO/GOAL-STATE 翻账行是唯一
改写点，git revert 单提交可逆）。
Reversibility: 高（单提交回滚面）。

## D2：flake 稳定化的容差选型 = 解码域逐样本 1/255 + 尺寸相等（非 PNG 容器字节带）

11-04 法证确认 GPU 渲染 1-LSB 级非确定且「无正确侧」（baseline 自身漂移）——
任何容器字节级断言都过敏。真不变量 = 解码后语义（尺寸相等 + 逐样本 ≤1/255）。
防「放宽 = 橡皮图章」：companion sanity 断言钉住比较器灵敏度（人为 +2 错位必红），
真回归（双关态渲染出印框内容）差异量级远超容差。
Reversibility: 无关（测试口径，容差收紧随 Phase 12+ 渲染确定性工作再评估）。

## D3：F-11-04-1 修复 = ExportState 单函数 realpath 双拼写（非 GOAL-STATE 候选的入口 resolvingSymlinksInPath）

实测证据：Foundation `resolvingSymlinksInPath` 不解析前缀链接（L027/SessionWatcher/
SessionTreeScanner 三处在案）——GOAL-STATE 候选方案字面无效。落地照
SessionTreeScanner 的 realpath(3) 模式：`ExportState.targetRelPaths` 对 root 与
loaded 两侧各求一次物理拼写、任意组合匹配（覆盖 loaded 物理×root 链接（11-04
walkthrough 实测形态）与反向）；`canExport` gate 同步改为以 targets 非空为真条件
（修「按钮可点但入队空跑」的第二半）。收益：修复收敛在可单测纯函数（App 层
`@testable` 先例），SessionCoordinator 零改动、无回归面。
Reversibility: 高（单函数 + 4 测试）。

## D4：Release 直启计量技巧（模糊腿复测跑批）

Release 产物直启宿主的两处坑（Debug 不受影响）：① Release 二进制无 Debug 的绝对
PackageFrameworks rpath → `DYLD_FRAMEWORK_PATH` 须显式补
`Products/Release/PackageFrameworks`；② Release 签名 Team ID 失配 + WebP 包框架
未入 app 嵌入路径 → 主 app（--deep）与 WebP 框架以 `Lightamer Dev` 重签。
另：自定义 `-derivedDataPath` 触发 SPM submodule 重拉失败（SourcePackages 未随
拷贝）——Release 计量应复用默认容器（同容器双 configuration 共存）。
此技巧登记供 Phase 15 的 Release 计量复用。
Reversibility: 无关（操作记录）。

## D5：VALIDATION SC#5 测试锚 = 注入面自查实录 + 队列 settle 语义单测的组合

post-actions（EXP-08）无独立单测类（脚本执行是 Process 实跑 + GUI 面）：锚采用
① 11-04 执行期注入面自查实录（`$()`/反引号/分号路径逐字进 `$1` + `/tmp/INJECTED`
哨兵未创建——EXP-08 安全语义的硬证据）+ ② `ExportQueueTests` 的 completion
settle 语义（仅 done 触发）。三列表内明示证据形态为「执行期实录」，不作测试文件
伪装——「翻账只认证据」以证据本相入表。
Reversibility: 无关（签核口径）。

## mask-fence 收编评估（executor 协议第 5 条）

不适用：本批零 iop dispatch 面改动（测试/文档/单函数修复）；11-04 D15 的评估结论
（v1 不收编，Phase 15 复评位）维持。

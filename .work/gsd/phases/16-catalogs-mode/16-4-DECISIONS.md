# Plan 16-4 执行期决策（DECISIONS）

> RESEARCH/CONTEXT 未覆盖细节按 plan 纪律标注执行期决策，不臆造。共 11 条。

## D1 基准口径：Release 主判据 + 三轮对账 + 直启参数

SC#3 主判据 = **Release 分栏**（Debug 仅参考，16-1-DECISIONS D15 口径延续）；三轮对账 =
Debug ×3 + Release ×3（全矩阵最差逐轮 12.21/13.20/12.92 与 11.53/12.28/11.87——波动
±1ms 级，裁决对波动不敏感）。Release 直启 = `build-for-testing -configuration Release` +
`codesign --force --deep --sign -`（Team ID 校验挡 DYLD 注入）+ test-direct 同款直启命令；
DYLD 搜索顺序 **app 内嵌 Frameworks 优先**、`$DD/PackageFrameworks` 兜 SwiftPM WebP 产物
（无它 `@rpath` 直接失败）。参数已注记入 harness 头注（plan files_modified 申报的
「Release 参数注记」位）。

## D2 混合代际 Release 产物陷阱（本轮执行期发现，LESSONS 候选）

首轮 Release 直启 `dlopen` 报 LightamerTests→LightamerCore 符号错配（mangled signature
含 `A2_`/`A3_` 模块引用差异）。排查：两份 LightamerCore.framework（`$DD` 根 + app 内嵌）
UUID 相同 ⇒ 排除「陈旧副本被优先加载」；真因 = 先前一次 Release 构建实际 **TEST BUILD
FAILED**（管道 `| tail` 吞掉退出码，`$?` 取自 tail）——失败构建留下混合代际产物。处置 =
删 `Build/Products/Release` 全量重编 + 构建判据改读 `TEST BUILD SUCCEEDED` 行。
**教训：xcodebuild 管道取码必须 `PIPESTATUS` 或先落日志再 `echo $?`；混合代际产物症状 =
测试束 dlopen 符号错配，处置 = 清该配置产物目录。**

## D3 `.lcat.bak` 保留形态 = 一代备份

晋升前旧文件 rename 为 `catalog.lcat.bak`（同目录 L009）；**保留一代**（下次破坏式重建
覆盖），不自动清理——它是破坏式重建后组织数据的唯一恢复源（RQ-16-15 单文件兜底语义），
删除它 = 替用户丢弃唯一备份。晋升中断回退 = `.bak` rename 回 `.lcat`，原文件字节不变
（测试断言 Data 全等）。

## D4 checkpoint 确定性化（不赌 SQLite 关闭行为）

首版实现假设「writer close ⇒ SQLite 自动收敛并删除 tmp -wal」，实测不成立（close 后
-wal 存活，5 测试中 2 个破坏式用例被自设守卫挡下）。定案：晋升前**显式
`PRAGMA wal_checkpoint(TRUNCATE)`**（经自有句柄）——语义 = 全部已提交页必须落在主文件；
守卫改为「checkpoint 后 wal 字节数 > 0 = 拒绝晋升」（空壳 wal/-.shm 为无害残件，rename
前清除）。PRAGMA 字串收进 `CatalogIndexSchema.checkpointTruncate(on:)`——**缝 b 纪律：
不得出现第三 PRAGMA 落点**。

## D5 逐会话失败跳过（sweepAll 先例）

对账式重建中单会话投影失败（lindex 损坏等）`try?` 跳过并继续——全库修复动作不应被一个
坏会话中止；跳过计入进度 total，成功计入返回值。与 16-1 `sweepAll` 的容错形态一致。

## D6 重建 UI 形态（执行期 UI 决策）

- 进度 = 设置面 X/N 会话行（ProgressView）+ Catalogs 网格**空网格 + 进度** overlay
  （RQ-16-14 推荐态：保 Smart Albums 侧栏可见性，仅照片网格清空）+ 重建完成 onChange
  触发网格 reload。
- 完成提示 = alert 两套文案（对账「目录已与 N 个会话对账。」；破坏式逐字
  「元数据已恢复；分类与集合需从备份恢复或重新整理。」）。
- 破坏式按钮**仅在 schemaFailed 禁用态出现**，且前置 confirmationDialog（明示组织数据
  将被丢弃 + 先备份 .lcat 提示）——不可逆动作的用户知情双保险（执行期增益，plan 未禁止）。
- 位置行旁新增「退出 app 后拷贝此文件即完整备份（单文件库）」提示（T2③ 复核项；
  原 16-2 rebuild_hint 文案保留在重建节，两者不冲突）。

## D7 重建期共享三元组时序

破坏式重建**前置** `SessionIndexController.closeSharedCatalogHandles()`（新缝：关三件套
且清 `sharedCatalogURL`——否则 `repointSharedCatalog` 的同 URL 幂等守卫会拒绝重建）；两档
重建完成后统一 close + repoint（新句柄 + `sharedCatalogStoreRebuilt` 消费者重绑钩子）。
理由：活跃写句柄会在 rename 晋升后继续写孤儿 inode，把已提交状态留在旧文件里。

## D8 CatalogOrganizationTests await 提升（构建修复，非产品缺陷）

全量重编（tuist generate 换 pbxproj → 该文件首次重编）暴露 `XCTAssertEqual(try await
store.memberCount(...), 4)` 的 async overload 解析失败（`'await' in an autoclosure that
does not support concurrency`）。修复 = 提升为局部变量再断言（同断言语义）。16-3 期
增量编译从未重编该文件故未暴露。全仓 grep 确认无同型第二处。

## D9 终测与 T2 源并存注记（数字有效性）

T1 的 Release 三轮基准在与 T2 源（CatalogRebuilder + App UI 面）并存的工作树上执行，
但 T2 对查询/投影热路径**零改动**（新文件 CatalogRebuilder 不进 harness 路径；App 侧
为设置/网格 UI 面）——基准数字有效性不受影响；T1/T2 分两笔独立提交（`b744770`/`f7a8037`）。

## D10 基准 harness 输出交错处理

XCTest 的 print 与 Test Case passed 行在直启宿主下偶发粘行（`BENCH|mat` 前缀被吞），
96 形状中 1 行以粘行形式出现。perf.md 落账时以 `grep -o` 粘行提取补全——**96/96 全测**
（非形状缺失）；后续 harness 若复用，可改 `FileHandle` 直写绕开 stdout 交错（additive，
本轮不动已验证面）。

## D11 16-2 验收注记①不采纳（loadMore 静默吞错补 logger）

16-2 验收注记①建议 CatalogBrowserModel.loadMore 失败补 logger（「16-4 顺手」）——本轮
**不动**：注记明言「UI 容错选择，nit 级不修」，且本 plan files_modified 未申报该文件；
顺手修违反「范围外改动不入 commit」纪律（长程任务修复铁律 1）。留计划外 backlog。

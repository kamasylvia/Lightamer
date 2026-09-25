# Plan 09-04 — SUMMARY(批量 apply + 复制粘贴 HIST-05 + before/after HIST-06 + PERF-07)

**执行**:ZCode subagent worker(2026-09-26);7 commits(未 push)。
**终轮全 suite:1133 tests / 6 skip / 0 fail**(基线 1097 → 1133,净增 36:
PasteSemantics 16 + SessionBatchApplier 12 + Perf07 3 + BeforeAfter 5)。每任务
边界 `.work/config.toml [gsd]` 开关检查(auto=true / paused=false 全程)。

## 任务完成表

| T | 内容 | commit | 验证 |
|---|---|---|---|
| T1 | PastePayload(冻结载荷 + skip 集 + 部分选择面) | `feat(history): PastePayload copy carrier + skip set` | skip 真值表 9 tests(decode 域/恒等默认/创意带/边界/多实例/有效链投影/Codable 字节/勾选过滤) |
| T2 | PasteSemantics 三式 + pasteSet 投影 + live 路径 + 剪贴板 + 部分粘贴对话框 + 菜单 | `feat(history): paste three modes + live path + partial dialog` | 16/0(overwrite 精确非超集 + ⌘Z 逐字节 + redo;merge latest-wins + 异名共存 + 恰 1 commit;partial 子集;UUID 重铸;sidecar 往返 drift-free) |
| T3 | SessionBatchApplier 段1+段2 + store claim + App 批量路由 | `feat(session): batch apply segments 1+2 + index claim + app routing` | 6/0(索引逐列/writer=nil 磁盘零字节/live 跳过/磁盘 sidecar 为 compose 真身【毒化索引反证】/pristine 铸造自洽/缩略图 stale 翻转) |
| T4 | BatchSidecarWriter 段3 + 崩溃注入 + flush 缝 | `feat(session): segment-3 serial sidecar write queue + crash heal` | 10/0(drain 逐字节 + dirty 清零 + 进度 1/3..3/3;串行 FIFO + 每图一文件;崩溃注入 → 重开自愈【写盘行从磁盘真身覆盖毒化 claim,未写行保持诚实 dirty】;teardown flush) |
| T5 | PERF-07 门 + O(n²) 修复 + perf.md | `test(perf): PERF-07 gate ledger — 10k apply 0.419s Release + O(n²) claim fix` | **门:段1+段2 万张 0.419s(Release/SSD)≤5s,余量 ~12×**;Debug 0.518s;段3 6.23s/1606 docs/s 只记;UNITEK 0.44s/100 张只记 |
| T6/T7 | before/after 底座 + 三形态 UI | `feat(ui): before/after three forms — pristine plane + peek + hold blit` | 5/0(BEFORE 平面 == 独立 pristine 渲染逐字节;peek(k) == 重放逐字节 + 指针不动;peek/hold 零 history 项;hold 快路径零渲染;override(live)== 默认路径逐字节) |
| T8 | 再生链 E2E + dirty 徽章 + 层投影回归修复 + GUI 轮 + 收口 | `fix(history)+feat(ui): global projection scope filter + stale-regen chain + dirty badge` | apply→stale→tier B 再生→thumb_params_hash 翻转全链;claim 窗口徽章两态;全 suite 1133/6/0 |

## 验收标准对照(PLAN 验收标准)

- ✅ HIST-05 复制:载荷冻结(实例集+层栈快照+skip 记录)+ skip 集(decode 域 + 恒等默认;创意域/borders/watermark 保留)+ 部分复制对话框(逐实例勾选 + 覆盖/合并 picker)+ UUID 重铸
- ✅ HIST-05 paste:三式反向断言(overwrite 精确非超集 / merge latest-wins 异名共存 / partial 子集恰落)+ live 保护(批量循环跳过 + 交互路径粘贴)+ **单图 ⌘Z 恰 1**(epoch 形单 commit);UI 文案无「整批撤销」暗示
- ✅ 批量三段式:**段1+段2 万张 0.419s(Release/SSD 复核钉数,跨机器口径入 perf.md)** + 段1-2 零渲染零解码常驻断言(writer=nil 磁盘字节不变;类型面无 decode/render 参数)+ 索引单事务
- ✅ 段3:串行写队列 + 同目录 tmp 原子晋升(journal 吞自事件)+ dirty=0 回写 + 进度上报 + flush 余量(teardown 缝)+ **崩溃注入自愈**(重开按 sidecar 重读零丢失)+ 禁合并多图
- ✅ 一致性窗口契约:dirty 行 sidecar 为真(compose 权威测试:毒化索引不影响 compose;自愈覆盖索引)+ 「进行中」徽章(grid 黄 … 徽章 + 测试两态)
- ✅ HIST-06 三形态:split 双平面 blit(scissor 零新 kernel)/ 快照点 peek(逐字节 == 重放)/ hold 零重渲——pristine 平面常驻(upstreamHash 天然区分零 schema 改动)+ renderPreview override(默认路径字节恒等回归)+ peek/hold 零 history 项
- ✅ 缩略图 stale 再生全链(apply → 徽章 → 后台再生 → hash 更新;GUI 轮真会话实证)
- ✅ L010 identifier(paste.partial.* / beforeafter.* / toolbar.before_after)+ zh catalog(L025,zh 标签)+ 全 suite 0 fail + 每任务独立提交 + 边界查开关 + SUMMARY/DECISIONS 落盘

## 关键实现事实(下游必读)

- **paste 一提交机制**:`HistoryItem.pasteSet`(additive optional,06-01 先例)+
  `commitPaste`;merge 项 = layerScope nil 普通全局项投影贡献全部记录;
  overwrite 项 = `pasteEpochScope` 标记 = EPOCH(全局投影只取其 pasteSet,老项
  死状态;层栈快照走 stackSnapshot 槽,rebuildLayerStack 兼匹配双标记)。
  **overwrite 追加未动栈**(非替换)——⌘Z 依赖老项在栈内。
- **全局投影作用域过滤回归**:新增走查曾丢 `layerScope == nil` 过滤(层作用域
  双胞胎漏进全局去重,LayerCoreTests 抓出)——已修;09-05 签核回归重点复跑
  HistoryStack/LayerCore/BeforeAfter 三族。
- **claim SQL 教训(D8)**:per-row 值的批量 UPDATE 必须 PK-seek 循环,禁 per-row
  重执行 bulk-IN(全表扫 × n,O(n²) 77s→0.010s)。
- **skip 边界 D1**:`decodeDomainBoundary = 15.0(ashift)`;plan 公式 <28.0 不可
  字面执行(v50 表 exposure 21.0 等 <28 与「创意域保留」矛盾;dt 实为 flag 制)。
- **pristine 平面缓存** = override render 用 records 的 paramsHash 链天然区分
  upstreamHash(零 schema 改动);override 的 colorout display fold 局部落盒,
  不捕获 live 链。EditorState.pristineSeedRecords = base 只读暴露。
- **stale 再生零新接线**:9-3 的 memory stale 感知 + execute 时重读行 + bind 腿
  直接消化段2 的 stale+新 hash(9-3 移交面兑现);apply 收尾 `browserModel.reload`
  驱动徽章。
- **GUI 轮**(FINDINGS 09-4 节):真会话(2 张真 ARW,00012 带 .lra)全链——
  粘贴 15s 窗口内 claim/落盘/清 dirty/E 徽章/缩略图再生全部实证;split HUD +
  hold \ 键切换链截图 6 张归档。GUI-20(侧栏已编辑计数不即时刷新,轻)+
  GUI-21(segmented 控件 CGEvent 点击不可靠,AX radio 可靠——自动化按 AX 口径)。

## 遗留与风险

1. **跨图 undo 组**(plan 显式 defer):per-image commit 可退,批级 journal v2。
2. **层结构 merge**(D4):merge 只并全局实例;层结构合并 defer(v2)。
3. **skip 集 flag 制升级**(D1):IOPFlags 增 DEPRECATED/UNSAFE_COPY/HIDDEN 后
   平移;现边界 <15.0 常量随 v50 表(表变则常量变)。
4. **GUI-20 侧栏计数滞后**(轻):批量 apply 后已编辑计数待 reconcile/重开对齐;
   建议 Phase 12 顺手在 apply 收尾回填 counts。
5. **D10 观感 / 拖线手感 / peek 等待 / 部分对话框交互** Manual-Only 待人工
   (FINDINGS 09-4 表)。
6. **pasteSet 为持久格式增量**:09-05 签核的 VALIDATION 反模式扫描应把
   「pasteSet 往返 + 旧档兼容」列入回归抽查(现有 16+13 测试已盖)。

# M2-2-1 DECISIONS — 执行决策记录

> Plan M2-2-1 执行期决策（2026-09-29）。KD-1..7 = planner 裁决，逐条执行确认；D1..D8 = 执行偏差/细化，均实测归因，不重开任何 CONTEXT 裁决。

## KD 执行确认（planner 裁决 → 落地状态）

- **KD-1（包目录形态）✅**：常量落 `LibrarySchema`（`fileExtension`/`mediaDirectoryName`/`thumbsDirectoryName(stem:)`）；`image_path` + `path_kind`（PathKind 0/1/2）+ `volume_uuid` 冻结列在表；resolve/stale 归 P2 ImageLinker（本 plan 只测 path_kind 逻辑写入/读回 round-trip）。移动语义口径入 SUMMARY。
- **KD-2（版本化 + 迁移前快照缝）✅**：dispatch 读 `PRAGMA user_version`（真源），0→fresh（DDL + project_meta 播种 + stamp 1）/ 1→ok / >1→`LibraryError.futureSchema`，refuse 先于任何写（文件字节不动——比 session/catalog 的「先 DDL 后 dispatch」更严，user_version 使 absent 检测无需 meta 表）。`ProjectFileStore.dispatchSchema` 内 N→N+1 臂已建：先自动 backup 快照（`.pre-migrate.bak`）再 `LibrarySchema.migrate`；v1 下为结构性死代码（无 N ∈ 1..<1），M2-8/M2-10 激活预留表走此缝。
- **KD-3（L013 + images 冻结清单）✅**：28 列按清单序落 DDL；`params_hash` TEXT；消费点交叉核对全过——FTS `content_rowid='id'`（id 置首）、album_content 外键、M2-2-3 keyset `idx_images_capture(capture_date, id)`、四分组列（`camera_make`/`camera_model`/rating）、排序子集列（filename/rating/capture_date/iso/focal_length）全部实名在列。
- **KD-4（引用计数）✅**：`ref_count` 物化列（DEFAULT 0）+ 同事务联动；add 幂等（INSERT OR IGNORE + changes()==1 才 ++）；remove/subtree-remove 逐成员行递减（一图在子树两相册付两次，`MAX(ref_count-1,0)` 封底）；归零不删行（测试钉）；删 images 行由 FK CASCADE 连带清 membership（ref_count 随行亡，无需簿记）。
- **KD-5（FTS5 同步）✅**：external-content + 触发器映射 `new.`/`old.exif_search_words`；FTS 列名与 images 列同名（E3 钉）；rebuild 幂等测试过；tokenizer 零定制 + tokenchars 负例断言。NULL words 先插后 UPDATE 的路径（Indexer round-trip 实测）触发器对称工作。
- **KD-6（checkpoint 纪律）✅**：节流 = plan 字面 **OR** 语义（≥2s 或 ≥64 写批）；`close()` 强制 TRUNCATE，busy/log 非零抛 `checkpointFailed` 不静默；`-wal` 0 字节实测断言（64 批边界 + close 后）；backup 走 sqlite3_backup。
- **KD-7（FilterDomain.library 5 臂）✅**：orderBySQL tiebreaker `image_path ASC`（file_stem 备选未用，plan 允许落 DECISIONS）；baseline `(1=1)`；columnRef `+i.`；keywordsCondition = session 四子句形状打物化列（独立 `.library` 臂，非合并模式，grep 可见）；SmartAlbumStore.evaluate = typed `missingStore` 占位（M2-2-3 补真实现）。五处均无 default 臂（编译器穷举强制）。`.session`/`.catalog` 输出字节回归快照钉死（LibraryFilterDomainTests 专条 + 既有四 suite 零改动全绿）。

## 执行决策（D1..D8）

- **D1 测试数 61 > plan 预估 25..35**：词表族逐变体断言（f2.8/f 2 8/iso800/iso 800/35mm/35 mm/日期五变体/曝光倒数族）+ typed 错误面逐 case（unknown id 六面）+ KD-2 dispatch 三分独立用例——同一 AC 面的更细分账。判据（0 fail）不受影响，SUMMARY 已注。
- **D2 tuist generate 分任务补跑**：plan「T1 一次建齐 5 文件 + 测试 → generate 一次」的假设与「每任务独立提交」的提交纪律冲突（T1 提交时 T2-T4 文件若已存在会混入工作区边界核对）。选择分任务提交、新文件任务各自 generate（T2/T4 各一次）；产物等价，边界更干净。
- **D3 backup 源 = 第二只读短连接（裸 sqlite3 C API）**：计划假设「`withHandle` 拿 handle 做 backup」，但 `SQLiteHandle` 不暴露裸 `OpaquePointer` 且 Session 域冻结（红线 5 只许动两文件）。改为 ProjectFileStore 内自管裸连接对（源 READONLY / 目标 RW|CREATE），WAL 下第二连接读提交快照、backup API 持一致性（探针 P3 同款姿态实测过）。`SQLiteHandle` 零改动。
- **D4 `sending` 闭包 + Sendable 返回约束**：`withHandle`/`withWriteBatch` 在 Swift 6 strict concurrency 下跨 actor 传闭包触发 region-isolation 错误；参数标 `sending`（SE-0414）+ `T: Sendable`。缝语义不变：handle 恒不出 actor，测试侧闭包去 self 捕获（helper 提 static）。
- **D5 光圈 spaced 变体 = 数字分段 `f 2 8`**：首实现把小数点留在了 spaced 形态（`f 2.8`）；unicode61 下 `2.8` 会被切成 `2`,`8` 两 token，`f 2.8` 与 `f 2 8` 语义等价，但 plan 字面钉 `f 2 8`——词表列用 plan 字面（测试捕获后修正）。查询侧 `f2.8`/`f/2.8`/`f 2.8` 三拼法归同变体集。
- **D6 canonicalDecimal 双加点 bug**：查询侧光圈正则的 fraction 已带点、`canonicalDecimal` 又拼点 → `"2..8"` → Double nil → 0（`f0` 变体）。单测捕获，去调用侧加点。教训：数字拼接两处 Only-One-Place 原则。
- **D7 语句复用缺 reset**：removeAlbum 的 decrement UPDATE 在循环内复用，step DONE 后未 reset 即 rebind → SQLITE_MISUSE（code 21）。级联子树测试捕获，补 `reset()`（教训候选 L：SQLiteStatement 复用循环必须 reset-before-bind——与 seedProjectMeta 既有写法对齐）。
- **D8 images.image_path 无 UNIQUE 约束**：v1 冻结面按 plan 列清单字面落，未加 UNIQUE；导入去重 = P2 导入面的 SELECT-then-INSERT 逻辑（P2 注意：DB 层无唯一兜底，若 P2 plan 假设有需回此账）。
- **D9 createAlbum 统一 typed 面**：`FilterPredicateGroup.validating()` 失败不裸抛 FilterPredicateError，包成 `LibraryError.constraintViolation(detail:)`（原错误进 detail）——store 消费方只需捕 LibraryError 一族。

## 教训（已落 `.work/LESSONS.md` L037/L038）

1. **L037** D7 语句复用 reset 纪律（SQLiteStatement 循环内必须 reset-before-bind）。
2. **L038** XCTest actor 断言模式：`XCTAssert*` 自闭包不支持 await——actor 调用先落局部变量再断言；typed 错误断言用 do/catch 辅助函数；`sending` 闭包零实例捕获（helper 提 static）。

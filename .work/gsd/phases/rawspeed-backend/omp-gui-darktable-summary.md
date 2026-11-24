# darktable M3a 第三轮 — 交付摘要（2026-11-25，omp）

## 结论头

| 档 | 选中（DB 核对） | 首张生效 | 完成 | 结果 |
|---|---|---|---|---|
| 101 张 | 101 | <0.4 s | ~2 s | 可用：≈50 张/s |
| 1,000 张 | — | — | — | 未测（时间盒耗尽） |
| 10,000 张 | 10,000 | — | **无有效完成时间** | 逐张元数据 + 10,000 个 XMP 写出（≈90 s 跨度）但 `history` 表零增长 |

**判定句**：对照「懒渲染，批量修一万张也只要几秒」——**不成立**。本机最好观测速率 ≈50 张/s（101 张 ≈2 s，外推 10k ≈3.3 min，已高一个半数量级）；10k 档三次尝试中，最远一次完成了 sidecar 与元数据却**没有把 history 持久化**。粘贴路径不解码，失败/慢的根源在架构/代码（逐张 DB 写 + `dt_image_synch_xmps` 逐张 sidecar + 大体量单任务），**不是解码器**。

## 关键数字与证据

- 库：11,103 行（10,000 / 1,000 / 101 + 2 个重复导入产物）；硬链接样张 23 MB CC0 DNG。
- 粘贴语义 = **append**（源图 9 个可复制模块追加到目标），不是覆盖。
- 复制状态有效判据：`libs/copy_history.c:75-90`（多选，或单选且非源图）；只选源图时 paste 按设计置灰。
- 10k 档 A 轮：4 Hz DB 轮询 → 应用日志 **352 条** `sqlite3 error 5 (database is locked)`；库为 `journal_mode=delete`（darktable 强制 MEMORY），读锁饿死写事务 → 该轮作废（`evidence/gui/darktable-c-dblock.txt`）。
- 10k 档 C 轮：`batch/n10000/` 实得 **10,000 个 `.xmp`**（mtime 02:23–02:24，含 exposure），10,000 张 `change_timestamp` 跨度 **90.1 s**；`history` 总数 16,514、film 1 有历史 7,364 张——与开跑前一致（`evidence/gui/darktable-c-10k-evidence.txt`）。
- 方法学：`journal_mode=MEMORY` 的库不能用高频只读轮询做完成判据；改用 UI 进度条或 sidecar 计数。

## 删除与偏好

- 进程清零（`pgrep` 自证）；`$G/darktable/` **523 MB** 已删（app、隔离 HOME、11,103 硬链接、11,101 XMP、DB、帧、日志）；`df` 39 GB avail。
- 偏好：`defaults import org.darktable` 已执行，**磁盘 plist 内容已还原**（1726 B，5 键）；但 `defaults read` 仍空（cfprefsd 缓存；按纪律未 killall cfprefsd）。风险：缓存落盘可能覆盖；备份原件随 `$G` 删除，无法二次还原。
- `~/Library` 顶层无新增 darktable 条目。

## 自审

`evidence/gui/darktable-c-SELFREVIEW.md`：**PASS / 0 error + 0 minor**（脚本复算：CSV 两行、targets=10000、grown_after=0、352 条锁错误、10k XMP、报告六项断言、库内皮面复核）。

## 未验项

- 1,000 张档未测。
- 10k 档「history 未持久化」只做了 DB/文件层取证，未定位到 darktable 内部具体代码路径（单事务回滚 vs 写锁失败）。
- 粘贴按钮的真实鼠标点击在启用状态下不生效（原因未定位）；101 档靠 `Ctrl+V` 生效。

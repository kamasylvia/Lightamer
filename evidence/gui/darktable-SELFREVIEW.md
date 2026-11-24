# darktable GUI lane — self-review (补测批, §10)

结论头：**PASS / 0 error + 0 minor**（脚本核对；域内 omp 自审实例未启动，原因见下）

## 为什么是脚本核对

- 通用任务书要求另起 `omp -p` 自审实例；上一对象同一位置的自审实例在 170 s 被 SIGTERM、无产出。
- 本补测批的总墙钟已被驱动调试吃掉（90 min 上限），00:20 后不再有启动自审实例的预算。
- 任务书允许的回落：「若仍失败，改为用脚本从 CSV 复算全部统计并与报告逐项核对，在报告里写明是脚本核对」。本文件即该回落。

## 核对项与结果

脚本：`evidence/gui/darktable-b-selfcheck.py`（可复跑）。执行输出：

```
PASS 0 error
recomputed rate=12.47/s ms=80.20 extrapolated_10k=802.0s (13.37 min)
```

逐项：

1. **算术自洽**：`darktable-b-thumbs.csv` 的 `rate_per_s` / `ms_per_thumb` 由 `n_thumbs=101`、`elapsed_s=8.1` 复算一致（12.47 张/s、80.20 ms/张）；报告 §10 的 13.3 min = 10,000 × 80.2 ms = 802 s。
2. **报告数字 ↔ CSV**：`4.736`（导入窗口）在报告与 import CSV 同时出现；`13.3 min` 在报告 §0 与 §10 同时出现；`800 s` 与复算值一致。
3. **粘贴失败声明 ↔ 源码**：
   - `release-5.6.2:src/lua` 中 `paste_history` 命中 0 次（§10.2 第 1 条成立）。
   - `release-5.6.2:src/lua/events.c` 的 shortcut 注册行含 `dt_action_register(..., 0, 0)`（无默认键，第 3 条成立）。
   - `release-5.6.2:src/gui/accelerators.c` 含 `_find_views(ac)` 的 view-flag 检查（第 2 条成立）。
4. **粘贴 CSV 完整性**：6 条尝试、无一行是成功（第 4/5/6 条为环境/驱动失败，不是产品成功）。

## 未覆盖（脚本无法替代的部分）

- 存证帧抽检：本轮帧随 `$G/darktable` 一并删除，未做独立抽检；§10 的结论不依赖帧，只依赖 DB 计数与源码。
- 运行时 `ret=nan` 的原始 Lua 日志随 `$G` 删除；报告中的引用来自当轮终端输出（本文件不重造证据）。

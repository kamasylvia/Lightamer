# omp GUI lane — darktable 补测批 summary (2026-11-24)

## 结论头

- **M3a/M3b/M3c：未测得**（6 条驱动路径全部未能创建粘贴任务；任务书假设的 Lua `image:paste_history` 在 5.6.2 不存在）。
- **M1 热：未测**（时间盒耗尽）。
- 新增硬数字：**101 张导入在主窗 4.736 s 时已完成**；**缩略图 crawler 101 张 ≤8.1 s = 12.5 张/s = 80.2 ms/张** → **全量 10k 外推 ≈802 s ≈13.4 min**（默认 `backthumbs_mipsize=never` 时不发生）。
- 判定：粘贴仍是**DB-only 懒渲染**（代码路径不变，§3/§10.4）；但本轮**没有粘贴墙钟**，不能宣布「一万张几秒」。缩略图侧不懒：80 ms/张。

## 关键表

| 项 | 值 |
|---|---|
| 导入 101 张（窗口出现时刻） | 4.736 s |
| 缩略图 101 张 | ≤8.1 s（12.47/s，80.2 ms/张） |
| 10k 全量缩略图外推 | 802 s（13.37 min） |
| 粘贴任务创建次数 | 0 / 6 次尝试 |
| 源图 history | 11 项，exposure +0.7 EV |

## 失败根因（源码）

1. `release-5.6.2:src/lua/image.c` 无 `paste_history`。
2. `dt.gui.action("views/thumbtable/paste history")` → `ret=nan`；`accelerators.c:4476-4483` view-flag 检查拒绝 thumb 动作。
3. `events.c:666` Lua 快捷键动作无默认键。
4. 合成 Ctrl+C 没有建立 copy 状态（`act_on.c:650` → active_images），Ctrl+V 在 `control_jobs.c:2595` guard 处直接返回。

## 删除与收尾

- `$G/darktable`（491 MB）已删；进程 `pgrep lightamer-gui-test` 清零。
- `org.darktable` 已 `defaults import` 还原；`~/Library` 前后 diff 为空；`df -h /` 41 GB。
- 自审：**脚本核对 PASS / 0 error + 0 minor**（`evidence/gui/darktable-SELFREVIEW.md`；omp 自审实例未启动，时间盒耗尽后按任务书回落）。

## 未验项

- M3a/b/c 全部；M1 热；n1000/n10000 导入与粘贴；存证帧抽检（帧已随 $G 删除）。

## commit

（见本提交）

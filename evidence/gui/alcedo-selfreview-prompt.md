你是 Alcedo Studio GUI 计时 lane（Lightamer issue #26）的独立域内自审。只读，不改报告/CSV/帧。工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。

# 输入（只读这些）
- 报告：`.work/gsd/phases/rawspeed-backend/GUI-alcedo.md`
- CSV：`evidence/gui/alcedo-m1m2.csv`、`alcedo-hot-zoom.csv`、`alcedo-zoom.csv`、`alcedo-m3-100.csv`、`alcedo-m3-1000.csv`、`alcedo-m3-10000.csv`
- 帧：`/Users/Shared/lightamer-gui-test/alcedo/frames/`（约 270 张；抽 3 张：`cold-1-2-ready.png`、`hot-2-10-ready.png`、`zoomx-2-after.png`）
- 源码参考：`/Volumes/UNITEK/Documents/Development/AlcedoStudio/alcedo_studio/src/renderer/pipeline_scheduler.cpp`、`.../src/ui/alcedo_main/album_backend/adjustment_transfer_apply_coordinator.cpp`、`.../thumbnail_manager.cpp`
- 脚本：`evidence/gui/_harness/{alcedo.py,measure1.py,measure1b.py,measure3.py,cap_shot.py}`

# 检查项（逐项给证据）
1. 统计复算：cold/hot/edit/zoom 的 n、median、min、max 与报告 §0 表逐格核对；M3 三档的 import/paste/task/thumb 数字与 CSV 核对。
2. 抽 3 次运行复看存证帧：就绪帧确实是完整图像（非黑/非空 UI）；`hot-2-10-ready.png` 应是 GFX 图；`zoomx-2-after.png` 右下读数应是 95%（1:1 档）。
3. 归因自洽：报告说「粘贴不逐张解码、84 张/s」是否有 CSV + 代码路径支撑（`adjustment_transfer_apply_coordinator.cpp` 的循环与 `RefreshOneTarget`）；「热切 16× 是架构原因」的 66 s vs 冷开 4.0 s 是否同文件、同口径。
4. 边界诚实：内存压力 22%、热切 n=3/4/3、5–8 Hz 判据地板、Z8 preview2 坏图这些限制是否写进 §8；有没有把「命令返回」和「稳定」混为一谈。
5. 与 SPIKE §4 对账的减法是否算错（3.846 − 0.83 − 0.08 ≈ 2.94 s；GFX 3.996 vs 0.556 = 7.2×；60 s vs 4 s = 15×）。
6. 报告是否泄露用户真实项目名/路径/张数；启动器是否被截图（不应有）。

# 输出
- 只写 `evidence/gui/alcedo-SELFREVIEW.md`。
- 第一行结论头：`PASS` 或 `N error + N minor`。
- 每条 finding 给文件:行号/数据依据；error = 数字错、口径混、无证据的断言；minor = 表述/四舍五入/未验项不全。
- 4 分钟内完成；不要改任何其它文件。最后一条消息输出结论头与 finding 列表。

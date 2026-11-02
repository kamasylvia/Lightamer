# library-first-launch 走查 MANIFEST（2026-11-02）

首启图库优先真机三项（产物二进制 dgzsvdw…/Debug，macOS 27）：

| # | 文件（本地，git-ignored） | 断言 |
|---|---|---|
| 1 | `lfl-01-first-launch.png` | 冷启动（无默认库）→ 顶栏 "Library" + 中央空态三件（文案/导入按钮/拖放提示）+ 右 Inspector 0 照片总数；**无 Welcome sheet** |
| 2 | `lfl-02-import-panel.png` | ⌘⇧I（空态按钮同 impulse）→ 文件夹选择面板弹出（Import Folder 腿活） |
| 3 | `lfl-03-relaunch.png` | 二次启动（默认库已在，recents 非空）→ 直进图库面，**无 Welcome 回退** |

附带验证：`~/Library/Application Support/Lightamer/Library.lalb` 首启自动创建；
File 菜单 Import Folder… 在位（AX 实证）；正常 quit 零残留进程（lock 文件死 pid
残留 = SingleWriterLock fixture 设计，flock 仲裁不受影响）。

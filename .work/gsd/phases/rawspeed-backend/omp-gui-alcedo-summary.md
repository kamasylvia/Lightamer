# Alcedo Studio GUI timing — lane summary (issue #26)

HEAD at start: `4349dee034e16f2f3ae9e1f187919feb57738080`
Binary: Alcedo Studio 0.3.6 official arm64, SHA256 `549b2b0a72036f0f1b78e555eafde0d686797f88759c20ae664f6d63b31b76b7`

## 结论头

| 项 | 数字 |
|---|---|
| M1 冷（launch→首图稳定，n=5/样张） | 7RM5 **3.846 s** · GFX100S **3.996 s** · Z8 **3.616 s** |
| M1 热（编辑器内切换，n=10） | 7RM5 **3.775 s**（n=3）· GFX **57.914 s**（12.0–65.6，n=4）· Z8 **34.079 s**（23.4–40.8，n=3） |
| M2 曝光（n=10，每次 +0.5 EV） | 命令返回 **0.163 s** · 视口稳定 **1.548 s**（判据地板约 1.0 s） |
| 100% 放大（n=5） | 细节到位 **1.40 s** · 稳定 3.42 s（8 帧地板） |
| M3a 粘贴（99/999/9,999 张） | 命令返回 0.215/0.095/0.228 s · 后台 **1.516 / 12.703 / 118.895 s**（84 张/s） |
| M3b 缩略图（强制全量） | 99 张 **38.1 s**；1k ≈**7.2 min**、10k ≈**76.9 min**（40 张采样外推） |
| M3c 刷新期打开 GFX | 命令 **14.7 / 33.1 / 23.7 s**（空载 5.10 / 5.43 / 4.84 s = 2.9× / 6.1× / 4.9×） |

**判定句：** 批量粘贴合格（懒在 version/DB 层，84 张/s，不逐张解码）；单图打开/切换不合格（`FAST_PREVIEW` 仍 `DecodeRes::FULL` + 2560，切换全程黑屏，100 MP 热切从 12 s 恶化到 54–66 s，同文件冷开 4.0 s = ≥16×（open 相位 ≈21×））——架构/调度原因，不是单纯解码器。

## 删除结果

- 已删 `/Users/Shared/lightamer-gui-test/alcedo/`（2.1 GB）；`pgrep -x AlcedoStudio` = 0。
- `defaults delete com.alcedo-app.Alcedo` + 空 plist 删除；新 Library 条目 total=0；用户既有 `Application Support/Alcedo` 未动。
- 磁盘 35 GB → 38 GB 可用；`$G/_harness`、`$G/_launchcheck` 保留。

## 自审

- r1 = 3 error + 7 minor（`evidence/gui/alcedo-SELFREVIEW-r1.md`）；r2 = 1 假 error（证据未提交、误用 `git ls-files`）+ 5 minor；r3 = **PASS**（`evidence/gui/alcedo-SELFREVIEW.md`）。

## Commit

- `d574dc7a42a5e3eef6f7bb3111a0489163abeb90` — `docs(gui-timing): add Alcedo Studio 0.3.6 latency report`（20 paths；body `Refs #24` / `refs #26`）。此 SHA 行在提交后写入，不在该 commit 内。

## 未验项

- 热切轮次可用内存 22%（低于守卫 30%），热切数字含系统压力；热切 n=3/4/3。
- 截帧分相（单轮取值带）：编辑 2.76–3.53 Hz、冷开 4.76–7.38 Hz、热黑屏 7.75 Hz、zoom 3.91 Hz；3/8 帧判据地板已单列，M2/100% 的稳定值被地板放大。
- 缩略图解码 vs 管线+编码未拆分；无逐 rep CPU/GPU 计数器。
- 未验证真机 Trackpad 手势；100% 用合成双击（读数 95% ≈ 1:1）。
- 过程偏差：一次 `screencapture -R` 速度测试拍到用户其它窗口，未读取内容，临时文件已删。

# omp GUI 计时总结 · LightCraft 官方 0.21.1

## 结论头

| 项 | 结果 |
|---|---|
| M1 冷开（n=5/样张） | 7RM5 ARW **4.011 s**、GFX100S RAF **4.033 s**、Z8 NEF **3.454 s**（启动 2.26–2.34 s + 图像段 1.12–1.78 s） |
| M1 热切换（n=12） | **0.720 s** 墙钟；应用自报缓存首帧 0–34.5 ms（12/12 `cached`），主渲染 114–148 ms 随后 |
| M2 编辑（n=12，±0.68 EV） | **0.211 s**（应用渲染 22.5–25.4 ms） |
| M3 批量粘贴 | 100 张 **18 ms** / 1 000 张 **50 ms** / 10 000 张 **347 ms**；可见缩略图刷新 0.53 / 0.53 / 0.40 s |
| M3c 刷新期打开 | 0.612 / 0.582 / 0.605 s（基线 0.720 s，无退化） |

**判定**：懒渲染四层（预览优先 / 视口尺寸渲染 / 设置键缓存 / 虚拟化网格）全部到位。**批量等待与解码器无关**（粘贴 = 纯设置批提交 34.7 µs/张；刷新只算可见+预取的 ~92 格，与 N 无关）。解码相关的最大一段是冷开图像段（0.61–0.90 s 应用渲染），已快于 darktable（1.12–1.80 s 墙钟 vs 1.7–2.1 s）。

## 删除结果

- 进程：App + lane 脚本 + 本 lane `caffeinate` 全部退出；用户既有进程未动。
- `$G/lightcraft/` 1.3 GB 已删除。
- 偏好：无新 domain、真实 `~/Library` 新增条目 0 → 无需还原。
- 磁盘：删除后 `/` 余量 36 GB。

## 自审

- R1：`evidence/gui/lightcraft-SELFREVIEW.md` = 5 error + 7 minor（统计/口径）。
- R2：`evidence/gui/lightcraft-SELFREVIEW-r2.md` = 1 error + 3 minor（修 R1；新发现的是首帧计数口径）。
- R3：`evidence/gui/lightcraft-SELFREVIEW-r3.md` = 0 error + 1 minor。
- R4：`evidence/gui/lightcraft-SELFREVIEW-r4.md` = **0 error + 1 minor**（该 minor 为措辞标签，已改写，无数字变化）。

## 未验项

- 墙钟含仪器相位（3 帧 ≈0.15 s + 0–0.5 s 状态轮询）；已用应用自报帧计时交叉标注。
- M3 目标为字节互异 JPEG（内容哈希去重使同内容硬链接坍缩），非 RAW。
- 自证相关：ARW 0.996 / RAF 0.996 / NEF 0.991（第一版固定 rect 对 RAF 只得 0.788）。
- 交换区基线 7.6–9.8 GB（既存），全程空闲 72–73%、无换页抖动。
- 未测 100% 缩放编辑、蒙版、导出、AX 语义树。

## commit

（收尾补 SHA）

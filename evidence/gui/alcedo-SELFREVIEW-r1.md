3 error + 7 minor

# Alcedo Studio GUI 计时 lane 自审（issue #26）

对象：`.work/gsd/phases/rawspeed-backend/GUI-alcedo.md`（2026-11-25）。只读复算 6 个 CSV、194 张 PNG 抽样、Alcedo 源码；未改报告/CSV/帧。

## 已复核通过（不需修）

- **统计复算**：cold 7RM5 3.8462 [3.8257/4.4003]、GFX 3.9958 [3.9605/4.1169]、Z8 3.6160 [3.5448/3.6769]；hot 3.7754/57.9137/34.0787（n=3/4/3，min/max 全对）；edit set 0.16345 [0.11383/0.20362]、stable 1.5481 [1.3953/1.9556]、onset 0.92945 [0.8291/1.2555]；zoom n=5、min 3.3579/max 3.5493 — 与 §0 逐格一致（唯一 median 偏差见 M3）。
- **M3**：import 0.137/0.933/8.987 s、paste 0.215/0.095/0.228 s、task 1.5156/12.7030/118.8949 s（applied 99/999/9999，failure 0）、thumbs 38.11/17.20/18.46 s 与 CSV 全对；吞吐 65.3/78.6/84.1 张/s 复算一致。
- **帧**：`cold-1-2-ready.png` 为完整 7RM5 图（草坡/树/直方图/胶片带，非黑非空）；`hot-2-10-ready.png` 为 GFX 图（文件名 `Fujifilm-GFX100S-…RAF`，std 79.9）；`zoomx-2-after.png` 右下读数 **95%** ✓。
- **归因代码**：`adjustment_transfer_apply_coordinator.cpp:132-165` 循环内只有 LoadHistorySnapshot→PasteAsRootRelativeVersion→PersistHistory，无解码/渲染调用；`thumbnail_manager.cpp:450-467` 只遍历 `thumbnail_pins_`；`library_commands.cpp:51` `kThumbnailsInFlight = 4`；`pipeline_scheduler.cpp:26-27,151,159,178,190` = 2560/8192，`pipeline_apply_request.hpp:50` = 4096 — 引用与本地 clone 一致。
- **泄露**：报告只用 `$G` 与 TestRAW 路径；抽帧文件名均为 CC0 样张（7RM5/GFX/Z8），无用户实拍项目名/路径；194 张 PNG 亮度扫描（max mean 77）无启动器/白底帧。§1.1 DMG 176,082,021 B、SHA256 `549b2b0a…b76b7`、`studio.alcedo.Studio`/adhoc 复算一致。
- **§5 算术**：3.846−0.83−0.08 = 2.936 ≈ 2.94；3.996/0.556 = 7.19；65.626/3.996 = 16.4 — 减法/倍率本身无错（对象错配见 E1）。
- **§8 边界**：22% 内存、热切 n=3/4/3、Z8 preview2 0.116、CGWindowList 全黑均已写。无「命令返回=稳定」的混写（M1/M2 分离正确），唯 M3c 基线除外（E2）。

## error

**E1 §5「大图（GFX 210 MB）| P1 冷开 556 ms」对象错配。**
SPIKE 全篇只有一个样张：`SPIKE.md:15` = `7RM5-LosslessCompressedLarge.ARW`（85.9 MB/85 MP）；`SPIKE.md:204-205` 的 556 ms 是该 ARW 的**全分辨率**值，不是 GFX 210 MB，也不是 2560 档。`GUI-alcedo.md:144` 把它当 GFX 基准得 7.2×，`§5` 同行的「热切差 ~100×」（57.9/0.556）同错。文件与分辨率档双错配。修法：GFX 行标注「无 file-matched CLI 数字」；唯一可比的是 85 MP ARW 行（已 file-match），或补测 GFX 的 SPIKE 数字。

**E2 M3c 基线口径混：stable 分子 vs 命令返回分母。**
`GUI-alcedo.md:47`「16.9 s 稳定（基线冷开 GFX 5.1 s）」、`:136`「16.9–34.1 s vs 空载 5.1 s（3.3–6.7×）」。CSV 里 `m3c_open.ready` = 16.8988/34.1273/24.7632（capture stable），而 `open_source.sec` = 5.0956/5.4315/4.8437（`editor.open` **命令往返**，无 cap）。同口径（命令返回）比值 = 14.740/5.096 = **2.89×**、33.149/5.432 = **6.10×**、23.677/4.844 = **4.89×**（即 2.9–6.1×）；3.3–6.7× 用 16.9(stable)/5.1(cmd) 得，抬高约 10–15%。且 5.1 被三档共用，实际基线 5.10/5.43/4.84。修法：分子分母同用命令返回，或补测空载 stable。

**E3 截帧率「5–8 Hz / 3 帧地板 0.6–0.9 s」与自有 CSV 矛盾。**
`GUI-alcedo.md:38`「以 5 Hz 窗口截帧为准」、`:103`「约 5–8 Hz」、`:169`「5–8 Hz：3 帧 0.6–0.9 s，8 帧 2.4 s」、`:187` 同。实测 cap 中位 Δt：`edit-1` 0.349 s / `edit-5` 0.315 s（**2.9–3.2 Hz**）、`zoomx-2` 0.256 s（3.9 Hz）、`cold-1-2` 0.146 s（6.8 Hz）、`hot-2-10` 0.129 s（7.8 Hz）；只有黑屏期达 7.8 Hz。故 M2 的 3 帧地板 ≈ **1.0 s**（非 0.9），5 Hz×8 帧=1.6 s 也与「8 帧 2.4 s」自相矛盾（2.4 s 对应 3.3 Hz）。结论（Alcedo 慢）不变，但 §8 的地板披露数字须改为按测量类分列（渲染 2.9–3.9 Hz / 黑屏 7.8 Hz）。

## minor

**M1 `:27` 热切示例混用 rep4 与 rep10。**
rep4（第 2 次 GFX）：t_open 58.664、图片 60.877、stable 61.535；rep10（第 4 次 GFX 切换）：t_open 61.140、图片 **64.923**、stable 65.626（黑屏 1.204→64.923 ≈ 63.7 s）。句中「图片 60.88 s 出现」属 rep4，「65.6 s 稳定」属 rep10，「黑屏 60.9 s」≈rep4。修法：分开写 rep4（60.88/61.53）与 rep10（64.92/65.63）。

**M2 证据链与脚本对不上（`:118`）。**
`alcedo-m1m2.csv` 的 10 行 hot 全是 `error`（`unsupported operand type(s) for -: 'float' and 'list'`，measure1.py `off = t - cap.args`）；hot 真值在 `alcedo-hot-zoom.csv`（measure1b.py），报告未说明重跑。zoom：`alcedo-zoom.csv` 数值 = `zoomx-*` summaries（n=12、stable_n=8），但 `_harness/` 无生成 zoomx 的脚本（measure1.py 用 `inp.key('1')`、measure1b.py 用 `inp.key(18)`，均非双击；报告 §1.4 称键盘 1 已弃用、双击测）。需落 zoom 脚本或标注 ad-hoc。

**M3 舍入/复算小漂（≤0.03 s）。**
窗口出现 0.83/0.83/0.89 vs csv 中位 0.819/0.803/0.885（GFX +0.027，`:12-13`）；`editor.open` 1.63/1.03 vs 1.621/1.036（`:13`，而 `:180` 写 1.04–1.62，报告内自相矛盾）；zoom ready median 3.41 vs 3.4225（`:46`）；「首见 3.2–3.5 s」不含 Z8 的 2.95（`:16`，按 diff_prev≥0.5 复算 3.160/3.362/2.967，定义未在 §1 给出）；10k 外推 4,608 s/76.8 min vs 9999/40×18.4617 = 4,615 s/76.9 min（`:128`）。

**M4 §7「删除」未执行且帧数不符（`:159`）。**
`/Users/Shared/lightamer-gui-test/alcedo/` 仍在：apps 484M、dl 226M、batch 10,000 硬链接、batchproj*、thumbs 99/40/40、frames（194 PNG，314 文件）、logs、home、project；`defaults domains` 仍有 `com.alcedo-app.Alcedo`；进程 0（已清）。「约 270 帧」vs 194 PNG。修法：§7 改将来时/勾选状态，或真删后再写完成。

**M5 源码引用属 v0.3.3，非被测 0.3.6（`:65,:135`）。**
本地 clone HEAD `6024386` = tag **v0.3.3**（2026-10-15）；DMG 是 **0.3.6**（2026-11-17）。行号在该 clone 上核对通过，但 `:163` 实际是 `QUALITY_BASE_PREVIEW` 分支行，ROI 的 2560 finish 在 **:159**。建议标注「源码引用 = v0.3.3 clone，行为在 0.3.6 上实测」。

**M6 16× 口径不对称（保守方向，`:28,:65,:181`）。**
cold 3.996 含 0.83 窗口 + 0.08 项目（`:16` 自述），hot 65.6 从 pre-open 截帧起算；同文件但窗口不同。按 open 相位算 65.626/(3.996−0.91) ≈ **21×**，16× 是下界。建议写「≥16×」或统一原点。

**M7 启动器内容断言未观测（`:18`）。**
「启动器只显示本 lane 的项目，未出现用户真实最近项目」无截图佐证（194 PNG 全是编辑器）；它是隔离 `HOME/CFFIXED_USER_HOME` 的推断。建议 §8 标为推断，或补一张启动器帧（当前「启动器不截图」本身为真）。

## 结论

数字主体（cold/hot/edit/M3、三张抽帧、代码路径、SPIKE 减法）成立；三处 error 均为可比性/口径问题（E1 跨文件+跨分辨率、E2 stable vs 命令返回、E3 采样率），不影响「Alcedo 单图切换分钟级、批量粘贴懒在 DB 层」的方向性结论，但影响对外引用时的数字可信度。修 E1–E3 + M1/M3/M4 后可锁定。

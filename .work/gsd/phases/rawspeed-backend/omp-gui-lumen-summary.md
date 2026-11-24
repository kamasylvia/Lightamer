# Lumen RAW 2.3.0 GUI 计时 · 执行摘要（Lightamer #26）

HEAD `c8bd209bd2c3ab76f905c055d6747e6d94d82811`。报告正本 = `GUI-lumen.md`，CSV = `evidence/gui/lumen-*.csv`，脚手架 = `evidence/gui/_harness/`。

## 结论头

| | 值 |
|---|---|
| M1 冷（n=5，`open`→稳定） | **4.25 / 4.35 / 4.24 s**（7RM5 / GFX100S / Z8）；应用引导 3.06 s，图后段 1.18–1.29 s |
| M1 热切换（n=10） | **0.98 s**（0.88 / 1.06） |
| M2 编辑（n=10，±0.3 EV） | **0.854 s**（0.816 / 0.981） |
| M3a 粘贴 | 100 张 0.063 s；1000 张 1.16 s；1999 张 4.60 s（2.30 ms/张） |
| M3b 缩略图刷新 | **不刷新**（0/N；+2 EV 后首条缩略图帧差 1.83/255，证据 `evidence/gui/lumen-m3b-thumbs.md`） |
| M3c 刷新期可交互 | 否——粘贴在 GUI 线程（源码推断 + 探针实测），2000 张时 ≥2.0 s 无响应 |
| N=10000 | 未测：产品上限 2000 张（`library.add` 报错），按上限补测 1999 |

## 判定

- **打开/热切换合格**：解码+首屏 1.18–1.29 s，无长挂起；冷启动的 3.06 s 是 PyInstaller 引导，不是解码。
- **编辑 0.854 s = 架构原因**（整管线重跑 + 180 ms 防抖），解码器占比 0。
- **批量等待 = 架构原因**（O(N²) 条目查找 + 前台同步 + 无缩略图失效），解码占比 0；换 rawspeed 救不了这两项。

## 方法与限制

- 合成鼠标/键盘在本会话不被投递（已实测），M1 冷用 `open -a`、其余用应用自带控制通道（`photo.open` / `edit.apply` / `edit.copy`）。
- 隔离 HOME + 硬链接样张；`AXIsProcessTrusted=True`；截图只用 `screencapture -l <本 lane 窗口>`。
- 自证：就绪帧画布 vs `lumen-cli render` 参考图 r = 0.955。
- 就绪判据在自审后修正（去掉 `std > 8` 假阳性旁路），GFX/Z8 冷启动数字为重测值。

## 删除

`$G/lumen/` 已删（2.3 GB：App 910 MB、DMG 632 MB、隔离 HOME 157 MB、存证帧 269 MB、15,099 个硬链接 341 MB）；真实 `~/Library` 只删运行前不存在的三条 `LUMEN RAW` 条目（Application Support / Caches 2.2 GB / Logs）；`defaults` 域名前后无差异。磁盘余量 37 GB → 38 GB。

## 自审

- 第一轮：`FAIL / 4 error + 9 minor`（`evidence/gui/lumen-SELFREVIEW.md`）——抓到冷启动判据假阳性、M3b 无工件、§4 推断当实测、§7 未删先写。四项已回修。
- 第二轮：`omp` 实例启动后 ~20 min 未产出（日志只有 `Working...`，已被本 lane 终止），**无第二轮结论**；4 个 error 的逐条回修证据在 `evidence/gui/lumen-SELFREVIEW-RESPONSE.md`。

## 未验

- 滑杆拖动的连续渲染（合成输入不可用）；100% 放大细节读取、导出、AI 功能；缩略图单张成本未单独计时（代码路径 + 导入总时长代替）。
- CPU/GPU 占用未逐 rep 采样。

- `c68e6ddb` — `docs(gui-timing): add LUMEN RAW 2.3.0 real-machine latency report`（2 paths：本报告 + 本摘要；body `Refs #24` / `refs #26`）。此 SHA 行在提交后写入，不在该 commit 内。CSV / 脚手架 / 自审文件在 `evidence/gui/`（本仓证据链分仓策略，`.gitignore`，未入仓）。

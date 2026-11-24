# RawLab GUI 计时 · 收口摘要（#26）

- HEAD：`2372a1f853014b6bf733e6c8d7080886ee4f7144`
- 对象：RawLab 官方 0.12.0（macOS arm64），`RawLab-Mac-0.12.0-arm64.zip`，SHA256 `6f2cca0b…8b`（官方 SHA256SUMS 一致），adhoc / spctl rejected / quarantine 已剥。
- 报告：`.work/gsd/phases/rawspeed-backend/GUI-rawlab.md`；数据：`evidence/gui/rawlab-{cold,hot,m2,m3}.csv`；自审：`evidence/gui/rawlab-SELFREVIEW.md`。

## 关键数字

| 项 | RawLab 0.12.0 | darktable 基准 |
|---|---|---|
| 冷打开（含启动） | 6.75 s NEF / 7.55 s ARW / 8.21 s RAF | 6.2–6.5 s |
| 其中应用启动 | 2.3 s | 4.5 s |
| 窗口→图稳定 | 4.40 / 5.21 / 5.90 s | 1.7–2.1 s |
| 热切换 NEF | 4.03 s（n=6） | — |
| 热切换 RAF 210 MB | **≥86 s 整窗冻结**（6/6 超 25 s；单探针 86 s 帧差 0.00） | — |
| 编辑 | 1.119 s（n=10，onset 0.62 s） | 0.68 s |
| 批量 100 张 | prepare 2.82 s + apply 2.65 s（26–30 ms/张） | ≈20 ms/张 |
| 批量 1100 张 | 导入 8.83 s；prepare >120 s 超时 | — |
| 缩略图刷新 | 不刷新（无失效通知，源码证据） | ≈80 ms/张、按需 |

## 判定句

- 冷打开 = 解码/显影成本：启动 2.3 s + 图后段 4.4–5.9 s；100 MP 只多 1.46 s，换 rawspeed 收益上限约 3–4 s（受 2.3 s 启动限制）。
- 热切换 100 MP RAF ≥86 s 冻结 = 架构/代码原因（主线程阻塞 + 内存膨胀：96% CPU、RSS 4.0→1.4 GB、swap 6.98/8 GB）；解码器只能救其中一段。
- 编辑 1.119 s = 架构原因（每次提交整条 develop 重跑，无 ROI/增量）。
- 批量 = 架构原因主导（O(N) 逐张 `probeRAW` + 主线程同步写 + 缩略图不失效）；解码器原因占比小（只读 RAW 头，不全图解码）。

## 删除结果

- `$G/rawlab/` 全树 5.2 GB 已删（apps/dl/batch/frames/src/samples/home/logs）。
- 偏好域 `com.rawtools.rawlab.mac`（运行前不存在）已 `defaults delete` 并删 plist；复查域名 0 命中、Preferences 无 rawlab 文件。
- `df -h /`：36 GB 可用 → 38 GB 可用（删后 84%）。
- 本 lane 进程清零（`pgrep -f "RawLab Mac.app"` = 0）。

## 自审

- 首轮：`FAIL / 4 error + 12 minor`（E1 onset 区间、E2 prepare 2.82 来源、E3 资源数字无存证、E4 「≥86 s」绝对化）。已逐条回修；E4 补入首轮低负载 7.27 s 完成观测，E3 补 `logs/resource-sample.txt` 点位采样。
- 复审（窄口径，独立 subagent）：`PASS / 0 error + 1 minor`（唯一 minor：§9 外发稿未复述 `m3-100b.json` 的计时起点误置，已引转录可追溯）。见 `evidence/gui/rawlab-SELFREVIEW-r2.md`。

## commit

单提交 `docs(gui-timing): add RawLab 0.12.0 real-machine latency report`（refs #26 / Refs #24；SHA 以 `git log` 为准，本条不内嵌以免 amend 自指）。

## 未验项

- M3 10000 未测（inode 去重 + 时窗）；M3c 未测（无后台刷新阶段）；NEF 相关度 0.856 < 0.9（已如实标注）。
- 热切换 RAF 的 86 s 含当时 swap 6.98/8 GB 的环境因素，报告已限定表述。

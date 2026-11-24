# 域内自审任务书 — darktable GUI 计时（#26）

你是独立自审实例。工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。只读，不改产物（发现 error 写进报告由主执行者回修）。

## 输入

- 报告：`.work/gsd/phases/rawspeed-backend/GUI-darktable.md`
- 数据：`.work/gsd/phases/rawspeed-backend/evidence/gui/darktable-*.csv`
- 存证帧：`/Users/Shared/lightamer-gui-test/darktable/frames/`（仓外；只读）
- 样张内嵌预览：`/Users/Shared/lightamer-gui-test/darktable/samples/*-preview{1,2,4}.jpg`

## 必做五件事

1. **统计复核**：从 CSV 重算每组的 median / min / p90（M1 冷 5 个/样张，热 10 个/样张，M2 10 个），与报告表逐项对比；差 >5% 标 error。
2. **口径核对**：M1 是否从进程启动量到视口稳定；M2 是否从松手量到稳定（报告须扣掉拖拽时长）；M3a/b/c 是否分别是「UI 接受 / 缩略图真值 / 积压期打开」。混入口径 = error。
3. **存证帧抽检 3 次**：任选 3 个 `*-ready.png` 与其 `*-first.png`，运行
   `_harness/venv/bin/python _harness/verify.py <first> <ready> <sample-basename>`，相关系数应 >0.9；
   并确认 ready 帧确为 darktable 暗房界面（不是启动 splash / 空窗）。
4. **归因数字自洽**：§4 的拆分（粘贴 UI 返回、DB 完成、缩略图刷新、单张缩略图成本）相加/外推须与 §3 表一致；外推方法须写明。
5. **隐私与边界**：报告/CSV 不得出现用户实拍文件名、GPS、作者、序列号；不得含图像字节。产品树须零改动（`git status --short` 只应有 `.work/gsd/phases/rawspeed-backend/` 与 `evidence/gui/` 文本）。

## 输出

写 `.work/gsd/phases/rawspeed-backend/evidence/gui/darktable-SELFREVIEW.md`：

- 结论头：`PASS / N error + N minor`
- 逐项：统计复核表、口径判定、3 帧抽检结果（文件名 + 相关系数）、归因自洽判定、隐私/边界判定
- 每个 error 给 `file:line` 或 CSV 行号与复算值

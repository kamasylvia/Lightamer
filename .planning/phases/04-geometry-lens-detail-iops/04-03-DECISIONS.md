# 04-03 DECISIONS — rotate/perspective（ashift）执行决策记录

> Plan 未覆盖点的裁决记录（任务书指令：写入本文件并继续，不停下等确认）。
> T0 三条按 plan 决策记录走（见 DISCUSSION-LOG 04-03-T0 节）。

## 04-03-T0 模块身份 + 透视参数面（plan 推荐采纳）

- **D-04-03-T0-1 单一 `ashift` op**：一个实例、面板两个区块（旋转/透视），内嵌裁切位默认全幅；v50 槽位 15.0（`iop_order.c:319` `{15.0} "ashift"` 实测确认；rotate 在 crop 24.5 之前 ✓，flip 16.0 之后 ✓）。
- **D-04-03-T0-2 透视交互 = (a) 参数面滑块 + Vision 自动检测填充**：不直接暴露 4 角手柄（defer Phase 6，liquify 顶点交互基建复用）。
- **D-04-03-T0-3 EXIF 方向分工**：90° 步进由 flip（04-02）承担（reloadDefaults 从 DecodedImage 种默认）；ashift 只管微调/透视。模块头注记。

## 实现裁决（plan 未覆盖）

- **D1 mode 锁定 GENERIC**：dt params 的 `mode/orthocorr/aspect/cropmode/lines` 不进 Params；`fLength/cropFactor` 保留为 sidecar 兼容位但 generic 下惰性（dt `commit_params:5600-5605` 同语义：generic → `f_length_kb=28/orthocorr=0/aspect=1`）。`commitParams` 按 dt `_isneutral:985-999`（eps 1e-4）判中性。
- **D2 uniforms 走 setBytes per-run**（偏离 plan T1 的"commitParams → uniforms buffer"字面）：单应依赖 bufIn 尺寸（`_homography` 中心/焦距项），commit 时无尺寸；FlipModule setBytes 前例。`piece.data = nil`。
- **D3 前向补 `dscOut` 盖章**（PixelPipe.run one-liner）：`modifyROIIn`/process 的 clip 偏移需 full buf_out（dt `piece->buf_out`）；`dscOut` 现无消费者，盖章安全。
- **D4 bilinear 边框语义**：采样中心落在输入域外 → 整像素 `(0,0,0,0)`；域内像素的 4 taps clamp-to-edge。dt 边框行为未深究（死分支风险 L020④），此处以 Swift↔Python 合成双实现互锁为准，记 intentional divergence。
- **D5 中性 + 病态（AABB <4px）→ blit 恒等**：dt 置 `piece->enabled=FALSE`；管线拥有 enablement，模块只做恒等渲染 + `AppError.logger` 记日志，不 crash。
- **D6 editing 种子带 ENABLED 中性 ashift**（exposure-0EV 式：面板有实例可驱；恒等 → 缓存零扰动）。
- **D7 帧约定**（L020 教训前置，注释钉死三处）：
  - forward walk 输出 `levelROI` 的 xy 即上游相对原点；`modifyROIOut` 保持 `x/y = input.x/y`（dt `:1148` 字面），只重算 w/h（forward AABB × 内嵌裁切 → floor）。
  - backward walk 从 forward 结果出发，`modifyROIIn` 收到的 `roi` 已是输出帧坐标；inverse 角点 + clip 偏移后取 AABB（输出帧 → 输入帧变换），+2px 边距 → clamp bufIn。不再加 `buf_in` 原点（crop 双重偏移同类错的 rotate 版）。
  - `process` 按 `(roiOut.x+i+cx)/scale → Hinv → *scale − roiIn.xy` re-base（部分下游请求逐边界协议；全窗口时退化为 dt `:3542-3558` 字面）。
- **D8 Vision 访问级**：`VisionDetect` internal + public facade `AshiftAutoDetect`（plan Artifacts 注记）；面板经 `PipeCoordinator.detectionSourceImage()`（新增只读 additive）取 `decoded.ciImage`，零管线读回。
- **D9 符号约定以探针为准**：horizon 角 → rotation 修正量的符号、rectangle 角点 y-flip 顺序，全部由 VisionDetectTests 真跑钉死（失败即改映射不改测试期望的反向操作禁止——期望来自合成真值，映射来自代码）。

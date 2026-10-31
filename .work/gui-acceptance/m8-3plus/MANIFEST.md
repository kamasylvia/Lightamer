# M8-3+ 走查 MANIFEST（配方——执行归 orchestrator 批准轮）

> 探针协议：真机实况（computer-use 或真机截屏）；GUI pointer 不可达时走进程内
> 真链探针先例（M2-7-3）。每项：配方 + 预期 + 证据位。

## 1. disclosed amber 行真机可达（T2）

- 配方：开 C200 实拍（或样张库约拍类）→ Film 面板启用 → 选 film=C200、
  paper=crystal → 读 readout 行下 amber 行。
- 预期：amber 文案「中性未收敛——受限于调节墙」可见；切 portra×endura 后行消失。
- 证据：`m83p-01-disclosed.png` + `m83p-02-safe-norow.png`。

## 2. 反转收敛（T2/E2）

- 配方：film=velvia → paper picker 展开 → 选 2383 → 读 Print Mode 节 → 切
  Direct positive → 读 caption。
- 预期：picker 仅 incumbent + 2383/2393；Direct 下 B 钳制时 manual-CC caption
  可见；存量 RA-4 档不跳纸。
- 证据：`m83p-03-converge.png` + `m83p-04-mode.png`。

## 3. 三算子 off 默认节（T4/T5）

- 配方：新档启用 → 读 grain/halation/diffusion 三节。
- 预期：三节全 Off；toggle grain → amount 读数 ≈ 桥值；family picker 四 id
  verbatim。
- 证据：`m83p-05-off.png` + `m83p-06-ontoggle.png`。

## 4. portra 真照片对照腿（m-3③ 关闭）

- 配方：portra 实拍开 film（默认对）→ 导出 SDR → 与 Alcedo 同档出片并排。
- 预期：观感同族（色偏/密度在 ±5% 目视带内）；记录差异项。
- 证据：`m83p-07-portra-compare.png` + 差异清单行。

## 5. C200 回退档观感（坏态修复前后对照）

- 配方：C200×crystal 开 film → 读 readout（Y=250 钉墙 + amber）→ 观察暗部/
  蓝通道 posterize 台阶 vs 修前截屏（R9 证据）。
- 预期：台阶减轻/消失；灰平衡目视中性。
- 证据：`m83p-08-c200-after.png` + 修前对照引用。

## 6. 三戳 + m-6①（T6 leg-2）

- 配方：冷 pair 启用 film → 记 S1（commit）/S2（build 完成）/S3（.lra mtime）；
  窗外 undo 旋转 → 读视口恢复。
- 预期：S3 ≈ S1+2s（HOLD）；undo 即时恢复（m-6① 关闭）。
- 证据：三戳值行 + `m83p-09-undo.png`。

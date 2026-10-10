# M4-2-01 ACCEPTANCE — 双重验收记录（待 orchestrator 编排）

> 状态：**PENDING**（执行方 = worker 自证完毕；zcode 独立验收与 omp 串行二次
> 验收均未跑——按 config `dual_acceptance = true` 的流程由 orchestrator 编排）。

## 交接面

- 执行方自证正本 = `M4-2-01-SUMMARY.md`（任务序/实测带/红线自证/T5 FAIL 判定
  数据）+ `M4-2-01-DECISIONS.md`（§1 六项执行裁定 / §2 实测带 / §3 偏差注记 /
  §4 T5 判定与 T6 处置）。
- 真图门证据 = evidence 仓 `m4-2-01/probe/`（`156b7cf`；双跑逐行一致）。
- 定向轮数字：Layers **420/3/0** + App **708/0/0**（基线 3335 + 30 = 3365 预期，
  --all 对账轮建议随验收波执行）。
- 验收重点提示：①T5 FAIL 判定的证据链（probe.log 双跑 + DIAG 两行）②滞回 raw
  门修复对 MaskRevisionTests 产线腿的影响面 ③junction 整像素裁定 + 共享修复的
  负测覆盖（RidgeExtractTests cross/bridge/T-fork）④红线自证复核（kernel/
  overlay/PipeCache/snap 族零 diff）。
- FAIL 回注路径：验收发现 → 修复批 → 复验（本文件追加记录）。

# M6-1-01 ACCEPTANCE — 双重验收记录（config `dual_acceptance = true`）

> 编排纪律：**zcode 独立验收 PASS → 串行 omp 二次验收（严禁并发——computer-use
> 单实例）**；两路结论落本文件（PASS/FAIL + 证据指针）；FAIL 回注修复批后重走。
> 本批（worker 执行 2026-10-13）交付面与证据正本：
> - 任务序/commit 表/定向轮对表 = `M6-1-01-SUMMARY.md`
> - 执行偏差与机检清单 = `M6-1-01-DECISIONS.md`
> - 走查配方（Manual-Only 行）= `.work/gui-acceptance/m6-1/MANIFEST.md`
> - 五门 golden 证据 = SUMMARY「Golden 五门」节（测试文件在库可复跑）

## 第一路：zcode 独立验收

- status: **pending**（待 orchestrator 派遣；验收范围 = AC1..AC8 逐条 + 抽查
  实现与 AC 一致性 + 定向 bundle 复跑）
- 结论：
- 证据：

## 第二路：omp 二次验收（串行，第一路 PASS 后）

- status: **pending**
- 结论：
- 证据：

## 处置记录

（FAIL 回注修复批的 commit 与重走记录逐行追加于此）

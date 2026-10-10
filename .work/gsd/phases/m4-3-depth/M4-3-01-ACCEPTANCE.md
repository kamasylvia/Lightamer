# M4-3-01 ACCEPTANCE（骨架——双重验收编排，config `dual_acceptance = true`）

> 本文件由执行批只建骨架；两路验收结论由验收环节落账（PASS/FAIL + 证据）。
> **硬约束：两次验收严禁并发（computer-use 单实例会打架），严格串行。**

## 验收输入

- plan = `M4-3-01-PLAN.md`（AC 13 条总表）
- 执行 = `M4-3-01-SUMMARY.md` + `M4-3-01-DECISIONS.md`（§1..§9，含 m1..m7 回勾）
- checker = `M4-3-CHECKER.md`（PASS / 0E+7M+6obs，处方执行批已采纳）
- 批次 = `d2e234a..b615636` 七提交 + 收口批

## 第一路：zcode subagent 独立验收

- 结论：**（待落账）**
- 证据：**（待落账）**
- 日期：**（待落账）**

## 第二路：omp 二次验收（串行，第一路 PASS 后）

- 结论：**（待落账）**
- 证据（computer-use 走查配方 = `.work/gui-acceptance/m4-3/MANIFEST.md`）：
  **（待落账）**
- 日期：**（待落账）**

## FAIL 回注

（两路任一 FAIL → 修复批后重走；回注条目在此登记。）

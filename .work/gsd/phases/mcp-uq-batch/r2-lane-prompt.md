# MCP-UQ 批域内终审任务书（omp subagent review lane R2）

你是 MCP-UQ 增量批的终审 agent。工作目录
/Volumes/UNITEK/Documents/Development/Lightamer。只读产物。R1 报告
`.work/gsd/phases/mcp-uq-batch/r1-report.md`（FAIL/2+14）可读——它是审查
对象的一部分（对照输入），不是中间态。lane prompt/monitor/omp-evidence
禁读。全程中文，stdout 最后一条消息一次性完整输出结论。

## 背景

R1 在 diff 仍含 E-1（Project.swift 误删 Control 登记行）时审查。
执行 lane 此后修复了 R1 全部 2 error + 12 minor（M-4 接受注记、
M-8/M-13 挂账，见 DECISIONS R1 closeout 节），ΔN 17→18
（M-5 新法 `testEveryCatalogedOpResolvesEncodedDefaults`）。

## 审查对象

1. **R1 修复验证**：E-1（`git diff HEAD -- Project.swift` 纯插入？）、
   E-2（15 onboarding 键 en 值在位？）、M-1/M-2/M-3/M-5/M-6/M-7/M-9/
   M-10/M-11/M-12/M-14 是否如 DECISIONS closeout 所称落地。
2. **增量 diff 审查**：R1 后新增改动（en 值、marker 单源、token 扩、
   有界等、NOTICE §V、三文件头、M-5 法、SKILL 枚举）有无新问题。
3. **反自取消探针**：SUMMARY/DECISIONS 终态 vs 实际 diff 逐项核对；
   M-4 接受理由是否成立（语义零触证据）；M-8/M-13 挂账是否合理。
4. **残留扫描**：`grep 33/24/all33/Union32/editing (9|10)` 零残留复核；
   封存面 17 件零 diff 复核。

## 机器纪律（强制）

- 只读审查：**不跑构建、不跑全套、不派子进程测试**。
- 不杀任何进程，不碰 DerivedData，不写任何文件。

## 输出格式

结论头 `PASS / N error + N minor`（相对 R1 修复后状态的新 finding；
R1 已修项逐项 `FIXED` 确认），后接逐 finding（文件:行 + 根因 +
证据 + 修复建议）。

# LUMEN-A SUMMARY — 分析地基（LU2+LU1）执行摘要

> 执行批 = LUMEN-A-PLAN.md（fixer `a0e43b44` + checker `75678937` 后 HEAD）。
> 执行窗 = 2026-10-23。逐任务 commit-per-task，全英文 Conventional Commits
> （`lumena` 前缀），零 issue ref（内部规划口径；产品面源码批——本批交付为
> Core/Library 域 additive + App Library 面，按 CONVENTIONS 产品面规则本应
> 关联 issue，但仓内 issues 未启用（先前批同口径），沿用零 ref 并在此备案）。

## 逐任务记账

| 任务 | commit | 内容 | 测试 |
|---|---|---|---|
| T1 | `2b841916` | schema v6 七列 additive 迁移（DDL + imagesColumns 双登记 + 幂等探针 ALTER）+ 版本字面量族随代际走（5→6 / future 6→7 / 快照代 4-6/3-6 等——机械后果，DECISIONS §1） | LibrarySchemaV6Tests +3 |
| T2 | `34e7d0c0` | EXIF serial + SubSecTime 读腿（Exif dict 主 + TIFF 兜底；fillMetadata 写腿 = 实际消费点） | ExifSerialSubsecTests +3 |
| T3 | `e87d9edc` | SharpnessAnalyzer + Signature16（review B-1 实式）+ NOTICE Lumen RAW 条目 + NumPy 参考对拍 golden | CullingAnalysisGoldenTests +4 |
| T4 | `6597f51d` | EyeClosureAnalyzer（Vision landmarks 眼睑比 + 注入工厂 + 阈值注入）+ 标定集机制（evidence 模板） | EyeClosureAnalyzerTests +3 |
| T5 | `4e1104da` | LibraryAnalysisService actor（三防 + 防风暴 + 懒回填）+ LibraryStore.setAnalysis/notify 缝 + App 装配（review M-2） | ServiceTests +4 / WiringTests +4 |
| T6 | `db41fd0d` | BurstAnnotator 查询期注记（五点直译 + L013 组 id + m-5 三钉）+ NumPy 参考 golden | BurstAnnotatorTests +4 |
| T7 | `b0da9c24` | 智能相册四案（16→20）+ FilterSQL 直比/typed 臂 + 网格徽章 + 转栈一键 + Settings 行 + xcstrings 11 键尾插 | FilterCullingFieldsTests +5 |
| T8 | （本 commit） | Project.swift 八文件入册（七 LIB + 一 APP）+ BUNDLE-MAP 八行 + tuist generate 末位 + docs | — |

## ΔN 终账（T8 末轮机检值）

- 计划带 **+12..15**；实账 **+31**（Library 747→774 = +27，App 970→974 =
  +4；构成 3+3+4+3+8+4+5）——**越带 +16..19，申报如下**：
  - 每任务的 method 数按 SC 子句逐条落位（每条 SC 一测），T3/T4/T6 的
    golden + 边界 + 分支面天然多方法；
  - T5 越带主因 = review M-2 追加的 App 装配面（WiringTests +4——enabled
    门/开关状态机/probe 组合/registry 适配各一）；
  - T7 +5 = 四案集成 + 两 typed 臂 + 白名单回归 + 徽章表驱动 + 转栈断言
    （m-6/m-11 两评审项各占一）；
  - T8 末轮对账（真实机值）= **Library 774/4/0、App 974/6/0** 全绿零回归
    （t8-library.log / t8-app.log；App +4 = 装配面 WiringTests）。
- 全套 `--all` 不在本批（orchestrator 批准制，Plan C 收口轮统一对账）。

## 验收判定（机检汇总）

- 构建：全部任务 TEST BUILD SUCCEEDED（tuist generate 后全链绿）。
- 定向：`--bundle Library` 772/4/0、`--bundle App` 970/6/0（T7 后回归）；
  T8 终轮见 tail 记录（t8-library.log / t8-app.log）。
- zh-audit：`--check` PASS（1697 source / 2016 catalog）+ `--self-test`
  PASS（留档 = 本 SUMMARY 时点输出，脚本可复跑）。
- 红线核：LightamerSidecar / HistoryStack / CullingToolset /
  StackClustering / McpServerController 全程零 diff（git 逐 commit 可核）；
  MIT 归属三文件头 + NOTICE 条目 Q；xcstrings 尾块纯插入（历史键 byte 相等
  断言在插入脚本内）；L013 组 id（decimal string 断言）；L041（tuist
  generate 恒批末位——批内按 L041 对策「新文件落盘后无条件重跑」执行过多次
  幂等 generate，正式登记 generate 在 T8 末位一次）。
- golden 三面：清晰度（culling_golden.json，锚 55.6/27.4 带内）、连拍
  （burst_golden.json，参考对拍）、闭眼（CI 钉数学面；绝对阈值 = 标定集
  机制待实拍，D-LU-4 副路径）。

## 证据指针

- 构建/测试日志：`.work/gsd/phases/lumen-culling/evidence/lumena/`
  （t1..t8 系列；.work evidence 目录按仓策略 gitignored，正本在工作树）。
- golden 脚本：`Scripts/gen-culling-golden.py`（含 cv2 auto-ksize 探针
  记录）、`Scripts/gen-burst-golden.py`（含 m-5 comparator pin）。
- 标定集机制：`.work/gsd/phases/lumen-culling/evidence/culling-analysis/
  calibration/README.md` + `CALIBRATION-TEMPLATE.md`。
- 裁定与偏差正本：同目录 `LUMEN-A-DECISIONS.md`。

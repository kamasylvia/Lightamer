# spektra-module P1 replan lane（omp）

你是 spektra-module P1 的 replanner。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。**只改 `.work/gsd/phases/spektra-module/PLAN.md`（原地重写为 v2），零产品代码、零构建、零 commit（orchestrator 代提交）。**

## 输入

1. **唯一闭合清单（最高优先）**：`.work/gsd/phases/spektra-module/SM-PLAN-REVIEW.md`（zcode 评审，FAIL / 2 blocking + 10 major + 9 minor + replan 闭合清单节）
2. 设计正本：`.work/gsd/phases/spektra-module/RESEARCH.md`
3. 旧版：`.work/gsd/phases/spektra-module/PLAN.md`（v1——评审已判不可交付，逐条对照修订）
4. 基线：HEAD `9a69d0e4`（先亲核）

## 硬性要求（评审驳回点必须逐条消解）

- **B1**：实例放置改走**调整层内**（照搬 `FilmPanelModel.addPlacement()` 先例形态）；判别谓词改读层内实例（`effectiveInstances()` 局限）；MCP `apply_params` 无层参数的约束显式处置（扩 MCP 面 or 文档化限制，二选一给判定）。
- **B2**：逐位恒等门**改 ε 带等价口径**（按评审的误差放大分析给具体带宽与归因）+「process 不 bump」理由重写。
- **M1..M10 + 9 minor**：逐条给修法；其中 M2（assembleFilmLeg 用**注入缝**暴露，禁 public 化）、M3（histogram 留 legacy 腿双轨期不动）、M6（迁移行存活保障）、M7（渲染入口清点：QuickLook/追色/缩略图全覆盖）、M8（中间面内存预算：100MP ~1.6GB vs 8192MB 门——给复用/单 pass 设计判定）是重点。
- 封存面申报按评审口径重算（M2/M3 非封存修法前提下「2 行 + 1 期望」是否仍成立）；ΔN 重估（评审估 ~75-80 减 4 退役）。
- 每任务 AC 全部机检可验；T 序 commit-per-task 可串行；env 门 `LIGHTAMER_FILM_MODULE=1` 默认 off 贯穿（含 M5 与 `testAllCatalogOpsAreDefaultFaceRegistered` 的冲突消解）。

## 产出纪律

- PLAN.md v2：chunked 写（每段 ≤8KB 追加 + 字节数自检）；文首加「v2 changelog」节逐条映射评审 finding→消解位置。
- stdout 最后一条一次性完整输出（B1/B2/M1-M10 逐条消解摘要 + ΔN + 封存面新申报）。

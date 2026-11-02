# 光谱核 module 化 P1 plan lane（omp）

你是 Lightamer 的 planner。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文，commit 英文。**本 lane 只写 PLAN.md + SUMMARY 级规划产物（.work/gsd/phases/spektra-module/ 下），零产品代码、零构建、零测试、零 commit（产物落盘即可，orchestrator 代提交）。**

## 基线

派遣时刻 HEAD（先 `git log -1 --format="%h %s"` 亲核并写进 PLAN）。M9-2 B&W 修复批应已在 HEAD 之内；若 `git status` 有 Film/ 未提交 diff = 异常，停下上报。

## 执行正本

`.work/gsd/phases/spektra-module/RESEARCH.md`（已定稿，orchestrator 审读通过）——PLAN 以 §4 设计案 + §5 迁移 + §6 风险为骨架展开任务分解。

## 用户裁决（预批准，不再呈裁）

六条 OQ 全采推荐：
- OQ-1(a) `.oneInstance` 单实例（需求出现再撤）
- OQ-2(a) 保留直方图自适应求解；**P2 挂账不立项**——本批 = P1 only
- OQ-3(a) spektraFilm 入 GradeCatalog + op 内 ACEScc 往返（4.1(a) 形态）
- OQ-4(b) sidecar 版本号不 bump、键面零新键；旧档内容判定（`filmRecord` 键在场 && 无 spektraFilm 实例 = legacy 腿）
- OQ-5(a) 节点图 Film 卡 P1 退役
- OQ-6(a) 串行——以派遣时 HEAD 为基线（含 M9-2 全部交付）

## PLAN 必须覆盖（P1 范围 = module 化不改核，视觉逐位恒等）

1. V50Order 新增 `("spektraFilm", 46.7)`（verbatim 行）+ GradeCatalog 注册（owner .grade）+ ACEScc 往返臂设计（入口 log 化/出口 linear 化的 kernel 或纯函数选型，RESEARCH §4.1(a)）。
2. FilmMethodBox 转正为可注册 module：`.oneInstance` flags、iopOrder 消费、add-face（GradeCatalog 枚举 + NodeOwnershipCatalog）、enable/disable 语义。
3. 参数载体迁移：FilmRecord(document 级 14 字段) → module instance params（`ModuleInstance.paramsData` 通道）；document carrier/sidecar `filmRecord` 键转 legacy 只读；history 键族处置（`history_film_*` 保留 or 新键——给判定）。
4. 双轨读迁移：legacy 档走旧回放腿逐位恒等；新档走 module 链；面板「Convert to Film module」迁移行（`ProcessMigrationRow` 泛化复用）；env 门 `LIGHTAMER_FILM_MODULE=1` 默认 off。
5. 求解链不动：FilmSolveCache 全帧预走键控原样；`pixelUm` 仍全帧锚（P2 挂账）；`tileHalo` 返 0、不设 `allowTiling`。
6. 下游面：DRT 尾段交接（film 从尾段共享序退出后的 sub-run 剩余序）、导出 `filmTail` TaskLocal 退役或保留判定、缩略图恒 legacy 政策、Film 面板数据源换锚、节点 Film 卡退役、MCP/NodeGraphCommand 面。
7. 测试策略：**两宿主逐位相等桥接测试**（legacy 回放腿 vs module 链同一输入逐位比对——golden 冻结面）；双臂 golden kernel 字节零改红线；既有 Film/Spectral 测试域归置（BUNDLE-MAP 同批）。
8. 封存面申报：PixelPipe / V50Order / GradeCatalog(NodeOwnershipCatalog) / ExportQueueContract 预计触碰——逐件申报例外形态（对齐 M8-3+ 先例：逐 hunk 申报）；schema 版本号零触碰（OQ-4(b)）。

## 产出纪律

- `PLAN.md` chunked 写（每段 ≤8KB 追加 + 字节数自检，防截断——M8-3+/M9-3 先例）；T1..Tn 序 + 每任务 AC（机检可验）+ ΔN 预估 + 封存面申报表。
- stdout 最后一条消息一次性完整输出摘要（omp 输出兜底惯例）。

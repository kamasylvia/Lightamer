# spektra-module 决策账本

## D-SM-0（2026-11-03 用户裁决）：全量造 module 生命线，不降档

用户原话「做」，确认对 replan v3 任务书的定性：**P1 = 给 film 造一整套 module 生命线**，不是「搬参数到位」。

五条生命线全要，禁拆 P1a/P1b：

1. **材料解析缝**（B1）：FilmMaterialStore 从 App 层下沉或注入到 IOP module 可达面——不给则 module 恒 blitIdentity、胶片整段消失。
2. **requestTags 供给**（B2）：三处 TaskLocal 消费（FilmPrintBake 555/566/576/605、FilmTailPolicy 851-866/906）在 module 路必须有供给点。
3. **merge-down 语义**（B4）：`.mergedIntoBase` × recordChange reject = 实例蒸发（数据丢失），必须有显式处置。
4. **appex 注册**（M3）：QuickLook registry 仅三件，spektraFilm 恒 unknown op。
5. **scratch 分配**（M8）：SpectralScratchAllocator Leg 三值与 module 争槽 + RSS 8192MB 门。

**理由**：分档会造出「能建实例但渲染不出胶片」的半成品态——module 存在但不产出像素，比不做更糟（用户可见的假功能）。宁可单批跨度大、多轮评审，不可交付假 module。

**推论**：
- 允许 ΔN 大幅上修（v3 交付为准，评审估 ~75-80 减 4 退役）。
- 封存面申报必然扩大（v2 复审已点名需增五行），按逐 hunk 申报制执行。
- execute 分期仍按 T 序串行（commit-per-task），但**不按功能分档交付**——P1 全量 PASS 才算闭环。

## D-SM-EXEC（2026-11-04 omp 执行批）：P1 全量落地注记

### r4 三 minor 消解

- **r4-m1**：封存结论句补记 Core Presets 非封存两小 hunk（`PresetError.layerOnlyOpPresent`
  additive case + `PresetApplier.makePayload` 防御过滤）——过滤留 Core（App 调用点过滤会漏
  MCP/batch 面；Core 过滤是第二道墙的第一形）。
- **r4-m2**：D-SM-15① 装配机制 = actor-owned once-flag（`QLAssembly.shared.ensure`，两腿首用
  调；static let 内零等待——禁令遵守）。实报见 SUMMARY。
- **r4-m3**：AC-T6'-13 补走查兜底 + Core `QuickLookFilmResources`（Bundle 形参可测形）；
  appex Env 接线由走查覆盖（本批走查移交 orchestrator，见偏差 1）。

### 生命线终态（五条全量）

1. 材料解析缝：`FilmMaterialSeam`（Core holder）+ App `attachFilmStore` 安装 + QL 独立安装。
2. requestTags 供给：`resolveLegTags` 纯函数 + per-target 兄弟腿（R-M1）+ QL TaskLocal 直装。
3. merge-down 语义：预检 toast + `mergeDown` refuse（⑯）+ 基链拒收（蒸发闭环）。
4. appex 注册：QL 全量 populate + material seam + tags（D-SM-15/16；ε 带正测）。
5. scratch 分配：自持 run-scoped 中间面（D-SM-12R）+ 计数槽 ≤1 + 8192 绝对门（探针默认 skip）。

### 实数与封存

- ΔN = 净增 **97**（101 − 4），分项见 SUMMARY（与 PLAN §0.2 逐位一致）。
- 封存终态 = 实质 3 行（V50Order/GradeCatalog/LayerStack⑯）+ 1 注释例外（PixelPipe）
  + Core Presets 两小 hunk（r4-m1）；其余 12 行零 diff（机检）。
- 环境门：process 3 / sidecar v13 / UserDefaults 零新键 / env 默认 off 全程；G4 透明越门登记。

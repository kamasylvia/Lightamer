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

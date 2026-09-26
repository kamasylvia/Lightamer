# Plan 06-05 Summary — 图层 UI 与前半签核（LayersPanelView + 层路由 + 蒙版工具 + history 全粒度 + E2E + 性能记账）

**执行**：2026-09-24 夜间 ZCode subagent（GSD executor；逐字执行 06-05-PLAN：read_first → T1..T6 → 验收标准逐条自验）
**终轮全 suite**：**768 / 3 skip / 0 fail**（基线 747 → +21；`Scripts/test-direct.sh` 直启零弹窗；touch Tests + `build-for-testing` 重编后复跑）
**提交**：`8c9d464`（C0 遗留修复）→ T1-T4 接线（feat(ui)）→ T5（perf(testing)）→ T6（E2E + GUI 修复 + 文档收尾，本提交批）。未 push（纪律：本地 commit 即完成态）。

## 任务完成表

| 任务 | 内容 | commit | 验证数字 / 证据 |
|---|---|---|---|
| C0 | 前班遗留消化：① 06-06 遗留① mask 缓存键折几何态（mapper stableHash）② 06-04 note-1 raster-only 降级腿折层 opacity ③ 05-07 note-2 bayesshrink 单源钉 ④ HistoryHash 层锚补折 mask | `8c9d464` | Plan0605LeftoverTests 5/0：几何变更 → mask 平面 miss + 重光栅化（plane 字节 diff > 1/4 px，防空转）；raster-only 降级平面 mean == opacity（两条降级腿）；drift 锚 mask 翻转敏感 + 确定性；bayesshrink 字面量 0.5229 ≠ sqrt(70)/16 防回归钉 |
| T1 | LayersPanelView：自下而上层列表（眼/inline rename/blend Picker 17 模式 zh-en/opacity D-H1 滑块/mask chip）+ 操作条（添加/拷贝/合并向下/删除 + 显示蒙版）+ 拖拽重排（1 commit） | feat(ui) 批 | LayerUIWiringTests：添加/拷贝/合并/重排/删除各恰 1 结构项 + undo 还原（顺序/恒等/参数）；面板四件套全量（`layer.row.<uuid>` 稳定 id + 58 键 catalog + ≤280pt + D-H1） |
| T2 | 层选中 Inspector 路由：InspectorEditSession 注入 layerScope；几何模块层内隐藏（13/15/16/17 ∪ crop/enlargecanvas/liquify，D-06-05-T1-3）；「添加模块」fresh-identity 克隆 | 同批 | 层 K 参数隔离（base hash 逐字节不变）+ 24 面板 layerScope 分发全过 + 全量回归（24 面板零改动实证） |
| T3 | LayerEditingState 状态机（视口手势互斥归口）+ MaskToolbarView（五工具浮视口下缘 + 笔刷参数环 + 渐变 linear/sigmoidal）+ MaskOverlayHost（brush/eraser/gradient/ellipse/path，press-即装真实 UUID + 笔画结束恰 1 commit） | 同批 | 状态机互斥单元测试（三路由穷举 + 无选中禁用 + 悬空自愈）；工具 id 稳定全量；GUI 轮 brush 描画/armed 高亮/禁用态 diff=0 实证 |
| T4 | history 全粒度：结构项（stackSnapshot 型，`__layerStack__` scope 标记）+ layerScope 参数项 + undo/redo/jump 双轨重建（结构快照 ⊕ in-scope 项 newest-wins）+ coordinator 层渲染路由（processComposite 分支）+ 侧车层记录持久化/恢复 | 同批 | 每类恰 1 commit 断言（含 opacity 拖动/mask 笔画）+ undo 渲染还原 + E2E 侧车 round-trip（drift 自查通过） |
| T5 | 性能记账 + FULL 政策 benchmark | perf(testing) | **10 层稳态拖动 Debug median 15.6-16.4ms < 16.6ms（60fps 达标）**；FULL benchmark：fit cold 16-17ms / window cold 4-5ms / cacheAll 小图 0ms 但 100MP 不可持续 → **维持 fullColdLayer**（D-06-05-T5-1）；窗口化账本 cold 166.7MB vs cacheAll 280MB；数字落 `.work/06/perf.md` |
| T6 | E2E round-trip + GUI 验收轮 + 前半签核 | 本批 | `LayerE2ERoundTripTests`：真实 DNG → 3 层异 blend/opacity + brush/gradient 蒙版 + 层内参数 + 重排 → undo×2 → 侧车 → 全新 coordinator restore → UUID 恒等 + 参数逐字节 + **渲染逐字节恒等**；GUI 轮 8 张截图 + 量化落 FINDINGS（含当场修复 GUI-14/15/16）；前半签核落 `06-DISCUSSION-LOG.md`（SC#1/2/3/5 前半全 ✅，缺口台账零静默） |

## 全套测试

- 终轮：**768 / 3 skip / 0 fail**（240s；基线 747 → +21 = C0 5 + LayerUIWiring 12 + LayerDragPerf 3 + E2E 1）
- 密码弹窗：无（直启路径全程零弹窗）
- 全量回归覆盖 Inspector 路由改动（PanelWiringTests 全量在内）

## 验收标准对照

- [x] LayersPanelView 全件 + 面板四件套 + PanelWiring +≥6（每类操作恰 1 commit + 重排可退）——LayerUIWiringTests 12 用例
- [x] 层选 Inspector 路由：24 既有面板零改动回归绿 + 层间参数不串 + 层内几何只读/隐藏
- [x] 蒙版绘制五工具 + 手势互斥状态机 + Manual-Only 登记（FINDINGS）+ 笔画→渲染增量链路 UX 兑现（描画实时 tint + chip）
- [x] history 全粒度：六类操作逐类 1 commit（merge 落 base 的 N+1 形态落 DECISIONS D-06-05-T1-2）+ undo/redo 渲染还原断言
- [x] 拖动门：10 层稳态 median 实测 15.6-16.4ms（60fps 达标，无放宽）+ perf.md composite 段落账
- [x] FULL 政策 benchmark 结论落 DECISIONS（维持 fullColdLayer，数据驱动）
- [x] E2E round-trip 渲染逐字节恒等 + GUI 验收轮 FINDINGS 登记 + 前半签核 DISCUSSION-LOG（缺口零静默）
- [x] 全 suite 绿（0 fail）；每任务独立提交；SUMMARY + DECISIONS 落盘

## 决策与勘误（正本 06-05-DECISIONS.md，10 条）

C0 mapper 哈希有界采样（D-C0-1）；drift 锚 mask 折叠的格式窗口期收紧（D-C0-2）；chip 矢量快照策略（D-T1-1）；merge 落 base N+1 形态（D-T1-2）；层内几何豁免面扩大至 UI 三件（D-T1-3，回答 06-01 遗留 D-06-01-T4-1）；layerScope 注入式路由（D-T2-1）；手势互斥单点状态机（D-T3-1）；press-即装 form + dirty 门（D-T3-2）；FULL 政策维持冷层（D-T5-1）；侧车双轨读写契约（D-T6-1）。

## 遗留 / 风险（移交 6-7+）

1. **GUI-17（低）**：显示蒙版 toggle 偶发不可见（AX + 渲染同缺，复现一次）——overlay 请求路径已由 row-tap 驱动验证，人工复验挂 FINDINGS。
2. **cmd-drag 调 brush size** viewport 手势未实现（参数环面板等效能力已交付）——6-7 前补。
3. gradient 两端手柄 / ellipse / path 手柄的 viewport 手感：数据腿 + kernel 已由 06-03/04 单测钉住，细粒度待人工（FINDINGS Manual-Only）。
4. 100MP 蒙版笔画延迟未实测（本轮 24MP 无卡顿）——性能轮。
5. 驱动层几何拒绝集仍为 13/15/16/17（UI 已按扩大集隐藏）——数据面扩集（+crop/enlargecanvas/liquify）随 6-7 签核收口。
6. merge 落 base = N+1 commit（dt 形态）——如需严格 1 commit 走 additive 字段迁移（D-T1-2）。
7. 既有 GoldenColor flake（L018 类 CI 腿，0-2 浮动）沿用挂账，本轮终轮未复现。

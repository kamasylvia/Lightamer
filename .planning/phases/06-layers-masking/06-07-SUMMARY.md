# Plan 06-07 — retouch（修复层）+ Phase 6 终签核 — SUMMARY

> 执行：夜间 ZCode subagent worker（2026-09-24）。plan = 06-07（逐字执行 read_first
> → T1..T6 → 验收标准自验）。基线 768/3skip/0fail → **终轮 788/3skip/0fail**（+20）。

## 交付总览

| Task | 内容 | 提交 | 验证 |
|---|---|---|---|
| T1 | retouch 层 kind + stroke 模型 + sidecar 拼写冻结 | `feat(layers)`（RetouchLayer/RetouchStroke/LayerKind.retouch/sidecar strokes optional + kind 分派/snapshot kind-aware/duplicate kind-aware/mergeDown 拒绝 retouch） | RetouchLayerCoreTests 5 + RetouchSidecarTests 4 + 回归（Phase6Sidecar 7/LayerCore 11） |
| T2 | clone/blur/fill GPU 腿 + 源区∪目标 AABB 扩窗 + 驱动器 retouch 腿 + stroke 腿缓存 | `feat(retouch)`（RetouchKernels.metal 4 kernel + RGBA Deriche 3 kernel、RetouchEngine、LayerCompositeDriver kind 分派 + expandedHint + retouchPosition） | RetouchParityTests：clone ≤1e-5、fill 常数域 ≤1e-5（含层 opacity 折叠）、blur 剖面（边缘塌缩+线性场保持 ≤2e-3）、**跨窗扩窗无源区黑边 ≤1e-5**、空层恒等逐字节、缓存记账 |
| T3 | heal 迭代核 + 降级判定 | 同 `feat(retouch)` 提交 | heal_laplace_step（红黑 SOR 半扫/dispatch）+ subtract/add + 批量误差读回；**vs 独立 float64 参考 <1e-3**；**基准 median ~10-12ms << 100ms → heal 留 6-7，不拆 6.5b**（D-06-07-T3-1） |
| T4 | RetouchPanelView + RetouchOverlayHost + 路由 + 面板四件套 | `feat(ui)`（Panel/OverlayHost/LayerEditingState retouch 路由/EditorState 三 mutation/LayersPanel retouch 行 + 笔画数 chip/InspectorView 路由/**GUI-18 zh-Hans catalog 修复**） | LayerUIWiringTests 14/14（含 retouch 路由互斥 + stroke 恰 1 commit/⌘Z 还原）；GUI 真机走查（真 RAW：加层/画 stroke/⌘Z chip 1→0，FINDINGS 06-07 节 4 截图） |
| T5 | golden 收口 + 全量回归 + 本 SUMMARY | 本提交 | touch 测试文件 + build-for-testing 重编 + 终轮全套 **788/3skip/0fail** |
| T6 | Phase 6 终签核 | 本提交 | SC#1-5 证据落 DISCUSSION-LOG + 06-VALIDATION（status: validated + nyquist_compliant: true）+ REQUIREMENTS 14 reqs 翻账 + manifest Phase 6 总账节 + PERF-2 记账 + Phase 7 移交清单 |

## 关键数字

- **heal parity**：GPU vs 独立 float64 红黑 SOR 参考 <1e-3（24×18 patch，掩码内
  compared>50；Dirichlet 外区逐值不动）。
- **heal 基准**：160×120 典型 patch median **9.99–11.63ms**（预算 100ms；门定 25ms）
  → **不拆 6.5b**（D-06-07-T3-1）。
- **clone 解析断言**：mask 内逐值 == 源平移 ≤1e-5；外部逐字节不动。
- **跨窗扩窗**：hint 32px → 57px 窗；源 patch 出窗内容完整（≤1e-5，非黑）。
- **fill 常数域**：mask 内 == 填充色（层 opacity 0.5 折叠闭式 ≤1e-5）。
- **空 retouch 层**：合成输出与无层栈逐字节恒等（轨 B 插链零增量）。
- **heal composite smoke**：真 RAW 合成路径修改掩码内区、外部逐字节不动、无 NaN。
- **全 suite**：788/3skip/0fail（基线 768 → +20）。

## 决策（详见 06-07-DECISIONS.md）

D-06-07-T1-1（kind 定名 retouch，raster 不设）、T1-2（stroke 拼写冻结复用 MaskForm）、
T2-1（驱动器 retouch 腿非子链）、T2-2（hint 预扩窗 + walk clamp）、T2-3（patch 裁剪
O(patch) 拒全平面模糊）、T3-1（**heal 留 6-7 不拆 6.5b**）、T3-2（heal 容差档 1e-3）、
T4-1（路由第 3 优先级 + 源拾取 toggle）、T5-1（stroke 腿缓存键）。

## 遗留/移交（零静默）

- **GUI-18（本轮发现+当场修复）**：zh-Hans catalog 标签破坏运行时回退 → 全裸键；
  修复 + 592/592 键验证 + LESSONS L025。
- **Manual-Only 追加 3 行**（FINDINGS 06-07 节）：source 拾取手感、stroke 羽化视觉、
  heal 效果人像目检（数据腿均已 parity 钉住）。
- **minor**：retouch 路由激活时蒙版工具条仍显示（视觉冗余，UI 打磨轮）。
- **v1 圈定**：stroke 视口绘制仅圆形（path lasso 数据腿就绪、手势未接）；blur 仅
  gaussian（bilateral 后续）；fill 仅纯色（erase 后续）；retouch 层不叠 parametric
  mask（NO_MASKS，D-06-CONTEXT-4）。
- Phase 7 移交清单见 DISCUSSION-LOG 终节（AI mask 消费端接口/层栈 API 面/mask 版本化）。

## 验收标准对照（plan Acceptance 8 条全过）

1. retouch 层 kind + stroke 模型 ✅（D-06-07-T1-1/T1-2 + round-trip 冻结拼写）
2. clone/blur/fill golden + 跨窗扩窗内容级断言 ✅（RetouchParityTests）
3. heal 基准判定落 DECISIONS ✅（交付向：median ~10ms，parity 达标——非降级路径）
4. retouch 交互 + 面板 ✅（四件套 + PanelWiring + Manual-Only + FINDINGS）
5. SC#1-5 证据指针落 DISCUSSION-LOG ✅（缺口零遗留，注记见 VALIDATION）
6. 06-VALIDATION ✅（status: validated + nyquist_compliant: true + REQUIREMENTS 翻账
   + manifest 总账）
7. PERF-2 记账 + PERF-5 联动 + Phase 7 移交清单 ✅（perf.md + DISCUSSION-LOG）
8. 终轮全 suite 0 fail ✅（788/3skip/0fail；无 /tmp 过程产物残留入工作区；app quit 干净）

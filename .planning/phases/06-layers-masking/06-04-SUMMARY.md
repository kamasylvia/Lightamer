# Plan 06-04 Summary — parametric/raster/combine mask（蒙版体系收口）

**执行**：2026-09-24 夜间 ZCode subagent（逐字执行 06-04-PLAN：read_first → T1..T6 → 验收标准逐条自验）
**终轮全 suite**：**723 / 3skip / 0 fail**（基线 698 → 723，+25；`Scripts/test-direct.sh` 直启零弹窗）
**提交**：6 个（T1..T5 + T6 收尾），Conventional Commits，逐任务独立；未 push（纪律）。

## 交付

### T1 parametric mask kernel（luma + JzCzhz 单 kernel——D-06-CONTEXT-3）
- `ParametricMask.swift`：记录模型（dt blend.h slot 编号 + 4 点曲线 + per-channel invert/boost + 后处理参数 + invert）；`packedParameters()` = dt `_blendif_process_parameters`（blend.c:167-216）逐式移植（exp2 boost、0.001 斜率地板、双开端 ±FLT_MAX、非活动槽满量程）。
- `ParametricMaskKernels.metal`：`mask_blendif` = `blendop_mask_rgb_jzczhz`（blendop.cl:1096-1131 + blendif_factor_rgb_jzczhz :329-408）直译；Jz 常量 SAME-SOURCE 复制（parity 钉住漂移）。
- `ParametricReference`（BlendOpReference 扩展）：float64 参考先行（6-2 三方门模式）。
- **门**：6 case（luma/Jz/Cz/hz × in/out）× 6 fixture；平腿/luma <1e-5 严门，jzczhz ramp 5e-4（D-06-04-T1-3 实测校准）；**平场二元门精确**；参数打包逐式钉。
- **战果**：平场门抓出 kernel 与参考**同源反转 bug**（dt 三元方向写反，双边修复——D-06-04-T1-2；两份镜像同错唯有平场/常数门可戳破，教训已记）。

### T2 mask 后处理链（blur / feather / contrast+brightness）
- `MaskPostProcessKernels.metal`：单通道 Deriche（col/row/store；L018 双 buffer 纪律；输入逐采样 [0,1] clamp = dt blend.c:708-710）。
- `MaskCombiner.postProcess`：**dt 组装序钉死** blur → feather → tone curve（blend.c:305-355 after-blur guide 默认），门控逐条（radius>0.1；|contrast|/|brightness|≥0.01 且 opacity>1e-4）。
- `mask_tone_curve` = blendop.cl:1309-1449 逐式（e=exp(3·contrast) 宿主折算）。
- **门**：blur vs float64 递归 <1e-6（σ 1.5/4/12）；tone curve <1e-6（brightness 正/负支）；Core 系数镜像 == IOP GaussianBlur（防漂移钉）；**序 pin + 非空转探针**（反序 blur/feather 真不同 >1e-4，pin 非空转）。

### T3 combine 五式 kernel + MaskGroup 语义
- `MaskCombineKernels.metal`（Core）：`mask_combine_pair` = group.c:487-630 五式逐行（每式含 inverted 支路，masks.h:52-68 位序）；ping-pong read/read/write（L018 非原地累积）；`mask_invert`/`mask_fill`/`mask_resample` 辅助。
- `MaskCombiner.reduce`：有序 ping-pong reduce；首项安装归一化（D-06-04-T3-1）；>4 抛错（D-06-04-T3-2）。
- `MaskGroupItem.child`（additive optional）：组内组递归；`drawnGroupPlane` per-item op/inverted/opacity（dt `_group_get_mask_roi` 口径，缺 form 跳过）；`DrawnMaskRasterizer.singleFormPlane` 供组合输入腿。
- **门**：5 式 × 正/反 <1e-6（零+正混合 dest 压 both_positive 支路）；两圆并/交/差/排/和**解析面积 golden**（闭式圆交 + 周长离散界，数值级）；reduce 序敏感（A−B ≠ B−A）；上界拒绝；(A∪B)−C 嵌套面积门。

### T4 raster mask：烘焙 + 旁挂 PNG + hash 校验
- `RasterMaskRef`（冻结拼写）：`{fileName, maskHash: UInt64-decimal-String, invert}`；hash = StableHash(PNG 文件字节)。
- `RasterMaskStore`：16-bit 灰度 PNG（ImageIO，gray16 双侧 little）bake/load/verify；烘焙分辨率政策 = 当前窗口（D-06-04-T4-1）；量化界 1/65535；**加载分辨率失配 nearest 重采样**（测试抓出真缺口后补）；**降级语义**（D-06-04-T4-2）：缺失/损坏/失配 → 窗口全 1 平面 + reason 透出，不静默吞。
- MaskSpec/SidecarMaskSpec：parametric/raster payload 冻结（additive optional；nil 不进 canonical 字节 → 06-03 文档 mask cache hash 不变）。
- **门**：bake→load uint16 逐值恒等 + 量化界；三失败腿**真实构造**（换 PNG / 截断重哈希 / 缺失）；invert 腿；payload 前向兼容字节冻结；hash 覆盖三 payload。

### T5 三类 ⊕ 组合语义 + driver 全接线
- `MaskCombiner.effectivePlane`：drawn（组/单形态）⊗ parametric ⊓ raster → **单一有效平面**（D-06-04-T5-1），后处理链收尾，层 opacity 全程折叠恰一次（D-06-04-T5-2），`maskKey(stableHash)` 缓存 + 降级 reason 穿 @Sendable 闭包透出。
- `LayerCompositeDriver`：mask 腿换装 `effectivePlane`（`hasAnyPayload` 门），`maskDirectory` 参数贯通（nil + raster ref = 记录在案的降级 + error log）；6-3 消费点（blend mask 腿/前缀折叠）零改动。
- **门**：drawn⊕parametric == 基线·float64 cond <1e-5；三全 == min(drawn·cond, raster) <1e-6；raster-only 安装 == raster·op（量化界）；无目录降级内容中性 + reason 非空；**三 payload 编辑记账**（曲线编辑：5 hits/2 misses/B 链零重算 + 前缀 miss；链编辑：mask 平面 HIT 双向独立）；3 层含三类 mask sidecar round-trip 参数逐字节 + UUID 恒等 + **渲染逐字节恒等**（L014 fence）。

### T6 golden 收口
- manifest `input/golden/manifest.md` 新增「mask golden 总账」11 行（L017 注记：dt-cli 不可达对象以 float64 解析参考常驻回归替代轨 A，每行直译正本 file:line + 测试锚）。
- TODO.md 06-04 勾选 + 结论行；GOAL-STATE 增量更新；本 SUMMARY + DECISIONS（11 条裁决）。

## 验收标准逐条核验（plan Verification/Acceptance 对照）

| 验收项 | 结果 | 证据 |
|---|---|---|
| parametric parity <1e-5 + 平场二元门 + L023 往返（未新增 uniforms 矩阵对——Jz 常量复用 6-2 同源，参考链钉住） | ✅ | ParametricMaskParityTests（6 case × 6 fixture；平门精确；打包钉） |
| 后处理链 blur/feather <1e-6 + tone_curve 直译 + dt 组装序钉死 | ✅ | blur/toneCurve parity + orderPinned（含非空转探针） |
| combine 五式 × 正/反 <1e-6 + 两圆解析面积 golden + MaskGroup 嵌套 + reduce 非原地累积（L018 ping-pong） | ✅ | MaskCombineTests（formula/area/nested/order/bound） |
| raster 旁挂 PNG 16-bit 灰度 + decimal String hash + round-trip 恒等 + 失配降级落 DECISIONS（真实构造损坏文件） | ✅ | RasterMaskRoundTripTests + D-06-04-T4-1/T4-2 |
| 三类 ⊕ → 单一有效平面 + 蒙版编辑链零重算（三类扩展）+ 3 层含 mask round-trip 渲染逐字节 | ✅ | 装配三测 + testThreePayloadMaskEditAccounting + testThreePayloadMaskRoundTripAndRenderIdentity |
| 全 suite 绿 + 每任务独立提交 + SUMMARY/DECISIONS/manifest 落盘 | ✅ | 723/3skip/0fail；commits T1..T6；三件齐 |

## 决策/风险/移交

- 决策 11 条入 `06-04-DECISIONS.md`（单 kernel 全通道族、平场门战果、容差校准、feather v1 高斯、首项安装、上界抛错、烘焙窗口分辨率 + nearest 重采样、降级语义、intersect join、gopacity 单次折叠、golden 轨注记）。
- **UI 缺口（预期内）**：parametric/raster 面板与降级 UI 标记 = 6-5（本 plan 只到 render/log/返回值层）；`feather_in/out` guided-filter 升级缝 + bilinear 重采样已登记 DECISIONS。
- 全量回归：轨 B 全链零增量复核随 723 全套绿达成（GeometryGolden/轨 B 用例在内，0 fail）；seed/注册未触碰（无 seed 改动项）。
- 密码弹窗：无（直启路径全程零弹窗）。

*Phase 6 / Plan 06-04 close.*

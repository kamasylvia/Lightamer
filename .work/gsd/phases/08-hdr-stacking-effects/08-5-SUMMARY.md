# Plan 08-5 SUMMARY — dehaze + text overlay + LUT 判定 + 矩阵收口 + Phase 8 签核（W3）

**执行**：ZCode executor subagent worker（2026-09-28；`auto=true/paused=false` 每任务边界复核全程 ×7）
**提交**（7 个，未 push，Conventional Commits）：

| commit | 任务 | 内容 |
|---|---|---|
| `efccca9` | T0 | **08-1 验收回注 P1 必修**：ExifPrecheck ΔEV 快门项改亮度倍数语义 `log2(t_cand/t_ref)` + 头注释勘误 + MTBAlignTests 两断言翻转（+2→−2 / +3→−1）+ ProvenanceV4Tests 新增 `testE2EEXIFBracketMergesToKnownLuminance`（真实快门 EXIF 经生产 leg → 产物 ≈L(0.25) ±0.5%、provenance EV = [0,−2,+1]、exposureRatioVerified = [true,true,true]）+ research §2.4 公式勘误同批 |
| `4de6264` | T1 | **dehaze 14.0**（FX-04）：四 kernel 直译（`hazeremoval.cl:22-163` 滑动 min/max O(N) + transision_map `t=1−min(p/A0)·strength` + 还原式 `t_min=clamp(exp(−d·dmax),1/1024,1)`）+ 窗口式 `w1=2+⌈4·wscale⌉`/`w2=3+⌈6·wscale⌉` + **box mean 两遍近似替代 guided filter（planner 裁决冻结）** + A0/distance_max 固定 1024 长边网格降采样 + 内容哈希缓存复用（自身参数变更复用/内容变更重算，`ambientComputations` 缝钉）+ float64 参考同式双写（ambient 例程即生产例程）+ 合成雾反演 golden 三场景 + CLAHE 零混入断言 + 面板四件套 + 5 键 zh/en |
| `eec0173` | T2 | **textOverlay 66.7**（FX-05，第二条非 dt 行）：V50Order add-only（strip 双行剥离钉，94→95）+ CoreText 多行排版 → 白字 RGBA 上下文 → alpha 抽取 coverage → r8Unorm → `text_overlay_composite`（uniform 线性色 + 透明度 + 逆旋转采样，无色彩矩阵）+ YiyinFontStore 复用 + StableHash(params⊕longEdge) 纹理缓存 MISS/HIT + 空内容 routed-blit 中性 + 层蒙版局部化 + yiyin 77.0 零改动 + 同链共存用例 + 面板 + 12 键 zh/en |
| `ac4f709` | T3 | **LUT HDR 域精度判定写死 + lut3d 矩阵列 + preview 预算**：双表族实测（正域 [0.5,8] maxRel=3.8e-4 过门 / 混合符号 ±2.8 maxRel=4.6e-1 破门 78 点——D7 常驻原因坐实）+ `rgba16FloatDefaultAccepted=false` 常量分支 + 32F 行为钉（16F-lossy lattice 值 4.0009765625 经 GPU 精确 1e-5）+ lut3d 列走真 pipe（identity ≤1.2e-7 / ×2 gain 线性精确）+ preview float32 预算正式结论（70MB/平面 ×1.05 上限断言 + 四管线缓存策略结构钉） |
| `cd0b5b9` | T4 | **收口顺手**（08-1 验收注记 #2/#4 消费）：BandStreamer bands 全宽 Tile（`bands(height:width:)`）+ 显式 N 对照表 {1,2,3,4,5,8,16} 替代同参自比 + 28/41 B/px 契约保留 |
| T4 收口 | T4 | 本提交：SUMMARY/DECISIONS/TODO/perf.md 08-5 节/PROGRESS.log |
| T5 签核 | T5 | 08-VALIDATION + DISCUSSION-LOG 终节 + REQUIREMENTS 翻账 ×10 + C 档第 3 停执行记录（本提交） |

**回归**：每任务边界相关套件全绿（T0：MTB 14/Prov 9/Stack 三套 37；T1：Dehaze 6 + V50 14 + Panel 71 + Effects 5；T2：TextOverlay 6 + V50 15 + YiyinWatermark 36 + YiyinBorders 31；T3/T4：Matrix 7 + HDRMerge 15）。**全 Phase 终轮 = 1768/11skip/0fail（729.6s，`/tmp/la-085-final-suite.log`）**——基线 1636（13-3 后）+ 08-1（52）+ 08-2（~31）+ 08-3（24）+ 08-4（14）+ 08-5（净 +15：Dehaze 6 / TextOverlay 6 / Matrix +2 / ProvenanceV4 +1）。在案 flake（LayerE2ERoundTrip / ToneEqualPerf / GoldenColor）本轮零现身。

## 验收标准逐条（AC 自检）

- [x] **dehaze 14.0**：四 kernel 直译（滑动 min/max 逐行对照 .cl；transision_map；还原式）+ 窗口式 w1/w2 数值表 + **A0/distance_max preview 算 + full/export 复用（cached + 输入 hash 校验失效——D-08-5-T1-2 固定网格 + 内容哈希）** + **box 两遍近似裁决遵守**（planner 冻结，参考同式双写，parity 6.6e-5）+ 合成雾反演 golden（float64 同式双写，三场景 |Ĵ−J|≤0.15 钉，t≥t_min 带）+ CLAHE 零混入（`makeBox("clahe") == nil` 断言）+ 面板四件套（slider×2 + toggle + D-H1 + 5 键）
- [x] **text overlay 66.7**：V50Order 新行只增不改（strip 双行剥离 = 93 条钉 + count 95 + 唯一性）+ strip-to-93 钉同步 +1 + CoreText→MTLTexture（YiyinFontStore 复用；渲染目标不复用 yiyin CGImage 面）+ StableHash(textParams) 纹理缓存（MISS/HIT + longEdge 入键断言）+ 层蒙版局部化（蒙版内内容级 + 蒙版外逐字节）+ 描边/阴影不进 v1 + **yiyin 77.0 零改动**（Yiyin 面零触碰 + V50OrderTests 全绿 + order 关系断言）+ 同链共存用例 + 面板四件套 + 12 键
- [x] **LUT HDR 域精度判定**：HDR 域样本点 1e-3 相对容差断言写死（双表族）+ 升格预案分支可编译可达（`rgba16FloatDefaultAccepted` 常量翻转即换世界）+ 结论入 SUMMARY/DECISIONS（**D7 rgba32Float 保持——混合符号面 78 点破门坐实；正域面 3.8e-4 本可达标如实记录**）
- [x] **HDR-04 验证矩阵收口**：lut3d 列 parity（identity/×2 gain 走真 pipe 1.2e-7）+ 真合并产物 preview 行（预算上限断言）+ preview float32 预算复核结论落 perf.md（零新缓存类 + enforceBudget 五档零改 + EDR drawable ≈62MB 注记）
- [x] **全 Phase 终轮 0 fail**：1768/11skip/0fail；perf.md 全 Phase 汇总对账节落盘
- [x] **签核**：08-VALIDATION（SC#1-4 证据指针 + Per-Task Map + Manual-Only 汇总）+ 08-DISCUSSION-LOG 终节 + REQUIREMENTS 翻账 Delivered ×10 + **C 档第 3 停执行记录在案**（翻账 commit 后停等用户过目）
- [x] 每任务独立提交 ×7 + 边界查 config 开关（auto=true/paused=false ×7）+ 不 push + fixture 全本地盘 /tmp（禁 UNITEK）+ SUMMARY + DECISIONS 落盘

## Manual-Only 登记（不阻塞）

1. **dehaze box 近似 vs dt guided filter 视觉差对比**（planner 裁决的 Manual-Only 对比项，v1 接受；guided 全移植 = Reversibility 后补位）。
2. **text overlay 真机排版观感**（字体/字号/位置手感轮；解析面已由 FULL-BLOCK 字形分析断言钉死）。

## 偏离与勘误

1. **T0 顺序前置**：P1 必修在 T1 前独立提交（回注缺陷不与特性混交）。
2. **执行期修复（D-08-5-T1-4）**：box mean 对 2D kernel 误走 1D dispatch——stage-by-stage parity probe 定位后新增 `dispatchBox2D` 分型（parity 44× → 6.6e-5）。
3. **EXIF E2E fixture L=0.25**（D-08-5-T0-1）：L=0.5 时 +1EV 帧触及 §1.2 交集带裁剪门使自检失真——fixture 避让非语义变更。
4. **A0 统计降采样网格**（D-08-5-T1-2）：dt 的 gui_data 复用形态在 Lightamer 落为「固定 1024 网格 + 内容哈希缓存」——读回上界 12.6MB（规避 full 兜底 1.63GB 读回）且跨 pipe 估计一致；dark-channel 窗口随网格缩放。
5. **plan 计数口径**：终轮 1768 = 1752（08-3/08-4 验收后 HEAD）+ 本 plan 净增 15（Dehaze 6 + TextOverlay 6 + Matrix +2 + ProvenanceV4 +1）；基线「1636」按 R1 修订版（13-3 后）执行，13-1 的 +21 在 08 车道开跑前已在 HEAD。

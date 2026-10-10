# M4-3-01 SUMMARY — Depth 蒙版批（DA V2 Small × M2AI-10 worker × Lumen 四段管线）

> 执行 = ZCode executor subagent worker（夜间全自动授权在案）；
> 2026-10-10，起点 `d2e234a`，批次 tip `644588e`（9 提交），基线 **3335/16/0**（M4-1-VALIDATION）。
> 规格正本 = `M4-3-01-PLAN.md`；裁决正本 = `M4-3-CONTEXT.md`（OQ-1..7 全 A +
> D-1..D-5）；执行期正本 = `M4-3-01-DECISIONS.md`（§1..§9）；
> checker 处方回勾 = DECISIONS §9（m1..m7 全 ✅）。

## 1. 任务序与提交（7 代码/脚本提交 + 本收口）

| 任务 | commit | 交付面 |
|---|---|---|
| T1 | `814fc97` `feat(ai): depth anything v2 small asset chain with additive manifest fields` | 第六 profile `depthAnythingV2SmallF16`（revision `cfef6f6f2a` 锁定）+ additive `inputShortEdge`/family 判别式 + `build-depth-release-asset.sh`（确定性 zip + zipinfo 自检 + digest sentinel 重写）+ digest 真值入库（45,759,882 B / `3824a48c…`）+ DECISIONS §spike |
| T2 | `b7f2598` `feat(core): depth to near-mask pipeline with typed flat-depth face` | `DepthMaskPipeline.swift` 四段纯函数（Lumen :71-74 同参带名常量）+ `AIMaskError.noDepthStructure` + DepthMaskPipelineTests 8（numpy 锚/两级靶/斜坡 golden/typed 负测/参数缝） |
| T3 | `22872ea` `feat(app): depth inference leg on the ai worker process` | `AIWorkerDepth.swift`（臂 a image 输入 + half 输出 + isfinite m3 + F32 LE 文件）+ AIWorkerMain family 三腿 + `AIWorkerClient.runDepth` + DepthWorkerLegTests 3 + LCRSettingsTests 6 行翻面 |
| T4 | `97e2d67` `feat(app): depth mask service with package resolver and entry gate` | `DepthMaskService`（gate 四态纯函数 + ditto resolver【勘误 §4】+ preview JPEG + manifest 单源读回 + 竞态守卫 commit 缝）+ `AIMaskSource.depth` + DepthMaskEditingTests 8 |
| T5 | `98de649` `feat(app): depth mask toolbar entry with download states` | DepthEntryGate.visual 折叠 + MaskToolbarView Depth 组（单入口/下载/进度/重试四态）+ LightamerApp 注入（front-matter 增补申报）+ xcstrings 七键尾块纯插入（zh-audit PASS 1855） |
| T6 | `ec4894f` `test(app): depth golden precision and determinism gates` | `gen-depth-golden.py`（确定性合成 + sRGB ICC 标签 + F32 参考件 CPU_ONLY）+ 5 fixtures + ref-f32.bin（4,061,160 B）+ DepthGoldenTests 3（精度门/确定性/worker 端到端 + m5 open 形状） |
| T7 | `b615636` `chore(perf): depth inference probe across compute units` | `DepthPerfProbeTests`（env 双门控 skip）+ `perf.md` 落账 |
| T8 | `dda9433` docs + `644588e` `fix(test): temp-copy the image anchor in depth commit tests`（污染修复随收口补提交，事实 = DECISIONS §7） | SUMMARY/DECISIONS §7-9/ACCEPTANCE 骨架/GOAL-STATE/TODO/LESSONS/gui-acceptance 草案（local-only） |

## 2. 实测带与门值

- **spike（D-4，亲核）**：F16 件输入 = **image 类型 518(W)×392(H)**（BGRA，
  预处理烘焙 → 臂 a）；输出 = `depth` image **OneComponent32Half**，越大越近。
  **plan 的 396 勘误为 392**（checker m2 的 (H,W) 单源 = manifest）。
- **精度门（OQ-6）**：abs-rel ≤ 0.01 + max-abs ≤ 0.02。`.all` 生产腿实测
  0.0023 / 0.0029 / 0.0036（三在门件）；horizon 0.0092（e2e 件，92% 门余量
  卫生排除）、ramp 0.0237（无结构 OOD 排除）——非调门，全表 fixture README。
- **确定性门**：同包同 units 双跑逐字节 ✓。
- **perf**（`perf.md`）：forward 中位 all **45.0 ms** / cpuAndGPU 55.8 /
  cpuOnly 67.0；端到端（preview→run→readback→pipeline）**231.3 ms**。扣管道
  开销推理核 ≈30-35 ms，落 Apple 自报 25-33 ms 带（无 >10× 超带项）。
- **digest/资产链**：zip 45,759,882 B / sha256 `3824a48c…`；确定性打包两次
  构建逐字节一致；zip 内容自检（6 条目 + NOTICE 署名）脚本内 exit≠0 门。

## 3. bundle 分账（终验轮，2026-10-10/11）

| bundle | 基线 | 终验 | Δ | 备注 |
|---|---|---|---|---|
| Layers | 394 | **411/3/0** | +17 | Pipeline 8 + Editing 9 |
| Library | 619 | **626/4/0** | +7 | Catalog 4 + Store 3 |
| App | 704 | **711/4/0** | +7 | Leg 3 + Golden 3 + Probe 1（2 skip = probe env 门 + absent-assets 门，装包后正确语义） |
| 三 bundle 合计 | 1717 | **1748/11/0** | +31 | 估测带 +26..32（o4）命中；checker 注估 30-40 内 |

IOP/IOPParity 零触碰（本批零渲染管线面）——零漂移天然成立，未跑（非本批
边界；收口只跑定向三 bundle，`--all` 未申请）。

## 4. 端到端走查（spike ② 兑现）

- Release `ai-models-v1` 创建 + zip 上传（上传字节 = digest 锁定字节逐位）。
- 真下载走查（真网）：删本地安装位 → `ModelAssetStore.download` 真链 →
  notInstalled→installed → resolver 解包 → DepthSession 生成一轮
  （812,232 B，header 518×392）→ 下载 zip SHA-256 与在库 digest 逐位一致。
- 走查 harness = 一次性 /tmp 编译（真源 + walkmain），即弃；证据在
  DECISIONS §8。

## 5. 执行期重大事实（详见 DECISIONS）

1. **392 非 396**（spike 亲核，全链按 392 落地）。
2. **守卫 (b) 数学不可达**（非 NaN 输入恒 coverage ≥5%；NaN backstop +
   coverageFloor 参数缝——§3，plan KD-4 字面修正注记）。
3. **golden 三假说两证伪一真因**：真因 = 测试参考块错索引（gate 序 ≠ 生成器
   五输入序）；session 输出与 coremltools CPU predict **逐位一致**（§6）。
4. **跨 bundle fixture 污染事故（本批引入，已修复自证）**：T4 commit 测试
   直 load 共享 fixture → masks/sidecar 污染 RasterEditFaceTests 竞态面；
   修复 = tempFixtureCopy + 残留清除；修复后 App 711/4/0 全绿 + 三向对照
   实验存档（§7）。**LESSONS L072 沉淀**。
5. **Resolver 勘误兑现**：release 档「zip→可用包」一跳在 App 侧 depth 腿
   补齐（enhancement 族顺延待其 digest 发布批，observation 不扩面）。
6. **边界增补**：`LightamerApp.swift` 两行（环境注入点）+ 深度包安装 ops
   （ditto 解包至运行位，§5 命令在案）。
7. **偏差申报**：golden 输入「真实 RAW 样张」→ 确定性合成自然样张（隐私/
   许可双红线，fixture README 偏差节）。

## 6. 红线自证清单（T8 机检，全部 ✅）

- `git diff d2e234a..HEAD` 零命中集：Sidecar/、Aces2Kernels.metal、
  六格式导出矩阵、V50Order、Registry.swift、DrtRecord、HistoryStack、
  HistoryHash、LayerEditingState、MaskEdgeKernels.metal、
  **AIWorkerProtocol.swift**、NodeGraphCommand——全零。
- 全 `.metal` 零新增零 diff；Project.swift 依赖面零 diff（零新 SPM）。
- 仓内零模型字节（`git ls-files` 机检；`Resources/AIModels/.keep` 为既有
  哨兵；DepthPrecision fixture = PNG/bin 非 o5 红线物）。
- AC#3 grep 门：App target 产线 MLModel 构造点仅在 AIWorkerMain/
  AIWorkerEnhancement/AIWorkerDepth 三文件（Core SemanticEngine 既有
  InProcessMLModelRunner 面零新增——m7 精确化表述兑现）。
- zh-audit `--check` PASS（1855 catalog = 1848 + 7，纯插入 added=7/
  removed=0/modified=0）。
- digest fail-closed 面保持：其余 release profile digest 恒 nil（负测在
  库）。

## 7. m1..m7 处方回勾（checker M4-3-CHECKER.md §4）

全七项采纳兑现，逐条表 = DECISIONS §9（m1 CLI 名 ✅ / m2 单源 392 ✅ /
m3 isfinite ✅ / m4 脚本自检 ✅ / m5 穷举+open 形状 ✅ / m6 近区 10.25% ✅ /
m7 白名单+grep 门精确化 ✅）。

## 8. 双重验收编排（config `dual_acceptance = true`）

zcode subagent 独立验收 PASS 后 → **串行** omp 二次验收（computer-use 走查；
严禁并发）。本批执行方只建骨架 = `M4-3-01-ACCEPTANCE.md`；GUI 走查配方草案
= `.work/gui-acceptance/m4-3/MANIFEST.md`（Manual-Only 行——三电路激活环境
级全惰先例，M3-4 在案）。

## 9. 挂账与遗留

- **enhancement 族 resolver 顺延**：release 档 zip→包一跳仅 depth 腿补齐；
  enhancement digest 发布批处置（observation，DECISIONS §2/§4）。
- **guided filter（OQ-5 边界）**：深边界糊可见度 = GUI 走查观察项，证据驱动
  挂 V2。
- **远景第二入口**：invert 位已承载；零成本后补糖（DECISIONS 注记）。
- **测试对账口径**：终验三 bundle 1748/11/0（基线 1717 + 31 = 8+9+3+3+7+1
  精确）；全套 `--all` 未申请（本批零 IOP 触碰，无需 orchestrator 批准轮）。
- **未 push**（纪律）；Release tag `ai-models-v1` 已上 remote（plan T8 ops
  明示，资产字节 digest 锁定与代码 tag 无关）。

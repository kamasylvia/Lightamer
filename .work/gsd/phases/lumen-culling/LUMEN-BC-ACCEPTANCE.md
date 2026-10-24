# LUMEN-BC-ACCEPTANCE — plan B+plan C(缓存底座/选片视图 + 蒙版精细化)综合独立验收

> 验收轮:2026-10-24,验收人 = zcode 独立验收 lane(plan 忠实 + 对抗角度合并——
> A 已双路 + omp 三眼闭环,本报告只覆盖 B/C)。
> 对象 = `3b916721..8896a46e`(LUMEN-B 七 commit)+ `66730d55..5fee217d`(LUMEN-C
> 五 commit);主树 HEAD = `5fee217d`(git log 亲核,全程只读,零源码改动;
> git status 跟踪面亲证干净)。
> 报告与探针证据落 `.work/gsd/phases/lumen-culling/evidence/lumenbc/`,本报告不 commit。

## PASS / 0 blocking + 0 major + 4 minor + 10 obs

**判定:PASS**。B 六任务 + C 四任务 SC 逐条有机检判据且全部独立复现;全套 `--all`
独立复跑 **TOTAL|4204/41/0|**(2225s)与 executor 三轮**逐位一致**,零 fail 零 MEMFAIL;
FIX2③(全批 `LibraryProjectController` 空 diff)与 16 件封存面(`McpServerController`/
`AIMaskFeather`/`PixelPipe`/`HistoryStack`/`LightamerSidecar`/`CullingView`/
`SessionThumbnailProvider` 等)零 diff 全数亲证;全批 xcstrings **352/0 纯插入** +
zh-audit 双 PASS(1719/2038,uv run 亲跑);对账算术**精确闭合**(4144 基线 + B +41 +
C +19 = 4204)。四项 minor 均为台账/卫生/边界级,无一触及行为红线;对抗面四路
(并发压力/损坏注入/大图内存/MCP 实调)全过。

---

## 一、全套独立复跑(验收清单第 3 项)——逐位命中

`Scripts/machine-guard.sh` PASS(G1-G4,free 74-76%)→ caffeinate + nohup + disown
独立一轮 `Scripts/test-direct.sh --all`,证据 = `evidence/lumenbc/acc-all-round1.log`:

| bundle | 本验收实测 | executor 三轮 | peak RSS |
|---|---|---|---|
| IOP | **771/5/0** | 771/5/0(×3) | 5309MB |
| IOPParity | **478/6/0** | 478/6/0(×3) | 3565MB |
| Layers | **502/6/0** | 502/6/0(×3) | 683MB |
| Library | **776/4/0** | 776/4/0(×3) | 799MB |
| Sessions | **285/9/0** | 285/9/0(×3) | 1161MB |
| Export | **385/5/0** | 385/5/0(×3) | 3885MB |
| App | **1007/6/0** | 1007/6/0(×3) | 2832MB |
| **TOTAL** | **4204/41/0 / 2225s** | 4204/41/0(2246/2281/2297s) | 全 <8G,零 MEMFAIL |

- **对账精确闭合**(obs-4):A 二路验收真值 = `4144/40/0`(4112 r12 基线 + A T1-T8
  +31 + 徽章修复批 `dcc1c030` +1)→ +41(B)→ 4185 → +19(C:Layers 494→502、
  App 996→1007、其余五 bundle 与 B 收口逐位同值)→ **4204**。C-SUMMARY 的
  「±1 组成漂移」叙述保守于实情,数学无漂移。
- skip 40→41 = 恰一本批新增 LU5 时长探针族(红线 14,`LIGHTAMER_PERF_PROBE=1`
  门,默认 skip)——与 C-DECISIONS §3.6 一致。
- per-bundle 向量 vs B 前基线:Layers +8 / App +11(C 申报)逐位对上;B 增量
  IOP +18 / App +22 / Library +1(SUMMARY §ΔN)同样闭合。

## 二、LUMEN-B 逐任务判定(验收清单第 1 项)——六任务全 PASS

| 任务 | 判据(亲跑/亲核) | 判定 |
|---|---|---|
| T1 LAPV1 格式 | round-trip **逐位**断言(双源:LCG 噪声 + 照片样合成)+ float16 相对误差 <0.05% 断言 + quantize 幂等专测 + 平面重排单调压缩 smoke + 畸形输入 typed 容错例——全部在 `SmartPreviewStoreTests`(IOP 771/5/0 内)独立复跑绿;格式层源码逐行核(magic/头长/JSON 头/planar float16/zlib) | PASS |
| T2 键/index/LRU/in-flight | 键 = `path\|size\|mtime ns\|process version\|格式版 → sha1 hex`(mtime ns = `st_mtimespec` 同秒连拍防撞;失效三例 + hex 形专测);SQLite WAL `entries(key,kind,bytes,used)` + 损坏删 db/-wal/-shm 重建;LRU 4GB 默认(`previews.cacheMB` 全仓字面量恰一处 = Core 常量亲 grep)/trim 90%/每 16 写;in-flight 同 key 合并(shared holder `replaceShared` 往返亲证);降级直解码/禁用中性(disabled = 原解码逐字节直通,enabled-敌意目录仍量化——DECISIONS §5 语义)各有专测 | PASS |
| T3 四门接线 | 消费点亲 grep:gate ② `WorkspaceHostView:746`(RenderLeg 生产侧,注入 bridge)+ gate ③ `CullViewLoader:275` + gate ④ `CullingToolset:117`(seam 内部换路由,签名零改;`McpServerController:932` 构造点零 diff 消费);gate ① 申报未接线(见 §五.1);**编辑腿零路由亲证**:EditorState/PipeCoordinator/PixelPipe 全批零 SmartPreviewStore 引用(t3-grep.log + 本验收重跑同判);默认中性 golden(disabled 逐字节)+ 命中/未命中逐位 golden(disk hit == miss == quantize(decode))在册 | PASS(gate ① 结构性偏差判等,§五) |
| T4 CullFace 第三 face | `AppPhase.cull` additive(路由 tripwire 测试 +4 行亲核);CullViewLoader:显示档 2560 = `CGImageSourceCreateThumbnailAtIndex` 内嵌直读(零 RAW 解码——域内零 RAWDecoder 引用)+ LRU 14 + 全尺寸 LRU cap 2 + ±3 预读尾插 + 生产门 cap 2(ThumbnailProductionGate 复用,bridge 仅 private→internal 访问级 diff)+ full_size ≥50% 判定(三案表驱动 + 缺席=假诚实臂)+ 回落腿切换(fallbackDecodeCount 计数钉);`CullingView.swift`/`SessionThumbnailProvider` 零 diff;`720` 域内零命中 | PASS |
| T5 键位评级写腿 | `CullKeymap` 表驱动单源(G/D 钉死 + 0-5/P/X/U/6-9/A/C/F + Z 偏差);视图 `onKeyPress` 恰经表(无散落 switch);评级写腿 = 注入缝绑 `LibraryStore.setMetadataMarks` + 本地 projection 即时刷新(`applyWrittenMarks`)+ flag 0/1/2 与 sidecar trio 一致专测 + A 同步前进 + 重复色标清零;xcstrings 尾插 **160/0** 纯插入(numstat 亲核);zh-audit 双 PASS | PASS |
| T6 对比/组跳/提示条/插队 | 对比状态机(换候选/Tab 切侧/↑ 晋升/退出交接/单行拒入)+ 共享 zoom 单源 + 组跳(前跳落组首/后跳落前组首/无组退化为步进)+ 提示条映射(sharpness/blurry/闭眼/burst n/m/best)+ 插队 ±(−2..+6) 窗纯函数 + `LibraryAnalysisService.prioritize` 优先缝 + wiring 装配(各专测在册);全批 diff 零触 legacy CullingView | PASS |
| T7 收口 | Settings 容量行(阶梯 Picker + live `setLimit`)+ Project.swift 恰两行 + BUNDLE-MAP 两行 + tuist generate 批末位 + 15 键登记 | PASS |

## 三、LUMEN-C 逐任务判定(验收清单第 2 项)——四任务全 PASS

| 任务 | 判据(亲跑/亲核) | 判定 |
|---|---|---|
| T1 五步直译 | `MaskRefine.swift` 源码逐行对 CONTEXT X8 全式(band 0.75/σ{.5,2,8,32}/.08²/.25\|d\|+.02/gate²/smoothstep/grow-shrink 钳);`import Metal`/`MTLCompute` 零命中;`fineEdge=4096` 恰一处;MIT 文件头 + NOTICE Q 条目含 MaskRefine(亲读);**golden firsthand 亲算**(自织探针直读 `maskrefine_golden.bin`,独立重算):**mean \|Δ\| = 2.84e-3 / max = 6.39e-2**,与申报 2.8e-3/6.4e-2 吻合、带 0.02/0.15 内;场景八法(twigs/broad-ramps/门控表驱动/钳边界/畸变容错/fineSize 钳数学/探针)在 Layers **502/6/0** 独立复跑绿 | PASS |
| T2 编排 | 单飞(`isBusy` 哨兵 + 并发专测)+ 等待队列(waitingCount 钉)+ 一步 history commit(复用 `commitRasterMask` 既有缝,items +1 断言 + ⌘Z 恢复快速蒙版断言)+ 失败保底(注入抛错 → 蒙版 hash 不变 + history 不变 + toast 必达)+ `refineCommit` 断环(generation commit 触发一次/refine commit 零触发)+ fineAuto typed 读(缺席=true)+ 1.2s debounce(关=不触发、开=debounce 后自动触发、手动仍可达)+ MCP typed unknown(`refineMasksForMCP`)——App **1007/6/0** 内全绿;`mask.fineAuto` 键字面量全仓恰一处(Coordinator:55,余四命中 = 注释/AX id,亲核) | PASS |
| T3 MCP refine_masks | `refineMasks` 供给面恰两处(EditingToolset:120 Seams 声明 + LightamerShell:1136 post-assignment 装配,projectWriteProbe 先例同位);nil 缝 = typed 不可用脸 + live-image 要求 + unknown typed + gate 串行 + 入参校验——五面专测在册;**McpServerController 全批零 diff**(`git diff c7bc2b9b..HEAD -- McpServerController.swift` 空——M-4 裁决核亲证);快照 conscious 批 32→33/23→24 六文件亲核;culling 域 14 工具零触(tools.md + 快照闭集) | PASS |
| T4 Settings 收口 | `mask.fineAuto` 行(SettingsPages:300 蒙版精细化节,AppPreferences alias 单源)+ Project.swift 三行(530/837/838)+ BUNDLE-MAP 三行(302/861/862)+ tuist generate 批末位(23664aba)+ xcstrings +3 | PASS |

## 四、对抗角度(验收清单第 4 项)——四路全过

1. **SmartPreviewStore 并发攻击**(自织探针,production 源文件原样 swiftc 编译,
   precondition 实断言,证据 `evidence/lumenbc/store-stress.swift` + `stress-run.log`):
   - 多 reader:24 并发请求 / 8 key → **恰 8 次解码**,全部等值返回(in-flight 合并在真并发下成立);
   - 写淘汰赛跑:60 噪声源(~2.4MB)灌 2MB 预算 + 并发 touch/trim 40 轮 → 无崩溃,flush 后显式 trim 回 90% 内(1867133B ≤ 1887436B)、显式 target 200KB 生效(103715B)、**index↔file 集合一致**(存活 key 全有文件);
   - 损坏注入:21 文件 garbage 化 10 个 → 冷店全量重载**逐平面精确**(== quantize(decode)),重建后 0 个非法 envelope;
   - 损坏 index + 并发双载:junk 覆写 index.db → typed 重建 + 记账恢复。
2. **CullView 预读 × 编辑器竞争**:预读/full 产制全部经 ThumbnailProductionGate cap 2 串行化,face 关闭不取消但在制量级小(2560 内嵌 ~10ms 级),actor 排空即释放,无泄漏(obs-5);fulls LRU 2 封顶内存。
3. **MaskRefine 大图内存面**(4096 cap 探针,`/usr/bin/time -l` ru_maxrss):4096×3072 guide 全五步 **0.30s / 峰值 RSS 475MB**——远低于 GUI 3G 触发线;与 Lumen 33MP≈7s 参照相比量级更优(cap 域更小 + reduced-copy blur)。`refine-probe-run.log` 在库。
4. **fineAuto debounce 自愈形**(1.2s):`autoTask` cancel-previous 折叠突发;`refineCommit` 断环防自激励(专测);patch 重烘焙 commit 再点火 = 自愈语义(patch 1s debounce 先落,refine 读 settled 面)——代码链亲核 + 测试双臂覆盖。
5. **refine_masks MCP 实调**(真机 GUI 实例 + Streamable HTTP,证据 `toolslist.sse`/`refine1.sse`/`refine2.sse`/`acq.sse`):
   - `tools/list` = **33 工具闭集**,refine_masks 在册(编辑域);
   - 无控制权调用 → typed `[controlNotHeld]`(requiresControl 闸在 handler 前);
   - control_acquire 后无会话 relPath → typed `[notSessionMember]`;
   - control_acquire/release 往返干净(`held:true→false`)。正路径(真项目 + AI 蒙版)走查归 validate 道(manifest 在案)。

## 五、偏差十五项逐条判等(验收清单第 5 项)

**B 八项**:
1. **gate ① 结构性不接线**——**接受**。论证成立:本仓载入腿平面 = 编辑工作平面本体(lazy CIImage 全分辨率),缓存量化它 = 直触 H-LU3 第二臂(编辑平面逐位漂移)= 红线禁手;PipeCoordinator/EditorState 零 diff 亲证。**对照 B-1 教训(A 批徽章断链)死路检查:无死路残余**——三活门构造点逐一亲证(Shell:1074 / McpServerController:932 / WorkspaceHostView:746 / CullViewLoader 缺省腿),未接线状态在源码注释 + DECISIONS 双声明,重开加速诉求留后批立项口。
2. **gate ② v1 pristine 腿**——接受。hasEdits 行从占位变 pristine 观感图,列语义不变;develop 物化 = P2 域,申报在案。
3. **2560 档位**——接受。预算算术亲核(2560 长边平面 ~17MB × 6 ≈ 105MB);4096 臂弃理由(1.6GB 内存)成立。
4. **zlib level-1 等价**——接受。Compression framework 无级别旋钮,`COMPRESSION_ZLIB` 速度定向 = 意图结构满足;「高级别不可达」使红线不可破。
5. **层弃(2560 JPEG 视图层 + 320 thumbs 层)**——接受。直读 10.6ms/张实测口径 + `.lathumbs` 既有派生物承担;index `kind` 列保留 = 表形直译完整。
6. **Z 键(X7 外可加)**——接受。G/D 钉死对不动,Space 让位滚动语义合理。
7. **评级投影即时面(.lra 真相回填挂下次编辑侧 mark 写)**——接受。库域判定面定位自洽,投影落 .lalb DB 跨会话持久;折衷申报明确,非静默语义漂移。
8. **reopen 探针 skip 族**——接受。代证链(T2/T3 golden 即命中路径本体 + Lumen 40ms 口径)+ 挂账 validate 道与 GUI 走查同轮,账面诚实。

**C 七项**:
9. **per-mask commit(N 步 undo)**——接受。批级单 item 需新 history item 类型 = 封存面禁区(红线 2),停手正确;自动路径(99%)单蒙版 = 一步,与 Lumen 同义。
10. **re-bake featherRadius 恒 0**——接受。存储 PNG 已物化羽化,再施 = 双羽化;AIMaskFeather 零 diff 亲证(X8 正交兑现);percent「下次 bake」交互为现状语义非本批引入。
11. **guide 腿盘真相**(QuickLookRenderer ≤4096,pristineOnly:false)——接受。零新渲染代码复用 14-2 headless 链;live 滑杆 2s debounce 窗边界注记在案;蒙版语义锚定 decode frame 为继承定案,guide 仅质量辅助。
12. **erode/dilate chamfer/运行最大值形**——接受。vImage 无椭圆 morphology;±1px 带界类差被 golden 带吸收——**firsthand mean 2.84e-3 / max 6.39e-2 实测在带内**(本次验收独立复算,非转抄)。
13. **patch commit 再点火自愈形**——接受。hook 不分 patch 是行为面而非缺陷:patch 置换 raster 后 re-refine = 收敛自愈;`refineCommit` 断环防自激励;debounce 1.2s > patch 1.2s 链次序成立。
14. **skip +1(LU5 时长探针)**——接受。红线 14 族标准形;全套 skip 40→41 对账闭合。
15. **xcstrings 同文件提交(T2 带工具描述键)**——形式接受(键集恰 7 键、两次尾插纯插入成立),**但台账行数申报失真 → minor-1**。

## 六、回归面(验收清单第 6 项)——全过

- **FIX2③**:全批 `git diff c7bc2b9b..HEAD -- LibraryProjectController.swift` 空(亲证)。
- **封存面 16 件零 diff**(全批):PixelPipe / Lut3dKernels.metal / HistoryStack / HistoryHash / LightamerSidecar / V50Order / NodeOwnershipCatalog(GradeCatalog) / DrtRecord / TerminalTailPolicy / DrtTailAssembly / ExportQueueContract / **McpServerController**(M-4 裁决核) / AIMaskFeather / CullingView / SessionThumbnailProvider / RAWDecoder。
- EditorState/PipeCoordinator:B 批零 diff(B-SUMMARY 断言对 B 成立);C 批 EditorState 仅 additive `maskRefine: MaskRefineCoordinator?`(nil = 既有构造/测试零行为,申报过)。
- **M2-3 档A/档B**:SessionThumbnailProvider 零触;bridge 唯一 diff = `ThumbnailProductionGate` private→internal(语义零改,复用申报形)。
- **xcstrings 全批 352/0 纯插入**(numstat + 逐 commit numstat);`LocalizationValue("prefix_\(x)")` 禁形零命中;`runModal` 族零命中(L057);zh-audit `--check` + `--self-test` 双 PASS 亲跑(uv run,1719 source / 2038 catalog)。
- **静置 churn**:真机 GUI 实例(对抗 #5 同实例)静置三采样 **0.0% CPU**;全套复跑后零 Lightamer/caffeinate/test-direct 残留进程。
- 「三窗持续正常」与 GUI 评级流/对比缩放/重开探针走查 = **validate 道职责**(`.work/gui-acceptance/lumen-b|c/MANIFEST.md` 在案),本验收道为纯文本机检,如实留待。

## 七、分级清单

**blocking(0)**——无。

**major(0)**——无。

**minor(4)**:
1. **C 批 xcstrings 台账数字失真**:LUMEN-C-SUMMARY 称「三次尾插(48/48/48 行)」、DECISIONS §3.7 称「48 行/48 行」;实测 = **两次尾插 64+48 行**(c374889d = 64/0、e5790c59 = 0、23664aba = 48/0,numstat 亲核)。键集恰 7 键、纯插入性质、同文件不可拆分 staging 的申报理由均成立——纯账面失真,违 §3.1「台账与实际一致」;修复 = 文档勘误随下批 docs 批。
2. **MaskRefine.swift:138 MR_DEBUG 调试残留**:env 门控 stderr 调试输出(`MR_DEBUG=1`)未在 DECISIONS/SUMMARY 登记的生产文件钩子;惰性(默认零行为)但属未申报面,建议随下批摘除或登记。
3. **CullViewLoader full 档无内嵌预览 RAW 的边界**:`embeddedFullSize`(maxPixel `Int.max` + `CreateThumbnailFromImageAlways`)在无内嵌预览的 RAW 上由 ImageIO 落全解码——绕开 T3 缓存路由、`isEmbedded=true` 误标、单次大分配无 cap。主流 RAW 均带内嵌预览,边界窄;fulls LRU 2 + gate 2 兜底。建议后续把 sensor-px 判定前置到提取前。
4. **B T1 typed 容错覆盖 4/5 案 + 误差度量形未申报**:枚举五案中 `badHeader`(JSON 解码失败)无直接测试例(`headerTooLarge` 结构性不可达);<0.05% 断言采用 max-幅值归一形式(per-sample 相对误差近零无界,测试注释自述但 DECISIONS 未记)。建议补 1 例 + DECISIONS 补记度量形。

**obs(10)**:
1. 插队窗 −2..+6 双闭 = 9 行,Lumen Python 切片 `[focus-2:focus+6]` = 8 行(end-exclusive)——plan 钉死值即 9 行实现忠实 plan,与上游保真差 1 行,备查。
2. trim 节律「终局一致」形:16 写巡检间隙缓存可超预算(探针实测 preTrim 2.38MB > 2MB),显式 trim/setLimit 即回——Lumen 同形,无害。
3. `refineMasks` 「恰两处」为供给面口径(Seams + Shell);工具体内 guard/调用两处引用与 DECISIONS §2 自洽,备查。
4. 对账 ±1 已解:A 二路真值 4144(修复批 +1)→ 4144+41+19 = **4204 精确闭合**;C-SUMMARY「±1 组成漂移」叙述保守。
5. CullView 预读/full 产制 face 关闭不取消——量级小、gate cap、actor 排空释放,可接受。
6. gate ① 无死路残余(三活门构造点亲证 + 双声明)。
7. 计划 files_modified 之外的邻接小触点(WorkspaceModel `AppPhase.cull`/LibraryAnalysisWiring prioritizeAnalysis/AppPreferences alias/RasterMaskStore `loadPlane` additive)全部 additive 且 SUMMARY/DECISIONS 有申报——清单纪律合格。
8. MCP 实调三面:33 闭集 + controlNotHeld/notSessionMember typed + acquire/release 往返。
9. MaskRefine 4096×3072:0.30s / 475MB——大图内存面无险。
10. SmartPreviewStore 压力四案全过 + 静置 0.0% CPU + 全套后零残留进程(还原声明见 §八)。

## 八、还原声明

- 全套复跑、GUI 实例(对抗 #5 自起,PID 98202)、caffeinate:全部退出,**零进程残留**(ps 亲证)。
- 验收自写 UserDefaults 键 `mcp_server_enabled` 已 `defaults delete` 还原;运行产生的 `mcp-endpoint.json` 残留已清(`mcp-endpoint.lock` 为 2026-09-28 既有物,未触碰)。
- /tmp 探针二进制已删,源码 + 运行日志随 evidence 入库(仓内仅 `.work/` 新增,零源码/零跟踪面改动;`git status` 跟踪面干净,HEAD `5fee217d` 未动,本报告不 commit)。

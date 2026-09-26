# Plan 11-04 DECISIONS — 执行期决策清单

1. **D1（T1）渲染/编码腿拆分 = `ExportRenderer` additive 两段化**：11-03 `render()` 为一体全链，而 11-01 D3「artifact 真载荷」要求 render→encode 边界可中断（cancel 不落盘）。解法：`renderStage`（decode→…→quantize+命名，零写盘）+ `encodeStage`（显式参数列表 encoder→原子晋升），`render()` 保持原签名内部组合——11-03 调用方与测试零改动。`StageOutput` 与契约 `ExportRenderStage` 携同一参数面（plane/formatSpec/targetColorSpace/dpi/destination/sourceURL/editorSignature）。
2. **D2（T1）`ExportRenderArtifact` 真载荷形态**：真载荷 = `stage: ExportRenderStage?`（nil = 单测 synthetic token 模式）；`Hashable` 手写且只combine token/width/height——100MP plane（GB 级 Data）绝不进 Hasher（identity 比较零开销）。
3. **D3（T1）leg 签名补 `ExportJobContext`**：11-01 `ExportRenderLeg` 单参数（snapshot）承载不了落点/占用名/override。扩为 `(snapshot, context)`；context = destinationDirectory + **dequeue 时枚举**的 occupiedNames（11-03 E2E 冲突教训：执行时读，不缓存于 enqueue）+ instancesOverride（live-edit 面）+ editorSignature。契约文件为计划内兑现面（非禁改件）。
4. **D4（T1）无 per-job waiter continuation**：9-3 骨架的 `waiters`/`resume nil` 件被「快照 + `setProgressHook` 通知」替代——导出是 fire-and-forget（无 `thumbnail(for:)` 式阻塞取图语义），`cancelAll` 的「resume waiters nil」由「pending 标 cancelled + 代际闸 + 进度窗重置」等价实现。plan「resume waiters nil」语义以替代件兑现，非遗漏。
5. **D5（T1）cancel(in-flight) 的诚实语义**：取消旗在 render→encode 边界检查——render 段零写盘故弃之无痕；**encode 一旦开始则完成 `.done`**（文件已原子晋升，状态不谎报磁盘）。防 dequeue 竞态：cancel 先武装 `cancelledInFlight` 再查 pending 表，settled 计数两路只记一次。
6. **D6（T1）progress 代际记账**：`done/total` 为当前 generation 窗口（cancelAll 重置 0/0）；stale straggler 出闸不计入新代；retry 撤销 failed 的 settled 计数再于完成时回补，`done ≤ total` 恒成立。
7. **D7（T1）job 不快照 document**：契约注释期望 job 携 document payload，但 11-03 renderer 已钉「disk sidecar truth 在出队时读」（`instancesOverride` 为显式覆盖通道）——queue 不预读 sidecar，避免入队/出队两份真相。live-edit 面由 enqueueExport 的 override 参数承担。
8. **D8（T2/T6）GUI 取消/重试与多图 N×M 入队不走查**：单 fixture 单 job 瞬时完成，GUI 无中间态可观察；语义由 ExportQueueTests ②③⑤⑥ 全覆盖。GUI 走查以「可见状态面 + post-action 实跑」为界。
9. **D9（T4）面板挂载点 = 工具栏点亮 + ⌘⇧E focusedValue 桥**：Inspector 列是调整面板域（且 grid/culling 模式整列隐藏），导出为模态工作流 → sheet。工具栏「Phase 11 disabled」占位按钮点亮为主入口；File 菜单 ⌘⇧E 经新 `ExportPanelRequestKey` focusedValue 桥接（scene 间无共享状态）。L010 identifier 全键：`toolbar.export`、`export.button.{close,add_variant,remove_variant,choose_directory,reset_destination,choose_script,clear_script,run,cancel_all,cancel_one,retry}`、`export.picker.{sizing,format,color_space,tiff_compression}`、`export.field.{long_edge_px,short_edge_px,scale_percent,dpi,output_tag}`、`export.toggle.{yiyin,webp_lossless,postaction_script,postaction_reveal}`、`export.slider.quality`、`export.group.variant_N`、`export.list.variants`、`export.warning.large_tiff`、`export.progress.overall`、`export.row.job`。
10. **D10（T4）tag 派生消费位置 = ExportState.enqueueExport**：`resolvedOutputTags` 需要 canvas 尺寸（percent 模式折叠），queue/renderer 均不知画布——入队时由面板传 `canvasSize`（当前图 extent）解析并写回各 variant 的 `outputTag`（显式 tag 优先、单 variant → nil）。跨图同名冲突降级为 ExportNamer `-1/-2` 递增。
11. **D11（T4）色彩空间 Picker 直用 rawValue 显示**（sRGB/DisplayP3/AdobeRGB/ProPhoto/Rec2020 为专有名词，不进 catalog）；格式 kind 用面板本地 enum（带关联值 enum 无法直接驱动 Picker），切换时填该格式默认参数再由 per-kind 行细调。
12. **D12（T5）post-action 偏好持久化 = UserDefaults**：脚本 bookmark + 双开关是**用户偏好**（D-11-CONTEXT-3 的「recipe 不落盘」不覆盖此项——D-11-CONTEXT-6 要求显式配置可持久）；普通 bookmark（非沙盒，`ENABLE_USER_SELECTED_FILES=read-write` 已在 Project.swift）+ 每次触发 `resolveScript` 重验可达性，失效降级「未选择脚本」态（无弹窗风暴）。
13. **D13（T5）completion hook 面**：Core `ExportQueue.setCompletionHook` 仅 `.done` 且当代 generation 触发（failed/cancelled/stale 不触发——OQ-11-7 逐文件语义 + R8 纪律）；fire-and-forget detached（慢脚本不阻塞 pump）。ExportState 侧 MainActor hop 后 fire：reveal 走 AppKit 主线程，脚本 Process 在 utility detached 中跑完并记录 exit status。
14. **D14（T3）terminate flush 位 = 记录放弃**：02-06 先例是有界等待强制落盘（sidecar 是唯一真相）；导出 job 无 journal 且渲染段零写盘（无半成品），等待无收益——v1 记录在飞计数即放行退出（D-11-CONTEXT-8 重启丢队列语义的一环）。
15. **D15（T6）flaky 处置 = 域外挂账不改断言**：`testYiyinFourStateMatrixAndBorderedRoundTrip` 的 byte-exact 断言在基线上同样 fail/pass 交替（GPU 非确定 + AGX assertion），本 plan 无权改 11-03 测试；修复候选（像素容差比对）挂 GOAL-STATE 待人工。

## mask-fence 收编评估（executor 协议第 5 条）

**结论：v1 不收编（正确性无碍，收益仅并发，改动面超本 plan 范围）。**

事实核查（四处直取 `metal.commandQueue` 面）：
- `DrawnMaskRasterizer.swift:515` 区（mask_stamp 静态 render encoder 的 commandBuffer）
- `RasterMaskStore.swift:58`（`readPlane` fence 回读——烘焙路径，导出不触发）
- `RetouchEngine.swift:541+`（ROI blit commandBuffer）
- `AIMaskService.swift:130`（推理前 fence——蒙版**生成**路径，导出不触发）

导出链含绘制蒙版/修复层时，`DrawnMaskRasterizer`/`RetouchEngine` 的静态 dispatch 落编辑队列：同一 device、同队列内 fence 自洽，**正确性无碍**；仅该子块不享 exportCommandQueue 的并发隔离。收编需改 4 处 seam（`metal.commandQueue` 显式取用点改走 TaskLocal 感知的 `makeCommandBuffer`）+ 图层回归全绿，超出 11-04 面且当前无用户可见症状——Phase 15 性能轮若实测导出 GPU 争抢再收编（届时与 `yieldsToEditor` 一并评估）。

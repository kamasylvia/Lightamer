# M2-3-3 DECISIONS — 编辑器面（三段布局 + 七页签 + 示波器 + RAW Decode + Settings）

> 执行身份注记：T1-T3（`46e13fb` / `29553ba` / `05317d1`）由前任 worker 完成；前任在 T4
> 在制品中断（机器重启），T4 由续班 worker 收尾提交（`921a98f`，含 4 处编译级修复 +
> 收尾申报）；T5（`8d556c7`）与 T6 收口由续班 worker 完成。
> 执行日期：2026-09-29。

## KD 执行确认

- **KD-1（三段布局包装边界）**：前置核对步执行，结论 = **`EditorAreaView.swift`
  全 plan 零 diff**（`git diff --name-only 46e13fb^..HEAD` 无该文件）——三段壳全部挂接走
  `EditorWorkspaceShellView` 外层包装文件，视口/手势/overlay/busy/FIT/ZoomHUD 面零迁移
  （既有测试零改动全绿）。M2-2-4 冻结快照（`LibraryLegacyGateTests`）不含编辑器域
  identifier，且零 diff 包装使快照顾虑 moot；快照测试 T5 后复跑全绿。
- **KD-2（路由表代码化）**：`EditorTabRoute` Alcedo 七页序 + `EditorTabRoutingTable`
  静态映射 + `EditorPanelDescriptor`（registry op 常量引用，非字符串字面量）落成；
  完备性断言域 = 动态 populated-registry − {TextOverlay}（checker m3），TAB-MATRIX md
  与表同批互校（T2 验收步）。Display Transform 页 = Vignette + DRT 占位节（**checker
  E1 勘误执行**：AgX 保持失挂；`git grep -i agx` 在三文件仅命中的是 E1 勘误注释与
  TAB-MATRIX 勘误注记行——路由表 `panels(for:)` 实际条目零命中，其余 5 名
  （filmicrgb/sigmoid/denoiseprofile/nlmeans/bilateral）三文件零命中）。
- **KD-3（示波器 GPU 归约）**：`ScopeReduce` 双 pass + `ScopeReduceKernels.metal`
  （atomic_uint bin 256×4 + 波形列散点）；队列路由 = PipeCoordinator 唯一获取点
  （`detectionMetal()`），新增代码 `makeCommandQueue()` grep 零命中；直方图读回
  fence 纪律承 L014/HistogramReduce 先例；节流 = `ScopeThrottle` 纯 MainActor 状态机
  （≤15 Hz 流式 + 0.25s idle 补算 + 不可见零 tap），3 条状态机单测在
  `ScopeReduceTests`。
- **KD-4（RAW Decode overrides）**：见 D1-D5。
- **KD-5（Settings 七页+3）**：页集 = D7 十项（`navigationPages` 精确断言，含
  Acceleration/Updates 负例）+ Catalogs 门控页（`displayedPages` 两态断言）；
  Displays/MCP/Catalogs 三节**语句级 verbatim 迁移**（identifier/存储面逐字保留），
  `visibleCatalogSectionMarkers` 函数零 diff（`LibraryLegacyGateTests` 11 条零改动
  全绿）；LCR/ACA = 结构骨架 + M2-10 空态家族，零假开关；Keyboard v1 =
  展示/检测/恢复三面，不活绑重映射（恢复按钮仅在有 overrides 时可见）；mask 三选
  = 只存不接线（M2-7 消费）。

## 偏差与执行裁决

1. **D1 KD-4 膨胀字段规则触发（申报）**：sharpness/boost 两腿在
   `rawTechnicalParams(from:)` readback 无承载字段 → cache key 漏漂移。按纪律 5 同批
   扩 `RAWTechnicalParams`（Optional `sharpnessAmount`/`boost`，encodeIfPresent——
   nil 腿 JSON 字节形不变）+ `HistoryHash.decodeParamsHash` 两腿 Optional fold
   （nil 不折，M2-3-3 前文档 hash 逐字节不变）。front-matter + 纪律 5 当场更新
   （`921a98f` 同批）。单测钉死：identity decode 的 rawTech JSON 无新键 +
   decodeParamsHash 与默认路径逐字节相等。
2. **D2 LightamerApp.swift 越界一行（申报）**：front-matter 未申报该文件；Settings
   scene 补 `.environment(pipeCoordinator)` 一行——13-2 display 覆盖行读 coordinator
   （`refreshDisplayProfile`）而 Settings scene 从未注入（存量缺失注入，页面迁移时
   显形；不补则 displays 页打开即 crash）。纯增量行，DECISIONS 归因。
3. **D3 orchestrator 豁免件 `02f727f`**：`McpServerController.swift` stdout fsync
   管道防御修复——orchestrator 修的非本 plan commit（test-spawn fixture 子进程
   SIGABRT flake 钉死）。边界审计按 SHA 剔除，SUMMARY 注记；本 plan 未触碰该文件。
4. **D4 decodeRAW 内部 version-selection 块重构**：KD-4 decoder version override 腿
   的必要重构（`var requested` 探针块 → `resolveDecoderVersion` 纯函数）。**行为等价
   可证**：`.automatic` 解析 = 旧逻辑逐语义复刻（v9 ⇔ macOS 27+ ∧ 文件探针含 v9）；
   public `decode(url:)` 调用点零改动（默认参数编译级保证）。AC#8 的「既有语句不改」
   在 public 缝面上成立；内部重构在 KD-4 授权范围内。
5. **D5 aggregate NR 腿走 legacy options key（INIT 载体）**：现代 CIRAWFilter 无
   aggregate NR 属性，唯一载体 = filter INIT 的 options 字典。macOS 27 SDK apinotes
   将 `kCIInputNoiseReductionAmountKey` 改名 `CIRAWFilterOption.noiseReductionAmount`
   （前任草稿用旧拼写编译失败，续班修正）。readback 的 `noiseReductionAmount` 字段
   既有（`RAWTechnicalParams` 实态），该腿 cache key 漂移天然成立。
6. **D6 CIRAWFilter init 改带 options 字典**：空字典 = no-options init 字节等价
   （identity 路径单测钉死）；避免条件性双 init 分支。
7. **D7 identity 零漂移的断言面 = params/hash/JSON 字节三维**：像素面不可用作逐字节
   断言（CIRAW speckle 非确定，GUI-22 在案记录）——identity 契约钉在
   `RAWTechnicalParams` Equatable 相等 + `decodeParamsHash` 相等 + 编码 JSON 键集
   不含新键（pre-M2-3-3 字节形）。
8. **D8 会话级 overrides 载体形态**：`WorkspaceModel.rawDecodeOverrides` 按
   `url.path` 键控；identity 写入即删键（零冗余）；`closeEditor()` 全清（KD-4
   关图丢弃）；RawDecodePanelView 每次 commit 重发 `EditorState.load`（checker E2
   单一请求链）。持久化 = M2-4 节点模型 schema（挂账，见下）。
9. **D9 T4 草稿救援 4 处**（前任中断在制品的编译级修复，`921a98f` 内）：
   ① 废弃 key 拼写 → `CIRAWFilterOption.noiseReductionAmount`；② Picker 漏
   `selection:`；③ `resolveDecoderVersion`/`applyOverrides` 提 public + `RAWTechnicalParams`
   加 Equatable（测试惯例 = public 面、无 @testable，`RAWDecoderTests` 头注先例）；
   ④ 一处 MARK 注释恢复（diff 纯增量保持）。
10. **D10 测试计数 +30 = 预估带（25..35）上沿**：routing 9 + scope 7 + rawdecode 5 +
    settings 9 = 30；2130（M2-3-2 终值）→ 2160 终值，14 skip 不变，0 fail。
11. **D11 Keyboard 页 v1 恢复按钮条件可见**：override 存储面已建（M2-x 重映射工作的
    唯一存储契约），但 v1 无写 UI → `hasKeyboardOverrides` 恒 false → 恢复按钮隐藏
    （零假开关纪律；按钮出现即代表真有可恢复状态）。
12. **D12 Settings 窗口宽度**：480pt Form → NavigationSplitView `minWidth: 640`/
    `minHeight: 420`（左列表 190pt + 详情区；Alcedo SettingDialog 形态）。

## M2-4+ 挂账

- **Decode overrides 持久化**：会话级 → sidecar/项目包（KD-4 明确非目标；M2-4 节点
  模型 schema 扩展承载）。
- **RAWDemosaic 算法菜单/高光重建**：CIRAW 路线不可达（STACK.md Decoder 策略对比节），
  不入对标范围（非本 plan 产出，登记防丢）。

## 性能观察项（P4 T2 清单接账，只登记不阻塞）

- ① 示波器拖累 PREVIEW 帧率与否（后备 = 采样半分辨率 ROI，方案记 DECISIONS 不砍波形）。
- ② 左轨「工具轨窄列 + 竖向胶片条」并存宽度观感（用户裁决点）。
- ③ zh 文案补录：本 plan 新键族（`editor_*` / `rawdecode_*` / `settings_page_*` /
  `settings_*` 新页族）= P4 对账批（OQ-9 A 先例）。

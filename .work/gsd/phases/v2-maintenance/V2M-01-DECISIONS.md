# V2M-01 DECISIONS（波 1 缺陷修复批裁定记录，2026-10-15/16 夜间批）

> 执行批：T1→T6 串行全落地；五 commit 链 =
> `54124c7e`（T1）/ `5567b56c`（T2）/ `83f48bbb`（T3）/ `e74be37b`（T4）/
> `8133726e`（T5）。基线 = `7b252db1`。红线族机检全过（SUMMARY §五）。

## D-1 三分裁定（T1 action 4）

- **ColorMatchPanelModel**：同病同修——快照化（`snapshotParams`/`snapshotRecord`
  存储属性）+ `updateInstance` 钩子兑现（:54 doc comment 许诺而实现缺席，
  planner 亲核成立）+ 四刷新点（init / view `.onChange(of: instance)` seam /
  solve 回填 `refreshSnapshotFromChain` / `commitStrengthDrag` 尾）。
- **Film/Drt 孪生 = 三分之「健康」，两文件零 diff**：读码裁定——
  `FilmPanelModel.record` / `DrtPanelModel.record` 的 binding get 穿读
  `editorState.history.effectiveFilm/DrtRecord()`（history items 已物化值记录
  的数组尾扫，**零 JSONDecoder**）+ workspace carrier 字典查（零解码）；与
  ColorMatch 的「每读 instances 线性扫 + 每读 JSONDecoder」不同构。D-1 sample
  栈 84/84 flush 叶子 = ColorMatchPanelModel.params.getter 独占，无 Film/Drt
  叶子。按 plan「仅热读无重解码 → 无实测证据不预防性重写」登记，不改。
- **C-1 落实**：`.onChange(of: instance)` 挂在 `content(_ model:)` 非 nil 作用
  域（view 级，provider 值工厂零触）。
- **C-2 落实**：刷新点④择「live 值臂」（commit 尾采纳末次 live 值 = commit
  payload 本体；record 重读臂在 commit 异步落地前会取到拖前值）。理由 = 竞争
  窗内读面连续性；onChange 终态兜底不受扰。已在代码注释+单测
  `testLiveWindowOverridesTheSnapshotUntilCommit` 钉死。
- **E-1 覆盖面**：checker 穷举五路径（切换/commit 重渲/MCP 外部写/undo-redo
  rebuild/面板复现 init）全部由 `.onChange(of: instance)` seam 覆盖，未发现
  第六路径（与 CHECKER §二 E-1 结论一致）。

## D-2 修法三选裁定（T2 action 2）

- **裁定 = H-Aa 三选中的「automatic 收紧」**：`resolveDecoderVersion` 的
  `.automatic` 臂恒回 `.version8`；v9 只经显式 `.forceV9` 可达。
- **bisect 证据链**（正本 = `evidence/V2M-01/d2-bisect/TRANSCRIPT.md`，local-only）：
  ①基线复现（同机身供件 ILCE-7RM5；原 5G4A DNG 不在盘，按 plan 同机身替代）→
  ②③sidecar 切断/新位导入吸收成立（首开即毒，无 sidecar）→ **④解码探针**：
  unmanaged 渲染 v9≈v8 像素近同且平衡（H-Aa 原形「解码本身毒」证伪）；
  **working-space 腿（CIContextPool 形态）v9 输出 linMeans G/R≈3.9（毒）而
  v8 输出同转换 G/R≈1.06（净）**；对照文件（他 Sony 机身 v8）同 P3 标签转换
  中性 → 毒化腿 = **CI 色管理转换 × v9 CoreML 输出**，非解码、非文件、非
  P3 标签本身 → ⑤不适用（v8 已净）⑥被探针升级替代（毒化在转换即坐实）
  → ⑦Preview.app（同 OS Apple RAW 栈）同文件正常（交叉证人；Alcedo 证人
  跳过 = 项目导入深 GUI，成本超收益，Preview 与缺陷链同栈更贴）。
- **三选取舍理由**：机制对全部 v9 能力文件同构，「已验证好机身」白名单无从
  建立（beta 名单逐季扩张）；解码后通道健全性门无法区分「夜景绿树」与毒化
  （双向假阳假阴）；automatic 收紧 = 纯函数缝（M2-3-3 T4 declared seam）
  零 .metal 零红线，UI 零改（automatic 标签即 "Default"）。
- **正例对照**：修前 WS(automatic) spread 0.742（>0.5 断言界应红）；修后
  0.062（绿）。回归钉 = 供件级
  `testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace`
  （`input/RAW/GREENCAST-7RM5.ARW` untracked 域，缺席 XCTSkip）+ 矩阵更新
  （`testResolveDecoderVersionMatrix` automatic 三臂全 v8）+ `testRAW9OptIn`
  重钉（默认 v8 + 显式 forceV9 腿仍达 v9）。
- **遗留面申报**：forceV9 显式档在本机（7RM5）仍产出毒化平面——用户显式
  行为、面板有 readout/downgrade 提示，不改；重入口条件 = 探针 WS 腿对
  v9 能力机身转中性后恢复 opt-in（TRANSCRIPT 重启条件节）。既往 automatic
  文档重载后 used=v8，decodeParamsHash 一次性漂移（D-H4 drift face，
  重渲非数据损失）。

## D-3 钉序形态（T3）

- **收敛单一换图通道**：grid onChange 与 filmstrip onOpen 两腿并入
  `switchCurrent(to:)`（phase guard + `openCurrent` + 单 phase 写，幂等）。
- **真竞态封闭**：`loadCurrentImage` 原 await 后无取消检查点——被 `.task(id:)`
  重启超替的旧任务可恢复并写陈旧 `versionCoordinator.projection` +
  发陈旧 `EditorState.load`（点击不换图的真实机制类）；每个 await 后补
  `Task.isCancelled` dead-drop。
- **先例对照**：omp-02「末图锁定」与本批观察的"未换"复现 = **A/B 字节相同
  副本**（cmp 亲证）——切换成功但像素相同，观感假象；真 stuck 类 = 上述
  竞态，已结构性封闭。
- **ΔN = 0 记账**：换图序判定为 SwiftUI 视图级行为（onChange/task seam），
  不可纯函数化；FilmstripModelTests 既有 6 法全绿。加固循环证据见 GUI
  MANIFEST V2M-D3-01（Blocked-Env——通道受堵，机制论证代偿）。

## D-4 机制定案（T4）

- **前置走查受阻**（AX harness 多选通道不可用——cmd+click 旗标不生效，
  m6-closeout 批注同款；Edit>全选未达 browser model）。机制定案按代码事实链：
  标题串创建时点 `pendingTargets.count == 0`（zh 查表成功、值为 0）而 START
  按钮点击时读同 @State 得正确 targets → **首渲消费 pre-arm 呈现快照**
  （M-1 两候选中的「呈现时点陈旧快照」族表现）。
- **主修形态 = `.sheet(item:)` payload**（两候选下都鲁棒形）：三个计数承载
  对话框（focus_stack/stack_denoise/hdr_merge）arm 点构造 `MergeDialogCount`
  随 item 进入内容闭包——计数绑定呈现触发本体，与状态店/呈现快照两机制解耦。
  动作面零改（pendingTargets + start 按钮字节同前）；Mertens/pano 静态体
  保持 isPresented 形。
- **走查 AC 未闭合**（标题计数屏面证据 Blocked-Env）——`.sheet(item:)` 的
  item 即呈现触发值、结构性排除陈旧读；若走查批复验仍见 0 → 按 plan 风险节
  「快照上移」预案返工（一轮损失，不产假交付）。

## D-5 形态复核（T5）

- planner 裁定维持：调用点 `Int((holeFraction * 100).rounded())` 对齐在册
  `%lld` 变体；xcstrings 零改动（目录 en/zh 两值本即整数百分数语义，
  `%lf` 变体会渲染「12.340000%」反劣化）。半分界 = Foundation `.rounded()`
  远离零舍入，DECISIONS 记一句（本条）。RESEARCH §四「补 %lf 变体」翻案
  不行使。V17 绿例措辞：调用点形态 = 函数参数 + `Int(…rounded())` 包装，
  供给面推导 Int → `%lld` 命中（V2M-02 T1 断言面生效时此键 = 绿例活体）。

## 偏差与批外观察清单

1. **T1 刷新点②挂点形**：plan 文本 `{ model.updateInstance(instance) }` 为
   语义形；实现用双参 `{ _, newInstance in model.updateInstance(newInstance) }`
   （macOS 14+ onChange 正形）+ C-1 非 nil 作用域——语义等价，无偏差。
2. **T2 步⑥替代**：管线双臂（terminalTail legacy vs .drt）被 WS 探针升级
   替代（毒化在转换腿坐实后尾段无分析价值）——计划内替代，TRANSCRIPT 记录。
3. **T2 ⑦证人替换**：Alcedo → Preview.app（同 OS RAW 栈，与缺陷链同栈更贴；
   Alcedo 需项目导入深 GUI）。TRANSCRIPT 申报。
4. **T2 测试域**：`testRAW9OptIn`/`testRAW9FallbackForUnsupportedCamera`
   （RAWDecoderTests）随语义更新——plan files_modified 未列 RAWDecoderTests
   （只列 RawDecodeOverridesTests）；两文件同归 IOP bundle，零 Project.swift
   触碰，属同缝修正申报。
5. **GUI 走查四项 Blocked-Env**（D-1 三零/D-3 循环/D-4 标题/D-5 toast）：
   通道受堵诊断 = `gui-acceptance/v2m/MANIFEST.md`；不硬造判定。批外疑点
   两笔（项目面 colormatch 面板 hasImage=nil 异常；导入进度停滞 Registered-obs）
   原样上报，未动手（批外窗口）。
6. **IOP GrainTests 单 flake**：全套前置定向轮 687/5/1（`testSameParams
   DifferentImagesDiffer` diff=0 ≤768 门）——同码 T2 轮全绿 + 单类复测 8/0/0
   绿 + 本批 diff 窗口不含 grain/seed/identity 面 → GPU 状态序漂移 flake
   （M2-7-3 重测顺序漂移先例族）。处置 = 留证（/tmp/la-direct-tests-IOP.log
   当轮快照）+ 全套净轮取值；全套若复现同签名再升级归因。

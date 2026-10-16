# M7-4-01 PLAN REVIEW — 独立 plan 评审（替代 omp 路，零共享上下文）

```
phase:        m7-4-mcp-o4
reviewee:     M7-4-01-PLAN.md（HEAD fe1e7dbf；plan 引用基线 0b34d199 与 fe1e7dbf 间为
              plan 自身 docs commit，代码零漂移——坐标核验有效）
reviewer:     独立评审 subagent（ZCode；2026-10-13/17）
method:       PLAN/CONTEXT/RESEARCH 三文档通读 + 代码面逐点亲验（S1 poll 体 / S2 装配
              点 / O4 四层 / UQ-A2 两腿 / match_color 锚 / union fresh 坐标 / 计数钉
              全量 grep 扫描 / sidecar 投影层 / HistoryHash 折叠面 / seed 参数流）
verdict:      须修后放行（1 blocking + 3 major + 2 medium + 6 low/info；
              修法全部落在 plan 文本与 SC 措辞，一处需红线条款修订，一处需
              CONTEXT D-M7-4-7/D-M7-4-8 联动修订）
```

## Findings 总表

| # | 严重度 | 任务面 | 一句话 |
|---|---|---|---|
| F1 | **BLOCKING** | T3/T6 | note/author 持久化面缺失：`SidecarHistoryItemRecord` 字段镜像不在 files_modified，且被「LightamerSidecar 类型/schemaVersion 零 diff」红线明文禁止——feature 依现 plan 落地即死脸 |
| F2 | **MAJOR** | T1 | 忙旋消解机理错误：`poll(250)` 超时形对恒可读 fd 无速率限制（poll 就绪即返，超时只封阻塞相），「退化 4Hz」断言为假且将写进 DECISIONS 校订注记 |
| F3 | **MAJOR** | T6 | union 外五计数钉 21→22 算术错误：五钉全部计 editing+culling 面（7+14=21），editing 7→9 后应为 **23**——M7-3 评审 H1 家族复发 |
| F4 | **MAJOR** | T4 | exclusive 臂未处理 encodeStage catch 清理腿（:724 `removeItem(at: destination)`）：encoder 中途 throw 会删掉本特性要保护的目的文件 |
| F5 | MEDIUM | T2 | 预热装配点漏第四宿主面 `startReadOnlyHTTPHost`（:652-708，--project heldByOther 只读 http 臂同样服 list_luts）；SC「恰 3 装配点」把缺口机检固化 |
| F6 | MEDIUM | T2/T5 | plan 内锚坐标漂移：「startHeadlessStdioHost :524 段 / startHTTPHost :754 段」与 HEAD 不符（真身 :714-754 / :952；:754 恰是 stdio 宿主收尾括号）；与 plan 自我申报的「fresh 坐标已亲核」相悖 |
| F7 | LOW | T3 | per-target `rejected(reason)` 的 reason 源未定义：compose/claim 失败行的 `BatchApplyOutcome.failedRelPaths` 无 typed reason |
| F8 | LOW | T3 | get_history 顶层 author「position 位 item（最新 kept item）」二义：截断（suffix kept）红尾态下两者不是同一 item |
| F9 | LOW | T3 | note 同名二义：document 级 metadata note（append_note/get_history 顶层）vs HistoryItem.note（本波新 per-item）——agent 面无区分说明 |
| F10 | LOW | T3 | paste targets 重复项未处理（同 relPath 两次 = 双 compose/claim/write + 应答重复行） |
| F11 | LOW | T3 | copy/paste source 为 GUI-live 图时读盘 sidecar（≤2s debounce 滞后）——target 有 live 硬拒、source 无对称处理，姿势未申报 |
| F12 | INFO | T3 | SC hunk 清单漏透传链两签名：`commitPaste`（HistoryStack.swift）与 `composeSegment`（SessionBatchApplier.swift）也须加默认参 |
| F13 | INFO | T4 | link() 在 exFAT 等不支持硬链接的卷上 EOPNOTSUPP → internalError：.fail 档在部分外置卷（本工作区自身在 /Volumes/UNITEK）从「可导出」翻为「渲染后必败」——plan 风险节已申报但「皆本地卷」论据与实情有隙 |
| F14 | INFO | T2 | 预热在测试语境的副作用未评估：e2e/仲裁 spawn 的真宿主每进程 50s .utility 解析 + 向真实用户 LUT 根 seeding；套件噪音与变慢风险待申报 |

---

## Findings 详述（证据 + 修法）

### F1（BLOCKING）note/author 持久化面缺失 + 红线自相矛盾

**证据**（代码亲验）：

- `LightamerCore/Sources/Sidecar/LightamerSidecar.swift :799-871`：`SidecarHistoryItemRecord` 是 HistoryItem 的**逐字段镜像投影**——自带 `Keys` 枚举（:801-805，九键与 HistoryItem.CodingKeys 平行）、自带 `init(_:)`（:831-841）、自带 decode/encode（:843-870）、自带 `item` 重建（:807-816）。HistoryItem 的 runtime Codable **不是** sidecar 的编码路径（HistoryStack.swift :57-60 头注明言「the sidecar projects through `SidecarHistoryItemRecord`」）。
- 因此 plan T3 只改 `HistoryStack.swift`（HistoryItem additive 两字段）时：note/author **永不落盘**（镜像 init 不携带）、**永不可读回**（镜像 `item` 重建不还原）。
- 消费方全在镜像下游：get_history 读 `document.history`（= `SidecarHistoryRecord.stack` → `items.map(\.item)`）；T6 自家的「sidecar 字节 roundtrip + 旧档 tolerant 负测」golden 也过此层——**T6 测试批才爆炸**（晚暴露一轮），且届时唯一修法 = 改 `LightamerSidecar.swift`，恰被 red_lines[2]「LightamerSidecar 类型/schemaVersion 零 diff」明文禁止（该红线**无申报内例外**子句——对比同表 encodeStage 有「申报内例外」 carve-out，证明无例外为笔误非设计）。
- plan 自引的「drtRecord/filmRecord 同族先例」恰恰**包含**镜像与 bump：AGENTS M3-3 节原文「sidecar v9（filmRecord 字段 + HistoryItem.filmRecord **镜像**）」；git 实证 v7=versions（950668a4）/ v8=ai provenance（a2a8612f）/ v9=film record + history additive plane（7e5b3082）/ v10=process（3be89a19）——近年每次同族添加都 bump。

**修法**（三件，同批）：

1. red_lines[2] 改为「LightamerSidecar 类型零 diff **除 `SidecarHistoryItemRecord` 恰 additive 两字段**（note/author，encodeIfPresent/decodeIfPresent + nil 不编码——filmRecord :826-829 同族镜像形；schemaVersion 裁决见下）」。
2. files_modified 补 `LightamerCore/Sources/Sidecar/LightamerSidecar.swift` 行（T3）；T3 SC 与 checker 关注点 6 补该文件 hunk 级判据（恰两字段 + init 镜像 + decode/encodeIfPresent）。
3. schemaVersion 显式裁决（DECISIONS 申报，二选一）：(a) bump 10→11（同族惯例，v9 film 先例形）；或 (b) 维持 10 不 bump（additive optional 双向 tolerant、无语义重释——须写明偏离惯例理由）。不可含糊。

### F2（MAJOR）T1 忙旋消解机理错误：250ms 超时形对恒可读 fd 无效

**证据**：

- 病灶认定正确（McpServerController.swift :396-398：`events: 0` + `poll(&fds, 1, -1)` 实测永不醒）——**修法第①点（`events: POLLIN`）与第③点分流（HUP → break → close+exit(0)）本身成立**，主目标（HUP 唤醒）不受影响。
- 但第②点的机理断言为假：`poll(2)` 的 timeout 只封**阻塞相**上界；fd 已就绪（/dev/null 恒返 POLLIN，research §2.2 自家实证「poll(-1) 立即醒」）时 `poll(&fds, 1, 250)` **照样立即返回**（count=1, revents=POLLIN）。plan T1 action ③ 的 else 臂（「count == 0（超时）或纯 POLLIN → 只清 revents 续 poll」）**无 sleep** → /dev/null 上仍是 syscall 速率热旋。「恒可读 fd 退化 4Hz .utility 低频循环（忙旋消解）」（plan T1 action ②、风险节、CONTEXT D-M7-4-7、research §2.2）为**假命题**；且 T1 action 4 要把「有 dup2 + 250ms bounded re-poll = 4Hz 循环不自噬不忙旋」写进 DECISIONS 校订注记——假机理将**沉淀进台账**。
- 更糟：red line「S1 修复语义钉：恰三点改形」把执行者锁死在此形态——按 plan 加 sleep 反而构成「第四点改形」违约。OQ-7 否决的备选乙（「-1 阻塞 + 测试面接受自旋」）被以「卫生差」为由拒绝，而现 plan 形态在恒可读 fd 上的实际行为**就是乙**（还白付 idle 态 4Hz 唤醒成本）。

**修法**（二选一，均需改 plan action/SC + CONTEXT D-M7-4-7 联动）：

- **甲（推荐）**：分流分支内速率限制——纯 POLLIN（非 HUP/非超时）臂 sleep 250ms（`usleep`/`Thread.sleep`）再续 poll；250ms 超时可保留（无害）或回 `-1`（idle 全阻塞零唤醒，严格更优：idle 零唤醒 + 数据态 4Hz 帽 + HUP 照旧即时）。作为第③点分支体的组成部分申报（不算第四语义点）。
- **乙**：诚实改判——接受自旋（= 乙方案行为），删全部「忙旋消解/4Hz」措辞，D-M7-4-7 重写为「POLLIN + 分流 + 接受恒可读 fd 自旋（.utility、测试语境短生命周期）」。
- 无论甲乙：SC grep 判据同步（甲 = 增 `usleep|sleep` 分支在位判据；乙 = 删「忙旋消解」句）；T1 action 4 的 DECISIONS 注记措辞按选定形改写。

### F3（MAJOR）union 外五计数钉 21→22 算术错误（应为 23）

**证据**（五钉语境全量亲验）：

- `McpRegistrySnapshotTests :196-206`：断言对象 = `makeRegistry(editing:culling:)` 双域面，message 自述「the editing+culling closed face is exactly 21 tools」= **7+14**。
- `McpSearchStateToolsetTests :274`（同双域装配）、`McpHostTests :243/:697`（spawn 宿主全脸 = 21）、`McpLauncherTests :200`（同双域）——五钉全部同族。
- plan 自家 T6 action 2 写明「copy/paste 两行加入（editing **7→9**）」→ 双域面 = 9+14 = **23**，非 22。22 的由来疑为按「+1」惯性套写（单工具先例 list_luts 6→7 的肌肉记忆）。
- 后果：按 plan 执行（钉改 22）→ T6/T7 五法齐红（实际 23）→ 回注一轮 churn；或执行者自行纠偏 = plan SC 与实际 diff 不符。M7-3 评审 H1（计数钉漏列/算错）家族复发。
- plan 的残漏 grep（`count, 21`/`count == 21`/`all27` 零命中）能在执行期兜住目标值错（改 22 后 grep 干净但测试红）——但 SC 文本须先改对。

**修法**：plan T6 action 2/3、T6 SC、checker 关注点 3 全部 21→22 改 **21→23**；message 句式不变。

### F4（MAJOR）T4 exclusive 臂漏 encoder-error 清理腿的改道（现形会删保护对象）

**证据**：

- `ExportRenderer.swift :714-726`：encoder throw 路径执行 `try? FileManager.default.removeItem(at: destination)`（对**最终 destination**）——现语义正确（throw 只可能留 stray tmp，destination 若存在必是本 job 自己的产物前身）。
- exclusive 臂下 destination 可能是**他进程在 TOCTOU 窗内建的同名文件**——encoder throw（如位深不支持、编码器内部错误）时该清理腿会**删掉他进程的文件** = 本特性要防的事故经错误路径复现。
- plan T4 action 1 只写「tmp/link/defer 段 + post-encode 两腿喂 tmp」，未提此清理腿；SC 的 hunk 核清单（「恰签名尾追 + tmp/link/defer 段 + gain-map wrap 段」）同样漏列——checker 会放行一个正确的 SC 面下的错误实现。
- 附带：TOCTOU 负测（§4.3 腿①）走的是 link() EEXIST 正常路径，**不覆盖** encoder-throw 交错。

**修法**：T4 action 1 追加一点——exclusiveFinalWrite=true 时 catch 清理腿改道 tmp（或整腿跳过，defer 已拥有 tmp 清理）；SC 追加 hunk 判据（清理腿在 exclusive 臂下不再触 destination）；T6/T4 测试批建议加第五腿（强制 encoder 失败 + 预植 destination 字节不变断言）。

### F5（MEDIUM）T2 预热漏第四宿主面 startReadOnlyHTTPHost

**证据**：`McpServerController.swift :652-708`——`startReadOnlyHTTPHost` 为独立宿主启动函数（:598 由 `runHeadlessArbitrated` 的 heldByOther 只读臂调用），:658-664 装配完整 editing 域（list_luts 在册）。plan 预热三点（startHeadlessStdioHost/startHTTPHost/GUI）不含此面 → **只读臂 agent 首调 list_luts 仍 50s** = S2 挂账②的痛点原样保留在该臂；SC「恰 3 装配点」将缺口机检固化。GUI embed 经 `startEmbeddedServer → startHTTPHost`（:1083）被第二点传递覆盖（LightamerApp 第三点冗余但无害——preference off 时守卫早退，第三点为 LUT 面板收益，可留）。

**修法**：预热改四装配点（+`startReadOnlyHTTPHost` 段——仍在 McpServerController.swift 单文件内，T2 恰四文件 SC 不破）；或上提至 `runHeadless`/`runHeadlessArbitrated` 层一次覆盖全部无头臂（SC 随形改）；SC grep 与 CONTEXT D-M7-4-8「3 点」措辞联动修订。

### F6（MEDIUM）T2 锚坐标漂移（plan 自我申报「fresh 已亲核」下的硬伤）

**证据**：plan T2 action 1 写「`startHeadlessStdioHost`（:524 段宿主启动处）/ `startHTTPHost`（:754 段）」——HEAD 实况：`startHeadlessStdioHost` 定义 :714-754、`startHTTPHost` :952 起；:524 落在 `runHeadless` 体内、:754 恰是 stdio 宿主的收尾括号。read_first 引的 `LutLibraryStore.swift :103-120`（holder 实为 :103-138 段内，可接受）与 T5 的 LightamerApp「:1371」（return 行实为 :1369，:1371 为闭括号——范围引用可容忍，单点引用不准）。plan 头注与研究/CONTEXT 均宣称「file:line 逐点亲核复核吻合」，此三处为反例。

**修法**：plan T2 两锚改 :714 / :952；T5 的 :1371 改 :1369（或一律改区间引用）。零风险文本修订。

### F7（LOW）rejected(reason) 的 reason 源未定义

`SessionBatchApplier.apply` 的失败分账只有裸 relPath 列表（:32-51 `BatchApplyOutcome`；:269-281 claim 回滚 = 全批 failed）——无 typed reason。MCP 应答 `{status: applied|rejected(reason)}` 的 reason 串对 compose 失败行（unreadable sidecar）与 claim 回滚行取什么值，plan 未钉。建议：固定 token（`unreadableSidecar` / `internalError`）+ DECISIONS 钉形；或应答降为 `rejected` 无 reason 细分（诚实够用）。

### F8（LOW）get_history 顶层 author 的截断二义

截断保 suffix（:855-859），红尾态（position 落在 kept 窗之下，:806-810 注记）下「position 位 item」≠「最新 kept item」——plan/CONTEXT 两处把二者括注等同。建议钉死实现式：`stack.position >= 0 ? stack.items[stack.position].author : .null`（真 position item，与截断无关），括注改「无截断时即最新 kept item」。

### F9（LOW）note 同名二义（document 级 vs item 级）

`append_note` 写 document.note（get_history 顶层 `note` 键 :895）；本波 `apply_params(note:)`/`paste_adjustments(note:)` 写 HistoryItem.note（per-item `note` 键）。同名异层，agent 侧无说明易混。建议：两新工具 description 各加一句（item-level edit note, distinct from the document-level note set via append_note），或 DECISIONS 注记申报不处理。

### F10（LOW）targets 重复项

同 relPath 双传 = composeSegment 循环处理两次 + claim 两条同键 + 应答重复行。建议 pre-check 去重（Set 收敛 + 应答单行）或 invalidParams 拒绝重复（一行 guard）。plan 未提；不阻塞。

### F11（LOW）live source 的 ≤2s 读盘滞后

copy/paste source = GUI 正在编辑的图时走盘上 sidecar（2s debounce，可能滞后于 live 态）；target 侧有 live 硬拒、source 侧无对称面。姿势与 GUI Copy Adjustments 现状一致（dialog 同读盘），可接受，但建议 DECISIONS 一句申报（或对 live source 同发 typed 拒）。

### F12（INFO）T3 SC hunk 清单漏透传链签名

note/author 到 HistoryItem 的链 = `apply` → `composeSegment` → `paste` → `commitPaste` → `HistoryItem.init`。后两者签名扩展未进 SC 的 hunk 核清单（「恰两字段 + init 默认参 + CodingKeys 两 case」）。可行无疑，清单补全即可。

### F13（INFO）exFAT 卷 link() 支持面

风险节已申报「不做特殊分支」，但论据「本项目导出目录皆本地卷」有隙：本工作区自身在 /Volumes/UNITEK 外置盘，用户导出目标常见外置卷；exFAT 无硬链接 → .fail 档从「可导出」翻「渲染满成本后 internalError」。建议：DECISIONS 注记该行为变化 + （可选后续）EOPNOTSUPP/ENOSYS 降级回 plain rename 并 log（FAIL 保证退化为快照门——须显式申报，勿静默）。

### F14（INFO）预热入测试语境的副作用

T2 落地后每个 spawn 真宿主的测试（仲裁套件 + T1 e2e）每进程付 ~50s .utility 解析 + 对真实用户 LUT 根 seeding（幂等哨兵）；e2e 的 ≤12s 窗内预热与断言并发抢 CPU。建议：DECISIONS 申报观察项；可选 env 门（如 `LIGHTAMER_SKIP_LUT_PREHEAT`）留作执行期权衡，非本波必做。

---

## 评审维度逐项结论

1. **T1 S1 修复**：病灶/落点/四语义零改面亲验成立（:388-408 函数体、once guard :391-394/:410-413、M1 自守卫 :390、close+exit(0) :405-406、http 不 arm）；断连检测延迟上界 = HUP 即时唤醒（250ms 粒度只影响 idle 轮询，12s 活性窗无扰，plan 判断正确）；e2e 断言可观测性设计好（≤12s + wal==0 双正面证）。**但忙旋机理为假（F2）**；「修后优雅面首真」措辞波及面核对：挂账⑥/H3③/特殊事项 5 三处 + M7-3 签核文档不回改纪律齐备（CONTEXT 顺路件表 + T1 action 4 + T7 DECISIONS 三处落点闭环）——唯注记文本须按 F2 修法改写。
2. **T2 S2 A+C**：预热机理成立（`shared` getter :112-116 触发 `sharedInstance` 惰性 once-init = 50s 全库解析；并发首调经锁串行，语义与 plan 描述一致）；**装配点清单漏第四宿主面（F5）**；锚坐标漂移（F6）；预热与 M6-1 锁交互核 = 无涉（seedBuiltIns 写用户级 LUT 根非项目锁面，时机前移不改性）；测试语境副作用未申报（F14）；C 文案落点核 = `mcp_tool_desc_list_luts` 在 xcstrings :32586 在位，原位值改 + DECISIONS 申报形齐备；McpTimeouts 零 diff 可行（applyBatch 60s :220 既有档消费）。S3 正臂腿可行性亲验成立（stub :444-452 heldTargets 形 + 差分谓词 :474 + makePackage 不开真锁 → pre-check 通过、diff 臂可达）。
3. **T3 O4**：链四层现成性亲验成立（谓词单源 :35-38 + enumerate :241-265 + pastePayload :302-324 纯化抽取可行；paste :86-95 overwrite/epoch/UUID recast；apply 三段 :232-296 compose 零渲染 + claim 单事务 + 写队）；apply_params 全框 :591-685 同构可拼；seed 参数流核 = GUI 批贴 `seedInstances()`（LightamerApp :2510）vs MCP apply_params/match_color 传 `[]`（payload 已含全投影）——plan paste 用「editingSeed 同源」与 GUI 批面对齐，**正确**。paste 批量原子性 = compose 段 per-target 分账 + claim 全有全无 + 写队逐 target 原子晋升——中途 invalid 的行为面已由既有结构覆盖，唯 reason 映射未钉（F7）。live 硬拒与 search_photos 衔接成立（seams.liveImageURL 判 :605-608 先例）。**但持久化面缺失为 blocking（F1）**；SC hunk 清单欠两签名（F12）；F8/F9/F10/F11 见上。
4. **T4 UQ-A2**：TOCTOU 窗认定与修法框架成立（encodeStage :659-672 签名尾追可行；gain-map 臂 :680-702 早退面 + post-encode 跳过 :693-698 亲证「直包即可」；MPF 偏移 = 文件内相对偏移，link()/rename 保内容逐字节 → 无偏移问题——评审问点的答案是否定的）；同目录 tmp = 同卷 → EXDEV 构造性消解成立；queue 递缝成立（render 腿 wrap :489-493 + encode 腿 :521-528 + encodeLeg 读点 :720 同族；leg 闭包签名 :700 冻结面零 diff 可行）；TOCTOU 负测确定性交错（render 后手工建文件 → 快照门已过、encode exclusive 拒）设计成立。**但清理腿漏改道为 major（F4）**；exFAT 面见 F13。
5. **T6 union**：fresh 坐标全部抽验吻合（:20 头注 / :219 all27 / :244 测试名 / :249-250 计数 / :255-260 destructive 9 件集 / :299 / :327 / :334 descriptionKeys / :479 / 五外钉 :203/:274/:243/:697/:200）——**唯目标值 22 错、应 23（F3）**；destructive 9→10 断言正确；GUI 面（historyRow :201-235 note 副标题 + author 徽章）落点可行、与 get_history author 读面翻转自洽（pristine .null 两端一致）；残漏 grep 设计好但须配 F3 修正后的目标值。
6. **SC/ΔN/红线**：SC 可机检性总体高（grep/diff 面核/bundle 对账齐）；ΔN 带 +21..28 与逐任务记账一致（典型 23）；files_modified 与红线族交集核出 **F1 矛盾**（唯一 blocker）+ ProjectToolset.swift 头注「= the 27 union」注释不在残漏清扫清单内（清单外文件注释陈旧，建议清扫范围改全仓）；F12 清单补全。
7. **独立猎残**：F4（现 plan 下 checker 不可见的错误路径覆盖缺失）与 F2（假机理沉淀台账）为本评审新增的最高价值发现；其余 F13/F14 为申报完整性建议。

## 与先例教训的对照

- **M7-3 H1（计数钉漏列/算错）**：F3 直接复发（22 vs 23）——本次靠五钉语境全量亲验捕获。
- **M7-3 H2（锚捕获）/H4（谓词逻辑洞）**：本波无同形发现；F2 属同族方法论（机制断言未经语义推演——poll 就绪语义未推演即写结论）。
- **E-2（golden 失明）**：F1 为典型潜在形（sidecar 镜像缺失在 T6 golden 才爆）——本评审在 plan 期捕获，成本最低。
- **M2-7-3 parentage / L041 / L057**：plan 登记纪律与 L057 禁令条款齐备，无发现。

## 总评（verdict）

**须修后放行。** Plan 骨架（任务序/红线/快照取权/单源纪律/测试策略/T7 收口）质量高，绝大部分 file:line 与机制链亲验吻合；但 **F1 为 blocking**（不修则 MCP2-09 落地即死脸且与红线冲突、执行中期必然停摆归因），F2/F3/F4 三处 major 会在执行中后期以测试红/错误实现放行两种坏方式兑现。五项修订全部为 plan/CONTEXT 文本与 SC 措辞级（无一行产线设计翻案——S1 修法形态微调为唯一代码面变化，幅度 1-3 行）。修订后本 plan 可进入执行；建议修订批与 M7-4-01 同 commit 体系落盘（PLAN/CONTEXT/RESEARCH 联动处逐处改，历史 research 正文按惯例不改、以 CONTEXT D 条修订为准）。

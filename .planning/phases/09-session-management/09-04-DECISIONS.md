# Plan 09-04 — 执行决策(DECISIONS)

> 执行期决策边界(09-CONTEXT specifics):RESEARCH 未覆盖/公式与现表冲突的实现细节在此登记。
> 编号 D1..D11 按产生顺序;全部为 09-04 范围内决策(标注可逆性)。

## D1:skip 集 decode 域边界 = `< ashift 15.0`(plan 公式修正)
plan 公式「V50Order < colorin 28.0」对 verbatim v50 表**不可字面执行**:exposure(21.0)、
toneequal(24.0)、crop(24.5)、flip(16.0)、liquify(18.0) 都在 colorin 之前(dt 场景参照
设计使然),字面执行 = 复制粘贴的核心载荷全部被禁,与同 plan 验收行「创意域保留」自相
矛盾。dt 正本规则是 **flag 制**(`dt_history_module_skip_copy` = history.h:107-110,
`DEPRECATED|UNSAFE_COPY|HIDDEN`),exposure 照拷。Lightamer IOPFlags 尚无该三类,故
decode 域 = 有序段「strictly < 15.0(ashift)」:rawprepare/temperature/highlights/
demosaic/denoiseprofile/lens/cacorrectrgb/hazeremoval 等**传感器/镜头锚定值**永不跨图;
ashift(15.0) 起(含 exposure/toneequal/crop/…)可拷。测试 `testCopyKeepsTheSceneRe
ferredCreativeBand`/`testCopyKeepsAshiftAtTheBoundaryWhenModified` 钉边界。
Reversibility: 高(单常量 + 显式注释;升级为 flag 制时平移)。

## D2:恒等默认比对 = (opName, multiPriority) + paramsData + enabled(multiName 不比)
dt 比的是 params 与 default_params 的 memcmp(不看 multi_name)。改名不改参 = 未修改
→ 跳过(载荷不膨胀);测试钉「renamed-but-unmodified stays excluded」。
Reversibility: 高(纯函数)。

## D3:paste 落栈形态 = 单条 paste commit + 两型标记(HistoryItem 加 `pasteSet`)
验收硬门「单图 ⌘Z 恰 1 撤销本次 paste(commit 计数 + 还原逐字节)」在既有 commit()
语义下只有两条路:每实例一 commit(⌘Z 一步只退一条,违门)或**一条 commit 携带整份
载荷**。选择后者 = HistoryItem 增 additive optional `pasteSet: [ModuleInstance]?`
(decodeIfPresent/encodeIfPresent——06-01 stackSnapshot 同款先例,旧档解码不变,
ONE-WAY 兼容)。两型:**merge** paste(layerScope = nil,普通全局项,投影贡献全部
pasteSet 记录);**overwrite** paste(layerScope = `pasteEpochScope` 标记,全局投影
= EPOCH——只取其 pasteSet,更老项为死状态)。`snapshot` 槽位仍存首记录(非可选字段
不变),投影走 `pasteRecords`(pasteSet ?? [snapshot])。**overwrite 追加在未动栈上
而非替换栈**:前向 = payload 精确(dt DELETE+INSERT 可观测语义);⌘Z = 指针落到
epoch 之下 → 旧投影逐字节还原;redo 前向再证。首版「栈替换(items=[pasteItem])」
使 ⌘Z 无处可退(测试抓出),已按追加形修正。
Reversibility: 中(additive 字段为格式增量,如需回退 = 停写该字段,旧档不受影响)。

## D4:merge v1 不并层结构(全局实例 only)
payload.layerStack 仅 overwrite 整体安装(含「源无层 → 目标层清空」的精确重复语义);
merge 保持目标层栈不变(层结构合并 = 结构级 diff + 蒙版迁移,超 plan 词义)。执行期
记录,层合并 defer。
Reversibility: 高(v2 可加,不影响格式)。

## D5:段3 串行写队列默认**不聚批**(批量延迟关)
机械盘并发负收益 → 串行钉死;可选聚批延迟(每 64 张/500ms)plan 期留口,实测 SSD
~1600 docs/s(万张 6.2s)且 USB 卷语义为「后台分钟级可接受(dt XMP 同步同为循环外
后置)」,聚批复杂度不换收益——**默认关闭**,不实现延迟参数。禁合并多图进一个文件
(sidecar-per-image 格式锁)照 plan 钉死(测试:12 目标 = 12 个 .lra)。
Reversibility: 高(加参数即可)。

## D6:label 本地化归调用方(Core 无 String Catalog 依赖)
`PasteSemantics.paste(label:)` 由 App 传 `String(localized: "history_paste_adjustments")`;
Core 不引 localization。D(deviation from v1 sketch,记 02-04 同款先例)。

## D7:菜单 ⌘⇧V(无对话框)默认 = **merge**
dt 默认粘贴为 replace(overwrite),但其对象是单图+undo 组;批量场景下一次误点
overwrite 会重写 N 张(sidecar 全换),merge 为加性且每图 ⌘Z 可退——**批量安全优先**。
overwrite 由部分粘贴对话框的 mode picker(合并/覆盖 segmented,dt hist_dialog 同构)
显式提供。记录为执行期决策,如需改默认只动 App 一行。
Reversibility: 高。

## D8:段2 claim SQL = 单 prepared `WHERE path = ?` PK-seek 循环(修 O(n²))
首版按「temp table + `WHERE path IN (SELECT …)`」形态**per-row 重复执行**——SQLite
每次执行全表扫 `images` 再探 temp 表,O(n²),实测 10k = **77.5s(Release)**,且
Debug/Release 重合(77.0/77.5s)→ 算法问题而非优化问题。修复 = 单条 prepared
`WHERE path = ?`(主键 seek)在同一事务内循环 10k 次 → **0.010s(~7700×)**。
「10k 行 = 一个事务」纪律不变。教训入 perf.md:bulk-IN 形态只适用于常量值集**单次**
执行;per-row 值必须 PK seek。
Reversibility: 无需(正确性+性能双修)。

## D9:Release 计量的直启注入签名处置(一次性环境,工程未改)
Release app = hardened runtime,直启注入 libXCTestBundleInject 被 library validation
拒。处置 = `codesign --force --deep --sign "Lightamer Dev"` + entitlements
(`disable-library-validation` + `allow-dyld-environment-variables`)重签 Release 产物;
**每次 Release 重建后需重做**(重签覆盖)。Project.swift 默认未动(DIST-5 hardened
语义保留;此为本地计量通道,非发布产物)。
Reversibility: 高(不落工程)。

## D10:崩溃自愈挂 openSession(非 reconcile)
`healDirtyRows` 挂 9-1 openSession 回填之后(plan 词义「挂 9-1 增量同步」);语义 =
dirty 行逐行重读**磁盘 sidecar** → 可读则覆盖索引列 + dirty=0;不可读/缺失则**保持
dirty**(徽章继续说真话,下次 reconcile 裁决)。reconcile 四时点不重复挂(写侧
journal 已吞自事件,mtime 漂移腿天然覆盖已写盘的 dirty 行)。
Reversibility: 高。

## D11:before/after 状态归口 = BeforeAfterState(D-03b 新态对象)+ HUD 内联
三形态的呈现状态(splitEnabled/splitFraction/peekIndex/isHoldingOriginal)归独立
@Observable 对象(app root @State + environment),**不含任何渲染触发**——取平面 =
视图 `.task(id:)` 经 coordinator override render(D-X1 单生产者不破);hold = 纯
blit 状态翻转(零渲染,counter 断言)。peek 步进标签 1-based(用户口径),状态栏
槽位 StatusBar.comparePoint 增量可选参数。split blit = 同 PSO + fit quad 双绘制
+ 互补 scissor(零新 kernel;fraction 0 = hold 全屏 BEFORE)。
Reversibility: 高(纯 App 层)。

## D12:grid 行模型增 `dirty` 投影 + 「…」徽章(一致性窗口不静默)
09-03 Row 投影加 `dirty: Bool`(claim 窗口徽章数据面),cell 三徽章位加黄「…」;
reload 由批量粘贴收尾驱动(LightamerApp pasteToSelection)。CullingPipelineTests 的
Row 构造同步补参(memberwise init 变更涟漪,2 处)。
Reversibility: 高。

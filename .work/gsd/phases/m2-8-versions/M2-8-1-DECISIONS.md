# M2-8-1 DECISIONS — 执行期裁决与签注

> Plan 悬决销账三件（KD 内钉死）+ checker 批签注 + 红线偏离申报。裁决正本 =
> D-M2-8-CONTEXT-1..12（全部按推荐 A 生效，未重开）。

## 悬决销账（KD 必答三件）

1. **版本 swap 的 sidecar 写原子序（KD-2）**：单条 MainActor 同步状态转移
   「outgoing 槽.chain ← EditorState.history（值拷贝）→ installVersionChain
   (target.chain) → target.chain = nil → activeVersionID ← target.id」，命令内
   零 await；随后一次 `versionActionDidChange()` 通知 PipeCoordinator 走
   `scheduleSidecarWrite()`——`makeSidecarDocument()` 读 **post-swap 快照一次**，
   SidecarStore tmp 原子晋升落盘。**磁盘上从不存在中间态**；UI 连点合并进同一
   2s debounce。VersionSwapTests 的 post-swap 文件态断言钉死。
2. **`version_ref` upsert 触发位（KD-5）**：版本命令尾（五命令统一走
   `finishVersionAction → syncProjection()`）+ restore hydrate 尾（含 nil 臂
   reset——切图清空时对新 element 同步一次空集清投影）各 reconcile 一次；整表
   reconcile 幂等故重复调用无成本。投影失败 = log 不 toast（投影非真相）。装配
   点 = `EditorWorkspaceShellView.loadCurrentImage`（row.id 缝，注入先于 load，
   hydrate 对账的是 incoming element）。Sessions 模式 sink 恒 nil = 零引用。
3. **pristine 不变量收窄的边界测试（KD-6）**：①App 级——空链版本创建 →
   flush → `.lra` 诞生且 `history.position == -1`、versions 含 2 槽
   （VersionSwapTests）；②Core 级——空 active 链 + 非空 versions →
   `effectiveInstances().isEmpty` 仍判无编辑（SidecarV7Tests）。

## 创建即激活（Alcedo 语义推定签注）

createFromScratch / branchFromCurrent 均创建后**立即激活**新版本（swap 四步的
target = 新版本）。Alcedo 源码无反面证据，按 UX 常理裁定；晨审可翻（翻 = 创建后
停留原版本，一行改动：新命令尾不调 installVersionChain）。

## rawOverrides 不随版本换（KD-2 有意排除面签注）

rawOverrides 是 image-global decode 域——随版本 swap 会触发重解码，违「切换即时」。
版本链只携带 param/DRT/layer 结构面；decode 域单图单份。行为面未立测（decode 域
本就不在链 swap 路径上，结构性保证）。

## reduced DDL 偏离签注（KD-3）

`version_ref` 激活列为 **5 列 reduced DDL**（version_id TEXT PK / element_id
INTEGER FK CASCADE / display_name TEXT / created_at_unix INTEGER /
updated_at_unix INTEGER），预留注释 sketch 的 **`head_commit_hash` 不激活**
（OQ-2-A：v1 版本 = 独立线性链，无 commit hash 可写）；版本 active 态不投影
（`image_edit_state` 维持预留）。`version_id` 用 UUID **String**（.lra↔.lalb
关联键；L013 decimal 规则不涉及——无 hash 列）。将来翻 DAG 世界线时该列可
additive 加回。

## 版本默认名编号规则

`「Version N」` = 槽位数 +1（cosmetic；identity = UUID）。remove 全部后计数自然
回到 1（checker E4 跨图污染用例的命名面）。会话内 create→remove→create 可能重用
编号——展示名重复无害，DECISIONS 备案。

## checker 批签注（E1 版本链访问缝三件）

- ①`SidecarVersionRecord.public init(id:name:createdAt:updatedAt:chain:
  HistoryStack?)` —— App 落盘投影唯一构造入口（`SidecarLayerStackRecord.init(
  _ snapshot:)` 同款）。
- ②`public var chainStack: HistoryStack?` —— hydrate 读取面（`.snapshot`
  同款）。
- ③`public static func HistoryStack.copyingPrefixOf(_:upTo:)` —— branch 前缀
  拷贝缝，落 **LightamerSidecar.swift**（LightamerCore 单 target，internal
  `init(items:position:)` 同模块可见；`HistoryStack.swift` 本体零 diff 保持，
  M2-6-3 DRT fold extension 的同款落位先例）。
- **两 record private→internal 理由**（L042「先查 access level」先例）：版本链
  拼写（`SidecarVersionRecord.chain`）嵌入**同一份** item/record 编码器——拼写
  零改、纯 access level；复制键集 = 两个待迁移格式（SidecarInstanceRecord
  06-01 widening 正本先例）。record 对永不出 Core（消费面 = ①②）。
- **paste/switch 免缝**：值拷贝 + `commitPaste`/`commitDrt` 已 public
  （HistoryStack.swift:229/:257 实测）——版本模型零新增 HistoryStack 写面。

## 红线偏离申报（checker E2，「本 plan 不触 ProjectFileStore」推翻）

**根因**：实测 pre-migrate hook = 固定路径 `<stem>.pre-migrate.bak` +
`backup(..., allowExisting: false)` typed refusal——v1→v2 迁过的包在二代二进制
（stored=2 < 3）重开必撞「destination already exists」= **打开即死、永远死**
（二次迁移死锁）。**改法**（hook 侧轮换，dispatchSchema 三路 dispatch 形状零改、
`migrate` 签名零改）：快照按 `stored→to` 代际命名（`<stem>.pre-migrate.1-3.bak` /
`.2-3.bak`，代际共存互不覆盖）+ 同名旧件（同代失败重试）清旧后重照；
`backup(from:to:allowExisting:)` 死参收窄为 `backup(from:to:)`（`allowExisting`
从未有 true 调用者；refusal 上移 public `backup(to:)` 一帧，行为不变）。链式两代
迁移测试钉死（v1 fixture → 回拨 2 → 重开 → v3 + 两代快照共存）。

## E3 版本 pin 触点穷举实况（checker 点名 + 执行期补点）

checker 点名：DrtSidecarTests:71、LibraryDocumentTests:107/151/174-180、
DefaultLookTests:277/297、LibrarySchemaTests:171/193/274/279/284——全部落改
（另 LibrarySchemaTests:170 raw PRAGMA 位 + 两文件头注释同步）。**执行期实测
补点 3 处**（SUMMARY 偏差 §）：DrtPersistenceTests:325（APP bundle 字面 6）、
SidecarMetadataV3Tests:178/250/261/265/268（LIB bundle 字节 golden 家族）、
DefaultLookTests 快照名触点（`pre-migrate.bak` → `pre-migrate.1-3.bak`，E2 轮换
命名连带）。教训：版本 pin 触点穷举应以「grep 字面 version 数字 + 字节 golden
测试」机检，不赖人工枚举（LESSONS 已记）。

## 投影通道先例签注（KD-5 备注）

`LibraryStore.updateProjection`（has_edits/params_hash）至今零生产调用者；本
plan 的 version_ref 通道 = **注入式 sink 形态的第一个实例**（VersionProjectionSink
= elementID + store，shell 装配根读一次显式注入，视图 body 零直读）。后续
has_edits 投影通道立项时复用同款形态。

## 命名注记

plan 行文「migration v1→v2」为 CONTEXT :67 勘误既定项（实做 **v2→v3**，v1→v2 =
M2-5-2 既有）；测试名 `testFreshCreateStampsUserVersionThree...` 沿实做版本。

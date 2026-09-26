# Plan 12-1 DECISIONS — 执行期决策

> 正本依据：12-RESEARCH §2/§3、12-CONTEXT D-12-CONTEXT-1/8。以下为执行期裁决（plan 期未钉死/需落实现形态的细节），全部有测试锚。

## D1 sidecar_mtime 值来源 = 段2 预测值（claim 时刻 now）

- `claimMetadataApply` 的 `sidecar_mtime=?` 写**预测值**（`Date().timeIntervalSince1970`，全 claim 单值）；段3 写盘后的**实际** mtime 由既有 mtime 漂移检测（`backfillSidecarSummaries`）在下次 open 时判「漂移 → 重读 → 回写精确值」校正——与每一条 9-4 batch paste 的既有演化路径完全同构。
- 不采用「段3 写后实测回写」：那需要改 `clearBatchDirty`（plan 纪律「原样不动」）或加新写回缝；预测值的唯一代价 = 元数据写过行的**一次性**漂移重读（9-4 paste 行本来就必走，非新增成本）。
- 不变量由 crash 注入测试钉死：crash 窗口 reopen 后 `healDirtyRows` 旧值回填 + dirty=0 + 逐行 index==磁盘真身（`testCrashBetweenClaimAndWriteHealsToOldValues`）。

## D2 keywords 语义三态 + UI 录入约定

- sidecar `keywords: [String]?`：nil=未打标 / `[]`=已清空 / 数组=完整层级 path（`|` 分隔，打子不物化祖先）。
- DB `keywords` 列物化 = `joined(separator: "|")`：nil→NULL、`[]`→空串——「未打标 vs 已清空」在缓存列可区分（`materializeKeywords` 单点）。
- UI 录入（Inspector 行 + 网格 alert）= **逗号分隔**多值；`|` 是 path 存储形态、录入 typed-ban（`MetadataError.keywordContainsSeparator`）——层级 path 的既有值显示原样、提交含 `|` 的新值会被拒（XMP 导入的 path 值不经此面）。
- appendKeywords = 保序精确匹配去重（不折叠大小写）；appendNote 拼接符 = `\n`（MCP-06 append_note 上游语义）。

## D3 EXIF 回填谓词锚（plan 定死案③的落地形态）

- 谓词 = `orphan_sidecar = 0 AND camera_make IS NULL`（单锚）。
- 文本列（camera_make/camera_model/lens_model）无值写 `''` 哨兵（已尝试标记）；数值列（iso/focal_length/aperture/exposure）无值保持 NULL（SQLite 三值逻辑下不被锚命中）——成功处理的行**恰扫一次**（直调二扫返回 0 断言）。
- 打不开/无 properties 的文件保持 NULL → 下次 open 重试（Phase 9 降级姿态不变）。
- 七列与 Phase 9 四列**同一批 UPDATE**（orientation/width/height/capture_date 同步重算——确定性重读，值恒等）；既有 v1 行（orientation 已填）被该锚单轮收编。

## D4 unparsable meta schemaVersion → REFUSE（fail-closed）

- 旧行为：meta 值非数字时落入「absent」分支 stamp-over——若表实际缺列，静默盖版本戳会跳过迁移。新行为：值存在但不可解析 → `schemaFailed` 拒开（永不猜测未知状态）。v99 拒开语义不变。

## D5 「迁移失败不破坏原库」的断言口径 = 数据级保全

- 中迁失败（meta 表缺失 fixture）→ 事务 ROLLBACK → 列集回 25 + 行字节不变（直接断言）。
- 只读文件 → open 拒开 + 文件字节逐字节不动（直接断言）。
- v99 拒开 → **数据级**保全（25 列 schema/行/ meta 值不变）；不主张字节级不动——冻结的 open 序里 WAL/index DDL 先于版本检查（09-01 行为，非本 plan 改动面），v1 形态 fixture 缺 dir index 时会补建（真实 v99 库为 v2 二进制所写，DDL 全 no-op）。

## D6 快捷键冲突表 + 文本聚焦降薪

- 冲突核对：bare `0-5` / `x` / `p`、`⌘0-6` 在既有命令面**零冲突**（既有 bare 键 = z/f，均为 disabled 占位）。
- bare 键在文本编辑时会截字（AppKit 菜单 key equivalent 先于 field editor）→ Inspector metadata 两字段聚焦时经 `metadataFieldFocused` focused-value **自动 disable** 全部 bare 项（⌘ 系不受影响，一并 disable 保守处理）。
- 语义映射：键 `0` = 清除评分（nil；C1/Lr 惯例，rating 0 是值非清除）；X/P = toggle（读目标当前 flag：全带该值 → 清，否则设）；⌘0 = 清色标，⌘1-6 → 色标 0-5。

## D7 C1 七色映射（0-6 = 红/橙/黄/绿/蓝/紫/灰）

- RESEARCH/CONTEXT 未钉色名，执行期钉死如上（SwiftUI 语义色）；越界值回落灰。
- ⌘1-6 只达 0-5：色标 6（灰）v1 无键盘位，经后续菜单/过滤面可达（文档化例外）。

## D8 MetadataService 目标姿态

- **pristine 目标**（无 sidecar）：mint 自洽文档（decodeParamsHash=0 + decoderVersion "unknown-metadata" + seed 默认实例 + 空 history）——SessionBatchApplier 同姿态，`driftDetected` 自文件自身字段重算恒 false，后续编辑器加载不误报漂移。
- **existing-but-unreadable sidecar**：SKIP（比 9-4 参数批的「pristine 化覆盖」更严）——元数据写绝不可毁既有编辑（ outcome.skippedRelPaths 承载，行不 claim）。

## D9 sync changed-leg 追加清五元数据列（F7 闭环补点）

- 文件 mtime/size 漂移（被替换）时 changed-leg 原本只清 sidecar 摘要列——若不同步清五元数据列，替换后的文件会残留旧 sidecar 的评分（真身违约）。additive 五列置 NULL → backfill 重读重导。T3 提交内，回归 16/16。

## D10 fetch 投影收敛 + Row 扩展

- `fetchAllRows`/`fetchRow` 的 34 列 SELECT 收敛为共享拼写（`rowSelectColumns` + `readRow` 单投影）——additive 扩列时两路径不可再漂移；行为等价（SessionIndexStoreTests 16/16）。
- `SessionBrowserModel.Row` 扩 rating/colorLabel/flag 三字段（plan files_modified 未显式列 SessionBrowserModel.swift——T6 overlay 数据面的必要承载，projection/placeholder 同批）。

## D11 测试容器 fixture 细节

- 迁移 fixture 的 scan 流**重放 fixture 行的 stat 值**（mtime/size）使 open diff 为 no-op——旧行逐列字节断言的前提；孤儿行走 scanOrphans 保活。
- 删库重建 parity 用测试自有 `SQLiteHandle` 裸读 34 列（与 store 行投影解耦，T2 时 Row 尚未扩列也成立）；`scan_epoch` 合法递增排除。
- `AsyncStream` 单次消费：同一流喂两次 open 第二次得 0 页——parity 测试每 open 构造新流（教训候选入 L032）。

## D12 杂项

- commit `e0ce1ed` body 笔误 `.worl/12/perf.md`（实为 `.work/12/perf.md`）——cosmetic，不重写历史。
- 万张门 `writer: nil` 门形态（段1+段2）复用 MetadataService 公共路径（writer 可空为 gate 语义，非生产形态）；生产路径 writer 恒有（MetadataController.configure 注入 batchSidecarWriter）。
- GUI 走查 ⌘4→色标3（绿）实测与菜单标签「绿 (⌘4)」一致——「第 N 键 = 第 N-1 号色」是「⌘0=清除」并列的可读映射，非 off-by-one。

## D13 ⌘色标键位映射：第 N 键 = 第 N-1 号色（⌘0 = 清除）

- 映射形态即 D12 上述 ⌘4 实测条目的正名：「⌘1-6 → 色标 0-5、⌘0 = 清除」与菜单标签「绿 (⌘4)」一致，是「⌘0=清除」并列下的可读映射，非 off-by-one。
- 代价：色标 6（灰）无键盘位（C1 七色只映射 ⌘1-6 六键），经后续菜单/过滤面可达（与 D7 文档化例外同源）。

> 编号勘误（2026-09-26 验收轮）：原稿将本条寄居 D12 第三 bullet，致 SUMMARY/TODO/commit 所称「决策 13 条 / D12/D13」与节计数（12）不一致；验收时升格为独立 D13 节，内容实质未改。
- zh-Hans.lproj 在 Debug 产物中为**空目录**（无表文件）——L025 破坏面是「partial 表改变 fallback 链」，空目录无表不构成风险；zh 首屏全量中文渲染实证（12-1-01-open 证据）。

# M7-4-01 ACCEPTANCE（第二路独立验收）— zcode subagent，2026-10-17

```
phase:      m7-4-mcp-o4
object:     M7-4-01 执行链 49fab645..df0928f4（7 commits，T1-T7）
method:     零共享上下文独立第二眼（替代 omp 制度位，夜间全自动授权在案）——
            全套独立复跑 + 五面独立审计（切入点与第一路错开：paste 批量写
            三段事务语义 / V11 五法非永真性 + 升级链 / MPF 偏移容器交互 +
            卷实测 / e2e 实质 + kill 对照亲跑 / 偏差十条独立复核）
verdict:    **PASS / 0 error + 3 minor（第一路 2 open + 本路新 1 open，均非阻断）**
dual_acc:   本文件 = 第二路；与第一路 ACCEPTANCE 无分歧（补充 + 行号勘正）
```

## 结论头

**PASS / 0 error + 3 minor** —— 全套独立复跑 `TOTAL|3925/35/0|` exit 0 零
MEMFAIL 七 bundle 逐位对账闭合；五面审计全数成立且无与第一路的分歧；
两条独立新发现均属 open 观察级（段3 写失败应答面 / exFAT 申报卷归类例），
不构成阻断。M7-3 挂账①②③⑤⑥清算亲证兑现；union 改动权行使合规。

## §1 亲跑数字（独立复跑，非转抄）

- **全套 `caffeinate -dis Scripts/test-direct.sh --all`（先全新
  build-for-testing exit 0；产物内容新鲜度以符号亲证——执行方产物 mtime
  早于 T6 commit 的疑点以二进制内容证据消解：主机含 `paste_adjustments`
  ×9、Library xctest 含 `SidecarV11Tests` ×4，本全套轮即跑在该产物上）**：
  `TOTAL|3925/35/0|` **2058s**，exit 0，**零 MEMFAIL，七 bundle 全 8G 门内**。

  | bundle | 申报 | 本轮亲跑 | peakRSS |
  |---|---|---|---|
  | IOP | 687/5/0 | **687/5/0** ✓ | 7610MB |
  | IOPParity | 460/3/0 | **460/3/0** ✓ | 7009MB |
  | Layers | 494/5/0 | **494/5/0** ✓ | 808MB |
  | Library | 736/4/0 | **736/4/0** ✓ | 621MB |
  | Sessions | 284/9/0 | **284/9/0** ✓ | 1262MB |
  | Export | 385/5/0 | **385/5/0** ✓ | 6170MB |
  | App | 879/4/0 | **879/4/0** ✓ | 2832MB |
  | **TOTAL** | 3925/35/0 | **3925/35/0** ✓ | — |

  对账：基线 3905 + ΔN 20（App+11/Library+5/Export+4）= 3925 精确；
  skip 5+3+5+4+9+5+4 = 35 零漂移；App 轮 370s（无 50s 预热停滞——runner
  中央 env 门生效面）。
- **kill 形对照（本路自建探针，非复用第一路脚本）**：spawn 同一产线宿主
  `--mcp-stdio` → initialize → project_create → **SIGKILL** → exit=-9，
  `.lalb-wal` = **387312 字节（非 0）**——与第一路实测逐字节同值；
  graceful 形（全套轮 e2e 绿）wal==0 / kill 形 387KB，**wal==0 断言判别力
  两路独立实证**。
- **zh-audit**：`--check` PASS（1698 source / 1946 catalog keys）+
  `--self-test` PASS——亲跑同值。
- 卷实测：`diskutil info /Volumes/UNITEK` = **Case-sensitive APFS**；
  同目录 `link()` 探针 exit 0（link count 2）——见 §5 观察项。

## §2 面1 — O4 写面（paste 批量写事务性 + GUI 读面）

- **三段批事务语义走查**（SessionBatchApplier + BatchSidecarWriter 全文亲读）：
  - 段1 compose：per-target 内存组合，unreadable sidecar → failed 行（不写、
    不回滚他人）——per-target 分账正确。
  - 段2 index claim：**ONE transaction for ALL targets**——claim 失败 =
    事务回滚，rows 保持旧态、sidecar 零写（段3 永不跑），全批
    failedRelPaths → MCP 面 pasteFailureReason → 旧 sidecar 可读 →
    `internalError` 全批诚实应答。**与申报一致**（DECISIONS §3「claim 回滚
    = internalError 兜底」）。
  - 段3 写队列：per-target 原子晋升（tmp sibling + replaceItemAt）——写失败
    不回滚已写目标（无需：每写自原子），行保持 dirty + heal leg 下次 open
    以 sidecar 为真覆盖 index（最终一致，crash contract M6-09-04 既有）。
  - **minor-3（本路新发现，open）**：段3 drain 写失败**不进应答**——
    `outcome.appliedRelPaths` 在 ENQUEUE 后即全量填充（文档注释自认语义 =
    "composed + claimed"），`flushForTeardown` 的 drain 失败仅 log；
    MCP paste 应答在 drain 失败路径仍报 `applied`，而「写达后方返」契约的
    实质（agent 下一步 get_history 读到新态）不成立。**非本批引入缺陷**
    （apply_params M7-3 同姿势；SC#2 posture + heal leg 是 writer 的既有
    设计），但 MCP per-target ledger 把该语义缝隙新暴露到 agent 可见面。
    建议 UPSTREAM-QUEUE 挂账：applied 语义诚实化或 drain 失败回传
    failedRelPaths。
- **GUI 读面（结构亲核 + stub 级证据）**：`HistoryRowData.item` 携全量
  `HistoryItem` → `historyRow` 读 `item.note`（caption2 + lineLimit(1)
  副标题）/ `item.author`（nil/空 = 无徽章；Capsule 徽章 + AX label 键
  `editor_history_author_badge`，zh = 「作者 %@」xcstrings 亲验）。
  GUI 面无渲染级测试（plan 未要求；historyRows 既有测试不触 note/author
  显示）——结构面实装核通过。
- **O4 golden 实质亲读**：paste ledger 法（appliedCount/author/note 应答 +
  磁盘真身 label="MCP paste_adjustments"/pasteEpochScope/author/note 四落盘
  断言 + mask contentRevision nil + 立即读回）——非永真；live 硬拒法
  （磁盘零触断言）；membership/probe 分臂；重复 targets invalidParams；
  unreadable 源全拒批；include 子集 + includeDrt opt-out。copy golden
  （transferableCount 1 + temperature/gamma 灰显 VISIBLE 断言 + 库 id 双形态）。

## §3 面2 — v11 面

- **五法读码（非永真性独立判定）**：
  - ①v10-form byte-exact：digit-rewind 造 v10 档 → decode → re-encode
    逐字节——若 encode 注入 note/author null 或 bump schemaVersion 即红，
    **真实漂移守卫**（「无被动升级」契约的字节钉）。
  - ②nil-face = v10 shape 仅 digit 异：键缺席断言实质；两条字节差断言
    部分 by-construction（v10String 本身由 v11String 单 replace 构造），
    判定 = 该法主体（encodeIfPresent 键缺席面）成立、字节差面弱于注释
    措辞——观察级注记，非缺陷。
  - ③stamped round-trip byte-faithful：镜像四件（init 携带/`item` 重建/
    decodeIfPresent/encodeIfPresent）任一缺失即红——实质。
  - ④HistoryHash 隔离负测：同编辑态 ± note/author → 同 hash +
    driftDetected false 双断言——独立实质（± note/author 真实造两档）。
  - ⑤future-12 tolerance：CHECKER C1 守卫重正实质（schemaVersion 12
    decode 出全量 + note/author 存活）。
- **SidecarV10Tests 零 diff（git diff = 0 行亲跑）+ :327 法语义退化申报
  属实**（硬编码 11 字面 bump 后 = current，forward 守卫面消失，V11⑤
  重正——申报-补偿闭环成立）。
- **旧 v10 档打开升级链亲核**：decode 路径保留存储 schemaVersion=10
  （V11①字节钉死无被动升级）；app save 路径 = `makeSidecarDocument` →
  designated init re-mint → `schemaVersion = schemaVersionCurrent`（
  LightamerSidecar.swift :444 亲读）——**v10 档打开后编辑重存 = 升 v11**，
  解码不升级、写档升级，与 v8/v9/v10 先例链同构。全套轮 Library 736/4/0
  （含 V10+V11 全法）本路亲证绿 = 造档亲测通道（in-test digit-rewind 造档
  → 真解码器消费）。

## §4 面3 — UQ-A2 面

- **exclusive/gain-map wrap UltraHDR 容器交互（MPF 偏移文件内相对性）**：
  结构面亲证安全——①gain-map 编码器内部 rewrap（CopyImageSource，
  「ImageIO rewrites the moved internal offsets」:165-168 亲读）在 encoder
  内部 promotion（moveItem → writeTarget）**之前**完成；②encodeStage 的
  promoteExclusive（link + unlink tmp）内容中性——promotion 链上零字节
  修改，MPF 偏移自计算后恒有效；③ICC strip（删 APP2）/XMP mount（注 APP1）
  对 gain-map 文件**结构性不可达**（gain-map arm 早退，:95-97 注记明言
  「APP2 delete or APP1 inject shifts absolute offsets and kills the MPF
  subimage」）；④既有 MPF 面测试钉（`testGainMapContainerMPFIndexSegment
  IsPresent` / `testGainMapArmSkipsTheICCStrip` /
  `testRewrapSurvivesAndPolicyNoneStaysUltraHDR` /
  `testGainMapPromotionLeavesNoTmpResidue`）全套轮亲证绿。
- **五腿亲读**：TOCTOU 负测（typed 错 + intruder 字节不变 + glob 零残留）、
  正向恒等（byte-equal）、.replace 负面守卫（decoded 0xEE 断言覆盖发生）、
  .increment（既有 E2E face）、encoder 失败腿（float32 vs png spec 强制
  throw + 预植字节不变 + 零残留）——全部实质非永真。Export 385/5/0 全套轮
  亲证绿。
- **exFAT EOPNOTSUPP 申报行为面**：promoteExclusive 非 EEXIST errno →
  `encodeFailed` 兜底（代码亲读正确；DECISIONS §3 + UPSTREAM-QUEUE 挂账
  「EOPNOTSUPP 降级 plain rename 勿静默」在位）。**观察项（见 §7）**：
  申报中「含本工作区所在 /Volumes/UNITEK 类外置卷」的卷归类对本卷不实。
- **可选腿注记**：T4 两条可选腿（queue 级 / gain-map 变体）未行使且未像
  偏差9 那样显式申报——plan「可选腿（时间盒）」条款内不行使非违规，
  申报完备性小缺口（与偏差9 同形）。

## §5 面4 — S1 面

- **poll 体三点改形 diff 亲核**（49fab645 全 diff + HEAD 函数全文）：
  `events: Int16(POLLIN)` / `poll(&fds, 1, 250)` / revents 分流（HUP/ERR →
  break 至原样 close+exit(0) 体）+ 纯 POLLIN 臂清 revents +
  `Task.sleep(250ms)` + count==0 超时臂零 sleep 注记——恰三点，函数其余
  零触。F2 真机理（sleep 臂 = 速率限制本体，超时形只封阻塞相）与注释、
  DECISIONS §2.10、AGENTS :542 三处一致亲验。
- **四语义零改**：once guard（eofArmDone）/ mode 自守卫（:390 `guard
  mode == .stdio`）/ close+exit(0) 体 / 两调用点（:321/:571）mode 传参——
  亲核成立。
- **e2e 实质亲读**（testStdioDisconnectReleasesProjectGracefullyE2E）：
  真产线二进制 + 真握手（initialize → initialized → project_create）
  + **锁语义侧写在测试体内**（退出前第二 open = typed projectHeldByOther
  :493-504——偏差9「未另立时间盒腿」与测试体一致）+ 关 stdin 真 EOF →
  ≤12s 退出 + exit status 0 + wal 存在且 size==0 四断言组。全套轮 App
  bundle 内绿 = 本路亲证。
- **S2 预热**：`warmLutLibrary` 恰 1 定义（:676）+ env 门（:677-678）+
  四装配点（:692 只读 http / :755 stdio / :997 http / LightamerApp :1265
  GUI）+ `Task.detached(priority: .utility)` 亲核。**挂账②收口 = 机制面
  （A 预热 + C 文案）成立**；冷窗数字维持 M7-3 正本 50.2s、本波未重测
  （偏差7 如实申报——env 门使然，非静默）。App 轮 370s（本路实测）无
  50s 停滞 = 预热-旁路机制生效面佐证。
- **S3 正臂腿**：三 clause 断言（before==nil :532 / after!=nil :543 /
  store 未变 :546-548）+ heldTargets 非空传参（:537-538）亲核成立。

## §6 面5 — 偏差十条独立复核 + runner env 门 + 第一路 2 minor

| # | 偏差 | 本路裁决 | 独立依据 |
|---|---|---|---|
| 1 | 探针分仓 | **成立** | evidence 仓 `70774ad` 亲验（7 文件 326 行）+ 盘上 7 件在位 + /tmp/m73_probe 原件留存 |
| 2 | T2 五文件 | **成立** | d3f487a6 stat 含 EditingToolset（en defaultValue 即 en 正本，冷首调句 diff 亲读） |
| 3 | runner 中央 env 门 | **成立（合理扩展非越权）** | test-direct.sh :68 亲验；in-process 直调 startHTTPHost 亲验（McpHostTests 7+ / McpRenderParity / McpFinalSnapshot 各 1，共 9+ 调用点）——plan F14 spawn 面确实漏盖 in-process 面；测试基建文件、additive、申报在案 |
| 4 | V11 落 LIB 域 | **成立** | Project.swift 恰一行（V10 邻位）+ BUNDLE-MAP LIB 5 法行亲验 |
| 5 | 温度归属 | **成立** | transferableCount 1 断言 + temperature/gamma transferable false 亲读；RAW-decode 归属注记实存（**勘正：注记在 `NodeOwnership.swift` :28，非第一路所记 NodeOwnershipCatalog :21**） |
| 6 | 空源 invalidParams | **成立** | paste body :1010-1013 亲读；封闭表既有码 |
| 7 | S2 预热观察证据 | **成立（如实）** | 冷窗未重测如实申报；机制面 + 文案面独立核成立 |
| 8 | V10 :327 语义退化 | **成立** | V10 文件 0 行 diff 亲跑 + V11⑤守卫重正亲读 |
| 9 | e2e 可选锁窗腿 | **成立** | 侧写以同测试内 projectHeldByOther 承载（:493-504），确定性形强于竞速形 |
| 10 | 三处措辞校订 | **成立** | M7-3 签核文档零回改（diff 0 行亲跑）+ DECISIONS §2.10 + AGENTS :542 修后终形亲读 |

- **minor-1 复核（成立）**：五处过时注释全部实存——`McpFinalSnapshotTests`
  :263（"exactly these 27 descriptors"）/:268（"27 is"）【勘正：第一路
  报告两行号互换，两处均实存】+ `McpHostTests` :466/:668（"21-tool face"
  两处）+ `McpSearchStateToolsetTests` :16/:265（"rides 21"）。可执行形态
  断言全部正确（union 29 / 五钉 23 亲跑），注释矛盾面维持 open hygiene。
- **minor-2 复核（成立）**：`promoteExclusive` 中 `strerror(errno)` 求值
  先于 `errno == EEXIST` 判读（亲读 :807-812 形）——POSIX 不保证 strerror
  保全 errno；防覆盖语义不损（EEXIST 误判降级 = encodeFailed 兜底仍拒
  晋升），typed 面理论降级。macOS 当前实现未触发（TOCTOU 负测全套轮绿）。
  维持 open，建议随下一 Export 波一行重整。

## §7 独立发现（本路新增）

- **minor-3（open，honesty/robustness 观察，非阻断）**：见 §2——MCP
  paste 应答的 `applied` 在段3 drain 写失败路径失真（ENQUEUE 后填充、
  失败仅 log 不回传；heal leg 最终一致但 agent 单步视角被误导）。既有
  段3 语义（M6-09-04），apply_params 同姿势；MCP per-target ledger 面
  新暴露。建议 UPSTREAM-QUEUE 挂账（applied 语义诚实化 / drain 失败
  回传），随 MCP 波顺路。
- **观察项 A（申报文字勘误）**：DECISIONS §3 exFAT 申报「含本工作区所在
  /Volumes/UNITEK 类外置卷」对本卷不实——`/Volumes/UNITEK` 实测 =
  Case-sensitive APFS，同目录 `link()` 探针 exit 0（link count 2）→
  **本工作区 .fail 档终写原子面实际可用**（利好非缺陷）；EOPNOTSUPP →
  encodeFailed 行为申报本身正确。建议下次触碰该文档时勘正卷归类例子。
- **观察项 B（申报完备性注记）**：T4 两条可选腿（queue 级 / gain-map
  变体）未行使且未单列申报（plan 时间盒条款内非违规；偏差9 为同形申报
  先例）。
- **行号勘正注记**：第一路/DECISIONS 所记若干行号与 HEAD 实际有微移
  （union 四计数实际 :275/:328/:356/:510、editing 钉实际 :223、温度注记
  实际 NodeOwnership.swift :28、minor-1 两行号互换）——记录时点差异，
  实质面全数成立，无需改判。

## §8 红线族抽验（本路独立亲跑）

零新 SPM（Project.swift 恰一行 SidecarV11Tests 登记 + dependencies 块
零 diff）| `.metal` 全域零 diff（0 行）| HistoryHash.swift 零 diff |
McpToolRegistry.swift 零 diff | ExportNamer.swift 零 diff |
LibraryProjectController.swift 零 diff（FIX2③ 第三波维持亲验）|
`isAdjustmentTransferable` 全仓恰 1 定义（grep 亲跑）| `.runModal(`App
/Sources 零命中 | LocalizationValue 插值唯一命中 = LightamerApp :2307
既有文档注释 | xcstrings 恰 2 hunks（1 原位值改 + 1 尾块三键插入，diff
亲读）| UserDefaults 零新键（diff 面 grep 仅文档句）| SidecarV10Tests
零 diff | M7-3 签核文档零回改 | 改动文件清单 35 文件 = T1-T7 逐 commit
--stat 并集（偏差③申报面 Scripts/test-direct.sh 在册）。
LightamerSidecar carve-out 逐 hunk 亲核 = 恰申报面（Keys 两 case + 存储
两 + init 镜像两 + item 重建两 + decode/encodeIfPresent 四 + 
schemaVersionCurrent 一行 + 头注）。

## §9 判定与分歧

- **第二路独立验收 PASS / 0 error + 3 minor（均 open 非阻断）。**
- **与第一路分歧：无。** 补充 = minor-3（新）+ 观察项 A/B + 行号勘正；
  第一路 2 minor 双双独立复核成立并维持 open。
- 全套 3925/35/0 两路独立复跑同值闭合；kill 形对照两路独立实测同值
  （387312 字节）——判别力双证。
- 三 minor 建议处置：minor-1/2 随 M7-5 波顺路消化（第一路建议维持）；
  minor-3 挂 UPSTREAM-QUEUE 随 MCP 后续波诚实化。观察项 A 随下次文档
  触碰勘正。
- 本验收产物不 push（夜间授权链内；推送收敛主会话）。

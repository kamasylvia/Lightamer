# M7-4-01 DECISIONS — 执行期裁定与偏差申报正本

> 修订版 plan（F1-F14 落定 + CHECKER 放行）执行批的裁定记录。结构性零偏差；
> 小偏差逐条申报如下。晨审可推翻，推翻 = 修订对应面。

## §1 union 显式改点位清单（本波取权申报）

`Tests/LightamerTests/McpFinalSnapshotTests.swift` 全点位：

1. 冻结表 `editingTools`：+`copy_adjustments`（readOnlyHint: true）+
   +`paste_adjustments`（destructiveHint: true）两行 + `apply_params` schema
   行同批改（note 属性——两层 consciously change together）。
2. 计数 ×4：verbatim 轮 `descriptors.count` :249 27→29 / 域组合 `u.count`
   :299 27→29 / tools/list 轮 `tools.count` :326 27→29 / direct-entry
   `directTools.count` :479 27→29。
3. destructive 集 9→10（+ paste_adjustments；:255-260 集断言 + 注释同批）。
4. `descriptionKeys` +2（copy/paste 两键，:361 后）。
5. `all27` → `all29`（定义 + 引用改名；头注历史句措辞勘正「was the
   27-tool set then」非易碎形）。
6. 测试名 `testFinalSnapshotUnion27Verbatim` → `...Union29Verbatim`。
7. message 同批（:250 计数句 / :326「no 30th tool」/ 域组合句 / 头注 M7-4
   取权段〔M7-5 串行禁并行注记延续〕）。

`Tests/LightamerTests/McpRegistrySnapshotTests.swift`（editing 层）：
apply_params 行（note）+ copy/paste 两行 + :203 钉 21→23 + message 同批。

**union 外五钉显式改**（F-1 家族，M7-3 五钉教训清单形；全部 21→23 + message
同批，算术钉 = editing 9 + culling 14 = **23** 非 22——M7-3 H1 家族防复发）：
`McpRegistrySnapshotTests :203` / `McpSearchStateToolsetTests :274` /
`McpHostTests :243` / `McpHostTests :697` / `McpLauncherTests :200`。

**残漏 grep 收口**：`count, 21` / `count == 21` / `all27` 全仓 MCP 测试面零
命中；「27-tool」注释形态随手清（头注句）。

## §2 偏差清单（小偏差逐条；结构性零偏差）

1. **探针分仓**（T1）：plan 文「小件文本随 T1 commit」与主仓 pack 政策 B
   （`.gitignore :80 .work/gsd/phases/*/evidence/`，2026-10-10 用户令）冲突
   ——按政策 B 落地：盘上迁 `phases/m7-4-mcp-o4/evidence/m73-probe/`（SC 的
   ls 判据满足）+ git 面随 **lightamer-evidence 仓** commit `70774ad`（七个
   探针源 + 来源注记）；原件 `/tmp/m73_probe/` 留存不删（迁非移）。
2. **T2 恰四文件 → 五文件**（T2 SC 勘误申报）：`EditingToolset.swift` 的
   list_luts **en defaultValue** 即 en 文案正本（xcstrings 只存 zh）——
   「en defaultValue + zh 译文同批」必然触碰该文件；T2 = controller + App +
   **EditingToolset** + xcstrings + ProjectToolsetTests 五文件。历史先例 =
   M7-3 `3ef68910`（render_preview 原位值改同形）。
3. **runner 中央 env 门**（T2/F14 扩展）：plan 只写仲裁 fixture 注入，但
   `McpHostTests`（7 处）/`McpFinalSnapshotTests`/`McpRenderParityTests`
   **in-process 直调 `startHTTPHost`** ——App/Export bundle 宿主会付 ~50s
   预热 + 真实 LUT 根 seeding（plan「App bundle in-process 零预热面」判定
   对这三文件不成立）。修法 = `Scripts/test-direct.sh` 导出
   `LIGHTAMER_SKIP_LUT_PREHEAT=1`（runner = 测试语境定义；spawn 子进程 env
   继承全覆盖）——一处中央注入替代三处 per-file setenv；T1 fixture 显式注
   入行保留（F14 字面）。实测：App 轮 385s→373s（零 50s 停滞）。
4. **SidecarV11Tests 落 LIB 域**（T6/F1）：plan 文「Layers 域」按「V10 同位
   先例形」读解——V10 实际登记于 `LightamerTestsLibrary`（Project.swift
   :624 + BUNDLE-MAP :731 LIB 行；CHECKER 原文「LIB〔=Layers 域〕」即此同位
   指称）。V11 = Project.swift 恰一行（V10 邻位）+ BUNDLE-MAP 恰一行
   （LIB 5 法）+ tuist generate 恒末位。
5. **TemperatureModule 归属修正**（T6 golden 首版两红）：temperature 属
   RAW-decode 域（NodeOwnershipCatalog :21 注记「camera WB is a RAW Decode
   concern」）非 grade-owned → 不可贴。golden 预期按实表改（transferable
   count 1 非 2；灰显行 = temperature + gamma 两行）——断言未放宽，捕获面
   即正确性。
6. **paste 空源 payload = typed invalidParams**（T3）：源链可读但零
   transferable（pristine 源）时 payload nil——F7 固定 token 集无
   「noTransferableSource」位，全拒批语义（目标侧拒）也不适用；裁定 = caller
   错误 → `invalidParams("the source carries no transferable grade
   adjustments…")`（封闭表既有码；copy 先行枚举可避免）。源 sidecar 不可读
   = 全拒批 unreadableSidecar ledger（在集内）。
7. **S2 预热观察证据**（D-M7-4-8 观察面）：e2e/验收轮宿主经 env 门零预热
   CPU、零真实根 seeding（§偏差 3）；冷窗收敛实测留档 = T2 轮 373s vs T1
   轮 385s（含 runner 门前后对照）；真冷窗 ~50s 数字正本仍是 M7-3 第二路
   实测 50.2s（本波未重测冷窗——env 门使然，如实申报）。
8. **SidecarV10Tests :327 future-tolerance 法语义退化**（CHECKER C1 申报
   面）：硬编码 `schemaVersion = 11` 字面 bump 后 = current，法仍绿但
   forward 守卫面消失——V11 第五法（schemaVersion 12）重正守卫；V10 文件
   零触维持（`git diff` 亲证零行）。
9. **e2e 可选锁窗腿未行使**（T1）：锁语义侧写以同测试内「退出前第二
   project_open = typed projectHeldByOther」承载（确定性强于 12s 窗内竞速
   形），未另立时间盒腿——SC「可选腿（时间盒内顺手）」条款内不行使，非
   静默放宽。
10. **⑥/H3③/特殊事项 5 三处措辞校订注记**（T1 action 4 兑现；M7-3 签核文
    档零回改——`git diff` 亲证零行）：修后 stdio 优雅面**成真**（此前双臂
    皆惰性：http = kernel 地板、stdio = watcher `events:0` 惰性）；不对称
    变为「stdio graceful / http kernel-floor」的真实差异。**F2 真机理表述**：
    bounded re-poll 的 250ms 超时只封阻塞相上界——恒可读 fd 上 poll 就绪即
    返，超时形本身不构成速率限制（「超时形消解忙旋」为假命题）；忙旋消解
    本体 = 纯 POLLIN 臂的 250ms sleep（4Hz .utility 帽）；真管道 HUP 到达
    时下一轮 poll 立即返 HUP 不经 sleep 臂（12s 活性窗无扰，e2e 0.87s 实证）。
    dup2 卫生修后仍必要且更 load-bearing（无 dup2 测试宿主真 stdin 关闭即
    exit(0) 自噬；有 dup2 + sleep 臂 = 不自噬不忙旋）。UPSTREAM-QUEUE 三观察
    项（tasks/wait_task 面 / paste per-target 版本化 / 库域批量写 +
    withTimeout v2 B 线）随翻账入队。

## §3 上游分歧与行为变化申报

- **保留 render 步快照检查**（D-M7-4-9，与上游 `6203791` 唯一分歧）：快照
  在渲染前 = doomed job 免付全渲染成本（成本门非正确性门）；正确性门 =
  link() EEXIST。`ExportRenderer.swift :633-637` 快照门零触（diff 面核）。
- **exFAT/无硬链接卷行为变化**（F13）：`.fail` 档在 EOPNOTSUPP/ENOSYS 卷
  （含本工作区所在 /Volumes/UNITEK 类外置卷）从「可导出」翻「渲染满成本后
  必败」（`encodeFailed` 兜底）——EOPNOTSUPP 降级回 plain rename 不入本波，
  挂 UPSTREAM-QUEUE 可选项（勿静默）。
- **tmp 命名/清理终形**：`.<name>.<uuid>.tmp` 同目录隐藏 tmp；defer 清理
  零残留（glob 断言钉死）；encoder-error 清理腿 exclusive 臂**不触
  destination**（F4——可能是 TOCTOU 窗内他进程文件；checker 全走查确认
  destination 触点恰一处已改道，gain-map 编码器自有 ciTmp/rewrapTmp 非此面）。
- **destructiveHint 语义**：paste_adjustments destructiveHint:true → 集断言
  9→10——M2-9 Export 页冲突档/UI 零联动（MCP 注解纯描述面），checker 未提
  异议，裁定维持。
- **paste source live 读盘 ≤2s 滞后姿势**（F11 申报）：source 为 GUI 正在
  编辑的图时走盘上 sidecar（≤2s debounce 滞后于 live 态）——与 GUI Copy
  Adjustments dialog 同姿势（dialog 同读盘）；target 有 live 硬拒、source 无
  对称面 = 申报面非缺陷面。
- **per-target reason 固定 token 集钉形**（F7）：notSessionMember /
  imageLiveInEditor / unreadableSidecar / internalError——应答 JSON 字符串
  非 16 档封闭表错误码（McpToolRegistry.swift 零 diff 机检过）；全拒批 =
  appliedCount=0 诚实应答非 throw。
- **targets 重复项 invalidParams 拒绝形**（F10）：`Set(targets).count !=
  targets.count` 一行 guard——显式 > 隐式（静默去重掩盖调用方 bug）。
- **get_history 顶层 author = position 真位式**（F8）：
  `stack.position >= 0 ? stack.items[stack.position].author : null`——红尾
  fixture 一腿钉死（position 3 + limit 2：最新 kept item ≠ position item，
  顶层读 position 位）；pristine/空链 .null。

## §4 S3/O1 漂移注记（维持裁定）

复制体在测试桩内（makeGuiShapedProvider——GUI 装配闭包的测试孪生）；产线
单源由 T3 Catalog 抽取建立（GUI model 委托 + MCP 双消费）。漂移注记维持，
不另抽测试桩（T2 行使记录，正本 = M7-4-CONTEXT 顺路件③）。

## §5 红线族机检终值（T7 全 PASS）

零新 SPM（Project.swift dependencies 块零 diff，恰一行 SidecarV11Tests 登记）
/ `.metal` 全域零 diff / HistoryHash.swift 零 diff / McpToolRegistry.swift 零
diff（McpTimeouts 同文件零触——16 档封闭表 + 超时档零新增）/ ExportNamer.swift
零 diff / LibraryProjectController.swift 零 diff（FIX2③ 第三波维持）/
PixelPipe·V50Order·ModuleRegistry·DrtRecord·TerminalTailPolicy·DrtTailAssembly·
DrtEotf·PipelineDocument·NodeGraphCommand·Lut3dKernels.metal·NodeOwnershipCatalog
零 diff / isAdjustmentTransferable 全仓恰单一函数定义 / `.runModal(` App/Sources
零命中 / LocalizationValue 插值禁形零新增（唯一命中 = LightamerApp :2307 M3-1
既有文档注释，非本批行）/ Project.swift 恰一行 + BUNDLE-MAP 恰一行（申报内）/
xcstrings 恰三尾块插入 + 一原位改（hunk ×2）/ UserDefaults 零新键 /
SidecarV10Tests 零触 / M7-3 签核文档零回改 / zh-audit --check（1698 keys）+
--self-test 双 PASS。

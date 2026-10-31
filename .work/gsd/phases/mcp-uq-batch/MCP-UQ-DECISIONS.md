# MCP-UQ 增量批 DECISIONS

## D-UQ-0 执行事故：Project.swift 登记行误删（已修复，亲证纯插入）

执行期登记新测试文件时，一次 PUT 范围吞行误删了
`McpControlToolsetTests.swift` 登记行（后一次修复又吞
`AgentControlCoordinatorTests.swift` 行，均已补回）。症状 = App 轮
1075（=1073+17−15）对不上 4443+17=4460。修复后 `git diff Project.swift`
亲证纯插入两行。教训：显式清单文件的行级编辑必须 diff 复核整文件
（本批已补该动作）。

## D-UQ-1 合成缝：三源合成，IopCatalog 零复列

`get_schema` 数据源 = IopCatalog（名录+type）× seed 编码默认 ×
range/meaning 手写表。手写面仅 range+meaning 两列（19 op 全行），
key 集/type 串/version/iopOrder 全消费现役单源——T3 guard 继续 policing
key，新增覆盖测试 policing 注记闭合。备选「Codable 反射全生成」否决：
语义（range/含义）反射不可得，与 IopCatalog 头注 research ruling 同理。

## D-UQ-2 range 口径：界面的，非 wire 的

上游 AgentSchema 注记 verbatim 借鉴（"The ranges are the interface's,
not the wire's"）：agent 越界 → 写面拒绝而非钳制。tool 描述 +
应答 note 双处明示。

## D-UQ-3 S2 配置形态：stdio 双块（非 HTTP）

Claude Code/Desktop 双块均走 `--mcp-stdio`（一进程一 agent，
与 launcher 模板/现役 headless 面一致）。HTTP 端点动态端口不适粘贴
配置；discovery 路径在 CLI 用法行与 config_hint 注记中交代。
备选「HTTP URL 粘贴」否决：端口 ephemeral，粘贴即过期。

## D-UQ-4 S3 只做 HTTP，不做 stdio 派生

一级门只走 discovery→HTTP（app 须开 + MCP 须启；typed refused 区分）。
stdio 派生（起 `--mcp-stdio` 子进程握手）看似能免「app 须开」，
实则抢 writer lock（只读降级）且与 GUI 会话语义分裂——二级 native CLI
立项时再议。任务书「stdio/HTTP 握手」落为 HTTP 单腿，特此申报。

## D-UQ-5 stdout 纯结果 discipline

成功时 stdout 仅结果 JSON（list 为换行名录，call 为 content 文档），
一切诊断走 stderr——LightCraft docs/mcp.md 同款 pipe-safe。
`stdoutSink/stderrSink` 可注入（测试劫持面；生产默认 fd 直写）。

## D-UQ-6 快照纪律：serial right 行使

本批行使 union 快照 serial right：editing domain 10→11（`get_schema`
只读零参），union 33→34。改动：domain 快照行 + union 行 + all33→all34
改名 + count 钉 11 处（union×3、SC7 direct-entry、control union、
refine 域枚举、editing+culling、host×2、launcher、searchstate）+
descriptionKeys 1 键 + tools.md 再生成 + SKILL.md count×3/枚举/§6。
destructive 集不变（10 枚）——只读工具零影响。

## D-UQ-7 测试 env 缝：headlessEndpointPaths 单源

`McpOneShot.resolveEndpoint` 默认 paths 走
`McpServerController.headlessEndpointPaths`（DEBUG 读
`LIGHTAMER_MCP_ENDPOINT_DIR` + release 默认），与 headless 臂同缝——
e2e 子进程测试经 env 注入测试域（L036）。

## 机器注记

- G4 透明越门：Data 卷可用 19387MB（<25GB 门），现实基线 ~19G，
  按先例透明越门；起跑前清 /tmp 残留（`mcp-*`/`lightamer-*`），
  ps 清零亲证（仅本 omp 进程）。
- `--monitor 7200` 伴跑（monitor.log），构建/全套全程看门狗在位。
- SPM：`tuist generate` 一次过；xcodebuild 带
  `-disableAutomaticPackageResolution` 离线先例。

## R1 域内自审 closeout（FAIL/2+14 → 全修）

- E-1：Project.swift 登记行误删（见 D-UQ-0）——已修复纯插入两行。
- E-2：onboarding 15 键补 en 值（家族双语惯例）。
- M-3 SKILL 枚举 11 + §6 nod；M-5 encodedDefaults 覆盖法（ΔN 17→18）；
  M-6 两断言硬化；M-7 caller-fault 码全扩 refused；M-9 marker 全串单源；
  M-10 help exit 2 注记；M-11 e2e 60s 有界等；M-12 NOTICE §V + 三文件头；
  M-14 转义合一；M-1/M-2 账本数字修正。
- M-4（xcstrings 空白重序列化 `": {`→`":{`）：接受——json.dump 全文件
  重写所致，语义零触（新键尾块 + 旧值 0 变 + 旧序保持，R1 §10 实证）；
  归一化需手写补丁机，成本 > 收益。
- M-8（stdout fd 级兜底缺失）：挂账——SDK 无 observed 噪音，`| jq` 场景
  硬化属二级 CLI 立项面。
- M-13（`mcp call render_preview` MB 级 stdout）：挂账——pipe-safe 但笨重，
  二级立项 `--out` 文件臂时消解。

## zcode review 修复轮（E-3 + B-2）

- E-3（error）：`jsonValue` 的 `value as? Bool` 首检被 Foundation
  NSNumber 桥接污染——`__NSCFNumber(0/1) as? Bool` 成功（0/1 数字
  默认值输出 false/true：temperature gains 1.0 / colisa 0 /
  exposure 0 / toneequal 十 band / equalizer g0-g5 全污染）。
  修 = 删首检，NSNumber 分支内 `CFGetTypeID(n) ==
  CFBooleanGetTypeID()` 判真布尔（Swift Bool 桥接后同属
  kCFBoolean，无需单独分支）。
- E-3 测试机理（镜像自洽教训）：旧 M-6「独立解码」把 wire 值再过
  同一污染函数自我镜像（`bool(false) == bool(false)`）——zcode
  review 指出后重写为五模块 Params init 转录的独立字面量断言
  （模块默认值改动则测试诚实变红）+ `testJsonValueTreatsZero-
  AndOneAsNumbers` 直测（0/1 六种数字装 + JSON 真布尔两枚）。
  「独立断言不得经过被测函数」入 L 教训候选。
- 旧/新双向亲证：新回归在旧 jsonValue 下 30 failures（红），修后
  绿——断言独立性实证非宣称。
- B-2（minor）：usage `list [--list]` 改 `list, --list`（旧写法暗示
  `mcp list --list` 合法而 parse 拒收）+ `usage.contains("--list")`
  注记断言。
- 封存面 17 件零 diff；G4 贴线透明越门（15.8G，§9 先例）；zh-audit
  --check PASS（1783/2116/10）；App Mcp 族 19 类定向全绿（250/0/0）+
  IOPP McpRenderParityTests 9/0/0（该类归 IOPP bundle，BUNDLE-MAP#107）。

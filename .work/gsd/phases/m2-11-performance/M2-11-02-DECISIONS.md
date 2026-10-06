# M2-11-02 DECISIONS — 执行期裁定（2026-10-07 夜间执行 worker；晨审可推翻）

## §1 D-M2-11-02-1（T3 终态）：nlmeans bounded 降载尝试三档试尽 → revert（默认退出）

尝试序按 KD-3/E4 执行（decimate 加深 57→37→29，无更浅档禁入项）；三档拖动②与引擎级
数字全录 `perf.md` §OQ-7-A。判定 = 全不达 16.6ms，且引擎单腿（26.5ms @29 趟）独自超门
→ decimate 杠杆数学不可达（线性外推达线需 ≤8 趟 = 观感崩坏）。处置 = 工作树 revert，
产线零 diff（AC#8 revert 分支字面成立）；`NLMeansParityTests` 零重钉（committed 档 pin
原样绿，IOPParity 362/3/0 全量定向轮亲证）；挂账行 + V2 备选语义移交 M2-11-04。
依据：OQ-7-A「不达即 revert 挂账——revert 是默认成功路径，强改硬凑是失败」+ plan 纪律
「不为凑 16.6ms 硬签观感回归」。尝试期工作树改动（offsets step 泛型化 + previewDecimateStep
档位常量）未产生任何 commit，随 revert 消失。

## §2 D-M2-11-02-2（T5 执行期发现）：Release 配置断代缺陷三修（commit `bff022e`，越界申报）

Release 构建自 09-05（09-26 产物）后从未再跑，两处潜伏缺陷在其后波次落地：
① `WorkspaceHostView` 对 `#if DEBUG` 专属的 `EditorProbeIfRequested` modifier 在**未
guarded 调用点**链入（Release 无此类型 → 编译失败）；修 = 调用点 postfix `#if DEBUG`
（Debug 面逐字节不变）。
② 同文件 import 完成回调 Task 内可选链复合表达式触发 Release -O 类型检查超时；
修 = 两个 optional 提升为局部量（语义不变）。
③ `AIWorkerClientTests.testIPCChannelSpikeBenchmark` 引用 `#if DEBUG` 专属的
`AIWorkerMain.spikeOp` 无 gate（Release worker 对 "spike" 应答 unknown-op，测试在
Release 本就永不可过）；修 = 整函数 `#if DEBUG` 门控（func 计数不变，Debug 面不变）。
处置依据：夜间授权 + PERF-06 Release 复核为本 plan 明文义务、三修皆 Release-only
编译面最小修复 + Debug 构建复验绿；T5 ledger 行已随 `e19a03f` 落账。晨审若裁越界
回退 = revert `bff022e`（Release 构建随之复断，T5 义务不可达——附此dependency 注记）。

## §3 D-M2-11-02-3：Instruments .trace（465MB 级二进制）盘上归档、不入 git

两 trace 合计 465MB（hitch trace 432MB 因 Animation Hitches 模板含 Metal/显示全表）。
入 git = 每克隆永久背负，与仓内既有证据惯例（截图 KB 级）冲突。处置 = 盘上归档
（`profile/*.trace` 在位，AC#6「归档」字面成立）+ `.git/info/exclude` 本地排除（先例 =
`.planning` 垫片 2026-09-28 裁决）+ **可入 git 的导出证据随批提交**（hitches 表 XML
135KB + 分析脚本 + summary + TRACE-NOTES）。checker 复核走盘上文件 + 导出证据双通道。

## §4 D-M2-11-02-4（T6 通道）：computer-use 不可用于 subagent → AX 回退 + Manual-Only 行

computer-use SDK 本执行面实测返回 "Computer Use is not available in subagent"（主 agent
专属策略——M2-3 方法学授权面在本 worker 环境被平台层拒绝，非用户授权缺位）。回退 =
System Events AX 驱动（表单处置/按钮/滑块轨道 click 实测可达；M2-7「synthetic pointer
不达」为无 AX 的 CGEvent 路线，AX 路线实测有效）。结果：编辑会话 trace ×2 真采集
（probe 自动化缝 + AX 驱动）；hitch 拖动场景 >50ms = 0（Animation Hitches 仪器 498 帧
全单帧 16.67ms）；缩放/平移/万张滚动三场景无 AX 驱动通道 → **Manual-Only 登记**
（plan KD-6 兜底条款），不阻塞本 plan 其余任务收口。万张 fixture（10k × 256² JPEG）
已备于 /tmp（即弃，L009）未消费。

## §5 D-M2-11-02-5：RAW9 CoreML 编译冷不可复现（磁盘缓存命中态）

T4 探针实测 A7R V decode cold 0.176s——CoreML 编译产物跨进程磁盘缓存命中；在案
2.62s（13-1 perf）为首编译态。清系统缓存属环境破坏性操作，不在执行半径。落账 =
PERF-05 编译冷行以「磁盘缓存命中态实测值 + 在案首编译值双注记」呈现；M2-11-04 重述批
若需硬数字须显式清缓存轮（登记为待人工/待专项）。

## §6 D-M2-11-02-6（观察项 O-1）：RAF 100MP 静态 warm 双峰噪声

静态 warm RAF 列三轮中位跨 14-42ms 两态（ARW 无此现象；拖动帧型两档链亦见尾尖峰带
10-52）。疑源（入口平面 CI 腿状态机 / GPU 时钟态 / 内存压力）未定位。处置 = perf.md
O-1 观察项 + M2-11-05 GUI 验收轮顺带观察；不判缺陷、不设门（KD-1 判定不在测试内
断言纪律的账面延伸）。

## §7 预算/纪律对账

- 改码半径：AC#8 达成——产线 diff = WorkspaceHostView 三处（D-M2-11-02-2 申报越界，
  Release-only 编译面）+ 零 PixelPipe/NLMeansModule 命中（T3 revert 后 `git diff` 亲证
  LightamerCore/LightamerIOP/App 于 T3 维度零 diff；bff022e 两文件为唯一产线 hunk）。
- `--all` 未跑（批准制未申请，plan 纪律 5 收口跑定向轮：IOP + IOPParity + EXPORT 全绿
  + SESS Release 轮 1/0/0）；全套留 M2-11-05 终验。
- 提交七件：de424d0（T1）/ 7e79a2e（T2）/ bff022e（T5 修复）/ 7a87eaa（T4）/
  e19a03f（T5 账）/ T6 证据批 / T7 收口批。未 push。

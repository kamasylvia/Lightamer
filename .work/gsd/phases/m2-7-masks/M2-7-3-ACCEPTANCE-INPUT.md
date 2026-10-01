# M2-7-3 ACCEPTANCE-INPUT — 验收 subagent 移交清单（M2-7 phase 收口批）

> 输入唯一入口（M2-5/M2-6 移交口径；plan 7b88bbb KD-4）。执行批 commits =
> `853172e`（走查证据）/ `60582c3`（熔断行）/ T2 perf.md / `78b4f0f`（zh 键）/
> T4 翻账批。plan AC 总表 = `M2-7-3-PLAN.md`（8 条，机检方式逐条在表）。

## 一、AC 指针（三 plan）

| plan | AC 表 | SUMMARY（机检记录） | 验收状态 |
|---|---|---|---|
| M2-7-1（数据/内核） | `M2-7-1-PLAN.md` 12 条 | `M2-7-1-SUMMARY.md` §AC 总表 12/12 | **已验收 PASS**（`M2-7-1-ACCEPTANCE.md`，0e+0m，`93ca9e7`） |
| M2-7-2（面板/交互） | `M2-7-2-PLAN.md` 11 条 | `M2-7-2-SUMMARY.md` §AC 总表 11/11 | **已验收 PASS**（`M2-7-2-ACCEPTANCE.md`，0e+1m 已修，`bf2a4db`） |
| M2-7-3（收口，本批） | `M2-7-3-PLAN.md` 8 条 | `M2-7-3-SUMMARY.md` §AC 总表 | **待验收**（本清单移交对象） |

## 二、熔断裁决记录（验收复核重点；可推翻——plan 风险节：裁决记录 = 输入非结论）

- **裁决**：OQ-4-C 熔断**行使**——Follow Edges UI 默认 mode 翻 `.snap`
  （`60582c3`，App 域 429/0/0 定向复归平 P2 基线）；walker 与 `.streamline`
  分支保留，模式选择器仍可选；streamline 完整流线**挂 V2**。
- **判据实测**（正本 = `evidence/m2-7-3/probe/probe.log`，叠加图 ev_*.png）：
  - 判据① 冷 6.3ms 中位（×10，probe.log 在案值）/ 热 ~0.001ms（×100）——远内 200ms，未触发；
  - 判据② **触发**：8 景盒 × 2 阈值 streamline 链长 ≤3 点；100-seed 网格
    82/100 空；场分辨率（1024/2560）× 步长（1.5/0.75）扫频 0/3 功能链
    （排除降采样假说）；snap 12px 触达内确定性 2 点贴边线；
  - 判据③ n/a（seam 只跑 preview 桶；FULL 单发 73.7ms 语境数字在 perf.md）。
- **走查形态限制（复核时须知）**：GUI pointer 注入环境不可达（synthetic
  click 不达窗口——P2 E3 同根因），走查 = 进程内真链探针（CIRAW 真解码 +
  真 kernel 原文编译 + FollowEdges.swift 原文，shim 仅脚手架）+ GUI 工具栏
  武装态截图。推翻渠道 = 验收方以自身 GUI/实机证据对照，或复核 probe.log
  方法论（`probe/main.swift` 全文在案可复跑）。
- **REQUIREMENTS 措辞**：M2MASK-05 已带 P3 注记「Delivered（snap 态，
  streamline 挂 V2）」——若验收推翻熔断（实证 streamline 可用），回改措辞
  单批同步（plan 风险节口径）。

## 三、挂账清单（非阻塞，非本 phase 缺陷）

1. **GUI 交互五点实操证据**（E3 延续，逻辑面单测已覆盖）：缩略格渲染 /
   锁删 toast / Locate 页签联动 / 双羽化手柄拖动 / Default Behavior ask
   sheet——AX identifier 不可读 + IME 截获 + pointer 注入不可达，环境受限
   （`M2-7-2-DECISIONS.md` §四）。
2. **缩略 pass 运行时数字**（perf.md 表二）：探针不可达（Core framework
   闭包拉 libwebp 模块）+ GUI 无蒙版内容可渲（无 pointer 绘制）——架构面
   （O(缩略像素) + LRU + 零新 queue）已由 P2 AC1/AC9 钉，数字留实测。
3. **streamline V2**：walker 对真实照片脊型失稳（本批走查实测），修复方向
   （脊线预提取/亚像素质心/自适应步长）入 V2 节；`.streamline` 分支与模式
   选择器保留，复活零重写。
4. **M2-7-2 已登记转记**：filmstrip 缩略图单击/双击未切换已载图像（Session
   既有面，非蒙版域）。

## 四、Manual-Only 候选（GUI 验收轮 / 真机批）

1. 真机 HDR 屏 + 100MP 样张 Follow Edges 全流程手感（含判据③ FULL 路径
   若 V2 启用）。
2. 双羽化手柄拖动实时性（超标 fallback = 拖动中缩略窗口平面预览——挂账级，
   本 phase 未实现）。
3. 蒙版缩略图 GPU 管线目测（三腿腿型 + LRU 逐出行为）。
4. 锁删 toast / Locate 页签联动 / ask sheet 三分流实操。
5. Follow Edges snap 模式真机手感（阈值/强度/方向三参数滑杆实操）。

## 五、验收方式建议

- 复跑口径：`caffeinate -dis Scripts/test-direct.sh --bundle App|--bundle Layers`
  （本批源码增量仅 App 域一行 + xcstrings；全套终跑数字在 M2-7-3-SUMMARY
  §测试数字，采用执行方声明对账 + 抽域复跑同 M2-7-2 先例）。
- 机检随手可用：`uv run python3 Scripts/zh-audit.py --check`（exit 0）；
  `git diff bf2a4db..HEAD --stat`（P3 真窗口：源码面 = LayerEditingState.swift +
  Localizable.xcstrings 两文件 + .work 申报面，零第三类）。
- 熔断复核入口：`evidence/m2-7-3/probe/probe.log` + SUMMARY §走查裁决。

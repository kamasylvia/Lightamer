# R6-R1 修复批 — SUMMARY（2026-10-27）

基线 = `fb32ef92`（全套 4292/35/0）。批 = omp FAIL 回注：B-1 第二病灶诊断
+ 真修（issue #8）+ m-1 DRT 面板诊断与修复（issue #9）+ 机制回归 + 收口。
裁决正本 = `R6-R1-DECISIONS.md`。

## 一、战果

### B-1 第二病灶（blocking 正主，commit `80f8814f`，issue #8）

- **机制（插桩实证，非推断）**：SwiftUI `onChange(of:)` 值输入重估丢失——
  失败轮 trace：`fire(.completed)（adapter 应用终态）→ tail nil 写 →
  modifier body 重估读到 nil（@State adapter 完好、无重挂载）→ onChange
  永不消费该转换`。nil 是 run 最后一个写，一次丢失永久丢失（~28%/轮）。
  复活/重挂载/else 早退三假说实证排除；R6 invalidate 语义维持闭合。
- **修法**：run tail 直接事件通道——`onImportRunEnded` 监听面（nil 写后同
  main turn 同步触发，clear-first）；ImportProgressModifier 注册 adapter
  时挂臂，闭包 = onChange else 臂逐行镜像；双通道幂等（谁先谁 nil 掉
  @State adapter）。onChange else 臂保留（挂载前在飞 run 边缘）。
- **回归**：+3 确定性机制法（tail 事件排序契约 / onChange 结构性缺席世界
  的 finish+reload 必达 / 无挂臂 no-op）。
- **GUI 统计功效**：修复构建 **0/35 零行**（20 轮批 0/20 + 终版 15 轮
  0/15；未修复基线 28%/轮 → 15 连绿概率 ≈1.7%）。omp 判据（0/15）满足。

### m-1 DRT 面板（minor，commit `0507135b`，issue #9）

- **黑盒复现**：probe-stay 实例 + AX 位置聚类压 tab——vignette 在、DRT
  控件零（omp6-09 表型）。
- **机制**：AR-01 m11 lazy-build 化 else 臂留 `EmptyView`——该挂载语境
  不给无内容视图发 appear（插桩：body 一次 model=nil、onAppear 零触发；
  鸡生蛋死锁）。Film 同款存活因常驻 header。
- **修法**：else 臂真零尺寸叶（Color.clear height 0）——A/B 实证 onAppear
  触发 + 全控件渲染（方法/Rec.2020/ST 2084/峰值/限色）；峰值设 100→400
  nits 实时回读。R6 T3-DRT 存活链唯一 blocker 已除（GUI 重驱动移交下轮）。

### T5 收口

- 封存面 17 件零 diff（产品面 = 3 App 文件 + 1 测试文件；Core/IOP 零 diff；
  WorkspaceModel 未触——无载体族例外申报需求）。
- 全套 `Scripts/test-direct.sh --all`（guard + ps 内联清零 + `--monitor
  21600` 伴跑 + nohup disown）：

**全套终值 = 4295/35/0**（基线 4292/35/0 + Δ3，3997s，零 MEMFAIL）

- Δ executed = +3 精确吻合新增测试法数（ImportCompletionRegressionTests
  +3）；skip 35 恒定（零波动）。
- per-bundle：IOP 788/1/0（RSS 5779MB）· IOPParity 529/11/0（5326MB）
  · Layers 507/5/0（1178MB）· **Library 782/4/0（746MB，+3 = 本批新法）**
  · Sessions 285/4/0（1207MB）· Export 385/4/0（4956MB）
  · App 1019/6/0（2832MB）——除 Library +3 外与 R6 登记值逐位同；全部
  <8G MEMFAIL 门；DrtPersistenceTests teardown SIGTRAP flake 未复现
  （全套绿，obs-1 维持观察登记）。

## 二、commit 列表

| commit | 内容 | issue |
|---|---|---|
| `80f8814f` | fix(r6r1): drive the import run-end through a direct tail event | #8 |
| `0507135b` | fix(r6r1): give the DRT lazy-build appear hook a real leaf | #9 |
| （收口） | docs(r6r1): R6-R1 ledger — summary + decisions | — |

## 三、卫生

- GUI 实例逐一 kill 清零（ps 复核 0）；`library.recentProjects` 探针污染
  整键删除；/tmp fixture 即弃域留存；px 代理一开一关（gh 建单 + push 期）。
- issues #8/#9 经 gh 建单（代理期），commits 带 `fixes #8`/`fixes #9` 随
  默认分支推送自动关闭；issue 描述含机制+验证摘要。
- obs 登记 3 项（teardown SIGTRAP flake / tab 轨索引漂移再证 / 图库网格
  cell 无 AX 物化），见 DECISIONS §五。

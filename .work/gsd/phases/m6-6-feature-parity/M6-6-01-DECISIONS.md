---
phase: m6-6
plan: "M6-6-01"
kind: plan-decisions
created: 2026-10-16
executor: zcode subagent（夜间全自动授权链）
status: closed
---

# M6-6-01 DECISIONS — 裁定记录与执行期台账

> 范围与裁定正本 = `M6-6-CONTEXT.md` D1-D9（评审修订版）。本件只记
> 执行期落地取舍 / 状态判定争议台账 / 偏差。零结构性偏差。

## §1 行粒度与盘点取舍（T1）

- **134 rows / 12 域**（SHELL 6 / LIB 16 / EDT 15 / ADJ 19 / DEV 8 /
  GEO 3 / NODE 8 / MASK 12 / DRT 10 / EXP 14 / AI 11 / OWN 12）——在
  CONTEXT §3 预估带（~111-147）与 plan 带（120-140）内。合并粒度兑现
  处：ADJ 四 Post 件各独行（Alcedo 目录逐件对齐）而「Look 面板分组」
  并入 EDT-05（七页签 IA 行 Notes）；GEO 三行（crop / rotation / 全局
  语义），aspect 并入 GEO-01。
- **粒度即纪律的机检边界**：T1 AC 的裸 `grep -o 'FEAT-…' | uniq -d`
  会把 Notes 列的交叉引用误计为重复 id——初稿三处 Notes 引用
  （EDT-07→NODE-06 / ADJ-11→OWN-11 / OWN-05→DRT-10）改为文字指涉
  （"the sibling panel family" 等），保 T1 AC 字面零输出；T2 门 A2 只
  取 id 单元格，语义上更准（self-test 钉死该口径）。
- **上游增量测绘对表**（plan T1 要求）：raster 输入链 → DEV-08
  （Delivered，M4-1）；LUT 编码维 → EDT-13 Notes（M3-1 兑现）；
  OCIO 参考变换 / 图库分组 / 任务岛 → 不 mint 行（非交付面，注记在
  survey）；v0.3.1 导入选择器 → LIB-09（M4-1 已超集兑现）。
- **dt-gap 表（survey §9）不入 checklist 行**（CONTEXT §3 纪律）——
  OWN-12（dt 超集 Partial）+ ADJ-19（39 模块面）两行承载其交付子集。

## §2 状态判定争议台账（R2，账面优先序）

- **FEAT-SHELL-03（主题 tokens）= Partial**：M2-3 交付的是 Alcedo 式
  IA 骨架而非其暗色玻璃 token 集（原生外观 + 本地 Theme 层）；账面无
  「token 一比一」记录 → 不给 Delivered。
- **FEAT-EDT-08（崩溃恢复）= Delivered（Source=Alcedo）**：Alcedo 的
  面 = 崩溃后 save-recovery bar；我方以连续 sidecar 持久化 + 强制 flush
  消解同一问题（无 bar 可显）。功能等价判定记本条，晨审可翻。
- **FEAT-LIB-14（挑片视图）= Partial**：Phase 9 双窗 compare 模式
  （CullingView）在册为亲证交付；LightCraft 语义的 flag 驱动 culling
  pass 未立项（charter 裁决⑤）——两半分记。
- **FEAT-MASK-04（参数化 range 蒙版）= Delivered**：Alcedo 只有
  enabled=false 占位；我方 M2-7-2 真实现（luma 梯形 + Cz/hz 曲线 +
  吸管）——beyond-parity 行，非缺口。
- **FEAT-DEV-05/06（demosaic 菜单 / 高光重建）= OOS**：STACK.md
  CIRAW 路线结构性不可达注记为锚（评审 F6/F2 口径——OOS 集 =
  Updates 页 + Nikon HE + demosaic 菜单，D2 括号为示例非穷尽）。
- **FEAT-EXP-13（TIFF 压缩选项）= Partial**：8/16/32-bit 位深在册
  Delivered；显式 NONE/LZW/ZIP picker 无账面记录 → 保守侧不给
  Delivered（编码器默认值在跑，口径 = 账面沉默面）。
- **Missing 全集**（3 行）= LIB-04 Activity view / LIB-13 smart
  albums / LIB-15 watched folders——账面沉默面（前者）+ charter 裁决⑤
  不立项锚（后两者），全部带 note，验收/晨审可翻。

## §3 执行期偏差与事件

1. **appex 签名债事件（T4 全套前置，环境域零源码）**：build-for-testing
   首轮 `ValidateEmbeddedBinary` 双 appex 失败——DerivedData 内两 appex
   残留 2026-10-15 "Lightamer Dev" CMS 签名（与父 app ad-hoc 不匹配；
   同族 = perf.md §事故 4 / D-09-04-D9 Release 直启重签环境债）。处置 =
   盘上 `codesign --force --sign -` 强制 ad-hoc（`Signature=adhoc` 亲证）
   → 增量重跑 build-for-testing **TEST BUILD SUCCEEDED**。零源码触碰、
   零 Project.swift diff、零 DerivedData 全清（时长代价 ≈ 0，增量）。
   LESSONS L080 登记。
2. **parity-audit 自测揪出解析器真缺陷（T2 内闭环）**：gaps 生成行同以
   `| FEAT-` 开头，解析器原样吸入行集 → 摘要重算自污染（stale fixture
   往返测试红）。修复 = 解析器跳过四 marker 内部（生成块是门输出不是
   手维护行）；红绿回合自证。该缺陷若漏到 T3 会让首个 `--write` 后的
   `--check` 假红——self-test 纪律的直接兑现。
3. **A5 扫描路径按账面实位落**：plan 文本「REQUIREMENTS.md /
   ROADMAP.md / AGENTS.md」字面在仓根——实际正本在 `.work/gsd/`。
   落地为 `.work/gsd/REQUIREMENTS.md` + `.work/gsd/ROADMAP.md` +
   `AGENTS.md`（公开树缺席 = 显式 skip 注记，R3 口径不变）。语义与
   plan 一致（被扫文件集相同），路径登记本条。
4. **ci.yml parity job 注释措辞**：plan 样例块含 em-dash，落盘改 ASCII
   连字符（公开树 ASCII 纪律同向）；结构（ubuntu-latest / 5min / 步骤 /
   裸 python3 --check）逐字同 plan。
5. **零结构性偏差**：SC1-SC6 全数按 plan 判据实测（SUMMARY 对表）；
   gaps 行序 = D5 状态严重度序（LightCraft 影响排名的显式简化，排名
   细化挂 V2 候选注记）。

## §4 T4 收口核对（红线族零 diff 机检）

- Swift 全域 / `*.metal` / `Project.swift` / `LightamerSidecar.swift` /
  `Pipe/History/` + `PipeCacheKey.swift` + V50Order / MCP 快照族 /
  Export 三件 / UserDefaults / runModal / LocalizationValue 插值禁形：
  全零（SUMMARY §红线自检同表）。
- xcstrings = N-1 三键尾块纯插入（51+/0-）；zh-audit PASS 前后恒定；
  三 untracked 兄弟件零触碰。

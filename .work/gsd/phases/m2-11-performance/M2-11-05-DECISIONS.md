# M2-11-05 DECISIONS — closeout 裁决签注（KD-1..5 + 执行期裁定 D1..D4）

> 裁决正本；与 SUMMARY/INPUT/VALIDATION 互引。晨审可逐条推翻。

## KD-1 终验证据组织 —— 签注

- 净轮 = 第 3 试全套（前两试 App 段崩）——「任一 flake 复现 → 台账记账 + 恢复协议，
  终值以干净轮为准」**字面兑现**；判定式 `16+Δs` 保形（Δs=0，M2-11 新测经 E3-a
  零 skip 增量，checker E3 回注免凑数条款未触发）。
- L055 核读 = 脚本机检（verdict 全 ok）+ 人工七日志 tail（abnormal=0/ANE=0/末条
  Executed 全挂靠 All tests）双保险，INPUT §2.1 表逐行在案。
- **D1（崩点归属裁定）**：App bundle 四红非单一 ANE 亦非测试缺陷——ToneEqual
  encode 路径悬垂 retain（swift_unknownObjectRetain，2 .ips 同栈 mod dispatch 函数），
  崩点漂移 = 堆态依赖；产线零 diff（9586c1b..HEAD IOP/Core 空）排除回归 → **潜伏
  旧账**。环境协同因子（Data 98% 满 + Metal shader cache MDB_MAP_FULL + 重编译
  风暴）为触发放大器而非根因——隔离复绿 + 卫生处置后净轮落地佐证。归属 = 晨审裁
  （修复批 fix 或 Maintenance M4）。
- **D2（分域口径注记）**：Version 域 = Sidecar（.lra v7 versions）+ Library（.lalb
  version_ref）两目录并检——plan 未给字面路径，按 M2-8 交付面取域；三域全零命中，
  口径取宽不改变结论。

## KD-2 GUI 一轮四义 —— 签注 + 通道边界

- 四义全有着落（证据行/补测行/Manual-Only 行三形态——AC#5 字面）。
- **D3（Manual-Only 判据）**：四条通道边界实测后登记——①合成右键不开 SwiftUI
  context menu（grid 双入口腿）；②LazyVGrid cell 零 AX 暴露；③hover 门控按钮
  （预设导出 save-panel 腿；同族 NSSavePanel 已由 Backup Project 腿 live 覆盖）；
  ④NSOpenPanel 路径表单 IME 截键（万张滚动腿）。全部带机器门在案说明，非静默降级。
- 走查 FINDING 只登记不修（纪律 1）：FINDING-F（L057 家族 LUT 导入 .cube 取消
  SIGSEGV——签名消息与 L057 逐字同源；.ips 归档）+ FINDING-G（标记菜单裸键，
  F-2 同族）。

## KD-3 挂账总汇编 —— 签注

- 两栏单一清单 = INPUT §4.4（Maintenance M1-M7 / V2+观察 V1-V17）——各 phase
  挂账原文零改写，逐项带锚；M2-10 十项落位：关闭三项（#5 视觉走查 / #9 性能表 /
  #10 flake 台账）、同源落位一项（#8→M1）、维持六项。
- 新登记 error 级两枚（M4/M5）入 Maintenance 栏并标注「归属晨审裁」——清单为唯一
  移交面。

## KD-4 VALIDATION-INPUT → C 档第 3 停 → 翻账批 —— 签注

- INPUT 四节齐（机检/终验/GUI/SC 对账+挂账+签核路径）后即 C 档第 3 停；夜间授权
  在案（D-07-3-T5-1 先例 + 「开跑，不要停」）→ 同批落签 VALIDATION + 翻账批
  （KD-4.2 授权形态字面适用）。
- **M2NODE-03 呈报（禁静默条款兑现）**：INPUT §4.5 + VALIDATION 特殊事项 + 本条
  三处显式——翻勾依据 = checker E2「翻勾逾期带指针件」（TODO.md M2-5 批「add 面
  严格化」+ M2-5-3-ACCEPTANCE）；晨审可裁保持 uncheck（届时 revert 该行翻勾，
  其余翻账不受影响）。
- 翻账批 = REQUIREMENTS/ROADMAP/STATE/TODO/GOAL-STATE 五处同 commit（`3f91221`）
  + 历史行零改写（追加/翻勾/续接点整体翻新——纪律 4 字面）。

## KD-5 PERF 重述门对账形态 —— 签注

- 三态判定无第四态：达标七门 + 挂账一门（denoise→V2）+ 观察项四枚（O-1/fit2560/
  万张滚动 Manual-Only/渐进显示）——INPUT §4.1 逐行三列；门不硬签（各 plan
  DECISIONS 裁决为准——02 波 OQ-7-A revert / 03 波 KD-4 未触发 / 04 波 OQ-1-A）。

## 执行期裁定补充

- **D4（证据命名勘误）**：走查批 .ips 初名 `appbundle-crash-2026-10-07-0937-*`
  误标（实为 GUI 走查崩非 App bundle 轮）→ 已改名 `guiwalk-crash-2026-10-07-0937-
  lut-import-panel.ips`（`b5fa68a` 前落盘，MANIFEST 行 23 指针正确）。
- 磁盘/缓存卫生（ktrace 残留 3.7GB + 陈旧 DerivedData 容器 1.7GB + Metal cache
  + 测试残留）= 可再生缓存清理，非用户数据；系恢复协议处置段，随 §2.3 在册。

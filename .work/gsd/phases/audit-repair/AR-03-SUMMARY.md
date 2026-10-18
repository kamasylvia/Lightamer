# AR-03 SUMMARY — plan C(机械小件批)执行摘要

> 执行批 = audit-repair plan C(AR-03),2026-10-18,单 executor 串行
> 于 AR-02 闭环后(plan depends_on 兑现)。同 worktree
> `/tmp/la-ar-bc-wt`(branch `audit-repair-bc`)。

## 任务清单与 commits

| 任务 | commit | 内容 | 判定 |
|---|---|---|---|
| T1-a overlay/background 15 | `7640ed2e` | 6 overlay + 9 background → 尾闭包形(ShapeStyle/`in:`/alignment 合法重载零触) | PASS |
| T1-b 杂项 8 | `8c0514a9` | showsIndicators ×3 + foregroundColor ×1 + onCommit ×1 + coordinateSpace ×1 + dropDestination ×2 | PASS(dropDestination 语义让渡申报 D-AR3-3) |
| T1-c cornerRadius 14 + menuStyle 5 + onChange 1 | `af4581c7` | clipShape 换形(圆角值 verbatim)+ menuStyle 钦定对(.menuStyle(.button)+.buttonStyle(.borderless))+ onChange 双参形 | PASS |
| T1 fixup | `8f78f392` | coordinateSpace → `.named(...)` factory(SDK swiftinterface 对表,plan 红线「编译失败回正本重对表」行使) | PASS |
| T2 minor 五件 | `5d522e88` | m1 AnyView 收紧 / m4 @Observable 迁移 / m5 private / m7 .task + once-guard 清 / m8 static let formatter | PASS |
| T3 验收 + 登记 | 本 commit | 定向轮 921/16/0 + 截图对比 3/5 亲证 + 挂账 3/销账 8 登记 + 收口文档 | PASS |

## 机检终值

- 五族 grep 清零:`showsIndicators:` / `.foregroundColor(` /
  `.menuStyle(.borderlessButton)` / `.cornerRadius(` /
  `.onChange(of:...) { _ in` —— App/Sources **全零命中**;43 处逐处
  对账表(行号零漂移)= DECISIONS D-AR3-1。
- 红线面:LibraryProjectController 零 diff;封存面全域零 diff;
  LightamerIOP 零 diff;xcstrings 零 diff;UserDefaults 零新键;
  Project.swift 零 diff;禁形机检两零命中(LocalizationValue 插值 /
  .runModal()。
- 定向轮:`--bundle App` **921/16/0**(325s,peakRSS 2832MB——与
  AR-02 净轮逐值一致;C 批零 ΔN 证实)。
- **全套 --all 净轮(收尾,C 后单轮,供件净轮)**:`3969/37/0`,
  2036s,零 fail 零 MEMFAIL(峰值 IOPParity 8113MB 贴 8G 门,机检门
  内——SPIKE 注记的贴线 bundle 口径)。逐 bundle:IOP 687/5、IOPParity
  460/3、Layers 494/5、Library 738/4、Sessions 284/9、Export 385/5、
  App 921/6。
- ΔN:**C 批 +0**;全批终值对账(executed 口径)= 基线 3963 →
  AR-01 +4 → AR-02 探针 +2(越 B 带 +0..1 上界 +1,显式申报)→
  AR-03 +0 = **3969/37/0**(全批终值带 3964..3972 内;skip = 基线
  35 + 探针族 2,逐族闭合)。首轮 --all(worktree 缺 input/ 本机
  供件)= 3969/132/0——供件域 skip 漂移 +95(golden/RAW 生成物不在
  git),拷主树 `input/` 后净轮回基线域;两轮 executed 逐值一致
  (3969),供件漂移只动 skip 不动 pass/fail——漂移面诚实申报。
  B 批 ΔN 口径终账修订 = AR-02 DECISIONS D-AR2-6(SUMMARY 同批修)。

## 截图对比(borderlessButton 唯一观感面)

3/5 执行批亲证**逐像素一致**(softproof / EDR / preset——同窗口
frame、改前 = 8e3bd59d 构建 vs 改后 = 本批构建,cliclick 展开 +
裁剪对比);2/5(FilterBar / CatalogFilterBar——legacy Session face
QA 通道)配方让渡 MANIFEST,实机验收批补判(D-AR3-5)。

## 挂账/销账终账

- 挂账 3:m10(复数)/ o4(翻译注释)/ o6(LutPanelView → D-6 专项
  卷)——零代码动作登记(DECISIONS D-AR3-6)。
- 销账 8:o1 / o2 / o3 / o5 / o7 / o8 / m2① / m3 notes + LANEA
  side-note 两行(F-5)——登记 DECISIONS D-AR3-7。
- 清单外残余:旧 View 实参形 overlay/background ~40 处未入批(冻结
  口径纪律),现成清单登记 D-AR3-8 供后续卫生批。

## 偏差清单

1. coordinateSpace fixup(+1 commit):plan 字面形不编译,SDK 对表
   `.named()` factory(D-AR3-2)。
2. dropDestination Bool→Void 语义让渡:视觉拒绝反馈消失、最终行为
   等价(D-AR3-3,plan 风险节预定申报面)。
3. borderlessButton 截图对比 2/5 让渡配方(FilterBar/CatalogFilterBar
   ——legacy face 导航链超时间盒;3/5 已证零差)(D-AR3-5)。
4. m8 dateFormat 保守口径维持终账(ISO 定长 = 检索语法契约面)
   (D-AR3-4)。
5. C 路合并 MANIFEST 未落盘(条款活线,静态基线执行)(D-AR3-11)。

## 走查(MANIFEST 配方,实机归验收批/用户)

配方与判据 = `.work/gui-acceptance/audit-repair-bc/MANIFEST.md`
(local-only):B/C 面板拖动 60Hz + m9 readout 复核行(m10 观察行)+
borderlessButton ④⑤ 处补判 + category/collection 拖入行为 +
cornerRadius/overlay 观感零差抽查。执行批机检证据 =
`/tmp/ar03-shots/`(前后截图六张 + 裁剪对比,即弃域)。

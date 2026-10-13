# M3-2 回溯二次验收报告（OMP 路双路并发终验，R2）

> 验收员：OMP / 日期：2026-10-10 / HEAD：`d57488ec` / 方法：零共享上下文亲读全部正本 + 上一轮 8 抽查点独立重验（日志直算/Python 复算/git 机检），只读未跑测试。
> 口径：HEAD 远超 M3-2 收官，演进差异标「后演进，不记账」。

## 结论头

`PASS / 0 error + 4 minor`

OQ 七条实质清零链成立；spike 证据在盘、关键数字逐值命中；设计三接缝与代码现状对表成立。4 minor 均为转录精度/历史引用形式面，无一动摇结论。

## 一、OQ 清零链（抽验 3 条下游兑现）

1. **OQ-3 资产 c 混合**：M3-3-01-PLAN L60-68 亲核——28 JSON 原样 + neutral 全表实测值回注 + 五件套逐字落地，与 CONTEXT D-M3-2-5/D-M3-2-8 同向 ✓
2. **M3-4-CHECKER 七项**（L178-185）：①..⑦ 与 CONTEXT D 条/OQ 推荐逐项对表零漂移；⑤ 引 RESEARCH :336「公开标准部分用公开参考值」亲核逐字 ✓
3. **OQ-4 无独立 D 条**：CONTEXT D 条仅 D-M3-2-1..8（grep 行号 16-85 在案），OQ-4 推荐仅载 OQ 节 L129-136 → 上一轮 minor-1 复核成立 ✓

## 二、spike 证据（日志直算复核）

4. **bench run4-7**：8 行 `PERF|` 亲读，RAF 中位 57.5/44.7/46.5/50.6、ARW 14.5/12.8/13.2/13.3，与 perf.md L352-358 表逐值命中；ARW 全稳带 12.3-15.6 ✓
5. **探针相位计数**：RAFFirst 日志 `PROBE|` 按相位 uniq -c = 40/12/25/15/20/15（base/same/fresh/gap/sdr/clr，RAF/ARW 双列同构），与快照源码 L204-233 count 逐项一致；四探针名与 .txt L238/257/276/304 同名 ✓
6. **中位复算**（sort -n 独立算）：RAF/fresh 17.58（perf.md 称 17.4，Δ0.18）、RAF/gap 21.99（称 22.0 ✓）、ARW/gap 21.17（称 20.7，Δ0.47）、RAF/clr 16.66（称 16.2）；RAF/sdr n=20 偶数中位=(15.99+16.51)/2=16.25（称 16.0，上一轮 16.25 正确，本验初算奇数口径已自纠）→ minor-2 复核成立，min/max 逐值命中 ✓
7. **decode 腿**：两日志 `PROBE| dec` 全量——RAF 74.1-83.2（含 83.2 一帧，perf.md 称 74-81 带宽收窄）、ARW 109.9-118.1（称 110-112，实测 118.1/114.3/114.8 超出）；BENCH 复刻 12 行 + 开图 fp 增幅与 perf.md 逐值一致；「候选排除」结论方向不动 → minor-2 decode 部分成立 ✓
8. **neutral 值域重算**（Python 直读仓内 JSON）：160 组合 C≡0，M∈[28.4,92.1]/Y∈[24.6,116.0]，33/160 出 [40,90] 带 → RESEARCH §1.3「M≈57-79/Y≈63-79」误载确认，下游 M3-3-01-PLAN 已回注纠正 → minor-3 复核逐值成立 ✓

## 三、设计接缝（代码亲核，后演进行号漂移但语义成立）

9. **seed 签名零改**：`PixelPipe.swift:1684` `seed(upstream:params:)` 在位，调用点 :1084，交接注释 :160-166/:1095-1100「keeps exact signature」✓（上一轮引 :1553/:959，行号后演进漂移）
10. **NodeKind 零新增**：`PipelineDocument.swift:44-47` 仍三 case，行号至今逐位有效 ✓
11. **pristine 缺键门**：`PipeCoordinator.swift:804-809` filmTailPolicy 缺键即 nil + `FilmRecord.swift:141-143` ✓（上一轮引 :777-780，行号后演进漂移）

## 四、收口与跟踪（机检）

- 收口 commit live = `2b3cc954`（adjudicate the RAF…），6 文件全 docs/.work，`LightamerCore/|LightamerIOP/|App/` 命中 0 → 零产线 diff 实质成立 ✓
- evidence/ 在盘 9 文件齐（README 索引表命中；mtime 10-08 18:17-18:18）；协变量日志 1015 行含 Renderer Utilization/free%/swap ✓
- `git log --all -- evidence/` 零记录：证据包从未入 git；现 `.gitignore:80` 政策 B 忽略（后演进，不记账）

## 五、minor 清单（4 项）

- **minor-1**：OQ-4 无独立 D 条（沿用上一轮，复核成立）
- **minor-2**：perf.md §O-1 中位小数/带宽收窄（fresh 17.4/ARW-gap 20.7/sdr 16.0/clr 16.2 + decode 双带；沿用上一轮，独立复算确认）
- **minor-3**：RESEARCH §1.3 中性包值域误载（沿用上一轮，逐值复算确认，下游已纠正）
- **minor-4（本验新增，上一轮报告取证瑕疵）**：①上一轮 §2.3「git ls-files 全仓仅命中证据快照 .txt」不可复现——现 ls-files 仅 3 md 且 evidence/ 从无 git 历史；②上一轮引收口 commit `c8ddc57` 现不可解析（改写前旧 SHA，rewrite-map L216 在册，live = `2b3cc954`）。两处实质结论（探针未入仓/收口在案）仍成立，仅引用失效。可修性：小修（历史报告勘误，可不修）。

## 六、分歧项（与上一轮 M3-2-ACCEPTANCE-OMP.md）

结论同为 PASS，无判定分歧。取证层两处差异（已归入 minor-4）：ls-files 断言不成立（上一轮未察 evidence 从未入 git）；收口 SHA 引用失效（SHA 改写后演进，上一轮未用 live SHA）。sdr 中位口径上一轮 16.25 正确，本验确认非分歧。

## 七、会话卫生

只读验收：除本报告外零写入；未跑测试；无网络动作。

OMP-VERDICT: PASS

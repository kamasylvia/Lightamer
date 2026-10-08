# M3-2 CONTEXT — FSIM research 环（discuss/research 起草批，2026-10-07/08）

> Phase = M3-2（ROADMAP M3-2 行：FSIM research 环，估 1 plan；M7 spike + FSIM-03
> 注记搭车）。本文 = 研究定稿载体 + C 档第 1 停裁决面（OQ-M3-2-1..7 交用户）。
> 读解正本 = 同目录 `RESEARCH-NOTES.md`（§ 引用见各 D 条）。
> 状态：research 起草完成 → **C 档第 1 停**：OQ 裁决前不进 plan。

## Phase Goal（ROADMAP 原文锚定）

两段式胶片模拟阶段模型 + 配光自动求解设计定稿；光谱不可达预期管理入册；
资产三态裁决面；FSIM-03 注记落档；FSIM-01a..d 细化草案转正或修正；
M7 RAF 双峰 spike 顺带。验收形态 = OQ 清零 + 设计评审（C 档第 1 停）。

## 决议（D-M3-2-N）

### D-M3-2-1 阶段承载方案：推荐「document 级 FilmRecord + 固定点 film sub-run」（三方案对比，RESEARCH §3）

- 胶片段 = `FilmRecord` document 级单例（材料/配光/强度族）+ 主链顶面后的
  film sub-run（负片段 → 滤色增益 → 印相段 LUT）→ 既有 DRT tail；
  `DrtTailAssembly.seed(upstream:)` 签名零改（film 输出 hash 作 upstream）。
- 场景置位 = 主链内 grade 域独立 op `filmPlacement`（RFC-023 恒等核+双侧支
  曲线，双侧 pull-back + m 参数化，可蒙版）；FilmRecord 不承载置位。
- 节点图 M2-4 语义零改动（UI 卡 = PipelineDocument 投影层只读卡，M3-3 plan 期
  细化）；M2-6 持久化四件套同构复用；pristine = 缺键逐位直通（DRT 同款门）。
- 被否形态：新 NodeKind 段（M2-4 破面最大 + 多重胶片段物理失真）；grade ops 化
  （材料语义降格为图层效果 + enlarger 全图物理不符）。**最终裁定 = OQ-M3-2-1。**

### D-M3-2-2 光谱不可达声明定稿（RESEARCH §2）

- 边界：CIRAW 后 RGB 起步，81 波长光谱重放架构性不可达（光谱信息在解码即折叠，
  同 demosaic 菜单不可达之理）；可行核 = 阶段分离语义 + RGB 域染料近似
  （密度曲线 + 底色偏移 + 串扰矩阵 + 滤色通道增益 + 相纸曲线）。
- 保真面/不可达面双清单入册（RESEARCH §2）；用户可见措辞 =「物理流程建模，
  非光谱重放」。FSIM-01c 原文「架构性不可达声明随 research 落档」以本节兑现。

### D-M3-2-3 配光自动求解 = 两段式（bake 期中性包 + 运行期测光归一）（RESEARCH §4）

- bake 期（每 film×paper 对一次）：mid-gray 通道均衡解 (M0,Y0) 中性滤色包
  （SpektraLab `neutral_print_filters.json` 同构物，自研求解器）。
- 运行期（每图一次 CPU 统计腿）：SceneHistogram 同构统计（128 bins + 分位整数秩）
  → 曝光归一 gain（= printing.cpp 几何均值归一的 RGB 域简化）；内容自适应通道
  偏移为可选档（默认关 = SpektraLab 行为）；**手动 Y/M 偏移恒叠加**（FSIM-01b
  钦定）。
- 确定性门 = 同输入统计+同材料+同模式 → 同解（闭式/有界迭代 + 整数秩统计 +
  缓存键 `fnv(材料对Hash ⊕ 统计Hash ⊕ 模式tag)`）。
- SpektraLab 实测修正：其「自动配光」= 离线材料对查表 + 在线曝光归一，非逐图
  求解滤色组合——FSIM-01b 的「测光自动算印相滤色组合」按本 D 条两段式解释
  转正（内容自适应偏移档为超出 SpektraLab 的可选增强，OQ-M3-2-2）。

### D-M3-2-4 相纸通路 = M3-1-01 烘焙缝 + 独立 FilmMaterialStore（RESEARCH §4.3）

- 印相段（相纸曲线+胶片中性曲线反转+输出编码）静态 per 材料对 → 复合表烘焙
  65³ LUT（`bakedCompositeTable` 同款机制），输入/输出编码取
  `LutEncodingCatalog` 现行行（不加新行）；滤色 = LUT 前逐通道标量增益
  （一 LUT 服务全滤色组合）。载体倾向独立 store（材料对身份 ≠ 用户 LUT 库；
  CC BY-SA 资产与 MIT LUT 物理隔离）——store 归属 M3-3 plan 期终裁。

### D-M3-2-5 FSIM-01a..d 转正/修正建议（REQUIREMENTS 草案处置）

- **01a 修正转正**：「胶片段语义」= document 级 FilmRecord + 主链后固定点
  sub-run + UI 投影卡（原草案「链上新增胶片阶段」的节点段读法不采纳，随
  OQ-M3-2-1 裁定生效）；与 M2-4 命令集/history/sidecar 兼容性 = pristine 直通
  + additive 键族。
- **01b 转正 + 细化**：配光自动求解按 D-M3-2-3 两段式解释；确定性门原文保留
  并给出实现保证清单。
- **01c 转正**：染料近似域基线 = §2 声明 + §6 golden 策略（数学复算主门）；
  golden 参考基线构造方式按 RESEARCH §6 交 plan 期细化（原草案「plan 期定」
  维持）。
- **01d 修正动议**：资产三态对比按 RESEARCH §5 更新事实基础（密度域同构发现），
  研究倾向 c 混合态（对 OQ-V2-10 默认倾向②自建起步的修正动议）——裁决 =
  OQ-M3-2-3。

### D-M3-2-6 FSIM-03 注记落档（RESEARCH §7）

影调蒙版属印相阶段（负片后、相纸前），与场景置位蒙版非同一功能；我方载体 =
film sub-run 内 mask plane（M2-7 蒙版源架构复用），非 grade 层、非 DRT tail。
M3 只落注记不立项；实现候选挂 M4+。

### D-M3-2-7 M7 spike 设计定稿、执行与否随 OQ（RESEARCH §8）

RAF 100MP warm 14↔42ms 双峰 spike 方法 = signpost 分段计时 + IOReport GPU 采样
+ 状态变量二分（疑源三项在案）；产出 = perf.md O-1 结论行 + 证据落本 phase
evidence/；零产线 diff。是否随本环执行 = OQ-M3-2-6（ROADMAP 行原文含「顺带」）。

### D-M3-2-8 许可操作面（若资产态裁决非纯自建，RESEARCH §5）

CC BY-SA 资产入库五件套：独立目录 + LICENSE 全文 + NOTICE（署名/citation/
来源版本）+ CHANGELOG 行 + fixture 只引用不改写；与 `Resources/LUTs/`（MIT）
物理隔离；SpektraLab 渲染产物不入仓不 push；衍生 bake 资产若随包分发须同许可
标注（运行时生成缓存不随仓分发则义务停留在源 JSON）。

## 验收形态对照（本 phase 自检）

- OQ 清零 → OQ-M3-2-1..7 全部有推荐项，待用户裁决（C 档第 1 停兑现处）。
- 设计评审 → 本文 + RESEARCH-NOTES 为评审对象；FSIM-01a..d 转正版随 OQ 裁定
  回写 REQUIREMENTS（下批翻账动作，非本文范围）。
- spike 结论入 perf.md → OQ-M3-2-6 裁「本环执行」时兑现。

## Open Questions（OQ-M3-2-1..7，每条带推荐）

### OQ-M3-2-1 阶段承载方案（FSIM-01a 定形）

- 选项：①独立胶片段 NodeKind 段 ②Grade 件族扩展（胶片 = grade ops）
  ③document 级 FilmRecord + 固定点 sub-run + 置位 grade op【推荐】。
- 推荐：**③**。材料物理语义最忠实（单例/全图，enlarger 隐喻）；M2-4 节点模型
  零改动（投影卡）；M2-6 全套先例机械复用，M3-3 规模最可控（RESEARCH §3 对比表）。
- 影响面：③ 裁定后 FSIM-01a 按修正版转正（D-M3-2-5）。

### OQ-M3-2-2 配光求解自动化程度

- 选项：①全自动仅中性包+曝光归一（SpektraLab 行为）②全自动 + 内容自适应通道
  偏移默认开 ③自动（中性包+曝光归一）+ 内容自适应偏移为可选档默认关 +
  手动 Y/M 偏移恒在【推荐】。
- 推荐：**③**。FSIM-01b 原文 =「自动求解 + Y/M 手动偏移覆盖」（③ 的骨架）；
  内容自适应偏移作为增强档保留但默认关——默认行为与 SpektraLab 对齐（可对比、
  可解释），增强档给 M3-3 验收外的后续空间。确定性门三案皆满足。

### OQ-M3-2-3 资产三态（OQ-V2-10 承接裁决）

- 选项：a 自建起步（OQ-V2-10 当时默认倾向）b 引入 28 配置+8 LUT（CC BY-SA）
  c 混合：引擎/schema/加载器自建 + profile JSON 整文件原样引入（独立归属 +
  SA 隔离清单见 D-M3-2-8）+ 缺口后续自建补齐【推荐】。
- 推荐：**c**。修正动议依据 = 本环实测 density_curves/log_exposure（256×3，
  status M 打印密度域）与我方 RGB 密度域染料近似**直接同构**（RESEARCH §1.5），
  引入转化成本远低于 OQ-V2-10 时的预估；光谱字段不消费但随文件原样保留。
  许可义务真实但清单化可控（D-M3-2-8）。用户若拒绝 CC BY-SA 入公开仓 → 回落 a，
  M3-3 golden/观感风险相应提高（RESEARCH §5 对比表）。

### OQ-M3-2-4 FSIM-02 宽容度面板归属

- 选项：①维持 ROADMAP 现行（M3-4 独立 plan：宽容度面板 + M3 收口）
  ②并入 M3-3（随阶段模型同批交付）。
- 推荐：**①**。宽容度面板依赖 descriptor 运行时（中性 ramp 测 descriptor，
  RESEARCH §6-4）与置位/负片段平面读数——M3-3 主体落地后做，交互教导语义
  也有完整链可走查；M3-3 主打已含阶段模型+求解器+面板+持久化四件，并入会
  过载。ROADMAP M3-4 行原文即此安排，无翻案理由。

### OQ-M3-2-5 golden 参考基线（FSIM-01c）

- 选项：①独立数学复算主门 + SpektraLab 渲染仅本地目测不入仓【推荐】
  ②数学门 + SpektraLab 渲染图入库作视觉 golden ③仅视觉对照。
- 推荐：**①**。许可最干净（本仓含公开 GitHub 谱系，GPL 程序输出图 +
  CC BY-SA 配置的产出物归属存疑，保守隔离）；染料近似与光谱引擎本就非逐像素
  对应，视觉 golden 语义不成立；数学复算 = M3-1-01 成熟先例（RESEARCH §6）。

### OQ-M3-2-6 M3-2 产出物形态（M7 spike 是否本环执行）

- 选项：①design doc + OQ 即可，spike 留 M3-4 尾 ②同批跑 spike（ROADMAP 行
  原文「顺带」，S 规模、计量基建在期、spike 设计已定稿 RESEARCH §8）【推荐】。
- 推荐：**②**。成本最低点在 research 环（无产线在飞冲突窗口），结论早出对
  M3-3..M3-4 的 perf 面零负担；若 OQ-M3-2-1 裁定引发 M3-3 方向重议，spike 结论
  不受影响（独立面）。

### OQ-M3-2-7 场景置位算子形态（若 OQ-M3-2-1 裁③）

- 选项：①独立 `filmPlacement` op（RFC-023 语义曲线，双侧 pull-back + m，
  恒等核 bit-exact 直通）②复用现有 exposure/contrast 组合近似置位。
- 推荐：**①**。宽容度面板（FSIM-02）需要置位曲线一等参数与 descriptor 读数
  语义（「after placement」直方图）；现有 exposure/contrast 无恒等核/双侧独立
  膝点，语义不对位；新 op = IOP additive，风险低（RESEARCH §1.2/§3）。

# OQ — V2/Maintenance 站真分叉点清单（规划起草 subagent，2026-10-08）

> 配套正本 = 同目录 `V2-PROPOSAL.md`。每条给选项 + 推荐 + 理由；§4.5 用户预裁「按推荐」通道适用（可随时推翻）。编号 OQ-V2-1..10。

---

## OQ-V2-1：M3 主打方向

- **选项**：A = 胶片暗房（M2GRADE-08 + FSIM-01/02/03）；B = 栅格链+蒙版（RASTER-IN-01 + ALCE-02 + MASK-06 V2 / MASK-07）。
- **推荐**：**A**。
- **理由**：资产复用最厚（M2-5 Grade/LUT 库 + M2-6 DRT + M2-11 计量全在期）；M2GRADE-08 原文注「可插队 M2 后期」窗口即现在；FSIM = Alcedo 无此面的差异化卖点。方案 B 的 RASTER-IN 晚一站无沉没成本（现状可开非 RAW，只是语义未形式化），整体滚 M4。

## OQ-V2-2：Maintenance 提级面（M1/M6/M7 进不进 M3）

- **选项**：①全不进（触发条件档维持）②M7 spike 搭 M3 research 环 ③M6 显示腿杠杆进 M3。
- **推荐**：**②**——M7（RAF 14↔42ms 双峰）S 规模 spike，计量基建全在，搭 FSIM research 环顺带跑；M1/M6 触发条件未现（100MP 增强/16GB swap 压力），维持待触发不立项。
- **理由**：M6 的处置线在 AGENTS.md 资源监控节已有机检兜底（MEMFAIL >8G kill），主动优化无需求拉动；M1 行带流式是 L 级引擎件，无场景不启动。

## OQ-V2-3：denoise 拖动降档预览语义（M2 栏）是否进 M3

- **选项**：①M3 搭车做 UX 语义（拖动降档/松手全质量）②挂 V2 后段 ③直接上 kernel 重写 C 案。
- **推荐**：**①**，S/M 规模随 M3 任一波搭车；③（kernel 重写/时域复用 = L）继续挂后。
- **理由**：OQ-7-A bounded 降载三档已试尽 revert（引擎级单腿 26.5ms@29 趟独自超门，数学不可达），UX 语义是仅剩低成本路径；kernel 重写无回本预期支撑。

## OQ-V2-4：RASTER-IN-01 与 100MP 流式（M1）是否捆绑

- **选项**：①捆绑（RASTER-IN 带 M1 行带流式）②不捆绑（RASTER-IN 走既有 TilingPlan，M1 待触发）。
- **推荐**：**②**。
- **理由**：`c573087` 两阶段 engine 已闭 12MP 档；RASTER-IN 首批目标 = 常规栅格（JPEG/PNG/TIFF）+ EXR 读，100MP EXR/HDR 场景先记录不优化；捆绑会把 L 级引擎件塞进 parity plan，规模失控。真实 100MP 栅格用户出现再触发 M1。

## OQ-V2-5：EXR 读写依赖（ALCE-02 + RASTER-IN-01 的 EXR 面）

- **选项**：①引第三方 SPM（libopenexr binding 类，修订「仅 libwebp/libavif」依赖红线）②自写 minimal EXR 读写子集（uncompressed/ZIP/PIZ 有限组合，S/M 级 Metal/CPU 路径）③EXR 面砍出首批（RASTER-IN 先做 JPEG/PNG/TIFF，EXR 延后独立裁决）。
- **推荐**：**③先行、research 环内 ①vs② 出对比结论再裁**——RASTER-IN 价值核在「display-referred 经 DRT 逆链」语义与 JPEG/PNG/TIFF 入口，EXR 非首批阻塞项；依赖红线修订是用户专属裁决权，不夹带。
- **理由**：ImageIO 无 EXR 读写是硬事实；Alcedo 用 OCIO/OpenEXR 栈不可平移（依赖最小化约束 PROJECT.md 明文）。

## OQ-V2-6：TRACK 追色族时机

- **选项**：①M4（保守）②M3 尾波搭车 ③M5+。
- **推荐**：**M4**；若用户日常高频走 MCP-10 agent 编排修图则提前至 M3 尾波。
- **理由**：TRACK-01..05 是 L 级算法族（Reinhard/CDF/OT 选型 + golden parity 门），两案 M3 已满载；MCP-09-C `match_color` 工具位依赖本族——使用频率是唯一提级理由，用户自判。

## OQ-V2-7：YIYIN-09 搭车哪波

- **选项**：①M3-W1 与小件族同批 ②独立 mini-plan 殿后 ③不进 M3。
- **推荐**：**①**。
- **理由**：S 规模；fork `f8de57a` 参考已同步（上游 PR #126 形态）；REQUIREMENTS :278 原文即注「M2-11 收官后 mini-plan」——钦定窗口就是现在。

## OQ-V2-8：IOP-HDR-06 / IOP-PANO-01 合成族时机

- **选项**：①两件都 M4 ②Mertens M4、PANO M5 ③两件都 M5+。
- **推荐**：**②**。
- **理由**：Mertens（M）复用 Phase 8 HDR 管线（IOP-HDR-04 出口现成），轻；PANO（L）是全新合成模式（SIFT/球面投影/分块羽化自实现量大），独立大件不与格式扩容/蒙版族混波。

## OQ-V2-9：冲突档选择器归属（M2-9 挂账#4）

- **选项**：①M3-W1 小件族批内修 ②随在飞修复批扩容 ③独立 fix plan。
- **推荐**：**①**——M3-W1 与 zh 清算/peak-ICC 同批（同为 S 级 UI/文档面，互不相干可一 plan 多任务）。
- **理由**：晨审已判「选择器必须暴露」，引擎三档交付且单测+E2E 钉死（M2-9-VALIDATION #59 行），纯 UI 暴露 S 修；在飞修复批 owned 面不同（ToneEqual/L057），并入会搅隔离边界。

## OQ-V2-10：FSIM 资产面（SpektraLab CC BY-SA 胶片/相纸配置）引不引

- **选项**：①research 环裁（对比自建配置 vs 引入 28 款实测配置+8 放大 LUT 的成本与归属面）②直接自建，零 CC BY-SA 资产 ③直接引入。
- **推荐**：**①**——research 环列三态对比（归属成本：独立 NOTICE/CHANGELOG + SA 传染仅及资产本体 + 不与 MIT spectral_film_lut 混用），默认倾向②自建起步、①③视自建质量差距再裁。
- **理由**：SPEKTRALAB-NOTES 许可红线明确可引入但流程成本真实；RGB 域染料近似下 28 款配置的可迁移度未验证（其配置面向 81 波长光谱引擎调校）——先验证语义框架（FSIM-01 阶段模型），资产面后置。

---

## 附：非分叉注记（不占 OQ 编号）

- ALCE-01/04/05/06/07 已随 2026-09-27 重定义提级 V1 并交付（M2-5/6/8/10），本站零动作；REQUIREMENTS ALCE 行翻勾注记归下批翻账（非本文范围）。
- V1-V17 观察项按 M2-11-VALIDATION-INPUT §4.4 落位维持；V5/V9/V10 已关闭；V14/V15 随 M3-W1 zh 清算（若 OQ-V2-9 同批则一并）。
- M4/M5 两 error FINDING 在飞修复批处置，本站零动作；修复批交付后其挂账状态以修复批报告为准。

## 裁决记录（用户预裁 2026-10-08「按推荐」生效）

OQ-V2-1..10 全部按推荐采纳：**M3 = 方案 A「胶片暗房」**（M2GRADE-08 W1 前置 + FSIM-01/02 主打 + 搭车族 YIYIN-09/zh 清算/冲突档选择器/peak-ICC/denoise 降档语义/M7 spike 搭 research）；方案 B（RASTER-IN/MASK-06/07）滚 M4；TRACK/Mertens M4、PANO M5；EXR 砍出首批（research 环出依赖对比再裁）。

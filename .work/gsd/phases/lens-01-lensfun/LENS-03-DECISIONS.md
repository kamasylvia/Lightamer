# LENS-03 DECISIONS — plan L3 裁定记录

> 正本 = CONTEXT.md(D-LENS-6/-8 + X7/X8);本文件只记执行期裁定与偏差申报。

## D-L3-1 TCA ROI union 的双轨面(T2)

resolved(lensfun)面 = 真三通道 union(edgeSample R/G/B 各坐标进 AABB,D7 注记兑现);**manual 面 = G 通道 + 2px 维持**(理由:手动 TCA 滑杆 ±0.01 量级 sub-pixel,union 增益为零而 CPU 成本 ×3;04-04 D7 注记本就只承诺 resolved-XML 路径)。resolve miss → 落 manual 面(identity 渲染语义一致)。**ROI 的 lensfun 系数在此前「isNeutral 短路」语义上 opened up**(L2 D-L3-3 注记的保守过宽面被 T2 取代——lensfun 文档现在走真 union 面)。

## D-L3-2 yM 笔误复发(T2 修复 + 流程教训)

T2 的行手术把 modifyROIIn else 臂从模板文本复制回 `yM = max(ym, q.y)`(bug 版)——**fix(lens02) 修过的同一行第二次回归**。根因 = 同文件多处近似行 + python 模板文本携带历史 bug。**ROINegotiationTests 的 62×62 钉死测试两次抓到(门网有效)**。LESSONS 候选:多位置近似行的编辑禁用「整块替换」模板,改行号锚定;python 模板文本必须从 git show HEAD 现取而非上下文记忆。

## D-L3-3 投影求值序 = Alcedo 实序(T1,plan 风险节裁决)

kernel 求值序 = **normalized → ×1/scale → projection fold(target→erect→source)→ distortion → TCA**(Alcedo lens_calib.metal `lens_warp_rgba32f` 实序)。L2 T3 的「×1/scale 施于映射后终采样偏移」序随批退役(plan T1 action 2 的序描述与 Alcedo 实序的歧义按风险节裁决「以 Alcedo 实序为准移植并头注释钉死」)。影响面:scale=1 恒等(红线 12 保);user-scale/auto-scale > 1 且有畸变时数值随新序(L2 新面无 pre-existing 文档,合法);L2 scale golden 重钉(零畸变精确 1/s 比例 + 有畸变方向)。

## D-L3-4 投影 golden 分层门(T1)

rectilinear 对(rect→rect 恒等)= **1e-5**(warp 级,scale golden 同门);**任何投影折 = 2e-3**(erect↔rect/tan 链一阶导最大 ~14(1/cos²@1.3rad),float 折叠坐标的 1e-7 噪声放大到采样域 1e-4+ → 值域差实测 2.07e-4)。CPU twin = 同源公式 Double 版(转录检查);残差随 tan 梯度缩放而错误公式不会——非转录错的判据。**出帧采样带(|coord| > 帧)豁免**(几何 clamp 面,非转录对象;豁免数 ≤ 帧面积 1/4 的 sanity 断言在册)。真独立对账 = LENS-04 T4 RawLab 抽查。

## D-L3-5 MSL slot 常量 = enum(T1 编译陷阱)

program-scope `constant int` **不是** MSL 常量表达式——switch case 静默不命中(走 default,无编译错、无运行时错,纯语义错;ProjectionGolden 的 (0,0) got/exp 差 0.14 抓到)。修复 = `enum ProjSlot { … }`。**教训(LESSONS 候选):MSL 的 switch case 必须整型常量表达式,`constant` 限定的 program-scope 变量不合格且无告警。**

## D-L3-6 快照检取源 = RawLab 钉版拷贝(T3)

plan 指引「官方 tar.bz2 检取(失败停手上报)」;执行取 **RawLab 的 pinned checkout 直拷**(同一 2026-10-12 archive,SHA-256 `97c9f805…` 与 RawLab README 登记一致,56 xml 5.1MB 逐文件 SHA manifest 在库)——离线、可审计、零网络依赖,优于网络检取。README 登记同源性。

## D-L3-7 设置段落点 = SettingsCachePage(T3)

plan 说「设置项迁 Settings」未钉独立页;Lens Data 段挂 **SettingsCachePage**(数据管理语义族 + 避免新页路由面扩大)。dbTag readout 的解析走 `resolveAndInstall()`(与启动同优先序,read-only 面)。

## D-L3-8 seed 目录名 = version_1-seeded(T3)

seeder 目标 = `support/<bundle>/Lensfun/version_1-seeded/`(与更新通道的 `version_1/` 分离:种子 = 随包原版,version_1 = 更新通道产物;优先序 seeded > downloaded 保证「更新后仍可回退到种子语义」的审计面)。

## D-L3-9 LensKernelParams 携带 sourceProjection(T1)

entry `<type>` → LensMatchedProfile.projectionHint(memo 面)→ resolve() 折 LensKernelParams.sourceProjection → resolveUniforms 折 uniforms(srcTgt)。params.sourceProjection additive 字段落位但**写入点 = LENS-04 T1 快照批**(T1 阶段该字段为快照预备位;渲染面走 kernel 携带,零死字段)。

## 键清单(T1/T3)

`panel_lens_target_projection` / `panel_lens_projection_rectilinear` / `panel_lens_projection_fisheye` / `panel_lens_projection_equisolid` / `panel_lens_projection_stereographic` / `panel_lens_projection_orthographic`(T1,6)+ `settings_lensfun_section` / `settings_lensfun_dbtag` / `settings_lensfun_check_update` / `settings_lensfun_updating` / `settings_lensfun_updated` / `settings_lensfun_sha_mismatch` / `settings_lensfun_update_failed` / `settings_lensfun_hint`(T3,8)= 14 键尾块纯插入。UserDefaults 零新增。

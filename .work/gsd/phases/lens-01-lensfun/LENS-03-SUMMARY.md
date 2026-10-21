# LENS-03 SUMMARY — plan L3:projection + TCA ROI union + 数据分发 + NOTICE/许可

> status: executed | date: 2026-10-21 | 起算基 = LENS-02 终态(d87c1517)
> 裁决正本 = CONTEXT.md(D-LENS-6/-8 + X7/X8 + H-L3 + 红线 15 条)

## 逐任务记账

| 任务 | commit | 内容 | ΔN | 验收 |
|---|---|---|---|---|
| T1 | `5ed54541` | LensProjection(8 槽枚举 + 四激活型 CPU 对,Alcedo GPL 移植三件套)+ kernel 投影段(ProjSlot enum 常量 + 五型对)+ **求值序钉死 = Alcedo 实序**(scale→projection→distortion→TCA;L2 终偏移序退役,scale=1/rectilinear 对双恒等保红线 12)+ resolve() 硬拒解除(target 未设保守拒绝维持)+ Params.targetProjection/sourceProjection additive + 面板 target picker + 投影×auto-crop 接线(edgeSample 折投影)+ LensProjectionGolden(IOPParity 6:五对 + coincident 恒等;出帧带豁免 + tan 域分层门 2e-3 登记)+ LensProjectionResolve(IOP 7) | +13 | IOPParity 6/0/0;IOP 7/0/0 |
| T2 | `fd1618e0` | resolved(lensfun)面 ROI = 真三通道 union(edgeSample R/G/B 各 AABB union;D7 注记兑现)+ manual 面 G 近似维持(D-L3-1)+ yM 笔误复发修复(见 D-L3-2)+ TCA union 测试(2% poly3-TCA 轮廓 dominates G 包络) | +1 | IOP ROINegotiation 12/0/0 |
| T3 | `091e2ac9` | Resources/Lensfun 钉版快照(56 xml 5.1MB + README[来源/SHA/日期/unmodified] + version_1.SHA256SUMS per-file 清单;folderReference)+ LensfunDataDistribution(per-file seeder + 四态优先序 + dbTag[16 hex] + 手动 SHA 校验更新通道[mismatch 拒绝安装])+ Settings Lens Data 段(dbTag readout + 检查更新;L057 async 缝)+ LensfunDataLocation.seeded + 面板下载臂 seed 优先 + LensfunDistributionTests(App 6) | +6 | App 6/0/0 |
| T4 | `00204d4f` | NOTICE 三条目(N lensfun CC-BY-SA-3.0 + O Alcedo 投影 + P RawLab auto-crop/状态机)+ Resources/Licenses/Lensfun 全套(cc-by-sa/lgpl/database-声明 + README)+ fixtures README 交叉链接 | 0 | grep 四词全命中;许可文本 50.9KB 在库 |
| T5 | 本 commit | 三 bundle 定向 + docs | 0 | 见下 |

**ΔN 终账 = +20**(13+1+6)。预算 +16..26 带内 ✓。

## 定向 bundle(L3 收口轮)

- `--bundle IOP`:**743/5/0**
- `--bundle IOPParity`:**469/3/0**
- `--bundle App`:**961/6/0**

## 关键裁定(细节 = LENS-03-DECISIONS.md)

- **求值序 = Alcedo lens_calib.metal 实序**(scale→projection→distortion→TCA;plan 风险节「以 Alcedo 实序为准」钉死)。L2 的「×1/scale 终偏移」面随批移位:L2 scale golden 重钉(新序 + 零畸变精确 1/s 比例断言),scale=1/rectilinear 双恒等 = pre-L2 渲染逐字节(golden 复跑证明)。
- **投影 golden 分层门**:rectilinear 对 1e-5;任何投影折 2e-3(erect↔rect/tan 链一阶导放大的 float 噪声;实测 2.07e-4;CPU twin 同源 Double 公式——非转录错,残差随 tan 梯度缩放)。出帧采样带豁免(几何 clamp 面)。
- **MTL 陷阱登记**:program-scope `constant int` 不是常量表达式,switch case 静默落 default——slot 常量必须 enum(编译期)。

## 红线核验

- T2 零 metal diff ✓;投影默认 rectilinear 恒等(默认中性零行为门红线 12,golden 证明)✓
- 数据资产纪律:钉版 SHA 校验拒绝安装 ✓;无自动更新 ✓;customPathKey 零改 ✓;整库随包(无子集化)✓
- GPL 三件套(LensProjection/LensAutoCrop 版权头 + 修改标注 + NOTICE 三条目一一对应)✓
- xcstrings 尾块纯插入(6+8 键)+ zh-audit 双 PASS ✓;tuist generate 恒末位 ✓

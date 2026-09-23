#include <metal_stdlib>
using namespace metal;

// BilateralKernels.metal (Plan 05-08, IOP-DENOISE-03) — dt `bilateral`
// ("surface blur", v50 10.0, RGB 域) 两档的 MSL 直译（tree dc58cf0ba1）。
//
// DIRECT LEG (rad = 3σs+1 ≤ 6): bilateral.cc:175-254 逐行直译。
//   - 空间权 m = exp(−(l²+k²)/(2σs²)) 先对整窗求和归一（CPU 预算进 buffer 0
//     —— dt :185-192 同序：先累加 weight 再 m /= weight）；
//   - 域权 per-pixel exp(−Σc (p−q)²·isig2c)，isig2c = 1/(2σc²)（uniforms）；
//   - 边界 rad 圈原样拷出（dt :210-217/:248-253 border copy 语义）。
//
// 5D GRID LEG (rad > 6): dt CPU 侧 permutohedral lattice（bilateral.cc
// :266-310 splat val=(r,g,b,1)×权 / blur / slice 后 val /= val[3] 归一）的
// 稠密 5D 网格对偶（bilateral.cl 3D grid 的 5 维推广：splat 原子散射 /
// blur_line ×5 维 / slice 三十二角插值）。工程模式与 05-01 BilateralGrid3D
// 同源（atomic_float 累加；blur out-of-place ping-pong——L018 禁 read_write）。
//
// 网格坐标 = 平面锚定：(gid + offset)/σ（offset = tile 读矩形原点 − 基 cell
// 平移——tile 执行与整幅执行落同一物理格，分块==整幅 <1e-3 的结构前提，
// DECISIONS OQ7）。range 维度值域 [0,1]（bilateral.cl image_to_grid clamp
// 语义；>1 值 clamp 到顶格，DECISIONS 记近似域）。payload =
// float4(w·r, w·g, w·b, w) —— dt lattice splat 的 val 对偶，slice 以
// val.rgb / val.w 归一。

struct BilateralDirectUniforms {
    int width;
    int height;
    int radius;
    float isig2r;
    float isig2g;
    float isig2b;
};

// 直连档：窗口 stamp（bilateral.cc:219-247 主循环直译 + 边界拷贝）。
kernel void bilateral_direct(
    texture2d<float, access::read>  in   [[texture(0)]],
    texture2d<float, access::write> out  [[texture(1)]],
    device const float*             weights [[buffer(0)]], // (2r+1)² 归一空间权
    constant BilateralDirectUniforms& u [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.width || gid.y >= (uint)u.height) return;
    const int r = u.radius;
    const int wd = 2 * r + 1;
    const float4 p = in.read(gid);
    // 边界 rad 圈原样拷出（dt :210-217 top/bottom + :248-253 left/right）。
    if ((int)gid.y < r || (int)gid.y >= u.height - r ||
        (int)gid.x < r || (int)gid.x >= u.width - r) {
        out.write(p, gid);
        return;
    }
    float4 res = 0.0f;
    float sumw = 0.0f;
    for (int l = -r; l <= r; l++) {
        for (int k = -r; k <= r; k++) {
            const float4 q = in.read(gid + uint2(k, l));
            const float3 d = (p.xyz - q.xyz);
            const float diff = d.x * d.x * u.isig2r
                             + d.y * d.y * u.isig2g
                             + d.z * d.z * u.isig2b;
            const float w = weights[(l + r) * wd + (k + r)] * exp(-diff);
            res += q * w;
            sumw += w;
        }
    }
    res /= sumw;
    res.w = p.w; // alpha 直通（管线 premultiplied α≡1）
    out.write(res, gid);
}

struct Bilateral5DUniforms {
    int width;     // 本矩形（tile 读矩形或整幅）
    int height;
    int originX;   // 矩形平面原点（像素）
    int originY;
    int baseX;     // 本地网格基 cell（spatial——整数格，相位与整幅严格一致）
    int baseY;
    int cellsX;    // 本地网格 dims（全部 ≥ 4——dt 3D grid 同款下限）
    int cellsY;
    int cellsR;
    int cellsG;
    int cellsB;
    float sigmaS;
    float sigmaR;
    float sigmaG;
    float sigmaB;
};

// 5D 网格坐标（bilateral.cl image_to_grid 5 维推广）：平面锚定浮点采样
// g = (gid + origin)/σ（tile 与整幅逐位同式）→ 整数 cell 减基得本地索引；
// range 维 clamp [0, cells−1]（image_to_grid 同形）。xi = min(cells−2, …)、
// f = g − xi（dt 同形）。
static inline void grid_coords5d(
    uint2 gid, float4 pixel, constant Bilateral5DUniforms& u,
    thread int* xi, thread float* ff)
{
    const float gx = ((float)gid.x + (float)u.originX) / u.sigmaS;
    const float gy = ((float)gid.y + (float)u.originY) / u.sigmaS;
    xi[0] = min(max((int)gx - u.baseX, 0), u.cellsX - 2);
    xi[1] = min(max((int)gy - u.baseY, 0), u.cellsY - 2);
    ff[0] = gx - (float)(xi[0] + u.baseX);
    ff[1] = gy - (float)(xi[1] + u.baseY);
    const float gr = clamp(pixel.x / u.sigmaR, 0.0f, (float)(u.cellsR - 1));
    const float gg = clamp(pixel.y / u.sigmaG, 0.0f, (float)(u.cellsG - 1));
    const float gb = clamp(pixel.z / u.sigmaB, 0.0f, (float)(u.cellsB - 1));
    xi[2] = min((int)gr, u.cellsR - 2);
    xi[3] = min((int)gg, u.cellsG - 2);
    xi[4] = min((int)gb, u.cellsB - 2);
    ff[2] = gr - (float)xi[2];
    ff[3] = gg - (float)xi[3];
    ff[4] = gb - (float)xi[4];
}

// 网格 cell 线性索引（x-minor 布局：x 步 1，y 步 cellsX，r/g/b 递乘）。
static inline int grid_base5d(
    thread int* xi, constant Bilateral5DUniforms& u, int a, int b, int c)
{
    const int oy = u.cellsX;
    const int orr = u.cellsX * u.cellsY;
    const int og = orr * u.cellsR;
    const int ob = og * u.cellsG;
    return xi[0] + oy * (xi[1]) + orr * (xi[2] + a) + og * (xi[3] + b) + ob * (xi[4] + c);
}

// splat：每像素 32 角 pentalinear 散射（atomic_float 加；val=(r,g,b,1)×权
// —— dt lattice.splat 对偶；bilateral.cl splat 的 local 聚合省略为直接
// 原子加——HistogramReduce / 05-01 3D grid 同工程模式）。
kernel void bilateral5d_splat(
    texture2d<float, access::read> in [[texture(0)]],
    device atomic_float*           grid [[buffer(0)]],
    constant Bilateral5DUniforms&  u [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.width || gid.y >= (uint)u.height) return;
    const float4 pixel = in.read(gid);
    int xi[5]; float ff[5];
    grid_coords5d(gid, pixel, u, xi, ff);
    const float w00 = (1 - ff[0]) * (1 - ff[1]);
    const float w10 = ff[0] * (1 - ff[1]);
    const float w01 = (1 - ff[0]) * ff[1];
    const float w11 = ff[0] * ff[1];
    const float wxy[4] = { w00, w10, w01, w11 };
    const int xoff[4] = { 0, 1, 0, 1 };
    const int yoff[4] = { 0, 0, 1, 1 };
    for (int a = 0; a < 2; a++) {
        for (int b = 0; b < 2; b++) {
            for (int c = 0; c < 2; c++) {
                const float wrgb = (a ? ff[2] : 1 - ff[2]) * (b ? ff[3] : 1 - ff[3])
                                 * (c ? ff[4] : 1 - ff[4]);
                for (int q = 0; q < 4; q++) {
                    int xj[5] = { xi[0] + xoff[q], xi[1] + yoff[q], xi[2], xi[3], xi[4] };
                    const int base = grid_base5d(xj, u, a, b, c);
                    const float w = wrgb * wxy[q];
                    atomic_fetch_add_explicit(grid + 4 * base + 0, w * pixel.x, memory_order_relaxed);
                    atomic_fetch_add_explicit(grid + 4 * base + 1, w * pixel.y, memory_order_relaxed);
                    atomic_fetch_add_explicit(grid + 4 * base + 2, w * pixel.z, memory_order_relaxed);
                    atomic_fetch_add_explicit(grid + 4 * base + 3, w, memory_order_relaxed);
                }
            }
        }
    }
}

// blur_line：单维 [1,4,6,4,1]/16（edge 处理 = bilateral.cl blur_line 逐式；
// axis 0=x 1=y 2=r 3=g 4=b；out-of-place ping-pong，L018）。一线程一线，
// 线索引（2D 展平 line = gid.x + gid.y·linesWidth）= 其余 4 维 flat
//（d 升序 mixed-radix）。
kernel void bilateral5d_blur_line(
    device const float* ibuf [[buffer(0)]],
    device float*       obuf [[buffer(1)]],
    constant Bilateral5DUniforms& u [[buffer(2)]],
    constant int2& axisAndWidth [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int cells[5] = { u.cellsX, u.cellsY, u.cellsR, u.cellsG, u.cellsB };
    const int ax = axisAndWidth.x;
    const int linesWidth = axisAndWidth.y;
    const int n = cells[ax];
    // axis 真步长 = Π_{e<ax} cells[e]；线总数 = Π_{d≠ax} cells[d]。
    int axisStride = 1;
    long lines = 1;
    int trueStride[5];
    long compressedWeight[5];
    for (int d = 0; d < 5; d++) {
        trueStride[d] = 1;
        for (int e = 0; e < d; e++) { trueStride[d] *= cells[e]; }
        if (d == ax) { axisStride = trueStride[d]; continue; }
        compressedWeight[d] = lines;   // d 升序累计（跳过 ax）
        lines *= cells[d];
    }
    const long line = (long)gid.x + (long)gid.y * (long)linesWidth;
    if (line >= lines || n < 4) return;
    // 线索引 → 其余 4 维 digit（d 升序压缩位权提取）；base = Σ digit×真步长。
    long base = 0, rem = line;
    for (int d = 0; d < 5; d++) {
        if (d == ax) continue;
        base += (rem % cells[d]) * (long)trueStride[d];
        rem /= cells[d];
    }
    const float w0 = 6.0f / 16.0f, w1 = 4.0f / 16.0f, w2 = 1.0f / 16.0f;
    // payload = float4/格——滚动 tmp 按通道各自持有（CL 原文逐元素滚动的
    // 4 通道并行形；标量 tmp 跨通道复用会污染 val/w 比——05-08 实测教训）。
    device const float4* ib4 = (device const float4*)ibuf;
    device float4*       ob4 = (device float4*)obuf;
    auto at = [&](int i) -> long { return base + (long)i * axisStride; };
    float4 t1 = ib4[at(0)];
    ob4[at(0)] = ib4[at(0)] * w0 + w1 * ib4[at(1)] + w2 * ib4[at(2)];
    float4 t2 = ib4[at(1)];
    ob4[at(1)] = ib4[at(1)] * w0 + w1 * (ib4[at(2)] + t1) + w2 * ib4[at(3)];
    for (int i = 2; i < n - 2; i++) {
        const float4 t3 = ib4[at(i)];
        ob4[at(i)] = ib4[at(i)] * w0
            + w1 * (ib4[at(i + 1)] + t2)
            + w2 * (ib4[at(i + 2)] + t1);
        t1 = t2; t2 = t3;
    }
    const float4 t3 = ib4[at(n - 2)];
    ob4[at(n - 2)] = ib4[at(n - 2)] * w0 + w1 * (ib4[at(n - 1)] + t2) + w2 * t1;
    ob4[at(n - 1)] = ib4[at(n - 1)] * w0 + w1 * t3 + w2 * t2;
}

// slice：32 角 pentalinear 查表 + val.rgb / val.w 归一（dt lattice.slice
// val[k] /= val[3] 对偶）；w ≤ 0 的未触格回落输入（NaN 防护——稠密网格
// 特有；查询点自身 splat 保证 w>0，防护仅兜数值边界）。
kernel void bilateral5d_slice(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float*             grid [[buffer(0)]],
    constant Bilateral5DUniforms&   u [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.width || gid.y >= (uint)u.height) return;
    const float4 pixel = in.read(gid);
    int xi[5]; float ff[5];
    grid_coords5d(gid, pixel, u, xi, ff);
    const float w00 = (1 - ff[0]) * (1 - ff[1]);
    const float w10 = ff[0] * (1 - ff[1]);
    const float w01 = (1 - ff[0]) * ff[1];
    const float w11 = ff[0] * ff[1];
    const float wxy[4] = { w00, w10, w01, w11 };
    const int xoff[4] = { 0, 1, 0, 1 };
    const int yoff[4] = { 0, 0, 1, 1 };
    float4 val = 0.0f;
    for (int a = 0; a < 2; a++) {
        for (int b = 0; b < 2; b++) {
            for (int c = 0; c < 2; c++) {
                const float wrgb = (a ? ff[2] : 1 - ff[2]) * (b ? ff[3] : 1 - ff[3])
                                 * (c ? ff[4] : 1 - ff[4]);
                for (int q = 0; q < 4; q++) {
                    int xj[5] = { xi[0] + xoff[q], xi[1] + yoff[q], xi[2], xi[3], xi[4] };
                    const int base = grid_base5d(xj, u, a, b, c);
                    val += wrgb * wxy[q] * float4(
                        grid[4 * base], grid[4 * base + 1], grid[4 * base + 2], grid[4 * base + 3]);
                }
            }
        }
    }
    float4 o = pixel;
    if (val.w > 0.0f) {
        o.x = val.x / val.w;
        o.y = val.y / val.w;
        o.z = val.z / val.w;
    }
    out.write(o, gid);
}

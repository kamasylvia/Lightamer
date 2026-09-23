#include <metal_stdlib>
using namespace metal;

// BilateralGrid3DKernels.metal (Plan 05-01-T7) — dt 3D bilateral grid
// 三阶段的 MSL 直译（dt `data/kernels/bilateral.cl` 对偶）。
//
// 网格布局：x-major 单平面 float（dt `b->buf` 对偶——加权计数，非归一化
// 均值；payload/weight 比值是误读，见 D-05-01-T7 审计）。
//   idx = (x + sizeX * y) * sizeZ + z。
// sigma 以 uniforms 传入（grid_size 已由 Swift 侧定）。
//
// splat 原子散射：device atomic_float 累加（05-05 monochrome 首个 GPU 消费
// 者钉住：05-01 的位模式 atomic_uint 整数加 ≠ float 加，数值错误——改用
// atomic_float 直接累加；xcrun metal 编译通过，M4 运行时验证见 05-05-DECISIONS
// D4；HistogramReduce 的整型直方图仍走 atomic_uint，不受影响）。
// 每像素散射 `contrib = 100/σ_s²` 缩放的 trilinear 权重（dt 对偶）。
//
// blur_line / blur_line_z：bilateral.cl 逐行直译（out-of-place 双缓冲——
// L018：禁 image2d read_write，grid 以 device buffer 双平面 ping-pong）。
// slice：三线性查表 + detail norm（dt slice 形，detail=−1 基底）。

struct BilateralGridUniforms {
    int sizeX;
    int sizeY;
    int sizeZ;
    float sigmaS;
    float sigmaR;
    float detail;
    int width;
    int height;
};

// splat：每像素 trilinear 散射到 grid（atomic_float 加）。
kernel void bilateral3d_splat(
    texture2d<float, access::read> in [[texture(0)]],
    device atomic_float*           grid [[buffer(0)]],
    constant BilateralGridUniforms& u [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.width || gid.y >= (uint)u.height) return;
    const float L = in.read(gid).x;
    const float gx = clamp((float)gid.x / u.sigmaS, 0.0f, (float)(u.sizeX - 1));
    const float gy = clamp((float)gid.y / u.sigmaS, 0.0f, (float)(u.sizeY - 1));
    const float gz = clamp(L / u.sigmaR, 0.0f, (float)(u.sizeZ - 1));
    const int xi = min((int)gx, u.sizeX - 2);
    const int yi = min((int)gy, u.sizeY - 2);
    const int zi = min((int)gz, u.sizeZ - 2);
    const float fx = gx - (float)xi;
    const float fy = gy - (float)yi;
    const float fz = gz - (float)zi;
    const float contrib = 100.0f / (u.sigmaS * u.sigmaS);
    const int base = (xi + u.sizeX * yi) * u.sizeZ + zi;
    // dt CPU strides（bilateral.c:204-206: ox=size_z, oy=size_x*size_z,
    // oz=1；05-01 初版误用 CL x-minor 步长，05-05-T3 非立方网格暴露）。
    const int ox = u.sizeZ, oy = u.sizeX * u.sizeZ, oz = 1;
    const float qw[4] = {
        (1-fx)*(1-fy), fx*(1-fy),
        (1-fx)*fy,     fx*fy,
    };
    const int qoffs[4] = { 0, ox, oy, oy+ox };
    for (int k = 0; k < 4; k++) {
        // 加权计数 += w × (1−fz)/fz × contrib ——float 原子加（dt 对偶）。
        atomic_fetch_add_explicit(grid + base + qoffs[k], qw[k] * (1-fz) * contrib, memory_order_relaxed);
        atomic_fetch_add_explicit(grid + base + qoffs[k] + oz, qw[k] * fz * contrib, memory_order_relaxed);
    }
}

// blur_line：x 或 y 维高斯 [1,4,6,4,1]/16（axis=0 → x；axis=1 → y）。
// 每线程一条 line（out-of-place：ibuf → obuf）。
kernel void bilateral3d_blur_line(
    device const float* ibuf [[buffer(0)]],
    device float*       obuf [[buffer(1)]],
    constant BilateralGridUniforms& u [[buffer(2)]],
    constant int& axis [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float w0 = 6.0f/16.0f, w1 = 4.0f/16.0f, w2 = 1.0f/16.0f;
    const int nx = u.sizeX, ny = u.sizeY, nz = u.sizeZ;
    if (axis == 0) {
        // gid.x = y, gid.y = z（两维铺排）。
        const int y = (int)gid.x, z = (int)gid.y;
        if (y >= ny || z >= nz) return;
        {
            auto at = [&](int x) -> int { return ((x + nx * y) * nz + z); };
            float t1 = ibuf[at(0)];
            obuf[at(0)] = ibuf[at(0)]*w0 + w1*ibuf[at(1)] + w2*ibuf[at(2)];
            float t2 = ibuf[at(1)];
            obuf[at(1)] = ibuf[at(1)]*w0 + w1*(ibuf[at(2)] + t1) + w2*ibuf[at(min(3, nx-1))];
            for (int x = 2; x < nx - 2; x++) {
                const float t3 = ibuf[at(x)];
                obuf[at(x)] = ibuf[at(x)]*w0 + w1*(ibuf[at(x+1)] + t2) + w2*(ibuf[at(x+2)] + t1);
                t1 = t2; t2 = t3;
            }
            if (nx > 3) {
                const float t3 = ibuf[at(nx-2)];
                obuf[at(nx-2)] = ibuf[at(nx-2)]*w0 + w1*(ibuf[at(nx-1)] + t2) + w2*t1;
                obuf[at(nx-1)] = ibuf[at(nx-1)]*w0 + w1*t3 + w2*t2;
            }
        }
    } else {
        // gid.x = x, gid.y = z。
        const int x = (int)gid.x, z = (int)gid.y;
        if (x >= nx || z >= nz) return;
        {
            auto at = [&](int y) -> int { return ((x + nx * y) * nz + z); };
            float t1 = ibuf[at(0)];
            obuf[at(0)] = ibuf[at(0)]*w0 + w1*ibuf[at(1)] + w2*ibuf[at(2)];
            float t2 = ibuf[at(1)];
            obuf[at(1)] = ibuf[at(1)]*w0 + w1*(ibuf[at(2)] + t1) + w2*ibuf[at(min(3, ny-1))];
            for (int y = 2; y < ny - 2; y++) {
                const float t3 = ibuf[at(y)];
                obuf[at(y)] = ibuf[at(y)]*w0 + w1*(ibuf[at(y+1)] + t2) + w2*(ibuf[at(y+2)] + t1);
                t1 = t2; t2 = t3;
            }
            if (ny > 3) {
                const float t3 = ibuf[at(ny-2)];
                obuf[at(ny-2)] = ibuf[at(ny-2)]*w0 + w1*(ibuf[at(ny-1)] + t2) + w2*t1;
                obuf[at(ny-1)] = ibuf[at(ny-1)]*w0 + w1*t3 + w2*t2;
            }
        }
    }
}

// blur_line_z：z 维 −2 阶导 [−2,−4,+…]/16（out-of-place）。
kernel void bilateral3d_blur_line_z(
    device const float* ibuf [[buffer(0)]],
    device float*       obuf [[buffer(1)]],
    constant BilateralGridUniforms& u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float w1 = 4.0f/16.0f, w2 = 2.0f/16.0f;
    const int nx = u.sizeX, ny = u.sizeY, nz = u.sizeZ;
    const int x = (int)gid.x, y = (int)gid.y;
    if (x >= nx || y >= ny) return;
    {
        auto at = [&](int z) -> int { return ((x + nx * y) * nz + z); };
        float t1 = ibuf[at(0)];
        obuf[at(0)] = w1*ibuf[at(1)] + w2*ibuf[at(min(2, nz-1))];
        float t2 = ibuf[at(1)];
        obuf[at(1)] = w1*(ibuf[at(2)] - t1) + w2*ibuf[at(min(3, nz-1))];
        for (int z = 2; z < nz - 2; z++) {
            const float t3 = ibuf[at(z)];
            obuf[at(z)] = w1*(ibuf[at(z+1)] - t2) + w2*(ibuf[at(z+2)] - t1);
            t1 = t2; t2 = t3;
        }
        if (nz > 3) {
            const float t3 = ibuf[at(nz-2)];
            obuf[at(nz-2)] = w1*(ibuf[at(nz-1)] - t2) - w2*t1;
            obuf[at(nz-1)] = -w1*t3 - w2*t2;
        }
    }
}

// slice：三线性查表 + detail norm（dt slice 形，detail=−1 基底）。
// out = in（COPY）后 L 通道替换为 max(0, L + norm × (p − L))。
kernel void bilateral3d_slice(
    texture2d<float, access::read>  in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float*             grid [[buffer(0)]],
    constant BilateralGridUniforms& u [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.width || gid.y >= (uint)u.height) return;
    const float4 px = in.read(gid);
    const float L = px.x;
    const float gx = clamp((float)gid.x / u.sigmaS, 0.0f, (float)(u.sizeX - 1));
    const float gy = clamp((float)gid.y / u.sigmaS, 0.0f, (float)(u.sizeY - 1));
    const float gz = clamp(L / u.sigmaR, 0.0f, (float)(u.sizeZ - 1));
    const int xi = min((int)gx, u.sizeX - 2);
    const int yi = min((int)gy, u.sizeY - 2);
    const int zi = min((int)gz, u.sizeZ - 2);
    const float fx = gx - (float)xi;
    const float fy = gy - (float)yi;
    const float fz = gz - (float)zi;
    const int base = (xi + u.sizeX * yi) * u.sizeZ + zi;
    // dt CPU strides（同 splat 注释；dt slice_to_output :261-263 对偶）。
    const int ox = u.sizeZ, oy = u.sizeX * u.sizeZ, oz = 1;
    const int offs[8] = { 0, ox, oy, oy+ox, oz, oz+ox, oz+oy, oz+oy+ox };
    const float ws[8] = {
        (1-fx)*(1-fy)*(1-fz), fx*(1-fy)*(1-fz),
        (1-fx)*fy*(1-fz),     fx*fy*(1-fz),
        (1-fx)*(1-fy)*fz,     fx*(1-fy)*fz,
        (1-fx)*fy*fz,         fx*fy*fz,
    };
    float ldiff = 0;
    for (int k = 0; k < 8; k++) {
        ldiff += grid[base + offs[k]] * ws[k];
    }
    const float norm = -u.detail * u.sigmaR * 0.04f;
    const float Lout = fmax(0.0f, L + norm * ldiff);
    out.write(float4(Lout, px.y, px.z, px.w), gid);
}

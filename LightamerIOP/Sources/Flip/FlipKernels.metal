#include <metal_stdlib>
using namespace metal;

// flip iop kernel (Plan 04-02-T2, IOP-GEO-04).
//
// Verbatim port of Darktable's `basic.cl:2933-2967` flip kernel (tree
// dc58cf0ba1): per INPUT pixel `gid`, mirror X/Y by the orientation bits,
// then swap XY — and write to the OUTPUT coord. Dispatch spans the INPUT
// plane (dt `process_cl` passes `width/height` = roi_in as the grid).
//
// Bit layout (`image.h:137-140`): bit0 = FLIP_Y (vertical), bit1 = FLIP_X
// (horizontal), bit2 = SWAP_XY (transpose / 90° steps).
//
// L006: float32 math only — pure index remap, no sampling. Alpha rides
// the pixel untouched.

struct FlipUniforms {
    int orientation;
    int inWidth;
    int inHeight;
};

kernel void flip_apply(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    constant FlipUniforms&            u      [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    if (gid.x >= uint(u.inWidth) || gid.y >= uint(u.inHeight)) { return; }

    // ORIENTATION_FLIP_X = 2
    int ox = (u.orientation & 2) ? u.inWidth - int(gid.x) - 1 : int(gid.x);

    // ORIENTATION_FLIP_Y = 1
    int oy = (u.orientation & 1) ? u.inHeight - int(gid.y) - 1 : int(gid.y);

    // ORIENTATION_SWAP_XY = 4
    if (u.orientation & 4) {
        const int tmp = ox;
        ox = oy;
        oy = tmp;
    }

    out.write(in.read(gid), uint2(ox, oy));
}

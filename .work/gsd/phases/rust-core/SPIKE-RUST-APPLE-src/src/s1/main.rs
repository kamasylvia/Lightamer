// S1 — CIRAWFilter from Rust: decode the A7R5 CC0 sample, render into a
// MTLTexture via a Metal-backed CIContext, read back. Five cold iterations.

use objc2::rc::{autoreleasepool, Retained};
use objc2_core_foundation::{CGRect, CGSize};
use objc2_core_graphics::{CGColorSpace, CGColorSpaceCreateWithName, kCGColorSpaceExtendedLinearSRGB};
use objc2_core_image::{CIContext, CIRAWDecoderVersion8, CIRAWFilter};
use objc2_foundation::{NSArray, NSString, NSURL};
use objc2_metal::*;
use std::ffi::c_void;
use std::ptr::NonNull;
use std::time::Instant;

fn main() {
    unsafe {
        autoreleasepool(|_| {
            let path = std::env::args().nth(1).unwrap_or_else(|| {
                format!(
                    "{}/Library/Application Support/Lightamer/TestRAW/7RM5-LosslessCompressedLarge.ARW",
                    std::env::var("HOME").unwrap()
                )
            });
            println!("file: {path}");
            let device = MTLCreateSystemDefaultDevice().expect("no Metal device");
            println!("device: {}", device.name());
            let queue = device.newCommandQueue().expect("queue");

            let url = NSURL::fileURLWithPath(&NSString::from_str(&path));
            let filter = CIRAWFilter::filterWithImageURL(&url).expect("CIRAWFilter init failed");
            let versions: Retained<NSArray<NSString>> = filter.supportedDecoderVersions();
            let vlist: Vec<String> = versions.to_vec().iter().map(|v| v.to_string()).collect();
            println!("supportedDecoderVersions: {vlist:?}");

            filter.setDecoderVersion(CIRAWDecoderVersion8);
            println!("decoderVersion set to: {}", filter.decoderVersion());

            let native: CGSize = filter.nativeSize();
            println!("nativeSize: {} x {}", native.width, native.height);

            // Metal-backed CIContext, EDR-capable float target.
            let ctx = CIContext::contextWithMTLDevice(&device);
            let cs = CGColorSpaceCreateWithName(Some(kCGColorSpaceExtendedLinearSRGB))
                .expect("extended linear sRGB color space");

            let w = native.width as usize;
            let h = native.height as usize;
            let pf = MTLPixelFormat::RGBA16Float;
            let desc = MTLTextureDescriptor::texture2DDescriptorWithPixelFormat_width_height_mipmapped(
                pf, w, h, false,
            );
            desc.setUsage(
                MTLTextureUsage::ShaderRead | MTLTextureUsage::ShaderWrite | MTLTextureUsage::RenderTarget,
            );
            desc.setStorageMode(MTLStorageMode::Shared);
            let tex_in = device.newTextureWithDescriptor(&desc).expect("CI target texture");
            println!(
                "render target: {}x{} {:?} bytes={}",
                w,
                h,
                pf,
                w * h * 8
            );

            let region = MTLRegion {
                origin: MTLOrigin { x: 0, y: 0, z: 0 },
                size: MTLSize { width: w, height: h, depth: 1 },
            };
            let mut out = vec![0u8; w * h * 8];
            let bounds = CGRect {
                origin: objc2_core_foundation::CGPoint { x: 0.0, y: 0.0 },
                size: CGSize { width: native.width, height: native.height },
            };

            let mut times = Vec::new();
            let mut img_size = (0usize, 0usize);
            for i in 0..5 {
                let t0 = Instant::now();
                let f = CIRAWFilter::filterWithImageURL(&url).expect("filter");
                f.setDecoderVersion(CIRAWDecoderVersion8);
                let t_filter = t0.elapsed();
                let image = f.outputImage().expect("outputImage");
                let ext = image.extent();
                img_size = (ext.size.width as usize, ext.size.height as usize);

                let cb = queue.commandBuffer().expect("cb");
                ctx.render_toMTLTexture_commandBuffer_bounds_colorSpace(
                    &image,
                    &tex_in,
                    Some(&cb),
                    bounds,
                    &cs,
                );
                cb.commit();
                cb.waitUntilCompleted();
                tex_in.getBytes_bytesPerRow_fromRegion_mipmapLevel(
                    NonNull::new_unchecked(out.as_mut_ptr() as *mut c_void),
                    w * 8,
                    region,
                    0,
                );
                let total = t0.elapsed();
                println!(
                    "run {}: filter {:.1}ms  full decode+render+readback {:.1}ms  extent {}x{}",
                    i + 1,
                    t_filter.as_secs_f64() * 1000.0,
                    total.as_secs_f64() * 1000.0,
                    ext.size.width,
                    ext.size.height
                );
                times.push(total.as_secs_f64() * 1000.0);
                let _ = &f;
            }
            times.sort_by(|a, b| a.partial_cmp(b).unwrap());
            println!("median decode+render+readback: {:.1} ms", times[2]);
            println!("image extent: {}x{}", img_size.0, img_size.1);
            // cheap non-empty proof (sum of first 4KB bytes)
            let sum: u64 = out.iter().take(4096).map(|b| *b as u64).sum();
            println!("first-4KB byte sum: {sum}");
            let _ = device; // keep device alive until here
        });
    }
}

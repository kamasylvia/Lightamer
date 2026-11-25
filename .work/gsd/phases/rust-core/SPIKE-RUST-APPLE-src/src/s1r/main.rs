// S1b — rawspeed decode -> in-memory DNG -> CIRAWFilter (image data, no temp file).
use objc2::rc::autoreleasepool;
use objc2_core_foundation::{CGRect, CGSize};
use objc2_core_graphics::{CGColorSpace, CGColorSpaceCreateWithName, kCGColorSpaceExtendedLinearSRGB};
use objc2_core_image::{CIContext, CIRAWDecoderVersion8, CIRAWFilter};
use objc2_foundation::{NSData, NSString};
use objc2_metal::*;
use std::ffi::{c_char, c_void, CStr};
use std::ptr::NonNull;
use std::time::Instant;

#[repr(C)]
struct RsError {
    code: i32,
    message: [c_char; 512],
}
#[repr(C)]
struct RsImage {
    _private: [u8; 0],
}

extern "C" {
    fn rs_open(path: *const c_char, cameras_xml: *const c_char, err: *mut RsError) -> *mut RsImage;
    fn rs_build_dng(
        img: *const RsImage,
        downsample: i32,
        out_bytes: *mut *mut u8,
        out_len: *mut usize,
        err: *mut RsError,
    ) -> i32;
    fn rs_free_bytes(bytes: *mut u8);
    fn rs_free(img: *mut RsImage);
    fn rs_fill_info(img: *const RsImage, out: *mut RsImageInfo, err: *mut RsError) -> i32;
}

#[repr(C)]
struct RsImageInfo {
    width: i32,
    height: i32,
    uncropped_width: i32,
    uncropped_height: i32,
    crop_left: i32,
    crop_top: i32,
    crop_right: i32,
    crop_bottom: i32,
    pitch_elems: i32,
    cpp: i32,
    bpp: i32,
    is_cfa: i32,
    is_xtrans: i32,
    cfa_dcraw_filter: u32,
    cfa_pattern: [i32; 4],
    black_level: i32,
    black_level_separate: [i32; 4],
    white_level: i32,
    wb_coeffs: [f32; 3],
    color_matrix: [f32; 9],
    make: [c_char; 64],
    model: [c_char; 64],
    has_color_matrix: i32,
    has_wb: i32,
}

fn err_str(e: &RsError) -> String {
    unsafe { CStr::from_ptr(e.message.as_ptr()).to_string_lossy().into_owned() }
}

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
            let cpath = std::ffi::CString::new(path.clone()).unwrap();
            let cam = std::env::args().nth(2).unwrap_or_else(|| {
                "/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/rawspeed/data/cameras.xml".into()
            });
            let ccam = std::ffi::CString::new(cam.clone()).unwrap();
            println!("cameras.xml: {cam}");
            let mut err = RsError { code: 0, message: [0; 512] };
            let device = MTLCreateSystemDefaultDevice().expect("no Metal device");
            let queue = device.newCommandQueue().expect("queue");
            let ctx = CIContext::contextWithMTLDevice(&device);
            let cs = CGColorSpaceCreateWithName(Some(kCGColorSpaceExtendedLinearSRGB)).unwrap();

            let mut totals = Vec::new();
            for run in 0..5 {
                let t0 = Instant::now();
                let img = rs_open(cpath.as_ptr(), ccam.as_ptr(), &mut err);
                if img.is_null() {
                    eprintln!("rs_open failed: {} ({})", err_str(&err), err.code);
                    std::process::exit(4);
                }
                let t_rs = t0.elapsed();
                let mut info: RsImageInfo = std::mem::zeroed();
                if rs_fill_info(img, &mut info, &mut err) != 0 {
                    eprintln!("rs_fill_info failed: {}", err_str(&err));
                    std::process::exit(5);
                }
                if run == 0 {
                    let make = CStr::from_ptr(info.make.as_ptr()).to_string_lossy().to_string();
                    let model = CStr::from_ptr(info.model.as_ptr()).to_string_lossy().to_string();
                    println!(
                        "rawspeed: {} {} mosaic {}x{} cfa={} xtrans={} black={} white={}",
                        make, model, info.width, info.height, info.is_cfa, info.is_xtrans,
                        info.black_level, info.white_level
                    );
                }

                let t_dng = Instant::now();
                let mut dng_ptr: *mut u8 = std::ptr::null_mut();
                let mut dng_len: usize = 0;
                if rs_build_dng(img, 0, &mut dng_ptr, &mut dng_len, &mut err) != 0 {
                    eprintln!("rs_build_dng failed: {}", err_str(&err));
                    std::process::exit(6);
                }
                let t_dng_build = t_dng.elapsed();
                let data = NSData::dataWithBytes_length(dng_ptr as *const c_void, dng_len);
                rs_free_bytes(dng_ptr);
                rs_free(img);

                let t_ci = Instant::now();
                let hint = NSString::from_str("DNG");
                let filter = CIRAWFilter::filterWithImageData_identifierHint(&data, Some(&hint))
                    .expect("CIRAWFilter from DNG data failed");
                let versions: Vec<String> = filter
                    .supportedDecoderVersions()
                    .to_vec()
                    .iter()
                    .map(|v| v.to_string())
                    .collect();
                filter.setDecoderVersion(CIRAWDecoderVersion8);
                let native: CGSize = filter.nativeSize();
                let t_filter = t_ci.elapsed();

                let w = native.width as usize;
                let h = native.height as usize;
                let desc = MTLTextureDescriptor::texture2DDescriptorWithPixelFormat_width_height_mipmapped(
                    MTLPixelFormat::RGBA16Float, w, h, false,
                );
                desc.setUsage(
                    MTLTextureUsage::ShaderRead | MTLTextureUsage::ShaderWrite | MTLTextureUsage::RenderTarget,
                );
                desc.setStorageMode(MTLStorageMode::Shared);
                let tex = device.newTextureWithDescriptor(&desc).expect("texture");
                let region = MTLRegion {
                    origin: MTLOrigin { x: 0, y: 0, z: 0 },
                    size: MTLSize { width: w, height: h, depth: 1 },
                };
                let mut out = vec![0u8; w * h * 8];
                let bounds = CGRect {
                    origin: objc2_core_foundation::CGPoint { x: 0.0, y: 0.0 },
                    size: native,
                };
                let image = filter.outputImage().expect("outputImage");
                let cb = queue.commandBuffer().expect("cb");
                ctx.render_toMTLTexture_commandBuffer_bounds_colorSpace(&image, &tex, Some(&cb), bounds, &cs);
                cb.commit();
                cb.waitUntilCompleted();
                tex.getBytes_bytesPerRow_fromRegion_mipmapLevel(
                    NonNull::new_unchecked(out.as_mut_ptr() as *mut c_void),
                    w * 8,
                    region,
                    0,
                );
                let t_render = t_ci.elapsed();
                let total = t0.elapsed();
                if run == 0 {
                    println!("supportedDecoderVersions(DNG): {versions:?}");
                    println!("decoderVersion after set: {}", filter.decoderVersion());
                    println!("CIRAW nativeSize(DNG): {} x {} ({:.1}MB RGBA16F)", w, h, (w*h*8) as f64/1e6);
                    println!("first-4KB byte sum: {}", out.iter().take(4096).map(|b| *b as u64).sum::<u64>());
                }
                println!(
                    "run {}: rawspeed {:.1}ms  DNG build {:.1}ms  CIRAW filter {:.1}ms  render+readback {:.1}ms  total {:.1}ms (DNG {:.1}MB)",
                    run+1,
                    t_rs.as_secs_f64()*1000.0,
                    t_dng_build.as_secs_f64()*1000.0,
                    t_filter.as_secs_f64()*1000.0,
                    (t_render - t_filter).as_secs_f64()*1000.0,
                    total.as_secs_f64()*1000.0,
                    dng_len as f64/1e6
                );
                totals.push(total.as_secs_f64()*1000.0);
            }
            totals.sort_by(|a,b| a.partial_cmp(b).unwrap());
            println!("median rawspeed+in-memory-DNG+CIRAW total: {:.1} ms", totals[2]);
        });
    }
}

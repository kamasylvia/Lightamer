// S3 — ImageIO encode/decode + ColorSync transform, all from Rust.
// - encode RGBA8 into JPEG / HEIC / AVIF with an embedded ICC profile
// - read back and print the embedded profile name
// - ColorSync: sRGB ICC -> Display P3 ICC on a float32 RGB buffer,
//   byte-compared against the Swift reference (out/s3-cs-*.bin).

use objc2_core_foundation::{CFArray, CFData, CFDictionary, CFMutableData, CFRetained, CFString, CFURL, CFURLPathStyle};
use objc2_core_graphics::{
    CGColorRenderingIntent, CGColorSpace, CGDataProvider, CGImage, CGImageAlphaInfo, CGBitmapInfo,
};
use objc2_image_io::{
    CGImageDestinationAddImage, CGImageDestinationCreateWithData, CGImageDestinationFinalize,
    CGImageSourceCopyPropertiesAtIndex, CGImageSourceCreateImageAtIndex, CGImageSourceCreateWithData,
    kCGImagePropertyProfileName,
};
use std::ffi::c_void;
use std::fs;

#[link(name = "ColorSync", kind = "framework")]
extern "C" {
    fn ColorSyncProfileCreateWithURL(url: *const c_void, error: *mut *mut c_void) -> *const c_void;
    fn ColorSyncTransformCreate(profile_sequence: *const c_void, options: *const c_void) -> *const c_void;
    fn ColorSyncTransformConvert(
        transform: *const c_void,
        width: usize,
        height: usize,
        dst: *mut c_void,
        dst_depth: u32,
        dst_layout: u32,
        dst_bytes_per_row: usize,
        src: *const c_void,
        src_depth: u32,
        src_layout: u32,
        src_bytes_per_row: usize,
        options: *const c_void,
    ) -> bool;
    fn CFRelease(cf: *const c_void);
    static kColorSyncProfile: *const c_void;
    static kColorSyncRenderingIntent: *const c_void;
    static kColorSyncTransformTag: *const c_void;
    static kColorSyncRenderingIntentRelative: *const c_void;
    static kColorSyncTransformDeviceToPCS: *const c_void;
    static kColorSyncTransformPCSToDevice: *const c_void;
}

// ColorSyncDataDepth / ColorSyncDataLayout (SDK ColorSyncTransform.h)
const CS_32BIT_FLOAT: u32 = 7;
const CS_ALPHA_NONE: u32 = 0;

extern "C" {
    fn CGColorSpaceCreateWithICCData(data: *const c_void) -> *const c_void;
    fn CGColorSpaceRelease(space: *const c_void);
    fn CFStringGetCString(s: *const c_void, buf: *mut u8, size: isize, enc: u32) -> bool;
}
const K_CF_STRING_ENCODING_UTF8: u32 = 0x0800_0100;

unsafe fn cfstr_to_string(p: *const c_void) -> String {
    if p.is_null() {
        return "<null>".into();
    }
    let mut buf = [0u8; 512];
    if CFStringGetCString(p, buf.as_mut_ptr(), buf.len() as isize, K_CF_STRING_ENCODING_UTF8) {
        let end = buf.iter().position(|b| *b == 0).unwrap_or(buf.len());
        String::from_utf8_lossy(&buf[..end]).into_owned()
    } else {
        "<unconvertible>".into()
    }
}

fn pattern_rgba(w: usize, h: usize) -> Vec<u8> {
    let mut v = Vec::with_capacity(w * h * 4);
    for y in 0..h {
        for x in 0..w {
            v.push((x * 255 / w) as u8);
            v.push((y * 255 / h) as u8);
            v.push(((x * 7 + y * 13) % 256) as u8);
            v.push(255);
        }
    }
    v
}

fn main() {
    unsafe {
        let icc_path = "/System/Library/ColorSync/Profiles/sRGB Profile.icc";
        let icc = fs::read(icc_path).expect("read sRGB ICC");
        println!("ICC: {icc_path} ({} bytes)", icc.len());

        let w = 64usize;
        let h = 48usize;
        let rgba = pattern_rgba(w, h);

        // CFData copies the ICC bytes.
        let icc_cf = CFData::new(None, icc.as_ptr(), icc.len() as isize).expect("CFData ICC");
        let cs_ptr = CGColorSpaceCreateWithICCData(CFRetained::as_ptr(&icc_cf).as_ptr() as *const c_void);
        if cs_ptr.is_null() {
            eprintln!("CGColorSpaceCreateWithICCData returned NULL");
            std::process::exit(2);
        }
        let space: &CGColorSpace = &*(cs_ptr as *const CGColorSpace);

        let provider_data = CFData::new(None, rgba.as_ptr(), rgba.len() as isize).expect("CFData px");
        let provider = CGDataProvider::with_cf_data(Some(&provider_data)).expect("provider");
        let bitmap_info = CGBitmapInfo(CGImageAlphaInfo::PremultipliedLast.0);
        let image = CGImage::new(
            w,
            h,
            8,
            32,
            w * 4,
            Some(space),
            bitmap_info,
            Some(&provider),
            std::ptr::null(),
            false,
            CGColorRenderingIntent::RenderingIntentDefault,
        )
        .expect("CGImage");
        println!("CGImage created: {}x{} with ICC-derived color space", w, h);

        for (uti, ext) in [
            ("public.jpeg", "jpg"),
            ("public.heic", "heic"),
            ("public.avif", "avif"),
        ] {
            let dest_data = CFMutableData::new(None, 0).expect("CFMutableData");
            let uti_cf = CFString::from_str(uti);
            match CGImageDestinationCreateWithData(&dest_data, &uti_cf, 1, None) {
                Some(dest) => {
                    CGImageDestinationAddImage(&dest, &image, None);
                    if !CGImageDestinationFinalize(&dest) {
                        println!("{uti}: finalize FAILED");
                        continue;
                    }
                    let d: &CFData = &*(CFRetained::as_ptr(&dest_data).as_ptr() as *const CFData);
                    let len = d.length() as usize;
                    let bytes = std::slice::from_raw_parts(d.byte_ptr(), len);
                    let path = format!("out/s3.{ext}");
                    fs::write(&path, bytes).unwrap();
                    println!("{uti}: encoded {} bytes -> {path}", len);

                    // read back
                    match CGImageSourceCreateWithData(d, None) {
                        Some(src) => {
                            let mut profile = "<no properties>".to_string();
                            if let Some(props) = CGImageSourceCopyPropertiesAtIndex(&src, 0, None) {
                                let key = kCGImagePropertyProfileName as *const CFString as *const c_void;
                                let val = props.value(key);
                                profile = cfstr_to_string(val);
                            }
                            let mut dims = (0, 0);
                            if let Some(rimg) = CGImageSourceCreateImageAtIndex(&src, 0, None) {
                                dims = (CGImage::width(Some(&rimg)), CGImage::height(Some(&rimg)));
                                if let Some(rcs) = CGImage::color_space(Some(&rimg)) {
                                    if let Some(name) = CGColorSpace::name(Some(&rcs)) {
                                        println!(
                                            "{uti}: readback {}x{} profileName='{}' colorSpaceName='{}'",
                                            dims.0,
                                            dims.1,
                                            profile,
                                            name
                                        );
                                        continue;
                                    }
                                }
                            }
                            println!("{uti}: readback {}x{} profileName='{}'", dims.0, dims.1, profile);
                        }
                        None => println!("{uti}: CGImageSourceCreateWithData FAILED"),
                    }
                }
                None => println!("{uti}: CGImageDestinationCreateWithData FAILED (UTI unsupported?)"),
            }
        }

        // ---------- ColorSync transform ----------
        let srgb_url = CFURL::with_file_system_path(
            None,
            Some(&CFString::from_str("/System/Library/ColorSync/Profiles/sRGB Profile.icc")),
            CFURLPathStyle::CFURLPOSIXPathStyle,
            false,
        )
        .expect("CFURL sRGB");
        let p3_url = CFURL::with_file_system_path(
            None,
            Some(&CFString::from_str("/System/Library/ColorSync/Profiles/Display P3.icc")),
            CFURLPathStyle::CFURLPOSIXPathStyle,
            false,
        )
        .expect("CFURL P3");
        let src_profile = ColorSyncProfileCreateWithURL(CFRetained::as_ptr(&srgb_url).as_ptr() as *const c_void, std::ptr::null_mut());
        let dst_profile = ColorSyncProfileCreateWithURL(CFRetained::as_ptr(&p3_url).as_ptr() as *const c_void, std::ptr::null_mut());
        if src_profile.is_null() || dst_profile.is_null() {
            eprintln!("ColorSyncProfileCreateWithURL failed");
            std::process::exit(3);
        }
        // profileSequence must be an array of DICTIONARIES carrying
        // kColorSyncProfile + kColorSyncRenderingIntent + kColorSyncTransformTag.
        let mut keys: [*const c_void; 3] = [
            kColorSyncProfile,
            kColorSyncRenderingIntent,
            kColorSyncTransformTag,
        ];
        let mut vals_src: [*const c_void; 3] = [
            src_profile,
            kColorSyncRenderingIntentRelative,
            kColorSyncTransformDeviceToPCS,
        ];
        let mut vals_dst: [*const c_void; 3] = [
            dst_profile,
            kColorSyncRenderingIntentRelative,
            kColorSyncTransformPCSToDevice,
        ];
        let dict_src = CFDictionary::new(
            None,
            keys.as_mut_ptr(),
            vals_src.as_mut_ptr(),
            3,
            &objc2_core_foundation::kCFTypeDictionaryKeyCallBacks,
            &objc2_core_foundation::kCFTypeDictionaryValueCallBacks,
        )
        .expect("src profile dict");
        let dict_dst = CFDictionary::new(
            None,
            keys.as_mut_ptr(),
            vals_dst.as_mut_ptr(),
            3,
            &objc2_core_foundation::kCFTypeDictionaryKeyCallBacks,
            &objc2_core_foundation::kCFTypeDictionaryValueCallBacks,
        )
        .expect("dst profile dict");
        let mut dict_ptrs: [*const c_void; 2] = [
            CFRetained::as_ptr(&dict_src).as_ptr() as *const c_void,
            CFRetained::as_ptr(&dict_dst).as_ptr() as *const c_void,
        ];
        let seq = CFArray::new(
            None,
            dict_ptrs.as_mut_ptr(),
            2,
            &objc2_core_foundation::kCFTypeArrayCallBacks,
        )
        .expect("CFArray profiles");
        let transform = ColorSyncTransformCreate(CFRetained::as_ptr(&seq).as_ptr() as *const c_void, std::ptr::null());
        if transform.is_null() {
            eprintln!("ColorSyncTransformCreate failed");
            std::process::exit(4);
        }
        println!("ColorSync transform created: sRGB ICC -> Display P3 ICC");

        // float32 RGB, 3 channels
        let tw = 16usize;
        let th = 16usize;
        let mut src = Vec::with_capacity(tw * th * 3);
        for y in 0..th {
            for x in 0..tw {
                src.push((x as f32 + 0.5) / tw as f32);
                src.push((y as f32 + 0.5) / th as f32);
                src.push(((x + y) as f32 + 0.5) / (tw + th) as f32);
            }
        }
        let src_bytes = std::slice::from_raw_parts(src.as_ptr() as *const u8, src.len() * 4);
        fs::write("out/s3-cs-src-rust.bin", src_bytes).unwrap();

        let mut dst = vec![0f32; tw * th * 3];
        let ok = ColorSyncTransformConvert(
            transform,
            tw,
            th,
            dst.as_mut_ptr() as *mut c_void,
            CS_32BIT_FLOAT,
            CS_ALPHA_NONE,
            tw * 12,
            src.as_ptr() as *const c_void,
            CS_32BIT_FLOAT,
            CS_ALPHA_NONE,
            tw * 12,
            std::ptr::null(),
        );
        println!("ColorSyncTransformConvert(3ch float) = {ok}");
        if ok {
            let out_bytes = std::slice::from_raw_parts(dst.as_ptr() as *const u8, dst.len() * 4);
            fs::write("out/s3-cs-rust.bin", out_bytes).unwrap();
            println!(
                "wrote out/s3-cs-rust.bin ({} bytes), first rgb = [{:.6},{:.6},{:.6}]",
                out_bytes.len(),
                dst[0],
                dst[1],
                dst[2]
            );
        } else {
            println!("3-channel float layout rejected; see report");
        }

        CFRelease(transform);
        CFRelease(src_profile);
        CFRelease(dst_profile);
        CGColorSpaceRelease(cs_ptr);
        let _ = (image, space, provider, provider_data, icc_cf);
    }
}

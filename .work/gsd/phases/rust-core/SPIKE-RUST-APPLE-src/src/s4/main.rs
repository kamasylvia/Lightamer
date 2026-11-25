// S4 — Rust host runs the repo's unmodified Metal shaders.
// Compiles Passthrough.metal + ExposureKernels.metal at runtime from source,
// dispatches pass_through (with function constants) then exposure_apply,
// reads back RGBA32Float and writes s4-rust.bin for byte comparison vs Swift.

use objc2::rc::autoreleasepool;
use objc2_foundation::NSString;
use objc2_metal::*;
use std::ffi::c_void;
use std::ptr::NonNull;
use std::fs;

const W: usize = 257;
const H: usize = 193;

fn main() {
    unsafe {
        autoreleasepool(|_| {
            let device = MTLCreateSystemDefaultDevice().expect("no Metal device");
            println!("device: {}", device.name());

            let shader_dir = std::env::args().nth(1).unwrap_or_else(|| "shaders".into());
            let src = format!(
                "{}\n{}\n",
                fs::read_to_string(format!("{shader_dir}/Passthrough.metal")).unwrap(),
                fs::read_to_string(format!("{shader_dir}/ExposureKernels.metal")).unwrap()
            );

            // --- compile library from source (runtime MSL compilation) ---
            let ns_src = NSString::from_str(&src);
            let library = match device.newLibraryWithSource_options_error(&ns_src, None) {
                Ok(lib) => lib,
                Err(e) => {
                    eprintln!("newLibraryWithSource failed: {}", e.localizedDescription());
                    std::process::exit(3);
                }
            };
            println!("library compiled from source at runtime");

            // --- function constants for pass_through ---
            let consts = MTLFunctionConstantValues::new();
            let use_srgb: bool = false;
            let ev: f32 = 0.5;
            consts.setConstantValue_type_atIndex(
                NonNull::new_unchecked(&use_srgb as *const bool as *mut c_void),
                MTLDataType::Bool,
                0,
            );
            consts.setConstantValue_type_atIndex(
                NonNull::new_unchecked(&ev as *const f32 as *mut c_void),
                MTLDataType::Float,
                1,
            );
            let name = NSString::from_str("pass_through");
            let f_pass = library
                .newFunctionWithName_constantValues_error(&name, &consts)
                .expect("pass_through function");
            let p_pass = device
                .newComputePipelineStateWithFunction_error(&f_pass)
                .expect("pass pipeline");

            let name2 = NSString::from_str("exposure_apply");
            let f_exp = library
                .newFunctionWithName(&name2)
                .expect("exposure_apply function");
            let p_exp = device
                .newComputePipelineStateWithFunction_error(&f_exp)
                .expect("exposure pipeline");

            // --- textures ---
            let desc = MTLTextureDescriptor::texture2DDescriptorWithPixelFormat_width_height_mipmapped(
                MTLPixelFormat::RGBA32Float,
                W,
                H,
                false,
            );
            desc.setUsage(MTLTextureUsage::ShaderRead | MTLTextureUsage::ShaderWrite);
            desc.setStorageMode(MTLStorageMode::Shared);
            let tex_in = device.newTextureWithDescriptor(&desc).expect("tex in");
            let tex_mid = device.newTextureWithDescriptor(&desc).expect("tex mid");
            let tex_out = device.newTextureWithDescriptor(&desc).expect("tex out");

            // --- deterministic input, also written for the Swift reference ---
            let mut input = vec![0f32; W * H * 4];
            for y in 0..H {
                for x in 0..W {
                    let i = (y * W + x) * 4;
                    input[i] = ((x * 3 + y * 5) as f32) * 0.001;
                    input[i + 1] = (((x * y) % 97) as f32) / 97.0;
                    input[i + 2] = (x as f32 + 0.5) / W as f32;
                    input[i + 3] = 1.0;
                }
            }
            fs::write("out/s4-input.bin", floats_to_bytes(&input)).unwrap();

            let region = MTLRegion {
                origin: MTLOrigin { x: 0, y: 0, z: 0 },
                size: MTLSize { width: W, height: H, depth: 1 },
            };
            tex_in.replaceRegion_mipmapLevel_withBytes_bytesPerRow(
                region,
                0,
                NonNull::new_unchecked(input.as_ptr() as *mut c_void),
                W * 16,
            );

            let queue = device.newCommandQueue().expect("queue");
            let cb = queue.commandBuffer().expect("cb");

            // pass 1: pass_through
            let enc = cb.computeCommandEncoder().expect("enc1");
            enc.setComputePipelineState(&p_pass);
            enc.setTexture_atIndex(Some(&tex_in), 0);
            enc.setTexture_atIndex(Some(&tex_mid), 1);
            let tg = MTLSize { width: 16, height: 16, depth: 1 };
            let groups = MTLSize {
                width: (W + 15) / 16,
                height: (H + 15) / 16,
                depth: 1,
            };
            enc.dispatchThreadgroups_threadsPerThreadgroup(groups, tg);
            enc.endEncoding();

            // pass 2: exposure_apply (black=0.02, scale=1.35)
            #[repr(C)]
            struct Uniforms {
                black: f32,
                scale: f32,
            }
            let u = Uniforms { black: 0.02, scale: 1.35 };
            let enc2 = cb.computeCommandEncoder().expect("enc2");
            enc2.setComputePipelineState(&p_exp);
            enc2.setTexture_atIndex(Some(&tex_mid), 0);
            enc2.setTexture_atIndex(Some(&tex_out), 1);
            enc2.setBytes_length_atIndex(NonNull::new_unchecked(&u as *const Uniforms as *mut c_void), 8, 0);
            enc2.dispatchThreadgroups_threadsPerThreadgroup(groups, tg);
            enc2.endEncoding();

            cb.commit();
            cb.waitUntilCompleted();

            let mut out = vec![0u8; W * H * 16];
            tex_out.getBytes_bytesPerRow_fromRegion_mipmapLevel(
                NonNull::new_unchecked(out.as_mut_ptr() as *mut c_void),
                W * 16,
                region,
                0,
            );
            fs::write("out/s4-rust.bin", &out).unwrap();

            // sanity: print a few texels
            let f: &[f32] = bytemuck_cast(&out);
            println!(
                "first texel rgba = [{:.6}, {:.6}, {:.6}, {:.1}]",
                f[0], f[1], f[2], f[3]
            );
            println!("wrote out/s4-rust.bin ({} bytes)", out.len());
        });
    }
}

fn floats_to_bytes(v: &[f32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(v.len() * 4);
    for f in v {
        out.extend_from_slice(&f.to_le_bytes());
    }
    out
}

fn bytemuck_cast(bytes: &[u8]) -> &[f32] {
    unsafe { std::slice::from_raw_parts(bytes.as_ptr() as *const f32, bytes.len() / 4) }
}

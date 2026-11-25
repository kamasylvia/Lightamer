// Build the rawspeed C ABI shim (reused from the repo's spike-src verbatim).
use std::env;

fn main() {
    let rs_root = env::var("RAWSPEED_SPIKE_ROOT")
        .unwrap_or_else(|_| "/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike".into());
    let lib_dir = format!("{rs_root}/build/rawspeed");
    println!("cargo:rerun-if-changed=csrc/rawspeed_shim.cpp");
    println!("cargo:rerun-if-changed=csrc/rawspeed_shim.h");
    println!("cargo:rerun-if-changed=csrc/dngwriter.h");

    cc::Build::new()
        .cpp(true)
        .std("c++20")
        .file("csrc/rawspeed_shim.cpp")
        .include("csrc")
        .include(format!("{rs_root}/rawspeed/src/librawspeed"))
        .include(format!("{lib_dir}/src"))
        .include(format!("{rs_root}/rawspeed/src/external"))
        .include("/opt/homebrew/opt/libomp/include")
        .compile("rawspeed_shim");

    println!("cargo:rustc-link-search=native={lib_dir}");
    println!("cargo:rustc-link-lib=static=rawspeed");
    println!("cargo:rustc-link-search=native=/opt/homebrew/opt/libomp/lib");
    println!("cargo:rustc-link-lib=dylib=omp");
    println!("cargo:rustc-link-search=native=/opt/homebrew/opt/pugixml/lib");
    println!("cargo:rustc-link-lib=dylib=pugixml");
    println!("cargo:rustc-link-search=native=/opt/homebrew/opt/libjpeg-turbo/lib");
    println!("cargo:rustc-link-lib=dylib=jpeg");
    println!("cargo:rustc-link-lib=dylib=z");
    println!("cargo:rustc-link-lib=dylib=c++");
}

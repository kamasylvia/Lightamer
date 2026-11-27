// SPDX-License-Identifier: GPL-3.0-or-later
#![allow(clippy::expect_used, clippy::panic)] // Build scripts report failure via panic/expect; that is cargo's normal build-error path.
//! Builds rawspeed (pinned submodule) + the C shim + the oracle binary.
//!
//! Layout: everything lands under `OUT_DIR` (inside `target/`). rawspeed is
//! configured and built by the `cmake` crate (Release, static, OpenMP on);
//! the shim is compiled by the `cc` crate; `rs-oracle` is compiled by a
//! direct `c++` invocation against the same `librawspeed.a`.
//!
//! `cameras.xml` is COPIED into `OUT_DIR` (not embedded): the baked default
//! path `RS_CAMERAS_XML_DEFAULT` points at that copy. After re-pinning the
//! submodule, `touch` this file to force a rebuild (cargo cannot watch the
//! gitlink).

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Workspace root: `crates/lightamer-decode/` lives two levels below it.
fn workspace_root() -> PathBuf {
    let manifest = env::var("CARGO_MANIFEST_DIR").expect("B2-a: CARGO_MANIFEST_DIR unset");
    Path::new(&manifest)
        .join("..")
        .join("..")
        .canonicalize()
        .expect("B2-a: cannot canonicalize workspace root")
}

/// Ninja parallelism (repo discipline caps at 6).
const NINJA_JOBS: &str = "-j6";

/// Configure and build the rawspeed static lib; return its build dir and lib.
fn build_rawspeed(rs_src: &Path) -> (PathBuf, PathBuf) {
    let dst = cmake::Config::new(rs_src)
        .define("CMAKE_BUILD_TYPE", "Release")
        .define("CMAKE_OSX_ARCHITECTURES", "arm64")
        .define("CMAKE_OSX_DEPLOYMENT_TARGET", "27.0")
        .define("BUILD_TESTING", "OFF")
        .define("BUILD_TOOLS", "OFF")
        .define("BUILD_BENCHMARKING", "OFF")
        .define("BUILD_FUZZERS", "OFF")
        .define("BUILD_DOCS", "OFF")
        .define("WITH_OPENMP", "ON")
        .define("CMAKE_PREFIX_PATH", "/opt/homebrew")
        .define("OpenMP_ROOT", "/opt/homebrew/opt/libomp")
        .cxxflag("-I/opt/homebrew/opt/libomp/include")
        .build_arg(NINJA_JOBS)
        .build();
    let rs_build = dst.join("build");
    let rs_lib = rs_build.join("librawspeed.a");
    assert!(
        rs_lib.is_file(),
        "B2-a: librawspeed.a not found under {} (cmake dst = {})",
        rs_build.display(),
        dst.display()
    );
    (rs_build, rs_lib)
}

/// Compile `rs-oracle` against the same static lib; return its path.
fn compile_oracle(rs_src: &Path, rs_build: &Path, rs_lib: &Path, out: &Path) -> PathBuf {
    let oracle = out.join("rs-oracle");
    let cxx = env::var("CXX").unwrap_or_else(|_| "c++".to_owned());
    let status = Command::new(&cxx)
        .arg("-std=c++20")
        .arg("-O2")
        .arg("-I")
        .arg(rs_src.join("src").join("librawspeed"))
        .arg("-I")
        .arg(rs_src.join("src").join("external"))
        .arg("-I")
        .arg(rs_build.join("src"))
        .arg("-I")
        .arg("/opt/homebrew/opt/libomp/include")
        .arg("tools/rs-oracle.cpp")
        .arg(rs_lib)
        .arg("-L/opt/homebrew/opt/pugixml/lib")
        .arg("-lpugixml")
        .arg("-L/opt/homebrew/opt/libjpeg-turbo/lib")
        .arg("-ljpeg")
        .arg("-L/opt/homebrew/opt/libomp/lib")
        .arg("-lomp")
        .arg("-lz")
        .arg("-o")
        .arg(&oracle)
        .status()
        .expect("B2-a: cannot run C++ compiler for rs-oracle");
    assert!(
        status.success(),
        "B2-a: rs-oracle compile failed with {status}"
    );
    oracle
}

fn main() {
    let root = workspace_root();
    let out = PathBuf::from(env::var("OUT_DIR").expect("B2-a: OUT_DIR unset"));

    let rs_src = root.join("external").join("rawspeed");
    assert!(
        rs_src.join("CMakeLists.txt").is_file(),
        "B2-a: rawspeed submodule missing at {} (run `git submodule update --init external/rawspeed`)",
        rs_src.display()
    );

    // 1. rawspeed static lib, always Release (fast decode even under
    // `cargo test`; matches the spike recipe plus OpenMP_ROOT).
    let (rs_build, rs_lib) = build_rawspeed(&rs_src);

    // 2. Link: rawspeed static + Homebrew dylibs (absolute install names, no
    // rpath needed) + SDK zlib + libc++.
    println!("cargo:rustc-link-search=native={}", rs_build.display());
    println!("cargo:rustc-link-lib=static=rawspeed");
    println!("cargo:rustc-link-search=native=/opt/homebrew/opt/pugixml/lib");
    println!("cargo:rustc-link-lib=dylib=pugixml");
    println!("cargo:rustc-link-search=native=/opt/homebrew/opt/libjpeg-turbo/lib");
    println!("cargo:rustc-link-lib=dylib=jpeg");
    println!("cargo:rustc-link-search=native=/opt/homebrew/opt/libomp/lib");
    println!("cargo:rustc-link-lib=dylib=omp");
    println!("cargo:rustc-link-lib=z");
    println!("cargo:rustc-link-lib=c++");

    // 3. cameras.xml copied into OUT_DIR; the default meta path bakes it in.
    let cameras = out.join("cameras.xml");
    fs::copy(rs_src.join("data").join("cameras.xml"), &cameras)
        .expect("B2-a: cannot copy cameras.xml to OUT_DIR");
    let cameras_str = cameras
        .to_str()
        .expect("B2-a: OUT_DIR path is not UTF-8")
        .to_owned();

    // 4. The C shim.
    cc::Build::new()
        .cpp(true)
        .std("c++20")
        .include(rs_src.join("src").join("librawspeed"))
        .include(rs_src.join("src").join("external"))
        .include(rs_build.join("src"))
        .include("/opt/homebrew/opt/libomp/include")
        .define(
            "RS_CAMERAS_XML_DEFAULT",
            format!("\"{cameras_str}\"").as_str(),
        )
        .file("csrc/rawspeed_shim.cpp")
        .compile("lightamer_rawspeed_shim");

    // 5. The oracle.
    let oracle = compile_oracle(&rs_src, &rs_build, &rs_lib, &out);

    // 6. Compile-time env for the crate (lib + tests) + rerun guards.
    println!("cargo:rustc-env=RAWSPEED_CAMERAS_XML={cameras_str}");
    println!(
        "cargo:rustc-env=RS_ORACLE_BIN={}",
        oracle.to_str().expect("B2-a: oracle path is not UTF-8")
    );
    println!("cargo:rerun-if-changed=csrc/rawspeed_shim.h");
    println!("cargo:rerun-if-changed=csrc/rawspeed_shim.cpp");
    println!("cargo:rerun-if-changed=tools/rs-oracle.cpp");
    println!("cargo:rerun-if-changed=../../external/rawspeed/CMakeLists.txt");
    println!("cargo:rerun-if-changed=../../external/rawspeed/data/cameras.xml");
    println!("cargo:rerun-if-changed=../../external/rawspeed/src/librawspeed/RawSpeed-API.h");
}

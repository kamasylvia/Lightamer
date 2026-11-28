// SPDX-License-Identifier: GPL-3.0-or-later
#![allow(clippy::expect_used, clippy::panic)] // Build scripts report failure via panic/expect; that is cargo's normal build-error path.
//! Compiles the oracle static libs: verbatim upstream C plus the chain/stub
//! glue (C11), and the CFA shift wrapper (C++17). Optimizer on, FP contract
//! off, no fast math — the oracle must compute what upstream computes.

const C_SOURCES: &[&str] = &[
    "csrc/chain.c",
    "csrc/predicates_tu.c",
    "csrc/rawprepare_glue.c",
    "csrc/rawprepare_tu.c",
    "stubs/stubs.c",
];

const UPSTREAM_SOURCES: &[&str] = &[
    "upstream/dng_gainmap_struct.inc",
    "upstream/image_predicates.inc",
    "upstream/rawprepare_cfa.inc",
    "upstream/rawprepare_commit.inc",
    "upstream/rawprepare_crop.inc",
    "upstream/rawprepare_defaults.inc",
    "upstream/rawprepare_gainmaps.inc",
    "upstream/rawprepare_normalized.inc",
    "upstream/rawprepare_pipe.inc",
    "upstream/rawprepare_process.inc",
    "upstream/rawprepare_rawcrops.inc",
    "upstream/rawprepare_roi.inc",
    "upstream/rawprepare_types.inc",
    "upstream/rawspeed_crop.inc",
    "upstream/shift_dcraw.inc",
];

fn main() {
    cc::Build::new()
        .std("c11")
        .opt_level(2)
        .flag("-ffp-contract=off")
        .flag("-fno-fast-math")
        .includes(["upstream", "stubs", "csrc"])
        .files(C_SOURCES)
        .compile("lightamer_oracle_c");
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .opt_level(2)
        .flag("-ffp-contract=off")
        .flag("-fno-fast-math")
        .includes(["upstream", "stubs", "csrc"])
        .file("csrc/crop_tu.cpp")
        .compile("lightamer_oracle_cpp");
    for source in C_SOURCES
        .iter()
        .chain(UPSTREAM_SOURCES)
        .chain(["csrc/crop_tu.cpp", "csrc/oracle_abi.h", "stubs/dt_shim.h"].iter())
    {
        println!("cargo:rerun-if-changed={source}");
    }
}

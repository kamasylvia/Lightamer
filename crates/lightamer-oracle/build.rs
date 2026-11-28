// SPDX-License-Identifier: GPL-3.0-or-later
#![allow(clippy::expect_used, clippy::panic)] // Build scripts report failure via panic/expect; that is cargo's normal build-error path.
//! Compiles the oracle static libs: verbatim upstream C plus the chain/stub
//! glue (C11), and the CFA shift wrapper (C++17). Optimizer on, FP contract
//! off, no fast math — the oracle must compute what upstream computes.

// Glue the crate authors: warnings stay on (anything here is ours to fix).
const GLUE_SOURCES: &[&str] = &[
    "csrc/chain.c",
    "csrc/rawprepare_glue.c",
    "csrc/hotpixels_glue.c",
    "stubs/stubs.c",
];

// Translation units that are mostly verbatim upstream bytes: warnings off
// (`-w`), since the flagged lines cannot be edited. The shim header they
// include still compiles with warnings on via the glue build above.
const VERBATIM_TUS: &[&str] = &[
    "csrc/predicates_tu.c",
    "csrc/rawprepare_tu.c",
    "csrc/hotpixels_tu.c",
];

const UPSTREAM_SOURCES: &[&str] = &[
    "upstream/dng_gainmap_struct.inc",
    "upstream/hotpixels_bayer.inc",
    "upstream/hotpixels_commit.inc",
    "upstream/hotpixels_defaults.inc",
    "upstream/hotpixels_fcn.inc",
    "upstream/hotpixels_mono.inc",
    "upstream/hotpixels_pipe.inc",
    "upstream/hotpixels_process.inc",
    "upstream/hotpixels_types.inc",
    "upstream/hotpixels_xtrans.inc",
    "upstream/image_predicates.inc",
    "upstream/pipe_predicates.inc",
    "upstream/pipe_type_enum.inc",
    "upstream/piece_cfa.inc",
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
        .files(GLUE_SOURCES)
        .compile("lightamer_oracle_glue");
    cc::Build::new()
        .std("c11")
        .opt_level(2)
        .flag("-ffp-contract=off")
        .flag("-fno-fast-math")
        .flag("-w")
        .includes(["upstream", "stubs", "csrc"])
        .files(VERBATIM_TUS)
        .compile("lightamer_oracle_verbatim");
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .opt_level(2)
        .flag("-ffp-contract=off")
        .flag("-fno-fast-math")
        .flag("-w") // verbatim rawspeed bytes (shift_dcraw.inc), same policy
        .includes(["upstream", "stubs", "csrc"])
        .file("csrc/crop_tu.cpp")
        .compile("lightamer_oracle_cpp");
    for source in GLUE_SOURCES
        .iter()
        .chain(VERBATIM_TUS)
        .chain(UPSTREAM_SOURCES)
        .chain(["csrc/crop_tu.cpp", "csrc/oracle_abi.h", "stubs/dt_shim.h"].iter())
    {
        println!("cargo:rerun-if-changed={source}");
    }
}

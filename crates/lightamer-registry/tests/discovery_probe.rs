// SPDX-License-Identifier: GPL-3.0-or-later
//! Discovery probe target: `zz_probe` present or absent per environment.
//!
//! Driven by `Scripts/rust-discovery-probe.sh`, which creates or removes the
//! `zz_probe` module directory and expects this test to observe it. The probe
//! id is not a baseline module name, so this file stays clean under
//! `check-no-iop-names`.

#[test]
fn probe_expectation() {
    let Ok(expect) = std::env::var("LIGHTAMER_DISCOVERY_PROBE") else {
        lightamer_testkit::skip!(
            Input,
            "LIGHTAMER_DISCOVERY_PROBE unset (run Scripts/rust-discovery-probe.sh)"
        );
        return;
    };
    match expect.as_str() {
        "present" => assert!(
            lightamer_registry::find("zz_probe").is_some(),
            "zz_probe must be discovered once its directory exists"
        ),
        "absent" => assert!(
            lightamer_registry::find("zz_probe").is_none(),
            "zz_probe must vanish once its directory is removed"
        ),
        other => assert!(
            ["present", "absent"].contains(&other),
            "bad LIGHTAMER_DISCOVERY_PROBE={other}"
        ),
    }
}

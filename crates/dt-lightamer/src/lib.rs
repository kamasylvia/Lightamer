// SPDX-License-Identifier: GPL-3.0-or-later
//! Exclusive features: pano/focus/HDR merge, node DRT, versions, AI (phase C fills it).

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}

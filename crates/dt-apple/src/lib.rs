// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS-only: CIRAW/ColorSync/Vision/ImageIO/Metal (A6 adds gating + legs).

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}

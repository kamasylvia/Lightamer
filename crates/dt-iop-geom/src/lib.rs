// SPDX-License-Identifier: GPL-3.0-or-later
//! Geometry modules: lens/cacorrect/ashift/flip/crop/… (B7 fills it).

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}

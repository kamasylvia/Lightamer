// SPDX-License-Identifier: GPL-3.0-or-later
//! Command/Query/Event + `CoreHandle`: the UI's only entry point (A7a fills it).

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
